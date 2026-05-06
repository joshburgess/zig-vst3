const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const ihost_application_iid = tuid.inlineUid(0x58E595CC, 0xDB2D4969, 0x8B6AAF8C, 0x36A664E5);
pub const ivst3_to_vst2_wrapper_iid = tuid.inlineUid(0x29633AEC, 0x1D1C47E2, 0xBB85B97B, 0xD36EAC61);
pub const ivst3_to_au_wrapper_iid = tuid.inlineUid(0xA3B8C6C5, 0xC0954688, 0xB0916F0B, 0xB697AA44);
pub const ivst3_to_aax_wrapper_iid = tuid.inlineUid(0x6D319DC6, 0x60C56242, 0xB32C951B, 0x93BEF4C6);
pub const ivst3_wrapper_mpe_support_iid = tuid.inlineUid(0x44149067, 0x42CF4BF9, 0x8800B750, 0xF7359FE3);

pub const IHostApplicationVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getName: *const fn (*anyopaque, [*]vsttypes.TChar) callconv(.C) base_types.tresult,
    createInstance: *const fn (*anyopaque, *const tuid.TUID, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
};

pub const IHostApplication = extern struct {
    vtable: *const IHostApplicationVTable,
};

pub const IVst3ToVst2WrapperVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
};

pub const IVst3ToVst2Wrapper = extern struct {
    vtable: *const IVst3ToVst2WrapperVTable,
};

pub const IVst3ToAUWrapperVTable = IVst3ToVst2WrapperVTable;
pub const IVst3ToAAXWrapperVTable = IVst3ToVst2WrapperVTable;

pub const IVst3ToAUWrapper = extern struct {
    vtable: *const IVst3ToAUWrapperVTable,
};

pub const IVst3ToAAXWrapper = extern struct {
    vtable: *const IVst3ToAAXWrapperVTable,
};

pub const IVst3WrapperMPESupportVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    enableMPEInputProcessing: *const fn (*anyopaque, base_types.TBool) callconv(.C) base_types.tresult,
    setMPEInputDeviceSettings: *const fn (*anyopaque, base_types.int32, base_types.int32, base_types.int32) callconv(.C) base_types.tresult,
};

pub const IVst3WrapperMPESupport = extern struct {
    vtable: *const IVst3WrapperMPESupportVTable,
};

test "host application vtable slot counts include FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IHostApplication));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IVst3ToVst2Wrapper));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IVst3ToAUWrapper));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IVst3ToAAXWrapper));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IVst3WrapperMPESupport));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IHostApplication));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IVst3ToVst2Wrapper));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IVst3ToAUWrapper));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IVst3ToAAXWrapper));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IVst3WrapperMPESupport));
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IHostApplicationVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 3), @typeInfo(IVst3ToVst2WrapperVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IVst3WrapperMPESupportVTable).@"struct".fields.len);
}
