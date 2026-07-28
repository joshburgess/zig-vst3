#include "x11_window_shim.h"

#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct _XDisplay Display;
typedef unsigned long XID;
typedef XID Window;
typedef unsigned long Atom;

typedef struct {
    int type;
    unsigned long serial;
    int send_event;
    Display *display;
    Window window;
} XAnyEvent;

typedef struct {
    int type;
    unsigned long serial;
    int send_event;
    Display *display;
    Window event;
    Window window;
    int x;
    int y;
    int width;
    int height;
    int border_width;
    Window above;
    int override_redirect;
} XConfigureEvent;

typedef struct {
    int type;
    unsigned long serial;
    int send_event;
    Display *display;
    Window window;
    int mode;
    int detail;
} XFocusChangeEvent;

typedef union {
    char b[20];
    short s[10];
    long l[5];
} XClientMessageData;

typedef struct {
    int type;
    unsigned long serial;
    int send_event;
    Display *display;
    Window window;
    Atom message_type;
    int format;
    XClientMessageData data;
} XClientMessageEvent;

typedef union {
    int type;
    XAnyEvent xany;
    XConfigureEvent xconfigure;
    XFocusChangeEvent xfocus;
    XClientMessageEvent xclient;
    long pad[24];
} XEvent;

enum {
    focus_in = 9,
    focus_out = 10,
    configure_notify = 22,
    client_message = 33
};

#define STRUCTURE_NOTIFY_MASK (1L << 17)
#define FOCUS_CHANGE_MASK (1L << 21)

typedef struct {
    void *library;
    Display *(*open_display)(const char *);
    int (*close_display)(Display *);
    int (*default_screen)(Display *);
    Window (*root_window)(Display *, int);
    unsigned long (*black_pixel)(Display *, int);
    unsigned long (*white_pixel)(Display *, int);
    Window (*create_simple_window)(
        Display *,
        Window,
        int,
        int,
        unsigned int,
        unsigned int,
        unsigned int,
        unsigned long,
        unsigned long);
    int (*destroy_window)(Display *, Window);
    int (*store_name)(Display *, Window, const char *);
    Atom (*intern_atom)(Display *, const char *, int);
    int (*set_wm_protocols)(Display *, Window, Atom *, int);
    int (*select_input)(Display *, Window, long);
    int (*map_window)(Display *, Window);
    int (*unmap_window)(Display *, Window);
    int (*resize_window)(Display *, Window, unsigned int, unsigned int);
    int (*flush)(Display *);
    int (*pending)(Display *);
    int (*next_event)(Display *, XEvent *);
} x11_api;

struct zv3_x11_window {
    x11_api api;
    Display *display;
    Window window;
    Atom wm_delete_window;
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

#define LOAD_X11(api, field, name) \
    load_symbol((api)->library, name, &(api)->field, sizeof((api)->field))

static int load_x11(x11_api *api) {
    static const char *const names[] = {
        "libX11.so.6",
        "libX11.so"
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
        LOAD_X11(api, open_display, "XOpenDisplay") != 0 ||
        LOAD_X11(api, close_display, "XCloseDisplay") != 0 ||
        LOAD_X11(api, default_screen, "XDefaultScreen") != 0 ||
        LOAD_X11(api, root_window, "XRootWindow") != 0 ||
        LOAD_X11(api, black_pixel, "XBlackPixel") != 0 ||
        LOAD_X11(api, white_pixel, "XWhitePixel") != 0 ||
        LOAD_X11(api, create_simple_window, "XCreateSimpleWindow") != 0 ||
        LOAD_X11(api, destroy_window, "XDestroyWindow") != 0 ||
        LOAD_X11(api, store_name, "XStoreName") != 0 ||
        LOAD_X11(api, intern_atom, "XInternAtom") != 0 ||
        LOAD_X11(api, set_wm_protocols, "XSetWMProtocols") != 0 ||
        LOAD_X11(api, select_input, "XSelectInput") != 0 ||
        LOAD_X11(api, map_window, "XMapWindow") != 0 ||
        LOAD_X11(api, unmap_window, "XUnmapWindow") != 0 ||
        LOAD_X11(api, resize_window, "XResizeWindow") != 0 ||
        LOAD_X11(api, flush, "XFlush") != 0 ||
        LOAD_X11(api, pending, "XPending") != 0 ||
        LOAD_X11(api, next_event, "XNextEvent") != 0) {
        if (api->library != NULL) {
            dlclose(api->library);
        }
        memset(api, 0, sizeof(*api));
        return -1;
    }
    return 0;
}

int zv3_x11_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_x11_window **out_window) {
    zv3_x11_window *window;
    char *terminated_title;
    int screen;
    Window root;

    if (title == NULL || title_length == 0 || width == 0 || height == 0 ||
        out_window == NULL || title_length == SIZE_MAX) {
        return -1;
    }
    *out_window = NULL;
    window = (zv3_x11_window *)calloc(1, sizeof(*window));
    terminated_title = (char *)malloc(title_length + 1);
    if (window == NULL || terminated_title == NULL) {
        free(terminated_title);
        free(window);
        return -1;
    }
    memcpy(terminated_title, title, title_length);
    terminated_title[title_length] = '\0';
    if (load_x11(&window->api) != 0) {
        free(terminated_title);
        free(window);
        return -1;
    }
    window->display = window->api.open_display(NULL);
    if (window->display == NULL) {
        dlclose(window->api.library);
        free(terminated_title);
        free(window);
        return -1;
    }
    screen = window->api.default_screen(window->display);
    root = window->api.root_window(window->display, screen);
    window->window = window->api.create_simple_window(
        window->display,
        root,
        0,
        0,
        width,
        height,
        0,
        window->api.black_pixel(window->display, screen),
        window->api.white_pixel(window->display, screen));
    if (window->window == 0 ||
        window->api.store_name(
            window->display,
            window->window,
            terminated_title) == 0 ||
        window->api.select_input(
            window->display,
            window->window,
            STRUCTURE_NOTIFY_MASK | FOCUS_CHANGE_MASK) == 0) {
        if (window->window != 0) {
            window->api.destroy_window(window->display, window->window);
        }
        window->api.close_display(window->display);
        dlclose(window->api.library);
        free(terminated_title);
        free(window);
        return -1;
    }
    window->wm_delete_window = window->api.intern_atom(
        window->display,
        "WM_DELETE_WINDOW",
        0);
    if (window->wm_delete_window == 0 ||
        window->api.set_wm_protocols(
            window->display,
            window->window,
            &window->wm_delete_window,
            1) == 0) {
        window->api.destroy_window(window->display, window->window);
        window->api.close_display(window->display);
        dlclose(window->api.library);
        free(terminated_title);
        free(window);
        return -1;
    }
    window->api.flush(window->display);
    free(terminated_title);
    *out_window = window;
    return 0;
}

void zv3_x11_window_destroy(zv3_x11_window *window) {
    if (window == NULL) {
        return;
    }
    if (window->display != NULL && window->window != 0) {
        window->api.destroy_window(window->display, window->window);
        window->api.flush(window->display);
    }
    if (window->display != NULL) {
        window->api.close_display(window->display);
    }
    if (window->api.library != NULL) {
        dlclose(window->api.library);
    }
    free(window);
}

int zv3_x11_window_show(zv3_x11_window *window) {
    if (window == NULL || window->display == NULL || window->window == 0) {
        return -1;
    }
    if (window->api.map_window(window->display, window->window) == 0) {
        return -1;
    }
    window->api.flush(window->display);
    return 0;
}

int zv3_x11_window_hide(zv3_x11_window *window) {
    if (window == NULL || window->display == NULL || window->window == 0) {
        return -1;
    }
    if (window->api.unmap_window(window->display, window->window) == 0) {
        return -1;
    }
    window->api.flush(window->display);
    return 0;
}

int zv3_x11_window_resize(
    zv3_x11_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height) {
    if (window == NULL || window->display == NULL || window->window == 0 ||
        requested_width == 0 || requested_height == 0 ||
        accepted_width == NULL || accepted_height == NULL) {
        return -1;
    }
    if (window->api.resize_window(
        window->display,
        window->window,
        requested_width,
        requested_height) == 0) {
        return -1;
    }
    window->api.flush(window->display);
    *accepted_width = requested_width;
    *accepted_height = requested_height;
    return 0;
}

int zv3_x11_window_poll(
    zv3_x11_window *window,
    zv3_x11_window_event *out_event) {
    XEvent event;
    size_t index;

    if (window == NULL || window->display == NULL || window->window == 0 ||
        out_event == NULL) {
        return -1;
    }
    memset(out_event, 0, sizeof(*out_event));
    for (index = 0; index < 32; index += 1) {
        if (window->api.pending(window->display) <= 0) {
            return 0;
        }
        if (window->api.next_event(window->display, &event) != 0) {
            return -1;
        }
        if (event.xany.window != window->window) {
            continue;
        }
        if (event.type == client_message &&
            event.xclient.format == 32 &&
            (Atom)event.xclient.data.l[0] == window->wm_delete_window) {
            out_event->type = 1;
            return 0;
        }
        if (event.type == configure_notify) {
            if (event.xconfigure.width <= 0 || event.xconfigure.height <= 0) {
                return -1;
            }
            out_event->type = 2;
            out_event->width = (uint32_t)event.xconfigure.width;
            out_event->height = (uint32_t)event.xconfigure.height;
            return 0;
        }
        if (event.type == focus_in || event.type == focus_out) {
            out_event->type = 4;
            out_event->focused = event.type == focus_in ? 1U : 0U;
            return 0;
        }
    }
    return 0;
}

void *zv3_x11_window_parent(zv3_x11_window *window) {
    if (window == NULL || window->window == 0) {
        return NULL;
    }
    return (void *)(uintptr_t)window->window;
}
