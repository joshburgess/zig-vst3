const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const NoteExpressionTypeID = base_types.uint32;
pub const NoteExpressionValue = f64;
pub const KeyswitchTypeID = base_types.uint32;

pub const inote_expression_controller_iid = tuid.inlineUid(0xB7F8F859, 0x41234872, 0x91169581, 0x4F3721A3);
pub const ikeyswitch_controller_iid = tuid.inlineUid(0x1F2F76D3, 0xBFFB4B96, 0xB99527A5, 0x5EBCCEF4);

pub const NoteExpressionTypeIDs = enum(base_types.uint32) {
    kVolumeTypeID = 0,
    kPanTypeID = 1,
    kTuningTypeID = 2,
    kVibratoTypeID = 3,
    kExpressionTypeID = 4,
    kBrightnessTypeID = 5,
    kTextTypeID = 6,
    kPhonemeTypeID = 7,
    kCustomStart = 100000,
    kCustomEnd = 200000,
    kInvalidTypeID = 0xFFFFFFFF,
};

pub const NoteExpressionValueEvent = extern struct {
    typeId: NoteExpressionTypeID = 0,
    noteId: base_types.int32 = 0,
    value: NoteExpressionValue = 0,
};

pub const NoteExpressionIntValueEvent = extern struct {
    typeId: NoteExpressionTypeID = 0,
    noteId: base_types.int32 = 0,
    value: base_types.uint64 = 0,
};

pub const NoteExpressionTextEvent = extern struct {
    typeId: NoteExpressionTypeID = 0,
    noteId: base_types.int32 = 0,
    textLen: base_types.uint32 = 0,
    text: ?[*:0]const base_types.char16 = null,
};

pub const NoteExpressionValueDescription = extern struct {
    defaultValue: NoteExpressionValue = 0,
    minimum: NoteExpressionValue = 0,
    maximum: NoteExpressionValue = 0,
    stepCount: base_types.int32 = 0,
};

pub const NoteExpressionTypeInfo = extern struct {
    typeId: NoteExpressionTypeID = 0,
    title: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    shortTitle: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    units: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    unitId: base_types.int32 = 0,
    valueDesc: NoteExpressionValueDescription = .{},
    associatedParameterId: vsttypes.ParamID = 0,
    flags: base_types.int32 = 0,

    pub const NoteExpressionTypeFlags = packed struct(base_types.int32) {
        is_bipolar: bool = false,
        is_one_shot: bool = false,
        is_absolute: bool = false,
        associated_parameter_id_valid: bool = false,
        _: u28 = 0,

        pub const kIsBipolar: base_types.int32 = 1 << 0;
        pub const kIsOneShot: base_types.int32 = 1 << 1;
        pub const kIsAbsolute: base_types.int32 = 1 << 2;
        pub const kAssociatedParameterIDValid: base_types.int32 = 1 << 3;
    };
};

pub const KeyswitchTypeIDs = enum(base_types.uint32) {
    kNoteOnKeyswitchTypeID = 0,
    kOnTheFlyKeyswitchTypeID = 1,
    kOnReleaseKeyswitchTypeID = 2,
    kKeyRangeTypeID = 3,
};

pub const KeyswitchInfo = extern struct {
    typeId: KeyswitchTypeID = 0,
    title: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    shortTitle: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    keyswitchMin: base_types.int32 = 0,
    keyswitchMax: base_types.int32 = 0,
    keyRemapped: base_types.int32 = 0,
    unitId: base_types.int32 = 0,
    flags: base_types.int32 = 0,
};

pub const INoteExpressionControllerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getNoteExpressionCount: *const fn (*anyopaque, base_types.int32, base_types.int16) callconv(.C) base_types.int32,
    getNoteExpressionInfo: *const fn (*anyopaque, base_types.int32, base_types.int16, base_types.int32, *NoteExpressionTypeInfo) callconv(.C) base_types.tresult,
    getNoteExpressionStringByValue: *const fn (*anyopaque, base_types.int32, base_types.int16, NoteExpressionTypeID, NoteExpressionValue, [*]vsttypes.TChar) callconv(.C) base_types.tresult,
    getNoteExpressionValueByString: *const fn (*anyopaque, base_types.int32, base_types.int16, NoteExpressionTypeID, [*:0]const vsttypes.TChar, *NoteExpressionValue) callconv(.C) base_types.tresult,
};

pub const INoteExpressionController = extern struct {
    vtable: *const INoteExpressionControllerVTable,
};

pub const IKeyswitchControllerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getKeyswitchCount: *const fn (*anyopaque, base_types.int32, base_types.int16) callconv(.C) base_types.int32,
    getKeyswitchInfo: *const fn (*anyopaque, base_types.int32, base_types.int16, base_types.int32, *KeyswitchInfo) callconv(.C) base_types.tresult,
};

pub const IKeyswitchController = extern struct {
    vtable: *const IKeyswitchControllerVTable,
};

test "note expression event struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(NoteExpressionValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(NoteExpressionValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(NoteExpressionIntValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(NoteExpressionIntValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 24), @sizeOf(NoteExpressionTextEvent));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(NoteExpressionTextEvent));
    try @import("std").testing.expectEqual(@as(usize, 32), @sizeOf(NoteExpressionValueDescription));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(NoteExpressionValueDescription));
    try @import("std").testing.expectEqual(@as(usize, 816), @sizeOf(NoteExpressionTypeInfo));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(NoteExpressionTypeInfo));
    try @import("std").testing.expectEqual(@as(usize, 536), @sizeOf(KeyswitchInfo));
    try @import("std").testing.expectEqual(@as(usize, 4), @alignOf(KeyswitchInfo));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(INoteExpressionController));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IKeyswitchController));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(INoteExpressionController));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IKeyswitchController));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(INoteExpressionControllerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IKeyswitchControllerVTable).@"struct".fields.len);
}
