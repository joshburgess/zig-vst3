const base = @import("../base/types.zig");
const events = @import("ivstevents.zig");
const std = @import("std");
const vsttypes = @import("vsttypes.zig");

pub fn boundTo(comptime T: type, minval: T, maxval: T, x: T) T {
    if (x < minval) return minval;
    if (x > maxval) return maxval;
    return x;
}

pub fn init(
    event: *events.Event,
    event_type: base.uint16,
    bus_index: base.int32,
    sample_offset: base.int32,
    ppq_position: vsttypes.TQuarterNotes,
    flags: base.uint16,
) *events.Event {
    event.busIndex = bus_index;
    event.sampleOffset = sample_offset;
    event.ppqPosition = ppq_position;
    event.flags = flags;
    event.type = event_type;
    return event;
}

pub fn getMIDINormValue(value: base.uint8) vsttypes.ParamValue {
    return boundTo(vsttypes.ParamValue, 0, 1, @as(vsttypes.ParamValue, @floatFromInt(value)) / 127);
}

pub fn getMIDICCOutValue(value: vsttypes.ParamValue) base.int8 {
    if (std.math.isNan(value)) return 0;
    return boundTo(base.int8, 0, 127, @intFromFloat(@min(@as(vsttypes.ParamValue, 127), value * 128)));
}

pub fn getMIDI14BitValue(value: vsttypes.ParamValue) base.int16 {
    if (std.math.isNan(value)) return 0;
    return boundTo(base.int16, 0, 0x3FFF, @intFromFloat(@min(@as(vsttypes.ParamValue, 0x3FFF), value * 0x4000)));
}

pub fn getMIDI14BitNormValue(value: base.int16) vsttypes.ParamValue {
    return boundTo(vsttypes.ParamValue, 0, 1, @as(vsttypes.ParamValue, @floatFromInt(value)) / 0x3FFF);
}

pub fn getPitchBendValue(event: *const events.LegacyMIDICCOutEvent) base.int16 {
    const value: base.int16 = @intCast(event.value & 0x7F);
    const value2: base.int16 = @intCast(event.value2 & 0x7F);
    return value | (value2 << 7);
}

pub fn setPitchBendValue(event: *events.LegacyMIDICCOutEvent, value: vsttypes.ParamValue) void {
    const new_value = getMIDI14BitValue(value);
    event.value = @intCast(new_value & 0x7F);
    event.value2 = @intCast((new_value >> 7) & 0x7F);
}

pub fn getNormPitchBendValue(event: *const events.LegacyMIDICCOutEvent) vsttypes.ParamValue {
    return getMIDI14BitNormValue(getPitchBendValue(event));
}

pub fn initLegacyMIDICCOutEvent(
    event: *events.Event,
    control_number: base.uint8,
    channel: base.int8,
    value: base.int8,
    value2: base.int8,
) *events.LegacyMIDICCOutEvent {
    _ = init(event, @intFromEnum(events.Event.EventTypes.kLegacyMIDICCOutEvent), 0, 0, 0, 0);
    event.data.midiCCOut.channel = channel;
    event.data.midiCCOut.controlNumber = control_number;
    event.data.midiCCOut.value = value;
    event.data.midiCCOut.value2 = value2;
    return &event.data.midiCCOut;
}

test "event helpers match expected MIDI behavior" {
    try @import("std").testing.expectEqual(@as(base.int8, 127), getMIDICCOutValue(1));
    try @import("std").testing.expectEqual(@as(base.int16, 0x3FFF), getMIDI14BitValue(1));
    try @import("std").testing.expectEqual(@as(base.int8, 0), getMIDICCOutValue(std.math.nan(vsttypes.ParamValue)));
    try @import("std").testing.expectEqual(@as(base.int16, 0), getMIDI14BitValue(std.math.nan(vsttypes.ParamValue)));

    var event = events.Event{};
    const midi = initLegacyMIDICCOutEvent(&event, 10, 2, 64, 1);
    try @import("std").testing.expectEqual(@intFromEnum(events.Event.EventTypes.kLegacyMIDICCOutEvent), event.type);
    try @import("std").testing.expectEqual(@as(base.uint8, 10), midi.controlNumber);

    setPitchBendValue(midi, 1);
    try @import("std").testing.expectEqual(@as(base.int16, 0x3FFF), getPitchBendValue(midi));
}
