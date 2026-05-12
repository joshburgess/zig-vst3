const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const imidi_mapping2_iid = tuid.inlineUid(0x6DE14B88, 0x03F94F09, 0xA2552F0F, 0x9326593E);
pub const imidi_learn2_iid = tuid.inlineUid(0xF07E498A, 0x78864327, 0x8B431CED, 0xA3C553FC);

pub const MidiGroup = base_types.uint8;
pub const MidiChannel = base_types.uint8;
pub const BusIndex = base_types.int32;

pub const Midi2Controller = extern struct {
    bank_registered: base_types.uint8 = 0,
    index_reserved: base_types.uint8 = 0,
};

pub const Midi2ControllerParamIDAssignment = extern struct {
    pId: vsttypes.ParamID = 0,
    busIndex: BusIndex = 0,
    channel: MidiChannel = 0,
    controller: Midi2Controller = .{},
};

pub const Midi2ControllerParamIDAssignmentList = extern struct {
    count: base_types.uint32 = 0,
    map: ?[*]Midi2ControllerParamIDAssignment = null,
};

pub const Midi1ControllerParamIDAssignment = extern struct {
    pId: vsttypes.ParamID = 0,
    busIndex: BusIndex = 0,
    channel: MidiChannel = 0,
    controller: vsttypes.CtrlNumber = 0,
};

pub const Midi1ControllerParamIDAssignmentList = extern struct {
    count: base_types.uint32 = 0,
    map: ?[*]Midi1ControllerParamIDAssignment = null,
};

pub const IMidiMapping2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getNumMidi2ControllerAssignments: *const fn (*anyopaque, vsttypes.BusDirection) callconv(.c) base_types.uint32,
    getMidi2ControllerAssignments: *const fn (*anyopaque, vsttypes.BusDirection, *const Midi2ControllerParamIDAssignmentList) callconv(.c) base_types.tresult,
    getNumMidi1ControllerAssignments: *const fn (*anyopaque, vsttypes.BusDirection) callconv(.c) base_types.uint32,
    getMidi1ControllerAssignments: *const fn (*anyopaque, vsttypes.BusDirection, *const Midi1ControllerParamIDAssignmentList) callconv(.c) base_types.tresult,
};

pub const IMidiMapping2 = extern struct {
    vtable: *const IMidiMapping2VTable,
};

pub const IMidiLearn2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    onLiveMidi2ControllerInput: *const fn (*anyopaque, BusIndex, MidiChannel, Midi2Controller) callconv(.c) base_types.tresult,
    onLiveMidi1ControllerInput: *const fn (*anyopaque, BusIndex, MidiChannel, vsttypes.CtrlNumber) callconv(.c) base_types.tresult,
};

pub const IMidiLearn2 = extern struct {
    vtable: *const IMidiLearn2VTable,
};

test "MIDI 2 mapping struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 2), @sizeOf(Midi2Controller));
    try @import("std").testing.expectEqual(@as(usize, 12), @sizeOf(Midi2ControllerParamIDAssignment));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(Midi2ControllerParamIDAssignmentList));
    try @import("std").testing.expectEqual(@as(usize, 12), @sizeOf(Midi1ControllerParamIDAssignment));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(Midi1ControllerParamIDAssignmentList));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IMidiMapping2));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IMidiLearn2));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IMidiMapping2VTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IMidiLearn2VTable).@"struct".fields.len);
}
