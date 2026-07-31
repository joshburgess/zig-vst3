#include "zig_vstgui_accessibility_bridge.h"

#if (!defined(__APPLE__) && !defined(_WIN32)) || \
    defined(ZIG_VSTGUI_TEST_ATSPI_TRANSPORT)

#if defined(__linux__) || defined(ZIG_VSTGUI_TEST_ATSPI_TRANSPORT)

#include "zig_vstgui_accessibility_atspi.h"

#include "vstgui/lib/platform/iplatformframe.h"

#include <gio/gio.h>

#include <algorithm>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace ZigVstgui {

namespace {

constexpr const char* root_path = "/org/a11y/atspi/accessible/root";
constexpr const char* cache_path = "/org/a11y/atspi/cache";
constexpr const char* null_path = "/org/a11y/atspi/null";
constexpr const char* accessible_interface = "org.a11y.atspi.Accessible";
constexpr const char* application_interface = "org.a11y.atspi.Application";
constexpr const char* cache_interface = "org.a11y.atspi.Cache";
constexpr const char* action_interface = "org.a11y.atspi.Action";
constexpr const char* component_interface = "org.a11y.atspi.Component";
constexpr const char* editable_text_interface = "org.a11y.atspi.EditableText";
constexpr const char* object_event_interface = "org.a11y.atspi.Event.Object";
constexpr const char* value_interface = "org.a11y.atspi.Value";
constexpr const char* registry_name = "org.a11y.atspi.Registry";
constexpr const char* registry_path = "/org/a11y/atspi/registry";
constexpr const char* socket_interface = "org.a11y.atspi.Socket";
constexpr int bus_call_timeout_ms = 1000;
constexpr unsigned int maximum_dispatches_per_tick = 32;

constexpr const char* introspection_xml = R"xml(
<node>
  <interface name='org.a11y.atspi.Accessible'>
    <property name='version' type='u' access='read'/>
    <property name='Name' type='s' access='read'/>
    <property name='Description' type='s' access='read'/>
    <property name='Parent' type='(so)' access='read'/>
    <property name='ChildCount' type='i' access='read'/>
    <property name='Locale' type='s' access='read'/>
    <property name='AccessibleId' type='s' access='read'/>
    <property name='HelpText' type='s' access='read'/>
    <method name='GetChildAtIndex'>
      <arg direction='in' name='index' type='i'/>
      <arg direction='out' type='(so)'/>
    </method>
    <method name='GetChildren'>
      <arg direction='out' type='a(so)'/>
    </method>
    <method name='GetIndexInParent'>
      <arg direction='out' type='i'/>
    </method>
    <method name='GetRelationSet'>
      <arg direction='out' type='a(ua(so))'/>
    </method>
    <method name='GetRole'>
      <arg direction='out' type='u'/>
    </method>
    <method name='GetRoleName'>
      <arg direction='out' type='s'/>
    </method>
    <method name='GetLocalizedRoleName'>
      <arg direction='out' type='s'/>
    </method>
    <method name='GetState'>
      <arg direction='out' type='au'/>
    </method>
    <method name='GetAttributes'>
      <arg direction='out' type='a{ss}'/>
    </method>
    <method name='GetApplication'>
      <arg direction='out' type='(so)'/>
    </method>
    <method name='GetInterfaces'>
      <arg direction='out' type='as'/>
    </method>
  </interface>
  <interface name='org.a11y.atspi.Application'>
    <property name='ToolkitName' type='s' access='read'/>
    <property name='Version' type='s' access='read'/>
    <property name='ToolkitVersion' type='s' access='read'/>
    <property name='AtspiVersion' type='s' access='read'/>
    <property name='InterfaceVersion' type='u' access='read'/>
    <property name='Id' type='i' access='readwrite'/>
    <method name='GetLocale'>
      <arg direction='in' name='lctype' type='u'/>
      <arg direction='out' type='s'/>
    </method>
    <method name='GetApplicationBusAddress'>
      <arg direction='out' type='s'/>
    </method>
  </interface>
  <interface name='org.a11y.atspi.Action'>
    <property name='version' type='u' access='read'/>
    <property name='NActions' type='i' access='read'/>
    <method name='GetDescription'><arg direction='in' type='i'/><arg direction='out' type='s'/></method>
    <method name='GetName'><arg direction='in' type='i'/><arg direction='out' type='s'/></method>
    <method name='GetLocalizedName'><arg direction='in' type='i'/><arg direction='out' type='s'/></method>
    <method name='GetKeyBinding'><arg direction='in' type='i'/><arg direction='out' type='s'/></method>
    <method name='GetActions'><arg direction='out' type='a(sss)'/></method>
    <method name='DoAction'><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
  </interface>
  <interface name='org.a11y.atspi.Component'>
    <property name='version' type='u' access='read'/>
    <method name='Contains'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='u'/><arg direction='out' type='b'/></method>
    <method name='GetAccessibleAtPoint'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='u'/><arg direction='out' type='(so)'/></method>
    <method name='GetExtents'><arg direction='in' type='u'/><arg direction='out' type='(iiii)'/></method>
    <method name='GetPosition'><arg direction='in' type='u'/><arg direction='out' type='i'/><arg direction='out' type='i'/></method>
    <method name='GetSize'><arg direction='out' type='i'/><arg direction='out' type='i'/></method>
    <method name='GetLayer'><arg direction='out' type='u'/></method>
    <method name='GetMDIZOrder'><arg direction='out' type='n'/></method>
    <method name='GrabFocus'><arg direction='out' type='b'/></method>
    <method name='GetAlpha'><arg direction='out' type='d'/></method>
    <method name='SetExtents'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='u'/><arg direction='out' type='b'/></method>
    <method name='SetPosition'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='in' type='u'/><arg direction='out' type='b'/></method>
    <method name='SetSize'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
    <method name='ScrollTo'><arg direction='in' type='u'/><arg direction='out' type='b'/></method>
    <method name='ScrollToPoint'><arg direction='in' type='u'/><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
  </interface>
  <interface name='org.a11y.atspi.Value'>
    <property name='version' type='u' access='read'/>
    <property name='MinimumValue' type='d' access='read'/>
    <property name='MaximumValue' type='d' access='read'/>
    <property name='MinimumIncrement' type='d' access='read'/>
    <property name='CurrentValue' type='d' access='readwrite'/>
    <property name='Text' type='s' access='read'/>
  </interface>
  <interface name='org.a11y.atspi.EditableText'>
    <property name='version' type='u' access='read'/>
    <method name='SetTextContents'><arg direction='in' type='s'/><arg direction='out' type='b'/></method>
    <method name='InsertText'><arg direction='in' type='i'/><arg direction='in' type='s'/><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
    <method name='CopyText'><arg direction='in' type='i'/><arg direction='in' type='i'/></method>
    <method name='CutText'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
    <method name='DeleteText'><arg direction='in' type='i'/><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
    <method name='PasteText'><arg direction='in' type='i'/><arg direction='out' type='b'/></method>
  </interface>
  <interface name='org.a11y.atspi.Cache'>
    <property name='version' type='u' access='read'/>
    <method name='GetItems'><arg direction='out' type='a((so)(so)(so)iiassusau)'/></method>
    <signal name='AddAccessible'><arg type='((so)(so)(so)iiassusau)'/></signal>
    <signal name='RemoveAccessible'><arg type='(so)'/></signal>
  </interface>
  <interface name='org.a11y.atspi.Event.Object'>
    <property name='version' type='u' access='read'/>
    <signal name='PropertyChange'><arg type='s'/><arg type='i'/><arg type='i'/><arg type='v'/><arg type='a{sv}'/></signal>
    <signal name='BoundsChanged'><arg type='s'/><arg type='i'/><arg type='i'/><arg type='v'/><arg type='a{sv}'/></signal>
    <signal name='StateChanged'><arg type='s'/><arg type='i'/><arg type='i'/><arg type='v'/><arg type='a{sv}'/></signal>
  </interface>
</node>
)xml";

const char* localeName() {
    const char* value = std::setlocale(LC_MESSAGES, nullptr);
    return value ? value : "C";
}

const char* roleName(AtspiRole role) {
    switch (role) {
        case AtspiRole::combo_box: return "combo box";
        case AtspiRole::panel: return "panel";
        case AtspiRole::progress_bar: return "progress bar";
        case AtspiRole::push_button: return "push button";
        case AtspiRole::slider: return "slider";
        case AtspiRole::toggle_button: return "toggle button";
        case AtspiRole::entry: return "entry";
        case AtspiRole::chart: return "chart";
    }
    return "panel";
}

std::string childPath(std::size_t index) {
    char storage[80] {};
    const int length = std::snprintf(
        storage,
        sizeof(storage),
        "/org/a11y/atspi/accessible/control_%zu",
        index
    );
    if (length <= 0 || static_cast<std::size_t>(length) >= sizeof(storage)) return {};
    return storage;
}

void returnError(GDBusMethodInvocation* invocation, const char* message) {
    g_dbus_method_invocation_return_error_literal(
        invocation,
        G_DBUS_ERROR,
        G_DBUS_ERROR_INVALID_ARGS,
        message
    );
}

void diagnostic(const char* stage, const GError* error = nullptr) {
    if (!std::getenv("ZIG_VSTGUI_DIAGNOSTICS")) return;
    std::fprintf(
        stderr,
        "AT-SPI bridge %s%s%s\n",
        stage,
        error ? ": " : "",
        error ? error->message : ""
    );
}

}

class NativeAccessibilityBridge::Impl {
public:
    struct Object {
        Impl* owner {nullptr};
        std::size_t index {0};
        bool root {false};
        bool cache {false};
        std::string path;
    };

    struct Observer {
        Impl* owner {nullptr};
        const AccessibilityNode* node {nullptr};
        Object* object {nullptr};
    };

    ~Impl() {
        shutdown();
    }

    bool initialize(
        VSTGUI::CFrame* source_frame,
        const std::vector<AccessibilityEntry>& source_entries
    ) {
        if (!source_frame) return false;
        frame = source_frame;
        for (const auto& entry : source_entries) {
            if (entry.node && entry.view) entries.push_back(entry);
        }

        GError* error = nullptr;
        introspection = g_dbus_node_info_new_for_xml(introspection_xml, &error);
        if (!introspection) {
            diagnostic("could not parse interface definitions", error);
            if (error) g_error_free(error);
            return false;
        }

        const std::string address = accessibilityBusAddress();
        if (address.empty()) {
            diagnostic("accessibility bus is unavailable");
            return false;
        }
        connection = g_dbus_connection_new_for_address_sync(
            address.c_str(),
            static_cast<GDBusConnectionFlags>(
                G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION
            ),
            nullptr,
            nullptr,
            &error
        );
        if (!connection) {
            diagnostic("could not connect to the accessibility bus", error);
            if (error) g_error_free(error);
            return false;
        }
        g_dbus_connection_set_exit_on_close(connection, false);
        const char* unique = g_dbus_connection_get_unique_name(connection);
        if (!unique || unique[0] == '\0') {
            diagnostic("accessibility bus did not assign a unique name");
            return false;
        }
        bus_name = unique;

        if (!registerObjects()) {
            diagnostic("could not publish the accessible object tree");
            return false;
        }
        if (!embed()) {
            diagnostic("registry embedding failed");
            return false;
        }
        installObservers();
        ready = true;
        return true;
    }

    void shutdown() {
        ready = false;
        for (const auto& observer : observers) {
            if (observer->node) observer->node->setObserver(nullptr, nullptr);
        }
        observers.clear();
        if (connection) {
            for (auto registration = registrations.rbegin();
                 registration != registrations.rend(); ++registration) {
                g_dbus_connection_unregister_object(connection, *registration);
            }
        }
        registrations.clear();
        objects.clear();
        if (connection) {
            g_object_unref(connection);
            connection = nullptr;
        }
        if (introspection) {
            g_dbus_node_info_unref(introspection);
            introspection = nullptr;
        }
        entries.clear();
        frame = nullptr;
        bus_name.clear();
        registry_bus.clear();
        registry_root.clear();
    }

    void dispatch() {
        if (!ready) return;
        auto* context = g_main_context_default();
        for (unsigned int count = 0;
             count < maximum_dispatches_per_tick &&
             g_main_context_pending(context);
             ++count) {
            g_main_context_iteration(context, false);
        }
    }

    void layoutChanged() {
        if (!ready) return;
        emitBoundsChanged(*objects[0]);
        for (std::size_t index = 0; index < entries.size(); ++index)
            emitBoundsChanged(*objects[index + 1]);
    }

    std::size_t elementCount() const {
        return entries.size();
    }

private:
    static void methodCall(
        GDBusConnection*,
        const gchar*,
        const gchar*,
        const gchar* interface_name,
        const gchar* method_name,
        GVariant* parameters,
        GDBusMethodInvocation* invocation,
        gpointer userdata
    ) {
        auto* object = static_cast<Object*>(userdata);
        if (!object || !object->owner) {
            returnError(invocation, "Accessibility object is unavailable");
            return;
        }
        if (g_strcmp0(interface_name, accessible_interface) == 0) {
            object->owner->accessibleMethod(*object, method_name, parameters, invocation);
            return;
        }
        if (object->root && g_strcmp0(interface_name, application_interface) == 0) {
            object->owner->applicationMethod(method_name, invocation);
            return;
        }
        if (g_strcmp0(interface_name, action_interface) == 0) {
            object->owner->actionMethod(*object, method_name, parameters, invocation);
            return;
        }
        if (g_strcmp0(interface_name, component_interface) == 0) {
            object->owner->componentMethod(*object, method_name, parameters, invocation);
            return;
        }
        if (g_strcmp0(interface_name, editable_text_interface) == 0) {
            object->owner->editableTextMethod(*object, method_name, parameters, invocation);
            return;
        }
        if (object->cache && g_strcmp0(interface_name, cache_interface) == 0) {
            object->owner->cacheMethod(method_name, invocation);
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown accessibility method"
        );
    }

    static GVariant* getProperty(
        GDBusConnection*,
        const gchar*,
        const gchar*,
        const gchar* interface_name,
        const gchar* property_name,
        GError**,
        gpointer userdata
    ) {
        auto* object = static_cast<Object*>(userdata);
        if (!object || !object->owner) return nullptr;
        if (g_strcmp0(interface_name, accessible_interface) == 0)
            return object->owner->accessibleProperty(*object, property_name);
        if (object->root && g_strcmp0(interface_name, application_interface) == 0)
            return object->owner->applicationProperty(property_name);
        if (g_strcmp0(interface_name, action_interface) == 0)
            return object->owner->actionProperty(*object, property_name);
        if (g_strcmp0(interface_name, component_interface) == 0)
            return object->owner->versionProperty(property_name);
        if (g_strcmp0(interface_name, editable_text_interface) == 0)
            return object->owner->versionProperty(property_name);
        if (object->cache && g_strcmp0(interface_name, cache_interface) == 0)
            return object->owner->versionProperty(property_name);
        if (g_strcmp0(interface_name, object_event_interface) == 0)
            return object->owner->versionProperty(property_name);
        if (g_strcmp0(interface_name, value_interface) == 0)
            return object->owner->valueProperty(*object, property_name);
        return nullptr;
    }

    static gboolean setProperty(
        GDBusConnection*,
        const gchar*,
        const gchar*,
        const gchar* interface_name,
        const gchar* property_name,
        GVariant* value,
        GError** error,
        gpointer userdata
    ) {
        auto* object = static_cast<Object*>(userdata);
        if (object && object->owner && !object->root &&
            g_strcmp0(interface_name, value_interface) == 0 &&
            g_strcmp0(property_name, "CurrentValue") == 0 &&
            g_variant_is_of_type(value, G_VARIANT_TYPE_DOUBLE)) {
            const auto* current = object->owner->entry(*object);
            if (current && AtspiNodeAdapter(current->node)
                .setCurrentValue(g_variant_get_double(value))) return true;
            g_set_error_literal(
                error,
                G_DBUS_ERROR,
                G_DBUS_ERROR_FAILED,
                "Accessibility value was rejected"
            );
            return false;
        }
        if (!object || !object->owner || !object->root ||
            g_strcmp0(interface_name, application_interface) != 0 ||
            g_strcmp0(property_name, "Id") != 0 ||
            !g_variant_is_of_type(value, G_VARIANT_TYPE_INT32)) {
            g_set_error_literal(
                error,
                G_DBUS_ERROR,
                G_DBUS_ERROR_INVALID_ARGS,
                "Invalid accessibility property"
            );
            return false;
        }
        object->owner->application_id = g_variant_get_int32(value);
        return true;
    }

    inline static const GDBusInterfaceVTable interface_vtable {
        methodCall,
        getProperty,
        setProperty,
        {nullptr},
    };

    std::string accessibilityBusAddress() {
        GError* error = nullptr;
        GDBusConnection* session = g_bus_get_sync(
            G_BUS_TYPE_SESSION,
            nullptr,
            &error
        );
        if (!session) {
            diagnostic("session bus is unavailable", error);
            if (error) g_error_free(error);
            return {};
        }
        GVariant* reply = g_dbus_connection_call_sync(
            session,
            "org.a11y.Bus",
            "/org/a11y/bus",
            "org.a11y.Bus",
            "GetAddress",
            nullptr,
            G_VARIANT_TYPE("(s)"),
            G_DBUS_CALL_FLAGS_NO_AUTO_START,
            bus_call_timeout_ms,
            nullptr,
            &error
        );
        g_object_unref(session);
        if (!reply) {
            diagnostic("could not read the accessibility bus address", error);
            if (error) g_error_free(error);
            return {};
        }
        const char* address = nullptr;
        g_variant_get(reply, "(&s)", &address);
        std::string result = address ? address : "";
        g_variant_unref(reply);
        return result;
    }

    GDBusInterfaceInfo* interfaceInfo(const char* name) const {
        return introspection
            ? g_dbus_node_info_lookup_interface(introspection, name)
            : nullptr;
    }

    bool registerInterface(Object* object, const char* name) {
        auto* info = interfaceInfo(name);
        if (!object || !info) return false;
        GError* error = nullptr;
        const guint registration = g_dbus_connection_register_object(
            connection,
            object->path.c_str(),
            info,
            &interface_vtable,
            object,
            nullptr,
            &error
        );
        if (registration == 0) {
            diagnostic("object registration failed", error);
            if (error) g_error_free(error);
            return false;
        }
        registrations.push_back(registration);
        return true;
    }

    bool registerObjects() {
        auto root = std::make_unique<Object>();
        root->owner = this;
        root->root = true;
        root->path = root_path;
        Object* root_object = root.get();
        objects.push_back(std::move(root));
        if (!registerInterface(root_object, accessible_interface) ||
            !registerInterface(root_object, application_interface) ||
            !registerInterface(root_object, component_interface) ||
            !registerInterface(root_object, object_event_interface)) return false;

        for (std::size_t index = 0; index < entries.size(); ++index) {
            auto object = std::make_unique<Object>();
            object->owner = this;
            object->index = index;
            object->path = childPath(index);
            if (object->path.empty()) return false;
            Object* child = object.get();
            objects.push_back(std::move(object));
            if (!registerInterface(child, accessible_interface) ||
                !registerInterface(child, component_interface) ||
                !registerInterface(child, object_event_interface)) return false;
            const auto current = snapshot(*child);
            if (current.hasInterface(AtspiInterface::action) &&
                !registerInterface(child, action_interface)) return false;
            if (current.hasInterface(AtspiInterface::value) &&
                !registerInterface(child, value_interface)) return false;
            if (current.hasInterface(AtspiInterface::editable_text) &&
                !registerInterface(child, editable_text_interface)) return false;
        }
        auto cache = std::make_unique<Object>();
        cache->owner = this;
        cache->cache = true;
        cache->path = cache_path;
        Object* cache_object = cache.get();
        objects.push_back(std::move(cache));
        if (!registerInterface(cache_object, cache_interface)) return false;
        return true;
    }

    struct EmbedResult {
        GMainLoop* loop {nullptr};
        std::string bus;
        std::string path;
    };

    static void embedFinished(
        GObject* source,
        GAsyncResult* async_result,
        gpointer userdata
    ) {
        auto* result = static_cast<EmbedResult*>(userdata);
        GError* error = nullptr;
        GVariant* reply = g_dbus_connection_call_finish(
            G_DBUS_CONNECTION(source),
            async_result,
            &error
        );
        if (reply) {
            const char* socket_bus = nullptr;
            const char* socket_path = nullptr;
            g_variant_get(reply, "((&s&o))", &socket_bus, &socket_path);
            result->bus = socket_bus ? socket_bus : "";
            result->path = socket_path ? socket_path : "";
            g_variant_unref(reply);
        } else if (error) {
            diagnostic("registry Embed call failed", error);
            g_error_free(error);
        }
        if (result->loop) g_main_loop_quit(result->loop);
    }

    bool embed() {
        EmbedResult result;
        result.loop = g_main_loop_new(g_main_context_default(), false);
        if (!result.loop) return false;
        g_dbus_connection_call(
            connection,
            registry_name,
            registry_path,
            socket_interface,
            "Embed",
            g_variant_new("((so))", bus_name.c_str(), root_path),
            G_VARIANT_TYPE("((so))"),
            G_DBUS_CALL_FLAGS_NO_AUTO_START,
            bus_call_timeout_ms,
            nullptr,
            embedFinished,
            &result
        );
        g_main_loop_run(result.loop);
        g_main_loop_unref(result.loop);
        registry_bus = std::move(result.bus);
        registry_root = std::move(result.path);
        return !registry_root.empty();
    }

    const AccessibilityEntry* entry(const Object& object) const {
        if (object.root || object.index >= entries.size()) return nullptr;
        return &entries[object.index];
    }

    AtspiSnapshot snapshot(const Object& object) const {
        const auto* current = entry(object);
        if (!current) return {};
        const bool visible = current->view->isVisible();
        return AtspiNodeAdapter(current->node).snapshot(
            current->view->wantsFocus(),
            visible,
            visible
        );
    }

    const char* objectBus(const Object& object) const {
        if (object.root) {
            return registry_bus.empty() ? "" : registry_bus.c_str();
        }
        return bus_name.c_str();
    }

    const char* objectParentPath(const Object& object) const {
        if (object.root) {
            return registry_root.empty() ? null_path : registry_root.c_str();
        }
        return root_path;
    }

    struct Bounds {
        gint32 x {0};
        gint32 y {0};
        gint32 width {0};
        gint32 height {0};
    };

    static gint32 coordinate(double value) {
        if (value <= static_cast<double>(G_MININT32)) return G_MININT32;
        if (value >= static_cast<double>(G_MAXINT32)) return G_MAXINT32;
        return static_cast<gint32>(std::lround(value));
    }

    Bounds bounds(const Object& object, guint32 coordinate_type) const {
        VSTGUI::CRect rectangle;
        if (object.root) {
            rectangle = frame->getViewSize();
        } else {
            const auto* current = entry(object);
            if (!current) return {};
            rectangle = current->view->getViewSize();
            current->view->translateToGlobal(rectangle, true);
        }
        if (coordinate_type == 0 && frame->getPlatformFrame()) {
            VSTGUI::CPoint origin;
            if (frame->getPlatformFrame()->getGlobalPosition(origin))
                rectangle.offset(origin.x, origin.y);
        }
        return {
            coordinate(rectangle.left),
            coordinate(rectangle.top),
            coordinate(rectangle.getWidth()),
            coordinate(rectangle.getHeight()),
        };
    }

    static bool contains(const Bounds& bounds, gint32 x, gint32 y) {
        const gint64 right = static_cast<gint64>(bounds.x) + bounds.width;
        const gint64 bottom = static_cast<gint64>(bounds.y) + bounds.height;
        return x >= bounds.x && y >= bounds.y && x < right && y < bottom;
    }

    GVariant* versionProperty(const char* property) const {
        return g_strcmp0(property, "version") == 0
            ? g_variant_new_uint32(1)
            : nullptr;
    }

    void appendInterfaces(GVariantBuilder& builder, const Object& object) const {
        g_variant_builder_add(&builder, "s", "Accessible");
        g_variant_builder_add(&builder, "s", "Component");
        if (object.root) {
            g_variant_builder_add(&builder, "s", "Application");
            return;
        }
        const auto current = snapshot(object);
        if (current.hasInterface(AtspiInterface::action))
            g_variant_builder_add(&builder, "s", "Action");
        if (current.hasInterface(AtspiInterface::value))
            g_variant_builder_add(&builder, "s", "Value");
        if (current.hasInterface(AtspiInterface::editable_text))
            g_variant_builder_add(&builder, "s", "EditableText");
    }

    void appendCacheItem(GVariantBuilder& builder, const Object& object) const {
        const auto current = snapshot(object);
        g_variant_builder_open(
            &builder,
            G_VARIANT_TYPE("((so)(so)(so)iiassusau)")
        );
        g_variant_builder_add(&builder, "(so)", bus_name.c_str(), object.path.c_str());
        g_variant_builder_add(&builder, "(so)", bus_name.c_str(), root_path);
        g_variant_builder_add(
            &builder,
            "(so)",
            objectBus(object),
            objectParentPath(object)
        );
        g_variant_builder_add(
            &builder,
            "i",
            object.root ? -1 : static_cast<gint32>(object.index)
        );
        g_variant_builder_add(
            &builder,
            "i",
            object.root ? static_cast<gint32>(entries.size()) : 0
        );
        g_variant_builder_open(&builder, G_VARIANT_TYPE("as"));
        appendInterfaces(builder, object);
        g_variant_builder_close(&builder);
        g_variant_builder_add(
            &builder,
            "s",
            object.root ? "Plugin editor" : current.name.c_str()
        );
        g_variant_builder_add(
            &builder,
            "u",
            object.root ? 75u : static_cast<guint32>(current.role)
        );
        g_variant_builder_add(
            &builder,
            "s",
            object.root ? "" : current.description.c_str()
        );
        g_variant_builder_open(&builder, G_VARIANT_TYPE("au"));
        g_variant_builder_add(&builder, "u", current.states[0]);
        g_variant_builder_add(&builder, "u", current.states[1]);
        g_variant_builder_close(&builder);
        g_variant_builder_close(&builder);
    }

    void cacheMethod(
        const char* method,
        GDBusMethodInvocation* invocation
    ) const {
        if (g_strcmp0(method, "GetItems") != 0) {
            g_dbus_method_invocation_return_error_literal(
                invocation,
                G_DBUS_ERROR,
                G_DBUS_ERROR_UNKNOWN_METHOD,
                "Unknown accessibility cache method"
            );
            return;
        }
        GVariantBuilder builder;
        g_variant_builder_init(
            &builder,
            G_VARIANT_TYPE("a((so)(so)(so)iiassusau)")
        );
        appendCacheItem(builder, *objects[0]);
        for (std::size_t index = 0; index < entries.size(); ++index)
            appendCacheItem(builder, *objects[index + 1]);
        g_dbus_method_invocation_return_value(
            invocation,
            g_variant_new(
                "(@a((so)(so)(so)iiassusau))",
                g_variant_builder_end(&builder)
            )
        );
    }

    static GVariant* emptyEventProperties() {
        GVariantBuilder builder;
        g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
        return g_variant_builder_end(&builder);
    }

    void emitObjectSignal(
        const Object& object,
        const char* signal,
        const char* detail,
        gint32 detail1,
        gint32 detail2,
        GVariant* value
    ) const {
        if (!connection || !value) return;
        GError* error = nullptr;
        if (!g_dbus_connection_emit_signal(
                connection,
                nullptr,
                object.path.c_str(),
                object_event_interface,
                signal,
                g_variant_new(
                    "(siiv@a{sv})",
                    detail,
                    detail1,
                    detail2,
                    value,
                    emptyEventProperties()
                ),
                &error
            )) {
            diagnostic("could not publish an accessibility event", error);
            if (error) g_error_free(error);
        }
    }

    void emitPropertyChange(
        const Object& object,
        const char* property,
        GVariant* value
    ) const {
        emitObjectSignal(object, "PropertyChange", property, 0, 0, value);
    }

    void emitStateChange(
        const Object& object,
        const char* state,
        bool enabled
    ) const {
        emitObjectSignal(
            object,
            "StateChanged",
            state,
            enabled ? 1 : 0,
            0,
            g_variant_new_int32(0)
        );
    }

    void emitBoundsChanged(const Object& object) const {
        const auto area = bounds(object, 0);
        emitObjectSignal(
            object,
            "BoundsChanged",
            "",
            0,
            0,
            g_variant_new("(iiii)", area.x, area.y, area.width, area.height)
        );
    }

    void nodeChanged(const Object& object, AccessibilityChange change) const {
        const auto current = snapshot(object);
        switch (change) {
            case AccessibilityChange::role:
                emitPropertyChange(
                    object,
                    "accessible-role",
                    g_variant_new_uint32(static_cast<guint32>(current.role))
                );
                break;
            case AccessibilityChange::name:
                emitPropertyChange(
                    object,
                    "accessible-name",
                    g_variant_new_string(current.name.c_str())
                );
                break;
            case AccessibilityChange::description:
                emitPropertyChange(
                    object,
                    "accessible-description",
                    g_variant_new_string(current.description.c_str())
                );
                break;
            case AccessibilityChange::value:
                emitPropertyChange(
                    object,
                    "accessible-value",
                    g_variant_new_string(current.value_text.c_str())
                );
                break;
            case AccessibilityChange::range:
                emitPropertyChange(
                    object,
                    "accessible-value",
                    g_variant_new_double(current.range.current)
                );
                break;
            case AccessibilityChange::state:
                emitStateChange(
                    object,
                    "enabled",
                    current.hasState(AtspiState::enabled)
                );
                emitStateChange(
                    object,
                    "checked",
                    current.hasState(AtspiState::checked)
                );
                emitStateChange(
                    object,
                    "selected",
                    current.hasState(AtspiState::selected)
                );
                break;
            case AccessibilityChange::focus:
                emitStateChange(
                    object,
                    "focused",
                    current.hasState(AtspiState::focused)
                );
                break;
        }
    }

    static void accessibilityChanged(
        void* userdata,
        AccessibilityChange change
    ) {
        auto* observer = static_cast<Observer*>(userdata);
        if (observer && observer->owner && observer->object)
            observer->owner->nodeChanged(*observer->object, change);
    }

    void installObservers() {
        observers.reserve(entries.size());
        for (std::size_t index = 0; index < entries.size(); ++index) {
            auto observer = std::make_unique<Observer>();
            observer->owner = this;
            observer->node = entries[index].node;
            observer->object = objects[index + 1].get();
            observer->node->setObserver(observer.get(), accessibilityChanged);
            observers.push_back(std::move(observer));
        }
    }

    GVariant* actionProperty(const Object& object, const char* property) const {
        if (auto* version = versionProperty(property)) return version;
        if (g_strcmp0(property, "NActions") != 0) return nullptr;
        const auto* current = entry(object);
        const auto count = current
            ? AtspiNodeAdapter(current->node).actionCount()
            : 0;
        return g_variant_new_int32(static_cast<gint32>(count));
    }

    void actionMethod(
        const Object& object,
        const char* method,
        GVariant* parameters,
        GDBusMethodInvocation* invocation
    ) const {
        const auto* current = entry(object);
        if (!current) {
            returnError(invocation, "Accessibility action is unavailable");
            return;
        }
        AtspiNodeAdapter adapter(current->node);
        if (g_strcmp0(method, "GetActions") == 0) {
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("a(sss)"));
            for (std::size_t index = 0; index < adapter.actionCount(); ++index) {
                AtspiAction action;
                if (adapter.actionAt(index, action))
                    g_variant_builder_add(&builder, "(sss)", action.name, action.description, "");
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@a(sss))", g_variant_builder_end(&builder))
            );
            return;
        }
        gint32 index = -1;
        g_variant_get(parameters, "(i)", &index);
        AtspiAction action;
        if (index < 0 || !adapter.actionAt(static_cast<std::size_t>(index), action)) {
            returnError(invocation, "Accessibility action index is out of range");
            return;
        }
        if (g_strcmp0(method, "DoAction") == 0) {
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(b)", adapter.performAction(static_cast<std::size_t>(index)))
            );
            return;
        }
        const char* result = nullptr;
        if (g_strcmp0(method, "GetDescription") == 0) result = action.description;
        if (g_strcmp0(method, "GetName") == 0 ||
            g_strcmp0(method, "GetLocalizedName") == 0) result = action.name;
        if (g_strcmp0(method, "GetKeyBinding") == 0) result = "";
        if (result) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", result));
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown accessibility action method"
        );
    }

    static bool textOffset(
        const std::string& text,
        gint32 character_offset,
        std::size_t& byte_offset
    ) {
        if (character_offset < 0) return false;
        const auto characters = g_utf8_strlen(text.c_str(), text.size());
        if (character_offset > characters) return false;
        byte_offset = static_cast<std::size_t>(
            g_utf8_offset_to_pointer(text.c_str(), character_offset) - text.c_str()
        );
        return true;
    }

    void editableTextMethod(
        const Object& object,
        const char* method,
        GVariant* parameters,
        GDBusMethodInvocation* invocation
    ) const {
        const auto* current = entry(object);
        if (!current) {
            returnError(invocation, "Editable accessibility text is unavailable");
            return;
        }
        AtspiNodeAdapter adapter(current->node);
        if (g_strcmp0(method, "SetTextContents") == 0) {
            const char* text = nullptr;
            g_variant_get(parameters, "(&s)", &text);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(b)", adapter.setCurrentText(text))
            );
            return;
        }
        if (g_strcmp0(method, "InsertText") == 0) {
            gint32 position = -1;
            gint32 length = -1;
            const char* inserted = nullptr;
            g_variant_get(parameters, "(i&si)", &position, &inserted, &length);
            std::string text = snapshot(object).value_text;
            std::size_t offset = 0;
            bool accepted = inserted && length >= 0 &&
                textOffset(text, position, offset);
            if (accepted) {
                const auto available = std::strlen(inserted);
                const auto requested = std::min<std::size_t>(
                    static_cast<std::size_t>(length),
                    available
                );
                const char* valid_end = nullptr;
                if (!g_utf8_validate(inserted, requested, &valid_end))
                    accepted = false;
                if (accepted) {
                    text.insert(offset, inserted, requested);
                    accepted = adapter.setCurrentText(text.c_str());
                }
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(b)", accepted)
            );
            return;
        }
        if (g_strcmp0(method, "DeleteText") == 0) {
            gint32 start = -1;
            gint32 end = -1;
            g_variant_get(parameters, "(ii)", &start, &end);
            std::string text = snapshot(object).value_text;
            std::size_t first = 0;
            std::size_t last = 0;
            bool accepted = start <= end &&
                textOffset(text, start, first) &&
                textOffset(text, end, last);
            if (accepted) {
                text.erase(first, last - first);
                accepted = adapter.setCurrentText(text.c_str());
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(b)", accepted)
            );
            return;
        }
        if (g_strcmp0(method, "CutText") == 0 ||
            g_strcmp0(method, "PasteText") == 0) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", false));
            return;
        }
        if (g_strcmp0(method, "CopyText") == 0) {
            g_dbus_method_invocation_return_error_literal(
                invocation,
                G_DBUS_ERROR,
                G_DBUS_ERROR_NOT_SUPPORTED,
                "Clipboard access is unavailable"
            );
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown editable accessibility text method"
        );
    }

    GVariant* valueProperty(const Object& object, const char* property) const {
        if (auto* version = versionProperty(property)) return version;
        const auto current = snapshot(object);
        if (!current.range.present) return nullptr;
        if (g_strcmp0(property, "MinimumValue") == 0)
            return g_variant_new_double(current.range.minimum);
        if (g_strcmp0(property, "MaximumValue") == 0)
            return g_variant_new_double(current.range.maximum);
        if (g_strcmp0(property, "MinimumIncrement") == 0)
            return g_variant_new_double(0.0);
        if (g_strcmp0(property, "CurrentValue") == 0)
            return g_variant_new_double(current.range.current);
        if (g_strcmp0(property, "Text") == 0)
            return g_variant_new_string(current.value_text.c_str());
        return nullptr;
    }

    void componentMethod(
        const Object& object,
        const char* method,
        GVariant* parameters,
        GDBusMethodInvocation* invocation
    ) const {
        if (g_strcmp0(method, "GetSize") == 0) {
            const auto area = bounds(object, 1);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(ii)", area.width, area.height)
            );
            return;
        }
        if (g_strcmp0(method, "GetLayer") == 0) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(u)", 3u));
            return;
        }
        if (g_strcmp0(method, "GetMDIZOrder") == 0) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(n)", -1));
            return;
        }
        if (g_strcmp0(method, "GrabFocus") == 0) {
            const auto* current = entry(object);
            const bool focused = current && AtspiNodeAdapter(current->node).grabFocus();
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", focused));
            return;
        }
        if (g_strcmp0(method, "GetAlpha") == 0) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(d)", 1.0));
            return;
        }
        if (g_strcmp0(method, "SetExtents") == 0 ||
            g_strcmp0(method, "SetPosition") == 0 ||
            g_strcmp0(method, "SetSize") == 0 ||
            g_strcmp0(method, "ScrollTo") == 0 ||
            g_strcmp0(method, "ScrollToPoint") == 0) {
            g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", false));
            return;
        }
        if (g_strcmp0(method, "GetExtents") == 0 ||
            g_strcmp0(method, "GetPosition") == 0) {
            guint32 coordinate_type = 0;
            g_variant_get(parameters, "(u)", &coordinate_type);
            const auto area = bounds(object, coordinate_type);
            if (g_strcmp0(method, "GetExtents") == 0) {
                g_dbus_method_invocation_return_value(
                    invocation,
                    g_variant_new("((iiii))", area.x, area.y, area.width, area.height)
                );
            } else {
                g_dbus_method_invocation_return_value(
                    invocation,
                    g_variant_new("(ii)", area.x, area.y)
                );
            }
            return;
        }
        if (g_strcmp0(method, "Contains") == 0 ||
            g_strcmp0(method, "GetAccessibleAtPoint") == 0) {
            gint32 x = 0;
            gint32 y = 0;
            guint32 coordinate_type = 0;
            g_variant_get(parameters, "(iiu)", &x, &y, &coordinate_type);
            if (g_strcmp0(method, "Contains") == 0) {
                g_dbus_method_invocation_return_value(
                    invocation,
                    g_variant_new("(b)", contains(bounds(object, coordinate_type), x, y))
                );
                return;
            }
            const Object* match = nullptr;
            if (object.root) {
                for (std::size_t index = entries.size() + 1; index > 1; --index) {
                    const auto* candidate = objects[index - 1].get();
                    if (contains(bounds(*candidate, coordinate_type), x, y)) {
                        match = candidate;
                        break;
                    }
                }
            } else if (contains(bounds(object, coordinate_type), x, y)) {
                match = &object;
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new(
                    "((so))",
                    match ? bus_name.c_str() : "",
                    match ? match->path.c_str() : null_path
                )
            );
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown accessibility component method"
        );
    }

    GVariant* accessibleProperty(const Object& object, const char* property) const {
        if (g_strcmp0(property, "version") == 0) return g_variant_new_uint32(1);
        if (g_strcmp0(property, "Name") == 0) {
            if (object.root) return g_variant_new_string("Plugin editor");
            return g_variant_new_string(snapshot(object).name.c_str());
        }
        if (g_strcmp0(property, "Description") == 0) {
            if (object.root) return g_variant_new_string("");
            return g_variant_new_string(snapshot(object).description.c_str());
        }
        if (g_strcmp0(property, "Parent") == 0) {
            return g_variant_new(
                "(so)",
                objectBus(object),
                objectParentPath(object)
            );
        }
        if (g_strcmp0(property, "ChildCount") == 0) {
            const auto count = object.root ? entries.size() : 0;
            return g_variant_new_int32(static_cast<gint32>(count));
        }
        if (g_strcmp0(property, "Locale") == 0)
            return g_variant_new_string(localeName());
        if (g_strcmp0(property, "AccessibleId") == 0) {
            if (object.root) return g_variant_new_string("plugin-editor");
            char identifier[48] {};
            std::snprintf(identifier, sizeof(identifier), "control-%zu", object.index);
            return g_variant_new_string(identifier);
        }
        if (g_strcmp0(property, "HelpText") == 0) {
            if (object.root) return g_variant_new_string("");
            return g_variant_new_string(snapshot(object).description.c_str());
        }
        return nullptr;
    }

    void accessibleMethod(
        const Object& object,
        const char* method,
        GVariant* parameters,
        GDBusMethodInvocation* invocation
    ) const {
        if (g_strcmp0(method, "GetChildAtIndex") == 0) {
            gint32 index = -1;
            g_variant_get(parameters, "(i)", &index);
            if (!object.root || index < 0 ||
                static_cast<std::size_t>(index) >= entries.size()) {
                returnError(invocation, "Accessibility child index is out of range");
                return;
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new(
                    "((so))",
                    bus_name.c_str(),
                    objects[static_cast<std::size_t>(index) + 1]->path.c_str()
                )
            );
            return;
        }
        if (g_strcmp0(method, "GetChildren") == 0) {
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("a(so)"));
            if (object.root) {
                for (std::size_t index = 1; index <= entries.size(); ++index) {
                    g_variant_builder_add(
                        &builder,
                        "(so)",
                        bus_name.c_str(),
                        objects[index]->path.c_str()
                    );
                }
            }
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@a(so))", g_variant_builder_end(&builder))
            );
            return;
        }
        if (g_strcmp0(method, "GetIndexInParent") == 0) {
            const gint32 index = object.root
                ? -1
                : static_cast<gint32>(object.index);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(i)", index)
            );
            return;
        }
        if (g_strcmp0(method, "GetRelationSet") == 0) {
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("a(ua(so))"));
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@a(ua(so)))", g_variant_builder_end(&builder))
            );
            return;
        }
        if (g_strcmp0(method, "GetRole") == 0) {
            const guint32 role = object.root
                ? 75u
                : static_cast<guint32>(snapshot(object).role);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(u)", role)
            );
            return;
        }
        if (g_strcmp0(method, "GetRoleName") == 0 ||
            g_strcmp0(method, "GetLocalizedRoleName") == 0) {
            const char* name = object.root
                ? "application"
                : roleName(snapshot(object).role);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(s)", name)
            );
            return;
        }
        if (g_strcmp0(method, "GetState") == 0) {
            const auto state = object.root
                ? std::array<uint32_t, 2> {}
                : snapshot(object).states;
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("au"));
            g_variant_builder_add(&builder, "u", state[0]);
            g_variant_builder_add(&builder, "u", state[1]);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@au)", g_variant_builder_end(&builder))
            );
            return;
        }
        if (g_strcmp0(method, "GetAttributes") == 0) {
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("a{ss}"));
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@a{ss})", g_variant_builder_end(&builder))
            );
            return;
        }
        if (g_strcmp0(method, "GetApplication") == 0) {
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("((so))", bus_name.c_str(), root_path)
            );
            return;
        }
        if (g_strcmp0(method, "GetInterfaces") == 0) {
            GVariantBuilder builder;
            g_variant_builder_init(&builder, G_VARIANT_TYPE("as"));
            appendInterfaces(builder, object);
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(@as)", g_variant_builder_end(&builder))
            );
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown accessible method"
        );
    }

    GVariant* applicationProperty(const char* property) const {
        if (g_strcmp0(property, "ToolkitName") == 0)
            return g_variant_new_string("zig-vst3");
        if (g_strcmp0(property, "Version") == 0 ||
            g_strcmp0(property, "ToolkitVersion") == 0)
            return g_variant_new_string("1");
        if (g_strcmp0(property, "AtspiVersion") == 0)
            return g_variant_new_string("2.1");
        if (g_strcmp0(property, "InterfaceVersion") == 0)
            return g_variant_new_uint32(1);
        if (g_strcmp0(property, "Id") == 0)
            return g_variant_new_int32(application_id);
        return nullptr;
    }

    void applicationMethod(
        const char* method,
        GDBusMethodInvocation* invocation
    ) const {
        if (g_strcmp0(method, "GetLocale") == 0) {
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(s)", localeName())
            );
            return;
        }
        if (g_strcmp0(method, "GetApplicationBusAddress") == 0) {
            g_dbus_method_invocation_return_value(
                invocation,
                g_variant_new("(s)", "")
            );
            return;
        }
        g_dbus_method_invocation_return_error_literal(
            invocation,
            G_DBUS_ERROR,
            G_DBUS_ERROR_UNKNOWN_METHOD,
            "Unknown application method"
        );
    }

    VSTGUI::CFrame* frame {nullptr};
    std::vector<AccessibilityEntry> entries;
    GDBusNodeInfo* introspection {nullptr};
    GDBusConnection* connection {nullptr};
    std::string bus_name;
    std::string registry_bus;
    std::string registry_root;
    std::vector<std::unique_ptr<Object>> objects;
    std::vector<std::unique_ptr<Observer>> observers;
    std::vector<guint> registrations;
    gint32 application_id {0};
    bool ready {false};
};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() { close(); }

bool NativeAccessibilityBridge::open(
    VSTGUI::CFrame* frame,
    const std::vector<AccessibilityEntry>& entries
) {
    close();
    auto next = std::make_unique<Impl>();
    if (!next->initialize(frame, entries)) return false;
    impl = std::move(next);
    return true;
}

void NativeAccessibilityBridge::close() {
    impl.reset();
}

void NativeAccessibilityBridge::dispatch() {
    if (impl) impl->dispatch();
}

void NativeAccessibilityBridge::layoutChanged() {
    if (impl) impl->layoutChanged();
}

bool NativeAccessibilityBridge::active() const {
    return impl != nullptr;
}

std::size_t NativeAccessibilityBridge::elementCount() const {
    return impl ? impl->elementCount() : 0;
}

}

#else

namespace ZigVstgui {

class NativeAccessibilityBridge::Impl {};

NativeAccessibilityBridge::NativeAccessibilityBridge() = default;
NativeAccessibilityBridge::~NativeAccessibilityBridge() = default;

bool NativeAccessibilityBridge::open(
    VSTGUI::CFrame*,
    const std::vector<AccessibilityEntry>&
) {
    return false;
}

void NativeAccessibilityBridge::close() {}
void NativeAccessibilityBridge::dispatch() {}
void NativeAccessibilityBridge::layoutChanged() {}
bool NativeAccessibilityBridge::active() const { return false; }
std::size_t NativeAccessibilityBridge::elementCount() const { return 0; }

}

#endif

#endif
