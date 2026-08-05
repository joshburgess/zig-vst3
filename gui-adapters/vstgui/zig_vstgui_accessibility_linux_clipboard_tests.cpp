#include "zig_vstgui_accessibility_clipboard.h"

#if defined(__linux__)

#include <xcb/xcb.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <string>
#include <thread>
#include <vector>

namespace {

bool require(bool condition, const char* message) {
    if (condition) return true;
    std::fprintf(stderr, "Linux clipboard test failed: %s\n", message);
    return false;
}

class Dispatcher {
public:
    explicit Dispatcher(
        const std::shared_ptr<ZigVstgui::AccessibilityClipboard>& value
    ) : clipboard(value), worker([this] {
        while (running.load(std::memory_order_acquire)) {
            clipboard->dispatch();
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        clipboard->dispatch();
    }) {}

    ~Dispatcher() {
        running.store(false, std::memory_order_release);
        worker.join();
    }

private:
    std::shared_ptr<ZigVstgui::AccessibilityClipboard> clipboard;
    std::atomic<bool> running {true};
    std::thread worker;
};

class SelectionRequester {
public:
    struct Reply {
        xcb_atom_t type {XCB_ATOM_NONE};
        uint8_t format {0};
        std::vector<uint8_t> bytes;
        bool refused {false};
    };

    SelectionRequester() {
        int screen_index = 0;
        connection = xcb_connect(nullptr, &screen_index);
        if (!connection || xcb_connection_has_error(connection)) return;
        auto screen = xcb_setup_roots_iterator(xcb_get_setup(connection));
        for (int index = 0; index < screen_index && screen.rem; ++index)
            xcb_screen_next(&screen);
        if (!screen.rem) return;
        window = xcb_generate_id(connection);
        const auto cookie = xcb_create_window_checked(
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
            0,
            nullptr
        );
        auto* error = xcb_request_check(connection, cookie);
        if (error) {
            std::free(error);
            window = XCB_WINDOW_NONE;
            return;
        }
        clipboard = intern("CLIPBOARD");
        property = intern("ZIG_VSTGUI_CLIPBOARD_TEST");
    }

    ~SelectionRequester() {
        if (!connection) return;
        if (window != XCB_WINDOW_NONE)
            xcb_destroy_window(connection, window);
        xcb_disconnect(connection);
    }

    bool valid() const {
        return connection && window != XCB_WINDOW_NONE &&
            clipboard != XCB_ATOM_NONE && property != XCB_ATOM_NONE;
    }

    xcb_atom_t intern(const char* name) const {
        if (!connection) return XCB_ATOM_NONE;
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

    bool request(xcb_atom_t target, Reply& result) const {
        if (!valid() || target == XCB_ATOM_NONE) return false;
        xcb_delete_property(connection, window, property);
        xcb_convert_selection(
            connection,
            window,
            clipboard,
            target,
            property,
            XCB_CURRENT_TIME
        );
        xcb_flush(connection);

        const auto deadline = std::chrono::steady_clock::now() +
            std::chrono::milliseconds(500);
        for (;;) {
            while (auto* event = xcb_poll_for_event(connection)) {
                const auto response = event->response_type & ~0x80;
                if (response == XCB_SELECTION_NOTIFY) {
                    const auto* notification =
                        reinterpret_cast<xcb_selection_notify_event_t*>(event);
                    const bool matching = notification->requestor == window &&
                        notification->selection == clipboard &&
                        notification->target == target;
                    const auto response_property = notification->property;
                    std::free(event);
                    if (!matching) continue;
                    if (response_property == XCB_ATOM_NONE) {
                        result = {};
                        result.refused = true;
                        return true;
                    }
                    return readProperty(result);
                }
                std::free(event);
            }
            if (xcb_connection_has_error(connection) ||
                std::chrono::steady_clock::now() >= deadline)
                return false;
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }

private:
    bool readProperty(Reply& result) const {
        const auto cookie = xcb_get_property(
            connection,
            true,
            window,
            property,
            XCB_GET_PROPERTY_TYPE_ANY,
            0,
            1024 * 1024 / 4 + 1
        );
        auto* reply = xcb_get_property_reply(connection, cookie, nullptr);
        if (!reply) return false;
        const auto length = xcb_get_property_value_length(reply);
        const auto* bytes = static_cast<const uint8_t*>(
            xcb_get_property_value(reply)
        );
        Reply value;
        value.type = reply->type;
        value.format = reply->format;
        value.bytes.assign(bytes, bytes + length);
        const bool complete = reply->bytes_after == 0;
        std::free(reply);
        if (!complete) return false;
        result = std::move(value);
        return true;
    }

    xcb_connection_t* connection {nullptr};
    xcb_window_t window {XCB_WINDOW_NONE};
    xcb_atom_t clipboard {XCB_ATOM_NONE};
    xcb_atom_t property {XCB_ATOM_NONE};
};

bool containsAtom(
    const SelectionRequester::Reply& reply,
    xcb_atom_t expected
) {
    if (reply.type != XCB_ATOM_ATOM || reply.format != 32 ||
        reply.bytes.size() % sizeof(uint32_t) != 0)
        return false;
    for (std::size_t offset = 0; offset < reply.bytes.size();
         offset += sizeof(uint32_t)) {
        uint32_t atom = 0;
        std::memcpy(&atom, reply.bytes.data() + offset, sizeof(atom));
        if (atom == expected) return true;
    }
    return false;
}

}

int main() {
    if (!std::getenv("DISPLAY")) {
        std::puts("Linux clipboard test skipped: DISPLAY is unavailable");
        return 0;
    }
    if (unsetenv("WAYLAND_DISPLAY") != 0) {
        std::fputs("Linux clipboard test could not clear WAYLAND_DISPLAY\n", stderr);
        return 1;
    }

    auto first = ZigVstgui::createLinuxAccessibilityClipboard();
    auto second = ZigVstgui::createLinuxAccessibilityClipboard();
    if (!require(first && second, "providers were not constructed")) return 1;
    SelectionRequester requester;
    if (!require(requester.valid(), "external requester was not constructed"))
        return 1;

    const std::string initial = u8"accessibility Δ clipboard";
    if (!require(first->writeText(initial), "first provider did not own the selection"))
        return 1;
    {
        Dispatcher dispatch(first);
        std::string received;
        if (!require(
                second->readText(received, 1024) && received == initial,
                "UTF-8 selection exchange failed"
            ))
            return 1;

        received = "preserved";
        if (!require(
                !second->readText(received, 4) && received == "preserved",
                "bounded read changed its destination"
            ))
            return 1;

        SelectionRequester::Reply targets;
        if (!require(
                requester.request(requester.intern("TARGETS"), targets) &&
                    !containsAtom(targets, XCB_ATOM_STRING),
                "unavailable Latin-1 conversion was advertised"
            ))
            return 1;
    }

    const std::string latin1_compatible = u8"café";
    if (!require(
            first->writeText(latin1_compatible),
            "Latin-1-compatible UTF-8 selection was rejected"
        ))
        return 1;
    {
        Dispatcher dispatch(first);
        SelectionRequester::Reply targets;
        if (!require(
                requester.request(requester.intern("TARGETS"), targets) &&
                    containsAtom(targets, XCB_ATOM_STRING),
                "available Latin-1 conversion was not advertised"
            ))
            return 1;
        SelectionRequester::Reply latin1;
        const std::string expected("caf\xe9", 4);
        if (!require(
                requester.request(XCB_ATOM_STRING, latin1) &&
                    !latin1.refused && latin1.type == XCB_ATOM_STRING &&
                    latin1.format == 8 &&
                    std::string(latin1.bytes.begin(), latin1.bytes.end()) == expected,
                "Latin-1 selection conversion failed"
            ))
            return 1;
    }

    const std::string maximum_payload(1024 * 1024, 'x');
    if (!require(
            first->writeText(maximum_payload),
            "maximum-size selection was rejected"
        ))
        return 1;
    {
        Dispatcher dispatch(first);
        std::string received;
        if (!require(
                second->readText(received, maximum_payload.size()) &&
                    received == maximum_payload,
                "maximum-size selection exchange failed"
            ))
            return 1;
    }

    const std::string replacement = "second owner";
    if (!require(second->writeText(replacement), "selection takeover failed"))
        return 1;
    {
        Dispatcher dispatch(second);
        std::string received;
        if (!require(
                first->readText(received, 1024) && received == replacement,
                "selection takeover was not externally readable"
            ))
            return 1;
    }

    const std::string embedded_nul("invalid\0text", 12);
    if (!require(
            !first->writeText(embedded_nul),
            "embedded NUL text was accepted"
        ))
        return 1;
    const std::string invalid_utf8("\xC3\x28", 2);
    if (!require(
            !first->writeText(invalid_utf8),
            "invalid UTF-8 text was accepted"
        ))
        return 1;
    if (!require(
            !first->writeText(std::string(1024 * 1024 + 1, 'x')),
            "oversized text was accepted"
        ))
        return 1;

    std::puts("Linux X11 accessibility clipboard exchange passed");
    return 0;
}

#endif
