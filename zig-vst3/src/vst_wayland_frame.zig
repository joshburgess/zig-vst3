const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const iwaylandframe = @import("pluginterfaces/gui/iwaylandframe.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn WaylandHost(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: iwaylandframe.IWaylandHost = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        open_count: types.uint32 = 0,
        close_count: types.uint32 = 0,
        last_closed_display: ?*iwaylandframe.wl_display = null,

        pub fn asInterface(self: *Self) *iwaylandframe.IWaylandHost {
            return &self.iface;
        }

        fn acceptClose(self: *Self, display: ?*iwaylandframe.wl_display) void {
            self.last_closed_display = display;
        }

        const owner = interface_map.ownerFromField(Self, iwaylandframe.IWaylandHost, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iwaylandframe.iwayland_host_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IWaylandHost");
        }

        fn openWaylandConnection(ptr: *anyopaque) callconv(.c) ?*iwaylandframe.wl_display {
            const self = owner(ptr);
            self.open_count +|= 1;
            if (@hasDecl(Config, "openWaylandConnection")) return Config.openWaylandConnection(self);
            return null;
        }

        fn closeWaylandConnection(ptr: *anyopaque, display: ?*iwaylandframe.wl_display) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.close_count +|= 1;
            if (@hasDecl(Config, "closeWaylandConnection")) {
                const result = Config.closeWaylandConnection(self, display);
                if (result != types.kResultOk) return result;
            }
            self.acceptClose(display);
            return types.kResultOk;
        }

        const vtable = iwaylandframe.IWaylandHostVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .openWaylandConnection = openWaylandConnection,
            .closeWaylandConnection = closeWaylandConnection,
        };
    };
}

pub fn WaylandFrame(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: iwaylandframe.IWaylandFrame = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        surface_count: types.uint32 = 0,
        parent_surface_count: types.uint32 = 0,
        parent_toplevel_count: types.uint32 = 0,
        last_display: ?*iwaylandframe.wl_display = null,
        last_parent_rect: iplugview.ViewRect = .{},

        pub fn asInterface(self: *Self) *iwaylandframe.IWaylandFrame {
            return &self.iface;
        }

        fn recordDisplay(self: *Self, display: ?*iwaylandframe.wl_display) void {
            self.last_display = display;
        }

        fn acceptParentRect(self: *Self, rect: *const iplugview.ViewRect) void {
            self.last_parent_rect = rect.*;
        }

        const owner = interface_map.ownerFromField(Self, iwaylandframe.IWaylandFrame, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iwaylandframe.iwayland_frame_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IWaylandFrame");
        }

        fn getWaylandSurface(ptr: *anyopaque, display: ?*iwaylandframe.wl_display) callconv(.c) ?*iwaylandframe.wl_surface {
            const self = owner(ptr);
            self.surface_count +|= 1;
            self.recordDisplay(display);
            if (@hasDecl(Config, "getWaylandSurface")) {
                return Config.getWaylandSurface(display);
            }
            return null;
        }

        fn failParentSurface(self: *Self, rect: *iplugview.ViewRect) ?*iwaylandframe.xdg_surface {
            rect.* = .{};
            self.acceptParentRect(rect);
            return null;
        }

        fn getParentSurface(ptr: *anyopaque, rect_raw: [*c]iplugview.ViewRect, display: ?*iwaylandframe.wl_display) callconv(.c) ?*iwaylandframe.xdg_surface {
            if (rect_raw == null) return null;
            const rect: *iplugview.ViewRect = @ptrCast(rect_raw);
            const self = owner(ptr);
            self.parent_surface_count +|= 1;
            self.recordDisplay(display);
            if (@hasDecl(Config, "getParentSurface")) {
                const surface = Config.getParentSurface(rect, display);
                if (surface == null) return self.failParentSurface(rect);
                self.acceptParentRect(rect);
                return surface;
            }
            return self.failParentSurface(rect);
        }

        fn getParentToplevel(ptr: *anyopaque, display: ?*iwaylandframe.wl_display) callconv(.c) ?*iwaylandframe.xdg_toplevel {
            const self = owner(ptr);
            self.parent_toplevel_count +|= 1;
            self.recordDisplay(display);
            if (@hasDecl(Config, "getParentToplevel")) {
                return Config.getParentToplevel(display);
            }
            return null;
        }

        const vtable = iwaylandframe.IWaylandFrameVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getWaylandSurface = getWaylandSurface,
            .getParentSurface = getParentSurface,
            .getParentToplevel = getParentToplevel,
        };
    };
}

test "wayland host returns null display by default and tracks close" {
    const Host = WaylandHost(struct {});
    var host = Host{};
    const iface = host.asInterface();

    try std.testing.expectEqual(@as(?*iwaylandframe.wl_display, null), iface.vtable.openWaylandConnection(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.closeWaylandConnection(iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);
    try std.testing.expectEqual(@as(?*iwaylandframe.wl_display, null), host.last_closed_display);
}

test "wayland host delegates connection hooks" {
    const display: *iwaylandframe.wl_display = @ptrFromInt(0x1000);
    const Host = WaylandHost(struct {
        pub fn openWaylandConnection(self: anytype) ?*iwaylandframe.wl_display {
            _ = self;
            return display;
        }

        pub fn closeWaylandConnection(self: anytype, value: ?*iwaylandframe.wl_display) types.tresult {
            _ = self;
            return if (value == display) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    try std.testing.expectEqual(display, iface.vtable.openWaylandConnection(iface).?);
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.closeWaylandConnection(iface, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.closeWaylandConnection(iface, display));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 2), host.close_count);
    try std.testing.expectEqual(display, host.last_closed_display.?);
}

test "wayland host preserves last accepted close display on rejection" {
    const display: *iwaylandframe.wl_display = @ptrFromInt(0x1000);
    const other_display: *iwaylandframe.wl_display = @ptrFromInt(0x2000);
    const Host = WaylandHost(struct {
        pub fn closeWaylandConnection(_: anytype, value: ?*iwaylandframe.wl_display) types.tresult {
            return if (value == display) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.closeWaylandConnection(iface, display));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.closeWaylandConnection(iface, other_display));
    try std.testing.expectEqual(@as(types.uint32, 2), host.close_count);
    try std.testing.expectEqual(display, host.last_closed_display.?);
}

test "wayland host supports query interface" {
    const Host = WaylandHost(struct {});
    var host = Host{};
    const iface = host.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iwaylandframe.iwayland_host_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_host: *iwaylandframe.IWaylandHost = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_host.vtable.release(queried_host));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), host.ref_count.load(.seq_cst));
    const queried_unknown: *iwaylandframe.IWaylandHost = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "wayland host clears unsupported query output" {
    const Host = WaylandHost(struct {});
    var host = Host{};
    const iface = host.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "wayland frame returns null by default" {
    const Frame = WaylandFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();

    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(@as(?*iwaylandframe.wl_surface, null), iface.vtable.getWaylandSurface(iface, null));
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_surface, null), iface.vtable.getParentSurface(iface, null, null));
    try std.testing.expectEqual(@as(types.uint32, 0), frame.parent_surface_count);
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_surface, null), iface.vtable.getParentSurface(iface, &rect, null));
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_toplevel, null), iface.vtable.getParentToplevel(iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), frame.surface_count);
    try std.testing.expectEqual(@as(types.uint32, 1), frame.parent_surface_count);
    try std.testing.expectEqual(@as(types.uint32, 1), frame.parent_toplevel_count);
    try std.testing.expectEqual(@as(iplugview.ViewRect, .{}), frame.last_parent_rect);
}

test "wayland frame delegates surface hooks" {
    const display: *iwaylandframe.wl_display = @ptrFromInt(0x1000);
    const surface: *iwaylandframe.wl_surface = @ptrFromInt(0x2000);
    const parent: *iwaylandframe.xdg_surface = @ptrFromInt(0x3000);
    const toplevel: *iwaylandframe.xdg_toplevel = @ptrFromInt(0x4000);
    const Frame = WaylandFrame(struct {
        pub fn getWaylandSurface(value: ?*iwaylandframe.wl_display) ?*iwaylandframe.wl_surface {
            return if (value == display) surface else null;
        }

        pub fn getParentSurface(rect: *iplugview.ViewRect, value: ?*iwaylandframe.wl_display) ?*iwaylandframe.xdg_surface {
            rect.left = 11;
            rect.top = 22;
            rect.right = 33;
            rect.bottom = 44;
            return if (value == display) parent else null;
        }

        pub fn getParentToplevel(value: ?*iwaylandframe.wl_display) ?*iwaylandframe.xdg_toplevel {
            return if (value == display) toplevel else null;
        }
    });
    var frame = Frame{};
    const iface = frame.asInterface();
    var rect = iplugview.ViewRect{};

    try std.testing.expectEqual(surface, iface.vtable.getWaylandSurface(iface, display).?);
    try std.testing.expectEqual(@as(?*iwaylandframe.wl_surface, null), iface.vtable.getWaylandSurface(iface, null));
    try std.testing.expectEqual(parent, iface.vtable.getParentSurface(iface, &rect, display).?);
    try std.testing.expectEqual(@as(types.int32, 11), rect.left);
    try std.testing.expectEqual(@as(types.int32, 22), rect.top);
    try std.testing.expectEqual(@as(types.int32, 33), rect.right);
    try std.testing.expectEqual(@as(types.int32, 44), rect.bottom);
    try std.testing.expectEqual(rect, frame.last_parent_rect);
    rect = .{ .left = 1, .top = 2, .right = 3, .bottom = 4 };
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_surface, null), iface.vtable.getParentSurface(iface, &rect, null));
    try std.testing.expectEqual(@as(iplugview.ViewRect, .{}), rect);
    try std.testing.expectEqual(@as(iplugview.ViewRect, .{}), frame.last_parent_rect);
    try std.testing.expectEqual(toplevel, iface.vtable.getParentToplevel(iface, display).?);
    try std.testing.expectEqual(@as(types.uint32, 2), frame.surface_count);
    try std.testing.expectEqual(@as(types.uint32, 2), frame.parent_surface_count);
    try std.testing.expectEqual(@as(types.uint32, 1), frame.parent_toplevel_count);
    try std.testing.expectEqual(display, frame.last_display.?);
}

test "wayland frame supports query interface" {
    const Frame = WaylandFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iwaylandframe.iwayland_frame_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_frame: *iwaylandframe.IWaylandFrame = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_frame.vtable.release(queried_frame));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), frame.ref_count.load(.seq_cst));
    const queried_unknown: *iwaylandframe.IWaylandFrame = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "wayland frame clears unsupported query output" {
    const Frame = WaylandFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
