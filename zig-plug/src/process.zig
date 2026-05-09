const std = @import("std");

pub const ParameterChange = struct {
    id: u32,
    sample_offset: usize,
    normalized: f64,
};

pub const ParameterSegment = struct {
    start_offset: usize,
    end_offset: usize,
    normalized: f64,
};

pub const BlockSegment = struct {
    start_offset: usize,
    end_offset: usize,
};

pub const BlockSegmentIterator = struct {
    changes: ParameterChanges,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *BlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const end = self.changes.nextSampleOffset(start) orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const ProcessBlockSegmentIterator = struct {
    parameter_changes: ParameterChanges,
    events: Events,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *ProcessBlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const next_parameter_offset = self.parameter_changes.nextSampleOffset(start);
        const next_event_offset = self.events.nextSampleOffset(start);
        const end = if (next_parameter_offset) |parameter_offset|
            if (next_event_offset) |event_offset| @min(parameter_offset, event_offset) else parameter_offset
        else
            next_event_offset orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const ParameterSegmentIterator = struct {
    changes: ParameterChanges,
    id: u32,
    frame_count: usize,
    default: f64,
    next_start: usize = 0,

    pub fn next(self: *ParameterSegmentIterator) ?ParameterSegment {
        const segment = self.changes.segmentAt(self.id, self.next_start, self.frame_count, self.default) orelse return null;
        self.next_start = segment.end_offset;
        return segment;
    }
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
            if (item.id != id) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn first(self: ParameterChanges, id: u32) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.id != id) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
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
            if (item.id != id or item.sample_offset > sample_offset) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
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

    pub fn nextSampleOffsetForId(self: ParameterChanges, id: u32, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.id != id or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn segmentAt(self: ParameterChanges, id: u32, start_offset: usize, frame_count: usize, default: f64) ?ParameterSegment {
        if (start_offset >= frame_count) return null;
        const next_offset = self.nextSampleOffsetForId(id, start_offset) orelse frame_count;
        return .{
            .start_offset = start_offset,
            .end_offset = @min(next_offset, frame_count),
            .normalized = self.normalizedAtOrBeforeOr(id, start_offset, default),
        };
    }

    pub fn segments(self: ParameterChanges, id: u32, frame_count: usize, default: f64) ParameterSegmentIterator {
        return .{
            .changes = self,
            .id = id,
            .frame_count = frame_count,
            .default = default,
        };
    }

    pub fn blockSegments(self: ParameterChanges, frame_count: usize) BlockSegmentIterator {
        return .{
            .changes = self,
            .frame_count = frame_count,
        };
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

pub const EventKindIterator = struct {
    events: Events,
    kind: EventKind,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *EventKindIterator) ?Event {
        var result: ?Event = null;
        var result_index: usize = 0;
        for (self.events.items, 0..) |item, index| {
            if (item.kind != self.kind) continue;
            if (self.last_offset) |offset| {
                if (item.sample_offset < offset) continue;
                if (item.sample_offset == offset and index <= self.last_index) continue;
            }
            if (result == null or item.sample_offset < result.?.sample_offset or
                (item.sample_offset == result.?.sample_offset and index < result_index))
            {
                result = item;
                result_index = index;
            }
        }
        if (result) |item| {
            self.last_offset = item.sample_offset;
            self.last_index = result_index;
        }
        return result;
    }
};

pub const EventOffsetIterator = struct {
    events: Events,
    sample_offset: usize,
    next_index: usize = 0,

    pub fn next(self: *EventOffsetIterator) ?Event {
        while (self.next_index < self.events.items.len) : (self.next_index += 1) {
            const item = self.events.items[self.next_index];
            if (item.sample_offset == self.sample_offset) {
                self.next_index += 1;
                return item;
            }
        }
        return null;
    }
};

pub const EventBlockSegmentIterator = struct {
    events: Events,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *EventBlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const end = self.events.nextSampleOffset(start) orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
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

    pub fn validate(self: Event, frame_count: usize) !void {
        if (self.sample_offset >= frame_count) return error.EventOutsideBlock;
        switch (self.kind) {
            .note_on, .note_off => try validateUnitEventValue(self.velocity),
            .midi_cc, .aftertouch, .note_expression_value => try validateUnitEventValue(self.value),
            .pitch_bend => try validateBipolarEventValue(self.value),
            .note_expression_int, .note_expression_text, .data, .other => {},
        }
    }
};

fn validateUnitEventValue(value: f32) !void {
    if (std.math.isNan(value) or value < 0.0 or value > 1.0) return error.EventValueOutsideNormalizedRange;
}

fn validateBipolarEventValue(value: f32) !void {
    if (std.math.isNan(value) or value < -1.0 or value > 1.0) return error.EventValueOutsideNormalizedRange;
}

pub const Events = struct {
    items: []const Event = &.{},

    pub fn init(items: []const Event, frame_count: usize) !Events {
        for (items) |item| {
            try item.validate(frame_count);
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

    pub fn firstSampleOffsetForKind(self: Events, kind: EventKind) ?usize {
        const event = self.firstKind(kind) orelse return null;
        return event.sample_offset;
    }

    pub fn latestSampleOffsetForKind(self: Events, kind: EventKind) ?usize {
        const event = self.latestKind(kind) orelse return null;
        return event.sample_offset;
    }

    pub fn countKind(self: Events, kind: EventKind) usize {
        var count: usize = 0;
        for (self.items) |item| {
            if (item.kind == kind) count += 1;
        }
        return count;
    }

    pub fn firstKind(self: Events, kind: EventKind) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (item.kind != kind) continue;
            if (result == null or item.sample_offset < result.?.sample_offset) result = item;
        }
        return result;
    }

    pub fn latestKind(self: Events, kind: EventKind) ?Event {
        var result: ?Event = null;
        for (self.items) |item| {
            if (item.kind != kind) continue;
            if (result == null or item.sample_offset >= result.?.sample_offset) result = item;
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

    pub fn nextSampleOffsetForKind(self: Events, kind: EventKind, after_sample_offset: usize) ?usize {
        var result: ?usize = null;
        for (self.items) |item| {
            if (item.kind != kind or item.sample_offset <= after_sample_offset) continue;
            if (result == null or item.sample_offset < result.?) result = item.sample_offset;
        }
        return result;
    }

    pub fn ofKind(self: Events, kind: EventKind) EventKindIterator {
        return .{ .events = self, .kind = kind };
    }

    pub fn atOffset(self: Events, sample_offset: usize) EventOffsetIterator {
        return .{ .events = self, .sample_offset = sample_offset };
    }

    pub fn blockSegments(self: Events, frame_count: usize) EventBlockSegmentIterator {
        return .{
            .events = self,
            .frame_count = frame_count,
        };
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
        try event.validate(self.frame_count);
        if (self.count >= self.storage.len) return error.EventStorageFull;
        self.storage[self.count] = event;
        self.count += 1;
    }

    pub fn appendAll(self: *EventWriter, source: Events) !void {
        if (source.items.len > self.storage.len - self.count) return error.EventStorageFull;
        for (source.items) |event| {
            try event.validate(self.frame_count);
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

    pub fn firstSampleOffsetForKind(self: *const EventWriter, kind: EventKind) ?usize {
        return self.events().firstSampleOffsetForKind(kind);
    }

    pub fn latestSampleOffsetForKind(self: *const EventWriter, kind: EventKind) ?usize {
        return self.events().latestSampleOffsetForKind(kind);
    }

    pub fn countKind(self: *const EventWriter, kind: EventKind) usize {
        return self.events().countKind(kind);
    }

    pub fn firstKind(self: *const EventWriter, kind: EventKind) ?Event {
        return self.events().firstKind(kind);
    }

    pub fn latestKind(self: *const EventWriter, kind: EventKind) ?Event {
        return self.events().latestKind(kind);
    }

    pub fn hasKind(self: *const EventWriter, kind: EventKind) bool {
        return self.events().hasKind(kind);
    }

    pub fn nextSampleOffset(self: *const EventWriter, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffset(after_sample_offset);
    }

    pub fn nextSampleOffsetForKind(self: *const EventWriter, kind: EventKind, after_sample_offset: usize) ?usize {
        return self.events().nextSampleOffsetForKind(kind, after_sample_offset);
    }

    pub fn ofKind(self: *const EventWriter, kind: EventKind) EventKindIterator {
        return self.events().ofKind(kind);
    }

    pub fn atOffset(self: *const EventWriter, sample_offset: usize) EventOffsetIterator {
        return self.events().atOffset(sample_offset);
    }

    pub fn blockSegments(self: *const EventWriter) EventBlockSegmentIterator {
        return self.events().blockSegments(self.frame_count);
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
            if (sample_rate <= 0.0 or !std.math.isFinite(sample_rate)) return error.InvalidSampleRate;
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
            if (attachments.output_events) |writer| try context.setOutputEvents(writer);
            return context;
        }

        pub fn setParameterChanges(self: *@This(), changes: []const ParameterChange) !void {
            self.parameter_changes = try ParameterChanges.init(changes, self.frameCount());
        }

        pub fn setEvents(self: *@This(), events: []const Event) !void {
            self.events = try Events.init(events, self.frameCount());
        }

        pub fn setOutputEvents(self: *@This(), writer: *EventWriter) !void {
            if (writer.frame_count != self.frameCount()) return error.MismatchedFrameCount;
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

        pub fn nextParameterChangeOffsetForId(self: @This(), id: u32, after_sample_offset: usize) ?usize {
            return self.parameter_changes.nextSampleOffsetForId(id, after_sample_offset);
        }

        pub fn parameterSegmentAt(self: @This(), id: u32, start_offset: usize, default: f64) ?ParameterSegment {
            return self.parameter_changes.segmentAt(id, start_offset, self.frameCount(), default);
        }

        pub fn parameterSegments(self: @This(), id: u32, default: f64) ParameterSegmentIterator {
            return self.parameter_changes.segments(id, self.frameCount(), default);
        }

        pub fn parameterBlockSegments(self: @This()) BlockSegmentIterator {
            return self.parameter_changes.blockSegments(self.frameCount());
        }

        pub fn processBlockSegments(self: @This()) ProcessBlockSegmentIterator {
            return .{
                .parameter_changes = self.parameter_changes,
                .events = self.events,
                .frame_count = self.frameCount(),
            };
        }

        pub fn inputEvents(self: @This()) Events {
            return self.events;
        }

        pub fn inputEventsOfKind(self: @This(), kind: EventKind) EventKindIterator {
            return self.events.ofKind(kind);
        }

        pub fn inputEventsAtOffset(self: @This(), sample_offset: usize) EventOffsetIterator {
            return self.events.atOffset(sample_offset);
        }

        pub fn inputEventBlockSegments(self: @This()) EventBlockSegmentIterator {
            return self.events.blockSegments(self.frameCount());
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

        pub fn firstEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            return self.events.firstSampleOffsetForKind(kind);
        }

        pub fn latestEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            return self.events.latestSampleOffsetForKind(kind);
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

        pub fn nextEventOffsetForKind(self: @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.events.nextSampleOffsetForKind(kind, after_sample_offset);
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

        pub fn outputEventBlockSegments(self: @This()) EventBlockSegmentIterator {
            const writer = self.output_events orelse return (Events{}).blockSegments(self.frameCount());
            return writer.blockSegments();
        }

        pub fn outputEventsAtOffset(self: @This(), sample_offset: usize) EventOffsetIterator {
            return self.writtenOutputEvents().atOffset(sample_offset);
        }

        pub fn firstOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffset();
        }

        pub fn latestOutputEventOffset(self: @This()) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffset();
        }

        pub fn firstOutputEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            const writer = self.output_events orelse return null;
            return writer.firstSampleOffsetForKind(kind);
        }

        pub fn latestOutputEventOffsetForKind(self: @This(), kind: EventKind) ?usize {
            const writer = self.output_events orelse return null;
            return writer.latestSampleOffsetForKind(kind);
        }

        pub fn firstOutputEvent(self: @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().firstKind(kind);
        }

        pub fn latestOutputEvent(self: @This(), kind: EventKind) ?Event {
            return self.writtenOutputEvents().latestKind(kind);
        }

        pub fn hasOutputEvent(self: @This(), kind: EventKind) bool {
            return self.writtenOutputEvents().hasKind(kind);
        }

        pub fn countOutputEvents(self: @This(), kind: EventKind) usize {
            return self.writtenOutputEvents().countKind(kind);
        }

        pub fn nextOutputEventOffset(self: @This(), after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffset(after_sample_offset);
        }

        pub fn nextOutputEventOffsetForKind(self: @This(), kind: EventKind, after_sample_offset: usize) ?usize {
            return self.writtenOutputEvents().nextSampleOffsetForKind(kind, after_sample_offset);
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

test "process context rejects invalid sample rates" {
    const input = [_]f32{0.0};
    var output = [_]f32{0.0};
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};

    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(0.0, &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(-48_000.0, &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(std.math.inf(f64), &input_channels, &output_channels));
    try std.testing.expectError(error.InvalidSampleRate, ProcessContext(f32).init(std.math.nan(f64), &input_channels, &output_channels));
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
    try std.testing.expectEqual(@as(?usize, 1), context.nextParameterChangeOffsetForId(1, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextParameterChangeOffsetForId(2, 0));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.25 }, context.parameterSegmentAt(1, 0, 0.25).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 2, .normalized = 0.5 }, context.parameterSegmentAt(1, 1, 0.25).?);
    var parameter_segments = context.parameterSegments(1, 0.25);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.25 }, parameter_segments.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 2, .normalized = 0.5 }, parameter_segments.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), parameter_segments.next());
    var block_segments = context.parameterBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, block_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, block_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), block_segments.next());
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(usize, 1), context.inputEventCount());
    try std.testing.expect(!context.inputEventsEmpty());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffset());
    try std.testing.expectEqual(@as(?usize, 1), context.firstEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), context.firstEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), context.latestEventOffsetForKind(.note_off));
    try std.testing.expect(context.hasEvent(.note_on));
    try std.testing.expect(!context.hasEvent(.note_off));
    try std.testing.expectEqual(@as(usize, 1), context.countEvents(.note_on));
    try std.testing.expectEqual(@as(i16, 60), context.firstEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(i16, 60), context.latestEvent(.note_on).?.pitch);
    try std.testing.expectEqual(@as(?Event, null), context.firstEvent(.note_off));
    try std.testing.expectEqual(@as(?Event, null), context.latestEvent(.note_off));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextEventOffsetForKind(.note_on, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextEventOffsetForKind(.note_off, 0));
    var note_events = context.inputEventsOfKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), note_events.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), note_events.next());
    var offset_events = context.inputEventsAtOffset(1);
    try std.testing.expectEqual(EventKind.note_on, offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());
    var event_segments = context.inputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, event_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, event_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), event_segments.next());
    var process_segments = context.processBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, process_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, process_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), process_segments.next());
    try std.testing.expect(context.hasOutputEventWriter());
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

    var output_storage: [1]Event = undefined;
    var mismatched_writer = EventWriter.init(&output_storage, 2);
    try std.testing.expectError(error.MismatchedFrameCount, context.setOutputEvents(&mismatched_writer));
    try std.testing.expectError(error.MismatchedFrameCount, ProcessContext(f32).initWith(
        48_000.0,
        &input_channels,
        &output_channels,
        .{ .output_events = &mismatched_writer },
    ));
}

test "parameter changes validate block offsets and normalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 4);

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
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffsetForId(7, 0));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(7, 3));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(9, 0));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 3, .normalized = 0.25 }, view.segmentAt(7, 0, 4, 1.0).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 3, .end_offset = 4, .normalized = 0.75 }, view.segmentAt(7, 3, 4, 1.0).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 2, .normalized = 0.5 }, view.segmentAt(8, 0, 4, 0.5).?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), view.segmentAt(7, 4, 4, 1.0));
    try std.testing.expectEqual(@as(usize, 0), (ParameterChanges{}).changeCount());
    try std.testing.expect((ParameterChanges{}).isEmpty());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffset());
}

test "parameter changes query by sample offset without requiring sorted input" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);

    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 4));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedAtOrBefore(7, 5));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffsetForId(7, 1));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, view.segmentAt(7, 1, 8, 0.0).?);
}

test "parameter changes iterate stable automation segments without allocation" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.segments(7, 8, 0.0);

    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.0 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 5, .end_offset = 8, .normalized = 0.75 }, iterator.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), iterator.next());
}

test "parameter changes iterate block segments split at change offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 9, .sample_offset = 3, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.blockSegments(8);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());

    var empty = (ParameterChanges{}).blockSegments(4);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = view.blockSegments(0);
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
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

    try std.testing.expectEqual(@as(usize, 10), view.eventCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 3), view.firstSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, 0), view.latestSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), view.firstSampleOffsetForKind(.other));
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
    var offset_events = view.atOffset(3);
    try std.testing.expectEqual(EventKind.note_off, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.pitch_bend, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.aftertouch, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_value, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_int, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.note_expression_text, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.data, offset_events.next().?.kind);
    try std.testing.expectEqual(EventKind.other, offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), offset_events.next());
}

test "events iterate block segments split at event offsets" {
    const items = [_]Event{
        Event.noteOn(5, 0, 60, 1.0),
        Event.midiCc(1, 0, 1, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.pitchBend(5, 0, 0.25),
    };
    const view = try Events.init(&items, 8);
    var iterator = view.blockSegments(8);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());

    var empty = (Events{}).blockSegments(4);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = view.blockSegments(0);
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "process block segments split at parameter and event offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 2, .normalized = 0.25 },
    };
    const events = [_]Event{
        Event.noteOn(3, 0, 60, 1.0),
        Event.noteOff(5, 0, 60, 0.0),
    };
    const parameter_changes = try ParameterChanges.init(&changes, 8);
    const input_events = try Events.init(&events, 8);
    var iterator = ProcessBlockSegmentIterator{
        .parameter_changes = parameter_changes,
        .events = input_events,
        .frame_count = 8,
    };

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 2 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 2, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());

    var empty = ProcessBlockSegmentIterator{ .parameter_changes = .{}, .events = .{}, .frame_count = 4 };
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = ProcessBlockSegmentIterator{ .parameter_changes = parameter_changes, .events = input_events, .frame_count = 0 };
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "events query by sample offset without requiring sorted input" {
    const items = [_]Event{
        Event.noteOn(5, 0, 67, 0.5),
        Event.noteOff(3, 0, 60, 0.0),
        Event.noteOn(1, 0, 60, 1.0),
        Event.noteOn(5, 0, 72, 0.25),
    };
    const view = try Events.init(&items, 8);

    try std.testing.expectEqual(@as(usize, 1), view.firstKind(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 60), view.firstKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(usize, 5), view.latestKind(.note_on).?.sample_offset);
    try std.testing.expectEqual(@as(i16, 72), view.latestKind(.note_on).?.pitch);
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffsetForKind(.note_on, 1));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForKind(.note_off, 3));
    var note_ons = view.ofKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(i16, 67), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(i16, 72), note_ons.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), note_ons.next());
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

test "events reject invalid normalized values" {
    const too_loud_note = [_]Event{
        Event.noteOn(0, 0, 60, 1.5),
    };
    const nan_cc = [_]Event{
        Event.midiCc(0, 0, 1, std.math.nan(f32)),
    };
    const wide_bend = [_]Event{
        Event.pitchBend(0, 0, 1.5),
    };

    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&too_loud_note, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&nan_cc, 4));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, Events.init(&wide_bend, 4));
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
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    try std.testing.expectEqual(@as(?usize, 1), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffset());
    try std.testing.expect(writer.hasKind(.note_on));
    try std.testing.expect(!writer.hasKind(.note_off));
    try std.testing.expectEqual(@as(usize, 1), writer.countKind(.note_on));
    try std.testing.expectEqual(EventKind.note_on, writer.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_on, writer.latestKind(.note_on).?.kind);
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffset(1));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffsetForKind(.note_on, 1));
    var written_notes = writer.ofKind(.note_on);
    try std.testing.expectEqual(@as(i16, 60), written_notes.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_notes.next());
    try std.testing.expectEqual(@as(usize, 1), writer.capacity());
    try std.testing.expectEqual(@as(usize, 0), writer.remainingCapacity());
    try std.testing.expectError(error.EventStorageFull, writer.append(Event.noteOff(1, 0, 60, 0.0)));
    writer.clear();
    try std.testing.expect(writer.isEmpty());
    try std.testing.expect(!writer.isFull());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expectEqual(@as(usize, 0), writer.eventCount());
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, null), writer.latestSampleOffset());
    try std.testing.expect(!writer.hasKind(.note_on));
    try std.testing.expectEqual(@as(usize, 0), writer.countKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), writer.firstKind(.note_on));
    try std.testing.expectEqual(@as(?Event, null), writer.latestKind(.note_on));
    try std.testing.expectEqual(@as(?usize, null), writer.nextSampleOffset(0));
    try std.testing.expectEqual(@as(usize, 1), writer.remainingCapacity());

    var empty_storage: [1]Event = undefined;
    var empty_writer = EventWriter.init(&empty_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, empty_writer.append(Event.noteOn(4, 0, 60, 1.0)));
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, empty_writer.append(Event.noteOn(0, 0, 60, -0.25)));
}

test "event writer appends event views atomically" {
    const items = [_]Event{
        Event.noteOn(0, 0, 60, 1.0),
        Event.noteOff(1, 0, 60, 0.0),
    };
    var storage: [2]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try writer.appendAll(try Events.init(&items, 4));
    try std.testing.expectEqual(@as(usize, 2), writer.eventCount());
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffset());
    try std.testing.expectEqual(@as(?usize, 0), writer.firstSampleOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), writer.latestSampleOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), writer.firstSampleOffsetForKind(.midi_cc));
    try std.testing.expect(writer.hasKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), writer.countKind(.note_off));
    try std.testing.expectEqual(EventKind.note_on, writer.firstKind(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, writer.latestKind(.note_off).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), writer.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 1), writer.nextSampleOffsetForKind(.note_off, 0));
    var written_note_offs = writer.ofKind(.note_off);
    try std.testing.expectEqual(@as(i16, 60), written_note_offs.next().?.pitch);
    try std.testing.expectEqual(@as(?Event, null), written_note_offs.next());
    var written_offset_events = writer.atOffset(1);
    try std.testing.expectEqual(EventKind.note_off, written_offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), written_offset_events.next());
    var written_segments = writer.blockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, written_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 4 }, written_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), written_segments.next());
    try std.testing.expectEqual(EventKind.note_on, writer.events().items[0].kind);
    try std.testing.expectEqual(EventKind.note_off, writer.events().items[1].kind);

    var full_storage: [1]Event = undefined;
    var full_writer = EventWriter.init(&full_storage, 4);
    try std.testing.expectError(error.EventStorageFull, full_writer.appendAll(try Events.init(&items, 4)));
    try std.testing.expectEqual(@as(usize, 0), full_writer.eventCount());

    const outside = [_]Event{Event.noteOn(4, 0, 60, 1.0)};
    var outside_storage: [1]Event = undefined;
    var outside_writer = EventWriter.init(&outside_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, outside_writer.appendAll(.{ .items = &outside }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());

    const invalid = [_]Event{Event.midiCc(0, 0, 1, 2.0)};
    try std.testing.expectError(error.EventValueOutsideNormalizedRange, outside_writer.appendAll(.{ .items = &invalid }));
    try std.testing.expectEqual(@as(usize, 0), outside_writer.eventCount());
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
    try std.testing.expectEqual(@as(?usize, 0), context.firstOutputEventOffsetForKind(.note_on));
    try std.testing.expectEqual(@as(?usize, 1), context.latestOutputEventOffsetForKind(.note_off));
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffsetForKind(.midi_cc));
    var output_offset_events = context.outputEventsAtOffset(1);
    try std.testing.expectEqual(EventKind.note_off, output_offset_events.next().?.kind);
    try std.testing.expectEqual(@as(?Event, null), output_offset_events.next());
    var output_segments = context.outputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, output_segments.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 2 }, output_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), output_segments.next());
    try std.testing.expect(context.outputEventsFull());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventCount());
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEvent(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.firstOutputEvent(.note_off).?.kind);
    try std.testing.expect(context.hasOutputEvent(.note_on));
    try std.testing.expect(!context.hasOutputEvent(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(EventKind.note_on, context.firstOutputEvent(.note_on).?.kind);
    try std.testing.expectEqual(EventKind.note_off, context.latestOutputEvent(.note_off).?.kind);
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffset(1));
    try std.testing.expectEqual(@as(?usize, 1), context.nextOutputEventOffsetForKind(.note_off, 0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForKind(.note_on, 0));
    context.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), context.outputEventCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputEventRemainingCapacity());
    try std.testing.expectEqual(@as(?usize, null), context.firstOutputEventOffset());
    try std.testing.expectEqual(@as(?usize, null), context.latestOutputEventOffset());
    try std.testing.expect(!context.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 0), context.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(?Event, null), context.firstOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), context.latestOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), context.nextOutputEventOffsetForKind(.note_on, 0));
    var cleared_output_segments = context.outputEventBlockSegments();
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 2 }, cleared_output_segments.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), cleared_output_segments.next());
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
    try std.testing.expect(!no_writer.hasOutputEvent(.note_on));
    try std.testing.expectEqual(@as(usize, 0), no_writer.countOutputEvents(.note_on));
    try std.testing.expectEqual(@as(?Event, null), no_writer.firstOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?Event, null), no_writer.latestOutputEvent(.note_on));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffset(0));
    try std.testing.expectEqual(@as(?usize, null), no_writer.nextOutputEventOffsetForKind(.note_on, 0));
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvent(events[0]));
    try std.testing.expectError(error.OutputEventsUnavailable, no_writer.appendOutputEvents(try Events.init(&events, input.len)));
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
    no_writer.clearOutputEvents();
    try std.testing.expectEqual(@as(usize, 0), no_writer.outputEventCount());
}
