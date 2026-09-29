#define _POSIX_C_SOURCE 200809L

#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct wl_interface wl_interface;

typedef struct {
    const char* name;
    const char* signature;
    const wl_interface** types;
} wl_message;

struct wl_interface {
    const char* name;
    int version;
    int method_count;
    const wl_message* methods;
    int event_count;
    const wl_message* events;
};

typedef enum {
    proxy_display,
    proxy_registry,
    proxy_seat,
    proxy_manager,
    proxy_device,
    proxy_source,
    proxy_offer,
} proxy_kind;

typedef struct wl_proxy {
    proxy_kind kind;
    uint32_t version;
    void (**listener)(void);
    void* listener_data;
} wl_proxy;

typedef struct wl_display {
    wl_proxy proxy;
    int descriptors[2];
    int roundtrip;
    wl_proxy* registry;
    wl_proxy* device;
    wl_proxy* source;
} wl_display;

const wl_interface wl_registry_interface = {
    "wl_registry", 1, 0, NULL, 0, NULL,
};

const wl_interface wl_seat_interface = {
    "wl_seat", 1, 0, NULL, 0, NULL,
};

static wl_display* active_display;
static uint8_t captured[1024 * 1024];
static size_t captured_length;

static wl_proxy* allocate_proxy(proxy_kind kind, uint32_t version) {
    wl_proxy* proxy = (wl_proxy*)calloc(1, sizeof(*proxy));
    if (proxy == NULL) return NULL;
    proxy->kind = kind;
    proxy->version = version;
    return proxy;
}

wl_display* wl_display_connect(const char* name) {
    wl_display* display;
    (void)name;
    display = (wl_display*)calloc(1, sizeof(*display));
    if (display == NULL || pipe(display->descriptors) != 0) {
        free(display);
        return NULL;
    }
    display->proxy.kind = proxy_display;
    display->proxy.version = 1;
    active_display = display;
    captured_length = 0;
    return display;
}

void wl_display_disconnect(wl_display* display) {
    if (display == NULL) return;
    close(display->descriptors[0]);
    close(display->descriptors[1]);
    if (active_display == display) active_display = NULL;
    free(display);
}

static void announce_globals(wl_display* display) {
    typedef void (*global_fn)(
        void*, wl_proxy*, uint32_t, const char*, uint32_t
    );
    global_fn global;
    if (display->registry == NULL || display->registry->listener == NULL) return;
    global = (global_fn)display->registry->listener[0];
    global(
        display->registry->listener_data,
        display->registry,
        1,
        "wl_seat",
        1
    );
    if (getenv("ZV3_WAYLAND_FAKE_NO_MANAGER") == NULL) {
        global(
            display->registry->listener_data,
            display->registry,
            2,
            "ext_data_control_manager_v1",
            1
        );
    }
}

static void announce_selection(wl_display* display) {
    typedef void (*data_offer_fn)(void*, wl_proxy*, wl_proxy*);
    typedef void (*selection_fn)(void*, wl_proxy*, wl_proxy*);
    typedef void (*mime_fn)(void*, wl_proxy*, const char*);
    wl_proxy* offer;
    if (display->device == NULL || display->device->listener == NULL) return;
    offer = allocate_proxy(proxy_offer, 1);
    if (offer == NULL) return;
    ((data_offer_fn)display->device->listener[0])(
        display->device->listener_data,
        display->device,
        offer
    );
    if (offer->listener != NULL) {
        ((mime_fn)offer->listener[0])(
            offer->listener_data,
            offer,
            "text/plain;charset=utf-8"
        );
    }
    ((selection_fn)display->device->listener[1])(
        display->device->listener_data,
        display->device,
        offer
    );
}

int wl_display_roundtrip(wl_display* display) {
    if (display == NULL) return -1;
    if (display->roundtrip == 0) announce_globals(display);
    if (display->roundtrip == 1) announce_selection(display);
    display->roundtrip += 1;
    return 0;
}

int wl_display_dispatch_pending(wl_display* display) {
    return display == NULL ? -1 : 0;
}

int wl_display_dispatch(wl_display* display) {
    return display == NULL ? -1 : 0;
}

int wl_display_flush(wl_display* display) {
    return display == NULL ? -1 : 0;
}

int wl_display_get_fd(wl_display* display) {
    return display == NULL ? -1 : display->descriptors[0];
}

int wl_display_get_error(wl_display* display) {
    return display == NULL ? 1 : 0;
}

static wl_proxy* bind_registry(wl_display* display, va_list arguments) {
    uint32_t name = va_arg(arguments, uint32_t);
    const char* interface_name = va_arg(arguments, const char*);
    uint32_t version = va_arg(arguments, uint32_t);
    proxy_kind kind;
    wl_proxy* result;
    (void)display;
    (void)name;
    (void)va_arg(arguments, void*);
    kind = strcmp(interface_name, "wl_seat") == 0 ? proxy_seat : proxy_manager;
    result = allocate_proxy(kind, version);
    return result;
}

static void capture_source(wl_display* display, wl_proxy* source) {
    typedef void (*send_fn)(void*, wl_proxy*, const char*, int32_t);
    typedef void (*selection_fn)(void*, wl_proxy*, wl_proxy*);
    int descriptors[2];
    ssize_t count;
    captured_length = 0;
    display->source = source;
    if (display->device != NULL && display->device->listener != NULL) {
        ((selection_fn)display->device->listener[1])(
            display->device->listener_data,
            display->device,
            NULL
        );
    }
    if (source == NULL || source->listener == NULL || pipe(descriptors) != 0) {
        return;
    }
    ((send_fn)source->listener[0])(
        source->listener_data,
        source,
        "text/plain;charset=utf-8",
        descriptors[1]
    );
    while ((count = read(
                descriptors[0],
                captured + captured_length,
                sizeof(captured) - captured_length
            )) > 0) {
        captured_length += (size_t)count;
        if (captured_length == sizeof(captured)) break;
    }
    close(descriptors[0]);
}

static void send_external_text(int descriptor) {
    static const char value[] = "outside \xce\x94 selection";
    const char* selected = getenv("ZV3_WAYLAND_FAKE_TEXT");
    size_t selected_length;
    int duplicate = dup(descriptor);
    size_t offset = 0;
    if (duplicate < 0) return;
    if (selected == NULL) selected = value;
    selected_length = strlen(selected);
    while (offset < selected_length) {
        ssize_t written = write(
            duplicate,
            selected + offset,
            selected_length - offset
        );
        if (written > 0) {
            offset += (size_t)written;
        } else {
            break;
        }
    }
    close(duplicate);
}

wl_proxy* wl_proxy_marshal_flags(
    wl_proxy* proxy,
    uint32_t opcode,
    const wl_interface* interface,
    uint32_t version,
    uint32_t flags,
    ...
) {
    va_list arguments;
    wl_proxy* result = NULL;
    (void)flags;
    va_start(arguments, flags);
    if (proxy->kind == proxy_display && opcode == 1) {
        result = allocate_proxy(proxy_registry, version);
        ((wl_display*)proxy)->registry = result;
        (void)va_arg(arguments, void*);
    } else if (proxy->kind == proxy_registry && opcode == 0) {
        result = bind_registry(active_display, arguments);
    } else if (proxy->kind == proxy_manager && opcode == 0) {
        result = allocate_proxy(proxy_source, version);
        (void)va_arg(arguments, void*);
    } else if (proxy->kind == proxy_manager && opcode == 1) {
        result = allocate_proxy(proxy_device, version);
        active_display->device = result;
        (void)va_arg(arguments, void*);
        (void)va_arg(arguments, wl_proxy*);
    } else if (proxy->kind == proxy_source && opcode == 0) {
        (void)va_arg(arguments, const char*);
    } else if (proxy->kind == proxy_device && opcode == 0) {
        capture_source(active_display, va_arg(arguments, wl_proxy*));
    } else if (proxy->kind == proxy_offer && opcode == 0) {
        (void)va_arg(arguments, const char*);
        send_external_text(va_arg(arguments, int));
    }
    va_end(arguments);
    if ((flags & 1U) != 0) free(proxy);
    (void)interface;
    return result;
}

uint32_t wl_proxy_get_version(wl_proxy* proxy) {
    return proxy == NULL ? 0 : proxy->version;
}

int wl_proxy_add_listener(
    wl_proxy* proxy,
    void (**listener)(void),
    void* data
) {
    if (proxy == NULL || listener == NULL) return -1;
    proxy->listener = listener;
    proxy->listener_data = data;
    return 0;
}

void wl_proxy_destroy(wl_proxy* proxy) {
    free(proxy);
}

const uint8_t* zv3_wayland_fake_captured(size_t* length) {
    if (length != NULL) *length = captured_length;
    return captured;
}

void zv3_wayland_fake_cancel_source(void) {
    typedef void (*cancelled_fn)(void*, wl_proxy*);
    wl_proxy* source;
    if (active_display == NULL || active_display->source == NULL) return;
    source = active_display->source;
    active_display->source = NULL;
    if (source->listener != NULL) {
        ((cancelled_fn)source->listener[1])(
            source->listener_data,
            source
        );
    }
}
