const std = @import("std");
const midi1 = @import("midi1.zig");

pub const MessageType = enum(u4) {
    utility = 0x0,
    system = 0x1,
    midi1_channel_voice = 0x2,
    data64 = 0x3,
    midi2_channel_voice = 0x4,
    data128 = 0x5,
    reserved32_6 = 0x6,
    reserved32_7 = 0x7,
    reserved64_8 = 0x8,
    reserved64_9 = 0x9,
    reserved64_a = 0xA,
    reserved96_b = 0xB,
    reserved96_c = 0xC,
    flex_data = 0xD,
    reserved128_e = 0xE,
    stream = 0xF,
};

pub fn wordCountForType(message_type: MessageType) u3 {
    return switch (message_type) {
        .utility, .system, .midi1_channel_voice, .reserved32_6, .reserved32_7 => 1,
        .data64, .midi2_channel_voice, .reserved64_8, .reserved64_9, .reserved64_a => 2,
        .reserved96_b, .reserved96_c => 3,
        .data128, .flex_data, .reserved128_e, .stream => 4,
    };
}

pub const Packet = struct {
    storage: [4]u32,
    word_count: u3,

    pub fn init(words_source: []const u32) !Packet {
        if (words_source.len == 0 or words_source.len > 4) return error.InvalidUmpWordCount;
        const expected_count = wordCountForType(typeFromWord(words_source[0]));
        if (words_source.len != expected_count) return error.InvalidUmpWordCount;

        var packet = Packet{
            .storage = .{ 0, 0, 0, 0 },
            .word_count = @intCast(words_source.len),
        };
        @memcpy(packet.storage[0..words_source.len], words_source);
        return packet;
    }

    pub fn valid(self: Packet) bool {
        if (self.word_count == 0 or self.word_count > self.storage.len) return false;
        return self.word_count == wordCountForType(typeFromWord(self.storage[0]));
    }

    pub fn words(self: *const Packet) []const u32 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.word_count];
    }

    pub fn messageType(self: Packet) ?MessageType {
        if (!self.valid()) return null;
        return typeFromWord(self.storage[0]);
    }

    pub fn group(self: Packet) ?u4 {
        const message_type = self.messageType() orelse return null;
        if (message_type == .utility or message_type == .stream) return null;
        return @intCast((self.storage[0] >> 24) & 0x0F);
    }

    pub fn status(self: Packet) ?u4 {
        if (!self.valid()) return null;
        return @intCast((self.storage[0] >> 20) & 0x0F);
    }

    pub fn channel(self: Packet) ?u4 {
        const message_type = self.messageType() orelse return null;
        if (message_type != .midi1_channel_voice and message_type != .midi2_channel_voice) {
            return null;
        }
        return @intCast((self.storage[0] >> 16) & 0x0F);
    }
};

pub const Iterator = struct {
    source: []const u32,
    cursor: usize = 0,

    pub fn next(self: *Iterator) !?Packet {
        if (self.cursor > self.source.len) return error.InvalidUmpIteratorState;
        if (self.cursor == self.source.len) return null;

        const count: usize = wordCountForType(typeFromWord(self.source[self.cursor]));
        const end = std.math.add(usize, self.cursor, count) catch
            return error.TruncatedUmpPacket;
        if (end > self.source.len) return error.TruncatedUmpPacket;
        const packet = try Packet.init(self.source[self.cursor..end]);
        self.cursor = end;
        return packet;
    }

    pub fn reset(self: *Iterator) void {
        self.cursor = 0;
    }
};

pub const Midi1Packet = struct {
    group: u4,
    message: midi1.Message,
};

pub fn fromMidi1(group: u8, message: midi1.Message) !Packet {
    if (group > 15) return error.InvalidUmpGroup;
    if (!message.valid()) return error.InvalidMidiMessage;

    const bytes = message.bytes();
    const data2 = if (bytes.len == 3) bytes[2] else 0;
    const word = (@as(u32, 0x2) << 28) |
        (@as(u32, group) << 24) |
        (@as(u32, bytes[0]) << 16) |
        (@as(u32, bytes[1]) << 8) |
        data2;
    return Packet.init(&.{word});
}

pub fn toMidi1(packet: Packet) !Midi1Packet {
    if (!packet.valid()) return error.InvalidUmpPacket;
    if (packet.messageType().? != .midi1_channel_voice) {
        return error.NotMidi1ChannelVoiceUmp;
    }

    const word = packet.storage[0];
    const status: u8 = @intCast((word >> 16) & 0xFF);
    const data1: u8 = @intCast((word >> 8) & 0xFF);
    const data2: u8 = @intCast(word & 0xFF);
    const message_kind = kindFromStatus(status) orelse return error.InvalidMidi1ChannelVoiceUmp;
    const message = switch (message_kind) {
        .program_change, .channel_pressure => blk: {
            if (data2 != 0) return error.InvalidMidi1ChannelVoiceUmp;
            break :blk try midi1.Message.parse(&.{ status, data1 });
        },
        else => try midi1.Message.parse(&.{ status, data1, data2 }),
    };
    return .{
        .group = @intCast((word >> 24) & 0x0F),
        .message = message,
    };
}

pub fn scale7To8(value: u7) u8 {
    const shifted: u8 = @as(u8, value) << 1;
    const repeat: u8 = value & 0x3F;
    const mask: u8 = if (value <= 0x40) 0 else 0xFF;
    return shifted | ((repeat >> 5) & mask);
}

pub fn scale7To16(value: u7) u16 {
    const shifted: u16 = @as(u16, value) << 9;
    const repeat: u16 = value & 0x3F;
    const mask: u16 = if (value <= 0x40) 0 else 0xFFFF;
    return shifted | (((repeat << 3) | (repeat >> 3)) & mask);
}

pub fn scale14To16(value: u14) u16 {
    const shifted: u16 = @as(u16, value) << 2;
    const repeat: u16 = value & 0x1FFF;
    const mask: u16 = if (value <= 0x2000) 0 else 0xFFFF;
    return shifted | ((repeat >> 11) & mask);
}

pub fn scale7To32(value: u7) u32 {
    const shifted: u32 = @as(u32, value) << 25;
    const repeat: u32 = value & 0x3F;
    const mask: u32 = if (value <= 0x40) 0 else 0xFFFF_FFFF;
    return shifted |
        (((repeat << 19) | (repeat << 13) | (repeat << 7) | (repeat << 1) |
            (repeat >> 5)) & mask);
}

pub fn scale14To32(value: u14) u32 {
    const shifted: u32 = @as(u32, value) << 18;
    const repeat: u32 = value & 0x1FFF;
    const mask: u32 = if (value <= 0x2000) 0 else 0xFFFF_FFFF;
    return shifted | (((repeat << 5) | (repeat >> 8)) & mask);
}

pub fn scale8To7(value: u8) u7 {
    return @intCast(value >> 1);
}

pub fn scale16To7(value: u16) u7 {
    return @intCast(value >> 9);
}

pub fn scale32To7(value: u32) u7 {
    return @intCast(value >> 25);
}

pub fn scale16To14(value: u16) u14 {
    return @intCast(value >> 2);
}

pub fn scale32To14(value: u32) u14 {
    return @intCast(value >> 18);
}

fn typeFromWord(word: u32) MessageType {
    return @enumFromInt((word >> 28) & 0x0F);
}

fn kindFromStatus(status: u8) ?midi1.MessageKind {
    if ((status & 0xF0) < 0x80 or (status & 0xF0) > 0xE0) return null;
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

test "UMP message types select their specified packet sizes" {
    const expected = [_]u3{ 1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4 };
    for (expected, 0..) |word_count, raw_type| {
        try std.testing.expectEqual(
            word_count,
            wordCountForType(@enumFromInt(raw_type)),
        );
    }
}

test "UMP packets validate framing and expose fields" {
    const packet = try Packet.init(&.{ 0x4490_3C7F, 0 });
    try std.testing.expectEqual(MessageType.midi2_channel_voice, packet.messageType().?);
    try std.testing.expectEqual(@as(?u4, 4), packet.group());
    try std.testing.expectEqual(@as(?u4, 9), packet.status());
    try std.testing.expectEqual(@as(?u4, 0), packet.channel());
    try std.testing.expectEqual(@as(usize, 2), packet.words().len);

    try std.testing.expectError(error.InvalidUmpWordCount, Packet.init(&.{}));
    try std.testing.expectError(error.InvalidUmpWordCount, Packet.init(&.{0x4000_0000}));
    try std.testing.expectError(
        error.InvalidUmpWordCount,
        Packet.init(&.{ 0x5000_0000, 0, 0 }),
    );

    var malformed = packet;
    malformed.word_count = 5;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.words().len);
    try std.testing.expectEqual(@as(?MessageType, null), malformed.messageType());
}

test "UMP iterator walks mixed packet sizes and contains truncation" {
    const words = [_]u32{
        0x2090_3C7F,
        0x4090_3C00,
        0xFFFF_0000,
        0xD000_0000,
        1,
        2,
        3,
    };
    var iterator = Iterator{ .source = &words };
    try std.testing.expectEqual(MessageType.midi1_channel_voice, (try iterator.next()).?.messageType().?);
    try std.testing.expectEqual(MessageType.midi2_channel_voice, (try iterator.next()).?.messageType().?);
    try std.testing.expectEqual(MessageType.flex_data, (try iterator.next()).?.messageType().?);
    try std.testing.expect((try iterator.next()) == null);

    var truncated = Iterator{ .source = &.{ 0x5000_0000, 1 } };
    try std.testing.expectError(error.TruncatedUmpPacket, truncated.next());
    try std.testing.expectEqual(@as(usize, 0), truncated.cursor);

    iterator.cursor = words.len + 1;
    try std.testing.expectError(error.InvalidUmpIteratorState, iterator.next());
    iterator.reset();
    try std.testing.expectEqual(@as(usize, 0), iterator.cursor);
}

test "MIDI 1 channel messages round trip through UMP exactly" {
    const messages = [_]midi1.Message{
        try midi1.Message.noteOff(2, 60, 64),
        try midi1.Message.noteOn(3, 61, 100),
        try midi1.Message.polyphonicKeyPressure(4, 62, 80),
        try midi1.Message.controlChange(5, 74, 99),
        try midi1.Message.programChange(6, 12),
        try midi1.Message.channelPressure(7, 45),
        try midi1.Message.pitchBend(8, 0x2345),
    };
    for (messages) |message| {
        const packet = try fromMidi1(11, message);
        try std.testing.expectEqual(@as(?u4, 11), packet.group());
        const decoded = try toMidi1(packet);
        try std.testing.expectEqual(@as(u4, 11), decoded.group);
        try std.testing.expectEqualSlices(u8, message.bytes(), decoded.message.bytes());
    }
}

test "MIDI 1 UMP translation rejects malformed packets transactionally" {
    try std.testing.expectError(
        error.InvalidUmpGroup,
        fromMidi1(16, try midi1.Message.noteOn(0, 60, 100)),
    );
    try std.testing.expectError(
        error.NotMidi1ChannelVoiceUmp,
        toMidi1(try Packet.init(&.{ 0x4090_3C00, 0 })),
    );
    try std.testing.expectError(
        error.InvalidMidi1ChannelVoiceUmp,
        toMidi1(try Packet.init(&.{0x20F0_0000})),
    );
    try std.testing.expectError(
        error.InvalidMidi1ChannelVoiceUmp,
        toMidi1(try Packet.init(&.{0x20C0_0101})),
    );
}

test "UMP value scaling preserves every MIDI 1 value and endpoint" {
    try std.testing.expectEqual(@as(u8, 0), scale7To8(0));
    try std.testing.expectEqual(std.math.maxInt(u8), scale7To8(127));
    try std.testing.expectEqual(@as(u16, 0), scale7To16(0));
    try std.testing.expectEqual(std.math.maxInt(u16), scale7To16(127));
    try std.testing.expectEqual(@as(u32, 0), scale7To32(0));
    try std.testing.expectEqual(std.math.maxInt(u32), scale7To32(127));
    try std.testing.expectEqual(@as(u16, 0), scale14To16(0));
    try std.testing.expectEqual(std.math.maxInt(u16), scale14To16(16383));
    try std.testing.expectEqual(@as(u32, 0), scale14To32(0));
    try std.testing.expectEqual(std.math.maxInt(u32), scale14To32(16383));

    for (0..128) |raw_value| {
        const value: u7 = @intCast(raw_value);
        try std.testing.expectEqual(value, scale8To7(scale7To8(value)));
        try std.testing.expectEqual(value, scale16To7(scale7To16(value)));
        try std.testing.expectEqual(value, scale32To7(scale7To32(value)));
    }
    for (0..16384) |raw_value| {
        const value: u14 = @intCast(raw_value);
        try std.testing.expectEqual(value, scale16To14(scale14To16(value)));
        try std.testing.expectEqual(value, scale32To14(scale14To32(value)));
    }
}
