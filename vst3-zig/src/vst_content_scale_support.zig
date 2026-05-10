const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const scale_support = @import("pluginterfaces/gui/iplugviewcontentscalesupport.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn ContentScaleSupport(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: scale_support.IPlugViewContentScaleSupport = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        scale_factor: scale_support.ScaleFactor = 1.0,

        pub fn asInterface(self: *Self) *scale_support.IPlugViewContentScaleSupport {
            return &self.iface;
        }

        pub fn currentScaleFactor(self: *const Self) scale_support.ScaleFactor {
            return self.scale_factor;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *scale_support.IPlugViewContentScaleSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &scale_support.iplug_view_content_scale_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugViewContentScaleSupport");
        }

        fn setContentScaleFactor(ptr: *anyopaque, factor: scale_support.ScaleFactor) callconv(.C) types.tresult {
            if (factor <= 0 or !std.math.isFinite(factor)) return types.kInvalidArgument;
            if (@hasDecl(Config, "setContentScaleFactor")) {
                const result = Config.setContentScaleFactor(factor);
                if (result != types.kResultOk) return result;
            }
            owner(ptr).scale_factor = factor;
            return types.kResultOk;
        }

        const vtable = scale_support.IPlugViewContentScaleSupportVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .setContentScaleFactor = setContentScaleFactor,
        };
    };
}

test "content scale support stores positive scale factors" {
    const Support = ContentScaleSupport(struct {});
    var support = Support{};
    const iface = support.asInterface();

    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 1.0), support.currentScaleFactor());
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setContentScaleFactor(iface, 2.0));
    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 2.0), support.currentScaleFactor());
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.setContentScaleFactor(iface, 0.0));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.setContentScaleFactor(iface, -1.0));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.setContentScaleFactor(iface, std.math.nan(scale_support.ScaleFactor)));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.setContentScaleFactor(iface, std.math.inf(scale_support.ScaleFactor)));
    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 2.0), support.currentScaleFactor());
}

test "content scale support preserves previous factor when config rejects changes" {
    const Support = ContentScaleSupport(struct {
        pub fn setContentScaleFactor(factor: scale_support.ScaleFactor) types.tresult {
            return if (factor <= 2.0) types.kResultOk else types.kResultFalse;
        }
    });
    var support = Support{};
    const iface = support.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.setContentScaleFactor(iface, 2.0));
    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 2.0), support.currentScaleFactor());
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setContentScaleFactor(iface, 3.0));
    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 2.0), support.currentScaleFactor());
}

test "content scale support supports query interface" {
    const Support = ContentScaleSupport(struct {});
    var support = Support{};
    const iface = support.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &scale_support.iplug_view_content_scale_support_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_support: *scale_support.IPlugViewContentScaleSupport = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_support.vtable.release(queried_support));
}
