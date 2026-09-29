const std = @import("std");
const midi_ci = @import("midi_ci.zig");

pub const Features = packed struct(u7) {
    midi_message_report: bool = false,
    reserved_one: bool = false,
    reserved_two: bool = false,
    reserved_three: bool = false,
    reserved_four: bool = false,
    reserved_five: bool = false,
    reserved_six: bool = false,

    pub fn valid(self: Features) bool {
        return !self.reserved_one and
            !self.reserved_two and
            !self.reserved_three and
            !self.reserved_four and
            !self.reserved_five and
            !self.reserved_six;
    }
};

pub const Inquiry = struct {
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
};

pub const Reply = struct {
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    features: Features,
};

pub const Kind = enum(u7) {
    inquiry = 0x40,
    reply = 0x41,
};

pub const Message = union(Kind) {
    inquiry: Inquiry,
    reply: Reply,

    pub fn encodedLength(self: Message) !usize {
        try validate(self);
        return switch (self) {
            .inquiry => 13,
            .reply => 14,
        };
    }

    pub fn encode(self: Message, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        const header = switch (self) {
            .inquiry => |value| value,
            .reply => |value| Inquiry{
                .source = value.source,
                .destination = value.destination,
            },
        };
        destination[0] = 0x7E;
        destination[1] = 0x7F;
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(std.meta.activeTag(self));
        destination[4] = 2;
        writeU28(destination[5..9], header.source.value);
        writeU28(destination[9..13], header.destination.value);
        switch (self) {
            .inquiry => {},
            .reply => |value| {
                destination[13] = @as(u7, @bitCast(value.features));
            },
        }
        return destination[0..length];
    }

    pub fn parse(source: []const u8) !Message {
        if (source.len < 13) return error.TruncatedMidiCiMessage;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or
            source[1] != 0x7F or
            source[2] != 0x0D)
            return error.NotMidiCiProcessInquiry;
        if (source[4] != 2) return error.UnsupportedMidiCiVersion;
        const kind: Kind = switch (source[3]) {
            0x40 => .inquiry,
            0x41 => .reply,
            else => return error.NotMidiCiProcessInquiry,
        };
        const expected_length: usize = switch (kind) {
            .inquiry => 13,
            .reply => 14,
        };
        if (source.len != expected_length)
            return error.InvalidMidiCiMessageLength;
        const header = Inquiry{
            .source = .{ .value = readU28(source[5..9]) },
            .destination = .{ .value = readU28(source[9..13]) },
        };
        if (!validHeader(header)) return error.InvalidMidiCiProcessInquiry;
        return switch (kind) {
            .inquiry => .{ .inquiry = header },
            .reply => {
                const features: Features = @bitCast(
                    @as(u7, @intCast(source[source.len - 1])),
                );
                if (!features.valid())
                    return error.InvalidMidiCiProcessInquiryFeatures;
                return .{ .reply = .{
                    .source = header.source,
                    .destination = header.destination,
                    .features = features,
                } };
            },
        };
    }
};

pub const Transaction = struct {
    source: midi_ci.Muid,
    destination: midi_ci.Muid,

    pub fn init(
        source: midi_ci.Muid,
        destination: midi_ci.Muid,
    ) !Transaction {
        const header = Inquiry{
            .source = source,
            .destination = destination,
        };
        if (!validHeader(header)) return error.InvalidMidiCiProcessInquiry;
        if (source.value == destination.value) return error.MidiCiMuidCollision;
        return .{ .source = source, .destination = destination };
    }

    pub fn inquiry(self: Transaction) Message {
        return .{ .inquiry = .{
            .source = self.source,
            .destination = self.destination,
        } };
    }

    pub fn accept(self: Transaction, message: Message) !Reply {
        try validate(message);
        const reply = switch (message) {
            .reply => |value| value,
            .inquiry => return error.UnexpectedMidiCiProcessInquiry,
        };
        if (reply.source.value != self.destination.value or
            reply.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        return reply;
    }
};

pub const Responder = struct {
    source: midi_ci.Muid,
    features: Features,

    pub fn init(
        source: midi_ci.Muid,
        features: Features,
    ) !Responder {
        if (!source.validSource() or !features.valid())
            return error.InvalidMidiCiProcessInquiry;
        return .{ .source = source, .features = features };
    }

    pub fn handle(self: Responder, message: Message) !Message {
        try validate(message);
        const inquiry = switch (message) {
            .inquiry => |value| value,
            .reply => return error.UnexpectedMidiCiProcessInquiryReply,
        };
        if (inquiry.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        if (inquiry.source.value == self.source.value)
            return error.MidiCiMuidCollision;
        return .{ .reply = .{
            .source = self.source,
            .destination = inquiry.source,
            .features = self.features,
        } };
    }
};

fn validate(message: Message) !void {
    const header = switch (message) {
        .inquiry => |value| value,
        .reply => |value| Inquiry{
            .source = value.source,
            .destination = value.destination,
        },
    };
    if (!validHeader(header)) return error.InvalidMidiCiProcessInquiry;
    switch (message) {
        .inquiry => {},
        .reply => |value| {
            if (!value.features.valid())
                return error.InvalidMidiCiProcessInquiryFeatures;
        },
    }
}

fn validHeader(header: Inquiry) bool {
    return header.source.validSource() and header.destination.validSource();
}

fn writeU28(destination: []u8, value: u28) void {
    destination[0] = @intCast(value & 0x7F);
    destination[1] = @intCast((value >> 7) & 0x7F);
    destination[2] = @intCast((value >> 14) & 0x7F);
    destination[3] = @intCast((value >> 21) & 0x7F);
}

fn readU28(source: []const u8) u28 {
    return @as(u28, @intCast(source[0])) |
        (@as(u28, @intCast(source[1])) << 7) |
        (@as(u28, @intCast(source[2])) << 14) |
        (@as(u28, @intCast(source[3])) << 21);
}

test "MIDI-CI process inquiry capabilities transact over wire" {
    const transaction = try Transaction.init(
        try midi_ci.Muid.init(1),
        try midi_ci.Muid.init(2),
    );
    const responder = try Responder.init(
        try midi_ci.Muid.init(2),
        .{ .midi_message_report = true },
    );
    var inquiry_storage: [13]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&inquiry_storage);
    try std.testing.expectEqualSlices(u8, &.{
        0x7E, 0x7F, 0x0D, 0x40, 0x02,
        0x01, 0x00, 0x00, 0x00, 0x02,
        0x00, 0x00, 0x00,
    }, inquiry_bytes);
    const reply_message = try responder.handle(try Message.parse(inquiry_bytes));
    var reply_storage: [14]u8 = undefined;
    const reply_bytes = try reply_message.encode(&reply_storage);
    const reply = try transaction.accept(try Message.parse(reply_bytes));
    try std.testing.expect(reply.features.midi_message_report);
}

test "MIDI-CI process inquiry capabilities reject malformed messages" {
    var storage: [14]u8 = .{0x55} ** 14;
    const invalid = Message{ .reply = .{
        .source = .{ .value = 2 },
        .destination = .{ .value = 1 },
        .features = .{ .reserved_one = true },
    } };
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiProcessInquiryFeatures,
        invalid.encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);

    const valid = Message{ .reply = .{
        .source = .{ .value = 2 },
        .destination = .{ .value = 1 },
        .features = .{ .midi_message_report = true },
    } };
    const encoded = try valid.encode(&storage);
    storage[13] = 0x02;
    try std.testing.expectError(
        error.InvalidMidiCiProcessInquiryFeatures,
        Message.parse(encoded),
    );
    try std.testing.expectError(
        error.InvalidMidiCiMessageLength,
        Message.parse(encoded[0..13]),
    );
}

test "MIDI-CI process inquiry capabilities correlate replies" {
    const transaction = try Transaction.init(
        try midi_ci.Muid.init(1),
        try midi_ci.Muid.init(2),
    );
    try std.testing.expectError(
        error.MidiCiMuidMismatch,
        transaction.accept(.{ .reply = .{
            .source = try midi_ci.Muid.init(3),
            .destination = try midi_ci.Muid.init(1),
            .features = .{},
        } }),
    );
    try std.testing.expectError(
        error.MidiCiMuidCollision,
        Transaction.init(
            try midi_ci.Muid.init(1),
            try midi_ci.Muid.init(1),
        ),
    );
}
