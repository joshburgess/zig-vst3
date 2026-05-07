const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstplugview = @import("pluginterfaces/vst/ivstplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn ParameterFinder(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstplugview.IParameterFinder = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *ivstplugview.IParameterFinder {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstplugview.IParameterFinder = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstplugview.iparameter_finder_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IParameterFinder");
        }

        fn findParameter(_: *anyopaque, x: types.int32, y: types.int32, out: *vsttypes.ParamID) callconv(.C) types.tresult {
            if (@hasDecl(Config, "findParameter")) {
                if (Config.findParameter(x, y)) |id| {
                    out.* = id;
                    return types.kResultOk;
                }
            }
            out.* = vsttypes.kNoParamId;
            return types.kResultFalse;
        }

        const vtable = ivstplugview.IParameterFinderVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .findParameter = findParameter,
        };
    };
}

test "parameter finder maps coordinates to parameter ids" {
    const Finder = ParameterFinder(struct {
        pub fn findParameter(x: types.int32, y: types.int32) ?vsttypes.ParamID {
            if (x >= 10 and x < 20 and y >= 5 and y < 15) return 42;
            return null;
        }
    });

    var finder = Finder{};
    const iface = finder.asInterface();

    var found: vsttypes.ParamID = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.findParameter(iface, 12, 6, &found));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 42), found);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.findParameter(iface, 2, 6, &found));
    try std.testing.expectEqual(vsttypes.kNoParamId, found);
}

test "parameter finder supports query interface" {
    const Finder = ParameterFinder(struct {});
    var finder = Finder{};
    const iface = finder.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstplugview.iparameter_finder_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_finder: *ivstplugview.IParameterFinder = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_finder.vtable.release(queried_finder));
}
