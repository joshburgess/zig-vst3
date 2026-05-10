const std = @import("std");
const builtin = @import("builtin");

pub const TUID = [16]u8;

pub const FUID = struct {
    bytes: TUID,

    pub fn fromTuid(tuid: TUID) FUID {
        return .{ .bytes = tuid };
    }

    pub fn toTuid(self: FUID) TUID {
        return self.bytes;
    }

    pub fn equals(self: FUID, other: FUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    pub fn fromString(text: []const u8) !FUID {
        return .{ .bytes = try inlineUidFromString(text) };
    }

    pub fn toString(self: FUID) [32]u8 {
        var out: [32]u8 = undefined;

        if (comCompatible()) {
            writeHexU32(&out, 0, long1(self.bytes));
            writeHexU16(&out, 8, @intCast((long2(self.bytes) & 0xFFFF0000) >> 16));
            writeHexU16(&out, 12, @intCast(long2(self.bytes) & 0x0000FFFF));
            writeHexBytes(&out, 16, self.bytes[8..16]);
        } else {
            writeHexBytes(&out, 0, &self.bytes);
        }

        return out;
    }
};

pub fn inlineUid(l1: u32, l2: u32, l3: u32, l4: u32) TUID {
    if (comCompatible()) {
        return .{
            @intCast((l1 & 0x000000FF)),
            @intCast((l1 & 0x0000FF00) >> 8),
            @intCast((l1 & 0x00FF0000) >> 16),
            @intCast((l1 & 0xFF000000) >> 24),
            @intCast((l2 & 0x00FF0000) >> 16),
            @intCast((l2 & 0xFF000000) >> 24),
            @intCast((l2 & 0x000000FF)),
            @intCast((l2 & 0x0000FF00) >> 8),
            @intCast((l3 & 0xFF000000) >> 24),
            @intCast((l3 & 0x00FF0000) >> 16),
            @intCast((l3 & 0x0000FF00) >> 8),
            @intCast((l3 & 0x000000FF)),
            @intCast((l4 & 0xFF000000) >> 24),
            @intCast((l4 & 0x00FF0000) >> 16),
            @intCast((l4 & 0x0000FF00) >> 8),
            @intCast((l4 & 0x000000FF)),
        };
    }

    return .{
        @intCast((l1 & 0xFF000000) >> 24),
        @intCast((l1 & 0x00FF0000) >> 16),
        @intCast((l1 & 0x0000FF00) >> 8),
        @intCast((l1 & 0x000000FF)),
        @intCast((l2 & 0xFF000000) >> 24),
        @intCast((l2 & 0x00FF0000) >> 16),
        @intCast((l2 & 0x0000FF00) >> 8),
        @intCast((l2 & 0x000000FF)),
        @intCast((l3 & 0xFF000000) >> 24),
        @intCast((l3 & 0x00FF0000) >> 16),
        @intCast((l3 & 0x0000FF00) >> 8),
        @intCast((l3 & 0x000000FF)),
        @intCast((l4 & 0xFF000000) >> 24),
        @intCast((l4 & 0x00FF0000) >> 16),
        @intCast((l4 & 0x0000FF00) >> 8),
        @intCast((l4 & 0x000000FF)),
    };
}

pub fn inlineUidFromString(text: []const u8) !TUID {
    if (text.len != 32) return error.InvalidFuidString;

    if (comCompatible()) {
        const l1 = try parseHexU32(text[0..8]);
        const l2_hi = try parseHexU16(text[8..12]);
        const l2_lo = try parseHexU16(text[12..16]);
        const l3 = try parseHexU32(text[16..24]);
        const l4 = try parseHexU32(text[24..32]);
        return inlineUid(l1, (@as(u32, l2_hi) << 16) | l2_lo, l3, l4);
    }

    var bytes: TUID = undefined;
    for (&bytes, 0..) |*byte, index| {
        byte.* = try parseHexByte(text[index * 2 ..][0..2]);
    }
    return bytes;
}

fn comCompatible() bool {
    return builtin.target.os.tag == .windows;
}

fn long1(bytes: TUID) u32 {
    if (comCompatible()) {
        return makeLong(bytes[3], bytes[2], bytes[1], bytes[0]);
    }
    return makeLong(bytes[0], bytes[1], bytes[2], bytes[3]);
}

fn long2(bytes: TUID) u32 {
    if (comCompatible()) {
        return makeLong(bytes[5], bytes[4], bytes[7], bytes[6]);
    }
    return makeLong(bytes[4], bytes[5], bytes[6], bytes[7]);
}

fn makeLong(b0: u8, b1: u8, b2: u8, b3: u8) u32 {
    return (@as(u32, b0) << 24) | (@as(u32, b1) << 16) | (@as(u32, b2) << 8) | b3;
}

fn writeHexU32(out: *[32]u8, offset: usize, value: u32) void {
    writeHexU16(out, offset, @intCast((value & 0xFFFF0000) >> 16));
    writeHexU16(out, offset + 4, @intCast(value & 0x0000FFFF));
}

fn writeHexU16(out: *[32]u8, offset: usize, value: u16) void {
    out[offset] = hexDigit(@intCast((value & 0xF000) >> 12));
    out[offset + 1] = hexDigit(@intCast((value & 0x0F00) >> 8));
    out[offset + 2] = hexDigit(@intCast((value & 0x00F0) >> 4));
    out[offset + 3] = hexDigit(@intCast(value & 0x000F));
}

fn writeHexBytes(out: *[32]u8, offset: usize, bytes: []const u8) void {
    for (bytes, 0..) |byte, index| {
        out[offset + index * 2] = hexDigit(byte >> 4);
        out[offset + index * 2 + 1] = hexDigit(byte & 0x0F);
    }
}

fn hexDigit(value: u8) u8 {
    return if (value < 10) '0' + value else 'A' + (value - 10);
}

fn parseHexU32(text: []const u8) !u32 {
    if (text.len != 8) return error.InvalidFuidString;
    var value: u32 = 0;
    for (text) |ch| {
        value = (value << 4) | try parseHexNibble(ch);
    }
    return value;
}

fn parseHexU16(text: []const u8) !u16 {
    if (text.len != 4) return error.InvalidFuidString;
    var value: u16 = 0;
    for (text) |ch| {
        value = (value << 4) | @as(u16, try parseHexNibble(ch));
    }
    return value;
}

fn parseHexByte(text: []const u8) !u8 {
    if (text.len != 2) return error.InvalidFuidString;
    return (try parseHexNibble(text[0]) << 4) | try parseHexNibble(text[1]);
}

fn parseHexNibble(ch: u8) !u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => error.InvalidFuidString,
    };
}

test "INLINE_UID matches SDK layout for P0 interfaces" {
    const cases = [_]struct {
        name: []const u8,
        actual: TUID,
        non_com: TUID,
        com: TUID,
    }{
        .{
            .name = "FUnknown",
            .actual = inlineUid(0x00000000, 0x00000000, 0xC0000000, 0x00000046),
            .non_com = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
            .com = .{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46 },
        },
        .{
            .name = "IPluginBase",
            .actual = inlineUid(0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625),
            .non_com = .{ 0x22, 0x88, 0x8D, 0xDB, 0x15, 0x6E, 0x45, 0xAE, 0x83, 0x58, 0xB3, 0x48, 0x08, 0x19, 0x06, 0x25 },
            .com = .{ 0xDB, 0x8D, 0x88, 0x22, 0x6E, 0x15, 0xAE, 0x45, 0x83, 0x58, 0xB3, 0x48, 0x08, 0x19, 0x06, 0x25 },
        },
        .{
            .name = "IComponent",
            .actual = inlineUid(0xE831FF31, 0xF2D54301, 0x928EBBEE, 0x25697802),
            .non_com = .{ 0xE8, 0x31, 0xFF, 0x31, 0xF2, 0xD5, 0x43, 0x01, 0x92, 0x8E, 0xBB, 0xEE, 0x25, 0x69, 0x78, 0x02 },
            .com = .{ 0x31, 0xFF, 0x31, 0xE8, 0xD5, 0xF2, 0x01, 0x43, 0x92, 0x8E, 0xBB, 0xEE, 0x25, 0x69, 0x78, 0x02 },
        },
        .{
            .name = "IAudioProcessor",
            .actual = inlineUid(0x42043F99, 0xB7DA453C, 0xA569E79D, 0x9AAEC33D),
            .non_com = .{ 0x42, 0x04, 0x3F, 0x99, 0xB7, 0xDA, 0x45, 0x3C, 0xA5, 0x69, 0xE7, 0x9D, 0x9A, 0xAE, 0xC3, 0x3D },
            .com = .{ 0x99, 0x3F, 0x04, 0x42, 0xDA, 0xB7, 0x3C, 0x45, 0xA5, 0x69, 0xE7, 0x9D, 0x9A, 0xAE, 0xC3, 0x3D },
        },
        .{
            .name = "IEditController",
            .actual = inlineUid(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E),
            .non_com = .{ 0xDC, 0xD7, 0xBB, 0xE3, 0x77, 0x42, 0x44, 0x8D, 0xA8, 0x74, 0xAA, 0xCC, 0x97, 0x9C, 0x75, 0x9E },
            .com = .{ 0xE3, 0xBB, 0xD7, 0xDC, 0x42, 0x77, 0x8D, 0x44, 0xA8, 0x74, 0xAA, 0xCC, 0x97, 0x9C, 0x75, 0x9E },
        },
    };

    for (cases) |case| {
        const expected = if (comCompatible()) case.com else case.non_com;
        try std.testing.expectEqualSlices(u8, &expected, &case.actual);
    }
}

test "FUID string round-trips" {
    const original = FUID.fromTuid(inlineUid(0xDCD7BBE3, 0x7742448D, 0xA874AACC, 0x979C759E));
    const text = original.toString();
    const parsed = try FUID.fromString(&text);
    try std.testing.expect(original.equals(parsed));
    try std.testing.expectError(error.InvalidFuidString, FUID.fromString("not-a-fuid"));
}
