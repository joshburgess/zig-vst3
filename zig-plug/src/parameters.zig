const std = @import("std");

pub const FloatParam = struct {
    id: u32,
    name: []const u8,
    min: f64 = 0.0,
    max: f64 = 1.0,
    default: f64 = 0.0,

    pub fn init(id: u32, name: []const u8, min: f64, max: f64, default: f64) FloatParam {
        std.debug.assert(max > min);
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = std.math.clamp(default, min, max),
        };
    }

    pub fn normalize(self: FloatParam, plain: f64) f64 {
        const clamped = std.math.clamp(plain, self.min, self.max);
        return (clamped - self.min) / (self.max - self.min);
    }

    pub fn denormalize(self: FloatParam, normalized: f64) f64 {
        const clamped = std.math.clamp(normalized, 0.0, 1.0);
        return self.min + clamped * (self.max - self.min);
    }

    pub fn defaultNormalized(self: FloatParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPercent(self: FloatParam, normalized: f64, buffer: []u8) ![]const u8 {
        const percent = @as(u32, @intFromFloat(@round(self.normalize(self.denormalize(normalized)) * 100.0)));
        return std.fmt.bufPrint(buffer, "{d}%", .{percent});
    }
};

test "float parameter clamps defaults and values" {
    const param = FloatParam.init(7, "Gain", -12.0, 6.0, 12.0);

    try std.testing.expectEqual(@as(u32, 7), param.id);
    try std.testing.expectEqualStrings("Gain", param.name);
    try std.testing.expectEqual(@as(f64, 6.0), param.default);
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(-24.0));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(12.0));
    try std.testing.expectEqual(@as(f64, -12.0), param.denormalize(-1.0));
    try std.testing.expectEqual(@as(f64, 6.0), param.denormalize(2.0));
}

test "float parameter round-trips normalized values" {
    const param = FloatParam.init(0, "Gain", 0.0, 1.0, 0.5);
    const values = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0 };

    for (values) |value| {
        try std.testing.expectApproxEqAbs(value, param.normalize(param.denormalize(value)), 0.000001);
    }
}

test "float parameter formats percent values" {
    const param = FloatParam.init(0, "Gain", 0.0, 1.0, 1.0);
    var buffer: [8]u8 = undefined;

    try std.testing.expectEqualStrings("0%", try param.formatPercent(0.0, &buffer));
    try std.testing.expectEqualStrings("50%", try param.formatPercent(0.5, &buffer));
    try std.testing.expectEqualStrings("100%", try param.formatPercent(2.0, &buffer));
}
