#ifndef ZIG_VSTGUI_ACCESSIBILITY_WAYLAND_CLIPBOARD_H
#define ZIG_VSTGUI_ACCESSIBILITY_WAYLAND_CLIPBOARD_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct zv3_wayland_clipboard zv3_wayland_clipboard;

zv3_wayland_clipboard* zv3_wayland_clipboard_create(void);
void zv3_wayland_clipboard_destroy(zv3_wayland_clipboard* clipboard);
int zv3_wayland_clipboard_write(
    zv3_wayland_clipboard* clipboard,
    const uint8_t* text,
    size_t length
);
int zv3_wayland_clipboard_read(
    zv3_wayland_clipboard* clipboard,
    size_t maximum_length,
    uint8_t** text,
    size_t* length
);
void zv3_wayland_clipboard_free(uint8_t* text);
void zv3_wayland_clipboard_dispatch(zv3_wayland_clipboard* clipboard);

#ifdef __cplusplus
}
#endif

#endif
