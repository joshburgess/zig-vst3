const std = @import("std");

pub const maximum_header_bytes = std.math.maxInt(u14);

pub const Encoding = enum {
    ascii,
    mcoded7,
    zlib_mcoded7,

    pub fn text(self: Encoding) []const u8 {
        return switch (self) {
            .ascii => "ASCII",
            .mcoded7 => "Mcoded7",
            .zlib_mcoded7 => "zlib+Mcoded7",
        };
    }

    pub fn parse(source: []const u8) !Encoding {
        if (std.mem.eql(u8, source, "ASCII")) return .ascii;
        if (std.mem.eql(u8, source, "Mcoded7")) return .mcoded7;
        if (std.mem.eql(u8, source, "zlib+Mcoded7")) return .zlib_mcoded7;
        return error.UnsupportedMidiCiPropertyEncoding;
    }
};

pub const Mcoded7 = struct {
    pub fn encodedLength(source_length: usize) !usize {
        const overhead = source_length / 7 +
            @intFromBool(source_length % 7 != 0);
        return std.math.add(
            usize,
            source_length,
            overhead,
        );
    }

    pub fn decodedLength(source: []const u8) !usize {
        if (source.len == 0) return 0;
        const remainder = source.len % 8;
        if (remainder == 1) return error.InvalidMidiCiMcoded7Length;
        for (source) |byte| {
            if (byte > 0x7f) return error.InvalidMidiCiMcoded7Byte;
        }
        if (remainder != 0) {
            const prefix = source[source.len - remainder];
            const data_count = remainder - 1;
            const unused_bits = 7 - data_count;
            const unused_mask = (@as(u8, 1) << @intCast(unused_bits)) - 1;
            if ((prefix & unused_mask) != 0)
                return error.InvalidMidiCiMcoded7Prefix;
        }
        return (source.len / 8) * 7 + if (remainder == 0) 0 else remainder - 1;
    }

    pub fn encode(source: []const u8, destination: []u8) ![]const u8 {
        const length = try encodedLength(source.len);
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        var source_offset: usize = 0;
        var destination_offset: usize = 0;
        while (source_offset < source.len) {
            const count: usize = @min(source.len - source_offset, 7);
            var prefix: u8 = 0;
            for (source[source_offset..][0..count], 0..) |byte, index| {
                prefix |= (byte >> 7) << @intCast(6 - index);
                destination[destination_offset + 1 + index] = byte & 0x7f;
            }
            destination[destination_offset] = prefix;
            source_offset += count;
            destination_offset += count + 1;
        }
        return destination[0..length];
    }

    pub fn decode(source: []const u8, destination: []u8) ![]const u8 {
        const length = try decodedLength(source);
        if (destination.len < length) return error.MidiCiBufferTooSmall;
        var source_offset: usize = 0;
        var destination_offset: usize = 0;
        while (source_offset < source.len) {
            const count: usize = @min(source.len - source_offset - 1, 7);
            const prefix = source[source_offset];
            for (source[source_offset + 1 ..][0..count], 0..) |byte, index| {
                const high_bit = (prefix >> @intCast(6 - index)) & 1;
                destination[destination_offset + index] = byte | (high_bit << 7);
            }
            source_offset += count + 1;
            destination_offset += count;
        }
        return destination[0..length];
    }
};

pub const ZlibMcoded7 = struct {
    pub const work_buffer_length = std.compress.flate.max_window_len;

    pub fn encode(
        source: []const u8,
        compressed: []u8,
        work: []u8,
        destination: []u8,
    ) ![]const u8 {
        if (compressed.len <= 8 or work.len < work_buffer_length)
            return error.MidiCiBufferTooSmall;
        var output: std.Io.Writer = .fixed(compressed);
        var compressor = std.compress.flate.Compress.init(
            &output,
            work,
            .zlib,
            .default,
        ) catch return error.MidiCiBufferTooSmall;
        compressor.writer.writeAll(source) catch
            return error.MidiCiBufferTooSmall;
        compressor.finish() catch return error.MidiCiBufferTooSmall;
        return Mcoded7.encode(output.buffered(), destination);
    }

    pub fn decode(
        source: []const u8,
        compressed: []u8,
        work: []u8,
        staging: []u8,
        destination: []u8,
    ) ![]const u8 {
        if (work.len < work_buffer_length)
            return error.MidiCiBufferTooSmall;
        const zlib = try Mcoded7.decode(source, compressed);
        var input: std.Io.Reader = .fixed(zlib);
        var decompressor: std.compress.flate.Decompress =
            .init(&input, .zlib, work);
        var output: std.Io.Writer = .fixed(staging);
        const count = decompressor.reader.streamRemaining(&output) catch |err|
            return switch (err) {
                error.WriteFailed => error.MidiCiBufferTooSmall,
                else => error.InvalidMidiCiPropertyCompressedData,
            };
        if (input.bufferedLen() != 0)
            return error.InvalidMidiCiPropertyCompressedData;
        if (destination.len < count) return error.MidiCiBufferTooSmall;
        @memcpy(destination[0..count], staging[0..count]);
        return destination[0..count];
    }
};

pub const RequestHeader = struct {
    resource: []const u8,
    res_id: ?[]const u8 = null,
    mutual_encoding: ?Encoding = null,
    media_type: ?[]const u8 = null,
    pagination: ?Pagination = null,
    set_partial: bool = false,

    pub fn valid(self: RequestHeader) bool {
        if (!validResource(self.resource)) return false;
        if (self.res_id) |value| {
            if (!validResourceId(value)) return false;
        }
        if (self.media_type) |value| {
            if (!validAsciiText(value, 75)) return false;
        }
        if (self.pagination) |pagination| {
            if (pagination.limit == 0) return false;
        }
        return true;
    }

    pub fn writeJson(self: RequestHeader, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiPropertyRequestHeader;
        try writer.writeAll("{\"resource\":");
        try writeString(writer, self.resource);
        if (self.res_id) |value| {
            try writer.writeAll(",\"resId\":");
            try writeString(writer, value);
        }
        if (self.mutual_encoding) |value| {
            try writer.writeAll(",\"mutualEncoding\":");
            try writeString(writer, value.text());
        }
        if (self.media_type) |value| {
            try writer.writeAll(",\"mediaType\":");
            try writeString(writer, value);
        }
        if (self.pagination) |value| {
            try writer.print(",\"offset\":{d},\"limit\":{d}", .{
                value.offset,
                value.limit,
            });
        }
        if (self.set_partial)
            try writer.writeAll(",\"setPartial\":true");
        try writer.writeByte('}');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(RequestHeader) {
        var parsed = try parseHeaderObject(allocator, source, "{\"resource\":");
        errdefer parsed.deinit();
        const object = parsed.value.object;
        const resource = try requiredString(object, "resource");
        const offset = try optionalUnsigned(object, "offset", u32);
        const limit = try optionalUnsigned(object, "limit", u32);
        if ((offset == null) != (limit == null))
            return error.IncompleteMidiCiPropertyPagination;
        const pagination: ?Pagination = if (offset) |offset_value| .{
            .offset = offset_value,
            .limit = limit orelse
                return error.IncompleteMidiCiPropertyPagination,
        } else null;
        const value = RequestHeader{
            .resource = resource,
            .res_id = try optionalString(object, "resId"),
            .mutual_encoding = if (try optionalString(object, "mutualEncoding")) |text|
                try Encoding.parse(text)
            else
                null,
            .media_type = try optionalString(object, "mediaType"),
            .pagination = pagination,
            .set_partial = try optionalBool(object, "setPartial") orelse false,
        };
        if (!value.valid()) return error.InvalidMidiCiPropertyRequestHeader;
        return transferParsed(RequestHeader, parsed, value);
    }
};

pub const Pagination = struct {
    offset: u32,
    limit: u32,
};

pub const ReplyStatus = enum(u16) {
    ok = 200,
    accepted = 202,
    resource_unavailable = 341,
    bad_data = 342,
    too_many_requests = 343,
    bad_request = 400,
    unauthorized = 403,
    not_found = 404,
    not_allowed = 405,
    payload_too_large = 413,
    unsupported_media_type = 415,
    invalid_data_version = 445,
    internal_error = 500,
};

pub const ReplyHeader = struct {
    status: ReplyStatus,
    message: ?[]const u8 = null,
    mutual_encoding: ?Encoding = null,
    cache_time: ?u32 = null,
    total_count: ?u32 = null,
    media_type: ?[]const u8 = null,
    subscribe_id: ?[]const u8 = null,
    state_revision: ?[]const u8 = null,
    timestamp: ?u64 = null,

    pub fn valid(self: ReplyHeader) bool {
        if (self.message) |value| {
            if (!validAsciiText(value, 512)) return false;
        }
        if (self.media_type) |value| {
            if (!validAsciiText(value, 75)) return false;
        }
        if (self.subscribe_id) |value| {
            if (!validSubscribeId(value)) return false;
        }
        if (self.state_revision) |value| {
            if (!validAsciiText(value, 512)) return false;
        }
        return true;
    }

    pub fn writeJson(self: ReplyHeader, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiPropertyReplyHeader;
        try writer.print("{{\"status\":{d}", .{@intFromEnum(self.status)});
        if (self.message) |value| {
            try writer.writeAll(",\"message\":");
            try writeString(writer, value);
        }
        if (self.mutual_encoding) |value| {
            try writer.writeAll(",\"mutualEncoding\":");
            try writeString(writer, value.text());
        }
        if (self.cache_time) |value|
            try writer.print(",\"cacheTime\":{d}", .{value});
        if (self.total_count) |value|
            try writer.print(",\"totalCount\":{d}", .{value});
        if (self.media_type) |value| {
            try writer.writeAll(",\"mediaType\":");
            try writeString(writer, value);
        }
        if (self.subscribe_id) |value| {
            try writer.writeAll(",\"subscribeId\":");
            try writeString(writer, value);
        }
        if (self.state_revision) |value| {
            try writer.writeAll(",\"stateRev\":");
            try writeString(writer, value);
        }
        if (self.timestamp) |value|
            try writer.print(",\"timestamp\":{d}", .{value});
        try writer.writeByte('}');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(ReplyHeader) {
        var parsed = try parseHeaderObject(allocator, source, "{\"status\":");
        errdefer parsed.deinit();
        const object = parsed.value.object;
        const status_number = try requiredUnsigned(object, "status", u16);
        const status = parseEnumNumber(ReplyStatus, status_number) orelse
            return error.InvalidMidiCiPropertyReplyStatus;
        const value = ReplyHeader{
            .status = status,
            .message = try optionalString(object, "message"),
            .mutual_encoding = if (try optionalString(object, "mutualEncoding")) |text|
                try Encoding.parse(text)
            else
                null,
            .cache_time = try optionalUnsigned(object, "cacheTime", u32),
            .total_count = try optionalUnsigned(object, "totalCount", u32),
            .media_type = try optionalString(object, "mediaType"),
            .subscribe_id = try optionalString(object, "subscribeId"),
            .state_revision = try optionalString(object, "stateRev"),
            .timestamp = try optionalUnsigned(object, "timestamp", u64),
        };
        if (!value.valid()) return error.InvalidMidiCiPropertyReplyHeader;
        return transferParsed(ReplyHeader, parsed, value);
    }
};

pub const SubscriptionCommand = enum {
    start,
    partial,
    full,
    notify,
    end,

    pub fn text(self: SubscriptionCommand) []const u8 {
        return @tagName(self);
    }

    pub fn parse(source: []const u8) !SubscriptionCommand {
        inline for (std.meta.tags(SubscriptionCommand)) |tag| {
            if (std.mem.eql(u8, source, @tagName(tag))) return tag;
        }
        return error.InvalidMidiCiPropertySubscriptionCommand;
    }
};

pub const SubscriptionHeader = struct {
    command: SubscriptionCommand,
    resource: ?[]const u8 = null,
    res_id: ?[]const u8 = null,
    mutual_encoding: ?Encoding = null,
    media_type: ?[]const u8 = null,
    subscribe_id: ?[]const u8 = null,

    pub fn valid(self: SubscriptionHeader) bool {
        if (self.resource) |value| {
            if (!validResource(value)) return false;
        }
        if (self.res_id) |value| {
            if (!validResourceId(value)) return false;
        }
        if (self.media_type) |value| {
            if (!validAsciiText(value, 75)) return false;
        }
        if (self.subscribe_id) |value| {
            if (!validSubscribeId(value)) return false;
        }
        return switch (self.command) {
            .start => self.resource != null and self.subscribe_id == null,
            .partial, .full, .notify, .end => self.resource == null and
                self.res_id == null and
                self.subscribe_id != null,
        };
    }

    pub fn writeJson(self: SubscriptionHeader, writer: anytype) !void {
        if (!self.valid()) return error.InvalidMidiCiPropertySubscriptionHeader;
        try writer.writeAll("{\"command\":");
        try writeString(writer, self.command.text());
        if (self.resource) |value| {
            try writer.writeAll(",\"resource\":");
            try writeString(writer, value);
        }
        if (self.res_id) |value| {
            try writer.writeAll(",\"resId\":");
            try writeString(writer, value);
        }
        if (self.mutual_encoding) |value| {
            try writer.writeAll(",\"mutualEncoding\":");
            try writeString(writer, value.text());
        }
        if (self.media_type) |value| {
            try writer.writeAll(",\"mediaType\":");
            try writeString(writer, value);
        }
        if (self.subscribe_id) |value| {
            try writer.writeAll(",\"subscribeId\":");
            try writeString(writer, value);
        }
        try writer.writeByte('}');
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(SubscriptionHeader) {
        var parsed = try parseHeaderObject(allocator, source, "{\"command\":");
        errdefer parsed.deinit();
        const object = parsed.value.object;
        const value = SubscriptionHeader{
            .command = try SubscriptionCommand.parse(
                try requiredString(object, "command"),
            ),
            .resource = try optionalString(object, "resource"),
            .res_id = try optionalString(object, "resId"),
            .mutual_encoding = if (try optionalString(object, "mutualEncoding")) |text|
                try Encoding.parse(text)
            else
                null,
            .media_type = try optionalString(object, "mediaType"),
            .subscribe_id = try optionalString(object, "subscribeId"),
        };
        if (!value.valid()) return error.InvalidMidiCiPropertySubscriptionHeader;
        return transferParsed(SubscriptionHeader, parsed, value);
    }
};

pub const NotifyStatus = enum(u16) {
    timeout_wait = 100,
    terminate = 144,
    timeout = 408,
};

pub const NotifyHeader = struct {
    status: NotifyStatus,

    pub fn writeJson(self: NotifyHeader, writer: anytype) !void {
        try writer.print("{{\"status\":{d}}}", .{@intFromEnum(self.status)});
    }

    pub fn parseJson(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) !std.json.Parsed(NotifyHeader) {
        var parsed = try parseHeaderObject(allocator, source, "{\"status\":");
        errdefer parsed.deinit();
        const status_number = try requiredUnsigned(
            parsed.value.object,
            "status",
            u16,
        );
        const value = NotifyHeader{
            .status = parseEnumNumber(NotifyStatus, status_number) orelse
                return error.InvalidMidiCiPropertyNotifyStatus,
        };
        return transferParsed(NotifyHeader, parsed, value);
    }
};

fn parseHeaderObject(
    allocator: std.mem.Allocator,
    source: []const u8,
    required_prefix: []const u8,
) !std.json.Parsed(std.json.Value) {
    if (source.len == 0 or source.len > maximum_header_bytes)
        return error.InvalidMidiCiPropertyHeaderLength;
    if (!std.mem.startsWith(u8, source, required_prefix))
        return error.InvalidMidiCiPropertyHeaderOrder;
    try validateHeaderBytes(source);
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        source,
        .{},
    );
    errdefer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |value| value,
        else => return error.InvalidMidiCiPropertyHeader,
    };
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        if (!validHeaderKey(entry.key_ptr.*))
            return error.InvalidMidiCiPropertyHeaderKey;
        switch (entry.value_ptr.*) {
            .bool, .integer, .float, .number_string, .string => {},
            else => return error.InvalidMidiCiPropertyHeaderValue,
        }
    }
    return parsed;
}

fn validateHeaderBytes(source: []const u8) !void {
    var in_string = false;
    var escaped = false;
    for (source) |byte| {
        if (byte > 0x7f) return error.InvalidMidiCiPropertyHeaderByte;
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (byte == '\\') {
                escaped = true;
            } else if (byte == '"') {
                in_string = false;
            }
        } else if (byte == '"') {
            in_string = true;
        } else if (std.ascii.isWhitespace(byte)) {
            return error.InvalidMidiCiPropertyHeaderWhitespace;
        }
    }
}

fn validHeaderKey(source: []const u8) bool {
    if (source.len == 0 or source.len > 20 or
        !std.ascii.isLower(source[0]))
        return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte)) return false;
    }
    return true;
}

fn validResource(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '-') return false;
    }
    return true;
}

fn validResourceId(source: []const u8) bool {
    if (source.len == 0 or source.len > 36) return false;
    for (source) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    }
    return true;
}

fn validSubscribeId(source: []const u8) bool {
    if (source.len == 0 or source.len > 8) return false;
    for (source) |byte| {
        if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '_')
            return false;
    }
    return true;
}

fn validAsciiText(source: []const u8, maximum: usize) bool {
    if (source.len > maximum) return false;
    for (source) |byte| {
        if (byte > 0x7f) return false;
    }
    return true;
}

fn writeString(writer: anytype, source: []const u8) !void {
    try writer.print("{f}", .{std.json.fmt(source, .{})});
}

fn requiredString(
    object: std.json.ObjectMap,
    key: []const u8,
) ![]const u8 {
    return (try optionalString(object, key)) orelse
        error.MissingMidiCiPropertyHeaderField;
}

fn optionalString(
    object: std.json.ObjectMap,
    key: []const u8,
) !?[]const u8 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .string => |text| text,
        else => error.InvalidMidiCiPropertyHeaderFieldType,
    };
}

fn optionalBool(object: std.json.ObjectMap, key: []const u8) !?bool {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .bool => |boolean| boolean,
        else => error.InvalidMidiCiPropertyHeaderFieldType,
    };
}

fn requiredUnsigned(
    object: std.json.ObjectMap,
    key: []const u8,
    comptime T: type,
) !T {
    return (try optionalUnsigned(object, key, T)) orelse
        error.MissingMidiCiPropertyHeaderField;
}

fn optionalUnsigned(
    object: std.json.ObjectMap,
    key: []const u8,
    comptime T: type,
) !?T {
    const value = object.get(key) orelse return null;
    const integer = switch (value) {
        .integer => |number| number,
        else => return error.InvalidMidiCiPropertyHeaderFieldType,
    };
    if (integer < 0 or integer > std.math.maxInt(T))
        return error.InvalidMidiCiPropertyHeaderNumber;
    return @intCast(integer);
}

fn transferParsed(
    comptime T: type,
    parsed: std.json.Parsed(std.json.Value),
    value: T,
) std.json.Parsed(T) {
    return .{ .arena = parsed.arena, .value = value };
}

fn parseEnumNumber(comptime T: type, number: anytype) ?T {
    inline for (std.meta.tags(T)) |tag| {
        if (@intFromEnum(tag) == number) return tag;
    }
    return null;
}

test "Property Exchange request headers round trip common fields" {
    const expected = RequestHeader{
        .resource = "ExampleList",
        .res_id = "entry_1",
        .mutual_encoding = .mcoded7,
        .media_type = "application/octet-stream",
        .pagination = .{ .offset = 10, .limit = 5 },
        .set_partial = true,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try expected.writeJson(&output.writer);
    try std.testing.expectEqualStrings(
        "{\"resource\":\"ExampleList\",\"resId\":\"entry_1\",\"mutualEncoding\":\"Mcoded7\",\"mediaType\":\"application/octet-stream\",\"offset\":10,\"limit\":5,\"setPartial\":true}",
        output.written(),
    );
    const parsed = try RequestHeader.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings(expected.resource, parsed.value.resource);
    try std.testing.expectEqual(expected.pagination, parsed.value.pagination);
    try std.testing.expect(parsed.value.set_partial);
}

test "Property Exchange reply headers cover status and metadata" {
    const expected = ReplyHeader{
        .status = .ok,
        .message = "Ready",
        .mutual_encoding = .zlib_mcoded7,
        .cache_time = 30,
        .total_count = 128,
        .subscribe_id = "sub_1",
        .state_revision = "revision_7",
        .timestamp = 1_700_000_000,
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try expected.writeJson(&output.writer);
    const parsed = try ReplyHeader.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(expected.status, parsed.value.status);
    try std.testing.expectEqual(expected.cache_time, parsed.value.cache_time);
    try std.testing.expectEqual(expected.total_count, parsed.value.total_count);
    try std.testing.expectEqualStrings("Ready", parsed.value.message.?);
    try std.testing.expectEqualStrings(
        "revision_7",
        parsed.value.state_revision.?,
    );
    try std.testing.expectEqual(
        @as(?u64, 1_700_000_000),
        parsed.value.timestamp,
    );
}

test "Property Exchange subscription headers enforce lifecycle shapes" {
    const start = SubscriptionHeader{
        .command = .start,
        .resource = "ChannelList",
    };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try start.writeJson(&output.writer);
    try std.testing.expectEqualStrings(
        "{\"command\":\"start\",\"resource\":\"ChannelList\"}",
        output.written(),
    );
    const parsed = try SubscriptionHeader.parseJson(
        std.testing.allocator,
        "{\"command\":\"partial\",\"subscribeId\":\"sub123\"}",
    );
    defer parsed.deinit();
    try std.testing.expectEqual(.partial, parsed.value.command);
    try std.testing.expectEqualStrings("sub123", parsed.value.subscribe_id.?);
    try std.testing.expectError(
        error.InvalidMidiCiPropertySubscriptionHeader,
        SubscriptionHeader.parseJson(
            std.testing.allocator,
            "{\"command\":\"start\",\"subscribeId\":\"sub123\"}",
        ),
    );
}

test "Property Exchange notify headers accept only defined statuses" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try (NotifyHeader{ .status = .terminate }).writeJson(&output.writer);
    try std.testing.expectEqualStrings("{\"status\":144}", output.written());
    const parsed = try NotifyHeader.parseJson(
        std.testing.allocator,
        output.written(),
    );
    defer parsed.deinit();
    try std.testing.expectEqual(.terminate, parsed.value.status);
    try std.testing.expectError(
        error.InvalidMidiCiPropertyNotifyStatus,
        NotifyHeader.parseJson(std.testing.allocator, "{\"status\":200}"),
    );
}

test "Property Exchange headers reject malformed constrained JSON" {
    const cases = [_][]const u8{
        "{ \"resource\":\"DeviceInfo\"}",
        "{\"resource\": \"DeviceInfo\"}",
        "{\"resId\":\"one\",\"resource\":\"DeviceInfo\"}",
        "{\"resource\":\"Bad.Resource\"}",
        "{\"resource\":\"DeviceInfo\",\"offset\":0}",
        "{\"resource\":\"DeviceInfo\",\"limit\":1}",
        "{\"resource\":\"DeviceInfo\",\"bad_key\":true}",
        "{\"resource\":\"DeviceInfo\",\"extra\":[]}",
        "{\"resource\":\"DeviceInfo\",\"mediaType\":\"audio/\xc3\xa9\"}",
    };
    for (cases) |source| {
        if (RequestHeader.parseJson(std.testing.allocator, source)) |parsed| {
            parsed.deinit();
            return error.TestExpectedError;
        } else |_| {}
    }
}

test "Property Exchange headers reject one byte over the wire limit before allocation" {
    const prefix = "{\"resource\":";
    var source: [maximum_header_bytes + 1]u8 = @splat('x');
    @memcpy(source[0..prefix.len], prefix);
    try std.testing.expectError(
        error.InvalidMidiCiPropertyHeaderLength,
        RequestHeader.parseJson(std.testing.failing_allocator, &source),
    );
}

test "Property Exchange header parsing releases every failed allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        testRequestHeaderAllocationFailure,
        .{},
    );
}

fn testRequestHeaderAllocationFailure(allocator: std.mem.Allocator) !void {
    const parsed = try RequestHeader.parseJson(
        allocator,
        "{\"resource\":\"DeviceInfo\",\"resId\":\"entry_1\"}",
    );
    defer parsed.deinit();
    try std.testing.expectEqualStrings("DeviceInfo", parsed.value.resource);
    try std.testing.expectEqualStrings("entry_1", parsed.value.res_id.?);
}

test "Property Exchange zlib Mcoded7 round trips and rejects malformed data" {
    var compressed: [256]u8 = undefined;
    var work: [ZlibMcoded7.work_buffer_length]u8 = undefined;
    var encoded: [320]u8 = undefined;
    var staging: [128]u8 = undefined;
    var decoded: [128]u8 = undefined;
    const source =
        "{\"resource\":\"ChannelList\",\"message\":\"repeated repeated repeated\"}";
    const value = try ZlibMcoded7.encode(
        source,
        &compressed,
        &work,
        &encoded,
    );
    for (value) |byte| try std.testing.expect(byte <= 0x7f);
    try std.testing.expectEqualSlices(
        u8,
        source,
        try ZlibMcoded7.decode(
            value,
            &compressed,
            &work,
            &staging,
            &decoded,
        ),
    );
    const before = decoded;
    try std.testing.expectError(
        error.MidiCiBufferTooSmall,
        ZlibMcoded7.decode(
            value,
            &compressed,
            &work,
            &staging,
            decoded[0..4],
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &decoded);
    var malformed = encoded;
    malformed[1] ^= 1;
    try std.testing.expectError(
        error.InvalidMidiCiPropertyCompressedData,
        ZlibMcoded7.decode(
            malformed[0..value.len],
            &compressed,
            &work,
            &staging,
            &decoded,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &decoded);
}

test "Mcoded7 round trips every short-group boundary" {
    var source: [33]u8 = undefined;
    for (&source, 0..) |*byte, index| byte.* = @truncate(index * 37 + 0x80);
    var encoded: [38]u8 = undefined;
    var decoded: [33]u8 = undefined;
    for (0..source.len + 1) |length| {
        const bytes = try Mcoded7.encode(source[0..length], &encoded);
        for (bytes) |byte| try std.testing.expect(byte <= 0x7f);
        const result = try Mcoded7.decode(bytes, &decoded);
        try std.testing.expectEqualSlices(u8, source[0..length], result);
        try std.testing.expectEqual(length, try Mcoded7.decodedLength(bytes));
    }
}

test "Mcoded7 rejects malformed input before changing destination" {
    var destination = [_]u8{0xaa} ** 8;
    try std.testing.expectError(
        error.InvalidMidiCiMcoded7Length,
        Mcoded7.decode(&.{0}, &destination),
    );
    try std.testing.expectError(
        error.InvalidMidiCiMcoded7Byte,
        Mcoded7.decode(&.{ 0, 0x80 }, &destination),
    );
    try std.testing.expectError(
        error.InvalidMidiCiMcoded7Prefix,
        Mcoded7.decode(&.{ 1, 0 }, &destination),
    );
    try std.testing.expectEqualSlices(u8, &([_]u8{0xaa} ** 8), &destination);
}

const property_header_fuzz_seeds = [_][]const u8{
    "{\"resource\":\"DeviceInfo\"}",
    "{\"status\":200}",
    "{\"command\":\"start\",\"resource\":\"ChannelList\"}",
    "{\"status\":144}",
};

test "fuzz bounded MIDI-CI Property Exchange headers and Mcoded7" {
    try std.testing.fuzz({}, fuzzPropertyHeadersAndMcoded7, .{
        .corpus = &.{
            property_header_fuzz_seeds[0],
            property_header_fuzz_seeds[1],
            property_header_fuzz_seeds[2],
            property_header_fuzz_seeds[3],
        },
    });
}

fn fuzzPropertyHeadersAndMcoded7(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    var storage: [1024]u8 = undefined;
    const length: usize = switch (smith.valueRangeAtMost(u8, 0, 4)) {
        0 => smith.slice(&storage),
        1...4 => |seed_index| seeded: {
            const seed = property_header_fuzz_seeds[seed_index - 1];
            @memcpy(storage[0..seed.len], seed);
            break :seeded seed.len;
        },
        else => smith.slice(&storage),
    };
    const source = storage[0..length];

    if (RequestHeader.parseJson(std.testing.allocator, source)) |parsed| {
        defer parsed.deinit();
        try std.testing.expect(parsed.value.valid());
    } else |_| {}
    if (ReplyHeader.parseJson(std.testing.allocator, source)) |parsed| {
        defer parsed.deinit();
        try std.testing.expect(parsed.value.valid());
    } else |_| {}
    if (SubscriptionHeader.parseJson(std.testing.allocator, source)) |parsed| {
        defer parsed.deinit();
        try std.testing.expect(parsed.value.valid());
    } else |_| {}
    if (NotifyHeader.parseJson(std.testing.allocator, source)) |parsed| {
        defer parsed.deinit();
    } else |_| {}

    var decoded_storage: [1024]u8 = undefined;
    if (Mcoded7.decode(source, &decoded_storage)) |decoded| {
        var encoded_storage: [1171]u8 = undefined;
        const encoded = try Mcoded7.encode(decoded, &encoded_storage);
        try std.testing.expectEqualSlices(u8, source, encoded);
    } else |_| {}
}
