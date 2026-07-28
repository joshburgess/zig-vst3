const builtin = @import("builtin");
const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const gui = core.gui;
const plugin = core.plugin;

pub fn Backend(comptime Api: type) type {
    return struct {
        const Self = @This();
        const maximum_title_bytes = 128;

        title_storage: [maximum_title_bytes]u8 = undefined,
        title_length: u8,
        window: ?Api.Window = null,

        pub fn init(title: []const u8) !Self {
            if (title.len == 0) return error.EmptyWindowTitle;
            if (title.len > maximum_title_bytes)
                return error.WindowTitleTooLong;
            if (!std.unicode.utf8ValidateSlice(title) or
                std.mem.indexOfScalar(u8, title, 0) != null)
                return error.InvalidWindowTitle;
            var result = Self{
                .title_length = @intCast(title.len),
            };
            @memcpy(result.title_storage[0..title.len], title);
            return result;
        }

        pub fn windowBackend(self: *Self) plugin.StandaloneWindowBackend {
            return .{
                .context = self,
                .vtable = &window_vtable,
            };
        }

        pub fn isOpen(self: *const Self) bool {
            return self.window != null;
        }

        fn open(
            context: *anyopaque,
            size: gui.Size,
            _: gui.Scale,
        ) !gui.NativeParent {
            const self: *Self = @ptrCast(@alignCast(context));
            if (!Api.supported) return error.UnsupportedPlatform;
            if (self.window != null)
                return error.X11WindowAlreadyOpen;
            const window = try Api.open(
                self.title_storage[0..self.title_length],
                size,
            );
            const parent = Api.parent(window) orelse {
                Api.destroy(window);
                return error.X11WindowParentUnavailable;
            };
            self.window = window;
            return .{ .platform = .x11, .handle = parent };
        }

        fn close(context: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(context));
            if (self.window) |window| Api.destroy(window);
            self.window = null;
        }

        fn show(context: *anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try Api.show(
                self.window orelse return error.X11WindowNotOpen,
            );
        }

        fn hide(context: *anyopaque) !void {
            const self: *Self = @ptrCast(@alignCast(context));
            try Api.hide(
                self.window orelse return error.X11WindowNotOpen,
            );
        }

        fn requestResize(
            context: *anyopaque,
            requested: gui.Size,
        ) !gui.Size {
            const self: *Self = @ptrCast(@alignCast(context));
            return try Api.resize(
                self.window orelse return error.X11WindowNotOpen,
                requested,
            );
        }

        fn pollEvent(context: *anyopaque) !plugin.StandaloneWindowEvent {
            const self: *Self = @ptrCast(@alignCast(context));
            return try Api.poll(
                self.window orelse return error.X11WindowNotOpen,
            );
        }

        fn destroy(context: *anyopaque) void {
            close(context);
        }

        const window_vtable = plugin.StandaloneWindowBackend.VTable{
            .open = open,
            .close = close,
            .show = show,
            .hide = hide,
            .request_resize = requestResize,
            .poll_event = pollEvent,
            .destroy = destroy,
        };
    };
}

const X11SystemApi = if (builtin.os.tag == .linux)
    LinuxApi
else
    UnsupportedLinuxApi;

const UnsupportedLinuxApi = struct {
    const supported = false;
    const Window = u32;

    fn open(_: []const u8, _: gui.Size) !Window {
        return error.UnsupportedPlatform;
    }

    fn destroy(_: Window) void {}

    fn show(_: Window) !void {
        return error.UnsupportedPlatform;
    }

    fn hide(_: Window) !void {
        return error.UnsupportedPlatform;
    }

    fn resize(_: Window, _: gui.Size) !gui.Size {
        return error.UnsupportedPlatform;
    }

    fn poll(_: Window) !plugin.StandaloneWindowEvent {
        return error.UnsupportedPlatform;
    }

    fn parent(_: Window) ?*anyopaque {
        return null;
    }
};

const LinuxApi = struct {
    const c = @cImport({
        @cInclude("x11_window_shim.h");
    });

    const supported = true;
    const Window = *c.zv3_x11_window;

    fn open(title: []const u8, size: gui.Size) !Window {
        var window: ?Window = null;
        if (c.zv3_x11_window_create(
            title.ptr,
            title.len,
            size.width,
            size.height,
            &window,
        ) != 0)
            return error.X11WindowCreateFailed;
        return window orelse error.X11WindowCreateFailed;
    }

    fn destroy(window: Window) void {
        c.zv3_x11_window_destroy(window);
    }

    fn show(window: Window) !void {
        if (c.zv3_x11_window_show(window) != 0)
            return error.X11WindowShowFailed;
    }

    fn hide(window: Window) !void {
        if (c.zv3_x11_window_hide(window) != 0)
            return error.X11WindowHideFailed;
    }

    fn resize(window: Window, requested: gui.Size) !gui.Size {
        var width: u32 = 0;
        var height: u32 = 0;
        if (c.zv3_x11_window_resize(
            window,
            requested.width,
            requested.height,
            &width,
            &height,
        ) != 0)
            return error.X11WindowResizeFailed;
        if (width == 0 or height == 0)
            return error.X11WindowResizeFailed;
        return .{ .width = width, .height = height };
    }

    fn poll(window: Window) !plugin.StandaloneWindowEvent {
        var event: c.zv3_x11_window_event = undefined;
        if (c.zv3_x11_window_poll(window, &event) != 0)
            return error.X11WindowPollFailed;
        return switch (event.type) {
            0 => .none,
            1 => .close_requested,
            2 => if (event.width == 0 or event.height == 0)
                error.X11WindowInvalidEvent
            else
                .{ .resized = .{
                    .width = event.width,
                    .height = event.height,
                } },
            3 => if (!std.math.isFinite(event.scale_x) or
                !std.math.isFinite(event.scale_y) or
                event.scale_x <= 0.0 or event.scale_y <= 0.0)
                error.X11WindowInvalidEvent
            else
                .{ .scale_changed = .{
                    .x = event.scale_x,
                    .y = event.scale_y,
                } },
            4 => .{ .focus_changed = event.focused != 0 },
            else => error.X11WindowInvalidEvent,
        };
    }

    fn parent(window: Window) ?*anyopaque {
        return c.zv3_x11_window_parent(window);
    }
};

pub const X11WindowBackend = Backend(X11SystemApi);

const MockApi = struct {
    const supported = true;
    const Window = usize;

    var open_fails: bool = false;
    var destroy_count: usize = 0;
    var show_count: usize = 0;
    var hide_count: usize = 0;
    var event: plugin.StandaloneWindowEvent = .none;

    fn reset() void {
        open_fails = false;
        destroy_count = 0;
        show_count = 0;
        hide_count = 0;
        event = .none;
    }

    fn open(_: []const u8, _: gui.Size) !Window {
        if (open_fails) return error.MockOpenFailed;
        return 1;
    }

    fn destroy(_: Window) void {
        destroy_count += 1;
    }

    fn show(_: Window) !void {
        show_count += 1;
    }

    fn hide(_: Window) !void {
        hide_count += 1;
    }

    fn resize(_: Window, requested: gui.Size) !gui.Size {
        return requested;
    }

    fn poll(_: Window) !plugin.StandaloneWindowEvent {
        const result = event;
        event = .none;
        return result;
    }

    fn parent(window: Window) ?*anyopaque {
        return @ptrFromInt(window);
    }
};

test "X11 window backend adapts lifecycle resize and events" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = try TestBackend.init("Standalone Probe");
    const erased = backend.windowBackend();
    const parent = try erased.vtable.open(
        erased.context,
        .{ .width = 640, .height = 480 },
        .{},
    );
    try std.testing.expectEqual(gui.Platform.x11, parent.platform);
    try erased.vtable.show(erased.context);
    try erased.vtable.hide(erased.context);
    try std.testing.expectEqual(
        gui.Size{ .width = 900, .height = 700 },
        try erased.vtable.request_resize(
            erased.context,
            .{ .width = 900, .height = 700 },
        ),
    );
    MockApi.event = .{ .focus_changed = true };
    try std.testing.expectEqual(
        plugin.StandaloneWindowEvent{ .focus_changed = true },
        try erased.vtable.poll_event(erased.context),
    );
    erased.vtable.close(erased.context);
    erased.vtable.destroy(erased.context);
    try std.testing.expectEqual(@as(usize, 1), MockApi.destroy_count);
    try std.testing.expectEqual(@as(usize, 1), MockApi.show_count);
    try std.testing.expectEqual(@as(usize, 1), MockApi.hide_count);
}

test "X11 window backend retries failed open" {
    MockApi.reset();
    const TestBackend = Backend(MockApi);
    var backend = try TestBackend.init("Retry");
    const erased = backend.windowBackend();
    MockApi.open_fails = true;
    try std.testing.expectError(
        error.MockOpenFailed,
        erased.vtable.open(
            erased.context,
            .{ .width = 640, .height = 480 },
            .{},
        ),
    );
    try std.testing.expect(!backend.isOpen());
    MockApi.open_fails = false;
    _ = try erased.vtable.open(
        erased.context,
        .{ .width = 640, .height = 480 },
        .{},
    );
    try std.testing.expect(backend.isOpen());
    erased.vtable.destroy(erased.context);
}

test "X11 window backend validates titles" {
    const TestBackend = Backend(MockApi);
    try std.testing.expectError(
        error.EmptyWindowTitle,
        TestBackend.init(""),
    );
    try std.testing.expectError(
        error.InvalidWindowTitle,
        TestBackend.init("bad\x00title"),
    );
    try std.testing.expectError(
        error.InvalidWindowTitle,
        TestBackend.init("\xff"),
    );
    try std.testing.expectError(
        error.WindowTitleTooLong,
        TestBackend.init(&@as([129]u8, @splat('x'))),
    );
}

test "X11 window backend reports unsupported platform" {
    if (builtin.os.tag == .linux) return;
    var backend = try X11WindowBackend.init("Unsupported");
    const erased = backend.windowBackend();
    try std.testing.expectError(
        error.UnsupportedPlatform,
        erased.vtable.open(
            erased.context,
            .{ .width = 640, .height = 480 },
            .{},
        ),
    );
}
