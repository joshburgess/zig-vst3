const std = @import("std");
const midi_ci = @import("midi_ci.zig");

pub const Id = struct {
    bytes: [5]u7,

    pub fn init(source: [5]u8) !Id {
        var bytes: [5]u7 = undefined;
        for (source, 0..) |byte, index| {
            if (byte > 0x7F) return error.InvalidMidiCiProfileId;
            bytes[index] = @intCast(byte);
        }
        return .{ .bytes = bytes };
    }

    pub fn standard(
        bank: u7,
        number: u7,
        version: u7,
        level: u7,
    ) Id {
        return .{ .bytes = .{ 0x7E, bank, number, version, level } };
    }
};

pub fn List(comptime capacity: usize) type {
    if (capacity > 0x3FFF)
        @compileError("MIDI-CI Profile list capacity exceeds u14");
    return struct {
        const Self = @This();

        storage: [capacity]Id = undefined,
        count: u14 = 0,

        pub fn init(profiles: []const Id) !Self {
            if (profiles.len > capacity)
                return error.MidiCiProfileListCapacityExceeded;
            var result = Self{ .count = @intCast(profiles.len) };
            @memcpy(result.storage[0..profiles.len], profiles);
            if (!result.valid()) return error.InvalidMidiCiProfileList;
            return result;
        }

        pub fn slice(self: *const Self) []const Id {
            if (!self.valid()) return &.{};
            return self.storage[0..self.count];
        }

        pub fn valid(self: Self) bool {
            if (self.count > capacity) return false;
            for (self.storage[0..self.count], 0..) |profile, index| {
                for (self.storage[0..index]) |previous| {
                    if (std.meta.eql(profile, previous)) return false;
                }
            }
            return true;
        }
    };
}

pub const Inquiry = struct {
    address: midi_ci.Address = .function_block,
    version: u5 = 2,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,

    pub fn valid(self: Inquiry) bool {
        return validVersion(self.version) and
            self.source.validSource() and
            self.destination.validSource();
    }

    pub fn encode(self: Inquiry, destination: []u8) ![]const u8 {
        if (!self.valid()) return error.InvalidMidiCiProfileInquiry;
        if (destination.len < 13) return error.MidiCiBufferTooSmall;
        writeHeader(
            destination[0..13],
            self.address,
            0x20,
            self.version,
            self.source,
            self.destination,
        );
        return destination[0..13];
    }

    pub fn parse(source: []const u8) !Inquiry {
        if (source.len != 13) return error.InvalidMidiCiMessageLength;
        const header = try parseHeader(source, 0x20);
        const inquiry = Inquiry{
            .address = header.address,
            .version = header.version,
            .source = header.source,
            .destination = header.destination,
        };
        if (!inquiry.valid()) return error.InvalidMidiCiProfileInquiry;
        return inquiry;
    }
};

pub fn Reply(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        const ProfileList = List(capacity);

        address: midi_ci.Address = .function_block,
        version: u5 = 2,
        source: midi_ci.Muid,
        destination: midi_ci.Muid,
        enabled: ProfileList,
        disabled: ProfileList,

        pub fn valid(self: Self) bool {
            if (!validVersion(self.version) or
                !self.source.validSource() or
                !self.destination.validSource() or
                !self.enabled.valid() or
                !self.disabled.valid())
                return false;
            for (self.enabled.slice()) |enabled| {
                for (self.disabled.slice()) |disabled| {
                    if (std.meta.eql(enabled, disabled)) return false;
                }
            }
            return true;
        }

        pub fn encodedLength(self: Self) !usize {
            if (!self.valid()) return error.InvalidMidiCiProfileReply;
            return 17 + 5 *
                (@as(usize, self.enabled.count) + @as(usize, self.disabled.count));
        }

        pub fn encode(self: Self, destination: []u8) ![]const u8 {
            const length = try self.encodedLength();
            if (destination.len < length) return error.MidiCiBufferTooSmall;
            writeHeader(
                destination[0..13],
                self.address,
                0x21,
                self.version,
                self.source,
                self.destination,
            );
            writeU14(destination[13..15], self.enabled.count);
            var offset: usize = 15;
            offset = writeProfiles(destination, offset, self.enabled.slice());
            writeU14(destination[offset .. offset + 2], self.disabled.count);
            offset += 2;
            offset = writeProfiles(destination, offset, self.disabled.slice());
            return destination[0..offset];
        }

        pub fn parse(source: []const u8) !Self {
            if (source.len < 17) return error.TruncatedMidiCiMessage;
            const header = try parseHeader(source, 0x21);
            const enabled_count = readU14(source[13..15]);
            const disabled_count_offset =
                15 + 5 * @as(usize, enabled_count);
            if (enabled_count > capacity or
                disabled_count_offset + 2 > source.len)
                return error.InvalidMidiCiMessageLength;
            const disabled_count = readU14(
                source[disabled_count_offset .. disabled_count_offset + 2],
            );
            const expected_length =
                disabled_count_offset + 2 + 5 * @as(usize, disabled_count);
            if (disabled_count > capacity or source.len != expected_length)
                return error.InvalidMidiCiMessageLength;
            var enabled = ProfileList{ .count = enabled_count };
            readProfiles(
                enabled.storage[0..enabled_count],
                source[15..disabled_count_offset],
            );
            var disabled = ProfileList{ .count = disabled_count };
            readProfiles(
                disabled.storage[0..disabled_count],
                source[disabled_count_offset + 2 ..],
            );
            const reply = Self{
                .address = header.address,
                .version = header.version,
                .source = header.source,
                .destination = header.destination,
                .enabled = enabled,
                .disabled = disabled,
            };
            if (!reply.valid()) return error.InvalidMidiCiProfileReply;
            return reply;
        }
    };
}

pub const SetKind = enum(u7) {
    on = 0x22,
    off = 0x23,
};

pub const Set = struct {
    kind: SetKind,
    address: midi_ci.Address = .function_block,
    version: u5 = 2,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    profile: Id,
    channels: u14 = 0,

    pub fn valid(self: Set) bool {
        if (!validVersion(self.version) or
            !self.source.validSource() or
            !self.destination.validSource() or
            self.channels > 256)
            return false;
        if (self.version == 1 and self.channels != 0) return false;
        if (self.kind == .off and self.channels != 0) return false;
        return switch (self.address) {
            .channel => true,
            .group, .function_block => self.channels == 0,
        };
    }

    pub fn encodedLength(self: Set) !usize {
        if (!self.valid()) return error.InvalidMidiCiProfileSet;
        return if (self.version == 1) 18 else 20;
    }

    pub fn encode(self: Set, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        writeHeader(
            destination[0..13],
            self.address,
            @intFromEnum(self.kind),
            self.version,
            self.source,
            self.destination,
        );
        writeProfile(destination[13..18], self.profile);
        if (self.version == 2) {
            writeU14(
                destination[18..20],
                if (self.kind == .on) self.channels else 0,
            );
        }
        return destination[0..length];
    }

    pub fn parse(source: []const u8) !Set {
        if (source.len < 18) return error.TruncatedMidiCiMessage;
        const kind: SetKind = switch (source[3]) {
            0x22 => .on,
            0x23 => .off,
            else => return error.NotMidiCiProfileSet,
        };
        const header = try parseHeader(source, @intFromEnum(kind));
        const expected_length: usize = if (header.version == 1) 18 else 20;
        if (source.len != expected_length)
            return error.InvalidMidiCiMessageLength;
        const value = Set{
            .kind = kind,
            .address = header.address,
            .version = header.version,
            .source = header.source,
            .destination = header.destination,
            .profile = readProfile(source[13..18]),
            .channels = if (header.version == 2)
                readU14(source[18..20])
            else
                0,
        };
        if (!value.valid()) return error.InvalidMidiCiProfileSet;
        return value;
    }
};

pub const ReportKind = enum(u7) {
    enabled = 0x24,
    disabled = 0x25,
};

pub const Report = struct {
    kind: ReportKind,
    address: midi_ci.Address = .function_block,
    version: u5 = 2,
    source: midi_ci.Muid,
    profile: Id,
    channels: u14 = 0,

    pub fn valid(self: Report) bool {
        if (!validVersion(self.version) or
            !self.source.validSource() or
            self.channels > 256)
            return false;
        if (self.version == 1 and self.channels != 0) return false;
        return switch (self.address) {
            .channel => true,
            .group, .function_block => self.channels == 0,
        };
    }

    pub fn encodedLength(self: Report) !usize {
        if (!self.valid()) return error.InvalidMidiCiProfileReport;
        return if (self.version == 1) 18 else 20;
    }

    pub fn encode(self: Report, destination: []u8) ![]const u8 {
        const length = try self.encodedLength();
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        writeHeader(
            destination[0..13],
            self.address,
            @intFromEnum(self.kind),
            self.version,
            self.source,
            midi_ci.Muid.broadcast(),
        );
        writeProfile(destination[13..18], self.profile);
        if (self.version == 2) writeU14(destination[18..20], self.channels);
        return destination[0..length];
    }

    pub fn parse(source: []const u8) !Report {
        if (source.len < 18) return error.TruncatedMidiCiMessage;
        const kind: ReportKind = switch (source[3]) {
            0x24 => .enabled,
            0x25 => .disabled,
            else => return error.NotMidiCiProfileReport,
        };
        const header = try parseHeader(source, @intFromEnum(kind));
        const expected_length: usize = if (header.version == 1) 18 else 20;
        if (source.len != expected_length)
            return error.InvalidMidiCiMessageLength;
        if (!header.destination.isBroadcast())
            return error.InvalidMidiCiProfileReportDestination;
        const report = Report{
            .kind = kind,
            .address = header.address,
            .version = header.version,
            .source = header.source,
            .profile = readProfile(source[13..18]),
            .channels = if (header.version == 2)
                readU14(source[18..20])
            else
                0,
        };
        if (!report.valid()) return error.InvalidMidiCiProfileReport;
        return report;
    }
};

pub const PresenceKind = enum(u7) {
    added = 0x26,
    removed = 0x27,
};

pub const Presence = struct {
    kind: PresenceKind,
    address: midi_ci.Address = .function_block,
    version: u5 = 2,
    source: midi_ci.Muid,
    profile: Id,

    pub fn valid(self: Presence) bool {
        return self.version == 2 and self.source.validSource();
    }

    pub fn encode(self: Presence, destination: []u8) ![]const u8 {
        if (!self.valid()) return error.InvalidMidiCiProfilePresence;
        if (destination.len < 18) return error.MidiCiBufferTooSmall;
        writeHeader(
            destination[0..13],
            self.address,
            @intFromEnum(self.kind),
            self.version,
            self.source,
            midi_ci.Muid.broadcast(),
        );
        writeProfile(destination[13..18], self.profile);
        return destination[0..18];
    }

    pub fn parse(source: []const u8) !Presence {
        if (source.len != 18) return error.InvalidMidiCiMessageLength;
        const kind: PresenceKind = switch (source[3]) {
            0x26 => .added,
            0x27 => .removed,
            else => return error.NotMidiCiProfilePresence,
        };
        const header = try parseHeader(source, @intFromEnum(kind));
        if (!header.destination.isBroadcast())
            return error.InvalidMidiCiProfileReportDestination;
        const presence = Presence{
            .kind = kind,
            .address = header.address,
            .version = header.version,
            .source = header.source,
            .profile = readProfile(source[13..18]),
        };
        if (!presence.valid()) return error.InvalidMidiCiProfilePresence;
        return presence;
    }
};

pub const DetailsInquiry = struct {
    address: midi_ci.Address = .function_block,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
    profile: Id,
    target: u7,

    pub fn valid(self: DetailsInquiry) bool {
        return self.source.validSource() and self.destination.validSource();
    }

    pub fn encode(
        self: DetailsInquiry,
        destination: []u8,
    ) ![]const u8 {
        if (!self.valid()) return error.InvalidMidiCiProfileDetails;
        if (destination.len < 19) return error.MidiCiBufferTooSmall;
        writeHeader(
            destination[0..13],
            self.address,
            0x28,
            2,
            self.source,
            self.destination,
        );
        writeProfile(destination[13..18], self.profile);
        destination[18] = self.target;
        return destination[0..19];
    }

    pub fn parse(source: []const u8) !DetailsInquiry {
        if (source.len != 19) return error.InvalidMidiCiMessageLength;
        const header = try parseHeader(source, 0x28);
        if (header.version != 2) return error.UnsupportedMidiCiVersion;
        const inquiry = DetailsInquiry{
            .address = header.address,
            .source = header.source,
            .destination = header.destination,
            .profile = readProfile(source[13..18]),
            .target = @intCast(source[18]),
        };
        if (!inquiry.valid()) return error.InvalidMidiCiProfileDetails;
        return inquiry;
    }
};

pub fn DetailsReply(comptime capacity: usize) type {
    if (capacity > 0x3FFF)
        @compileError("MIDI-CI Profile Details capacity exceeds u14");
    return struct {
        const Self = @This();

        address: midi_ci.Address = .function_block,
        source: midi_ci.Muid,
        destination: midi_ci.Muid,
        profile: Id,
        target: u7,
        storage: [capacity]u8 = undefined,
        count: u14 = 0,

        pub fn init(
            address: midi_ci.Address,
            source: midi_ci.Muid,
            destination: midi_ci.Muid,
            profile: Id,
            target: u7,
            source_data: []const u8,
        ) !Self {
            if (source_data.len > capacity)
                return error.MidiCiProfileDetailsCapacityExceeded;
            var reply = Self{
                .address = address,
                .source = source,
                .destination = destination,
                .profile = profile,
                .target = target,
                .count = @intCast(source_data.len),
            };
            for (source_data, 0..) |byte, index| {
                if (byte > 0x7F) return error.InvalidMidiCiDataByte;
                reply.storage[index] = byte;
            }
            if (!reply.valid()) return error.InvalidMidiCiProfileDetails;
            return reply;
        }

        pub fn data(self: *const Self) []const u8 {
            if (!self.valid()) return &.{};
            return self.storage[0..self.count];
        }

        pub fn valid(self: Self) bool {
            if (!self.source.validSource() or
                !self.destination.validSource() or
                self.count > capacity)
                return false;
            for (self.storage[0..self.count]) |byte| {
                if (byte > 0x7F) return false;
            }
            return true;
        }

        pub fn encodedLength(self: Self) !usize {
            if (!self.valid()) return error.InvalidMidiCiProfileDetails;
            return 21 + @as(usize, self.count);
        }

        pub fn encode(self: Self, destination: []u8) ![]const u8 {
            const length = try self.encodedLength();
            if (destination.len < length) return error.MidiCiBufferTooSmall;
            writeHeader(
                destination[0..13],
                self.address,
                0x29,
                2,
                self.source,
                self.destination,
            );
            writeProfile(destination[13..18], self.profile);
            destination[18] = self.target;
            writeU14(destination[19..21], self.count);
            for (self.data(), 0..) |byte, index| {
                destination[21 + index] = byte;
            }
            return destination[0..length];
        }

        pub fn parse(source: []const u8) !Self {
            if (source.len < 21) return error.TruncatedMidiCiMessage;
            const header = try parseHeader(source, 0x29);
            if (header.version != 2) return error.UnsupportedMidiCiVersion;
            const count = readU14(source[19..21]);
            if (count > capacity or source.len != 21 + @as(usize, count))
                return error.InvalidMidiCiMessageLength;
            var reply = Self{
                .address = header.address,
                .source = header.source,
                .destination = header.destination,
                .profile = readProfile(source[13..18]),
                .target = @intCast(source[18]),
                .count = count,
            };
            for (source[21..], 0..) |byte, index| {
                reply.storage[index] = byte;
            }
            if (!reply.valid()) return error.InvalidMidiCiProfileDetails;
            return reply;
        }
    };
}

pub fn SpecificData(comptime capacity: usize) type {
    if (capacity > 0x0FFF_FFFF)
        @compileError("MIDI-CI Profile Specific Data capacity exceeds u28");
    return struct {
        const Self = @This();

        address: midi_ci.Address = .function_block,
        version: u5 = 2,
        source: midi_ci.Muid,
        destination: midi_ci.Muid,
        profile: Id,
        storage: [capacity]u8 = undefined,
        count: u28 = 0,

        pub fn init(
            address: midi_ci.Address,
            version: u5,
            source: midi_ci.Muid,
            destination: midi_ci.Muid,
            profile: Id,
            source_data: []const u8,
        ) !Self {
            if (source_data.len > capacity)
                return error.MidiCiProfileSpecificDataCapacityExceeded;
            var message = Self{
                .address = address,
                .version = version,
                .source = source,
                .destination = destination,
                .profile = profile,
                .count = @intCast(source_data.len),
            };
            for (source_data, 0..) |byte, index| {
                if (byte > 0x7F) return error.InvalidMidiCiDataByte;
                message.storage[index] = byte;
            }
            if (!message.valid())
                return error.InvalidMidiCiProfileSpecificData;
            return message;
        }

        pub fn data(self: *const Self) []const u8 {
            if (!self.valid()) return &.{};
            return self.storage[0..self.count];
        }

        pub fn valid(self: Self) bool {
            if (!validVersion(self.version) or
                !self.source.validSource() or
                (!self.destination.validSource() and
                    !self.destination.isBroadcast()) or
                self.count > capacity)
                return false;
            for (self.storage[0..self.count]) |byte| {
                if (byte > 0x7F) return false;
            }
            return true;
        }

        pub fn encodedLength(self: Self) !usize {
            if (!self.valid())
                return error.InvalidMidiCiProfileSpecificData;
            return 22 + @as(usize, self.count);
        }

        pub fn encode(self: Self, destination: []u8) ![]const u8 {
            const length = try self.encodedLength();
            if (destination.len < length) return error.MidiCiBufferTooSmall;
            writeHeader(
                destination[0..13],
                self.address,
                0x2F,
                self.version,
                self.source,
                self.destination,
            );
            writeProfile(destination[13..18], self.profile);
            writeU28(destination[18..22], self.count);
            @memcpy(destination[22..length], self.data());
            return destination[0..length];
        }

        pub fn parse(source_bytes: []const u8) !Self {
            if (source_bytes.len < 22) return error.TruncatedMidiCiMessage;
            const header = try parseHeader(source_bytes, 0x2F);
            const count = readU28(source_bytes[18..22]);
            if (count > capacity or
                source_bytes.len != 22 + @as(usize, count))
                return error.InvalidMidiCiMessageLength;
            var message = Self{
                .address = header.address,
                .version = header.version,
                .source = header.source,
                .destination = header.destination,
                .profile = readProfile(source_bytes[13..18]),
                .count = count,
            };
            @memcpy(message.storage[0..count], source_bytes[22..]);
            if (!message.valid())
                return error.InvalidMidiCiProfileSpecificData;
            return message;
        }
    };
}

pub const ChannelCountDetails = struct {
    active: u14,
    maximum: u14,

    pub fn valid(self: ChannelCountDetails) bool {
        return self.maximum >= 1 and
            self.maximum <= 256 and
            self.active <= self.maximum;
    }

    pub fn encode(
        self: ChannelCountDetails,
        destination: []u8,
    ) ![]const u8 {
        if (!self.valid()) return error.InvalidMidiCiProfileChannelCount;
        if (destination.len < 4) return error.MidiCiBufferTooSmall;
        writeU14(destination[0..2], self.active);
        writeU14(destination[2..4], self.maximum);
        return destination[0..4];
    }

    pub fn parse(source: []const u8) !ChannelCountDetails {
        if (source.len != 4) return error.InvalidMidiCiMessageLength;
        for (source) |byte| {
            if (byte > 0x7F) return error.InvalidMidiCiDataByte;
        }
        const details = ChannelCountDetails{
            .active = readU14(source[0..2]),
            .maximum = readU14(source[2..4]),
        };
        if (!details.valid()) return error.InvalidMidiCiProfileChannelCount;
        return details;
    }
};

pub const DetailsTransaction = struct {
    inquiry_value: DetailsInquiry,
    complete: bool = false,

    pub fn init(inquiry_value: DetailsInquiry) !DetailsTransaction {
        if (!inquiry_value.valid()) return error.InvalidMidiCiProfileDetails;
        if (inquiry_value.source.value == inquiry_value.destination.value)
            return error.MidiCiMuidCollision;
        return .{ .inquiry_value = inquiry_value };
    }

    pub fn inquiry(self: DetailsTransaction) DetailsInquiry {
        return self.inquiry_value;
    }

    pub fn accept(self: *DetailsTransaction, reply: anytype) !void {
        if (self.complete) return error.InvalidMidiCiProfileDetailsState;
        if (!reply.valid()) return error.InvalidMidiCiProfileDetails;
        if (!addressEqual(reply.address, self.inquiry_value.address) or
            reply.source.value != self.inquiry_value.destination.value or
            reply.destination.value != self.inquiry_value.source.value or
            !std.meta.eql(reply.profile, self.inquiry_value.profile) or
            reply.target != self.inquiry_value.target)
            return error.MidiCiProfileDetailsMismatch;
        self.complete = true;
    }
};

pub const InquiryTransaction = struct {
    inquiry_value: Inquiry,
    saw_group_reply: bool = false,
    complete: bool = false,

    pub fn init(inquiry_value: Inquiry) !InquiryTransaction {
        if (!inquiry_value.valid()) return error.InvalidMidiCiProfileInquiry;
        if (inquiry_value.source.value == inquiry_value.destination.value)
            return error.MidiCiMuidCollision;
        return .{ .inquiry_value = inquiry_value };
    }

    pub fn inquiry(self: InquiryTransaction) Inquiry {
        return self.inquiry_value;
    }

    pub fn accept(
        self: *InquiryTransaction,
        reply: anytype,
    ) !bool {
        if (self.complete) return error.InvalidMidiCiProfileInquiryState;
        if (!reply.valid()) return error.InvalidMidiCiProfileReply;
        if (reply.version != self.inquiry_value.version or
            reply.source.value != self.inquiry_value.destination.value or
            reply.destination.value != self.inquiry_value.source.value)
            return error.MidiCiProfileReplyMismatch;
        const final = switch (self.inquiry_value.address) {
            .channel => |channel| switch (reply.address) {
                .channel => |reply_channel| channel == reply_channel,
                else => false,
            },
            .group => switch (reply.address) {
                .group => true,
                else => false,
            },
            .function_block => switch (reply.address) {
                .function_block => true,
                .channel => {
                    if (self.saw_group_reply)
                        return error.MidiCiProfileReplyOrder;
                    return false;
                },
                .group => {
                    self.saw_group_reply = true;
                    return false;
                },
            },
        };
        if (self.inquiry_value.address != .function_block and !final)
            return error.MidiCiProfileReplyMismatch;
        self.complete = final;
        return final;
    }
};

pub const SetTransaction = struct {
    request: Set,
    complete: bool = false,

    pub fn init(request: Set) !SetTransaction {
        if (!request.valid()) return error.InvalidMidiCiProfileSet;
        if (request.source.value == request.destination.value)
            return error.MidiCiMuidCollision;
        return .{ .request = request };
    }

    pub fn message(self: SetTransaction) Set {
        return self.request;
    }

    pub fn accept(self: *SetTransaction, report: Report) !bool {
        if (self.complete) return error.InvalidMidiCiProfileSetState;
        if (!report.valid()) return error.InvalidMidiCiProfileReport;
        if (report.version != self.request.version or
            report.source.value != self.request.destination.value or
            !addressEqual(report.address, self.request.address) or
            !std.meta.eql(report.profile, self.request.profile))
            return error.MidiCiProfileReportMismatch;
        self.complete = true;
        return switch (self.request.kind) {
            .on => report.kind == .enabled,
            .off => report.kind == .disabled,
        };
    }
};

const ParsedHeader = struct {
    address: midi_ci.Address,
    version: u5,
    source: midi_ci.Muid,
    destination: midi_ci.Muid,
};

fn writeHeader(
    destination: []u8,
    address: midi_ci.Address,
    kind: u7,
    version: u5,
    source: midi_ci.Muid,
    target: midi_ci.Muid,
) void {
    destination[0] = 0x7E;
    destination[1] = addressByte(address);
    destination[2] = 0x0D;
    destination[3] = kind;
    destination[4] = version;
    writeU28(destination[5..9], source.value);
    writeU28(destination[9..13], target.value);
}

fn parseHeader(source: []const u8, kind: u7) !ParsedHeader {
    if (source.len < 13) return error.TruncatedMidiCiMessage;
    for (source) |byte| {
        if (byte > 0x7F) return error.InvalidMidiCiDataByte;
    }
    if (source[0] != 0x7E or source[2] != 0x0D or source[3] != kind)
        return error.NotMidiCiProfileMessage;
    if (source[4] != 1 and source[4] != 2)
        return error.UnsupportedMidiCiVersion;
    const header = ParsedHeader{
        .address = try parseAddress(source[1]),
        .version = @intCast(source[4]),
        .source = .{ .value = readU28(source[5..9]) },
        .destination = .{ .value = readU28(source[9..13]) },
    };
    if (!header.source.validSource() or
        (!header.destination.validSource() and
            !header.destination.isBroadcast()))
        return error.InvalidMidiCiProfileMessage;
    return header;
}

fn validVersion(version: u5) bool {
    return version == 1 or version == 2;
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

fn writeProfile(destination: []u8, profile: Id) void {
    for (profile.bytes, 0..) |byte, index| destination[index] = byte;
}

fn readProfile(source: []const u8) Id {
    var bytes: [5]u7 = undefined;
    for (source[0..5], 0..) |byte, index| bytes[index] = @intCast(byte);
    return .{ .bytes = bytes };
}

fn writeProfiles(
    destination: []u8,
    initial_offset: usize,
    profiles: []const Id,
) usize {
    var offset = initial_offset;
    for (profiles) |profile| {
        writeProfile(destination[offset .. offset + 5], profile);
        offset += 5;
    }
    return offset;
}

fn readProfiles(destination: []Id, source: []const u8) void {
    for (destination, 0..) |*profile, index| {
        profile.* = readProfile(source[index * 5 ..][0..5]);
    }
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

test "MIDI-CI Profile inquiry accepts ordered function-block replies" {
    const ProfileList = List(4);
    const ProfileReply = Reply(4);
    const piano = Id.standard(0, 1, 1, 0);
    const organ = Id.standard(0, 2, 1, 0);
    var transaction = try InquiryTransaction.init(.{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
    });
    var storage: [57]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&storage);
    try std.testing.expectEqualDeep(
        transaction.inquiry_value,
        try Inquiry.parse(inquiry_bytes),
    );
    const channel_reply = ProfileReply{
        .address = .{ .channel = 0 },
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .enabled = try ProfileList.init(&.{piano}),
        .disabled = try ProfileList.init(&.{organ}),
    };
    const channel_bytes = try channel_reply.encode(&storage);
    try std.testing.expect(
        !try transaction.accept(try ProfileReply.parse(channel_bytes)),
    );
    const final_reply = ProfileReply{
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .enabled = try ProfileList.init(&.{}),
        .disabled = try ProfileList.init(&.{}),
    };
    const final_bytes = try final_reply.encode(&storage);
    try std.testing.expect(
        try transaction.accept(try ProfileReply.parse(final_bytes)),
    );
    try std.testing.expect(transaction.complete);
}

test "MIDI-CI Profile Set and Report cover versions and outcomes" {
    const profile = Id.standard(0, 1, 1, 0);
    const requests = [_]Set{
        .{
            .kind = .on,
            .address = .{ .channel = 2 },
            .source = try midi_ci.Muid.init(1),
            .destination = try midi_ci.Muid.init(2),
            .profile = profile,
            .channels = 8,
        },
        .{
            .kind = .off,
            .version = 1,
            .source = try midi_ci.Muid.init(1),
            .destination = try midi_ci.Muid.init(2),
            .profile = profile,
        },
    };
    var storage: [20]u8 = undefined;
    for (requests) |request| {
        var transaction = try SetTransaction.init(request);
        const request_bytes = try request.encode(&storage);
        try std.testing.expectEqualDeep(request, try Set.parse(request_bytes));
        const successful_kind: ReportKind = switch (request.kind) {
            .on => .enabled,
            .off => .disabled,
        };
        const report = Report{
            .kind = successful_kind,
            .address = request.address,
            .version = request.version,
            .source = request.destination,
            .profile = profile,
            .channels = request.channels,
        };
        const report_bytes = try report.encode(&storage);
        try std.testing.expect(
            try transaction.accept(try Report.parse(report_bytes)),
        );
    }
}

test "MIDI-CI Profile messages reject malformed lists and fields" {
    const ProfileList = List(2);
    const ProfileReply = Reply(2);
    const profile = Id.standard(0, 1, 1, 0);
    const duplicate_reply = ProfileReply{
        .source = try midi_ci.Muid.init(2),
        .destination = try midi_ci.Muid.init(1),
        .enabled = try ProfileList.init(&.{profile}),
        .disabled = .{
            .storage = .{ profile, undefined },
            .count = 1,
        },
    };
    var storage: [37]u8 = .{0x55} ** 37;
    const before = storage;
    try std.testing.expectError(
        error.InvalidMidiCiProfileReply,
        duplicate_reply.encode(&storage),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectError(
        error.InvalidMidiCiProfileSet,
        (Set{
            .kind = .on,
            .address = .group,
            .source = try midi_ci.Muid.init(1),
            .destination = try midi_ci.Muid.init(2),
            .profile = profile,
            .channels = 1,
        }).encode(&storage),
    );
    try std.testing.expectError(
        error.InvalidMidiCiProfileReport,
        (Report{
            .kind = .enabled,
            .version = 1,
            .source = try midi_ci.Muid.init(2),
            .profile = profile,
            .channels = 1,
        }).encode(&storage),
    );
}

test "MIDI-CI Profile reply covers bounded list combinations" {
    const ProfileList = List(8);
    const ProfileReply = Reply(8);
    var enabled_profiles: [8]Id = undefined;
    var disabled_profiles: [8]Id = undefined;
    for (0..8) |index| {
        enabled_profiles[index] = Id.standard(
            0,
            @intCast(index),
            1,
            0,
        );
        disabled_profiles[index] = Id.standard(
            1,
            @intCast(index),
            1,
            0,
        );
    }
    var storage: [97]u8 = undefined;
    for (0..9) |enabled_count| {
        for (0..9) |disabled_count| {
            const reply = ProfileReply{
                .source = try midi_ci.Muid.init(2),
                .destination = try midi_ci.Muid.init(1),
                .enabled = try ProfileList.init(
                    enabled_profiles[0..enabled_count],
                ),
                .disabled = try ProfileList.init(
                    disabled_profiles[0..disabled_count],
                ),
            };
            const encoded = try reply.encode(&storage);
            try std.testing.expectEqual(
                @as(usize, 17 + 5 * (enabled_count + disabled_count)),
                encoded.len,
            );
            const parsed = try ProfileReply.parse(encoded);
            try std.testing.expectEqual(reply.address, parsed.address);
            try std.testing.expectEqual(reply.version, parsed.version);
            try std.testing.expectEqual(reply.source.value, parsed.source.value);
            try std.testing.expectEqual(
                reply.destination.value,
                parsed.destination.value,
            );
            try std.testing.expectEqualSlices(
                Id,
                reply.enabled.slice(),
                parsed.enabled.slice(),
            );
            try std.testing.expectEqualSlices(
                Id,
                reply.disabled.slice(),
                parsed.disabled.slice(),
            );
        }
    }
}

test "MIDI-CI generated Profile state messages round trip and reject arbitrary input" {
    var random = std.Random.DefaultPrng.init(0x5052_4F46_494C_4521);
    var storage: [20]u8 = undefined;
    for (0..32_768) |_| {
        const version: u5 = if (random.random().boolean()) 1 else 2;
        const address: midi_ci.Address = switch (random.random().uintLessThan(u8, 3)) {
            0 => .{ .channel = random.random().int(u4) },
            1 => .group,
            else => .function_block,
        };
        const kind: SetKind = if (random.random().boolean()) .on else .off;
        const channels: u14 = if (version == 2 and
            kind == .on and
            addressByte(address) <= 0x0F)
            random.random().uintLessThan(u14, 257)
        else
            0;
        const source_value =
            random.random().uintLessThan(u28, 0x0FFF_FF00);
        var destination_value =
            random.random().uintLessThan(u28, 0x0FFF_FF00);
        if (destination_value == source_value)
            destination_value = (destination_value + 1) % 0x0FFF_FF00;
        var profile_bytes: [5]u7 = undefined;
        for (&profile_bytes) |*byte| byte.* = random.random().int(u7);
        const profile = Id{ .bytes = profile_bytes };
        const request = Set{
            .kind = kind,
            .address = address,
            .version = version,
            .source = .{ .value = source_value },
            .destination = .{ .value = destination_value },
            .profile = profile,
            .channels = channels,
        };
        const request_bytes = try request.encode(&storage);
        try std.testing.expectEqualDeep(request, try Set.parse(request_bytes));
        const report = Report{
            .kind = if (random.random().boolean()) .enabled else .disabled,
            .address = address,
            .version = version,
            .source = request.destination,
            .profile = profile,
            .channels = if (version == 2 and addressByte(address) <= 0x0F)
                random.random().uintLessThan(u14, 257)
            else
                0,
        };
        const report_bytes = try report.encode(&storage);
        try std.testing.expectEqualDeep(report, try Report.parse(report_bytes));

        const arbitrary_length =
            random.random().uintLessThan(usize, storage.len + 1);
        random.random().bytes(&storage);
        for (&storage) |*byte| byte.* &= 0x7F;
        _ = Set.parse(storage[0..arbitrary_length]) catch {};
        _ = Report.parse(storage[0..arbitrary_length]) catch {};
    }
}

test "MIDI-CI Profile function-block replies enforce channel then group order" {
    const ProfileList = List(1);
    const ProfileReply = Reply(1);
    var transaction = try InquiryTransaction.init(.{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
    });
    const empty = try ProfileList.init(&.{});
    try std.testing.expect(
        !try transaction.accept(ProfileReply{
            .address = .group,
            .source = try midi_ci.Muid.init(2),
            .destination = try midi_ci.Muid.init(1),
            .enabled = empty,
            .disabled = empty,
        }),
    );
    try std.testing.expectError(
        error.MidiCiProfileReplyOrder,
        transaction.accept(ProfileReply{
            .address = .{ .channel = 0 },
            .source = try midi_ci.Muid.init(2),
            .destination = try midi_ci.Muid.init(1),
            .enabled = empty,
            .disabled = empty,
        }),
    );
    try std.testing.expect(!transaction.complete);
}

test "MIDI-CI Profile presence reports round trip" {
    const profile = Id.standard(0, 1, 1, 0);
    const reports = [_]Presence{
        .{
            .kind = .added,
            .address = .{ .channel = 4 },
            .source = try midi_ci.Muid.init(2),
            .profile = profile,
        },
        .{
            .kind = .removed,
            .source = try midi_ci.Muid.init(2),
            .profile = profile,
        },
    };
    var storage: [18]u8 = undefined;
    for (reports) |report| {
        const encoded = try report.encode(&storage);
        try std.testing.expectEqualDeep(report, try Presence.parse(encoded));
    }
    _ = try reports[0].encode(&storage);
    storage[4] = 1;
    try std.testing.expectError(
        error.InvalidMidiCiProfilePresence,
        Presence.parse(&storage),
    );
    _ = try reports[0].encode(&storage);
    writeU28(storage[9..13], 3);
    try std.testing.expectError(
        error.InvalidMidiCiProfileReportDestination,
        Presence.parse(&storage),
    );
}

test "MIDI-CI Profile Details transaction and channel counts round trip" {
    const ProfileDetailsReply = DetailsReply(32);
    const profile = Id.standard(0, 1, 1, 0);
    var details_storage: [4]u8 = undefined;
    const details_bytes = try (ChannelCountDetails{
        .active = 8,
        .maximum = 16,
    }).encode(&details_storage);
    var transaction = try DetailsTransaction.init(.{
        .address = .{ .channel = 2 },
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .profile = profile,
        .target = 0,
    });
    var storage: [53]u8 = undefined;
    const inquiry_bytes = try transaction.inquiry().encode(&storage);
    try std.testing.expectEqualDeep(
        transaction.inquiry_value,
        try DetailsInquiry.parse(inquiry_bytes),
    );
    const reply = try ProfileDetailsReply.init(
        .{ .channel = 2 },
        try midi_ci.Muid.init(2),
        try midi_ci.Muid.init(1),
        profile,
        0,
        details_bytes,
    );
    const reply_bytes = try reply.encode(&storage);
    const parsed_reply = try ProfileDetailsReply.parse(reply_bytes);
    try transaction.accept(parsed_reply);
    try std.testing.expectEqualDeep(
        ChannelCountDetails{ .active = 8, .maximum = 16 },
        try ChannelCountDetails.parse(parsed_reply.data()),
    );
}

test "MIDI-CI Profile Details covers every bounded payload length" {
    const ProfileDetailsReply = DetailsReply(32);
    const profile = Id.standard(0, 1, 1, 0);
    var data: [32]u8 = undefined;
    @memset(&data, 0x55);
    var storage: [53]u8 = undefined;
    for (0..data.len + 1) |length| {
        const reply = try ProfileDetailsReply.init(
            .group,
            try midi_ci.Muid.init(2),
            try midi_ci.Muid.init(1),
            profile,
            0x40,
            data[0..length],
        );
        const encoded = try reply.encode(&storage);
        const parsed = try ProfileDetailsReply.parse(encoded);
        try std.testing.expectEqual(@as(usize, 21 + length), encoded.len);
        try std.testing.expectEqualSlices(u8, reply.data(), parsed.data());
    }
}

test "MIDI-CI Profile Details reject invalid counts and correlation" {
    var storage: [4]u8 = undefined;
    try std.testing.expectError(
        error.InvalidMidiCiProfileChannelCount,
        (ChannelCountDetails{
            .active = 17,
            .maximum = 16,
        }).encode(&storage),
    );
    const ProfileDetailsReply = DetailsReply(4);
    const profile = Id.standard(0, 1, 1, 0);
    var transaction = try DetailsTransaction.init(.{
        .source = try midi_ci.Muid.init(1),
        .destination = try midi_ci.Muid.init(2),
        .profile = profile,
        .target = 0,
    });
    const reply = try ProfileDetailsReply.init(
        .function_block,
        try midi_ci.Muid.init(3),
        try midi_ci.Muid.init(1),
        profile,
        0,
        &.{ 0, 0, 1, 0 },
    );
    try std.testing.expectError(
        error.MidiCiProfileDetailsMismatch,
        transaction.accept(reply),
    );
    try std.testing.expect(!transaction.complete);
}

test "MIDI-CI Profile Specific Data covers bounded payloads and versions" {
    const ProfileSpecificData = SpecificData(32);
    const profile = Id.standard(0, 1, 1, 0);
    var data: [32]u8 = undefined;
    for (&data, 0..) |*byte, index| byte.* = @intCast(index);
    var storage: [54]u8 = undefined;
    for (0..data.len + 1) |length| {
        for (1..3) |version| {
            const message = try ProfileSpecificData.init(
                .{ .channel = 3 },
                @intCast(version),
                try midi_ci.Muid.init(1),
                try midi_ci.Muid.init(2),
                profile,
                data[0..length],
            );
            const encoded = try message.encode(&storage);
            const parsed = try ProfileSpecificData.parse(encoded);
            try std.testing.expectEqual(
                @as(usize, 22 + length),
                encoded.len,
            );
            try std.testing.expectEqual(message.version, parsed.version);
            try std.testing.expectEqualSlices(
                u8,
                message.data(),
                parsed.data(),
            );
        }
    }
}

test "MIDI-CI Profile Specific Data rejects malformed input" {
    const ProfileSpecificData = SpecificData(4);
    const profile = Id.standard(0, 1, 1, 0);
    try std.testing.expectError(
        error.MidiCiProfileSpecificDataCapacityExceeded,
        ProfileSpecificData.init(
            .function_block,
            2,
            try midi_ci.Muid.init(1),
            try midi_ci.Muid.init(2),
            profile,
            &.{ 0, 1, 2, 3, 4 },
        ),
    );
    try std.testing.expectError(
        error.InvalidMidiCiDataByte,
        ProfileSpecificData.init(
            .function_block,
            2,
            try midi_ci.Muid.init(1),
            try midi_ci.Muid.init(2),
            profile,
            &.{0x80},
        ),
    );
    var storage: [26]u8 = undefined;
    const message = try ProfileSpecificData.init(
        .function_block,
        2,
        try midi_ci.Muid.init(1),
        try midi_ci.Muid.init(2),
        profile,
        &.{ 0, 1, 2, 3 },
    );
    _ = try message.encode(&storage);
    storage[18] = 3;
    try std.testing.expectError(
        error.InvalidMidiCiMessageLength,
        ProfileSpecificData.parse(&storage),
    );
    _ = try message.encode(&storage);
    storage[25] = 0x80;
    try std.testing.expectError(
        error.InvalidMidiCiDataByte,
        ProfileSpecificData.parse(&storage),
    );
}
