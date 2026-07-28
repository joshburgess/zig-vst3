const std = @import("std");

pub const maximum_channels = 64;

pub const Mode = enum {
    none,
    tpdf,
    noise_shaped,
};

pub const Config = struct {
    channel_count: usize,
    bits_per_sample: u6,
    mode: Mode = .tpdf,
    seed: u64 = 0x6a09_e667_f3bc_c909,
    noise_shape: f64 = 0.85,
};

/// Deterministic, allocation-free floating-point to signed PCM quantization.
pub const PcmDither = struct {
    config: Config,
    random_state: [maximum_channels]u64,
    quantization_error: [maximum_channels]f64 = @splat(0.0),

    pub fn init(config: Config) !PcmDither {
        try validateConfig(config);
        var result = PcmDither{
            .config = config,
            .random_state = undefined,
        };
        for (&result.random_state, 0..) |*state, channel| {
            state.* = mixSeed(config.seed, channel);
        }
        return result;
    }

    pub fn reset(self: *PcmDither) void {
        for (&self.random_state, 0..) |*state, channel| {
            state.* = mixSeed(self.config.seed, channel);
        }
        @memset(&self.quantization_error, 0.0);
    }

    pub fn channelCount(self: *const PcmDither) usize {
        return self.config.channel_count;
    }

    pub fn bitsPerSample(self: *const PcmDither) u6 {
        return self.config.bits_per_sample;
    }

    pub fn quantize(
        self: *PcmDither,
        sample: f64,
        channel: usize,
    ) !i32 {
        if (channel >= self.config.channel_count)
            return error.InvalidDitherChannel;
        if (!std.math.isFinite(sample))
            return error.InvalidDitherSample;

        const scale = quantizationScale(self.config.bits_per_sample);
        const minimum = -scale;
        const maximum = scale - 1.0;
        const feedback = switch (self.config.mode) {
            .noise_shaped => self.quantization_error[channel] *
                self.config.noise_shape,
            .none, .tpdf => 0.0,
        };
        const noise = switch (self.config.mode) {
            .none => 0.0,
            .tpdf, .noise_shaped => self.nextTpdfLsb(channel),
        };
        const shaped = sample * scale + feedback + noise;
        const quantized = std.math.clamp(@round(shaped), minimum, maximum);
        if (self.config.mode == .noise_shaped) {
            self.quantization_error[channel] =
                std.math.clamp(shaped - quantized, -1.0, 1.0);
        }
        return @intFromFloat(quantized);
    }

    pub fn quantizeInterleaved(
        self: *PcmDither,
        samples: []const f64,
        destination: []i32,
    ) !void {
        if (samples.len != destination.len)
            return error.MismatchedDitherBufferLength;
        if (samples.len % self.config.channel_count != 0)
            return error.IncompleteDitherFrame;
        for (samples) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidDitherSample;
        }
        for (samples, destination, 0..) |sample, *encoded, index| {
            encoded.* = try self.quantize(
                sample,
                index % self.config.channel_count,
            );
        }
    }

    fn nextTpdfLsb(self: *PcmDither, channel: usize) f64 {
        return self.nextUnit(channel) - self.nextUnit(channel);
    }

    fn nextUnit(self: *PcmDither, channel: usize) f64 {
        var state = self.random_state[channel];
        state +%= 0x9e37_79b9_7f4a_7c15;
        self.random_state[channel] = state;
        var value = state;
        value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
        value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
        value ^= value >> 31;
        const mantissa = value >> 11;
        return @as(f64, @floatFromInt(mantissa)) *
            0x1.0p-53;
    }
};

fn validateConfig(config: Config) !void {
    if (config.channel_count == 0 or
        config.channel_count > maximum_channels)
        return error.InvalidDitherChannelCount;
    if (config.bits_per_sample < 2 or config.bits_per_sample > 32)
        return error.InvalidDitherBitDepth;
    if (!std.math.isFinite(config.noise_shape) or
        config.noise_shape < 0.0 or config.noise_shape >= 1.0)
        return error.InvalidNoiseShape;
}

fn quantizationScale(bits_per_sample: u6) f64 {
    const scale: u64 = @as(u64, 1) <<
        @intCast(bits_per_sample - 1);
    return @floatFromInt(scale);
}

fn mixSeed(seed: u64, channel: usize) u64 {
    var value = seed +%
        (@as(u64, @intCast(channel)) +% 1) *%
            0x9e37_79b9_7f4a_7c15;
    value = (value ^ (value >> 30)) *% 0xbf58_476d_1ce4_e5b9;
    value = (value ^ (value >> 27)) *% 0x94d0_49bb_1331_11eb;
    value ^= value >> 31;
    return value;
}

test "PCM dither is deterministic independent per channel and resettable" {
    const config = Config{
        .channel_count = 2,
        .bits_per_sample = 16,
        .seed = 1234,
    };
    var first = try PcmDither.init(config);
    var second = try PcmDither.init(config);
    var left_differs_from_right = false;
    for (0..256) |_| {
        const first_left = try first.quantize(0.0, 0);
        const first_right = try first.quantize(0.0, 1);
        try std.testing.expectEqual(
            first_left,
            try second.quantize(0.0, 0),
        );
        try std.testing.expectEqual(
            first_right,
            try second.quantize(0.0, 1),
        );
        left_differs_from_right = left_differs_from_right or
            first_left != first_right;
    }
    try std.testing.expect(left_differs_from_right);

    first.reset();
    second.reset();
    try std.testing.expectEqual(
        try first.quantize(0.125, 0),
        try second.quantize(0.125, 0),
    );
}

test "TPDF source has zero mean and one sixth LSB squared variance" {
    var dither = try PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 24,
        .seed = 0x1234_5678,
    });
    const count = 200_000;
    var sum: f64 = 0.0;
    var square_sum: f64 = 0.0;
    for (0..count) |_| {
        const sample = dither.nextTpdfLsb(0);
        sum += sample;
        square_sum += sample * sample;
    }
    const mean = sum / count;
    const variance = square_sum / count - mean * mean;
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), mean, 0.003);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / 6.0),
        variance,
        0.003,
    );
}

test "PCM quantization covers signed endpoints and validates contracts" {
    var dither = try PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 16,
        .mode = .none,
    });
    try std.testing.expectEqual(
        @as(i32, -32_768),
        try dither.quantize(-1.0, 0),
    );
    try std.testing.expectEqual(
        @as(i32, 32_767),
        try dither.quantize(1.0, 0),
    );
    try std.testing.expectEqual(
        @as(i32, 32_767),
        try dither.quantize(2.0, 0),
    );
    try std.testing.expectError(
        error.InvalidDitherSample,
        dither.quantize(std.math.nan(f64), 0),
    );
    try std.testing.expectError(
        error.InvalidDitherChannel,
        dither.quantize(0.0, 1),
    );
    try std.testing.expectError(
        error.InvalidDitherChannelCount,
        PcmDither.init(.{
            .channel_count = 0,
            .bits_per_sample = 16,
        }),
    );
    try std.testing.expectError(
        error.InvalidDitherBitDepth,
        PcmDither.init(.{
            .channel_count = 1,
            .bits_per_sample = 1,
        }),
    );
}

test "noise-shaped PCM error remains bounded across long input" {
    var dither = try PcmDither.init(.{
        .channel_count = 1,
        .bits_per_sample = 16,
        .mode = .noise_shaped,
        .seed = 9876,
        .noise_shape = 0.9,
    });
    for (0..100_000) |index| {
        const sample =
            @as(f64, @floatFromInt(index % 97)) / 97.0 - 0.5;
        _ = try dither.quantize(sample, 0);
        try std.testing.expect(std.math.isFinite(
            dither.quantization_error[0],
        ));
        try std.testing.expect(
            @abs(dither.quantization_error[0]) <= 1.0,
        );
    }
}
