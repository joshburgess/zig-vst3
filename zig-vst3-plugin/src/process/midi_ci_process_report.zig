const std = @import("std");
const midi_ci = @import("midi_ci.zig");

pub const DataControl = enum(u7) {
    capability_only = 0x00,
    non_default = 0x01,
    full = 0x7F,
};

pub const SystemMessages = packed struct(u7) {
    mtc_quarter_frame: bool = false,
    song_position: bool = false,
    song_select: bool = false,
    reserved_three: bool = false,
    reserved_four: bool = false,
    reserved_five: bool = false,
    reserved_six: bool = false,

    pub fn valid(self: SystemMessages) bool {
        return !self.reserved_three and
            !self.reserved_four and
            !self.reserved_five and
            !self.reserved_six;
    }
};

pub const ChannelMessages = packed struct(u7) {
    pitch_bend: bool = false,
    control_change: bool = false,
    registered_controller: bool = false,
    assignable_controller: bool = false,
    program_change: bool = false,
    channel_pressure: bool = false,
    reserved_six: bool = false,

    pub fn valid(self: ChannelMessages) bool {
        return !self.reserved_six;
    }
};

pub const NoteMessages = packed struct(u7) {
    notes: bool = false,
    poly_pressure: bool = false,
    per_note_pitch_bend: bool = false,
    registered_per_note_controller: bool = false,
    assignable_per_note_controller: bool = false,
    reserved_five: bool = false,
    reserved_six: bool = false,

    pub fn valid(self: NoteMessages) bool {
        return !self.reserved_five and !self.reserved_six;
    }
};

pub const Requests = struct {
    system: SystemMessages = .{},
    channel: ChannelMessages = .{},
    note: NoteMessages = .{},

    pub fn valid(self: Requests) bool {
        return self.system.valid() and self.channel.valid() and self.note.valid();
    }

    pub fn isSubsetOf(self: Requests, other: Requests) bool {
        return subset(SystemMessages, self.system, other.system) and
            subset(ChannelMessages, self.channel, other.channel) and
            subset(NoteMessages, self.note, other.note);
    }

    pub fn intersection(self: Requests, other: Requests) Requests {
        return .{
            .system = intersect(SystemMessages, self.system, other.system),
            .channel = intersect(ChannelMessages, self.channel, other.channel),
            .note = intersect(NoteMessages, self.note, other.note),
        };
    }

    fn hasSystem(self: Requests) bool {
        return @as(u7, @bitCast(self.system)) != 0;
    }
};

pub const Inquiry = struct {
    address: midi_ci.Address = .function_block,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    data_control: DataControl,
    requests: Requests,
};

pub const Reply = struct {
    address: midi_ci.Address = .function_block,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    requests: Requests,
};

pub const End = struct {
    address: midi_ci.Address = .function_block,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
};

pub const Kind = enum(u7) {
    inquiry = 0x42,
    reply = 0x43,
    end = 0x44,
};

pub const Message = union(Kind) {
    inquiry: Inquiry,
    reply: Reply,
    end: End,

    pub fn encodedLength(self: Message) !usize {
        try validate(self);
        return switch (self) {
            .inquiry => 18,
            .reply => 17,
            .end => 13,
        };
    }

    pub fn encode(self: Message, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        const header = headerOf(self);
        destination[0] = 0x7E;
        destination[1] = addressByte(header.address);
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(std.meta.activeTag(self));
        destination[4] = 2;
        writeU28(destination[5..9], header.source.value);
        writeU28(destination[9..13], header.destination.value);
        switch (self) {
            .inquiry => |value| {
                destination[13] = @intFromEnum(value.data_control);
                writeRequests(destination[14..18], value.requests);
            },
            .reply => |value| writeRequests(destination[13..17], value.requests),
            .end => {},
        }
        return destination[0..length];
    }

    pub fn parse(source: []const u8) !Message {
        if (source.len < 13) return error.TruncatedMidiCiMessage;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or source[2] != 0x0D)
            return error.NotMidiCiMessageReport;
        if (source[4] != 2) return error.UnsupportedMidiCiVersion;
        const kind: Kind = switch (source[3]) {
            0x42 => .inquiry,
            0x43 => .reply,
            0x44 => .end,
            else => return error.NotMidiCiMessageReport,
        };
        const expected_length: usize = switch (kind) {
            .inquiry => 18,
            .reply => 17,
            .end => 13,
        };
        if (source.len != expected_length)
            return error.InvalidMidiCiMessageLength;
        const header = End{
            .address = try parseAddress(source[1]),
            .source = .{ .value = readU28(source[5..9]) },
            .destination = .{ .value = readU28(source[9..13]) },
        };
        if (!validHeader(header)) return error.InvalidMidiCiMessageReport;
        return switch (kind) {
            .inquiry => {
                const data_control: DataControl = switch (source[13]) {
                    0x00 => .capability_only,
                    0x01 => .non_default,
                    0x7F => .full,
                    else => return error.InvalidMidiCiReportDataControl,
                };
                const requests = try parseRequests(source[14..18]);
                const value = Inquiry{
                    .address = header.address,
                    .source = header.source,
                    .destination = header.destination,
                    .data_control = data_control,
                    .requests = requests,
                };
                if (!validInquiry(value)) return error.InvalidMidiCiMessageReport;
                return .{ .inquiry = value };
            },
            .reply => .{ .reply = .{
                .address = header.address,
                .source = header.source,
                .destination = header.destination,
                .requests = try parseRequests(source[13..17]),
            } },
            .end => .{ .end = header },
        };
    }
};

pub const Transaction = struct {
    inquiry_value: Inquiry,
    state: State = .awaiting_reply,

    pub const State = enum {
        awaiting_reply,
        receiving,
        complete,
    };

    pub fn init(inquiry_value: Inquiry) !Transaction {
        if (!validInquiry(inquiry_value)) return error.InvalidMidiCiMessageReport;
        if (inquiry_value.source.value == inquiry_value.destination.value)
            return error.MidiCiMuidCollision;
        return .{ .inquiry_value = inquiry_value };
    }

    pub fn inquiry(self: Transaction) Message {
        return .{ .inquiry = self.inquiry_value };
    }

    pub fn acceptBegin(self: *Transaction, message: Message) !Reply {
        if (self.state != .awaiting_reply)
            return error.InvalidMidiCiReportState;
        try validate(message);
        const reply = switch (message) {
            .reply => |value| value,
            else => return error.UnexpectedMidiCiMessageReport,
        };
        try self.correlate(.{
            .address = reply.address,
            .source = reply.source,
            .destination = reply.destination,
        });
        if (!reply.requests.isSubsetOf(self.inquiry_value.requests))
            return error.UnrequestedMidiCiReportMessages;
        self.state = .receiving;
        return reply;
    }

    pub fn acceptEnd(self: *Transaction, message: Message) !void {
        if (self.state != .receiving) return error.InvalidMidiCiReportState;
        try validate(message);
        const end = switch (message) {
            .end => |value| value,
            else => return error.UnexpectedMidiCiMessageReport,
        };
        try self.correlate(end);
        self.state = .complete;
    }

    fn correlate(self: Transaction, header: End) !void {
        if (!addressEqual(header.address, self.inquiry_value.address) or
            header.source.value != self.inquiry_value.destination.value or
            header.destination.value != self.inquiry_value.source.value)
            return error.MidiCiMessageReportMismatch;
    }
};

pub const Responder = struct {
    source: midi_ci.Muid,
    supported: Requests,

    pub fn init(source: midi_ci.Muid, supported: Requests) !Responder {
        if (!source.validSource() or !supported.valid())
            return error.InvalidMidiCiMessageReport;
        return .{ .source = source, .supported = supported };
    }

    pub fn begin(self: Responder, message: Message) !Message {
        try validate(message);
        const inquiry = switch (message) {
            .inquiry => |value| value,
            else => return error.UnexpectedMidiCiMessageReport,
        };
        if (inquiry.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        if (inquiry.source.value == self.source.value)
            return error.MidiCiMuidCollision;
        return .{ .reply = .{
            .address = inquiry.address,
            .source = self.source,
            .destination = inquiry.source,
            .requests = inquiry.requests.intersection(self.supported),
        } };
    }

    pub fn end(self: Responder, inquiry: Inquiry) !Message {
        if (!validInquiry(inquiry)) return error.InvalidMidiCiMessageReport;
        if (inquiry.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        if (inquiry.source.value == self.source.value)
            return error.MidiCiMuidCollision;
        return .{ .end = .{
            .address = inquiry.address,
            .source = self.source,
            .destination = inquiry.source,
        } };
    }
};

fn validate(message: Message) !void {
    const header = headerOf(message);
    if (!validHeader(header)) return error.InvalidMidiCiMessageReport;
    switch (message) {
        .inquiry => |value| {
            if (!validInquiry(value)) return error.InvalidMidiCiMessageReport;
        },
        .reply => |value| {
            if (!value.requests.valid() or
                (value.requests.hasSystem() and
                    !addressEqual(value.address, .function_block)))
                return error.InvalidMidiCiMessageReportRequests;
        },
        .end => {},
    }
}

fn validInquiry(value: Inquiry) bool {
    if (!validHeader(.{
        .address = value.address,
        .source = value.source,
        .destination = value.destination,
    }) or !value.requests.valid()) return false;
    return !value.requests.hasSystem() or
        addressEqual(value.address, .function_block);
}

fn validHeader(header: End) bool {
    return header.source.validSource() and header.destination.validSource();
}

fn headerOf(message: Message) End {
    return switch (message) {
        .inquiry => |value| .{
            .address = value.address,
            .source = value.source,
            .destination = value.destination,
        },
        .reply => |value| .{
            .address = value.address,
            .source = value.source,
            .destination = value.destination,
        },
        .end => |value| value,
    };
}

fn writeRequests(destination: []u8, requests: Requests) void {
    destination[0] = @as(u7, @bitCast(requests.system));
    destination[1] = 0;
    destination[2] = @as(u7, @bitCast(requests.channel));
    destination[3] = @as(u7, @bitCast(requests.note));
}

fn parseRequests(source: []const u8) !Requests {
    if (source[1] != 0) return error.InvalidMidiCiMessageReportRequests;
    const requests = Requests{
        .system = @bitCast(@as(u7, @intCast(source[0]))),
        .channel = @bitCast(@as(u7, @intCast(source[2]))),
        .note = @bitCast(@as(u7, @intCast(source[3]))),
    };
    if (!requests.valid()) return error.InvalidMidiCiMessageReportRequests;
    return requests;
}

fn subset(comptime T: type, left: T, right: T) bool {
    const left_bits: u7 = @bitCast(left);
    const right_bits: u7 = @bitCast(right);
    return left_bits & ~right_bits == 0;
}

fn intersect(comptime T: type, left: T, right: T) T {
    const left_bits: u7 = @bitCast(left);
    const right_bits: u7 = @bitCast(right);
    return @bitCast(left_bits & right_bits);
}

fn addressByte(address: midi_ci.Address) u7 {
    return switch (address) {
        .channel => |channel| channel,
        .group => 0x7E,
        .function_block => 0x7F,
    };
}

fn parseAddress(value: u8) !midi_ci.Address {
    return switch (value) {
        0x00...0x0F => .{ .channel = @intCast(value) },
        0x7E => .group,
        0x7F => .function_block,
        else => error.InvalidMidiCiAddress,
    };
}

fn addressEqual(left: midi_ci.Address, right: midi_ci.Address) bool {
    return addressByte(left) == addressByte(right);
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

test "MIDI-CI message report transaction brackets supported requests" {
    const inquiry = Inquiry{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .data_control = .non_default,
        .requests = .{
            .system = .{ .song_position = true },
            .channel = .{
                .control_change = true,
                .program_change = true,
            },
            .note = .{ .notes = true },
        },
    };
    var transaction = try Transaction.init(inquiry);
    const responder = try Responder.init(
        try midi_ci.Muid.init(2),
        .{
            .system = .{ .song_position = true },
            .channel = .{ .control_change = true },
        },
    );
    var storage: [18]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&storage);
    const begin_message = try responder.begin(try Message.parse(inquiry_bytes));
    const begin_bytes = try begin_message.encode(&storage);
    const reply = try transaction.acceptBegin(try Message.parse(begin_bytes));
    try std.testing.expect(reply.requests.system.song_position);
    try std.testing.expect(reply.requests.channel.control_change);
    try std.testing.expect(!reply.requests.channel.program_change);
    try std.testing.expect(!reply.requests.note.notes);
    const end_message = try responder.end(inquiry);
    const end_bytes = try end_message.encode(&storage);
    try transaction.acceptEnd(try Message.parse(end_bytes));
    try std.testing.expectEqual(Transaction.State.complete, transaction.state);
}

test "MIDI-CI message report validates addressing and bitmaps" {
    try std.testing.expectError(
        error.InvalidMidiCiMessageReport,
        Transaction.init(.{
            .address = .{ .channel = 0 },
            .source = try midi_ci.Muid.init(1),
            .destination = try midi_ci.Muid.init(2),
            .data_control = .full,
            .requests = .{
                .system = .{ .mtc_quarter_frame = true },
            },
        }),
    );

    const message = Message{ .inquiry = .{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .data_control = .capability_only,
        .requests = .{ .channel = .{ .pitch_bend = true } },
    } };
    var storage: [18]u8 = undefined;
    const encoded = try message.encode(&storage);
    storage[13] = 2;
    try std.testing.expectError(
        error.InvalidMidiCiReportDataControl,
        Message.parse(encoded),
    );
    storage[13] = 0;
    storage[15] = 1;
    try std.testing.expectError(
        error.InvalidMidiCiMessageReportRequests,
        Message.parse(encoded),
    );
}

test "MIDI-CI message report rejects state and correlation errors transactionally" {
    const inquiry = Inquiry{
        .address = .group,
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .data_control = .full,
        .requests = .{ .channel = .{ .control_change = true } },
    };
    var transaction = try Transaction.init(inquiry);
    try std.testing.expectError(
        error.UnrequestedMidiCiReportMessages,
        transaction.acceptBegin(.{ .reply = .{
            .address = .group,
            .source = try midi_ci.Muid.init(2),
            .destination = try midi_ci.Muid.init(1),
            .requests = .{ .note = .{ .notes = true } },
        } }),
    );
    try std.testing.expectEqual(
        Transaction.State.awaiting_reply,
        transaction.state,
    );
    _ = try transaction.acceptBegin(.{ .reply = .{
        .address = .group,
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .requests = .{ .channel = .{ .control_change = true } },
    } });
    try std.testing.expectError(
        error.MidiCiMessageReportMismatch,
        transaction.acceptEnd(.{ .end = .{
            .address = .function_block,
            .source = try midi_ci.Muid.init(2),
            .destination = try midi_ci.Muid.init(1),
        } }),
    );
    try std.testing.expectEqual(Transaction.State.receiving, transaction.state);
}

test "MIDI-CI generated message report transactions preserve invariants" {
    var random = std.Random.DefaultPrng.init(0x5052_4F43_2D52_5054);
    var storage: [18]u8 = undefined;
    const controls = [_]DataControl{
        .capability_only,
        .non_default,
        .full,
    };
    for (0..32_768) |_| {
        const requests = Requests{
            .system = @bitCast(
                random.random().uintLessThan(u7, 1 << 3),
            ),
            .channel = @bitCast(
                random.random().uintLessThan(u7, 1 << 6),
            ),
            .note = @bitCast(
                random.random().uintLessThan(u7, 1 << 5),
            ),
        };
        const supported = Requests{
            .system = @bitCast(
                random.random().uintLessThan(u7, 1 << 3),
            ),
            .channel = @bitCast(
                random.random().uintLessThan(u7, 1 << 6),
            ),
            .note = @bitCast(
                random.random().uintLessThan(u7, 1 << 5),
            ),
        };
        const address: midi_ci.Address = if (requests.hasSystem())
            .function_block
        else switch (random.random().uintLessThan(u8, 3)) {
            0 => .{ .channel = random.random().int(u4) },
            1 => .group,
            else => .function_block,
        };
        const source_value =
            random.random().uintLessThan(u28, 0x0FFF_FF00);
        var destination_value =
            random.random().uintLessThan(u28, 0x0FFF_FF00);
        if (destination_value == source_value)
            destination_value = (destination_value + 1) % 0x0FFF_FF00;
        const inquiry = Inquiry{
            .address = address,
            .source = .{ .value = source_value },
            .destination = .{ .value = destination_value },
            .data_control = controls[
                random.random().uintLessThan(usize, controls.len)
            ],
            .requests = requests,
        };
        var transaction = try Transaction.init(inquiry);
        const responder = try Responder.init(
            inquiry.destination,
            supported,
        );
        const inquiry_bytes = try transaction.inquiry().encode(&storage);
        const begin = try responder.begin(try Message.parse(inquiry_bytes));
        const begin_bytes = try begin.encode(&storage);
        const reply = try transaction.acceptBegin(
            try Message.parse(begin_bytes),
        );
        try std.testing.expectEqualDeep(
            requests.intersection(supported),
            reply.requests,
        );
        const end_bytes = try (try responder.end(inquiry)).encode(&storage);
        try transaction.acceptEnd(try Message.parse(end_bytes));
        try std.testing.expectEqual(Transaction.State.complete, transaction.state);

        const arbitrary_length =
            random.random().uintLessThan(usize, storage.len + 1);
        random.random().bytes(&storage);
        for (&storage) |*byte| byte.* &= 0x7F;
        _ = Message.parse(storage[0..arbitrary_length]) catch {};
    }
}
