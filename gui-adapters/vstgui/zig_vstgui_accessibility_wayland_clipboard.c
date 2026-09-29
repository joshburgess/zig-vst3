#define _POSIX_C_SOURCE 200809L

#include "zig_vstgui_accessibility_wayland_clipboard.h"

#if defined(__linux__) || defined(ZIG_VSTGUI_WAYLAND_CLIPBOARD_TEST_PLATFORM)

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

typedef struct wl_display wl_display;
typedef struct wl_proxy wl_proxy;
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

typedef struct {
    void* library;
    wl_display* (*display_connect)(const char*);
    void (*display_disconnect)(wl_display*);
    int (*display_roundtrip)(wl_display*);
    int (*display_dispatch_pending)(wl_display*);
    int (*display_dispatch)(wl_display*);
    int (*display_flush)(wl_display*);
    int (*display_get_fd)(wl_display*);
    int (*display_get_error)(wl_display*);
    wl_proxy* (*proxy_marshal_flags)(
        wl_proxy*,
        uint32_t,
        const wl_interface*,
        uint32_t,
        uint32_t,
        ...
    );
    uint32_t (*proxy_get_version)(wl_proxy*);
    int (*proxy_add_listener)(wl_proxy*, void (**)(void), void*);
    void (*proxy_destroy)(wl_proxy*);
    const wl_interface* registry_interface;
    const wl_interface* seat_interface;
} wayland_api;

typedef struct source_slot source_slot;
typedef struct offer_slot offer_slot;

struct source_slot {
    struct zv3_wayland_clipboard* clipboard;
    wl_proxy* proxy;
    uint8_t* text;
    size_t length;
    source_slot* next;
};

struct offer_slot {
    wl_proxy* proxy;
    int utf8_variant;
    int plain;
    offer_slot* next;
};

struct zv3_wayland_clipboard {
    wayland_api api;
    wl_display* display;
    wl_proxy* registry;
    wl_proxy* seat;
    wl_proxy* manager;
    wl_proxy* device;
    source_slot* sources;
    source_slot* owned_source;
    offer_slot* offers;
    offer_slot* selection;
    offer_slot* primary_selection;
    int finished;
};

static wl_interface data_source_interface;
static wl_interface data_offer_interface;
static wl_interface data_device_interface;
static const wl_interface* protocol_types[9];

static const wl_message manager_requests[] = {
    {"create_data_source", "n", protocol_types + 0},
    {"get_data_device", "no", protocol_types + 1},
    {"destroy", "", protocol_types + 0},
};

static const wl_message source_requests[] = {
    {"offer", "s", protocol_types + 0},
    {"destroy", "", protocol_types + 0},
};

static const wl_message source_events[] = {
    {"send", "sh", protocol_types + 0},
    {"cancelled", "", protocol_types + 0},
};

static const wl_message offer_requests[] = {
    {"receive", "sh", protocol_types + 0},
    {"destroy", "", protocol_types + 0},
};

static const wl_message offer_events[] = {
    {"offer", "s", protocol_types + 0},
};

static const wl_message device_requests[] = {
    {"set_selection", "?o", protocol_types + 3},
    {"destroy", "", protocol_types + 0},
    {"set_primary_selection", "?o", protocol_types + 3},
};

static const wl_message device_events[] = {
    {"data_offer", "n", protocol_types + 4},
    {"selection", "?o", protocol_types + 4},
    {"finished", "", protocol_types + 0},
    {"primary_selection", "?o", protocol_types + 4},
};

static wl_interface data_manager_interface = {
    "ext_data_control_manager_v1",
    1,
    3,
    manager_requests,
    0,
    NULL,
};

static wl_interface data_source_interface = {
    "ext_data_control_source_v1",
    1,
    2,
    source_requests,
    2,
    source_events,
};

static wl_interface data_offer_interface = {
    "ext_data_control_offer_v1",
    1,
    2,
    offer_requests,
    1,
    offer_events,
};

static wl_interface data_device_interface = {
    "ext_data_control_device_v1",
    1,
    3,
    device_requests,
    4,
    device_events,
};

enum {
    marshal_flag_destroy = 1,
    transfer_timeout_ms = 250,
};

static int load_symbol(
    void* library,
    const char* name,
    void* destination,
    size_t destination_size
) {
    void* symbol;
    if (destination_size != sizeof(symbol)) return -1;
    symbol = dlsym(library, name);
    if (symbol == NULL) return -1;
    memcpy(destination, &symbol, sizeof(symbol));
    return 0;
}

#define LOAD_WAYLAND(api, field, name) \
    load_symbol((api)->library, name, &(api)->field, sizeof((api)->field))

static int load_interface(
    void* library,
    const char* name,
    const wl_interface** destination
) {
    void* symbol = dlsym(library, name);
    if (symbol == NULL) return -1;
    *destination = (const wl_interface*)symbol;
    return 0;
}

static int load_wayland(wayland_api* api) {
    static const char* const names[] = {
        "libwayland-client.so.0",
        "libwayland-client.so",
    };
    size_t index;

    memset(api, 0, sizeof(*api));
    for (index = 0; index < sizeof(names) / sizeof(names[0]); index += 1) {
        api->library = dlopen(names[index], RTLD_NOW | RTLD_LOCAL);
        if (api->library != NULL) break;
    }
    if (api->library == NULL ||
        LOAD_WAYLAND(api, display_connect, "wl_display_connect") != 0 ||
        LOAD_WAYLAND(api, display_disconnect, "wl_display_disconnect") != 0 ||
        LOAD_WAYLAND(api, display_roundtrip, "wl_display_roundtrip") != 0 ||
        LOAD_WAYLAND(
            api,
            display_dispatch_pending,
            "wl_display_dispatch_pending"
        ) != 0 ||
        LOAD_WAYLAND(api, display_dispatch, "wl_display_dispatch") != 0 ||
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
            &api->registry_interface
        ) != 0 ||
        load_interface(
            api->library,
            "wl_seat_interface",
            &api->seat_interface
        ) != 0) {
        if (api->library != NULL) dlclose(api->library);
        memset(api, 0, sizeof(*api));
        return -1;
    }

    memset(protocol_types, 0, sizeof(protocol_types));
    protocol_types[0] = &data_source_interface;
    protocol_types[1] = &data_device_interface;
    protocol_types[2] = api->seat_interface;
    protocol_types[3] = &data_source_interface;
    protocol_types[4] = &data_offer_interface;
    return 0;
}

static wl_proxy* bind_global(
    zv3_wayland_clipboard* clipboard,
    uint32_t name,
    const wl_interface* interface,
    uint32_t version
) {
    return clipboard->api.proxy_marshal_flags(
        clipboard->registry,
        0,
        interface,
        version,
        0,
        name,
        interface->name,
        version,
        NULL
    );
}

static offer_slot* find_offer(
    zv3_wayland_clipboard* clipboard,
    wl_proxy* proxy
) {
    offer_slot* offer = clipboard->offers;
    while (offer != NULL) {
        if (offer->proxy == proxy) return offer;
        offer = offer->next;
    }
    return NULL;
}

static void destroy_offer(
    zv3_wayland_clipboard* clipboard,
    offer_slot* target
) {
    offer_slot** cursor = &clipboard->offers;
    while (*cursor != NULL && *cursor != target) cursor = &(*cursor)->next;
    if (*cursor == NULL) return;
    *cursor = target->next;
    if (clipboard->selection == target) clipboard->selection = NULL;
    if (clipboard->primary_selection == target) {
        clipboard->primary_selection = NULL;
    }
    clipboard->api.proxy_marshal_flags(
        target->proxy,
        1,
        NULL,
        clipboard->api.proxy_get_version(target->proxy),
        marshal_flag_destroy
    );
    free(target);
}

static void offer_mime(void* data, wl_proxy* proxy, const char* mime) {
    offer_slot* offer = (offer_slot*)data;
    (void)proxy;
    if (mime == NULL) return;
    if (strcmp(mime, "text/plain;charset=utf-8") == 0) {
        offer->utf8_variant = 1;
    } else if (strcmp(mime, "text/plain;charset=UTF-8") == 0) {
        offer->utf8_variant = 2;
    } else if (strcmp(mime, "UTF8_STRING") == 0) {
        offer->utf8_variant = 3;
    } else if (strcmp(mime, "text/plain") == 0) {
        offer->plain = 1;
    }
}

static const struct {
    void (*offer)(void*, wl_proxy*, const char*);
} offer_listener = {
    offer_mime,
};

static void device_data_offer(void* data, wl_proxy* proxy, wl_proxy* value) {
    zv3_wayland_clipboard* clipboard = (zv3_wayland_clipboard*)data;
    offer_slot* offer;
    (void)proxy;
    if (value == NULL || find_offer(clipboard, value) != NULL) return;
    offer = (offer_slot*)calloc(1, sizeof(*offer));
    if (offer == NULL) {
        clipboard->api.proxy_marshal_flags(
            value,
            1,
            NULL,
            clipboard->api.proxy_get_version(value),
            marshal_flag_destroy
        );
        return;
    }
    offer->proxy = value;
    offer->next = clipboard->offers;
    clipboard->offers = offer;
    if (clipboard->api.proxy_add_listener(
            value,
            (void (**)(void))&offer_listener,
            offer
        ) != 0) {
        destroy_offer(clipboard, offer);
    }
}

static void device_selection(void* data, wl_proxy* proxy, wl_proxy* value) {
    zv3_wayland_clipboard* clipboard = (zv3_wayland_clipboard*)data;
    offer_slot* previous = clipboard->selection;
    (void)proxy;
    clipboard->selection = find_offer(clipboard, value);
    if (previous != NULL && previous != clipboard->selection) {
        destroy_offer(clipboard, previous);
    }
}

static void device_finished(void* data, wl_proxy* proxy) {
    zv3_wayland_clipboard* clipboard = (zv3_wayland_clipboard*)data;
    (void)proxy;
    clipboard->finished = 1;
}

static void device_primary_selection(
    void* data,
    wl_proxy* proxy,
    wl_proxy* value
) {
    zv3_wayland_clipboard* clipboard = (zv3_wayland_clipboard*)data;
    offer_slot* previous = clipboard->primary_selection;
    (void)proxy;
    clipboard->primary_selection = find_offer(clipboard, value);
    if (previous != NULL && previous != clipboard->primary_selection) {
        destroy_offer(clipboard, previous);
    }
}

static const struct {
    void (*data_offer)(void*, wl_proxy*, wl_proxy*);
    void (*selection)(void*, wl_proxy*, wl_proxy*);
    void (*finished)(void*, wl_proxy*);
    void (*primary_selection)(void*, wl_proxy*, wl_proxy*);
} device_listener = {
    device_data_offer,
    device_selection,
    device_finished,
    device_primary_selection,
};

static int remaining_milliseconds(const struct timespec* deadline) {
    struct timespec now;
    int64_t milliseconds;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
    milliseconds = (int64_t)(deadline->tv_sec - now.tv_sec) * 1000 +
        (deadline->tv_nsec - now.tv_nsec) / 1000000;
    if (milliseconds <= 0) return 0;
    if (milliseconds > transfer_timeout_ms) return transfer_timeout_ms;
    return (int)milliseconds;
}

static int write_bounded(int descriptor, const uint8_t* text, size_t length) {
    struct timespec deadline;
    size_t offset = 0;
    if (clock_gettime(CLOCK_MONOTONIC, &deadline) != 0) return -1;
    deadline.tv_nsec += transfer_timeout_ms * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    while (offset < length) {
        ssize_t written = write(descriptor, text + offset, length - offset);
        if (written > 0) {
            offset += (size_t)written;
            continue;
        }
        if (written < 0 && errno == EINTR) continue;
        if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            struct pollfd poll_descriptor = {descriptor, POLLOUT, 0};
            int timeout = remaining_milliseconds(&deadline);
            int result;
            if (timeout == 0) return -1;
            result = poll(&poll_descriptor, 1, timeout);
            if (result < 0 && errno == EINTR) continue;
            if (result <= 0 || (poll_descriptor.revents & POLLOUT) == 0) {
                return -1;
            }
            continue;
        }
        return -1;
    }
    return 0;
}

static int flush_bounded(zv3_wayland_clipboard* clipboard) {
    struct timespec deadline;
    if (clock_gettime(CLOCK_MONOTONIC, &deadline) != 0) return -1;
    deadline.tv_nsec += transfer_timeout_ms * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    for (;;) {
        int result = clipboard->api.display_flush(clipboard->display);
        if (result >= 0) return 0;
        if (errno == EINTR) continue;
        if (errno != EAGAIN && errno != EWOULDBLOCK) return -1;
        {
            struct pollfd descriptor = {
                clipboard->api.display_get_fd(clipboard->display),
                POLLOUT,
                0,
            };
            int timeout = remaining_milliseconds(&deadline);
            if (timeout == 0) return -1;
            result = poll(&descriptor, 1, timeout);
            if (result < 0 && errno == EINTR) continue;
            if (result <= 0 || (descriptor.revents & POLLOUT) == 0) return -1;
        }
    }
}

static void source_send(
    void* data,
    wl_proxy* proxy,
    const char* mime,
    int32_t descriptor
) {
    source_slot* source = (source_slot*)data;
    int flags;
    (void)proxy;
    if (descriptor < 0) return;
    flags = fcntl(descriptor, F_GETFL, 0);
    if (flags >= 0) (void)fcntl(descriptor, F_SETFL, flags | O_NONBLOCK);
    if (mime != NULL &&
        (strcmp(mime, "text/plain;charset=utf-8") == 0 ||
         strcmp(mime, "text/plain") == 0 ||
         strcmp(mime, "UTF8_STRING") == 0)) {
        (void)write_bounded(descriptor, source->text, source->length);
    }
    close(descriptor);
}

static void remove_source(source_slot* source) {
    zv3_wayland_clipboard* clipboard = source->clipboard;
    source_slot** cursor = &clipboard->sources;
    while (*cursor != NULL && *cursor != source) cursor = &(*cursor)->next;
    if (*cursor == NULL) return;
    *cursor = source->next;
    if (clipboard->owned_source == source) clipboard->owned_source = NULL;
    clipboard->api.proxy_marshal_flags(
        source->proxy,
        1,
        NULL,
        clipboard->api.proxy_get_version(source->proxy),
        marshal_flag_destroy
    );
    free(source->text);
    free(source);
}

static void source_cancelled(void* data, wl_proxy* proxy) {
    (void)proxy;
    remove_source((source_slot*)data);
}

static const struct {
    void (*send)(void*, wl_proxy*, const char*, int32_t);
    void (*cancelled)(void*, wl_proxy*);
} source_listener = {
    source_send,
    source_cancelled,
};

static void registry_global(
    void* data,
    wl_proxy* registry,
    uint32_t name,
    const char* interface,
    uint32_t version
) {
    zv3_wayland_clipboard* clipboard = (zv3_wayland_clipboard*)data;
    uint32_t bound_version = version > 1 ? 1 : version;
    (void)registry;
    if (interface == NULL || bound_version == 0) return;
    if (strcmp(interface, "wl_seat") == 0 && clipboard->seat == NULL) {
        clipboard->seat = bind_global(
            clipboard,
            name,
            clipboard->api.seat_interface,
            bound_version
        );
    } else if (strcmp(interface, "ext_data_control_manager_v1") == 0 &&
               clipboard->manager == NULL) {
        clipboard->manager = bind_global(
            clipboard,
            name,
            &data_manager_interface,
            bound_version
        );
    }
}

static void registry_global_remove(
    void* data,
    wl_proxy* registry,
    uint32_t name
) {
    (void)data;
    (void)registry;
    (void)name;
}

static const struct {
    void (*global)(void*, wl_proxy*, uint32_t, const char*, uint32_t);
    void (*global_remove)(void*, wl_proxy*, uint32_t);
} registry_listener = {
    registry_global,
    registry_global_remove,
};

static void destroy_clipboard(zv3_wayland_clipboard* clipboard) {
    if (clipboard == NULL) return;
    while (clipboard->sources != NULL) remove_source(clipboard->sources);
    while (clipboard->offers != NULL) {
        destroy_offer(clipboard, clipboard->offers);
    }
    if (clipboard->device != NULL) {
        clipboard->api.proxy_marshal_flags(
            clipboard->device,
            1,
            NULL,
            clipboard->api.proxy_get_version(clipboard->device),
            marshal_flag_destroy
        );
    }
    if (clipboard->manager != NULL) {
        clipboard->api.proxy_marshal_flags(
            clipboard->manager,
            2,
            NULL,
            clipboard->api.proxy_get_version(clipboard->manager),
            marshal_flag_destroy
        );
    }
    if (clipboard->seat != NULL) clipboard->api.proxy_destroy(clipboard->seat);
    if (clipboard->registry != NULL) {
        clipboard->api.proxy_destroy(clipboard->registry);
    }
    if (clipboard->display != NULL) {
        clipboard->api.display_flush(clipboard->display);
        clipboard->api.display_disconnect(clipboard->display);
    }
    if (clipboard->api.library != NULL) dlclose(clipboard->api.library);
    free(clipboard);
}

zv3_wayland_clipboard* zv3_wayland_clipboard_create(void) {
    zv3_wayland_clipboard* clipboard;
    {
        const char* display_name = getenv("WAYLAND_DISPLAY");
        if (display_name == NULL || display_name[0] == '\0') return NULL;
    }
    clipboard = (zv3_wayland_clipboard*)calloc(1, sizeof(*clipboard));
    if (clipboard == NULL || load_wayland(&clipboard->api) != 0) {
        free(clipboard);
        return NULL;
    }
    clipboard->display = clipboard->api.display_connect(NULL);
    if (clipboard->display == NULL) {
        destroy_clipboard(clipboard);
        return NULL;
    }
    clipboard->registry = clipboard->api.proxy_marshal_flags(
        (wl_proxy*)clipboard->display,
        1,
        clipboard->api.registry_interface,
        clipboard->api.proxy_get_version((wl_proxy*)clipboard->display),
        0,
        NULL
    );
    if (clipboard->registry == NULL ||
        clipboard->api.proxy_add_listener(
            clipboard->registry,
            (void (**)(void))&registry_listener,
            clipboard
        ) != 0 ||
        clipboard->api.display_roundtrip(clipboard->display) < 0 ||
        clipboard->seat == NULL ||
        clipboard->manager == NULL) {
        destroy_clipboard(clipboard);
        return NULL;
    }
    clipboard->device = clipboard->api.proxy_marshal_flags(
        clipboard->manager,
        1,
        &data_device_interface,
        clipboard->api.proxy_get_version(clipboard->manager),
        0,
        NULL,
        clipboard->seat
    );
    if (clipboard->device == NULL ||
        clipboard->api.proxy_add_listener(
            clipboard->device,
            (void (**)(void))&device_listener,
            clipboard
        ) != 0 ||
        clipboard->api.display_roundtrip(clipboard->display) < 0 ||
        clipboard->finished) {
        destroy_clipboard(clipboard);
        return NULL;
    }
    return clipboard;
}

void zv3_wayland_clipboard_destroy(zv3_wayland_clipboard* clipboard) {
    destroy_clipboard(clipboard);
}

int zv3_wayland_clipboard_write(
    zv3_wayland_clipboard* clipboard,
    const uint8_t* text,
    size_t length
) {
    source_slot* source;
    if (clipboard == NULL || clipboard->finished ||
        (length != 0 && text == NULL)) {
        return -1;
    }
    source = (source_slot*)calloc(1, sizeof(*source));
    if (source == NULL) return -1;
    if (length != 0) {
        source->text = (uint8_t*)malloc(length);
        if (source->text == NULL) {
            free(source);
            return -1;
        }
        memcpy(source->text, text, length);
    }
    source->clipboard = clipboard;
    source->length = length;
    source->proxy = clipboard->api.proxy_marshal_flags(
        clipboard->manager,
        0,
        &data_source_interface,
        clipboard->api.proxy_get_version(clipboard->manager),
        0,
        NULL
    );
    if (source->proxy == NULL ||
        clipboard->api.proxy_add_listener(
            source->proxy,
            (void (**)(void))&source_listener,
            source
        ) != 0) {
        if (source->proxy != NULL) clipboard->api.proxy_destroy(source->proxy);
        free(source->text);
        free(source);
        return -1;
    }
    source->next = clipboard->sources;
    clipboard->sources = source;
    clipboard->owned_source = source;
    clipboard->api.proxy_marshal_flags(
        source->proxy,
        0,
        NULL,
        clipboard->api.proxy_get_version(source->proxy),
        0,
        "text/plain;charset=utf-8"
    );
    clipboard->api.proxy_marshal_flags(
        source->proxy,
        0,
        NULL,
        clipboard->api.proxy_get_version(source->proxy),
        0,
        "text/plain"
    );
    clipboard->api.proxy_marshal_flags(
        source->proxy,
        0,
        NULL,
        clipboard->api.proxy_get_version(source->proxy),
        0,
        "UTF8_STRING"
    );
    clipboard->api.proxy_marshal_flags(
        clipboard->device,
        0,
        NULL,
        clipboard->api.proxy_get_version(clipboard->device),
        0,
        source->proxy
    );
    return flush_bounded(clipboard);
}

static const char* selected_mime(const offer_slot* offer) {
    if (offer->utf8_variant == 1) return "text/plain;charset=utf-8";
    if (offer->utf8_variant == 2) return "text/plain;charset=UTF-8";
    if (offer->utf8_variant == 3) return "UTF8_STRING";
    if (offer->plain) return "text/plain";
    return NULL;
}

static int copy_owned(
    source_slot* source,
    size_t maximum_length,
    uint8_t** text,
    size_t* length
) {
    uint8_t* result = NULL;
    if (source->length > maximum_length) return -1;
    if (source->length != 0) {
        result = (uint8_t*)malloc(source->length);
        if (result == NULL) return -1;
        memcpy(result, source->text, source->length);
    }
    *text = result;
    *length = source->length;
    return 0;
}

static int read_offer(
    zv3_wayland_clipboard* clipboard,
    offer_slot* offer,
    size_t maximum_length,
    uint8_t** text,
    size_t* length
) {
    const char* mime = selected_mime(offer);
    struct timespec deadline;
    uint8_t* result = NULL;
    size_t used = 0;
    int descriptors[2];
    int flags;
    int complete = 0;

    if (mime == NULL || pipe(descriptors) != 0) return -1;
    flags = fcntl(descriptors[0], F_GETFL, 0);
    if (flags < 0 ||
        fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) != 0 ||
        clock_gettime(CLOCK_MONOTONIC, &deadline) != 0) {
        close(descriptors[0]);
        close(descriptors[1]);
        return -1;
    }
    deadline.tv_nsec += transfer_timeout_ms * 1000000L;
    if (deadline.tv_nsec >= 1000000000L) {
        deadline.tv_sec += 1;
        deadline.tv_nsec -= 1000000000L;
    }
    clipboard->api.proxy_marshal_flags(
        offer->proxy,
        0,
        NULL,
        clipboard->api.proxy_get_version(offer->proxy),
        0,
        mime,
        descriptors[1]
    );
    close(descriptors[1]);
    if (flush_bounded(clipboard) != 0) {
        close(descriptors[0]);
        return -1;
    }

    while (!complete) {
        uint8_t buffer[4096];
        ssize_t count;
        for (;;) {
            count = read(descriptors[0], buffer, sizeof(buffer));
            if (count > 0) {
                uint8_t* grown;
                if ((size_t)count > maximum_length - used) {
                    free(result);
                    close(descriptors[0]);
                    return -1;
                }
                grown = (uint8_t*)realloc(result, used + (size_t)count);
                if (grown == NULL) {
                    free(result);
                    close(descriptors[0]);
                    return -1;
                }
                result = grown;
                memcpy(result + used, buffer, (size_t)count);
                used += (size_t)count;
                continue;
            }
            if (count == 0) {
                complete = 1;
                break;
            }
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) break;
            free(result);
            close(descriptors[0]);
            return -1;
        }
        if (!complete) {
            struct pollfd poll_descriptors[2];
            int timeout = remaining_milliseconds(&deadline);
            int poll_result;
            if (timeout == 0) {
                free(result);
                close(descriptors[0]);
                return -1;
            }
            poll_descriptors[0].fd = descriptors[0];
            poll_descriptors[0].events = POLLIN | POLLHUP;
            poll_descriptors[0].revents = 0;
            poll_descriptors[1].fd = clipboard->api.display_get_fd(
                clipboard->display
            );
            poll_descriptors[1].events = POLLIN;
            poll_descriptors[1].revents = 0;
            poll_result = poll(poll_descriptors, 2, timeout);
            if (poll_result < 0 && errno == EINTR) continue;
            if (poll_result <= 0 ||
                (poll_descriptors[0].revents & (POLLERR | POLLNVAL)) != 0 ||
                (poll_descriptors[1].revents & (POLLERR | POLLHUP | POLLNVAL)) != 0) {
                free(result);
                close(descriptors[0]);
                return -1;
            }
            if ((poll_descriptors[1].revents & POLLIN) != 0 &&
                clipboard->api.display_dispatch(clipboard->display) < 0) {
                free(result);
                close(descriptors[0]);
                return -1;
            }
        }
    }
    close(descriptors[0]);
    *text = result;
    *length = used;
    return 0;
}

int zv3_wayland_clipboard_read(
    zv3_wayland_clipboard* clipboard,
    size_t maximum_length,
    uint8_t** text,
    size_t* length
) {
    if (clipboard == NULL || text == NULL || length == NULL ||
        clipboard->finished) {
        return -1;
    }
    *text = NULL;
    *length = 0;
    if (clipboard->api.display_dispatch_pending(clipboard->display) < 0 ||
        clipboard->api.display_get_error(clipboard->display) != 0) {
        return -1;
    }
    if (clipboard->selection != NULL) {
        return read_offer(
            clipboard,
            clipboard->selection,
            maximum_length,
            text,
            length
        );
    }
    if (clipboard->owned_source != NULL) {
        return copy_owned(
            clipboard->owned_source,
            maximum_length,
            text,
            length
        );
    }
    return -1;
}

void zv3_wayland_clipboard_free(uint8_t* text) {
    free(text);
}

void zv3_wayland_clipboard_dispatch(zv3_wayland_clipboard* clipboard) {
    struct pollfd descriptor;
    if (clipboard == NULL || clipboard->finished) return;
    if (clipboard->api.display_dispatch_pending(clipboard->display) < 0) {
        clipboard->finished = 1;
        return;
    }
    descriptor.fd = clipboard->api.display_get_fd(clipboard->display);
    descriptor.events = POLLIN;
    descriptor.revents = 0;
    while (poll(&descriptor, 1, 0) > 0 &&
           (descriptor.revents & POLLIN) != 0) {
        if (clipboard->api.display_dispatch(clipboard->display) < 0) {
            clipboard->finished = 1;
            return;
        }
        descriptor.revents = 0;
    }
}

#endif
