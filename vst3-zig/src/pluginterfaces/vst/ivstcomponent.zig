const base_types = @import("../base/types.zig");
const ibstream = @import("../base/ibstream.zig");
const ipluginbase = @import("../base/ipluginbase.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const icomponent_iid = tuid.inlineUid(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802);

pub const kDefaultFactoryFlags = ipluginbase.PFactoryInfo.kUnicode;

pub const MediaTypes = enum(vsttypes.MediaType) {
    kAudio = 0,
    kEvent = 1,
    kNumMediaTypes = 2,
};

pub const BusDirections = enum(vsttypes.BusDirection) {
    kInput = 0,
    kOutput = 1,
};

pub const BusTypes = enum(vsttypes.BusType) {
    kMain = 0,
    kAux = 1,
};

pub const BusFlags = packed struct(base_types.uint32) {
    default_active: bool = false,
    is_control_voltage: bool = false,
    _: u30 = 0,

    pub const kDefaultActive: base_types.uint32 = 1 << 0;
    pub const kIsControlVoltage: base_types.uint32 = 1 << 1;
};

pub const BusInfo = extern struct {
    mediaType: vsttypes.MediaType = 0,
    direction: vsttypes.BusDirection = 0,
    channelCount: base_types.int32 = 0,
    name: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    busType: vsttypes.BusType = 0,
    flags: base_types.uint32 = 0,
};

pub const IoModes = enum(vsttypes.IoMode) {
    kSimple = 0,
    kAdvanced = 1,
    kOfflineProcessing = 2,
};

pub const RoutingInfo = extern struct {
    mediaType: vsttypes.MediaType = 0,
    busIndex: base_types.int32 = 0,
    channel: base_types.int32 = 0,
};

pub const IComponentVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    initialize: *const fn (*anyopaque, ?*anyopaque) callconv(.C) base_types.tresult,
    terminate: *const fn (*anyopaque) callconv(.C) base_types.tresult,
    getControllerClassId: *const fn (*anyopaque, *tuid.TUID) callconv(.C) base_types.tresult,
    setIoMode: *const fn (*anyopaque, vsttypes.IoMode) callconv(.C) base_types.tresult,
    getBusCount: *const fn (*anyopaque, vsttypes.MediaType, vsttypes.BusDirection) callconv(.C) base_types.int32,
    getBusInfo: *const fn (*anyopaque, vsttypes.MediaType, vsttypes.BusDirection, base_types.int32, *BusInfo) callconv(.C) base_types.tresult,
    getRoutingInfo: *const fn (*anyopaque, *RoutingInfo, *RoutingInfo) callconv(.C) base_types.tresult,
    activateBus: *const fn (*anyopaque, vsttypes.MediaType, vsttypes.BusDirection, base_types.int32, base_types.TBool) callconv(.C) base_types.tresult,
    setActive: *const fn (*anyopaque, base_types.TBool) callconv(.C) base_types.tresult,
    setState: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.C) base_types.tresult,
    getState: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.C) base_types.tresult,
};

test "component struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 276), @sizeOf(BusInfo));
    try @import("std").testing.expectEqual(@as(usize, 12), @sizeOf(RoutingInfo));
    try @import("std").testing.expectEqual(@as(usize, 14), @typeInfo(IComponentVTable).@"struct".fields.len);
}
