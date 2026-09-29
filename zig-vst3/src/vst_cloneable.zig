const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const icloneable = @import("pluginterfaces/base/icloneable.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn Cloneable(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: icloneable.ICloneable = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        clone_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *icloneable.ICloneable {
            return &self.iface;
        }

        const owner = interface_map.ownerFromField(Self, icloneable.ICloneable, "iface");

        fn query(ptr: *anyopaque, requested_iid: [*c]const tuid.TUID, out: [*c]?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &icloneable.icloneable_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "ICloneable");
        }

        fn clone(ptr: *anyopaque) callconv(.c) ?*anyopaque {
            const self = owner(ptr);
            self.clone_count +|= 1;
            if (@hasDecl(Config, "clone")) {
                return Config.clone(@ptrCast(self));
            }
            return null;
        }

        const vtable = icloneable.ICloneableVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .clone = clone,
        };
    };
}

test "cloneable defaults to no clone" {
    const Object = Cloneable(struct {});
    var object = Object{};
    const iface = object.asInterface();

    try std.testing.expectEqual(@as(?*anyopaque, null), iface.vtable.clone(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), object.clone_count);
}

test "cloneable delegates to config clone hook" {
    const Config = struct {
        var clone_target: u32 = 123;

        fn clone(_: *anyopaque) ?*anyopaque {
            return &clone_target;
        }
    };
    const Object = Cloneable(Config);
    var object = Object{};
    const iface = object.asInterface();

    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(&Config.clone_target)), iface.vtable.clone(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), object.clone_count);
}

test "cloneable supports query interface" {
    const Object = Cloneable(struct {});
    var object = Object{};
    const iface = object.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &icloneable.icloneable_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_cloneable: *icloneable.ICloneable = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_cloneable.vtable.release(queried_cloneable));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), object.ref_count.load(.seq_cst));
    const queried_unknown: *icloneable.ICloneable = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "cloneable clears unsupported query output" {
    const Object = Cloneable(struct {});
    var object = Object{};
    const iface = object.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
