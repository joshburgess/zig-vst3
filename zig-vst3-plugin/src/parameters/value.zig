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

test "normalized and modulated values clamp generated inputs" {
    const inputs = [_]f64{
        -std.math.inf(f64),
        -1.0,
        -0.001,
        0.0,
        0.25,
        1.0,
        1.001,
        2.0,
        std.math.inf(f64),
        std.math.nan(f64),
    };

    for (inputs) |input| {
        var normalized = NormalizedValue.init(input);
        const expected = if (std.math.isNan(input) or input < 0.0) 0.0 else if (input > 1.0) 1.0 else input;
        try std.testing.expectEqual(expected, normalized.load());

        normalized.store(1.0 - expected);
        try std.testing.expectEqual(1.0 - expected, normalized.load());
    }

    for (inputs) |base| {
        for (inputs) |modulation| {
            var value = ModulatedValue.init(base);
            const expected_base = if (std.math.isNan(base) or base < 0.0) 0.0 else if (base > 1.0) 1.0 else base;
            const expected_modulation = if (std.math.isNan(modulation)) 0.0 else std.math.clamp(modulation, -1.0, 1.0);

            value.storeModulation(modulation);

            try std.testing.expectEqual(expected_base, value.loadBase());
            try std.testing.expectApproxEqAbs(expected_modulation, value.loadModulation(), 0.000001);
            try std.testing.expectApproxEqAbs(std.math.clamp(expected_base + expected_modulation, 0.0, 1.0), value.load(), 0.000001);
        }
    }
}
