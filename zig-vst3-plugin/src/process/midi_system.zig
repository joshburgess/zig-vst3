const std = @import("std");
const ump = @import("midi_ump.zig");

pub const Status = enum(u8) {
    time_code = 0xF1,
    song_position = 0xF2,
    song_select = 0xF3,
    tune_request = 0xF6,
    timing_clock = 0xF8,
    start = 0xFA,
    continue_playback = 0xFB,
    stop = 0xFC,
    active_sensing = 0xFE,
    reset = 0xFF,
};

pub const Payload = union(Status) {
    time_code: u7,
    song_position: u14,
    song_select: u7,
    tune_request: void,
    timing_clock: void,
    start: void,
    continue_playback: void,
    stop: void,
    active_sensing: void,
    reset: void,
};

pub const Message = struct {
    group: u4,
    payload: Payload,

    pub fn packet(self: Message) !ump.Packet {
        const status = std.meta.activeTag(self.payload);
        var word = (@as(u32, 0x1) << 28) |
            (@as(u32, self.group) << 24) |
            (@as(u32, @intFromEnum(status)) << 16);
        switch (self.payload) {
            .time_code => |value| word |= @as(u32, value) << 8,
            .song_position => |value| {
                word |= @as(u32, @intCast(value & 0x7F)) << 8;
                word |= @as(u32, @intCast(value >> 7));
            },
            .song_select => |value| word |= @as(u32, value) << 8,
            .tune_request,
            .timing_clock,
            .start,
            .continue_playback,
            .stop,
            .active_sensing,
            .reset,
            => {},
        }
        return ump.Packet.init(&.{word});
    }

    pub fn parse(ump_packet: ump.Packet) !Message {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        if (ump_packet.messageType().? != .system) return error.NotSystemUmp;

        const word = ump_packet.storage[0];
        const status_byte: u8 = @intCast((word >> 16) & 0xFF);
        const status = statusFromByte(status_byte) orelse return error.UnsupportedSystemStatus;
        const data1: u8 = @intCast((word >> 8) & 0xFF);
        const data2: u8 = @intCast(word & 0xFF);
        const payload: Payload = switch (status) {
            .time_code => .{ .time_code = try dataByte(data1, data2) },
            .song_position => blk: {
                if (data1 > 127 or data2 > 127) return error.InvalidSystemDataByte;
                break :blk .{ .song_position = (@as(u14, @intCast(data2)) << 7) | @as(u14, @intCast(data1)) };
            },
            .song_select => .{ .song_select = try dataByte(data1, data2) },
            .tune_request,
            .timing_clock,
            .start,
            .continue_playback,
            .stop,
            .active_sensing,
            .reset,
            => blk: {
                if (data1 != 0 or data2 != 0) return error.InvalidSystemReservedField;
                break :blk switch (status) {
                    .tune_request => .{ .tune_request = {} },
                    .timing_clock => .{ .timing_clock = {} },
                    .start => .{ .start = {} },
                    .continue_playback => .{ .continue_playback = {} },
                    .stop => .{ .stop = {} },
                    .active_sensing => .{ .active_sensing = {} },
                    .reset => .{ .reset = {} },
                    else => unreachable,
                };
            },
        };
        return .{
            .group = @intCast((word >> 24) & 0x0F),
            .payload = payload,
        };
    }
};

fn dataByte(value: u8, reserved: u8) !u7 {
    if (value > 127) return error.InvalidSystemDataByte;
    if (reserved != 0) return error.InvalidSystemReservedField;
    return @intCast(value);
}

fn statusFromByte(value: u8) ?Status {
    return switch (value) {
        0xF1 => .time_code,
        0xF2 => .song_position,
        0xF3 => .song_select,
        0xF6 => .tune_request,
        0xF8 => .timing_clock,
        0xFA => .start,
        0xFB => .continue_playback,
        0xFC => .stop,
        0xFE => .active_sensing,
        0xFF => .reset,
        else => null,
    };
}

test "system common and realtime messages round trip" {
    const messages = [_]Message{
        .{ .group = 0, .payload = .{ .time_code = 0x7F } },
        .{ .group = 1, .payload = .{ .song_position = 0x3FFF } },
        .{ .group = 2, .payload = .{ .song_select = 0x7F } },
        .{ .group = 3, .payload = .{ .tune_request = {} } },
        .{ .group = 4, .payload = .{ .timing_clock = {} } },
        .{ .group = 5, .payload = .{ .start = {} } },
        .{ .group = 6, .payload = .{ .continue_playback = {} } },
        .{ .group = 7, .payload = .{ .stop = {} } },
        .{ .group = 8, .payload = .{ .active_sensing = {} } },
        .{ .group = 15, .payload = .{ .reset = {} } },
    };
    for (messages) |message| {
        try std.testing.expectEqualDeep(message, try Message.parse(try message.packet()));
    }
}

test "system messages use canonical wire fields" {
    try std.testing.expectEqualSlices(
        u32,
        &.{0x19F2_017F},
        (try (Message{
            .group = 9,
            .payload = .{ .song_position = 0x3F81 },
        }).packet()).words(),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{0x1AFF_0000},
        (try (Message{
            .group = 10,
            .payload = .{ .reset = {} },
        }).packet()).words(),
    );
}

test "system parser rejects unsupported status and malformed fields" {
    try std.testing.expectError(
        error.NotSystemUmp,
        Message.parse(try ump.Packet.init(&.{0x2090_3C7F})),
    );
    try std.testing.expectError(
        error.UnsupportedSystemStatus,
        Message.parse(try ump.Packet.init(&.{0x10F4_0000})),
    );
    try std.testing.expectError(
        error.InvalidSystemDataByte,
        Message.parse(try ump.Packet.init(&.{0x10F1_8000})),
    );
    try std.testing.expectError(
        error.InvalidSystemReservedField,
        Message.parse(try ump.Packet.init(&.{0x10F3_0101})),
    );
    try std.testing.expectError(
        error.InvalidSystemReservedField,
        Message.parse(try ump.Packet.init(&.{0x10F8_0001})),
    );
}
