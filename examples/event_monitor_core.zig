const std = @import("std");
const plug = @import("zig-vst3-plugin");

pub const EventMonitor = struct {
    pub const name = "zig-vst3-plugin Core Event Monitor";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};

    note_on_count: usize = 0,
    note_off_count: usize = 0,
    note_attack_count: usize = 0,
    note_release_count: usize = 0,
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
    main_bus_note_count: usize = 0,
    main_bus_event_count: usize = 0,
    next_main_bus_event_offset: ?usize = null,
    channel_zero_midi_count: usize = 0,
    channel_zero_event_count: usize = 0,
    next_channel_zero_event_offset: ?usize = null,
    next_main_bus_channel_zero_event_offset: ?usize = null,
    latest_note_expression_int_value: u64 = 0,

    pub fn process(self: *EventMonitor, context: *plug.process.ProcessContext(f32)) void {
        self.note_on_count = 0;
        self.note_off_count = 0;
        self.note_attack_count = context.countNoteAttacks();
        self.note_release_count = context.countNoteReleases();
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
        if (context.firstInputEvent()) |event| self.first_note_offset = event.sample_offset;
        if (context.latestInputEvent()) |event| self.latest_event_offset = event.sample_offset;
        self.latest_note_expression_offset = context.latestEventOffsetForKind(.note_expression_int);
        self.next_pitch_bend_offset = context.nextEventOffsetForKind(.pitch_bend, 0);
        self.latest_midi_cc_value = 0.0;
        self.latest_aftertouch_bus = 0;
        self.main_bus_note_count = 0;
        self.main_bus_event_count = context.countEventsForBus(0);
        self.next_main_bus_event_offset = context.nextEventOffsetForBus(0, 0);
        self.channel_zero_midi_count = 0;
        self.channel_zero_event_count = context.countEventsForChannel(0);
        self.next_channel_zero_event_offset = context.nextEventOffsetForChannel(0, 0);
        self.next_main_bus_channel_zero_event_offset = context.nextEventOffsetForBusChannel(0, 0, 0);
        self.latest_note_expression_int_value = 0;

        self.note_on_count = context.countEvents(.note_on);
        var note_events = context.inputEventsOfKind(.note_on);
        while (note_events.next()) |event| {
            if (event.isForBus(0)) self.main_bus_note_count += 1;
        }

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
            if (event.isForChannel(0)) self.channel_zero_midi_count += 1;
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
    try std.testing.expectEqualStrings("zig-vst3-plugin Core Event Monitor", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqual(@as(usize, 0), Spec.ParameterSet.count);
    plug.plugin.validateLifecycle(EventMonitor);
}

test "event monitor core example can inspect input event views" {
    const events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
        plug.process.Event.midiCc(2, 0, 74, 0.5),
        plug.process.Event.noteOff(3, 0, 60, 0.0),
    };
    const view = try plug.process.Events.init(&events, 4);

    try std.testing.expectEqual(@as(usize, 3), view.eventCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expect(view.hasEvents());
    try std.testing.expectEqual(@as(?usize, 1), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(plug.process.EventKind.note_on, view.first().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, view.latest().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.midi_cc, view.firstAtOffset(2).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, view.latestAtOffset(3).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_on, view.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, view.latestKind(.note_off).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, view.firstKindAtOffset(.note_off, 3).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, view.latestKindAtOffset(.note_off, 3).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), view.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), view.countNoteAttacks());
    try std.testing.expectEqual(@as(usize, 1), view.countNoteReleases());
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(2));
    try std.testing.expectEqual(@as(usize, 1), view.countKindAtOffset(.note_off, 3));
    try std.testing.expectEqual(@as(usize, 3), view.countBus(0));
    try std.testing.expectEqual(@as(usize, 3), view.countChannel(0));
    try std.testing.expectEqual(@as(usize, 3), view.countBusChannel(0, 0));
    try std.testing.expect(view.hasKind(.note_on));
    try std.testing.expect(view.kindEmpty(.pitch_bend));
    try std.testing.expect(view.hasNoteAttacks());
    try std.testing.expect(view.hasNoteReleases());
    try std.testing.expect(view.hasAtOffset(2));
    try std.testing.expect(!view.hasAtOffset(0));
    try std.testing.expect(view.hasKindAtOffset(.midi_cc, 2));
    try std.testing.expect(view.offsetEmpty(0));
    try std.testing.expect(view.kindAtOffsetEmpty(.midi_cc, 3));
    try std.testing.expect(view.hasBus(0));
    try std.testing.expect(!view.busEmpty(0));
    try std.testing.expect(view.channelEmpty(1));
    try std.testing.expect(view.hasBusChannel(0, 0));
    try std.testing.expect(view.busChannelEmpty(1, 0));
    try std.testing.expect(!view.onlyAtOffset(1));
    try std.testing.expect(!view.onlyKind(.note_on));
    try std.testing.expect(!view.onlyKindAtOffset(.note_on, 1));
    try std.testing.expect(!view.onlyNoteAttacks());
    try std.testing.expect(!view.onlyNoteReleases());
    try std.testing.expect(view.onlyBus(0));
    try std.testing.expect(view.onlyChannel(0));
    try std.testing.expect(view.onlyBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffsetForKind(.note_off, 1));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForBus(0, 1));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForChannel(0, 1));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffsetForBusChannel(0, 0, 1));

    var note_events = view.ofKind(.note_on);
    try std.testing.expectEqual(plug.process.EventKind.note_on, note_events.next().?.kind);
    try std.testing.expectEqual(@as(?plug.process.Event, null), note_events.next());

    var events_at_offset = view.atOffset(2);
    try std.testing.expectEqual(plug.process.EventKind.midi_cc, events_at_offset.next().?.kind);
    try std.testing.expectEqual(@as(?plug.process.Event, null), events_at_offset.next());

    var segments = view.blockSegments(4);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 2 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 2, .end_offset = 3 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 3, .end_offset = 4 }, segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), segments.next());

    const note_only_items = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
    };
    const note_only = try plug.process.Events.init(&note_only_items, 4);
    try std.testing.expect(note_only.onlyAtOffset(1));
    try std.testing.expect(note_only.onlyKind(.note_on));
    try std.testing.expect(note_only.onlyKindAtOffset(.note_on, 1));
    try std.testing.expect(note_only.onlyNoteAttacks());
    try std.testing.expect(!note_only.onlyNoteReleases());

    const outside_block = [_]plug.process.Event{
        plug.process.Event.noteOn(4, 0, 60, 0.75),
    };
    const bad_channel = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 16, 60, 0.75),
    };
    const bad_pitch = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 128, 0.75),
    };
    const bad_control = [_]plug.process.Event{
        plug.process.Event.midiCc(1, 0, 128, 0.5),
    };
    const bad_bus = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75).withBusIndex(-1),
    };
    const bad_value = [_]plug.process.Event{
        plug.process.Event.pitchBend(1, 0, 2.0),
    };
    try std.testing.expectError(error.EventOutsideBlock, plug.process.Events.init(&outside_block, 4));
    try std.testing.expectError(error.InvalidEventChannel, plug.process.Events.init(&bad_channel, 4));
    try std.testing.expectError(error.InvalidEventPitch, plug.process.Events.init(&bad_pitch, 4));
    try std.testing.expectError(error.InvalidEventControlNumber, plug.process.Events.init(&bad_control, 4));
    try std.testing.expectError(error.InvalidEventBusIndex, plug.process.Events.init(&bad_bus, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, plug.process.Events.init(&bad_value, 4));
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

    const input_event_view = context.inputEvents();
    try std.testing.expectEqual(@as(usize, 11), context.inputEventCount());
    try std.testing.expectEqual(@as(usize, 11), input_event_view.eventCount());
    try std.testing.expect(!context.inputEventsEmpty());
    try std.testing.expect(context.hasInputEvents());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, 3), context.latestEventOffset());
    try std.testing.expectEqual(@as(?usize, 2), context.nextEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 3), context.nextEventOffset(2));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(3));
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstInputEvent().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestInputEvent().?.kind);
    try std.testing.expectEqual(plug.process.EventKind.midi_cc, context.firstInputEventAtOffset(2).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestInputEventAtOffset(3).?.kind);
    try std.testing.expect(context.firstInputEventAtOffset(0) == null);
    try std.testing.expect(context.hasEvent(.note_on));
    try std.testing.expect(!context.eventsOfKindEmpty(.midi_cc));
    try std.testing.expectEqual(@as(usize, 9), context.countEventsAtOffset(3));
    try std.testing.expectEqual(@as(usize, 1), context.countEventsOfKindAtOffset(.note_on, 3));
    try std.testing.expect(context.hasEventAtOffset(2));
    try std.testing.expect(!context.hasEventAtOffset(0));
    try std.testing.expect(context.hasEventOfKindAtOffset(.midi_cc, 2));
    try std.testing.expect(!context.hasEventOfKindAtOffset(.midi_cc, 3));
    try std.testing.expect(context.eventsAtOffsetEmpty(0));
    try std.testing.expect(!context.eventsAtOffsetEmpty(3));
    try std.testing.expect(context.eventsOfKindAtOffsetEmpty(.midi_cc, 3));
    try std.testing.expect(!context.eventsOfKindAtOffsetEmpty(.midi_cc, 2));
    try std.testing.expect(context.hasNoteAttacks());
    try std.testing.expect(context.hasNoteReleases());
    try std.testing.expect(!context.noteAttacksEmpty());
    try std.testing.expect(!context.noteReleasesEmpty());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 3), context.latestEventOffsetForBus(0));
    try std.testing.expectEqual(@as(?usize, 3), context.firstEventOffsetForBus(2));
    try std.testing.expectEqual(@as(usize, 10), context.countEventsForBus(0));
    try std.testing.expect(context.hasEventsForBus(0));
    try std.testing.expect(!context.eventsForBusEmpty(0));
    try std.testing.expect(!context.hasEventsForBus(3));
    try std.testing.expect(context.eventsForBusEmpty(3));
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstEventForBus(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestEventForBus(0).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(?usize, 3), context.latestEventOffsetForChannel(0));
    try std.testing.expectEqual(@as(usize, 6), context.countEventsForChannel(0));
    try std.testing.expect(context.hasEventsForChannel(0));
    try std.testing.expect(!context.eventsForChannelEmpty(0));
    try std.testing.expect(!context.hasEventsForChannel(9));
    try std.testing.expect(context.eventsForChannelEmpty(9));
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstEventForChannel(0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestEventForChannel(0).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(?usize, 3), context.latestEventOffsetForBusChannel(0, 0));
    try std.testing.expectEqual(@as(usize, 5), context.countEventsForBusChannel(0, 0));
    try std.testing.expect(context.hasEventsForBusChannel(0, 0));
    try std.testing.expect(!context.eventsForBusChannelEmpty(0, 0));
    try std.testing.expect(!context.hasEventsForBusChannel(3, 0));
    try std.testing.expect(context.eventsForBusChannelEmpty(3, 0));
    try std.testing.expectEqual(plug.process.EventKind.note_on, context.firstEventForBusChannel(0, 0).?.kind);
    try std.testing.expectEqual(plug.process.EventKind.note_off, context.latestEventForBusChannel(0, 0).?.kind);
    try std.testing.expect(!context.onlyInputEventsAtOffset(3));
    try std.testing.expect(!context.onlyInputEventsOfKind(.note_on));
    try std.testing.expect(!context.onlyInputEventsOfKindAtOffset(.note_on, 3));
    try std.testing.expect(!context.onlyInputNoteAttacks());
    try std.testing.expect(!context.onlyInputNoteReleases());
    try std.testing.expect(!context.onlyInputEventsForBus(0));
    try std.testing.expect(!context.onlyInputEventsForChannel(0));
    try std.testing.expect(!context.onlyInputEventsForBusChannel(0, 0));

    const note_only_events = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 60, 0.75),
    };
    const note_only_context = try plug.process.ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .events = &note_only_events,
    });
    try std.testing.expect(note_only_context.onlyInputEventsAtOffset(1));
    try std.testing.expect(note_only_context.onlyInputEventsOfKind(.note_on));
    try std.testing.expect(note_only_context.onlyInputEventsOfKindAtOffset(.note_on, 1));
    try std.testing.expect(note_only_context.onlyInputNoteAttacks());
    try std.testing.expect(!note_only_context.onlyInputNoteReleases());
    try std.testing.expect(note_only_context.onlyInputEventsForBus(0));
    try std.testing.expect(note_only_context.onlyInputEventsForChannel(0));
    try std.testing.expect(note_only_context.onlyInputEventsForBusChannel(0, 0));

    const note_attack = events[0].asNoteAttack().?;
    try std.testing.expectEqual(@as(i16, 60), note_attack.pitch);
    try std.testing.expectEqual(plug.process.NoteLifecycle.attack, events[0].noteLifecycle());
    try std.testing.expect(events[0].isKindAtOffset(.note_on, 1));
    try std.testing.expect(events[0].isNoteForPitch(60));
    const note_release = events[10].asNoteRelease().?;
    try std.testing.expectEqual(@as(i16, 60), note_release.pitch);
    try std.testing.expectEqual(plug.process.NoteLifecycle.release, events[10].noteLifecycle());
    try std.testing.expect(events[10].isNoteRelease());
    try std.testing.expect(events[1].isMidi());
    try std.testing.expectEqual(@as(i16, 74), events[1].asMidiCC().?.control_number);
    try std.testing.expectEqual(@as(f32, 0.25), events[3].asPitchBend().?.value);
    try std.testing.expectEqual(@as(f32, 0.75), events[5].asNoteExpressionValue().?.value);
    try std.testing.expectEqual(@as(u32, 5), events[7].asNoteExpressionText().?.expression_type_id);
    try std.testing.expect(events[8].isData());
    try std.testing.expectEqualSlices(u8, &sysex, events[8].asData().?.data);
    try std.testing.expect(events[9].isOther());

    const retargeted_note = plug.process.Event.noteOn(0, 0, 60, 0.25)
        .withSampleOffset(2)
        .withChannel(1)
        .withPitch(64)
        .withVelocity(0.5);
    const retargeted_note_payload = retargeted_note.asNoteOn().?;
    try std.testing.expectEqual(@as(usize, 2), retargeted_note_payload.sample_offset);
    try std.testing.expectEqual(@as(i16, 1), retargeted_note_payload.channel);
    try std.testing.expectEqual(@as(i16, 64), retargeted_note_payload.pitch);
    try std.testing.expectEqual(@as(f32, 0.5), retargeted_note_payload.velocity);

    const retargeted_cc = plug.process.Event.midiCc(0, 0, 1, 0.25)
        .withBusIndex(2)
        .withSampleOffset(3)
        .withChannel(4)
        .withControlNumber(74)
        .withValue(0.5);
    const cc_payload = retargeted_cc.asMidiCC().?;
    try std.testing.expectEqual(@as(i32, 2), cc_payload.bus_index);
    try std.testing.expectEqual(@as(usize, 3), cc_payload.sample_offset);
    try std.testing.expectEqual(@as(i16, 4), cc_payload.channel);
    try std.testing.expectEqual(@as(i16, 74), cc_payload.control_number);
    try std.testing.expectEqual(@as(f32, 0.5), cc_payload.value);

    const retargeted_expression = plug.process.Event.noteExpressionInt(0, 1, 2, 3)
        .withNoteId(8)
        .withExpressionTypeId(9)
        .withIntValue(10);
    const expression_payload = retargeted_expression.asNoteExpressionInt().?;
    try std.testing.expectEqual(@as(i32, 8), expression_payload.note_id);
    try std.testing.expectEqual(@as(u32, 9), expression_payload.expression_type_id);
    try std.testing.expectEqual(@as(u64, 10), expression_payload.value);

    const retargeted_data = plug.process.Event.dataEvent(0, 0, &sysex)
        .withDataType(7)
        .withData(sysex[1..]);
    const data_payload = retargeted_data.asData().?;
    try std.testing.expectEqual(@as(u32, 7), data_payload.data_type);
    try std.testing.expectEqualSlices(u8, sysex[1..], data_payload.data);

    plugin.process(&context);

    try std.testing.expectEqual(@as(usize, 2), plugin.note_on_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_off_count);
    try std.testing.expectEqual(@as(usize, 2), plugin.note_attack_count);
    try std.testing.expectEqual(@as(usize, 1), plugin.note_release_count);
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
    try std.testing.expectEqual(@as(usize, 2), plugin.main_bus_note_count);
    try std.testing.expectEqual(@as(usize, 10), plugin.main_bus_event_count);
    try std.testing.expectEqual(@as(?usize, 1), plugin.next_main_bus_event_offset);
    try std.testing.expectEqual(@as(usize, 1), plugin.channel_zero_midi_count);
    try std.testing.expectEqual(@as(usize, 6), plugin.channel_zero_event_count);
    try std.testing.expectEqual(@as(?usize, 1), plugin.next_channel_zero_event_offset);
    try std.testing.expectEqual(@as(?usize, 1), plugin.next_main_bus_channel_zero_event_offset);
    try std.testing.expectEqual(@as(u64, 7), plugin.latest_note_expression_int_value);

    var segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 1, .end_offset = 2 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 2, .end_offset = 3 }, segments.next().?);
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 3, .end_offset = 4 }, segments.next().?);
    try std.testing.expectEqual(@as(?plug.process.BlockSegment, null), segments.next());
}

test "event monitor core example reports empty input event views" {
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const context = try plug.process.ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectEqual(@as(usize, 0), context.inputEventCount());
    try std.testing.expect(context.inputEventsEmpty());
    try std.testing.expect(!context.hasInputEvents());
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(0));
    try std.testing.expectEqual(@as(usize, 0), context.countNoteAttacks());
    try std.testing.expect(!context.hasNoteAttacks());
    try std.testing.expect(context.noteAttacksEmpty());
    try std.testing.expect(!context.onlyInputEventsOfKind(.note_on));
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.firstEvent(.note_on));
    try std.testing.expectEqual(@as(?plug.process.Event, null), context.latestInputEvent());

    var note_events = context.inputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(?plug.process.Event, null), note_events.next());

    var segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(plug.process.BlockSegment{ .start_offset = 0, .end_offset = 1 }, segments.next().?);
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
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.main_bus_event_count);
    try std.testing.expectEqual(@as(?usize, 1), instance.plugin.next_main_bus_event_offset);
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.channel_zero_midi_count);
    try std.testing.expectEqual(@as(usize, 1), instance.plugin.channel_zero_event_count);
    try std.testing.expectEqual(@as(?usize, 1), instance.plugin.next_channel_zero_event_offset);
    try std.testing.expectEqual(@as(?usize, 1), instance.plugin.next_main_bus_channel_zero_event_offset);
    try std.testing.expectEqual(@as(f64, 0.25), instance.plugin.latest_midi_cc_value);
}
