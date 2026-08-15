const std = @import("std");
const buffer_regions = @import("buffer_regions.zig");

pub const Mode = enum {
    peak,
    rms,
};

pub const Config = struct {
    sample_rate: f64,
    attack_ms: f64 = 1.0,
    release_ms: f64 = 100.0,
    mode: Mode = .peak,
};

pub fn BallisticsFilter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("BallisticsFilter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        config: Config,
        attack_coefficient: Sample,
        release_coefficient: Sample,
        envelope: Sample = 0.0,

        pub fn init(config: Config) !Self {
            const coefficients = try calculate(Sample, config);
            return .{
                .config = config,
                .attack_coefficient = coefficients.attack,
                .release_coefficient = coefficients.release,
            };
        }

        pub fn configure(self: *Self, config: Config) !void {
            const coefficients = try calculate(Sample, config);
            if (config.mode != self.config.mode) self.envelope = 0.0;
            self.config = config;
            self.attack_coefficient = coefficients.attack;
            self.release_coefficient = coefficients.release;
        }

        pub fn reset(self: *Self, value: Sample) !void {
            if (!std.math.isFinite(value) or value < 0.0)
                return error.InvalidBallisticsResetValue;
            const envelope = switch (self.config.mode) {
                .peak => value,
                .rms => value * value,
            };
            if (!std.math.isFinite(envelope))
                return error.InvalidBallisticsResetValue;
            self.envelope = envelope;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            if (!self.processingValid()) {
                self.envelope = 0.0;
                return 0.0;
            }
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            const magnitude = @abs(accepted);
            const detector = switch (self.config.mode) {
                .peak => magnitude,
                .rms => magnitude * magnitude,
            };
            const coefficient = if (detector > self.envelope)
                self.attack_coefficient
            else
                self.release_coefficient;
            self.envelope =
                coefficient * self.envelope +
                (1.0 - coefficient) * detector;
            if (!std.math.isFinite(self.envelope) or self.envelope < 0.0) {
                self.envelope = 0.0;
                return 0.0;
            }
            return self.current();
        }

        pub fn process(
            self: *Self,
            input: []const Sample,
            output: []Sample,
        ) !void {
            if (input.len != output.len)
                return error.BallisticsBufferLengthMismatch;
            if (!buffer_regions.exactOrDisjoint(Sample, input, output))
                return error.BallisticsBufferOverlap;
            for (input, output) |input_sample, *output_sample|
                output_sample.* = self.processSample(input_sample);
        }

        pub fn current(self: *const Self) Sample {
            if (!std.math.isFinite(self.envelope) or self.envelope < 0.0)
                return 0.0;
            return switch (self.config.mode) {
                .peak => self.envelope,
                .rms => @sqrt(self.envelope),
            };
        }

        pub fn valid(self: *const Self) bool {
            const expected = calculate(Sample, self.config) catch return false;
            return self.attack_coefficient == expected.attack and
                self.release_coefficient == expected.release and
                std.math.isFinite(self.envelope) and
                self.envelope >= 0.0;
        }

        fn processingValid(self: *const Self) bool {
            validateConfig(self.config) catch return false;
            return coefficientValid(self.attack_coefficient) and
                coefficientValid(self.release_coefficient) and
                std.math.isFinite(self.envelope) and
                self.envelope >= 0.0;
        }
    };
}

fn Coefficients(comptime Sample: type) type {
    return struct {
        attack: Sample,
        release: Sample,
    };
}

fn calculate(comptime Sample: type, config: Config) !Coefficients(Sample) {
    try validateConfig(config);
    return .{
        .attack = try timeCoefficient(Sample, config.sample_rate, config.attack_ms),
        .release = try timeCoefficient(
            Sample,
            config.sample_rate,
            config.release_ms,
        ),
    };
}

fn validateConfig(config: Config) !void {
    if (!std.math.isFinite(config.sample_rate) or
        config.sample_rate < 1_000.0 or
        config.sample_rate > 768_000.0 or
        !std.math.isFinite(config.attack_ms) or
        config.attack_ms < 0.0 or
        config.attack_ms > 60_000.0 or
        !std.math.isFinite(config.release_ms) or
        config.release_ms < 0.0 or
        config.release_ms > 60_000.0)
        return error.InvalidBallisticsConfig;
}

fn timeCoefficient(
    comptime Sample: type,
    sample_rate: f64,
    time_ms: f64,
) !Sample {
    if (time_ms == 0.0) return 0.0;
    const coefficient: Sample = @floatCast(
        @exp(-1.0 / (sample_rate * time_ms * 0.001)),
    );
    if (!coefficientValid(coefficient))
        return error.InvalidBallisticsConfig;
    return coefficient;
}

fn coefficientValid(value: anytype) bool {
    return std.math.isFinite(value) and value >= 0.0 and value < 1.0;
}

test "ballistics zero attack tracks peaks and release decays" {
    var filter = try BallisticsFilter(f64).init(.{
        .sample_rate = 1_000.0,
        .attack_ms = 0.0,
        .release_ms = 100.0,
        .mode = .peak,
    });
    try std.testing.expectEqual(@as(f64, 1.0), filter.processSample(-1.0));
    const released = filter.processSample(0.0);
    try std.testing.expectApproxEqAbs(
        @exp(-0.01),
        released,
        0.000_000_001,
    );
}

test "ballistics RMS converges to a constant magnitude" {
    var filter = try BallisticsFilter(f32).init(.{
        .sample_rate = 48_000.0,
        .attack_ms = 10.0,
        .release_ms = 100.0,
        .mode = .rms,
    });
    for (0..48_000) |_| _ = filter.processSample(-0.25);
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        filter.current(),
        0.000_01,
    );
}

test "ballistics configuration is transactional and hostile state resets" {
    var filter = try BallisticsFilter(f32).init(.{
        .sample_rate = 48_000.0,
    });
    const original = filter.config;
    try std.testing.expectError(
        error.InvalidBallisticsConfig,
        filter.configure(.{
            .sample_rate = 48_000.0,
            .attack_ms = -1.0,
        }),
    );
    try std.testing.expectEqual(original, filter.config);
    filter.envelope = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 0.0), filter.processSample(1.0));
    try std.testing.expect(filter.valid());

    filter.config.mode = .rms;
    const before_reset = filter.envelope;
    try std.testing.expectError(
        error.InvalidBallisticsResetValue,
        filter.reset(std.math.floatMax(f32)),
    );
    try std.testing.expectEqual(before_reset, filter.envelope);
}

test "ballistics permits exact in-place buffers and rejects shifted overlap" {
    const config = Config{ .sample_rate = 48_000.0 };
    var storage = [_]f32{ 0.25, 0.5, 0.75, 1.0 };
    var shifted = try BallisticsFilter(f32).init(config);
    const before = shifted;
    const storage_before = storage;
    try std.testing.expectError(
        error.BallisticsBufferOverlap,
        shifted.process(storage[0..3], storage[1..4]),
    );
    try std.testing.expectEqualDeep(before, shifted);
    try std.testing.expectEqualDeep(storage_before, storage);

    var in_place = try BallisticsFilter(f32).init(config);
    try in_place.process(&storage, &storage);
    for (storage) |sample| try std.testing.expect(std.math.isFinite(sample));
}
