const attributes = @import("ivstattributes.zig");
const base_types = @import("../base/types.zig");
const std = @import("std");
const tuid = @import("../../tuid.zig");

pub const imessage_iid = tuid.inlineUid(0x936F033B, 0xC6C047DB, 0xBB0882F8, 0x13C1E613);
pub const iconnection_point_iid = tuid.inlineUid(0x70A4156F, 0x6E6E4026, 0x989148BF, 0xAA60D8D1);

pub const IMessageVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getMessageID: *const fn (*anyopaque) callconv(.c) ?base_types.FIDString,
    setMessageID: *const fn (*anyopaque, ?base_types.FIDString) callconv(.c) void,
    getAttributes: *const fn (*anyopaque) callconv(.c) ?*attributes.IAttributeList,
};

pub const IMessage = extern struct {
    vtable: *const IMessageVTable,
};

pub fn messageId(message: *IMessage) ?[]const u8 {
    const id = message.vtable.getMessageID(message) orelse return null;
    return std.mem.span(id);
}

pub fn messageIdEquals(message: *IMessage, expected: []const u8) bool {
    const actual = messageId(message) orelse return false;
    return std.mem.eql(u8, actual, expected);
}

pub const IConnectionPointVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    connect: *const fn (*anyopaque, ?*IConnectionPoint) callconv(.c) base_types.tresult,
    disconnect: *const fn (*anyopaque, ?*IConnectionPoint) callconv(.c) base_types.tresult,
    notify: *const fn (*anyopaque, ?*IMessage) callconv(.c) base_types.tresult,
};

pub const IConnectionPoint = extern struct {
    vtable: *const IConnectionPointVTable,
};

test "message vtable slot counts include FUnknown prefix" {
    try std.testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IMessage));
    try std.testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IConnectionPoint));
    try std.testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IMessage));
    try std.testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IConnectionPoint));
    try std.testing.expectEqual(@as(usize, 6), @typeInfo(IMessageVTable).@"struct".fields.len);
    try std.testing.expectEqual(@as(usize, 6), @typeInfo(IConnectionPointVTable).@"struct".fields.len);
}

test "message ID helpers reject a null ABI string" {
    const Stub = struct {
        fn getMessageID(_: *anyopaque) callconv(.c) ?base_types.FIDString {
            return null;
        }
    };
    var vtable: IMessageVTable = undefined;
    vtable.getMessageID = Stub.getMessageID;
    var message = IMessage{ .vtable = &vtable };
    try std.testing.expect(messageId(&message) == null);
    try std.testing.expect(!messageIdEquals(&message, "resource"));
}
