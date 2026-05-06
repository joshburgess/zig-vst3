const base_types = @import("../base/types.zig");
const vsttypes = @import("vsttypes.zig");

pub const FrameRateFlags = packed struct(base_types.uint32) {
    pull_down_rate: bool = false,
    drop_rate: bool = false,
    _: u30 = 0,

    pub const kPullDownRate: base_types.uint32 = 1 << 0;
    pub const kDropRate: base_types.uint32 = 1 << 1;
};

pub const FrameRate = extern struct {
    framesPerSecond: base_types.uint32 = 0,
    flags: base_types.uint32 = 0,
};

pub const ChordMasks = packed struct(base_types.uint16) {
    chord_mask: u12 = 0,
    reserved: u4 = 0,

    pub const kChordMask: base_types.uint16 = 0x0FFF;
    pub const kReservedMask: base_types.uint16 = 0xF000;
};

pub const Chord = extern struct {
    keyNote: base_types.uint8 = 0,
    rootNote: base_types.uint8 = 0,
    chordMask: base_types.int16 = 0,
};

pub const StatesAndFlags = packed struct(base_types.uint32) {
    _: u1 = 0,
    playing: bool = false,
    cycle_active: bool = false,
    recording: bool = false,
    __: u4 = 0,
    system_time_valid: bool = false,
    project_time_music_valid: bool = false,
    tempo_valid: bool = false,
    bar_position_valid: bool = false,
    cycle_valid: bool = false,
    time_sig_valid: bool = false,
    smpte_valid: bool = false,
    clock_valid: bool = false,
    ___: u1 = 0,
    cont_time_valid: bool = false,
    chord_valid: bool = false,
    ____: u13 = 0,

    pub const kPlaying: base_types.uint32 = 1 << 1;
    pub const kCycleActive: base_types.uint32 = 1 << 2;
    pub const kRecording: base_types.uint32 = 1 << 3;
    pub const kSystemTimeValid: base_types.uint32 = 1 << 8;
    pub const kContTimeValid: base_types.uint32 = 1 << 17;
    pub const kProjectTimeMusicValid: base_types.uint32 = 1 << 9;
    pub const kBarPositionValid: base_types.uint32 = 1 << 11;
    pub const kCycleValid: base_types.uint32 = 1 << 12;
    pub const kTempoValid: base_types.uint32 = 1 << 10;
    pub const kTimeSigValid: base_types.uint32 = 1 << 13;
    pub const kChordValid: base_types.uint32 = 1 << 18;
    pub const kSmpteValid: base_types.uint32 = 1 << 14;
    pub const kClockValid: base_types.uint32 = 1 << 15;
};

pub const ProcessContext = extern struct {
    state: base_types.uint32 = 0,
    sampleRate: f64 = 0,
    projectTimeSamples: vsttypes.TSamples = 0,
    systemTime: base_types.int64 = 0,
    continousTimeSamples: vsttypes.TSamples = 0,
    projectTimeMusic: vsttypes.TQuarterNotes = 0,
    barPositionMusic: vsttypes.TQuarterNotes = 0,
    cycleStartMusic: vsttypes.TQuarterNotes = 0,
    cycleEndMusic: vsttypes.TQuarterNotes = 0,
    tempo: f64 = 0,
    timeSigNumerator: base_types.int32 = 0,
    timeSigDenominator: base_types.int32 = 0,
    chord: Chord = .{},
    smpteOffsetSubframes: base_types.int32 = 0,
    frameRate: FrameRate = .{},
    samplesToNextClock: base_types.int32 = 0,
};

test "process context struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 8), @sizeOf(FrameRate));
    try @import("std").testing.expectEqual(@as(usize, 4), @alignOf(FrameRate));
    try @import("std").testing.expectEqual(@as(usize, 4), @sizeOf(Chord));
    try @import("std").testing.expectEqual(@as(usize, 2), @alignOf(Chord));
    try @import("std").testing.expectEqual(@as(usize, 112), @sizeOf(ProcessContext));
    try @import("std").testing.expectEqual(@as(usize, 8), @alignOf(ProcessContext));
}
