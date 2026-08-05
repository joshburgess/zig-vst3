const std = @import("std");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Address = enum(u2) {
    channel,
    group,
};

pub const Target = struct {
    group: u4,
    address: Address,
    channel: u4 = 0,

    pub fn valid(self: Target) bool {
        return self.address == .channel or self.channel == 0;
    }
};

pub const Status = enum(u8) {
    set_tempo = 0x00,
    set_time_signature = 0x01,
    set_metronome = 0x02,
    set_key_signature = 0x05,
    set_chord_name = 0x06,
};

pub const TimeSignature = struct {
    numerator: u9,
    denominator_power: u8,
    thirty_second_notes: u8,

    pub fn valid(self: TimeSignature) bool {
        return self.numerator >= 1 and self.numerator <= 256;
    }
};

pub const Metronome = struct {
    clocks_per_primary_click: u8,
    bar_accents: [3]u8,
    subdivision_clicks: [2]u8,
};

pub const Tonic = enum(u4) {
    unknown,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
};

pub const KeySignature = struct {
    sharps_flats: i4,
    tonic: Tonic,
};

pub const ChordType = enum(u5) {
    clear,
    major,
    major_6th,
    major_7th,
    major_9th,
    major_11th,
    major_13th,
    minor,
    minor_6th,
    minor_7th,
    minor_9th,
    minor_11th,
    minor_13th,
    dominant,
    dominant_9th,
    dominant_11th,
    dominant_13th,
    augmented,
    augmented_7th,
    diminished,
    diminished_7th,
    half_diminished,
    major_minor,
    pedal,
    power,
    suspended_2nd,
    suspended_4th,
    suspended_4th_7th,
};

pub const AlterationType = enum(u4) {
    none,
    add,
    subtract,
    raise,
    lower,
};

pub const Alteration = struct {
    kind: AlterationType = .none,
    degree: u4 = 0,

    pub fn valid(self: Alteration) bool {
        return self.kind != .none or self.degree == 0;
    }
};

pub const ChordName = struct {
    tonic_sharps_flats: i4,
    tonic: Tonic,
    chord_type: ChordType,
    alterations: [4]Alteration = .{Alteration{}} ** 4,
    bass_sharps_flats: i4 = -8,
    bass: Tonic = .unknown,
    bass_chord_type: ChordType = .clear,
    bass_alterations: [2]Alteration = .{Alteration{}} ** 2,

    pub fn valid(self: ChordName) bool {
        if (self.tonic_sharps_flats < -2 or self.tonic_sharps_flats > 2)
            return false;
        if (self.bass == .unknown) {
            if (self.bass_sharps_flats != -8) return false;
        } else if (self.bass_sharps_flats < -2 or self.bass_sharps_flats > 2) {
            return false;
        }
        for (self.alterations) |alteration| {
            if (!alteration.valid()) return false;
        }
        for (self.bass_alterations) |alteration| {
            if (!alteration.valid()) return false;
        }
        return true;
    }
};

pub const Payload = union(Status) {
    set_tempo: u32,
    set_time_signature: TimeSignature,
    set_metronome: Metronome,
    set_key_signature: KeySignature,
    set_chord_name: ChordName,
};

pub const Message = struct {
    target: Target,
    payload: Payload,

    pub fn packet(self: Message) !ump.Packet {
        if (!self.target.valid()) return error.InvalidFlexTarget;
        const status = std.meta.activeTag(self.payload);
        if (status != .set_key_signature and status != .set_chord_name and
            self.target.address != .group)
            return error.InvalidFlexTarget;

        var words = [_]u32{0} ** 4;
        setByte(&words, 0, 0xD0 | @as(u8, self.target.group));
        setByte(
            &words,
            1,
            (@as(u8, @intFromEnum(self.target.address)) << 4) |
                @as(u8, self.target.channel),
        );
        setByte(&words, 3, @intFromEnum(status));

        switch (self.payload) {
            .set_tempo => |value| {
                if (value == 0) return error.InvalidFlexTempo;
                words[1] = value;
            },
            .set_time_signature => |value| {
                if (!value.valid()) return error.InvalidFlexTimeSignature;
                setByte(&words, 4, @truncate(value.numerator));
                setByte(&words, 5, value.denominator_power);
                setByte(&words, 6, value.thirty_second_notes);
            },
            .set_metronome => |value| {
                setByte(&words, 4, value.clocks_per_primary_click);
                for (value.bar_accents, 0..) |accent, index|
                    setByte(&words, 5 + index, accent);
                for (value.subdivision_clicks, 0..) |clicks, index|
                    setByte(&words, 8 + index, clicks);
            },
            .set_key_signature => |value| {
                const encoded_sharps_flats: u4 = @bitCast(value.sharps_flats);
                setByte(
                    &words,
                    4,
                    (@as(u8, encoded_sharps_flats) << 4) |
                        @as(u8, @intFromEnum(value.tonic)),
                );
            },
            .set_chord_name => |value| {
                if (!value.valid()) return error.InvalidFlexChordName;
                setByte(
                    &words,
                    4,
                    encodeSignedNibble(value.tonic_sharps_flats) |
                        @as(u8, @intFromEnum(value.tonic)),
                );
                setByte(&words, 5, @intFromEnum(value.chord_type));
                for (value.alterations, 0..) |alteration, index|
                    setByte(&words, 6 + index, encodeAlteration(alteration));
                setByte(
                    &words,
                    12,
                    encodeSignedNibble(value.bass_sharps_flats) |
                        @as(u8, @intFromEnum(value.bass)),
                );
                setByte(&words, 13, @intFromEnum(value.bass_chord_type));
                for (value.bass_alterations, 0..) |alteration, index|
                    setByte(&words, 14 + index, encodeAlteration(alteration));
            },
        }
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet) !Message {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .flex_data) return error.NotFlexDataUmp;

        const form_and_target = byteAt(ump_packet, 1);
        if ((form_and_target & 0xC0) != 0) return error.UnsupportedFlexFormat;
        const address: Address = switch ((form_and_target >> 4) & 3) {
            0 => .channel,
            1 => .group,
            else => return error.InvalidFlexTarget,
        };
        const target = Target{
            .group = @intCast(byteAt(ump_packet, 0) & 0x0F),
            .address = address,
            .channel = @intCast(form_and_target & 0x0F),
        };
        if (!target.valid()) return error.InvalidFlexTarget;
        if (byteAt(ump_packet, 2) != 0) return error.UnsupportedFlexStatusBank;

        const status: Status = switch (byteAt(ump_packet, 3)) {
            0x00 => .set_tempo,
            0x01 => .set_time_signature,
            0x02 => .set_metronome,
            0x05 => .set_key_signature,
            0x06 => .set_chord_name,
            else => return error.UnsupportedFlexStatus,
        };
        if (status != .set_key_signature and status != .set_chord_name and
            target.address != .group)
            return error.InvalidFlexTarget;

        const payload: Payload = switch (status) {
            .set_tempo => blk: {
                try expectZeroRange(ump_packet, 8, 16);
                if (ump_packet.storage[1] == 0) return error.InvalidFlexTempo;
                break :blk .{ .set_tempo = ump_packet.storage[1] };
            },
            .set_time_signature => blk: {
                try expectZeroRange(ump_packet, 7, 16);
                const encoded_numerator = byteAt(ump_packet, 4);
                const value = TimeSignature{
                    .numerator = if (encoded_numerator == 0) 256 else encoded_numerator,
                    .denominator_power = byteAt(ump_packet, 5),
                    .thirty_second_notes = byteAt(ump_packet, 6),
                };
                if (!value.valid()) return error.InvalidFlexTimeSignature;
                break :blk .{ .set_time_signature = value };
            },
            .set_metronome => blk: {
                try expectZeroRange(ump_packet, 10, 16);
                break :blk .{ .set_metronome = .{
                    .clocks_per_primary_click = byteAt(ump_packet, 4),
                    .bar_accents = .{
                        byteAt(ump_packet, 5),
                        byteAt(ump_packet, 6),
                        byteAt(ump_packet, 7),
                    },
                    .subdivision_clicks = .{
                        byteAt(ump_packet, 8),
                        byteAt(ump_packet, 9),
                    },
                } };
            },
            .set_key_signature => blk: {
                try expectZeroRange(ump_packet, 5, 16);
                const value = byteAt(ump_packet, 4);
                const tonic: Tonic = switch (value & 0x0F) {
                    0 => .unknown,
                    1 => .a,
                    2 => .b,
                    3 => .c,
                    4 => .d,
                    5 => .e,
                    6 => .f,
                    7 => .g,
                    else => return error.InvalidFlexTonic,
                };
                const encoded_sharps_flats: u4 = @intCast(value >> 4);
                break :blk .{ .set_key_signature = .{
                    .sharps_flats = @bitCast(encoded_sharps_flats),
                    .tonic = tonic,
                } };
            },
            .set_chord_name => blk: {
                try expectZeroRange(ump_packet, 10, 12);
                const value = ChordName{
                    .tonic_sharps_flats = decodeSignedNibble(byteAt(ump_packet, 4)),
                    .tonic = try parseTonic(byteAt(ump_packet, 4)),
                    .chord_type = try parseChordType(byteAt(ump_packet, 5)),
                    .alterations = .{
                        try parseAlteration(byteAt(ump_packet, 6)),
                        try parseAlteration(byteAt(ump_packet, 7)),
                        try parseAlteration(byteAt(ump_packet, 8)),
                        try parseAlteration(byteAt(ump_packet, 9)),
                    },
                    .bass_sharps_flats = decodeSignedNibble(byteAt(ump_packet, 12)),
                    .bass = try parseTonic(byteAt(ump_packet, 12)),
                    .bass_chord_type = try parseChordType(byteAt(ump_packet, 13)),
                    .bass_alterations = .{
                        try parseAlteration(byteAt(ump_packet, 14)),
                        try parseAlteration(byteAt(ump_packet, 15)),
                    },
                };
                if (!value.valid()) return error.InvalidFlexChordName;
                break :blk .{ .set_chord_name = value };
            },
        };
        return .{ .target = target, .payload = payload };
    }
};

fn parseTonic(value: u8) !Tonic {
    return switch (value & 0x0F) {
        0 => .unknown,
        1 => .a,
        2 => .b,
        3 => .c,
        4 => .d,
        5 => .e,
        6 => .f,
        7 => .g,
        else => error.InvalidFlexTonic,
    };
}

fn parseChordType(value: u8) !ChordType {
    if (value > @intFromEnum(ChordType.suspended_4th_7th))
        return error.InvalidFlexChordType;
    return @enumFromInt(value);
}

fn parseAlteration(value: u8) !Alteration {
    const raw_kind = value >> 4;
    if (raw_kind > @intFromEnum(AlterationType.lower))
        return error.InvalidFlexAlteration;
    const alteration = Alteration{
        .kind = @enumFromInt(raw_kind),
        .degree = @intCast(value & 0x0F),
    };
    if (!alteration.valid()) return error.InvalidFlexAlteration;
    return alteration;
}

fn encodeAlteration(alteration: Alteration) u8 {
    return (@as(u8, @intFromEnum(alteration.kind)) << 4) | alteration.degree;
}

fn encodeSignedNibble(value: i4) u8 {
    const encoded: u4 = @bitCast(value);
    return @as(u8, encoded) << 4;
}

fn decodeSignedNibble(value: u8) i4 {
    const encoded: u4 = @intCast(value >> 4);
    return @bitCast(encoded);
}

fn expectZeroRange(ump_packet: ump.Packet, start: usize, end: usize) !void {
    for (start..end) |index| {
        if (byteAt(ump_packet, index) != 0) return error.InvalidFlexReservedField;
    }
}

test "fixed Flex Data messages round trip every supported status" {
    const messages = [_]Message{
        .{
            .target = .{ .group = 3, .address = .group },
            .payload = .{ .set_tempo = 50_000_000 },
        },
        .{
            .target = .{ .group = 4, .address = .group },
            .payload = .{ .set_time_signature = .{
                .numerator = 7,
                .denominator_power = 3,
                .thirty_second_notes = 8,
            } },
        },
        .{
            .target = .{ .group = 5, .address = .group },
            .payload = .{ .set_metronome = .{
                .clocks_per_primary_click = 24,
                .bar_accents = .{ 3, 2, 0 },
                .subdivision_clicks = .{ 2, 0 },
            } },
        },
        .{
            .target = .{ .group = 6, .address = .channel, .channel = 9 },
            .payload = .{ .set_key_signature = .{
                .sharps_flats = -4,
                .tonic = .d,
            } },
        },
        .{
            .target = .{ .group = 7, .address = .channel, .channel = 2 },
            .payload = .{ .set_chord_name = .{
                .tonic_sharps_flats = 1,
                .tonic = .c,
                .chord_type = .major_7th,
                .alterations = .{
                    .{ .kind = .add, .degree = 9 },
                    .{},
                    .{},
                    .{},
                },
                .bass_sharps_flats = -1,
                .bass = .e,
                .bass_chord_type = .minor,
                .bass_alterations = .{
                    .{ .kind = .raise, .degree = 5 },
                    .{},
                },
            } },
        },
    };
    for (messages) |message|
        try std.testing.expectEqualDeep(message, try Message.parse(try message.packet()));
}

test "fixed Flex Data messages use canonical wire fields" {
    const time = Message{
        .target = .{ .group = 4, .address = .group },
        .payload = .{ .set_time_signature = .{
            .numerator = 256,
            .denominator_power = 3,
            .thirty_second_notes = 8,
        } },
    };
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xD410_0001, 0x0003_0800, 0, 0 },
        (try time.packet()).words(),
    );

    const key = Message{
        .target = .{ .group = 2, .address = .channel, .channel = 7 },
        .payload = .{ .set_key_signature = .{
            .sharps_flats = -4,
            .tonic = .d,
        } },
    };
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xD207_0005, 0xC400_0000, 0, 0 },
        (try key.packet()).words(),
    );

    const chord = Message{
        .target = .{ .group = 7, .address = .channel, .channel = 2 },
        .payload = .{ .set_chord_name = .{
            .tonic_sharps_flats = 1,
            .tonic = .c,
            .chord_type = .major_7th,
            .alterations = .{
                .{ .kind = .add, .degree = 9 },
                .{},
                .{},
                .{},
            },
            .bass_sharps_flats = -1,
            .bass = .e,
            .bass_chord_type = .minor,
            .bass_alterations = .{
                .{ .kind = .raise, .degree = 5 },
                .{},
            },
        } },
    };
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xD702_0006, 0x1303_1900, 0, 0xF507_3500 },
        (try chord.packet()).words(),
    );
}

test "fixed Flex Data parser rejects malformed fields" {
    try std.testing.expectError(
        error.NotFlexDataUmp,
        Message.parse(try ump.Packet.init(&.{0x10F8_0000})),
    );
    try std.testing.expectError(
        error.UnsupportedFlexFormat,
        Message.parse(try ump.Packet.init(&.{ 0xD440_0000, 1, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFlexTarget,
        Message.parse(try ump.Packet.init(&.{ 0xD420_0005, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.UnsupportedFlexStatusBank,
        Message.parse(try ump.Packet.init(&.{ 0xD410_0100, 1, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFlexTempo,
        Message.parse(try ump.Packet.init(&.{ 0xD410_0000, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFlexTonic,
        Message.parse(try ump.Packet.init(&.{ 0xD400_0005, 0x0800_0000, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFlexReservedField,
        Message.parse(try ump.Packet.init(&.{ 0xD410_0001, 0x0402_0801, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFlexChordType,
        Message.parse(try ump.Packet.init(&.{
            0xD400_0006,
            0x031C_0000,
            0,
            0x8000_0000,
        })),
    );
    try std.testing.expectError(
        error.InvalidFlexChordName,
        Message.parse(try ump.Packet.init(&.{
            0xD400_0006,
            0x8301_0000,
            0,
            0x8000_0000,
        })),
    );
}
