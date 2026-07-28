const std = @import("std");

/// A positional write may return short progress, but never more than `bytes.len`.
pub const Operations = struct {
    context: ?*anyopaque = null,
    vtable: *const VTable = &system_vtable,

    pub const VTable = struct {
        write_at: *const fn (
            ?*anyopaque,
            std.Io,
            std.Io.File,
            u64,
            []const u8,
        ) anyerror!usize,
        set_length: *const fn (
            ?*anyopaque,
            std.Io,
            std.Io.File,
            u64,
        ) anyerror!void,
    };

    pub fn writeAt(
        self: Operations,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !void {
        var written: usize = 0;
        while (written < bytes.len) {
            const write_offset = std.math.add(
                u64,
                offset,
                @intCast(written),
            ) catch return error.FileOffsetOverflow;
            const count = try self.vtable.write_at(
                self.context,
                io,
                file,
                write_offset,
                bytes[written..],
            );
            if (count == 0) return error.FileWriteMadeNoProgress;
            if (count > bytes.len - written)
                return error.InvalidFileWriteCount;
            written += count;
        }
    }

    pub fn setLength(
        self: Operations,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        try self.vtable.set_length(
            self.context,
            io,
            file,
            length,
        );
    }
};

fn systemWriteAt(
    _: ?*anyopaque,
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    bytes: []const u8,
) !usize {
    const buffers = [_][]const u8{bytes};
    return file.writePositional(io, &buffers, offset);
}

fn systemSetLength(
    _: ?*anyopaque,
    io: std.Io,
    file: std.Io.File,
    length: u64,
) !void {
    try file.setLength(io, length);
}

const system_vtable = Operations.VTable{
    .write_at = systemWriteAt,
    .set_length = systemSetLength,
};

pub const Checkpoint = struct {
    committed_length: u64,
    payload_end: u64,
    alignment: u8,

    pub fn exact(committed_length: u64) Checkpoint {
        return .{
            .committed_length = committed_length,
            .payload_end = committed_length,
            .alignment = 1,
        };
    }

    pub fn aligned(
        committed_length: u64,
        payload_end: u64,
        alignment: u8,
    ) !Checkpoint {
        const expected_length = try alignedLength(
            payload_end,
            alignment,
        );
        if (expected_length != committed_length)
            return error.InvalidCommittedFileLength;
        return .{
            .committed_length = committed_length,
            .payload_end = payload_end,
            .alignment = alignment,
        };
    }

    /// Restore the committed boundary and its canonical zero padding.
    pub fn restore(
        self: Checkpoint,
        operations: Operations,
        io: std.Io,
        file: std.Io.File,
    ) !void {
        const expected_length = try alignedLength(
            self.payload_end,
            self.alignment,
        );
        if (expected_length != self.committed_length)
            return error.InvalidCommittedFileLength;
        try operations.setLength(io, file, self.committed_length);
        _ = try writeAlignmentPadding(
            operations,
            io,
            file,
            self.payload_end,
            self.alignment,
        );
    }
};

pub fn writeAlignmentPadding(
    operations: Operations,
    io: std.Io,
    file: std.Io.File,
    payload_end: u64,
    alignment: u8,
) !u8 {
    const padding = try alignmentPadding(payload_end, alignment);
    if (padding == 0) return 0;
    const zeros: [7]u8 = @splat(0);
    try operations.writeAt(
        io,
        file,
        payload_end,
        zeros[0..padding],
    );
    return padding;
}

/// Restores one committed payload boundary without accepting inconsistent
/// container state.
pub fn restoreAlignedLength(
    operations: Operations,
    io: std.Io,
    file: std.Io.File,
    committed_length: u64,
    payload_end: u64,
    alignment: u8,
) !void {
    const checkpoint = try Checkpoint.aligned(
        committed_length,
        payload_end,
        alignment,
    );
    try checkpoint.restore(
        operations,
        io,
        file,
    );
}

fn alignedLength(payload_end: u64, alignment: u8) !u64 {
    const padding = try alignmentPadding(payload_end, alignment);
    return std.math.add(
        u64,
        payload_end,
        padding,
    ) catch return error.FileOffsetOverflow;
}

fn alignmentPadding(payload_end: u64, alignment: u8) !u8 {
    if (alignment == 0 or
        alignment > 8 or
        !std.math.isPowerOfTwo(alignment))
        return error.InvalidFileAlignment;
    const remainder: u8 = @intCast(payload_end % alignment);
    return if (remainder == 0)
        0
    else
        alignment - remainder;
}

const InvalidWriteBackend = struct {
    count: usize,

    fn operations(self: *@This()) Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn writeAt(
        context: ?*anyopaque,
        _: std.Io,
        _: std.Io.File,
        _: u64,
        _: []const u8,
    ) !usize {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingWriteBackendContext,
        ));
        return self.count;
    }

    fn setLength(
        _: ?*anyopaque,
        _: std.Io,
        _: std.Io.File,
        _: u64,
    ) !void {}

    const vtable = Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
    };
};

const RestoreFaultBackend = struct {
    delegate: Operations = .{},
    write_calls: usize = 0,
    set_length_calls: usize = 0,
    fail_write: bool = false,
    fail_set_length: bool = false,

    fn operations(self: *@This()) Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn writeAt(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !usize {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingRestoreBackendContext,
        ));
        self.write_calls += 1;
        if (self.fail_write) return error.InjectedPaddingWriteFailure;
        try self.delegate.writeAt(io, file, offset, bytes);
        return bytes.len;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingRestoreBackendContext,
        ));
        self.set_length_calls += 1;
        if (self.fail_set_length)
            return error.InjectedFileTruncateFailure;
        try self.delegate.setLength(io, file, length);
    }

    const vtable = Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
    };
};

test "system file writer operations write and truncate positionally" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "operations.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const operations = Operations{};
    try operations.writeAt(std.testing.io, file, 4, "abcd");
    try operations.setLength(std.testing.io, file, 6);

    var bytes: [6]u8 = undefined;
    try std.testing.expectEqual(
        bytes.len,
        try file.readPositionalAll(std.testing.io, &bytes, 0),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 'a', 'b' },
        &bytes,
    );
}

test "file writer operations reject invalid backend progress" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-progress.bin",
        .{},
    );
    defer file.close(std.testing.io);

    var backend = InvalidWriteBackend{ .count = 0 };
    try std.testing.expectError(
        error.FileWriteMadeNoProgress,
        backend.operations().writeAt(
            std.testing.io,
            file,
            0,
            "abc",
        ),
    );
    backend.count = 4;
    try std.testing.expectError(
        error.InvalidFileWriteCount,
        backend.operations().writeAt(
            std.testing.io,
            file,
            0,
            "abc",
        ),
    );
}

test "file writer alignment padding writes only required zero bytes" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "padding.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const fill: [16]u8 = @splat(0xff);
    try (Operations{}).writeAt(std.testing.io, file, 0, &fill);
    try std.testing.expectEqual(
        @as(u8, 5),
        try writeAlignmentPadding(
            .{},
            std.testing.io,
            file,
            3,
            8,
        ),
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        try writeAlignmentPadding(
            .{},
            std.testing.io,
            file,
            8,
            8,
        ),
    );
    try std.testing.expectError(
        error.InvalidFileAlignment,
        writeAlignmentPadding(
            .{},
            std.testing.io,
            file,
            0,
            3,
        ),
    );
    var bytes: [8]u8 = @splat(0xff);
    _ = try file.readPositionalAll(std.testing.io, &bytes, 0);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0, 0 },
        bytes[3..8],
    );
}

test "aligned length restoration validates before truncating" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "restore.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const fill: [12]u8 = @splat(0xff);
    try (Operations{}).writeAt(std.testing.io, file, 0, &fill);

    try std.testing.expectError(
        error.InvalidCommittedFileLength,
        restoreAlignedLength(
            .{},
            std.testing.io,
            file,
            7,
            5,
            8,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 12),
        (try file.stat(std.testing.io)).size,
    );

    try restoreAlignedLength(
        .{},
        std.testing.io,
        file,
        8,
        5,
        8,
    );
    try std.testing.expectEqual(
        @as(u64, 8),
        (try file.stat(std.testing.io)).size,
    );
    var bytes: [8]u8 = undefined;
    try std.testing.expectEqual(
        bytes.len,
        try file.readPositionalAll(std.testing.io, &bytes, 0),
    );
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, bytes[5..]);
}

test "file checkpoint restores exact and aligned boundaries" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "checkpoint.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const fill: [16]u8 = @splat(0xff);
    const operations = Operations{};
    try operations.writeAt(std.testing.io, file, 0, &fill);

    try Checkpoint.exact(10).restore(
        operations,
        std.testing.io,
        file,
    );
    try std.testing.expectEqual(
        @as(u64, 10),
        (try file.stat(std.testing.io)).size,
    );

    try operations.writeAt(std.testing.io, file, 0, &fill);
    const aligned = try Checkpoint.aligned(8, 5, 8);
    try aligned.restore(operations, std.testing.io, file);
    var bytes: [8]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &bytes, 0);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, bytes[5..]);

    try std.testing.expectError(
        error.InvalidCommittedFileLength,
        Checkpoint.aligned(7, 5, 8),
    );
}

test "file checkpoint contains restore failures and remains retryable" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "checkpoint-faults.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const fill: [16]u8 = @splat(0xff);
    try (Operations{}).writeAt(std.testing.io, file, 0, &fill);

    var backend = RestoreFaultBackend{ .fail_set_length = true };
    const checkpoint = try Checkpoint.aligned(8, 5, 8);
    try std.testing.expectError(
        error.InjectedFileTruncateFailure,
        checkpoint.restore(
            backend.operations(),
            std.testing.io,
            file,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 16),
        (try file.stat(std.testing.io)).size,
    );
    try std.testing.expectEqual(@as(usize, 0), backend.write_calls);

    backend.fail_set_length = false;
    backend.fail_write = true;
    try std.testing.expectError(
        error.InjectedPaddingWriteFailure,
        checkpoint.restore(
            backend.operations(),
            std.testing.io,
            file,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 8),
        (try file.stat(std.testing.io)).size,
    );

    backend.fail_write = false;
    try checkpoint.restore(
        backend.operations(),
        std.testing.io,
        file,
    );
    var bytes: [8]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &bytes, 0);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0 }, bytes[5..]);
}

test "invalid file checkpoint does not invoke storage operations" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-checkpoint.bin",
        .{},
    );
    defer file.close(std.testing.io);

    var backend = RestoreFaultBackend{};
    const invalid = Checkpoint{
        .committed_length = 7,
        .payload_end = 5,
        .alignment = 8,
    };
    try std.testing.expectError(
        error.InvalidCommittedFileLength,
        invalid.restore(
            backend.operations(),
            std.testing.io,
            file,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), backend.set_length_calls);
    try std.testing.expectEqual(@as(usize, 0), backend.write_calls);
}
