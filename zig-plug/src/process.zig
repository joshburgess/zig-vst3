const std = @import("std");

pub const ParameterChange = struct {
    id: u32,
    sample_offset: usize,
    normalized: f64,
};

pub const ParameterChanges = struct {
    items: []const ParameterChange = &.{},

    pub fn init(items: []const ParameterChange, frame_count: usize) !ParameterChanges {
        for (items) |item| {
            if (item.sample_offset >= frame_count) {
                return error.ParameterChangeOutsideBlock;
            }
            if (item.normalized < 0.0 or item.normalized > 1.0 or std.math.isNan(item.normalized)) {
                return error.ParameterChangeOutsideNormalizedRange;
            }
        }
        return .{ .items = items };
    }

    pub fn latest(self: ParameterChanges, id: u32) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.id == id) result = item;
        }
        return result;
    }

    pub fn latestNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.latest(id) orelse return null;
        return change.normalized;
    }

    pub fn latestAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.id == id and item.sample_offset <= sample_offset) result = item;
        }
        return result;
    }

    pub fn latestNormalizedAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.latestAtOrBefore(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn nextSampleOffset(self: ParameterChanges, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }
};

pub const EventKind = enum {
    note_on,
    note_off,
    midi_cc,
    pitch_bend,
    aftertouch,
    note_expression_value,
    note_expression_int,
    note_expression_text,
    data,
    other,
};

pub const Event = struct {
    kind: EventKind,
    bus_index: i32,
    sample_offset: usize,
    channel: i16 = 0,
    pitch: i16 = 0,
    control_number: i16 = 0,
    note_id: i32 = 0,
    expression_type_id: u32 = 0,
    data_type: u32 = 0,
    data: []const u8 = &.{},
    velocity: f32 = 0,
    value: f32 = 0,
    int_value: u64 = 0,

    pub fn noteOn(sample_offset: usize, channel: i16, pitch: i16, velocity: f32) Event {
        return .{
            .kind = .note_on,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .velocity = velocity,
        };
    }

    pub fn noteOff(sample_offset: usize, channel: i16, pitch: i16, velocity: f32) Event {
        return .{
            .kind = .note_off,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .velocity = velocity,
        };
    }

    pub fn midiCc(sample_offset: usize, channel: i16, control_number: i16, value: f32) Event {
        return .{
            .kind = .midi_cc,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .control_number = control_number,
            .value = value,
        };
    }

    pub fn pitchBend(sample_offset: usize, channel: i16, value: f32) Event {
        return .{
            .kind = .pitch_bend,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .value = value,
        };
    }

    pub fn aftertouch(sample_offset: usize, channel: i16, pitch: i16, value: f32) Event {
        return .{
            .kind = .aftertouch,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .channel = channel,
            .pitch = pitch,
            .value = value,
        };
    }

    pub fn noteExpressionValue(sample_offset: usize, note_id: i32, expression_type_id: u32, value: f32) Event {
        return .{
            .kind = .note_expression_value,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
            .value = value,
        };
    }

    pub fn noteExpressionInt(sample_offset: usize, note_id: i32, expression_type_id: u32, value: u64) Event {
        return .{
            .kind = .note_expression_int,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
            .int_value = value,
        };
    }

    pub fn noteExpressionText(sample_offset: usize, note_id: i32, expression_type_id: u32) Event {
        return .{
            .kind = .note_expression_text,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .note_id = note_id,
            .expression_type_id = expression_type_id,
        };
    }

    pub fn dataEvent(sample_offset: usize, data_type: u32, data: []const u8) Event {
        return .{
            .kind = .data,
            .bus_index = 0,
            .sample_offset = sample_offset,
            .data_type = data_type,
            .data = data,
        };
    }

    pub fn other(sample_offset: usize) Event {
        return .{
            .kind = .other,
            .bus_index = 0,
            .sample_offset = sample_offset,
        };
    }
};

pub const Events = struct {
    items: []const Event = &.{},

    pub fn init(items: []const Event, frame_count: usize) !Events {
        for (items) |item| {
            if (item.sample_offset >= frame_count) {
                return error.EventOutsideBlock;
            }
        }
        return .{ .items = items };
    }

    pub fn countKind(self: Events, kind: EventKind) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.kind == kind) count += 1;
        }
        return count;
    }

    pub fn hasKind(self: Events, kind: EventKind) bool {
        for (self.items) |item| {
            if (item.kind == kind) return true;
        }
        return false;
    }
};

pub const EventWriter = struct {
    storage: []Event,
    count: usize = 0,
    frame_count: usize,

    pub fn init(storage: []Event, frame_count: usize) EventWriter {
        return .{
            .storage = storage,
            .frame_count = frame_count,
        };
    }

    pub fn append(self: *EventWriter, event: Event) !void {
        if (event.sample_offset >= self.frame_count) return error.EventOutsideBlock;
        if (self.count >= self.storage.len) return error.EventStorageFull;
        self.storage[self.count] = event;
        self.count += 1;
    }

    pub fn appendAll(self: *EventWriter, source: Events) !void {
        if (source.items.len > self.storage.len - self.count) return error.EventStorageFull;
        for (source.items) |event| {
            if (event.sample_offset >= self.frame_count) return error.EventOutsideBlock;
        }
        for (source.items) |event| {
            self.storage[self.count] = event;
            self.count += 1;
        }
    }

    pub fn events(self: *const EventWriter) Events {
        return .{ .items = self.storage[0..self.count] };
    }
};

pub fn AudioInputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []const Sample,
        frame_count: usize,

        pub fn init(channels: []const []const Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]const Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }
    };
}

pub fn AudioOutputs(comptime Sample: type) type {
    return struct {
        const Self = @This();

        channels: []const []Sample,
        frame_count: usize,

        pub fn init(channels: []const []Sample) !Self {
            const frame_count = if (channels.len == 0) 0 else channels[0].len;
            for (channels) |channel_samples| {
                if (channel_samples.len != frame_count) {
                    return error.MismatchedFrameCount;
                }
            }
            return .{
                .channels = channels,
                .frame_count = frame_count,
            };
        }

        pub fn channel(self: Self, index: usize) ?[]Sample {
            if (index >= self.channels.len) return null;
            return self.channels[index];
        }
    };
}

pub const ProcessAttachments = struct {
    parameter_changes: []const ParameterChange = &.{},
    events: []const Event = &.{},
    output_events: ?*EventWriter = null,
};

pub fn ProcessContext(comptime Sample: type) type {
    return struct {
        sample_rate: f64,
        inputs: AudioInputs(Sample),
        outputs: AudioOutputs(Sample),
        parameter_changes: ParameterChanges = .{},
        events: Events = .{},
        output_events: ?*EventWriter = null,

        pub fn init(sample_rate: f64, input_channels: []const []const Sample, output_channels: []const []Sample) !@This() {
            return .{
                .sample_rate = sample_rate,
                .inputs = try AudioInputs(Sample).init(input_channels),
                .outputs = try AudioOutputs(Sample).init(output_channels),
            };
        }

        pub fn initWith(
            sample_rate: f64,
            input_channels: []const []const Sample,
            output_channels: []const []Sample,
            attachments: ProcessAttachments,
        ) !@This() {
            var context = try @This().init(sample_rate, input_channels, output_channels);
            try context.setParameterChanges(attachments.parameter_changes);
            try context.setEvents(attachments.events);
            if (attachments.output_events) |writer| context.setOutputEvents(writer);
            return context;
        }

        pub fn setParameterChanges(self: *@This(), changes: []const ParameterChange) !void {
            self.parameter_changes = try ParameterChanges.init(changes, self.frameCount());
        }

        pub fn setEvents(self: *@This(), events: []const Event) !void {
            self.events = try Events.init(events, self.frameCount());
        }

        pub fn setOutputEvents(self: *@This(), writer: *EventWriter) void {
            self.output_events = writer;
        }

        pub fn frameCount(self: @This()) usize {
            return @min(self.inputs.frame_count, self.outputs.frame_count);
        }
    };
}

test "audio input view validates channel frame counts" {
    const left = [_]f32{ 0.1, 0.2 };
    const right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]const f32{ &left, &right };
    const inputs = try AudioInputs(f32).init(&channels);

    try std.testing.expectEqual(@as(usize, 2), inputs.channels.len);
    try std.testing.expectEqual(@as(usize, 2), inputs.frame_count);
    try std.testing.expectEqual(@as(f32, 0.3), inputs.channel(1).?[0]);
    try std.testing.expectEqual(@as(?[]const f32, null), inputs.channel(2));
}

test "audio output view rejects mismatched channel frame counts" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{0.3};
    const channels = [_][]f32{ &left, &right };

    try std.testing.expectError(error.MismatchedFrameCount, AudioOutputs(f32).init(&channels));
}

test "process context reports usable frame count" {
    const in_left = [_]f64{ 0.1, 0.2, 0.3 };
    const in_right = [_]f64{ 0.4, 0.5, 0.6 };
    var out_left = [_]f64{ 0.0, 0.0, 0.0 };
    var out_right = [_]f64{ 0.0, 0.0, 0.0 };
    const input_channels = [_][]const f64{ &in_left, &in_right };
    const output_channels = [_][]f64{ &out_left, &out_right };
    const context = try ProcessContext(f64).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
}

test "process context validates attached parameter changes and events" {
    const input = [_]f32{ 0.1, 0.2 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 1, .normalized = 0.5 },
    };
    const events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
    };
    var storage: [1]Event = undefined;
    var writer = EventWriter.init(&storage, input.len);
    const context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .parameter_changes = &changes,
        .events = &events,
        .output_events = &writer,
    });

    try std.testing.expectEqual(@as(f64, 0.5), context.parameter_changes.latest(1).?.normalized);
    try std.testing.expectEqual(@as(usize, 1), context.events.countKind(.note_on));
    try std.testing.expect(context.output_events != null);
}

test "process context rejects attached changes outside frame count" {
    const input = [_]f32{0.1};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const changes = [_]ParameterChange{
        .{ .id = 1, .sample_offset = 1, .normalized = 0.5 },
    };
    const events = [_]Event{
        Event.noteOn(1, 0, 60, 1.0),
    };
    var context = try ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);

    try std.testing.expectError(error.ParameterChangeOutsideBlock, context.setParameterChanges(&changes));
    try std.testing.expectError(error.EventOutsideBlock, context.setEvents(&events));
    try std.testing.expectError(error.ParameterChangeOutsideBlock, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .parameter_changes = &changes },
    ));
    try std.testing.expectError(error.EventOutsideBlock, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .events = &events },
    ));
}

test "parameter changes validate block offsets and normalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(usize, 3), view.items.len);
    try std.testing.expectEqual(@as(f64, 0.75), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalized(7));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalized(9));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latest(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.latestAtOrBefore(7, 3).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 2));
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalizedAtOrBefore(7, 3));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
}

test "parameter changes reject values outside the process block" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 4, .normalized = 0.25 },
    };

    try std.testing.expectError(error.ParameterChangeOutsideBlock, ParameterChanges.init(&changes, 4));
}

test "parameter changes reject denormalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 1.5 },
    };

    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&changes, 4));
}

test "events validate block offsets and count kinds" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 0.75),
        Event.midiCc(1, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.pitchBend(3, 0, 1.0),
        Event.aftertouch(3, 0, 60, 0.25),
        Event.noteExpressionValue(3, 42, 5, 0.5),
        Event.noteExpressionInt(3, 42, 5, 7),
        Event.noteExpressionText(3, 42, 5),
        Event.dataEvent(3, 1, &.{ 0x01, 0x02 }),
        Event.other(3),
    };
    const view = try Events.init(&items, 4);

    try std.testing.expectEqual(@as(usize, 10), view.items.len);
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_off));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.data));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.other));
    try std.testing.expect(view.hasKind(.note_on));
    try std.testing.expect(view.hasKind(.data));
}

test "events reject values outside the process block" {
    const items = [_]Event{
        Event.noteOn(4, 0, 60, 1.0),
    };

    try std.testing.expectError(error.EventOutsideBlock, Events.init(&items, 4));
}

test "event writer validates offsets and capacity" {
    var storage: [1]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try writer.append(Event.noteOn(0, 0, 60, 1.0));
    try std.testing.expectEqual(@as(usize, 1), writer.events().items.len);
    try std.testing.expectError(error.EventStorageFull, writer.append(Event.noteOff(1, 0, 60, 0.0)));

    var empty_storage: [1]Event = undefined;
    var empty_writer = EventWriter.init(&empty_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, empty_writer.append(Event.noteOn(4, 0, 60, 1.0)));
}

test "event writer appends event views atomically" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var storage: [2]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try writer.appendAll(try Events.init(&items, 4));
    try std.testing.expectEqual(@as(usize, 2), writer.events().items.len);
    try std.testing.expectEqual(EventKind.note_on, writer.events().items[0].kind);
    try std.testing.expectEqual(EventKind.note_off, writer.events().items[1].kind);

    var full_storage: [1]Event = undefined;
    var full_writer = EventWriter.init(&full_storage, 4);
    try std.testing.expectError(error.EventStorageFull, full_writer.appendAll(try Events.init(&items, 4)));
    try std.testing.expectEqual(@as(usize, 0), full_writer.events().items.len);

    const outside = [_]Event{Event.noteOn(4, 0, 60, 1.0)};
    var outside_storage: [1]Event = undefined;
    var outside_writer = EventWriter.init(&outside_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, outside_writer.appendAll(.{ .items = &outside }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.events().items.len);
}
