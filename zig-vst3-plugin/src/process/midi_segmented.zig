const std = @import("std");

pub fn payloadEnd(
    source_len: usize,
    cursor: usize,
    maximum_payload_bytes: usize,
) usize {
    return @min(
        std.math.add(
            usize,
            cursor,
            maximum_payload_bytes,
        ) catch source_len,
        source_len,
    );
}

pub fn packetForm(
    comptime Form: type,
    source_len: usize,
    cursor: usize,
    end: usize,
    maximum_payload_bytes: usize,
) Form {
    if (source_len <= maximum_payload_bytes) return .complete;
    if (cursor == 0) return .begin;
    if (end == source_len) return .end;
    return .continuation;
}

pub fn packetizerStateValid(
    source_len: usize,
    cursor: usize,
    emitted_empty: bool,
) bool {
    return cursor <= source_len and
        (source_len == 0 or !emitted_empty);
}

pub fn reassemblyStateValid(
    count: usize,
    capacity: usize,
    active: bool,
    completed: bool,
    identity_present: bool,
    identity_empty: bool,
) bool {
    if (count > capacity) return false;
    if (active and (completed or !identity_present)) return false;
    if (completed and !identity_present) return false;
    if (!active and !completed and
        (count != 0 or !identity_empty))
        return false;
    return true;
}

pub fn replace(
    comptime Byte: type,
    storage: []Byte,
    count: *usize,
    source: []const Byte,
) bool {
    if (source.len > storage.len) return false;
    @memcpy(storage[0..source.len], source);
    @memset(storage[source.len..], 0);
    count.* = source.len;
    return true;
}

pub fn append(
    comptime Byte: type,
    storage: []Byte,
    count: *usize,
    source: []const Byte,
) bool {
    const new_count = std.math.add(
        usize,
        count.*,
        source.len,
    ) catch return false;
    if (new_count > storage.len) return false;
    @memcpy(storage[count.*..new_count], source);
    count.* = new_count;
    return true;
}

pub fn setCompletion(
    active: *bool,
    completed: *bool,
    completes: bool,
) bool {
    active.* = !completes;
    completed.* = completes;
    return completes;
}

test "segmented payload bounds contain addition overflow" {
    try std.testing.expectEqual(
        @as(usize, 12),
        payloadEnd(12, 10, 4),
    );
    try std.testing.expectEqual(
        @as(usize, 12),
        payloadEnd(12, std.math.maxInt(usize), 4),
    );
}

test "segmented packetizer phase rejects retained sentinel mismatches" {
    try std.testing.expect(packetizerStateValid(0, 0, false));
    try std.testing.expect(packetizerStateValid(0, 0, true));
    try std.testing.expect(packetizerStateValid(4, 4, false));
    try std.testing.expect(!packetizerStateValid(0, 1, false));
    try std.testing.expect(!packetizerStateValid(4, 5, false));
    try std.testing.expect(!packetizerStateValid(4, 0, true));
}

test "segmented storage updates are transactional" {
    var storage = [_]u8{ 1, 2, 3, 4 };
    var count: usize = 2;
    try std.testing.expect(!append(
        u8,
        &storage,
        &count,
        &.{ 5, 6, 7 },
    ));
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 3, 4 },
        &storage,
    );
    try std.testing.expect(append(
        u8,
        &storage,
        &count,
        &.{ 5, 6 },
    ));
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 2, 5, 6 },
        &storage,
    );
}

test "segmented replacement scrubs inactive capacity" {
    var storage = [_]u8{ 1, 2, 3, 4 };
    var count: usize = storage.len;
    try std.testing.expect(replace(u8, &storage, &count, &.{9}));
    try std.testing.expectEqualSlices(u8, &.{ 9, 0, 0, 0 }, &storage);
    try std.testing.expectEqual(@as(usize, 1), count);
}

test "segmented reassembly state validates identity phases" {
    try std.testing.expect(reassemblyStateValid(
        0,
        8,
        false,
        false,
        false,
        true,
    ));
    try std.testing.expect(reassemblyStateValid(
        2,
        8,
        true,
        false,
        true,
        false,
    ));
    try std.testing.expect(!reassemblyStateValid(
        2,
        8,
        true,
        true,
        true,
        false,
    ));
}
