const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

pub fn bounded(index: types.int32, count: usize) ?usize {
    if (index < 0) return null;
    const value: usize = @intCast(index);
    return if (value < count) value else null;
}

pub fn clampedCount(count: types.int32, capacity: usize) usize {
    if (count <= 0) return 0;
    return @min(@as(usize, @intCast(count)), capacity);
}

test "bounded converts valid host indexes" {
    try std.testing.expectEqual(@as(?usize, 0), bounded(0, 2));
    try std.testing.expectEqual(@as(?usize, 1), bounded(1, 2));
}

test "bounded rejects negative and out-of-range host indexes" {
    try std.testing.expectEqual(@as(?usize, null), bounded(-1, 2));
    try std.testing.expectEqual(@as(?usize, null), bounded(2, 2));
    try std.testing.expectEqual(@as(?usize, null), bounded(0, 0));
}

test "clampedCount converts host counts to storage bounds" {
    try std.testing.expectEqual(@as(usize, 0), clampedCount(-1, 3));
    try std.testing.expectEqual(@as(usize, 0), clampedCount(0, 3));
    try std.testing.expectEqual(@as(usize, 2), clampedCount(2, 3));
    try std.testing.expectEqual(@as(usize, 3), clampedCount(4, 3));
}
