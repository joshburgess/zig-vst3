const std = @import("std");

pub const Mode = enum {
    low_pass_12,
    high_pass_12,
    band_pass_12,
    low_pass_24,
    high_pass_24,
    band_pass_24,
};

pub const Config = struct {
    mode: Mode,
    sample_rate: f64,
    frequency_hz: f64,
    resonance: f64 = 0.0,
    drive: f64 = 1.0,
};

pub fn LadderFilter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LadderFilter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: Config,
        coefficient: Sample,
        feedback: Sample,
        drive: Sample,
        state: [4]Sample = @splat(0.0),

        pub fn init(config: Config) !Self {
            const derived = try calculate(Sample, config);
            return .{
                .config = config,
                .coefficient = derived.coefficient,
                .feedback = derived.feedback,
                .drive = derived.drive,
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const derived = try calculate(Sample, config);
            self.config = config;
            self.coefficient = derived.coefficient;
            self.feedback = derived.feedback;
            self.drive = derived.drive;
        }

        pub fn reset(self: *Self) void {
            self.state = @splat(0.0);
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.processingValid()) {
                self.reset();
                return accepted;
            }

            const feedback_input = accepted - self.feedback * self.state[3];
            var stage_input = std.math.tanh(
                feedback_input * self.drive,
            ) / self.drive;
            var stage_output: [4]Sample = undefined;
            for (0..4) |index| {
                const correction = self.coefficient *
                    (stage_input - self.state[index]);
                const low = correction + self.state[index];
                self.state[index] = correction + low;
                stage_output[index] = low;
                stage_input = low;
            }

            const output = switch (self.config.mode) {
                .low_pass_12 => stage_output[1],
                .high_pass_12 => accepted -
                    2.0 * stage_output[0] +
                    stage_output[1],
                .band_pass_12 => stage_output[0] - stage_output[1],
                .low_pass_24 => stage_output[3],
                .high_pass_24 => accepted -
                    4.0 * stage_output[0] +
                    6.0 * stage_output[1] -
                    4.0 * stage_output[2] +
                    stage_output[3],
                .band_pass_24 => stage_output[1] -
                    2.0 * stage_output[2] +
                    stage_output[3],
            };
            if (!std.math.isFinite(output)) {
                self.reset();
                return 0.0;
            }
            for (self.state) |value| {
                if (!std.math.isFinite(value)) {
                    self.reset();
                    return 0.0;
                }
            }
            return output;
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.LadderFilterBufferLengthMismatch;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            const derived = calculate(Sample, self.config) catch return false;
            if (self.coefficient != derived.coefficient or
                self.feedback != derived.feedback or
                self.drive != derived.drive)
                return false;
            for (self.state) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            return true;
        }

        fn processingValid(self: *const Self) bool {
            if (!std.math.isFinite(self.coefficient) or
                self.coefficient <= 0.0 or
                self.coefficient >= 1.0 or
                !std.math.isFinite(self.feedback) or
                self.feedback < 0.0 or
                self.feedback > 3.96 or
                !std.math.isFinite(self.drive) or
                self.drive < 0.1 or
                self.drive > 20.0)
                return false;
            for (self.state) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            return true;
        }
    };
}

fn Derived(comptime Sample: type) type {
    return struct {
        coefficient: Sample,
        feedback: Sample,
        drive: Sample,
    };
}

fn calculate(comptime Sample: type, config: Config) !Derived(Sample) {
    try validateConfig(config);
    const warped = @tan(std.math.pi * config.frequency_hz /
        config.sample_rate);
    const result = Derived(Sample){
        .coefficient = @floatCast(warped / (1.0 + warped)),
        .feedback = @floatCast(config.resonance * 3.96),
        .drive = @floatCast(config.drive),
    };
    if (!std.math.isFinite(result.coefficient) or
        !std.math.isFinite(result.feedback) or
        !std.math.isFinite(result.drive))
        return error.InvalidLadderFilterConfig;
    return result;
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.frequency_hz) or
        config.frequency_hz < 1.0 or
        config.frequency_hz >= config.sample_rate * 0.49 or
        !std.math.isFinite(config.resonance) or
        config.resonance < 0.0 or
        config.resonance > 1.0 or
        !std.math.isFinite(config.drive) or
        config.drive < 0.1 or
        config.drive > 20.0)
        return error.InvalidLadderFilterConfig;
}

test "ladder low-pass separates low and high frequencies" {
    var filter = try LadderFilter(f64).init(.{
        .mode = .low_pass_24,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
        .resonance = 0.2,
    });
    var low_energy: f64 = 0.0;
    var high_energy: f64 = 0.0;
    for (0..4_096) |index| {
        const phase: f64 = @floatFromInt(index);
        const output = filter.processSample(
            0.01 * @sin(std.math.tau * 100.0 * phase / 48_000.0),
        );
        if (index >= 2_048) low_energy += output * output;
    }
    filter.reset();
    for (0..4_096) |index| {
        const phase: f64 = @floatFromInt(index);
        const output = filter.processSample(
            0.01 * @sin(std.math.tau * 10_000.0 * phase / 48_000.0),
        );
        if (index >= 2_048) high_energy += output * output;
    }
    try std.testing.expect(low_energy > high_energy * 100.0);
}

test "ladder processing is independent of block partitioning" {
    const Filter = LadderFilter(f32);
    const config = Config{
        .mode = .band_pass_24,
        .sample_rate = 48_000.0,
        .frequency_hz = 2_000.0,
        .resonance = 0.95,
        .drive = 4.0,
    };
    var whole = try Filter.init(config);
    var split = try Filter.init(config);
    var input: [128]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = if (index == 0) 1.0 else 0.0;
    var whole_output: [128]f32 = undefined;
    var split_output: [128]f32 = undefined;
    try whole.process(&input, &whole_output);
    try split.process(input[0..37], split_output[0..37]);
    try split.process(input[37..], split_output[37..]);
    try std.testing.expectEqualSlices(f32, &whole_output, &split_output);
    for (whole_output) |sample| try std.testing.expect(std.math.isFinite(sample));
}

test "ladder rejects invalid config and contains hostile state" {
    try std.testing.expectError(
        error.InvalidLadderFilterConfig,
        LadderFilter(f32).init(.{
            .mode = .low_pass_12,
            .sample_rate = 48_000.0,
            .frequency_hz = 1_000.0,
            .resonance = 1.1,
        }),
    );
    var filter = try LadderFilter(f32).init(.{
        .mode = .high_pass_12,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    filter.state[0] = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 0.25), filter.processSample(0.25));
    try std.testing.expectEqualDeep([4]f32{ 0.0, 0.0, 0.0, 0.0 }, filter.state);
}
