const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn PlugFrame(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: iplugview.IPlugFrame = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        last_view: ?*iplugview.IPlugView = null,
        last_rect: iplugview.ViewRect = .{},
        resize_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *iplugview.IPlugFrame {
            return &self.iface;
        }

        fn acceptResize(self: *Self, view: ?*iplugview.IPlugView, rect: *const iplugview.ViewRect) void {
            self.last_view = view;
            self.last_rect = rect.*;
        }

        const owner = interface_map.ownerFromField(Self, iplugview.IPlugFrame, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugview.iplug_frame_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugFrame");
        }

        fn resizeView(ptr: *anyopaque, view: ?*iplugview.IPlugView, rect: *iplugview.ViewRect) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.resize_count +|= 1;
            if (@hasDecl(Config, "resizeView")) {
                const result = Config.resizeView(view, rect);
                if (result != types.kResultOk) return result;
            }
            self.acceptResize(view, rect);
            return types.kResultOk;
        }

        const vtable = iplugview.IPlugFrameVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .resizeView = resizeView,
        };
    };
}

test "plug frame stores resize requests by default" {
    const Frame = PlugFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();
    var rect = iplugview.ViewRect{ .left = 1, .top = 2, .right = 101, .bottom = 202 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.resizeView(iface, null, &rect));
    try std.testing.expectEqual(@as(types.uint32, 1), frame.resize_count);
    try std.testing.expectEqual(rect, frame.last_rect);
    try std.testing.expectEqual(@as(?*iplugview.IPlugView, null), frame.last_view);
}

test "plug frame delegates resize requests to config" {
    const Config = struct {
        var resize_count: types.uint32 = 0;
        var last_width: types.int32 = 0;

        fn resizeView(_: ?*iplugview.IPlugView, rect: *iplugview.ViewRect) types.tresult {
            resize_count += 1;
            last_width = rect.right - rect.left;
            return types.kResultFalse;
        }
    };
    const Frame = PlugFrame(Config);
    var frame = Frame{};
    const iface = frame.asInterface();
    var rect = iplugview.ViewRect{ .left = 10, .top = 0, .right = 42, .bottom = 20 };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.resizeView(iface, null, &rect));
    try std.testing.expectEqual(@as(types.uint32, 1), Config.resize_count);
    try std.testing.expectEqual(@as(types.int32, 32), Config.last_width);
    try std.testing.expectEqual(@as(types.uint32, 1), frame.resize_count);
}

test "plug frame stores accepted delegated resize state" {
    const Config = struct {
        fn resizeView(_: ?*iplugview.IPlugView, rect: *iplugview.ViewRect) types.tresult {
            rect.right = rect.left + 640;
            rect.bottom = rect.top + 480;
            return types.kResultOk;
        }
    };
    const Frame = PlugFrame(Config);
    var frame = Frame{};
    const iface = frame.asInterface();
    const view: *iplugview.IPlugView = @ptrFromInt(0x1000);
    var rect = iplugview.ViewRect{ .left = 10, .top = 20, .right = 30, .bottom = 40 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.resizeView(iface, view, &rect));
    try std.testing.expectEqual(@as(types.uint32, 1), frame.resize_count);
    try std.testing.expectEqual(view, frame.last_view.?);
    try std.testing.expectEqual(iplugview.ViewRect{ .left = 10, .top = 20, .right = 650, .bottom = 500 }, frame.last_rect);
}

test "plug frame preserves accepted resize state when delegation fails" {
    const Config = struct {
        fn resizeView(_: ?*iplugview.IPlugView, _: *iplugview.ViewRect) types.tresult {
            return types.kResultFalse;
        }
    };
    const Frame = PlugFrame(Config);
    var frame = Frame{
        .last_rect = .{ .left = 1, .top = 2, .right = 101, .bottom = 202 },
    };
    const iface = frame.asInterface();
    var rejected = iplugview.ViewRect{ .left = 10, .top = 20, .right = 30, .bottom = 40 };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.resizeView(iface, null, &rejected));
    try std.testing.expectEqual(@as(types.uint32, 1), frame.resize_count);
    try std.testing.expectEqual(iplugview.ViewRect{ .left = 1, .top = 2, .right = 101, .bottom = 202 }, frame.last_rect);
    try std.testing.expectEqual(@as(?*iplugview.IPlugView, null), frame.last_view);
}

test "plug frame supports query interface" {
    const Frame = PlugFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iplugview.iplug_frame_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_frame: *iplugview.IPlugFrame = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_frame.vtable.release(queried_frame));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), frame.ref_count.load(.seq_cst));
    const queried_unknown: *iplugview.IPlugFrame = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "plug frame clears unsupported query output" {
    const Frame = PlugFrame(struct {});
    var frame = Frame{};
    const iface = frame.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
