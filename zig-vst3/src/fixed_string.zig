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
    copyAsciiToUtf16ZPtr(dest, N, source);
}

pub fn copyAsciiToUtf16ZPtr(dest: [*]types.char16, capacity: usize, source: []const u8) void {
    if (capacity == 0) return;
    @memset(dest[0..capacity], 0);
    const len = @min(source.len, capacity - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

pub fn copyUtf16Z(dest: anytype, source: []const types.char16) void {
    const N = @typeInfo(@TypeOf(dest.*)).array.len;
    copyUtf16ZPtr(dest, N, source);
}

pub fn copyUtf16ZPtr(dest: [*]types.char16, capacity: usize, source: []const types.char16) void {
    if (capacity == 0) return;
    @memset(dest[0..capacity], 0);
    const len = @min(source.len, capacity - 1);
    @memcpy(dest[0..len], source[0..len]);
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

test "copyAsciiToUtf16ZPtr accepts zero capacity" {
    var text = [_]types.char16{'x'} ** 1;

    copyAsciiToUtf16ZPtr(&text, 0, "abc");

    try std.testing.expectEqual(@as(types.char16, 'x'), text[0]);
}

test "copyUtf16Z zero-fills and truncates" {
    var text = [_]types.char16{'x'} ** 4;

    copyUtf16Z(&text, &.{ 'a', 'b', 'c', 'd', 'e' });

    try std.testing.expectEqualSlices(types.char16, &.{ 'a', 'b', 'c', 0 }, &text);
}

test "copyUtf16ZPtr accepts zero capacity" {
    var text = [_]types.char16{'x'} ** 1;

    copyUtf16ZPtr(&text, 0, &.{ 'a', 'b', 'c' });

    try std.testing.expectEqual(@as(types.char16, 'x'), text[0]);
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

test "copyAsciiZ generated capacity boundaries" {
    const Case = struct {
        capacity: usize,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{ .capacity = 1, .expected = &.{0} },
        .{ .capacity = 2, .expected = &.{ 'a', 0 } },
        .{ .capacity = 4, .expected = &.{ 'a', 'b', 'c', 0 } },
        .{ .capacity = 8, .expected = &.{ 'a', 'b', 'c', 'd', 'e', 0, 0, 0 } },
    };

    inline for (cases) |case| {
        var text = [_]u8{'x'} ** case.capacity;

        copyAsciiZ(&text, "abcde");

        try std.testing.expectEqualSlices(u8, case.expected, &text);
    }
}

test "copyAsciiToUtf16Z generated capacity boundaries" {
    const Case = struct {
        capacity: usize,
        expected: []const types.char16,
    };
    const cases = [_]Case{
        .{ .capacity = 1, .expected = &.{0} },
        .{ .capacity = 2, .expected = &.{ 'a', 0 } },
        .{ .capacity = 4, .expected = &.{ 'a', 'b', 'c', 0 } },
        .{ .capacity = 8, .expected = &.{ 'a', 'b', 'c', 'd', 'e', 0, 0, 0 } },
    };

    inline for (cases) |case| {
        var text = [_]types.char16{'x'} ** case.capacity;

        copyAsciiToUtf16Z(&text, "abcde");

        try std.testing.expectEqualSlices(types.char16, case.expected, &text);
    }
}

test "copyUtf16Z generated capacity boundaries" {
    const source = [_]types.char16{ 'a', 'b', 'c', 'd', 'e' };
    const Case = struct {
        capacity: usize,
        expected: []const types.char16,
    };
    const cases = [_]Case{
        .{ .capacity = 1, .expected = &.{0} },
        .{ .capacity = 2, .expected = &.{ 'a', 0 } },
        .{ .capacity = 4, .expected = &.{ 'a', 'b', 'c', 0 } },
        .{ .capacity = 8, .expected = &.{ 'a', 'b', 'c', 'd', 'e', 0, 0, 0 } },
    };

    inline for (cases) |case| {
        var text = [_]types.char16{'x'} ** case.capacity;

        copyUtf16Z(&text, &source);

        try std.testing.expectEqualSlices(types.char16, case.expected, &text);
    }
}

test "readUtf16ZAsAscii generated output boundaries" {
    const source = [_:0]types.char16{ 'a', 0x0100, 'c', 0 };
    const Case = struct {
        capacity: usize,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{ .capacity = 0, .expected = "" },
        .{ .capacity = 1, .expected = &.{'a'} },
        .{ .capacity = 2, .expected = &.{ 'a', 0xff } },
        .{ .capacity = 4, .expected = &.{ 'a', 0xff, 'c' } },
    };

    inline for (cases) |case| {
        var buffer = [_]u8{0} ** case.capacity;

        const text = readUtf16ZAsAscii(&source, &buffer);

        try std.testing.expectEqualSlices(u8, case.expected, text);
    }
}
