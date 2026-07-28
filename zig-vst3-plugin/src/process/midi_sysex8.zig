const std = @import("std");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const sysex7 = @import("midi_sysex7.zig");
const segmented = @import("midi_segmented.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Kind = sysex7.Kind;

pub const Chunk = struct {
    group: u4,
    kind: Kind,
    stream_id: u8,
    storage: [13]u8 = .{0} ** 13,
    count: u4 = 0,

    pub fn init(group: u8, kind: Kind, stream_id: u8, bytes: []const u8) !Chunk {
        if (group > 15) return error.InvalidUmpGroup;
        if (bytes.len > 13) return error.Sysex8ChunkTooLarge;
        var chunk = Chunk{
            .group = @intCast(group),
            .kind = kind,
            .stream_id = stream_id,
            .count = @intCast(bytes.len),
        };
        @memcpy(chunk.storage[0..bytes.len], bytes);
        return chunk;
    }

    pub fn data(self: *const Chunk) []const u8 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: Chunk) bool {
        if (self.count > self.storage.len) return false;
        for (self.storage[self.count..]) |value| {
            if (value != 0) return false;
        }
        return true;
    }

    pub fn packet(self: Chunk) !ump.Packet {
        if (!self.valid()) return error.InvalidSysex8Chunk;
        var words = [_]u32{0} ** 4;
        const byte1 = (@as(u8, @intFromEnum(self.kind)) << 4) | @as(u8, self.count);
        setByte(&words, 0, 0x50 | @as(u8, self.group));
        setByte(&words, 1, byte1);
        setByte(&words, 2, self.stream_id);
        for (self.storage, 0..) |value, index| setByte(&words, index + 3, value);
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet) !Chunk {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        if (ump_packet.messageType().? != .data128) return error.NotSysex8Ump;

        const status_and_count = byteAt(ump_packet, 1);
        const raw_kind = status_and_count >> 4;
        if (raw_kind > 3) return error.InvalidSysex8Kind;
        const count = status_and_count & 0x0F;
        if (count > 13) return error.Sysex8ChunkTooLarge;

        var chunk = Chunk{
            .group = @intCast((ump_packet.storage[0] >> 24) & 0x0F),
            .kind = @enumFromInt(raw_kind),
            .stream_id = byteAt(ump_packet, 2),
            .count = @intCast(count),
        };
        for (&chunk.storage, 0..) |*destination, index| {
            const value = byteAt(ump_packet, index + 3);
            if (index < count) {
                destination.* = value;
            } else if (value != 0) {
                return error.InvalidSysex8ReservedField;
            }
        }
        return chunk;
    }
};

pub const Packetizer = struct {
    group: u4,
    stream_id: u8,
    source: []const u8,
    cursor: usize = 0,
    emitted_empty: bool = false,

    pub fn init(group: u8, stream_id: u8, source: []const u8) !Packetizer {
        if (group > 15) return error.InvalidUmpGroup;
        return .{
            .group = @intCast(group),
            .stream_id = stream_id,
            .source = source,
        };
    }

    pub fn next(self: *Packetizer) !?ump.Packet {
        if (self.cursor > self.source.len) return error.InvalidSysex8PacketizerState;
        if (self.source.len == 0) {
            if (self.emitted_empty) return null;
            self.emitted_empty = true;
            return try (try Chunk.init(self.group, .complete, self.stream_id, &.{})).packet();
        }
        if (self.cursor == self.source.len) return null;

        const end = segmented.payloadEnd(
            self.source.len,
            self.cursor,
            13,
        );
        const kind = segmented.packetForm(
            Kind,
            self.source.len,
            self.cursor,
            end,
            13,
        );
        const packet = try (try Chunk.init(
            self.group,
            kind,
            self.stream_id,
            self.source[self.cursor..end],
        )).packet();
        self.cursor = end;
        return packet;
    }

    pub fn reset(self: *Packetizer) void {
        self.cursor = 0;
        self.emitted_empty = false;
    }
};

pub fn Reassembler(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = undefined,
        count: usize = 0,
        group: ?u4 = null,
        stream_id: ?u8 = null,
        active: bool = false,
        completed: bool = false,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn valid(self: *const Self) bool {
            return segmented.reassemblyStateValid(
                self.count,
                capacity,
                self.active,
                self.completed,
                self.group != null and self.stream_id != null,
                self.group == null and self.stream_id == null,
            );
        }

        pub fn message(self: *const Self) ?[]const u8 {
            if (!self.valid() or !self.completed) return null;
            return self.storage[0..self.count];
        }

        pub fn push(self: *Self, ump_packet: ump.Packet) !bool {
            if (!self.valid()) return error.InvalidSysex8ReassemblerState;
            const chunk = try Chunk.parse(ump_packet);
            return switch (chunk.kind) {
                .complete => try self.acceptInitial(chunk, true),
                .begin => try self.acceptInitial(chunk, false),
                .continuation => try self.acceptContinuation(chunk, false),
                .end => try self.acceptContinuation(chunk, true),
            };
        }

        fn acceptInitial(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (self.active) {
                return if (completes)
                    error.UnexpectedSysex8Complete
                else
                    error.UnexpectedSysex8Begin;
            }
            if (!segmented.replace(
                u8,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.Sysex8CapacityExceeded;
            self.group = chunk.group;
            self.stream_id = chunk.stream_id;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }

        fn acceptContinuation(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (!self.active) {
                return if (completes)
                    error.UnexpectedSysex8End
                else
                    error.UnexpectedSysex8Continuation;
            }
            if (self.group.? != chunk.group) return error.Sysex8GroupMismatch;
            if (self.stream_id.? != chunk.stream_id) return error.Sysex8StreamMismatch;
            if (!segmented.append(
                u8,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.Sysex8CapacityExceeded;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }
    };
}

test "SysEx8 chunks round trip every data byte" {
    const source = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 0x80, 0xFE, 0xFF, 11, 12 };
    const chunk = try Chunk.init(5, .continuation, 0xA5, &source);
    const packet = try chunk.packet();
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x552D_A500, 0x0102_0304, 0x0506_0780, 0xFEFF_0B0C },
        packet.words(),
    );
    try std.testing.expectEqualDeep(chunk, try Chunk.parse(packet));
}

test "SysEx8 packetizer and reassembler cover every boundary length" {
    var source: [80]u8 = undefined;
    for (&source, 0..) |*value, index| value.* = @intCast(index * 3);
    const Assembler = Reassembler(source.len);

    for (0..source.len + 1) |length| {
        var packetizer = try Packetizer.init(9, 0x42, source[0..length]);
        var assembler = Assembler{};
        var packet_count: usize = 0;
        while (try packetizer.next()) |packet| {
            packet_count += 1;
            _ = try assembler.push(packet);
        }
        try std.testing.expectEqual(@max(@as(usize, 1), (length + 12) / 13), packet_count);
        try std.testing.expectEqual(@as(?u4, 9), assembler.group);
        try std.testing.expectEqual(@as(?u8, 0x42), assembler.stream_id);
        try std.testing.expectEqualSlices(u8, source[0..length], assembler.message().?);
    }
}

test "SysEx8 rejects malformed chunks and sequences transactionally" {
    try std.testing.expectError(
        error.Sysex8ChunkTooLarge,
        Chunk.init(0, .complete, 0, &([_]u8{0} ** 14)),
    );
    try std.testing.expectError(
        error.InvalidSysex8Kind,
        Chunk.parse(try ump.Packet.init(&.{ 0x5040_0000, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidSysex8ReservedField,
        Chunk.parse(try ump.Packet.init(&.{ 0x5000_0000, 0x0100_0000, 0, 0 })),
    );

    const Assembler = Reassembler(14);
    var assembler = Assembler{};
    _ = try assembler.push(try (try Chunk.init(
        0,
        .begin,
        7,
        &([_]u8{1} ** 13),
    )).packet());
    const before = assembler;
    try std.testing.expectError(
        error.Sysex8StreamMismatch,
        assembler.push(try (try Chunk.init(0, .end, 8, &.{1})).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    try std.testing.expectError(
        error.Sysex8CapacityExceeded,
        assembler.push(try (try Chunk.init(0, .end, 7, &.{ 1, 2 })).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    try std.testing.expect(try assembler.push(
        try (try Chunk.init(0, .end, 7, &.{1})).packet(),
    ));
}
