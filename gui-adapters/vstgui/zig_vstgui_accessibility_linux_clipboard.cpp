#include "zig_vstgui_accessibility_clipboard.h"
#include "zig_vstgui_accessibility_wayland_clipboard.h"

#if defined(__linux__) || defined(ZIG_VSTGUI_WAYLAND_CLIPBOARD_TEST_PLATFORM)

#include <glib.h>
#include <poll.h>
#include <xcb/xcb.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iterator>
#include <memory>
#include <string>
#include <utility>

namespace ZigVstgui {

namespace {

constexpr std::size_t maximum_text_bytes = 1024 * 1024;
constexpr int selection_timeout_ms = 250;

xcb_atom_t internAtom(xcb_connection_t* connection, const char* name) {
    const auto cookie = xcb_intern_atom(
        connection,
        false,
        static_cast<uint16_t>(std::strlen(name)),
        name
    );
    auto* reply = xcb_intern_atom_reply(connection, cookie, nullptr);
    if (!reply) return XCB_ATOM_NONE;
    const auto atom = reply->atom;
    std::free(reply);
    return atom;
}

bool validText(const std::string& text) {
    return text.size() <= maximum_text_bytes &&
        text.find('\0') == std::string::npos &&
        g_utf8_validate(text.data(), text.size(), nullptr);
}

bool convertUtf8ToLatin1(const std::string& text, std::string& converted) {
    if (!validText(text)) return false;
    std::string result;
    result.reserve(text.size());
    const auto* cursor = text.data();
    const auto* end = cursor + text.size();
    while (cursor != end) {
        const auto remaining = static_cast<gssize>(end - cursor);
        const auto code_point = g_utf8_get_char_validated(cursor, remaining);
        if (code_point == static_cast<gunichar>(-1) ||
            code_point == static_cast<gunichar>(-2) ||
            code_point > 0xff)
            return false;
        result.push_back(static_cast<char>(code_point));
        cursor = g_utf8_next_char(cursor);
    }
    converted = std::move(result);
    return true;
}

class UnavailableClipboard final : public AccessibilityClipboard {
public:
    bool writeText(const std::string&) override { return false; }
    bool readText(std::string&, std::size_t) override { return false; }
};

class WaylandClipboard final : public AccessibilityClipboard {
public:
    WaylandClipboard() : clipboard(zv3_wayland_clipboard_create()) {}

    ~WaylandClipboard() override {
        zv3_wayland_clipboard_destroy(clipboard);
    }

    bool valid() const { return clipboard != nullptr; }

    bool writeText(const std::string& text) override {
        if (!clipboard || !validText(text)) return false;
        return zv3_wayland_clipboard_write(
            clipboard,
            reinterpret_cast<const uint8_t*>(text.data()),
            text.size()
        ) == 0;
    }

    bool readText(std::string& text, std::size_t maximum_bytes) override {
        if (!clipboard || maximum_bytes > maximum_text_bytes) return false;
        uint8_t* bytes = nullptr;
        std::size_t length = 0;
        if (zv3_wayland_clipboard_read(
                clipboard,
                maximum_bytes,
                &bytes,
                &length
            ) != 0)
            return false;
        std::string received;
        if (length != 0) {
            received.assign(
                reinterpret_cast<const char*>(bytes),
                length
            );
        }
        zv3_wayland_clipboard_free(bytes);
        if (!validText(received) || received.size() > maximum_bytes)
            return false;
        text = std::move(received);
        return true;
    }

    void dispatch() override {
        zv3_wayland_clipboard_dispatch(clipboard);
    }

private:
    zv3_wayland_clipboard* clipboard {nullptr};
};

class X11Clipboard final : public AccessibilityClipboard {
public:
    X11Clipboard() {
        connection = xcb_connect(nullptr, &screen_index);
        if (!connection || xcb_connection_has_error(connection)) return;

        auto screen = xcb_setup_roots_iterator(xcb_get_setup(connection));
        for (int index = 0; index < screen_index && screen.rem; ++index)
            xcb_screen_next(&screen);
        if (!screen.rem) return;

        window = xcb_generate_id(connection);
        const uint32_t event_mask = XCB_EVENT_MASK_PROPERTY_CHANGE;
        const auto create_cookie = xcb_create_window_checked(
            connection,
            XCB_COPY_FROM_PARENT,
            window,
            screen.data->root,
            0,
            0,
            1,
            1,
            0,
            XCB_WINDOW_CLASS_INPUT_OUTPUT,
            screen.data->root_visual,
            XCB_CW_EVENT_MASK,
            &event_mask
        );
        auto* create_error = xcb_request_check(connection, create_cookie);
        if (create_error) {
            std::free(create_error);
            window = XCB_WINDOW_NONE;
            return;
        }

        clipboard_atom = internAtom(connection, "CLIPBOARD");
        utf8_atom = internAtom(connection, "UTF8_STRING");
        targets_atom = internAtom(connection, "TARGETS");
        text_atom = internAtom(connection, "TEXT");
        property_atom = internAtom(connection, "ZIG_VSTGUI_CLIPBOARD");
        incremental_atom = internAtom(connection, "INCR");
        ready = clipboard_atom != XCB_ATOM_NONE &&
            utf8_atom != XCB_ATOM_NONE &&
            targets_atom != XCB_ATOM_NONE &&
            text_atom != XCB_ATOM_NONE &&
            property_atom != XCB_ATOM_NONE &&
            incremental_atom != XCB_ATOM_NONE;
        xcb_flush(connection);
    }

    ~X11Clipboard() override {
        if (!connection) return;
        if (ready && ownsSelection()) {
            xcb_set_selection_owner(
                connection,
                XCB_WINDOW_NONE,
                clipboard_atom,
                XCB_CURRENT_TIME
            );
        }
        if (window != XCB_WINDOW_NONE)
            xcb_destroy_window(connection, window);
        xcb_flush(connection);
        xcb_disconnect(connection);
    }

    bool valid() const { return ready; }

    bool writeText(const std::string& text) override {
        if (!ready || !validText(text)) return false;
        xcb_set_selection_owner(
            connection,
            window,
            clipboard_atom,
            XCB_CURRENT_TIME
        );
        xcb_flush(connection);
        if (!ownsSelection()) return false;
        retained_text = text;
        return true;
    }

    bool readText(std::string& text, std::size_t maximum_bytes) override {
        if (!ready || maximum_bytes > maximum_text_bytes) return false;
        const auto owner = selectionOwner();
        if (owner == XCB_WINDOW_NONE) return false;
        if (owner == window) {
            if (retained_text.size() > maximum_bytes) return false;
            text = retained_text;
            return true;
        }

        std::string received;
        if (!requestText(utf8_atom, received, maximum_bytes) &&
            !requestLatin1(received, maximum_bytes))
            return false;
        if (!validText(received) || received.size() > maximum_bytes)
            return false;
        text = std::move(received);
        return true;
    }

    void dispatch() override {
        if (!ready) return;
        while (auto* event = xcb_poll_for_event(connection)) {
            handleEvent(event, nullptr);
            std::free(event);
        }
    }

private:
    xcb_window_t selectionOwner() const {
        const auto cookie = xcb_get_selection_owner(connection, clipboard_atom);
        auto* reply = xcb_get_selection_owner_reply(connection, cookie, nullptr);
        if (!reply) return XCB_WINDOW_NONE;
        const auto owner = reply->owner;
        std::free(reply);
        return owner;
    }

    bool ownsSelection() const { return selectionOwner() == window; }

    bool publishProperty(
        xcb_window_t requestor,
        xcb_atom_t property,
        xcb_atom_t type,
        uint8_t format,
        uint32_t count,
        const void* data
    ) {
        const auto cookie = xcb_change_property_checked(
            connection,
            XCB_PROP_MODE_REPLACE,
            requestor,
            property,
            type,
            format,
            count,
            data
        );
        auto* error = xcb_request_check(connection, cookie);
        if (!error) return true;
        std::free(error);
        return false;
    }

    void selectionRequest(const xcb_selection_request_event_t& request) {
        auto property = request.property;
        if (property == XCB_ATOM_NONE) property = request.target;
        bool published = false;
        if (request.selection == clipboard_atom && ownsSelection()) {
            if (request.target == targets_atom) {
                const xcb_atom_t targets[] = {
                    targets_atom,
                    utf8_atom,
                    text_atom,
                    XCB_ATOM_STRING,
                };
                std::string latin1;
                const auto target_count = convertUtf8ToLatin1(
                    retained_text,
                    latin1
                ) ? std::size(targets) : std::size(targets) - 1;
                published = publishProperty(
                    request.requestor,
                    property,
                    XCB_ATOM_ATOM,
                    32,
                    static_cast<uint32_t>(target_count),
                    targets
                );
            } else if (request.target == utf8_atom ||
                       request.target == text_atom) {
                published = publishProperty(
                    request.requestor,
                    property,
                    utf8_atom,
                    8,
                    static_cast<uint32_t>(retained_text.size()),
                    retained_text.data()
                );
            } else if (request.target == XCB_ATOM_STRING) {
                std::string latin1;
                if (convertUtf8ToLatin1(retained_text, latin1)) {
                    published = publishProperty(
                        request.requestor,
                        property,
                        XCB_ATOM_STRING,
                        8,
                        static_cast<uint32_t>(latin1.size()),
                        latin1.data()
                    );
                }
            }
        }

        xcb_selection_notify_event_t notification {};
        notification.response_type = XCB_SELECTION_NOTIFY;
        notification.time = request.time;
        notification.requestor = request.requestor;
        notification.selection = request.selection;
        notification.target = request.target;
        notification.property = published ? property :
            static_cast<xcb_atom_t>(XCB_ATOM_NONE);
        xcb_send_event(
            connection,
            false,
            request.requestor,
            XCB_EVENT_MASK_NO_EVENT,
            reinterpret_cast<const char*>(&notification)
        );
        xcb_flush(connection);
    }

    void handleEvent(
        xcb_generic_event_t* event,
        xcb_selection_notify_event_t** notification
    ) {
        switch (event->response_type & ~0x80) {
            case XCB_SELECTION_REQUEST:
                selectionRequest(
                    *reinterpret_cast<xcb_selection_request_event_t*>(event)
                );
                break;
            case XCB_SELECTION_CLEAR:
                if (!ownsSelection()) retained_text.clear();
                break;
            case XCB_SELECTION_NOTIFY:
                if (notification)
                    *notification = reinterpret_cast<xcb_selection_notify_event_t*>(event);
                break;
            default:
                break;
        }
    }

    xcb_selection_notify_event_t* waitForSelection(xcb_atom_t target) {
        const auto deadline = std::chrono::steady_clock::now() +
            std::chrono::milliseconds(selection_timeout_ms);
        for (;;) {
            while (auto* event = xcb_poll_for_event(connection)) {
                xcb_selection_notify_event_t* notification = nullptr;
                handleEvent(event, &notification);
                if (notification &&
                    notification->requestor == window &&
                    notification->selection == clipboard_atom &&
                    notification->target == target)
                    return notification;
                std::free(event);
            }
            if (xcb_connection_has_error(connection)) return nullptr;

            const auto now = std::chrono::steady_clock::now();
            if (now >= deadline) return nullptr;
            const auto remaining = std::chrono::duration_cast<
                std::chrono::milliseconds
            >(deadline - now);
            pollfd descriptor {
                xcb_get_file_descriptor(connection),
                POLLIN,
                0,
            };
            const auto result = poll(
                &descriptor,
                1,
                std::max(1, static_cast<int>(remaining.count()))
            );
            if (result < 0 && errno == EINTR) continue;
            if (result <= 0) return nullptr;
        }
    }

    bool requestProperty(
        xcb_atom_t target,
        std::string& bytes,
        xcb_atom_t& type,
        std::size_t maximum_bytes
    ) {
        xcb_delete_property(connection, window, property_atom);
        xcb_convert_selection(
            connection,
            window,
            clipboard_atom,
            target,
            property_atom,
            XCB_CURRENT_TIME
        );
        xcb_flush(connection);

        auto* notification = waitForSelection(target);
        if (!notification) return false;
        const bool published = notification->requestor == window &&
            notification->selection == clipboard_atom &&
            notification->target == target &&
            notification->property == property_atom;
        std::free(notification);
        if (!published) return false;

        const auto cookie = xcb_get_property(
            connection,
            true,
            window,
            property_atom,
            XCB_GET_PROPERTY_TYPE_ANY,
            0,
            static_cast<uint32_t>(maximum_bytes / 4 + 1)
        );
        auto* reply = xcb_get_property_reply(connection, cookie, nullptr);
        if (!reply) return false;
        type = reply->type;
        const auto length = static_cast<std::size_t>(
            xcb_get_property_value_length(reply)
        );
        const bool valid = reply->format == 8 &&
            reply->bytes_after == 0 &&
            type != incremental_atom &&
            length <= maximum_bytes;
        if (valid) {
            const auto* value = static_cast<const char*>(
                xcb_get_property_value(reply)
            );
            bytes.assign(value, length);
        }
        std::free(reply);
        return valid;
    }

    bool requestText(
        xcb_atom_t target,
        std::string& text,
        std::size_t maximum_bytes
    ) {
        xcb_atom_t type = XCB_ATOM_NONE;
        std::string bytes;
        if (!requestProperty(target, bytes, type, maximum_bytes) ||
            type != utf8_atom ||
            !g_utf8_validate(bytes.data(), bytes.size(), nullptr))
            return false;
        text = std::move(bytes);
        return true;
    }

    bool requestLatin1(std::string& text, std::size_t maximum_bytes) {
        xcb_atom_t type = XCB_ATOM_NONE;
        std::string bytes;
        if (!requestProperty(
                XCB_ATOM_STRING,
                bytes,
                type,
                maximum_bytes
            ) || type != XCB_ATOM_STRING)
            return false;

        std::string converted;
        converted.reserve(bytes.size());
        for (const auto byte : bytes) {
            const auto value = static_cast<unsigned char>(byte);
            if (value < 0x80) {
                converted.push_back(static_cast<char>(value));
            } else {
                if (converted.size() + 2 > maximum_bytes) return false;
                converted.push_back(static_cast<char>(0xC0 | (value >> 6)));
                converted.push_back(static_cast<char>(0x80 | (value & 0x3F)));
            }
        }
        text = std::move(converted);
        return true;
    }

    xcb_connection_t* connection {nullptr};
    int screen_index {0};
    xcb_window_t window {XCB_WINDOW_NONE};
    xcb_atom_t clipboard_atom {XCB_ATOM_NONE};
    xcb_atom_t utf8_atom {XCB_ATOM_NONE};
    xcb_atom_t targets_atom {XCB_ATOM_NONE};
    xcb_atom_t text_atom {XCB_ATOM_NONE};
    xcb_atom_t property_atom {XCB_ATOM_NONE};
    xcb_atom_t incremental_atom {XCB_ATOM_NONE};
    std::string retained_text;
    bool ready {false};
};

}

std::shared_ptr<AccessibilityClipboard> createLinuxAccessibilityClipboard() {
    auto wayland = std::make_shared<WaylandClipboard>();
    if (wayland->valid()) return wayland;
    auto x11 = std::make_shared<X11Clipboard>();
    if (x11->valid()) return x11;
    return std::make_shared<UnavailableClipboard>();
}

}

#endif
