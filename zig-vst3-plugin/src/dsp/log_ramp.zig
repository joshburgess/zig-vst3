const std = @import("std");

pub fn LogRampedValue(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LogRampedValue supports f32 and f64 values");

    return struct {
        const Self = @This();

        current_value: Sample,
        target_value: Sample,
        ratio: Sample = 1.0,
        remaining: usize = 0,

        pub fn init(value: Sample) !Self {
            try validateValue(value);
            return .{
                .current_value = value,
                .target_value = value,
            };
        }

        pub fn setCurrentAndTarget(self: *Self, value: Sample) !void {
            try validateValue(value);
            self.current_value = value;
            self.target_value = value;
            self.ratio = 1.0;
            self.remaining = 0;
        }

        pub fn setTarget(
            self: *Self,
            target_value: Sample,
            ramp_samples: usize,
        ) !void {
            try validateValue(target_value);
            if (!self.valid())
                return error.InvalidLogRampState;
            if (ramp_samples == 0 or target_value == self.current_value) {
                try self.setCurrentAndTarget(target_value);
                return;
            }
            const ratio = std.math.pow(
                Sample,
                target_value / self.current_value,
                1.0 / @as(Sample, @floatFromInt(ramp_samples)),
            );
            if (!std.math.isFinite(ratio) or ratio <= 0.0)
                return error.InvalidLogRampTarget;
            self.target_value = target_value;
            self.ratio = ratio;
            self.remaining = ramp_samples;
        }

        pub fn next(self: *Self) Sample {
            if (!self.valid()) {
                self.current_value = 1.0;
                self.target_value = 1.0;
                self.ratio = 1.0;
                self.remaining = 0;
                return 1.0;
            }
            if (self.remaining == 0) return self.current_value;
            self.remaining -= 1;
            if (self.remaining == 0) {
                self.current_value = self.target_value;
                self.ratio = 1.0;
            } else {
                self.current_value *= self.ratio;
            }
            return self.current_value;
        }

        pub fn skip(self: *Self, count: usize) Sample {
            const advanced = @min(count, self.remaining);
            if (advanced == 0) return self.nextWithoutAdvance();
            if (!self.valid()) return self.next();
            if (advanced == self.remaining) {
                self.current_value = self.target_value;
                self.ratio = 1.0;
                self.remaining = 0;
            } else {
                self.current_value *= std.math.pow(
                    Sample,
                    self.ratio,
                    @floatFromInt(advanced),
                );
                self.remaining -= advanced;
            }
            return self.current_value;
        }

        pub fn current(self: *const Self) Sample {
            return if (self.valid()) self.current_value else 1.0;
        }

        pub fn target(self: *const Self) Sample {
            return if (self.valid()) self.target_value else 1.0;
        }

        pub fn smoothing(self: *const Self) bool {
            return self.valid() and self.remaining != 0;
        }

        pub fn valid(self: *const Self) bool {
            return valueValid(self.current_value) and
                valueValid(self.target_value) and
                std.math.isFinite(self.ratio) and
                self.ratio > 0.0;
        }

        fn nextWithoutAdvance(self: *const Self) Sample {
            return if (self.valid()) self.current_value else 1.0;
        }

        fn validateValue(value: Sample) !void {
            if (!valueValid(value)) return error.InvalidLogRampValue;
        }

        fn valueValid(value: Sample) bool {
            return std.math.isFinite(value) and value > 0.0;
        }
    };
}

test "log ramp reaches geometric midpoint and exact target" {
    var ramp = try LogRampedValue(f64).init(1.0);
    try ramp.setTarget(16.0, 4);
    try std.testing.expectEqual(@as(f64, 2.0), ramp.next());
    try std.testing.expectEqual(@as(f64, 4.0), ramp.next());
    try std.testing.expectEqual(@as(f64, 8.0), ramp.next());
    try std.testing.expectEqual(@as(f64, 16.0), ramp.next());
    try std.testing.expect(!ramp.smoothing());
}

test "log ramp skip matches repeated advancement" {
    var skipped = try LogRampedValue(f32).init(0.25);
    var repeated = try LogRampedValue(f32).init(0.25);
    try skipped.setTarget(4.0, 16);
    try repeated.setTarget(4.0, 16);
    const skipped_value = skipped.skip(7);
    var repeated_value: f32 = 0.0;
    for (0..7) |_| repeated_value = repeated.next();
    try std.testing.expectApproxEqAbs(
        repeated_value,
        skipped_value,
        0.000_001,
    );
    try std.testing.expectEqual(skipped.remaining, repeated.remaining);
}

test "log ramp rejects invalid values and repairs hostile state" {
    var ramp = try LogRampedValue(f32).init(1.0);
    try std.testing.expectError(
        error.InvalidLogRampValue,
        ramp.setTarget(0.0, 10),
    );
    try std.testing.expectEqual(@as(f32, 1.0), ramp.current());
    ramp.ratio = std.math.nan(f32);
    try std.testing.expectEqual(@as(f32, 1.0), ramp.next());
    try std.testing.expect(ramp.valid());
}
