const std = @import("std");
const flex = @import("midi_flex.zig");
const sysex7 = @import("midi_sysex7.zig");
const ump = @import("midi_ump.zig");
const ump_bytes = @import("midi_ump_bytes.zig");
const segmented = @import("midi_segmented.zig");
const byteAt = ump_bytes.byteAt;
const setByte = ump_bytes.setByte;

pub const Form = sysex7.Kind;

pub const Kind = enum(u16) {
    unknown_metadata = 0x0100,
    project_name = 0x0101,
    composition_name = 0x0102,
    midi_clip_name = 0x0103,
    copyright_notice = 0x0104,
    composer_name = 0x0105,
    lyricist_name = 0x0106,
    arranger_name = 0x0107,
    publisher_name = 0x0108,
    primary_performer_name = 0x0109,
    accompanying_performer_name = 0x010A,
    recording_date = 0x010B,
    recording_location = 0x010C,
    unknown_performance = 0x0200,
    lyrics = 0x0201,
    lyrics_language = 0x0202,
    ruby = 0x0203,
    ruby_language = 0x0204,

    pub fn bank(self: Kind) u8 {
        return @intCast(@intFromEnum(self) >> 8);
    }

    pub fn status(self: Kind) u8 {
        return @truncate(@intFromEnum(self));
    }
};

pub const Chunk = struct {
    target: flex.Target,
    kind: Kind,
    form: Form,
    storage: [12]u8 = .{0} ** 12,
    count: u4 = 0,

    pub fn init(
        target: flex.Target,
        kind: Kind,
        form: Form,
        bytes: []const u8,
    ) !Chunk {
        if (!target.valid()) return error.InvalidFlexTarget;
        if (bytes.len > 12) return error.FlexTextChunkTooLarge;
        if ((form == .complete or form == .begin) and startsWithBom(bytes))
            return error.InvalidFlexTextByteOrderMark;
        var chunk = Chunk{
            .target = target,
            .kind = kind,
            .form = form,
            .count = @intCast(bytes.len),
        };
        for (bytes, 0..) |byte, index| {
            if (byte == 0) return error.InvalidFlexTextByte;
            chunk.storage[index] = byte;
        }
        if ((form == .begin or form == .continuation) and bytes.len != 12)
            return error.ShortFlexTextContinuation;
        return chunk;
    }

    pub fn data(self: *const Chunk) []const u8 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: Chunk) bool {
        if (!self.target.valid() or self.count > 12) return false;
        if ((self.form == .begin or self.form == .continuation) and self.count != 12)
            return false;
        if ((self.form == .complete or self.form == .begin) and
            startsWithBom(self.storage[0..self.count]))
            return false;
        for (self.storage[0..self.count]) |byte| {
            if (byte == 0) return false;
        }
        for (self.storage[self.count..]) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    pub fn packet(self: Chunk) !ump.Packet {
        if (!self.valid()) return error.InvalidFlexTextChunk;
        var words = [_]u32{0} ** 4;
        setByte(&words, 0, 0xD0 | @as(u8, self.target.group));
        setByte(
            &words,
            1,
            (@as(u8, @intFromEnum(self.form)) << 6) |
                (@as(u8, @intFromEnum(self.target.address)) << 4) |
                @as(u8, self.target.channel),
        );
        setByte(&words, 2, self.kind.bank());
        setByte(&words, 3, self.kind.status());
        for (self.storage[0..self.count], 0..) |byte, index|
            setByte(&words, 4 + index, byte);
        return ump.Packet.init(&words);
    }

    pub fn parse(ump_packet: ump.Packet) !Chunk {
        if (!ump_packet.valid()) return error.InvalidUmpPacket;
        const message_type = ump_packet.messageType() orelse
            return error.InvalidUmpPacket;
        if (message_type != .flex_data) return error.NotFlexDataUmp;

        const target_and_form = byteAt(ump_packet, 1);
        const address: flex.Address = switch ((target_and_form >> 4) & 3) {
            0 => .channel,
            1 => .group,
            else => return error.InvalidFlexTarget,
        };
        const target = flex.Target{
            .group = @intCast(byteAt(ump_packet, 0) & 0x0F),
            .address = address,
            .channel = @intCast(target_and_form & 0x0F),
        };
        if (!target.valid()) return error.InvalidFlexTarget;
        const form: Form = @enumFromInt(target_and_form >> 6);
        const kind = kindFromFields(byteAt(ump_packet, 2), byteAt(ump_packet, 3)) orelse
            return error.UnsupportedFlexTextKind;

        var count: usize = 12;
        for (0..12) |index| {
            if (byteAt(ump_packet, 4 + index) == 0) {
                count = index;
                break;
            }
        }
        for (count..12) |index| {
            if (byteAt(ump_packet, 4 + index) != 0)
                return error.InvalidFlexTextPadding;
        }
        if ((form == .begin or form == .continuation) and count != 12)
            return error.ShortFlexTextContinuation;

        var chunk = Chunk{
            .target = target,
            .kind = kind,
            .form = form,
            .count = @intCast(count),
        };
        for (chunk.storage[0..count], 0..) |*destination, index|
            destination.* = byteAt(ump_packet, 4 + index);
        if ((form == .complete or form == .begin) and
            startsWithBom(chunk.storage[0..chunk.count]))
            return error.InvalidFlexTextByteOrderMark;
        return chunk;
    }
};

pub const Packetizer = struct {
    target: flex.Target,
    kind: Kind,
    source: []const u8,
    cursor: usize = 0,
    emitted_empty: bool = false,

    pub fn init(target: flex.Target, kind: Kind, source: []const u8) !Packetizer {
        if (!target.valid()) return error.InvalidFlexTarget;
        if (source.len > 32 * 12) return error.FlexTextTooLong;
        if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidFlexTextEncoding;
        if (startsWithBom(source)) return error.InvalidFlexTextByteOrderMark;
        for (source) |byte| {
            if (byte == 0) return error.InvalidFlexTextByte;
        }
        return .{ .target = target, .kind = kind, .source = source };
    }

    pub fn valid(self: *const Packetizer) bool {
        if (!segmented.packetizerStateValid(
            self.source.len,
            self.cursor,
            self.emitted_empty,
        ) or !self.target.valid() or
            self.source.len > 32 * 12 or
            !std.unicode.utf8ValidateSlice(self.source) or
            startsWithBom(self.source)) return false;
        for (self.source) |byte| {
            if (byte == 0) return false;
        }
        return true;
    }

    pub fn next(self: *Packetizer) !?ump.Packet {
        if (!self.valid()) return error.InvalidFlexTextPacketizerState;
        if (self.source.len == 0) {
            if (self.emitted_empty) return null;
            self.emitted_empty = true;
            return try (try Chunk.init(
                self.target,
                self.kind,
                .complete,
                &.{},
            )).packet();
        }
        if (self.cursor == self.source.len) return null;

        const end = segmented.payloadEnd(
            self.source.len,
            self.cursor,
            12,
        );
        const form = segmented.packetForm(
            Form,
            self.source.len,
            self.cursor,
            end,
            12,
        );
        const packet = try (try Chunk.init(
            self.target,
            self.kind,
            form,
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
        packet_count: u6 = 0,
        target: ?flex.Target = null,
        kind: ?Kind = null,
        active: bool = false,
        completed: bool = false,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn valid(self: *const Self) bool {
            if (self.packet_count > 32) return false;
            if (!segmented.reassemblyStateValid(
                self.count,
                capacity,
                self.active,
                self.completed,
                self.target != null and self.kind != null,
                self.target == null and self.kind == null,
            )) return false;
            if (!self.active and !self.completed and
                self.packet_count != 0)
                return false;
            if (self.active or self.completed) {
                const target = self.target orelse return false;
                if (!target.valid() or self.packet_count == 0) return false;
                const packet_bytes = @as(usize, self.packet_count) * 12;
                if (self.active and self.count != packet_bytes) return false;
                if (self.completed and
                    (self.count < packet_bytes - 12 or
                        self.count > packet_bytes))
                    return false;
                if (startsWithBom(self.storage[0..self.count])) return false;
                for (self.storage[0..self.count]) |byte| {
                    if (byte == 0) return false;
                }
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
            if (!self.valid()) return error.InvalidFlexTextReassemblerState;
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
                    error.UnexpectedFlexTextComplete
                else
                    error.UnexpectedFlexTextBegin;
            }
            if (!segmented.replace(
                u8,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.FlexTextCapacityExceeded;
            self.packet_count = 1;
            self.target = chunk.target;
            self.kind = chunk.kind;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }

        fn acceptContinuation(self: *Self, chunk: Chunk, completes: bool) !bool {
            if (!self.active) {
                return if (completes)
                    error.UnexpectedFlexTextEnd
                else
                    error.UnexpectedFlexTextContinuation;
            }
            const target = self.target orelse
                return error.InvalidFlexTextReassemblerState;
            const kind = self.kind orelse
                return error.InvalidFlexTextReassemblerState;
            if (!std.meta.eql(target, chunk.target)) return error.FlexTextTargetMismatch;
            if (kind != chunk.kind) return error.FlexTextKindMismatch;
            if (self.packet_count == 32) return error.FlexTextPacketLimitExceeded;
            if (!segmented.append(
                u8,
                self.storage[0..],
                &self.count,
                chunk.storage[0..chunk.count],
            )) return error.FlexTextCapacityExceeded;
            self.packet_count += 1;
            return segmented.setCompletion(
                &self.active,
                &self.completed,
                completes,
            );
        }
    };
}

fn kindFromFields(bank: u8, status: u8) ?Kind {
    const value = (@as(u16, bank) << 8) | status;
    return switch (value) {
        0x0100...0x010C, 0x0200...0x0204 => @enumFromInt(value),
        else => null,
    };
}

fn startsWithBom(bytes: []const u8) bool {
    return bytes.len >= 3 and std.mem.eql(u8, bytes[0..3], "\xEF\xBB\xBF");
}

test "Flex Data text packetizers and reassemblers cover every boundary" {
    var source: [384]u8 = undefined;
    for (&source, 0..) |*byte, index| byte.* = @intCast('a' + index % 26);
    const target = flex.Target{ .group = 4, .address = .channel, .channel = 3 };
    const Assembler = Reassembler(source.len);

    for (0..source.len + 1) |length| {
        var packetizer = try Packetizer.init(target, .composition_name, source[0..length]);
        var assembler = Assembler{};
        while (try packetizer.next()) |packet| _ = try assembler.push(packet);
        try std.testing.expectEqualDeep(target, assembler.target.?);
        try std.testing.expectEqual(Kind.composition_name, assembler.kind.?);
        try std.testing.expectEqualSlices(u8, source[0..length], assembler.text().?);
        for (assembler.storage[length..]) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
        assembler.reset();
        for (assembler.storage) |byte|
            try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "Flex Data text preserves segmented canonical fields" {
    const chunk = try Chunk.init(
        .{ .group = 7, .address = .channel, .channel = 2 },
        .lyrics,
        .continuation,
        "abcdefghijkl",
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0xD782_0201, 0x6162_6364, 0x6566_6768, 0x696A_6B6C },
        (try chunk.packet()).words(),
    );
    try std.testing.expectEqualDeep(chunk, try Chunk.parse(try chunk.packet()));
}

test "Flex Data text rejects malformed input and sequences transactionally" {
    const target = flex.Target{ .group = 1, .address = .group };
    try std.testing.expectError(
        error.InvalidFlexTextEncoding,
        Packetizer.init(target, .project_name, &.{0xFF}),
    );
    try std.testing.expectError(
        error.InvalidFlexTextByte,
        Packetizer.init(target, .project_name, "bad\x00name"),
    );
    try std.testing.expectError(
        error.InvalidFlexTextByteOrderMark,
        Packetizer.init(target, .project_name, "\xEF\xBB\xBFProject"),
    );
    try std.testing.expectError(
        error.FlexTextTooLong,
        Packetizer.init(target, .project_name, "x" ** 385),
    );
    try std.testing.expectError(
        error.ShortFlexTextContinuation,
        Chunk.init(target, .project_name, .begin, "short"),
    );

    const Assembler = Reassembler(32);
    var assembler = Assembler{};
    _ = try assembler.push(try (try Chunk.init(
        target,
        .project_name,
        .begin,
        "abcdefghijkl",
    )).packet());
    const before = assembler;
    try std.testing.expectError(
        error.FlexTextKindMismatch,
        assembler.push(try (try Chunk.init(
            target,
            .composition_name,
            .end,
            "x",
        )).packet()),
    );
    try std.testing.expectEqualDeep(before, assembler);
    assembler.target = .{ .group = 1, .address = .group, .channel = 1 };
    try std.testing.expect(!assembler.valid());
    try std.testing.expectEqual(@as(?[]const u8, null), assembler.bytes());
    try std.testing.expectError(
        error.InvalidFlexTextReassemblerState,
        assembler.push(try (try Chunk.init(
            target,
            .project_name,
            .end,
            "done",
        )).packet()),
    );
    assembler.target = target;
    assembler.packet_count = 0;
    try std.testing.expect(!assembler.valid());
    assembler.packet_count = 1;
    try std.testing.expect(assembler.valid());
    try std.testing.expect(try assembler.push(
        try (try Chunk.init(target, .project_name, .end, "done")).packet(),
    ));
    try std.testing.expectEqualStrings("abcdefghijkldone", assembler.text().?);

    var malformed_packetizer = try Packetizer.init(
        target,
        .project_name,
        "name",
    );
    malformed_packetizer.emitted_empty = true;
    try std.testing.expect(!malformed_packetizer.valid());
    try std.testing.expectError(
        error.InvalidFlexTextPacketizerState,
        malformed_packetizer.next(),
    );
    malformed_packetizer.emitted_empty = false;
    malformed_packetizer.target = .{ .group = 1, .address = .group, .channel = 1 };
    try std.testing.expect(!malformed_packetizer.valid());
}
