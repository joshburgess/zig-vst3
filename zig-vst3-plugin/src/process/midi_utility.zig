const std = @import("std");
const ump = @import("midi_ump.zig");

pub const Status = enum(u4) {
    noop = 0x0,
    jr_clock = 0x1,
    jr_timestamp = 0x2,
    delta_ticks_per_quarter_note = 0x3,
    delta_clockstamp = 0x4,
};

pub const Payload = union(Status) {
    noop: void,
    jr_clock: u16,
    jr_timestamp: u16,
    delta_ticks_per_quarter_note: u16,
    delta_clockstamp: u20,
};

pub const Message = struct {
    payload: Payload,

    pub fn packet(self: Message) !ump.Packet {
        const status = std.meta.activeTag(self.payload);
        var word = @as(u32, @intFromEnum(status)) << 20;
        switch (self.payload) {
            .noop => {},
            .jr_clock, .jr_timestamp => |value| word |= value,
            .delta_ticks_per_quarter_note => |value| {
                if (value == 0) return error.InvalidDeltaTicksPerQuarterNote;
                word |= value;
            },
            .delta_clockstamp => |value| word |= value,
        }
        return ump.Packet.init(&.{word});
    }

    pub fn parse(ump_packet: ump.Packet) !Message {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .utility) return error.NotUtilityUmp;

        const word = ump_packet.storage[0];
        if ((word & 0x0F00_0000) != 0) return error.InvalidUtilityReservedField;
        const status: Status = switch ((word >> 20) & 0x0F) {
            0 => .noop,
            1 => .jr_clock,
            2 => .jr_timestamp,
            3 => .delta_ticks_per_quarter_note,
            4 => .delta_clockstamp,
            else => return error.UnsupportedUtilityStatus,
        };
        const value = word & 0x000F_FFFF;
        const payload: Payload = switch (status) {
            .noop => blk: {
                if (value != 0) return error.InvalidUtilityReservedField;
                break :blk .{ .noop = {} };
            },
            .jr_clock => blk: {
                if ((value & 0xF0000) != 0) return error.InvalidUtilityReservedField;
                break :blk .{ .jr_clock = @intCast(value) };
            },
            .jr_timestamp => blk: {
                if ((value & 0xF0000) != 0) return error.InvalidUtilityReservedField;
                break :blk .{ .jr_timestamp = @intCast(value) };
            },
            .delta_ticks_per_quarter_note => blk: {
                if ((value & 0xF0000) != 0) return error.InvalidUtilityReservedField;
                if (value == 0) return error.InvalidDeltaTicksPerQuarterNote;
                break :blk .{ .delta_ticks_per_quarter_note = @intCast(value) };
            },
            .delta_clockstamp => .{ .delta_clockstamp = @intCast(value) },
        };
        return .{ .payload = payload };
    }
};

test "utility messages round trip every defined status" {
    const messages = [_]Message{
        .{ .payload = .{ .noop = {} } },
        .{ .payload = .{ .jr_clock = 0xFFFF } },
        .{ .payload = .{ .jr_timestamp = 0x1234 } },
        .{ .payload = .{ .delta_ticks_per_quarter_note = 960 } },
        .{ .payload = .{ .delta_clockstamp = 0xF_FFFF } },
    };
    for (messages) |message| {
        try std.testing.expectEqualDeep(message, try Message.parse(try message.packet()));
    }
}

test "utility messages use groupless canonical fields" {
    try std.testing.expectEqualSlices(
        u32,
        &.{0x0010_ABCD},
        (try (Message{ .payload = .{ .jr_clock = 0xABCD } }).packet()).words(),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{0x004F_FFFF},
        (try (Message{ .payload = .{ .delta_clockstamp = 0xF_FFFF } }).packet()).words(),
    );
}

test "utility parser rejects reserved fields and unsupported statuses" {
    try std.testing.expectError(
        error.NotUtilityUmp,
        Message.parse(try ump.Packet.init(&.{0x10F8_0000})),
    );
    try std.testing.expectError(
        error.InvalidUtilityReservedField,
        Message.parse(try ump.Packet.init(&.{0x0100_0000})),
    );
    try std.testing.expectError(
        error.UnsupportedUtilityStatus,
        Message.parse(try ump.Packet.init(&.{0x0050_0000})),
    );
    try std.testing.expectError(
        error.InvalidUtilityReservedField,
        Message.parse(try ump.Packet.init(&.{0x001F_0000})),
    );
    try std.testing.expectError(
        error.InvalidDeltaTicksPerQuarterNote,
        Message.parse(try ump.Packet.init(&.{0x0030_0000})),
    );
    try std.testing.expectError(
        error.InvalidDeltaTicksPerQuarterNote,
        (Message{ .payload = .{ .delta_ticks_per_quarter_note = 0 } }).packet(),
    );
}
