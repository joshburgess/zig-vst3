const std = @import("std");
const ump = @import("midi_ump.zig");
const byteAt = @import("midi_ump_bytes.zig").byteAt;
const segmented = @import("midi_segmented.zig");

pub const Kind = enum(u2) {
    complete,
    begin,
    continuation,
    end,
};

pub const Chunk = struct {
    group: u4,
    kind: Kind,
    storage: [6]u7 = .{ 0, 0, 0, 0, 0, 0 },
    count: u3 = 0,

    pub fn init(group: u8, kind: Kind, bytes: []const u8) !Chunk {
        if (group > 15) return error.InvalidUmpGroup;
        if (bytes.len > 6) return error.Sysex7ChunkTooLarge;
        var chunk = Chunk{
            .group = @intCast(group),
            .kind = kind,
            .count = @intCast(bytes.len),
        };
        for (bytes, 0..) |value, index| {
            if (value > 127) return error.InvalidSysex7DataByte;
            chunk.storage[index] = @intCast(value);
        }
        return chunk;
    }

    pub fn data(self: *const Chunk) []const u7 {
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
        if (!self.valid()) return error.InvalidSysex7Chunk;
        const byte1 = (@as(u8, @intFromEnum(self.kind)) << 4) | @as(u8, self.count);
        var first = (@as(u32, 0x3) << 28) |
            (@as(u32, self.group) << 24) |
            (@as(u32, byte1) << 16);
        var second: u32 = 0;
        for (self.storage, 0..) |value, index| {
            if (index < 2) {
                first |= @as(u32, value) << @intCast(8 - index * 8);
            } else {
                second |= @as(u32, value) << @intCast(40 - index * 8);
            }
        }
        return ump.Packet.init(&.{ first, second });
    }

    pub fn parse(ump_packet: ump.Packet) !Chunk {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        if (ump_packet.messageType().? != .data64) return error.NotSysex7Ump;

        const status_and_count = byteAt(ump_packet, 1);
        const raw_kind = status_and_count >> 4;
        if (raw_kind > 3) return error.InvalidSysex7Kind;
        const count = status_and_count & 0x0F;
        if (count > 6) return error.Sysex7ChunkTooLarge;

        var chunk = Chunk{
            .group = @intCast((ump_packet.storage[0] >> 24) & 0x0F),
            .kind = @enumFromInt(raw_kind),
            .count = @intCast(count),
        };
        for (&chunk.storage, 0..) |*destination, index| {
            const value = byteAt(ump_packet, index + 2);
            if (index < count) {
                if (value > 127) return error.InvalidSysex7DataByte;
                destination.* = @intCast(value);
            } else if (value != 0) {
                return error.InvalidSysex7ReservedField;
            }
        }
        return chunk;
    }
};

pub const Packetizer = struct {
    group: u4,
    source: []const u8,
    cursor: usize = 0,
    emitted_empty: bool = false,

    pub fn init(group: u8, source: []const u8) !Packetizer {
        if (group > 15) return error.InvalidUmpGroup;
        for (source) |value| {
            if (value > 127) return error.InvalidSysex7DataByte;
        }
        return .{ .group = @intCast(group), .source = source };
    }

    pub fn next(self: *Packetizer) !?ump.Packet {
        if (self.cursor > self.source.len) return error.InvalidSysex7PacketizerState;
        if (self.source.len == 0) {
            if (self.emitted_empty) return null;
            self.emitted_empty = true;
            return try (try Chunk.init(self.group, .complete, &.{})).packet();
        }
        if (self.cursor == self.source.len) return null;

        const end = segmented.payloadEnd(
            self.source.len,
            self.cursor,
            6,
        );
        const kind = segmented.packetForm(
            Kind,
            self.source.len,
            self.cursor,
            end,
            6,
        );
        const packet = try (try Chunk.init(
            self.group,
            kind,
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

        storage: [capacity]u7 = undefined,
        count: usize = 0,
        group: ?u4 = null,
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
                self.group != null,
                self.group == null,
            );
        }

        pub fn message(self: *const Self) ?[]const u7 {
            if (!self.valid() or !self.completed) return null;
            return self.storage[0..self.count];
        }

        pub fn push(self: *Self, ump_packet: ump.Packet) !bool {
            if (!self.valid()) return error.InvalidSysex7ReassemblerState;
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
                    error.UnexpectedSysex7Complete
                else
                    error.UnexpectedSysex7Begin;
            }
            if (!segmented.replace(
                u7,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.Sysex7CapacityExceeded;
            self.group = chunk.group;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }

        fn acceptContinuation(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (!self.active) {
                return if (completes)
                    error.UnexpectedSysex7End
                else
                    error.UnexpectedSysex7Continuation;
            }
            if (self.group.? != chunk.group) return error.Sysex7GroupMismatch;
            if (!segmented.append(
                u7,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.Sysex7CapacityExceeded;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }
    };
}

test "SysEx7 chunks round trip packet fields" {
    const chunk = try Chunk.init(5, .continuation, &.{ 1, 2, 3, 4, 5, 6 });
    const packet = try chunk.packet();
    try std.testing.expectEqualSlices(u32, &.{ 0x3526_0102, 0x0304_0506 }, packet.words());
    try std.testing.expectEqualDeep(chunk, try Chunk.parse(packet));

    const short = try Chunk.init(15, .complete, &.{ 0x7F, 0x01 });
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x3F02_7F01, 0 },
        (try short.packet()).words(),
    );
}

test "SysEx7 packetizer and reassembler cover every boundary length" {
    var source: [64]u8 = undefined;
    var expected: [64]u7 = undefined;
    for (&source, &expected, 0..) |*source_value, *expected_value, index| {
        source_value.* = @intCast(index);
        expected_value.* = @intCast(index);
    }
    const Assembler = Reassembler(64);

    for (0..source.len + 1) |length| {
        var packetizer = try Packetizer.init(9, source[0..length]);
        var assembler = Assembler{};
        var packet_count: usize = 0;
        while (try packetizer.next()) |packet| {
            packet_count += 1;
            _ = try assembler.push(packet);
        }
        try std.testing.expectEqual(@max(@as(usize, 1), (length + 5) / 6), packet_count);
        try std.testing.expectEqual(@as(?u4, 9), assembler.group);
        try std.testing.expectEqualSlices(u7, expected[0..length], assembler.message().?);
        packetizer.reset();
        try std.testing.expect((try packetizer.next()) != null);
    }
}

test "SysEx7 rejects malformed chunks and sequences transactionally" {
    try std.testing.expectError(
        error.InvalidSysex7DataByte,
        Chunk.init(0, .complete, &.{128}),
    );
    try std.testing.expectError(
        error.Sysex7ChunkTooLarge,
        Chunk.init(0, .complete, &.{ 1, 2, 3, 4, 5, 6, 7 }),
    );
    try std.testing.expectError(
        error.InvalidSysex7Kind,
        Chunk.parse(try ump.Packet.init(&.{ 0x3040_0000, 0 })),
    );
    try std.testing.expectError(
        error.Sysex7ChunkTooLarge,
        Chunk.parse(try ump.Packet.init(&.{ 0x3007_0000, 0 })),
    );
    try std.testing.expectError(
        error.InvalidSysex7ReservedField,
        Chunk.parse(try ump.Packet.init(&.{ 0x3001_0102, 0 })),
    );

    const Assembler = Reassembler(7);
    var assembler = Assembler{};
    try std.testing.expectError(
        error.UnexpectedSysex7Continuation,
        assembler.push(try (try Chunk.init(0, .continuation, &.{1})).packet()),
    );
    _ = try assembler.push(try (try Chunk.init(0, .begin, &.{ 1, 2, 3, 4, 5, 6 })).packet());
    const before = assembler;
    try std.testing.expectError(
        error.Sysex7GroupMismatch,
        assembler.push(try (try Chunk.init(1, .end, &.{7})).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    try std.testing.expectError(
        error.Sysex7CapacityExceeded,
        assembler.push(try (try Chunk.init(0, .end, &.{ 7, 8 })).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    try std.testing.expect(try assembler.push(
        try (try Chunk.init(0, .end, &.{7})).packet(),
    ));
    try std.testing.expectEqualSlices(u7, &.{ 1, 2, 3, 4, 5, 6, 7 }, assembler.message().?);

    assembler.count = 8;
    try std.testing.expect(!assembler.valid());
    try std.testing.expect(assembler.message() == null);
    try std.testing.expectError(
        error.InvalidSysex7ReassemblerState,
        assembler.push(try (try Chunk.init(0, .complete, &.{})).packet()),
    );
    assembler.reset();
    try std.testing.expect(assembler.valid());
}

test "SysEx7 packetizer rejects malformed input and retained cursors" {
    try std.testing.expectError(error.InvalidUmpGroup, Packetizer.init(16, &.{}));
    try std.testing.expectError(error.InvalidSysex7DataByte, Packetizer.init(0, &.{128}));

    var packetizer = try Packetizer.init(0, &.{ 1, 2, 3 });
    packetizer.cursor = 4;
    try std.testing.expectError(error.InvalidSysex7PacketizerState, packetizer.next());
}
