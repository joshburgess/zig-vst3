const base_types = @import("types.zig");
const fvariant = @import("fvariant.zig");
const tuid = @import("../../tuid.zig");

pub const ipersistent_iid = tuid.inlineUid(0xBA1A4637, 0x3C9F46D0, 0xA65DBA0E, 0xB85DA829);
pub const iattributes_iid = tuid.inlineUid(0xFA1E32F9, 0xCA6D46F5, 0xA982F956, 0xB1191B58);
pub const iattributes2_iid = tuid.inlineUid(0x1382126A, 0xFECA4871, 0x97D52A45, 0xB042AE99);

pub const IAttrID = base_types.FIDString;

pub const IPersistentVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getClassID: *const fn (*anyopaque, [*c]base_types.char8) callconv(.c) base_types.tresult,
    saveAttributes: *const fn (*anyopaque, ?*IAttributes) callconv(.c) base_types.tresult,
    loadAttributes: *const fn (*anyopaque, ?*IAttributes) callconv(.c) base_types.tresult,
};

pub const IAttributesVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    set: *const fn (*anyopaque, IAttrID, [*c]const fvariant.FVariant) callconv(.c) base_types.tresult,
    queue: *const fn (*anyopaque, IAttrID, [*c]const fvariant.FVariant) callconv(.c) base_types.tresult,
    setBinaryData: *const fn (*anyopaque, IAttrID, ?*anyopaque, base_types.uint32, bool) callconv(.c) base_types.tresult,
    get: *const fn (*anyopaque, IAttrID, [*c]fvariant.FVariant) callconv(.c) base_types.tresult,
    unqueue: *const fn (*anyopaque, IAttrID, [*c]fvariant.FVariant) callconv(.c) base_types.tresult,
    getQueueItemCount: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.int32,
    resetQueue: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.tresult,
    resetAllQueues: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    getBinaryData: *const fn (*anyopaque, IAttrID, ?*anyopaque, base_types.uint32) callconv(.c) base_types.tresult,
    getBinaryDataSize: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.uint32,
};

pub const IAttributes2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    set: *const fn (*anyopaque, IAttrID, [*c]const fvariant.FVariant) callconv(.c) base_types.tresult,
    queue: *const fn (*anyopaque, IAttrID, [*c]const fvariant.FVariant) callconv(.c) base_types.tresult,
    setBinaryData: *const fn (*anyopaque, IAttrID, ?*anyopaque, base_types.uint32, bool) callconv(.c) base_types.tresult,
    get: *const fn (*anyopaque, IAttrID, [*c]fvariant.FVariant) callconv(.c) base_types.tresult,
    unqueue: *const fn (*anyopaque, IAttrID, [*c]fvariant.FVariant) callconv(.c) base_types.tresult,
    getQueueItemCount: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.int32,
    resetQueue: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.tresult,
    resetAllQueues: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    getBinaryData: *const fn (*anyopaque, IAttrID, ?*anyopaque, base_types.uint32) callconv(.c) base_types.tresult,
    getBinaryDataSize: *const fn (*anyopaque, IAttrID) callconv(.c) base_types.uint32,
    countAttributes: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getAttributeID: *const fn (*anyopaque, base_types.int32) callconv(.c) IAttrID,
};

pub const IPersistent = extern struct {
    vtable: *const IPersistentVTable,
};

pub const IAttributes = extern struct {
    vtable: *const IAttributesVTable,
};

pub const IAttributes2 = extern struct {
    vtable: *const IAttributes2VTable,
};

test "persistent vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPersistent));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IAttributes));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IAttributes2));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IPersistent));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IAttributes));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IAttributes2));
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IPersistentVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 13), @typeInfo(IAttributesVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 15), @typeInfo(IAttributes2VTable).@"struct".fields.len);
}
