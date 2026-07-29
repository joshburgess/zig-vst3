const std = @import("std");

pub fn readExactAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    destination: []u8,
    comptime truncated_error: anyerror,
) !void {
    _ = std.math.add(
        u64,
        offset,
        destination.len,
    ) catch return truncated_error;
    if (try file.readPositionalAll(io, destination, offset) != destination.len)
        return truncated_error;
}

pub fn readBoundedFile(
    io: std.Io,
    file: std.Io.File,
    storage: []u8,
    comptime storage_error: anyerror,
    comptime truncated_error: anyerror,
) ![]u8 {
    const size = (try file.stat(io)).size;
    if (size > storage.len) return storage_error;
    const byte_count: usize = @intCast(size);
    try readExactAt(
        io,
        file,
        0,
        storage[0..byte_count],
        truncated_error,
    );
    return storage[0..byte_count];
}

test "exact positional reads preserve the caller error contract" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "exact.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "abc", 0);

    var complete: [3]u8 = undefined;
    try readExactAt(
        std.testing.io,
        file,
        0,
        &complete,
        error.TestTruncatedContainer,
    );
    try std.testing.expectEqualSlices(u8, "abc", &complete);

    var truncated: [4]u8 = undefined;
    try std.testing.expectError(
        error.TestTruncatedContainer,
        readExactAt(
            std.testing.io,
            file,
            0,
            &truncated,
            error.TestTruncatedContainer,
        ),
    );

    var overflowing: [2]u8 = undefined;
    try std.testing.expectError(
        error.TestTruncatedContainer,
        readExactAt(
            std.testing.io,
            file,
            std.math.maxInt(u64),
            &overflowing,
            error.TestTruncatedContainer,
        ),
    );
}

test "bounded file reads preserve storage errors and return exact slice" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "bounded.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "abcd", 0);

    var complete: [6]u8 = @splat(0xaa);
    const bytes = try readBoundedFile(
        std.testing.io,
        file,
        &complete,
        error.TestStorageTooSmall,
        error.TestTruncatedContainer,
    );
    try std.testing.expectEqualSlices(u8, "abcd", bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xaa }, complete[4..]);

    var short: [3]u8 = undefined;
    try std.testing.expectError(
        error.TestStorageTooSmall,
        readBoundedFile(
            std.testing.io,
            file,
            &short,
            error.TestStorageTooSmall,
            error.TestTruncatedContainer,
        ),
    );
}
