const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const scale_support = @import("pluginterfaces/gui/iplugviewcontentscalesupport.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_value = @import("vst_value.zig");

fn isValidScaleFactor(factor: scale_support.ScaleFactor) bool {
    return vst_value.isPositiveFinite(factor);
}

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

        const owner = interface_map.ownerFromField(Self, scale_support.IPlugViewContentScaleSupport, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &scale_support.iplug_view_content_scale_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugViewContentScaleSupport");
        }

        fn setContentScaleFactor(ptr: *anyopaque, factor: scale_support.ScaleFactor) callconv(.c) types.tresult {
            if (!isValidScaleFactor(factor)) return types.kInvalidArgument;
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

test "content scale support recognizes finite positive factors" {
    try std.testing.expect(isValidScaleFactor(1.0));
    try std.testing.expect(isValidScaleFactor(2.5));
    try std.testing.expect(!isValidScaleFactor(0.0));
    try std.testing.expect(!isValidScaleFactor(-1.0));
    try std.testing.expect(!isValidScaleFactor(std.math.nan(scale_support.ScaleFactor)));
    try std.testing.expect(!isValidScaleFactor(std.math.inf(scale_support.ScaleFactor)));
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

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), support.ref_count.load(.seq_cst));
    const queried_unknown: *scale_support.IPlugViewContentScaleSupport = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "content scale support clears unsupported query output" {
    const Support = ContentScaleSupport(struct {});
    var support = Support{};
    const iface = support.asInterface();
    var queried: ?*anyopaque = iface;

    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
