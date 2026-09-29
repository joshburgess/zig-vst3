const std = @import("std");
const biquad = @import("biquad.zig");

pub const Config = struct {
    sample_rate: f64,
    frequency_hz: f64,
};

pub fn Split(comptime Sample: type) type {
    return struct {
        low: Sample,
        high: Sample,
    };
}

pub fn LinkwitzRileyFilter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LinkwitzRileyFilter supports f32 and f64 samples");

    const Biquad = biquad.SmoothedBiquad(Sample);

    return struct {
        const Self = @This();

        config: Config,
        low: [2]Biquad = .{ .{}, .{} },
        high: [2]Biquad = .{ .{}, .{} },

        pub fn init(config: Config) !Self {
            const coefficients = try calculate(config);
            var self = Self{ .config = config };
            self.apply(coefficients);
            return self;
        }

        pub fn configure(
            self: *Self,
            config: Config,
            transition_samples: usize,
        ) !void {
            const coefficients = try calculate(config);
            self.config = config;
            for (&self.low) |*stage|
                stage.setTarget(coefficients.low, transition_samples);
            for (&self.high) |*stage|
                stage.setTarget(coefficients.high, transition_samples);
        }

        pub fn reset(self: *Self) void {
            for (&self.low) |*stage| stage.reset();
            for (&self.high) |*stage| stage.reset();
        }

        pub fn processSample(self: *Self, input: Sample) Split(Sample) {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.processingValid()) {
                const coefficients = calculate(self.config) catch {
                    self.reset();
                    return .{ .low = accepted, .high = 0.0 };
                };
                self.apply(coefficients);
                return .{ .low = accepted, .high = 0.0 };
            }

            var low_output = accepted;
            for (&self.low) |*stage| low_output = stage.process(low_output);
            var high_output = accepted;
            for (&self.high) |*stage|
                high_output = stage.process(high_output);
            if (!std.math.isFinite(low_output) or
                !std.math.isFinite(high_output))
            {
                self.reset();
                return .{ .low = 0.0, .high = 0.0 };
            }
            return .{ .low = low_output, .high = high_output };
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            low_output: []Sample,
            high_output: []Sample,
        ) !void {
            if (input.len != low_output.len or input.len != high_output.len)
                return error.LinkwitzRileyBufferLengthMismatch;
            for (input, low_output, high_output) |
                input_sample,
                *low_sample,
                *high_sample,
            | {
                const split = self.processSample(input_sample);
                low_sample.* = split.low;
                high_sample.* = split.high;
            }
        }

        pub fn valid(self: *const Self) bool {
            const expected = calculate(self.config) catch return false;
            for (self.low) |stage| {
                if (!stageValid(stage) or
                    !std.meta.eql(stage.target, expected.low))
                    return false;
            }
            for (self.high) |stage| {
                if (!stageValid(stage) or
                    !std.meta.eql(stage.target, expected.high))
                    return false;
            }
            return true;
        }

        fn processingValid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            for (self.low) |stage| {
                if (!stageValid(stage)) return false;
            }
            for (self.high) |stage| {
                if (!stageValid(stage)) return false;
            }
            return true;
        }

        fn apply(self: *Self, coefficients: CoefficientPair) void {
            for (&self.low) |*stage| stage.setImmediate(coefficients.low);
            for (&self.high) |*stage| stage.setImmediate(coefficients.high);
            self.reset();
        }
    };
}

const CoefficientPair = struct {
    low: biquad.Coefficients,
    high: biquad.Coefficients,
};

fn calculate(config: Config) !CoefficientPair {
    try validateConfig(config);
    const q = 1.0 / @sqrt(2.0);
    return .{
        .low = try (biquad.Config{
            .kind = .low_pass,
            .sample_rate = config.sample_rate,
            .frequency_hz = config.frequency_hz,
            .gain_db = 0.0,
            .q = q,
        }).coefficients(),
        .high = try (biquad.Config{
            .kind = .high_pass,
            .sample_rate = config.sample_rate,
            .frequency_hz = config.frequency_hz,
            .gain_db = 0.0,
            .q = q,
        }).coefficients(),
    };
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.frequency_hz) or
        config.frequency_hz < 1.0 or
        config.frequency_hz >= config.sample_rate * 0.49)
        return error.InvalidLinkwitzRileyConfig;
}

fn stageValid(stage: anytype) bool {
    return stage.current.valid() and
        stage.target.valid() and
        stage.step.valid() and
        std.math.isFinite(stage.z1) and
        std.math.isFinite(stage.z2);
}

test "linkwitz-riley branches meet at minus six decibels" {
    var crossover = try LinkwitzRileyFilter(f64).init(.{
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    var low_energy: f64 = 0.0;
    var high_energy: f64 = 0.0;
    var input_energy: f64 = 0.0;
    for (0..16_384) |index| {
        const sample = @sin(
            std.math.tau *
                1_000.0 *
                @as(f64, @floatFromInt(index)) /
                48_000.0,
        );
        const split = crossover.processSample(sample);
        if (index >= 4_096) {
            input_energy += sample * sample;
            low_energy += split.low * split.low;
            high_energy += split.high * split.high;
        }
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        low_energy / input_energy,
        0.002,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        high_energy / input_energy,
        0.002,
    );
}

test "linkwitz-riley processing is independent of block partitioning" {
    const Filter = LinkwitzRileyFilter(f32);
    const config = Config{
        .sample_rate = 48_000.0,
        .frequency_hz = 2_500.0,
    };
    var input: [128]f32 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @sin(
            std.math.tau *
                600.0 *
                @as(f32, @floatFromInt(index)) /
                48_000.0,
        );
    var whole = try Filter.init(config);
    var whole_low: [128]f32 = undefined;
    var whole_high: [128]f32 = undefined;
    try whole.process(&input, &whole_low, &whole_high);

    var split = try Filter.init(config);
    var split_low: [128]f32 = undefined;
    var split_high: [128]f32 = undefined;
    try split.process(
        input[0..51],
        split_low[0..51],
        split_high[0..51],
    );
    try split.process(input[51..], split_low[51..], split_high[51..]);
    try std.testing.expectEqualSlices(f32, &whole_low, &split_low);
    try std.testing.expectEqualSlices(f32, &whole_high, &split_high);
}

test "linkwitz-riley rejects invalid config and repairs hostile state" {
    var crossover = try LinkwitzRileyFilter(f32).init(.{
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    const original = crossover.config;
    try std.testing.expectError(
        error.InvalidLinkwitzRileyConfig,
        crossover.configure(.{
            .sample_rate = 48_000.0,
            .frequency_hz = 30_000.0,
        }, 0),
    );
    try std.testing.expectEqual(original, crossover.config);
    crossover.low[0].z1 = std.math.nan(f32);
    const result = crossover.processSample(0.25);
    try std.testing.expectEqual(@as(f32, 0.25), result.low);
    try std.testing.expectEqual(@as(f32, 0.0), result.high);
    try std.testing.expect(crossover.valid());
}
