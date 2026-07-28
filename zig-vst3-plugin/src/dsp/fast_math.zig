const std = @import("std");
const simd_register = @import("simd_register.zig");

/// Selects one bounded Padé approximation.
pub const Operation = enum {
    cosh,
    sinh,
    tanh,
    cosine,
    sine,
    tangent,
    exponential,
    log_one_plus,
};

/// Provides checked scalar and in-place Padé approximations for f32 or f64.
pub fn Approximations(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("fast math supports f32 and f64 values");

    return struct {
        pub fn cosh(value: Sample) !Sample {
            return evaluate(.cosh, value);
        }

        pub fn sinh(value: Sample) !Sample {
            return evaluate(.sinh, value);
        }

        pub fn tanh(value: Sample) !Sample {
            return evaluate(.tanh, value);
        }

        pub fn cos(value: Sample) !Sample {
            return evaluate(.cosine, value);
        }

        pub fn sin(value: Sample) !Sample {
            return evaluate(.sine, value);
        }

        pub fn tan(value: Sample) !Sample {
            return evaluate(.tangent, value);
        }

        pub fn exp(value: Sample) !Sample {
            return evaluate(.exponential, value);
        }

        pub fn logOnePlus(value: Sample) !Sample {
            return evaluate(.log_one_plus, value);
        }

        /// Evaluates one value within the documented range of the operation.
        pub fn evaluate(operation: Operation, value: Sample) !Sample {
            if (!validInput(operation, value))
                return error.FastMathInputOutOfRange;
            const result = approximate(operation, value);
            if (!std.math.isFinite(result))
                return error.FastMathNonFiniteResult;
            return result;
        }

        /// Validates the complete slice before replacing any value.
        pub fn apply(operation: Operation, values: []Sample) !void {
            for (values) |value| _ = try evaluate(operation, value);
            for (values) |*value| value.* = approximate(operation, value.*);
        }

        pub fn applyVector(
            operation: Operation,
            values: []Sample,
            comptime lane_count: usize,
        ) !void {
            if (lane_count == 0 or lane_count > 64)
                @compileError("fast-math SIMD lane count must be 1 through 64");
            for (values) |value| _ = try evaluate(operation, value);

            var offset: usize = 0;
            while (offset + lane_count <= values.len) : (offset += lane_count) {
                const input = loadVector(lane_count, values[offset..]);
                storeVector(
                    lane_count,
                    values[offset..],
                    approximateVector(lane_count, operation, input),
                );
            }
            for (values[offset..]) |*value|
                value.* = approximate(operation, value.*);
        }

        pub fn applyNative(operation: Operation, values: []Sample) !void {
            return applyVector(
                operation,
                values,
                simd_register.nativeLaneCount(Sample),
            );
        }

        fn approximate(operation: Operation, value: Sample) Sample {
            const squared = value * value;
            return switch (operation) {
                .cosh => blk: {
                    const numerator = -(39_251_520.0 +
                        squared * (18_471_600.0 +
                            squared * (1_075_032.0 +
                                14_615.0 * squared)));
                    const denominator = -39_251_520.0 +
                        squared * (1_154_160.0 +
                            squared * (-16_632.0 + 127.0 * squared));
                    break :blk numerator / denominator;
                },
                .sinh => blk: {
                    const numerator = -value * (11_511_339_840.0 +
                        squared * (1_640_635_920.0 +
                            squared * (52_785_432.0 +
                                squared * 479_249.0)));
                    const denominator = -11_511_339_840.0 +
                        squared * (277_920_720.0 +
                            squared * (-3_177_720.0 +
                                squared * 18_361.0));
                    break :blk numerator / denominator;
                },
                .tanh => blk: {
                    const numerator = value * (135_135.0 +
                        squared * (17_325.0 +
                            squared * (378.0 + squared)));
                    const denominator = 135_135.0 +
                        squared * (62_370.0 +
                            squared * (3_150.0 + 28.0 * squared));
                    break :blk numerator / denominator;
                },
                .cosine => blk: {
                    const numerator = 39_251_520.0 -
                        squared * (18_471_600.0 +
                            squared * (-1_075_032.0 +
                                14_615.0 * squared));
                    const denominator = 39_251_520.0 +
                        squared * (1_154_160.0 +
                            squared * (16_632.0 + 127.0 * squared));
                    break :blk numerator / denominator;
                },
                .sine => blk: {
                    const numerator = -value * (-11_511_339_840.0 +
                        squared * (1_640_635_920.0 +
                            squared * (-52_785_432.0 +
                                squared * 479_249.0)));
                    const denominator = 11_511_339_840.0 +
                        squared * (277_920_720.0 +
                            squared * (3_177_720.0 +
                                squared * 18_361.0));
                    break :blk numerator / denominator;
                },
                .tangent => blk: {
                    const numerator = value * (-135_135.0 +
                        squared * (17_325.0 +
                            squared * (-378.0 + squared)));
                    const denominator = -135_135.0 +
                        squared * (62_370.0 +
                            squared * (-3_150.0 + 28.0 * squared));
                    break :blk numerator / denominator;
                },
                .exponential => blk: {
                    const numerator = 1_680.0 + value *
                        (840.0 + value *
                            (180.0 + value * (20.0 + value)));
                    const denominator = 1_680.0 + value *
                        (-840.0 + value *
                            (180.0 + value * (-20.0 + value)));
                    break :blk numerator / denominator;
                },
                .log_one_plus => blk: {
                    const numerator = value * (7_560.0 +
                        value * (15_120.0 +
                            value * (9_870.0 +
                                value * (2_310.0 + value * 137.0))));
                    const denominator = 7_560.0 +
                        value * (18_900.0 +
                            value * (16_800.0 +
                                value * (6_300.0 +
                                    value * (900.0 + 30.0 * value))));
                    break :blk numerator / denominator;
                },
            };
        }

        fn validInput(operation: Operation, value: Sample) bool {
            if (!std.math.isFinite(value)) return false;
            return switch (operation) {
                .cosh, .sinh, .tanh => value >= -5.0 and value <= 5.0,
                .cosine, .sine => value >= -std.math.pi and
                    value <= std.math.pi,
                .tangent => value > -std.math.pi / 2.0 and
                    value < std.math.pi / 2.0,
                .exponential => value >= -6.0 and value <= 4.0,
                .log_one_plus => value >= -0.8 and value <= 5.0,
            };
        }

        fn approximateVector(
            comptime lane_count: usize,
            operation: Operation,
            value: @Vector(lane_count, Sample),
        ) @Vector(lane_count, Sample) {
            const Vector = @Vector(lane_count, Sample);
            const squared = value * value;
            return switch (operation) {
                .cosh => blk: {
                    const numerator = -(vectorConstant(Vector, 39_251_520.0) +
                        squared *
                            (vectorConstant(Vector, 18_471_600.0) +
                                squared *
                                    (vectorConstant(Vector, 1_075_032.0) +
                                        vectorConstant(Vector, 14_615.0) *
                                            squared)));
                    const denominator =
                        vectorConstant(Vector, -39_251_520.0) +
                        squared *
                            (vectorConstant(Vector, 1_154_160.0) +
                                squared *
                                    (vectorConstant(Vector, -16_632.0) +
                                        vectorConstant(Vector, 127.0) *
                                            squared));
                    break :blk numerator / denominator;
                },
                .sinh => blk: {
                    const numerator = -value *
                        (vectorConstant(Vector, 11_511_339_840.0) +
                            squared *
                                (vectorConstant(Vector, 1_640_635_920.0) +
                                    squared *
                                        (vectorConstant(Vector, 52_785_432.0) +
                                            squared *
                                                vectorConstant(
                                                    Vector,
                                                    479_249.0,
                                                ))));
                    const denominator =
                        vectorConstant(Vector, -11_511_339_840.0) +
                        squared *
                            (vectorConstant(Vector, 277_920_720.0) +
                                squared *
                                    (vectorConstant(Vector, -3_177_720.0) +
                                        squared *
                                            vectorConstant(
                                                Vector,
                                                18_361.0,
                                            )));
                    break :blk numerator / denominator;
                },
                .tanh => blk: {
                    const numerator = value *
                        (vectorConstant(Vector, 135_135.0) +
                            squared *
                                (vectorConstant(Vector, 17_325.0) +
                                    squared *
                                        (vectorConstant(Vector, 378.0) +
                                            squared)));
                    const denominator =
                        vectorConstant(Vector, 135_135.0) +
                        squared *
                            (vectorConstant(Vector, 62_370.0) +
                                squared *
                                    (vectorConstant(Vector, 3_150.0) +
                                        vectorConstant(Vector, 28.0) *
                                            squared));
                    break :blk numerator / denominator;
                },
                .cosine => blk: {
                    const numerator =
                        vectorConstant(Vector, 39_251_520.0) -
                        squared *
                            (vectorConstant(Vector, 18_471_600.0) +
                                squared *
                                    (vectorConstant(Vector, -1_075_032.0) +
                                        vectorConstant(Vector, 14_615.0) *
                                            squared));
                    const denominator =
                        vectorConstant(Vector, 39_251_520.0) +
                        squared *
                            (vectorConstant(Vector, 1_154_160.0) +
                                squared *
                                    (vectorConstant(Vector, 16_632.0) +
                                        vectorConstant(Vector, 127.0) *
                                            squared));
                    break :blk numerator / denominator;
                },
                .sine => blk: {
                    const numerator = -value *
                        (vectorConstant(Vector, -11_511_339_840.0) +
                            squared *
                                (vectorConstant(Vector, 1_640_635_920.0) +
                                    squared *
                                        (vectorConstant(Vector, -52_785_432.0) +
                                            squared *
                                                vectorConstant(
                                                    Vector,
                                                    479_249.0,
                                                ))));
                    const denominator =
                        vectorConstant(Vector, 11_511_339_840.0) +
                        squared *
                            (vectorConstant(Vector, 277_920_720.0) +
                                squared *
                                    (vectorConstant(Vector, 3_177_720.0) +
                                        squared *
                                            vectorConstant(
                                                Vector,
                                                18_361.0,
                                            )));
                    break :blk numerator / denominator;
                },
                .tangent => blk: {
                    const numerator = value *
                        (vectorConstant(Vector, -135_135.0) +
                            squared *
                                (vectorConstant(Vector, 17_325.0) +
                                    squared *
                                        (vectorConstant(Vector, -378.0) +
                                            squared)));
                    const denominator =
                        vectorConstant(Vector, -135_135.0) +
                        squared *
                            (vectorConstant(Vector, 62_370.0) +
                                squared *
                                    (vectorConstant(Vector, -3_150.0) +
                                        vectorConstant(Vector, 28.0) *
                                            squared));
                    break :blk numerator / denominator;
                },
                .exponential => blk: {
                    const numerator =
                        vectorConstant(Vector, 1_680.0) +
                        value *
                            (vectorConstant(Vector, 840.0) +
                                value *
                                    (vectorConstant(Vector, 180.0) +
                                        value *
                                            (vectorConstant(Vector, 20.0) +
                                                value)));
                    const denominator =
                        vectorConstant(Vector, 1_680.0) +
                        value *
                            (vectorConstant(Vector, -840.0) +
                                value *
                                    (vectorConstant(Vector, 180.0) +
                                        value *
                                            (vectorConstant(Vector, -20.0) +
                                                value)));
                    break :blk numerator / denominator;
                },
                .log_one_plus => blk: {
                    const numerator = value *
                        (vectorConstant(Vector, 7_560.0) +
                            value *
                                (vectorConstant(Vector, 15_120.0) +
                                    value *
                                        (vectorConstant(Vector, 9_870.0) +
                                            value *
                                                (vectorConstant(
                                                    Vector,
                                                    2_310.0,
                                                ) +
                                                    value *
                                                        vectorConstant(
                                                            Vector,
                                                            137.0,
                                                        )))));
                    const denominator =
                        vectorConstant(Vector, 7_560.0) +
                        value *
                            (vectorConstant(Vector, 18_900.0) +
                                value *
                                    (vectorConstant(Vector, 16_800.0) +
                                        value *
                                            (vectorConstant(Vector, 6_300.0) +
                                                value *
                                                    (vectorConstant(
                                                        Vector,
                                                        900.0,
                                                    ) +
                                                        vectorConstant(
                                                            Vector,
                                                            30.0,
                                                        ) *
                                                            value))));
                    break :blk numerator / denominator;
                },
            };
        }

        fn vectorConstant(
            comptime Vector: type,
            value: Sample,
        ) Vector {
            return @splat(value);
        }

        fn loadVector(
            comptime lane_count: usize,
            source: []const Sample,
        ) @Vector(lane_count, Sample) {
            const Vector = @Vector(lane_count, Sample);
            const pointer: *align(@alignOf(Sample)) const Vector =
                @ptrCast(source.ptr);
            return pointer.*;
        }

        fn storeVector(
            comptime lane_count: usize,
            destination: []Sample,
            value: @Vector(lane_count, Sample),
        ) void {
            const Vector = @Vector(lane_count, Sample);
            const pointer: *align(@alignOf(Sample)) Vector =
                @ptrCast(destination.ptr);
            pointer.* = value;
        }
    };
}

test "fast math scalar approximations track standard functions" {
    const Fast = Approximations(f64);
    try std.testing.expectApproxEqAbs(
        @cos(1.25),
        try Fast.cos(1.25),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @sin(-2.0),
        try Fast.sin(-2.0),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @tan(0.75),
        try Fast.tan(0.75),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @exp(2.0),
        try Fast.exp(2.0),
        0.000_2,
    );
    try std.testing.expectApproxEqAbs(
        @log(1.5),
        try Fast.logOnePlus(0.5),
        0.000_001,
    );
}

test "fast math hyperbolic approximations preserve symmetry" {
    const Fast = Approximations(f32);
    try std.testing.expectApproxEqAbs(
        try Fast.cosh(2.0),
        try Fast.cosh(-2.0),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        try Fast.sinh(2.0),
        -(try Fast.sinh(-2.0)),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        std.math.tanh(@as(f32, 2.0)),
        try Fast.tanh(2.0),
        0.000_01,
    );
}

test "fast math buffer transforms are transactional" {
    const Fast = Approximations(f64);
    var values = [_]f64{ -0.5, 0.0, 0.5 };
    try Fast.apply(.sine, &values);
    try std.testing.expectApproxEqAbs(@sin(-0.5), values[0], 0.000_001);
    try std.testing.expectApproxEqAbs(@sin(0.5), values[2], 0.000_001);

    var invalid = [_]f64{ 0.0, 2.0, 0.25 };
    const before = invalid;
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        Fast.apply(.tangent, &invalid),
    );
    try std.testing.expectEqualSlices(f64, &before, &invalid);
}

test "fast math rejects non-finite and out-of-range values" {
    const Fast = Approximations(f32);
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        Fast.sin(std.math.nan(f32)),
    );
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        Fast.exp(4.01),
    );
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        Fast.logOnePlus(-0.81),
    );
}

test "fast math vector paths match scalar across widths and tails" {
    try expectVectorParity(f32);
    try expectVectorParity(f64);
}

test "fast math vector validation is transactional" {
    const Fast = Approximations(f32);
    var values = [_]f32{ 0.0, 0.25, 2.0, -0.25, 0.5 };
    const before = values;
    try std.testing.expectError(
        error.FastMathInputOutOfRange,
        Fast.applyVector(.tangent, &values, 4),
    );
    try std.testing.expectEqualSlices(f32, &before, &values);
}

fn expectVectorParity(comptime Sample: type) !void {
    const Fast = Approximations(Sample);
    const operations = [_]Operation{
        .cosh,
        .sinh,
        .tanh,
        .cosine,
        .sine,
        .tangent,
        .exponential,
        .log_one_plus,
    };
    const tolerance: Sample =
        if (Sample == f32) 2.0e-5 else 2.0e-12;
    inline for (.{ 2, 4, 8 }) |lane_count| {
        for (operations) |operation| {
            for (0..18) |sample_count| {
                var storage: [19]Sample = @splat(9.0);
                for (
                    storage[1 .. sample_count + 1],
                    0..,
                ) |*sample, index| {
                    sample.* =
                        @as(Sample, @floatFromInt(index % 9)) * 0.1 - 0.4;
                }
                var expected = storage;
                try Fast.apply(
                    operation,
                    expected[1 .. sample_count + 1],
                );
                try Fast.applyVector(
                    operation,
                    storage[1 .. sample_count + 1],
                    lane_count,
                );
                for (expected, storage) |expected_value, actual_value|
                    try std.testing.expectApproxEqAbs(
                        expected_value,
                        actual_value,
                        tolerance,
                    );
            }
        }
    }

    var native_values = [_]Sample{ -0.4, -0.2, 0.0, 0.2, 0.4 };
    var native_expected = native_values;
    try Fast.apply(.exponential, &native_expected);
    try Fast.applyNative(.exponential, &native_values);
    for (native_expected, native_values) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, tolerance);
}
