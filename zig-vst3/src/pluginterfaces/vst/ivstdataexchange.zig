const audio_processor = @import("ivstaudioprocessor.zig");
const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const idata_exchange_handler_iid = tuid.inlineUid(0x36D551BD, 0x6FF54F08, 0xB48E830D, 0x8BD5A03B);
pub const idata_exchange_receiver_iid = tuid.inlineUid(0x45A759DC, 0x84FA4907, 0xABCB6175, 0x2FC786B6);

pub const DataExchangeQueueID = base_types.uint32;
pub const DataExchangeBlockID = base_types.uint32;
pub const DataExchangeUserContextID = base_types.uint32;

pub const InvalidDataExchangeQueueID: DataExchangeQueueID = 0x7FFFFFFF;
pub const InvalidDataExchangeBlockID: DataExchangeBlockID = 0x7FFFFFFF;

pub const DataExchangeBlock = extern struct {
    data: ?*anyopaque = null,
    size: base_types.uint32 = 0,
    blockID: DataExchangeBlockID = 0,
};

pub const IDataExchangeHandlerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    openQueue: *const fn (*anyopaque, ?*audio_processor.IAudioProcessor, base_types.uint32, base_types.uint32, base_types.uint32, DataExchangeUserContextID, [*c]DataExchangeQueueID) callconv(.c) base_types.tresult,
    closeQueue: *const fn (*anyopaque, DataExchangeQueueID) callconv(.c) base_types.tresult,
    lockBlock: *const fn (*anyopaque, DataExchangeQueueID, [*c]DataExchangeBlock) callconv(.c) base_types.tresult,
    freeBlock: *const fn (*anyopaque, DataExchangeQueueID, DataExchangeBlockID, base_types.TBool) callconv(.c) base_types.tresult,
};

pub const IDataExchangeReceiverVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    queueOpened: *const fn (*anyopaque, DataExchangeUserContextID, base_types.uint32, [*c]base_types.TBool) callconv(.c) void,
    queueClosed: *const fn (*anyopaque, DataExchangeUserContextID) callconv(.c) void,
    onDataExchangeBlocksReceived: *const fn (*anyopaque, DataExchangeUserContextID, base_types.uint32, ?[*]DataExchangeBlock, base_types.TBool) callconv(.c) void,
};

pub const IDataExchangeHandler = extern struct {
    vtable: *const IDataExchangeHandlerVTable,
};

pub const IDataExchangeReceiver = extern struct {
    vtable: *const IDataExchangeReceiverVTable,
};

test "data exchange struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(DataExchangeBlock));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(DataExchangeBlock));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IDataExchangeHandler));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IDataExchangeReceiver));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IDataExchangeHandler));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IDataExchangeReceiver));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IDataExchangeHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IDataExchangeReceiverVTable).@"struct".fields.len);
}
