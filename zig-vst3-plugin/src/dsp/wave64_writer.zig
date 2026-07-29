const std = @import("std");
const file_writer_io = @import("file_writer_io.zig");
const wave64_metadata = @import("wave64_metadata.zig");
const pcm_dither = @import("pcm_dither.zig");
const pcm_encode = @import("pcm_encode.zig");

pub const Encoding = enum {
    pcm_i16,
    pcm_i24,
    pcm_i32,
    ieee_f32,
};

pub const Spec = struct {
    sample_rate: u32,
    channel_count: u16,
    encoding: Encoding,
};

pub const header_bytes: u64 = 104;

const riff_guid = [_]u8{
    0x72, 0x69, 0x66, 0x66, 0x2e, 0x91, 0xcf, 0x11,
    0xa5, 0xd6, 0x28, 0xdb, 0x04, 0xc1, 0x00, 0x00,
};
const wave_guid = [_]u8{
    0x77, 0x61, 0x76, 0x65, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};
const format_guid = [_]u8{
    0x66, 0x6d, 0x74, 0x20, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};
const data_guid = [_]u8{
    0x64, 0x61, 0x74, 0x61, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};

pub fn requiredBytes(spec: Spec, frame_count: u64) !u64 {
    return requiredBytesWithMetadata(spec, frame_count, .{});
}

pub fn requiredBytesWithMetadata(
    spec: Spec,
    frame_count: u64,
    metadata: wave64_metadata.Metadata,
) !u64 {
    try validateSpec(spec);
    const metadata_bytes = try wave64_metadata.requiredBytes(metadata);
    const data_bytes = std.math.mul(
        u64,
        frame_count,
        try frameBytes(spec),
    ) catch return error.Wave64SizeOverflow;
    const padded_data = std.mem.alignForward(
        u64,
        data_bytes,
        8,
    );
    const prefix_bytes = std.math.add(
        u64,
        header_bytes,
        metadata_bytes,
    ) catch return error.Wave64SizeOverflow;
    return std.math.add(
        u64,
        prefix_bytes,
        padded_data,
    ) catch return error.Wave64SizeOverflow;
}

pub fn makeHeader(spec: Spec, frame_count: u64) ![header_bytes]u8 {
    try validateSpec(spec);
    const data_bytes = std.math.mul(
        u64,
        frame_count,
        try frameBytes(spec),
    ) catch return error.Wave64SizeOverflow;
    const total_bytes = try requiredBytes(spec, frame_count);
    var header: [header_bytes]u8 = undefined;
    writeHeader(&header, spec, data_bytes, total_bytes);
    return header;
}

pub const FileWriter = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    spec: Spec,
    frames_written: u64 = 0,
    data_bytes: u64 = 0,
    byte_count: u64 = header_bytes,
    metadata_bytes: u64 = 0,
    data_offset: u64 = header_bytes,
    failed: bool = false,

    /// The caller owns the file and must keep it open for the writer lifetime.
    pub fn init(io: std.Io, file: std.Io.File, spec: Spec) !FileWriter {
        return initWithOperations(io, file, spec, .{});
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        return initWithMetadataAndOperations(
            io,
            file,
            spec,
            .{},
            operations,
        );
    }

    pub fn initWithMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: wave64_metadata.Metadata,
    ) !FileWriter {
        return initWithMetadataAndOperations(
            io,
            file,
            spec,
            metadata,
            .{},
        );
    }

    fn initWithMetadataAndOperations(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: wave64_metadata.Metadata,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        try validateSpec(spec);
        const metadata_bytes = try wave64_metadata.requiredBytes(metadata);
        const data_offset = std.math.add(
            u64,
            header_bytes,
            metadata_bytes,
        ) catch return error.Wave64SizeOverflow;
        try operations.setLength(io, file, data_offset);
        try writeContainerPrefix(operations, io, file, data_offset);
        _ = try wave64_metadata.writeFile(io, file, 40, metadata);
        try writeFormatAndDataHeader(
            operations,
            io,
            file,
            40 + metadata_bytes,
            spec,
            0,
        );
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .spec = spec,
            .byte_count = data_offset,
            .metadata_bytes = metadata_bytes,
            .data_offset = data_offset,
        };
    }

    pub fn append(
        self: *FileWriter,
        comptime Sample: type,
        samples: []const Sample,
    ) !void {
        if (!self.valid()) return error.InvalidWave64FileWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames: u64 = @intCast(
            samples.len / self.spec.channel_count,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_written,
            added_frames,
        ) catch return error.Wave64SizeOverflow;
        const added_bytes = std.math.mul(
            u64,
            @intCast(samples.len),
            sampleBytes(self.spec.encoding),
        ) catch return error.Wave64SizeOverflow;
        const next_data_bytes = std.math.add(
            u64,
            self.data_bytes,
            added_bytes,
        ) catch return error.Wave64SizeOverflow;
        const next_byte_count = try totalBytes(
            self.data_offset,
            next_data_bytes,
        );
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
            8,
        );

        writeEncodedSamples(
            self.operations,
            self.io,
            self.file,
            self.data_offset + self.data_bytes,
            Sample,
            samples,
            self.spec.encoding,
        ) catch |err| {
            checkpoint.restore(
                self.operations,
                self.io,
                self.file,
            ) catch {
                self.failed = true;
            };
            return err;
        };

        self.frames_written = next_frames;
        self.data_bytes = next_data_bytes;
        self.byte_count = next_byte_count;
        writePadding(
            self.operations,
            self.io,
            self.file,
            self.data_offset,
            self.data_bytes,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        updateSizes(
            self.operations,
            self.io,
            self.file,
            self.data_offset,
            self.data_bytes,
            self.byte_count,
        ) catch |err| {
            self.failed = true;
            return err;
        };
    }

    pub fn appendDithered(
        self: *FileWriter,
        comptime Sample: type,
        samples: []const Sample,
        dither: *pcm_dither.PcmDither,
    ) !void {
        if (!self.valid()) return error.InvalidWave64FileWriterState;
        try validateDitheredSamples(Sample, samples, self.spec, dither);
        const added_frames: u64 = @intCast(
            samples.len / self.spec.channel_count,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_written,
            added_frames,
        ) catch return error.Wave64SizeOverflow;
        const added_bytes = std.math.mul(
            u64,
            @intCast(samples.len),
            sampleBytes(self.spec.encoding),
        ) catch return error.Wave64SizeOverflow;
        const next_data_bytes = std.math.add(
            u64,
            self.data_bytes,
            added_bytes,
        ) catch return error.Wave64SizeOverflow;
        const next_byte_count = try totalBytes(
            self.data_offset,
            next_data_bytes,
        );
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
            8,
        );
        const original_dither = dither.*;

        pcm_encode.writeDitheredWithOperations(
            self.operations,
            self.io,
            self.file,
            self.data_offset + self.data_bytes,
            Sample,
            samples,
            .little,
            dither,
        ) catch |err| {
            dither.* = original_dither;
            checkpoint.restore(
                self.operations,
                self.io,
                self.file,
            ) catch {
                self.failed = true;
            };
            return err;
        };

        self.frames_written = next_frames;
        self.data_bytes = next_data_bytes;
        self.byte_count = next_byte_count;
        writePadding(
            self.operations,
            self.io,
            self.file,
            self.data_offset,
            self.data_bytes,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        updateSizes(
            self.operations,
            self.io,
            self.file,
            self.data_offset,
            self.data_bytes,
            self.byte_count,
        ) catch |err| {
            self.failed = true;
            return err;
        };
    }

    pub fn finalize(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidWave64FileWriterState;
        try self.recover();
        try self.file.sync(self.io);
    }

    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidWave64FileWriterState;
        const checkpoint = file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
            8,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        checkpoint.restore(
            self.operations,
            self.io,
            self.file,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        updateSizes(
            self.operations,
            self.io,
            self.file,
            self.data_offset,
            self.data_bytes,
            self.byte_count,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        self.failed = false;
    }

    pub fn valid(self: *const FileWriter) bool {
        return !self.failed and self.recoverable();
    }

    pub fn recoverable(self: *const FileWriter) bool {
        validateSpec(self.spec) catch return false;
        if (self.metadata_bytes & 7 != 0) return false;
        const expected_offset = std.math.add(
            u64,
            header_bytes,
            self.metadata_bytes,
        ) catch return false;
        if (self.data_offset != expected_offset) return false;
        const expected_data = std.math.mul(
            u64,
            self.frames_written,
            frameBytes(self.spec) catch return false,
        ) catch return false;
        const expected_bytes = totalBytes(
            self.data_offset,
            expected_data,
        ) catch return false;
        return self.byte_count == expected_bytes and
            self.data_bytes == expected_data;
    }
};

fn writeHeader(
    destination: []u8,
    spec: Spec,
    data_bytes: u64,
    total_bytes: u64,
) void {
    const bytes_per_sample = sampleBytes(spec.encoding);
    const block_align: u16 = @intCast(
        @as(u64, spec.channel_count) * bytes_per_sample,
    );
    const byte_rate = spec.sample_rate * @as(u32, block_align);
    const format_code: u16 = switch (spec.encoding) {
        .pcm_i16, .pcm_i24, .pcm_i32 => 1,
        .ieee_f32 => 3,
    };

    @memcpy(destination[0..16], &riff_guid);
    std.mem.writeInt(u64, destination[16..24], total_bytes, .little);
    @memcpy(destination[24..40], &wave_guid);
    @memcpy(destination[40..56], &format_guid);
    std.mem.writeInt(u64, destination[56..64], 40, .little);
    std.mem.writeInt(u16, destination[64..66], format_code, .little);
    std.mem.writeInt(u16, destination[66..68], spec.channel_count, .little);
    std.mem.writeInt(u32, destination[68..72], spec.sample_rate, .little);
    std.mem.writeInt(u32, destination[72..76], byte_rate, .little);
    std.mem.writeInt(u16, destination[76..78], block_align, .little);
    std.mem.writeInt(
        u16,
        destination[78..80],
        @intCast(bytes_per_sample * 8),
        .little,
    );
    @memcpy(destination[80..96], &data_guid);
    std.mem.writeInt(
        u64,
        destination[96..104],
        data_bytes + 24,
        .little,
    );
}

fn writeContainerPrefix(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    total_bytes: u64,
) !void {
    var prefix: [40]u8 = undefined;
    @memcpy(prefix[0..16], &riff_guid);
    std.mem.writeInt(u64, prefix[16..24], total_bytes, .little);
    @memcpy(prefix[24..40], &wave_guid);
    try operations.writeAt(io, file, 0, &prefix);
}

fn writeFormatAndDataHeader(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    spec: Spec,
    data_bytes: u64,
) !void {
    var header: [64]u8 = undefined;
    const bytes_per_sample = sampleBytes(spec.encoding);
    const block_align: u16 = @intCast(
        @as(u64, spec.channel_count) * bytes_per_sample,
    );
    const byte_rate = spec.sample_rate * @as(u32, block_align);
    const format_code: u16 = switch (spec.encoding) {
        .pcm_i16, .pcm_i24, .pcm_i32 => 1,
        .ieee_f32 => 3,
    };
    @memcpy(header[0..16], &format_guid);
    std.mem.writeInt(u64, header[16..24], 40, .little);
    std.mem.writeInt(u16, header[24..26], format_code, .little);
    std.mem.writeInt(u16, header[26..28], spec.channel_count, .little);
    std.mem.writeInt(u32, header[28..32], spec.sample_rate, .little);
    std.mem.writeInt(u32, header[32..36], byte_rate, .little);
    std.mem.writeInt(u16, header[36..38], block_align, .little);
    std.mem.writeInt(
        u16,
        header[38..40],
        @intCast(bytes_per_sample * 8),
        .little,
    );
    @memcpy(header[40..56], &data_guid);
    std.mem.writeInt(
        u64,
        header[56..64],
        std.math.add(u64, data_bytes, 24) catch
            return error.Wave64SizeOverflow,
        .little,
    );
    try operations.writeAt(io, file, offset, &header);
}

fn updateSizes(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    data_offset: u64,
    data_bytes: u64,
    total_bytes: u64,
) !void {
    var encoded: [8]u8 = undefined;
    std.mem.writeInt(u64, &encoded, total_bytes, .little);
    try operations.writeAt(io, file, 16, &encoded);
    std.mem.writeInt(
        u64,
        &encoded,
        std.math.add(u64, data_bytes, 24) catch
            return error.Wave64SizeOverflow,
        .little,
    );
    try operations.writeAt(io, file, data_offset - 8, &encoded);
}

fn totalBytes(data_offset: u64, data_bytes: u64) !u64 {
    const padded_data = std.mem.alignForward(u64, data_bytes, 8);
    return std.math.add(
        u64,
        data_offset,
        padded_data,
    ) catch return error.Wave64SizeOverflow;
}

fn writePadding(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    data_offset: u64,
    data_bytes: u64,
) !void {
    _ = try file_writer_io.writeAlignmentPadding(
        operations,
        io,
        file,
        data_offset + data_bytes,
        8,
    );
}

fn writeEncodedSamples(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    comptime Sample: type,
    samples: []const Sample,
    encoding: Encoding,
) !void {
    try pcm_encode.writeValidatedWithOperations(
        operations,
        io,
        file,
        initial_offset,
        Sample,
        samples,
        pcmEncoding(encoding),
        .little,
    );
}

fn encodeSamples(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    encoding: Encoding,
) void {
    pcm_encode.encodeValidated(
        Sample,
        destination,
        samples,
        pcmEncoding(encoding),
        .little,
    );
}

fn validateSamples(
    comptime Sample: type,
    samples: []const Sample,
    spec: Spec,
) !void {
    if (Sample != f32 and Sample != f64)
        @compileError("Wave64 writing supports f32 and f64 input");
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.Wave64ChannelLengthMismatch;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.NonFiniteWave64Sample;
        if (spec.encoding == .ieee_f32 and
            !std.math.isFinite(@as(f32, @floatCast(sample))))
            return error.NonFiniteWave64Sample;
    }
}

fn validateDitheredSamples(
    comptime Sample: type,
    samples: []const Sample,
    spec: Spec,
    dither: *const pcm_dither.PcmDither,
) !void {
    try validateSamples(Sample, samples, spec);
    if (spec.encoding == .ieee_f32)
        return error.DitherRequiresIntegerPcm;
    if (dither.channelCount() != spec.channel_count)
        return error.DitherChannelCountMismatch;
    if (dither.bitsPerSample() != encodingBits(spec.encoding))
        return error.DitherBitDepthMismatch;
}

fn validateSpec(spec: Spec) !void {
    if (spec.sample_rate < 1_000 or
        spec.sample_rate > 768_000 or
        spec.channel_count == 0 or
        spec.channel_count > 64)
        return error.InvalidWave64Spec;
}

fn frameBytes(spec: Spec) !u64 {
    return std.math.mul(
        u64,
        spec.channel_count,
        sampleBytes(spec.encoding),
    ) catch return error.Wave64SizeOverflow;
}

fn sampleBytes(encoding: Encoding) u64 {
    return @intCast(pcm_encode.byteCount(pcmEncoding(encoding)));
}

fn encodingBits(encoding: Encoding) u6 {
    return pcm_encode.bitCount(pcmEncoding(encoding));
}

fn pcmEncoding(encoding: Encoding) pcm_encode.Encoding {
    return switch (encoding) {
        .pcm_i16 => .pcm_i16,
        .pcm_i24 => .pcm_i24,
        .pcm_i32 => .pcm_i32,
        .ieee_f32 => .ieee_f32,
    };
}

test "Wave64 header stores 64-bit chunk sizes and standard GUIDs" {
    const spec = Spec{
        .sample_rate = 192_000,
        .channel_count = 2,
        .encoding = .pcm_i32,
    };
    const frames: u64 = 1_000_000_000;
    const header = try makeHeader(spec, frames);
    try std.testing.expectEqualSlices(u8, &riff_guid, header[0..16]);
    try std.testing.expectEqualSlices(u8, &wave_guid, header[24..40]);
    try std.testing.expectEqualSlices(u8, &format_guid, header[40..56]);
    try std.testing.expectEqualSlices(u8, &data_guid, header[80..96]);
    try std.testing.expectEqual(
        @as(u64, 8_000_000_104),
        std.mem.readInt(u64, header[16..24], .little),
    );
    try std.testing.expectEqual(
        @as(u64, 8_000_000_024),
        std.mem.readInt(u64, header[96..104], .little),
    );
}

test "file-backed Wave64 writer streams PCM24 with eight-byte padding" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.w64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.append(f32, &.{0.5});
    try std.testing.expectEqual(@as(u64, 112), writer.byte_count);
    try writer.append(f32, &.{-0.5});
    try writer.finalize();
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(u64, 112), writer.byte_count);

    var bytes: [112]u8 = undefined;
    try std.testing.expectEqual(
        bytes.len,
        try file.readPositionalAll(std.testing.io, &bytes, 0),
    );
    try std.testing.expectEqual(
        @as(u64, 30),
        std.mem.readInt(u64, bytes[96..104], .little),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x00, 0x00, 0x40, 0x00, 0x00, 0xc0 },
        bytes[104..110],
    );
    try std.testing.expectEqualSlices(u8, &.{ 0, 0 }, bytes[110..112]);
}

test "file-backed Wave64 dither preserves bytes and state across appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "dithered.w64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i32,
    };
    const samples = [_]f64{ 0.25, -0.25, 0.5, -0.5 };
    const config = pcm_dither.Config{
        .channel_count = 2,
        .bits_per_sample = 32,
        .mode = .noise_shaped,
        .seed = 101,
    };
    var streamed_dither = try pcm_dither.PcmDither.init(config);
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.appendDithered(f64, samples[0..2], &streamed_dither);
    try writer.appendDithered(f64, samples[2..], &streamed_dither);
    try writer.finalize();

    var expected: [16]u8 = undefined;
    var expected_dither = try pcm_dither.PcmDither.init(config);
    try pcm_encode.encodeDithered(
        f64,
        &expected,
        &samples,
        .little,
        &expected_dither,
    );
    var actual: [16]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(
            std.testing.io,
            &actual,
            writer.data_offset,
        ),
    );
    try std.testing.expectEqualSlices(u8, &expected, &actual);
    try std.testing.expectEqualDeep(expected_dither, streamed_dither);
}

test "Wave64 writer validates append transactionally" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional.w64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.init(std.testing.io, file, .{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .ieee_f32,
    });
    try std.testing.expectError(
        error.Wave64ChannelLengthMismatch,
        writer.append(f32, &.{ 0.0, 0.5, 1.0 }),
    );
    try std.testing.expectEqual(
        header_bytes,
        try file.length(std.testing.io),
    );
    try std.testing.expect(writer.valid());
    writer.metadata_bytes = 1;
    try std.testing.expect(!writer.valid());
    try std.testing.expectError(
        error.InvalidWave64FileWriterState,
        writer.append(f32, &.{ 0.0, 0.0 }),
    );
}
