const std = @import("std");
const dynamics = @import("dynamics.zig");
const oversampling = @import("oversampling.zig");

pub const Config = struct {
    sample_rate: f64,
    threshold_db: f64 = -1.0,
    release_ms: f64 = 100.0,
    reconstruction_guard_db: f64 = 0.5,

    pub fn validate(self: Config) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            self.sample_rate > 192_000.0 or
            !std.math.isFinite(self.threshold_db) or
            self.threshold_db < -48.0 or
            self.threshold_db > 0.0 or
            !std.math.isFinite(self.release_ms) or
            self.release_ms < 0.01 or
            self.release_ms > 10_000.0 or
            !std.math.isFinite(self.reconstruction_guard_db) or
            self.reconstruction_guard_db < 0.0 or
            self.reconstruction_guard_db > 12.0 or
            self.threshold_db - self.reconstruction_guard_db < -60.0)
            return error.InvalidInterSampleLimiterConfig;
    }
};

pub fn InterSampleLimiter(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("InterSampleLimiter supports f32 and f64 samples");

    const Oversampler = oversampling.Oversampler(
        Sample,
        maximum_frames,
        factor,
    );
    const PeakLimiter = dynamics.Limiter(Sample);

    return struct {
        const Self = @This();

        pub const latency_samples = Oversampler.latency_samples;
        pub const oversampling_factor = factor;

        config: Config,
        oversampler: Oversampler,
        high_rate_limiter: PeakLimiter,
        output_limiter: PeakLimiter,

        pub fn init(config: Config) !Self {
            try config.validate();
            return .{
                .config = config,
                .oversampler = try Oversampler.init(),
                .high_rate_limiter = try PeakLimiter.init(.{
                    .sample_rate = config.sample_rate *
                        @as(f64, @floatFromInt(factor)),
                    .threshold_db = config.threshold_db -
                        config.reconstruction_guard_db,
                    .release_ms = config.release_ms,
                }),
                .output_limiter = try PeakLimiter.init(.{
                    .sample_rate = config.sample_rate,
                    .threshold_db = config.threshold_db,
                    .release_ms = config.release_ms,
                }),
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const replacement = try init(config);
            self.* = replacement;
        }

        pub fn reset(self: *Self) void {
            self.oversampler.reset();
            self.high_rate_limiter.reset();
            self.output_limiter.reset();
        }

        pub fn process(self: *Self, samples: []Sample) !void {
            if (!self.valid()) return error.InvalidInterSampleLimiterState;
            const high_rate = try self.oversampler.upsample(samples);
            self.high_rate_limiter.process(high_rate);
            try self.oversampler.downsample(samples);
            self.output_limiter.process(samples);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return @min(
                self.high_rate_limiter.gainReductionDb(),
                self.output_limiter.gainReductionDb(),
            );
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            return self.oversampler.valid() and
                self.high_rate_limiter.valid() and
                self.output_limiter.valid();
        }
    };
}

test "inter-sample limiter contains reconstructed high-frequency peaks" {
    const Processor = InterSampleLimiter(f64, 128, 4);
    var limiter = try Processor.init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -1.0,
        .release_ms = 20.0,
        .reconstruction_guard_db = 1.0,
    });
    var block: [128]f64 = undefined;
    var phase: f64 = 0.0;
    for (0..8) |_| {
        for (&block) |*sample| {
            sample.* = 1.2 * @sin(std.math.tau * phase);
            phase += 18_000.0 / 48_000.0;
            phase -= @floor(phase);
        }
        try limiter.process(&block);
    }

    const Probe = oversampling.Oversampler(f64, 128, 4);
    var probe = try Probe.init();
    var peak: f64 = 0.0;
    for (0..4) |_| {
        const reconstructed = try probe.upsample(&block);
        for (reconstructed) |sample| peak = @max(peak, @abs(sample));
        var discarded: [128]f64 = undefined;
        try probe.downsample(&discarded);
    }
    const ceiling = std.math.pow(f64, 10.0, -1.0 / 20.0);
    try std.testing.expect(peak <= ceiling + 0.000_1);
    try std.testing.expect(limiter.gainReductionDb() < 0.0);
}

test "inter-sample limiter passes independent sinc peak probe" {
    var limiter = try InterSampleLimiter(f64, 256, 4).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -1.0,
        .release_ms = 20.0,
        .reconstruction_guard_db = 1.0,
    });
    var block: [256]f64 = undefined;
    var phase: f64 = 0.0;
    for (0..16) |_| {
        for (&block) |*sample| {
            sample.* = 1.2 * @sin(std.math.tau * phase);
            phase += 18_000.0 / 48_000.0;
            phase -= @floor(phase);
        }
        try limiter.process(&block);
    }
    const ceiling = std.math.pow(f64, 10.0, -1.0 / 20.0);
    try std.testing.expect(
        lanczosPeak(block[32..224], 16, 12) <= ceiling + 0.000_1,
    );
}

test "inter-sample limiter rejects capacity without partial output" {
    const Processor = InterSampleLimiter(f32, 4, 2);
    var limiter = try Processor.init(.{ .sample_rate = 48_000.0 });
    var samples = [_]f32{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    const before = samples;
    try std.testing.expectError(
        error.OversamplingCapacityExceeded,
        limiter.process(&samples),
    );
    try std.testing.expectEqualSlices(f32, &before, &samples);
}

test "inter-sample limiter retains maximum oversampled rate support" {
    var limiter = try InterSampleLimiter(f64, 4, 16).init(.{
        .sample_rate = 192_000.0,
        .release_ms = 10_000.0,
    });
    var samples = [_]f64{ 0.25, -0.5, 0.75, -1.0 };
    try limiter.process(&samples);
    try std.testing.expect(limiter.valid());
    for (samples) |sample|
        try std.testing.expect(std.math.isFinite(sample));
}

fn lanczosPeak(
    samples: []const f64,
    factor: usize,
    radius: usize,
) f64 {
    var peak: f64 = 0.0;
    for (radius..samples.len - radius) |center| {
        for (0..factor) |phase_index| {
            const phase = @as(f64, @floatFromInt(phase_index)) /
                @as(f64, @floatFromInt(factor));
            var value: f64 = 0.0;
            var weight_sum: f64 = 0.0;
            for (center - radius + 1..center + radius + 1) |index| {
                const distance =
                    @as(f64, @floatFromInt(center)) + phase -
                    @as(f64, @floatFromInt(index));
                const weight =
                    normalizedSinc(distance) *
                    normalizedSinc(
                        distance / @as(f64, @floatFromInt(radius)),
                    );
                value += samples[index] * weight;
                weight_sum += weight;
            }
            if (@abs(weight_sum) > std.math.floatEps(f64))
                value /= weight_sum;
            peak = @max(peak, @abs(value));
        }
    }
    return peak;
}

fn normalizedSinc(value: f64) f64 {
    if (@abs(value) <= std.math.floatEps(f64)) return 1.0;
    const angle = std.math.pi * value;
    return @sin(angle) / angle;
}
