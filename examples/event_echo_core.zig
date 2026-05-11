const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const EventEcho = struct {
    pub const name = "zig-vst3-plugin Core Event Echo";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    pub fn process(_: *EventEcho, context: *plug.process.ProcessContext(f32)) void {
        const events = context.inputEvents();
        if (!context.canAppendOutputEventValues(events)) return;
        context.appendOutputEvents(events) catch return;
    }
};

pub const Spec = plug.plugin.PluginSpec(EventEcho);
pub const Instance = plug.plugin.PluginInstance(EventEcho);

test "event echo core example declares reflected metadata" {
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Event Echo", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    plug.plugin.validateLifecycle(EventEcho);
}

test "event echo core example writes input events to output events" {
    var plugin = EventEcho{};
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOff(1, 0, 60, 0.0),
    };
    var output_event_storage: [2]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    plugin.process(&context);

    try std.testing.expect(context.hasOutputEventWriter());
    try std.testing.expect(!context.outputEventsEmpty());
    try std.testing.expect(context.outputEventsFull());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, input.len), context.outputEventFrameCount());
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expect(context.hasOutputEvent(.note_off));
    try std.testing.expect(context.hasOutputNoteAttacks());
    try std.testing.expect(context.hasOutputNoteReleases());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteReleases());
    try std.testing.expect(!context.onlyOutputEventsOfKind(.note_on));
    try std.testing.expect(!context.onlyOutputNoteAttacks());
    try std.testing.expect(!context.onlyOutputNoteReleases());
    try std.testing.expect(context.hasOutputEventsForBus(0));
    try std.testing.expect(context.hasOutputEventsForChannel(0));
    try std.testing.expect(context.hasOutputEventsForBusChannel(0, 0));
    try std.testing.expect(context.onlyOutputEventsForBus(0));
    try std.testing.expect(context.onlyOutputEventsForChannel(0));
    try std.testing.expect(context.onlyOutputEventsForBusChannel(0, 0));
    try std.testing.expect(!context.hasOutputEventsForBus(1));
    try std.testing.expect(context.outputEventsForBusEmpty(1));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForBus(0));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForChannel(0));
    try std.testing.expectEqual(@as(usize, 2), context.countOutputEventsForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEventsForBusChannel(1, 0));
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstWrittenOutputEvent().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestWrittenOutputEvent().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstOutputEventAtOffset(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestOutputEventAtOffset(1).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstOutputEventOfKindAtOffset(.note_on, 0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestOutputEventOfKindAtOffset(.note_off, 1).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstOutputEventForBus(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestOutputEventForBus(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstOutputEventForChannel(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestOutputEventForChannel(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstOutputEventForBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestOutputEventForBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(@as(usize, 0), context.firstOutputEvent(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(usize, 1), context.latestOutputEvent(.note_off).?.sample_offset);
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffsetForBus(1));
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.firstOutputEventForBus(1));
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.latestOutputEventForChannel(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForKind(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForBus(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForBusChannel(0, 0, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBus(1, 0));
    try std.testing.expect(!context.canAppendOutputEvent());
    try std.testing.expect(!context.canAppendOutputEventValue(events[0]));

    var output_events_at_offset = context.outputEventsAtOffset(1);
    try std.testing.expectEqual(plug.process.EventKind.note_off, output_events_at_offset.next().?.kind);
    try std.testing.expectEqual(@as(?plug.process.Event, null), output_events_at_offset.next());

    var output_note_events = context.outputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(usize, 0), output_note_events.next().?.sample_offset);
    try std.testing.expectEqual(@as(?plug.process.Event, null), output_note_events.next());

    var segments = context.outputEventBlockSegments();
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 2 }, segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), segments.next());

    try std.testing.expectEqual(@as(usize, 2), context.clearOutputEventsCount());
    try std.testing.expectEqual(@as(usize, 0), context.clearOutputEventsCount());
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expect(!context.hasOutputEvents());
    try std.testing.expect(!context.outputEventsFull());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.firstWrittenOutputEvent());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.latestWrittenOutputEvent());
    try std.testing.expect(!context.hasOutputEvent(.note_on));
    try std.testing.expect(!context.hasOutputNoteAttacks());
    try std.testing.expect(!context.hasOutputNoteReleases());
}

test "event echo core example leaves output unchanged when capacity is too small" {
    var plugin = EventEcho{};
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
        plug.process.Event.noteOff(1, 0, 60, 0.0),
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 1), context.outputEventRemainingCapacity());
}

test "event echo core example ignores events when no output writer is attached" {
    var plugin = EventEcho{};
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
    };
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
    });

    plugin.process(&context);

    try std.testing.expect(!context.hasOutputEventWriter());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expect(context.outputEventsEmpty());
}

test "event echo core example can run through plugin instance" {
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]plug.process.Event{
        plug.process.Event.noteOff(0, 0, 60, 0.0),
    };
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    var context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &events,
        .output_events = &output_events,
    });

    instance.process(&context);

    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expect(context.hasOutputEvent(.note_off));
    try std.testing.expect(context.hasOutputNoteReleases());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteReleases());
    try std.testing.expectEqual(@as(usize, 0), context.firstOutputEvent(.note_off).?.sample_offset);
}
