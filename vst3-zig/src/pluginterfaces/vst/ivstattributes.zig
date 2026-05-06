const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iattribute_list_iid = tuid.inlineUid(0x1E5F0AEB, 0xCC7F4533, 0xA2544011, 0x38AD5EE4);
pub const istream_attributes_iid = tuid.inlineUid(0xD6CE2FFC, 0xEFAF4B8C, 0x9E74F1BB, 0x12DA44B4);

pub const AttrID = [*:0]const base_types.char8;

pub const IAttributeListVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setInt: *const fn (*anyopaque, AttrID, base_types.int64) callconv(.C) base_types.tresult,
    getInt: *const fn (*anyopaque, AttrID, *base_types.int64) callconv(.C) base_types.tresult,
    setFloat: *const fn (*anyopaque, AttrID, f64) callconv(.C) base_types.tresult,
    getFloat: *const fn (*anyopaque, AttrID, *f64) callconv(.C) base_types.tresult,
    setString: *const fn (*anyopaque, AttrID, [*:0]const vsttypes.TChar) callconv(.C) base_types.tresult,
    getString: *const fn (*anyopaque, AttrID, [*]vsttypes.TChar, base_types.uint32) callconv(.C) base_types.tresult,
    setBinary: *const fn (*anyopaque, AttrID, ?*const anyopaque, base_types.uint32) callconv(.C) base_types.tresult,
    getBinary: *const fn (*anyopaque, AttrID, *?*const anyopaque, *base_types.uint32) callconv(.C) base_types.tresult,
};

pub const IAttributeList = extern struct {
    vtable: *const IAttributeListVTable,
};

pub const IStreamAttributesVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getFileName: *const fn (*anyopaque, [*]vsttypes.TChar) callconv(.C) base_types.tresult,
    getAttributes: *const fn (*anyopaque) callconv(.C) ?*IAttributeList,
};

pub const IStreamAttributes = extern struct {
    vtable: *const IStreamAttributesVTable,
};

test "attribute vtable slot counts include FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IAttributeList));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IStreamAttributes));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IAttributeList));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IStreamAttributes));
    try @import("std").testing.expectEqual(@as(usize, 11), @typeInfo(IAttributeListVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IStreamAttributesVTable).@"struct".fields.len);
}
