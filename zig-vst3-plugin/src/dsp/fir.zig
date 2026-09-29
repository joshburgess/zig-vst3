const std = @import("std");

pub fn FirFilter(comptime Sample: type, comptime coefficient_capacity: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("FirFilter supports f32 and f64 samples");
    if (coefficient_capacity == 0)
        @compileError("FirFilter coefficient capacity must be nonzero");

    return struct {
        const Self = @This();

        coefficients: [coefficient_capacity]Sample = @splat(0.0),
        coefficient_count: usize = 0,
        history: [coefficient_capacity]Sample = @splat(0.0),
        write_index: usize = 0,

        pub fn init(coefficients: []const Sample) !Self {
            var self = Self{};
            try self.configure(coefficients);
            return self;
        }

        pub fn configure(
            self: *Self,
            coefficients: []const Sample,
        ) !void {
            if (coefficients.len == 0 or
                coefficients.len > coefficient_capacity)
                return error.InvalidFirCoefficients;
            for (coefficients) |coefficient| {
                if (!std.math.isFinite(coefficient))
                    return error.InvalidFirCoefficients;
            }

            var replacement: [coefficient_capacity]Sample = @splat(0.0);
            @memcpy(replacement[0..coefficients.len], coefficients);
            self.coefficients = replacement;
            self.coefficient_count = coefficients.len;
            self.reset();
        }

        pub fn reset(self: *Self) void {
            self.history = @splat(0.0);
            self.write_index = 0;
        }

        pub fn processSample(self: *Self, input: Sample) Sample {
            return self.processSampleChecked(input) catch {
                if (!self.valid()) self.* = .{} else self.reset();
                return if (std.math.isFinite(input)) input else 0.0;
            };
        }

        pub fn processSampleChecked(
            self: *Self,
            input: Sample,
        ) !Sample {
            if (!self.valid())
                return error.InvalidFirFilterState;
            if (!std.math.isFinite(input))
                return error.NonFiniteFirInput;
            self.history[self.write_index] =
                input;

            var output: Sample = 0.0;
            for (self.coefficients[0..self.coefficient_count], 0..) |
                coefficient,
                offset,
            | {
                const history_index =
                    (self.write_index + coefficient_capacity -
                        offset % coefficient_capacity) %
                    coefficient_capacity;
                output += coefficient * self.history[history_index];
            }
            self.write_index = (self.write_index + 1) % coefficient_capacity;
            if (!std.math.isFinite(output)) {
                self.reset();
                return error.NonFiniteFirOutput;
            }
            return output;
        }

        pub fn process(self: *Self, samples: []Sample) void {
            for (samples) |*sample| sample.* = self.processSample(sample.*);
        }

        pub fn valid(self: *const Self) bool {
            if (self.coefficient_count == 0 or
                self.coefficient_count > coefficient_capacity or
                self.write_index >= coefficient_capacity)
                return false;
            for (self.coefficients[0..self.coefficient_count]) |coefficient| {
                if (!std.math.isFinite(coefficient)) return false;
            }
            for (self.history) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }
    };
}

test "FIR filter produces its impulse response across blocks" {
    var filter = try FirFilter(f32, 4).init(&.{ 0.5, 0.25, -0.125 });
    var first = [_]f32{ 1.0, 0.0 };
    var second = [_]f32{ 0.0, 0.0 };
    filter.process(&first);
    filter.process(&second);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 0.25 },
        &first,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ -0.125, 0.0 },
        &second,
    );
}

test "FIR configuration is transactional and resets history" {
    var filter = try FirFilter(f64, 3).init(&.{ 1.0, 0.5 });
    _ = filter.processSample(2.0);
    try std.testing.expectError(
        error.InvalidFirCoefficients,
        filter.configure(&.{std.math.nan(f64)}),
    );
    try std.testing.expectEqual(
        @as(f64, 1.0),
        filter.coefficients[0],
    );
    try filter.configure(&.{0.25});
    try std.testing.expectEqual(
        @as(f64, 0.0),
        filter.processSample(0.0),
    );
}

test "FIR filter recovers malformed public state" {
    var filter = try FirFilter(f32, 2).init(&.{1.0});
    filter.write_index = 3;
    try std.testing.expectEqual(
        @as(f32, 0.5),
        filter.processSample(0.5),
    );
    try std.testing.expect(!filter.valid());
}

test "checked FIR processing reports failures without fail-silent fallback" {
    var filter = try FirFilter(f32, 2).init(&.{ 1.0, 0.5 });
    try std.testing.expectError(
        error.NonFiniteFirInput,
        filter.processSampleChecked(std.math.inf(f32)),
    );
    try std.testing.expect(filter.valid());
    filter.write_index = 3;
    try std.testing.expectError(
        error.InvalidFirFilterState,
        filter.processSampleChecked(0.5),
    );
}
