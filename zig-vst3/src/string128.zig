const std = @import("std");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn clear(dest: *vsttypes.String128) void {
    @memset(dest, 0);
}

pub fn clearPtr(dest: [*]vsttypes.TChar) void {
    @memset(dest[0..128], 0);
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
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

test "String128 copies zero-fill and truncate ASCII text" {
    const long_text =
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyz";
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** 128;

    copy(&value, long_text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), value[127]);
    for (value[0..127], 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, long_text[index]), char);
    }

    clear(&value);
    try std.testing.expectEqualSlices(vsttypes.TChar, &([_]vsttypes.TChar{0} ** 128), &value);
}

test "String128 pointer copies zero-fill and truncate ASCII text" {
    const long_text =
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz" ++
        "abcdefghijklmnopqrstuvwxyz";
    var value: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** 128;

    copyPtr(&value, long_text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), value[127]);
    for (value[0..127], 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, long_text[index]), char);
    }

    clearPtr(&value);
    try std.testing.expectEqualSlices(vsttypes.TChar, &([_]vsttypes.TChar{0} ** 128), &value);
}
