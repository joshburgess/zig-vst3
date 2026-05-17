const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

pub fn copyAsciiZ(dest: anytype, source: []const u8) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    @memset(dest, 0);
    const len = @min(source.len, N - 1);
    @memcpy(dest[0..len], source[0..len]);
}

pub fn copyAsciiToUtf16Z(dest: anytype, source: []const u8) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    @memset(dest, 0);
    const len = @min(source.len, N - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

pub fn readUtf16ZAsAscii(source: [*]const types.char16, buffer: []u8) []const u8 {
    var len: usize = 0;
    while (len < buffer.len and source[len] != 0) : (len += 1) {
        buffer[len] = @intCast(@min(source[len], 0xff));
    }
    return buffer[0..len];
}

test "copyAsciiZ zero-fills and truncates" {
    var text = [_]u8{'x'} ** 4;

    copyAsciiZ(&text, "abcdef");

    try std.testing.expectEqualSlices(u8, &.{ 'a', 'b', 'c', 0 }, &text);
}

test "copyAsciiToUtf16Z zero-fills and truncates" {
    var text = [_]types.char16{'x'} ** 4;

    copyAsciiToUtf16Z(&text, "abcdef");

    try std.testing.expectEqualSlices(types.char16, &.{ 'a', 'b', 'c', 0 }, &text);
}

test "readUtf16ZAsAscii stops at zero and clamps code units" {
    const source = [_:0]types.char16{ 'a', 0x1234, 'c', 0 };
    var buffer = [_]u8{0} ** 8;

    const text = readUtf16ZAsAscii(&source, &buffer);

    try std.testing.expectEqualSlices(u8, &.{ 'a', 0xff, 'c' }, text);
}

test "readUtf16ZAsAscii truncates to output buffer" {
    const source = [_:0]types.char16{ 'a', 'b', 'c', 0 };
    var buffer = [_]u8{0} ** 2;

    const text = readUtf16ZAsAscii(&source, &buffer);

    try std.testing.expectEqualSlices(u8, "ab", text);
}
