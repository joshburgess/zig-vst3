const std = @import("std");

pub fn Phase(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Phase supports f32 and f64 values");

    return struct {
        const Self = @This();

        radians: Sample = 0.0,

        pub fn init(radians: Sample) !Self {
            if (!std.math.isFinite(radians))
                return error.InvalidPhase;
            return .{ .radians = wrap(radians) };
        }

        pub fn reset(self: *Self) void {
            self.radians = 0.0;
        }

        /// Returns the current phase, then advances by a nonnegative increment.
        pub fn advance(self: *Self, increment: Sample) !Sample {
            if (!self.valid() or
                !std.math.isFinite(increment) or
                increment < 0.0)
                return error.InvalidPhaseAdvance;
            const current = self.radians;
            self.radians = wrap(self.radians + @mod(increment, std.math.tau));
            return current;
        }

        pub fn valid(self: *const Self) bool {
            return std.math.isFinite(self.radians) and
                self.radians >= 0.0 and
                self.radians < std.math.tau;
        }

        fn wrap(value: Sample) Sample {
            const remainder = @mod(value, std.math.tau);
            return if (remainder < 0.0)
                remainder + std.math.tau
            else
                remainder;
        }
    };
}

test "phase returns its current value and wraps positive advances" {
    var phase = try Phase(f64).init(std.math.tau - 0.25);
    try std.testing.expectApproxEqAbs(
        std.math.tau - 0.25,
        try phase.advance(0.5),
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        phase.radians,
        0.000_000_000_001,
    );
    try std.testing.expect(phase.valid());
}

test "phase normalizes construction and reset" {
    var phase = try Phase(f32).init(-0.5);
    try std.testing.expectApproxEqAbs(
        @as(f32, std.math.tau - 0.5),
        phase.radians,
        0.000_001,
    );
    phase.reset();
    try std.testing.expectEqual(@as(f32, 0.0), phase.radians);
}

test "phase rejects invalid increments without mutation" {
    var phase = try Phase(f32).init(0.25);
    try std.testing.expectError(
        error.InvalidPhaseAdvance,
        phase.advance(-0.5),
    );
    try std.testing.expectEqual(@as(f32, 0.25), phase.radians);
    phase.radians = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidPhaseAdvance,
        phase.advance(0.5),
    );
}
