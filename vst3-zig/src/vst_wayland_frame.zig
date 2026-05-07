const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const iwaylandframe = @import("pluginterfaces/gui/iwaylandframe.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn WaylandFrame(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: iwaylandframe.IWaylandFrame = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *iwaylandframe.IWaylandFrame {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *iwaylandframe.IWaylandFrame = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iwaylandframe.iwayland_frame_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IWaylandFrame");
        }

        fn getWaylandSurface(_: *anyopaque, display: ?*iwaylandframe.wl_display) callconv(.C) ?*iwaylandframe.wl_surface {
            if (@hasDecl(Config, "getWaylandSurface")) {
                return Config.getWaylandSurface(display);
            }
            return null;
        }

        fn getParentSurface(_: *anyopaque, rect: *iplugview.ViewRect, display: ?*iwaylandframe.wl_display) callconv(.C) ?*iwaylandframe.xdg_surface {
            if (@hasDecl(Config, "getParentSurface")) {
                return Config.getParentSurface(rect, display);
            }
            return null;
        }

        fn getParentToplevel(_: *anyopaque, display: ?*iwaylandframe.wl_display) callconv(.C) ?*iwaylandframe.xdg_toplevel {
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

test "wayland frame returns null by default" {
    const Frame = WaylandFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();

    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(@as(?*iwaylandframe.wl_surface, null), iface.vtable.getWaylandSurface(iface, null));
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_surface, null), iface.vtable.getParentSurface(iface, &rect, null));
    try std.testing.expectEqual(@as(?*iwaylandframe.xdg_toplevel, null), iface.vtable.getParentToplevel(iface, null));
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
}
