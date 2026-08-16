const std = @import("std");
const audio_metadata = @import("audio_metadata.zig");
const file_writer_io = @import("file_writer_io.zig");
const pcm_dither = @import("pcm_dither.zig");
const pcm_encode = @import("pcm_encode.zig");

pub const Encoding = enum {
    pcm_i16,
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
    data_bytes: usize = 0,
    byte_count: usize = 54,

    /// The destination storage must outlive the writer.
    pub fn init(destination: []u8, spec: Spec) !Writer {
        const required = try requiredBytes(spec, 0);
        if (destination.len < required) return error.AiffOutputTooSmall;
        writeHeader(destination, spec, 0, 0, @intCast(required - 8));
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
        if (!self.valid()) return error.InvalidAiffWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.AiffSizeOverflow;
        if (next_frames > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
        const added_bytes = std.math.mul(
            usize,
            samples.len,
            sampleBytes(self.spec.encoding),
        ) catch return error.AiffSizeOverflow;
        const next_data_bytes = std.math.add(
            usize,
            self.data_bytes,
            added_bytes,
        ) catch return error.AiffSizeOverflow;
        const required = try requiredBytes(self.spec, next_frames);
        if (self.destination.len < required)
            return error.AiffOutputTooSmall;

        encodeSamples(
            Sample,
            self.destination[54 + self.data_bytes ..][0..added_bytes],
            samples,
            self.spec.encoding,
        );
        if (next_data_bytes & 1 != 0)
            self.destination[54 + next_data_bytes] = 0;
        self.frames_written = next_frames;
        self.data_bytes = next_data_bytes;
        self.byte_count = required;
        writeHeader(
            self.destination,
            self.spec,
            @intCast(next_frames),
            @intCast(next_data_bytes),
            @intCast(required - 8),
        );
    }

    pub fn bytes(self: *const Writer) []const u8 {
        if (!self.valid()) return &.{};
        return self.destination[0..self.byte_count];
    }

    pub fn valid(self: *const Writer) bool {
        if (self.byte_count < 54 or self.byte_count > self.destination.len)
            return false;
        const expected = requiredBytes(
            self.spec,
            self.frames_written,
        ) catch return false;
        const frame_bytes = @as(usize, self.spec.channel_count) *
            sampleBytes(self.spec.encoding);
        const expected_data = std.math.mul(
            usize,
            self.frames_written,
            frame_bytes,
        ) catch return false;
        return self.byte_count == expected and
            self.data_bytes == expected_data;
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
    data_offset: usize = 54,
    byte_count: usize = 54,
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
            &.{},
            operations,
        );
    }

    pub fn initWithMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: []const audio_metadata.Entry,
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
        metadata: []const audio_metadata.Entry,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        try validateSpec(spec);
        const metadata_bytes =
            try audio_metadata.requiredAiffTextBytes(metadata);
        const data_offset = std.math.add(
            usize,
            54,
            metadata_bytes,
        ) catch return error.AiffSizeOverflow;
        if (data_offset - 8 > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
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
        if (metadata.len != 0) {
            _ = try audio_metadata.writeAiffTextFile(
                io,
                file,
                38,
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
        if (!self.valid()) return error.InvalidAiffFileWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.AiffSizeOverflow;
        if (next_frames > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
        const added_bytes = std.math.mul(
            usize,
            samples.len,
            sampleBytes(self.spec.encoding),
        ) catch return error.AiffSizeOverflow;
        const next_data_bytes = std.math.add(
            usize,
            self.data_bytes,
            added_bytes,
        ) catch return error.AiffSizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            usize,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.AiffSizeOverflow;
        if (next_byte_count - 8 > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
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
        self.data_bytes = next_data_bytes;
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
        if (!self.valid()) return error.InvalidAiffFileWriterState;
        try validateDitheredSamples(Sample, samples, self.spec, dither);
        const added_frames = samples.len / self.spec.channel_count;
        const next_frames = std.math.add(
            usize,
            self.frames_written,
            added_frames,
        ) catch return error.AiffSizeOverflow;
        if (next_frames > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
        const added_bytes = std.math.mul(
            usize,
            samples.len,
            sampleBytes(self.spec.encoding),
        ) catch return error.AiffSizeOverflow;
        const next_data_bytes = std.math.add(
            usize,
            self.data_bytes,
            added_bytes,
        ) catch return error.AiffSizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            usize,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.AiffSizeOverflow;
        if (next_byte_count - 8 > std.math.maxInt(u32))
            return error.AiffSizeOverflow;
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
            .big,
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
        if (!self.recoverable()) return error.InvalidAiffFileWriterState;
        try self.recover();
        try self.operations.sync(self.io, self.file);
    }

    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidAiffFileWriterState;
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
            54,
            self.metadata_bytes,
        ) catch return false;
        const frame_bytes = std.math.mul(
            usize,
            @as(usize, self.spec.channel_count),
            sampleBytes(self.spec.encoding),
        ) catch return false;
        const expected_data = std.math.mul(
            usize,
            self.frames_written,
            frame_bytes,
        ) catch return false;
        return self.data_offset == expected_data_offset and
            self.byte_count == expected and
            self.data_bytes == expected_data;
    }

    fn writeCurrentHeaders(self: *const FileWriter) !void {
        var prefix: [38]u8 = undefined;
        writePrefix(
            &prefix,
            self.spec,
            @intCast(self.frames_written),
            @intCast(self.byte_count - 8),
        );
        var sound_header: [16]u8 = undefined;
        writeSoundHeader(
            &sound_header,
            @intCast(self.data_bytes),
        );
        try self.operations.writeAt(self.io, self.file, 0, &prefix);
        try self.operations.writeAt(
            self.io,
            self.file,
            @intCast(self.data_offset - sound_header.len),
            &sound_header,
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
    const frame_bytes = std.math.mul(
        usize,
        @as(usize, spec.channel_count),
        sampleBytes(spec.encoding),
    ) catch return error.AiffSizeOverflow;
    const data_bytes = std.math.mul(
        usize,
        frame_count,
        frame_bytes,
    ) catch return error.AiffSizeOverflow;
    if (data_bytes > std.math.maxInt(u32) - 8 or
        data_bytes > std.math.maxInt(u32) - 46)
        return error.AiffSizeOverflow;
    return 54 + data_bytes + (data_bytes & 1);
}

pub fn writeInterleaved(
    comptime Sample: type,
    destination: []u8,
    samples: []const Sample,
    spec: Spec,
) ![]const u8 {
    try validateSamples(Sample, samples, spec);
    const frame_count = samples.len / spec.channel_count;
    if (frame_count > std.math.maxInt(u32))
        return error.AiffSizeOverflow;
    const required = try requiredBytes(spec, frame_count);
    if (destination.len < required) return error.AiffOutputTooSmall;

    const data_bytes = samples.len * sampleBytes(spec.encoding);
    writeHeader(
        destination,
        spec,
        @intCast(frame_count),
        @intCast(data_bytes),
        @intCast(required - 8),
    );
    encodeSamples(
        Sample,
        destination[54 .. 54 + data_bytes],
        samples,
        spec.encoding,
    );
    if (data_bytes & 1 != 0) destination[required - 1] = 0;
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
    if (frame_count > std.math.maxInt(u32))
        return error.AiffSizeOverflow;
    const required = try requiredBytes(spec, frame_count);
    if (destination.len < required) return error.AiffOutputTooSmall;

    const data_bytes = samples.len * sampleBytes(spec.encoding);
    writeHeader(
        destination,
        spec,
        @intCast(frame_count),
        @intCast(data_bytes),
        @intCast(required - 8),
    );
    try pcm_encode.encodeDithered(
        Sample,
        destination[54 .. 54 + data_bytes],
        samples,
        .big,
        dither,
    );
    if (data_bytes & 1 != 0) destination[required - 1] = 0;
    return destination[0..required];
}

fn writeHeader(
    destination: []u8,
    spec: Spec,
    frame_count: u32,
    data_bytes: u32,
    form_bytes: u32,
) void {
    writePrefix(
        destination[0..38],
        spec,
        frame_count,
        form_bytes,
    );
    writeSoundHeader(destination[38..54], data_bytes);
}

fn writePrefix(
    destination: []u8,
    spec: Spec,
    frame_count: u32,
    form_bytes: u32,
) void {
    @memcpy(destination[0..4], "FORM");
    std.mem.writeInt(u32, destination[4..8], form_bytes, .big);
    @memcpy(destination[8..12], "AIFF");
    @memcpy(destination[12..16], "COMM");
    std.mem.writeInt(u32, destination[16..20], 18, .big);
    std.mem.writeInt(u16, destination[20..22], spec.channel_count, .big);
    std.mem.writeInt(u32, destination[22..26], frame_count, .big);
    std.mem.writeInt(
        u16,
        destination[26..28],
        @intCast(sampleBytes(spec.encoding) * 8),
        .big,
    );
    writeExtendedSampleRate(destination[28..38], spec.sample_rate);
}

fn writeSoundHeader(destination: []u8, data_bytes: u32) void {
    @memcpy(destination[0..4], "SSND");
    std.mem.writeInt(u32, destination[4..8], data_bytes + 8, .big);
    @memset(destination[8..16], 0);
}

fn writeExtendedSampleRate(destination: []u8, sample_rate: u32) void {
    const exponent: u5 = @intCast(31 - @clz(sample_rate));
    const exponent_bits: u16 = 16_383 + @as(u16, exponent);
    const shift: u6 = 63 - @as(u6, exponent);
    const mantissa = @as(u64, sample_rate) << shift;
    std.mem.writeInt(u16, destination[0..2], exponent_bits, .big);
    std.mem.writeInt(u64, destination[2..10], mantissa, .big);
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
        .big,
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
        .big,
    );
}

fn validateSamples(
    comptime Sample: type,
    samples: []const Sample,
    spec: Spec,
) !void {
    if (Sample != f32 and Sample != f64)
        @compileError("AIFF writing supports f32 and f64 input");
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.AiffChannelLengthMismatch;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.NonFiniteAiffSample;
    }
}

fn validateDitheredSamples(
    comptime Sample: type,
    samples: []const Sample,
    spec: Spec,
    dither: *const pcm_dither.PcmDither,
) !void {
    try validateSamples(Sample, samples, spec);
    try dither.validate();
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
        return error.InvalidAiffSpec;
}

fn sampleBytes(encoding: Encoding) usize {
    return pcm_encode.byteCount(pcmEncoding(encoding));
}

fn encodingBits(encoding: Encoding) u6 {
    return pcm_encode.bitCount(pcmEncoding(encoding));
}

fn pcmEncoding(encoding: Encoding) pcm_encode.Encoding {
    return switch (encoding) {
        .pcm_i16 => .pcm_i16,
        .pcm_i24 => .pcm_i24,
        .pcm_i32 => .pcm_i32,
    };
}

test "AIFF dither path covers 16 24 and 32 bit PCM" {
    inline for ([_]Encoding{ .pcm_i16, .pcm_i24, .pcm_i32 }) |encoding| {
        const bits = encodingBits(encoding);
        var dither = try pcm_dither.PcmDither.init(.{
            .channel_count = 1,
            .bits_per_sample = bits,
            .mode = .noise_shaped,
            .seed = 99,
        });
        var storage: [66]u8 = undefined;
        const encoded = try writeInterleavedDithered(
            f64,
            &storage,
            &.{ -1.0, 0.0, 1.0 },
            .{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = encoding,
            },
            &dither,
        );
        try std.testing.expectEqualStrings("FORM", encoded[0..4]);
        try std.testing.expectEqual(
            try requiredBytes(.{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = encoding,
            }, 3),
            encoded.len,
        );
    }
}

test "AIFF writer produces bounded mono PCM16" {
    var storage: [60]u8 = undefined;
    const encoded = try writeInterleaved(
        f32,
        &storage,
        &.{ -1.0, 0.0, 1.0 },
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    try std.testing.expectEqual(@as(usize, 60), encoded.len);
    try std.testing.expectEqualStrings("FORM", encoded[0..4]);
    try std.testing.expectEqualStrings("AIFF", encoded[8..12]);
    try std.testing.expectEqualStrings("COMM", encoded[12..16]);
    try std.testing.expectEqualStrings("SSND", encoded[38..42]);
    try std.testing.expectEqual(@as(u32, 3), std.mem.readInt(
        u32,
        encoded[22..26],
        .big,
    ));
    try std.testing.expectEqual(@as(i16, -32_767), @as(i16, @bitCast(
        std.mem.readInt(u16, encoded[54..56], .big),
    )));
    try std.testing.expectEqual(@as(u16, 0x400e), std.mem.readInt(
        u16,
        encoded[28..30],
        .big,
    ));
    try std.testing.expectEqual(
        @as(u64, 0xbb80_0000_0000_0000),
        std.mem.readInt(u64, encoded[30..38], .big),
    );

    var pcm32_storage: [58]u8 = undefined;
    const pcm32 = try writeInterleaved(
        f32,
        &pcm32_storage,
        &.{1.0},
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i32,
        },
    );
    try std.testing.expectEqual(@as(i32, 2_147_483_647), @as(i32, @bitCast(
        std.mem.readInt(u32, pcm32[54..58], .big),
    )));
}

test "AIFF writer produces interleaved PCM24 and pads odd data" {
    var storage: [66]u8 = undefined;
    const encoded = try writeInterleaved(
        f64,
        &storage,
        &.{ 0.25, -0.25, 0.5, -0.5 },
        .{
            .sample_rate = 96_000,
            .channel_count = 2,
            .encoding = .pcm_i24,
        },
    );
    try std.testing.expectEqual(@as(usize, 66), encoded.len);
    try std.testing.expectEqual(@as(u16, 24), std.mem.readInt(
        u16,
        encoded[26..28],
        .big,
    ));
    try std.testing.expectEqual(@as(u32, 20), std.mem.readInt(
        u32,
        encoded[42..46],
        .big,
    ));
    try std.testing.expectEqual(@as(u8, 0x20), encoded[54]);
    try std.testing.expectEqual(@as(u8, 0xe0), encoded[57]);

    var odd_storage: [58]u8 = undefined;
    const odd = try writeInterleaved(
        f32,
        &odd_storage,
        &.{0.5},
        .{
            .sample_rate = 44_100,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
    );
    try std.testing.expectEqual(@as(usize, 58), odd.len);
    try std.testing.expectEqual(@as(u8, 0), odd[57]);
}

test "AIFF writer validates before changing caller storage" {
    var storage: [64]u8 = @splat(0xaa);
    const before = storage;
    try std.testing.expectError(
        error.AiffChannelLengthMismatch,
        writeInterleaved(
            f32,
            &storage,
            &.{ 0.0, 0.5, 1.0 },
            .{
                .sample_rate = 48_000,
                .channel_count = 2,
                .encoding = .pcm_i16,
            },
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectError(
        error.AiffOutputTooSmall,
        writeInterleaved(
            f32,
            storage[0..54],
            &.{0.0},
            .{
                .sample_rate = 48_000,
                .channel_count = 1,
                .encoding = .pcm_i16,
            },
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
}

test "incremental AIFF writer matches one-shot output across padding" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    const samples = [_]f32{ 0.25, -0.25 };
    var one_shot_storage: [60]u8 = undefined;
    const one_shot = try writeInterleaved(
        f32,
        &one_shot_storage,
        &samples,
        spec,
    );
    var incremental_storage: [60]u8 = undefined;
    var writer = try Writer.init(&incremental_storage, spec);
    try writer.append(f32, samples[0..1]);
    try std.testing.expectEqual(@as(usize, 58), writer.bytes().len);
    try writer.append(f32, samples[1..2]);
    try std.testing.expectEqualSlices(u8, one_shot, writer.bytes());
    try std.testing.expectEqual(@as(usize, 2), writer.frames_written);
}

test "incremental AIFF append failure preserves encoded output" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
    };
    var storage: [58]u8 = @splat(0xaa);
    var writer = try Writer.init(&storage, spec);
    try writer.append(f32, &.{0.5});
    const before = storage;
    try std.testing.expectError(
        error.AiffOutputTooSmall,
        writer.append(f32, &.{ 0.25, 0.75 }),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectEqual(@as(usize, 1), writer.frames_written);
    try std.testing.expect(writer.valid());
}

test "incremental AIFF writer contains malformed public state" {
    var storage: [54]u8 = undefined;
    var writer = try Writer.init(
        &storage,
        .{
            .sample_rate = 44_100,
            .channel_count = 1,
            .encoding = .pcm_i16,
        },
    );
    writer.data_bytes = std.math.maxInt(usize);
    try std.testing.expect(!writer.valid());
    try std.testing.expectEqual(@as(usize, 0), writer.bytes().len);
    try std.testing.expectError(
        error.InvalidAiffWriterState,
        writer.append(f32, &.{0.0}),
    );
}

test "file-backed AIFF writer matches caller-buffer output across padding" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.aiff",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    const samples = [_]f32{ 0.25, -0.25 };
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.append(f32, samples[0..1]);
    try std.testing.expectEqual(@as(usize, 58), writer.byte_count);
    try writer.append(f32, samples[1..]);
    try writer.finalize();
    try std.testing.expect(writer.valid());

    var expected_storage: [60]u8 = undefined;
    const expected = try writeInterleaved(
        f32,
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

test "file-backed AIFF dither matches one-shot state across appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "dithered.aiff",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i24,
    };
    const samples = [_]f64{ 0.25, -0.25 };
    const config = pcm_dither.Config{
        .channel_count = 1,
        .bits_per_sample = 24,
        .mode = .noise_shaped,
        .seed = 88,
    };
    var streamed_dither = try pcm_dither.PcmDither.init(config);
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.appendDithered(f64, samples[0..1], &streamed_dither);
    try writer.appendDithered(f64, samples[1..], &streamed_dither);
    try writer.finalize();

    var expected_storage: [60]u8 = undefined;
    var expected_dither = try pcm_dither.PcmDither.init(config);
    const expected = try writeInterleavedDithered(
        f64,
        &expected_storage,
        &samples,
        spec,
        &expected_dither,
    );
    var actual: [60]u8 = undefined;
    try std.testing.expectEqual(
        actual.len,
        try file.readPositionalAll(std.testing.io, &actual, 0),
    );
    try std.testing.expectEqualSlices(u8, expected, &actual);
    try std.testing.expectEqualDeep(expected_dither, streamed_dither);
}

test "file-backed AIFF writer validates before changing the file" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional.aiff",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.init(std.testing.io, file, .{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
    });
    var before: [54]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &before, 0);
    try std.testing.expectError(
        error.AiffChannelLengthMismatch,
        writer.append(f32, &.{ 0.0, 0.5, 1.0 }),
    );
    try std.testing.expectEqual(
        @as(u64, 54),
        try file.length(std.testing.io),
    );
    var after: [54]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &after, 0);
    try std.testing.expectEqualSlices(u8, &before, &after);

    writer.data_bytes = 1;
    try std.testing.expectError(
        error.InvalidAiffFileWriterState,
        writer.finalize(),
    );
}

test "file-backed AIFF writer embeds text metadata before sound data" {
    const entries = [_]audio_metadata.Entry{
        .{ .id = audio_metadata.aiff_name, .value = "Metadata title" },
        .{ .id = audio_metadata.aiff_author, .value = "Artist" },
    };
    const metadata_bytes =
        try audio_metadata.requiredAiffTextBytes(&entries);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata.aiff",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.initWithMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        &entries,
    );
    try writer.append(f32, &.{0.25});
    try writer.finalize();

    var bytes: [128]u8 = undefined;
    const length: usize = @intCast(try file.length(std.testing.io));
    try std.testing.expect(length <= bytes.len);
    _ = try file.readPositionalAll(
        std.testing.io,
        bytes[0..length],
        0,
    );
    var iterator = try audio_metadata.AiffTextIterator.init(
        bytes[38..][0..metadata_bytes],
    );
    for (entries) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.id, actual.id);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expectEqualStrings(
        "SSND",
        bytes[38 + metadata_bytes ..][0..4],
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(length - 8)),
        std.mem.readInt(u32, bytes[4..8], .big),
    );
}
