const std = @import("std");

pub const Linear = struct {
    sample_rate: f64,
    minimum: f64,
    maximum: f64,
    current: f64,
    target: f64,
    step: f64 = 0.0,
    remaining_samples: usize = 0,

    pub fn init(
        sample_rate: f64,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) !Linear {
        try validate(sample_rate, value, minimum, maximum);
        return .{
            .sample_rate = sample_rate,
            .minimum = minimum,
            .maximum = maximum,
            .current = value,
            .target = value,
        };
    }

    pub fn setImmediate(
        self: *Linear,
        sample_rate: f64,
        value: f64,
    ) !void {
        const replacement = try init(
            sample_rate,
            value,
            self.minimum,
            self.maximum,
        );
        self.* = replacement;
    }

    pub fn setTarget(
        self: *Linear,
        sample_rate: f64,
        value: f64,
        smoothing_seconds: f64,
    ) !void {
        try validate(sample_rate, value, self.minimum, self.maximum);
        if (!std.math.isFinite(smoothing_seconds) or
            smoothing_seconds < 0.0 or
            smoothing_seconds > 60.0)
            return error.InvalidSmoothingDuration;
        if (!self.valid()) return error.InvalidSmoothedValueState;
        if (sample_rate == self.sample_rate and value == self.target) return;

        const sample_count_float = @round(sample_rate * smoothing_seconds);
        if (!std.math.isFinite(sample_count_float) or
            sample_count_float >
                @as(f64, @floatFromInt(std.math.maxInt(usize))))
            return error.InvalidSmoothingDuration;
        const sample_count: usize = @intFromFloat(sample_count_float);
        if (sample_count == 0)
            return self.setImmediate(sample_rate, value);

        const step =
            (value - self.current) /
            @as(f64, @floatFromInt(sample_count));
        if (!std.math.isFinite(step))
            return error.InvalidSmoothingDuration;
        self.sample_rate = sample_rate;
        self.target = value;
        self.step = step;
        self.remaining_samples = sample_count;
    }

    pub fn next(self: *Linear) f64 {
        if (!self.valid()) return self.repair();
        const value = self.current;
        if (self.remaining_samples > 0) {
            self.remaining_samples -= 1;
            if (self.remaining_samples == 0) {
                _ = self.settle();
            } else {
                const next_value = self.current + self.step;
                if (!self.valueInRange(next_value)) {
                    _ = self.settle();
                } else {
                    self.current = next_value;
                }
            }
        }
        return value;
    }

    pub fn skip(self: *Linear, sample_count: usize) f64 {
        if (!self.valid()) return self.repair();
        const count = @min(sample_count, self.remaining_samples);
        if (count == self.remaining_samples) return self.settle();
        const next_value = self.current +
            self.step * @as(f64, @floatFromInt(count));
        if (!self.valueInRange(next_value)) return self.settle();
        self.current = next_value;
        self.remaining_samples -= count;
        return self.current;
    }

    pub fn valid(self: *const Linear) bool {
        validate(
            self.sample_rate,
            self.current,
            self.minimum,
            self.maximum,
        ) catch return false;
        if (!std.math.isFinite(self.target) or
            self.target < self.minimum or
            self.target > self.maximum or
            !std.math.isFinite(self.step))
            return false;
        const maximum_remaining: usize =
            @intFromFloat(self.sample_rate * 60.0);
        return self.remaining_samples <= maximum_remaining;
    }

    fn valueInRange(self: *const Linear, value: f64) bool {
        return std.math.isFinite(value) and
            value >= self.minimum and
            value <= self.maximum;
    }

    fn settle(self: *Linear) f64 {
        self.current = self.target;
        self.step = 0.0;
        self.remaining_samples = 0;
        return self.current;
    }

    fn repair(self: *Linear) f64 {
        self.* = .{
            .sample_rate = 48_000.0,
            .minimum = 0.0,
            .maximum = 0.0,
            .current = 0.0,
            .target = 0.0,
        };
        return self.current;
    }

    fn validate(
        sample_rate: f64,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) !void {
        if (!std.math.isFinite(sample_rate) or
            sample_rate < 1_000.0 or
            sample_rate > 768_000.0 or
            !std.math.isFinite(minimum) or
            !std.math.isFinite(maximum) or
            minimum > maximum or
            !std.math.isFinite(value) or
            value < minimum or
            value > maximum)
            return error.InvalidSmoothedValue;
    }
};

pub const Multiplicative = struct {
    sample_rate: f64,
    minimum: f64,
    maximum: f64,
    current: f64,
    target: f64,
    multiplier: f64 = 1.0,
    remaining_samples: usize = 0,

    pub fn init(
        sample_rate: f64,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) !Multiplicative {
        try validate(sample_rate, value, minimum, maximum);
        return .{
            .sample_rate = sample_rate,
            .minimum = minimum,
            .maximum = maximum,
            .current = value,
            .target = value,
        };
    }

    pub fn setImmediate(
        self: *Multiplicative,
        sample_rate: f64,
        value: f64,
    ) !void {
        const replacement = try init(
            sample_rate,
            value,
            self.minimum,
            self.maximum,
        );
        self.* = replacement;
    }

    pub fn setTarget(
        self: *Multiplicative,
        sample_rate: f64,
        value: f64,
        smoothing_seconds: f64,
    ) !void {
        try validate(sample_rate, value, self.minimum, self.maximum);
        if (!std.math.isFinite(smoothing_seconds) or
            smoothing_seconds < 0.0 or
            smoothing_seconds > 60.0)
            return error.InvalidSmoothingDuration;
        if (!self.valid()) return error.InvalidSmoothedValueState;
        if (sample_rate == self.sample_rate and value == self.target) return;

        const sample_count_float = @round(sample_rate * smoothing_seconds);
        if (!std.math.isFinite(sample_count_float) or
            sample_count_float >
                @as(f64, @floatFromInt(std.math.maxInt(usize))))
            return error.InvalidSmoothingDuration;
        const sample_count: usize = @intFromFloat(sample_count_float);
        if (sample_count == 0)
            return self.setImmediate(sample_rate, value);

        const exponent =
            1.0 / @as(f64, @floatFromInt(sample_count));
        const multiplier = std.math.pow(
            f64,
            value / self.current,
            exponent,
        );
        if (!std.math.isFinite(multiplier) or multiplier <= 0.0)
            return error.InvalidSmoothingDuration;
        self.sample_rate = sample_rate;
        self.target = value;
        self.multiplier = multiplier;
        self.remaining_samples = sample_count;
    }

    pub fn next(self: *Multiplicative) f64 {
        if (!self.valid()) return self.repair();
        const value = self.current;
        if (self.remaining_samples > 0) {
            self.remaining_samples -= 1;
            if (self.remaining_samples == 0) {
                _ = self.settle();
            } else {
                const next_value = self.current * self.multiplier;
                if (!self.valueInRange(next_value)) {
                    _ = self.settle();
                } else {
                    self.current = next_value;
                }
            }
        }
        return value;
    }

    pub fn skip(self: *Multiplicative, sample_count: usize) f64 {
        if (!self.valid()) return self.repair();
        const count = @min(sample_count, self.remaining_samples);
        if (count == self.remaining_samples) return self.settle();
        const next_value = self.current * std.math.pow(
            f64,
            self.multiplier,
            @as(f64, @floatFromInt(count)),
        );
        if (!self.valueInRange(next_value)) return self.settle();
        self.current = next_value;
        self.remaining_samples -= count;
        return self.current;
    }

    pub fn valid(self: *const Multiplicative) bool {
        validate(
            self.sample_rate,
            self.current,
            self.minimum,
            self.maximum,
        ) catch return false;
        if (!std.math.isFinite(self.target) or
            self.target < self.minimum or
            self.target > self.maximum or
            !std.math.isFinite(self.multiplier) or
            self.multiplier <= 0.0)
            return false;
        const maximum_remaining: usize =
            @intFromFloat(self.sample_rate * 60.0);
        return self.remaining_samples <= maximum_remaining;
    }

    fn valueInRange(
        self: *const Multiplicative,
        value: f64,
    ) bool {
        return std.math.isFinite(value) and
            value >= self.minimum and
            value <= self.maximum;
    }

    fn settle(self: *Multiplicative) f64 {
        self.current = self.target;
        self.multiplier = 1.0;
        self.remaining_samples = 0;
        return self.current;
    }

    fn repair(self: *Multiplicative) f64 {
        self.* = .{
            .sample_rate = 48_000.0,
            .minimum = 1.0,
            .maximum = 1.0,
            .current = 1.0,
            .target = 1.0,
        };
        return self.current;
    }

    fn validate(
        sample_rate: f64,
        value: f64,
        minimum: f64,
        maximum: f64,
    ) !void {
        if (!std.math.isFinite(sample_rate) or
            sample_rate < 1_000.0 or
            sample_rate > 768_000.0 or
            !std.math.isFinite(minimum) or
            minimum <= 0.0 or
            !std.math.isFinite(maximum) or
            minimum > maximum or
            !std.math.isFinite(value) or
            value < minimum or
            value > maximum)
            return error.InvalidSmoothedValue;
    }
};

test "linear smoother reaches its exact target across partitions" {
    var whole = try Linear.init(1_000.0, -0.5, -1.0, 1.0);
    try whole.setTarget(1_000.0, 0.5, 0.004);
    var values: [6]f64 = undefined;
    for (&values) |*value| value.* = whole.next();

    var skipped = try Linear.init(1_000.0, -0.5, -1.0, 1.0);
    try skipped.setTarget(1_000.0, 0.5, 0.004);
    try std.testing.expectEqual(values[2], skipped.skip(2));
    try std.testing.expectEqual(@as(f64, 0.5), skipped.skip(2));
    try std.testing.expectEqual(@as(f64, 0.5), values[4]);
}

test "linear smoother rejects bad targets transactionally" {
    var value = try Linear.init(48_000.0, 0.5, 0.0, 1.0);
    const before = value;
    try std.testing.expectError(
        error.InvalidSmoothedValue,
        value.setTarget(48_000.0, 2.0, 0.01),
    );
    try std.testing.expectEqualDeep(before, value);
}

test "linear smoother contains hostile retained arithmetic" {
    var stepped = try Linear.init(
        48_000.0,
        std.math.floatMax(f64),
        -std.math.floatMax(f64),
        std.math.floatMax(f64),
    );
    stepped.target = std.math.floatMax(f64);
    stepped.step = std.math.floatMax(f64);
    stepped.remaining_samples = 2;
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        stepped.next(),
    );
    try std.testing.expect(stepped.valid());
    try std.testing.expectEqual(@as(usize, 0), stepped.remaining_samples);

    var malformed = stepped;
    malformed.current = std.math.nan(f64);
    try std.testing.expectEqual(@as(f64, 0.0), malformed.skip(1));
    try std.testing.expect(malformed.valid());
}

test "multiplicative smoother reaches its exact target across partitions" {
    var whole = try Multiplicative.init(1_000.0, 100.0, 20.0, 20_000.0);
    try whole.setTarget(1_000.0, 1_600.0, 0.004);
    var values: [6]f64 = undefined;
    for (&values) |*value| value.* = whole.next();
    try std.testing.expectEqualSlices(
        f64,
        &.{ 100.0, 200.0, 400.0, 800.0, 1_600.0, 1_600.0 },
        &values,
    );

    var skipped = try Multiplicative.init(
        1_000.0,
        100.0,
        20.0,
        20_000.0,
    );
    try skipped.setTarget(1_000.0, 1_600.0, 0.004);
    try std.testing.expectEqual(values[2], skipped.skip(2));
    try std.testing.expectEqual(@as(f64, 1_600.0), skipped.skip(2));
}

test "multiplicative smoother retargets and rejects zero transactionally" {
    var value = try Multiplicative.init(1_000.0, 100.0, 20.0, 20_000.0);
    try value.setTarget(1_000.0, 1_600.0, 0.004);
    _ = value.next();
    _ = value.next();
    try value.setTarget(1_000.0, 100.0, 0.002);
    try std.testing.expectEqual(@as(f64, 400.0), value.next());
    try std.testing.expectEqual(@as(f64, 200.0), value.next());
    try std.testing.expectEqual(@as(f64, 100.0), value.next());

    const before = value;
    try std.testing.expectError(
        error.InvalidSmoothedValue,
        value.setTarget(1_000.0, 0.0, 0.01),
    );
    try std.testing.expectEqualDeep(before, value);
    try std.testing.expectError(
        error.InvalidSmoothedValue,
        Multiplicative.init(48_000.0, 1.0, 0.0, 2.0),
    );
}

test "multiplicative smoother contains hostile retained arithmetic" {
    var multiplied = try Multiplicative.init(
        48_000.0,
        std.math.floatMax(f64),
        1.0,
        std.math.floatMax(f64),
    );
    multiplied.target = std.math.floatMax(f64);
    multiplied.multiplier = 2.0;
    multiplied.remaining_samples = 3;
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        multiplied.skip(1),
    );
    try std.testing.expect(multiplied.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        multiplied.remaining_samples,
    );

    var malformed = multiplied;
    malformed.multiplier = std.math.nan(f64);
    try std.testing.expectEqual(@as(f64, 1.0), malformed.next());
    try std.testing.expect(malformed.valid());
}

test "smoothed values contain generated retained arithmetic state" {
    for (0..4_096) |index| {
        const bits = @as(u64, index) *%
            0x9e37_79b9_7f4a_7c15 +%
            0xd1b5_4a32_d192_ed03;
        const generated: f64 = @bitCast(bits);

        var linear = try Linear.init(
            48_000.0,
            1.0,
            -std.math.floatMax(f64),
            std.math.floatMax(f64),
        );
        linear.target = 2.0;
        linear.step = generated;
        linear.remaining_samples = 2;
        try std.testing.expect(std.math.isFinite(linear.next()));
        try std.testing.expect(linear.valid());

        var multiplicative = try Multiplicative.init(
            48_000.0,
            1.0,
            std.math.floatMin(f64),
            std.math.floatMax(f64),
        );
        multiplicative.target = 2.0;
        multiplicative.multiplier = generated;
        multiplicative.remaining_samples = 2;
        try std.testing.expect(
            std.math.isFinite(multiplicative.next()),
        );
        try std.testing.expect(multiplicative.valid());
    }
}
