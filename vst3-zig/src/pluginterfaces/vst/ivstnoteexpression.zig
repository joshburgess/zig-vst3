const base_types = @import("../base/types.zig");

pub const NoteExpressionTypeID = base_types.uint32;
pub const NoteExpressionValue = f64;

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

test "note expression event struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(NoteExpressionValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(NoteExpressionIntValueEvent));
    try @import("std").testing.expectEqual(@as(usize, 24), @sizeOf(NoteExpressionTextEvent));
}
