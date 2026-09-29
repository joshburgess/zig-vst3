const std = @import("std");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const sysex7 = @import("midi_sysex7.zig");
const segmented = @import("midi_segmented.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Form = sysex7.Kind;

pub const Kind = enum(u8) {
    endpoint_name = 0x03,
    product_instance_id = 0x04,
    function_block_name = 0x12,

    pub fn bytesPerPacket(self: Kind) u4 {
        return if (self == .function_block_name) 13 else 14;
    }

    pub fn maximumLength(self: Kind) u7 {
        return switch (self) {
            .endpoint_name => 98,
            .product_instance_id => 42,
            .function_block_name => 91,
        };
    }
};

pub const Chunk = struct {
    kind: Kind,
    form: Form,
    block: ?u5,
    storage: [14]u8 = .{0} ** 14,
    count: u4 = 0,

    pub fn init(kind: Kind, form: Form, block: ?u5, bytes: []const u8) !Chunk {
        try validateBlock(kind, block);
        if (bytes.len > kind.bytesPerPacket()) return error.StreamTextChunkTooLarge;
        try validateTextBytes(kind, bytes);
        var chunk = Chunk{
            .kind = kind,
            .form = form,
            .block = block,
            .count = @intCast(bytes.len),
        };
        for (bytes, 0..) |byte, index| {
            chunk.storage[index] = byte;
        }
        if ((form == .begin or form == .continuation) and
            bytes.len != kind.bytesPerPacket())
            return error.ShortStreamTextContinuation;
        return chunk;
    }

    pub fn data(self: *const Chunk) []const u8 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: Chunk) bool {
        validateBlock(self.kind, self.block) catch return false;
        if (self.count > self.kind.bytesPerPacket()) return false;
        if ((self.form == .begin or self.form == .continuation) and
            self.count != self.kind.bytesPerPacket())
            return false;
        validateTextBytes(self.kind, self.storage[0..self.count]) catch return false;
        for (self.storage[self.count..]) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    pub fn packet(self: Chunk) !ump.Packet {
        if (!self.valid()) return error.InvalidStreamTextChunk;
        var words = [_]u32{0} ** 4;
        setByte(&words, 0, 0xF0 | (@as(u8, @intFromEnum(self.form)) << 2));
        setByte(&words, 1, @intFromEnum(self.kind));
        const data_start: usize = if (self.kind == .function_block_name) 3 else 2;
        if (self.block) |block| setByte(&words, 2, block);
        for (self.storage[0..self.count], 0..) |byte, index|
            setByte(&words, data_start + index, byte);
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet) !Chunk {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .stream) return error.NotStreamUmp;

        const first = byteAt(ump_packet, 0);
        if ((first & 0x03) != 0) return error.InvalidStreamReservedField;
        const form: Form = @enumFromInt((first >> 2) & 3);
        const kind: Kind = switch (byteAt(ump_packet, 1)) {
            0x03 => .endpoint_name,
            0x04 => .product_instance_id,
            0x12 => .function_block_name,
            else => return error.NotStreamTextNotification,
        };
        const block: ?u5 = if (kind == .function_block_name) blk: {
            const raw = byteAt(ump_packet, 2);
            if (raw > 31) return error.InvalidStreamTextBlock;
            break :blk @intCast(raw);
        } else null;
        const data_start: usize = if (kind == .function_block_name) 3 else 2;
        const maximum: usize = kind.bytesPerPacket();
        var count: usize = maximum;
        for (0..maximum) |index| {
            if (byteAt(ump_packet, data_start + index) == 0) {
                count = index;
                break;
            }
        }
        for (count..maximum) |index| {
            if (byteAt(ump_packet, data_start + index) != 0)
                return error.InvalidStreamTextPadding;
        }
        if ((form == .begin or form == .continuation) and count != maximum)
            return error.ShortStreamTextContinuation;
        var payload: [14]u8 = .{0} ** 14;
        for (payload[0..count], 0..) |*destination, index|
            destination.* = byteAt(ump_packet, data_start + index);
        try validateTextBytes(kind, payload[0..count]);

        var chunk = Chunk{
            .kind = kind,
            .form = form,
            .block = block,
            .count = @intCast(count),
        };
        @memcpy(chunk.storage[0..count], payload[0..count]);
        return chunk;
    }
};

pub const Packetizer = struct {
    kind: Kind,
    block: ?u5,
    source: []const u8,
    cursor: usize = 0,
    emitted_empty: bool = false,

    pub fn init(kind: Kind, block: ?u5, source: []const u8) !Packetizer {
        try validateBlock(kind, block);
        if (source.len > kind.maximumLength()) return error.StreamTextTooLong;
        try validateTextBytes(kind, source);
        if (kind != .product_instance_id and !std.unicode.utf8ValidateSlice(source))
            return error.InvalidStreamTextEncoding;
        return .{ .kind = kind, .block = block, .source = source };
    }

    pub fn valid(self: *const Packetizer) bool {
        if (!segmented.packetizerStateValid(
            self.source.len,
            self.cursor,
            self.emitted_empty,
        )) return false;
        validateBlock(self.kind, self.block) catch return false;
        if (self.source.len > self.kind.maximumLength()) return false;
        validateTextBytes(self.kind, self.source) catch return false;
        return self.kind == .product_instance_id or
            std.unicode.utf8ValidateSlice(self.source);
    }

    pub fn next(self: *Packetizer) !?ump.Packet {
        if (!self.valid()) return error.InvalidStreamTextPacketizerState;
        if (self.source.len == 0) {
            if (self.emitted_empty) return null;
            self.emitted_empty = true;
            return try (try Chunk.init(self.kind, .complete, self.block, &.{})).packet();
        }
        if (self.cursor == self.source.len) return null;

        const bytes_per_packet: usize = self.kind.bytesPerPacket();
        const end = segmented.payloadEnd(
            self.source.len,
            self.cursor,
            bytes_per_packet,
        );
        const form = segmented.packetForm(
            Form,
            self.source.len,
            self.cursor,
            end,
            bytes_per_packet,
        );
        const packet = try (try Chunk.init(
            self.kind,
            form,
            self.block,
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

        storage: [capacity]u8 = @splat(0),
        count: usize = 0,
        kind: ?Kind = null,
        block: ?u5 = null,
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
                self.kind != null,
                self.kind == null and self.block == null,
            )) return false;
            if (self.kind == .function_block_name and self.block == null) return false;
            if (self.kind != null and self.kind != .function_block_name and self.block != null)
                return false;
            if (self.kind) |kind| {
                if (self.count > kind.maximumLength()) return false;
                validateTextBytes(kind, self.storage[0..self.count]) catch return false;
            }
            return true;
        }

        pub fn bytes(self: *const Self) ?[]const u8 {
            if (!self.valid() or !self.completed) return null;
            return self.storage[0..self.count];
        }

        pub fn text(self: *const Self) ?[]const u8 {
            const value = self.bytes() orelse return null;
            return if (std.unicode.utf8ValidateSlice(value)) value else null;
        }

        pub fn push(self: *Self, ump_packet: ump.Packet) !bool {
            if (!self.valid()) return error.InvalidStreamTextReassemblerState;
            const chunk = try Chunk.parse(ump_packet);
            return switch (chunk.form) {
                .complete => try self.acceptInitial(chunk, true),
                .begin => try self.acceptInitial(chunk, false),
                .continuation => try self.acceptContinuation(chunk, false),
                .end => try self.acceptContinuation(chunk, true),
            };
        }

        fn acceptInitial(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (self.active) {
                return if (completes)
                    error.UnexpectedStreamTextComplete
                else
                    error.UnexpectedStreamTextBegin;
            }
            if (!segmented.replace(
                u8,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.StreamTextCapacityExceeded;
            self.kind = chunk.kind;
            self.block = chunk.block;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }

        fn acceptContinuation(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (!self.active) {
                return if (completes)
                    error.UnexpectedStreamTextEnd
                else
                    error.UnexpectedStreamTextContinuation;
            }
            const kind = self.kind orelse
                return error.InvalidStreamTextReassemblerState;
            if (kind != chunk.kind) return error.StreamTextKindMismatch;
            if (self.block != chunk.block) return error.StreamTextBlockMismatch;
            const maximum = @min(capacity, @as(usize, kind.maximumLength()));
            if (!segmented.append(
                u8,
                self.storage[0..maximum],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.StreamTextCapacityExceeded;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }
    };
}

fn validateBlock(kind: Kind, block: ?u5) !void {
    if (kind == .function_block_name) {
        if (block == null) return error.MissingStreamTextBlock;
    } else if (block != null) {
        return error.UnexpectedStreamTextBlock;
    }
}

fn validateTextBytes(kind: Kind, bytes: []const u8) !void {
    for (bytes) |byte| {
        if (byte == 0) return error.InvalidStreamTextByte;
        if (kind == .product_instance_id and (byte < 32 or byte > 126))
            return error.InvalidProductInstanceIdByte;
    }
}

test "stream text packetizers and reassemblers cover every boundary" {
    var source: [98]u8 = undefined;
    for (&source, 0..) |*byte, index| byte.* = @intCast('a' + index % 26);

    inline for (.{ Kind.endpoint_name, Kind.product_instance_id, Kind.function_block_name }) |kind| {
        const maximum = comptime @as(usize, kind.maximumLength());
        const block: ?u5 = if (kind == .function_block_name) 7 else null;
        const Assembler = Reassembler(maximum);
        for (0..maximum + 1) |length| {
            var packetizer = try Packetizer.init(kind, block, source[0..length]);
            var assembler = Assembler{};
            while (try packetizer.next()) |packet| _ = try assembler.push(packet);
            try std.testing.expectEqual(kind, assembler.kind.?);
            try std.testing.expectEqual(block, assembler.block);
            try std.testing.expectEqualSlices(u8, source[0..length], assembler.text().?);
            for (assembler.storage[length..]) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
            assembler.reset();
            for (assembler.storage) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
        }
    }
}

test "stream text packets preserve segmented canonical fields" {
    const chunk = try Chunk.init(
        .function_block_name,
        .continuation,
        9,
        "abcdefghijklm",
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xF812_0961, 0x6263_6465, 0x6667_6869, 0x6A6B_6C6D },
        (try chunk.packet()).words(),
    );
    try std.testing.expectEqualDeep(chunk, try Chunk.parse(try chunk.packet()));
}

test "stream text rejects malformed input and sequences transactionally" {
    try std.testing.expectError(
        error.MissingStreamTextBlock,
        Packetizer.init(.function_block_name, null, "name"),
    );
    try std.testing.expectError(
        error.UnexpectedStreamTextBlock,
        Packetizer.init(.endpoint_name, 1, "name"),
    );
    try std.testing.expectError(
        error.InvalidStreamTextEncoding,
        Packetizer.init(.endpoint_name, null, &.{0xFF}),
    );
    try std.testing.expectError(
        error.InvalidStreamTextByte,
        Packetizer.init(.endpoint_name, null, "bad\x00name"),
    );
    try std.testing.expectError(
        error.InvalidProductInstanceIdByte,
        Packetizer.init(.product_instance_id, null, "bad\nid"),
    );
    try std.testing.expectError(
        error.InvalidProductInstanceIdByte,
        Chunk.parse(try ump.Packet.init(&.{ 0xF004_7F00, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.InvalidStreamTextBlock,
        Chunk.parse(try ump.Packet.init(&.{ 0xF012_2061, 0, 0, 0 })),
    );
    try std.testing.expectError(
        error.ShortStreamTextContinuation,
        Chunk.init(.endpoint_name, .begin, null, "short"),
    );

    const Assembler = Reassembler(20);
    var assembler = Assembler{};
    _ = try assembler.push(try (try Chunk.init(
        .endpoint_name,
        .begin,
        null,
        "abcdefghijklmn",
    )).packet());
    const before = assembler;
    try std.testing.expectError(
        error.StreamTextKindMismatch,
        assembler.push(try (try Chunk.init(
            .product_instance_id,
            .end,
            null,
            "x",
        )).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    assembler.storage[0] = 0;
    try std.testing.expect(!assembler.valid());
    try std.testing.expectEqual(@as(?[]const u8, null), assembler.bytes());
    assembler.storage[0] = 'a';
    try std.testing.expect(assembler.valid());
    try std.testing.expect(try assembler.push(
        try (try Chunk.init(.endpoint_name, .end, null, "done")).packet(),
    ));
    try std.testing.expectEqualSlices(u8, "abcdefghijklmndone", assembler.text().?);

    const OversizedAssembler = Reassembler(112);
    var oversized = OversizedAssembler{};
    for (0..7) |_| {
        _ = try oversized.push(try (try Chunk.init(
            .endpoint_name,
            if (oversized.active) .continuation else .begin,
            null,
            "abcdefghijklmn",
        )).packet());
    }
    const retained = oversized;
    try std.testing.expectError(
        error.StreamTextCapacityExceeded,
        oversized.push(try (try Chunk.init(
            .endpoint_name,
            .end,
            null,
            "x",
        )).packet()),
    );
    try std.testing.expectEqualDeep(retained, oversized);

    var malformed_packetizer = try Packetizer.init(
        .function_block_name,
        1,
        "name",
    );
    malformed_packetizer.block = null;
    try std.testing.expect(!malformed_packetizer.valid());
    try std.testing.expectError(
        error.InvalidStreamTextPacketizerState,
        malformed_packetizer.next(),
    );
}
