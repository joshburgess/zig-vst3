const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const imidi_learn_iid = tuid.inlineUid(0x6B2449CC, 0x419740B5, 0xAB3C79DA, 0xC5FE5C86);

pub const IMidiLearnVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    onLiveMIDIControllerInput: *const fn (*anyopaque, base_types.int32, base_types.int16, vsttypes.CtrlNumber) callconv(.C) base_types.tresult,
};

test "MIDI learn vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IMidiLearnVTable).@"struct".fields.len);
}
