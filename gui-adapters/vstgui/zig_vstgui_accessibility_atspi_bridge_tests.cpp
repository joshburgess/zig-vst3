#include "zig_vstgui_accessibility_bridge.h"

#include "vstgui/lib/cframe.h"
#include "vstgui/lib/cview.h"
#include "vstgui/lib/vstguibase.h"

#include <gio/gio.h>

#include <atomic>
#include <chrono>
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
};

bool callSucceeded(GVariant* result, GError* error) {
    if (result) {
        g_variant_unref(result);
        return true;
    }
    if (error) g_error_free(error);
    return false;
}

void inspectApplication(
    GDBusConnection* connection,
    const char* application,
    const char* root,
    Evidence& evidence
) {
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
            path == "/org/a11y/atspi/accessible/control_0",
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
        evidence.child_role.store(role == 51, std::memory_order_release);
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
        evidence.child_interfaces.store(
            g_variant_n_children(interfaces) == 1,
            std::memory_order_release
        );
        g_variant_unref(interfaces);
        g_variant_unref(result);
    } else if (error) {
        g_error_free(error);
    }
}

struct Service {
    std::string address;
    Evidence evidence;
    std::mutex mutex;
    std::condition_variable condition;
    bool ready {false};
    bool valid {false};
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
        if (node && requestName(connection, bus_name) &&
            requestName(connection, registry_name)) {
            auto* bus_info = g_dbus_node_info_lookup_interface(node, bus_name);
            auto* registry_info = g_dbus_node_info_lookup_interface(
                node,
                "org.a11y.atspi.Socket"
            );
            bus_registration = g_dbus_connection_register_object(
                connection,
                bus_path,
                bus_info,
                &vtable,
                this,
                nullptr,
                &error
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
        {
            std::lock_guard<std::mutex> lock(mutex);
            valid = bus_registration != 0 && registry_registration != 0;
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

    bool start(const char* bus_address) {
        address = bus_address;
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
    void*,
    const ZigVstgui::AccessibilityNode&,
    const ZigVstgui::AccessibilityActionRequest&
) {
    return true;
}

int runTest() {
    g_setenv("ZIG_VSTGUI_DIAGNOSTICS", "1", true);
    GTestDBus* bus = g_test_dbus_new(G_TEST_DBUS_NONE);
    g_test_dbus_up(bus);
    Service service;
    if (!service.start(g_test_dbus_get_bus_address(bus))) {
        service.stop();
        g_test_dbus_down(bus);
        g_object_unref(bus);
        return 1;
    }

    ZigVstgui::AccessibilityNode node;
    node.setRole(ZigVstgui::AccessibilityRole::slider);
    node.setName("Gain");
    node.setDescription("Output level");
    node.setRange(0.0, 1.0, 0.5);
    node.setActionHandler(
        nullptr,
        perform,
        static_cast<uint32_t>(ZigVstgui::AccessibilityAction::focus) |
            static_cast<uint32_t>(ZigVstgui::AccessibilityAction::set_value)
    );
    auto frame = VSTGUI::owned(new VSTGUI::CFrame(
        VSTGUI::CRect(0, 0, 640, 480),
        nullptr
    ));
    auto view = VSTGUI::owned(new VSTGUI::CView(
        VSTGUI::CRect(10, 20, 110, 60)
    ));
    view->setWantsFocus(true);
    ZigVstgui::NativeAccessibilityBridge bridge;
    const bool opened = bridge.open(
        frame.get(),
        {{&node, view.get()}}
    );
    const bool active = bridge.active();
    const std::size_t element_count = bridge.elementCount();
    const bool published = opened && active &&
        element_count == 1 &&
        service.evidence.embedded.load(std::memory_order_acquire) &&
        service.evidence.id_set.load(std::memory_order_acquire) &&
        service.evidence.root_role.load(std::memory_order_acquire) &&
        service.evidence.child_found.load(std::memory_order_acquire) &&
        service.evidence.child_name.load(std::memory_order_acquire) &&
        service.evidence.child_role.load(std::memory_order_acquire) &&
        service.evidence.child_interfaces.load(std::memory_order_acquire);
    bridge.close();
    const bool closed = !bridge.active() && bridge.elementCount() == 0;
    if (!published || !closed) {
        std::fprintf(
            stderr,
            "AT-SPI bridge evidence: opened=%d active=%d count=%zu "
            "embedded=%d id=%d root-role=%d child=%d name=%d role=%d "
            "interfaces=%d closed=%d\n",
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
