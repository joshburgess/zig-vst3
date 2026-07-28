const std = @import("std");
const audio_metadata = @import("audio_metadata.zig");
const file_writer_io = @import("file_writer_io.zig");
const pcm_dither = @import("pcm_dither.zig");
const pcm_encode = @import("pcm_encode.zig");

pub const Encoding = enum {
    pcm_i16,
    ieee_f32,
    pcm_i24,
    pcm_i32,
};

pub const Spec = struct {
    sample_rate: u32,
    channel_count: u16,
    encoding: Encoding,
};

pub const Writer = struct {
    destination: []u8,
    spec: Spec,
    frames_written: usize = 0,
    byte_count: usize = 44,

    /// The destination storage must outlive the writer.
    pub fn init(destination: []u8, spec: Spec) !Writer {
        const required = try requiredBytes(spec, 0);
        if (destination.len < required) return error.WavOutputTooSmall;
        writeHeader(destination, spec, 0);
        return .{
            .destination = destination,
            .spec = spec,
        };
    }

    pub fn append(
        self: *Writer,
        comptime Sample: type,
        samples: []const Sample,
    ) !void {
        if (!self.valid()) return error.InvalidWavWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.WavSizeOverflow;
        const required = try requiredBytes(self.spec, next_frames);
        if (self.destination.len < required) return error.WavOutputTooSmall;
        const previous_data_bytes = try dataBytes(
            self.spec,
            self.frames_written,
        );
        const next_data_bytes = try dataBytes(self.spec, next_frames);
        const added_bytes = next_data_bytes - previous_data_bytes;

        encodeSamples(
            Sample,
            self.destination[44 + previous_data_bytes ..][0..added_bytes],
            samples,
            self.spec.encoding,
        );
        if (next_data_bytes & 1 != 0)
            self.destination[44 + next_data_bytes] = 0;
        self.frames_written = next_frames;
        self.byte_count = required;
        writeHeader(
            self.destination,
            self.spec,
            @intCast(next_data_bytes),
        );
    }

    pub fn appendDithered(
        self: *Writer,
        comptime Sample: type,
        samples: []const Sample,
        dither: *pcm_dither.PcmDither,
    ) !void {
        if (!self.valid()) return error.InvalidWavWriterState;
        try validateDitheredSamples(Sample, samples, self.spec, dither);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.WavSizeOverflow;
        const required = try requiredBytes(self.spec, next_frames);
        if (self.destination.len < required)
            return error.WavOutputTooSmall;
        const previous_data_bytes = try dataBytes(
            self.spec,
            self.frames_written,
        );
        const next_data_bytes = try dataBytes(self.spec, next_frames);
        const added_bytes = next_data_bytes - previous_data_bytes;

        try pcm_encode.encodeDithered(
            Sample,
            self.destination[44 + previous_data_bytes ..][0..added_bytes],
            samples,
            .little,
            dither,
        );
        if (next_data_bytes & 1 != 0)
            self.destination[44 + next_data_bytes] = 0;
        self.frames_written = next_frames;
        self.byte_count = required;
        writeHeader(
            self.destination,
            self.spec,
            @intCast(next_data_bytes),
        );
    }

    pub fn bytes(self: *const Writer) []const u8 {
        return self.destination[0..@min(self.byte_count, self.destination.len)];
    }

    pub fn valid(self: *const Writer) bool {
        if (self.byte_count < 44 or self.byte_count > self.destination.len)
            return false;
        const expected = requiredBytes(
            self.spec,
            self.frames_written,
        ) catch return false;
        return self.byte_count == expected;
    }
};

pub const FileWriter = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    spec: Spec,
    frames_written: usize = 0,
    data_bytes: usize = 0,
    metadata_bytes: usize = 0,
    data_offset: usize = 44,
    byte_count: usize = 44,
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
        return initWithRiffMetadataAndOperations(
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
        metadata: []const audio_metadata.Entry,
    ) !FileWriter {
        return initWithRiffMetadata(
            io,
            file,
            spec,
            .{ .info = metadata },
        );
    }

    pub fn initWithRiffMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: audio_metadata.RiffMetadata,
    ) !FileWriter {
        return initWithRiffMetadataAndOperations(
            io,
            file,
            spec,
            metadata,
            .{},
        );
    }

    fn initWithRiffMetadataAndOperations(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: audio_metadata.RiffMetadata,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        try validateSpec(spec);
        try audio_metadata.validateRiffMetadataChannelCount(
            metadata,
            spec.channel_count,
        );
        const metadata_bytes =
            try audio_metadata.requiredRiffMetadataBytes(metadata);
        const data_offset = std.math.add(
            usize,
            44,
            metadata_bytes,
        ) catch return error.WavSizeOverflow;
        if (data_offset - 8 > std.math.maxInt(u32))
            return error.WavSizeOverflow;
        var writer = FileWriter{
            .io = io,
            .file = file,
            .operations = operations,
            .spec = spec,
            .metadata_bytes = metadata_bytes,
            .data_offset = data_offset,
            .byte_count = data_offset,
        };
        try operations.setLength(io, file, @intCast(data_offset));
        try writer.writeCurrentHeaders();
        if (metadata_bytes != 0) {
            _ = try audio_metadata.writeRiffMetadataFile(
                io,
                file,
                12,
                metadata,
            );
        }
        return writer;
    }

    pub fn append(
        self: *FileWriter,
        comptime Sample: type,
        samples: []const Sample,
    ) !void {
        if (!self.valid()) return error.InvalidWavFileWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.WavSizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            usize,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.WavSizeOverflow;
        if (next_byte_count - 8 > std.math.maxInt(u32))
            return error.WavSizeOverflow;
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            @intCast(self.byte_count),
            @intCast(self.data_offset + self.data_bytes),
            2,
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
        self.data_bytes = try dataBytes(self.spec, next_frames);
        self.byte_count = next_byte_count;
        self.writeDataPadding() catch |err| {
            self.failed = true;
            return err;
        };
        self.writeCurrentHeaders() catch |err| {
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
        if (!self.valid()) return error.InvalidWavFileWriterState;
        try validateDitheredSamples(Sample, samples, self.spec, dither);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.WavSizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            usize,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.WavSizeOverflow;
        if (next_byte_count - 8 > std.math.maxInt(u32))
            return error.WavSizeOverflow;
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            @intCast(self.byte_count),
            @intCast(self.data_offset + self.data_bytes),
            2,
        );
        const original_dither = dither.*;

        pcm_encode.writeDitheredWithOperations(
            self.operations,
            self.io,
            self.file,
            @intCast(self.data_offset + self.data_bytes),
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
        self.data_bytes = try dataBytes(self.spec, next_frames);
        self.byte_count = next_byte_count;
        self.writeDataPadding() catch |err| {
            self.failed = true;
            return err;
        };
        self.writeCurrentHeaders() catch |err| {
            self.failed = true;
            return err;
        };
    }

    pub fn finalize(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidWavFileWriterState;
        try self.recover();
        try self.file.sync(self.io);
    }

    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidWavFileWriterState;
        const checkpoint = file_writer_io.Checkpoint.aligned(
            @intCast(self.byte_count),
            @intCast(self.data_offset + self.data_bytes),
            2,
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
        self.writeCurrentHeaders() catch |err| {
            self.failed = true;
            return err;
        };
        self.failed = false;
    }

    pub fn valid(self: *const FileWriter) bool {
        return !self.failed and self.recoverable();
    }

    pub fn recoverable(self: *const FileWriter) bool {
        const encoded_bytes = requiredBytes(
            self.spec,
            self.frames_written,
        ) catch return false;
        const expected = std.math.add(
            usize,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return false;
        const expected_data_offset = std.math.add(
            usize,
            44,
            self.metadata_bytes,
        ) catch return false;
        const expected_data_bytes = dataBytes(
            self.spec,
            self.frames_written,
        ) catch return false;
        return self.data_offset == expected_data_offset and
            self.byte_count == expected and
            self.data_bytes == expected_data_bytes;
    }

    fn writeCurrentHeaders(self: *const FileWriter) !void {
        var riff_header: [12]u8 = undefined;
        writeRiffHeader(
            &riff_header,
            @intCast(self.byte_count - 8),
        );
        var format_chunk: [24]u8 = undefined;
        writeFormatChunk(&format_chunk, self.spec);
        var data_header: [8]u8 = undefined;
        writeDataHeader(&data_header, @intCast(self.data_bytes));
        try self.operations.writeAt(self.io, self.file, 0, &riff_header);
        try self.operations.writeAt(
            self.io,
            self.file,
            @intCast(12 + self.metadata_bytes),
            &format_chunk,
        );
        try self.operations.writeAt(
            self.io,
            self.file,
            @intCast(self.data_offset - data_header.len),
            &data_header,
        );
    }

    fn writeDataPadding(self: *const FileWriter) !void {
        _ = try file_writer_io.writeAlignmentPadding(
            self.operations,
            self.io,
            self.file,
            @intCast(self.data_offset + self.data_bytes),
            2,
        );
    }
};

pub fn requiredBytes(spec: Spec, frame_count: usize) !usize {
    try validateSpec(spec);
    const data_bytes = try dataBytes(spec, frame_count);
    if (data_bytes > std.math.maxInt(u32))
        return error.WavSizeOverflow;
    const padded_data = std.math.add(
        usize,
        data_bytes,
        data_bytes & 1,
    ) catch return error.WavSizeOverflow;
    if (padded_data > std.math.maxInt(u32) - 36)
        return error.WavSizeOverflow;
    return std.math.add(
        usize,
        44,
        padded_data,
    ) catch return error.WavSizeOverflow;
}

pub fn writeInterleaved(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    spec: Spec,
) ![]const u8 {
    try validateSamples(Sample, samples, spec);

    const frame_count = samples.len / spec.channel_count;
    const required = try requiredBytes(spec, frame_count);
    if (destination.len < required) return error.WavOutputTooSmall;
    const data_bytes = try dataBytes(spec, frame_count);

    writeHeader(destination, spec, @intCast(data_bytes));
    encodeSamples(
        Sample,
        destination[44..][0..data_bytes],
        samples,
        spec.encoding,
    );
    if (data_bytes & 1 != 0)
        destination[44 + data_bytes] = 0;
    return destination[0..required];
}

pub fn writeInterleavedDithered(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    spec: Spec,
    dither: *pcm_dither.PcmDither,
) ![]const u8 {
    try validateDitheredSamples(Sample, samples, spec, dither);
    const frame_count = samples.len / spec.channel_count;
    const required = try requiredBytes(spec, frame_count);
    if (destination.len < required) return error.WavOutputTooSmall;
    const data_bytes = try dataBytes(spec, frame_count);

    writeHeader(destination, spec, @intCast(data_bytes));
    try pcm_encode.encodeDithered(
        Sample,
        destination[44..][0..data_bytes],
        samples,
        .little,
        dither,
    );
    if (data_bytes & 1 != 0)
        destination[44 + data_bytes] = 0;
    return destination[0..required];
}

fn writeHeader(destination: []u8, spec: Spec, data_bytes: u32) void {
    writePrefix(
        destination[0..36],
        spec,
        data_bytes + 36 + (data_bytes & 1),
    );
    writeDataHeader(destination[36..44], data_bytes);
}

fn writePrefix(destination: []u8, spec: Spec, riff_bytes: u32) void {
    writeRiffHeader(destination[0..12], riff_bytes);
    writeFormatChunk(destination[12..36], spec);
}

fn writeRiffHeader(destination: []u8, riff_bytes: u32) void {
    @memcpy(destination[0..4], "RIFF");
    std.mem.writeInt(u32, destination[4..8], riff_bytes, .little);
    @memcpy(destination[8..12], "WAVE");
}

fn writeFormatChunk(destination: []u8, spec: Spec) void {
    const bytes_per_sample = sampleBytes(spec.encoding);
    const block_align = @as(u16, @intCast(
        @as(usize, spec.channel_count) * bytes_per_sample,
    ));
    const byte_rate = spec.sample_rate * @as(u32, block_align);
    const format_code: u16 = switch (spec.encoding) {
        .pcm_i16, .pcm_i24, .pcm_i32 => 1,
        .ieee_f32 => 3,
    };

    @memcpy(destination[0..4], "fmt ");
    std.mem.writeInt(u32, destination[4..8], 16, .little);
    std.mem.writeInt(u16, destination[8..10], format_code, .little);
    std.mem.writeInt(u16, destination[10..12], spec.channel_count, .little);
    std.mem.writeInt(u32, destination[12..16], spec.sample_rate, .little);
    std.mem.writeInt(u32, destination[16..20], byte_rate, .little);
    std.mem.writeInt(u16, destination[20..22], block_align, .little);
    std.mem.writeInt(
        u16,
        destination[22..24],
        @intCast(bytes_per_sample * 8),
        .little,
    );
}

fn writeDataHeader(destination: []u8, data_bytes: u32) void {
    @memcpy(destination[0..4], "data");
    std.mem.writeInt(u32, destination[4..8], data_bytes, .little);
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

fn writeEncodedSamples(
    operations: file_writer_io.Operations,
    io: std.Io,
    file: std.Io.File,
    initial_offset: usize,
    comptime Sample: type,
    samples: []const Sample,
    encoding: Encoding,
) !void {
    try pcm_encode.writeValidatedWithOperations(
        operations,
        io,
        file,
        @intCast(initial_offset),
        Sample,
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
        @compileError("WAV writing supports f32 and f64 input");
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.WavChannelLengthMismatch;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.NonFiniteWavSample;
        if (spec.encoding == .ieee_f32 and
            !std.math.isFinite(@as(f32, @floatCast(sample))))
            return error.NonFiniteWavSample;
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
        return error.InvalidWavSpec;
}

fn sampleBytes(encoding: Encoding) usize {
    return pcm_encode.byteCount(pcmEncoding(encoding));
}

fn encodingBits(encoding: Encoding) u6 {
    return pcm_encode.bitCount(pcmEncoding(encoding));
}

fn dataBytes(spec: Spec, frame_count: usize) !usize {
    const frame_bytes = std.math.mul(
        usize,
        @as(usize, spec.channel_count),
        sampleBytes(spec.encoding),
    ) catch return error.WavSizeOverflow;
    return std.math.mul(
        usize,
        frame_count,
        frame_bytes,
    ) catch return error.WavSizeOverflow;
}

fn pcmEncoding(encoding: Encoding) pcm_encode.Encoding {
    return switch (encoding) {
        .pcm_i16 => .pcm_i16,
        .pcm_i24 => .pcm_i24,
        .pcm_i32 => .pcm_i32,
        .ieee_f32 => .ieee_f32,
    };
}

test "WAV writer produces bounded mono PCM" {
    var bytes: [50]u8 = undefined;
    const encoded = try writeInterleaved(
        f32,
        &bytes,
        &.{ -1.0, 0.0, 1.0 },
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    try std.testing.expectEqual(@as(usize, 50), encoded.len);
    try std.testing.expectEqualStrings("RIFF", encoded[0..4]);
    try std.testing.expectEqualStrings("WAVE", encoded[8..12]);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(
        u16,
        encoded[20..22],
        .little,
    ));
    try std.testing.expectEqual(@as(i16, -32_767), @as(i16, @bitCast(
        std.mem.readInt(u16, encoded[44..46], .little),
    )));
}

test "WAV writer pads odd 24-bit data chunks without inflating chunk size" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    var storage: [50]u8 = @splat(0xaa);
    const one_sample = try writeInterleaved(
        f32,
        &storage,
        &.{0.5},
        spec,
    );
    try std.testing.expectEqual(@as(usize, 48), one_sample.len);
    try std.testing.expectEqual(
        @as(u32, 40),
        std.mem.readInt(u32, one_sample[4..8], .little),
    );
    try std.testing.expectEqual(
        @as(u32, 3),
        std.mem.readInt(u32, one_sample[40..44], .little),
    );
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(
        u16,
        one_sample[34..36],
        .little,
    ));
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x00, 0x00, 0x40, 0x00 },
        one_sample[44..48],
    );

    const samples = [_]f32{ 0.5, -0.5 };
    const complete = try writeInterleaved(
        f32,
        &storage,
        &samples,
        spec,
    );
    var incremental_storage: [50]u8 = undefined;
    var incremental = try Writer.init(&incremental_storage, spec);
    try incremental.append(f32, samples[0..1]);
    try incremental.append(f32, samples[1..]);
    try std.testing.expectEqual(@as(usize, 50), complete.len);
    try std.testing.expectEqual(
        @as(u32, 6),
        std.mem.readInt(u32, complete[40..44], .little),
    );
    try std.testing.expectEqualSlices(u8, complete, incremental.bytes());
}

test "WAV writer dithers 24-bit and 32-bit integer PCM" {
    const spec_24 = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    var dither_24 = try pcm_dither.PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 24,
        .seed = 17,
    });
    var storage_24: [48]u8 = undefined;
    const encoded_24 = try writeInterleavedDithered(
        f64,
        &storage_24,
        &.{0.25},
        spec_24,
        &dither_24,
    );
    try std.testing.expectEqual(@as(usize, 48), encoded_24.len);
    try std.testing.expectEqual(@as(u8, 0), encoded_24[47]);

    const spec_32 = Spec{
        .sample_rate = 96_000,
        .channel_count = 1,
        .encoding = .pcm_i32,
    };
    var dither_32 = try pcm_dither.PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 32,
        .seed = 19,
    });
    var storage_32: [48]u8 = undefined;
    const encoded_32 = try writeInterleavedDithered(
        f64,
        &storage_32,
        &.{0.25},
        spec_32,
        &dither_32,
    );
    try std.testing.expectEqual(@as(usize, 48), encoded_32.len);
    try std.testing.expectEqual(@as(u16, 32), std.mem.readInt(
        u16,
        encoded_32[34..36],
        .little,
    ));
}

test "WAV writer supports deterministic incremental TPDF conversion" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
    };
    const samples = [_]f64{
        -1.0,  1.0,
        0.0,   0.0,
        0.125, -0.125,
    };
    var one_shot_bytes: [56]u8 = undefined;
    var one_shot_dither = try pcm_dither.PcmDither.init(.{
        .channel_count = 2,
        .bits_per_sample = 16,
        .seed = 42,
    });
    const one_shot = try writeInterleavedDithered(
        f64,
        &one_shot_bytes,
        &samples,
        spec,
        &one_shot_dither,
    );

    var incremental_bytes: [56]u8 = undefined;
    var writer = try Writer.init(&incremental_bytes, spec);
    var incremental_dither = try pcm_dither.PcmDither.init(.{
        .channel_count = 2,
        .bits_per_sample = 16,
        .seed = 42,
    });
    try writer.appendDithered(
        f64,
        samples[0..2],
        &incremental_dither,
    );
    try writer.appendDithered(
        f64,
        samples[2..],
        &incremental_dither,
    );
    try std.testing.expectEqualSlices(u8, one_shot, writer.bytes());
    try std.testing.expectEqual(
        @as(i16, -32_768),
        @as(i16, @bitCast(std.mem.readInt(
            u16,
            one_shot[44..46],
            .little,
        ))),
    );
    try std.testing.expectEqual(
        @as(i16, 32_767),
        @as(i16, @bitCast(std.mem.readInt(
            u16,
            one_shot[46..48],
            .little,
        ))),
    );
}

test "WAV dither path validates format before advancing state" {
    var dither = try pcm_dither.PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 16,
        .seed = 7,
    });
    const original = dither;
    var bytes: [48]u8 = undefined;
    try std.testing.expectError(
        error.DitherRequiresIntegerPcm,
        writeInterleavedDithered(
            f32,
            &bytes,
            &.{0.0},
            .{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = .ieee_f32,
            },
            &dither,
        ),
    );
    try std.testing.expectEqualDeep(original, dither);
}

test "WAV writer produces interleaved stereo float data" {
    var bytes: [60]u8 = undefined;
    const encoded = try writeInterleaved(
        f64,
        &bytes,
        &.{ 0.25, -0.25, 0.5, -0.5 },
        .{
            .sample_rate = 96_000,
            .channel_count = 2,
            .encoding = .ieee_f32,
        },
    );
    try std.testing.expectEqual(@as(usize, 60), encoded.len);
    try std.testing.expectEqual(@as(u16, 3), std.mem.readInt(
        u16,
        encoded[20..22],
        .little,
    ));
    const first: f32 = @bitCast(std.mem.readInt(
        u32,
        encoded[44..48],
        .little,
    ));
    const second: f32 = @bitCast(std.mem.readInt(
        u32,
        encoded[48..52],
        .little,
    ));
    try std.testing.expectEqual(@as(f32, 0.25), first);
    try std.testing.expectEqual(@as(f32, -0.25), second);
}

test "WAV writer validates before changing caller storage" {
    var bytes: [64]u8 = @splat(0xaa);
    const before = bytes;
    try std.testing.expectError(
        error.WavChannelLengthMismatch,
        writeInterleaved(
            f32,
            &bytes,
            &.{ 0.0, 0.5, 1.0 },
            .{
                .sample_rate = 48_000,
                .channel_count = 2,
                .encoding = .pcm_i16,
            },
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &bytes);
    try std.testing.expectError(
        error.WavOutputTooSmall,
        writeInterleaved(
            f32,
            bytes[0..44],
            &.{0.0},
            .{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = .pcm_i16,
            },
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &bytes);
}

test "incremental WAV writer matches one-shot output" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .ieee_f32,
    };
    const samples = [_]f64{ 0.25, -0.25, 0.5, -0.5 };
    var one_shot_storage: [60]u8 = undefined;
    const one_shot = try writeInterleaved(
        f64,
        &one_shot_storage,
        &samples,
        spec,
    );
    var incremental_storage: [60]u8 = undefined;
    var writer = try Writer.init(&incremental_storage, spec);
    try writer.append(f64, samples[0..2]);
    try writer.append(f64, samples[2..4]);
    try std.testing.expectEqualSlices(u8, one_shot, writer.bytes());
    try std.testing.expectEqual(@as(usize, 2), writer.frames_written);
}

test "incremental WAV append failure preserves encoded output" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
    };
    var storage: [48]u8 = @splat(0xaa);
    var writer = try Writer.init(&storage, spec);
    try writer.append(f32, &.{0.5});
    const before = storage;
    const before_count = writer.byte_count;
    try std.testing.expectError(
        error.WavOutputTooSmall,
        writer.append(f32, &.{ 0.25, 0.75 }),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectEqual(before_count, writer.byte_count);
    try std.testing.expectEqual(@as(usize, 1), writer.frames_written);
}

test "incremental WAV writer exposes a valid empty file" {
    var storage: [44]u8 = undefined;
    const writer = try Writer.init(
        &storage,
        .{
            .sample_rate = 44_100,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    try std.testing.expectEqual(@as(usize, 44), writer.bytes().len);
    try std.testing.expectEqual(@as(u32, 36), std.mem.readInt(
        u32,
        writer.bytes()[4..8],
        .little,
    ));
    try std.testing.expectEqual(@as(u32, 0), std.mem.readInt(
        u32,
        writer.bytes()[40..44],
        .little,
    ));
    try std.testing.expect(writer.valid());
}

test "incremental WAV writer contains malformed public state" {
    var storage: [44]u8 = undefined;
    var writer = try Writer.init(
        &storage,
        .{
            .sample_rate = 44_100,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    writer.byte_count = std.math.maxInt(usize);
    try std.testing.expect(!writer.valid());
    try std.testing.expectEqual(@as(usize, storage.len), writer.bytes().len);
    try std.testing.expectError(
        error.InvalidWavWriterState,
        writer.append(f32, &.{0.0}),
    );
}

test "file-backed WAV writer matches caller-buffer output" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .ieee_f32,
    };
    const samples = [_]f64{ 0.25, -0.25, 0.5, -0.5 };
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.append(f64, samples[0..2]);
    try writer.append(f64, samples[2..]);
    try writer.finalize();
    try std.testing.expect(writer.valid());

    var expected_storage: [60]u8 = undefined;
    const expected = try writeInterleaved(
        f64,
        &expected_storage,
        &samples,
        spec,
    );
    var actual: [60]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 0),
    );
    try std.testing.expectEqualSlices(u8, expected, &actual);
}

test "file-backed WAV writer replaces 24-bit padding across appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream-24.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    const samples = [_]f32{ 0.5, -0.5, 0.25 };
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.append(f32, samples[0..1]);
    try std.testing.expectEqual(
        @as(u64, 48),
        try file.length(std.testing.io),
    );
    try writer.append(f32, samples[1..]);
    try writer.finalize();

    var expected_storage: [54]u8 = undefined;
    const expected = try writeInterleaved(
        f32,
        &expected_storage,
        &samples,
        spec,
    );
    var actual: [54]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 0),
    );
    try std.testing.expectEqualSlices(u8, expected, &actual);
    try std.testing.expectEqual(@as(usize, 9), writer.data_bytes);
    try std.testing.expect(writer.valid());
}

test "file-backed WAV dither matches one-shot state across appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "dithered.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
    };
    const samples = [_]f32{ 0.25, -0.25, 0.5, -0.5 };
    const config = pcm_dither.Config{
        .channel_count = 2,
        .bits_per_sample = 16,
        .mode = .noise_shaped,
        .seed = 77,
    };
    var streamed_dither = try pcm_dither.PcmDither.init(config);
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.appendDithered(f32, samples[0..2], &streamed_dither);
    try writer.appendDithered(f32, samples[2..], &streamed_dither);
    try writer.finalize();

    var expected_storage: [52]u8 = undefined;
    var expected_dither = try pcm_dither.PcmDither.init(config);
    const expected = try writeInterleavedDithered(
        f32,
        &expected_storage,
        &samples,
        spec,
        &expected_dither,
    );
    var actual: [52]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 0),
    );
    try std.testing.expectEqualSlices(u8, expected, &actual);
    try std.testing.expectEqualDeep(expected_dither, streamed_dither);
}

test "file-backed WAV writer validates before changing the file" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.init(std.testing.io, file, .{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
    });
    var before: [44]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &before, 0);
    try std.testing.expectError(
        error.WavChannelLengthMismatch,
        writer.append(f32, &.{ 0.0, 0.5, 1.0 }),
    );
    try std.testing.expectEqual(
        @as(u64, 44),
        try file.length(std.testing.io),
    );
    var after: [44]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &after, 0);
    try std.testing.expectEqualSlices(u8, &before, &after);

    writer.byte_count = 45;
    try std.testing.expectError(
        error.InvalidWavFileWriterState,
        writer.finalize(),
    );
}

test "file-backed WAV writer embeds RIFF INFO metadata before audio" {
    const entries = [_]audio_metadata.Entry{
        .{ .id = audio_metadata.title, .value = "Metadata title" },
        .{ .id = audio_metadata.artist, .value = "Artist" },
    };
    const metadata_bytes =
        try audio_metadata.requiredRiffInfoBytes(&entries);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.initWithMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        &entries,
    );
    try writer.append(f32, &.{ 0.25, -0.25 });
    try writer.finalize();

    var bytes: [128]u8 = undefined;
    const length: usize = @intCast(try file.length(std.testing.io));
    try std.testing.expect(length <= bytes.len);
    _ = try file.readPositionalAll(
        std.testing.io,
        bytes[0..length],
        0,
    );
    const view = try audio_metadata.RiffInfoView.init(
        bytes[12..][0..metadata_bytes],
    );
    var iterator = view.iterator();
    for (entries) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.id, actual.id);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expectEqualStrings(
        "data",
        bytes[36 + metadata_bytes ..][0..4],
    );
    try std.testing.expectEqual(
        @as(u32, 4),
        std.mem.readInt(
            u32,
            bytes[40 + metadata_bytes ..][0..4],
            .little,
        ),
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(length - 8)),
        std.mem.readInt(u32, bytes[4..8], .little),
    );
}

test "file-backed WAV writer emits BWF and XML metadata before format" {
    const broadcast_metadata = @import("broadcast_metadata.zig");
    const metadata = audio_metadata.RiffMetadata{
        .broadcast = .{
            .description = "Production sound",
            .originator = "Recorder",
            .origination_date = .{
                .year = 2026,
                .month = 7,
                .day = 25,
            },
            .origination_time = .{
                .hour = 13,
                .minute = 45,
                .second = 2,
            },
            .time_reference = 96_000,
            .version = .version_2,
            .loudness = .{ .integrated = -2400 },
            .coding_history = "A=PCM,F=48000,W=16,M=mono\r\n",
        },
        .ixml = "<BWFXML><PROJECT>Feature</PROJECT></BWFXML>",
        .axml = "<audioFormatExtended/>",
        .info = &.{.{ .id = audio_metadata.title, .value = "Take 1" }},
    };
    const metadata_bytes =
        try audio_metadata.requiredRiffMetadataBytes(metadata);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "broadcast.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.initWithRiffMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
        metadata,
    );
    try writer.append(f32, &.{ 0.0, 0.5 });
    try writer.finalize();

    var bytes: [1024]u8 = undefined;
    const length: usize = @intCast(try file.length(std.testing.io));
    try std.testing.expect(length <= bytes.len);
    _ = try file.readPositionalAll(
        std.testing.io,
        bytes[0..length],
        0,
    );
    try std.testing.expectEqualStrings("bext", bytes[12..16]);
    const bext_payload =
        std.mem.readInt(u32, bytes[16..20], .little);
    const bext_bytes: usize = 8 + bext_payload + (bext_payload & 1);
    const broadcast = try broadcast_metadata.View.init(
        bytes[12..][0..bext_bytes],
    );
    try std.testing.expectEqual(
        @as(u64, 96_000),
        broadcast.time_reference,
    );
    var offset = 12 + bext_bytes;
    const ixml_bytes: usize =
        8 + std.mem.readInt(u32, bytes[offset + 4 ..][0..4], .little);
    const ixml = try audio_metadata.RiffXmlView.init(
        bytes[offset..][0 .. ixml_bytes + (ixml_bytes & 1)],
    );
    try std.testing.expectEqual(audio_metadata.RiffXmlKind.ixml, ixml.kind);
    offset = 12 + metadata_bytes;
    try std.testing.expectEqualStrings("fmt ", bytes[offset..][0..4]);
    try std.testing.expectEqualStrings(
        "data",
        bytes[offset + 24 ..][0..4],
    );
}

test "file-backed WAV writer rejects mismatched ADM track counts before mutation" {
    const entries = [_]@import("adm.zig").Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
    }};
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "mismatched-adm.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.setLength(std.testing.io, 7);
    try std.testing.expectError(
        error.AdmTrackCountMismatch,
        FileWriter.initWithRiffMetadata(
            std.testing.io,
            file,
            .{
                .sample_rate = 48_000,
                .channel_count = 2,
                .encoding = .pcm_i16,
            },
            .{
                .channel_allocation = .{
                    .num_tracks = 1,
                    .entries = &entries,
                },
            },
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 7),
        try file.length(std.testing.io),
    );
}
