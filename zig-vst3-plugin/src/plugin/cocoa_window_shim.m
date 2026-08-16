#import <AppKit/AppKit.h>

#include <limits.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "cocoa_window_shim.h"

@class ZV3StandaloneWindowDelegate;

struct zv3_cocoa_window {
    NSWindow *window;
    ZV3StandaloneWindowDelegate *delegate;
    int close_pending;
    int resize_pending;
    int scale_pending;
    int focus_pending;
    uint32_t width;
    uint32_t height;
    double scale;
    uint32_t focused;
};

@interface ZV3StandaloneWindowDelegate : NSObject <NSWindowDelegate> {
@public
    zv3_cocoa_window *state;
}
@end

static void update_size(zv3_cocoa_window *window) {
    const NSSize size = [[window->window contentView] bounds].size;

    if (size.width <= 0.0 || size.height <= 0.0 ||
        size.width > UINT32_MAX || size.height > UINT32_MAX) {
        return;
    }
    window->width = (uint32_t)llround(size.width);
    window->height = (uint32_t)llround(size.height);
    window->resize_pending = 1;
}

@implementation ZV3StandaloneWindowDelegate

- (BOOL)windowShouldClose:(NSWindow *)sender {
    (void)sender;
    state->close_pending = 1;
    return NO;
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    update_size(state);
}

- (void)windowDidChangeBackingProperties:(NSNotification *)notification {
    (void)notification;
    state->scale = [state->window backingScaleFactor];
    state->scale_pending = 1;
    update_size(state);
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    (void)notification;
    state->focused = 1;
    state->focus_pending = 1;
}

- (void)windowDidResignKey:(NSNotification *)notification {
    (void)notification;
    state->focused = 0;
    state->focus_pending = 1;
}

@end

static int valid_window(const zv3_cocoa_window *window) {
    return window != NULL && window->window != nil &&
        [NSThread isMainThread];
}

static int take_event(
    zv3_cocoa_window *window,
    zv3_cocoa_window_event *out_event) {
    if (window->close_pending != 0) {
        window->close_pending = 0;
        out_event->type = 1;
        return 1;
    }
    if (window->resize_pending != 0) {
        window->resize_pending = 0;
        out_event->type = 2;
        out_event->width = window->width;
        out_event->height = window->height;
        return 1;
    }
    if (window->scale_pending != 0) {
        window->scale_pending = 0;
        out_event->type = 3;
        out_event->scale_x = window->scale;
        out_event->scale_y = window->scale;
        return 1;
    }
    if (window->focus_pending != 0) {
        window->focus_pending = 0;
        out_event->type = 4;
        out_event->focused = window->focused;
        return 1;
    }
    return 0;
}

int zv3_cocoa_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_cocoa_window **out_window) {
    zv3_cocoa_window *window;
    NSString *window_title;
    NSRect bounds;
    NSUInteger style;

    if (title == NULL || title_length == 0 ||
        width == 0 || height == 0 ||
        out_window == NULL || ![NSThread isMainThread]) {
        return -1;
    }
    *out_window = NULL;
    @autoreleasepool {
        window_title = [[NSString alloc]
            initWithBytes:title
            length:title_length
            encoding:NSUTF8StringEncoding];
        if (window_title == nil) {
            return -1;
        }
        window = (zv3_cocoa_window *)calloc(1, sizeof(*window));
        if (window == NULL) {
            [window_title release];
            return -1;
        }
        [NSApplication sharedApplication];
        bounds = NSMakeRect(0.0, 0.0, width, height);
        style = NSWindowStyleMaskTitled |
            NSWindowStyleMaskClosable |
            NSWindowStyleMaskMiniaturizable |
            NSWindowStyleMaskResizable;
        window->window = [[NSWindow alloc]
            initWithContentRect:bounds
            styleMask:style
            backing:NSBackingStoreBuffered
            defer:NO];
        if (window->window == nil) {
            free(window);
            [window_title release];
            return -1;
        }
        window->delegate =
            [[ZV3StandaloneWindowDelegate alloc] init];
        if (window->delegate == nil) {
            [window->window release];
            free(window);
            [window_title release];
            return -1;
        }
        window->delegate->state = window;
        [window->window setDelegate:window->delegate];
        [window->window setReleasedWhenClosed:NO];
        [window->window setTitle:window_title];
        [window->window center];
        window->scale = [window->window backingScaleFactor];
        window->width = width;
        window->height = height;
        [window_title release];
        *out_window = window;
    }
    return 0;
}

void zv3_cocoa_window_destroy(zv3_cocoa_window *window) {
    if (window == NULL || ![NSThread isMainThread]) {
        return;
    }
    @autoreleasepool {
        [window->window setDelegate:nil];
        [window->window orderOut:nil];
        [window->window close];
        [window->window release];
        window->window = nil;
        window->delegate->state = NULL;
        [window->delegate release];
        window->delegate = nil;
        free(window);
    }
}

int zv3_cocoa_window_show(zv3_cocoa_window *window) {
    if (!valid_window(window)) {
        return -1;
    }
    [window->window makeKeyAndOrderFront:nil];
    return 0;
}

int zv3_cocoa_window_hide(zv3_cocoa_window *window) {
    if (!valid_window(window)) {
        return -1;
    }
    [window->window orderOut:nil];
    return 0;
}

int zv3_cocoa_window_resize(
    zv3_cocoa_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height) {
    NSSize accepted;

    if (!valid_window(window) ||
        requested_width == 0 || requested_height == 0 ||
        accepted_width == NULL || accepted_height == NULL) {
        return -1;
    }
    [window->window setContentSize:NSMakeSize(
        requested_width,
        requested_height)];
    accepted = [[window->window contentView] bounds].size;
    if (accepted.width <= 0.0 || accepted.height <= 0.0 ||
        accepted.width > UINT32_MAX || accepted.height > UINT32_MAX) {
        return -1;
    }
    *accepted_width = (uint32_t)llround(accepted.width);
    *accepted_height = (uint32_t)llround(accepted.height);
    return 0;
}

int zv3_cocoa_window_poll(
    zv3_cocoa_window *window,
    zv3_cocoa_window_event *out_event) {
    size_t index;

    if (!valid_window(window) || out_event == NULL) {
        return -1;
    }
    memset(out_event, 0, sizeof(*out_event));
    if (take_event(window, out_event) != 0) {
        return 0;
    }
    @autoreleasepool {
        for (index = 0; index < 32; index += 1) {
            NSEvent *event = [NSApp
                nextEventMatchingMask:NSEventMaskAny
                untilDate:[NSDate distantPast]
                inMode:NSDefaultRunLoopMode
                dequeue:YES];
            if (event == nil) {
                return 0;
            }
            [NSApp sendEvent:event];
            if (take_event(window, out_event) != 0) {
                return 0;
            }
        }
    }
    return 0;
}

void *zv3_cocoa_window_parent(zv3_cocoa_window *window) {
    if (!valid_window(window)) {
        return NULL;
    }
    return [window->window contentView];
}
