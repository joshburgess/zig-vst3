const std = @import("std");

pub fn overlap(comptime Sample: type, first: anytype, second: anytype) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_bytes = std.math.mul(
        usize,
        first.len,
        @sizeOf(Sample),
    ) catch return true;
    const second_bytes = std.math.mul(
        usize,
        second.len,
        @sizeOf(Sample),
    ) catch return true;
    const first_end = std.math.add(
        usize,
        first_start,
        first_bytes,
    ) catch return true;
    const second_end = std.math.add(
        usize,
        second_start,
        second_bytes,
    ) catch return true;
    return first_start < second_end and second_start < first_end;
}

pub fn same(first: anytype, second: anytype) bool {
    return first.len == second.len and
        (first.len == 0 or @intFromPtr(first.ptr) == @intFromPtr(second.ptr));
}

pub fn exactOrDisjoint(
    comptime Sample: type,
    first: anytype,
    second: anytype,
) bool {
    return same(first, second) or !overlap(Sample, first, second);
}

test "buffer regions distinguish exact shifted and disjoint slices" {
    var samples: [8]f32 = @splat(0.0);
    try std.testing.expect(same(samples[0..4], samples[0..4]));
    try std.testing.expect(!same(samples[0..4], samples[1..5]));
    try std.testing.expect(overlap(f32, samples[0..4], samples[1..5]));
    try std.testing.expect(!overlap(f32, samples[0..4], samples[4..8]));
    try std.testing.expect(exactOrDisjoint(
        f32,
        samples[0..4],
        samples[0..4],
    ));
    try std.testing.expect(!exactOrDisjoint(
        f32,
        samples[0..4],
        samples[1..5],
    ));
}
