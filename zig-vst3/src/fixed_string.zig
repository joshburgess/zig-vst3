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
