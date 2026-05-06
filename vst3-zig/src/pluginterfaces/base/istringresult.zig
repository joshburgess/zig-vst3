const base_types = @import("types.zig");
const tuid = @import("../../tuid.zig");

pub const istring_result_iid = tuid.inlineUid(0x550798BC, 0x872049DB, 0x84920A15, 0x3B50B7A8);
pub const istring_iid = tuid.inlineUid(0xF99DB7A3, 0x0FC14821, 0x800B0CF9, 0x8E348EDF);

pub const IStringResultVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setText: *const fn (*anyopaque, ?[*:0]const base_types.char8) callconv(.C) void,
};

pub const IStringVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    setText8: *const fn (*anyopaque, ?[*:0]const base_types.char8) callconv(.C) void,
    setText16: *const fn (*anyopaque, ?[*:0]const base_types.char16) callconv(.C) void,
    getText8: *const fn (*anyopaque) callconv(.C) ?[*:0]const base_types.char8,
    getText16: *const fn (*anyopaque) callconv(.C) ?[*:0]const base_types.char16,
    take: *const fn (*anyopaque, ?*anyopaque, bool) callconv(.C) void,
    isWideString: *const fn (*anyopaque) callconv(.C) bool,
};

pub const IStringResult = extern struct {
    vtable: *const IStringResultVTable,
};

pub const IString = extern struct {
    vtable: *const IStringVTable,
};

test "string result vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IStringResult));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IString));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IStringResult));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IString));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IStringResultVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 9), @typeInfo(IStringVTable).@"struct".fields.len);
}
