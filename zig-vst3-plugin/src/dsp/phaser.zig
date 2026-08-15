const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");
const dry_wet = @import("dry_wet.zig");
const modulation_rate = @import("modulation_rate.zig");
const smoothed_value = @import("smoothed_value.zig");

pub const Config = struct {
    sample_rate: f64,
    rate_hz: f64 = 0.5,
    minimum_hz: f64 = 300.0,
    maximum_hz: f64 = 2_000.0,
    feedback: f64 = 0.0,
    mix: f64 = 0.5,
    mixing_rule: dry_wet.MixingRule = .equal_power,

    pub fn validate(self: Config) !void {
        if (!std.math.isFinite(self.sample_rate) or
            self.sample_rate < 1_000.0 or
            self.sample_rate > 768_000.0 or
            !std.math.isFinite(self.rate_hz) or
            self.rate_hz < 0.0 or
            self.rate_hz > 20.0 or
            !std.math.isFinite(self.minimum_hz) or
            !std.math.isFinite(self.maximum_hz) or
            self.minimum_hz < 10.0 or
            self.minimum_hz > self.maximum_hz or
            self.maximum_hz > self.sample_rate * 0.45 or
            !std.math.isFinite(self.feedback) or
            self.feedback <= -0.99 or
            self.feedback >= 0.99 or
            !std.math.isFinite(self.mix) or
            self.mix < 0.0 or
            self.mix > 1.0)
            return error.InvalidPhaserConfig;
    }
};

pub fn Phaser(
    comptime Sample: type,
    comptime stage_count: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Phaser supports f32 and f64 samples");
    if (stage_count == 0 or stage_count > 16)
        @compileError("Phaser stage count must be from one through sixteen");

    return struct {
        const Self = @This();

        config: Config,
        state: [stage_count]Sample = @splat(0.0),
        phase: f64 = 0.0,
        feedback_sample: Sample = 0.0,
        lfo_rate: modulation_rate.RateSmoother,
        minimum_hz: smoothed_value.Linear,
        maximum_hz: smoothed_value.Linear,
        feedback: smoothed_value.Linear,
        mix: smoothed_value.Linear,

        pub fn init(config: Config) !Self {
            try config.validate();
            return .{
                .config = config,
                .lfo_rate = try modulation_rate.RateSmoother.init(
                    config.sample_rate,
                    config.rate_hz,
                ),
                .minimum_hz = try smoother(
                    config,
                    config.minimum_hz,
                    10.0,
                    768_000.0 * 0.45,
                ),
                .maximum_hz = try smoother(
                    config,
                    config.maximum_hz,
                    10.0,
                    768_000.0 * 0.45,
                ),
                .feedback = try smoother(
                    config,
                    config.feedback,
                    -0.99,
                    0.99,
                ),
                .mix = try smoother(config, config.mix, 0.0, 1.0),
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            try config.validate();
            var next_rate = self.lfo_rate;
            try next_rate.setImmediate(config.sample_rate, config.rate_hz);
            var next_minimum = self.minimum_hz;
            var next_maximum = self.maximum_hz;
            var next_feedback = self.feedback;
            var next_mix = self.mix;
            try next_minimum.setImmediate(
                config.sample_rate,
                config.minimum_hz,
            );
            try next_maximum.setImmediate(
                config.sample_rate,
                config.maximum_hz,
            );
            try next_feedback.setImmediate(
                config.sample_rate,
                config.feedback,
            );
            try next_mix.setImmediate(config.sample_rate, config.mix);
            self.config = config;
            self.lfo_rate = next_rate;
            self.minimum_hz = next_minimum;
            self.maximum_hz = next_maximum;
            self.feedback = next_feedback;
            self.mix = next_mix;
        }

        pub fn configureSmooth(
            self: *Self,
            config: Config,
            smoothing_seconds: f64,
        ) !void {
            try config.validate();
            if (config.sample_rate != self.config.sample_rate)
                return self.configure(config);
            var next_rate = self.lfo_rate;
            var next_minimum = self.minimum_hz;
            var next_maximum = self.maximum_hz;
            var next_feedback = self.feedback;
            var next_mix = self.mix;
            try next_rate.setTarget(
                config.sample_rate,
                config.rate_hz,
                smoothing_seconds,
            );
            try next_minimum.setImmediate(
                config.sample_rate,
                next_minimum.current,
            );
            try next_maximum.setImmediate(
                config.sample_rate,
                next_maximum.current,
            );
            try next_minimum.setTarget(
                config.sample_rate,
                config.minimum_hz,
                smoothing_seconds,
            );
            try next_maximum.setTarget(
                config.sample_rate,
                config.maximum_hz,
                smoothing_seconds,
            );
            try next_feedback.setTarget(
                config.sample_rate,
                config.feedback,
                smoothing_seconds,
            );
            try next_mix.setTarget(
                config.sample_rate,
                config.mix,
                smoothing_seconds,
            );
            self.config = config;
            self.lfo_rate = next_rate;
            self.minimum_hz = next_minimum;
            self.maximum_hz = next_maximum;
            self.feedback = next_feedback;
            self.mix = next_mix;
        }

        pub fn syncTempo(
            self: *Self,
            bpm: f64,
            division: modulation_rate.NoteDivision,
            smoothing_seconds: f64,
        ) !void {
            var config = self.config;
            config.rate_hz = try modulation_rate.rateHz(bpm, division);
            try self.configureSmooth(config, smoothing_seconds);
        }

        pub fn syncTransport(
            self: *Self,
            transport: ?@import("../process/context.zig").Transport,
            fallback_bpm: f64,
            division: modulation_rate.NoteDivision,
            smoothing_seconds: f64,
        ) !void {
            return self.syncTempo(
                try modulation_rate.tempoFromTransport(
                    transport,
                    fallback_bpm,
                ),
                division,
                smoothing_seconds,
            );
        }

        pub fn reset(self: *Self, phase: f64) !void {
            if (!std.math.isFinite(phase))
                return error.InvalidPhaserPhase;
            self.state = @splat(0.0);
            self.phase = phase - @floor(phase);
            self.feedback_sample = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const dry = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.clearProcessing();
                return dry;
            }

            const modulation =
                0.5 + 0.5 * @sin(std.math.tau * self.phase);
            const minimum_hz = self.minimum_hz.next();
            const maximum_hz = self.maximum_hz.next();
            const feedback = self.feedback.next();
            const mix = self.mix.next();
            const frequency =
                minimum_hz *
                std.math.pow(
                    f64,
                    maximum_hz / minimum_hz,
                    modulation,
                );
            const tangent =
                @tan(std.math.pi * frequency / self.config.sample_rate);
            const coefficient: Sample =
                @floatCast((1.0 - tangent) / (1.0 + tangent));
            var wet =
                dry +
                self.feedback_sample *
                    @as(Sample, @floatCast(feedback));
            for (&self.state) |*stage_state| {
                const output = coefficient * wet + stage_state.*;
                stage_state.* = wet - coefficient * output;
                wet = output;
            }
            if (!std.math.isFinite(wet)) {
                self.clearProcessing();
                return 0.0;
            }
            self.feedback_sample = wet;
            self.phase += self.lfo_rate.next() / self.config.sample_rate;
            self.phase -= @floor(self.phase);

            const gains = dry_wet.mixingGains(
                Sample,
                mix,
                self.config.mixing_rule,
            );
            const output = dry * gains.dry + wet * gains.wet;
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.PhaserBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.PhaserBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            self.config.validate() catch return false;
            if (!self.lfo_rate.valid() or
                self.lfo_rate.sample_rate != self.config.sample_rate or
                self.lfo_rate.target_hz != self.config.rate_hz or
                !self.minimum_hz.valid() or
                self.minimum_hz.sample_rate != self.config.sample_rate or
                self.minimum_hz.target != self.config.minimum_hz or
                !self.maximum_hz.valid() or
                self.maximum_hz.sample_rate !=
                    self.config.sample_rate or
                self.maximum_hz.target != self.config.maximum_hz or
                self.minimum_hz.current > self.maximum_hz.current or
                self.minimum_hz.remaining_samples !=
                    self.maximum_hz.remaining_samples or
                !frequencyTrajectoryValid(
                    self.minimum_hz,
                    self.maximum_hz,
                    self.config.sample_rate,
                ) or
                !self.feedback.valid() or
                self.feedback.sample_rate != self.config.sample_rate or
                self.feedback.target != self.config.feedback or
                !self.mix.valid() or
                self.mix.sample_rate != self.config.sample_rate or
                self.mix.target != self.config.mix or
                !std.math.isFinite(self.phase) or
                self.phase < 0.0 or
                self.phase >= 1.0 or
                !std.math.isFinite(self.feedback_sample))
                return false;
            for (self.state) |stage_state| {
                if (!std.math.isFinite(stage_state)) return false;
            }
            return true;
        }

        fn frequencyTrajectoryValid(
            minimum: smoothed_value.Linear,
            maximum: smoothed_value.Linear,
            sample_rate: f64,
        ) bool {
            const remaining: f64 =
                @floatFromInt(minimum.remaining_samples);
            const final_minimum =
                minimum.current + minimum.step * remaining;
            const final_maximum =
                maximum.current + maximum.step * remaining;
            return std.math.isFinite(final_minimum) and
                std.math.isFinite(final_maximum) and
                final_minimum >= 10.0 and
                final_minimum <= final_maximum and
                final_maximum <= sample_rate * 0.45;
        }

        fn clearProcessing(self: *Self) void {
            self.state = @splat(0.0);
            self.phase = 0.0;
            self.feedback_sample = 0.0;
            self.lfo_rate = modulation_rate.RateSmoother.init(
                self.config.sample_rate,
                self.config.rate_hz,
            ) catch self.lfo_rate;
            self.minimum_hz = smoother(
                self.config,
                self.config.minimum_hz,
                10.0,
                768_000.0 * 0.45,
            ) catch self.minimum_hz;
            self.maximum_hz = smoother(
                self.config,
                self.config.maximum_hz,
                10.0,
                768_000.0 * 0.45,
            ) catch self.maximum_hz;
            self.feedback = smoother(
                self.config,
                self.config.feedback,
                -0.99,
                0.99,
            ) catch self.feedback;
            self.mix = smoother(
                self.config,
                self.config.mix,
                0.0,
                1.0,
            ) catch self.mix;
        }

        fn smoother(
            config: Config,
            value: f64,
            minimum: f64,
            maximum: f64,
        ) !smoothed_value.Linear {
            return smoothed_value.Linear.init(
                config.sample_rate,
                value,
                minimum,
                maximum,
            );
        }
    };
}

test "static phaser cascade preserves all-pass energy" {
    const Effect = Phaser(f64, 4);
    var phaser = try Effect.init(.{
        .sample_rate = 48_000.0,
        .rate_hz = 0.0,
        .minimum_hz = 1_000.0,
        .maximum_hz = 1_000.0,
        .feedback = 0.0,
        .mix = 1.0,
        .mixing_rule = .linear,
    });
    var energy: f64 = 0.0;
    for (0..2_048) |index| {
        const sample = phaser.processSample(
            if (index == 0) 1.0 else 0.0,
        );
        energy += sample * sample;
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        energy,
        0.000_000_001,
    );
}

test "phaser output is independent of block partitioning" {
    const Effect = Phaser(f32, 6);
    const config = Config{
        .sample_rate = 48_000.0,
        .rate_hz = 0.7,
        .minimum_hz = 200.0,
        .maximum_hz = 4_000.0,
        .feedback = 0.4,
        .mix = 0.65,
    };
    var input: [128]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @floatCast(@sin(
            std.math.tau *
                330.0 *
                @as(f64, @floatFromInt(index)) /
                48_000.0,
        ));
    }

    var whole = try Effect.init(config);
    var whole_output: [128]f32 = undefined;
    try whole.process(&input, &whole_output);

    var partitioned = try Effect.init(config);
    var partitioned_output: [128]f32 = undefined;
    try partitioned.process(input[0..51], partitioned_output[0..51]);
    try partitioned.process(input[51..], partitioned_output[51..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
}

test "phaser rejects invalid config and contains hostile state" {
    const Effect = Phaser(f32, 4);
    var phaser = try Effect.init(.{ .sample_rate = 48_000.0 });
    try std.testing.expectError(
        error.InvalidPhaserConfig,
        phaser.configure(.{
            .sample_rate = 48_000.0,
            .minimum_hz = 2_000.0,
            .maximum_hz = 1_000.0,
        }),
    );
    try std.testing.expect(phaser.valid());
    phaser.state[1] = std.math.nan(f32);
    try std.testing.expectEqual(
        @as(f32, 0.25),
        phaser.processSample(0.25),
    );
    try std.testing.expectEqual(@as(f32, 0.0), phaser.state[1]);
}

test "phaser exposes tempo synchronization and smoothing" {
    const Effect = Phaser(f32, 4);
    var phaser = try Effect.init(.{ .sample_rate = 48_000.0 });
    try phaser.syncTempo(120.0, .half, 0.02);
    try std.testing.expectEqual(@as(f64, 1.0), phaser.config.rate_hz);
    try std.testing.expect(phaser.valid());
}

test "phaser smooths frequency range feedback and mix transactionally" {
    const Effect = Phaser(f64, 4);
    const initial = Config{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .minimum_hz = 100.0,
        .maximum_hz = 200.0,
        .feedback = 0.0,
        .mix = 0.0,
        .mixing_rule = .linear,
    };
    const target = Config{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .minimum_hz = 200.0,
        .maximum_hz = 400.0,
        .feedback = 0.8,
        .mix = 1.0,
        .mixing_rule = .linear,
    };
    var phaser = try Effect.init(initial);
    const before = phaser;
    try std.testing.expectError(
        error.InvalidModulationSmoothing,
        phaser.configureSmooth(target, -0.1),
    );
    try std.testing.expectEqualDeep(before, phaser);

    try phaser.configureSmooth(target, 0.004);
    try std.testing.expectEqual(@as(f64, 100.0), phaser.minimum_hz.current);
    try std.testing.expectEqual(@as(f64, 200.0), phaser.maximum_hz.current);
    try std.testing.expectEqual(@as(f64, 0.0), phaser.feedback.current);
    try std.testing.expectEqual(@as(f64, 0.0), phaser.mix.current);
    _ = phaser.processSample(0.25);
    try std.testing.expectEqual(@as(f64, 125.0), phaser.minimum_hz.current);
    try std.testing.expectEqual(@as(f64, 250.0), phaser.maximum_hz.current);
    try std.testing.expectEqual(@as(f64, 0.2), phaser.feedback.current);
    try std.testing.expectEqual(@as(f64, 0.25), phaser.mix.current);
    for (0..3) |_| _ = phaser.processSample(0.25);
    try std.testing.expectEqual(
        target.minimum_hz,
        phaser.minimum_hz.current,
    );
    try std.testing.expectEqual(
        target.maximum_hz,
        phaser.maximum_hz.current,
    );
    try std.testing.expectEqual(target.feedback, phaser.feedback.current);
    try std.testing.expectEqual(target.mix, phaser.mix.current);
    try std.testing.expect(phaser.valid());

    phaser.maximum_hz.remaining_samples = 1;
    try std.testing.expectEqual(
        @as(f64, 0.25),
        phaser.processSample(0.25),
    );
    try std.testing.expect(phaser.valid());
    phaser.minimum_hz.remaining_samples = 1;
    phaser.maximum_hz.remaining_samples = 1;
    phaser.minimum_hz.step = 1_000.0;
    try std.testing.expectEqual(
        @as(f64, 0.25),
        phaser.processSample(0.25),
    );
    try std.testing.expect(phaser.valid());
}

test "phaser permits in-place buffers and rejects shifted overlap" {
    const Effect = Phaser(f32, 4);
    var effect = try Effect.init(.{ .sample_rate = 48_000.0 });
    var storage = [_]f32{ 1.0, 0.5, 0.25, 0.0 };
    const retained = storage;
    const before = effect;
    try std.testing.expectError(
        error.PhaserBufferOverlap,
        effect.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, effect);
    try std.testing.expectEqualSlices(f32, &retained, &storage);
    try effect.process(&storage, &storage);
    for (storage) |sample| try std.testing.expect(std.math.isFinite(sample));
}
