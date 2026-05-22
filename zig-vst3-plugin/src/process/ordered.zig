pub fn before(candidate: anytype, current: anytype) bool {
    return candidate.sample_offset < current.sample_offset;
}

pub fn atOrAfter(candidate: anytype, current: anytype) bool {
    return candidate.sample_offset >= current.sample_offset;
}

pub fn afterOffset(candidate: anytype, sample_offset: usize) bool {
    return candidate.sample_offset > sample_offset;
}

pub fn beforeOffset(candidate: anytype, sample_offset: usize) bool {
    return candidate.sample_offset < sample_offset;
}

pub fn atOrBeforeOffset(candidate: anytype, sample_offset: usize) bool {
    return candidate.sample_offset <= sample_offset;
}

pub fn indexedBefore(candidate: anytype, current: anytype) bool {
    return before(candidate.item, current.item) or
        (candidate.item.sample_offset == current.item.sample_offset and candidate.index < current.index);
}

pub fn afterCursor(item: anytype, index: usize, last_offset: ?usize, last_index: usize) bool {
    const offset = last_offset orelse return true;
    if (item.sample_offset < offset) return false;
    if (item.sample_offset == offset and index <= last_index) return false;
    return true;
}

test "sample-offset ordering handles stored-order ties" {
    const std = @import("std");
    const Indexed = struct {
        item: struct { sample_offset: usize },
        index: usize,
    };

    try std.testing.expect(before(.{ .sample_offset = 1 }, .{ .sample_offset = 2 }));
    try std.testing.expect(!before(.{ .sample_offset = 2 }, .{ .sample_offset = 2 }));
    try std.testing.expect(atOrAfter(.{ .sample_offset = 2 }, .{ .sample_offset = 2 }));
    try std.testing.expect(afterOffset(.{ .sample_offset = 3 }, 2));
    try std.testing.expect(beforeOffset(.{ .sample_offset = 1 }, 2));
    try std.testing.expect(atOrBeforeOffset(.{ .sample_offset = 2 }, 2));
    try std.testing.expect(!atOrBeforeOffset(.{ .sample_offset = 3 }, 2));
    try std.testing.expect(indexedBefore(
        Indexed{ .item = .{ .sample_offset = 4 }, .index = 2 },
        Indexed{ .item = .{ .sample_offset = 4 }, .index = 3 },
    ));
    try std.testing.expect(afterCursor(.{ .sample_offset = 4 }, 3, 4, 2));
    try std.testing.expect(!afterCursor(.{ .sample_offset = 4 }, 2, 4, 2));
    try std.testing.expect(!afterCursor(.{ .sample_offset = 3 }, 3, 4, 2));
}
