#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <limits.h>
#include <stdlib.h>

#include "win_window_shim.h"

struct zv3_win_window {
    HWND handle;
    int close_pending;
    int resize_pending;
    int scale_pending;
    int focus_pending;
    uint32_t width;
    uint32_t height;
    double scale;
    uint32_t focused;
};

static const wchar_t window_class_name[] = L"zig-vst3-standalone-window";
static INIT_ONCE window_class_once = INIT_ONCE_STATIC_INIT;

static void update_client_size(zv3_win_window *window) {
    RECT bounds;

    if (GetClientRect(window->handle, &bounds) == 0) {
        return;
    }
    window->width = (uint32_t)(bounds.right - bounds.left);
    window->height = (uint32_t)(bounds.bottom - bounds.top);
    window->resize_pending = 1;
}

static LRESULT CALLBACK window_proc(
    HWND handle,
    UINT message,
    WPARAM word,
    LPARAM data) {
    zv3_win_window *window =
        (zv3_win_window *)(uintptr_t)GetWindowLongPtrW(
            handle,
            GWLP_USERDATA);

    if (message == WM_NCCREATE) {
        const CREATESTRUCTW *creation = (const CREATESTRUCTW *)data;
        window = (zv3_win_window *)creation->lpCreateParams;
        window->handle = handle;
        SetWindowLongPtrW(
            handle,
            GWLP_USERDATA,
            (LONG_PTR)(uintptr_t)window);
    }
    if (window == NULL) {
        return DefWindowProcW(handle, message, word, data);
    }

    switch (message) {
        case WM_CLOSE:
            window->close_pending = 1;
            return 0;
        case WM_SIZE:
            if (word != SIZE_MINIMIZED) {
                window->width = (uint32_t)LOWORD(data);
                window->height = (uint32_t)HIWORD(data);
                window->resize_pending = 1;
            }
            return 0;
        case WM_DPICHANGED: {
            const RECT *suggested = (const RECT *)data;
            const uint32_t dpi = (uint32_t)HIWORD(word);
            window->scale = (double)dpi / 96.0;
            window->scale_pending = 1;
            SetWindowPos(
                handle,
                NULL,
                suggested->left,
                suggested->top,
                suggested->right - suggested->left,
                suggested->bottom - suggested->top,
                SWP_NOACTIVATE | SWP_NOZORDER);
            return 0;
        }
        case WM_SETFOCUS:
            window->focused = 1;
            window->focus_pending = 1;
            return 0;
        case WM_KILLFOCUS:
            window->focused = 0;
            window->focus_pending = 1;
            return 0;
        default:
            return DefWindowProcW(handle, message, word, data);
    }
}

static BOOL CALLBACK register_window_class(
    PINIT_ONCE once,
    PVOID parameter,
    PVOID *context) {
    WNDCLASSEXW description;
    HINSTANCE instance = GetModuleHandleW(NULL);

    (void)once;
    (void)parameter;
    (void)context;
    ZeroMemory(&description, sizeof(description));
    description.cbSize = sizeof(description);
    description.style = CS_HREDRAW | CS_VREDRAW;
    description.lpfnWndProc = window_proc;
    description.hInstance = instance;
    description.hCursor = LoadCursorW(
        NULL,
        MAKEINTRESOURCEW(32512));
    description.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    description.lpszClassName = window_class_name;
    return RegisterClassExW(&description) != 0 ||
        GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
}

static int take_event(
    zv3_win_window *window,
    zv3_win_window_event *out_event) {
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

int zv3_win_window_create(
    const uint8_t *title,
    size_t title_length,
    uint32_t width,
    uint32_t height,
    zv3_win_window **out_window) {
    wchar_t wide_title[129];
    zv3_win_window *window;
    RECT bounds;
    int wide_length;

    if (title == NULL || title_length == 0 || title_length > 128 ||
        width == 0 || height == 0 ||
        width > INT_MAX || height > INT_MAX ||
        out_window == NULL) {
        return -1;
    }
    *out_window = NULL;
    wide_length = MultiByteToWideChar(
        CP_UTF8,
        MB_ERR_INVALID_CHARS,
        (const char *)title,
        (int)title_length,
        wide_title,
        128);
    if (wide_length <= 0) {
        return -1;
    }
    wide_title[wide_length] = L'\0';
    if (InitOnceExecuteOnce(
        &window_class_once,
        register_window_class,
        NULL,
        NULL) == 0) {
        return -1;
    }

    window = (zv3_win_window *)calloc(1, sizeof(*window));
    if (window == NULL) {
        return -1;
    }
    window->scale = 1.0;
    bounds.left = 0;
    bounds.top = 0;
    bounds.right = (LONG)width;
    bounds.bottom = (LONG)height;
    if (AdjustWindowRectEx(
        &bounds,
        WS_OVERLAPPEDWINDOW,
        FALSE,
        0) == 0) {
        free(window);
        return -1;
    }
    window->handle = CreateWindowExW(
        0,
        window_class_name,
        wide_title,
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        bounds.right - bounds.left,
        bounds.bottom - bounds.top,
        NULL,
        NULL,
        GetModuleHandleW(NULL),
        window);
    if (window->handle == NULL) {
        free(window);
        return -1;
    }
    window->resize_pending = 0;
    *out_window = window;
    return 0;
}

void zv3_win_window_destroy(zv3_win_window *window) {
    if (window == NULL) {
        return;
    }
    if (window->handle != NULL) {
        DestroyWindow(window->handle);
        window->handle = NULL;
    }
    free(window);
}

int zv3_win_window_show(zv3_win_window *window) {
    if (window == NULL || window->handle == NULL) {
        return -1;
    }
    ShowWindow(window->handle, SW_SHOW);
    UpdateWindow(window->handle);
    return 0;
}

int zv3_win_window_hide(zv3_win_window *window) {
    if (window == NULL || window->handle == NULL) {
        return -1;
    }
    ShowWindow(window->handle, SW_HIDE);
    return 0;
}

int zv3_win_window_resize(
    zv3_win_window *window,
    uint32_t requested_width,
    uint32_t requested_height,
    uint32_t *accepted_width,
    uint32_t *accepted_height) {
    RECT bounds;
    LONG_PTR style;
    LONG_PTR extended_style;

    if (window == NULL || window->handle == NULL ||
        requested_width == 0 || requested_height == 0 ||
        requested_width > INT_MAX || requested_height > INT_MAX ||
        accepted_width == NULL || accepted_height == NULL) {
        return -1;
    }
    style = GetWindowLongPtrW(window->handle, GWL_STYLE);
    extended_style = GetWindowLongPtrW(
        window->handle,
        GWL_EXSTYLE);
    bounds.left = 0;
    bounds.top = 0;
    bounds.right = (LONG)requested_width;
    bounds.bottom = (LONG)requested_height;
    if (AdjustWindowRectEx(
        &bounds,
        (DWORD)style,
        FALSE,
        (DWORD)extended_style) == 0) {
        return -1;
    }
    if (SetWindowPos(
        window->handle,
        NULL,
        0,
        0,
        bounds.right - bounds.left,
        bounds.bottom - bounds.top,
        SWP_NOMOVE | SWP_NOACTIVATE | SWP_NOZORDER) == 0) {
        return -1;
    }
    update_client_size(window);
    *accepted_width = window->width;
    *accepted_height = window->height;
    return 0;
}

int zv3_win_window_poll(
    zv3_win_window *window,
    zv3_win_window_event *out_event) {
    MSG message;
    size_t index;

    if (window == NULL || window->handle == NULL ||
        out_event == NULL) {
        return -1;
    }
    ZeroMemory(out_event, sizeof(*out_event));
    if (take_event(window, out_event) != 0) {
        return 0;
    }
    for (index = 0; index < 32; index += 1) {
        if (PeekMessageW(
            &message,
            window->handle,
            0,
            0,
            PM_REMOVE) == 0) {
            return 0;
        }
        TranslateMessage(&message);
        DispatchMessageW(&message);
        if (take_event(window, out_event) != 0) {
            return 0;
        }
    }
    return 0;
}

void *zv3_win_window_parent(zv3_win_window *window) {
    return window == NULL ? NULL : window->handle;
}
