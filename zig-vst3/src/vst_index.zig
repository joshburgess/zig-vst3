const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");

pub fn bounded(index: types.int32, count: usize) ?usize {
    if (index < 0) return null;
    const value: usize = @intCast(index);
    return if (value < count) value else null;
}

pub fn appendIndex(count: types.int32, capacity: usize) ?usize {
    if (count < 0) return null;
    const value: usize = @intCast(count);
    return if (value < capacity) value else null;
}

pub fn appendIndexU32(count: types.uint32, capacity: usize) ?usize {
    const value: usize = @intCast(count);
    return if (value < capacity) value else null;
}

pub fn clampedCount(count: types.int32, capacity: usize) usize {
    if (count <= 0) return 0;
    return @min(@as(usize, @intCast(count)), capacity);
}

pub fn clampedCountU32(count: types.uint32, capacity: usize) usize {
    return @min(@as(usize, @intCast(count)), capacity);
}

pub fn nonNegativeCount(count: types.int32) ?usize {
    if (count < 0) return null;
    return @intCast(count);
}

pub fn nonNegativeU32Count(count: types.int32) ?types.uint32 {
    if (count < 0) return null;
    return @intCast(count);
}

pub fn int32Count(count: usize) types.int32 {
    std.debug.assert(count <= std.math.maxInt(types.int32));
    return @intCast(count);
}

pub fn int32NextCount(index: usize) types.int32 {
    return int32Count(index + 1);
}

pub fn uint32Count(count: usize) types.uint32 {
    std.debug.assert(count <= std.math.maxInt(types.uint32));
    return @intCast(count);
}

pub fn uint32NextCount(index: usize) types.uint32 {
    return uint32Count(index + 1);
}

pub fn requireInt32Capacity(comptime capacity: usize, comptime name: []const u8) void {
    if (capacity > std.math.maxInt(types.int32)) {
        @compileError(name ++ " must fit in VST int32 counts");
    }
}

pub fn requireUint32Capacity(comptime capacity: usize, comptime name: []const u8) void {
    if (capacity > std.math.maxInt(types.uint32)) {
        @compileError(name ++ " must fit in VST uint32 counts");
    }
}

pub fn requireInt32Length(comptime len: usize, comptime name: []const u8) void {
    if (len > std.math.maxInt(types.int32)) {
        @compileError(name ++ " must fit in VST int32 length fields");
    }
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

test "appendIndex accepts only writable host count indexes" {
    try std.testing.expectEqual(@as(?usize, 0), appendIndex(0, 2));
    try std.testing.expectEqual(@as(?usize, 1), appendIndex(1, 2));
    try std.testing.expectEqual(@as(?usize, null), appendIndex(-1, 2));
    try std.testing.expectEqual(@as(?usize, null), appendIndex(2, 2));
    try std.testing.expectEqual(@as(?usize, null), appendIndex(0, 0));
}

test "appendIndexU32 accepts only writable unsigned count indexes" {
    try std.testing.expectEqual(@as(?usize, 0), appendIndexU32(0, 2));
    try std.testing.expectEqual(@as(?usize, 1), appendIndexU32(1, 2));
    try std.testing.expectEqual(@as(?usize, null), appendIndexU32(2, 2));
    try std.testing.expectEqual(@as(?usize, null), appendIndexU32(0, 0));
}

test "clampedCount converts host counts to storage bounds" {
    try std.testing.expectEqual(@as(usize, 0), clampedCount(-1, 3));
    try std.testing.expectEqual(@as(usize, 0), clampedCount(0, 3));
    try std.testing.expectEqual(@as(usize, 2), clampedCount(2, 3));
    try std.testing.expectEqual(@as(usize, 3), clampedCount(4, 3));
}

test "clampedCountU32 converts host counts to storage bounds" {
    try std.testing.expectEqual(@as(usize, 0), clampedCountU32(0, 3));
    try std.testing.expectEqual(@as(usize, 2), clampedCountU32(2, 3));
    try std.testing.expectEqual(@as(usize, 3), clampedCountU32(4, 3));
}

test "nonNegativeCount converts signed host counts" {
    try std.testing.expectEqual(@as(?usize, null), nonNegativeCount(-1));
    try std.testing.expectEqual(@as(?usize, 0), nonNegativeCount(0));
    try std.testing.expectEqual(@as(?usize, 7), nonNegativeCount(7));
}

test "nonNegativeU32Count converts signed host counts to unsigned VST fields" {
    try std.testing.expectEqual(@as(?types.uint32, null), nonNegativeU32Count(-1));
    try std.testing.expectEqual(@as(?types.uint32, 0), nonNegativeU32Count(0));
    try std.testing.expectEqual(@as(?types.uint32, 7), nonNegativeU32Count(7));
}

test "int32 count conversions keep the VST boundary explicit" {
    try std.testing.expectEqual(@as(types.int32, 0), int32Count(0));
    try std.testing.expectEqual(@as(types.int32, 7), int32Count(7));
    try std.testing.expectEqual(@as(types.int32, 8), int32NextCount(7));
}

test "uint32 count conversions keep the VST boundary explicit" {
    try std.testing.expectEqual(@as(types.uint32, 0), uint32Count(0));
    try std.testing.expectEqual(@as(types.uint32, 7), uint32Count(7));
    try std.testing.expectEqual(@as(types.uint32, 8), uint32NextCount(7));
}

test "int32 index helpers share generated boundary policy" {
    const capacities = [_]usize{ 0, 1, 2, 7 };
    const values = [_]types.int32{ -2, -1, 0, 1, 2, 6, 7, std.math.maxInt(types.int32) };

    for (capacities) |capacity| {
        for (values) |value| {
            const expected_index: ?usize = if (value >= 0 and @as(usize, @intCast(value)) < capacity)
                @intCast(value)
            else
                null;
            try std.testing.expectEqual(expected_index, bounded(value, capacity));
            try std.testing.expectEqual(expected_index, appendIndex(value, capacity));

            const expected_count: usize = if (value <= 0)
                0
            else
                @min(@as(usize, @intCast(value)), capacity);
            try std.testing.expectEqual(expected_count, clampedCount(value, capacity));
        }
    }
}

test "uint32 index helpers share generated boundary policy" {
    const capacities = [_]usize{ 0, 1, 2, 7 };
    const values = [_]types.uint32{ 0, 1, 2, 6, 7, std.math.maxInt(types.uint32) };

    for (capacities) |capacity| {
        for (values) |value| {
            const expected_index: ?usize = if (@as(usize, @intCast(value)) < capacity)
                @intCast(value)
            else
                null;
            try std.testing.expectEqual(expected_index, appendIndexU32(value, capacity));

            const expected_count = @min(@as(usize, @intCast(value)), capacity);
            try std.testing.expectEqual(expected_count, clampedCountU32(value, capacity));
        }
    }
}
