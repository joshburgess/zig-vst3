const std = @import("std");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Status = enum(u8) {
    endpoint_discovery = 0x00,
    endpoint_info = 0x01,
    device_identity = 0x02,
    stream_configuration_request = 0x05,
    stream_configuration_notification = 0x06,
    function_block_discovery = 0x10,
    function_block_info = 0x11,
    start_of_clip = 0x20,
    end_of_clip = 0x21,
};

pub const Protocol = enum(u8) {
    midi1 = 0x01,
    midi2 = 0x02,
};

pub const StreamConfiguration = struct {
    protocol: Protocol,
    transmit_jr_timestamps: bool = false,
    receive_jr_timestamps: bool = false,
};

pub const EndpointDiscovery = struct {
    version_major: u8,
    version_minor: u8,
    filter: u5,
};

pub const EndpointInfo = struct {
    version_major: u8,
    version_minor: u8,
    function_block_count: u6,
    static_function_blocks: bool,
    supports_midi1: bool,
    supports_midi2: bool,
    supports_receive_jr: bool,
    supports_transmit_jr: bool,

    pub fn valid(self: EndpointInfo) bool {
        return self.function_block_count <= 32;
    }
};

pub const DeviceIdentity = struct {
    manufacturer: [3]u7,
    family: [2]u7,
    model: [2]u7,
    revision: [4]u7,
};

pub const FunctionBlockSelector = union(enum) {
    one: u5,
    all,

    fn wireValue(self: FunctionBlockSelector) u8 {
        return switch (self) {
            .one => |block| block,
            .all => 0xFF,
        };
    }

    fn parse(value: u8) !FunctionBlockSelector {
        return switch (value) {
            0...31 => .{ .one = @intCast(value) },
            0xFF => .all,
            else => error.InvalidFunctionBlockSelector,
        };
    }
};

pub const FunctionBlockDiscovery = struct {
    selector: FunctionBlockSelector,
    filter: u2,
};

pub const Direction = enum(u2) {
    unknown,
    receiver,
    sender,
    bidirectional,
};

pub const UiHint = enum(u2) {
    unknown,
    receiver,
    sender,
    bidirectional,
};

pub const Midi1Proxy = enum(u2) {
    inapplicable,
    unrestricted_bandwidth,
    restricted_bandwidth,
    reserved,
};

pub const FunctionBlockInfo = struct {
    block: u5,
    enabled: bool,
    ui_hint: UiHint,
    midi1_proxy: Midi1Proxy,
    direction: Direction,
    first_group: u4,
    group_count: u5,
    ci_version: u8,
    max_sysex8_streams: u8,

    pub fn valid(self: FunctionBlockInfo) bool {
        if (self.direction == .unknown) return false;
        if (self.midi1_proxy == .reserved) return false;
        if (self.group_count == 0 or self.group_count > 16) return false;
        if (self.midi1_proxy != .inapplicable and self.group_count != 1) return false;
        return @as(u6, self.first_group) + self.group_count <= 16;
    }
};

pub const Payload = union(Status) {
    endpoint_discovery: EndpointDiscovery,
    endpoint_info: EndpointInfo,
    device_identity: DeviceIdentity,
    stream_configuration_request: StreamConfiguration,
    stream_configuration_notification: StreamConfiguration,
    function_block_discovery: FunctionBlockDiscovery,
    function_block_info: FunctionBlockInfo,
    start_of_clip: void,
    end_of_clip: void,
};

pub const Message = struct {
    payload: Payload,

    pub fn packet(self: Message) !ump.Packet {
        var words = [_]u32{0} ** 4;
        setByte(&words, 0, 0xF0);
        setByte(&words, 1, @intFromEnum(std.meta.activeTag(self.payload)));
        switch (self.payload) {
            .endpoint_discovery => |value| {
                setByte(&words, 2, value.version_major);
                setByte(&words, 3, value.version_minor);
                setByte(&words, 7, value.filter);
            },
            .endpoint_info => |value| {
                if (!value.valid()) return error.InvalidEndpointInfo;
                setByte(&words, 2, value.version_major);
                setByte(&words, 3, value.version_minor);
                setByte(
                    &words,
                    4,
                    @as(u8, value.function_block_count) |
                        @as(u8, if (value.static_function_blocks) 0x80 else 0),
                );
                setByte(
                    &words,
                    6,
                    @as(u8, @intFromBool(value.supports_midi1)) |
                        (@as(u8, @intFromBool(value.supports_midi2)) << 1),
                );
                setByte(
                    &words,
                    7,
                    @as(u8, @intFromBool(value.supports_transmit_jr)) |
                        (@as(u8, @intFromBool(value.supports_receive_jr)) << 1),
                );
            },
            .device_identity => |value| {
                for (value.manufacturer, 0..) |byte, index| setByte(&words, index + 5, byte);
                for (value.family, 0..) |byte, index| setByte(&words, index + 8, byte);
                for (value.model, 0..) |byte, index| setByte(&words, index + 10, byte);
                for (value.revision, 0..) |byte, index| setByte(&words, index + 12, byte);
            },
            .stream_configuration_request,
            .stream_configuration_notification,
            => |value| writeStreamConfiguration(&words, value),
            .function_block_discovery => |value| {
                setByte(&words, 2, value.selector.wireValue());
                setByte(&words, 3, value.filter);
            },
            .function_block_info => |value| {
                if (!value.valid()) return error.InvalidFunctionBlockInfo;
                setByte(
                    &words,
                    2,
                    @as(u8, value.block) | @as(u8, if (value.enabled) 0x80 else 0),
                );
                setByte(
                    &words,
                    3,
                    (@as(u8, @intFromEnum(value.ui_hint)) << 4) |
                        (@as(u8, @intFromEnum(value.midi1_proxy)) << 2) |
                        @as(u8, @intFromEnum(value.direction)),
                );
                setByte(&words, 4, value.first_group);
                setByte(&words, 5, value.group_count);
                setByte(&words, 6, value.ci_version);
                setByte(&words, 7, value.max_sysex8_streams);
            },
            .start_of_clip, .end_of_clip => {},
        }
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet) !Message {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .stream) return error.NotStreamUmp;
        if ((byteAt(ump_packet, 0) & 0x0F) != 0) return error.UnsupportedStreamPacketFormat;

        const status = statusFromByte(byteAt(ump_packet, 1)) orelse
            return error.UnsupportedStreamStatus;
        const payload: Payload = switch (status) {
            .endpoint_discovery => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1, 2, 3, 7 });
                const filter = byteAt(ump_packet, 7);
                if ((filter & 0xE0) != 0) return error.InvalidStreamReservedField;
                break :blk .{ .endpoint_discovery = .{
                    .version_major = byteAt(ump_packet, 2),
                    .version_minor = byteAt(ump_packet, 3),
                    .filter = @intCast(filter),
                } };
            },
            .endpoint_info => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1, 2, 3, 4, 6, 7 });
                const protocol_flags = byteAt(ump_packet, 6);
                const jr_flags = byteAt(ump_packet, 7);
                if ((protocol_flags & 0xFC) != 0 or (jr_flags & 0xFC) != 0)
                    return error.InvalidStreamReservedField;
                const count_and_static = byteAt(ump_packet, 4);
                if ((count_and_static & 0x7F) > 32) return error.InvalidEndpointInfo;
                const value = EndpointInfo{
                    .version_major = byteAt(ump_packet, 2),
                    .version_minor = byteAt(ump_packet, 3),
                    .function_block_count = @intCast(count_and_static & 0x7F),
                    .static_function_blocks = (count_and_static & 0x80) != 0,
                    .supports_midi1 = (protocol_flags & 1) != 0,
                    .supports_midi2 = (protocol_flags & 2) != 0,
                    .supports_transmit_jr = (jr_flags & 1) != 0,
                    .supports_receive_jr = (jr_flags & 2) != 0,
                };
                if (!value.valid()) return error.InvalidEndpointInfo;
                break :blk .{ .endpoint_info = value };
            },
            .device_identity => blk: {
                try expectZeroExcept(
                    ump_packet,
                    &.{ 0, 1, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 },
                );
                var value: DeviceIdentity = undefined;
                for (&value.manufacturer, 0..) |*byte, index|
                    byte.* = try dataByte(byteAt(ump_packet, index + 5));
                for (&value.family, 0..) |*byte, index|
                    byte.* = try dataByte(byteAt(ump_packet, index + 8));
                for (&value.model, 0..) |*byte, index|
                    byte.* = try dataByte(byteAt(ump_packet, index + 10));
                for (&value.revision, 0..) |*byte, index|
                    byte.* = try dataByte(byteAt(ump_packet, index + 12));
                break :blk .{ .device_identity = value };
            },
            .stream_configuration_request,
            .stream_configuration_notification,
            => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1, 2, 3 });
                const configuration = try parseStreamConfiguration(ump_packet);
                break :blk if (status == .stream_configuration_request)
                    .{ .stream_configuration_request = configuration }
                else
                    .{ .stream_configuration_notification = configuration };
            },
            .function_block_discovery => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1, 2, 3 });
                const block = byteAt(ump_packet, 2);
                const filter = byteAt(ump_packet, 3);
                if (filter > 3) return error.InvalidStreamReservedField;
                break :blk .{ .function_block_discovery = .{
                    .selector = try FunctionBlockSelector.parse(block),
                    .filter = @intCast(filter),
                } };
            },
            .function_block_info => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1, 2, 3, 4, 5, 6, 7 });
                const block_and_enabled = byteAt(ump_packet, 2);
                const flags = byteAt(ump_packet, 3);
                if ((flags & 0xC0) != 0) return error.InvalidStreamReservedField;
                if ((block_and_enabled & 0x7F) > 31)
                    return error.InvalidFunctionBlockInfo;
                const first_group = byteAt(ump_packet, 4);
                const group_count = byteAt(ump_packet, 5);
                if (first_group > 15 or group_count > 31)
                    return error.InvalidFunctionBlockInfo;
                const value = FunctionBlockInfo{
                    .block = @intCast(block_and_enabled & 0x7F),
                    .enabled = (block_and_enabled & 0x80) != 0,
                    .ui_hint = @enumFromInt((flags >> 4) & 3),
                    .midi1_proxy = @enumFromInt((flags >> 2) & 3),
                    .direction = @enumFromInt(flags & 3),
                    .first_group = @intCast(first_group),
                    .group_count = @intCast(group_count),
                    .ci_version = byteAt(ump_packet, 6),
                    .max_sysex8_streams = byteAt(ump_packet, 7),
                };
                if (!value.valid()) return error.InvalidFunctionBlockInfo;
                break :blk .{ .function_block_info = value };
            },
            .start_of_clip, .end_of_clip => blk: {
                try expectZeroExcept(ump_packet, &.{ 0, 1 });
                break :blk if (status == .start_of_clip)
                    .{ .start_of_clip = {} }
                else
                    .{ .end_of_clip = {} };
            },
        };
        return .{ .payload = payload };
    }
};

fn writeStreamConfiguration(words: *[4]u32, value: StreamConfiguration) void {
    setByte(words, 2, @intFromEnum(value.protocol));
    setByte(
        words,
        3,
        @as(u8, @intFromBool(value.transmit_jr_timestamps)) |
            (@as(u8, @intFromBool(value.receive_jr_timestamps)) << 1),
    );
}

fn parseStreamConfiguration(ump_packet: ump.Packet) !StreamConfiguration {
    const protocol: Protocol = switch (byteAt(ump_packet, 2)) {
        1 => .midi1,
        2 => .midi2,
        else => return error.InvalidStreamProtocol,
    };
    const flags = byteAt(ump_packet, 3);
    if ((flags & 0xFC) != 0) return error.InvalidStreamReservedField;
    return .{
        .protocol = protocol,
        .transmit_jr_timestamps = (flags & 1) != 0,
        .receive_jr_timestamps = (flags & 2) != 0,
    };
}

fn statusFromByte(value: u8) ?Status {
    return switch (value) {
        0x00 => .endpoint_discovery,
        0x01 => .endpoint_info,
        0x02 => .device_identity,
        0x05 => .stream_configuration_request,
        0x06 => .stream_configuration_notification,
        0x10 => .function_block_discovery,
        0x11 => .function_block_info,
        0x20 => .start_of_clip,
        0x21 => .end_of_clip,
        else => null,
    };
}

fn dataByte(value: u8) !u7 {
    if (value > 127) return error.InvalidStreamDataByte;
    return @intCast(value);
}

fn expectZeroExcept(ump_packet: ump.Packet, used: []const u8) !void {
    for (0..16) |index| {
        var is_used = false;
        for (used) |candidate| {
            if (index == candidate) {
                is_used = true;
                break;
            }
        }
        if (!is_used and byteAt(ump_packet, index) != 0)
            return error.InvalidStreamReservedField;
    }
}

test "fixed stream messages round trip every supported status" {
    const messages = [_]Message{
        .{ .payload = .{ .endpoint_discovery = .{
            .version_major = 1,
            .version_minor = 2,
            .filter = 0x1F,
        } } },
        .{ .payload = .{ .endpoint_info = .{
            .version_major = 1,
            .version_minor = 2,
            .function_block_count = 3,
            .static_function_blocks = true,
            .supports_midi1 = true,
            .supports_midi2 = true,
            .supports_receive_jr = true,
            .supports_transmit_jr = false,
        } } },
        .{ .payload = .{ .device_identity = .{
            .manufacturer = .{ 1, 2, 3 },
            .family = .{ 4, 5 },
            .model = .{ 6, 7 },
            .revision = .{ 8, 9, 10, 11 },
        } } },
        .{ .payload = .{ .stream_configuration_request = .{
            .protocol = .midi2,
            .transmit_jr_timestamps = true,
            .receive_jr_timestamps = true,
        } } },
        .{ .payload = .{ .stream_configuration_notification = .{
            .protocol = .midi1,
        } } },
        .{ .payload = .{ .function_block_discovery = .{
            .selector = .{ .one = 12 },
            .filter = 3,
        } } },
        .{ .payload = .{ .function_block_info = .{
            .block = 12,
            .enabled = true,
            .ui_hint = .sender,
            .midi1_proxy = .inapplicable,
            .direction = .bidirectional,
            .first_group = 4,
            .group_count = 6,
            .ci_version = 2,
            .max_sysex8_streams = 8,
        } } },
        .{ .payload = .{ .start_of_clip = {} } },
        .{ .payload = .{ .end_of_clip = {} } },
    };
    for (messages) |message| {
        try std.testing.expectEqualDeep(message, try Message.parse(try message.packet()));
    }
}

test "fixed stream messages use canonical wire fields" {
    const packet = try (Message{ .payload = .{ .stream_configuration_request = .{
        .protocol = .midi2,
        .transmit_jr_timestamps = true,
        .receive_jr_timestamps = false,
    } } }).packet();
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xF005_0201, 0, 0, 0 },
        packet.words(),
    );
}

test "fixed stream parser rejects malformed fields" {
    try std.testing.expectError(
        error.NotStreamUmp,
        Message.parse(try ump.Packet.init(&.{0x10F8_0000})),
    );
    try std.testing.expectError(
        error.UnsupportedStreamPacketFormat,
        Message.parse(try ump.Packet.init(&.{ 0xF400_0000, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.UnsupportedStreamStatus,
        Message.parse(try ump.Packet.init(&.{ 0xF07F_0000, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidStreamReservedField,
        Message.parse(try ump.Packet.init(&.{ 0xF000_0100, 0x0100_0000, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidStreamProtocol,
        Message.parse(try ump.Packet.init(&.{ 0xF005_0300, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidEndpointInfo,
        Message.parse(try ump.Packet.init(&.{ 0xF001_0101, 0x2100_0000, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFunctionBlockSelector,
        Message.parse(try ump.Packet.init(&.{ 0xF010_2003, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidFunctionBlockInfo,
        Message.parse(try ump.Packet.init(&.{ 0xF011_A003, 0x0001_0000, 0, 0 })),
    );
    const invalid = Message{ .payload = .{ .function_block_info = .{
        .block = 0,
        .enabled = true,
        .ui_hint = .unknown,
        .midi1_proxy = .inapplicable,
        .direction = .bidirectional,
        .first_group = 15,
        .group_count = 2,
        .ci_version = 0,
        .max_sysex8_streams = 0,
    } } };
    try std.testing.expectError(error.InvalidFunctionBlockInfo, invalid.packet());
}

test "function block discovery supports one block or all blocks" {
    const messages = [_]Message{
        .{ .payload = .{ .function_block_discovery = .{
            .selector = .{ .one = 31 },
            .filter = 1,
        } } },
        .{ .payload = .{ .function_block_discovery = .{
            .selector = .all,
            .filter = 2,
        } } },
    };
    for (messages) |message| {
        try std.testing.expectEqualDeep(message, try Message.parse(try message.packet()));
    }
}
