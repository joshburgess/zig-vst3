#include "zig_vstgui_accessibility_bridge.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cview.h"
#include "vstgui/lib/vstguibase.h"

#include <gio/gio.h>

#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

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
constexpr int timeout_ms = 2000;

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
    std::atomic<unsigned int> event_count {0};
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
        bool value = false;
        GVariantIter interface_iterator;
        g_variant_iter_init(&interface_iterator, interfaces);
        const char* interface = nullptr;
        while (g_variant_iter_next(&interface_iterator, "&s", &interface)) {
            accessible |= std::strcmp(interface, "Accessible") == 0;
            action |= std::strcmp(interface, "Action") == 0;
            component |= std::strcmp(interface, "Component") == 0;
            editable_text |= std::strcmp(interface, "EditableText") == 0;
            value |= std::strcmp(interface, "Value") == 0;
        }
        evidence.child_interfaces.store(
            accessible && action && component && editable_text && value,
            std::memory_order_release
        );
        evidence.editable_interface.store(
            editable_text,
            std::memory_order_release
        );
        g_variant_unref(interfaces);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }

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
            g_variant_n_children(items) == 2,
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
    evidence.hostile_inputs_rejected.store(
        hostile_rejected &&
            evidence.action_call_count.load(std::memory_order_acquire) ==
                calls_before_hostile,
        std::memory_order_release
    );
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
    g_setenv("ZIG_VSTGUI_DIAGNOSTICS", "1", true);
    GTestDBus* bus = g_test_dbus_new(G_TEST_DBUS_NONE);
    g_test_dbus_up(bus);
    Service service;
    ZigVstgui::AccessibilityNode node;
    node.setRole(ZigVstgui::AccessibilityRole::text_field);
    node.setName("Gain");
    node.setDescription("Output level");
    node.setValueText("AéB");
    node.setRange(0.0, 1.0, 0.5);
    node.setActionHandler(
        &service.evidence,
        perform,
        static_cast<uint32_t>(ZigVstgui::AccessibilityAction::focus) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::press) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_value)
    );
    auto frame = VSTGUI::owned(new VSTGUI::CFrame(
        VSTGUI::CRect(0, 0, 640, 480),
        nullptr
    ));
    auto* view = new VSTGUI::CView(
        VSTGUI::CRect(10, 20, 110, 60)
    );
    frame->addView(view);
    view->setWantsFocus(true);
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
        {{&node, view}},
        clipboard
    );
    const bool active = bridge.active();
    const std::size_t element_count = bridge.elementCount();
    node.setName("Output gain field");
    node.setFocused(true);
    bridge.layoutChanged();
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (service.evidence.property_event.load(std::memory_order_acquire) &&
            service.evidence.focus_event.load(std::memory_order_acquire) &&
            service.evidence.bounds_event.load(std::memory_order_acquire) &&
            service.evidence.event_count.load(std::memory_order_acquire) == 3 &&
            service.evidence.cache_add_count.load(std::memory_order_acquire) == 2) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    const bool published = missing_bus_safe && missing_registry_safe &&
        opened && active &&
        element_count == 1 &&
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
        service.evidence.cache_add_count.load(std::memory_order_acquire) == 2 &&
        service.evidence.hostile_inputs_rejected.load(std::memory_order_acquire) &&
        service.evidence.property_event.load(std::memory_order_acquire) &&
        service.evidence.focus_event.load(std::memory_order_acquire) &&
        service.evidence.bounds_event.load(std::memory_order_acquire);
    const auto events_before_close = service.evidence.event_count.load(
        std::memory_order_acquire
    );
    bridge.close();
    node.setName("Detached node");
    for (int attempt = 0; attempt < 100; ++attempt) {
        if (service.evidence.cache_remove_count.load(std::memory_order_acquire) == 2)
            break;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    const bool closed = !bridge.active() && bridge.elementCount() == 0 &&
        events_before_close == 3 &&
        service.evidence.event_count.load(std::memory_order_acquire) ==
            events_before_close &&
        service.evidence.cache_root_removed.load(std::memory_order_acquire) &&
        service.evidence.cache_child_removed.load(std::memory_order_acquire) &&
        service.evidence.cache_remove_count.load(std::memory_order_acquire) == 2;
    if (!published || !closed) {
        std::fprintf(
            stderr,
            "AT-SPI bridge evidence: missing-bus=%d missing-registry=%d "
            "opened=%d active=%d count=%zu "
            "embedded=%d id=%d root-role=%d child=%d name=%d role=%d "
            "interfaces=%d bounds=%d action-count=%d action=%d "
            "value-read=%d value-set=%d editable=%d text-set=%d insert=%d "
            "delete=%d paste=%d ab-updates=%u clipboard-writes=%u clipboard-reads=%u "
            "clipboard-methods=%d "
            "cache=%d cache-root-add=%d cache-child-add=%d "
            "cache-add-count=%u cache-root-remove=%d cache-child-remove=%d "
            "cache-remove-count=%u hostile-inputs=%d action-calls=%u "
            "property-event=%d focus-event=%d "
            "bounds-event=%d closed=%d\n",
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
            service.evidence.property_event.load(std::memory_order_acquire),
            service.evidence.focus_event.load(std::memory_order_acquire),
            service.evidence.bounds_event.load(std::memory_order_acquire),
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
