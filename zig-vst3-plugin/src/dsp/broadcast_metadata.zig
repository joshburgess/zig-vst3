const std = @import("std");

pub const fixed_payload_bytes: usize = 602;

pub const Version = enum(u16) {
    version_0 = 0,
    version_1 = 1,
    version_2 = 2,
};

pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn validate(self: Date) !void {
        if (self.year > 9999 or self.month < 1 or self.month > 12)
            return error.InvalidBroadcastDate;
        const maximum_day = daysInMonth(self.year, self.month);
        if (self.day < 1 or self.day > maximum_day)
            return error.InvalidBroadcastDate;
    }
};

pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,

    pub fn validate(self: Time) !void {
        if (self.hour > 23 or self.minute > 59 or self.second > 59)
            return error.InvalidBroadcastTime;
    }
};

/// Loudness values use the BWF unit of one hundredth LU, LUFS, or dBTP.
pub const Loudness = struct {
    integrated: ?i16 = null,
    range: ?i16 = null,
    maximum_true_peak: ?i16 = null,
    maximum_momentary: ?i16 = null,
    maximum_short_term: ?i16 = null,

    pub fn validate(self: Loudness) !void {
        try validateSignedLoudness(self.integrated);
        if (self.range) |value| {
            if (value < 0 or value > 9999)
                return error.InvalidBroadcastLoudness;
        }
        try validateSignedLoudness(self.maximum_true_peak);
        try validateSignedLoudness(self.maximum_momentary);
        try validateSignedLoudness(self.maximum_short_term);
    }
};

pub const Extension = struct {
    description: []const u8 = "",
    originator: []const u8 = "",
    originator_reference: []const u8 = "",
    origination_date: ?Date = null,
    origination_time: ?Time = null,
    time_reference: u64 = 0,
    version: Version = .version_0,
    umid: ?[64]u8 = null,
    loudness: ?Loudness = null,
    coding_history: []const u8 = "",

    pub fn validate(self: Extension) !void {
        try validateFixedText(self.description, 256);
        try validateFixedText(self.originator, 32);
        try validateFixedText(self.originator_reference, 32);
        if (self.origination_date) |date| try date.validate();
        if (self.origination_time) |time| try time.validate();
        try validateCodingHistory(self.coding_history);
        switch (self.version) {
            .version_0 => {
                if (self.umid != null) return error.UmidRequiresBroadcastVersion1;
                if (self.loudness != null)
                    return error.LoudnessRequiresBroadcastVersion2;
            },
            .version_1 => {
                if (self.loudness != null)
                    return error.LoudnessRequiresBroadcastVersion2;
            },
            .version_2 => {
                if (self.loudness) |loudness| try loudness.validate();
            },
        }
    }
};

pub const View = struct {
    bytes: []const u8,
    description: []const u8,
    originator: []const u8,
    originator_reference: []const u8,
    origination_date: ?Date,
    origination_time: ?Time,
    time_reference: u64,
    version: Version,
    umid: ?[]const u8,
    loudness: ?Loudness,
    coding_history: []const u8,

    pub fn init(bytes: []const u8) !View {
        if (bytes.len < 8 + fixed_payload_bytes or
            !std.mem.eql(u8, bytes[0..4], "bext"))
            return error.InvalidBroadcastExtension;
        const payload_bytes: usize = std.mem.readInt(
            u32,
            bytes[4..8],
            .little,
        );
        if (payload_bytes < fixed_payload_bytes)
            return error.InvalidBroadcastExtension;
        const padded_payload = std.math.add(
            usize,
            payload_bytes,
            payload_bytes & 1,
        ) catch return error.InvalidBroadcastExtension;
        const total_bytes = std.math.add(
            usize,
            8,
            padded_payload,
        ) catch return error.InvalidBroadcastExtension;
        if (total_bytes != bytes.len)
            return error.InvalidBroadcastExtension;
        if (payload_bytes & 1 != 0 and bytes[bytes.len - 1] != 0)
            return error.InvalidBroadcastPadding;

        const payload = bytes[8..][0..payload_bytes];
        const description = try readFixedText(payload[0..256]);
        const originator = try readFixedText(payload[256..288]);
        const originator_reference =
            try readFixedText(payload[288..320]);
        const date = try readDate(payload[320..330]);
        const time = try readTime(payload[330..338]);
        const time_reference = std.mem.readInt(
            u64,
            payload[338..346],
            .little,
        );
        const version = std.enums.fromInt(
            Version,
            std.mem.readInt(u16, payload[346..348], .little),
        ) orelse return error.UnsupportedBroadcastVersion;
        const umid_bytes = payload[348..412];
        const loudness_bytes = payload[412..422];
        const reserved = payload[422..602];
        if (!allZero(reserved))
            return error.NonzeroBroadcastReservedBytes;

        var umid: ?[]const u8 = null;
        var loudness: ?Loudness = null;
        switch (version) {
            .version_0 => {
                if (!allZero(payload[348..602]))
                    return error.NonzeroBroadcastReservedBytes;
            },
            .version_1 => {
                if (!allZero(loudness_bytes))
                    return error.NonzeroBroadcastReservedBytes;
                if (!allZero(umid_bytes)) umid = umid_bytes;
            },
            .version_2 => {
                if (!allZero(umid_bytes)) umid = umid_bytes;
                const decoded = Loudness{
                    .integrated = readSignedLoudness(loudness_bytes[0..2]),
                    .range = readRangeLoudness(loudness_bytes[2..4]),
                    .maximum_true_peak = readSignedLoudness(loudness_bytes[4..6]),
                    .maximum_momentary = readSignedLoudness(loudness_bytes[6..8]),
                    .maximum_short_term = readSignedLoudness(loudness_bytes[8..10]),
                };
                loudness = decoded;
            },
        }
        const coding_history = payload[fixed_payload_bytes..];
        try validateCodingHistory(coding_history);
        return .{
            .bytes = bytes,
            .description = description,
            .originator = originator,
            .originator_reference = originator_reference,
            .origination_date = date,
            .origination_time = time,
            .time_reference = time_reference,
            .version = version,
            .umid = umid,
            .loudness = loudness,
            .coding_history = coding_history,
        };
    }
};

pub fn requiredBytes(extension: Extension) !usize {
    try extension.validate();
    const payload_bytes = std.math.add(
        usize,
        fixed_payload_bytes,
        extension.coding_history.len,
    ) catch return error.BroadcastMetadataSizeOverflow;
    if (payload_bytes > std.math.maxInt(u32))
        return error.BroadcastMetadataSizeOverflow;
    const padded_payload = std.math.add(
        usize,
        payload_bytes,
        payload_bytes & 1,
    ) catch return error.BroadcastMetadataSizeOverflow;
    return std.math.add(
        usize,
        8,
        padded_payload,
    ) catch return error.BroadcastMetadataSizeOverflow;
}

pub fn encode(
    destination: []u8,
    extension: Extension,
) ![]const u8 {
    const required = try requiredBytes(extension);
    if (destination.len < required)
        return error.BroadcastMetadataOutputTooSmall;
    const payload_bytes = fixed_payload_bytes +
        extension.coding_history.len;
    @memset(destination[0..required], 0);
    @memcpy(destination[0..4], "bext");
    std.mem.writeInt(
        u32,
        destination[4..8],
        @intCast(payload_bytes),
        .little,
    );
    const payload = destination[8..][0..payload_bytes];
    writeFixedText(payload[0..256], extension.description);
    writeFixedText(payload[256..288], extension.originator);
    writeFixedText(
        payload[288..320],
        extension.originator_reference,
    );
    if (extension.origination_date) |date|
        writeDate(payload[320..330], date);
    if (extension.origination_time) |time|
        writeTime(payload[330..338], time);
    std.mem.writeInt(
        u64,
        payload[338..346],
        extension.time_reference,
        .little,
    );
    std.mem.writeInt(
        u16,
        payload[346..348],
        @intFromEnum(extension.version),
        .little,
    );
    if (extension.umid) |umid| @memcpy(payload[348..412], &umid);
    if (extension.version == .version_2) {
        const loudness = extension.loudness orelse Loudness{};
        writeLoudness(payload[412..414], loudness.integrated);
        writeLoudness(payload[414..416], loudness.range);
        writeLoudness(payload[416..418], loudness.maximum_true_peak);
        writeLoudness(payload[418..420], loudness.maximum_momentary);
        writeLoudness(payload[420..422], loudness.maximum_short_term);
    }
    @memcpy(
        payload[fixed_payload_bytes..],
        extension.coding_history,
    );
    return destination[0..required];
}

pub fn writeFile(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    extension: Extension,
) !usize {
    const required = try requiredBytes(extension);
    const payload_bytes = fixed_payload_bytes +
        extension.coding_history.len;
    var fixed: [8 + fixed_payload_bytes]u8 = undefined;
    _ = try encode(fixed[0..], .{
        .description = extension.description,
        .originator = extension.originator,
        .originator_reference = extension.originator_reference,
        .origination_date = extension.origination_date,
        .origination_time = extension.origination_time,
        .time_reference = extension.time_reference,
        .version = extension.version,
        .umid = extension.umid,
        .loudness = extension.loudness,
        .coding_history = "",
    });
    std.mem.writeInt(
        u32,
        fixed[4..8],
        @intCast(payload_bytes),
        .little,
    );
    try writeAt(io, file, offset, &fixed);
    try writeAt(
        io,
        file,
        offset + fixed.len,
        extension.coding_history,
    );
    if (payload_bytes & 1 != 0)
        try writeAt(io, file, offset + 8 + payload_bytes, &.{0});
    return required;
}

fn writeFixedText(destination: []u8, text: []const u8) void {
    @memcpy(destination[0..text.len], text);
}

fn readFixedText(field: []const u8) ![]const u8 {
    const end = std.mem.indexOfScalar(u8, field, 0) orelse field.len;
    const text = field[0..end];
    try validateFixedText(text, field.len);
    for (field[end..]) |byte| {
        if (byte != 0) return error.InvalidBroadcastTextPadding;
    }
    return text;
}

fn validateFixedText(text: []const u8, capacity: usize) !void {
    if (text.len > capacity) return error.BroadcastTextTooLong;
    for (text) |byte| {
        if (byte < 0x20 or byte > 0x7e)
            return error.InvalidBroadcastText;
    }
}

fn validateCodingHistory(history: []const u8) !void {
    if (history.len == 0) return;
    if (history.len < 2 or
        history[history.len - 2] != '\r' or
        history[history.len - 1] != '\n')
        return error.InvalidCodingHistory;
    var offset: usize = 0;
    while (offset < history.len) {
        const byte = history[offset];
        if (byte == '\r') {
            if (offset + 1 >= history.len or history[offset + 1] != '\n')
                return error.InvalidCodingHistory;
            offset += 2;
            continue;
        }
        if (byte < 0x20 or byte > 0x7e)
            return error.InvalidCodingHistory;
        offset += 1;
    }
}

fn writeDate(destination: []u8, date: Date) void {
    writeFourDigits(destination[0..4], date.year);
    destination[4] = '-';
    writeTwoDigits(destination[5..7], date.month);
    destination[7] = '-';
    writeTwoDigits(destination[8..10], date.day);
}

fn readDate(bytes: []const u8) !?Date {
    if (allZero(bytes)) return null;
    if (!validSeparator(bytes[4]) or !validSeparator(bytes[7]))
        return error.InvalidBroadcastDate;
    const date = Date{
        .year = readDigits(u16, bytes[0..4]) catch
            return error.InvalidBroadcastDate,
        .month = readDigits(u8, bytes[5..7]) catch
            return error.InvalidBroadcastDate,
        .day = readDigits(u8, bytes[8..10]) catch
            return error.InvalidBroadcastDate,
    };
    try date.validate();
    return date;
}

fn writeTime(destination: []u8, time: Time) void {
    writeTwoDigits(destination[0..2], time.hour);
    destination[2] = ':';
    writeTwoDigits(destination[3..5], time.minute);
    destination[5] = ':';
    writeTwoDigits(destination[6..8], time.second);
}

fn readTime(bytes: []const u8) !?Time {
    if (allZero(bytes)) return null;
    if (!validSeparator(bytes[2]) or !validSeparator(bytes[5]))
        return error.InvalidBroadcastTime;
    const time = Time{
        .hour = readDigits(u8, bytes[0..2]) catch
            return error.InvalidBroadcastTime,
        .minute = readDigits(u8, bytes[3..5]) catch
            return error.InvalidBroadcastTime,
        .second = readDigits(u8, bytes[6..8]) catch
            return error.InvalidBroadcastTime,
    };
    try time.validate();
    return time;
}

fn writeFourDigits(destination: []u8, value: u16) void {
    destination[0] = '0' + @as(u8, @intCast(value / 1000));
    destination[1] = '0' + @as(u8, @intCast(value / 100 % 10));
    destination[2] = '0' + @as(u8, @intCast(value / 10 % 10));
    destination[3] = '0' + @as(u8, @intCast(value % 10));
}

fn writeTwoDigits(destination: []u8, value: u8) void {
    destination[0] = '0' + value / 10;
    destination[1] = '0' + value % 10;
}

fn readDigits(comptime Integer: type, bytes: []const u8) !Integer {
    var result: Integer = 0;
    for (bytes) |byte| {
        if (byte < '0' or byte > '9')
            return error.InvalidBroadcastNumber;
        result = result * 10 + @as(Integer, @intCast(byte - '0'));
    }
    return result;
}

fn writeLoudness(destination: []u8, value: ?i16) void {
    std.mem.writeInt(
        u16,
        destination[0..2],
        @bitCast(value orelse @as(i16, 0x7fff)),
        .little,
    );
}

fn readSignedLoudness(bytes: []const u8) ?i16 {
    const raw = @as(u16, bytes[0]) | (@as(u16, bytes[1]) << 8);
    const value: i16 = @bitCast(raw);
    if (value == 0x7fff or value < -9999 or value > 9999)
        return null;
    return value;
}

fn readRangeLoudness(bytes: []const u8) ?i16 {
    const value = readSignedLoudness(bytes) orelse return null;
    return if (value < 0) null else value;
}

fn validateSignedLoudness(value: ?i16) !void {
    if (value) |present| {
        if (present < -9999 or present > 9999)
            return error.InvalidBroadcastLoudness;
    }
}

fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

fn isLeapYear(year: u16) bool {
    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn validSeparator(byte: u8) bool {
    return byte >= 0x20 and byte <= 0x7e;
}

fn writeAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    bytes: []const u8,
) !void {
    var writer = file.writer(io, &.{});
    try writer.seekTo(offset);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

test "BWF version 2 extension round trips all defined fields" {
    var umid: [64]u8 = @splat(0);
    umid[0] = 0x06;
    umid[1] = 0x0a;
    const extension = Extension{
        .description = "Location recording",
        .originator = "zig-vst3",
        .originator_reference = "USID-0001",
        .origination_date = .{ .year = 2026, .month = 7, .day = 25 },
        .origination_time = .{ .hour = 14, .minute = 5, .second = 9 },
        .time_reference = 48_000 * 60,
        .version = .version_2,
        .umid = umid,
        .loudness = .{
            .integrated = -2300,
            .range = 700,
            .maximum_true_peak = -102,
            .maximum_momentary = -1800,
            .maximum_short_term = -2000,
        },
        .coding_history = "A=PCM,F=48000,W=24,M=stereo\r\n",
    };
    var storage: [648]u8 = undefined;
    const encoded = try encode(&storage, extension);
    const view = try View.init(encoded);
    try std.testing.expectEqual(Version.version_2, view.version);
    try std.testing.expectEqualStrings(
        extension.description,
        view.description,
    );
    try std.testing.expectEqual(extension.origination_date, view.origination_date);
    try std.testing.expectEqual(extension.origination_time, view.origination_time);
    try std.testing.expectEqual(extension.time_reference, view.time_reference);
    try std.testing.expectEqualSlices(u8, &umid, view.umid.?);
    try std.testing.expectEqual(extension.loudness, view.loudness);
    try std.testing.expectEqualStrings(
        extension.coding_history,
        view.coding_history,
    );
}

test "BWF versions reserve fields they do not define" {
    var storage: [610]u8 = undefined;
    const version_0 = try encode(&storage, .{});
    const view_0 = try View.init(version_0);
    try std.testing.expectEqual(Version.version_0, view_0.version);
    try std.testing.expect(view_0.umid == null);
    try std.testing.expect(view_0.loudness == null);

    try std.testing.expectError(
        error.UmidRequiresBroadcastVersion1,
        encode(&storage, .{ .umid = @splat(1) }),
    );
    try std.testing.expectError(
        error.LoudnessRequiresBroadcastVersion2,
        encode(&storage, .{
            .version = .version_1,
            .loudness = .{},
        }),
    );
}

test "BWF validation rejects dates loudness and coding history" {
    var storage: [640]u8 = @splat(0xaa);
    const before = storage;
    try std.testing.expectError(
        error.InvalidBroadcastDate,
        encode(&storage, .{
            .origination_date = .{
                .year = 2025,
                .month = 2,
                .day = 29,
            },
        }),
    );
    try std.testing.expectEqual(before, storage);
    try std.testing.expectError(
        error.InvalidBroadcastLoudness,
        encode(&storage, .{
            .version = .version_2,
            .loudness = .{ .range = -1 },
        }),
    );
    try std.testing.expectError(
        error.InvalidCodingHistory,
        encode(&storage, .{ .coding_history = "missing terminator" }),
    );
}

test "BWF parser rejects reserved bytes and padding" {
    var storage: [614]u8 = undefined;
    const encoded = try encode(&storage, .{
        .coding_history = "x\r\n",
    });
    storage[8 + 500] = 1;
    try std.testing.expectError(
        error.NonzeroBroadcastReservedBytes,
        View.init(encoded),
    );
    storage[8 + 500] = 0;
    storage[encoded.len - 1] = 1;
    try std.testing.expectError(
        error.InvalidBroadcastPadding,
        View.init(encoded),
    );
}

test "BWF parser accepts alternate separators and ignores invalid loudness" {
    var storage: [610]u8 = undefined;
    const encoded = try encode(&storage, .{
        .origination_date = .{ .year = 2026, .month = 7, .day = 25 },
        .origination_time = .{ .hour = 9, .minute = 8, .second = 7 },
        .version = .version_2,
    });
    storage[8 + 324] = '/';
    storage[8 + 327] = '.';
    storage[8 + 332] = '_';
    storage[8 + 335] = ' ';
    std.mem.writeInt(u16, storage[8 + 412 ..][0..2], 0x8000, .little);
    std.mem.writeInt(u16, storage[8 + 414 ..][0..2], 0xffff, .little);
    const view = try View.init(encoded);
    try std.testing.expectEqual(
        Date{ .year = 2026, .month = 7, .day = 25 },
        view.origination_date.?,
    );
    try std.testing.expect(view.loudness.?.integrated == null);
    try std.testing.expect(view.loudness.?.range == null);
}
