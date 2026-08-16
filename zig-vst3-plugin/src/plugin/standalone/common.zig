const std = @import("std");

pub fn nextQueueIndex(index: usize, slot_count: usize) usize {
    const next = index + 1;
    return if (next == slot_count) 0 else next;
}

pub fn advanceFifoIndex(
    index: usize,
    count: usize,
    slot_count: usize,
) usize {
    const until_end = slot_count - index;
    return if (count < until_end)
        index + count
    else
        count - until_end;
}

pub fn sampleSlicesOverlap(
    comptime Sample: type,
    left: anytype,
    right: anytype,
) !bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_bytes = std.math.mul(
        usize,
        left.len,
        @sizeOf(Sample),
    ) catch return error.InvalidCaptureBuffer;
    const right_bytes = std.math.mul(
        usize,
        right.len,
        @sizeOf(Sample),
    ) catch return error.InvalidCaptureBuffer;
    const left_end = std.math.add(
        usize,
        left_start,
        left_bytes,
    ) catch return error.InvalidCaptureBuffer;
    const right_end = std.math.add(
        usize,
        right_start,
        right_bytes,
    ) catch return error.InvalidCaptureBuffer;
    return left_start < right_end and right_start < left_end;
}

pub fn recordSaturating(value: *std.atomic.Value(usize)) void {
    recordSaturatingAmount(value, 1);
}

pub fn recordSaturatingAmount(
    value: *std.atomic.Value(usize),
    amount: usize,
) void {
    if (amount == 0) return;
    var current = value.load(.monotonic);
    while (current != std.math.maxInt(usize)) {
        const next = std.math.add(
            usize,
            current,
            amount,
        ) catch std.math.maxInt(usize);
        if (value.cmpxchgWeak(
            current,
            next,
            .monotonic,
            .monotonic,
        )) |observed| {
            current = observed;
        } else return;
    }
}
