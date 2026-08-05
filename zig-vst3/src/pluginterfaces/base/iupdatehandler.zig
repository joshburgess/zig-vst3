const base_types = @import("types.zig");
const tuid = @import("../../tuid.zig");

pub const iupdate_handler_iid = tuid.inlineUid(0xF5246D56, 0x86544D60, 0xB026AFB5, 0x7B697B37);
pub const idependent_iid = tuid.inlineUid(0xF52B7AAE, 0xDE72416D, 0x8AF18ACE, 0x9DD7BD5E);

pub const IUpdateHandlerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    addDependent: *const fn (*anyopaque, ?*anyopaque, ?*IDependent) callconv(.c) base_types.tresult,
    removeDependent: *const fn (*anyopaque, ?*anyopaque, ?*IDependent) callconv(.c) base_types.tresult,
    triggerUpdates: *const fn (*anyopaque, ?*anyopaque, base_types.int32) callconv(.c) base_types.tresult,
    deferUpdates: *const fn (*anyopaque, ?*anyopaque, base_types.int32) callconv(.c) base_types.tresult,
};

pub const ChangeMessage = enum(base_types.int32) {
    kWillChange = 0,
    kChanged = 1,
    kDestroyed = 2,
    kWillDestroy = 3,
};

pub const kStdChangeMessageLast = ChangeMessage.kWillDestroy;

pub const IDependentVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    update: *const fn (*anyopaque, ?*anyopaque, base_types.int32) callconv(.c) void,
};

pub const IUpdateHandler = extern struct {
    vtable: *const IUpdateHandlerVTable,
};

pub const IDependent = extern struct {
    vtable: *const IDependentVTable,
};

test "update handler vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IUpdateHandler));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IDependent));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IUpdateHandler));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IDependent));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IUpdateHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IDependentVTable).@"struct".fields.len);
}
