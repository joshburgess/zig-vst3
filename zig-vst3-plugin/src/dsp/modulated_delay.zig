const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");
const delay = @import("delay.zig");
const dry_wet = @import("dry_wet.zig");
const modulation_rate = @import("modulation_rate.zig");
const smoothed_value = @import("smoothed_value.zig");

pub const Config = struct {
    sample_rate: f64,
    rate_hz: f64,
    center_delay_ms: f64,
    depth_ms: f64,
    feedback: f64,
    mix: f64,
    mixing_rule: dry_wet.MixingRule,
};

pub fn Processor(
    comptime Sample: type,
    comptime maximum_delay_samples: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("modulated delay supports f32 and f64 samples");
    if (maximum_delay_samples < 4)
        @compileError("modulated delay capacity must be at least four samples");

    const Delay = delay.DelayLine(Sample, maximum_delay_samples);

    return struct {
        const Self = @This();

        config: Config,
        delay_line: Delay = .{},
        phase: f64 = 0.0,
        feedback_sample: Sample = 0.0,
        lfo_rate: modulation_rate.RateSmoother,
        center_delay_ms: smoothed_value.Linear,
        depth_ms: smoothed_value.Linear,
        feedback: smoothed_value.Linear,
        mix: smoothed_value.Linear,

        pub fn init(config: Config) !Self {
            try validateConfig(config);
            return .{
                .config = config,
                .lfo_rate = try modulation_rate.RateSmoother.init(
                    config.sample_rate,
                    config.rate_hz,
                ),
                .center_delay_ms = try smoother(
                    config,
                    config.center_delay_ms,
                    0.0,
                    maximumDelayMs(),
                ),
                .depth_ms = try smoother(
                    config,
                    config.depth_ms,
                    0.0,
                    maximumDelayMs(),
                ),
                .feedback = try smoother(config, config.feedback, -0.99, 0.99),
                .mix = try smoother(config, config.mix, 0.0, 1.0),
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            try validateConfig(config);
            var next_rate = self.lfo_rate;
            try next_rate.setImmediate(config.sample_rate, config.rate_hz);
            var next_center = self.center_delay_ms;
            var next_depth = self.depth_ms;
            var next_feedback = self.feedback;
            var next_mix = self.mix;
            try next_center.setImmediate(
                config.sample_rate,
                config.center_delay_ms,
            );
            try next_depth.setImmediate(config.sample_rate, config.depth_ms);
            try next_feedback.setImmediate(config.sample_rate, config.feedback);
            try next_mix.setImmediate(config.sample_rate, config.mix);
            self.config = config;
            self.lfo_rate = next_rate;
            self.center_delay_ms = next_center;
            self.depth_ms = next_depth;
            self.feedback = next_feedback;
            self.mix = next_mix;
        }

        pub fn configureSmooth(
            self: *Self,
            config: Config,
            smoothing_seconds: f64,
        ) !void {
            try validateConfig(config);
            if (config.sample_rate != self.config.sample_rate)
                return self.configure(config);
            var next_rate = self.lfo_rate;
            var next_center = self.center_delay_ms;
            var next_depth = self.depth_ms;
            var next_feedback = self.feedback;
            var next_mix = self.mix;
            try next_rate.setTarget(
                config.sample_rate,
                config.rate_hz,
                smoothing_seconds,
            );
            try next_center.setTarget(
                config.sample_rate,
                config.center_delay_ms,
                smoothing_seconds,
            );
            try next_depth.setTarget(
                config.sample_rate,
                config.depth_ms,
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
            self.center_delay_ms = next_center;
            self.depth_ms = next_depth;
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
                return error.InvalidModulatedDelayPhase;
            self.delay_line.reset();
            self.phase = phase - @floor(phase);
            self.feedback_sample = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const dry = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.delay_line.reset();
                self.phase = 0.0;
                self.feedback_sample = 0.0;
                self.lfo_rate = modulation_rate.RateSmoother.init(
                    self.config.sample_rate,
                    self.config.rate_hz,
                ) catch return dry;
                self.resetParameterSmoothers() catch return dry;
                return dry;
            }

            const modulation = @sin(std.math.tau * self.phase);
            const center_delay_ms = self.center_delay_ms.next();
            const depth_ms = self.depth_ms.next();
            const feedback = self.feedback.next();
            const mix = self.mix.next();
            const delay_samples =
                (center_delay_ms + depth_ms * modulation) *
                self.config.sample_rate /
                1_000.0;
            const delay_input = dry +
                self.feedback_sample *
                    @as(Sample, @floatCast(feedback));
            const wet = self.delay_line.processSample(
                delay_input,
                delay_samples,
                .cubic,
            ) catch {
                self.delay_line.reset();
                self.feedback_sample = 0.0;
                return dry;
            };
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
                return error.ModulatedDelayBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.ModulatedDelayBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            return self.delay_line.valid() and
                self.lfo_rate.valid() and
                self.lfo_rate.sample_rate == self.config.sample_rate and
                self.lfo_rate.target_hz == self.config.rate_hz and
                self.center_delay_ms.valid() and
                self.center_delay_ms.target ==
                    self.config.center_delay_ms and
                self.depth_ms.valid() and
                self.depth_ms.target == self.config.depth_ms and
                self.feedback.valid() and
                self.feedback.target == self.config.feedback and
                self.mix.valid() and
                self.mix.target == self.config.mix and
                std.math.isFinite(self.phase) and
                self.phase >= 0.0 and
                self.phase < 1.0 and
                std.math.isFinite(self.feedback_sample);
        }

        fn validateConfig(config: Config) !void {
            if (!std.math.isFinite(config.sample_rate) or
                config.sample_rate < 1_000.0 or
                config.sample_rate > 768_000.0 or
                !std.math.isFinite(config.rate_hz) or
                config.rate_hz < 0.0 or
                config.rate_hz > 20.0 or
                !std.math.isFinite(config.center_delay_ms) or
                !std.math.isFinite(config.depth_ms) or
                config.depth_ms < 0.0 or
                !std.math.isFinite(config.feedback) or
                config.feedback <= -0.99 or
                config.feedback >= 0.99 or
                !std.math.isFinite(config.mix) or
                config.mix < 0.0 or
                config.mix > 1.0)
                return error.InvalidModulatedDelayConfig;

            const center_samples =
                config.center_delay_ms * config.sample_rate / 1_000.0;
            const depth_samples =
                config.depth_ms * config.sample_rate / 1_000.0;
            if (!std.math.isFinite(center_samples) or
                !std.math.isFinite(depth_samples) or
                center_samples - depth_samples < 1.0 or
                center_samples + depth_samples >
                    @as(f64, @floatFromInt(maximum_delay_samples - 2)))
                return error.InvalidModulatedDelayConfig;
        }

        fn resetParameterSmoothers(self: *Self) !void {
            self.center_delay_ms = try smoother(
                self.config,
                self.config.center_delay_ms,
                0.0,
                maximumDelayMs(),
            );
            self.depth_ms = try smoother(
                self.config,
                self.config.depth_ms,
                0.0,
                maximumDelayMs(),
            );
            self.feedback = try smoother(
                self.config,
                self.config.feedback,
                -0.99,
                0.99,
            );
            self.mix = try smoother(
                self.config,
                self.config.mix,
                0.0,
                1.0,
            );
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

        fn maximumDelayMs() f64 {
            return @as(f64, @floatFromInt(maximum_delay_samples - 2));
        }
    };
}

test "modulated delay produces its static delay and mix" {
    const Effect = Processor(f64, 32);
    var effect = try Effect.init(.{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .center_delay_ms = 4.0,
        .depth_ms = 0.0,
        .feedback = 0.0,
        .mix = 1.0,
        .mixing_rule = .linear,
    });
    var input: [8]f64 = @splat(0.0);
    input[0] = 1.0;
    var output: [8]f64 = undefined;
    try effect.process(&input, &output);
    try std.testing.expectEqual(@as(f64, 1.0), output[4]);
}

test "modulated delay is independent of block partitioning" {
    const Effect = Processor(f32, 512);
    const config = Config{
        .sample_rate = 48_000.0,
        .rate_hz = 1.5,
        .center_delay_ms = 3.0,
        .depth_ms = 1.5,
        .feedback = 0.4,
        .mix = 0.5,
        .mixing_rule = .linear,
    };
    var input: [96]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @sin(
            std.math.tau *
                440.0 *
                @as(f32, @floatFromInt(index)) /
                48_000.0,
        );
    }
    var whole = try Effect.init(config);
    var whole_output: [96]f32 = undefined;
    try whole.process(&input, &whole_output);
    var partitioned = try Effect.init(config);
    var partitioned_output: [96]f32 = undefined;
    try partitioned.process(input[0..31], partitioned_output[0..31]);
    try partitioned.process(input[31..], partitioned_output[31..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
}

test "modulated delay rejects config and contains hostile state" {
    const Effect = Processor(f32, 256);
    var effect = try Effect.init(.{
        .sample_rate = 48_000.0,
        .rate_hz = 0.5,
        .center_delay_ms = 3.0,
        .depth_ms = 1.0,
        .feedback = 0.0,
        .mix = 0.5,
        .mixing_rule = .linear,
    });
    try std.testing.expectError(
        error.InvalidModulatedDelayConfig,
        effect.configure(.{
            .sample_rate = 48_000.0,
            .rate_hz = 0.5,
            .center_delay_ms = 1.0,
            .depth_ms = 2.0,
            .feedback = 0.0,
            .mix = 0.5,
            .mixing_rule = .linear,
        }),
    );
    effect.phase = std.math.nan(f64);
    try std.testing.expectEqual(
        @as(f32, 0.25),
        effect.processSample(0.25),
    );
    try std.testing.expect(effect.valid());
}

test "modulated delay tempo changes smooth without block dependence" {
    const Effect = Processor(f64, 64);
    const config = Config{
        .sample_rate = 1_000.0,
        .rate_hz = 1.0,
        .center_delay_ms = 4.0,
        .depth_ms = 1.0,
        .feedback = 0.0,
        .mix = 0.5,
        .mixing_rule = .linear,
    };
    var whole = try Effect.init(config);
    try whole.syncTempo(120.0, .quarter, 0.004);
    var whole_output: [8]f64 = undefined;
    try whole.process(&@as([8]f64, @splat(0.0)), &whole_output);

    var partitioned = try Effect.init(config);
    try partitioned.syncTempo(120.0, .quarter, 0.004);
    var partitioned_output: [8]f64 = undefined;
    const input: [8]f64 = @splat(0.0);
    try partitioned.process(input[0..3], partitioned_output[0..3]);
    try partitioned.process(input[3..], partitioned_output[3..]);
    try std.testing.expectEqual(whole.phase, partitioned.phase);
    try std.testing.expectEqual(@as(f64, 2.0), whole.config.rate_hz);
    try std.testing.expectEqual(@as(f64, 2.0), whole.lfo_rate.current_hz);

    const before = whole;
    try std.testing.expectError(
        error.InvalidModulationTempo,
        whole.syncTempo(0.0, .quarter, 0.1),
    );
    try std.testing.expectEqualDeep(before, whole);
}

test "modulated delay smooths delay feedback and mix parameters" {
    const Effect = Processor(f64, 32);
    var effect = try Effect.init(.{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .center_delay_ms = 4.0,
        .depth_ms = 1.0,
        .feedback = 0.0,
        .mix = 0.0,
        .mixing_rule = .linear,
    });
    try effect.configureSmooth(.{
        .sample_rate = 1_000.0,
        .rate_hz = 0.0,
        .center_delay_ms = 8.0,
        .depth_ms = 2.0,
        .feedback = 0.5,
        .mix = 1.0,
        .mixing_rule = .linear,
    }, 0.004);
    try std.testing.expectEqual(@as(usize, 4), effect.mix.remaining_samples);
    for (0..5) |_| _ = effect.processSample(0.0);
    try std.testing.expectEqual(@as(f64, 8.0), effect.center_delay_ms.current);
    try std.testing.expectEqual(@as(f64, 2.0), effect.depth_ms.current);
    try std.testing.expectEqual(@as(f64, 0.5), effect.feedback.current);
    try std.testing.expectEqual(@as(f64, 1.0), effect.mix.current);
}

test "modulated delay permits in-place buffers and rejects shifted overlap" {
    const Effect = Processor(f32, 512);
    var effect = try Effect.init(.{
        .sample_rate = 48_000.0,
        .rate_hz = 1.0,
        .center_delay_ms = 3.0,
        .depth_ms = 1.0,
        .feedback = 0.25,
        .mix = 0.5,
        .mixing_rule = .linear,
    });
    var storage = [_]f32{ 1.0, 0.5, 0.25, 0.0 };
    const retained = storage;
    const before = effect;
    try std.testing.expectError(
        error.ModulatedDelayBufferOverlap,
        effect.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, effect);
    try std.testing.expectEqualSlices(f32, &retained, &storage);
    try effect.process(&storage, &storage);
    for (storage) |sample| try std.testing.expect(std.math.isFinite(sample));
}
