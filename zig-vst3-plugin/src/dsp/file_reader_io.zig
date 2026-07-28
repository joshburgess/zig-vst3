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
