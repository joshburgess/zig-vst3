const std = @import("std");
const fixed_string = @import("fixed_string.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const code_units = @typeInfo(vsttypes.String128).array.len;
pub const payload_units = code_units - 1;
pub const zero: vsttypes.String128 = [_]vsttypes.TChar{0} ** code_units;

pub fn clear(dest: *vsttypes.String128) void {
    @memset(dest, 0);
}

pub fn clearPtr(dest: [*]vsttypes.TChar) void {
    @memset(dest[0..code_units], 0);
}

pub fn copy(dest: *vsttypes.String128, source: []const u8) void {
    fixed_string.copyAsciiToUtf16Z(dest, source);
}

pub fn copyPtr(dest: [*]vsttypes.TChar, source: []const u8) void {
    fixed_string.copyAsciiToUtf16ZPtr(dest, code_units, source);
}

test "String128 copies zero-fill and truncate ASCII text" {
    const long_text =
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyz";
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** code_units;

    copy(&value, long_text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), value[payload_units]);
    for (value[0..payload_units], 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, long_text[index]), char);
    }

    clear(&value);
    try std.testing.expectEqualSlices(vsttypes.TChar, &zero, &value);
}

test "String128 pointer copies zero-fill and truncate ASCII text" {
    const long_text =
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyz";
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** code_units;

    copyPtr(&value, long_text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), value[payload_units]);
    for (value[0..payload_units], 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, long_text[index]), char);
    }

    clearPtr(&value);
    try std.testing.expectEqualSlices(vsttypes.TChar, &zero, &value);
}

test "String128 copies short and empty text with zero fill" {
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** code_units;

    copy(&value, "abc");
    try std.testing.expectEqualSlices(vsttypes.TChar, &.{ 'a', 'b', 'c', 0, 0 }, value[0..5]);
    for (value[5..]) |char| {
        try std.testing.expectEqual(@as(vsttypes.TChar, 0), char);
    }

    value = [_]vsttypes.TChar{'x'} ** code_units;
    copy(&value, "");
    try std.testing.expectEqualSlices(vsttypes.TChar, &zero, &value);
}

test "String128 pointer copies short and empty text with zero fill" {
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** code_units;

    copyPtr(&value, "abc");
    try std.testing.expectEqualSlices(vsttypes.TChar, &.{ 'a', 'b', 'c', 0, 0 }, value[0..5]);
    for (value[5..]) |char| {
        try std.testing.expectEqual(@as(vsttypes.TChar, 0), char);
    }

    value = [_]vsttypes.TChar{'x'} ** code_units;
    copyPtr(&value, "");
    try std.testing.expectEqualSlices(vsttypes.TChar, &zero, &value);
}
