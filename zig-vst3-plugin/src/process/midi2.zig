const std = @import("std");
const ump = @import("midi_ump.zig");

pub const Status = enum(u4) {
    registered_per_note_controller = 0x0,
    assignable_per_note_controller = 0x1,
    registered_controller = 0x2,
    assignable_controller = 0x3,
    relative_registered_controller = 0x4,
    relative_assignable_controller = 0x5,
    per_note_pitch_bend = 0x6,
    reserved = 0x7,
    note_off = 0x8,
    note_on = 0x9,
    polyphonic_key_pressure = 0xA,
    control_change = 0xB,
    program_change = 0xC,
    channel_pressure = 0xD,
    pitch_bend = 0xE,
    per_note_management = 0xF,
};

pub const NoteAttribute = enum(u8) {
    none = 0x00,
    manufacturer = 0x01,
    profile = 0x02,
    pitch_7_9 = 0x03,
};

pub const IndexedController = struct {
    bank_or_note: u7,
    index: u7,
    data: u32,
};

pub const PerNoteValue = struct {
    note: u7,
    data: u32,
};

pub const Note = struct {
    note: u7,
    attribute: u8,
    velocity: u16,
    attribute_data: u16,

    pub fn knownAttribute(self: Note) ?NoteAttribute {
        return switch (self.attribute) {
            0 => .none,
            1 => .manufacturer,
            2 => .profile,
            3 => .pitch_7_9,
            else => null,
        };
    }
};

pub const IndexedValue = struct {
    index: u7,
    data: u32,
};

pub const Program = struct {
    bank_valid: bool,
    program: u7,
    bank_msb: u7,
    bank_lsb: u7,
};

pub const PerNoteManagement = struct {
    note: u7,
    reset_controllers: bool,
    detach_controllers: bool,
};

pub const Payload = union(Status) {
    registered_per_note_controller: IndexedController,
    assignable_per_note_controller: IndexedController,
    registered_controller: IndexedController,
    assignable_controller: IndexedController,
    relative_registered_controller: IndexedController,
    relative_assignable_controller: IndexedController,
    per_note_pitch_bend: PerNoteValue,
    reserved: void,
    note_off: Note,
    note_on: Note,
    polyphonic_key_pressure: IndexedValue,
    control_change: IndexedValue,
    program_change: Program,
    channel_pressure: u32,
    pitch_bend: u32,
    per_note_management: PerNoteManagement,
};

pub const ChannelMessage = struct {
    group: u4,
    channel: u4,
    payload: Payload,

    pub fn parse(ump_packet: ump.Packet) !ChannelMessage {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        if (ump_packet.messageType().? != .midi2_channel_voice) {
            return error.NotMidi2ChannelVoiceUmp;
        }

        const first = ump_packet.storage[0];
        const second = ump_packet.storage[1];
        const status: Status = @enumFromInt((first >> 20) & 0x0F);
        const byte2: u8 = @intCast((first >> 8) & 0xFF);
        const byte3: u8 = @intCast(first & 0xFF);
        const payload: Payload = switch (status) {
            .registered_per_note_controller,
            .assignable_per_note_controller,
            .registered_controller,
            .assignable_controller,
            .relative_registered_controller,
            .relative_assignable_controller,
            => try indexedControllerPayload(status, byte2, byte3, second),
            .per_note_pitch_bend => blk: {
                try validateDataByte(byte2);
                if (byte3 != 0) return error.InvalidMidi2ReservedField;
                break :blk .{ .per_note_pitch_bend = .{
                    .note = @intCast(byte2),
                    .data = second,
                } };
            },
            .reserved => return error.ReservedMidi2Status,
            .note_off, .note_on => blk: {
                try validateDataByte(byte2);
                const note = Note{
                    .note = @intCast(byte2),
                    .attribute = byte3,
                    .velocity = @intCast(second >> 16),
                    .attribute_data = @intCast(second & 0xFFFF),
                };
                break :blk if (status == .note_on)
                    .{ .note_on = note }
                else
                    .{ .note_off = note };
            },
            .polyphonic_key_pressure, .control_change => blk: {
                try validateDataByte(byte2);
                if (byte3 != 0) return error.InvalidMidi2ReservedField;
                const value = IndexedValue{ .index = @intCast(byte2), .data = second };
                break :blk if (status == .control_change)
                    .{ .control_change = value }
                else
                    .{ .polyphonic_key_pressure = value };
            },
            .program_change => blk: {
                if (byte2 != 0 or (byte3 & 0xFE) != 0 or
                    ((second >> 16) & 0xFF) != 0)
                {
                    return error.InvalidMidi2ReservedField;
                }
                const program: u8 = @intCast(second >> 24);
                const bank_msb: u8 = @intCast((second >> 8) & 0xFF);
                const bank_lsb: u8 = @intCast(second & 0xFF);
                try validateDataByte(program);
                try validateDataByte(bank_msb);
                try validateDataByte(bank_lsb);
                break :blk .{ .program_change = .{
                    .bank_valid = (byte3 & 1) != 0,
                    .program = @intCast(program),
                    .bank_msb = @intCast(bank_msb),
                    .bank_lsb = @intCast(bank_lsb),
                } };
            },
            .channel_pressure, .pitch_bend => blk: {
                if (byte2 != 0 or byte3 != 0) return error.InvalidMidi2ReservedField;
                break :blk if (status == .channel_pressure)
                    .{ .channel_pressure = second }
                else
                    .{ .pitch_bend = second };
            },
            .per_note_management => blk: {
                try validateDataByte(byte2);
                if ((byte3 & 0xFC) != 0 or second != 0) {
                    return error.InvalidMidi2ReservedField;
                }
                break :blk .{ .per_note_management = .{
                    .note = @intCast(byte2),
                    .reset_controllers = (byte3 & 1) != 0,
                    .detach_controllers = (byte3 & 2) != 0,
                } };
            },
        };
        return .{
            .group = @intCast((first >> 24) & 0x0F),
            .channel = @intCast((first >> 16) & 0x0F),
            .payload = payload,
        };
    }

    pub fn packet(self: ChannelMessage) !ump.Packet {
        const status = std.meta.activeTag(self.payload);
        if (status == .reserved) return error.ReservedMidi2Status;

        var first = (@as(u32, 0x4) << 28) |
            (@as(u32, self.group) << 24) |
            (@as(u32, @intFromEnum(status)) << 20) |
            (@as(u32, self.channel) << 16);
        var second: u32 = 0;
        switch (self.payload) {
            .registered_per_note_controller,
            .assignable_per_note_controller,
            .registered_controller,
            .assignable_controller,
            .relative_registered_controller,
            .relative_assignable_controller,
            => |value| {
                first |= @as(u32, value.bank_or_note) << 8;
                first |= value.index;
                second = value.data;
            },
            .per_note_pitch_bend => |value| {
                first |= @as(u32, value.note) << 8;
                second = value.data;
            },
            .reserved => unreachable,
            .note_off, .note_on => |value| {
                first |= @as(u32, value.note) << 8;
                first |= value.attribute;
                second = (@as(u32, value.velocity) << 16) | value.attribute_data;
            },
            .polyphonic_key_pressure, .control_change => |value| {
                first |= @as(u32, value.index) << 8;
                second = value.data;
            },
            .program_change => |value| {
                if (value.bank_valid) first |= 1;
                second = (@as(u32, value.program) << 24) |
                    (@as(u32, value.bank_msb) << 8) |
                    value.bank_lsb;
            },
            .channel_pressure, .pitch_bend => |value| second = value,
            .per_note_management => |value| {
                first |= @as(u32, value.note) << 8;
                if (value.reset_controllers) first |= 1;
                if (value.detach_controllers) first |= 2;
            },
        }
        return ump.Packet.init(&.{ first, second });
    }
};

fn indexedControllerPayload(
    status: Status,
    bank_or_note: u8,
    index: u8,
    data: u32,
) !Payload {
    try validateDataByte(bank_or_note);
    try validateDataByte(index);
    const value = IndexedController{
        .bank_or_note = @intCast(bank_or_note),
        .index = @intCast(index),
        .data = data,
    };
    return switch (status) {
        .registered_per_note_controller => .{ .registered_per_note_controller = value },
        .assignable_per_note_controller => .{ .assignable_per_note_controller = value },
        .registered_controller => .{ .registered_controller = value },
        .assignable_controller => .{ .assignable_controller = value },
        .relative_registered_controller => .{ .relative_registered_controller = value },
        .relative_assignable_controller => .{ .relative_assignable_controller = value },
        else => unreachable,
    };
}

fn validateDataByte(value: u8) !void {
    if (value > 127) return error.InvalidMidi2DataByte;
}

test "MIDI 2 channel messages round trip every supported status" {
    const messages = [_]ChannelMessage{
        .{ .group = 1, .channel = 2, .payload = .{ .registered_per_note_controller = .{ .bank_or_note = 60, .index = 1, .data = 0x1234_5678 } } },
        .{ .group = 2, .channel = 3, .payload = .{ .assignable_per_note_controller = .{ .bank_or_note = 61, .index = 2, .data = 0x2345_6789 } } },
        .{ .group = 3, .channel = 4, .payload = .{ .registered_controller = .{ .bank_or_note = 4, .index = 3, .data = 0x3456_789A } } },
        .{ .group = 4, .channel = 5, .payload = .{ .assignable_controller = .{ .bank_or_note = 5, .index = 4, .data = 0x4567_89AB } } },
        .{ .group = 5, .channel = 6, .payload = .{ .relative_registered_controller = .{ .bank_or_note = 6, .index = 5, .data = 0xFFFF_FFFE } } },
        .{ .group = 6, .channel = 7, .payload = .{ .relative_assignable_controller = .{ .bank_or_note = 7, .index = 6, .data = 2 } } },
        .{ .group = 7, .channel = 8, .payload = .{ .per_note_pitch_bend = .{ .note = 62, .data = 0x8000_0000 } } },
        .{ .group = 8, .channel = 9, .payload = .{ .note_off = .{ .note = 63, .attribute = 3, .velocity = 0x1234, .attribute_data = 0x5678 } } },
        .{ .group = 9, .channel = 10, .payload = .{ .note_on = .{ .note = 64, .attribute = 0x7F, .velocity = 0xABCD, .attribute_data = 0xEF01 } } },
        .{ .group = 10, .channel = 11, .payload = .{ .polyphonic_key_pressure = .{ .index = 65, .data = 0x9876_5432 } } },
        .{ .group = 11, .channel = 12, .payload = .{ .control_change = .{ .index = 74, .data = 0x1111_2222 } } },
        .{ .group = 12, .channel = 13, .payload = .{ .program_change = .{ .bank_valid = true, .program = 12, .bank_msb = 3, .bank_lsb = 4 } } },
        .{ .group = 13, .channel = 14, .payload = .{ .channel_pressure = 0xCAFE_BABE } },
        .{ .group = 14, .channel = 15, .payload = .{ .pitch_bend = 0x8000_0000 } },
        .{ .group = 15, .channel = 0, .payload = .{ .per_note_management = .{ .note = 66, .reset_controllers = true, .detach_controllers = true } } },
    };

    for (messages) |message| {
        const packet = try message.packet();
        try std.testing.expectEqual(ump.MessageType.midi2_channel_voice, packet.messageType().?);
        try std.testing.expectEqualDeep(message, try ChannelMessage.parse(packet));
    }
}

test "MIDI 2 channel parser rejects reserved and malformed fields" {
    try std.testing.expectError(
        error.NotMidi2ChannelVoiceUmp,
        ChannelMessage.parse(try ump.Packet.init(&.{0x2090_3C7F})),
    );
    try std.testing.expectError(
        error.ReservedMidi2Status,
        ChannelMessage.parse(try ump.Packet.init(&.{ 0x4070_0000, 0 })),
    );
    try std.testing.expectError(
        error.InvalidMidi2ReservedField,
        ChannelMessage.parse(try ump.Packet.init(&.{ 0x40B0_4A01, 0 })),
    );
    try std.testing.expectError(
        error.InvalidMidi2DataByte,
        ChannelMessage.parse(try ump.Packet.init(&.{ 0x40A0_8000, 0 })),
    );
    try std.testing.expectError(
        error.InvalidMidi2ReservedField,
        ChannelMessage.parse(try ump.Packet.init(&.{ 0x40C0_0002, 0 })),
    );
    try std.testing.expectError(
        error.InvalidMidi2ReservedField,
        ChannelMessage.parse(try ump.Packet.init(&.{ 0x40F0_3C04, 0 })),
    );
    const reserved = ChannelMessage{
        .group = 0,
        .channel = 0,
        .payload = .{ .reserved = {} },
    };
    try std.testing.expectError(error.ReservedMidi2Status, reserved.packet());
}

test "MIDI 2 known note attributes classify without rejecting extensions" {
    const known = Note{
        .note = 60,
        .attribute = @intFromEnum(NoteAttribute.pitch_7_9),
        .velocity = 0,
        .attribute_data = 0,
    };
    try std.testing.expectEqual(NoteAttribute.pitch_7_9, known.knownAttribute().?);
    var extension = known;
    extension.attribute = 0x7F;
    try std.testing.expect(extension.knownAttribute() == null);
}
