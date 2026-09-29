const base_types = @import("types.zig");
const tuid = @import("../../tuid.zig");

pub const icloneable_iid = tuid.inlineUid(0xD45406B9, 0x3A2D4443, 0x9DAD9BA9, 0x85A1454B);

pub const ICloneableVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    clone: *const fn (*anyopaque) callconv(.c) ?*anyopaque,
};

pub const ICloneable = extern struct {
    vtable: *const ICloneableVTable,
};

test "cloneable vtable size matches SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ICloneable));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(ICloneableVTable).@"struct".fields.len);
}
