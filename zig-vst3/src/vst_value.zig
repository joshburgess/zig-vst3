const std = @import("std");

pub fn isNormalized(value: anytype) bool {
    return std.math.isFinite(value) and value >= 0.0 and value <= 1.0;
}

pub fn isPositiveFinite(value: anytype) bool {
    return std.math.isFinite(value) and value > 0.0;
}

test "normalized VST values are finite and inclusive" {
    try std.testing.expect(isNormalized(@as(f64, 0.0)));
    try std.testing.expect(isNormalized(@as(f64, 0.5)));
    try std.testing.expect(isNormalized(@as(f64, 1.0)));
}

test "normalized VST values reject non-finite and out-of-range values" {
    try std.testing.expect(!isNormalized(@as(f64, -0.1)));
    try std.testing.expect(!isNormalized(@as(f64, 1.1)));
    try std.testing.expect(!isNormalized(std.math.nan(f64)));
    try std.testing.expect(!isNormalized(std.math.inf(f64)));
}

test "positive finite VST values reject zero and non-finite values" {
    try std.testing.expect(isPositiveFinite(@as(f64, 44_100.0)));
    try std.testing.expect(!isPositiveFinite(@as(f64, 0.0)));
    try std.testing.expect(!isPositiveFinite(@as(f64, -1.0)));
    try std.testing.expect(!isPositiveFinite(std.math.nan(f64)));
    try std.testing.expect(!isPositiveFinite(std.math.inf(f64)));
}
