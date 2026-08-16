const std = @import("std");
const events = @import("events.zig");

pub const MessageKind = enum {
    note_off,
    note_on,
    polyphonic_key_pressure,
    control_change,
    program_change,
    channel_pressure,
    pitch_bend,
};

pub const Message = struct {
    storage: [3]u8,
    length: u2,

    pub fn parse(message_bytes: []const u8) !Message {
        if (message_bytes.len < 2 or message_bytes.len > 3) return error.InvalidMidiMessageLength;

        const parsed_kind = kindFromStatus(message_bytes[0]) orelse return error.UnsupportedMidiStatus;
        const required_length: usize = switch (parsed_kind) {
            .program_change, .channel_pressure => 2,
            else => 3,
        };
        if (message_bytes.len != required_length) return error.InvalidMidiMessageLength;

        for (message_bytes[1..]) |data_byte| {
            try validateDataByte(data_byte);
        }

        var message = Message{
            .storage = .{ 0, 0, 0 },
            .length = @intCast(required_length),
        };
        @memcpy(message.storage[0..required_length], message_bytes);
        return message;
    }

    pub fn noteOff(channel_index: u8, note: u8, velocity: u8) !Message {
        return threeByte(0x80, channel_index, note, velocity);
    }

    pub fn noteOn(channel_index: u8, note: u8, velocity: u8) !Message {
        return threeByte(0x90, channel_index, note, velocity);
    }

    pub fn polyphonicKeyPressure(channel_index: u8, note: u8, pressure: u8) !Message {
        return threeByte(0xA0, channel_index, note, pressure);
    }

    pub fn controlChange(channel_index: u8, controller: u8, value: u8) !Message {
        return threeByte(0xB0, channel_index, controller, value);
    }

    pub fn programChange(channel_index: u8, program: u8) !Message {
        return twoByte(0xC0, channel_index, program);
    }

    pub fn channelPressure(channel_index: u8, pressure: u8) !Message {
        return twoByte(0xD0, channel_index, pressure);
    }

    pub fn pitchBend(channel_index: u8, value: u14) !Message {
        return threeByte(
            0xE0,
            channel_index,
            @intCast(value & 0x7F),
            @intCast(value >> 7),
        );
    }

    pub fn fromEvent(event: events.Event) !?Message {
        return switch (event.kind) {
            .note_off => try Message.noteOff(
                try eventChannel(event),
                try eventDataByte(event.pitch),
                try dataByteFromNormalized(event.velocity),
            ),
            .note_on => try Message.noteOn(
                try eventChannel(event),
                try eventDataByte(event.pitch),
                try dataByteFromNormalized(event.velocity),
            ),
            .midi_cc => try Message.controlChange(
                try eventChannel(event),
                try eventDataByte(event.control_number),
                try dataByteFromNormalized(event.value),
            ),
            .pitch_bend => try Message.pitchBend(
                try eventChannel(event),
                try pitchBendFromNormalized(event.value),
            ),
            .aftertouch => try Message.polyphonicKeyPressure(
                try eventChannel(event),
                try eventDataByte(event.pitch),
                try dataByteFromNormalized(event.value),
            ),
            .note_expression_value,
            .note_expression_int,
            .note_expression_text,
            .data,
            .other,
            => null,
        };
    }

    pub fn valid(self: Message) bool {
        const message_kind = kindFromStatus(self.storage[0]) orelse return false;
        const required_length: u2 = switch (message_kind) {
            .program_change, .channel_pressure => 2,
            else => 3,
        };
        if (self.length != required_length) return false;
        for (self.storage[1..self.length]) |data_byte| {
            if (data_byte > 127) return false;
        }
        return true;
    }

    pub fn kind(self: Message) ?MessageKind {
        if (!self.valid()) return null;
        return kindFromStatus(self.storage[0]);
    }

    pub fn channel(self: Message) ?u8 {
        if (!self.valid()) return null;
        return self.storage[0] & 0x0F;
    }

    pub fn bytes(self: *const Message) []const u8 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.length];
    }

    pub fn data1(self: Message) ?u8 {
        if (!self.valid()) return null;
        return self.storage[1];
    }

    pub fn data2(self: Message) ?u8 {
        if (!self.valid() or self.length != 3) return null;
        return self.storage[2];
    }

    pub fn pitchBendValue(self: Message) ?u14 {
        if (self.kind() != .pitch_bend) return null;
        return @as(u14, self.storage[1]) | (@as(u14, self.storage[2]) << 7);
    }

    pub fn toEvent(self: Message, sample_offset: usize, bus_index: i32) ?events.Event {
        const message_kind = self.kind() orelse return null;
        const channel_index = self.channel() orelse return null;
        const event = switch (message_kind) {
            .note_off => events.Event.noteOff(
                sample_offset,
                channel_index,
                self.storage[1],
                normalized7(@intCast(self.storage[2])),
            ),
            .note_on => if (self.storage[2] == 0)
                events.Event.noteOff(sample_offset, channel_index, self.storage[1], 0.0)
            else
                events.Event.noteOn(
                    sample_offset,
                    channel_index,
                    self.storage[1],
                    normalized7(@intCast(self.storage[2])),
                ),
            .polyphonic_key_pressure => events.Event.aftertouch(
                sample_offset,
                channel_index,
                self.storage[1],
                normalized7(@intCast(self.storage[2])),
            ),
            .control_change => events.Event.midiCc(
                sample_offset,
                channel_index,
                self.storage[1],
                normalized7(@intCast(self.storage[2])),
            ),
            .pitch_bend => events.Event.pitchBend(
                sample_offset,
                channel_index,
                normalizedPitchBend(self.pitchBendValue() orelse return null),
            ),
            .program_change, .channel_pressure => return null,
        };
        return event.withBusIndex(bus_index);
    }
};

pub const StreamDecoder = struct {
    running_status: ?u8 = null,
    storage: [3]u8 = .{ 0, 0, 0 },
    length: u2 = 0,

    pub fn reset(self: *StreamDecoder) void {
        self.* = .{};
    }

    pub fn valid(self: StreamDecoder) bool {
        const status = self.running_status orelse return self.length == 0;
        const message_kind = kindFromStatus(status) orelse return false;
        const required_length: u2 = messageLength(message_kind);
        if (self.length == 0 or self.length >= required_length) return false;
        if (self.storage[0] != status) return false;
        for (self.storage[1..self.length]) |data_byte| {
            if (data_byte > 127) return false;
        }
        return true;
    }

    pub fn push(self: *StreamDecoder, byte: u8) !?Message {
        if (!self.valid()) {
            self.reset();
            return error.InvalidMidiDecoderState;
        }

        if (byte >= 0xF8) return null;

        if ((byte & 0x80) != 0) {
            _ = kindFromStatus(byte) orelse {
                self.reset();
                return error.UnsupportedMidiStatus;
            };
            self.running_status = byte;
            self.storage = .{ byte, 0, 0 };
            self.length = 1;
            return null;
        }

        const status = self.running_status orelse return error.MissingRunningStatus;
        const message_kind = kindFromStatus(status) orelse {
            self.reset();
            return error.InvalidMidiDecoderState;
        };
        const required_length = messageLength(message_kind);
        self.storage[self.length] = byte;
        self.length += 1;
        if (self.length != required_length) return null;

        const message = try Message.parse(self.storage[0..required_length]);
        self.storage = .{ status, 0, 0 };
        self.length = 1;
        return message;
    }
};

pub fn normalized7(value: u7) f32 {
    return @as(f32, @floatFromInt(value)) / 127.0;
}

pub fn normalizedPitchBend(value: u14) f32 {
    if (value < 8192) {
        return (@as(f32, @floatFromInt(value)) - 8192.0) / 8192.0;
    }
    return (@as(f32, @floatFromInt(value)) - 8192.0) / 8191.0;
}

pub fn dataByteFromNormalized(value: f32) !u7 {
    if (!std.math.isFinite(value) or value < 0.0 or value > 1.0) {
        return error.NormalizedValueOutsideRange;
    }
    return @intFromFloat(@round(value * 127.0));
}

pub fn pitchBendFromNormalized(value: f32) !u14 {
    if (!std.math.isFinite(value) or value < -1.0 or value > 1.0) {
        return error.NormalizedValueOutsideRange;
    }
    const scaled = if (value < 0.0)
        value * 8192.0 + 8192.0
    else
        value * 8191.0 + 8192.0;
    return @intFromFloat(@round(scaled));
}

fn twoByte(status: u8, channel: u8, data: u8) !Message {
    try validateChannel(channel);
    try validateDataByte(data);
    return .{
        .storage = .{ status | channel, data, 0 },
        .length = 2,
    };
}

fn threeByte(status: u8, channel: u8, data1_value: u8, data2_value: u8) !Message {
    try validateChannel(channel);
    try validateDataByte(data1_value);
    try validateDataByte(data2_value);
    return .{
        .storage = .{ status | channel, data1_value, data2_value },
        .length = 3,
    };
}

fn validateChannel(channel: u8) !void {
    if (channel > 15) return error.InvalidMidiChannel;
}

fn validateDataByte(value: u8) !void {
    if (value > 127) return error.InvalidMidiDataByte;
}

fn eventChannel(event: events.Event) !u8 {
    if (!event.hasChannel() or event.channel < 0 or event.channel > 15) {
        return error.InvalidMidiChannel;
    }
    return @intCast(event.channel);
}

fn eventDataByte(value: i16) !u7 {
    if (value < 0 or value > 127) return error.InvalidMidiDataByte;
    return @intCast(value);
}

fn kindFromStatus(status: u8) ?MessageKind {
    return switch (status & 0xF0) {
        0x80 => .note_off,
        0x90 => .note_on,
        0xA0 => .polyphonic_key_pressure,
        0xB0 => .control_change,
        0xC0 => .program_change,
        0xD0 => .channel_pressure,
        0xE0 => .pitch_bend,
        else => null,
    };
}

fn messageLength(kind: MessageKind) u2 {
    return switch (kind) {
        .program_change, .channel_pressure => 2,
        else => 3,
    };
}

test "channel voice messages generate and parse exact MIDI bytes" {
    const cases = [_]struct {
        message: Message,
        kind: MessageKind,
        expected: []const u8,
    }{
        .{ .message = try Message.noteOff(2, 60, 64), .kind = .note_off, .expected = &.{ 0x82, 60, 64 } },
        .{ .message = try Message.noteOn(3, 61, 100), .kind = .note_on, .expected = &.{ 0x93, 61, 100 } },
        .{ .message = try Message.polyphonicKeyPressure(4, 62, 80), .kind = .polyphonic_key_pressure, .expected = &.{ 0xA4, 62, 80 } },
        .{ .message = try Message.controlChange(5, 74, 99), .kind = .control_change, .expected = &.{ 0xB5, 74, 99 } },
        .{ .message = try Message.programChange(6, 12), .kind = .program_change, .expected = &.{ 0xC6, 12 } },
        .{ .message = try Message.channelPressure(7, 45), .kind = .channel_pressure, .expected = &.{ 0xD7, 45 } },
        .{ .message = try Message.pitchBend(8, 0x2345), .kind = .pitch_bend, .expected = &.{ 0xE8, 0x45, 0x46 } },
    };

    for (cases) |case| {
        try std.testing.expectEqualSlices(u8, case.expected, case.message.bytes());
        try std.testing.expectEqual(case.kind, case.message.kind().?);
        const parsed = try Message.parse(case.expected);
        try std.testing.expectEqualSlices(u8, case.expected, parsed.bytes());
    }
}

test "parser rejects system, running-status, malformed, and out-of-range messages" {
    try std.testing.expectError(error.InvalidMidiMessageLength, Message.parse(&.{0x90}));
    try std.testing.expectError(error.InvalidMidiMessageLength, Message.parse(&.{ 0x90, 60 }));
    try std.testing.expectError(error.InvalidMidiMessageLength, Message.parse(&.{ 0xC0, 1, 2 }));
    try std.testing.expectError(error.UnsupportedMidiStatus, Message.parse(&.{ 0xF0, 0 }));
    try std.testing.expectError(error.UnsupportedMidiStatus, Message.parse(&.{ 60, 100 }));
    try std.testing.expectError(error.InvalidMidiDataByte, Message.parse(&.{ 0x90, 128, 1 }));
    try std.testing.expectError(error.InvalidMidiChannel, Message.noteOn(16, 60, 100));
    try std.testing.expectError(error.InvalidMidiDataByte, Message.controlChange(0, 74, 255));
}

test "directly malformed message state fails closed" {
    const invalid_status = Message{ .storage = .{ 0xF0, 0, 0 }, .length = 2 };
    try std.testing.expect(!invalid_status.valid());
    try std.testing.expectEqual(@as(?MessageKind, null), invalid_status.kind());
    try std.testing.expectEqual(@as(?u8, null), invalid_status.channel());
    try std.testing.expectEqual(@as(usize, 0), invalid_status.bytes().len);
    try std.testing.expectEqual(@as(?events.Event, null), invalid_status.toEvent(0, 0));

    const invalid_length = Message{ .storage = .{ 0x90, 60, 100 }, .length = 2 };
    try std.testing.expect(!invalid_length.valid());
    try std.testing.expectEqual(@as(?u8, null), invalid_length.data1());
    try std.testing.expectEqual(@as(?u8, null), invalid_length.data2());

    const invalid_data = Message{ .storage = .{ 0x90, 128, 100 }, .length = 3 };
    try std.testing.expect(!invalid_data.valid());
    try std.testing.expectEqual(@as(usize, 0), invalid_data.bytes().len);
}

test "normalization preserves MIDI endpoints and pitch-bend center" {
    try std.testing.expectEqual(@as(f32, 0.0), normalized7(0));
    try std.testing.expectEqual(@as(f32, 1.0), normalized7(127));
    try std.testing.expectEqual(@as(f32, -1.0), normalizedPitchBend(0));
    try std.testing.expectEqual(@as(f32, 0.0), normalizedPitchBend(8192));
    try std.testing.expectEqual(@as(f32, 1.0), normalizedPitchBend(16383));

    try std.testing.expectEqual(@as(u7, 0), try dataByteFromNormalized(0.0));
    try std.testing.expectEqual(@as(u7, 127), try dataByteFromNormalized(1.0));
    try std.testing.expectEqual(@as(u14, 0), try pitchBendFromNormalized(-1.0));
    try std.testing.expectEqual(@as(u14, 8192), try pitchBendFromNormalized(0.0));
    try std.testing.expectEqual(@as(u14, 16383), try pitchBendFromNormalized(1.0));
    try std.testing.expectError(error.NormalizedValueOutsideRange, dataByteFromNormalized(std.math.nan(f32)));
    try std.testing.expectError(error.NormalizedValueOutsideRange, pitchBendFromNormalized(1.01));
}

test "representable messages convert to typed process events" {
    const note = (try Message.noteOn(3, 64, 127)).toEvent(12, 2).?;
    try std.testing.expectEqual(events.EventKind.note_on, note.kind);
    try std.testing.expectEqual(@as(i32, 2), note.bus_index);
    try std.testing.expectEqual(@as(usize, 12), note.sample_offset);
    try std.testing.expectEqual(@as(i16, 3), note.channel);
    try std.testing.expectEqual(@as(i16, 64), note.pitch);
    try std.testing.expectEqual(@as(f32, 1.0), note.velocity);

    const zero_velocity = (try Message.noteOn(0, 60, 0)).toEvent(0, 0).?;
    try std.testing.expectEqual(events.EventKind.note_off, zero_velocity.kind);

    const pressure = (try Message.polyphonicKeyPressure(1, 72, 64)).toEvent(4, 0).?;
    try std.testing.expectEqual(events.EventKind.aftertouch, pressure.kind);
    try std.testing.expectApproxEqAbs(@as(f32, 64.0 / 127.0), pressure.value, 0.000001);

    const control = (try Message.controlChange(2, 74, 32)).toEvent(5, 1).?;
    try std.testing.expectEqual(events.EventKind.midi_cc, control.kind);
    try std.testing.expectEqual(@as(i16, 74), control.control_number);

    const bend = (try Message.pitchBend(4, 8192)).toEvent(6, 1).?;
    try std.testing.expectEqual(events.EventKind.pitch_bend, bend.kind);
    try std.testing.expectEqual(@as(f32, 0.0), bend.value);

    try std.testing.expect((try Message.programChange(0, 10)).toEvent(0, 0) == null);
    try std.testing.expect((try Message.channelPressure(0, 10)).toEvent(0, 0) == null);
}

test "typed process events convert to MIDI messages" {
    const cases = [_]struct {
        event: events.Event,
        expected: []const u8,
    }{
        .{ .event = events.Event.noteOff(0, 1, 60, 0.5), .expected = &.{ 0x81, 60, 64 } },
        .{ .event = events.Event.noteOn(0, 2, 61, 1.0), .expected = &.{ 0x92, 61, 127 } },
        .{ .event = events.Event.aftertouch(0, 3, 62, 0.25), .expected = &.{ 0xA3, 62, 32 } },
        .{ .event = events.Event.midiCc(0, 4, 74, 0.75), .expected = &.{ 0xB4, 74, 95 } },
        .{ .event = events.Event.pitchBend(0, 5, 0.0), .expected = &.{ 0xE5, 0, 64 } },
    };

    for (cases) |case| {
        const message = (try Message.fromEvent(case.event)).?;
        try std.testing.expectEqualSlices(u8, case.expected, message.bytes());
    }

    try std.testing.expect((try Message.fromEvent(events.Event.other(0))) == null);
    try std.testing.expectError(
        error.InvalidMidiChannel,
        Message.fromEvent(events.Event.noteOn(0, 16, 60, 1.0)),
    );
    try std.testing.expectError(
        error.NormalizedValueOutsideRange,
        Message.fromEvent(events.Event.noteOn(0, 0, 60, std.math.nan(f32))),
    );
}

test "stream decoder handles complete messages and running status" {
    var decoder = StreamDecoder{};
    const bytes = [_]u8{
        0x92, 60,   100,
        61,   0,    0xB2,
        74,   64,   75,
        127,  0xC2, 10,
        11,
    };
    const expected = [_][]const u8{
        &.{ 0x92, 60, 100 },
        &.{ 0x92, 61, 0 },
        &.{ 0xB2, 74, 64 },
        &.{ 0xB2, 75, 127 },
        &.{ 0xC2, 10 },
        &.{ 0xC2, 11 },
    };

    var decoded_count: usize = 0;
    for (bytes) |byte| {
        if (try decoder.push(byte)) |message| {
            try std.testing.expectEqualSlices(u8, expected[decoded_count], message.bytes());
            decoded_count += 1;
        }
    }
    try std.testing.expectEqual(expected.len, decoded_count);
    try std.testing.expect(decoder.valid());
}

test "stream decoder preserves running status across realtime bytes" {
    var decoder = StreamDecoder{};
    try std.testing.expect((try decoder.push(0x90)) == null);
    try std.testing.expect((try decoder.push(60)) == null);
    try std.testing.expect((try decoder.push(0xF8)) == null);
    const first = (try decoder.push(100)).?;
    try std.testing.expectEqualSlices(u8, &.{ 0x90, 60, 100 }, first.bytes());

    try std.testing.expect((try decoder.push(61)) == null);
    try std.testing.expect((try decoder.push(0xFE)) == null);
    const second = (try decoder.push(101)).?;
    try std.testing.expectEqualSlices(u8, &.{ 0x90, 61, 101 }, second.bytes());
}

test "stream decoder resets after unsupported status and malformed direct state" {
    var decoder = StreamDecoder{};
    try std.testing.expectError(error.MissingRunningStatus, decoder.push(60));
    try std.testing.expectError(error.UnsupportedMidiStatus, decoder.push(0xF0));
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(@as(?u8, null), decoder.running_status);

    decoder = .{
        .running_status = 0x90,
        .storage = .{ 0x80, 60, 0 },
        .length = 2,
    };
    try std.testing.expect(!decoder.valid());
    try std.testing.expectError(error.InvalidMidiDecoderState, decoder.push(100));
    try std.testing.expect(decoder.valid());
    try std.testing.expectEqual(@as(?u8, null), decoder.running_status);

    try std.testing.expect((try decoder.push(0x90)) == null);
    try std.testing.expect((try decoder.push(60)) == null);
    try std.testing.expect((try decoder.push(0x91)) == null);
    try std.testing.expect((try decoder.push(61)) == null);
    const replaced = (try decoder.push(110)).?;
    try std.testing.expectEqualSlices(u8, &.{ 0x91, 61, 110 }, replaced.bytes());
}
