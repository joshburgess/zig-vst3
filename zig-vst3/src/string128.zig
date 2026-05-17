const std = @import("std");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const code_units = @typeInfo(vsttypes.String128).array.len;
pub const payload_units = code_units - 1;

pub fn clear(dest: *vsttypes.String128) void {
    @memset(dest, 0);
}

pub fn clearPtr(dest: [*]vsttypes.TChar) void {
    @memset(dest[0..code_units], 0);
}

pub fn copy(dest: *vsttypes.String128, source: []const u8) void {
    clear(dest);
    const len = @min(source.len, dest.len - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

pub fn copyPtr(dest: [*]vsttypes.TChar, source: []const u8) void {
    clearPtr(dest);
    const len = @min(source.len, payload_units);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
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
    try std.testing.expectEqualSlices(vsttypes.TChar, &([_]vsttypes.TChar{0} ** code_units), &value);
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
    try std.testing.expectEqualSlices(vsttypes.TChar, &([_]vsttypes.TChar{0} ** code_units), &value);
}
