const std = @import("std");
const events = @import("zig-vst3").pluginterfaces.vst.ivstevents;
const helpers = @import("zig-vst3").pluginterfaces.vst.vsteventshelper;
const noteexpression = @import("zig-vst3").pluginterfaces.vst.ivstnoteexpression;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};
    try stdout.print("NoteIDUserRange.kNoteIDUserRangeLowerBound {}\n", .{@intFromEnum(events.NoteIDUserRange.kNoteIDUserRangeLowerBound)});
    try stdout.print("NoteIDUserRange.kNoteIDUserRangeUpperBound {}\n", .{@intFromEnum(events.NoteIDUserRange.kNoteIDUserRangeUpperBound)});
    try stdout.print("DataEvent.kMidiSysEx {}\n", .{@intFromEnum(events.DataEvent.DataTypes.kMidiSysEx)});
    try stdout.print("Event.kIsLive {}\n", .{events.Event.EventFlags.kIsLive});
    try stdout.print("Event.kUserReserved1 {}\n", .{events.Event.EventFlags.kUserReserved1});
    try stdout.print("Event.kUserReserved2 {}\n", .{events.Event.EventFlags.kUserReserved2});
    try stdout.print("Event.kNoteOnEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kNoteOnEvent)});
    try stdout.print("Event.kNoteOffEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kNoteOffEvent)});
    try stdout.print("Event.kDataEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kDataEvent)});
    try stdout.print("Event.kPolyPressureEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kPolyPressureEvent)});
    try stdout.print("Event.kNoteExpressionValueEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kNoteExpressionValueEvent)});
    try stdout.print("Event.kNoteExpressionTextEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kNoteExpressionTextEvent)});
    try stdout.print("Event.kChordEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kChordEvent)});
    try stdout.print("Event.kScaleEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kScaleEvent)});
    try stdout.print("Event.kNoteExpressionIntValueEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kNoteExpressionIntValueEvent)});
    try stdout.print("Event.kLegacyMIDICCOutEvent {}\n", .{@intFromEnum(events.Event.EventTypes.kLegacyMIDICCOutEvent)});

    try printType(stdout, "NoteOnEvent", events.NoteOnEvent);
    try printOffset(stdout, "NoteOnEvent", "channel", events.NoteOnEvent, "channel");
    try printOffset(stdout, "NoteOnEvent", "pitch", events.NoteOnEvent, "pitch");
    try printOffset(stdout, "NoteOnEvent", "tuning", events.NoteOnEvent, "tuning");
    try printOffset(stdout, "NoteOnEvent", "velocity", events.NoteOnEvent, "velocity");
    try printOffset(stdout, "NoteOnEvent", "length", events.NoteOnEvent, "length");
    try printOffset(stdout, "NoteOnEvent", "noteId", events.NoteOnEvent, "noteId");
    try printType(stdout, "NoteOffEvent", events.NoteOffEvent);
    try printOffset(stdout, "NoteOffEvent", "channel", events.NoteOffEvent, "channel");
    try printOffset(stdout, "NoteOffEvent", "pitch", events.NoteOffEvent, "pitch");
    try printOffset(stdout, "NoteOffEvent", "velocity", events.NoteOffEvent, "velocity");
    try printOffset(stdout, "NoteOffEvent", "noteId", events.NoteOffEvent, "noteId");
    try printOffset(stdout, "NoteOffEvent", "tuning", events.NoteOffEvent, "tuning");
    try printType(stdout, "DataEvent", events.DataEvent);
    try printOffset(stdout, "DataEvent", "size", events.DataEvent, "size");
    try printOffset(stdout, "DataEvent", "type", events.DataEvent, "type");
    try printOffset(stdout, "DataEvent", "bytes", events.DataEvent, "bytes");
    try printType(stdout, "PolyPressureEvent", events.PolyPressureEvent);
    try printOffset(stdout, "PolyPressureEvent", "channel", events.PolyPressureEvent, "channel");
    try printOffset(stdout, "PolyPressureEvent", "pitch", events.PolyPressureEvent, "pitch");
    try printOffset(stdout, "PolyPressureEvent", "pressure", events.PolyPressureEvent, "pressure");
    try printOffset(stdout, "PolyPressureEvent", "noteId", events.PolyPressureEvent, "noteId");
    try printType(stdout, "ChordEvent", events.ChordEvent);
    try printOffset(stdout, "ChordEvent", "root", events.ChordEvent, "root");
    try printOffset(stdout, "ChordEvent", "bassNote", events.ChordEvent, "bassNote");
    try printOffset(stdout, "ChordEvent", "mask", events.ChordEvent, "mask");
    try printOffset(stdout, "ChordEvent", "textLen", events.ChordEvent, "textLen");
    try printOffset(stdout, "ChordEvent", "text", events.ChordEvent, "text");
    try printType(stdout, "ScaleEvent", events.ScaleEvent);
    try printOffset(stdout, "ScaleEvent", "root", events.ScaleEvent, "root");
    try printOffset(stdout, "ScaleEvent", "mask", events.ScaleEvent, "mask");
    try printOffset(stdout, "ScaleEvent", "textLen", events.ScaleEvent, "textLen");
    try printOffset(stdout, "ScaleEvent", "text", events.ScaleEvent, "text");
    try printType(stdout, "LegacyMIDICCOutEvent", events.LegacyMIDICCOutEvent);
    try printOffset(stdout, "LegacyMIDICCOutEvent", "controlNumber", events.LegacyMIDICCOutEvent, "controlNumber");
    try printOffset(stdout, "LegacyMIDICCOutEvent", "channel", events.LegacyMIDICCOutEvent, "channel");
    try printOffset(stdout, "LegacyMIDICCOutEvent", "value", events.LegacyMIDICCOutEvent, "value");
    try printOffset(stdout, "LegacyMIDICCOutEvent", "value2", events.LegacyMIDICCOutEvent, "value2");
    try printType(stdout, "NoteExpressionValueEvent", noteexpression.NoteExpressionValueEvent);
    try printType(stdout, "NoteExpressionIntValueEvent", noteexpression.NoteExpressionIntValueEvent);
    try printType(stdout, "NoteExpressionTextEvent", noteexpression.NoteExpressionTextEvent);
    try printType(stdout, "Event", events.Event);
    try printOffset(stdout, "Event", "busIndex", events.Event, "busIndex");
    try printOffset(stdout, "Event", "sampleOffset", events.Event, "sampleOffset");
    try printOffset(stdout, "Event", "ppqPosition", events.Event, "ppqPosition");
    try printOffset(stdout, "Event", "flags", events.Event, "flags");
    try printOffset(stdout, "Event", "type", events.Event, "type");
    try printOffset(stdout, "Event", "noteOn", events.Event, "data");
    try printOffset(stdout, "Event", "noteExpressionText", events.Event, "data");
    try printOffset(stdout, "Event", "midiCCOut", events.Event, "data");

    var event = events.Event{};
    _ = helpers.init(&event, @intFromEnum(events.Event.EventTypes.kDataEvent), 2, 64, 12.5, events.Event.EventFlags.kIsLive);
    try stdout.print("Helpers.init.busIndex {}\n", .{event.busIndex});
    try stdout.print("Helpers.init.sampleOffset {}\n", .{event.sampleOffset});
    try stdout.print("Helpers.init.ppqPosition {d:.6}\n", .{event.ppqPosition});
    try stdout.print("Helpers.init.flags {}\n", .{event.flags});
    try stdout.print("Helpers.init.type {}\n", .{event.type});
    try stdout.print("Helpers.getMIDINormValue.64 {d:.12}\n", .{helpers.getMIDINormValue(64)});
    try stdout.print("Helpers.getMIDICCOutValue.1 {}\n", .{helpers.getMIDICCOutValue(1)});
    try stdout.print("Helpers.getMIDI14BitValue.1 {}\n", .{helpers.getMIDI14BitValue(1)});
    try stdout.print("Helpers.getMIDI14BitNormValue.8192 {d:.12}\n", .{helpers.getMIDI14BitNormValue(8192)});
    const midi = helpers.initLegacyMIDICCOutEvent(&event, 10, 2, 64, 1);
    try stdout.print("Helpers.initLegacy.type {}\n", .{event.type});
    try stdout.print("Helpers.initLegacy.controlNumber {}\n", .{midi.controlNumber});
    try stdout.print("Helpers.initLegacy.channel {}\n", .{midi.channel});
    try stdout.print("Helpers.initLegacy.value {}\n", .{midi.value});
    try stdout.print("Helpers.initLegacy.value2 {}\n", .{midi.value2});
    helpers.setPitchBendValue(midi, 1);
    try stdout.print("Helpers.pitchBend.value {}\n", .{midi.value});
    try stdout.print("Helpers.pitchBend.value2 {}\n", .{midi.value2});
    try stdout.print("Helpers.getPitchBendValue {}\n", .{helpers.getPitchBendValue(midi)});
    try stdout.print("Helpers.getNormPitchBendValue {d:.12}\n", .{helpers.getNormPitchBendValue(midi)});

    try printType(stdout, "IEventList", events.IEventList);
    try printTuid(stdout, "IEventList", events.ievent_list_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}
