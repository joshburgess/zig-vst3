const std = @import("std");

pub fn isFiniteInRange(comptime T: type, value: T, min: T, max: T) bool {
    return std.math.isFinite(value) and value >= min and value <= max;
}

pub fn isNormalized(value: f64) bool {
    return isFiniteInRange(f64, value, 0.0, 1.0);
}

pub fn clampNormalized(value: f64) f64 {
    if (std.math.isNan(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

pub fn clampNormalizedNonZero(value: f64) f64 {
    if (std.math.isNan(value)) return std.math.floatEps(f64);
    return std.math.clamp(value, std.math.floatEps(f64), 1.0);
}

test "isFiniteInRange accepts inclusive finite bounds" {
    try std.testing.expect(isFiniteInRange(f32, -1.0, -1.0, 1.0));
    try std.testing.expect(isFiniteInRange(f32, 0.0, -1.0, 1.0));
    try std.testing.expect(isFiniteInRange(f32, 1.0, -1.0, 1.0));
}

test "isFiniteInRange rejects non-finite and out-of-range values" {
    try std.testing.expect(!isFiniteInRange(f32, -1.1, -1.0, 1.0));
    try std.testing.expect(!isFiniteInRange(f32, 1.1, -1.0, 1.0));
    try std.testing.expect(!isFiniteInRange(f32, std.math.nan(f32), -1.0, 1.0));
    try std.testing.expect(!isFiniteInRange(f32, std.math.inf(f32), -1.0, 1.0));
}

test "isNormalized accepts only finite zero-to-one values" {
    try std.testing.expect(isNormalized(0.0));
    try std.testing.expect(isNormalized(0.5));
    try std.testing.expect(isNormalized(1.0));
    try std.testing.expect(!isNormalized(-0.1));
    try std.testing.expect(!isNormalized(1.1));
    try std.testing.expect(!isNormalized(std.math.nan(f64)));
    try std.testing.expect(!isNormalized(std.math.inf(f64)));
}

test "clampNormalized clamps to finite zero-to-one values" {
    try std.testing.expectEqual(@as(f64, 0.0), clampNormalized(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), clampNormalized(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), clampNormalized(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), clampNormalized(1.25));
}

test "clampNormalizedNonZero keeps values above zero" {
    try std.testing.expectEqual(std.math.floatEps(f64), clampNormalizedNonZero(std.math.nan(f64)));
    try std.testing.expectEqual(std.math.floatEps(f64), clampNormalizedNonZero(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), clampNormalizedNonZero(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), clampNormalizedNonZero(1.25));
}
