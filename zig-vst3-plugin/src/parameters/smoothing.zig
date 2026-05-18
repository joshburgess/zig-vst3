const std = @import("std");
const common = @import("common.zig");

const clampNormalized = common.clampNormalized;
const clampNormalizedNonZero = common.clampNormalizedNonZero;

pub const LinearSmoother = struct {
    current: f64,
    target: f64,
    step: f64 = 0.0,
    remaining: usize = 0,

    pub fn init(value: f64) LinearSmoother {
        const clamped = clampNormalized(value);
        return .{ .current = clamped, .target = clamped };
    }

    pub fn reset(self: *LinearSmoother, value: f64) void {
        const clamped = clampNormalized(value);
        self.current = clamped;
        self.target = clamped;
        self.step = 0.0;
        self.remaining = 0;
    }

    pub fn currentValue(self: LinearSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: LinearSmoother) f64 {
        return self.target;
    }

    pub fn remainingSamples(self: LinearSmoother) usize {
        return self.remaining;
    }

    pub fn targetDelta(self: LinearSmoother) f64 {
        return @abs(self.target - self.current);
    }

    pub fn atTarget(self: LinearSmoother, tolerance: f64) bool {
        return self.targetDelta() <= @max(0.0, tolerance);
    }

    pub fn needsSmoothing(self: LinearSmoother, tolerance: f64) bool {
        return !self.atTarget(tolerance);
    }

    pub fn active(self: LinearSmoother) bool {
        return self.remaining != 0;
    }

    pub fn finished(self: LinearSmoother) bool {
        return self.remaining == 0;
    }

    pub fn setTarget(self: *LinearSmoother, target: f64, samples: usize) void {
        self.target = clampNormalized(target);
        self.remaining = samples;
        if (samples == 0) {
            self.current = self.target;
            self.step = 0.0;
        } else {
            self.step = (self.target - self.current) / @as(f64, @floatFromInt(samples));
        }
    }

    pub fn next(self: *LinearSmoother) f64 {
        if (self.remaining == 0) return self.current;
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.current = self.target;
        } else {
            self.current += self.step;
        }
        return self.current;
    }
};

pub const ExponentialSmoother = struct {
    current: f64,
    target: f64,
    coefficient: f64,

    pub fn init(value: f64, coefficient: f64) ExponentialSmoother {
        const clamped = clampNormalized(value);
        return .{
            .current = clamped,
            .target = clamped,
            .coefficient = clampNormalized(coefficient),
        };
    }

    pub fn reset(self: *ExponentialSmoother, value: f64) void {
        const clamped = clampNormalized(value);
        self.current = clamped;
        self.target = clamped;
    }

    pub fn currentValue(self: ExponentialSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: ExponentialSmoother) f64 {
        return self.target;
    }

    pub fn coefficientValue(self: ExponentialSmoother) f64 {
        return self.coefficient;
    }

    pub fn targetDelta(self: ExponentialSmoother) f64 {
        return @abs(self.target - self.current);
    }

    pub fn atTarget(self: ExponentialSmoother, tolerance: f64) bool {
        return self.targetDelta() <= @max(0.0, tolerance);
    }

    pub fn needsSmoothing(self: ExponentialSmoother, tolerance: f64) bool {
        return !self.atTarget(tolerance);
    }

    pub fn setCoefficient(self: *ExponentialSmoother, coefficient: f64) void {
        self.coefficient = clampNormalized(coefficient);
    }

    pub fn setTarget(self: *ExponentialSmoother, target: f64) void {
        self.target = clampNormalized(target);
    }

    pub fn next(self: *ExponentialSmoother) f64 {
        self.current += (self.target - self.current) * self.coefficient;
        return self.current;
    }
};

pub const LogSmoother = struct {
    current: f64,
    target: f64,
    ratio: f64 = 1.0,
    remaining: usize = 0,

    pub fn init(value: f64) LogSmoother {
        const clamped = clampNormalizedNonZero(value);
        return .{ .current = clamped, .target = clamped };
    }

    pub fn reset(self: *LogSmoother, value: f64) void {
        const clamped = clampNormalizedNonZero(value);
        self.current = clamped;
        self.target = clamped;
        self.ratio = 1.0;
        self.remaining = 0;
    }

    pub fn currentValue(self: LogSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: LogSmoother) f64 {
        return self.target;
    }

    pub fn remainingSamples(self: LogSmoother) usize {
        return self.remaining;
    }

    pub fn targetDelta(self: LogSmoother) f64 {
        return @abs(self.target - self.current);
    }

    pub fn atTarget(self: LogSmoother, tolerance: f64) bool {
        return self.targetDelta() <= @max(0.0, tolerance);
    }

    pub fn needsSmoothing(self: LogSmoother, tolerance: f64) bool {
        return !self.atTarget(tolerance);
    }

    pub fn active(self: LogSmoother) bool {
        return self.remaining != 0;
    }

    pub fn finished(self: LogSmoother) bool {
        return self.remaining == 0;
    }

    pub fn setTarget(self: *LogSmoother, target: f64, samples: usize) void {
        self.target = clampNormalizedNonZero(target);
        self.remaining = samples;
        if (samples == 0) {
            self.current = self.target;
            self.ratio = 1.0;
        } else {
            self.ratio = std.math.pow(f64, self.target / self.current, 1.0 / @as(f64, @floatFromInt(samples)));
        }
    }

    pub fn next(self: *LogSmoother) f64 {
        if (self.remaining == 0) return self.current;
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.current = self.target;
        } else {
            self.current *= self.ratio;
        }
        return self.current;
    }
};
test "linear smoother reaches target after requested samples" {
    var smoother = LinearSmoother.init(0.0);

    smoother.setTarget(1.0, 4);
    try std.testing.expect(smoother.active());
    try std.testing.expect(!smoother.finished());
    try std.testing.expectEqual(@as(usize, 4), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(0.0, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(!smoother.atTarget(0.25));
    try std.testing.expect(smoother.needsSmoothing(0.25));
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expect(smoother.finished());
    try std.testing.expectEqual(@as(usize, 0), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(0.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(smoother.atTarget(0.0));
    try std.testing.expect(!smoother.needsSmoothing(0.0));
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "linear smoother handles immediate and clamped targets" {
    var smoother = LinearSmoother.init(0.25);

    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(-1.0, 2);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
    smoother.reset(0.75);
    try std.testing.expectApproxEqAbs(0.75, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.targetValue(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expect(smoother.finished());
}

test "exponential smoother approaches target by coefficient" {
    var smoother = ExponentialSmoother.init(0.0, 0.25);

    smoother.setTarget(1.0);
    try std.testing.expectApproxEqAbs(0.0, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(!smoother.atTarget(0.5));
    try std.testing.expect(smoother.needsSmoothing(0.5));
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.4375, smoother.next(), 0.000001);
    smoother.setCoefficient(0.5);
    try std.testing.expectApproxEqAbs(0.71875, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.coefficientValue(), 0.000001);
    try std.testing.expect(smoother.atTarget(0.5));
    try std.testing.expect(!smoother.needsSmoothing(0.5));
}

test "exponential smoother clamps initial value target and coefficient" {
    var smoother = ExponentialSmoother.init(2.0, 2.0);

    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.coefficient, 0.000001);
    smoother.setTarget(-1.0);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
    smoother.reset(0.5);
    try std.testing.expectApproxEqAbs(0.5, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.targetValue(), 0.000001);
    smoother.setCoefficient(std.math.nan(f64));
    try std.testing.expectApproxEqAbs(0.0, smoother.coefficientValue(), 0.000001);
}

test "log smoother reaches multiplicative target after requested samples" {
    var smoother = LogSmoother.init(0.25);

    smoother.setTarget(1.0, 2);
    try std.testing.expect(smoother.active());
    try std.testing.expect(!smoother.finished());
    try std.testing.expectEqual(@as(usize, 2), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(0.25, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.targetDelta(), 0.000001);
    try std.testing.expect(!smoother.atTarget(0.25));
    try std.testing.expect(smoother.needsSmoothing(0.25));
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expect(smoother.finished());
    try std.testing.expectApproxEqAbs(0.0, smoother.targetDelta(), 0.000001);
    try std.testing.expect(smoother.atTarget(0.0));
    try std.testing.expect(!smoother.needsSmoothing(0.0));
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "log smoother clamps zero and handles immediate target" {
    var smoother = LogSmoother.init(0.0);

    try std.testing.expect(smoother.current > 0.0);
    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(std.math.nan(f64), 0);
    try std.testing.expectApproxEqAbs(std.math.floatEps(f64), smoother.current, 0.0);
    smoother.reset(0.5);
    try std.testing.expectApproxEqAbs(0.5, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.targetValue(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expect(smoother.finished());
}

test "smoothers clamp generated inputs and preserve endpoint invariants" {
    const inputs = [_]f64{
        -std.math.inf(f64),
        -1.0,
        0.0,
        0.125,
        0.5,
        1.0,
        2.0,
        std.math.inf(f64),
        std.math.nan(f64),
    };
    const sample_counts = [_]usize{ 0, 1, 2, 5 };

    for (inputs) |initial| {
        for (inputs) |target| {
            for (sample_counts) |samples| {
                var linear = LinearSmoother.init(initial);
                linear.setTarget(target, samples);
                const expected_target = clampNormalized(target);
                try std.testing.expect(linear.currentValue() >= 0.0 and linear.currentValue() <= 1.0);
                try std.testing.expectEqual(expected_target, linear.targetValue());
                try std.testing.expectEqual(samples != 0, linear.active());
                try std.testing.expectEqual(samples == 0, linear.finished());
                for (0..samples) |_| {
                    const next_value = linear.next();
                    try std.testing.expect(next_value >= 0.0 and next_value <= 1.0);
                }
                try std.testing.expectEqual(expected_target, linear.currentValue());
                try std.testing.expect(linear.finished());

                var logarithmic = LogSmoother.init(initial);
                logarithmic.setTarget(target, samples);
                const expected_log_target = clampNormalizedNonZero(target);
                try std.testing.expect(logarithmic.currentValue() > 0.0 and logarithmic.currentValue() <= 1.0);
                try std.testing.expectEqual(expected_log_target, logarithmic.targetValue());
                try std.testing.expectEqual(samples != 0, logarithmic.active());
                try std.testing.expectEqual(samples == 0, logarithmic.finished());
                for (0..samples) |_| {
                    const next_value = logarithmic.next();
                    try std.testing.expect(next_value > 0.0 and next_value <= 1.0);
                }
                try std.testing.expectEqual(expected_log_target, logarithmic.currentValue());
                try std.testing.expect(logarithmic.finished());
            }

            var exponential = ExponentialSmoother.init(initial, target);
            try std.testing.expect(exponential.currentValue() >= 0.0 and exponential.currentValue() <= 1.0);
            try std.testing.expect(exponential.coefficientValue() >= 0.0 and exponential.coefficientValue() <= 1.0);
            exponential.setTarget(target);
            exponential.setCoefficient(initial);
            const expected_target = clampNormalized(target);
            const expected_coefficient = clampNormalized(initial);
            try std.testing.expectEqual(expected_target, exponential.targetValue());
            try std.testing.expectEqual(expected_coefficient, exponential.coefficientValue());
            for (0..8) |_| {
                const next_value = exponential.next();
                try std.testing.expect(next_value >= 0.0 and next_value <= 1.0);
            }
        }
    }
}
