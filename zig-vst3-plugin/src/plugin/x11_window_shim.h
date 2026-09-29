#ifndef ZIG_VST3_X11_WINDOW_SHIM_H
#define ZIG_VST3_X11_WINDOW_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef struct zv3_x11_window zv3_x11_window;

typedef struct {
    uint32_t type;
    uint32_t width;
    uint32_t height;
    double scale_x;
    double scale_y;
    uint32_t focused;
} zv3_x11_window_event;

int zv3_x11_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_x11_window **out_window);
void zv3_x11_window_destroy(zv3_x11_window *window);
int zv3_x11_window_show(zv3_x11_window *window);
int zv3_x11_window_hide(zv3_x11_window *window);
int zv3_x11_window_resize(
    zv3_x11_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height);
int zv3_x11_window_poll(
    zv3_x11_window *window,
    zv3_x11_window_event *out_event);
void *zv3_x11_window_parent(zv3_x11_window *window);

#endif
