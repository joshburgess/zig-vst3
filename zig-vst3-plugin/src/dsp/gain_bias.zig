const std = @import("std");

pub fn Gain(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Gain supports f32 and f64 samples");

    return struct {
        const Self = @This();

        current_gain: Sample,
        target_gain: Sample,
        step: Sample = 0.0,
        remaining: usize = 0,

        pub fn init(linear_gain: Sample) !Self {
            try validateGain(linear_gain);
            return .{
                .current_gain = linear_gain,
                .target_gain = linear_gain,
            };
        }

        pub fn setLinear(
            self: *Self,
            linear_gain: Sample,
            ramp_samples: usize,
        ) !void {
            try validateGain(linear_gain);
            if (!self.valid()) return error.InvalidGainState;
            if (ramp_samples == 0) {
                self.current_gain = linear_gain;
                self.target_gain = linear_gain;
                self.step = 0.0;
                self.remaining = 0;
                return;
            }
            self.target_gain = linear_gain;
            self.step = (linear_gain - self.current_gain) /
                @as(Sample, @floatFromInt(ramp_samples));
            self.remaining = ramp_samples;
        }

        pub fn setDecibels(
            self: *Self,
            gain_db: f64,
            ramp_samples: usize,
        ) !void {
            if (!std.math.isFinite(gain_db) or
                gain_db < -160.0 or
                gain_db > 36.0)
                return error.InvalidGainDecibels;
            try self.setLinear(
                @floatCast(std.math.pow(f64, 10.0, gain_db / 20.0)),
                ramp_samples,
            );
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) {
                self.current_gain = 1.0;
                self.target_gain = 1.0;
                self.step = 0.0;
                self.remaining = 0;
                return accepted;
            }
            if (self.remaining != 0) {
                self.remaining -= 1;
                if (self.remaining == 0) {
                    self.current_gain = self.target_gain;
                    self.step = 0.0;
                } else {
                    const next_gain = self.current_gain + self.step;
                    if (!gainValid(next_gain)) {
                        self.current_gain = self.target_gain;
                        self.step = 0.0;
                        self.remaining = 0;
                    } else {
                        self.current_gain = next_gain;
                    }
                }
            }
            const output = accepted * self.current_gain;
            if (!std.math.isFinite(output)) {
                self.current_gain = 1.0;
                self.target_gain = 1.0;
                self.step = 0.0;
                self.remaining = 0;
                return 0.0;
            }
            return output;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn valid(self: *const Self) bool {
            return gainValid(self.current_gain) and
                gainValid(self.target_gain) and
                std.math.isFinite(self.step);
        }

        fn validateGain(value: Sample) !void {
            if (!gainValid(value)) return error.InvalidGainValue;
        }

        fn gainValid(value: Sample) bool {
            return std.math.isFinite(value) and value >= 0.0 and value <= 64.0;
        }
    };
}

pub fn Bias(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Bias supports f32 and f64 samples");

    return struct {
        const Self = @This();

        bias: Sample,

        pub fn init(bias: Sample) !Self {
            try validateBias(bias);
            return .{ .bias = bias };
        }

        pub fn setBias(self: *Self, bias: Sample) !void {
            try validateBias(bias);
            self.bias = bias;
        }

        pub fn processSample(self: *const Self, input: Sample) Sample {
            const accepted = if (std.math.isFinite(input)) input else 0.0;
            if (!self.valid()) return accepted;
            const output = accepted + self.bias;
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn process(self: *const Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn valid(self: *const Self) bool {
            return std.math.isFinite(self.bias);
        }

        fn validateBias(bias: Sample) !void {
            if (!std.math.isFinite(bias)) return error.InvalidBiasValue;
        }
    };
}

test "gain ramps linearly and reaches exact target" {
    var gain = try Gain(f32).init(1.0);
    try gain.setLinear(0.0, 4);
    try std.testing.expectEqual(@as(f32, 0.75), gain.processSample(1.0));
    try std.testing.expectEqual(@as(f32, 0.5), gain.processSample(1.0));
    try std.testing.expectEqual(@as(f32, 0.25), gain.processSample(1.0));
    try std.testing.expectEqual(@as(f32, 0.0), gain.processSample(1.0));
    try std.testing.expectEqual(@as(usize, 0), gain.remaining);
}

test "gain accepts decibels and contains hostile state" {
    var gain = try Gain(f64).init(1.0);
    try gain.setDecibels(-6.020599913279624, 0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        gain.processSample(1.0),
        0.000_000_001,
    );
    gain.step = std.math.nan(f64);
    try std.testing.expectEqual(@as(f64, 0.25), gain.processSample(0.25));
    try std.testing.expect(gain.valid());

    gain.current_gain = 1.0;
    gain.target_gain = 0.5;
    gain.step = 64.0;
    gain.remaining = 2;
    try std.testing.expectEqual(@as(f64, 0.5), gain.processSample(1.0));
    try std.testing.expect(gain.valid());
    try std.testing.expectEqual(@as(usize, 0), gain.remaining);
}

test "bias processes blocks and rejects invalid values" {
    var bias = try Bias(f32).init(0.25);
    var samples = [_]f32{ -0.25, 0.0, 0.75 };
    bias.process(&samples);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.0, 0.25, 1.0 },
        &samples,
    );
    try std.testing.expectError(
        error.InvalidBiasValue,
        bias.setBias(std.math.nan(f32)),
    );
    try std.testing.expect(bias.valid());
}
