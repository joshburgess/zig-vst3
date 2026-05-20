const std = @import("std");

pub fn isFiniteInRange(comptime T: type, value: T, min: T, max: T) bool {
    return std.math.isFinite(value) and value >= min and value <= max;
}

pub fn isPositiveFinite(value: f64) bool {
    return std.math.isFinite(value) and value > 0.0;
}

pub fn isValidRange(min: f64, max: f64) bool {
    return std.math.isFinite(min) and std.math.isFinite(max) and max > min;
}

pub fn isNormalized(value: f64) bool {
    return isFiniteInRange(f64, value, 0.0, 1.0);
}

pub fn isBipolarNormalized(value: f64) bool {
    return isFiniteInRange(f64, value, -1.0, 1.0);
}

pub fn clampNormalized(value: f64) f64 {
    if (std.math.isNan(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

pub fn clampBipolarNormalized(value: f64) f64 {
    if (std.math.isNan(value)) return 0.0;
    return std.math.clamp(value, -1.0, 1.0);
}

pub fn clampNormalizedNonZero(value: f64) f64 {
    if (std.math.isNan(value)) return std.math.floatEps(f64);
    return std.math.clamp(value, std.math.floatEps(f64), 1.0);
}

pub fn normalizedFromBipolar(value: f64) f64 {
    return (clampBipolarNormalized(value) + 1.0) * 0.5;
}

pub fn bipolarFromNormalized(value: f64) f64 {
    return clampNormalized(value) * 2.0 - 1.0;
}

pub fn containsNul(value: []const u8) bool {
    return std.mem.indexOfScalar(u8, value, 0) != null;
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

test "isPositiveFinite accepts only finite values greater than zero" {
    try std.testing.expect(isPositiveFinite(44_100.0));
    try std.testing.expect(!isPositiveFinite(0.0));
    try std.testing.expect(!isPositiveFinite(-1.0));
    try std.testing.expect(!isPositiveFinite(std.math.nan(f64)));
    try std.testing.expect(!isPositiveFinite(std.math.inf(f64)));
}

test "isValidRange accepts only finite increasing ranges" {
    try std.testing.expect(isValidRange(-1.0, 1.0));
    try std.testing.expect(!isValidRange(1.0, 1.0));
    try std.testing.expect(!isValidRange(2.0, 1.0));
    try std.testing.expect(!isValidRange(std.math.nan(f64), 1.0));
    try std.testing.expect(!isValidRange(0.0, std.math.inf(f64)));
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

test "isBipolarNormalized accepts only finite minus-one-to-one values" {
    try std.testing.expect(isBipolarNormalized(-1.0));
    try std.testing.expect(isBipolarNormalized(0.0));
    try std.testing.expect(isBipolarNormalized(1.0));
    try std.testing.expect(!isBipolarNormalized(-1.1));
    try std.testing.expect(!isBipolarNormalized(1.1));
    try std.testing.expect(!isBipolarNormalized(std.math.nan(f64)));
    try std.testing.expect(!isBipolarNormalized(std.math.inf(f64)));
}

test "clampNormalized clamps to finite zero-to-one values" {
    try std.testing.expectEqual(@as(f64, 0.0), clampNormalized(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), clampNormalized(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), clampNormalized(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), clampNormalized(1.25));
}

test "clampBipolarNormalized clamps to finite minus-one-to-one values" {
    try std.testing.expectEqual(@as(f64, 0.0), clampBipolarNormalized(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, -1.0), clampBipolarNormalized(-1.25));
    try std.testing.expectEqual(@as(f64, 0.5), clampBipolarNormalized(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), clampBipolarNormalized(1.25));
}

test "clampNormalizedNonZero keeps values above zero" {
    try std.testing.expectEqual(std.math.floatEps(f64), clampNormalizedNonZero(std.math.nan(f64)));
    try std.testing.expectEqual(std.math.floatEps(f64), clampNormalizedNonZero(-0.25));
    try std.testing.expectEqual(@as(f64, 0.5), clampNormalizedNonZero(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), clampNormalizedNonZero(1.25));
}

test "bipolar normalized conversion clamps both directions" {
    try std.testing.expectEqual(@as(f64, 0.0), normalizedFromBipolar(-2.0));
    try std.testing.expectEqual(@as(f64, 0.25), normalizedFromBipolar(-0.5));
    try std.testing.expectEqual(@as(f64, 0.5), normalizedFromBipolar(0.0));
    try std.testing.expectEqual(@as(f64, 1.0), normalizedFromBipolar(2.0));
    try std.testing.expectEqual(@as(f64, 0.5), normalizedFromBipolar(std.math.nan(f64)));

    try std.testing.expectEqual(@as(f64, -1.0), bipolarFromNormalized(-1.0));
    try std.testing.expectEqual(@as(f64, -0.5), bipolarFromNormalized(0.25));
    try std.testing.expectEqual(@as(f64, 0.0), bipolarFromNormalized(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), bipolarFromNormalized(2.0));
    try std.testing.expectEqual(@as(f64, -1.0), bipolarFromNormalized(std.math.nan(f64)));
}

test "containsNul reports interior NUL bytes" {
    try std.testing.expect(!containsNul(""));
    try std.testing.expect(!containsNul("Gain"));
    try std.testing.expect(containsNul("Gain\x00Trim"));
}
