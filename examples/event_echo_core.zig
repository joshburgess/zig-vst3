const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const EventEcho = struct {
    pub const name = "zig-vst3-plugin Core Event Echo";
    pub const vendor = "zig-vst3";
    pub const event_output = true;
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
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqualStrings("zig-vst3-plugin Core Event Echo", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    try std.testing.expect(Spec.audio_input);
    try std.testing.expect(Spec.audio_output);
    try std.testing.expect(Spec.event_input);
    try std.testing.expect(Spec.event_output);
    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(instance.hasAudioOutput());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(instance.hasEventOutput());
    plug.plugin.validateLifecycle(EventEcho);
}

test "event echo core example can inspect output event writers" {
    var storage: [3]plug.process.Event = undefined;
    var writer = plug.process.EventWriter.init(&storage, 4);
    const source_items = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
        plug.process.Event.noteOff(2, 0, 60, 0.0),
    };
    const source = try plug.process.Events.init(&source_items, 4);

    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.hasEvents());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 3), writer.capacity());
    try std.testing.expectEqual(@as(usize, 3), writer.remainingCapacity());
    try std.testing.expectEqual(@as(usize, 4), writer.frameCount());
    try std.testing.expect(writer.canAppend(2));
    try std.testing.expect(writer.canAppendEvents(source));
    try std.testing.expect(writer.canAppendEvent(source_items[0]));
    try std.testing.expect(!writer.canAppendEvent(plug.process.Event.noteOn(4, 0, 60, 0.75)));

    try std.testing.expectEqual(@as(usize, 2), try writer.appendAllCount(source));
    try std.testing.expectEqual(@as(usize, 2), writer.eventCount());
    try std.testing.expect(!writer.isEmpty());
    try std.testing.expect(writer.hasEvents());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 1), writer.remainingCapacity());
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 2), writer.latestSampleOffset());
    try std.testing.expectEqual(plug.process.EventKind.note_on, writer.first().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, writer.latest().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, writer.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, writer.latestKind(.note_off).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 2), writer.latestSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffsetForKind(.midi_cc));
    try std.testing.expectEqual(plug.process.EventKind.note_off, writer.firstAtOffset(2).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, writer.latestAtOffset(2).?.kind);
    try std.testing.expect(writer.hasKind(.note_on));
    try std.testing.expect(writer.kindEmpty(.pitch_bend));
    try std.testing.expectEqual(@as(usize, 1), writer.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), writer.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), writer.countNoteReleases());
    try std.testing.expectEqual(@as(usize, 1), writer.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), writer.countKindAtOffset(.note_off, 2));
    try std.testing.expectEqual(@as(usize, 2), writer.countBus(0));
    try std.testing.expectEqual(@as(usize, 2), writer.countChannel(0));
    try std.testing.expectEqual(@as(usize, 2), writer.countBusChannel(0, 0));
    try std.testing.expect(writer.hasBus(0));
    try std.testing.expect(!writer.busEmpty(0));
    try std.testing.expect(writer.channelEmpty(1));
    try std.testing.expect(writer.hasBusChannel(0, 0));
    try std.testing.expect(writer.busChannelEmpty(1, 0));
    try std.testing.expect(!writer.onlyAtOffset(1));
    try std.testing.expect(!writer.onlyKind(.note_on));
    try std.testing.expect(!writer.onlyKindAtOffset(.note_on, 1));
    try std.testing.expect(!writer.onlyNoteAttacks());
    try std.testing.expect(!writer.onlyNoteReleases());
    try std.testing.expect(writer.onlyBus(0));
    try std.testing.expect(writer.onlyChannel(0));
    try std.testing.expect(writer.onlyBusChannel(0, 0));

    try std.testing.expectEqual(@as(usize, 1), try writer.appendCount(plug.process.Event.other(3)));
    try std.testing.expect(writer.isFull());
    try std.testing.expect(!writer.canAppend(1));
    try std.testing.expectEqual(@as(usize, 3), writer.events().eventCount());
    try std.testing.expectEqual(plug.process.EventKind.other, writer.latest().?.kind);
    try std.testing.expectEqual(@as(?usize, 2), writer.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 2), writer.nextSampleOffsetForKind(.note_off, 1));
    try std.testing.expectEqual(@as(?usize, 2), writer.nextSampleOffsetForBus(0, 1));
    try std.testing.expectEqual(@as(?usize, 2), writer.nextSampleOffsetForChannel(0, 1));
    try std.testing.expectEqual(@as(?usize, 2), writer.nextSampleOffsetForBusChannel(0, 0, 1));
    try std.testing.expectError(error.EventStorageFull, writer.appendCount(plug.process.Event.noteOn(0, 0, 64, 0.5)));
    try std.testing.expectError(error.EventOutsideBlock, writer.appendCount(plug.process.Event.noteOn(4, 0, 64, 0.5)));

    var note_events = writer.ofKind(.note_on);
    try std.testing.expectEqual(plug.process.EventKind.note_on, note_events.next().?.kind);
    try std.testing.expectEqual(@as(?plug.process.Event, null), note_events.next());

    var events_at_offset = writer.atOffset(2);
    try std.testing.expectEqual(plug.process.EventKind.note_off, events_at_offset.next().?.kind);
    try std.testing.expectEqual(@as(?plug.process.Event, null), events_at_offset.next());

    var segments = writer.blockSegments();
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 2 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 2, .end_offset = 3 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 3, .end_offset = 4 }, segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), segments.next());

    try std.testing.expectEqual(@as(usize, 3), writer.clearCount());
    try std.testing.expectEqual(@as(usize, 0), writer.clearCount());
    try writer.append(source_items[0]);
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    writer.clear();
    try writer.appendAll(source);
    try std.testing.expectEqual(@as(usize, 2), writer.eventCount());
    writer.clear();
    try std.testing.expect(writer.isEmpty());
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
    try std.testing.expect(context.outputEventWriter().? == &output_events);
    try std.testing.expect(!context.outputEventsEmpty());
    try std.testing.expect(context.outputEventsFull());
    const written_events = context.writtenOutputEvents();
    try std.testing.expectEqual(@as(usize, 2), written_events.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.note_on, written_events.first().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, written_events.latest().?.kind);
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, input.len), context.outputEventFrameCount());
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expect(context.hasOutputEvent(.note_off));
    try std.testing.expect(!context.outputEventsOfKindEmpty(.note_on));
    try std.testing.expect(context.outputEventsOfKindEmpty(.midi_cc));
    try std.testing.expect(context.hasOutputNoteAttacks());
    try std.testing.expect(context.hasOutputNoteReleases());
    try std.testing.expect(!context.outputNoteAttacksEmpty());
    try std.testing.expect(!context.outputNoteReleasesEmpty());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputNoteReleases());
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEventsAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEventsAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEventsOfKindAtOffset(.note_on, 0));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEventsOfKindAtOffset(.note_off, 1));
    try std.testing.expect(context.hasOutputEventAtOffset(0));
    try std.testing.expect(context.hasOutputEventAtOffset(1));
    try std.testing.expect(!context.hasOutputEventAtOffset(2));
    try std.testing.expect(context.hasOutputEventOfKindAtOffset(.note_on, 0));
    try std.testing.expect(!context.hasOutputEventOfKindAtOffset(.note_off, 0));
    try std.testing.expect(!context.outputEventsAtOffsetEmpty(0));
    try std.testing.expect(context.outputEventsAtOffsetEmpty(2));
    try std.testing.expect(!context.outputEventsOfKindAtOffsetEmpty(.note_off, 1));
    try std.testing.expect(context.outputEventsOfKindAtOffsetEmpty(.note_off, 0));
    try std.testing.expect(!context.onlyOutputEventsAtOffset(0));
    try std.testing.expect(!context.onlyOutputEventsOfKindAtOffset(.note_on, 0));
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
    try std.testing.expect(!context.outputEventsForChannelEmpty(0));
    try std.testing.expect(context.outputEventsForChannelEmpty(1));
    try std.testing.expect(!context.outputEventsForBusChannelEmpty(0, 0));
    try std.testing.expect(context.outputEventsForBusChannelEmpty(1, 0));
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
    try std.testing.expect(context.canAppendOutputEvents(0));
    try std.testing.expect(!context.canAppendOutputEvents(1));
    try std.testing.expect(!context.canAppendOutputEventValue(events[0]));
    try std.testing.expect(!context.canAppendOutputEventValues(try plug.process.Events.init(&events, input.len)));

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
    try std.testing.expect(context.writtenOutputEvents().isEmpty());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.firstWrittenOutputEvent());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.latestWrittenOutputEvent());
    try std.testing.expect(!context.hasOutputEvent(.note_on));
    try std.testing.expect(!context.hasOutputNoteAttacks());
    try std.testing.expect(!context.hasOutputNoteReleases());
    try std.testing.expect(context.canAppendOutputEvents(2));
    try std.testing.expect(context.canAppendOutputEventValues(try plug.process.Events.init(&events, input.len)));

    try context.appendOutputEvent(events[0]);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 1), try context.appendOutputEventCount(events[1]));
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    context.clearOutputEvents();
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expectEqual(@as(usize, 2), try context.appendOutputEventsCount(try plug.process.Events.init(&events, input.len)));
    try std.testing.expect(context.outputEventsFull());
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
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventFrameCount());
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expect(!context.hasOutputEvents());
    try std.testing.expect(context.outputEventsFull());
    try std.testing.expect(!context.canAppendOutputEvent());
    try std.testing.expect(!context.canAppendOutputEvents(0));
    try std.testing.expect(!context.canAppendOutputEventValue(events[0]));
    try std.testing.expect(!context.canAppendOutputEventValues(try plug.process.Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffset());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.firstWrittenOutputEvent());
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.latestWrittenOutputEvent());
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForBusChannel(0, 0, 0));
    var missing_output_notes = context.outputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(?plug.process.Event, null), missing_output_notes.next());
    try std.testing.expectError(error.OutputEventsUnavailable, context.appendOutputEvent(events[0]));
    try std.testing.expectError(error.OutputEventsUnavailable, context.appendOutputEvents(try plug.process.Events.init(&events, input.len)));

    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input.len);
    try context.setOutputEvents(&output_events);
    try std.testing.expect(context.hasOutputEventWriter());
    try context.appendOutputEvent(events[0]);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
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
