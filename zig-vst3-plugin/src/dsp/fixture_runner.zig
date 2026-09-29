const std = @import("std");

pub fn BlockProcessor(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64) @compileError("BlockProcessor supports f32 and f64 samples");
    return struct {
        const Self = @This();
        const ProcessFn = *const fn (*anyopaque, []const Sample, []Sample) void;
        const ResetFn = *const fn (*anyopaque) void;

        context: *anyopaque,
        process_fn: ProcessFn,
        reset_fn: ResetFn,

        pub fn init(comptime Context: type, context: *Context) Self {
            if (!@hasDecl(Context, "processBlock") or !@hasDecl(Context, "reset")) {
                @compileError("block processor context requires processBlock and reset declarations");
            }
            return .{
                .context = @ptrCast(context),
                .process_fn = struct {
                    fn call(context_ptr: *anyopaque, input: []const Sample, output: []Sample) void {
                        const instance: *Context = @ptrCast(@alignCast(context_ptr));
                        instance.processBlock(input, output);
                    }
                }.call,
                .reset_fn = struct {
                    fn call(context_ptr: *anyopaque) void {
                        const instance: *Context = @ptrCast(@alignCast(context_ptr));
                        instance.reset();
                    }
                }.call,
            };
        }

        pub fn reset(self: Self) void {
            self.reset_fn(self.context);
        }

        pub fn processBlock(self: Self, input: []const Sample, output: []Sample) void {
            self.process_fn(self.context, input, output);
        }
    };
}

pub fn renderFixed(
    comptime Sample: type,
    processor: BlockProcessor(Sample),
    input: []const Sample,
    output: []Sample,
    block_size: usize,
) error{ InvalidBlockSize, OutputSizeMismatch }!void {
    if (block_size == 0) return error.InvalidBlockSize;
    if (output.len != input.len) return error.OutputSizeMismatch;
    processor.reset();
    var offset: usize = 0;
    while (offset < input.len) {
        const end = @min(input.len, offset + block_size);
        processor.processBlock(input[offset..end], output[offset..end]);
        offset = end;
    }
}

pub fn renderRandomized(
    comptime Sample: type,
    processor: BlockProcessor(Sample),
    input: []const Sample,
    output: []Sample,
    maximum_block_size: usize,
    seed: u64,
) error{ InvalidBlockSize, OutputSizeMismatch }!void {
    if (maximum_block_size == 0) return error.InvalidBlockSize;
    if (output.len != input.len) return error.OutputSizeMismatch;
    processor.reset();
    var random = std.Random.DefaultPrng.init(seed);
    var offset: usize = 0;
    while (offset < input.len) {
        const remaining = input.len - offset;
        const block_size = random.random().intRangeAtMost(usize, 1, @min(remaining, maximum_block_size));
        processor.processBlock(input[offset .. offset + block_size], output[offset .. offset + block_size]);
        offset += block_size;
    }
}

pub const Tolerance = struct {
    maximum_absolute: f64,
    maximum_relative: f64,
    maximum_rms: f64,
    relative_floor: f64 = 1.0e-12,

    fn valid(self: Tolerance) bool {
        return std.math.isFinite(self.maximum_absolute) and self.maximum_absolute >= 0.0 and
            std.math.isFinite(self.maximum_relative) and self.maximum_relative >= 0.0 and
            std.math.isFinite(self.maximum_rms) and self.maximum_rms >= 0.0 and
            std.math.isFinite(self.relative_floor) and self.relative_floor > 0.0;
    }
};

pub const ErrorMetrics = struct {
    maximum_absolute: f64,
    maximum_relative: f64,
    rms: f64,
    sample_count: usize,
};

pub const Comparison = struct {
    metrics: ErrorMetrics,
    passed: bool,
};

pub fn compare(
    comptime Sample: type,
    reference: []const Sample,
    actual: []const Sample,
    tolerance: Tolerance,
) error{ InvalidTolerance, SizeMismatch, EmptyInput }!Comparison {
    if (Sample != f32 and Sample != f64) @compileError("compare supports f32 and f64 samples");
    if (!tolerance.valid()) return error.InvalidTolerance;
    if (reference.len != actual.len) return error.SizeMismatch;
    if (reference.len == 0) return error.EmptyInput;

    var maximum_absolute: f64 = 0.0;
    var maximum_relative: f64 = 0.0;
    var squared_error: f64 = 0.0;
    var samples_with_excess_error: usize = 0;
    for (reference, actual) |reference_sample, actual_sample| {
        const expected: f64 = @floatCast(reference_sample);
        const observed: f64 = @floatCast(actual_sample);
        if (!std.math.isFinite(expected) or !std.math.isFinite(observed)) {
            return .{
                .metrics = .{
                    .maximum_absolute = std.math.inf(f64),
                    .maximum_relative = std.math.inf(f64),
                    .rms = std.math.inf(f64),
                    .sample_count = reference.len,
                },
                .passed = false,
            };
        }
        const absolute = @abs(observed - expected);
        const relative = absolute / @max(@abs(expected), tolerance.relative_floor);
        maximum_absolute = @max(maximum_absolute, absolute);
        maximum_relative = @max(maximum_relative, relative);
        squared_error += absolute * absolute;
        if (absolute > tolerance.maximum_absolute and relative > tolerance.maximum_relative) {
            samples_with_excess_error += 1;
        }
    }
    const rms = @sqrt(squared_error / @as(f64, @floatFromInt(reference.len)));
    return .{
        .metrics = .{
            .maximum_absolute = maximum_absolute,
            .maximum_relative = maximum_relative,
            .rms = rms,
            .sample_count = reference.len,
        },
        .passed = samples_with_excess_error == 0 and rms <= tolerance.maximum_rms,
    };
}

pub const WavSampleFormat = enum {
    pcm_i16,
    ieee_f32,
    ieee_f64,
};

pub const WavInfo = struct {
    sample_rate: u32,
    frames: usize,
    format: WavSampleFormat,
};

pub fn decodeMonoWav(
    comptime Sample: type,
    bytes: []const u8,
    output: []Sample,
) error{
    InvalidFormat,
    Truncated,
    UnsupportedFormat,
    OutputTooSmall,
    NonFiniteSample,
}!WavInfo {
    if (Sample != f32 and Sample != f64) @compileError("decodeMonoWav supports f32 and f64 output");
    if (bytes.len < 12) return error.Truncated;
    if (!std.mem.eql(u8, bytes[0..4], "RIFF") or !std.mem.eql(u8, bytes[8..12], "WAVE")) {
        return error.InvalidFormat;
    }
    const riff_end = std.math.add(usize, readU32(bytes[4..8]), 8) catch return error.InvalidFormat;
    if (riff_end > bytes.len) return error.Truncated;

    const Format = struct {
        code: u16,
        channels: u16,
        sample_rate: u32,
        byte_rate: u32,
        block_align: u16,
        bits_per_sample: u16,
    };
    var format: ?Format = null;
    var data: ?[]const u8 = null;
    var offset: usize = 12;
    while (offset + 8 <= riff_end) {
        const chunk_size: usize = readU32(bytes[offset + 4 .. offset + 8]);
        const payload = offset + 8;
        const end = std.math.add(usize, payload, chunk_size) catch return error.InvalidFormat;
        if (end > riff_end) return error.Truncated;
        if (std.mem.eql(u8, bytes[offset .. offset + 4], "fmt ")) {
            if (chunk_size < 16) return error.InvalidFormat;
            format = .{
                .code = readU16(bytes[payload .. payload + 2]),
                .channels = readU16(bytes[payload + 2 .. payload + 4]),
                .sample_rate = readU32(bytes[payload + 4 .. payload + 8]),
                .byte_rate = readU32(bytes[payload + 8 .. payload + 12]),
                .block_align = readU16(bytes[payload + 12 .. payload + 14]),
                .bits_per_sample = readU16(bytes[payload + 14 .. payload + 16]),
            };
        } else if (std.mem.eql(u8, bytes[offset .. offset + 4], "data")) {
            data = bytes[payload..end];
        }
        offset = end + (chunk_size & 1);
    }

    const description = format orelse return error.InvalidFormat;
    const samples = data orelse return error.InvalidFormat;
    if (description.channels != 1 or description.sample_rate < 8_000 or description.sample_rate > 384_000) {
        return error.UnsupportedFormat;
    }
    const source_format: WavSampleFormat = switch (description.code) {
        1 => if (description.bits_per_sample == 16) .pcm_i16 else return error.UnsupportedFormat,
        3 => switch (description.bits_per_sample) {
            32 => .ieee_f32,
            64 => .ieee_f64,
            else => return error.UnsupportedFormat,
        },
        else => return error.UnsupportedFormat,
    };
    const bytes_per_sample: usize = description.bits_per_sample / 8;
    if (description.block_align != bytes_per_sample or
        description.byte_rate != description.sample_rate * description.block_align or
        samples.len == 0 or samples.len % bytes_per_sample != 0)
    {
        return error.InvalidFormat;
    }
    const frames = samples.len / bytes_per_sample;
    if (output.len < frames) return error.OutputTooSmall;

    for (output[0..frames], 0..) |*destination, frame| {
        const sample_offset = frame * bytes_per_sample;
        const value: f64 = switch (source_format) {
            .pcm_i16 => @as(f64, @floatFromInt(@as(i16, @bitCast(readU16(samples[sample_offset .. sample_offset + 2]))))) / 32_768.0,
            .ieee_f32 => @floatCast(@as(f32, @bitCast(readU32(samples[sample_offset .. sample_offset + 4])))),
            .ieee_f64 => @bitCast(readU64(samples[sample_offset .. sample_offset + 8])),
        };
        if (!std.math.isFinite(value)) return error.NonFiniteSample;
        destination.* = @floatCast(value);
    }
    return .{ .sample_rate = description.sample_rate, .frames = frames, .format = source_format };
}

fn readU16(bytes: []const u8) u16 {
    return std.mem.readInt(u16, bytes[0..2], .little);
}

fn readU32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .little);
}

fn readU64(bytes: []const u8) u64 {
    return std.mem.readInt(u64, bytes[0..8], .little);
}

fn ieeeWavFixture(comptime Float: type, value: Float) [44 + @sizeOf(Float)]u8 {
    const Int = std.meta.Int(.unsigned, @bitSizeOf(Float));
    var bytes: [44 + @sizeOf(Float)]u8 = @splat(0);
    @memcpy(bytes[0..4], "RIFF");
    std.mem.writeInt(u32, bytes[4..8], bytes.len - 8, .little);
    @memcpy(bytes[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, bytes[16..20], 16, .little);
    std.mem.writeInt(u16, bytes[20..22], 3, .little);
    std.mem.writeInt(u16, bytes[22..24], 1, .little);
    std.mem.writeInt(u32, bytes[24..28], 48_000, .little);
    std.mem.writeInt(u32, bytes[28..32], 48_000 * @sizeOf(Float), .little);
    std.mem.writeInt(u16, bytes[32..34], @sizeOf(Float), .little);
    std.mem.writeInt(u16, bytes[34..36], @bitSizeOf(Float), .little);
    @memcpy(bytes[36..40], "data");
    std.mem.writeInt(u32, bytes[40..44], @sizeOf(Float), .little);
    std.mem.writeInt(Int, bytes[44..], @bitCast(value), .little);
    return bytes;
}

const TestProcessor = struct {
    state: f32 = 0.0,

    fn reset(self: *TestProcessor) void {
        self.state = 0.0;
    }

    fn processBlock(self: *TestProcessor, input: []const f32, output: []f32) void {
        for (input, output) |sample, *destination| {
            self.state = 0.75 * self.state + 0.25 * sample;
            destination.* = sample + self.state;
        }
    }
};

test "fixed and randomized blocks produce identical stateful output" {
    var input: [1024]f32 = undefined;
    for (&input, 0..) |*sample, index| sample.* = @sin(@as(f32, @floatFromInt(index)) * 0.03);
    var fixed: [input.len]f32 = undefined;
    var randomized: [input.len]f32 = undefined;
    var model = TestProcessor{};
    const processor = BlockProcessor(f32).init(TestProcessor, &model);
    try renderFixed(f32, processor, &input, &fixed, 64);
    try renderRandomized(f32, processor, &input, &randomized, 127, 0x4e414d);
    try std.testing.expectEqualSlices(f32, &fixed, &randomized);
}

test "comparison reports absolute relative and aggregate error" {
    const reference = [_]f32{ 0.0, 0.5, -1.0, 0.25 };
    const actual = [_]f32{ 0.0, 0.50001, -0.99999, 0.25 };
    const result = try compare(f32, &reference, &actual, .{
        .maximum_absolute = 2.0e-5,
        .maximum_relative = 3.0e-5,
        .maximum_rms = 1.0e-5,
        .relative_floor = 1.0e-6,
    });
    try std.testing.expect(result.passed);
    try std.testing.expect(result.metrics.maximum_absolute > 0.0);
    try std.testing.expect(result.metrics.maximum_relative > 0.0);
    try std.testing.expect(result.metrics.rms > 0.0);
    const failed = try compare(f32, &reference, &actual, .{
        .maximum_absolute = 1.0e-7,
        .maximum_relative = 1.0e-7,
        .maximum_rms = 1.0e-7,
    });
    try std.testing.expect(!failed.passed);

    const near_zero = try compare(f32, &[_]f32{1.0e-4}, &[_]f32{1.01e-4}, .{
        .maximum_absolute = 2.0e-6,
        .maximum_relative = 1.0e-4,
        .maximum_rms = 2.0e-6,
        .relative_floor = 1.0e-6,
    });
    try std.testing.expect(near_zero.metrics.maximum_relative > 1.0e-4);
    try std.testing.expect(near_zero.passed);
}

test "mono WAV decoder accepts bounded PCM and IEEE float fixtures" {
    var pcm: [48]u8 = @splat(0);
    @memcpy(pcm[0..4], "RIFF");
    std.mem.writeInt(u32, pcm[4..8], pcm.len - 8, .little);
    @memcpy(pcm[8..16], "WAVEfmt ");
    std.mem.writeInt(u32, pcm[16..20], 16, .little);
    std.mem.writeInt(u16, pcm[20..22], 1, .little);
    std.mem.writeInt(u16, pcm[22..24], 1, .little);
    std.mem.writeInt(u32, pcm[24..28], 48_000, .little);
    std.mem.writeInt(u32, pcm[28..32], 96_000, .little);
    std.mem.writeInt(u16, pcm[32..34], 2, .little);
    std.mem.writeInt(u16, pcm[34..36], 16, .little);
    @memcpy(pcm[36..40], "data");
    std.mem.writeInt(u32, pcm[40..44], 4, .little);
    std.mem.writeInt(u16, pcm[44..46], @bitCast(@as(i16, -16_384)), .little);
    std.mem.writeInt(u16, pcm[46..48], @bitCast(@as(i16, 16_384)), .little);
    var output: [2]f32 = undefined;
    const info = try decodeMonoWav(f32, &pcm, &output);
    try std.testing.expectEqual(@as(u32, 48_000), info.sample_rate);
    try std.testing.expectEqual(WavSampleFormat.pcm_i16, info.format);
    try std.testing.expectEqualSlices(f32, &.{ -0.5, 0.5 }, &output);

    const float32_fixture = ieeeWavFixture(f32, 0.25);
    var float32_output: [1]f64 = undefined;
    const float32_info = try decodeMonoWav(f64, &float32_fixture, &float32_output);
    try std.testing.expectEqual(WavSampleFormat.ieee_f32, float32_info.format);
    try std.testing.expectEqual(@as(f64, 0.25), float32_output[0]);

    const float64_fixture = ieeeWavFixture(f64, -0.75);
    var float64_output: [1]f32 = undefined;
    const float64_info = try decodeMonoWav(f32, &float64_fixture, &float64_output);
    try std.testing.expectEqual(WavSampleFormat.ieee_f64, float64_info.format);
    try std.testing.expectEqual(@as(f32, -0.75), float64_output[0]);

    var short_output: [1]f32 = undefined;
    try std.testing.expectError(error.OutputTooSmall, decodeMonoWav(f32, &pcm, &short_output));
    try std.testing.expectError(error.Truncated, decodeMonoWav(f32, pcm[0 .. pcm.len - 1], &output));
}

test "mono WAV decoder handles truncated and malformed near-valid inputs" {
    const fixture = ieeeWavFixture(f32, 0.25);
    var output: [1]f32 = undefined;
    for (0..fixture.len) |length| {
        try std.testing.expectError(error.Truncated, decodeMonoWav(f32, fixture[0..length], &output));
    }

    for (0..fixture.len) |index| {
        var mutated = fixture;
        mutated[index] ^= 0xff;
        _ = decodeMonoWav(f32, &mutated, &output) catch continue;
    }

    var stereo = fixture;
    std.mem.writeInt(u16, stereo[22..24], 2, .little);
    try std.testing.expectError(error.UnsupportedFormat, decodeMonoWav(f32, &stereo, &output));

    var invalid_rate = fixture;
    std.mem.writeInt(u32, invalid_rate[28..32], 1, .little);
    try std.testing.expectError(error.InvalidFormat, decodeMonoWav(f32, &invalid_rate, &output));

    const non_finite = ieeeWavFixture(f32, std.math.nan(f32));
    try std.testing.expectError(error.NonFiniteSample, decodeMonoWav(f32, &non_finite, &output));
}
