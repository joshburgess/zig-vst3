const std = @import("std");
const stream = @import("midi_stream.zig");

pub const broadcast_muid: u28 = 0x0FFF_FFFF;
const reserved_muid_start: u28 = 0x0FFF_FF00;

pub const Muid = struct {
    value: u28,

    pub fn init(value: u32) !Muid {
        if (value > broadcast_muid) return error.InvalidMidiCiMuid;
        const muid = Muid{ .value = @intCast(value) };
        if (!muid.validSource()) return error.InvalidMidiCiMuid;
        return muid;
    }

    pub fn broadcast() Muid {
        return .{ .value = broadcast_muid };
    }

    pub fn validSource(self: Muid) bool {
        return self.value < reserved_muid_start;
    }

    pub fn isBroadcast(self: Muid) bool {
        return self.value == broadcast_muid;
    }
};

pub const Categories = packed struct(u7) {
    reserved_zero: bool = false,
    deprecated_protocol_negotiation: bool = false,
    profile_configuration: bool = false,
    property_exchange: bool = false,
    process_inquiry: bool = false,
    reserved_five: bool = false,
    reserved_six: bool = false,

    pub fn valid(self: Categories) bool {
        return !self.reserved_zero and !self.reserved_five and !self.reserved_six;
    }
};

pub const Participant = struct {
    version: u5 = 2,
    muid: Muid,
    identity: stream.DeviceIdentity,
    categories: Categories = .{},
    maximum_sysex_size: u28 = 128,

    pub fn valid(self: Participant) bool {
        return self.version >= 1 and
            self.version <= 2 and
            self.muid.validSource() and
            self.categories.valid() and
            self.maximum_sysex_size >= 128;
    }
};

pub const Discovery = struct {
    participant: Participant,
    output_path: u7 = 0,
};

pub const Reply = struct {
    participant: Participant,
    destination: Muid,
    output_path: u7 = 0,
    function_block: ?u5 = null,
};

pub const Kind = enum(u7) {
    discovery = 0x70,
    reply = 0x71,
};

pub const Message = union(Kind) {
    discovery: Discovery,
    reply: Reply,

    pub fn encodedLength(self: Message) !usize {
        try validateMessage(self);
        return switch (self) {
            .discovery => |value| if (value.participant.version == 1) 29 else 30,
            .reply => |value| if (value.participant.version == 1) 29 else 31,
        };
    }

    pub fn encode(self: Message, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;

        const participant = switch (self) {
            .discovery => |value| value.participant,
            .reply => |value| value.participant,
        };
        destination[0] = 0x7E;
        destination[1] = 0x7F;
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(std.meta.activeTag(self));
        destination[4] = participant.version;
        writeU28(destination[5..9], participant.muid.value);
        writeU28(destination[9..13], switch (self) {
            .discovery => broadcast_muid,
            .reply => |value| value.destination.value,
        });
        writeU7(destination[13..16], &participant.identity.manufacturer);
        writeU7(destination[16..18], &participant.identity.family);
        writeU7(destination[18..20], &participant.identity.model);
        writeU7(destination[20..24], &participant.identity.revision);
        destination[24] = @as(u7, @bitCast(participant.categories));
        writeU28(destination[25..29], participant.maximum_sysex_size);

        if (participant.version >= 2) {
            switch (self) {
                .discovery => |value| destination[29] = value.output_path,
                .reply => |value| {
                    destination[29] = value.output_path;
                    destination[30] = if (value.function_block) |block| block else 0x7F;
                },
            }
        }
        return destination[0..length];
    }

    pub fn parse(source: anytype) !Message {
        if (source.len < 29) return error.TruncatedMidiCiMessage;
        for (source) |value| {
            if (value > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or source[1] != 0x7F or source[2] != 0x0D)
            return error.NotMidiCiDiscovery;

        const kind: Kind = switch (source[3]) {
            0x70 => .discovery,
            0x71 => .reply,
            else => return error.NotMidiCiDiscovery,
        };
        const version = source[4];
        if (version < 1 or version > 2) return error.UnsupportedMidiCiVersion;
        const expected_length: usize = switch (kind) {
            .discovery => if (version == 1) 29 else 30,
            .reply => if (version == 1) 29 else 31,
        };
        if (source.len != expected_length) return error.InvalidMidiCiMessageLength;

        const participant = Participant{
            .version = @intCast(version),
            .muid = .{ .value = readU28(source[5..9]) },
            .identity = .{
                .manufacturer = copyU7(3, source[13..16]),
                .family = copyU7(2, source[16..18]),
                .model = copyU7(2, source[18..20]),
                .revision = copyU7(4, source[20..24]),
            },
            .categories = @bitCast(@as(u7, @intCast(source[24]))),
            .maximum_sysex_size = readU28(source[25..29]),
        };
        if (!participant.valid()) return error.InvalidMidiCiParticipant;

        return switch (kind) {
            .discovery => blk: {
                if (readU28(source[9..13]) != broadcast_muid)
                    return error.InvalidMidiCiDiscoveryDestination;
                break :blk .{ .discovery = .{
                    .participant = participant,
                    .output_path = if (version >= 2) @intCast(source[29]) else 0,
                } };
            },
            .reply => blk: {
                const destination = Muid{ .value = readU28(source[9..13]) };
                if (!destination.validSource())
                    return error.InvalidMidiCiReplyDestination;
                const function_block: ?u5 = if (version == 1 or source[30] == 0x7F)
                    null
                else if (source[30] <= 31)
                    @intCast(source[30])
                else
                    return error.InvalidMidiCiFunctionBlock;
                break :blk .{ .reply = .{
                    .participant = participant,
                    .destination = destination,
                    .output_path = if (version >= 2) @intCast(source[29]) else 0,
                    .function_block = function_block,
                } };
            },
        };
    }
};

pub const DiscoveryTransaction = struct {
    initiator: Participant,
    output_path: u7,

    pub fn init(initiator: Participant, output_path: u7) !DiscoveryTransaction {
        if (!initiator.valid()) return error.InvalidMidiCiParticipant;
        if (initiator.version == 1 and output_path != 0)
            return error.UnsupportedMidiCiVersionField;
        return .{ .initiator = initiator, .output_path = output_path };
    }

    pub fn inquiry(self: DiscoveryTransaction) Message {
        return .{ .discovery = .{
            .participant = self.initiator,
            .output_path = self.output_path,
        } };
    }

    pub fn accept(self: DiscoveryTransaction, message: Message) !Reply {
        try validateMessage(message);
        const reply = switch (message) {
            .reply => |value| value,
            .discovery => return error.UnexpectedMidiCiDiscovery,
        };
        if (reply.destination.value != self.initiator.muid.value)
            return error.MidiCiMuidMismatch;
        if (reply.participant.muid.value == self.initiator.muid.value)
            return error.MidiCiMuidCollision;
        if (reply.participant.version >= 2 and reply.output_path != self.output_path)
            return error.MidiCiOutputPathMismatch;
        return reply;
    }
};

pub const DiscoveryResponder = struct {
    participant: Participant,
    function_block: ?u5 = null,

    pub fn init(
        participant: Participant,
        function_block: ?u5,
    ) !DiscoveryResponder {
        if (!participant.valid()) return error.InvalidMidiCiParticipant;
        if (participant.version == 1 and function_block != null)
            return error.UnsupportedMidiCiVersionField;
        return .{ .participant = participant, .function_block = function_block };
    }

    pub fn handle(self: DiscoveryResponder, message: Message) !Message {
        try validateMessage(message);
        const discovery = switch (message) {
            .discovery => |value| value,
            .reply => return error.UnexpectedMidiCiReply,
        };
        if (discovery.participant.muid.value == self.participant.muid.value)
            return error.MidiCiMuidCollision;
        return .{ .reply = .{
            .participant = self.participant,
            .destination = discovery.participant.muid,
            .output_path = if (self.participant.version >= 2)
                discovery.output_path
            else
                0,
            .function_block = self.function_block,
        } };
    }
};

pub const Invalidation = struct {
    version: u5 = 2,
    source: Muid,
    target: Muid,

    pub fn valid(self: Invalidation) bool {
        return self.version >= 1 and
            self.version <= 2 and
            self.source.validSource() and
            self.target.validSource();
    }

    pub fn encode(self: Invalidation, destination: []u8) ![]const u8 {
        if (!self.valid()) return error.InvalidMidiCiInvalidation;
        if (destination.len < 17) return error.MidiCiBufferTooSmall;
        destination[0] = 0x7E;
        destination[1] = 0x7F;
        destination[2] = 0x0D;
        destination[3] = 0x7E;
        destination[4] = self.version;
        writeU28(destination[5..9], self.source.value);
        writeU28(destination[9..13], broadcast_muid);
        writeU28(destination[13..17], self.target.value);
        return destination[0..17];
    }

    pub fn parse(source: anytype) !Invalidation {
        if (source.len != 17) return error.InvalidMidiCiMessageLength;
        for (source) |value| {
            if (value > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or
            source[1] != 0x7F or
            source[2] != 0x0D or
            source[3] != 0x7E)
            return error.NotMidiCiInvalidation;
        if (source[4] < 1 or source[4] > 2)
            return error.UnsupportedMidiCiVersion;
        if (readU28(source[9..13]) != broadcast_muid)
            return error.InvalidMidiCiInvalidationDestination;
        const invalidation = Invalidation{
            .version = @intCast(source[4]),
            .source = .{ .value = readU28(source[5..9]) },
            .target = .{ .value = readU28(source[13..17]) },
        };
        if (!invalidation.valid()) return error.InvalidMidiCiInvalidation;
        return invalidation;
    }

    pub fn targets(self: Invalidation, muid: Muid) bool {
        return self.valid() and muid.validSource() and self.target.value == muid.value;
    }
};

pub const ProductInstanceId = struct {
    storage: [16]u7 = .{0} ** 16,
    count: u5 = 0,

    pub fn init(source: []const u8) !ProductInstanceId {
        if (source.len > 16) return error.MidiCiProductInstanceIdTooLong;
        var value = ProductInstanceId{ .count = @intCast(source.len) };
        for (source, 0..) |byte, index| {
            if (byte < 32 or byte > 126)
                return error.InvalidMidiCiProductInstanceId;
            value.storage[index] = @intCast(byte);
        }
        return value;
    }

    pub fn text(self: *const ProductInstanceId) []const u7 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: ProductInstanceId) bool {
        if (self.count > self.storage.len) return false;
        for (self.storage[0..self.count]) |byte| {
            if (byte < 32 or byte > 126) return false;
        }
        for (self.storage[self.count..]) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    fn parse(source: anytype) !ProductInstanceId {
        if (source.len > 16) return error.MidiCiProductInstanceIdTooLong;
        var value = ProductInstanceId{ .count = @intCast(source.len) };
        for (source, 0..) |byte, index| {
            if (byte < 32 or byte > 126)
                return error.InvalidMidiCiProductInstanceId;
            value.storage[index] = @intCast(byte);
        }
        return value;
    }
};

pub const EndpointInformationInquiry = struct {
    version: u5 = 2,
    source: Muid,
    destination: Muid,
};

pub const EndpointInformationReply = struct {
    version: u5 = 2,
    source: Muid,
    destination: Muid,
    product_instance_id: ProductInstanceId,
};

pub const EndpointInformationKind = enum(u7) {
    inquiry = 0x72,
    reply = 0x73,
};

pub const EndpointInformationMessage = union(EndpointInformationKind) {
    inquiry: EndpointInformationInquiry,
    reply: EndpointInformationReply,

    pub fn encodedLength(self: EndpointInformationMessage) !usize {
        try validateEndpointInformation(self);
        return switch (self) {
            .inquiry => 14,
            .reply => |value| 16 + @as(usize, value.product_instance_id.count),
        };
    }

    pub fn encode(
        self: EndpointInformationMessage,
        destination: []u8,
    ) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        const header = switch (self) {
            .inquiry => |value| value,
            .reply => |value| EndpointInformationInquiry{
                .version = value.version,
                .source = value.source,
                .destination = value.destination,
            },
        };
        destination[0] = 0x7E;
        destination[1] = 0x7F;
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(std.meta.activeTag(self));
        destination[4] = header.version;
        writeU28(destination[5..9], header.source.value);
        writeU28(destination[9..13], header.destination.value);
        destination[13] = 0;
        switch (self) {
            .inquiry => {},
            .reply => |value| {
                destination[14] = value.product_instance_id.count;
                destination[15] = 0;
                writeU7(
                    destination[16..length],
                    value.product_instance_id.text(),
                );
            },
        }
        return destination[0..length];
    }

    pub fn parse(source: anytype) !EndpointInformationMessage {
        if (source.len < 14) return error.TruncatedMidiCiMessage;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or source[1] != 0x7F or source[2] != 0x0D)
            return error.NotMidiCiEndpointInformation;
        if (source[4] != 2) return error.UnsupportedMidiCiVersion;
        const kind: EndpointInformationKind = switch (source[3]) {
            0x72 => .inquiry,
            0x73 => .reply,
            else => return error.NotMidiCiEndpointInformation,
        };
        if (source[13] != 0) return error.UnsupportedMidiCiEndpointStatus;
        const header = EndpointInformationInquiry{
            .source = .{ .value = readU28(source[5..9]) },
            .destination = .{ .value = readU28(source[9..13]) },
        };
        if (!validEndpointHeader(header))
            return error.InvalidMidiCiEndpointInformation;
        return switch (kind) {
            .inquiry => {
                if (source.len != 14) return error.InvalidMidiCiMessageLength;
                return .{ .inquiry = header };
            },
            .reply => {
                if (source.len < 16) return error.TruncatedMidiCiMessage;
                const information_length =
                    @as(usize, source[14]) | (@as(usize, source[15]) << 7);
                if (information_length > 16 or source.len != 16 + information_length)
                    return error.InvalidMidiCiMessageLength;
                return .{ .reply = .{
                    .source = header.source,
                    .destination = header.destination,
                    .product_instance_id = try ProductInstanceId.parse(
                        source[16..],
                    ),
                } };
            },
        };
    }
};

pub const EndpointInformationTransaction = struct {
    source: Muid,
    destination: Muid,

    pub fn init(
        source: Muid,
        destination: Muid,
    ) !EndpointInformationTransaction {
        const header = EndpointInformationInquiry{
            .source = source,
            .destination = destination,
        };
        if (!validEndpointHeader(header))
            return error.InvalidMidiCiEndpointInformation;
        return .{ .source = source, .destination = destination };
    }

    pub fn inquiry(self: EndpointInformationTransaction) EndpointInformationMessage {
        return .{ .inquiry = .{
            .source = self.source,
            .destination = self.destination,
        } };
    }

    pub fn accept(
        self: EndpointInformationTransaction,
        message: EndpointInformationMessage,
    ) !EndpointInformationReply {
        try validateEndpointInformation(message);
        const reply = switch (message) {
            .reply => |value| value,
            .inquiry => return error.UnexpectedMidiCiEndpointInquiry,
        };
        if (reply.source.value != self.destination.value or
            reply.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        return reply;
    }
};

pub const EndpointInformationResponder = struct {
    source: Muid,
    product_instance_id: ProductInstanceId,

    pub fn init(
        source: Muid,
        product_instance_id: ProductInstanceId,
    ) !EndpointInformationResponder {
        if (!source.validSource() or !product_instance_id.valid())
            return error.InvalidMidiCiEndpointInformation;
        return .{
            .source = source,
            .product_instance_id = product_instance_id,
        };
    }

    pub fn handle(
        self: EndpointInformationResponder,
        message: EndpointInformationMessage,
    ) !EndpointInformationMessage {
        try validateEndpointInformation(message);
        const inquiry = switch (message) {
            .inquiry => |value| value,
            .reply => return error.UnexpectedMidiCiEndpointReply,
        };
        if (inquiry.destination.value != self.source.value)
            return error.MidiCiMuidMismatch;
        if (inquiry.source.value == self.source.value)
            return error.MidiCiMuidCollision;
        return .{ .reply = .{
            .source = self.source,
            .destination = inquiry.source,
            .product_instance_id = self.product_instance_id,
        } };
    }
};

pub const Address = union(enum) {
    channel: u4,
    group,
    function_block,

    fn wireValue(self: Address) u7 {
        return switch (self) {
            .channel => |channel| channel,
            .group => 0x7E,
            .function_block => 0x7F,
        };
    }

    fn parse(value: u8) !Address {
        return switch (value) {
            0x00...0x0F => .{ .channel = @intCast(value) },
            0x7E => .group,
            0x7F => .function_block,
            else => error.InvalidMidiCiAddress,
        };
    }
};

pub const MessageText = struct {
    storage: [103]u7 = .{0} ** 103,
    count: u7 = 0,

    pub fn init(source: []const u8) !MessageText {
        if (source.len > 103) return error.MidiCiMessageTextTooLong;
        var value = MessageText{ .count = @intCast(source.len) };
        for (source, 0..) |byte, index| {
            if (!validMessageTextByte(byte))
                return error.InvalidMidiCiMessageText;
            value.storage[index] = @intCast(byte);
        }
        return value;
    }

    pub fn bytes(self: *const MessageText) []const u7 {
        if (!self.valid()) return &.{};
        return self.storage[0..self.count];
    }

    pub fn valid(self: MessageText) bool {
        if (self.count > self.storage.len) return false;
        for (self.storage[0..self.count]) |byte| {
            if (!validMessageTextByte(byte)) return false;
        }
        for (self.storage[self.count..]) |byte| {
            if (byte != 0) return false;
        }
        return true;
    }

    fn parse(source: anytype) !MessageText {
        if (source.len > 103) return error.MidiCiMessageTextTooLong;
        var value = MessageText{ .count = @intCast(source.len) };
        for (source, 0..) |byte, index| {
            if (!validMessageTextByte(byte))
                return error.InvalidMidiCiMessageText;
            value.storage[index] = @intCast(byte);
        }
        return value;
    }
};

pub const AcknowledgementKind = enum(u7) {
    ack = 0x7D,
    nak = 0x7F,
};

pub const Acknowledgement = struct {
    kind: AcknowledgementKind,
    address: Address = .function_block,
    version: u5 = 2,
    source: Muid,
    destination: Muid,
    original_sub_id: u7 = 0,
    status_code: u7 = 0,
    status_data: u7 = 0,
    details: [5]u7 = .{0} ** 5,
    message: MessageText = .{},

    pub fn valid(self: Acknowledgement) bool {
        if (self.version < 1 or self.version > 2) return false;
        if (!self.source.validSource() or !self.destination.validSource())
            return false;
        if (!self.message.valid()) return false;
        if (self.kind == .nak and self.version == 1) {
            if (self.original_sub_id != 0 or
                self.status_code != 0 or
                self.status_data != 0 or
                self.message.count != 0)
                return false;
            for (self.details) |byte| {
                if (byte != 0) return false;
            }
        }
        return true;
    }

    pub fn encodedLength(self: Acknowledgement) !usize {
        if (!self.valid()) return error.InvalidMidiCiAcknowledgement;
        if (self.kind == .nak and self.version == 1) return 13;
        return 23 + @as(usize, self.message.count);
    }

    pub fn encode(
        self: Acknowledgement,
        destination: []u8,
    ) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        destination[0] = 0x7E;
        destination[1] = self.address.wireValue();
        destination[2] = 0x0D;
        destination[3] = @intFromEnum(self.kind);
        destination[4] = self.version;
        writeU28(destination[5..9], self.source.value);
        writeU28(destination[9..13], self.destination.value);
        if (length > 13) {
            destination[13] = self.original_sub_id;
            destination[14] = self.status_code;
            destination[15] = self.status_data;
            writeU7(destination[16..21], &self.details);
            destination[21] = self.message.count;
            destination[22] = 0;
            writeU7(destination[23..length], self.message.bytes());
        }
        return destination[0..length];
    }

    pub fn parse(source: anytype) !Acknowledgement {
        if (source.len < 13) return error.TruncatedMidiCiMessage;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        if (source[0] != 0x7E or source[2] != 0x0D)
            return error.NotMidiCiAcknowledgement;
        const kind: AcknowledgementKind = switch (source[3]) {
            0x7D => .ack,
            0x7F => .nak,
            else => return error.NotMidiCiAcknowledgement,
        };
        if (source[4] < 1 or source[4] > 2)
            return error.UnsupportedMidiCiVersion;
        var value = Acknowledgement{
            .kind = kind,
            .address = try Address.parse(source[1]),
            .version = @intCast(source[4]),
            .source = .{ .value = readU28(source[5..9]) },
            .destination = .{ .value = readU28(source[9..13]) },
        };
        if (kind == .nak and value.version == 1) {
            if (source.len != 13) return error.InvalidMidiCiMessageLength;
        } else {
            if (source.len < 23) return error.TruncatedMidiCiMessage;
            const text_length =
                @as(usize, source[21]) | (@as(usize, source[22]) << 7);
            if (text_length > 103 or source.len != 23 + text_length)
                return error.InvalidMidiCiMessageLength;
            value.original_sub_id = @intCast(source[13]);
            value.status_code = @intCast(source[14]);
            value.status_data = @intCast(source[15]);
            value.details = copyU7(5, source[16..21]);
            value.message = try MessageText.parse(source[23..]);
        }
        if (!value.valid()) return error.InvalidMidiCiAcknowledgement;
        return value;
    }

    pub fn isTimeoutWait(self: Acknowledgement) bool {
        return self.kind == .ack and self.status_code == 0x10;
    }

    pub fn timeoutMilliseconds(self: Acknowledgement) ?u16 {
        if (!self.isTimeoutWait()) return null;
        return @as(u16, self.status_data) * 100;
    }
};

fn validateMessage(message: Message) !void {
    switch (message) {
        .discovery => |value| {
            if (!value.participant.valid()) return error.InvalidMidiCiParticipant;
            if (value.participant.version == 1 and value.output_path != 0)
                return error.UnsupportedMidiCiVersionField;
        },
        .reply => |value| {
            if (!value.participant.valid()) return error.InvalidMidiCiParticipant;
            if (!value.destination.validSource())
                return error.InvalidMidiCiReplyDestination;
            if (value.participant.version == 1 and
                (value.output_path != 0 or value.function_block != null))
                return error.UnsupportedMidiCiVersionField;
        },
    }
}

fn validateEndpointInformation(message: EndpointInformationMessage) !void {
    switch (message) {
        .inquiry => |value| {
            if (!validEndpointHeader(value))
                return error.InvalidMidiCiEndpointInformation;
        },
        .reply => |value| {
            if (!validEndpointHeader(.{
                .version = value.version,
                .source = value.source,
                .destination = value.destination,
            }) or !value.product_instance_id.valid())
                return error.InvalidMidiCiEndpointInformation;
        },
    }
}

fn validEndpointHeader(value: EndpointInformationInquiry) bool {
    return value.version == 2 and
        value.source.validSource() and
        value.destination.validSource();
}

fn validMessageTextByte(byte: u8) bool {
    return byte == '\n' or (byte >= 0x20 and byte <= 0x7F);
}

fn writeU28(destination: *[4]u8, value: u28) void {
    for (destination, 0..) |*byte, index| {
        byte.* = @intCast((value >> @intCast(index * 7)) & 0x7F);
    }
}

fn writeU7(destination: []u8, source: []const u7) void {
    for (destination, source) |*output, byte| output.* = byte;
}

fn readU28(source: anytype) u28 {
    var value: u28 = 0;
    for (source, 0..) |byte, index| {
        value |= @as(u28, @intCast(byte)) << @intCast(index * 7);
    }
    return value;
}

fn copyU7(comptime length: usize, source: anytype) [length]u7 {
    var result: [length]u7 = undefined;
    for (&result, source) |*destination, byte| destination.* = @intCast(byte);
    return result;
}

fn testParticipant(version: u5, muid: u28) Participant {
    return .{
        .version = version,
        .muid = .{ .value = muid },
        .identity = .{
            .manufacturer = .{ 0x7D, 0, 0 },
            .family = .{ 1, 2 },
            .model = .{ 3, 4 },
            .revision = .{ 1, 0, 0, 0 },
        },
        .categories = .{
            .profile_configuration = true,
            .property_exchange = true,
        },
        .maximum_sysex_size = 512,
    };
}

test "MIDI-CI discovery versions encode and parse" {
    var storage: [31]u8 = undefined;
    for ([_]u5{ 1, 2 }) |version| {
        const transaction = try DiscoveryTransaction.init(
            testParticipant(version, 0x0123_4567),
            if (version == 1) 0 else 9,
        );
        const encoded = try transaction.inquiry().encode(&storage);
        try std.testing.expectEqual(
            @as(usize, if (version == 1) 29 else 30),
            encoded.len,
        );
        try std.testing.expectEqualDeep(
            transaction.inquiry(),
            try Message.parse(encoded),
        );
    }
}

test "MIDI-CI discovery transaction correlates a responder reply" {
    const transaction = try DiscoveryTransaction.init(testParticipant(2, 1), 17);
    const responder = try DiscoveryResponder.init(testParticipant(2, 2), 7);
    const reply_message = try responder.handle(transaction.inquiry());
    const reply = try transaction.accept(reply_message);
    try std.testing.expectEqual(@as(u28, 2), reply.participant.muid.value);
    try std.testing.expectEqual(@as(u7, 17), reply.output_path);
    try std.testing.expectEqual(@as(?u5, 7), reply.function_block);

    var storage: [31]u8 = undefined;
    const encoded = try reply_message.encode(&storage);
    try std.testing.expectEqual(@as(usize, 31), encoded.len);
    try std.testing.expectEqualDeep(reply_message, try Message.parse(encoded));
}

test "MIDI-CI discovery rejects invalid fields transactionally" {
    var storage: [31]u8 = .{0x55} ** 31;
    var invalid = Message{ .discovery = .{
        .participant = testParticipant(2, 1),
    } };
    invalid.discovery.participant.maximum_sysex_size = 127;
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiParticipant,
        invalid.encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);

    var valid_storage: [31]u8 = undefined;
    const transaction = try DiscoveryTransaction.init(testParticipant(2, 1), 3);
    const encoded = try transaction.inquiry().encode(&valid_storage);
    valid_storage[9] = 0;
    try std.testing.expectError(
        error.InvalidMidiCiDiscoveryDestination,
        Message.parse(encoded),
    );
}

test "MIDI-CI MUID and size boundaries" {
    try std.testing.expect((try Muid.init(0)).validSource());
    try std.testing.expect((try Muid.init(reserved_muid_start - 1)).validSource());
    try std.testing.expectError(error.InvalidMidiCiMuid, Muid.init(reserved_muid_start));
    try std.testing.expectError(error.InvalidMidiCiMuid, Muid.init(broadcast_muid));
    try std.testing.expectError(error.InvalidMidiCiMuid, Muid.init(0x1000_0000));
}

test "MIDI-CI version one responder omits version two fields" {
    const transaction = try DiscoveryTransaction.init(testParticipant(2, 1), 42);
    const responder = try DiscoveryResponder.init(testParticipant(1, 2), null);
    const reply_message = try responder.handle(transaction.inquiry());
    const reply = try transaction.accept(reply_message);
    try std.testing.expectEqual(@as(u5, 1), reply.participant.version);
    try std.testing.expectEqual(@as(u7, 0), reply.output_path);
    try std.testing.expectEqual(@as(?u5, null), reply.function_block);

    var storage: [31]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 29),
        (try reply_message.encode(&storage)).len,
    );
}

test "MIDI-CI parser rejects malformed discovery fields" {
    const transaction = try DiscoveryTransaction.init(testParticipant(2, 1), 3);
    var storage: [31]u8 = undefined;
    const encoded = try transaction.inquiry().encode(&storage);

    storage[24] = 1;
    try std.testing.expectError(
        error.InvalidMidiCiParticipant,
        Message.parse(encoded),
    );
    storage[24] = 0x0C;
    storage[30] = 0;
    try std.testing.expectError(
        error.InvalidMidiCiMessageLength,
        Message.parse(storage[0..31]),
    );
    storage[0] = 0xF0;
    try std.testing.expectError(error.InvalidMidiCiDataByte, Message.parse(encoded));
}

test "MIDI-CI generated messages round trip and arbitrary input is bounded" {
    var random = std.Random.DefaultPrng.init(0x4D49_4449_2D43_4921);
    var storage: [31]u8 = undefined;
    for (0..32_768) |_| {
        const version: u5 = if (random.random().boolean()) 1 else 2;
        const source_muid = random.random().uintLessThan(u28, reserved_muid_start);
        var destination_muid = random.random().uintLessThan(u28, reserved_muid_start);
        if (destination_muid == source_muid)
            destination_muid = (destination_muid + 1) % reserved_muid_start;
        var generated_participant = testParticipant(version, source_muid);
        generated_participant.categories = .{
            .deprecated_protocol_negotiation = random.random().boolean(),
            .profile_configuration = random.random().boolean(),
            .property_exchange = random.random().boolean(),
            .process_inquiry = random.random().boolean(),
        };
        generated_participant.maximum_sysex_size =
            128 + random.random().uintLessThan(u28, broadcast_muid - 127);

        const message: Message = if (random.random().boolean())
            .{ .discovery = .{
                .participant = generated_participant,
                .output_path = if (version == 1) 0 else random.random().int(u7),
            } }
        else
            .{ .reply = .{
                .participant = generated_participant,
                .destination = .{ .value = destination_muid },
                .output_path = if (version == 1) 0 else random.random().int(u7),
                .function_block = if (version == 1 or random.random().boolean())
                    null
                else
                    random.random().int(u5),
            } };
        const encoded = try message.encode(&storage);
        try std.testing.expectEqualDeep(message, try Message.parse(encoded));

        const arbitrary_length = random.random().uintLessThan(usize, storage.len + 1);
        random.random().bytes(&storage);
        for (&storage) |*byte| byte.* &= 0x7F;
        _ = Message.parse(storage[0..arbitrary_length]) catch {};
    }
}

test "MIDI-CI invalidation round trips and identifies its target" {
    const invalidation = Invalidation{
        .source = try Muid.init(0x0123_4567),
        .target = try Muid.init(0x0765_4321),
    };
    var storage: [17]u8 = undefined;
    const encoded = try invalidation.encode(&storage);
    try std.testing.expectEqualSlices(u8, &.{
        0x7E, 0x7F, 0x0D, 0x7E, 0x02,
        0x67, 0x0A, 0x0D, 0x09, 0x7F,
        0x7F, 0x7F, 0x7F, 0x21, 0x06,
        0x15, 0x3B,
    }, encoded);
    const parsed = try Invalidation.parse(encoded);
    try std.testing.expectEqualDeep(invalidation, parsed);
    try std.testing.expect(parsed.targets(try Muid.init(0x0765_4321)));
    try std.testing.expect(!parsed.targets(try Muid.init(3)));
}

test "MIDI-CI invalidation rejects reserved MUIDs and destinations" {
    var storage: [17]u8 = undefined;
    const invalidation = Invalidation{
        .source = .{ .value = 1 },
        .target = .{ .value = reserved_muid_start },
    };
    try std.testing.expectError(
        error.InvalidMidiCiInvalidation,
        invalidation.encode(&storage),
    );

    const valid = Invalidation{
        .source = .{ .value = 1 },
        .target = .{ .value = 2 },
    };
    _ = try valid.encode(&storage);
    storage[9] = 0;
    try std.testing.expectError(
        error.InvalidMidiCiInvalidationDestination,
        Invalidation.parse(&storage),
    );
}

test "MIDI-CI endpoint information transaction round trips" {
    const transaction = try EndpointInformationTransaction.init(
        try Muid.init(1),
        try Muid.init(2),
    );
    const responder = try EndpointInformationResponder.init(
        try Muid.init(2),
        try ProductInstanceId.init("SERIAL-123"),
    );
    var inquiry_storage: [14]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&inquiry_storage);
    const inquiry = try EndpointInformationMessage.parse(inquiry_bytes);
    const reply_message = try responder.handle(inquiry);
    var reply_storage: [32]u8 = undefined;
    const reply_bytes = try reply_message.encode(&reply_storage);
    const reply = try transaction.accept(
        try EndpointInformationMessage.parse(reply_bytes),
    );
    try std.testing.expectEqualSlices(
        u7,
        &.{ 'S', 'E', 'R', 'I', 'A', 'L', '-', '1', '2', '3' },
        reply.product_instance_id.text(),
    );
}

test "MIDI-CI endpoint information validates lengths text and correlation" {
    var storage: [32]u8 = .{0x55} ** 32;
    const invalid_reply = EndpointInformationMessage{ .reply = .{
        .source = .{ .value = 2 },
        .destination = .{ .value = 1 },
        .product_instance_id = .{
            .storage = .{0x7F} ** 16,
            .count = 1,
        },
    } };
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiEndpointInformation,
        invalid_reply.encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectError(
        error.MidiCiProductInstanceIdTooLong,
        ProductInstanceId.init("12345678901234567"),
    );
    try std.testing.expectError(
        error.InvalidMidiCiProductInstanceId,
        ProductInstanceId.init("bad\nid"),
    );

    const transaction = try EndpointInformationTransaction.init(
        try Muid.init(1),
        try Muid.init(2),
    );
    const wrong_reply = EndpointInformationMessage{ .reply = .{
        .source = .{ .value = 3 },
        .destination = .{ .value = 1 },
        .product_instance_id = try ProductInstanceId.init("SERIAL"),
    } };
    try std.testing.expectError(
        error.MidiCiMuidMismatch,
        transaction.accept(wrong_reply),
    );
}

test "MIDI-CI endpoint information covers every product ID length" {
    var text: [16]u8 = undefined;
    @memset(&text, 'A');
    for (0..text.len + 1) |length| {
        const message = EndpointInformationMessage{ .reply = .{
            .source = .{ .value = 2 },
            .destination = .{ .value = 1 },
            .product_instance_id = try ProductInstanceId.init(text[0..length]),
        } };
        var storage: [32]u8 = undefined;
        const encoded = try message.encode(&storage);
        try std.testing.expectEqual(@as(usize, 16 + length), encoded.len);
        try std.testing.expectEqualDeep(
            message,
            try EndpointInformationMessage.parse(encoded),
        );
    }
}

test "MIDI-CI ACK and NAK messages round trip" {
    const messages = [_]Acknowledgement{
        .{
            .kind = .ack,
            .source = .{ .value = 2 },
            .destination = .{ .value = 1 },
            .original_sub_id = 0x34,
            .status_code = 0x10,
            .status_data = 7,
            .details = .{ 1, 2, 3, 4, 5 },
            .message = try MessageText.init("waiting"),
        },
        .{
            .kind = .nak,
            .source = .{ .value = 2 },
            .destination = .{ .value = 1 },
            .original_sub_id = 0x72,
            .status_code = 0x41,
            .message = try MessageText.init("malformed"),
        },
        .{
            .kind = .nak,
            .version = 1,
            .source = .{ .value = 2 },
            .destination = .{ .value = 1 },
        },
    };
    var storage: [126]u8 = undefined;
    for (messages) |message| {
        const encoded = try message.encode(&storage);
        try std.testing.expectEqualDeep(message, try Acknowledgement.parse(encoded));
    }
    try std.testing.expectEqual(@as(?u16, 700), messages[0].timeoutMilliseconds());
    try std.testing.expectEqual(@as(?u16, null), messages[1].timeoutMilliseconds());
}

test "MIDI-CI acknowledgement covers message text boundaries" {
    var text: [103]u8 = undefined;
    @memset(&text, 'x');
    for (0..text.len + 1) |length| {
        const message = Acknowledgement{
            .kind = .ack,
            .address = .{ .channel = 15 },
            .source = .{ .value = 2 },
            .destination = .{ .value = 1 },
            .message = try MessageText.init(text[0..length]),
        };
        var storage: [126]u8 = undefined;
        const encoded = try message.encode(&storage);
        try std.testing.expectEqual(@as(usize, 23 + length), encoded.len);
        try std.testing.expectEqualDeep(message, try Acknowledgement.parse(encoded));
    }
}

test "MIDI-CI acknowledgement rejects invalid forms transactionally" {
    var storage: [126]u8 = .{0x55} ** 126;
    const invalid = Acknowledgement{
        .kind = .nak,
        .version = 1,
        .source = .{ .value = 2 },
        .destination = .{ .value = 1 },
        .status_code = 1,
    };
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiAcknowledgement,
        invalid.encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectError(
        error.InvalidMidiCiMessageText,
        MessageText.init("bad\ttext"),
    );
    try std.testing.expectError(
        error.MidiCiMessageTextTooLong,
        MessageText.init(&([_]u8{'x'} ** 104)),
    );
}

test "MIDI-CI generated acknowledgements round trip and arbitrary input is bounded" {
    var random = std.Random.DefaultPrng.init(0x4143_4B2D_4E41_4B21);
    var storage: [126]u8 = undefined;
    for (0..32_768) |_| {
        const kind: AcknowledgementKind = if (random.random().boolean())
            .ack
        else
            .nak;
        const version: u5 = if (random.random().boolean()) 1 else 2;
        const source = random.random().uintLessThan(u28, reserved_muid_start);
        var destination = random.random().uintLessThan(u28, reserved_muid_start);
        if (destination == source)
            destination = (destination + 1) % reserved_muid_start;
        const address: Address = switch (random.random().uintLessThan(u8, 3)) {
            0 => .{ .channel = random.random().int(u4) },
            1 => .group,
            else => .function_block,
        };
        var message_text = MessageText{};
        if (kind == .ack or version == 2) {
            message_text.count = random.random().uintLessThan(u7, 104);
            for (message_text.storage[0..message_text.count]) |*byte| {
                byte.* = if (random.random().uintLessThan(u8, 16) == 0)
                    '\n'
                else
                    @intCast(32 + random.random().uintLessThan(u8, 96));
            }
        }
        const has_extensions = kind == .ack or version == 2;
        var details: [5]u7 = .{0} ** 5;
        if (has_extensions) {
            for (&details) |*byte| byte.* = random.random().int(u7);
        }
        const message = Acknowledgement{
            .kind = kind,
            .address = address,
            .version = version,
            .source = .{ .value = source },
            .destination = .{ .value = destination },
            .original_sub_id = if (has_extensions) random.random().int(u7) else 0,
            .status_code = if (has_extensions) random.random().int(u7) else 0,
            .status_data = if (has_extensions) random.random().int(u7) else 0,
            .details = details,
            .message = message_text,
        };
        const encoded = try message.encode(&storage);
        try std.testing.expectEqualDeep(
            message,
            try Acknowledgement.parse(encoded),
        );

        const arbitrary_length =
            random.random().uintLessThan(usize, storage.len + 1);
        random.random().bytes(&storage);
        for (&storage) |*byte| byte.* &= 0x7F;
        _ = Acknowledgement.parse(storage[0..arbitrary_length]) catch {};
    }
}
