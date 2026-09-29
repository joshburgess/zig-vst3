#ifndef ZIG_VST3_WAYLAND_WINDOW_SHIM_H
#define ZIG_VST3_WAYLAND_WINDOW_SHIM_H

#include <stddef.h>
#include <stdint.h>

typedef struct zv3_wayland_window zv3_wayland_window;

typedef struct {
    uint32_t type;
    uint32_t width;
    uint32_t height;
    double scale_x;
    double scale_y;
    uint32_t focused;
} zv3_wayland_window_event;

int zv3_wayland_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_wayland_window **out_window);
void zv3_wayland_window_destroy(zv3_wayland_window *window);
int zv3_wayland_window_show(zv3_wayland_window *window);
int zv3_wayland_window_hide(zv3_wayland_window *window);
int zv3_wayland_window_resize(
    zv3_wayland_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height);
int zv3_wayland_window_poll(
    zv3_wayland_window *window,
    zv3_wayland_window_event *out_event);
void *zv3_wayland_window_parent(zv3_wayland_window *window);
void *zv3_wayland_window_display(zv3_wayland_window *window);
void *zv3_wayland_window_xdg_surface(zv3_wayland_window *window);
void *zv3_wayland_window_xdg_toplevel(zv3_wayland_window *window);
int zv3_wayland_window_size(
    zv3_wayland_window *window,
    uint32_t *out_width,
    uint32_t *out_height);

#endif
