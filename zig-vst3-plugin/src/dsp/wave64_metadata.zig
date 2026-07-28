const std = @import("std");
const audio_metadata = @import("audio_metadata.zig");
const broadcast_metadata = @import("broadcast_metadata.zig");

pub const Metadata = struct {
    broadcast: ?broadcast_metadata.Extension = null,
    info: []const audio_metadata.Entry = &.{},
};

pub const broadcast_guid = [_]u8{
    0x62, 0x65, 0x78, 0x74, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};

pub const list_guid = [_]u8{
    0x6c, 0x69, 0x73, 0x74, 0x2f, 0x91, 0xcf, 0x11,
    0xa5, 0xd6, 0x28, 0xdb, 0x04, 0xc1, 0x00, 0x00,
};

pub fn requiredBytes(metadata: Metadata) !u64 {
    var required: u64 = 0;
    if (metadata.broadcast) |broadcast| {
        _ = try broadcast_metadata.requiredBytes(broadcast);
        const payload_bytes: u64 = @intCast(
            broadcast_metadata.fixed_payload_bytes +
                broadcast.coding_history.len,
        );
        required = try addChunkBytes(required, payload_bytes);
    }
    if (metadata.info.len != 0) {
        const riff_bytes = try audio_metadata.requiredRiffInfoBytes(
            metadata.info,
        );
        required = try addChunkBytes(required, @intCast(riff_bytes - 8));
    }
    return required;
}

pub fn writeFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    metadata: Metadata,
) !u64 {
    const required = try requiredBytes(metadata);
    var offset = initial_offset;
    if (metadata.broadcast) |broadcast| {
        _ = try broadcast_metadata.requiredBytes(broadcast);
        const payload_bytes: u64 = @intCast(
            broadcast_metadata.fixed_payload_bytes +
                broadcast.coding_history.len,
        );
        try writeChunkHeader(
            io,
            file,
            offset,
            broadcast_guid,
            payload_bytes,
        );
        var fixed: [8 + broadcast_metadata.fixed_payload_bytes]u8 =
            undefined;
        _ = try broadcast_metadata.encode(&fixed, .{
            .description = broadcast.description,
            .originator = broadcast.originator,
            .originator_reference = broadcast.originator_reference,
            .origination_date = broadcast.origination_date,
            .origination_time = broadcast.origination_time,
            .time_reference = broadcast.time_reference,
            .version = broadcast.version,
            .umid = broadcast.umid,
            .loudness = broadcast.loudness,
        });
        try writeAt(io, file, offset + 24, fixed[8..]);
        try writeAt(
            io,
            file,
            offset + 24 + broadcast_metadata.fixed_payload_bytes,
            broadcast.coding_history,
        );
        const chunk_bytes = try chunkBytes(payload_bytes);
        try writeAlignmentPadding(
            io,
            file,
            offset + 24 + payload_bytes,
            chunk_bytes - 24 - payload_bytes,
        );
        offset += chunk_bytes;
    }
    if (metadata.info.len != 0) {
        const riff_bytes = try audio_metadata.requiredRiffInfoBytes(
            metadata.info,
        );
        const payload_bytes: u64 = @intCast(riff_bytes - 8);
        try writeChunkHeader(
            io,
            file,
            offset,
            list_guid,
            payload_bytes,
        );
        _ = try audio_metadata.writeRiffInfoPayloadFile(
            io,
            file,
            offset + 24,
            metadata.info,
        );
        const chunk_bytes = try chunkBytes(payload_bytes);
        try writeAlignmentPadding(
            io,
            file,
            offset + 24 + payload_bytes,
            chunk_bytes - 24 - payload_bytes,
        );
        offset += chunk_bytes;
    }
    if (offset - initial_offset != required)
        return error.InvalidWave64MetadataState;
    return required;
}

fn addChunkBytes(current: u64, payload_bytes: u64) !u64 {
    return std.math.add(
        u64,
        current,
        try chunkBytes(payload_bytes),
    ) catch return error.Wave64MetadataSizeOverflow;
}

fn chunkBytes(payload_bytes: u64) !u64 {
    const unaligned = std.math.add(
        u64,
        24,
        payload_bytes,
    ) catch return error.Wave64MetadataSizeOverflow;
    return std.mem.alignForward(u64, unaligned, 8);
}

fn writeChunkHeader(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    guid: [16]u8,
    payload_bytes: u64,
) !void {
    var header: [24]u8 = undefined;
    @memcpy(header[0..16], &guid);
    std.mem.writeInt(
        u64,
        header[16..24],
        std.math.add(u64, 24, payload_bytes) catch
            return error.Wave64MetadataSizeOverflow,
        .little,
    );
    try writeAt(io, file, offset, &header);
}

fn writeAlignmentPadding(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    padding_bytes: u64,
) !void {
    if (padding_bytes == 0) return;
    if (padding_bytes > 7) return error.InvalidWave64MetadataState;
    const zeros: [7]u8 = @splat(0);
    try writeAt(io, file, offset, zeros[0..@intCast(padding_bytes)]);
}

fn writeAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    bytes: []const u8,
) !void {
    var writer = file.writer(io, &.{});
    try writer.seekTo(offset);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

test "Wave64 metadata writes registered BEXT and INFO chunks" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata.w64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const metadata = Metadata{
        .broadcast = .{
            .description = "Wave64",
            .coding_history = "A=PCM\r\n",
        },
        .info = &.{
            .{ .id = audio_metadata.title, .value = "Title" },
        },
    };
    const required = try requiredBytes(metadata);
    try std.testing.expectEqual(
        required,
        try writeFile(std.testing.io, file, 3, metadata),
    );
    var bytes: [720]u8 = @splat(0xff);
    const read = try file.readPositionalAll(
        std.testing.io,
        bytes[0..@intCast(required)],
        3,
    );
    try std.testing.expectEqual(@as(usize, @intCast(required)), read);
    try std.testing.expectEqualSlices(
        u8,
        &broadcast_guid,
        bytes[0..16],
    );
    const first_bytes = std.mem.alignForward(
        u64,
        std.mem.readInt(u64, bytes[16..24], .little),
        8,
    );
    try std.testing.expectEqualSlices(
        u8,
        &list_guid,
        bytes[@intCast(first_bytes)..][0..16],
    );
    try std.testing.expectEqualSlices(
        u8,
        "INFO",
        bytes[@intCast(first_bytes + 24)..][0..4],
    );
}

test "Wave64 metadata validation precedes file mutation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid.w64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "retained", 0);
    try std.testing.expectError(
        error.InvalidCodingHistory,
        writeFile(std.testing.io, file, 0, .{
            .broadcast = .{ .coding_history = "bad" },
        }),
    );
    var retained: [8]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &retained, 0);
    try std.testing.expectEqualSlices(u8, "retained", &retained);
}
