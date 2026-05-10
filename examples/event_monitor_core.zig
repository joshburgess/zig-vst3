const std = @import("std");
const plug = @import("zig-plug");

pub const EventMonitor = struct {
    pub const name = "zig-plug Core Event Monitor";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    note_on_count: usize = 0,
    note_off_count: usize = 0,
    midi_cc_count: usize = 0,
    pitch_bend_count: usize = 0,
    aftertouch_count: usize = 0,
    note_expression_value_count: usize = 0,
    note_expression_int_count: usize = 0,
    note_expression_text_count: usize = 0,
    data_count: usize = 0,
    other_count: usize = 0,
    first_note_offset: ?usize = null,
    latest_event_offset: ?usize = null,
    latest_note_expression_offset: ?usize = null,
    next_pitch_bend_offset: ?usize = null,
    latest_midi_cc_value: f64 = 0.0,
    latest_aftertouch_bus: i32 = 0,
    latest_note_expression_int_value: u64 = 0,

    pub fn process(self: *EventMonitor, context: *plug.process.ProcessContext(f32)) void {
        self.note_on_count = 0;
        self.note_off_count = 0;
        self.midi_cc_count = 0;
        self.pitch_bend_count = 0;
        self.aftertouch_count = 0;
        self.note_expression_value_count = 0;
        self.note_expression_int_count = 0;
        self.note_expression_text_count = 0;
        self.data_count = 0;
        self.other_count = 0;
        self.first_note_offset = context.firstEventOffsetForKind(.note_on);
        self.latest_event_offset = context.latestEventOffset();
        self.latest_note_expression_offset = context.latestEventOffsetForKind(.note_expression_int);
        self.next_pitch_bend_offset = context.nextEventOffsetForKind(.pitch_bend, 0);
        self.latest_midi_cc_value = 0.0;
        self.latest_aftertouch_bus = 0;
        self.latest_note_expression_int_value = 0;

        var note_events = context.inputEventsOfKind(.note_on);
        while (note_events.next()) |_| self.note_on_count += 1;

        self.note_off_count = context.countEvents(.note_off);
        self.pitch_bend_count = context.countEvents(.pitch_bend);
        self.aftertouch_count = context.countEvents(.aftertouch);
        self.note_expression_value_count = context.countEvents(.note_expression_value);
        self.note_expression_int_count = context.countEvents(.note_expression_int);
        self.note_expression_text_count = context.countEvents(.note_expression_text);
        self.data_count = context.countEvents(.data);
        self.other_count = context.countEvents(.other);

        var cc_events = context.inputEventsOfKind(.midi_cc);
        while (cc_events.next()) |event| {
            const cc = event.asMidiCC().?;
            self.midi_cc_count += 1;
            self.latest_midi_cc_value = cc.value;
        }

        if (context.latestEvent(.aftertouch)) |event| {
            self.latest_aftertouch_bus = event.asAftertouch().?.bus_index;
        }
        if (context.latestEvent(.note_expression_int)) |event| {
            self.latest_note_expression_int_value = event.asNoteExpressionInt().?.value;
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(EventMonitor);
pub const Instance = plug.plugin.PluginInstance(EventMonitor);

test "event monitor core example declares reflected metadata" {
    try std.testing.expectEqualStrings("zig-plug Core Event Monitor", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    plug.plugin.validateLifecycle(EventMonitor);
}

test "event monitor core example summarizes input event kinds" {
    var plugin = EventMonitor{};
    const input = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const sysex = [_]u8{ 0xf0, 0x7d, 0x00, 0xf7 };
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
        plug.process.Event.midiCc(2, 0, 74, 0.5),
        plug.process.Event.noteOn(3, 0, 64, 0.5),
        plug.process.Event.pitchBend(3, 0, 0.25),
        plug.process.Event.aftertouch(3, 0, 64, 0.5).withBusIndex(2),
        plug.process.Event.noteExpressionValue(3, 42, 5, 0.75),
        plug.process.Event.noteExpressionInt(3, 42, 5, 7),
        plug.process.Event.noteExpressionText(3, 42, 5),
        plug.process.Event.dataEvent(3, 0, &sysex),
        plug.process.Event.other(3),
        plug.process.Event.noteOff(3, 0, 60, 0.0),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 2), plugin.note_on_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_off_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.midi_cc_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.pitch_bend_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.aftertouch_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_expression_value_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_expression_int_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_expression_text_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.data_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.other_count);
    try std.testing.expectEqual(@as(?usize, 1), plugin.first_note_offset);
    try std.testing.expectEqual(@as(?usize, 3), plugin.latest_event_offset);
    try std.testing.expectEqual(@as(?usize, 3), plugin.latest_note_expression_offset);
    try std.testing.expectEqual(@as(?usize, 3), plugin.next_pitch_bend_offset);
    try std.testing.expectEqual(@as(f64, 0.5), plugin.latest_midi_cc_value);
    try std.testing.expectEqual(@as(i32, 2), plugin.latest_aftertouch_bus);
    try std.testing.expectEqual(@as(u64, 7), plugin.latest_note_expression_int_value);

    var segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 2 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 2, .end_offset = 3 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 3, .end_offset = 4 }, segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), segments.next());
}

test "event monitor core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.midiCc(1, 0, 1, 0.25),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(usize, 1), instance.plugin.midi_cc_count);
    try std.testing.expectEqual(@as(f64, 0.25), instance.plugin.latest_midi_cc_value);
}
