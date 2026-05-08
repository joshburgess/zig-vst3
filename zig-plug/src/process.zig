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

    pub fn changeCount(self: ParameterChanges) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: ParameterChanges) bool {
        return self.items.len == 0;
    }

    pub fn firstSampleOffset(self: ParameterChanges) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn latestSampleOffset(self: ParameterChanges) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset > result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn latest(self: ParameterChanges, id: u32) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.id == id) result = item;
        }
        return result;
    }

    pub fn first(self: ParameterChanges, id: u32) ?ParameterChange {
        for (self.items) |item| {
            if (item.id == id) return item;
        }
        return null;
    }

    pub fn count(self: ParameterChanges, id: u32) usize {
        var result: usize = 0;
        for (self.items) |item| {
            if (item.id == id) result += 1;
        }
        return result;
    }

    pub fn has(self: ParameterChanges, id: u32) bool {
        return self.first(id) != null;
    }

    pub fn latestNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.latest(id) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.first(id) orelse return null;
        return change.normalized;
    }

    pub fn latestNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.latestNormalized(id) orelse default;
    }

    pub fn firstNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.firstNormalized(id) orelse default;
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

    pub fn normalizedAtOrBeforeOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedAtOrBefore(id, sample_offset) orelse default;
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

    pub fn withBusIndex(self: Event, bus_index: i32) Event {
        var event = self;
        event.bus_index = bus_index;
        return event;
    }

    pub fn withControlNumber(self: Event, control_number: i16) Event {
        var event = self;
        event.control_number = control_number;
        return event;
    }

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

    pub fn eventCount(self: Events) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: Events) bool {
        return self.items.len == 0;
    }

    pub fn firstSampleOffset(self: Events) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn latestSampleOffset(self: Events) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (result == null or item.sample_offset > result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn countKind(self: Events, kind: EventKind) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.kind == kind) count += 1;
        }
        return count;
    }

    pub fn firstKind(self: Events, kind: EventKind) ?Event {
        for (self.items) |item| {
            if (item.kind == kind) return item;
        }
        return null;
    }

    pub fn latestKind(self: Events, kind: EventKind) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (item.kind == kind) result = item;
        }
        return result;
    }

    pub fn hasKind(self: Events, kind: EventKind) bool {
        return self.firstKind(kind) != null;
    }

    pub fn nextSampleOffset(self: Events, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
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

    pub fn clear(self: *EventWriter) void {
        self.count = 0;
    }

    pub fn eventCount(self: *const EventWriter) usize {
        return self.count;
    }

    pub fn isEmpty(self: *const EventWriter) bool {
        return self.count == 0;
    }

    pub fn isFull(self: *const EventWriter) bool {
        return self.count == self.storage.len;
    }

    pub fn capacity(self: *const EventWriter) usize {
        return self.storage.len;
    }

    pub fn remainingCapacity(self: *const EventWriter) usize {
        return self.storage.len - self.count;
    }

    pub fn firstSampleOffset(self: *const EventWriter) ?usize {
        return self.events().firstSampleOffset();
    }

    pub fn latestSampleOffset(self: *const EventWriter) ?usize {
        return self.events().latestSampleOffset();
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

        pub fn channelCount(self: Self) usize {
            return self.channels.len;
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

        pub fn channelCount(self: Self) usize {
            return self.channels.len;
        }

        pub fn fill(self: Self, value: Sample) void {
            for (self.channels) |channel_samples| {
                @memset(channel_samples, value);
            }
        }

        pub fn clear(self: Self) void {
            self.fill(0);
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

        pub fn parameterChanges(self: @This()) ParameterChanges {
            return self.parameter_changes;
        }

        pub fn parameterChangeCount(self: @This()) usize {
            return self.parameter_changes.changeCount();
        }

        pub fn parameterChangesEmpty(self: @This()) bool {
            return self.parameter_changes.isEmpty();
        }

        pub fn firstParameterChangeOffset(self: @This()) ?usize {
            return self.parameter_changes.firstSampleOffset();
        }

        pub fn latestParameterChangeOffset(self: @This()) ?usize {
            return self.parameter_changes.latestSampleOffset();
        }

        pub fn latestParameterChange(self: @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.latest(id);
        }

        pub fn firstParameterChange(self: @This(), id: u32) ?ParameterChange {
            return self.parameter_changes.first(id);
        }

        pub fn countParameterChanges(self: @This(), id: u32) usize {
            return self.parameter_changes.count(id);
        }

        pub fn hasParameterChange(self: @This(), id: u32) bool {
            return self.parameter_changes.has(id);
        }

        pub fn latestParameterNormalized(self: @This(), id: u32) ?f64 {
            return self.parameter_changes.latestNormalized(id);
        }

        pub fn firstParameterNormalized(self: @This(), id: u32) ?f64 {
            return self.parameter_changes.firstNormalized(id);
        }

        pub fn firstParameterNormalizedOr(self: @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.firstNormalizedOr(id, default);
        }

        pub fn latestParameterNormalizedOr(self: @This(), id: u32, default: f64) f64 {
            return self.parameter_changes.latestNormalizedOr(id, default);
        }

        pub fn latestParameterChangeAtOrBefore(self: @This(), id: u32, sample_offset: usize) ?ParameterChange {
            return self.parameter_changes.latestAtOrBefore(id, sample_offset);
        }

        pub fn latestParameterNormalizedAtOrBefore(self: @This(), id: u32, sample_offset: usize) ?f64 {
            return self.parameter_changes.latestNormalizedAtOrBefore(id, sample_offset);
        }

        pub fn parameterNormalizedAtOrBeforeOr(self: @This(), id: u32, sample_offset: usize, default: f64) f64 {
            return self.parameter_changes.normalizedAtOrBeforeOr(id, sample_offset, default);
        }

        pub fn nextParameterChangeOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffset(after_sample_offset);
        }

        pub fn inputEvents(self: @This()) Events {
            return self.events;
        }

        pub fn inputEventCount(self: @This()) usize {
            return self.events.eventCount();
        }

        pub fn inputEventsEmpty(self: @This()) bool {
            return self.events.isEmpty();
        }

        pub fn firstEventOffset(self: @This()) ?usize {
            return self.events.firstSampleOffset();
        }

        pub fn latestEventOffset(self: @This()) ?usize {
            return self.events.latestSampleOffset();
        }

        pub fn firstEvent(self: @This(), kind: EventKind) ?Event {
            return self.events.firstKind(kind);
        }

        pub fn latestEvent(self: @This(), kind: EventKind) ?Event {
            return self.events.latestKind(kind);
        }

        pub fn hasEvent(self: @This(), kind: EventKind) bool {
            return self.events.hasKind(kind);
        }

        pub fn countEvents(self: @This(), kind: EventKind) usize {
            return self.events.countKind(kind);
        }

        pub fn nextEventOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffset(after_sample_offset);
        }

        pub fn appendOutputEvent(self: *@This(), event: Event) !void {
            const writer = self.output_events orelse return error.OutputEventsUnavailable;
            try writer.append(event);
        }

        pub fn appendOutputEvents(self: *@This(), events: Events) !void {
            const writer = self.output_events orelse return error.OutputEventsUnavailable;
            try writer.appendAll(events);
        }

        pub fn writtenOutputEvents(self: @This()) Events {
            const writer = self.output_events orelse return .{};
            return writer.events();
        }

        pub fn firstOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffset();
        }

        pub fn latestOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffset();
        }

        pub fn clearOutputEvents(self: @This()) void {
            const writer = self.output_events orelse return;
            writer.clear();
        }

        pub fn hasOutputEventWriter(self: @This()) bool {
            return self.output_events != null;
        }

        pub fn outputEventCount(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.eventCount();
        }

        pub fn outputEventCapacity(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.capacity();
        }

        pub fn outputEventRemainingCapacity(self: @This()) usize {
            const writer = self.output_events orelse return 0;
            return writer.remainingCapacity();
        }

        pub fn outputEventsEmpty(self: @This()) bool {
            const writer = self.output_events orelse return true;
            return writer.isEmpty();
        }

        pub fn outputEventsFull(self: @This()) bool {
            const writer = self.output_events orelse return true;
            return writer.isFull();
        }

        pub fn fillOutputs(self: @This(), value: Sample) void {
            self.outputs.fill(value);
        }

        pub fn clearOutputs(self: @This()) void {
            self.outputs.clear();
        }

        pub fn inputChannel(self: @This(), index: usize) ?[]const Sample {
            return self.inputs.channel(index);
        }

        pub fn outputChannel(self: @This(), index: usize) ?[]Sample {
            return self.outputs.channel(index);
        }

        pub fn inputChannelCount(self: @This()) usize {
            return self.inputs.channelCount();
        }

        pub fn outputChannelCount(self: @This()) usize {
            return self.outputs.channelCount();
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
    try std.testing.expectEqual(@as(usize, 2), inputs.channelCount());
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

test "audio output view fills and clears channels" {
    var left = [_]f32{ 0.1, 0.2 };
    var right = [_]f32{ 0.3, 0.4 };
    const channels = [_][]f32{ &left, &right };
    const outputs = try AudioOutputs(f32).init(&channels);

    outputs.fill(0.5);
    try std.testing.expectEqual(@as(f32, 0.5), left[0]);
    try std.testing.expectEqual(@as(f32, 0.5), left[1]);
    try std.testing.expectEqual(@as(f32, 0.5), right[0]);
    try std.testing.expectEqual(@as(f32, 0.5), right[1]);

    outputs.clear();
    try std.testing.expectEqual(@as(f32, 0.0), left[0]);
    try std.testing.expectEqual(@as(f32, 0.0), left[1]);
    try std.testing.expectEqual(@as(f32, 0.0), right[0]);
    try std.testing.expectEqual(@as(f32, 0.0), right[1]);
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
    try std.testing.expectEqual(@as(usize, 2), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputChannelCount());
    try std.testing.expectEqual(@as(f64, 0.4), context.inputChannel(1).?[0]);
    try std.testing.expectEqual(@as(?[]const f64, null), context.inputChannel(2));
    try std.testing.expectEqual(@as(f64, 0.0), context.outputChannel(1).?[0]);
    try std.testing.expectEqual(@as(?[]f64, null), context.outputChannel(2));

    context.fillOutputs(0.5);
    try std.testing.expectEqual(@as(f64, 0.5), out_left[0]);
    try std.testing.expectEqual(@as(f64, 0.5), out_right[2]);

    context.clearOutputs();
    try std.testing.expectEqual(@as(f64, 0.0), out_left[0]);
    try std.testing.expectEqual(@as(f64, 0.0), out_right[2]);
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

    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(usize, 1), context.parameterChanges().items.len);
    try std.testing.expectEqual(@as(usize, 1), context.parameterChangeCount());
    try std.testing.expect(!context.parameterChangesEmpty());
    try std.testing.expectEqual(@as(?usize, 1), context.firstParameterChangeOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestParameterChangeOffset());
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterChange(1).?.normalized);
    try std.testing.expectEqual(@as(usize, 1), context.countParameterChanges(1));
    try std.testing.expect(context.hasParameterChange(1));
    try std.testing.expect(!context.hasParameterChange(2));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalized(1));
    try std.testing.expectEqual(@as(?f64, 0.5), context.firstParameterNormalized(1));
    try std.testing.expectEqual(@as(f64, 0.5), context.firstParameterNormalizedOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.firstParameterNormalizedOr(2, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterNormalizedOr(1, 0.0));
    try std.testing.expectEqual(@as(f64, 0.25), context.latestParameterNormalizedOr(2, 0.25));
    try std.testing.expectEqual(@as(f64, 0.5), context.latestParameterChangeAtOrBefore(1, 1).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), context.latestParameterChangeAtOrBefore(1, 0));
    try std.testing.expectEqual(@as(?f64, 0.5), context.latestParameterNormalizedAtOrBefore(1, 1));
    try std.testing.expectEqual(@as(?f64, null), context.latestParameterNormalizedAtOrBefore(1, 0));
    try std.testing.expectEqual(@as(f64, 0.5), context.parameterNormalizedAtOrBeforeOr(1, 1, 0.0));
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextParameterChangeOffset(1));
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try std.testing.expect(!context.inputEventsEmpty());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffset());
    try std.testing.expectEqual(@as(usize, 1), context.inputEvents().items.len);
    try std.testing.expect(context.hasEvent(.note_on));
    try std.testing.expect(!context.hasEvent(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(i16, 60), context.firstEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEvent(.note_off));
    try std.testing.expectEqual(@as(?Event, null), context.latestEvent(.note_off));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(1));
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
    try std.testing.expectEqual(@as(usize, 3), view.changeCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expect(view.has(7));
    try std.testing.expect(!view.has(9));
    try std.testing.expectEqual(@as(usize, 2), view.count(7));
    try std.testing.expectEqual(@as(usize, 1), view.count(8));
    try std.testing.expectEqual(@as(usize, 0), view.count(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(f64, 0.75), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.75), view.latestNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalized(9));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalized(9));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latest(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.latestAtOrBefore(7, 3).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.normalizedAtOrBeforeOr(7, 2, 0.0));
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalizedAtOrBefore(7, 3));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(f64, 0.5), view.normalizedAtOrBeforeOr(8, 1, 0.5));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(usize, 0), (ParameterChanges{}).changeCount());
    try std.testing.expect((ParameterChanges{}).isEmpty());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffset());
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
    try std.testing.expectEqual(@as(usize, 10), view.eventCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_off));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.data));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.other));
    try std.testing.expect(view.hasKind(.note_on));
    try std.testing.expectEqual(@as(i16, 60), view.firstKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(usize, 0), view.latestKind(.note_on).?.sample_offset);
    try std.testing.expect(view.hasKind(.data));
    try std.testing.expectEqual(@as(usize, 0), (Events{}).eventCount());
    try std.testing.expect((Events{}).isEmpty());
    try std.testing.expectEqual(@as(?usize, null), (Events{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), (Events{}).latestSampleOffset());
    try std.testing.expectEqual(@as(?Event, null), (Events{}).firstKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), (Events{}).latestKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
}

test "event constructors can target non-main buses" {
    const event = Event.noteOn(1, 0, 60, 0.75).withBusIndex(2);

    try std.testing.expectEqual(EventKind.note_on, event.kind);
    try std.testing.expectEqual(@as(i32, 2), event.bus_index);
    try std.testing.expectEqual(@as(usize, 1), event.sample_offset);
    try std.testing.expectEqual(@as(i16, 60), event.pitch);
}

test "event constructors can keep legacy MIDI controller numbers" {
    const event = Event.pitchBend(3, 1, 0.25).withControlNumber(129);

    try std.testing.expectEqual(EventKind.pitch_bend, event.kind);
    try std.testing.expectEqual(@as(i16, 129), event.control_number);
    try std.testing.expectEqual(@as(usize, 3), event.sample_offset);
    try std.testing.expectEqual(@as(i16, 1), event.channel);
    try std.testing.expectEqual(@as(f32, 0.25), event.value);
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

    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try writer.append(Event.noteOn(0, 0, 60, 1.0));
    try std.testing.expect(!writer.isEmpty());
    try std.testing.expect(writer.isFull());
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    try std.testing.expectEqual(@as(usize, 1), writer.events().items.len);
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffset());
    try std.testing.expectEqual(@as(usize, 1), writer.capacity());
    try std.testing.expectEqual(@as(usize, 0), writer.remainingCapacity());
    try std.testing.expectError(error.EventStorageFull, writer.append(Event.noteOff(1, 0, 60, 0.0)));
    writer.clear();
    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expectEqual(@as(usize, 0), writer.events().items.len);
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), writer.latestSampleOffset());
    try std.testing.expectEqual(@as(usize, 1), writer.remainingCapacity());

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
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffset());
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

test "process context exposes output event helpers" {
    const input = [_]f32{ 0.0, 0.0 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    const events = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var storage: [2]Event = undefined;
    var writer = EventWriter.init(&storage, input.len);
    var context = try ProcessContext(f32).initWith(48_000.0, &input_channels, &output_channels, .{
        .output_events = &writer,
    });

    try std.testing.expect(context.hasOutputEventWriter());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expect(context.outputEventsEmpty());
    try std.testing.expect(!context.outputEventsFull());

    try context.appendOutputEvent(events[0]);
    try std.testing.expectEqual(@as(usize, 1), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 1), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 0), context.latestOutputEventOffset());
    try std.testing.expect(!context.outputEventsEmpty());
    try context.appendOutputEvents(try Events.init(events[1..], input.len));

    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffset());
    try std.testing.expect(context.outputEventsFull());
    try std.testing.expectEqual(@as(usize, 2), context.writtenOutputEvents().items.len);
    try std.testing.expectEqual(EventKind.note_on, context.writtenOutputEvents().items[0].kind);
    try std.testing.expectEqual(EventKind.note_off, context.writtenOutputEvents().items[1].kind);
    context.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffset());
    try std.testing.expect(context.outputEventsEmpty());

    var no_writer = try ProcessContext(f32).init(48_000.0, &input_channels, &output_channels);
    try std.testing.expect(!no_writer.hasOutputEventWriter());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCapacity());
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventRemainingCapacity());
    try std.testing.expect(no_writer.outputEventsEmpty());
    try std.testing.expect(no_writer.outputEventsFull());
    try std.testing.expectEqual(@as(?usize, null), no_writer.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), no_writer.latestOutputEventOffset());
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvent(events[0]));
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvents(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(usize, 0), no_writer.writtenOutputEvents().items.len);
    no_writer.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
}
