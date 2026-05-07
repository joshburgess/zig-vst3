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

pub const IntParam = struct {
    id: u32,
    name: []const u8,
    min: i64,
    max: i64,
    default: i64,

    pub fn init(id: u32, name: []const u8, min: i64, max: i64, default: i64) IntParam {
        std.debug.assert(max > min);
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = std.math.clamp(default, min, max),
        };
    }

    pub fn normalize(self: IntParam, plain: i64) f64 {
        const clamped = std.math.clamp(plain, self.min, self.max);
        return @as(f64, @floatFromInt(clamped - self.min)) / @as(f64, @floatFromInt(self.max - self.min));
    }

    pub fn denormalize(self: IntParam, normalized: f64) i64 {
        const clamped = std.math.clamp(normalized, 0.0, 1.0);
        const range = @as(f64, @floatFromInt(self.max - self.min));
        return self.min + @as(i64, @intFromFloat(@round(clamped * range)));
    }

    pub fn defaultNormalized(self: IntParam) f64 {
        return self.normalize(self.default);
    }
};

pub const BoolParam = struct {
    id: u32,
    name: []const u8,
    default: bool = false,

    pub fn normalize(_: BoolParam, plain: bool) f64 {
        return if (plain) 1.0 else 0.0;
    }

    pub fn denormalize(_: BoolParam, normalized: f64) bool {
        return normalized >= 0.5;
    }

    pub fn defaultNormalized(self: BoolParam) f64 {
        return self.normalize(self.default);
    }
};

pub fn EnumParam(comptime Enum: type) type {
    const info = @typeInfo(Enum).@"enum";
    std.debug.assert(info.fields.len > 0);

    return struct {
        const Self = @This();

        id: u32,
        name: []const u8,
        default: Enum,

        pub fn normalize(_: Self, value: Enum) f64 {
            if (info.fields.len == 1) return 0.0;
            return @as(f64, @floatFromInt(@intFromEnum(value))) / @as(f64, @floatFromInt(info.fields.len - 1));
        }

        pub fn denormalize(_: Self, normalized: f64) Enum {
            const clamped = std.math.clamp(normalized, 0.0, 1.0);
            const max_index = info.fields.len - 1;
            const index = @as(usize, @intFromFloat(@round(clamped * @as(f64, @floatFromInt(max_index)))));
            return @enumFromInt(index);
        }

        pub fn defaultNormalized(self: Self) f64 {
            return self.normalize(self.default);
        }

        pub fn label(_: Self, value: Enum) []const u8 {
            return @tagName(value);
        }
    };
}

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

test "int parameter clamps and rounds normalized values" {
    const param = IntParam.init(2, "Voices", 1, 16, 64);

    try std.testing.expectEqual(@as(u32, 2), param.id);
    try std.testing.expectEqualStrings("Voices", param.name);
    try std.testing.expectEqual(@as(i64, 16), param.default);
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(-2));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(20));
    try std.testing.expectEqual(@as(i64, 1), param.denormalize(-1.0));
    try std.testing.expectEqual(@as(i64, 16), param.denormalize(2.0));
    try std.testing.expectEqual(@as(i64, 9), param.denormalize(0.5));
}

test "bool parameter maps around midpoint" {
    const bypass = BoolParam{ .id = 3, .name = "Bypass", .default = true };

    try std.testing.expectEqual(@as(u32, 3), bypass.id);
    try std.testing.expectEqualStrings("Bypass", bypass.name);
    try std.testing.expectEqual(@as(f64, 1.0), bypass.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), bypass.normalize(false));
    try std.testing.expectEqual(@as(f64, 1.0), bypass.normalize(true));
    try std.testing.expect(!bypass.denormalize(0.49));
    try std.testing.expect(bypass.denormalize(0.5));
}

test "enum parameter maps tags to normalized positions" {
    const Mode = enum { clean, crunch, lead };
    const ModeParam = EnumParam(Mode);
    const mode = ModeParam{ .id = 4, .name = "Mode", .default = .crunch };

    try std.testing.expectEqual(@as(u32, 4), mode.id);
    try std.testing.expectEqualStrings("Mode", mode.name);
    try std.testing.expectEqual(@as(f64, 0.5), mode.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), mode.normalize(.clean));
    try std.testing.expectEqual(@as(f64, 1.0), mode.normalize(.lead));
    try std.testing.expectEqual(Mode.clean, mode.denormalize(-1.0));
    try std.testing.expectEqual(Mode.crunch, mode.denormalize(0.5));
    try std.testing.expectEqual(Mode.lead, mode.denormalize(2.0));
    try std.testing.expectEqualStrings("lead", mode.label(.lead));
}

test "single-value enum parameter stays at zero" {
    const Only = enum { value };
    const OnlyParam = EnumParam(Only);
    const only = OnlyParam{ .id = 5, .name = "Only", .default = .value };

    try std.testing.expectEqual(@as(f64, 0.0), only.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), only.normalize(.value));
    try std.testing.expectEqual(Only.value, only.denormalize(1.0));
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
