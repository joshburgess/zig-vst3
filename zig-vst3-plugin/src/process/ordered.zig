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

pub fn frameSpan(range: anytype) usize {
    return range.end_offset -| range.start_offset;
}

pub fn withinRange(range: anytype, sample_offset: usize) bool {
    return sample_offset >= range.start_offset and sample_offset < range.end_offset;
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

pub fn earliestOffset(first: ?usize, second: ?usize, fallback: usize) usize {
    const a = first orelse return second orelse fallback;
    const b = second orelse return a;
    return @min(a, b);
}

pub fn Matchers(comptime Item: type) type {
    return struct {
        pub const Indexed = struct {
            item: Item,
            index: usize,
        };

        pub fn first(items: []const Item, context: anytype, comptime matches: anytype) ?Item {
            var result: ?Item = null;
            for (items) |item| {
                if (!matches(item, context)) continue;
                if (result) |current| {
                    if (before(item, current)) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        pub fn latest(items: []const Item, context: anytype, comptime matches: anytype) ?Item {
            var result: ?Item = null;
            for (items) |item| {
                if (!matches(item, context)) continue;
                if (result) |current| {
                    if (atOrAfter(item, current)) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        pub fn firstStored(items: []const Item, context: anytype, comptime matches: anytype) ?Item {
            for (items) |item| {
                if (matches(item, context)) return item;
            }
            return null;
        }

        pub fn latestStored(items: []const Item, context: anytype, comptime matches: anytype) ?Item {
            var result: ?Item = null;
            for (items) |item| {
                if (matches(item, context)) result = item;
            }
            return result;
        }

        pub fn nextStored(items: []const Item, next_index: *usize, context: anytype, comptime matches: anytype) ?Item {
            while (next_index.* < items.len) {
                const item = items[next_index.*];
                next_index.* += 1;
                if (matches(item, context)) return item;
            }
            return null;
        }

        pub fn count(items: []const Item, context: anytype, comptime matches: anytype) usize {
            var result: usize = 0;
            for (items) |item| {
                if (matches(item, context)) result += 1;
            }
            return result;
        }

        pub fn has(items: []const Item, context: anytype, comptime matches: anytype) bool {
            for (items) |item| {
                if (matches(item, context)) return true;
            }
            return false;
        }

        pub fn only(items: []const Item, context: anytype, comptime matches: anytype) bool {
            if (items.len == 0) return false;
            for (items) |item| {
                if (!matches(item, context)) return false;
            }
            return true;
        }

        pub fn nextIndexed(items: []const Item, last_offset: ?usize, last_index: usize, context: anytype, comptime matches: anytype) ?Indexed {
            var result: ?Indexed = null;
            for (items, 0..) |item, index| {
                if (!matches(item, context)) continue;
                if (!afterCursor(item, index, last_offset, last_index)) continue;
                const candidate = Indexed{ .item = item, .index = index };
                if (result) |current| {
                    if (indexedBefore(candidate, current)) result = candidate;
                } else {
                    result = candidate;
                }
            }
            return result;
        }

        pub fn nextOffset(items: []const Item, after_sample_offset: usize, context: anytype, comptime matches: anytype) ?usize {
            var result: ?usize = null;
            for (items) |item| {
                if (!matches(item, context)) continue;
                if (!afterOffset(item, after_sample_offset)) continue;
                if (result) |current| {
                    if (beforeOffset(item, current)) result = item.sample_offset;
                } else {
                    result = item.sample_offset;
                }
            }
            return result;
        }
    };
}

test "sample-offset ordering handles stored-order ties" {
    const std = @import("std");
    const Indexed = struct {
        item: struct { sample_offset: usize },
        index: usize,
    };
    const Range = struct { start_offset: usize, end_offset: usize };

    try std.testing.expect(before(.{ .sample_offset = 1 }, .{ .sample_offset = 2 }));
    try std.testing.expect(!before(.{ .sample_offset = 2 }, .{ .sample_offset = 2 }));
    try std.testing.expect(atOrAfter(.{ .sample_offset = 2 }, .{ .sample_offset = 2 }));
    try std.testing.expect(afterOffset(.{ .sample_offset = 3 }, 2));
    try std.testing.expect(beforeOffset(.{ .sample_offset = 1 }, 2));
    try std.testing.expect(atOrBeforeOffset(.{ .sample_offset = 2 }, 2));
    try std.testing.expect(!atOrBeforeOffset(.{ .sample_offset = 3 }, 2));
    try std.testing.expectEqual(@as(usize, 3), frameSpan(Range{ .start_offset = 2, .end_offset = 5 }));
    try std.testing.expectEqual(@as(usize, 0), frameSpan(Range{ .start_offset = 5, .end_offset = 2 }));
    try std.testing.expect(withinRange(Range{ .start_offset = 2, .end_offset = 5 }, 2));
    try std.testing.expect(!withinRange(Range{ .start_offset = 2, .end_offset = 5 }, 5));
    try std.testing.expect(!withinRange(Range{ .start_offset = 2, .end_offset = 5 }, 1));
    try std.testing.expect(indexedBefore(
        Indexed{ .item = .{ .sample_offset = 4 }, .index = 2 },
        Indexed{ .item = .{ .sample_offset = 4 }, .index = 3 },
    ));
    try std.testing.expect(afterCursor(.{ .sample_offset = 4 }, 3, 4, 2));
    try std.testing.expect(!afterCursor(.{ .sample_offset = 4 }, 2, 4, 2));
    try std.testing.expect(!afterCursor(.{ .sample_offset = 3 }, 3, 4, 2));
    try std.testing.expectEqual(@as(usize, 2), earliestOffset(2, 5, 9));
    try std.testing.expectEqual(@as(usize, 2), earliestOffset(5, 2, 9));
    try std.testing.expectEqual(@as(usize, 5), earliestOffset(5, null, 9));
    try std.testing.expectEqual(@as(usize, 5), earliestOffset(null, 5, 9));
    try std.testing.expectEqual(@as(usize, 9), earliestOffset(null, null, 9));
}
