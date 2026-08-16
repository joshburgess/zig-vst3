const std = @import("std");
const core = @import("zig-vst3-plugin-core");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iwaylandframe = @import("pluginterfaces/gui/iwaylandframe.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn StandaloneBridge(comptime Window: type) type {
    return struct {
        const Self = @This();

        plug_frame: iplugview.IPlugFrame = .{
            .vtable = &plug_frame_vtable,
        },
        wayland_frame: iwaylandframe.IWaylandFrame = .{
            .vtable = &wayland_frame_vtable,
        },
        wayland_host: iwaylandframe.IWaylandHost = .{
            .vtable = &wayland_host_vtable,
        },
        ref_count: std.atomic.Value(types.uint32) =
            std.atomic.Value(types.uint32).init(1),
        window: *Window,
        run_loop: *iplugview.Linux.IRunLoop,
        open_connection_count: types.uint32 = 0,
        resize_count: types.uint32 = 0,
        last_view: ?*iplugview.IPlugView = null,
        last_rect: iplugview.ViewRect = .{},

        pub fn init(
            window: *Window,
            run_loop: *iplugview.Linux.IRunLoop,
        ) Self {
            return .{
                .window = window,
                .run_loop = run_loop,
            };
        }

        pub fn asPlugFrame(self: *Self) *iplugview.IPlugFrame {
            return &self.plug_frame;
        }

        pub fn asWaylandHost(
            self: *Self,
        ) *iwaylandframe.IWaylandHost {
            return &self.wayland_host;
        }

        pub fn activeConnectionCount(
            self: *const Self,
        ) types.uint32 {
            return self.open_connection_count;
        }

        pub fn validateDetached(self: *const Self) !void {
            if (self.open_connection_count != 0)
                return error.WaylandConnectionStillBorrowed;
            if (self.ref_count.load(.acquire) != 1)
                return error.WaylandFrameStillRetained;
        }

        const owner_from_plug_frame = interface_map.ownerFromField(
            Self,
            iplugview.IPlugFrame,
            "plug_frame",
        );
        const owner_from_wayland_frame = interface_map.ownerFromField(
            Self,
            iwaylandframe.IWaylandFrame,
            "wayland_frame",
        );
        const owner_from_wayland_host = interface_map.ownerFromField(
            Self,
            iwaylandframe.IWaylandHost,
            "wayland_host",
        );

        fn canonicalAddRef(self: *Self) types.uint32 {
            return funknown.incrementRefCount(
                &self.ref_count,
                "WaylandStandaloneFrame",
            );
        }

        fn canonicalRelease(self: *Self) types.uint32 {
            return funknown.decrementRefCount(
                &self.ref_count,
                "WaylandStandaloneFrame",
            );
        }

        fn canonicalQuery(
            self: *Self,
            requested_iid_raw: [*c]const tuid.TUID,
            out_raw: [*c]?*anyopaque,
        ) types.tresult {
            const arguments = funknown.queryArguments(
                requested_iid_raw,
                out_raw,
            ) orelse return types.kInvalidArgument;
            const requested_iid = arguments.requested_iid;
            const out = arguments.out;
            const entries = [_]interface_map.Entry{
                .{
                    .iid = &funknown.iid,
                    .ptr = &self.plug_frame,
                },
                .{
                    .iid = &iplugview.iplug_frame_iid,
                    .ptr = &self.plug_frame,
                },
                .{
                    .iid = &iwaylandframe.iwayland_frame_iid,
                    .ptr = &self.wayland_frame,
                },
                .{
                    .iid = &iwaylandframe.iwayland_host_iid,
                    .ptr = &self.wayland_host,
                },
            };
            for (entries) |entry| {
                if (!std.mem.eql(u8, requested_iid, entry.iid))
                    continue;
                _ = self.canonicalAddRef();
                out.* = entry.ptr;
                return types.kResultOk;
            }
            if (std.mem.eql(
                u8,
                requested_iid,
                &iplugview.irun_loop_iid,
            )) {
                _ = self.run_loop.vtable.addRef(self.run_loop);
                out.* = self.run_loop;
                return types.kResultOk;
            }
            out.* = null;
            return types.kNoInterface;
        }

        fn queryFromPlugFrame(
            ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            return owner_from_plug_frame(ptr).canonicalQuery(
                requested_iid,
                out,
            );
        }

        fn queryFromWaylandFrame(
            ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            return owner_from_wayland_frame(ptr).canonicalQuery(
                requested_iid,
                out,
            );
        }

        fn queryFromWaylandHost(
            ptr: *anyopaque,
            requested_iid: [*c]const tuid.TUID,
            out: [*c]?*anyopaque,
        ) callconv(.c) types.tresult {
            return owner_from_wayland_host(ptr).canonicalQuery(
                requested_iid,
                out,
            );
        }

        fn addRefFromPlugFrame(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_plug_frame(ptr).canonicalAddRef();
        }

        fn addRefFromWaylandFrame(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_wayland_frame(ptr).canonicalAddRef();
        }

        fn addRefFromWaylandHost(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_wayland_host(ptr).canonicalAddRef();
        }

        fn releaseFromPlugFrame(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_plug_frame(ptr).canonicalRelease();
        }

        fn releaseFromWaylandFrame(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_wayland_frame(ptr).canonicalRelease();
        }

        fn releaseFromWaylandHost(
            ptr: *anyopaque,
        ) callconv(.c) types.uint32 {
            return owner_from_wayland_host(ptr).canonicalRelease();
        }

        fn resizeView(
            ptr: *anyopaque,
            view: ?*iplugview.IPlugView,
            rect_raw: [*c]iplugview.ViewRect,
        ) callconv(.c) types.tresult {
            if (rect_raw == null) return types.kInvalidArgument;
            const rect: *iplugview.ViewRect = @ptrCast(rect_raw);
            const requested = rect.*;
            if (!iplugview.hasValidDimensions(requested))
                return types.kInvalidArgument;
            const width = @as(i64, requested.right) -
                @as(i64, requested.left);
            const height = @as(i64, requested.bottom) -
                @as(i64, requested.top);
            const requested_size = core.gui.Size{
                .width = std.math.cast(u32, width) orelse
                    return types.kInvalidArgument,
                .height = std.math.cast(u32, height) orelse
                    return types.kInvalidArgument,
            };
            const self = owner_from_plug_frame(ptr);
            self.resize_count +|= 1;
            const backend = self.window.windowBackend();
            const accepted = backend.vtable.request_resize(
                backend.context,
                requested_size,
            ) catch return types.kResultFalse;
            if (accepted.width == 0 or accepted.height == 0 or
                accepted.width > std.math.maxInt(types.int32) or
                accepted.height > std.math.maxInt(types.int32))
                return types.kInvalidArgument;
            const right = std.math.add(
                types.int32,
                requested.left,
                @intCast(accepted.width),
            ) catch return types.kInvalidArgument;
            const bottom = std.math.add(
                types.int32,
                requested.top,
                @intCast(accepted.height),
            ) catch return types.kInvalidArgument;
            rect.right = right;
            rect.bottom = bottom;
            self.last_view = view;
            self.last_rect = rect.*;
            return types.kResultOk;
        }

        fn matchesDisplay(
            self: *const Self,
            display: ?*iwaylandframe.wl_display,
        ) bool {
            const current = self.window.display() orelse return false;
            const supplied = display orelse return false;
            return @intFromPtr(current) == @intFromPtr(supplied);
        }

        fn getWaylandSurface(
            ptr: *anyopaque,
            display: ?*iwaylandframe.wl_display,
        ) callconv(.c) ?*iwaylandframe.wl_surface {
            const self = owner_from_wayland_frame(ptr);
            if (!self.matchesDisplay(display)) return null;
            const parent = self.window.parentSurface() orelse
                return null;
            return @ptrCast(parent);
        }

        fn clearRect(rect: *iplugview.ViewRect) void {
            rect.* = .{};
        }

        fn getParentSurface(
            ptr: *anyopaque,
            rect_raw: [*c]iplugview.ViewRect,
            display: ?*iwaylandframe.wl_display,
        ) callconv(.c) ?*iwaylandframe.xdg_surface {
            if (rect_raw == null) return null;
            const rect: *iplugview.ViewRect = @ptrCast(rect_raw);
            const self = owner_from_wayland_frame(ptr);
            if (!self.matchesDisplay(display)) {
                clearRect(rect);
                return null;
            }
            const size = self.window.currentSize() orelse {
                clearRect(rect);
                return null;
            };
            if (size.width == 0 or size.height == 0 or
                size.width > std.math.maxInt(types.int32) or
                size.height > std.math.maxInt(types.int32))
            {
                clearRect(rect);
                return null;
            }
            const surface = self.window.xdgSurface() orelse {
                clearRect(rect);
                return null;
            };
            rect.* = .{
                .right = @intCast(size.width),
                .bottom = @intCast(size.height),
            };
            return @ptrCast(surface);
        }

        fn getParentToplevel(
            ptr: *anyopaque,
            display: ?*iwaylandframe.wl_display,
        ) callconv(.c) ?*iwaylandframe.xdg_toplevel {
            const self = owner_from_wayland_frame(ptr);
            if (!self.matchesDisplay(display)) return null;
            const toplevel = self.window.xdgToplevel() orelse
                return null;
            return @ptrCast(toplevel);
        }

        fn openWaylandConnection(
            ptr: *anyopaque,
        ) callconv(.c) ?*iwaylandframe.wl_display {
            const self = owner_from_wayland_host(ptr);
            const display = self.window.display() orelse return null;
            if (self.open_connection_count ==
                std.math.maxInt(types.uint32))
                return null;
            self.open_connection_count += 1;
            return @ptrCast(display);
        }

        fn closeWaylandConnection(
            ptr: *anyopaque,
            display: ?*iwaylandframe.wl_display,
        ) callconv(.c) types.tresult {
            const self = owner_from_wayland_host(ptr);
            if (!self.matchesDisplay(display) or
                self.open_connection_count == 0)
                return types.kInvalidArgument;
            self.open_connection_count -= 1;
            return types.kResultOk;
        }

        const plug_frame_vtable = iplugview.IPlugFrameVTable{
            .queryInterface = queryFromPlugFrame,
            .addRef = addRefFromPlugFrame,
            .release = releaseFromPlugFrame,
            .resizeView = resizeView,
        };

        const wayland_frame_vtable =
            iwaylandframe.IWaylandFrameVTable{
                .queryInterface = queryFromWaylandFrame,
                .addRef = addRefFromWaylandFrame,
                .release = releaseFromWaylandFrame,
                .getWaylandSurface = getWaylandSurface,
                .getParentSurface = getParentSurface,
                .getParentToplevel = getParentToplevel,
            };

        const wayland_host_vtable =
            iwaylandframe.IWaylandHostVTable{
                .queryInterface = queryFromWaylandHost,
                .addRef = addRefFromWaylandHost,
                .release = releaseFromWaylandHost,
                .openWaylandConnection = openWaylandConnection,
                .closeWaylandConnection = closeWaylandConnection,
            };
    };
}

const TestWindow = struct {
    opened: bool = true,
    reject_resize: bool = false,
    current_size: core.gui.Size = .{
        .width = 640,
        .height = 480,
    },

    fn display(self: *const TestWindow) ?*anyopaque {
        return if (self.opened) @ptrFromInt(0x1000) else null;
    }

    fn parentSurface(self: *const TestWindow) ?*anyopaque {
        return if (self.opened) @ptrFromInt(0x2000) else null;
    }

    fn xdgSurface(self: *const TestWindow) ?*anyopaque {
        return if (self.opened) @ptrFromInt(0x3000) else null;
    }

    fn xdgToplevel(self: *const TestWindow) ?*anyopaque {
        return if (self.opened) @ptrFromInt(0x4000) else null;
    }

    fn currentSize(self: *const TestWindow) ?core.gui.Size {
        return if (self.opened) self.current_size else null;
    }

    fn windowBackend(
        self: *TestWindow,
    ) core.plugin.StandaloneWindowBackend {
        return .{
            .context = self,
            .vtable = &window_vtable,
        };
    }

    fn resize(
        ptr: *anyopaque,
        requested: core.gui.Size,
    ) anyerror!core.gui.Size {
        const self: *TestWindow = @ptrCast(@alignCast(ptr));
        if (self.reject_resize) return error.ResizeRejected;
        self.current_size = requested;
        return requested;
    }

    fn unusedOpen(
        _: *anyopaque,
        _: core.gui.Size,
        _: core.gui.Scale,
    ) anyerror!core.gui.NativeParent {
        return error.Unsupported;
    }

    fn unusedVoid(_: *anyopaque) void {}

    fn unusedFallible(_: *anyopaque) anyerror!void {
        return error.Unsupported;
    }

    fn unusedPoll(
        _: *anyopaque,
    ) anyerror!core.plugin.StandaloneWindowEvent {
        return error.Unsupported;
    }

    const window_vtable =
        core.plugin.StandaloneWindowBackend.VTable{
            .open = unusedOpen,
            .close = unusedVoid,
            .show = unusedFallible,
            .hide = unusedFallible,
            .request_resize = resize,
            .poll_event = unusedPoll,
            .destroy = unusedVoid,
        };
};

test "standalone Wayland bridge exposes canonical frame interfaces" {
    const Loop = @import("vst_linux_run_loop.zig").RunLoop(1, 1);
    const Bridge = StandaloneBridge(TestWindow);
    var window = TestWindow{};
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());
    const plug_frame = bridge.asPlugFrame();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        plug_frame.vtable.queryInterface(
            plug_frame,
            &iwaylandframe.iwayland_frame_iid,
            &queried,
        ),
    );
    const frame: *iwaylandframe.IWaylandFrame =
        @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(
        @as(usize, 0x2000),
        @intFromPtr(frame.vtable.getWaylandSurface(
            frame,
            @ptrFromInt(0x1000),
        ).?),
    );
    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(
        @as(usize, 0x3000),
        @intFromPtr(frame.vtable.getParentSurface(
            frame,
            &rect,
            @ptrFromInt(0x1000),
        ).?),
    );
    try std.testing.expectEqual(
        iplugview.ViewRect{ .right = 640, .bottom = 480 },
        rect,
    );
    try std.testing.expectEqual(
        @as(usize, 0x4000),
        @intFromPtr(frame.vtable.getParentToplevel(
            frame,
            @ptrFromInt(0x1000),
        ).?),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        frame.vtable.release(frame),
    );

    queried = null;
    try std.testing.expectEqual(
        types.kResultOk,
        plug_frame.vtable.queryInterface(
            plug_frame,
            &iplugview.irun_loop_iid,
            &queried,
        ),
    );
    const queried_loop: *iplugview.Linux.IRunLoop =
        @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(loop.asInterface(), queried_loop);
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        queried_loop.vtable.release(queried_loop),
    );

    queried = plug_frame;
    try std.testing.expectEqual(
        types.kNoInterface,
        plug_frame.vtable.queryInterface(
            plug_frame,
            &tuid.zero,
            &queried,
        ),
    );
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "standalone Wayland bridge preserves one COM identity" {
    const Loop = @import("vst_linux_run_loop.zig").RunLoop(1, 1);
    const Bridge = StandaloneBridge(TestWindow);
    var window = TestWindow{};
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        bridge.asWaylandHost().vtable.queryInterface(
            bridge.asWaylandHost(),
            &funknown.iid,
            &queried,
        ),
    );
    try std.testing.expectEqual(
        @as(?*anyopaque, bridge.asPlugFrame()),
        queried,
    );
    const unknown: *iplugview.IPlugFrame =
        @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        unknown.vtable.release(unknown),
    );
}

test "standalone Wayland bridge tracks connection borrows" {
    const Loop = @import("vst_linux_run_loop.zig").RunLoop(1, 1);
    const Bridge = StandaloneBridge(TestWindow);
    var window = TestWindow{};
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());
    const host = bridge.asWaylandHost();

    const display = host.vtable.openWaylandConnection(host).?;
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        bridge.activeConnectionCount(),
    );
    try std.testing.expectError(
        error.WaylandConnectionStillBorrowed,
        bridge.validateDetached(),
    );
    try std.testing.expectEqual(
        types.kInvalidArgument,
        host.vtable.closeWaylandConnection(
            host,
            @ptrFromInt(0x5000),
        ),
    );
    try std.testing.expectEqual(
        types.kResultOk,
        host.vtable.closeWaylandConnection(host, display),
    );
    try bridge.validateDetached();
    try std.testing.expectEqual(
        types.kInvalidArgument,
        host.vtable.closeWaylandConnection(host, display),
    );
}

test "standalone Wayland bridge negotiates parent resize" {
    const Loop = @import("vst_linux_run_loop.zig").RunLoop(1, 1);
    const Bridge = StandaloneBridge(TestWindow);
    var window = TestWindow{};
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());
    const plug_frame = bridge.asPlugFrame();
    const view: *iplugview.IPlugView = @ptrFromInt(0x6000);
    var rect = iplugview.ViewRect{
        .left = 10,
        .top = 20,
        .right = 810,
        .bottom = 620,
    };

    try std.testing.expectEqual(
        types.kResultOk,
        plug_frame.vtable.resizeView(plug_frame, view, &rect),
    );
    try std.testing.expectEqual(
        core.gui.Size{ .width = 800, .height = 600 },
        window.current_size,
    );
    try std.testing.expectEqual(rect, bridge.last_rect);
    try std.testing.expectEqual(view, bridge.last_view.?);
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        bridge.resize_count,
    );

    window.reject_resize = true;
    const rejected = iplugview.ViewRect{
        .left = 0,
        .top = 0,
        .right = 320,
        .bottom = 240,
    };
    rect = rejected;
    try std.testing.expectEqual(
        types.kResultFalse,
        plug_frame.vtable.resizeView(plug_frame, null, &rect),
    );
    try std.testing.expectEqual(rejected, rect);
    try std.testing.expectEqual(
        @as(types.uint32, 2),
        bridge.resize_count,
    );
}

test "standalone Wayland bridge rejects closed or foreign displays" {
    const Loop = @import("vst_linux_run_loop.zig").RunLoop(1, 1);
    const Bridge = StandaloneBridge(TestWindow);
    var window = TestWindow{};
    var loop = Loop{};
    var bridge = Bridge.init(&window, loop.asInterface());

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        bridge.asPlugFrame().vtable.queryInterface(
            bridge.asPlugFrame(),
            &iwaylandframe.iwayland_frame_iid,
            &queried,
        ),
    );
    const frame: *iwaylandframe.IWaylandFrame =
        @ptrCast(@alignCast(queried.?));
    var rect = iplugview.ViewRect{
        .right = 1,
        .bottom = 1,
    };
    try std.testing.expectEqual(
        @as(?*iwaylandframe.wl_surface, null),
        frame.vtable.getWaylandSurface(
            frame,
            @ptrFromInt(0x5000),
        ),
    );
    try std.testing.expectEqual(
        @as(?*iwaylandframe.xdg_surface, null),
        frame.vtable.getParentSurface(
            frame,
            &rect,
            @ptrFromInt(0x5000),
        ),
    );
    try std.testing.expectEqual(iplugview.ViewRect{}, rect);

    window.opened = false;
    try std.testing.expectEqual(
        @as(?*iwaylandframe.wl_display, null),
        bridge.asWaylandHost().vtable.openWaylandConnection(
            bridge.asWaylandHost(),
        ),
    );
    try std.testing.expectEqual(
        @as(?*iwaylandframe.xdg_toplevel, null),
        frame.vtable.getParentToplevel(
            frame,
            @ptrFromInt(0x1000),
        ),
    );
    try std.testing.expectEqual(
        @as(types.uint32, 1),
        frame.vtable.release(frame),
    );
}
