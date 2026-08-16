#include "zig_vstgui_accessibility_bridge.h"

#include "vstgui/lib/controls/ctextlabel.h"
#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cview.h"
#include "vstgui/lib/vstguibase.h"
#include "vstgui/lib/vstguiinit.h"

#include <gio/gio.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr const char* bus_name = "org.a11y.Bus";
constexpr const char* bus_path = "/org/a11y/bus";
constexpr const char* registry_name = "org.a11y.atspi.Registry";
constexpr const char* registry_path = "/org/a11y/atspi/registry";
constexpr const char* accessible_interface = "org.a11y.atspi.Accessible";
constexpr const char* application_interface = "org.a11y.atspi.Application";
constexpr const char* cache_interface = "org.a11y.atspi.Cache";
constexpr const char* cache_path = "/org/a11y/atspi/cache";
constexpr const char* object_event_interface = "org.a11y.atspi.Event.Object";
constexpr const char* first_child_path = "/org/a11y/atspi/accessible/control_0";
constexpr const char* second_child_path = "/org/a11y/atspi/accessible/control_1";
constexpr const char* third_child_path = "/org/a11y/atspi/accessible/control_2";
constexpr const char* fourth_child_path = "/org/a11y/atspi/accessible/control_3";
constexpr const char* fifth_child_path = "/org/a11y/atspi/accessible/control_4";
constexpr const char* sixth_child_path = "/org/a11y/atspi/accessible/control_5";
constexpr const char* seventh_child_path = "/org/a11y/atspi/accessible/control_6";
constexpr int timeout_ms = 2000;

class VstguiRuntime final {
public:
    VstguiRuntime() {
        VSTGUI::init(nullptr);
    }

    ~VstguiRuntime() {
        VSTGUI::exit();
    }
};

constexpr const char* service_xml = R"xml(
<node>
  <interface name='org.a11y.Bus'>
    <method name='GetAddress'>
      <arg direction='out' type='s'/>
    </method>
  </interface>
  <interface name='org.a11y.atspi.Socket'>
    <method name='Embed'>
      <arg direction='in' name='plug' type='(so)'/>
      <arg direction='out' name='socket' type='(so)'/>
    </method>
  </interface>
</node>
)xml";

struct Evidence {
    std::atomic<bool> embedded {false};
    std::atomic<bool> id_set {false};
    std::atomic<bool> root_role {false};
    std::atomic<bool> child_found {false};
    std::atomic<bool> child_name {false};
    std::atomic<bool> child_role {false};
    std::atomic<bool> child_interfaces {false};
    std::atomic<bool> component_bounds {false};
    std::atomic<bool> action_count {false};
    std::atomic<bool> action_performed {false};
    std::atomic<bool> value_read {false};
    std::atomic<bool> value_set {false};
    std::atomic<bool> text_interface {false};
    std::atomic<bool> text_queries {false};
    std::atomic<bool> text_boundaries {false};
    std::atomic<bool> rotated_text_geometry {false};
    std::atomic<bool> tail_truncated_text_geometry {false};
    std::atomic<bool> head_truncated_text_geometry {false};
    std::atomic<bool> truncated_state_event {false};
    std::atomic<bool> hostile_text_geometry {false};
    std::atomic<bool> hostile_component_geometry {false};
    std::atomic<bool> text_selection_queries {false};
    std::atomic<bool> caret_set {false};
    std::atomic<bool> selection_added {false};
    std::atomic<bool> selection_changed {false};
    std::atomic<bool> selection_removed {false};
    std::atomic<bool> reject_text_selection {false};
    std::atomic<bool> editable_interface {false};
    std::atomic<bool> text_set {false};
    std::atomic<bool> text_inserted {false};
    std::atomic<bool> text_deleted {false};
    std::atomic<bool> text_pasted {false};
    std::atomic<unsigned int> text_ab_updates {0};
    std::atomic<unsigned int> clipboard_writes {0};
    std::atomic<unsigned int> clipboard_reads {0};
    std::atomic<bool> clipboard_methods_succeeded {false};
    std::atomic<bool> reject_clipboard_writes {false};
    std::atomic<bool> reject_clipboard_reads {false};
    std::atomic<unsigned int> clipboard_read_mode {0};
    std::atomic<bool> cache_items {false};
    std::atomic<bool> cache_root_added {false};
    std::atomic<bool> cache_child_added {false};
    std::atomic<bool> cache_root_removed {false};
    std::atomic<bool> cache_child_removed {false};
    std::atomic<unsigned int> cache_add_count {0};
    std::atomic<unsigned int> cache_remove_count {0};
    std::atomic<bool> hostile_inputs_rejected {false};
    std::atomic<unsigned int> action_call_count {0};
    std::atomic<bool> property_event {false};
    std::atomic<bool> focus_event {false};
    std::atomic<bool> bounds_event {false};
    std::atomic<bool> text_insert_event {false};
    std::atomic<bool> text_delete_event {false};
    std::atomic<bool> text_replacement_delete_event {false};
    std::atomic<bool> text_replacement_insert_event {false};
    std::atomic<unsigned int> text_event_count {0};
    std::atomic<bool> caret_event {false};
    std::atomic<bool> selection_event {false};
    std::atomic<unsigned int> caret_event_count {0};
    std::atomic<unsigned int> selection_event_count {0};
    std::atomic<unsigned int> event_count {0};
    std::atomic<bool> inspection_complete {false};
    ZigVstgui::AccessibilityNode* node {nullptr};
};

class TestClipboard final : public ZigVstgui::AccessibilityClipboard {
public:
    explicit TestClipboard(Evidence& value_evidence) : evidence(value_evidence) {}

    bool writeText(const std::string& value) override {
        if (evidence.reject_clipboard_writes.load(std::memory_order_acquire))
            return false;
        std::lock_guard<std::mutex> lock(mutex);
        text = value;
        evidence.clipboard_writes.fetch_add(1, std::memory_order_acq_rel);
        return true;
    }

    bool readText(std::string& value, std::size_t maximum_bytes) override {
        if (evidence.reject_clipboard_reads.load(std::memory_order_acquire))
            return false;
        std::lock_guard<std::mutex> lock(mutex);
        switch (evidence.clipboard_read_mode.load(std::memory_order_acquire)) {
            case 1: value.assign(maximum_bytes + 1, 'x'); break;
            case 2: value.assign("x\0y", 3); break;
            case 3: value.assign("\xc3", 1); break;
            default:
                if (text.size() > maximum_bytes) return false;
                value = text;
                break;
        }
        evidence.clipboard_reads.fetch_add(1, std::memory_order_acq_rel);
        return true;
    }

private:
    Evidence& evidence;
    std::mutex mutex;
    std::string text;
};

void cacheEventReceived(
    GDBusConnection*,
    const gchar*,
    const gchar*,
    const gchar*,
    const gchar* signal_name,
    GVariant* parameters,
    gpointer userdata
) {
    auto* evidence = static_cast<Evidence*>(userdata);
    if (!evidence || !signal_name || !parameters) return;
    const char* application = nullptr;
    const char* path = nullptr;
    if (std::strcmp(signal_name, "AddAccessible") == 0) {
        GVariant* item = g_variant_get_child_value(parameters, 0);
        GVariant* reference = g_variant_get_child_value(item, 0);
        g_variant_get(reference, "(&s&o)", &application, &path);
        if (path && std::strcmp(path, "/org/a11y/atspi/accessible/root") == 0)
            evidence->cache_root_added.store(true, std::memory_order_release);
        if (path && std::strcmp(path, first_child_path) == 0)
            evidence->cache_child_added.store(true, std::memory_order_release);
        evidence->cache_add_count.fetch_add(1, std::memory_order_acq_rel);
        g_variant_unref(reference);
        g_variant_unref(item);
        return;
    }
    if (std::strcmp(signal_name, "RemoveAccessible") == 0) {
        g_variant_get(parameters, "((&s&o))", &application, &path);
        if (path && std::strcmp(path, "/org/a11y/atspi/accessible/root") == 0)
            evidence->cache_root_removed.store(true, std::memory_order_release);
        if (path && std::strcmp(path, first_child_path) == 0)
            evidence->cache_child_removed.store(true, std::memory_order_release);
        evidence->cache_remove_count.fetch_add(1, std::memory_order_acq_rel);
    }
}

bool callSucceeded(GVariant* result, GError* error) {
    if (result) {
        g_variant_unref(result);
        return true;
    }
    if (error) g_error_free(error);
    return false;
}

bool booleanResult(GVariant* result, GError* error, bool expected) {
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gboolean value = false;
    g_variant_get(result, "(b)", &value);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return static_cast<bool>(value) == expected;
}

bool callRejected(GVariant* result, GError* error) {
    if (result) {
        g_variant_unref(result);
        if (error) g_error_free(error);
        return false;
    }
    if (!error) return false;
    g_error_free(error);
    return true;
}

bool intPropertyMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    const char* interface,
    const char* property,
    gint32 expected
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.freedesktop.DBus.Properties",
        "Get",
        g_variant_new("(ss)", interface, property),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    GVariant* value = nullptr;
    g_variant_get(result, "(v)", &value);
    const bool matches = g_variant_is_of_type(value, G_VARIANT_TYPE_INT32) &&
        g_variant_get_int32(value) == expected;
    g_variant_unref(value);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return matches;
}

bool textBooleanMethod(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    const char* method,
    GVariant* parameters,
    bool expected
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        method,
        parameters,
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    return booleanResult(result, error, expected);
}

bool textSelectionMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    gint32 expected_start,
    gint32 expected_end
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetSelection",
        g_variant_new("(i)", 0),
        G_VARIANT_TYPE("(ii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gint32 start = -1;
    gint32 end = -1;
    g_variant_get(result, "(ii)", &start, &end);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return start == expected_start && end == expected_end;
}

bool textSelectionCountMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    gint32 expected
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetNSelections",
        nullptr,
        G_VARIANT_TYPE("(i)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gint32 count = -1;
    g_variant_get(result, "(i)", &count);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return count == expected;
}

bool textRangeMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    const char* method,
    gint32 offset,
    guint32 boundary,
    const char* expected_text,
    gint32 expected_start,
    gint32 expected_end
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        method,
        g_variant_new("(iu)", offset, boundary),
        G_VARIANT_TYPE("(sii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    const char* text = nullptr;
    gint32 start = -1;
    gint32 end = -1;
    g_variant_get(result, "(&sii)", &text, &start, &end);
    const bool matches = text && expected_text &&
        std::strcmp(text, expected_text) == 0 &&
        start == expected_start && end == expected_end;
    g_variant_unref(result);
    if (error) g_error_free(error);
    return matches;
}

bool boundedRangeMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    gint32 x,
    gint32 y,
    gint32 width,
    gint32 height,
    guint32 x_clip,
    guint32 y_clip,
    gint32 expected_start,
    gint32 expected_end,
    const char* expected_text
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetBoundedRanges",
        g_variant_new(
            "(iiiiuuu)",
            x,
            y,
            width,
            height,
            1u,
            x_clip,
            y_clip
        ),
        G_VARIANT_TYPE("(a(iisv))"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    GVariant* ranges = nullptr;
    g_variant_get(result, "(@a(iisv))", &ranges);
    const auto count = g_variant_n_children(ranges);
    bool matches = expected_start < 0 ? count == 0 : count == 1;
    if (matches && expected_start >= 0) {
        gint32 start = -1;
        gint32 end = -1;
        const char* text = nullptr;
        GVariant* unused = nullptr;
        g_variant_get_child(
            ranges,
            0,
            "(ii&s@v)",
            &start,
            &end,
            &text,
            &unused
        );
        matches = start == expected_start && end == expected_end && text &&
            expected_text && std::strcmp(text, expected_text) == 0;
        g_variant_unref(unused);
    }
    g_variant_unref(ranges);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return matches;
}

bool rotatedTextGeometryMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetCharacterExtents",
        g_variant_new("(iu)", 0, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gint32 x = 0;
    gint32 y = 0;
    gint32 width = 0;
    gint32 height = 0;
    g_variant_get(result, "(iiii)", &x, &y, &width, &height);
    g_variant_unref(result);
    if (error) g_error_free(error);
    bool matches = x >= 240 && x < 340 && y >= 20 && y < 120 &&
        width > 0 && width < 100 && height > 0 && height < 100;

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetOffsetAtPoint",
        g_variant_new("(iiu)", x + width / 2, y + height / 2, 1u),
        G_VARIANT_TYPE("(i)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 offset = -1;
        g_variant_get(result, "(i)", &offset);
        matches &= offset == 0;
        g_variant_unref(result);
    } else {
        matches = false;
    }
    if (error) g_error_free(error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetRangeExtents",
        g_variant_new("(iiu)", 0, 2, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 range_x = 0;
        gint32 range_y = 0;
        gint32 range_width = 0;
        gint32 range_height = 0;
        g_variant_get(
            result,
            "(iiii)",
            &range_x,
            &range_y,
            &range_width,
            &range_height
        );
        matches &= range_x <= x && range_y <= y &&
            range_x + range_width >= x + width &&
            range_y + range_height >= y + height;
        g_variant_unref(result);
    } else {
        matches = false;
    }
    if (error) g_error_free(error);

    return matches && boundedRangeMatches(
        connection,
        application,
        path,
        x,
        y,
        width,
        height,
        0u,
        0u,
        0,
        1,
        "A"
    );
}

struct TextExtent {
    gint32 x {-1};
    gint32 y {-1};
    gint32 width {-1};
    gint32 height {-1};

    bool available() const {
        return x >= 0 && y >= 0 && width >= 0 && height >= 0;
    }
};

bool characterExtent(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    gint32 offset,
    TextExtent& extent
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetCharacterExtents",
        g_variant_new("(iu)", offset, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    g_variant_get(
        result,
        "(iiii)",
        &extent.x,
        &extent.y,
        &extent.width,
        &extent.height
    );
    g_variant_unref(result);
    if (error) g_error_free(error);
    return true;
}

bool hasState(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    guint32 state
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        accessible_interface,
        "GetState",
        nullptr,
        G_VARIANT_TYPE("(au)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    GVariant* states = nullptr;
    g_variant_get(result, "(@au)", &states);
    const guint32 word = state / 32;
    guint32 value = 0;
    if (word < g_variant_n_children(states)) {
        GVariant* state_value = g_variant_get_child_value(states, word);
        value = g_variant_get_uint32(state_value);
        g_variant_unref(state_value);
    }
    const bool present = (value & (guint32 {1} << (state % 32))) != 0;
    g_variant_unref(states);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return present;
}

bool truncatedTextGeometryMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path,
    const char* text,
    bool truncate_head
) {
    const auto count = static_cast<gint32>(std::strlen(text));
    if (count < 3 || !hasState(connection, application, path, 34u)) return false;

    std::vector<TextExtent> extents(static_cast<std::size_t>(count));
    gint32 first_visible = -1;
    gint32 last_visible = -1;
    for (gint32 offset = 0; offset < count; ++offset) {
        auto& extent = extents[static_cast<std::size_t>(offset)];
        if (!characterExtent(connection, application, path, offset, extent))
            return false;
        if (!extent.available()) continue;
        if (first_visible < 0) first_visible = offset;
        last_visible = offset;
        GError* error = nullptr;
        GVariant* result = g_dbus_connection_call_sync(
            connection,
            application,
            path,
            "org.a11y.atspi.Text",
            "GetOffsetAtPoint",
            g_variant_new(
                "(iiu)",
                extent.x + extent.width / 2,
                extent.y + extent.height / 2,
                1u
            ),
            G_VARIANT_TYPE("(i)"),
            G_DBUS_CALL_FLAGS_NONE,
            timeout_ms,
            nullptr,
            &error
        );
        if (!result) {
            if (error) g_error_free(error);
            return false;
        }
        gint32 resolved = -1;
        g_variant_get(result, "(i)", &resolved);
        g_variant_unref(result);
        if (error) g_error_free(error);
        if (resolved != offset) return false;
    }
    if (first_visible < 0 || last_visible < first_visible ||
        last_visible - first_visible + 1 >= count) return false;
    if (truncate_head ? last_visible != count - 1 : first_visible != 0)
        return false;
    for (gint32 offset = first_visible; offset <= last_visible; ++offset) {
        if (!extents[static_cast<std::size_t>(offset)].available()) return false;
    }
    for (gint32 offset = 0; offset < first_visible; ++offset) {
        if (extents[static_cast<std::size_t>(offset)].available()) return false;
    }
    for (gint32 offset = last_visible + 1; offset < count; ++offset) {
        if (extents[static_cast<std::size_t>(offset)].available()) return false;
    }

    const gint32 hidden_start = truncate_head ? 0 : last_visible + 1;
    const gint32 hidden_end = truncate_head ? first_visible : count;
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetRangeExtents",
        g_variant_new("(iiu)", hidden_start, hidden_end, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    TextExtent hidden;
    g_variant_get(
        result,
        "(iiii)",
        &hidden.x,
        &hidden.y,
        &hidden.width,
        &hidden.height
    );
    g_variant_unref(result);
    if (error) g_error_free(error);
    if (hidden.x != -1 || hidden.y != -1 || hidden.width != -1 ||
        hidden.height != -1) return false;

    TextExtent visible_bounds = extents[static_cast<std::size_t>(first_visible)];
    for (gint32 offset = first_visible + 1; offset <= last_visible; ++offset) {
        const auto& extent = extents[static_cast<std::size_t>(offset)];
        const gint32 right = std::max(
            visible_bounds.x + visible_bounds.width,
            extent.x + extent.width
        );
        const gint32 bottom = std::max(
            visible_bounds.y + visible_bounds.height,
            extent.y + extent.height
        );
        visible_bounds.x = std::min(visible_bounds.x, extent.x);
        visible_bounds.y = std::min(visible_bounds.y, extent.y);
        visible_bounds.width = right - visible_bounds.x;
        visible_bounds.height = bottom - visible_bounds.y;
    }
    const std::string visible_text(
        text + first_visible,
        text + last_visible + 1
    );
    return boundedRangeMatches(
        connection,
        application,
        path,
        visible_bounds.x,
        visible_bounds.y,
        visible_bounds.width,
        visible_bounds.height,
        0u,
        0u,
        first_visible,
        last_visible + 1,
        visible_text.c_str()
    );
}

bool fallbackTextGeometryMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path
) {
    TextExtent extent;
    if (!characterExtent(connection, application, path, 0, extent) ||
        extent.x != 480 || extent.y != 70 || extent.width != 50 ||
        extent.height != 40) return false;

    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Text",
        "GetOffsetAtPoint",
        g_variant_new("(iiu)", 505, 90, 1u),
        G_VARIANT_TYPE("(i)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gint32 offset = -1;
    g_variant_get(result, "(i)", &offset);
    g_variant_unref(result);
    if (error) g_error_free(error);
    return offset == 0;
}

bool containedComponentGeometryMatches(
    GDBusConnection* connection,
    const char* application,
    const char* path
) {
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        path,
        "org.a11y.atspi.Component",
        "GetExtents",
        g_variant_new("(u)", 1u),
        G_VARIANT_TYPE("((iiii))"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return false;
    }
    gint32 x = -1;
    gint32 y = -1;
    gint32 width = -1;
    gint32 height = -1;
    g_variant_get(result, "((iiii))", &x, &y, &width, &height);
    g_variant_unref(result);
    if (error) g_error_free(error);
    const bool matches = x == 0 && y == 0 && width == 0 && height == 0;
    if (!matches) {
        std::fprintf(
            stderr,
            "AT-SPI contained component geometry: %d,%d %dx%d\n",
            x,
            y,
            width,
            height
        );
    }
    return matches;
}

void eventReceived(
    GDBusConnection*,
    const gchar*,
    const gchar*,
    const gchar*,
    const gchar* signal_name,
    GVariant* parameters,
    gpointer userdata
) {
    auto* evidence = static_cast<Evidence*>(userdata);
    if (!evidence || !signal_name || !parameters) return;
    const char* detail = nullptr;
    g_variant_get_child(parameters, 0, "&s", &detail);
    if (std::strcmp(signal_name, "PropertyChange") == 0 && detail &&
        std::strcmp(detail, "accessible-name") == 0) {
        evidence->property_event.store(true, std::memory_order_release);
        evidence->event_count.fetch_add(1, std::memory_order_acq_rel);
    }
    if (std::strcmp(signal_name, "StateChanged") == 0 && detail &&
        std::strcmp(detail, "focused") == 0) {
        evidence->focus_event.store(true, std::memory_order_release);
        evidence->event_count.fetch_add(1, std::memory_order_acq_rel);
    }
    if (std::strcmp(signal_name, "BoundsChanged") == 0) {
        evidence->bounds_event.store(true, std::memory_order_release);
        evidence->event_count.fetch_add(1, std::memory_order_acq_rel);
    }
    if (std::strcmp(signal_name, "TextChanged") == 0 && detail) {
        gint32 start = -1;
        gint32 length = -1;
        g_variant_get_child(parameters, 1, "i", &start);
        g_variant_get_child(parameters, 2, "i", &length);
        GVariant* boxed = g_variant_get_child_value(parameters, 3);
        GVariant* value = g_variant_get_variant(boxed);
        const char* text = g_variant_is_of_type(value, G_VARIANT_TYPE_STRING)
            ? g_variant_get_string(value, nullptr)
            : nullptr;
        if (start == 1 && length == 1 && text) {
            if (std::strcmp(detail, "insert") == 0 &&
                std::strcmp(text, "🙂") == 0)
                evidence->text_insert_event.store(true, std::memory_order_release);
            if (std::strcmp(detail, "delete") == 0 &&
                std::strcmp(text, "🙂") == 0)
                evidence->text_delete_event.store(true, std::memory_order_release);
            if (std::strcmp(detail, "delete") == 0 &&
                std::strcmp(text, "é") == 0)
                evidence->text_replacement_delete_event.store(
                    true,
                    std::memory_order_release
                );
            if (std::strcmp(detail, "insert") == 0 &&
                std::strcmp(text, "ø") == 0)
                evidence->text_replacement_insert_event.store(
                    true,
                    std::memory_order_release
                );
        }
        evidence->text_event_count.fetch_add(1, std::memory_order_acq_rel);
        g_variant_unref(value);
        g_variant_unref(boxed);
    }
    if (std::strcmp(signal_name, "TextCaretMoved") == 0) {
        gint32 offset = -1;
        g_variant_get_child(parameters, 1, "i", &offset);
        if (offset == 0 || offset == 2)
            evidence->caret_event.store(true, std::memory_order_release);
        evidence->caret_event_count.fetch_add(1, std::memory_order_acq_rel);
    }
    if (std::strcmp(signal_name, "TextSelectionChanged") == 0) {
        evidence->selection_event.store(true, std::memory_order_release);
        evidence->selection_event_count.fetch_add(1, std::memory_order_acq_rel);
    }
}

void truncatedEventReceived(
    GDBusConnection*,
    const gchar*,
    const gchar*,
    const gchar*,
    const gchar* signal_name,
    GVariant* parameters,
    gpointer userdata
) {
    auto* evidence = static_cast<Evidence*>(userdata);
    if (!evidence || !signal_name || !parameters ||
        std::strcmp(signal_name, "StateChanged") != 0) return;
    const char* detail = nullptr;
    gint32 enabled = -1;
    g_variant_get_child(parameters, 0, "&s", &detail);
    g_variant_get_child(parameters, 1, "i", &enabled);
    if (detail && std::strcmp(detail, "truncated") == 0 && enabled == 0)
        evidence->truncated_state_event.store(true, std::memory_order_release);
}

void inspectApplication(
    GDBusConnection* connection,
    const char* application,
    const char* root,
    Evidence& evidence
) {
    g_dbus_connection_signal_subscribe(
        connection,
        application,
        cache_interface,
        nullptr,
        cache_path,
        nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE,
        cacheEventReceived,
        &evidence,
        nullptr
    );
    g_dbus_connection_signal_subscribe(
        connection,
        application,
        object_event_interface,
        nullptr,
        first_child_path,
        nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE,
        eventReceived,
        &evidence,
        nullptr
    );
    g_dbus_connection_signal_subscribe(
        connection,
        application,
        object_event_interface,
        "StateChanged",
        fourth_child_path,
        nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE,
        truncatedEventReceived,
        &evidence,
        nullptr
    );
    GError* error = nullptr;
    GVariant* result = g_dbus_connection_call_sync(
        connection,
        application,
        root,
        "org.freedesktop.DBus.Properties",
        "Set",
        g_variant_new(
            "(ssv)",
            application_interface,
            "Id",
            g_variant_new_int32(37)
        ),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    evidence.id_set.store(callSucceeded(result, error), std::memory_order_release);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        application,
        root,
        accessible_interface,
        "GetRole",
        nullptr,
        G_VARIANT_TYPE("(u)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        guint32 role = 0;
        g_variant_get(result, "(u)", &role);
        evidence.root_role.store(role == 75, std::memory_order_release);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }


    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        application,
        root,
        accessible_interface,
        "GetChildren",
        nullptr,
        G_VARIANT_TYPE("(a(so))"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (!result) {
        if (error) g_error_free(error);
        return;
    }
    GVariant* children = nullptr;
    g_variant_get(result, "(@a(so))", &children);
    GVariantIter iterator;
    g_variant_iter_init(&iterator, children);
    const char* child_application = nullptr;
    const char* child_path = nullptr;
    if (!g_variant_iter_next(
            &iterator,
            "(&s&o)",
            &child_application,
            &child_path
        )) {
        g_variant_unref(children);
        g_variant_unref(result);
        return;
    }
    const std::string child_bus = child_application;
    const std::string path = child_path;
    evidence.child_found.store(
        child_bus == application &&
            path == first_child_path,
        std::memory_order_release
    );
    g_variant_unref(children);
    g_variant_unref(result);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Get",
        g_variant_new("(ss)", accessible_interface, "Name"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* value = nullptr;
        g_variant_get(result, "(v)", &value);
        evidence.child_name.store(
            g_variant_is_of_type(value, G_VARIANT_TYPE_STRING) &&
                std::strcmp(g_variant_get_string(value, nullptr), "Gain") == 0,
            std::memory_order_release
        );
        g_variant_unref(value);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    bool selection_queries = intPropertyMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "CaretOffset",
        1
    );
    selection_queries &= textSelectionCountMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        0
    );
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "SetCaretOffset",
        g_variant_new("(i)", 2),
        true
    );
    selection_queries &= intPropertyMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "CaretOffset",
        2
    );
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "AddSelection",
        g_variant_new("(ii)", 0, 2),
        true
    );
    selection_queries &= textSelectionCountMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        1
    ) && textSelectionMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        0,
        2
    );
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "AddSelection",
        g_variant_new("(ii)", 1, 2),
        false
    );
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "SetSelection",
        g_variant_new("(iii)", 0, 2, 0),
        true
    ) && textSelectionMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        0,
        2
    );
    evidence.reject_text_selection.store(true, std::memory_order_release);
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "SetSelection",
        g_variant_new("(iii)", 0, 1, 2),
        false
    ) && textSelectionMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        0,
        2
    );
    evidence.reject_text_selection.store(false, std::memory_order_release);
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "RemoveSelection",
        g_variant_new("(i)", 0),
        true
    );
    selection_queries &= textSelectionCountMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        0
    );
    selection_queries &= textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "SetCaretOffset",
        g_variant_new("(i)", 4),
        false
    ) && textBooleanMethod(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "SetSelection",
        g_variant_new("(iii)", 0, 0, 1),
        false
    );
    evidence.text_selection_queries.store(
        selection_queries,
        std::memory_order_release
    );

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "CopyText",
        g_variant_new("(ii)", 1, 2),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    bool clipboard_methods_succeeded = callSucceeded(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "CutText",
        g_variant_new("(ii)", 1, 2),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    clipboard_methods_succeeded &= booleanResult(result, error, true);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "PasteText",
        g_variant_new("(i)", 1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    clipboard_methods_succeeded &= booleanResult(result, error, true);
    evidence.clipboard_methods_succeeded.store(
        clipboard_methods_succeeded,
        std::memory_order_release
    );

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        accessible_interface,
        "GetRole",
        nullptr,
        G_VARIANT_TYPE("(u)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        guint32 role = 0;
        g_variant_get(result, "(u)", &role);
        evidence.child_role.store(role == 79, std::memory_order_release);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        accessible_interface,
        "GetInterfaces",
        nullptr,
        G_VARIANT_TYPE("(as)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* interfaces = nullptr;
        g_variant_get(result, "(@as)", &interfaces);
        bool accessible = false;
        bool action = false;
        bool component = false;
        bool editable_text = false;
        bool text = false;
        bool value = false;
        GVariantIter interface_iterator;
        g_variant_iter_init(&interface_iterator, interfaces);
        const char* interface = nullptr;
        while (g_variant_iter_next(&interface_iterator, "&s", &interface)) {
            accessible |= std::strcmp(interface, "Accessible") == 0;
            action |= std::strcmp(interface, "Action") == 0;
            component |= std::strcmp(interface, "Component") == 0;
            editable_text |= std::strcmp(interface, "EditableText") == 0;
            text |= std::strcmp(interface, "Text") == 0;
            value |= std::strcmp(interface, "Value") == 0;
        }
        evidence.child_interfaces.store(
            accessible && action && component && editable_text && text && value,
            std::memory_order_release
        );
        evidence.text_interface.store(text, std::memory_order_release);
        evidence.editable_interface.store(
            editable_text,
            std::memory_order_release
        );
        g_variant_unref(interfaces);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    bool text_queries = false;
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Get",
        g_variant_new("(ss)", "org.a11y.atspi.Text", "CharacterCount"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* value = nullptr;
        g_variant_get(result, "(v)", &value);
        text_queries = g_variant_is_of_type(value, G_VARIANT_TYPE_INT32) &&
            g_variant_get_int32(value) == 3;
        g_variant_unref(value);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetText",
        g_variant_new("(ii)", 0, -1),
        G_VARIANT_TYPE("(s)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        const char* value = nullptr;
        g_variant_get(result, "(&s)", &value);
        text_queries &= value && std::strcmp(value, "AéB") == 0;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    bool text_boundaries = false;
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        second_child_path,
        "org.a11y.atspi.Text",
        "GetStringAtOffset",
        g_variant_new("(iu)", 6, 1u),
        G_VARIANT_TYPE("(sii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        const char* value = nullptr;
        gint32 start = -1;
        gint32 end = -1;
        g_variant_get(result, "(&sii)", &value, &start, &end);
        text_boundaries = value && std::strcmp(value, "au ") == 0 &&
            start == 5 && end == 8;
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        second_child_path,
        "org.a11y.atspi.Text",
        "GetStringAtOffset",
        g_variant_new("(iu)", 15, 2u),
        G_VARIANT_TYPE("(sii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        const char* value = nullptr;
        gint32 start = -1;
        gint32 end = -1;
        g_variant_get(result, "(&sii)", &value, &start, &end);
        text_boundaries &= value && std::strcmp(value, "你好！ ") == 0 &&
            start == 14 && end == 18;
        g_variant_unref(result);
    } else {
        text_boundaries = false;
        if (error) g_error_free(error);
    }
    const bool legacy_word_at = textRangeMatches(
        connection,
        child_bus.c_str(),
        second_child_path,
        "GetTextAtOffset",
        6,
        1u,
        "au ",
        5,
        8
    );
    const bool legacy_word_end_at = textRangeMatches(
        connection,
        child_bus.c_str(),
        second_child_path,
        "GetTextAtOffset",
        6,
        2u,
        " au",
        4,
        7
    );
    const bool legacy_word_before = textRangeMatches(
        connection,
        child_bus.c_str(),
        second_child_path,
        "GetTextBeforeOffset",
        6,
        1u,
        "Café ",
        0,
        5
    );
    const bool legacy_word_after = textRangeMatches(
        connection,
        child_bus.c_str(),
        second_child_path,
        "GetTextAfterOffset",
        6,
        1u,
        "lait. ",
        8,
        14
    );
    const bool legacy_sentence_end = textRangeMatches(
        connection,
        child_bus.c_str(),
        second_child_path,
        "GetTextAtOffset",
        15,
        4u,
        " 你好！",
        13,
        17
    );
    text_boundaries &= legacy_word_at && legacy_word_end_at &&
        legacy_word_before && legacy_word_after && legacy_sentence_end;
    if (!legacy_word_at || !legacy_word_end_at || !legacy_word_before ||
        !legacy_word_after || !legacy_sentence_end) {
        std::fprintf(
            stderr,
            "AT-SPI legacy boundaries: at=%d end-at=%d before=%d "
            "after=%d sentence-end=%d\n",
            legacy_word_at,
            legacy_word_end_at,
            legacy_word_before,
            legacy_word_after,
            legacy_sentence_end
        );
    }
    evidence.text_boundaries.store(text_boundaries, std::memory_order_release);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetStringAtOffset",
        g_variant_new("(iu)", 1, 0u),
        G_VARIANT_TYPE("(sii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        const char* value = nullptr;
        gint32 start = -1;
        gint32 end = -1;
        g_variant_get(result, "(&sii)", &value, &start, &end);
        text_queries &= value && std::strcmp(value, "é") == 0 &&
            start == 1 && end == 2;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetCharacterAtOffset",
        g_variant_new("(i)", 1),
        G_VARIANT_TYPE("(i)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 value = -1;
        g_variant_get(result, "(i)", &value);
        text_queries &= value == 0xE9;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    gint32 character_x = 0;
    gint32 character_y = 0;
    gint32 character_width = 0;
    gint32 character_height = 0;
    bool character_geometry = false;
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetCharacterExtents",
        g_variant_new("(iu)", 1, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        g_variant_get(
            result,
            "(iiii)",
            &character_x,
            &character_y,
            &character_width,
            &character_height
        );
        character_geometry = character_x > 14 && character_x < 43 &&
            character_y >= 20 && character_y < 60 &&
            character_width > 1 && character_width < 33 &&
            character_height > 0 && character_height < 40;
        text_queries &= character_geometry;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    bool range_geometry = false;
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetRangeExtents",
        g_variant_new("(iiu)", 0, 2, 1u),
        G_VARIANT_TYPE("(iiii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 x = 0;
        gint32 y = 0;
        gint32 width = 0;
        gint32 height = 0;
        g_variant_get(result, "(iiii)", &x, &y, &width, &height);
        range_geometry = x == 14 && y == character_y &&
            x + width == character_x + character_width &&
            height == character_height;
        text_queries &= range_geometry;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    bool point_geometry = false;
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetOffsetAtPoint",
        g_variant_new(
            "(iiu)",
            character_x + character_width / 2,
            character_y + character_height / 2,
            1u
        ),
        G_VARIANT_TYPE("(i)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 offset = -1;
        g_variant_get(result, "(i)", &offset);
        point_geometry = offset == 1;
        text_queries &= point_geometry;
        g_variant_unref(result);
    } else {
        text_queries = false;
        if (error) g_error_free(error);
    }

    const bool bounded_complete = boundedRangeMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        character_x,
        20,
        character_width,
        40,
        3u,
        0u,
        1,
        2,
        "é"
    );
    const bool bounded_partial = boundedRangeMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        character_x + 1,
        20,
        character_width - 1,
        40,
        0u,
        0u,
        1,
        2,
        "é"
    );
    const bool bounded_minimum = boundedRangeMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        character_x + 1,
        20,
        character_width - 1,
        40,
        1u,
        0u,
        -1,
        -1,
        nullptr
    );
    const bool bounded_maximum = boundedRangeMatches(
        connection,
        child_bus.c_str(),
        path.c_str(),
        character_x,
        20,
        character_width - 1,
        40,
        2u,
        0u,
        -1,
        -1,
        nullptr
    );
    text_queries &= bounded_complete && bounded_partial && bounded_minimum &&
        bounded_maximum;
    if (!character_geometry || !range_geometry || !point_geometry ||
        !bounded_complete || !bounded_partial || !bounded_minimum ||
        !bounded_maximum) {
        std::fprintf(
            stderr,
            "AT-SPI text geometry: character=%d range=%d point=%d "
            "bounded=%d/%d/%d/%d rect=%d,%d %dx%d\n",
            character_geometry,
            range_geometry,
            point_geometry,
            bounded_complete,
            bounded_partial,
            bounded_minimum,
            bounded_maximum,
            character_x,
            character_y,
            character_width,
            character_height
        );
    }
    evidence.text_queries.store(text_queries, std::memory_order_release);
    evidence.rotated_text_geometry.store(
        rotatedTextGeometryMatches(
            connection,
            child_bus.c_str(),
            third_child_path
        ),
        std::memory_order_release
    );
    evidence.tail_truncated_text_geometry.store(
        truncatedTextGeometryMatches(
            connection,
            child_bus.c_str(),
            fourth_child_path,
            "ABCDEFGHIJKLMN",
            false
        ),
        std::memory_order_release
    );
    evidence.head_truncated_text_geometry.store(
        truncatedTextGeometryMatches(
            connection,
            child_bus.c_str(),
            fifth_child_path,
            "OPQRSTUVWXYZAB",
            true
        ),
        std::memory_order_release
    );
    evidence.hostile_text_geometry.store(
        fallbackTextGeometryMatches(
            connection,
            child_bus.c_str(),
            sixth_child_path
        ),
        std::memory_order_release
    );
    evidence.hostile_component_geometry.store(
        containedComponentGeometryMatches(
            connection,
            child_bus.c_str(),
            seventh_child_path
        ),
        std::memory_order_release
    );

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Component",
        "GetExtents",
        g_variant_new("(u)", 1u),
        G_VARIANT_TYPE("((iiii))"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        gint32 x = 0;
        gint32 y = 0;
        gint32 width = 0;
        gint32 height = 0;
        g_variant_get(result, "((iiii))", &x, &y, &width, &height);
        evidence.component_bounds.store(
            x == 10 && y == 20 && width == 100 && height == 40,
            std::memory_order_release
        );
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Get",
        g_variant_new("(ss)", "org.a11y.atspi.Action", "NActions"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* count = nullptr;
        g_variant_get(result, "(v)", &count);
        evidence.action_count.store(
            g_variant_get_int32(count) == 1,
            std::memory_order_release
        );
        g_variant_unref(count);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Action",
        "DoAction",
        g_variant_new("(i)", 0),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    callSucceeded(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        cache_path,
        cache_interface,
        "GetItems",
        nullptr,
        G_VARIANT_TYPE("(a((so)(so)(so)iiassusau))"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* items = nullptr;
        g_variant_get(result, "(@a((so)(so)(so)iiassusau))", &items);
        evidence.cache_items.store(
            g_variant_n_children(items) == 8,
            std::memory_order_release
        );
        g_variant_unref(items);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "InsertText",
        g_variant_new("(isi)", 2, "x", 1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    callSucceeded(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "DeleteText",
        g_variant_new("(ii)", 1, 2),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    callSucceeded(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Get",
        g_variant_new("(ss)", "org.a11y.atspi.Value", "CurrentValue"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    if (result) {
        GVariant* value_variant = nullptr;
        g_variant_get(result, "(v)", &value_variant);
        evidence.value_read.store(
            g_variant_get_double(value_variant) == 0.5,
            std::memory_order_release
        );
        g_variant_unref(value_variant);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Set",
        g_variant_new(
            "(ssv)",
            "org.a11y.atspi.Value",
            "CurrentValue",
            g_variant_new_double(0.75)
        ),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    callSucceeded(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "SetTextContents",
        g_variant_new("(s)", "Output gain"),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    callSucceeded(result, error);

    const auto calls_before_hostile = evidence.action_call_count.load(
        std::memory_order_acquire
    );
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Action",
        "DoAction",
        g_variant_new("(i)", -1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    bool hostile_rejected = callRejected(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "CopyText",
        g_variant_new("(ii)", 2, 1),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= callRejected(result, error);

    evidence.reject_clipboard_writes.store(true, std::memory_order_release);
    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "CopyText",
        g_variant_new("(ii)", 1, 2),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= callRejected(result, error);
    evidence.reject_clipboard_writes.store(false, std::memory_order_release);

    const auto pasteReturns = [&](gint32 position, bool expected) {
        GError* paste_error = nullptr;
        GVariant* paste_result = g_dbus_connection_call_sync(
            connection,
            child_bus.c_str(),
            path.c_str(),
            "org.a11y.atspi.EditableText",
            "PasteText",
            g_variant_new("(i)", position),
            G_VARIANT_TYPE("(b)"),
            G_DBUS_CALL_FLAGS_NONE,
            timeout_ms,
            nullptr,
            &paste_error
        );
        return booleanResult(paste_result, paste_error, expected);
    };

    evidence.reject_clipboard_reads.store(true, std::memory_order_release);
    hostile_rejected &= pasteReturns(1, false);
    evidence.reject_clipboard_reads.store(false, std::memory_order_release);

    hostile_rejected &= pasteReturns(4, false);
    for (unsigned int mode = 1; mode <= 3; ++mode) {
        evidence.clipboard_read_mode.store(mode, std::memory_order_release);
        hostile_rejected &= pasteReturns(1, false);
    }
    evidence.clipboard_read_mode.store(0, std::memory_order_release);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "InsertText",
        g_variant_new("(isi)", 4, "x", 1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= booleanResult(result, error, false);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "InsertText",
        g_variant_new("(isi)", 1, "é", 1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= booleanResult(result, error, false);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.EditableText",
        "DeleteText",
        g_variant_new("(ii)", 2, 1),
        G_VARIANT_TYPE("(b)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= booleanResult(result, error, false);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.freedesktop.DBus.Properties",
        "Set",
        g_variant_new(
            "(ssv)",
            "org.a11y.atspi.Value",
            "CurrentValue",
            g_variant_new_double(std::nan(""))
        ),
        nullptr,
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= callRejected(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetText",
        g_variant_new("(ii)", 2, 1),
        G_VARIANT_TYPE("(s)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= callRejected(result, error);

    error = nullptr;
    result = g_dbus_connection_call_sync(
        connection,
        child_bus.c_str(),
        path.c_str(),
        "org.a11y.atspi.Text",
        "GetStringAtOffset",
        g_variant_new("(iu)", 4, 0u),
        G_VARIANT_TYPE("(sii)"),
        G_DBUS_CALL_FLAGS_NONE,
        timeout_ms,
        nullptr,
        &error
    );
    hostile_rejected &= callRejected(result, error);
    evidence.hostile_inputs_rejected.store(
        hostile_rejected &&
            evidence.action_call_count.load(std::memory_order_acquire) ==
                calls_before_hostile,
        std::memory_order_release
    );
    evidence.inspection_complete.store(true, std::memory_order_release);
}

struct Service {
    std::string address;
    Evidence evidence;
    std::mutex mutex;
    std::condition_variable condition;
    bool ready {false};
    bool valid {false};
    bool register_registry {true};
    GMainContext* context {nullptr};
    GMainLoop* loop {nullptr};
    std::thread thread;

    static void methodCall(
        GDBusConnection* connection,
        const gchar*,
        const gchar*,
        const gchar* interface_name,
        const gchar* method_name,
        GVariant* parameters,
        GDBusMethodInvocation* invocation,
        gpointer userdata
    ) {
        auto* service = static_cast<Service*>(userdata);
        if (std::strcmp(interface_name, bus_name) == 0 &&
            std::strcmp(method_name, "GetAddress") == 0) {
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(s)", service->address.c_str())
            );
            return;
        }
        if (std::strcmp(interface_name, "org.a11y.atspi.Socket") == 0 &&
            std::strcmp(method_name, "Embed") == 0) {
            const char* application = nullptr;
            const char* root = nullptr;
            g_variant_get(parameters, "((&s&o))", &application, &root);
            inspectApplication(
                connection,
                application,
                root,
                service->evidence
            );
            service->evidence.embedded.store(true, std::memory_order_release);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("((so))", registry_name, registry_path)
            );
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown test service method"
        );
    }

    bool requestName(GDBusConnection* connection, const char* name) {
        GError* error = nullptr;
        GVariant* result = g_dbus_connection_call_sync(
            connection,
            "org.freedesktop.DBus",
            "/org/freedesktop/DBus",
            "org.freedesktop.DBus",
            "RequestName",
            g_variant_new("(su)", name, 0u),
            G_VARIANT_TYPE("(u)"),
            G_DBUS_CALL_FLAGS_NONE,
            timeout_ms,
            nullptr,
            &error
        );
        if (!result) {
            if (error) g_error_free(error);
            return false;
        }
        guint32 reply = 0;
        g_variant_get(result, "(u)", &reply);
        g_variant_unref(result);
        return reply == 1 || reply == 4;
    }

    void run() {
        context = g_main_context_new();
        g_main_context_push_thread_default(context);
        loop = g_main_loop_new(context, false);
        GError* error = nullptr;
        GDBusConnection* connection =
            g_dbus_connection_new_for_address_sync(
                address.c_str(),
                static_cast<GDBusConnectionFlags>(
                    G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                    G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION
                ),
                nullptr,
                nullptr,
                &error
            );
        GDBusNodeInfo* node = connection
            ? g_dbus_node_info_new_for_xml(service_xml, &error)
            : nullptr;
        static const GDBusInterfaceVTable vtable {
            methodCall,
            nullptr,
            nullptr,
            {nullptr},
        };
        guint bus_registration = 0;
        guint registry_registration = 0;
        const bool names_ready = node && requestName(connection, bus_name) &&
            (!register_registry || requestName(connection, registry_name));
        if (names_ready) {
            auto* bus_info = g_dbus_node_info_lookup_interface(node, bus_name);
            bus_registration = g_dbus_connection_register_object(
                connection,
                bus_path,
                bus_info,
                &vtable,
                this,
                nullptr,
                &error
            );
            if (register_registry) {
                auto* registry_info = g_dbus_node_info_lookup_interface(
                    node,
                    "org.a11y.atspi.Socket"
                );
                registry_registration = g_dbus_connection_register_object(
                    connection,
                    registry_path,
                    registry_info,
                    &vtable,
                    this,
                    nullptr,
                    &error
                );
            }
        }
        {
            std::lock_guard<std::mutex> lock(mutex);
            valid = bus_registration != 0 &&
                (!register_registry || registry_registration != 0);
            ready = true;
        }
        condition.notify_one();
        if (valid) g_main_loop_run(loop);
        if (connection && registry_registration)
            g_dbus_connection_unregister_object(connection, registry_registration);
        if (connection && bus_registration)
            g_dbus_connection_unregister_object(connection, bus_registration);
        if (node) g_dbus_node_info_unref(node);
        if (connection) g_object_unref(connection);
        if (error) g_error_free(error);
        g_main_loop_unref(loop);
        loop = nullptr;
        g_main_context_pop_thread_default(context);
        g_main_context_unref(context);
        context = nullptr;
    }

    bool start(const char* bus_address, bool with_registry = true) {
        address = bus_address;
        register_registry = with_registry;
        thread = std::thread([this] { run(); });
        std::unique_lock<std::mutex> lock(mutex);
        return condition.wait_for(
            lock,
            std::chrono::seconds(5),
            [this] { return ready; }
        ) && valid;
    }

    void stop() {
        if (context && loop) {
            g_main_context_invoke(
                context,
                [](gpointer data) -> gboolean {
                    g_main_loop_quit(static_cast<GMainLoop*>(data));
                    return G_SOURCE_REMOVE;
                },
                loop
            );
        }
        if (thread.joinable()) thread.join();
    }
};

bool perform(
    void* userdata,
    const ZigVstgui::AccessibilityNode&,
    const ZigVstgui::AccessibilityActionRequest& request
) {
    auto* evidence = static_cast<Evidence*>(userdata);
    if (!evidence) return false;
    evidence->action_call_count.fetch_add(1, std::memory_order_acq_rel);
    if (request.action == ZigVstgui::AccessibilityAction::set_caret ||
        request.action == ZigVstgui::AccessibilityAction::set_selection) {
        if (evidence->reject_text_selection.load(std::memory_order_acquire) ||
            !evidence->node ||
            !evidence->node->setTextSelection(request.text_start, request.text_end))
            return false;
        if (request.action == ZigVstgui::AccessibilityAction::set_caret &&
            request.text_start == 2 && request.text_end == 2)
            evidence->caret_set.store(true, std::memory_order_release);
        if (request.action == ZigVstgui::AccessibilityAction::set_selection &&
            request.text_start == 0 && request.text_end == 2)
            evidence->selection_added.store(true, std::memory_order_release);
        if (request.action == ZigVstgui::AccessibilityAction::set_selection &&
            request.text_start == 2 && request.text_end == 0)
            evidence->selection_changed.store(true, std::memory_order_release);
        if (request.action == ZigVstgui::AccessibilityAction::set_selection &&
            request.text_start == request.text_end)
            evidence->selection_removed.store(true, std::memory_order_release);
        return true;
    }
    if (request.action == ZigVstgui::AccessibilityAction::press)
        evidence->action_performed.store(true, std::memory_order_release);
    if (request.action == ZigVstgui::AccessibilityAction::set_value &&
        request.value == 0.75)
        evidence->value_set.store(true, std::memory_order_release);
    if (request.action == ZigVstgui::AccessibilityAction::set_value &&
        request.text && std::strcmp(request.text, "Output gain") == 0)
        evidence->text_set.store(true, std::memory_order_release);
    if (request.action == ZigVstgui::AccessibilityAction::set_value &&
        request.text && std::strcmp(request.text, "AéxB") == 0)
        evidence->text_inserted.store(true, std::memory_order_release);
    if (request.action == ZigVstgui::AccessibilityAction::set_value &&
        request.text && std::strcmp(request.text, "AB") == 0) {
        evidence->text_deleted.store(true, std::memory_order_release);
        evidence->text_ab_updates.fetch_add(1, std::memory_order_acq_rel);
    }
    if (request.action == ZigVstgui::AccessibilityAction::set_value &&
        request.text && std::strcmp(request.text, "AééB") == 0)
        evidence->text_pasted.store(true, std::memory_order_release);
    return true;
}

int runTest() {
    VstguiRuntime runtime;
    g_setenv("ZIG_VSTGUI_DIAGNOSTICS", "1", true);
    GTestDBus* bus = g_test_dbus_new(G_TEST_DBUS_NONE);
    g_test_dbus_up(bus);
    Service service;
    ZigVstgui::AccessibilityNode node;
    node.setRole(ZigVstgui::AccessibilityRole::text_field);
    node.setName("Gain");
    node.setDescription("Output level");
    node.setValueText("AéB");
    if (!node.setTextSelection(1, 1)) {
        g_test_dbus_down(bus);
        g_object_unref(bus);
        return 1;
    }
    service.evidence.node = &node;
    node.setRange(0.0, 1.0, 0.5);
    node.setActionHandler(
        &service.evidence,
        perform,
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::focus) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::press) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_value) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_caret) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_selection)
    );
    ZigVstgui::AccessibilityNode boundary_node;
    boundary_node.setRole(ZigVstgui::AccessibilityRole::text_field);
    boundary_node.setName("Boundary fixture");
    boundary_node.setValueText("Café au lait. 你好！ Next?");
    boundary_node.setReadOnly(true);
    auto frame = VSTGUI::owned(new VSTGUI::CFrame(
        VSTGUI::CRect(0, 0, 640, 480),
        nullptr
    ));
    auto* view = new VSTGUI::CTextLabel(
        VSTGUI::CRect(10, 20, 110, 60),
        "AéB"
    );
    view->setHoriAlign(VSTGUI::kLeftText);
    view->setTextInset(VSTGUI::CPoint(4, 2));
    frame->addView(view);
    view->setWantsFocus(true);
    auto* boundary_view = new VSTGUI::CView(
        VSTGUI::CRect(10, 70, 210, 110)
    );
    frame->addView(boundary_view);
    ZigVstgui::AccessibilityNode rotated_node;
    rotated_node.setRole(ZigVstgui::AccessibilityRole::text_field);
    rotated_node.setName("Rotated fixture");
    rotated_node.setValueText("AB");
    rotated_node.setReadOnly(true);
    auto* rotated_view = new VSTGUI::CTextLabel(
        VSTGUI::CRect(240, 20, 340, 120),
        "AB"
    );
    rotated_view->setHoriAlign(VSTGUI::kLeftText);
    rotated_view->setTextInset(VSTGUI::CPoint(4, 2));
    rotated_view->setTextRotation(90.0);
    frame->addView(rotated_view);
    ZigVstgui::AccessibilityNode tail_truncated_node;
    tail_truncated_node.setRole(ZigVstgui::AccessibilityRole::text_field);
    tail_truncated_node.setName("Tail truncated fixture");
    tail_truncated_node.setValueText("ABCDEFGHIJKLMN");
    tail_truncated_node.setReadOnly(true);
    auto* tail_truncated_view = new VSTGUI::CTextLabel(
        VSTGUI::CRect(360, 20, 410, 60),
        "ABCDEFGHIJKLMN"
    );
    tail_truncated_view->setHoriAlign(VSTGUI::kLeftText);
    tail_truncated_view->setTextInset(VSTGUI::CPoint(2, 2));
    tail_truncated_view->setTextTruncateMode(VSTGUI::CTextLabel::kTruncateTail);
    frame->addView(tail_truncated_view);
    ZigVstgui::AccessibilityNode head_truncated_node;
    head_truncated_node.setRole(ZigVstgui::AccessibilityRole::text_field);
    head_truncated_node.setName("Head truncated fixture");
    head_truncated_node.setValueText("OPQRSTUVWXYZAB");
    head_truncated_node.setReadOnly(true);
    auto* head_truncated_view = new VSTGUI::CTextLabel(
        VSTGUI::CRect(420, 20, 470, 60),
        "OPQRSTUVWXYZAB"
    );
    head_truncated_view->setHoriAlign(VSTGUI::kLeftText);
    head_truncated_view->setTextInset(VSTGUI::CPoint(2, 2));
    head_truncated_view->setTextTruncateMode(VSTGUI::CTextLabel::kTruncateHead);
    frame->addView(head_truncated_view);
    ZigVstgui::AccessibilityNode hostile_geometry_node;
    hostile_geometry_node.setRole(ZigVstgui::AccessibilityRole::text_field);
    hostile_geometry_node.setName("Hostile geometry fixture");
    hostile_geometry_node.setValueText("XY");
    hostile_geometry_node.setReadOnly(true);
    auto* hostile_geometry_view = new VSTGUI::CTextLabel(
        VSTGUI::CRect(480, 70, 580, 110),
        "XY"
    );
    hostile_geometry_view->setTextRotation(
        std::numeric_limits<double>::quiet_NaN()
    );
    frame->addView(hostile_geometry_view);
    ZigVstgui::AccessibilityNode hostile_component_node;
    hostile_component_node.setRole(ZigVstgui::AccessibilityRole::group);
    hostile_component_node.setName("Hostile component fixture");
    const double not_a_number = std::numeric_limits<double>::quiet_NaN();
    auto* hostile_component_view = new VSTGUI::CView(
        VSTGUI::CRect(not_a_number, 120, not_a_number, 160)
    );
    frame->addView(hostile_component_view);
    ZigVstgui::NativeAccessibilityBridge bridge;
    auto clipboard = std::make_shared<TestClipboard>(service.evidence);
    const bool missing_bus_safe = !bridge.open(
        frame.get(),
        {{&node, view}},
        clipboard
    ) && !bridge.active() && bridge.elementCount() == 0;
    Service bus_without_registry;
    if (!bus_without_registry.start(g_test_dbus_get_bus_address(bus), false)) {
        bus_without_registry.stop();
        g_test_dbus_down(bus);
        g_object_unref(bus);
        return 1;
    }
    const bool missing_registry_safe = !bridge.open(
        frame.get(),
        {{&node, view}},
        clipboard
    ) && !bridge.active() && bridge.elementCount() == 0;
    bridge.close();
    bus_without_registry.stop();
    if (!service.start(g_test_dbus_get_bus_address(bus))) {
        service.stop();
        g_test_dbus_down(bus);
        g_object_unref(bus);
        return 1;
    }
    const bool opened = bridge.open(
        frame.get(),
        {
            {&node, view},
            {&boundary_node, boundary_view},
            {&rotated_node, rotated_view},
            {&tail_truncated_node, tail_truncated_view},
            {&head_truncated_node, head_truncated_view},
            {&hostile_geometry_node, hostile_geometry_view},
            {&hostile_component_node, hostile_component_view},
        },
        clipboard
    );
    const bool active = bridge.active();
    const std::size_t element_count = bridge.elementCount();
    for (int attempt = 0; attempt < 400; ++attempt) {
        if (service.evidence.inspection_complete.load(std::memory_order_acquire))
            break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    node.setTextSelection(0, 2);
    node.setTextSelection(2, 0);
    node.setTextSelection(0, 0);
    node.setValueText("A🙂éB");
    node.setValueText("AéB");
    node.setValueText("AøB");
    node.setName("Output gain field");
    node.setFocused(true);
    tail_truncated_view->setViewSize(VSTGUI::CRect(360, 20, 580, 60));
    bridge.layoutChanged();
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (service.evidence.property_event.load(std::memory_order_acquire) &&
            service.evidence.focus_event.load(std::memory_order_acquire) &&
            service.evidence.bounds_event.load(std::memory_order_acquire) &&
            service.evidence.text_insert_event.load(std::memory_order_acquire) &&
            service.evidence.text_delete_event.load(std::memory_order_acquire) &&
            service.evidence.text_replacement_delete_event.load(
                std::memory_order_acquire
            ) &&
            service.evidence.text_replacement_insert_event.load(
                std::memory_order_acquire
            ) &&
            service.evidence.caret_event.load(std::memory_order_acquire) &&
            service.evidence.selection_event.load(std::memory_order_acquire) &&
            service.evidence.caret_event_count.load(std::memory_order_acquire) == 2 &&
            service.evidence.selection_event_count.load(std::memory_order_acquire) == 3 &&
            service.evidence.truncated_state_event.load(std::memory_order_acquire) &&
            service.evidence.text_event_count.load(std::memory_order_acquire) == 4 &&
            service.evidence.event_count.load(std::memory_order_acquire) == 3 &&
            service.evidence.cache_add_count.load(std::memory_order_acquire) == 8) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    const bool published = missing_bus_safe && missing_registry_safe &&
        opened && active &&
        element_count == 7 &&
        service.evidence.embedded.load(std::memory_order_acquire) &&
        service.evidence.id_set.load(std::memory_order_acquire) &&
        service.evidence.root_role.load(std::memory_order_acquire) &&
        service.evidence.child_found.load(std::memory_order_acquire) &&
        service.evidence.child_name.load(std::memory_order_acquire) &&
        service.evidence.child_role.load(std::memory_order_acquire) &&
        service.evidence.child_interfaces.load(std::memory_order_acquire) &&
        service.evidence.component_bounds.load(std::memory_order_acquire) &&
        service.evidence.action_count.load(std::memory_order_acquire) &&
        service.evidence.action_performed.load(std::memory_order_acquire) &&
        service.evidence.value_read.load(std::memory_order_acquire) &&
        service.evidence.value_set.load(std::memory_order_acquire) &&
        service.evidence.text_interface.load(std::memory_order_acquire) &&
        service.evidence.text_queries.load(std::memory_order_acquire) &&
        service.evidence.text_boundaries.load(std::memory_order_acquire) &&
        service.evidence.rotated_text_geometry.load(std::memory_order_acquire) &&
        service.evidence.tail_truncated_text_geometry.load(
            std::memory_order_acquire
        ) &&
        service.evidence.head_truncated_text_geometry.load(
            std::memory_order_acquire
        ) &&
        service.evidence.truncated_state_event.load(std::memory_order_acquire) &&
        service.evidence.hostile_text_geometry.load(std::memory_order_acquire) &&
        service.evidence.hostile_component_geometry.load(
            std::memory_order_acquire
        ) &&
        service.evidence.text_selection_queries.load(std::memory_order_acquire) &&
        service.evidence.caret_set.load(std::memory_order_acquire) &&
        service.evidence.selection_added.load(std::memory_order_acquire) &&
        service.evidence.selection_changed.load(std::memory_order_acquire) &&
        service.evidence.selection_removed.load(std::memory_order_acquire) &&
        service.evidence.editable_interface.load(std::memory_order_acquire) &&
        service.evidence.text_set.load(std::memory_order_acquire) &&
        service.evidence.text_inserted.load(std::memory_order_acquire) &&
        service.evidence.text_deleted.load(std::memory_order_acquire) &&
        service.evidence.text_pasted.load(std::memory_order_acquire) &&
        service.evidence.text_ab_updates.load(std::memory_order_acquire) == 2 &&
        service.evidence.clipboard_writes.load(std::memory_order_acquire) == 2 &&
        service.evidence.clipboard_reads.load(std::memory_order_acquire) == 4 &&
        service.evidence.clipboard_methods_succeeded.load(std::memory_order_acquire) &&
        service.evidence.cache_items.load(std::memory_order_acquire) &&
        service.evidence.cache_root_added.load(std::memory_order_acquire) &&
        service.evidence.cache_child_added.load(std::memory_order_acquire) &&
        service.evidence.cache_add_count.load(std::memory_order_acquire) == 8 &&
        service.evidence.hostile_inputs_rejected.load(std::memory_order_acquire) &&
        service.evidence.inspection_complete.load(std::memory_order_acquire) &&
        service.evidence.property_event.load(std::memory_order_acquire) &&
        service.evidence.focus_event.load(std::memory_order_acquire) &&
        service.evidence.bounds_event.load(std::memory_order_acquire) &&
        service.evidence.text_insert_event.load(std::memory_order_acquire) &&
        service.evidence.text_delete_event.load(std::memory_order_acquire) &&
        service.evidence.text_replacement_delete_event.load(
            std::memory_order_acquire
        ) &&
        service.evidence.text_replacement_insert_event.load(
            std::memory_order_acquire
        ) &&
        service.evidence.caret_event.load(std::memory_order_acquire) &&
        service.evidence.selection_event.load(std::memory_order_acquire) &&
        service.evidence.caret_event_count.load(std::memory_order_acquire) == 2 &&
        service.evidence.selection_event_count.load(std::memory_order_acquire) == 3 &&
        service.evidence.text_event_count.load(std::memory_order_acquire) == 4;
    const auto events_before_close = service.evidence.event_count.load(
        std::memory_order_acquire
    );
    const auto text_events_before_close = service.evidence.text_event_count.load(
        std::memory_order_acquire
    );
    const auto caret_events_before_close = service.evidence.caret_event_count.load(
        std::memory_order_acquire
    );
    const auto selection_events_before_close = service.evidence.selection_event_count.load(
        std::memory_order_acquire
    );
    bridge.close();
    node.setName("Detached node");
    node.setValueText("Detached value");
    node.setTextSelection(0, 1);
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (service.evidence.cache_remove_count.load(std::memory_order_acquire) == 8)
            break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    const bool closed = !bridge.active() && bridge.elementCount() == 0 &&
        events_before_close == 3 &&
        service.evidence.event_count.load(std::memory_order_acquire) ==
            events_before_close &&
        service.evidence.text_event_count.load(std::memory_order_acquire) ==
            text_events_before_close &&
        service.evidence.caret_event_count.load(std::memory_order_acquire) ==
            caret_events_before_close &&
        service.evidence.selection_event_count.load(std::memory_order_acquire) ==
            selection_events_before_close &&
        service.evidence.cache_root_removed.load(std::memory_order_acquire) &&
        service.evidence.cache_child_removed.load(std::memory_order_acquire) &&
        service.evidence.cache_remove_count.load(std::memory_order_acquire) == 8;
    if (!published || !closed) {
        std::fprintf(
            stderr,
            "AT-SPI bridge evidence: missing-bus=%d missing-registry=%d "
            "opened=%d active=%d count=%zu "
            "embedded=%d id=%d root-role=%d child=%d name=%d role=%d "
            "interfaces=%d bounds=%d action-count=%d action=%d "
            "value-read=%d value-set=%d text-interface=%d text-queries=%d "
            "text-boundaries=%d rotated-geometry=%d truncated-geometry=%d/%d/%d "
            "hostile-geometry=%d/%d "
            "selection-queries=%d caret-set=%d "
            "selection=%d/%d/%d "
            "editable=%d text-set=%d insert=%d "
            "delete=%d paste=%d ab-updates=%u clipboard-writes=%u clipboard-reads=%u "
            "clipboard-methods=%d "
            "cache=%d cache-root-add=%d cache-child-add=%d "
            "cache-add-count=%u cache-root-remove=%d cache-child-remove=%d "
            "cache-remove-count=%u hostile-inputs=%d action-calls=%u "
            "inspection=%d property-event=%d focus-event=%d "
            "bounds-event=%d text-event-count=%u text-insert=%d "
            "text-delete=%d replacement-delete=%d replacement-insert=%d "
            "caret-event=%d/%u selection-event=%d/%u "
            "closed=%d\n",
            missing_bus_safe,
            missing_registry_safe,
            opened,
            active,
            element_count,
            service.evidence.embedded.load(std::memory_order_acquire),
            service.evidence.id_set.load(std::memory_order_acquire),
            service.evidence.root_role.load(std::memory_order_acquire),
            service.evidence.child_found.load(std::memory_order_acquire),
            service.evidence.child_name.load(std::memory_order_acquire),
            service.evidence.child_role.load(std::memory_order_acquire),
            service.evidence.child_interfaces.load(std::memory_order_acquire),
            service.evidence.component_bounds.load(std::memory_order_acquire),
            service.evidence.action_count.load(std::memory_order_acquire),
            service.evidence.action_performed.load(std::memory_order_acquire),
            service.evidence.value_read.load(std::memory_order_acquire),
            service.evidence.value_set.load(std::memory_order_acquire),
            service.evidence.text_interface.load(std::memory_order_acquire),
            service.evidence.text_queries.load(std::memory_order_acquire),
            service.evidence.text_boundaries.load(std::memory_order_acquire),
            service.evidence.rotated_text_geometry.load(std::memory_order_acquire),
            service.evidence.tail_truncated_text_geometry.load(
                std::memory_order_acquire
            ),
            service.evidence.head_truncated_text_geometry.load(
                std::memory_order_acquire
            ),
            service.evidence.truncated_state_event.load(std::memory_order_acquire),
            service.evidence.hostile_text_geometry.load(std::memory_order_acquire),
            service.evidence.hostile_component_geometry.load(
                std::memory_order_acquire
            ),
            service.evidence.text_selection_queries.load(std::memory_order_acquire),
            service.evidence.caret_set.load(std::memory_order_acquire),
            service.evidence.selection_added.load(std::memory_order_acquire),
            service.evidence.selection_changed.load(std::memory_order_acquire),
            service.evidence.selection_removed.load(std::memory_order_acquire),
            service.evidence.editable_interface.load(std::memory_order_acquire),
            service.evidence.text_set.load(std::memory_order_acquire),
            service.evidence.text_inserted.load(std::memory_order_acquire),
            service.evidence.text_deleted.load(std::memory_order_acquire),
            service.evidence.text_pasted.load(std::memory_order_acquire),
            service.evidence.text_ab_updates.load(std::memory_order_acquire),
            service.evidence.clipboard_writes.load(std::memory_order_acquire),
            service.evidence.clipboard_reads.load(std::memory_order_acquire),
            service.evidence.clipboard_methods_succeeded.load(std::memory_order_acquire),
            service.evidence.cache_items.load(std::memory_order_acquire),
            service.evidence.cache_root_added.load(std::memory_order_acquire),
            service.evidence.cache_child_added.load(std::memory_order_acquire),
            service.evidence.cache_add_count.load(std::memory_order_acquire),
            service.evidence.cache_root_removed.load(std::memory_order_acquire),
            service.evidence.cache_child_removed.load(std::memory_order_acquire),
            service.evidence.cache_remove_count.load(std::memory_order_acquire),
            service.evidence.hostile_inputs_rejected.load(std::memory_order_acquire),
            service.evidence.action_call_count.load(std::memory_order_acquire),
            service.evidence.inspection_complete.load(std::memory_order_acquire),
            service.evidence.property_event.load(std::memory_order_acquire),
            service.evidence.focus_event.load(std::memory_order_acquire),
            service.evidence.bounds_event.load(std::memory_order_acquire),
            service.evidence.text_event_count.load(std::memory_order_acquire),
            service.evidence.text_insert_event.load(std::memory_order_acquire),
            service.evidence.text_delete_event.load(std::memory_order_acquire),
            service.evidence.text_replacement_delete_event.load(
                std::memory_order_acquire
            ),
            service.evidence.text_replacement_insert_event.load(
                std::memory_order_acquire
            ),
            service.evidence.caret_event.load(std::memory_order_acquire),
            service.evidence.caret_event_count.load(std::memory_order_acquire),
            service.evidence.selection_event.load(std::memory_order_acquire),
            service.evidence.selection_event_count.load(std::memory_order_acquire),
            closed
        );
    }
    service.stop();
    g_test_dbus_down(bus);
    g_object_unref(bus);
    return published && closed ? 0 : 2;
}

}

int main() {
    return runTest();
}
