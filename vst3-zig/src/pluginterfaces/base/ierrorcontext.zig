const base_types = @import("types.zig");
const istringresult = @import("istringresult.zig");
const tuid = @import("../../tuid.zig");

pub const ierror_context_iid = tuid.inlineUid(0x12BCD07B, 0x7C694336, 0xB7DA77C3, 0x444A0CD0);

pub const IErrorContextVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    disableErrorUI: *const fn (*anyopaque, bool) callconv(.C) void,
    errorMessageShown: *const fn (*anyopaque) callconv(.C) base_types.tresult,
    getErrorMessage: *const fn (*anyopaque, ?*istringresult.IString) callconv(.C) base_types.tresult,
};

pub const IErrorContext = extern struct {
    vtable: *const IErrorContextVTable,
};

test "error context vtable size matches SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IErrorContext));
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IErrorContextVTable).@"struct".fields.len);
}
