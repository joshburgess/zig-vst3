const std = @import("std");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const segmented = @import("midi_segmented.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Metadata = struct {
    group: u4,
    mds_id: u4,
    chunk_count: u16,
    chunk_number: u16,
    manufacturer_id: u16,
    device_id: u16,
    sub_id_1: u16,
    sub_id_2: u16,

    pub fn valid(self: Metadata) bool {
        if (self.chunk_number == 0) return true;
        return self.chunk_count == 0 or self.chunk_number <= self.chunk_count;
    }
};

pub const Header = struct {
    metadata: Metadata,
    valid_byte_count: u16,

    pub fn valid(self: Header) bool {
        return self.metadata.valid() and self.valid_byte_count >= 16;
    }

    pub fn payloadByteCount(self: Header) ?u16 {
        if (!self.valid()) return null;
        return self.valid_byte_count - 16;
    }

    pub fn packet(self: Header) !ump.Packet {
        if (!self.valid()) return error.InvalidMixedDataHeader;
        return ump.Packet.init(&.{
            (@as(u32, 0x5) << 28) |
                (@as(u32, self.metadata.group) << 24) |
                (@as(u32, 0x8) << 20) |
                (@as(u32, self.metadata.mds_id) << 16) |
                self.valid_byte_count,
            (@as(u32, self.metadata.chunk_count) << 16) |
                self.metadata.chunk_number,
            (@as(u32, self.metadata.manufacturer_id) << 16) |
                self.metadata.device_id,
            (@as(u32, self.metadata.sub_id_1) << 16) |
                self.metadata.sub_id_2,
        });
    }

    pub fn parse(ump_packet: ump.Packet) !Header {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .data128) return error.NotData128Ump;
        if (((ump_packet.storage[0] >> 20) & 0x0F) != 0x8)
            return error.NotMixedDataHeader;
        const header = Header{
            .metadata = .{
                .group = @intCast((ump_packet.storage[0] >> 24) & 0x0F),
                .mds_id = @intCast((ump_packet.storage[0] >> 16) & 0x0F),
                .chunk_count = @intCast(ump_packet.storage[1] >> 16),
                .chunk_number = @truncate(ump_packet.storage[1]),
                .manufacturer_id = @intCast(ump_packet.storage[2] >> 16),
                .device_id = @truncate(ump_packet.storage[2]),
                .sub_id_1 = @intCast(ump_packet.storage[3] >> 16),
                .sub_id_2 = @truncate(ump_packet.storage[3]),
            },
            .valid_byte_count = @truncate(ump_packet.storage[0]),
        };
        if (!header.valid()) return error.InvalidMixedDataHeader;
        return header;
    }
};

pub const Payload = struct {
    group: u4,
    mds_id: u4,
    storage: [14]u8 = .{0} ** 14,
    count: u4 = 0,

    pub fn init(group: u4, mds_id: u4, bytes: []const u8) !Payload {
        if (bytes.len > 14) return error.MixedDataPayloadTooLarge;
        var payload = Payload{
            .group = group,
            .mds_id = mds_id,
            .count = @intCast(bytes.len),
        };
        @memcpy(payload.storage[0..bytes.len], bytes);
        return payload;
    }

    pub fn data(self: *const Payload) []const u8 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: Payload) bool {
        if (self.count > 14) return false;
        for (self.storage[self.count..]) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    pub fn packet(self: Payload) !ump.Packet {
        if (!self.valid()) return error.InvalidMixedDataPayload;
        var words = [_]u32{0} ** 4;
        setByte(&words, 0, 0x50 | @as(u8, self.group));
        setByte(&words, 1, 0x90 | @as(u8, self.mds_id));
        for (self.storage[0..self.count], 0..) |byte, index|
            setByte(&words, 2 + index, byte);
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet, expected_count: u4) !Payload {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .data128) return error.NotData128Ump;
        if (((ump_packet.storage[0] >> 20) & 0x0F) != 0x9)
            return error.NotMixedDataPayload;
        if (expected_count > 14) return error.InvalidMixedDataPayloadCount;

        var payload = Payload{
            .group = @intCast((ump_packet.storage[0] >> 24) & 0x0F),
            .mds_id = @intCast((ump_packet.storage[0] >> 16) & 0x0F),
            .count = expected_count,
        };
        for (payload.storage[0..expected_count], 0..) |*destination, index|
            destination.* = byteAt(ump_packet, 2 + index);
        for (expected_count..14) |index| {
            if (byteAt(ump_packet, 2 + index) != 0)
                return error.InvalidMixedDataPadding;
        }
        return payload;
    }
};

pub const Packetizer = struct {
    header: Header,
    source: []const u8,
    cursor: usize = 0,
    emitted_header: bool = false,

    pub fn init(metadata: Metadata, source: []const u8) !Packetizer {
        if (!metadata.valid()) return error.InvalidMixedDataHeader;
        if (source.len > std.math.maxInt(u16) - 16)
            return error.MixedDataChunkTooLarge;
        return .{
            .header = .{
                .metadata = metadata,
                .valid_byte_count = @intCast(16 + source.len),
            },
            .source = source,
        };
    }

    pub fn valid(self: *const Packetizer) bool {
        const payload_bytes = self.header.payloadByteCount() orelse return false;
        if (payload_bytes != self.source.len or self.cursor > self.source.len)
            return false;
        return self.emitted_header or self.cursor == 0;
    }

    pub fn next(self: *Packetizer) !?ump.Packet {
        if (!self.valid()) return error.InvalidMixedDataPacketizerState;
        if (!self.emitted_header) {
            self.emitted_header = true;
            return try self.header.packet();
        }
        if (self.cursor == self.source.len) return null;

        const end = segmented.payloadEnd(
            self.source.len,
            self.cursor,
            14,
        );
        const packet = try (try Payload.init(
            self.header.metadata.group,
            self.header.metadata.mds_id,
            self.source[self.cursor..end],
        )).packet();
        self.cursor = end;
        return packet;
    }

    pub fn reset(self: *Packetizer) void {
        self.cursor = 0;
        self.emitted_header = false;
    }
};

pub fn Reassembler(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = @splat(0),
        count: usize = 0,
        header: ?Header = null,
        active: bool = false,
        completed: bool = false,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn valid(self: *const Self) bool {
            if (!segmented.reassemblyStateValid(
                self.count,
                capacity,
                self.active,
                self.completed,
                self.header != null,
                self.header == null,
            )) return false;
            if (self.header) |header| {
                const expected = header.payloadByteCount() orelse return false;
                if (self.count > expected) return false;
                if (self.completed != (self.count == expected)) return false;
            }
            return true;
        }

        pub fn bytes(self: *const Self) ?[]const u8 {
            if (!self.valid() or !self.completed) return null;
            return self.storage[0..self.count];
        }

        pub fn push(self: *Self, ump_packet: ump.Packet) !bool {
            if (!self.valid()) return error.InvalidMixedDataReassemblerState;
            if (!ump_packet.valid()) return error.InvalidUmpPacket;
            const message_type = ump_packet.messageType() orelse
                return error.InvalidUmpPacket;
            if (message_type != .data128) return error.NotData128Ump;
            return switch ((ump_packet.storage[0] >> 20) & 0x0F) {
                0x8 => try self.acceptHeader(try Header.parse(ump_packet)),
                0x9 => try self.acceptPayload(ump_packet),
                else => error.NotMixedDataPacket,
            };
        }

        fn acceptHeader(self: *Self, header: Header) !bool {
            if (self.active) return error.UnexpectedMixedDataHeader;
            const expected: usize = header.payloadByteCount() orelse
                return error.InvalidMixedDataHeader;
            if (expected > capacity) return error.MixedDataCapacityExceeded;
            @memset(&self.storage, 0);
            self.count = 0;
            self.header = header;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                expected == 0,
            );
        }

        fn acceptPayload(self: *Self, ump_packet: ump.Packet) !bool {
            if (!self.active) return error.UnexpectedMixedDataPayload;
            const header = self.header orelse
                return error.InvalidMixedDataReassemblerState;
            const expected: usize = header.payloadByteCount() orelse
                return error.InvalidMixedDataReassemblerState;
            if (self.count > expected)
                return error.InvalidMixedDataReassemblerState;
            const remaining = expected - self.count;
            const packet_count: u4 = @intCast(@min(remaining, 14));
            const payload = try Payload.parse(ump_packet, packet_count);
            if (payload.group != header.metadata.group)
                return error.MixedDataGroupMismatch;
            if (payload.mds_id != header.metadata.mds_id)
                return error.MixedDataIdMismatch;

            if (!segmented.append(
                u8,
                self.storage[0..],
                &self.count,
                payload.data(),
            )) return error.MixedDataCapacityExceeded;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                self.count == expected,
            );
        }
    };
}

test "Mixed Data Set chunks round trip every payload boundary" {
    var source: [128]u8 = undefined;
    for (&source, 0..) |*byte, index| byte.* = @intCast(index);
    const metadata = Metadata{
        .group = 4,
        .mds_id = 7,
        .chunk_count = 3,
        .chunk_number = 2,
        .manufacturer_id = 0x007D,
        .device_id = 0xFFFF,
        .sub_id_1 = 0x1234,
        .sub_id_2 = 0xABCD,
    };
    const Assembler = Reassembler(source.len);

    for (0..source.len + 1) |length| {
        var packetizer = try Packetizer.init(metadata, source[0..length]);
        var assembler = Assembler{};
        while (try packetizer.next()) |packet| _ = try assembler.push(packet);
        try std.testing.expectEqualDeep(metadata, assembler.header.?.metadata);
        try std.testing.expectEqualSlices(u8, source[0..length], assembler.bytes().?);
        for (assembler.storage[length..]) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
        assembler.reset();
        for (assembler.storage) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "Mixed Data Set packets use canonical wire fields" {
    const metadata = Metadata{
        .group = 4,
        .mds_id = 7,
        .chunk_count = 3,
        .chunk_number = 2,
        .manufacturer_id = 0x007D,
        .device_id = 0xFFFF,
        .sub_id_1 = 0x1234,
        .sub_id_2 = 0xABCD,
    };
    var packetizer = try Packetizer.init(metadata, "mixed payload");
    packetizer.header.valid_byte_count += 1;
    try std.testing.expect(!packetizer.valid());
    try std.testing.expectError(
        error.InvalidMixedDataPacketizerState,
        packetizer.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), packetizer.cursor);
    try std.testing.expect(!packetizer.emitted_header);
    packetizer.header.valid_byte_count -= 1;
    try std.testing.expect(packetizer.valid());
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x5487_001D, 0x0003_0002, 0x007D_FFFF, 0x1234_ABCD },
        (try packetizer.next()).?.words(),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x5497_6D69, 0x7865_6420, 0x7061_796C, 0x6F61_6400 },
        (try packetizer.next()).?.words(),
    );
    try std.testing.expect((try packetizer.next()) == null);
}

test "Mixed Data Set reassembly rejects malformed transitions transactionally" {
    const metadata = Metadata{
        .group = 4,
        .mds_id = 7,
        .chunk_count = 1,
        .chunk_number = 1,
        .manufacturer_id = 0x007D,
        .device_id = 0xFFFF,
        .sub_id_1 = 1,
        .sub_id_2 = 2,
    };
    try std.testing.expectError(
        error.InvalidMixedDataHeader,
        (Header{ .metadata = metadata, .valid_byte_count = 15 }).packet(),
    );
    try std.testing.expectError(
        error.InvalidMixedDataHeader,
        Packetizer.init(.{
            .group = 0,
            .mds_id = 0,
            .chunk_count = 2,
            .chunk_number = 3,
            .manufacturer_id = 0,
            .device_id = 0,
            .sub_id_1 = 0,
            .sub_id_2 = 0,
        }, "x"),
    );

    const Assembler = Reassembler(32);
    var assembler = Assembler{};
    var packetizer = try Packetizer.init(metadata, "abcdefghijklmnop");
    _ = try assembler.push((try packetizer.next()).?);
    _ = try assembler.push((try packetizer.next()).?);
    const before = assembler;
    const wrong = try (try Payload.init(4, 6, "op")).packet();
    try std.testing.expectError(error.MixedDataIdMismatch, assembler.push(wrong));
    try std.testing.expectEqualDeep(before, assembler);
    try std.testing.expect(try assembler.push((try packetizer.next()).?));
    try std.testing.expectEqualStrings("abcdefghijklmnop", assembler.bytes().?);
}
