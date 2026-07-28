const std = @import("std");
const audio_metadata = @import("audio_metadata.zig");
const file_writer_io = @import("file_writer_io.zig");
const pcm_dither = @import("pcm_dither.zig");
const pcm_encode = @import("pcm_encode.zig");

pub const Encoding = enum {
    pcm_i16,
    pcm_i24,
    pcm_i32,
    ieee_f32,
};

pub const Container = enum {
    rf64,
    bw64,

    fn id(self: Container) *const [4]u8 {
        return switch (self) {
            .rf64 => "RF64",
            .bw64 => "BW64",
        };
    }
};

pub const Spec = struct {
    sample_rate: u32,
    channel_count: u16,
    encoding: Encoding,
};

pub const header_bytes: u64 = 80;

pub fn requiredBytes(spec: Spec, frame_count: u64) !u64 {
    try validateSpec(spec);
    const frame_bytes = try frameBytes(spec);
    const data_bytes = std.math.mul(
        u64,
        frame_count,
        frame_bytes,
    ) catch return error.Rf64SizeOverflow;
    const padded_data = std.math.add(
        u64,
        data_bytes,
        data_bytes & 1,
    ) catch return error.Rf64SizeOverflow;
    return std.math.add(
        u64,
        header_bytes,
        padded_data,
    ) catch return error.Rf64SizeOverflow;
}

pub fn makeHeader(spec: Spec, frame_count: u64) ![header_bytes]u8 {
    return makeContainerHeader(.rf64, spec, frame_count);
}

pub fn makeBw64Header(spec: Spec, frame_count: u64) ![header_bytes]u8 {
    return makeContainerHeader(.bw64, spec, frame_count);
}

fn makeContainerHeader(
    container: Container,
    spec: Spec,
    frame_count: u64,
) ![header_bytes]u8 {
    try validateSpec(spec);
    const data_bytes = std.math.mul(
        u64,
        frame_count,
        try frameBytes(spec),
    ) catch return error.Rf64SizeOverflow;
    const total_bytes = try requiredBytes(spec, frame_count);
    var header: [header_bytes]u8 = undefined;
    writeHeader(
        &header,
        container,
        spec,
        frame_count,
        data_bytes,
        total_bytes - 8,
    );
    return header;
}

pub const FileWriter = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    container: Container = .rf64,
    spec: Spec,
    frames_written: u64 = 0,
    data_bytes: u64 = 0,
    metadata_bytes: u64 = 0,
    data_offset: u64 = header_bytes,
    byte_count: u64 = header_bytes,
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
            .rf64,
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
            .rf64,
            spec,
            metadata,
            .{},
        );
    }

    pub fn initBw64(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
    ) !FileWriter {
        return initBw64WithOperations(io, file, spec, .{});
    }

    pub fn initBw64WithOperations(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        return initWithRiffMetadataAndOperations(
            io,
            file,
            .bw64,
            spec,
            .{},
            operations,
        );
    }

    pub fn initBw64WithMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: []const audio_metadata.Entry,
    ) !FileWriter {
        return initBw64WithRiffMetadata(
            io,
            file,
            spec,
            .{ .info = metadata },
        );
    }

    pub fn initBw64WithRiffMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        metadata: audio_metadata.RiffMetadata,
    ) !FileWriter {
        return initWithRiffMetadataAndOperations(
            io,
            file,
            .bw64,
            spec,
            metadata,
            .{},
        );
    }

    fn initWithRiffMetadataAndOperations(
        io: std.Io,
        file: std.Io.File,
        container: Container,
        spec: Spec,
        metadata: audio_metadata.RiffMetadata,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        try validateSpec(spec);
        try audio_metadata.validateRiffMetadataChannelCount(
            metadata,
            spec.channel_count,
        );
        const metadata_bytes: u64 = @intCast(
            try audio_metadata.requiredRiffMetadataBytes(metadata),
        );
        const data_offset = std.math.add(
            u64,
            header_bytes,
            metadata_bytes,
        ) catch return error.Rf64SizeOverflow;
        var writer = FileWriter{
            .io = io,
            .file = file,
            .operations = operations,
            .container = container,
            .spec = spec,
            .metadata_bytes = metadata_bytes,
            .data_offset = data_offset,
            .byte_count = data_offset,
        };
        try operations.setLength(io, file, data_offset);
        try writer.writeCurrentHeaders();
        if (metadata_bytes != 0) {
            _ = try audio_metadata.writeRiffMetadataFile(
                io,
                file,
                48,
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
        if (!self.valid()) return error.InvalidRf64FileWriterState;
        try validateSamples(Sample, samples, self.spec);
        const added_frames: u64 = @intCast(
            samples.len / self.spec.channel_count,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_written,
            added_frames,
        ) catch return error.Rf64SizeOverflow;
        const added_bytes = std.math.mul(
            u64,
            @intCast(samples.len),
            sampleBytes(self.spec.encoding),
        ) catch return error.Rf64SizeOverflow;
        const next_data_bytes = std.math.add(
            u64,
            self.data_bytes,
            added_bytes,
        ) catch return error.Rf64SizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            u64,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.Rf64SizeOverflow;
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
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
        if (!self.valid()) return error.InvalidRf64FileWriterState;
        try validateDitheredSamples(Sample, samples, self.spec, dither);
        const added_frames: u64 = @intCast(
            samples.len / self.spec.channel_count,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_written,
            added_frames,
        ) catch return error.Rf64SizeOverflow;
        const added_bytes = std.math.mul(
            u64,
            @intCast(samples.len),
            sampleBytes(self.spec.encoding),
        ) catch return error.Rf64SizeOverflow;
        const next_data_bytes = std.math.add(
            u64,
            self.data_bytes,
            added_bytes,
        ) catch return error.Rf64SizeOverflow;
        const encoded_bytes = try requiredBytes(self.spec, next_frames);
        const next_byte_count = std.math.add(
            u64,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return error.Rf64SizeOverflow;
        const checkpoint = try file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
            2,
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
        if (!self.recoverable()) return error.InvalidRf64FileWriterState;
        try self.recover();
        try self.file.sync(self.io);
    }

    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable()) return error.InvalidRf64FileWriterState;
        const checkpoint = file_writer_io.Checkpoint.aligned(
            self.byte_count,
            self.data_offset + self.data_bytes,
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
        const expected_bytes = std.math.add(
            u64,
            encoded_bytes,
            self.metadata_bytes,
        ) catch return false;
        const expected_data_offset = std.math.add(
            u64,
            header_bytes,
            self.metadata_bytes,
        ) catch return false;
        const expected_data = std.math.mul(
            u64,
            self.frames_written,
            frameBytes(self.spec) catch return false,
        ) catch return false;
        return self.data_offset == expected_data_offset and
            self.byte_count == expected_bytes and
            self.data_bytes == expected_data;
    }

    fn writeCurrentHeaders(self: *const FileWriter) !void {
        var container_prefix: [48]u8 = undefined;
        writeContainerPrefix(
            &container_prefix,
            self.container,
            self.frames_written,
            self.data_bytes,
            self.byte_count - 8,
        );
        var format_chunk: [24]u8 = undefined;
        writeFormatChunk(&format_chunk, self.spec);
        var data_header: [8]u8 = undefined;
        writeDataHeader(&data_header);
        try self.operations.writeAt(
            self.io,
            self.file,
            0,
            &container_prefix,
        );
        try self.operations.writeAt(
            self.io,
            self.file,
            48 + self.metadata_bytes,
            &format_chunk,
        );
        try self.operations.writeAt(
            self.io,
            self.file,
            self.data_offset - data_header.len,
            &data_header,
        );
    }

    fn writeDataPadding(self: *const FileWriter) !void {
        _ = try file_writer_io.writeAlignmentPadding(
            self.operations,
            self.io,
            self.file,
            self.data_offset + self.data_bytes,
            2,
        );
    }
};

fn writeHeader(
    destination: []u8,
    container: Container,
    spec: Spec,
    frame_count: u64,
    data_bytes: u64,
    riff_bytes: u64,
) void {
    writePrefix(
        destination[0..72],
        container,
        spec,
        frame_count,
        data_bytes,
        riff_bytes,
    );
    writeDataHeader(destination[72..80]);
}

fn writePrefix(
    destination: []u8,
    container: Container,
    spec: Spec,
    frame_count: u64,
    data_bytes: u64,
    riff_bytes: u64,
) void {
    writeContainerPrefix(
        destination[0..48],
        container,
        frame_count,
        data_bytes,
        riff_bytes,
    );
    writeFormatChunk(destination[48..72], spec);
}

fn writeContainerPrefix(
    destination: []u8,
    container: Container,
    frame_count: u64,
    data_bytes: u64,
    riff_bytes: u64,
) void {
    @memcpy(destination[0..4], container.id());
    @memset(destination[4..8], 0xff);
    @memcpy(destination[8..12], "WAVE");
    @memcpy(destination[12..16], "ds64");
    std.mem.writeInt(u32, destination[16..20], 28, .little);
    std.mem.writeInt(u64, destination[20..28], riff_bytes, .little);
    std.mem.writeInt(u64, destination[28..36], data_bytes, .little);
    std.mem.writeInt(u64, destination[36..44], frame_count, .little);
    std.mem.writeInt(u32, destination[44..48], 0, .little);
}

fn writeFormatChunk(destination: []u8, spec: Spec) void {
    const bytes_per_sample = sampleBytes(spec.encoding);
    const block_align: u16 = @intCast(
        @as(u64, spec.channel_count) * bytes_per_sample,
    );
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

fn writeDataHeader(destination: []u8) void {
    @memcpy(destination[0..4], "data");
    @memset(destination[4..8], 0xff);
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
        @compileError("RF64 writing supports f32 and f64 input");
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.Rf64ChannelLengthMismatch;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.NonFiniteRf64Sample;
        if (spec.encoding == .ieee_f32 and
            !std.math.isFinite(@as(f32, @floatCast(sample))))
            return error.NonFiniteRf64Sample;
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
        return error.InvalidRf64Spec;
}

fn frameBytes(spec: Spec) !u64 {
    return std.math.mul(
        u64,
        spec.channel_count,
        sampleBytes(spec.encoding),
    ) catch return error.Rf64SizeOverflow;
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

test "RF64 header stores 64-bit sizes beyond classic RIFF limits" {
    const spec = Spec{
        .sample_rate = 192_000,
        .channel_count = 2,
        .encoding = .pcm_i32,
    };
    const frames: u64 = 1_000_000_000;
    const header = try makeHeader(spec, frames);
    try std.testing.expectEqualStrings("RF64", header[0..4]);
    try std.testing.expectEqualStrings("ds64", header[12..16]);
    try std.testing.expectEqual(
        @as(u64, 8_000_000_000),
        std.mem.readInt(u64, header[28..36], .little),
    );
    try std.testing.expectEqual(
        frames,
        std.mem.readInt(u64, header[36..44], .little),
    );
    try std.testing.expectEqual(
        @as(u64, 8_000_000_072),
        std.mem.readInt(u64, header[20..28], .little),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0xff, 0xff, 0xff, 0xff },
        header[76..80],
    );
}

test "BW64 header shares the 64-bit size contract with its own signature" {
    const header = try makeBw64Header(
        .{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = .pcm_i24,
        },
        3,
    );
    try std.testing.expectEqualStrings("BW64", header[0..4]);
    try std.testing.expectEqualStrings("ds64", header[12..16]);
    try std.testing.expectEqual(@as(u64, 18), std.mem.readInt(
        u64,
        header[28..36],
        .little,
    ));
    try std.testing.expectEqual(@as(u64, 3), std.mem.readInt(
        u64,
        header[36..44],
        .little,
    ));
}

test "file-backed RF64 writer streams PCM24 with word padding" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.rf64.wav",
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
    try std.testing.expectEqual(@as(u64, 84), writer.byte_count);
    try writer.append(f32, &.{-0.5});
    try writer.finalize();
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(u64, 86), writer.byte_count);

    var bytes: [86]u8 = undefined;
    try std.testing.expectEqual(
        bytes.len,
        try file.readPositionalAll(std.testing.io, &bytes, 0),
    );
    try std.testing.expectEqualStrings("RF64", bytes[0..4]);
    try std.testing.expectEqual(
        @as(u64, 6),
        std.mem.readInt(u64, bytes[28..36], .little),
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0x00, 0x00, 0x40, 0x00, 0x00, 0xc0 },
        bytes[80..86],
    );
}

test "file-backed RF64 dither preserves bytes and state across appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "dithered.rf64",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i24,
    };
    const samples = [_]f32{ 0.25, -0.25, 0.5, -0.5 };
    const config = pcm_dither.Config{
        .channel_count = 2,
        .bits_per_sample = 24,
        .mode = .noise_shaped,
        .seed = 99,
    };
    var streamed_dither = try pcm_dither.PcmDither.init(config);
    var writer = try FileWriter.init(std.testing.io, file, spec);
    try writer.appendDithered(f32, samples[0..2], &streamed_dither);
    try writer.appendDithered(f32, samples[2..], &streamed_dither);
    try writer.finalize();

    var expected: [12]u8 = undefined;
    var expected_dither = try pcm_dither.PcmDither.init(config);
    try pcm_encode.encodeDithered(
        f32,
        &expected,
        &samples,
        .little,
        &expected_dither,
    );
    var actual: [12]u8 = undefined;
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

test "RF64 writer validates append transactionally" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional.rf64.wav",
        .{},
    );
    defer file.close(std.testing.io);
    var writer = try FileWriter.init(std.testing.io, file, .{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .ieee_f32,
    });
    try std.testing.expectError(
        error.Rf64ChannelLengthMismatch,
        writer.append(f32, &.{ 0.0, 0.5, 1.0 }),
    );
    try std.testing.expectEqual(
        header_bytes,
        try file.length(std.testing.io),
    );
    try std.testing.expect(writer.valid());
}

test "file-backed RF64 writer embeds RIFF INFO metadata" {
    const entries = [_]audio_metadata.Entry{
        .{ .id = audio_metadata.title, .value = "RF64 title" },
        .{ .id = audio_metadata.software, .value = "zig-vst3" },
    };
    const metadata_bytes =
        try audio_metadata.requiredRiffInfoBytes(&entries);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata.rf64.wav",
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
    try writer.append(f32, &.{0.25});
    try writer.finalize();

    var bytes: [160]u8 = undefined;
    const length: usize = @intCast(try file.length(std.testing.io));
    try std.testing.expect(length <= bytes.len);
    _ = try file.readPositionalAll(
        std.testing.io,
        bytes[0..length],
        0,
    );
    _ = try audio_metadata.RiffInfoView.init(
        bytes[48..][0..metadata_bytes],
    );
    try std.testing.expectEqualStrings(
        "data",
        bytes[72 + metadata_bytes ..][0..4],
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(length - 8)),
        std.mem.readInt(u64, bytes[20..28], .little),
    );
}
