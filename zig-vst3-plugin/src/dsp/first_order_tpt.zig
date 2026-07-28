const std = @import("std");

pub const Kind = enum {
    low_pass,
    high_pass,
    all_pass,
};

pub const Config = struct {
    kind: Kind,
    sample_rate: f64,
    frequency_hz: f64,
};

pub fn FirstOrderTptFilter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("FirstOrderTptFilter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: Config,
        coefficient: Sample,
        state: Sample = 0.0,

        pub fn init(config: Config) !Self {
            return .{
                .config = config,
                .coefficient = try calculate(Sample, config),
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const coefficient = try calculate(Sample, config);
            self.config = config;
            self.coefficient = coefficient;
        }

        pub fn reset(self: *Self) void {
            self.state = 0.0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.processingValid()) {
                self.reset();
                return accepted;
            }
            const correction = self.coefficient * (accepted - self.state);
            const low = correction + self.state;
            self.state = correction + low;
            const high = accepted - low;
            const output = switch (self.config.kind) {
                .low_pass => low,
                .high_pass => high,
                .all_pass => low - high,
            };
            if (!std.math.isFinite(output) or
                !std.math.isFinite(self.state))
            {
                self.reset();
                return 0.0;
            }
            return output;
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.FirstOrderTptBufferLengthMismatch;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn valid(self: *const Self) bool {
            const expected = calculate(Sample, self.config) catch return false;
            return self.coefficient == expected and
                std.math.isFinite(self.state);
        }

        fn processingValid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            return std.math.isFinite(self.coefficient) and
                self.coefficient > 0.0 and
                self.coefficient < 1.0 and
                std.math.isFinite(self.state);
        }
    };
}

fn calculate(comptime Sample: type, config: Config) !Sample {
    try validateConfig(config);
    const g = @tan(std.math.pi * config.frequency_hz / config.sample_rate);
    const coefficient: Sample = @floatCast(g / (1.0 + g));
    if (!std.math.isFinite(coefficient) or
        coefficient <= 0.0 or
        coefficient >= 1.0)
        return error.InvalidFirstOrderTptConfig;
    return coefficient;
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.frequency_hz) or
        config.frequency_hz < 1.0 or
        config.frequency_hz >= config.sample_rate * 0.49)
        return error.InvalidFirstOrderTptConfig;
}

test "first-order TPT pass filters meet at minus three decibels" {
    inline for (.{ Kind.low_pass, Kind.high_pass }) |kind| {
        var filter = try FirstOrderTptFilter(f64).init(.{
            .kind = kind,
            .sample_rate = 48_000.0,
            .frequency_hz = 1_000.0,
        });
        var input_energy: f64 = 0.0;
        var output_energy: f64 = 0.0;
        for (0..16_384) |index| {
            const sample = @sin(
                std.math.tau *
                    1_000.0 *
                    @as(f64, @floatFromInt(index)) /
                    48_000.0,
            );
            const output = filter.processSample(sample);
            if (index >= 4_096) {
                input_energy += sample * sample;
                output_energy += output * output;
            }
        }
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.5),
            output_energy / input_energy,
            0.002,
        );
    }
}

test "first-order TPT all-pass output preserves impulse energy" {
    var filter = try FirstOrderTptFilter(f64).init(.{
        .kind = .all_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 2_000.0,
    });
    var energy: f64 = 0.0;
    for (0..4_096) |index| {
        const output = filter.processSample(
            if (index == 0) 1.0 else 0.0,
        );
        energy += output * output;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), energy, 0.000_001);
}

test "first-order TPT configuration is transactional and state recovers" {
    var filter = try FirstOrderTptFilter(f32).init(.{
        .kind = .low_pass,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
    });
    const original = filter.config;
    try std.testing.expectError(
        error.InvalidFirstOrderTptConfig,
        filter.configure(.{
            .kind = .high_pass,
            .sample_rate = 48_000.0,
            .frequency_hz = 30_000.0,
        }),
    );
    try std.testing.expectEqual(original, filter.config);
    filter.state = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 0.25), filter.processSample(0.25));
    try std.testing.expect(filter.valid());
}
