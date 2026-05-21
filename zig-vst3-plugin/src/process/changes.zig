const std = @import("std");
const common = @import("../common.zig");

pub const ParameterChange = struct {
    id: u32,
    sample_offset: usize,
    normalized: f64,

    pub fn isForId(self: ParameterChange, wanted_id: u32) bool {
        return self.id == wanted_id;
    }

    pub fn isAtOffset(self: ParameterChange, wanted_offset: usize) bool {
        return self.sample_offset == wanted_offset;
    }

    pub fn isForIdAtOffset(self: ParameterChange, wanted_id: u32, wanted_offset: usize) bool {
        return self.isForId(wanted_id) and self.isAtOffset(wanted_offset);
    }

    pub fn validate(self: ParameterChange, frame_count: usize) !void {
        if (self.sample_offset >= frame_count) return error.ParameterChangeOutsideBlock;
        if (!common.isNormalized(self.normalized)) return error.ParameterChangeOutsideNormalizedRange;
    }
};

const IndexedParameterChange = struct {
    item: ParameterChange,
    index: usize,
};

fn changeBefore(candidate: ParameterChange, current: ParameterChange) bool {
    return candidate.sample_offset < current.sample_offset;
}

fn changeAtOrAfter(candidate: ParameterChange, current: ParameterChange) bool {
    return candidate.sample_offset >= current.sample_offset;
}

fn changeAtOrBeforeOffset(candidate: ParameterChange, sample_offset: usize) bool {
    return candidate.sample_offset <= sample_offset;
}

fn changeAfterOffset(candidate: ParameterChange, sample_offset: usize) bool {
    return candidate.sample_offset > sample_offset;
}

fn changeOffsetBefore(candidate: ParameterChange, current_offset: usize) bool {
    return candidate.sample_offset < current_offset;
}

fn indexedChangeBefore(candidate: IndexedParameterChange, current: IndexedParameterChange) bool {
    return changeBefore(candidate.item, current.item) or
        (candidate.item.sample_offset == current.item.sample_offset and candidate.index < current.index);
}

fn indexedChangeAfterCursor(item: ParameterChange, index: usize, last_offset: ?usize, last_index: usize) bool {
    const offset = last_offset orelse return true;
    if (item.sample_offset < offset) return false;
    if (item.sample_offset == offset and index <= last_index) return false;
    return true;
}

const IdOffset = struct {
    id: u32,
    sample_offset: usize,
};

fn matchesAny(_: ParameterChange, _: void) bool {
    return true;
}

fn matchesId(item: ParameterChange, id: u32) bool {
    return item.isForId(id);
}

fn matchesOffset(item: ParameterChange, sample_offset: usize) bool {
    return item.isAtOffset(sample_offset);
}

fn matchesIdOffset(item: ParameterChange, context: IdOffset) bool {
    return item.isForIdAtOffset(context.id, context.sample_offset);
}

fn firstMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) ?ParameterChange {
    var result: ?ParameterChange = null;
    for (items) |item| {
        if (!matches(item, context)) continue;
        if (result) |current| {
            if (changeBefore(item, current)) result = item;
        } else {
            result = item;
        }
    }
    return result;
}

fn latestMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) ?ParameterChange {
    var result: ?ParameterChange = null;
    for (items) |item| {
        if (!matches(item, context)) continue;
        if (result) |current| {
            if (changeAtOrAfter(item, current)) result = item;
        } else {
            result = item;
        }
    }
    return result;
}

fn firstStoredMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) ?ParameterChange {
    for (items) |item| {
        if (matches(item, context)) return item;
    }
    return null;
}

fn latestStoredMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) ?ParameterChange {
    var result: ?ParameterChange = null;
    for (items) |item| {
        if (matches(item, context)) result = item;
    }
    return result;
}

fn nextStoredMatchingChange(items: []const ParameterChange, next_index: *usize, context: anytype, comptime matches: anytype) ?ParameterChange {
    while (next_index.* < items.len) {
        const item = items[next_index.*];
        next_index.* += 1;
        if (matches(item, context)) return item;
    }
    return null;
}

fn countMatchingChanges(items: []const ParameterChange, context: anytype, comptime matches: anytype) usize {
    var result: usize = 0;
    for (items) |item| {
        if (matches(item, context)) result +|= 1;
    }
    return result;
}

fn hasMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) bool {
    for (items) |item| {
        if (matches(item, context)) return true;
    }
    return false;
}

fn onlyMatchingChange(items: []const ParameterChange, context: anytype, comptime matches: anytype) bool {
    if (items.len == 0) return false;
    for (items) |item| {
        if (!matches(item, context)) return false;
    }
    return true;
}

fn nextMatchingChange(items: []const ParameterChange, last_offset: ?usize, last_index: usize, context: anytype, comptime matches: anytype) ?IndexedParameterChange {
    var result: ?IndexedParameterChange = null;
    for (items, 0..) |item, index| {
        if (!matches(item, context)) continue;
        if (!indexedChangeAfterCursor(item, index, last_offset, last_index)) continue;
        const candidate = IndexedParameterChange{ .item = item, .index = index };
        if (result) |current| {
            if (indexedChangeBefore(candidate, current)) result = candidate;
        } else {
            result = candidate;
        }
    }
    return result;
}

fn nextMatchingSampleOffset(items: []const ParameterChange, after_sample_offset: usize, context: anytype, comptime matches: anytype) ?usize {
    var result: ?usize = null;
    for (items) |item| {
        if (!matches(item, context)) continue;
        if (!changeAfterOffset(item, after_sample_offset)) continue;
        if (result) |current| {
            if (changeOffsetBefore(item, current)) result = item.sample_offset;
        } else {
            result = item.sample_offset;
        }
    }
    return result;
}

pub const ParameterSegment = struct {
    start_offset: usize,
    end_offset: usize,
    normalized: f64,

    pub fn frameCount(self: ParameterSegment) usize {
        return self.end_offset -| self.start_offset;
    }

    pub fn isEmpty(self: ParameterSegment) bool {
        return self.frameCount() == 0;
    }

    pub fn contains(self: ParameterSegment, sample_offset: usize) bool {
        return sample_offset >= self.start_offset and sample_offset < self.end_offset;
    }

    pub fn startsAt(self: ParameterSegment, sample_offset: usize) bool {
        return self.start_offset == sample_offset;
    }

    pub fn endsAt(self: ParameterSegment, sample_offset: usize) bool {
        return self.end_offset == sample_offset;
    }
};

pub const BlockSegment = struct {
    start_offset: usize,
    end_offset: usize,

    pub fn frameCount(self: BlockSegment) usize {
        return self.end_offset -| self.start_offset;
    }

    pub fn isEmpty(self: BlockSegment) bool {
        return self.frameCount() == 0;
    }

    pub fn contains(self: BlockSegment, sample_offset: usize) bool {
        return sample_offset >= self.start_offset and sample_offset < self.end_offset;
    }

    pub fn startsAt(self: BlockSegment, sample_offset: usize) bool {
        return self.start_offset == sample_offset;
    }

    pub fn endsAt(self: BlockSegment, sample_offset: usize) bool {
        return self.end_offset == sample_offset;
    }
};

pub const BlockSegmentIterator = struct {
    changes: ParameterChanges,
    frame_count: usize,
    next_start: usize = 0,

    pub fn next(self: *BlockSegmentIterator) ?BlockSegment {
        if (self.next_start >= self.frame_count) return null;
        const start = self.next_start;
        const end = self.changes.nextSampleOffset(start) orelse self.frame_count;
        self.next_start = @min(end, self.frame_count);
        return .{ .start_offset = start, .end_offset = self.next_start };
    }
};

pub const ParameterSegmentIterator = struct {
    changes: ParameterChanges,
    id: u32,
    frame_count: usize,
    default: f64,
    next_start: usize = 0,

    pub fn next(self: *ParameterSegmentIterator) ?ParameterSegment {
        const segment = self.changes.segmentAt(self.id, self.next_start, self.frame_count, self.default) orelse return null;
        self.next_start = segment.end_offset;
        return segment;
    }
};

pub const ParameterChangeIdIterator = struct {
    changes: ParameterChanges,
    id: u32,
    last_offset: ?usize = null,
    last_index: usize = 0,

    pub fn next(self: *ParameterChangeIdIterator) ?ParameterChange {
        if (nextMatchingChange(self.changes.items, self.last_offset, self.last_index, self.id, matchesId)) |result| {
            self.last_offset = result.item.sample_offset;
            self.last_index = result.index;
            return result.item;
        }
        return null;
    }
};

pub const ParameterChangeOffsetIterator = struct {
    changes: ParameterChanges,
    sample_offset: usize,
    next_index: usize = 0,

    pub fn next(self: *ParameterChangeOffsetIterator) ?ParameterChange {
        return nextStoredMatchingChange(self.changes.items, &self.next_index, self.sample_offset, matchesOffset);
    }
};

pub const ParameterChangeIdOffsetIterator = struct {
    changes: ParameterChanges,
    id: u32,
    sample_offset: usize,
    next_index: usize = 0,

    pub fn next(self: *ParameterChangeIdOffsetIterator) ?ParameterChange {
        const context = IdOffset{ .id = self.id, .sample_offset = self.sample_offset };
        return nextStoredMatchingChange(self.changes.items, &self.next_index, context, matchesIdOffset);
    }
};

pub const ParameterChanges = struct {
    items: []const ParameterChange = &.{},

    pub fn init(items: []const ParameterChange, frame_count: usize) !ParameterChanges {
        for (items) |item| {
            try item.validate(frame_count);
        }
        return .{ .items = items };
    }

    pub fn changeCount(self: ParameterChanges) usize {
        return self.items.len;
    }

    pub fn isEmpty(self: ParameterChanges) bool {
        return self.items.len == 0;
    }

    pub fn hasChanges(self: ParameterChanges) bool {
        return self.items.len != 0;
    }

    pub fn firstSampleOffset(self: ParameterChanges) ?usize {
        const change = self.firstChange() orelse return null;
        return change.sample_offset;
    }

    pub fn latestSampleOffset(self: ParameterChanges) ?usize {
        const change = latestMatchingChange(self.items, {}, matchesAny) orelse return null;
        return change.sample_offset;
    }

    pub fn firstChange(self: ParameterChanges) ?ParameterChange {
        return firstMatchingChange(self.items, {}, matchesAny);
    }

    pub fn latestChange(self: ParameterChanges) ?ParameterChange {
        return latestMatchingChange(self.items, {}, matchesAny);
    }

    pub fn firstSampleOffsetForId(self: ParameterChanges, id: u32) ?usize {
        const change = self.first(id) orelse return null;
        return change.sample_offset;
    }

    pub fn latestSampleOffsetForId(self: ParameterChanges, id: u32) ?usize {
        const change = self.latest(id) orelse return null;
        return change.sample_offset;
    }

    pub fn latest(self: ParameterChanges, id: u32) ?ParameterChange {
        return latestMatchingChange(self.items, id, matchesId);
    }

    pub fn first(self: ParameterChanges, id: u32) ?ParameterChange {
        return firstMatchingChange(self.items, id, matchesId);
    }

    pub fn firstAtOffset(self: ParameterChanges, sample_offset: usize) ?ParameterChange {
        return firstStoredMatchingChange(self.items, sample_offset, matchesOffset);
    }

    pub fn latestAtOffset(self: ParameterChanges, sample_offset: usize) ?ParameterChange {
        return latestStoredMatchingChange(self.items, sample_offset, matchesOffset);
    }

    pub fn firstForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        const context = IdOffset{ .id = id, .sample_offset = sample_offset };
        return firstStoredMatchingChange(self.items, context, matchesIdOffset);
    }

    pub fn latestForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        const context = IdOffset{ .id = id, .sample_offset = sample_offset };
        return latestStoredMatchingChange(self.items, context, matchesIdOffset);
    }

    pub fn count(self: ParameterChanges, id: u32) usize {
        return countMatchingChanges(self.items, id, matchesId);
    }

    pub fn countAtOffset(self: ParameterChanges, sample_offset: usize) usize {
        return countMatchingChanges(self.items, sample_offset, matchesOffset);
    }

    pub fn countForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) usize {
        const context = IdOffset{ .id = id, .sample_offset = sample_offset };
        return countMatchingChanges(self.items, context, matchesIdOffset);
    }

    pub fn has(self: ParameterChanges, id: u32) bool {
        return hasMatchingChange(self.items, id, matchesId);
    }

    pub fn hasAtOffset(self: ParameterChanges, sample_offset: usize) bool {
        return hasMatchingChange(self.items, sample_offset, matchesOffset);
    }

    pub fn hasForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) bool {
        const context = IdOffset{ .id = id, .sample_offset = sample_offset };
        return hasMatchingChange(self.items, context, matchesIdOffset);
    }

    pub fn empty(self: ParameterChanges, id: u32) bool {
        return !self.has(id);
    }

    pub fn offsetEmpty(self: ParameterChanges, sample_offset: usize) bool {
        return !self.hasAtOffset(sample_offset);
    }

    pub fn idAtOffsetEmpty(self: ParameterChanges, id: u32, sample_offset: usize) bool {
        return !self.hasForIdAtOffset(id, sample_offset);
    }

    pub fn only(self: ParameterChanges, id: u32) bool {
        return onlyMatchingChange(self.items, id, matchesId);
    }

    pub fn onlyAtOffset(self: ParameterChanges, sample_offset: usize) bool {
        return onlyMatchingChange(self.items, sample_offset, matchesOffset);
    }

    pub fn onlyForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) bool {
        const context = IdOffset{ .id = id, .sample_offset = sample_offset };
        return onlyMatchingChange(self.items, context, matchesIdOffset);
    }

    pub fn latestNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.latest(id) orelse return null;
        return change.normalized;
    }

    pub fn firstAnyNormalized(self: ParameterChanges) ?f64 {
        const change = self.firstChange() orelse return null;
        return change.normalized;
    }

    pub fn latestAnyNormalized(self: ParameterChanges) ?f64 {
        const change = self.latestChange() orelse return null;
        return change.normalized;
    }

    pub fn firstAnyNormalizedOr(self: ParameterChanges, default: f64) f64 {
        return self.firstAnyNormalized() orelse common.clampNormalized(default);
    }

    pub fn latestAnyNormalizedOr(self: ParameterChanges, default: f64) f64 {
        return self.latestAnyNormalized() orelse common.clampNormalized(default);
    }

    pub fn firstNormalized(self: ParameterChanges, id: u32) ?f64 {
        const change = self.first(id) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedAtOffset(self: ParameterChanges, sample_offset: usize) ?f64 {
        const change = self.firstAtOffset(sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn latestNormalizedAtOffset(self: ParameterChanges, sample_offset: usize) ?f64 {
        const change = self.latestAtOffset(sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedAtOffsetOr(self: ParameterChanges, sample_offset: usize, default: f64) f64 {
        return self.firstNormalizedAtOffset(sample_offset) orelse common.clampNormalized(default);
    }

    pub fn latestNormalizedAtOffsetOr(self: ParameterChanges, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedAtOffset(sample_offset) orelse common.clampNormalized(default);
    }

    pub fn firstNormalizedForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.firstForIdAtOffset(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn latestNormalizedForIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.latestForIdAtOffset(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn firstNormalizedForIdAtOffsetOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.firstNormalizedForIdAtOffset(id, sample_offset) orelse common.clampNormalized(default);
    }

    pub fn latestNormalizedForIdAtOffsetOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedForIdAtOffset(id, sample_offset) orelse common.clampNormalized(default);
    }

    pub fn latestNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.latestNormalized(id) orelse common.clampNormalized(default);
    }

    pub fn firstNormalizedOr(self: ParameterChanges, id: u32, default: f64) f64 {
        return self.firstNormalized(id) orelse common.clampNormalized(default);
    }

    pub fn latestAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?ParameterChange {
        var result: ?ParameterChange = null;
        for (self.items) |item| {
            if (!item.isForId(id)) continue;
            if (!changeAtOrBeforeOffset(item, sample_offset)) continue;
            if (result) |current| {
                if (changeAtOrAfter(item, current)) result = item;
            } else {
                result = item;
            }
        }
        return result;
    }

    pub fn latestNormalizedAtOrBefore(self: ParameterChanges, id: u32, sample_offset: usize) ?f64 {
        const change = self.latestAtOrBefore(id, sample_offset) orelse return null;
        return change.normalized;
    }

    pub fn normalizedAtOrBeforeOr(self: ParameterChanges, id: u32, sample_offset: usize, default: f64) f64 {
        return self.latestNormalizedAtOrBefore(id, sample_offset) orelse common.clampNormalized(default);
    }

    pub fn nextSampleOffset(self: ParameterChanges, after_sample_offset: usize) ?usize {
        return nextMatchingSampleOffset(self.items, after_sample_offset, {}, matchesAny);
    }

    pub fn nextSampleOffsetForId(self: ParameterChanges, id: u32, after_sample_offset: usize) ?usize {
        return nextMatchingSampleOffset(self.items, after_sample_offset, id, matchesId);
    }

    pub fn segmentAt(self: ParameterChanges, id: u32, start_offset: usize, frame_count: usize, default: f64) ?ParameterSegment {
        if (start_offset >= frame_count) return null;
        const next_offset = self.nextSampleOffsetForId(id, start_offset) orelse frame_count;
        return .{
            .start_offset = start_offset,
            .end_offset = @min(next_offset, frame_count),
            .normalized = self.normalizedAtOrBeforeOr(id, start_offset, default),
        };
    }

    pub fn segments(self: ParameterChanges, id: u32, frame_count: usize, default: f64) ParameterSegmentIterator {
        return .{
            .changes = self,
            .id = id,
            .frame_count = frame_count,
            .default = default,
        };
    }

    pub fn blockSegments(self: ParameterChanges, frame_count: usize) BlockSegmentIterator {
        return .{
            .changes = self,
            .frame_count = frame_count,
        };
    }

    pub fn forId(self: ParameterChanges, id: u32) ParameterChangeIdIterator {
        return .{
            .changes = self,
            .id = id,
        };
    }

    pub fn atOffset(self: ParameterChanges, sample_offset: usize) ParameterChangeOffsetIterator {
        return .{
            .changes = self,
            .sample_offset = sample_offset,
        };
    }

    pub fn forIdAtOffset(self: ParameterChanges, id: u32, sample_offset: usize) ParameterChangeIdOffsetIterator {
        return .{
            .changes = self,
            .id = id,
            .sample_offset = sample_offset,
        };
    }
};
test "parameter changes validate block offsets and normalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(usize, 3), view.changeCount());
    try std.testing.expect(!view.isEmpty());
    try std.testing.expect(changes[0].isForId(7));
    try std.testing.expect(!changes[0].isForId(8));
    try std.testing.expect(changes[0].isAtOffset(0));
    try std.testing.expect(!changes[0].isAtOffset(1));
    try std.testing.expect(changes[0].isForIdAtOffset(7, 0));
    try std.testing.expect(!changes[0].isForIdAtOffset(7, 1));
    try std.testing.expect(!changes[0].isForIdAtOffset(8, 0));
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffset());
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffset());
    try std.testing.expectEqual(changes[0], view.firstChange().?);
    try std.testing.expectEqual(changes[1], view.latestChange().?);
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstAnyNormalized());
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestAnyNormalized());
    try std.testing.expectEqual(@as(?usize, 0), view.firstSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, 3), view.latestSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, 2), view.firstSampleOffsetForId(8));
    try std.testing.expectEqual(@as(?usize, 2), view.latestSampleOffsetForId(8));
    try std.testing.expectEqual(@as(?usize, null), view.firstSampleOffsetForId(9));
    try std.testing.expectEqual(@as(?usize, null), view.latestSampleOffsetForId(9));
    try std.testing.expect(view.has(7));
    try std.testing.expect(!view.has(9));
    try std.testing.expect(!view.empty(7));
    try std.testing.expect(view.empty(9));
    try std.testing.expectEqual(@as(usize, 2), view.count(7));
    try std.testing.expectEqual(@as(usize, 1), view.count(8));
    try std.testing.expectEqual(@as(usize, 0), view.count(9));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(0));
    try std.testing.expectEqual(@as(usize, 1), view.countAtOffset(2));
    try std.testing.expectEqual(@as(usize, 0), view.countAtOffset(1));
    try std.testing.expectEqual(@as(usize, 1), view.countForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(usize, 0), view.countForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstAtOffset(0).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestAtOffset(2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.firstForIdAtOffset(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestForIdAtOffset(7, 0).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstAtOffset(1));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOffset(1));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestForIdAtOffset(7, 2));
    try std.testing.expect(view.hasAtOffset(0));
    try std.testing.expect(!view.hasAtOffset(1));
    try std.testing.expect(view.hasForIdAtOffset(7, 0));
    try std.testing.expect(!view.hasForIdAtOffset(8, 0));
    try std.testing.expect(!view.offsetEmpty(0));
    try std.testing.expect(view.offsetEmpty(1));
    try std.testing.expect(!view.idAtOffsetEmpty(7, 0));
    try std.testing.expect(view.idAtOffsetEmpty(8, 0));
    try std.testing.expect(!view.only(7));
    try std.testing.expect(!view.onlyAtOffset(0));
    try std.testing.expect(!view.onlyForIdAtOffset(7, 0));
    const gain_only_changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 3, .normalized = 0.75 },
    };
    const gain_only = try ParameterChanges.init(&gain_only_changes, 4);
    try std.testing.expect(gain_only.only(7));
    try std.testing.expect(!gain_only.only(8));
    try std.testing.expect(!gain_only.onlyAtOffset(0));
    try std.testing.expect(!gain_only.onlyForIdAtOffset(7, 0));
    const same_offset_changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 2, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 2, .normalized = 0.75 },
    };
    const same_offset = try ParameterChanges.init(&same_offset_changes, 4);
    try std.testing.expect(same_offset.only(7));
    try std.testing.expect(same_offset.onlyAtOffset(2));
    try std.testing.expect(!same_offset.onlyAtOffset(3));
    try std.testing.expect(same_offset.onlyForIdAtOffset(7, 2));
    try std.testing.expect(!same_offset.onlyForIdAtOffset(8, 2));
    try std.testing.expectEqual(@as(f64, 0.25), same_offset.first(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), same_offset.latest(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), same_offset.firstAtOffset(2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), same_offset.latestAtOffset(2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(f64, 0.75), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalized(7));
    try std.testing.expectEqual(@as(f64, 0.75), view.latestNormalizedOr(7, 0.0));
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedAtOffset(2));
    try std.testing.expectEqual(@as(?f64, 0.25), view.firstNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOffset(1));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalizedForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedForIdAtOffset(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedAtOffsetOr(0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedAtOffsetOr(1, 0.5));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedAtOffsetOr(2, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedAtOffsetOr(1, 0.5));
    try std.testing.expectEqual(@as(f64, 0.25), view.firstNormalizedForIdAtOffsetOr(7, 0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedForIdAtOffsetOr(7, 2, 0.5));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestNormalizedForIdAtOffsetOr(7, 0, 0.0));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedForIdAtOffsetOr(7, 2, 0.5));
    try std.testing.expectEqual(@as(?f64, null), view.firstNormalized(9));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalized(9));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestNormalizedOr(9, 0.5));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latest(9));
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.25), view.latestAtOrBefore(7, 2).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.latestAtOrBefore(7, 3).?.normalized);
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 2));
    try std.testing.expectEqual(@as(f64, 0.25), view.normalizedAtOrBeforeOr(7, 2, 0.0));
    try std.testing.expectEqual(@as(?f64, 0.75), view.latestNormalizedAtOrBefore(7, 3));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(?f64, null), view.latestNormalizedAtOrBefore(8, 1));
    try std.testing.expectEqual(@as(f64, 0.5), view.normalizedAtOrBeforeOr(8, 1, 0.5));
    try std.testing.expectEqual(@as(?usize, 2), view.nextSampleOffset(0));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffset(2));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffset(3));
    try std.testing.expectEqual(@as(?usize, 3), view.nextSampleOffsetForId(7, 0));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(7, 3));
    try std.testing.expectEqual(@as(?usize, null), view.nextSampleOffsetForId(9, 0));
    const first_segment = view.segmentAt(7, 0, 4, 1.0).?;
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 3, .normalized = 0.25 }, first_segment);
    try std.testing.expectEqual(@as(usize, 3), first_segment.frameCount());
    try std.testing.expect(!first_segment.isEmpty());
    try std.testing.expect(first_segment.contains(2));
    try std.testing.expect(!first_segment.contains(3));
    try std.testing.expect(first_segment.startsAt(0));
    try std.testing.expect(!first_segment.startsAt(1));
    try std.testing.expect(first_segment.endsAt(3));
    try std.testing.expect(!first_segment.endsAt(2));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 3, .end_offset = 4, .normalized = 0.75 }, view.segmentAt(7, 3, 4, 1.0).?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 2, .normalized = 0.5 }, view.segmentAt(8, 0, 4, 0.5).?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), view.segmentAt(7, 4, 4, 1.0));
    try std.testing.expect((ParameterSegment{ .start_offset = 2, .end_offset = 2, .normalized = 0.0 }).isEmpty());
    const reversed_parameter_segment = ParameterSegment{ .start_offset = 4, .end_offset = 2, .normalized = 0.0 };
    try std.testing.expectEqual(@as(usize, 0), reversed_parameter_segment.frameCount());
    try std.testing.expect(reversed_parameter_segment.isEmpty());
    try std.testing.expect(!reversed_parameter_segment.contains(3));
    try std.testing.expectEqual(@as(usize, 0), (ParameterChanges{}).changeCount());
    try std.testing.expect((ParameterChanges{}).isEmpty());
    try std.testing.expect(!(ParameterChanges{}).hasChanges());
    try std.testing.expect((ParameterChanges{}).empty(7));
    try std.testing.expect(!(ParameterChanges{}).only(7));
    try std.testing.expect(!(ParameterChanges{}).onlyAtOffset(0));
    try std.testing.expect(!(ParameterChanges{}).onlyForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffset());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstChange());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestChange());
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstAnyNormalized());
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestAnyNormalized());
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).firstSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffsetForId(7));
    try std.testing.expectEqual(@as(?usize, null), (ParameterChanges{}).latestSampleOffset());
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestAtOffset(0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).firstForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?ParameterChange, null), (ParameterChanges{}).latestForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestNormalizedAtOffset(0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).firstNormalizedForIdAtOffset(7, 0));
    try std.testing.expectEqual(@as(?f64, null), (ParameterChanges{}).latestNormalizedForIdAtOffset(7, 0));
}

test "parameter changes validate generated boundary cases" {
    const valid_offsets = [_]usize{ 0, 1, 3 };
    const valid_values = [_]f64{ 0.0, 0.25, 1.0 };
    for (valid_offsets) |sample_offset| {
        for (valid_values) |normalized| {
            const changes = [_]ParameterChange{
                .{
                    .id = std.math.maxInt(u32),
                    .sample_offset = sample_offset,
                    .normalized = normalized,
                },
            };
            const view = try ParameterChanges.init(&changes, 4);
            try std.testing.expectEqual(@as(usize, 1), view.changeCount());
            try std.testing.expectEqual(changes[0], view.firstChange().?);
        }
    }

    const invalid_offsets = [_]usize{ 4, 5, std.math.maxInt(usize) };
    for (invalid_offsets) |sample_offset| {
        const changes = [_]ParameterChange{
            .{ .id = 7, .sample_offset = sample_offset, .normalized = 0.5 },
        };
        try std.testing.expectError(error.ParameterChangeOutsideBlock, ParameterChanges.init(&changes, 4));
    }

    const invalid_values = [_]f64{
        -0.001,
        1.001,
        std.math.nan(f64),
        std.math.inf(f64),
        -std.math.inf(f64),
    };
    for (invalid_values) |normalized| {
        const changes = [_]ParameterChange{
            .{ .id = 7, .sample_offset = 0, .normalized = normalized },
        };
        try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&changes, 4));
    }
}

test "parameter changes query by sample offset without requiring sorted input" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);

    try std.testing.expectEqual(@as(f64, 0.25), view.first(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latest(7).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.firstAtOffset(5).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestAtOffset(5).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), view.firstForIdAtOffset(7, 5).?.normalized);
    try std.testing.expectEqual(@as(f64, 1.0), view.latestForIdAtOffset(7, 5).?.normalized);
    try std.testing.expectEqual(@as(?ParameterChange, null), view.firstForIdAtOffset(8, 5));
    try std.testing.expectEqual(@as(?ParameterChange, null), view.latestForIdAtOffset(8, 5));
    try std.testing.expectEqual(@as(?f64, 0.75), view.firstNormalizedForIdAtOffset(7, 5));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedForIdAtOffset(7, 5));
    try std.testing.expectEqual(@as(?f64, 0.25), view.latestNormalizedAtOrBefore(7, 4));
    try std.testing.expectEqual(@as(?f64, 1.0), view.latestNormalizedAtOrBefore(7, 5));
    try std.testing.expectEqual(@as(?usize, 5), view.nextSampleOffsetForId(7, 1));
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, view.segmentAt(7, 1, 8, 0.0).?);

    var id_changes = view.forId(7);
    try std.testing.expectEqual(changes[2], id_changes.next().?);
    try std.testing.expectEqual(changes[0], id_changes.next().?);
    try std.testing.expectEqual(changes[3], id_changes.next().?);
    try std.testing.expectEqual(@as(?ParameterChange, null), id_changes.next());

    var offset_changes = view.atOffset(5);
    try std.testing.expectEqual(changes[0], offset_changes.next().?);
    try std.testing.expectEqual(changes[3], offset_changes.next().?);
    try std.testing.expectEqual(@as(?ParameterChange, null), offset_changes.next());

    var id_offset_changes = view.forIdAtOffset(7, 5);
    try std.testing.expectEqual(changes[0], id_offset_changes.next().?);
    try std.testing.expectEqual(changes[3], id_offset_changes.next().?);
    try std.testing.expectEqual(@as(?ParameterChange, null), id_offset_changes.next());

    var missing_changes = view.forId(99);
    try std.testing.expectEqual(@as(?ParameterChange, null), missing_changes.next());
}

test "parameter changes generated queries match reference scans" {
    const Reference = struct {
        fn itemMatchesId(item: ParameterChange, id: u32) bool {
            return item.id == id;
        }

        fn count(items: []const ParameterChange, id: u32) usize {
            var result: usize = 0;
            for (items) |item| {
                if (itemMatchesId(item, id)) result += 1;
            }
            return result;
        }

        fn has(items: []const ParameterChange, id: u32) bool {
            return count(items, id) != 0;
        }

        fn only(items: []const ParameterChange, id: u32) bool {
            return items.len != 0 and count(items, id) == items.len;
        }

        fn first(items: []const ParameterChange, id: u32) ?ParameterChange {
            var result: ?ParameterChange = null;
            for (items) |item| {
                if (!itemMatchesId(item, id)) continue;
                if (result) |current| {
                    if (item.sample_offset < current.sample_offset) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        fn latest(items: []const ParameterChange, id: u32) ?ParameterChange {
            var result: ?ParameterChange = null;
            for (items) |item| {
                if (!itemMatchesId(item, id)) continue;
                if (result) |current| {
                    if (item.sample_offset >= current.sample_offset) result = item;
                } else {
                    result = item;
                }
            }
            return result;
        }

        fn nextAnyOffset(items: []const ParameterChange, after_sample_offset: usize) ?usize {
            var result: ?usize = null;
            for (items) |item| {
                if (item.sample_offset <= after_sample_offset) continue;
                if (result) |current| {
                    if (item.sample_offset < current) result = item.sample_offset;
                } else {
                    result = item.sample_offset;
                }
            }
            return result;
        }

        fn nextOffset(items: []const ParameterChange, id: u32, after_sample_offset: usize) ?usize {
            var result: ?usize = null;
            for (items) |item| {
                if (!itemMatchesId(item, id) or item.sample_offset <= after_sample_offset) continue;
                if (result) |current| {
                    if (item.sample_offset < current) result = item.sample_offset;
                } else {
                    result = item.sample_offset;
                }
            }
            return result;
        }

        fn countAtOffset(items: []const ParameterChange, sample_offset: usize) usize {
            var result: usize = 0;
            for (items) |item| {
                if (item.sample_offset == sample_offset) result += 1;
            }
            return result;
        }

        fn hasAtOffset(items: []const ParameterChange, sample_offset: usize) bool {
            return countAtOffset(items, sample_offset) != 0;
        }

        fn onlyAtOffset(items: []const ParameterChange, sample_offset: usize) bool {
            return items.len != 0 and countAtOffset(items, sample_offset) == items.len;
        }

        fn firstAtOffset(items: []const ParameterChange, sample_offset: usize) ?ParameterChange {
            for (items) |item| {
                if (item.sample_offset == sample_offset) return item;
            }
            return null;
        }

        fn countForIdAtOffset(items: []const ParameterChange, id: u32, sample_offset: usize) usize {
            var result: usize = 0;
            for (items) |item| {
                if (item.id == id and item.sample_offset == sample_offset) result += 1;
            }
            return result;
        }

        fn hasForIdAtOffset(items: []const ParameterChange, id: u32, sample_offset: usize) bool {
            return countForIdAtOffset(items, id, sample_offset) != 0;
        }

        fn onlyForIdAtOffset(items: []const ParameterChange, id: u32, sample_offset: usize) bool {
            return items.len != 0 and countForIdAtOffset(items, id, sample_offset) == items.len;
        }

        fn latestAtOffset(items: []const ParameterChange, sample_offset: usize) ?ParameterChange {
            var result: ?ParameterChange = null;
            for (items) |item| {
                if (item.sample_offset == sample_offset) result = item;
            }
            return result;
        }

        fn firstForIdAtOffset(items: []const ParameterChange, id: u32, sample_offset: usize) ?ParameterChange {
            for (items) |item| {
                if (item.id == id and item.sample_offset == sample_offset) return item;
            }
            return null;
        }

        fn latestForIdAtOffset(items: []const ParameterChange, id: u32, sample_offset: usize) ?ParameterChange {
            var result: ?ParameterChange = null;
            for (items) |item| {
                if (item.id == id and item.sample_offset == sample_offset) result = item;
            }
            return result;
        }
    };

    const ids = [_]u32{ 7, 8, 9 };
    const frame_count = 6;

    for (0..32) |seed| {
        var storage: [4]ParameterChange = undefined;
        for (&storage, 0..) |*item, index| {
            item.* = .{
                .id = ids[(seed + index * 2) % ids.len],
                .sample_offset = (seed * 3 + index * 2) % frame_count,
                .normalized = @as(f64, @floatFromInt((seed + index) % 5)) / 4.0,
            };
        }

        for (0..storage.len + 1) |len| {
            const items = storage[0..len];
            const view = try ParameterChanges.init(items, frame_count);

            for (ids) |id| {
                try std.testing.expectEqual(Reference.count(items, id), view.count(id));
                try std.testing.expectEqual(Reference.has(items, id), view.has(id));
                try std.testing.expectEqual(!Reference.has(items, id), view.empty(id));
                try std.testing.expectEqual(Reference.only(items, id), view.only(id));
                try std.testing.expectEqual(Reference.first(items, id), view.first(id));
                try std.testing.expectEqual(Reference.latest(items, id), view.latest(id));
                for (0..frame_count) |sample_offset| {
                    try std.testing.expectEqual(Reference.countForIdAtOffset(items, id, sample_offset), view.countForIdAtOffset(id, sample_offset));
                    try std.testing.expectEqual(Reference.hasForIdAtOffset(items, id, sample_offset), view.hasForIdAtOffset(id, sample_offset));
                    try std.testing.expectEqual(!Reference.hasForIdAtOffset(items, id, sample_offset), view.idAtOffsetEmpty(id, sample_offset));
                    try std.testing.expectEqual(Reference.onlyForIdAtOffset(items, id, sample_offset), view.onlyForIdAtOffset(id, sample_offset));
                    try std.testing.expectEqual(Reference.firstForIdAtOffset(items, id, sample_offset), view.firstForIdAtOffset(id, sample_offset));
                    try std.testing.expectEqual(Reference.latestForIdAtOffset(items, id, sample_offset), view.latestForIdAtOffset(id, sample_offset));
                    try std.testing.expectEqual(
                        Reference.nextAnyOffset(items, sample_offset),
                        view.nextSampleOffset(sample_offset),
                    );
                    try std.testing.expectEqual(
                        Reference.nextOffset(items, id, sample_offset),
                        view.nextSampleOffsetForId(id, sample_offset),
                    );
                }
            }

            for (0..frame_count) |sample_offset| {
                try std.testing.expectEqual(Reference.countAtOffset(items, sample_offset), view.countAtOffset(sample_offset));
                try std.testing.expectEqual(Reference.hasAtOffset(items, sample_offset), view.hasAtOffset(sample_offset));
                try std.testing.expectEqual(!Reference.hasAtOffset(items, sample_offset), view.offsetEmpty(sample_offset));
                try std.testing.expectEqual(Reference.onlyAtOffset(items, sample_offset), view.onlyAtOffset(sample_offset));
                try std.testing.expectEqual(Reference.firstAtOffset(items, sample_offset), view.firstAtOffset(sample_offset));
                try std.testing.expectEqual(Reference.latestAtOffset(items, sample_offset), view.latestAtOffset(sample_offset));
            }
        }
    }
}

test "parameter changes iterate stable automation segments without allocation" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 2, .normalized = 0.5 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.segments(7, 8, 0.0);

    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.0 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 5, .normalized = 0.25 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 5, .end_offset = 8, .normalized = 0.75 }, iterator.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), iterator.next());
}

test "parameter changes collapse same-offset values into one segment" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 7, .sample_offset = 1, .normalized = 0.75 },
        .{ .id = 7, .sample_offset = 4, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.segments(7, 8, 0.0);

    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 1, .normalized = 0.0 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 1, .end_offset = 4, .normalized = 0.75 }, iterator.next().?);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 4, .end_offset = 8, .normalized = 1.0 }, iterator.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), iterator.next());
}

test "parameter changes iterate block segments split at change offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 5, .normalized = 0.75 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 9, .sample_offset = 3, .normalized = 0.5 },
        .{ .id = 7, .sample_offset = 5, .normalized = 1.0 },
    };
    const view = try ParameterChanges.init(&changes, 8);
    var iterator = view.blockSegments(8);

    const first_segment = iterator.next().?;
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, first_segment);
    try std.testing.expectEqual(@as(usize, 1), first_segment.frameCount());
    try std.testing.expect(!first_segment.isEmpty());
    try std.testing.expect(first_segment.contains(0));
    try std.testing.expect(!first_segment.contains(1));
    try std.testing.expect(first_segment.startsAt(0));
    try std.testing.expect(!first_segment.startsAt(1));
    try std.testing.expect(first_segment.endsAt(1));
    try std.testing.expect(!first_segment.endsAt(0));
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 5, .end_offset = 8 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
    try std.testing.expect((BlockSegment{ .start_offset = 2, .end_offset = 2 }).isEmpty());
    const reversed_block_segment = BlockSegment{ .start_offset = 4, .end_offset = 2 };
    try std.testing.expectEqual(@as(usize, 0), reversed_block_segment.frameCount());
    try std.testing.expect(reversed_block_segment.isEmpty());
    try std.testing.expect(!reversed_block_segment.contains(3));

    var empty = (ParameterChanges{}).blockSegments(4);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 4 }, empty.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), empty.next());

    var zero = view.blockSegments(0);
    try std.testing.expectEqual(@as(?BlockSegment, null), zero.next());
}

test "parameter changes block segments ignore duplicate offsets" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 1, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.5 },
        .{ .id = 9, .sample_offset = 3, .normalized = 0.75 },
    };
    const view = try ParameterChanges.init(&changes, 5);
    var iterator = view.blockSegments(5);

    try std.testing.expectEqual(BlockSegment{ .start_offset = 0, .end_offset = 1 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 1, .end_offset = 3 }, iterator.next().?);
    try std.testing.expectEqual(BlockSegment{ .start_offset = 3, .end_offset = 5 }, iterator.next().?);
    try std.testing.expectEqual(@as(?BlockSegment, null), iterator.next());
}

test "parameter changes reject values outside the process block" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 4, .normalized = 0.25 },
    };

    try std.testing.expectError(error.ParameterChangeOutsideBlock, changes[0].validate(4));
    try std.testing.expectError(error.ParameterChangeOutsideBlock, ParameterChanges.init(&changes, 4));
}

test "parameter changes reject denormalized values" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 1.5 },
    };
    const infinite = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = std.math.inf(f64) },
    };

    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, changes[0].validate(4));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, infinite[0].validate(4));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&changes, 4));
    try std.testing.expectError(error.ParameterChangeOutsideNormalizedRange, ParameterChanges.init(&infinite, 4));
}

test "parameter changes clamp defaulted normalized reads" {
    const changes = [_]ParameterChange{
        .{ .id = 7, .sample_offset = 2, .normalized = 0.5 },
    };
    const empty = try ParameterChanges.init(&.{}, 4);
    const view = try ParameterChanges.init(&changes, 4);

    try std.testing.expectEqual(@as(f64, 0.0), empty.firstAnyNormalizedOr(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), empty.latestAnyNormalizedOr(1.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.firstAnyNormalizedOr(1.5));
    try std.testing.expectEqual(@as(f64, 0.5), view.latestAnyNormalizedOr(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), view.firstNormalizedOr(9, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.latestNormalizedOr(9, -0.25));
    try std.testing.expectEqual(@as(f64, 0.0), view.firstNormalizedAtOffsetOr(1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedAtOffsetOr(1, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.firstNormalizedForIdAtOffsetOr(7, 1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), view.latestNormalizedForIdAtOffsetOr(7, 1, 1.5));
    try std.testing.expectEqual(@as(f64, 0.0), view.normalizedAtOrBeforeOr(7, 1, std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.5), view.normalizedAtOrBeforeOr(7, 2, 1.5));

    var segments = view.segments(9, 4, 1.5);
    try std.testing.expectEqual(ParameterSegment{ .start_offset = 0, .end_offset = 4, .normalized = 1.0 }, segments.next().?);
    try std.testing.expectEqual(@as(?ParameterSegment, null), segments.next());
}
