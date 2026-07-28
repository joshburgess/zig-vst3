#define _POSIX_C_SOURCE 200809L

#include "wayland_window_shim.h"

#include <dlfcn.h>
#include <errno.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct wl_display wl_display;
typedef struct wl_proxy wl_proxy;

typedef struct wl_interface wl_interface;

typedef struct {
    const char *name;
    const char *signature;
    const wl_interface **types;
} wl_message;

struct wl_interface {
    const char *name;
    int version;
    int method_count;
    const wl_message *methods;
    int event_count;
    const wl_message *events;
};

typedef struct {
    size_t size;
    size_t alloc;
    void *data;
} wl_array;

typedef struct {
    void *library;
    wl_display *(*display_connect)(const char *);
    void (*display_disconnect)(wl_display *);
    int (*display_roundtrip)(wl_display *);
    int (*display_dispatch_pending)(wl_display *);
    int (*display_prepare_read)(wl_display *);
    void (*display_cancel_read)(wl_display *);
    int (*display_read_events)(wl_display *);
    int (*display_flush)(wl_display *);
    int (*display_get_fd)(wl_display *);
    int (*display_get_error)(wl_display *);
    wl_proxy *(*proxy_marshal_flags)(
        wl_proxy *,
        uint32_t,
        const wl_interface *,
        uint32_t,
        uint32_t,
        ...);
    uint32_t (*proxy_get_version)(wl_proxy *);
    int (*proxy_add_listener)(wl_proxy *, void (**)(void), void *);
    void (*proxy_destroy)(wl_proxy *);
    const wl_interface *registry_interface;
    const wl_interface *compositor_interface;
    const wl_interface *surface_interface;
    const wl_interface *shm_interface;
    const wl_interface *shm_pool_interface;
    const wl_interface *buffer_interface;
    const wl_interface *seat_interface;
    const wl_interface *keyboard_interface;
    const wl_interface *output_interface;
} wayland_api;

static wl_interface xdg_surface_interface;
static wl_interface xdg_toplevel_interface;
static const wl_interface *xdg_types[26];

static const wl_message xdg_wm_base_requests[] = {
    {"destroy", "", xdg_types + 0},
    {"create_positioner", "n", xdg_types + 4},
    {"get_xdg_surface", "no", xdg_types + 5},
    {"pong", "u", xdg_types + 0},
};

static const wl_message xdg_wm_base_events[] = {
    {"ping", "u", xdg_types + 0},
};

static wl_interface xdg_wm_base_interface = {
    "xdg_wm_base",
    1,
    4,
    xdg_wm_base_requests,
    1,
    xdg_wm_base_events,
};

static const wl_message xdg_surface_requests[] = {
    {"destroy", "", xdg_types + 0},
    {"get_toplevel", "n", xdg_types + 7},
    {"get_popup", "n?oo", xdg_types + 8},
    {"set_window_geometry", "iiii", xdg_types + 0},
    {"ack_configure", "u", xdg_types + 0},
};

static const wl_message xdg_surface_events[] = {
    {"configure", "u", xdg_types + 0},
};

static wl_interface xdg_surface_interface = {
    "xdg_surface",
    1,
    5,
    xdg_surface_requests,
    1,
    xdg_surface_events,
};

static const wl_message xdg_toplevel_requests[] = {
    {"destroy", "", xdg_types + 0},
    {"set_parent", "?o", xdg_types + 11},
    {"set_title", "s", xdg_types + 0},
    {"set_app_id", "s", xdg_types + 0},
    {"show_window_menu", "ouii", xdg_types + 12},
    {"move", "ou", xdg_types + 16},
    {"resize", "ouu", xdg_types + 18},
    {"set_max_size", "ii", xdg_types + 0},
    {"set_min_size", "ii", xdg_types + 0},
    {"set_maximized", "", xdg_types + 0},
    {"unset_maximized", "", xdg_types + 0},
    {"set_fullscreen", "?o", xdg_types + 21},
    {"unset_fullscreen", "", xdg_types + 0},
    {"set_minimized", "", xdg_types + 0},
};

static const wl_message xdg_toplevel_events[] = {
    {"configure", "iia", xdg_types + 0},
    {"close", "", xdg_types + 0},
};

static wl_interface xdg_toplevel_interface = {
    "xdg_toplevel",
    1,
    14,
    xdg_toplevel_requests,
    2,
    xdg_toplevel_events,
};

enum {
    event_none = 0,
    event_close = 1,
    event_resize = 2,
    event_scale = 3,
    event_focus = 4,
    maximum_outputs = 8,
    marshal_flag_destroy = 1,
    seat_capability_keyboard = 2,
    shm_format_xrgb8888 = 1
};

typedef struct {
    uint32_t name;
    wl_proxy *proxy;
    int32_t scale;
    int entered;
} output_slot;

struct zv3_wayland_window {
    wayland_api api;
    wl_display *display;
    wl_proxy *registry;
    wl_proxy *compositor;
    wl_proxy *shm;
    wl_proxy *seat;
    wl_proxy *keyboard;
    wl_proxy *surface;
    wl_proxy *xdg_wm_base;
    wl_proxy *xdg_surface;
    wl_proxy *xdg_toplevel;
    wl_proxy *background_buffer;
    output_slot outputs[maximum_outputs];
    uint32_t width;
    uint32_t height;
    int32_t scale;
    int configured;
    int visible;
    int close_pending;
    int resize_pending;
    int scale_pending;
    int focus_pending;
    int focused;
};

static int load_symbol(
    void *library,
    const char *name,
    void *destination,
    size_t destination_size) {
    void *symbol;

    if (destination_size != sizeof(symbol)) {
        return -1;
    }
    symbol = dlsym(library, name);
    if (symbol == NULL) {
        return -1;
    }
    memcpy(destination, &symbol, sizeof(symbol));
    return 0;
}

#define LOAD_WAYLAND(api, field, name) \
    load_symbol((api)->library, name, &(api)->field, sizeof((api)->field))

static int load_interface(
    void *library,
    const char *name,
    const wl_interface **destination) {
    void *symbol = dlsym(library, name);
    if (symbol == NULL) {
        return -1;
    }
    *destination = (const wl_interface *)symbol;
    return 0;
}

static int load_wayland(wayland_api *api) {
    static const char *const names[] = {
        "libwayland-client.so.0",
        "libwayland-client.so"
    };
    size_t index;

    memset(api, 0, sizeof(*api));
    for (index = 0; index < sizeof(names) / sizeof(names[0]); index += 1) {
        api->library = dlopen(names[index], RTLD_NOW | RTLD_LOCAL);
        if (api->library != NULL) {
            break;
        }
    }
    if (api->library == NULL ||
        LOAD_WAYLAND(api, display_connect, "wl_display_connect") != 0 ||
        LOAD_WAYLAND(api, display_disconnect, "wl_display_disconnect") != 0 ||
        LOAD_WAYLAND(api, display_roundtrip, "wl_display_roundtrip") != 0 ||
        LOAD_WAYLAND(
            api,
            display_dispatch_pending,
            "wl_display_dispatch_pending") != 0 ||
        LOAD_WAYLAND(api, display_prepare_read, "wl_display_prepare_read") != 0 ||
        LOAD_WAYLAND(api, display_cancel_read, "wl_display_cancel_read") != 0 ||
        LOAD_WAYLAND(api, display_read_events, "wl_display_read_events") != 0 ||
        LOAD_WAYLAND(api, display_flush, "wl_display_flush") != 0 ||
        LOAD_WAYLAND(api, display_get_fd, "wl_display_get_fd") != 0 ||
        LOAD_WAYLAND(api, display_get_error, "wl_display_get_error") != 0 ||
        LOAD_WAYLAND(api, proxy_marshal_flags, "wl_proxy_marshal_flags") != 0 ||
        LOAD_WAYLAND(api, proxy_get_version, "wl_proxy_get_version") != 0 ||
        LOAD_WAYLAND(api, proxy_add_listener, "wl_proxy_add_listener") != 0 ||
        LOAD_WAYLAND(api, proxy_destroy, "wl_proxy_destroy") != 0 ||
        load_interface(
            api->library,
            "wl_registry_interface",
            &api->registry_interface) != 0 ||
        load_interface(
            api->library,
            "wl_compositor_interface",
            &api->compositor_interface) != 0 ||
        load_interface(
            api->library,
            "wl_surface_interface",
            &api->surface_interface) != 0 ||
        load_interface(api->library, "wl_shm_interface", &api->shm_interface) != 0 ||
        load_interface(
            api->library,
            "wl_shm_pool_interface",
            &api->shm_pool_interface) != 0 ||
        load_interface(
            api->library,
            "wl_buffer_interface",
            &api->buffer_interface) != 0 ||
        load_interface(api->library, "wl_seat_interface", &api->seat_interface) != 0 ||
        load_interface(
            api->library,
            "wl_keyboard_interface",
            &api->keyboard_interface) != 0 ||
        load_interface(
            api->library,
            "wl_output_interface",
            &api->output_interface) != 0) {
        if (api->library != NULL) {
            dlclose(api->library);
        }
        memset(api, 0, sizeof(*api));
        return -1;
    }

    memset(xdg_types, 0, sizeof(xdg_types));
    xdg_types[5] = &xdg_surface_interface;
    xdg_types[6] = api->surface_interface;
    xdg_types[7] = &xdg_toplevel_interface;
    xdg_types[11] = &xdg_toplevel_interface;
    xdg_types[12] = api->seat_interface;
    xdg_types[16] = api->seat_interface;
    xdg_types[18] = api->seat_interface;
    xdg_types[21] = api->output_interface;
    xdg_types[22] = api->seat_interface;
    return 0;
}

static wl_proxy *bind_global(
    zv3_wayland_window *window,
    uint32_t name,
    const wl_interface *interface,
    uint32_t version) {
    return window->api.proxy_marshal_flags(
        window->registry,
        0,
        interface,
        version,
        0,
        name,
        interface->name,
        version,
        NULL);
}

static void queue_scale(zv3_wayland_window *window) {
    int32_t scale = 1;
    size_t index;

    for (index = 0; index < maximum_outputs; index += 1) {
        if (window->outputs[index].proxy != NULL &&
            window->outputs[index].entered &&
            window->outputs[index].scale > scale) {
            scale = window->outputs[index].scale;
        }
    }
    if (scale != window->scale) {
        window->scale = scale;
        window->scale_pending = 1;
    }
}

static void xdg_wm_base_ping(
    void *data,
    wl_proxy *xdg_wm_base,
    uint32_t serial) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    window->api.proxy_marshal_flags(
        xdg_wm_base,
        3,
        NULL,
        window->api.proxy_get_version(xdg_wm_base),
        0,
        serial);
}

static const struct {
    void (*ping)(void *, wl_proxy *, uint32_t);
} xdg_wm_base_listener = {
    xdg_wm_base_ping,
};

static void xdg_surface_configure(
    void *data,
    wl_proxy *xdg_surface,
    uint32_t serial) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    window->api.proxy_marshal_flags(
        xdg_surface,
        4,
        NULL,
        window->api.proxy_get_version(xdg_surface),
        0,
        serial);
    window->configured = 1;
}

static const struct {
    void (*configure)(void *, wl_proxy *, uint32_t);
} xdg_surface_listener = {
    xdg_surface_configure,
};

static void xdg_toplevel_configure(
    void *data,
    wl_proxy *xdg_toplevel,
    int32_t width,
    int32_t height,
    wl_array *states) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    (void)xdg_toplevel;
    (void)states;
    if (width > 0 && height > 0 &&
        (window->width != (uint32_t)width ||
         window->height != (uint32_t)height)) {
        window->width = (uint32_t)width;
        window->height = (uint32_t)height;
        window->resize_pending = 1;
    }
}

static void xdg_toplevel_close(void *data, wl_proxy *xdg_toplevel) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    (void)xdg_toplevel;
    window->close_pending = 1;
}

static const struct {
    void (*configure)(void *, wl_proxy *, int32_t, int32_t, wl_array *);
    void (*close)(void *, wl_proxy *);
} xdg_toplevel_listener = {
    xdg_toplevel_configure,
    xdg_toplevel_close,
};

static output_slot *find_output(
    zv3_wayland_window *window,
    wl_proxy *output) {
    size_t index;
    for (index = 0; index < maximum_outputs; index += 1) {
        if (window->outputs[index].proxy == output) {
            return &window->outputs[index];
        }
    }
    return NULL;
}

static void surface_enter(
    void *data,
    wl_proxy *surface,
    wl_proxy *output) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    output_slot *slot = find_output(window, output);
    (void)surface;
    if (slot != NULL) {
        slot->entered = 1;
        queue_scale(window);
    }
}

static void surface_leave(
    void *data,
    wl_proxy *surface,
    wl_proxy *output) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    output_slot *slot = find_output(window, output);
    (void)surface;
    if (slot != NULL) {
        slot->entered = 0;
        queue_scale(window);
    }
}

static const struct {
    void (*enter)(void *, wl_proxy *, wl_proxy *);
    void (*leave)(void *, wl_proxy *, wl_proxy *);
} surface_listener = {
    surface_enter,
    surface_leave,
};

static void output_geometry(
    void *data,
    wl_proxy *output,
    int32_t x,
    int32_t y,
    int32_t physical_width,
    int32_t physical_height,
    int32_t subpixel,
    const char *make,
    const char *model,
    int32_t transform) {
    (void)data;
    (void)output;
    (void)x;
    (void)y;
    (void)physical_width;
    (void)physical_height;
    (void)subpixel;
    (void)make;
    (void)model;
    (void)transform;
}

static void output_mode(
    void *data,
    wl_proxy *output,
    uint32_t flags,
    int32_t width,
    int32_t height,
    int32_t refresh) {
    (void)data;
    (void)output;
    (void)flags;
    (void)width;
    (void)height;
    (void)refresh;
}

static void output_done(void *data, wl_proxy *output) {
    (void)data;
    (void)output;
}

static void output_scale(
    void *data,
    wl_proxy *output,
    int32_t factor) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    output_slot *slot = find_output(window, output);
    if (slot != NULL && factor > 0) {
        slot->scale = factor;
        if (slot->entered) {
            queue_scale(window);
        }
    }
}

static const struct {
    void (*geometry)(
        void *,
        wl_proxy *,
        int32_t,
        int32_t,
        int32_t,
        int32_t,
        int32_t,
        const char *,
        const char *,
        int32_t);
    void (*mode)(void *, wl_proxy *, uint32_t, int32_t, int32_t, int32_t);
    void (*done)(void *, wl_proxy *);
    void (*scale)(void *, wl_proxy *, int32_t);
} output_listener = {
    output_geometry,
    output_mode,
    output_done,
    output_scale,
};

static void keyboard_keymap(
    void *data,
    wl_proxy *keyboard,
    uint32_t format,
    int32_t fd,
    uint32_t size) {
    (void)data;
    (void)keyboard;
    (void)format;
    (void)size;
    if (fd >= 0) {
        close(fd);
    }
}

static void keyboard_enter(
    void *data,
    wl_proxy *keyboard,
    uint32_t serial,
    wl_proxy *surface,
    wl_array *keys) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    (void)keyboard;
    (void)serial;
    (void)keys;
    if (surface == window->surface && !window->focused) {
        window->focused = 1;
        window->focus_pending = 1;
    }
}

static void keyboard_leave(
    void *data,
    wl_proxy *keyboard,
    uint32_t serial,
    wl_proxy *surface) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    (void)keyboard;
    (void)serial;
    if (surface == window->surface && window->focused) {
        window->focused = 0;
        window->focus_pending = 1;
    }
}

static void keyboard_key(
    void *data,
    wl_proxy *keyboard,
    uint32_t serial,
    uint32_t time,
    uint32_t key,
    uint32_t state) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)time;
    (void)key;
    (void)state;
}

static void keyboard_modifiers(
    void *data,
    wl_proxy *keyboard,
    uint32_t serial,
    uint32_t depressed,
    uint32_t latched,
    uint32_t locked,
    uint32_t group) {
    (void)data;
    (void)keyboard;
    (void)serial;
    (void)depressed;
    (void)latched;
    (void)locked;
    (void)group;
}

static void keyboard_repeat_info(
    void *data,
    wl_proxy *keyboard,
    int32_t rate,
    int32_t delay) {
    (void)data;
    (void)keyboard;
    (void)rate;
    (void)delay;
}

static const struct {
    void (*keymap)(void *, wl_proxy *, uint32_t, int32_t, uint32_t);
    void (*enter)(void *, wl_proxy *, uint32_t, wl_proxy *, wl_array *);
    void (*leave)(void *, wl_proxy *, uint32_t, wl_proxy *);
    void (*key)(void *, wl_proxy *, uint32_t, uint32_t, uint32_t, uint32_t);
    void (*modifiers)(
        void *,
        wl_proxy *,
        uint32_t,
        uint32_t,
        uint32_t,
        uint32_t,
        uint32_t);
    void (*repeat_info)(void *, wl_proxy *, int32_t, int32_t);
} keyboard_listener = {
    keyboard_keymap,
    keyboard_enter,
    keyboard_leave,
    keyboard_key,
    keyboard_modifiers,
    keyboard_repeat_info,
};

static void destroy_keyboard(zv3_wayland_window *window) {
    if (window->keyboard == NULL) {
        return;
    }
    if (window->api.proxy_get_version(window->keyboard) >= 3 &&
        window->api.display_get_error(window->display) == 0) {
        window->api.proxy_marshal_flags(
            window->keyboard,
            0,
            NULL,
            window->api.proxy_get_version(window->keyboard),
            marshal_flag_destroy);
    } else {
        window->api.proxy_destroy(window->keyboard);
    }
    window->keyboard = NULL;
}

static void seat_capabilities(
    void *data,
    wl_proxy *seat,
    uint32_t capabilities) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    if ((capabilities & seat_capability_keyboard) != 0 &&
        window->keyboard == NULL) {
        window->keyboard = window->api.proxy_marshal_flags(
            seat,
            1,
            window->api.keyboard_interface,
            window->api.proxy_get_version(seat),
            0,
            NULL);
        if (window->keyboard != NULL &&
            window->api.proxy_add_listener(
                window->keyboard,
                (void (**)(void))&keyboard_listener,
                window) != 0) {
            destroy_keyboard(window);
        }
    } else if ((capabilities & seat_capability_keyboard) == 0) {
        destroy_keyboard(window);
    }
}

static void seat_name(
    void *data,
    wl_proxy *seat,
    const char *name) {
    (void)data;
    (void)seat;
    (void)name;
}

static const struct {
    void (*capabilities)(void *, wl_proxy *, uint32_t);
    void (*name)(void *, wl_proxy *, const char *);
} seat_listener = {
    seat_capabilities,
    seat_name,
};

static void registry_global(
    void *data,
    wl_proxy *registry,
    uint32_t name,
    const char *interface,
    uint32_t version) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    size_t index;
    (void)registry;

    if (strcmp(interface, "wl_compositor") == 0 &&
        window->compositor == NULL) {
        uint32_t selected = version < 4 ? version : 4;
        window->compositor = bind_global(
            window,
            name,
            window->api.compositor_interface,
            selected);
    } else if (strcmp(interface, "wl_shm") == 0 && window->shm == NULL) {
        window->shm = bind_global(
            window,
            name,
            window->api.shm_interface,
            1);
    } else if (strcmp(interface, "xdg_wm_base") == 0 &&
        window->xdg_wm_base == NULL) {
        window->xdg_wm_base = bind_global(
            window,
            name,
            &xdg_wm_base_interface,
            1);
        if (window->xdg_wm_base != NULL &&
            window->api.proxy_add_listener(
                window->xdg_wm_base,
                (void (**)(void))&xdg_wm_base_listener,
                window) != 0) {
            window->api.proxy_destroy(window->xdg_wm_base);
            window->xdg_wm_base = NULL;
        }
    } else if (strcmp(interface, "wl_seat") == 0 && window->seat == NULL) {
        uint32_t selected = version < 4 ? version : 4;
        window->seat = bind_global(
            window,
            name,
            window->api.seat_interface,
            selected);
        if (window->seat != NULL &&
            window->api.proxy_add_listener(
                window->seat,
                (void (**)(void))&seat_listener,
                window) != 0) {
            window->api.proxy_destroy(window->seat);
            window->seat = NULL;
        }
    } else if (strcmp(interface, "wl_output") == 0) {
        for (index = 0; index < maximum_outputs; index += 1) {
            if (window->outputs[index].proxy == NULL) {
                uint32_t selected = version < 2 ? version : 2;
                window->outputs[index].name = name;
                window->outputs[index].scale = 1;
                window->outputs[index].proxy = bind_global(
                    window,
                    name,
                    window->api.output_interface,
                    selected);
                if (window->outputs[index].proxy != NULL &&
                    window->api.proxy_add_listener(
                        window->outputs[index].proxy,
                        (void (**)(void))&output_listener,
                        window) != 0) {
                    window->api.proxy_destroy(
                        window->outputs[index].proxy);
                    memset(
                        &window->outputs[index],
                        0,
                        sizeof(window->outputs[index]));
                }
                break;
            }
        }
    }
}

static void registry_global_remove(
    void *data,
    wl_proxy *registry,
    uint32_t name) {
    zv3_wayland_window *window = (zv3_wayland_window *)data;
    size_t index;
    (void)registry;

    for (index = 0; index < maximum_outputs; index += 1) {
        if (window->outputs[index].proxy != NULL &&
            window->outputs[index].name == name) {
            window->api.proxy_destroy(window->outputs[index].proxy);
            memset(
                &window->outputs[index],
                0,
                sizeof(window->outputs[index]));
            queue_scale(window);
            return;
        }
    }
}

static const struct {
    void (*global)(void *, wl_proxy *, uint32_t, const char *, uint32_t);
    void (*global_remove)(void *, wl_proxy *, uint32_t);
} registry_listener = {
    registry_global,
    registry_global_remove,
};

static void destroy_request(
    zv3_wayland_window *window,
    wl_proxy *proxy,
    uint32_t opcode) {
    if (proxy == NULL) {
        return;
    }
    if (window->display != NULL &&
        window->api.display_get_error(window->display) == 0) {
        window->api.proxy_marshal_flags(
            proxy,
            opcode,
            NULL,
            window->api.proxy_get_version(proxy),
            marshal_flag_destroy);
    } else {
        window->api.proxy_destroy(proxy);
    }
}

static int create_background_buffer(zv3_wayland_window *window) {
    char path[512];
    const char *runtime_dir = getenv("XDG_RUNTIME_DIR");
    wl_proxy *pool = NULL;
    int fd = -1;
    int path_length;
    int result = -1;

    if (runtime_dir == NULL) {
        return -1;
    }
    path_length = snprintf(
        path,
        sizeof(path),
        "%s/zig-vst3-wayland-XXXXXX",
        runtime_dir);
    if (path_length < 0 || (size_t)path_length >= sizeof(path)) {
        return -1;
    }
    fd = mkstemp(path);
    if (fd < 0) {
        return -1;
    }
    unlink(path);
    if (ftruncate(fd, 4) != 0) {
        goto finish;
    }
    pool = window->api.proxy_marshal_flags(
        window->shm,
        0,
        window->api.shm_pool_interface,
        window->api.proxy_get_version(window->shm),
        0,
        NULL,
        fd,
        4);
    if (pool == NULL) {
        goto finish;
    }
    window->background_buffer = window->api.proxy_marshal_flags(
        pool,
        0,
        window->api.buffer_interface,
        window->api.proxy_get_version(pool),
        0,
        NULL,
        0,
        1,
        1,
        4,
        shm_format_xrgb8888);
    if (window->background_buffer == NULL) {
        goto finish;
    }
    result = 0;

finish:
    if (pool != NULL) {
        destroy_request(window, pool, 1);
    }
    close(fd);
    return result;
}

static void destroy_window_state(zv3_wayland_window *window) {
    size_t index;

    if (window == NULL) {
        return;
    }
    destroy_keyboard(window);
    if (window->seat != NULL) {
        window->api.proxy_destroy(window->seat);
        window->seat = NULL;
    }
    for (index = 0; index < maximum_outputs; index += 1) {
        if (window->outputs[index].proxy != NULL) {
            window->api.proxy_destroy(window->outputs[index].proxy);
            window->outputs[index].proxy = NULL;
        }
    }
    if (window->background_buffer != NULL) {
        destroy_request(window, window->background_buffer, 0);
        window->background_buffer = NULL;
    }
    if (window->xdg_toplevel != NULL) {
        destroy_request(window, window->xdg_toplevel, 0);
        window->xdg_toplevel = NULL;
    }
    if (window->xdg_surface != NULL) {
        destroy_request(window, window->xdg_surface, 0);
        window->xdg_surface = NULL;
    }
    if (window->surface != NULL) {
        destroy_request(window, window->surface, 0);
        window->surface = NULL;
    }
    if (window->xdg_wm_base != NULL) {
        destroy_request(window, window->xdg_wm_base, 0);
        window->xdg_wm_base = NULL;
    }
    if (window->shm != NULL) {
        window->api.proxy_destroy(window->shm);
        window->shm = NULL;
    }
    if (window->compositor != NULL) {
        window->api.proxy_destroy(window->compositor);
        window->compositor = NULL;
    }
    if (window->registry != NULL) {
        window->api.proxy_destroy(window->registry);
        window->registry = NULL;
    }
    if (window->display != NULL) {
        window->api.display_disconnect(window->display);
        window->display = NULL;
    }
    if (window->api.library != NULL) {
        dlclose(window->api.library);
        window->api.library = NULL;
    }
}

int zv3_wayland_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_wayland_window **out_window) {
    zv3_wayland_window *window;
    char *terminated_title;

    if (title == NULL || title_length == 0 || width == 0 || height == 0 ||
        out_window == NULL || title_length == SIZE_MAX ||
        width > INT32_MAX || height > INT32_MAX) {
        return -1;
    }
    *out_window = NULL;
    window = (zv3_wayland_window *)calloc(1, sizeof(*window));
    terminated_title = (char *)malloc(title_length + 1);
    if (window == NULL || terminated_title == NULL) {
        free(terminated_title);
        free(window);
        return -1;
    }
    memcpy(terminated_title, title, title_length);
    terminated_title[title_length] = '\0';
    window->width = width;
    window->height = height;
    window->scale = 1;

    if (load_wayland(&window->api) != 0) {
        goto fail;
    }
    window->display = window->api.display_connect(NULL);
    if (window->display == NULL) {
        goto fail;
    }
    window->registry = window->api.proxy_marshal_flags(
        (wl_proxy *)window->display,
        1,
        window->api.registry_interface,
        window->api.proxy_get_version((wl_proxy *)window->display),
        0,
        NULL);
    if (window->registry == NULL ||
        window->api.proxy_add_listener(
            window->registry,
            (void (**)(void))&registry_listener,
            window) != 0 ||
        window->api.display_roundtrip(window->display) < 0 ||
        window->compositor == NULL ||
        window->shm == NULL ||
        window->xdg_wm_base == NULL) {
        goto fail;
    }

    window->surface = window->api.proxy_marshal_flags(
        window->compositor,
        0,
        window->api.surface_interface,
        window->api.proxy_get_version(window->compositor),
        0,
        NULL);
    if (window->surface == NULL ||
        window->api.proxy_add_listener(
            window->surface,
            (void (**)(void))&surface_listener,
            window) != 0) {
        goto fail;
    }
    window->xdg_surface = window->api.proxy_marshal_flags(
        window->xdg_wm_base,
        2,
        &xdg_surface_interface,
        window->api.proxy_get_version(window->xdg_wm_base),
        0,
        NULL,
        window->surface);
    if (window->xdg_surface == NULL ||
        window->api.proxy_add_listener(
            window->xdg_surface,
            (void (**)(void))&xdg_surface_listener,
            window) != 0) {
        goto fail;
    }
    window->xdg_toplevel = window->api.proxy_marshal_flags(
        window->xdg_surface,
        1,
        &xdg_toplevel_interface,
        window->api.proxy_get_version(window->xdg_surface),
        0,
        NULL);
    if (window->xdg_toplevel == NULL ||
        window->api.proxy_add_listener(
            window->xdg_toplevel,
            (void (**)(void))&xdg_toplevel_listener,
            window) != 0) {
        goto fail;
    }
    window->api.proxy_marshal_flags(
        window->xdg_toplevel,
        2,
        NULL,
        window->api.proxy_get_version(window->xdg_toplevel),
        0,
        terminated_title);
    window->api.proxy_marshal_flags(
        window->xdg_toplevel,
        3,
        NULL,
        window->api.proxy_get_version(window->xdg_toplevel),
        0,
        "zig-vst3-standalone");
    window->api.proxy_marshal_flags(
        window->surface,
        6,
        NULL,
        window->api.proxy_get_version(window->surface),
        0);
    if (window->api.display_roundtrip(window->display) < 0 ||
        !window->configured ||
        create_background_buffer(window) != 0) {
        goto fail;
    }
    free(terminated_title);
    *out_window = window;
    return 0;

fail:
    free(terminated_title);
    destroy_window_state(window);
    free(window);
    return -1;
}

void zv3_wayland_window_destroy(zv3_wayland_window *window) {
    if (window == NULL) {
        return;
    }
    destroy_window_state(window);
    free(window);
}

int zv3_wayland_window_show(zv3_wayland_window *window) {
    if (window == NULL || window->display == NULL ||
        window->surface == NULL || window->background_buffer == NULL) {
        return -1;
    }
    if (window->visible) {
        return 0;
    }
    window->api.proxy_marshal_flags(
        window->surface,
        1,
        NULL,
        window->api.proxy_get_version(window->surface),
        0,
        window->background_buffer,
        0,
        0);
    window->api.proxy_marshal_flags(
        window->surface,
        6,
        NULL,
        window->api.proxy_get_version(window->surface),
        0);
    if (window->api.display_flush(window->display) < 0 &&
        errno != EAGAIN) {
        return -1;
    }
    window->visible = 1;
    return 0;
}

int zv3_wayland_window_hide(zv3_wayland_window *window) {
    if (window == NULL || window->display == NULL ||
        window->surface == NULL) {
        return -1;
    }
    if (!window->visible) {
        return 0;
    }
    window->api.proxy_marshal_flags(
        window->surface,
        1,
        NULL,
        window->api.proxy_get_version(window->surface),
        0,
        NULL,
        0,
        0);
    window->api.proxy_marshal_flags(
        window->surface,
        6,
        NULL,
        window->api.proxy_get_version(window->surface),
        0);
    if (window->api.display_flush(window->display) < 0 &&
        errno != EAGAIN) {
        return -1;
    }
    window->visible = 0;
    return 0;
}

int zv3_wayland_window_resize(
    zv3_wayland_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height) {
    if (window == NULL || window->display == NULL ||
        window->surface == NULL || window->xdg_surface == NULL ||
        requested_width == 0 || requested_height == 0 ||
        requested_width > INT32_MAX || requested_height > INT32_MAX ||
        accepted_width == NULL || accepted_height == NULL) {
        return -1;
    }
    window->width = requested_width;
    window->height = requested_height;
    *accepted_width = requested_width;
    *accepted_height = requested_height;
    return 0;
}

static int emit_pending_event(
    zv3_wayland_window *window,
    zv3_wayland_window_event *out_event) {
    if (window->close_pending) {
        window->close_pending = 0;
        out_event->type = event_close;
        return 1;
    }
    if (window->resize_pending) {
        window->resize_pending = 0;
        out_event->type = event_resize;
        out_event->width = window->width;
        out_event->height = window->height;
        return 1;
    }
    if (window->scale_pending) {
        window->scale_pending = 0;
        out_event->type = event_scale;
        out_event->scale_x = (double)window->scale;
        out_event->scale_y = (double)window->scale;
        return 1;
    }
    if (window->focus_pending) {
        window->focus_pending = 0;
        out_event->type = event_focus;
        out_event->focused = window->focused ? 1U : 0U;
        return 1;
    }
    return 0;
}

int zv3_wayland_window_poll(
    zv3_wayland_window *window,
    zv3_wayland_window_event *out_event) {
    struct pollfd descriptor;
    int poll_result;

    if (window == NULL || window->display == NULL || out_event == NULL) {
        return -1;
    }
    memset(out_event, 0, sizeof(*out_event));
    if (emit_pending_event(window, out_event)) {
        return 0;
    }
    if (window->api.display_dispatch_pending(window->display) < 0) {
        return -1;
    }
    if (emit_pending_event(window, out_event)) {
        return 0;
    }
    while (window->api.display_prepare_read(window->display) != 0) {
        if (window->api.display_dispatch_pending(window->display) < 0) {
            return -1;
        }
        if (emit_pending_event(window, out_event)) {
            return 0;
        }
    }
    if (window->api.display_flush(window->display) < 0 &&
        errno != EAGAIN) {
        window->api.display_cancel_read(window->display);
        return -1;
    }
    descriptor.fd = window->api.display_get_fd(window->display);
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    poll_result = poll(&descriptor, 1, 0);
    if (poll_result < 0) {
        window->api.display_cancel_read(window->display);
        return errno == EINTR ? 0 : -1;
    }
    if (poll_result == 0 || (descriptor.revents & POLLIN) == 0) {
        window->api.display_cancel_read(window->display);
        if ((descriptor.revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
            return -1;
        }
        return 0;
    }
    if (window->api.display_read_events(window->display) < 0 ||
        window->api.display_dispatch_pending(window->display) < 0 ||
        window->api.display_get_error(window->display) != 0) {
        return -1;
    }
    (void)emit_pending_event(window, out_event);
    return 0;
}

void *zv3_wayland_window_parent(zv3_wayland_window *window) {
    return window == NULL ? NULL : window->surface;
}

void *zv3_wayland_window_display(zv3_wayland_window *window) {
    return window == NULL ? NULL : window->display;
}

void *zv3_wayland_window_xdg_surface(zv3_wayland_window *window) {
    return window == NULL ? NULL : window->xdg_surface;
}

void *zv3_wayland_window_xdg_toplevel(zv3_wayland_window *window) {
    return window == NULL ? NULL : window->xdg_toplevel;
}

int zv3_wayland_window_size(
    zv3_wayland_window *window,
    uint32_t *out_width,
    uint32_t *out_height) {
    if (window == NULL || window->surface == NULL ||
        out_width == NULL || out_height == NULL ||
        window->width == 0 || window->height == 0) {
        return -1;
    }
    *out_width = window->width;
    *out_height = window->height;
    return 0;
}
