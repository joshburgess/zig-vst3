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

    pub fn latestAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (item.id == id and item.sample_offset <= sample_offset) result = item;
        }
        return result;
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

pub fn ProcessContext(comptime Sample: type) type {
    return struct {
        sample_rate: f64,
        inputs: AudioInputs(Sample),
        outputs: AudioOutputs(Sample),
        parameter_changes: ParameterChanges = .{},
        events: Events = .{},
        output_events: ?*EventWriter = null,

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
    const context = ProcessContext(f64){
        .sample_rate = 48_000.0,
        .inputs = try AudioInputs(f64).init(&input_channels),
        .outputs = try AudioOutputs(f64).init(&output_channels),
    };

    try std.testing.expectEqual(@as(usize, 3), context.frameCount());
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
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latest(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.latestAtOrBefore(7, 3).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOrBefore(8, 1));
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
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 0, .pitch = 60, .velocity = 0.75 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 1, .channel = 0, .control_number = 1, .value = 0.5 },
        .{ .kind = .note_off, .bus_index = 0, .sample_offset = 3, .channel = 0, .pitch = 60 },
    };
    const view = try Events.init(&items, 4);

    try std.testing.expectEqual(@as(usize, 3), view.items.len);
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_on));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.midi_cc));
    try std.testing.expectEqual(@as(usize, 1), view.countKind(.note_off));
    try std.testing.expectEqual(@as(usize, 0), view.countKind(.data));
}

test "events reject values outside the process block" {
    const items = [_]Event{
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 4 },
    };

    try std.testing.expectError(error.EventOutsideBlock, Events.init(&items, 4));
}

test "event writer validates offsets and capacity" {
    var storage: [1]Event = undefined;
    var writer = EventWriter.init(&storage, 4);

    try writer.append(.{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .pitch = 60 });
    try std.testing.expectEqual(@as(usize, 1), writer.events().items.len);
    try std.testing.expectError(error.EventStorageFull, writer.append(.{ .kind = .note_off, .bus_index = 0, .sample_offset = 1, .pitch = 60 }));

    var empty_storage: [1]Event = undefined;
    var empty_writer = EventWriter.init(&empty_storage, 4);
    try std.testing.expectError(error.EventOutsideBlock, empty_writer.append(.{ .kind = .note_on, .bus_index = 0, .sample_offset = 4 }));
}
