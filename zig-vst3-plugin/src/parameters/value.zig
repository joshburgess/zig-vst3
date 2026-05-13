const std = @import("std");
const common = @import("common.zig");

const clampNormalized = common.clampNormalized;

pub const NormalizedValue = struct {
    bits: std.atomic.Value(u64),

    pub fn init(value: f64) NormalizedValue {
        return .{ .bits = std.atomic.Value(u64).init(@bitCast(clampNormalized(value))) };
    }

    pub fn load(self: *const NormalizedValue) f64 {
        return @bitCast(@constCast(&self.bits).load(.monotonic));
    }

    pub fn store(self: *NormalizedValue, value: f64) void {
        self.bits.store(@bitCast(clampNormalized(value)), .monotonic);
    }
};

pub const ModulatedValue = struct {
    base: NormalizedValue,
    modulation: NormalizedValue = NormalizedValue.init(0.5),

    pub fn init(base: f64) ModulatedValue {
        return .{ .base = NormalizedValue.init(base) };
    }

    pub fn storeBase(self: *ModulatedValue, value: f64) void {
        self.base.store(value);
    }

    pub fn loadBase(self: *const ModulatedValue) f64 {
        return self.base.load();
    }

    pub fn storeModulation(self: *ModulatedValue, offset: f64) void {
        const safe_offset = if (std.math.isNan(offset)) 0.0 else std.math.clamp(offset, -1.0, 1.0);
        self.modulation.store((safe_offset + 1.0) * 0.5);
    }

    pub fn loadModulation(self: *const ModulatedValue) f64 {
        return self.modulation.load() * 2.0 - 1.0;
    }

    pub fn load(self: *const ModulatedValue) f64 {
        return clampNormalized(self.loadBase() + self.loadModulation());
    }
};
test "normalized value clamps and updates atomically" {
    var value = NormalizedValue.init(2.0);

    try std.testing.expectEqual(@as(f64, 1.0), value.load());
    value.store(-1.0);
    try std.testing.expectEqual(@as(f64, 0.0), value.load());
    value.store(std.math.nan(f64));
    try std.testing.expectEqual(@as(f64, 0.0), value.load());
    value.store(0.25);
    try std.testing.expectEqual(@as(f64, 0.25), value.load());
}

test "modulated value combines base and bipolar offset" {
    var value = ModulatedValue.init(0.5);

    try std.testing.expectEqual(@as(f64, 0.5), value.loadBase());
    try std.testing.expectEqual(@as(f64, 0.0), value.loadModulation());
    try std.testing.expectEqual(@as(f64, 0.5), value.load());
    value.storeModulation(0.25);
    try std.testing.expectEqual(@as(f64, 0.25), value.loadModulation());
    try std.testing.expectEqual(@as(f64, 0.75), value.load());
    value.storeBase(0.1);
    try std.testing.expectEqual(@as(f64, 0.1), value.loadBase());
    value.storeModulation(-0.5);
    try std.testing.expectEqual(@as(f64, 0.0), value.load());
    value.storeModulation(2.0);
    try std.testing.expectEqual(@as(f64, 1.0), value.loadModulation());
    try std.testing.expectEqual(@as(f64, 1.0), value.load());
    value.storeBase(0.25);
    value.storeModulation(std.math.nan(f64));
    try std.testing.expectEqual(@as(f64, 0.0), value.loadModulation());
    try std.testing.expectEqual(@as(f64, 0.25), value.load());
}
