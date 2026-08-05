const std = @import("std");
const midi_ci = @import("midi_ci.zig");

pub const current_property_exchange_major: u7 = 1;
pub const current_property_exchange_minor: u7 = 2;

pub const Capabilities = struct {
    version: u5 = 2,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    simultaneous_requests: u7,
    property_exchange_major: u7 = 0,
    property_exchange_minor: u7 = 0,

    pub fn valid(self: Capabilities) bool {
        if ((self.version != 1 and self.version != 2) or
            !self.source.validSource() or
            !self.destination.validSource() or
            self.simultaneous_requests == 0)
            return false;
        return self.version == 2 or
            (self.property_exchange_major == 0 and
                self.property_exchange_minor == 0);
    }
};

pub const Kind = enum(u7) {
    inquiry = 0x30,
    reply = 0x31,
};

pub const Message = union(Kind) {
    inquiry: Capabilities,
    reply: Capabilities,

    pub fn capabilities(self: Message) Capabilities {
        return switch (self) {
            inline else => |value| value,
        };
    }

    pub fn encodedLength(self: Message) !usize {
        const value = self.capabilities();
        if (!value.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        return if (value.version == 1) 14 else 16;
    }

    pub fn encode(self: Message, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        const value = self.capabilities();
        destination[0] = 0x7E;
        destination[1] = 0x7F;
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(std.meta.activeTag(self));
        destination[4] = value.version;
        writeU28(destination[5..9], value.source.value);
        writeU28(destination[9..13], value.destination.value);
        destination[13] = value.simultaneous_requests;
        if (value.version == 2) {
            destination[14] = value.property_exchange_major;
            destination[15] = value.property_exchange_minor;
        }
        return destination[0..length];
    }

    pub fn parse(source: []const u8) !Message {
        if (source.len < 14) return error.TruncatedMidiCiMessage;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or
            source[1] != 0x7F or
            source[2] != 0x0D)
            return error.NotMidiCiPropertyExchange;
        const kind: Kind = switch (source[3]) {
            0x30 => .inquiry,
            0x31 => .reply,
            else => return error.NotMidiCiPropertyExchange,
        };
        if (source[4] != 1 and source[4] != 2)
            return error.UnsupportedMidiCiVersion;
        const version: u5 = @intCast(source[4]);
        const expected_length: usize = if (version == 1) 14 else 16;
        if (source.len != expected_length)
            return error.InvalidMidiCiMessageLength;
        const value = Capabilities{
            .version = version,
            .source = .{ .value = readU28(source[5..9]) },
            .destination = .{ .value = readU28(source[9..13]) },
            .simultaneous_requests = @intCast(source[13]),
            .property_exchange_major = if (version == 2)
                @intCast(source[14])
            else
                0,
            .property_exchange_minor = if (version == 2)
                @intCast(source[15])
            else
                0,
        };
        if (!value.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        return switch (kind) {
            .inquiry => .{ .inquiry = value },
            .reply => .{ .reply = value },
        };
    }
};

pub const Agreement = struct {
    simultaneous_requests: u7,
    property_exchange_compatible: bool,
    property_exchange_major: u7,
    property_exchange_minor: u7,
};

pub const Transaction = struct {
    inquiry_value: Capabilities,

    pub fn init(inquiry_value: Capabilities) !Transaction {
        if (!inquiry_value.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        if (inquiry_value.source.value == inquiry_value.destination.value)
            return error.MidiCiMuidCollision;
        return .{ .inquiry_value = inquiry_value };
    }

    pub fn inquiry(self: Transaction) Message {
        return .{ .inquiry = self.inquiry_value };
    }

    pub fn accept(self: Transaction, message: Message) !Agreement {
        const reply = switch (message) {
            .reply => |value| value,
            .inquiry => return error.UnexpectedMidiCiPropertyInquiry,
        };
        if (!reply.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        if (reply.source.value != self.inquiry_value.destination.value or
            reply.destination.value != self.inquiry_value.source.value or
            reply.version > self.inquiry_value.version)
            return error.MidiCiPropertyCapabilitiesMismatch;
        const same_major = reply.version == 2 and
            reply.property_exchange_major ==
                self.inquiry_value.property_exchange_major;
        const compatible = reply.version == 1 or same_major;
        return .{
            .simultaneous_requests = @min(
                reply.simultaneous_requests,
                self.inquiry_value.simultaneous_requests,
            ),
            .property_exchange_compatible = compatible,
            .property_exchange_major = if (compatible)
                reply.property_exchange_major
            else
                0,
            .property_exchange_minor = if (compatible)
                @min(
                    reply.property_exchange_minor,
                    self.inquiry_value.property_exchange_minor,
                )
            else
                0,
        };
    }
};

pub const Responder = struct {
    capabilities_value: Capabilities,

    pub fn init(capabilities_value: Capabilities) !Responder {
        if (!capabilities_value.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        return .{ .capabilities_value = capabilities_value };
    }

    pub fn handle(self: Responder, message: Message) !Message {
        const inquiry = switch (message) {
            .inquiry => |value| value,
            .reply => return error.UnexpectedMidiCiPropertyReply,
        };
        if (!inquiry.valid())
            return error.InvalidMidiCiPropertyCapabilities;
        if (inquiry.destination.value != self.capabilities_value.source.value)
            return error.MidiCiMuidMismatch;
        if (inquiry.source.value == self.capabilities_value.source.value)
            return error.MidiCiMuidCollision;
        const reply_version = @min(
            inquiry.version,
            self.capabilities_value.version,
        );
        return .{ .reply = .{
            .version = reply_version,
            .source = self.capabilities_value.source,
            .destination = inquiry.source,
            .simultaneous_requests = self.capabilities_value.simultaneous_requests,
            .property_exchange_major = if (reply_version == 2)
                self.capabilities_value.property_exchange_major
            else
                0,
            .property_exchange_minor = if (reply_version == 2)
                self.capabilities_value.property_exchange_minor
            else
                0,
        } };
    }
};

pub const DataKind = enum(u7) {
    get = 0x34,
    get_reply = 0x35,
    set = 0x36,
    set_reply = 0x37,
    subscription = 0x38,
    subscription_reply = 0x39,
    notify = 0x3F,

    fn fixedHeaderOnly(self: DataKind) bool {
        return self == .get or self == .set_reply;
    }
};

pub fn DataMessage(
    comptime header_capacity: usize,
    comptime data_capacity: usize,
) type {
    if (header_capacity > 0x3FFF or data_capacity > 0x3FFF)
        @compileError("MIDI-CI Property Exchange capacity exceeds u14");
    return struct {
        const Self = @This();

        kind: DataKind,
        version: u5 = 2,
        source: midi_ci.Muid,
        destination: midi_ci.Muid,
        request_id: u7,
        header_storage: [header_capacity]u8 = @splat(0),
        header_count: u14 = 0,
        total_chunks: u14 = 1,
        chunk_number: u14 = 1,
        data_storage: [data_capacity]u8 = @splat(0),
        data_count: u14 = 0,

        pub fn init(
            kind: DataKind,
            version: u5,
            source: midi_ci.Muid,
            destination: midi_ci.Muid,
            request_id: u7,
            header_data: []const u8,
            total_chunks: u14,
            chunk_number: u14,
            property_data: []const u8,
        ) !Self {
            if (header_data.len > header_capacity)
                return error.MidiCiPropertyHeaderCapacityExceeded;
            if (property_data.len > data_capacity)
                return error.MidiCiPropertyDataCapacityExceeded;
            var message = Self{
                .kind = kind,
                .version = version,
                .source = source,
                .destination = destination,
                .request_id = request_id,
                .header_count = @intCast(header_data.len),
                .total_chunks = total_chunks,
                .chunk_number = chunk_number,
                .data_count = @intCast(property_data.len),
            };
            for (header_data, 0..) |byte, index| {
                if (byte > 0x7F) return error.InvalidMidiCiDataByte;
                message.header_storage[index] = byte;
            }
            for (property_data, 0..) |byte, index| {
                if (byte > 0x7F) return error.InvalidMidiCiDataByte;
                message.data_storage[index] = byte;
            }
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            return message;
        }

        pub fn header(self: *const Self) []const u8 {
            if (!self.valid()) return &.{};
            return self.header_storage[0..self.header_count];
        }

        pub fn data(self: *const Self) []const u8 {
            if (!self.valid()) return &.{};
            return self.data_storage[0..self.data_count];
        }

        pub fn valid(self: Self) bool {
            if ((self.version != 1 and self.version != 2) or
                !self.source.validSource() or
                !self.destination.validSource() or
                self.header_count > header_capacity or
                self.data_count > data_capacity)
                return false;
            if (self.chunk_number == 0) {
                if (self.total_chunks == 0 or self.header_count != 0)
                    return false;
            } else if (self.total_chunks != 0 and
                self.chunk_number > self.total_chunks)
                return false;
            if (self.chunk_number > 1 and self.header_count != 0)
                return false;
            if (self.kind.fixedHeaderOnly() and
                (self.total_chunks != 1 or
                    self.chunk_number != 1 or
                    self.data_count != 0))
                return false;
            for (self.header_storage[0..self.header_count]) |byte| {
                if (byte > 0x7F) return false;
            }
            for (self.data_storage[0..self.data_count]) |byte| {
                if (byte > 0x7F) return false;
            }
            return true;
        }

        pub fn encodedLength(self: Self) !usize {
            if (!self.valid()) return error.InvalidMidiCiPropertyData;
            return 22 +
                @as(usize, self.header_count) +
                @as(usize, self.data_count);
        }

        pub fn encode(self: Self, destination: []u8) ![]const u8 {
            const length = try self.encodedLength();
            if (destination.len < length) return error.MidiCiBufferTooSmall;
            destination[0] = 0x7E;
            destination[1] = 0x7F;
            destination[2] = 0x0D;
            destination[3] = @intFromEnum(self.kind);
            destination[4] = self.version;
            writeU28(destination[5..9], self.source.value);
            writeU28(destination[9..13], self.destination.value);
            destination[13] = self.request_id;
            writeU14(destination[14..16], self.header_count);
            var offset: usize = 16;
            @memcpy(
                destination[offset .. offset + self.header_count],
                self.header(),
            );
            offset += self.header_count;
            writeU14(destination[offset .. offset + 2], self.total_chunks);
            offset += 2;
            writeU14(destination[offset .. offset + 2], self.chunk_number);
            offset += 2;
            writeU14(destination[offset .. offset + 2], self.data_count);
            offset += 2;
            @memcpy(
                destination[offset .. offset + self.data_count],
                self.data(),
            );
            return destination[0..length];
        }

        pub fn parse(source_bytes: []const u8) !Self {
            if (source_bytes.len < 22) return error.TruncatedMidiCiMessage;
            for (source_bytes) |byte| {
                if (byte > 0x7F) return error.InvalidMidiCiDataByte;
            }
            if (source_bytes[0] != 0x7E or
                source_bytes[1] != 0x7F or
                source_bytes[2] != 0x0D)
                return error.NotMidiCiPropertyExchange;
            const kind: DataKind = switch (source_bytes[3]) {
                0x34 => .get,
                0x35 => .get_reply,
                0x36 => .set,
                0x37 => .set_reply,
                0x38 => .subscription,
                0x39 => .subscription_reply,
                0x3F => .notify,
                else => return error.NotMidiCiPropertyData,
            };
            if (source_bytes[4] != 1 and source_bytes[4] != 2)
                return error.UnsupportedMidiCiVersion;
            const header_count = readU14(source_bytes[14..16]);
            if (header_count > header_capacity)
                return error.MidiCiPropertyHeaderCapacityExceeded;
            const chunk_fields_offset = 16 + @as(usize, header_count);
            if (chunk_fields_offset + 6 > source_bytes.len)
                return error.TruncatedMidiCiMessage;
            const data_count = readU14(
                source_bytes[chunk_fields_offset + 4 ..][0..2],
            );
            const expected_length =
                chunk_fields_offset + 6 + @as(usize, data_count);
            if (data_count > data_capacity)
                return error.MidiCiPropertyDataCapacityExceeded;
            if (source_bytes.len != expected_length)
                return error.InvalidMidiCiMessageLength;
            var message = Self{
                .kind = kind,
                .version = @intCast(source_bytes[4]),
                .source = .{ .value = readU28(source_bytes[5..9]) },
                .destination = .{ .value = readU28(source_bytes[9..13]) },
                .request_id = @intCast(source_bytes[13]),
                .header_count = header_count,
                .total_chunks = readU14(
                    source_bytes[chunk_fields_offset..][0..2],
                ),
                .chunk_number = readU14(
                    source_bytes[chunk_fields_offset + 2 ..][0..2],
                ),
                .data_count = data_count,
            };
            @memcpy(
                message.header_storage[0..header_count],
                source_bytes[16..chunk_fields_offset],
            );
            @memcpy(
                message.data_storage[0..data_count],
                source_bytes[chunk_fields_offset + 6 ..],
            );
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            return message;
        }
    };
}

pub const ChunkResult = enum {
    more,
    complete,
    aborted,
};

pub fn Reassembler(
    comptime header_capacity: usize,
    comptime data_capacity: usize,
) type {
    if (header_capacity > 0x3FFF or data_capacity > 0x3FFF)
        @compileError("MIDI-CI Property Exchange capacity exceeds u14");
    return struct {
        const Self = @This();

        started: bool = false,
        complete: bool = false,
        aborted: bool = false,
        kind: DataKind = .notify,
        version: u5 = 2,
        source: midi_ci.Muid = .{ .value = 0 },
        destination: midi_ci.Muid = .{ .value = 0 },
        request_id: u7 = 0,
        declared_total: u14 = 0,
        next_chunk: u14 = 1,
        header_storage: [header_capacity]u8 = @splat(0),
        header_count: u14 = 0,
        data_storage: [data_capacity]u8 = @splat(0),
        data_count: u14 = 0,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn validate(self: *const Self) !void {
            if (self.header_count > header_capacity or
                self.data_count > data_capacity)
            {
                return error.InvalidMidiCiPropertyReassemblyState;
            }
            if (!self.started) {
                if (self.complete or self.aborted or
                    self.header_count != 0 or self.data_count != 0 or
                    self.declared_total != 0 or self.next_chunk != 1)
                {
                    return error.InvalidMidiCiPropertyReassemblyState;
                }
                return;
            }
            if ((self.version != 1 and self.version != 2) or
                !self.source.validSource() or
                !self.destination.validSource() or
                (self.aborted and !self.complete))
            {
                return error.InvalidMidiCiPropertyReassemblyState;
            }
            if (self.kind.fixedHeaderOnly()) {
                if (!self.complete or self.aborted or
                    self.declared_total != 1 or self.next_chunk != 1 or
                    self.data_count != 0)
                {
                    return error.InvalidMidiCiPropertyReassemblyState;
                }
            } else if (self.complete and !self.aborted) {
                if (self.declared_total == 0 or
                    self.next_chunk != self.declared_total)
                {
                    return error.InvalidMidiCiPropertyReassemblyState;
                }
            } else if (self.next_chunk < 2 or
                (self.declared_total != 0 and
                    self.next_chunk > self.declared_total))
            {
                return error.InvalidMidiCiPropertyReassemblyState;
            }
            for (self.header_storage[0..self.header_count]) |byte| {
                if (byte > 0x7F)
                    return error.InvalidMidiCiPropertyReassemblyState;
            }
            for (self.data_storage[0..self.data_count]) |byte| {
                if (byte > 0x7F)
                    return error.InvalidMidiCiPropertyReassemblyState;
            }
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        pub fn header(self: *const Self) []const u8 {
            if (!self.valid() or !self.started or self.aborted) return &.{};
            return self.header_storage[0..self.header_count];
        }

        pub fn data(self: *const Self) []const u8 {
            if (!self.valid() or !self.started or self.aborted) return &.{};
            return self.data_storage[0..self.data_count];
        }

        pub fn push(self: *Self, message: anytype) !ChunkResult {
            try self.validate();
            if (self.complete)
                return error.InvalidMidiCiPropertyReassemblyState;
            if (!message.valid()) return error.InvalidMidiCiPropertyData;
            if (!self.started) {
                if (message.chunk_number != 1)
                    return error.InvalidMidiCiPropertyChunkSequence;
                if (message.header_count > header_capacity or
                    message.data_count > data_capacity)
                    return error.MidiCiPropertyReassemblyCapacityExceeded;
            } else {
                if (message.kind != self.kind or
                    message.version != self.version or
                    message.source.value != self.source.value or
                    message.destination.value != self.destination.value or
                    message.request_id != self.request_id)
                    return error.MidiCiPropertyChunkMismatch;
                if (message.header_count != 0)
                    return error.InvalidMidiCiPropertyChunkSequence;
                if (message.chunk_number == 0) {
                    self.complete = true;
                    self.aborted = true;
                    return .aborted;
                }
                if (message.chunk_number != self.next_chunk)
                    return error.InvalidMidiCiPropertyChunkSequence;
                if (self.declared_total == 0) {
                    if (message.total_chunks != 0 and
                        message.total_chunks != message.chunk_number)
                        return error.InvalidMidiCiPropertyChunkSequence;
                } else if (message.total_chunks != self.declared_total and
                    message.total_chunks != message.chunk_number)
                    return error.InvalidMidiCiPropertyChunkSequence;
                if (@as(usize, self.data_count) +
                    @as(usize, message.data_count) > data_capacity)
                    return error.MidiCiPropertyReassemblyCapacityExceeded;
            }
            const final = message.total_chunks != 0 and
                message.chunk_number == message.total_chunks;
            if (!final and message.chunk_number == std.math.maxInt(u14))
                return error.InvalidMidiCiPropertyChunkSequence;

            if (!self.started) {
                self.started = true;
                self.kind = message.kind;
                self.version = message.version;
                self.source = message.source;
                self.destination = message.destination;
                self.request_id = message.request_id;
                self.header_count = message.header_count;
                @memcpy(
                    self.header_storage[0..message.header_count],
                    message.header(),
                );
            }
            @memcpy(
                self.data_storage[self.data_count .. self.data_count + message.data_count],
                message.data(),
            );
            self.data_count += message.data_count;
            if (message.total_chunks != 0)
                self.declared_total = message.total_chunks;
            if (final) {
                self.complete = true;
                return .complete;
            }
            self.next_chunk = message.chunk_number + 1;
            return .more;
        }
    };
}

pub fn RequestIds(comptime capacity: usize) type {
    if (capacity == 0 or capacity > 127)
        @compileError("MIDI-CI Property Exchange request capacity must be 1 through 127");
    return struct {
        const Self = @This();

        active: std.StaticBitSet(capacity) =
            std.StaticBitSet(capacity).initEmpty(),
        next: u7 = 0,

        pub fn acquire(self: *Self) !u7 {
            if (!self.valid()) return error.InvalidMidiCiPropertyRequestIdsState;
            for (0..capacity) |offset| {
                const index =
                    (@as(usize, self.next) + offset) % capacity;
                if (!self.active.isSet(index)) {
                    self.active.set(index);
                    self.next = @intCast((index + 1) % capacity);
                    return @intCast(index);
                }
            }
            return error.MidiCiPropertyRequestIdsExhausted;
        }

        pub fn release(self: *Self, request_id: u7) !void {
            if (!self.valid()) return error.InvalidMidiCiPropertyRequestIdsState;
            if (request_id >= capacity or
                !self.active.isSet(request_id))
                return error.InvalidMidiCiPropertyRequestId;
            self.active.unset(request_id);
        }

        pub fn isActive(self: Self, request_id: u7) bool {
            return self.valid() and request_id < capacity and self.active.isSet(request_id);
        }

        pub fn count(self: Self) usize {
            if (!self.valid()) return 0;
            return self.active.count();
        }

        pub fn valid(self: Self) bool {
            if (self.next >= capacity) return false;
            var active_count: usize = 0;
            for (0..capacity) |request_id| {
                if (self.active.isSet(request_id)) active_count += 1;
            }
            return active_count == self.active.count();
        }
    };
}

fn writeU14(destination: []u8, value: u14) void {
    destination[0] = @intCast(value & 0x7F);
    destination[1] = @intCast(value >> 7);
}

fn readU14(source: []const u8) u14 {
    return @as(u14, @intCast(source[0])) |
        (@as(u14, @intCast(source[1])) << 7);
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

test "MIDI-CI Property Exchange capabilities transact over wire" {
    const transaction = try Transaction.init(.{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .simultaneous_requests = 4,
        .property_exchange_minor = 2,
    });
    const responder = try Responder.init(.{
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .simultaneous_requests = 2,
        .property_exchange_minor = 1,
    });
    var storage: [16]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&storage);
    const reply_message =
        try responder.handle(try Message.parse(inquiry_bytes));
    const reply_bytes = try reply_message.encode(&storage);
    const agreement = try transaction.accept(
        try Message.parse(reply_bytes),
    );
    try std.testing.expectEqual(@as(u7, 2), agreement.simultaneous_requests);
    try std.testing.expect(agreement.property_exchange_compatible);
    try std.testing.expectEqual(@as(u7, 0), agreement.property_exchange_major);
    try std.testing.expectEqual(@as(u7, 1), agreement.property_exchange_minor);
}

test "MIDI-CI Property Exchange capabilities cover versions and limits" {
    var storage: [16]u8 = undefined;
    for (1..3) |version| {
        for (1..128) |request_count| {
            const message = Message{ .inquiry = .{
                .version = @intCast(version),
                .source = try midi_ci.Muid.init(1),
                .destination = try midi_ci.Muid.init(2),
                .simultaneous_requests = @intCast(request_count),
            } };
            const encoded = try message.encode(&storage);
            try std.testing.expectEqual(
                if (version == 1) @as(usize, 14) else 16,
                encoded.len,
            );
            try std.testing.expectEqualDeep(
                message,
                try Message.parse(encoded),
            );
        }
    }
}

test "MIDI-CI Property Exchange capabilities reject malformed messages" {
    var storage: [16]u8 = .{0x55} ** 16;
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCapabilities,
        (Message{ .inquiry = .{
            .source = try midi_ci.Muid.init(1),
            .destination = try midi_ci.Muid.init(2),
            .simultaneous_requests = 0,
        } }).encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    storage = .{
        0x7E, 0x7F, 0x0D, 0x30, 0x02, 0x01, 0, 0,
        0,    0x02, 0,    0,    0,    0x01, 0, 0,
    };
    storage[1] = 0x0F;
    try std.testing.expectError(
        error.NotMidiCiPropertyExchange,
        Message.parse(&storage),
    );
    storage[1] = 0x7F;
    storage[15] = 0x80;
    try std.testing.expectError(
        error.InvalidMidiCiDataByte,
        Message.parse(&storage),
    );
}

test "MIDI-CI Property Exchange capability correlation is transactional" {
    const transaction = try Transaction.init(.{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .simultaneous_requests = 1,
    });
    try std.testing.expectError(
        error.MidiCiPropertyCapabilitiesMismatch,
        transaction.accept(.{ .reply = .{
            .source = try midi_ci.Muid.init(3),
            .destination = try midi_ci.Muid.init(1),
            .simultaneous_requests = 1,
        } }),
    );
    const agreement = try transaction.accept(.{ .reply = .{
        .version = 1,
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .simultaneous_requests = 1,
    } });
    try std.testing.expectEqual(@as(u7, 1), agreement.simultaneous_requests);
    try std.testing.expect(agreement.property_exchange_compatible);
    const incompatible = try transaction.accept(.{ .reply = .{
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .simultaneous_requests = 1,
        .property_exchange_major = 1,
    } });
    try std.testing.expect(!incompatible.property_exchange_compatible);
}

test "MIDI-CI Property Exchange data messages round trip every kind" {
    const PropertyData = DataMessage(16, 32);
    const kinds = [_]DataKind{
        .get,
        .get_reply,
        .set,
        .set_reply,
        .subscription,
        .subscription_reply,
        .notify,
    };
    var storage: [70]u8 = undefined;
    for (kinds) |kind| {
        for (1..3) |version| {
            const fixed = kind.fixedHeaderOnly();
            const message = try PropertyData.init(
                kind,
                @intCast(version),
                try midi_ci.Muid.init(1),
                try midi_ci.Muid.init(2),
                7,
                &.{ 1, 2, 3 },
                if (fixed) 1 else 3,
                1,
                if (fixed) &.{} else &.{ 4, 5, 6, 7 },
            );
            const encoded = try message.encode(&storage);
            const parsed = try PropertyData.parse(encoded);
            try std.testing.expectEqual(message.kind, parsed.kind);
            try std.testing.expectEqualSlices(
                u8,
                message.header(),
                parsed.header(),
            );
            try std.testing.expectEqualSlices(
                u8,
                message.data(),
                parsed.data(),
            );
            for (message.header_storage[message.header_count..]) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
            for (message.data_storage[message.data_count..]) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
            for (parsed.header_storage[parsed.header_count..]) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
            for (parsed.data_storage[parsed.data_count..]) |byte|
                try std.testing.expectEqual(@as(u8, 0), byte);
        }
    }
}

test "MIDI-CI Property Exchange data messages cover payload boundaries" {
    const PropertyData = DataMessage(8, 8);
    var bytes: [8]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @intCast(index);
    var storage: [38]u8 = undefined;
    for (0..9) |header_length| {
        for (0..9) |data_length| {
            const message = try PropertyData.init(
                .set,
                2,
                try midi_ci.Muid.init(1),
                try midi_ci.Muid.init(2),
                1,
                bytes[0..header_length],
                1,
                1,
                bytes[0..data_length],
            );
            const encoded = try message.encode(&storage);
            const parsed = try PropertyData.parse(encoded);
            try std.testing.expectEqual(
                @as(usize, 22 + header_length + data_length),
                encoded.len,
            );
            try std.testing.expectEqualSlices(
                u8,
                message.header(),
                parsed.header(),
            );
            try std.testing.expectEqualSlices(
                u8,
                message.data(),
                parsed.data(),
            );
        }
    }
}

test "MIDI-CI Property Exchange data messages reject invalid chunks" {
    const PropertyData = DataMessage(8, 8);
    const source = try midi_ci.Muid.init(1);
    const destination = try midi_ci.Muid.init(2);
    try std.testing.expectError(
        error.InvalidMidiCiPropertyData,
        PropertyData.init(
            .set,
            2,
            source,
            destination,
            1,
            &.{1},
            2,
            2,
            &.{2},
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyData,
        PropertyData.init(
            .get,
            2,
            source,
            destination,
            1,
            &.{1},
            2,
            1,
            &.{2},
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiDataByte,
        PropertyData.init(
            .notify,
            2,
            source,
            destination,
            1,
            &.{0x80},
            1,
            1,
            &.{},
        ),
    );
    var storage: [22]u8 = .{
        0x7E, 0x7F, 0x0D, 0x36, 0x02, 0x01, 0, 0,
        0,    0x02, 0,    0,    0,    1,    0, 0,
        1,    0,    1,    0,    0,    0,
    };
    storage[18] = 2;
    try std.testing.expectError(
        error.InvalidMidiCiPropertyData,
        PropertyData.parse(&storage),
    );
}

test "MIDI-CI Property Exchange reassembles known and unknown chunk counts" {
    const PropertyData = DataMessage(8, 8);
    const PropertyReassembler = Reassembler(8, 16);
    const source = try midi_ci.Muid.init(2);
    const destination = try midi_ci.Muid.init(1);
    var known = PropertyReassembler{};
    try std.testing.expectEqual(
        ChunkResult.more,
        try known.push(try PropertyData.init(
            .get_reply,
            2,
            source,
            destination,
            4,
            &.{ 1, 2 },
            2,
            1,
            &.{ 3, 4 },
        )),
    );
    try std.testing.expectEqual(
        ChunkResult.complete,
        try known.push(try PropertyData.init(
            .get_reply,
            2,
            source,
            destination,
            4,
            &.{},
            2,
            2,
            &.{ 5, 6 },
        )),
    );
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, known.header());
    try std.testing.expectEqualSlices(
        u8,
        &.{ 3, 4, 5, 6 },
        known.data(),
    );
    known.reset();
    try std.testing.expect(!known.started);
    try std.testing.expectEqual(@as(u14, 0), known.header_count);
    try std.testing.expectEqual(@as(u14, 0), known.data_count);
    for (known.header_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);
    for (known.data_storage) |byte|
        try std.testing.expectEqual(@as(u8, 0), byte);

    var unknown = PropertyReassembler{};
    try std.testing.expectEqual(
        ChunkResult.more,
        try unknown.push(try PropertyData.init(
            .subscription,
            2,
            source,
            destination,
            5,
            &.{1},
            0,
            1,
            &.{2},
        )),
    );
    try std.testing.expectEqual(
        ChunkResult.complete,
        try unknown.push(try PropertyData.init(
            .subscription,
            2,
            source,
            destination,
            5,
            &.{},
            2,
            2,
            &.{3},
        )),
    );
    try std.testing.expectEqualSlices(u8, &.{ 2, 3 }, unknown.data());
}

test "MIDI-CI Property Exchange reassembly rejects mismatches transactionally" {
    const PropertyData = DataMessage(8, 8);
    const PropertyReassembler = Reassembler(8, 3);
    const source = try midi_ci.Muid.init(2);
    const destination = try midi_ci.Muid.init(1);
    var reassembler = PropertyReassembler{};
    _ = try reassembler.push(try PropertyData.init(
        .get_reply,
        2,
        source,
        destination,
        1,
        &.{1},
        3,
        1,
        &.{2},
    ));
    try std.testing.expectError(
        error.MidiCiPropertyChunkMismatch,
        reassembler.push(try PropertyData.init(
            .get_reply,
            2,
            source,
            destination,
            2,
            &.{},
            3,
            2,
            &.{3},
        )),
    );
    try std.testing.expectEqualSlices(u8, &.{2}, reassembler.data());
    reassembler.next_chunk = 1;
    try std.testing.expectError(
        error.InvalidMidiCiPropertyReassemblyState,
        reassembler.validate(),
    );
    try std.testing.expectEqual(@as(usize, 0), reassembler.data().len);
    try std.testing.expectError(
        error.InvalidMidiCiPropertyReassemblyState,
        reassembler.push(try PropertyData.init(
            .get_reply,
            2,
            source,
            destination,
            1,
            &.{},
            3,
            2,
            &.{3},
        )),
    );
    try std.testing.expectEqual(@as(u14, 1), reassembler.next_chunk);
    reassembler.next_chunk = 2;
    reassembler.data_storage[0] = 0x80;
    try std.testing.expect(!reassembler.valid());
    reassembler.data_storage[0] = 2;
    try reassembler.validate();
    try std.testing.expectError(
        error.MidiCiPropertyReassemblyCapacityExceeded,
        reassembler.push(try PropertyData.init(
            .get_reply,
            2,
            source,
            destination,
            1,
            &.{},
            3,
            2,
            &.{ 3, 4, 5 },
        )),
    );
    try std.testing.expectEqualSlices(u8, &.{2}, reassembler.data());

    var malformed = PropertyReassembler{};
    malformed.started = true;
    malformed.header_count = std.math.maxInt(u14);
    malformed.data_count = std.math.maxInt(u14);
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.header().len);
    try std.testing.expectEqual(@as(usize, 0), malformed.data().len);
    const next_message = try PropertyData.init(
        .get_reply,
        2,
        source,
        destination,
        1,
        &.{1},
        1,
        1,
        &.{2},
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyReassemblyState,
        malformed.push(next_message),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u14),
        malformed.header_count,
    );
    try std.testing.expectEqual(
        std.math.maxInt(u14),
        malformed.data_count,
    );
}

test "MIDI-CI Property Exchange reassembly reports aborted data" {
    const PropertyData = DataMessage(8, 8);
    const PropertyReassembler = Reassembler(8, 8);
    const source = try midi_ci.Muid.init(2);
    const destination = try midi_ci.Muid.init(1);
    var reassembler = PropertyReassembler{};
    _ = try reassembler.push(try PropertyData.init(
        .subscription_reply,
        2,
        source,
        destination,
        1,
        &.{1},
        3,
        1,
        &.{2},
    ));
    try std.testing.expectEqual(
        ChunkResult.aborted,
        try reassembler.push(try PropertyData.init(
            .subscription_reply,
            2,
            source,
            destination,
            1,
            &.{},
            3,
            0,
            &.{},
        )),
    );
    try std.testing.expect(reassembler.complete);
    try std.testing.expect(reassembler.aborted);
    try std.testing.expectEqual(@as(usize, 0), reassembler.data().len);
}

test "MIDI-CI Property Exchange request IDs are bounded and reusable" {
    const PropertyRequestIds = RequestIds(4);
    var request_ids = PropertyRequestIds{};
    for (0..4) |expected| {
        try std.testing.expectEqual(
            @as(u7, @intCast(expected)),
            try request_ids.acquire(),
        );
    }
    try std.testing.expectError(
        error.MidiCiPropertyRequestIdsExhausted,
        request_ids.acquire(),
    );
    try request_ids.release(1);
    try std.testing.expectEqual(@as(u7, 1), try request_ids.acquire());
    try std.testing.expect(request_ids.isActive(1));
    try std.testing.expectEqual(@as(usize, 4), request_ids.count());
    try std.testing.expectError(
        error.InvalidMidiCiPropertyRequestId,
        request_ids.release(7),
    );

    request_ids.next = 4;
    try std.testing.expect(!request_ids.valid());
    try std.testing.expectEqual(@as(usize, 0), request_ids.count());
    try std.testing.expect(!request_ids.isActive(1));
    try std.testing.expectError(
        error.InvalidMidiCiPropertyRequestIdsState,
        request_ids.acquire(),
    );
    try std.testing.expectError(
        error.InvalidMidiCiPropertyRequestIdsState,
        request_ids.release(1),
    );
    request_ids.next = 0;
    try std.testing.expect(request_ids.valid());
    try request_ids.release(1);
}
