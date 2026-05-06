const base_types = @import("../base/types.zig");
const noteexpression = @import("ivstnoteexpression.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const ievent_list_iid = tuid.inlineUid(0x3A2C4214, 0x346349FE, 0xB2C4F397, 0xB9695A44);

pub const NoteIDUserRange = enum(base_types.int32) {
    kNoteIDUserRangeLowerBound = -10000,
    kNoteIDUserRangeUpperBound = -1000,
};

pub const NoteOnEvent = extern struct {
    channel: base_types.int16 = 0,
    pitch: base_types.int16 = 0,
    tuning: f32 = 0,
    velocity: f32 = 0,
    length: base_types.int32 = 0,
    noteId: base_types.int32 = 0,
};

pub const NoteOffEvent = extern struct {
    channel: base_types.int16 = 0,
    pitch: base_types.int16 = 0,
    velocity: f32 = 0,
    noteId: base_types.int32 = 0,
    tuning: f32 = 0,
};

pub const DataEvent = extern struct {
    size: base_types.uint32 = 0,
    type: base_types.uint32 = 0,
    bytes: ?[*]const base_types.uint8 = null,

    pub const DataTypes = enum(base_types.int32) {
        kMidiSysEx = 0,
    };
};

pub const PolyPressureEvent = extern struct {
    channel: base_types.int16 = 0,
    pitch: base_types.int16 = 0,
    pressure: f32 = 0,
    noteId: base_types.int32 = 0,
};

pub const ChordEvent = extern struct {
    root: base_types.int16 = 0,
    bassNote: base_types.int16 = 0,
    mask: base_types.int16 = 0,
    textLen: base_types.uint16 = 0,
    text: ?[*:0]const vsttypes.TChar = null,
};

pub const ScaleEvent = extern struct {
    root: base_types.int16 = 0,
    mask: base_types.int16 = 0,
    textLen: base_types.uint16 = 0,
    text: ?[*:0]const vsttypes.TChar = null,
};

pub const LegacyMIDICCOutEvent = extern struct {
    controlNumber: base_types.uint8 = 0,
    channel: base_types.int8 = 0,
    value: base_types.int8 = 0,
    value2: base_types.int8 = 0,
};

pub const Event = extern struct {
    busIndex: base_types.int32 = 0,
    sampleOffset: base_types.int32 = 0,
    ppqPosition: vsttypes.TQuarterNotes = 0,
    flags: base_types.uint16 = 0,
    type: base_types.uint16 = 0,
    data: extern union {
        noteOn: NoteOnEvent,
        noteOff: NoteOffEvent,
        data: DataEvent,
        polyPressure: PolyPressureEvent,
        noteExpressionValue: noteexpression.NoteExpressionValueEvent,
        noteExpressionText: noteexpression.NoteExpressionTextEvent,
        noteExpressionIntValue: noteexpression.NoteExpressionIntValueEvent,
        chord: ChordEvent,
        scale: ScaleEvent,
        midiCCOut: LegacyMIDICCOutEvent,
    } = .{ .noteOn = .{} },

    pub const EventFlags = packed struct(base_types.uint16) {
        is_live: bool = false,
        _: u13 = 0,
        user_reserved1: bool = false,
        user_reserved2: bool = false,

        pub const kIsLive: base_types.uint16 = 1 << 0;
        pub const kUserReserved1: base_types.uint16 = 1 << 14;
        pub const kUserReserved2: base_types.uint16 = 1 << 15;
    };

    pub const EventTypes = enum(base_types.uint16) {
        kNoteOnEvent = 0,
        kNoteOffEvent = 1,
        kDataEvent = 2,
        kPolyPressureEvent = 3,
        kNoteExpressionValueEvent = 4,
        kNoteExpressionTextEvent = 5,
        kChordEvent = 6,
        kScaleEvent = 7,
        kNoteExpressionIntValueEvent = 8,
        kLegacyMIDICCOutEvent = 65535,
    };
};

pub const IEventListVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getEventCount: *const fn (*anyopaque) callconv(.C) base_types.int32,
    getEvent: *const fn (*anyopaque, base_types.int32, *Event) callconv(.C) base_types.tresult,
    addEvent: *const fn (*anyopaque, *Event) callconv(.C) base_types.tresult,
};

pub const IEventList = extern struct {
    vtable: *const IEventListVTable,
};

test "event struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 20), @sizeOf(NoteOnEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(NoteOffEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(DataEvent));
    try @import("std").testing.expectEqual(@as(usize, 12), @sizeOf(PolyPressureEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(ChordEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(ScaleEvent));
    try @import("std").testing.expectEqual(@as(usize, 4), @sizeOf(LegacyMIDICCOutEvent));
    try @import("std").testing.expectEqual(@as(usize, 40), @sizeOf(Event));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IEventList));
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IEventListVTable).@"struct".fields.len);
}
