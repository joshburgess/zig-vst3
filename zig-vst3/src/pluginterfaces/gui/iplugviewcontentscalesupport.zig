const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const iplug_view_content_scale_support_iid = tuid.inlineUid(0x65ED9690, 0x8AC44525, 0x8AADEF7A, 0x72EA703F);

pub const ScaleFactor = f32;

pub const IPlugViewContentScaleSupportVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    setContentScaleFactor: *const fn (*anyopaque, ScaleFactor) callconv(.c) base_types.tresult,
};

pub const IPlugViewContentScaleSupport = extern struct {
    vtable: *const IPlugViewContentScaleSupportVTable,
};

test "plug view scale support vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPlugViewContentScaleSupport));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IPlugViewContentScaleSupport));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IPlugViewContentScaleSupportVTable).@"struct".fields.len);
}
