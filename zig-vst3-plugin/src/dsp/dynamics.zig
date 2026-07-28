const std = @import("std");

pub const CompressorConfig = struct {
    sample_rate: f64,
    threshold_db: f64 = -18.0,
    ratio: f64 = 4.0,
    attack_ms: f64 = 10.0,
    release_ms: f64 = 100.0,
    makeup_db: f64 = 0.0,

    pub fn validate(self: CompressorConfig) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            !std.math.isFinite(self.threshold_db) or
            self.threshold_db < -160.0 or
            self.threshold_db > 24.0 or
            !std.math.isFinite(self.ratio) or
            self.ratio < 1.0 or
            self.ratio > 100.0 or
            !validTime(self.attack_ms) or
            !validTime(self.release_ms) or
            !std.math.isFinite(self.makeup_db) or
            self.makeup_db < -60.0 or
            self.makeup_db > 60.0)
            return error.InvalidCompressorConfig;
        if (!validDynamicsCoefficient(dynamicsCoefficient(
            self.sample_rate,
            self.attack_ms,
        )) or !validDynamicsCoefficient(dynamicsCoefficient(
            self.sample_rate,
            self.release_ms,
        )))
            return error.InvalidCompressorConfig;
    }

    fn validTime(value: f64) bool {
        return std.math.isFinite(value) and value >= 0.01 and value <= 10_000.0;
    }
};

pub fn Compressor(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Compressor supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: CompressorConfig,
        attack_coefficient: f64,
        release_coefficient: f64,
        envelope: f64 = 0.0,
        gain_reduction_db: f64 = 0.0,

        pub fn init(config: CompressorConfig) !Self {
            try config.validate();
            return .{
                .config = config,
                .attack_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.attack_ms,
                ),
                .release_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.release_ms,
                ),
            };
        }

        pub fn configure(self: *Self, config: CompressorConfig) !void {
            try config.validate();
            self.config = config;
            self.attack_coefficient = dynamicsCoefficient(
                config.sample_rate,
                config.attack_ms,
            );
            self.release_coefficient = dynamicsCoefficient(
                config.sample_rate,
                config.release_ms,
            );
        }

        pub fn reset(self: *Self) void {
            self.envelope = 0.0;
            self.gain_reduction_db = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const finite_input: f64 = if (std.math.isFinite(input))
                @floatCast(input)
            else
                0.0;
            if (!self.valid()) {
                self.reset();
                return @floatCast(finite_input);
            }
            return @floatCast(
                finite_input * self.advanceGain(@abs(finite_input)),
            );
        }

        pub fn processLinkedFrame(
            self: *Self,
            samples: []Sample,
        ) !void {
            if (samples.len == 0)
                return error.EmptyLinkedCompressorFrame;
            self.processLinkedNonEmpty(samples);
        }

        pub fn processLinkedArray(
            self: *Self,
            comptime channel_count: usize,
            samples: *[channel_count]Sample,
        ) void {
            if (channel_count == 0)
                @compileError("linked compressor arrays cannot be empty");
            self.processLinkedNonEmpty(samples);
        }

        fn processLinkedNonEmpty(
            self: *Self,
            samples: []Sample,
        ) void {
            var level: f64 = 0.0;
            for (samples) |sample| {
                if (std.math.isFinite(sample))
                    level = @max(level, @abs(@as(f64, @floatCast(sample))));
            }
            if (!self.valid()) {
                self.reset();
                for (samples) |*sample| {
                    if (!std.math.isFinite(sample.*)) sample.* = 0.0;
                }
                return;
            }
            const gain = self.advanceGain(level);
            for (samples) |*sample| {
                const finite: f64 = if (std.math.isFinite(sample.*))
                    @floatCast(sample.*)
                else
                    0.0;
                sample.* = @floatCast(finite * gain);
            }
        }

        fn advanceGain(self: *Self, level: f64) f64 {
            const smoothing = if (level > self.envelope)
                self.attack_coefficient
            else
                self.release_coefficient;
            self.envelope =
                smoothing * self.envelope + (1.0 - smoothing) * level;

            const envelope_db = if (self.envelope > 0.0)
                20.0 * std.math.log10(self.envelope)
            else
                -160.0;
            const compressed_db = if (envelope_db > self.config.threshold_db)
                self.config.threshold_db +
                    (envelope_db - self.config.threshold_db) /
                        self.config.ratio
            else
                envelope_db;
            self.gain_reduction_db = @min(0.0, compressed_db - envelope_db);
            const gain = std.math.pow(
                f64,
                10.0,
                (self.gain_reduction_db + self.config.makeup_db) / 20.0,
            );
            return gain;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return self.gain_reduction_db;
        }

        pub fn linearGain(self: *const Self) f64 {
            if (!self.valid()) return 1.0;
            return std.math.pow(
                f64,
                10.0,
                (self.gain_reduction_db + self.config.makeup_db) / 20.0,
            );
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            return validDynamicsCoefficient(self.attack_coefficient) and
                validDynamicsCoefficient(self.release_coefficient) and
                std.math.isFinite(self.envelope) and
                self.envelope >= 0.0 and
                std.math.isFinite(self.gain_reduction_db) and
                self.gain_reduction_db <= 0.0;
        }
    };
}

pub const NoiseGateConfig = struct {
    sample_rate: f64,
    threshold_db: f64 = -40.0,
    ratio: f64 = 10.0,
    attack_ms: f64 = 1.0,
    release_ms: f64 = 100.0,

    pub fn validate(self: NoiseGateConfig) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            !std.math.isFinite(self.threshold_db) or
            self.threshold_db < -160.0 or
            self.threshold_db > 0.0 or
            !std.math.isFinite(self.ratio) or
            self.ratio < 1.0 or
            self.ratio > 100.0 or
            !validDynamicsTime(self.attack_ms) or
            !validDynamicsTime(self.release_ms))
            return error.InvalidNoiseGateConfig;
        if (!validDynamicsCoefficient(dynamicsCoefficient(
            self.sample_rate,
            self.attack_ms,
        )) or !validDynamicsCoefficient(dynamicsCoefficient(
            self.sample_rate,
            self.release_ms,
        )))
            return error.InvalidNoiseGateConfig;
    }
};

pub fn NoiseGate(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("NoiseGate supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: NoiseGateConfig,
        attack_coefficient: f64,
        release_coefficient: f64,
        envelope: f64 = 0.0,
        gain_reduction_db: f64 = 0.0,

        pub fn init(config: NoiseGateConfig) !Self {
            try config.validate();
            return .{
                .config = config,
                .attack_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.attack_ms,
                ),
                .release_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.release_ms,
                ),
            };
        }

        pub fn configure(self: *Self, config: NoiseGateConfig) !void {
            try config.validate();
            self.config = config;
            self.attack_coefficient = dynamicsCoefficient(
                config.sample_rate,
                config.attack_ms,
            );
            self.release_coefficient = dynamicsCoefficient(
                config.sample_rate,
                config.release_ms,
            );
        }

        pub fn reset(self: *Self) void {
            self.envelope = 0.0;
            self.gain_reduction_db = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const finite_input: f64 = if (std.math.isFinite(input))
                @floatCast(input)
            else
                0.0;
            if (!self.valid()) {
                self.reset();
                return @floatCast(finite_input);
            }

            const level = @abs(finite_input);
            const smoothing = if (level > self.envelope)
                self.attack_coefficient
            else
                self.release_coefficient;
            self.envelope =
                smoothing * self.envelope + (1.0 - smoothing) * level;
            const envelope_db = if (self.envelope > 0.0)
                20.0 * std.math.log10(self.envelope)
            else
                -160.0;
            self.gain_reduction_db =
                if (envelope_db < self.config.threshold_db)
                    @max(
                        -160.0,
                        (envelope_db - self.config.threshold_db) *
                            (self.config.ratio - 1.0),
                    )
                else
                    0.0;
            const gain = std.math.pow(
                f64,
                10.0,
                self.gain_reduction_db / 20.0,
            );
            return @floatCast(finite_input * gain);
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return self.gain_reduction_db;
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            return validDynamicsCoefficient(self.attack_coefficient) and
                validDynamicsCoefficient(self.release_coefficient) and
                std.math.isFinite(self.envelope) and
                self.envelope >= 0.0 and
                std.math.isFinite(self.gain_reduction_db) and
                self.gain_reduction_db <= 0.0;
        }
    };
}

pub const LimiterConfig = struct {
    sample_rate: f64,
    threshold_db: f64 = -0.1,
    release_ms: f64 = 100.0,

    pub fn validate(self: LimiterConfig) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            !std.math.isFinite(self.threshold_db) or
            self.threshold_db < -60.0 or
            self.threshold_db > 0.0 or
            !validDynamicsTime(self.release_ms))
            return error.InvalidLimiterConfig;
        if (!validDynamicsCoefficient(dynamicsCoefficient(
            self.sample_rate,
            self.release_ms,
        )))
            return error.InvalidLimiterConfig;
    }
};

pub fn Limiter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Limiter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: LimiterConfig,
        release_coefficient: f64,
        ceiling: f64,
        gain: f64 = 1.0,

        pub fn init(config: LimiterConfig) !Self {
            try config.validate();
            return .{
                .config = config,
                .release_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.release_ms,
                ),
                .ceiling = std.math.pow(
                    f64,
                    10.0,
                    config.threshold_db / 20.0,
                ),
            };
        }

        pub fn configure(self: *Self, config: LimiterConfig) !void {
            try config.validate();
            self.config = config;
            self.release_coefficient = dynamicsCoefficient(
                config.sample_rate,
                config.release_ms,
            );
            self.ceiling = std.math.pow(
                f64,
                10.0,
                config.threshold_db / 20.0,
            );
        }

        pub fn reset(self: *Self) void {
            self.gain = 1.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const finite_input: f64 = if (std.math.isFinite(input))
                @floatCast(input)
            else
                0.0;
            if (!self.valid()) {
                self.reset();
                return @floatCast(finite_input);
            }

            const amplitude = @abs(finite_input);
            const required_gain =
                if (amplitude > self.ceiling)
                    self.ceiling / amplitude
                else
                    1.0;
            if (required_gain < self.gain) {
                self.gain = required_gain;
            } else {
                self.gain = self.release_coefficient * self.gain +
                    (1.0 - self.release_coefficient) * required_gain;
            }
            return @floatCast(finite_input * self.gain);
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return if (self.gain > 0.0)
                20.0 * std.math.log10(self.gain)
            else
                -160.0;
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            return validDynamicsCoefficient(self.release_coefficient) and
                std.math.isFinite(self.ceiling) and
                self.ceiling > 0.0 and
                self.ceiling <= 1.0 and
                std.math.isFinite(self.gain) and
                self.gain > 0.0 and
                self.gain <= 1.0;
        }
    };
}

pub const LookaheadLimiterConfig = struct {
    sample_rate: f64,
    threshold_db: f64 = -0.1,
    release_ms: f64 = 100.0,
    lookahead_ms: f64 = 5.0,

    pub fn validate(self: LookaheadLimiterConfig) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            self.sample_rate > 768_000.0 or
            !std.math.isFinite(self.threshold_db) or
            self.threshold_db < -60.0 or
            self.threshold_db > 0.0 or
            !validDynamicsTime(self.release_ms) or
            !std.math.isFinite(self.lookahead_ms) or
            self.lookahead_ms < 0.0 or
            self.lookahead_ms > 100.0)
            return error.InvalidLookaheadLimiterConfig;
    }
};

pub fn LookaheadLimiter(
    comptime Sample: type,
    comptime maximum_lookahead_samples: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LookaheadLimiter supports f32 and f64 samples");
    if (maximum_lookahead_samples == 0)
        @compileError("lookahead limiter capacity must be nonzero");

    return struct {
        const Self = @This();

        config: LookaheadLimiterConfig,
        delay: [maximum_lookahead_samples + 1]Sample = @splat(0.0),
        lookahead_samples: usize,
        write_index: usize = 0,
        filled: usize = 0,
        ceiling: f64,
        release_coefficient: f64,
        gain: f64 = 1.0,

        pub fn init(config: LookaheadLimiterConfig) !Self {
            try config.validate();
            const lookahead = try lookaheadSamples(config);
            return .{
                .config = config,
                .lookahead_samples = lookahead,
                .ceiling = std.math.pow(
                    f64,
                    10.0,
                    config.threshold_db / 20.0,
                ),
                .release_coefficient = dynamicsCoefficient(
                    config.sample_rate,
                    config.release_ms,
                ),
            };
        }

        pub fn configure(
            self: *Self,
            config: LookaheadLimiterConfig,
        ) !void {
            const replacement = try init(config);
            self.* = replacement;
        }

        pub fn reset(self: *Self) void {
            self.delay = @splat(0.0);
            self.write_index = 0;
            self.filled = 0;
            self.gain = 1.0;
        }

        pub fn latencySamples(self: *const Self) usize {
            return self.lookahead_samples;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const finite_input: Sample =
                if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.reset();
                return finite_input;
            }

            const window = self.lookahead_samples + 1;
            self.delay[self.write_index] = finite_input;
            self.write_index = (self.write_index + 1) % window;
            self.filled = @min(self.filled + 1, window);
            if (self.filled < window) return 0.0;

            var peak: f64 = 0.0;
            for (self.delay[0..window]) |sample|
                peak = @max(peak, @abs(@as(f64, @floatCast(sample))));
            const required_gain = if (peak > self.ceiling)
                self.ceiling / peak
            else
                1.0;
            if (required_gain < self.gain) {
                self.gain = required_gain;
            } else {
                self.gain = self.release_coefficient * self.gain +
                    (1.0 - self.release_coefficient) * required_gain;
            }
            const delayed = self.delay[self.write_index];
            return @floatCast(@as(f64, @floatCast(delayed)) * self.gain);
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return if (self.gain > 0.0)
                20.0 * std.math.log10(self.gain)
            else
                -160.0;
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            const expected_lookahead =
                lookaheadSamples(self.config) catch return false;
            return expected_lookahead == self.lookahead_samples and
                self.lookahead_samples <= maximum_lookahead_samples and
                self.write_index <= self.lookahead_samples and
                self.filled <= self.lookahead_samples + 1 and
                std.math.isFinite(self.ceiling) and
                self.ceiling > 0.0 and
                self.ceiling <= 1.0 and
                validDynamicsCoefficient(self.release_coefficient) and
                std.math.isFinite(self.gain) and
                self.gain > 0.0 and
                self.gain <= 1.0;
        }

        fn lookaheadSamples(
            config: LookaheadLimiterConfig,
        ) !usize {
            const samples_float =
                @round(config.sample_rate * config.lookahead_ms * 0.001);
            if (!std.math.isFinite(samples_float) or
                samples_float < 0.0 or
                samples_float >
                    @as(
                        f64,
                        @floatFromInt(maximum_lookahead_samples),
                    ))
                return error.LookaheadLimiterCapacityExceeded;
            return @intFromFloat(samples_float);
        }
    };
}

pub const LookaheadCompressorConfig = struct {
    compressor: CompressorConfig,
    lookahead_ms: f64 = 5.0,

    pub fn validate(self: LookaheadCompressorConfig) !void {
        try self.compressor.validate();
        if (self.compressor.sample_rate > 768_000.0 or
            !std.math.isFinite(self.lookahead_ms) or
            self.lookahead_ms < 0.0 or
            self.lookahead_ms > 100.0)
            return error.InvalidLookaheadCompressorConfig;
    }
};

pub fn LookaheadCompressor(
    comptime Sample: type,
    comptime maximum_lookahead_samples: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LookaheadCompressor supports f32 and f64 samples");
    if (maximum_lookahead_samples == 0)
        @compileError("lookahead compressor capacity must be nonzero");

    const Detector = Compressor(Sample);
    return struct {
        const Self = @This();

        config: LookaheadCompressorConfig,
        delay: [maximum_lookahead_samples + 1]Sample = @splat(0.0),
        lookahead_samples: usize,
        write_index: usize = 0,
        filled: usize = 0,
        detector: Detector,

        pub fn init(config: LookaheadCompressorConfig) !Self {
            try config.validate();
            return .{
                .config = config,
                .lookahead_samples = try lookaheadSamples(config),
                .detector = try Detector.init(config.compressor),
            };
        }

        pub fn configure(
            self: *Self,
            config: LookaheadCompressorConfig,
        ) !void {
            self.* = try init(config);
        }

        pub fn reset(self: *Self) void {
            self.delay = @splat(0.0);
            self.write_index = 0;
            self.filled = 0;
            self.detector.reset();
        }

        pub fn latencySamples(self: *const Self) usize {
            return self.lookahead_samples;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const finite = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.reset();
                return finite;
            }
            const window = self.lookahead_samples + 1;
            self.delay[self.write_index] = finite;
            self.write_index = (self.write_index + 1) % window;
            self.filled = @min(self.filled + 1, window);
            _ = self.detector.processSample(finite);
            if (self.filled < window) return 0.0;
            const delayed = self.delay[self.write_index];
            const output: f64 =
                @as(f64, @floatCast(delayed)) *
                self.detector.linearGain();
            if (!std.math.isFinite(output)) {
                self.reset();
                return 0.0;
            }
            return @floatCast(output);
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn gainReductionDb(self: *const Self) f64 {
            return self.detector.gainReductionDb();
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            const expected = lookaheadSamples(self.config) catch return false;
            return expected == self.lookahead_samples and
                self.write_index <= self.lookahead_samples and
                self.filled <= self.lookahead_samples + 1 and
                self.detector.valid() and
                std.meta.eql(
                    self.detector.config,
                    self.config.compressor,
                );
        }

        fn lookaheadSamples(
            config: LookaheadCompressorConfig,
        ) !usize {
            const samples = @round(
                config.compressor.sample_rate *
                    config.lookahead_ms * 0.001,
            );
            if (samples >
                @as(f64, @floatFromInt(maximum_lookahead_samples)))
                return error.LookaheadCompressorCapacityExceeded;
            return @intFromFloat(samples);
        }
    };
}

fn validDynamicsTime(value: f64) bool {
    return std.math.isFinite(value) and value >= 0.01 and value <= 10_000.0;
}

fn dynamicsCoefficient(sample_rate: f64, milliseconds: f64) f64 {
    return @exp(-1.0 / (sample_rate * milliseconds * 0.001));
}

fn validDynamicsCoefficient(value: f64) bool {
    return std.math.isFinite(value) and value >= 0.0 and value < 1.0;
}

test "compressor converges to the configured static curve" {
    var compressor = try Compressor(f64).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -6.0,
        .ratio = 2.0,
        .attack_ms = 0.1,
        .release_ms = 10.0,
    });
    var output: f64 = 0.0;
    for (0..1_000) |_| output = compressor.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        std.math.pow(f64, 10.0, -3.0 / 20.0),
        output,
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -3.0),
        compressor.gainReductionDb(),
        0.000_01,
    );
}

test "compressor preserves signals below threshold and rejects bad config" {
    var compressor = try Compressor(f32).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -6.0,
        .attack_ms = 0.1,
        .release_ms = 0.1,
    });
    var samples = [_]f32{0.1} ** 32;
    compressor.process(&samples);
    for (samples) |sample|
        try std.testing.expectApproxEqAbs(@as(f32, 0.1), sample, 0.000_001);
    try std.testing.expectEqual(
        @as(f32, 0.0),
        compressor.processSample(std.math.nan(f32)),
    );
    try std.testing.expectError(
        error.InvalidCompressorConfig,
        compressor.configure(.{
            .sample_rate = 48_000.0,
            .ratio = 0.5,
        }),
    );
    compressor.envelope = std.math.nan(f64);
    try std.testing.expectEqual(
        @as(f32, 0.5),
        compressor.processSample(0.5),
    );
    try std.testing.expect(compressor.valid());
}

test "linked compressor applies one detector gain to every channel" {
    var compressor = try Compressor(f64).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -12.0,
        .ratio = 4.0,
        .attack_ms = 0.1,
        .release_ms = 20.0,
    });
    var frame = [2]f64{ 1.0, 0.1 };
    for (0..2_000) |_| {
        frame = .{ 1.0, 0.1 };
        try compressor.processLinkedFrame(&frame);
    }
    try std.testing.expect(compressor.gainReductionDb() < -8.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 10.0),
        frame[0] / frame[1],
        0.000_001,
    );
    var empty: [0]f64 = .{};
    try std.testing.expectError(
        error.EmptyLinkedCompressorFrame,
        compressor.processLinkedFrame(&empty),
    );
    compressor.envelope = std.math.nan(f64);
    var malformed = [2]f64{ std.math.nan(f64), 0.25 };
    try compressor.processLinkedFrame(&malformed);
    try std.testing.expectEqual(@as(f64, 0.0), malformed[0]);
    try std.testing.expectEqual(@as(f64, 0.25), malformed[1]);
    try std.testing.expect(compressor.valid());
}

test "noise gate applies its downward expansion curve" {
    var gate = try NoiseGate(f64).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -20.0,
        .ratio = 2.0,
        .attack_ms = 0.1,
        .release_ms = 0.1,
    });
    var output: f64 = 0.0;
    for (0..1_000) |_| output = gate.processSample(0.01);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.001),
        output,
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -20.0),
        gate.gainReductionDb(),
        0.000_1,
    );

    gate.reset();
    for (0..1_000) |_| output = gate.processSample(1.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), output, 0.000_001);
}

test "noise gate rejects invalid configuration and hostile state" {
    var gate = try NoiseGate(f32).init(.{ .sample_rate = 48_000.0 });
    try std.testing.expectError(
        error.InvalidNoiseGateConfig,
        gate.configure(.{ .sample_rate = 48_000.0, .ratio = 0.5 }),
    );
    gate.envelope = std.math.nan(f64);
    try std.testing.expectEqual(
        @as(f32, 0.5),
        gate.processSample(0.5),
    );
    try std.testing.expect(gate.valid());
}

test "limiter enforces its peak ceiling and releases" {
    var limiter = try Limiter(f64).init(.{
        .sample_rate = 48_000.0,
        .threshold_db = -6.0,
        .release_ms = 0.1,
    });
    const ceiling = std.math.pow(f64, 10.0, -6.0 / 20.0);
    try std.testing.expectApproxEqAbs(
        ceiling,
        limiter.processSample(2.0),
        0.000_000_001,
    );
    try std.testing.expect(limiter.gainReductionDb() < -6.0);
    for (0..1_000) |_| _ = limiter.processSample(0.1);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        limiter.gainReductionDb(),
        0.000_001,
    );
}

test "limiter rejects invalid configuration and non-finite input" {
    var limiter = try Limiter(f32).init(.{ .sample_rate = 48_000.0 });
    try std.testing.expectError(
        error.InvalidLimiterConfig,
        limiter.configure(.{
            .sample_rate = 48_000.0,
            .threshold_db = 1.0,
        }),
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        limiter.processSample(std.math.nan(f32)),
    );
    limiter.gain = std.math.inf(f64);
    try std.testing.expectEqual(
        @as(f32, 0.5),
        limiter.processSample(0.5),
    );
    try std.testing.expect(limiter.valid());
}

test "dynamics reject smoothing coefficients that cannot advance" {
    const extreme_rate = std.math.floatMax(f64);
    try std.testing.expectError(
        error.InvalidCompressorConfig,
        Compressor(f64).init(.{ .sample_rate = extreme_rate }),
    );
    try std.testing.expectError(
        error.InvalidNoiseGateConfig,
        NoiseGate(f64).init(.{ .sample_rate = extreme_rate }),
    );
    try std.testing.expectError(
        error.InvalidLimiterConfig,
        Limiter(f64).init(.{ .sample_rate = extreme_rate }),
    );

    var compressor =
        try Compressor(f64).init(.{ .sample_rate = 48_000.0 });
    const before = compressor;
    try std.testing.expectError(
        error.InvalidCompressorConfig,
        compressor.configure(.{ .sample_rate = extreme_rate }),
    );
    try std.testing.expectEqualDeep(before, compressor);

    const oversampled = try Limiter(f64).init(.{
        .sample_rate = 3_072_000.0,
        .release_ms = 10_000.0,
    });
    try std.testing.expect(oversampled.valid());
}

test "lookahead limiter delays and bounds a future peak" {
    const Processor = LookaheadLimiter(f64, 16);
    var limiter = try Processor.init(.{
        .sample_rate = 1_000.0,
        .threshold_db = -6.0,
        .release_ms = 10.0,
        .lookahead_ms = 4.0,
    });
    const ceiling = std.math.pow(f64, 10.0, -6.0 / 20.0);
    var input = [_]f64{ 0.25, 0.25, 2.0, 0.25, 0.25, 0.25, 0.25 };
    limiter.process(&input);
    try std.testing.expectEqual(@as(usize, 4), limiter.latencySamples());
    try std.testing.expectEqual(@as(f64, 0.0), input[3]);
    for (input[4..]) |sample|
        try std.testing.expect(@abs(sample) <= ceiling + 0.000_000_001);
    try std.testing.expectApproxEqAbs(ceiling, input[6], 0.000_000_001);
}

test "lookahead limiter matches independent scalar reference" {
    var limiter = try LookaheadLimiter(f64, 8).init(.{
        .sample_rate = 1_000.0,
        .threshold_db = -6.020599913279624,
        .release_ms = 5.0,
        .lookahead_ms = 2.0,
    });
    var samples = [_]f64{
        0.2,
        0.4,
        1.0,
        0.1,
        0.8,
        0.3,
        0.0,
        0.0,
        0.0,
        0.2,
    };
    const reference = [_]f64{
        0.0,
        0.0,
        0.1,
        0.2,
        0.5,
        0.05226586558652523,
        0.43296799539643605,
        0.18731235392520104,
        0.0,
        0.0,
    };
    limiter.process(&samples);
    for (reference, samples) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, 2.0e-14);
}

test "lookahead limiter is partition independent and rejects capacity" {
    const Processor = LookaheadLimiter(f32, 8);
    const config = LookaheadLimiterConfig{
        .sample_rate = 1_000.0,
        .threshold_db = -3.0,
        .release_ms = 20.0,
        .lookahead_ms = 3.0,
    };
    const source = [_]f32{ 0.1, 0.2, 1.5, -0.4, 0.3, 0.2, 0.1, 0.0 };
    var whole = try Processor.init(config);
    var whole_output = source;
    whole.process(&whole_output);
    var split = try Processor.init(config);
    var split_output = source;
    split.process(split_output[0..3]);
    split.process(split_output[3..]);
    try std.testing.expectEqualSlices(f32, &whole_output, &split_output);

    try std.testing.expectError(
        error.LookaheadLimiterCapacityExceeded,
        Processor.init(.{
            .sample_rate = 1_000.0,
            .lookahead_ms = 9.0,
        }),
    );
}

test "lookahead compressor anticipates a future transient" {
    const Processor = LookaheadCompressor(f64, 16);
    var processor = try Processor.init(.{
        .compressor = .{
            .sample_rate = 1_000.0,
            .threshold_db = -12.0,
            .ratio = 4.0,
            .attack_ms = 1.0,
            .release_ms = 20.0,
        },
        .lookahead_ms = 4.0,
    });
    try std.testing.expectEqual(@as(usize, 4), processor.latencySamples());
    var output: [9]f64 = undefined;
    const input = [_]f64{ 0.1, 0.1, 0.1, 0.1, 1.0, 0.1, 0.1, 0.1, 0.1 };
    for (input, 0..) |sample, index|
        output[index] = processor.processSample(sample);
    try std.testing.expect(output[4] < 0.1);
    try std.testing.expect(output[8] < 1.0);
    try std.testing.expect(processor.gainReductionDb() < 0.0);
}

test "lookahead compressor is partition independent and transactional" {
    const Processor = LookaheadCompressor(f32, 8);
    const config = LookaheadCompressorConfig{
        .compressor = .{
            .sample_rate = 1_000.0,
            .threshold_db = -9.0,
            .ratio = 3.0,
            .attack_ms = 1.0,
            .release_ms = 30.0,
        },
        .lookahead_ms = 3.0,
    };
    var input: [64]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = if (index % 11 == 0) 1.0 else 0.1;
    var whole = try Processor.init(config);
    var whole_output = input;
    whole.process(&whole_output);
    var split = try Processor.init(config);
    var split_output = input;
    split.process(split_output[0..23]);
    split.process(split_output[23..]);
    try std.testing.expectEqualSlices(f32, &whole_output, &split_output);
    const retained = split;
    try std.testing.expectError(
        error.LookaheadCompressorCapacityExceeded,
        split.configure(.{
            .compressor = config.compressor,
            .lookahead_ms = 9.0,
        }),
    );
    try std.testing.expectEqualDeep(retained, split);
    split.write_index = 99;
    try std.testing.expectEqual(
        @as(f32, 0.25),
        split.processSample(0.25),
    );
    try std.testing.expect(split.valid());
}
