const types = @import("types.zig");
const tuid = @import("../../tuid.zig");

pub const ibstream_iid = tuid.inlineUid(0xC3BF6EA2, 0x30994752, 0x9B6BF990, 0x1EE33E9B);
pub const isizeable_stream_iid = tuid.inlineUid(0x04F9549E, 0xE02F4E6E, 0x87E86A87, 0x47F4E17F);

pub const IStreamSeekMode = enum(types.int32) {
    kIBSeekSet = 0,
    kIBSeekCur = 1,
    kIBSeekEnd = 2,
};

pub const IBStreamVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    read: *const fn (*anyopaque, ?*anyopaque, types.int32, ?*types.int32) callconv(.C) types.tresult,
    write: *const fn (*anyopaque, ?*anyopaque, types.int32, ?*types.int32) callconv(.C) types.tresult,
    seek: *const fn (*anyopaque, types.int64, types.int32, ?*types.int64) callconv(.C) types.tresult,
    tell: *const fn (*anyopaque, *types.int64) callconv(.C) types.tresult,
};

pub const IBStream = extern struct {
    vtable: *const IBStreamVTable,
};

pub const ISizeableStreamVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    getStreamSize: *const fn (*anyopaque, *types.int64) callconv(.C) types.tresult,
    setStreamSize: *const fn (*anyopaque, types.int64) callconv(.C) types.tresult,
};

pub const ISizeableStream = extern struct {
    vtable: *const ISizeableStreamVTable,
};

test "stream vtable slot counts include FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IBStream));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ISizeableStream));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IBStreamVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(ISizeableStreamVTable).@"struct".fields.len);
}
