const std = @import("std");

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

pub const LinearSmoother = struct {
    current: f64,
    target: f64,
    step: f64 = 0.0,
    remaining: usize = 0,

    pub fn init(value: f64) LinearSmoother {
        const clamped = clampNormalized(value);
        return .{ .current = clamped, .target = clamped };
    }

    pub fn setTarget(self: *LinearSmoother, target: f64, samples: usize) void {
        self.target = clampNormalized(target);
        self.remaining = samples;
        if (samples == 0) {
            self.current = self.target;
            self.step = 0.0;
        } else {
            self.step = (self.target - self.current) / @as(f64, @floatFromInt(samples));
        }
    }

    pub fn next(self: *LinearSmoother) f64 {
        if (self.remaining == 0) return self.current;
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.current = self.target;
        } else {
            self.current += self.step;
        }
        return self.current;
    }
};

pub const ExponentialSmoother = struct {
    current: f64,
    target: f64,
    coefficient: f64,

    pub fn init(value: f64, coefficient: f64) ExponentialSmoother {
        const clamped = clampNormalized(value);
        return .{
            .current = clamped,
            .target = clamped,
            .coefficient = clampNormalized(coefficient),
        };
    }

    pub fn setTarget(self: *ExponentialSmoother, target: f64) void {
        self.target = clampNormalized(target);
    }

    pub fn next(self: *ExponentialSmoother) f64 {
        self.current += (self.target - self.current) * self.coefficient;
        return self.current;
    }
};

fn clampNormalized(value: f64) f64 {
    return std.math.clamp(value, 0.0, 1.0);
}

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
        const clamped = clampNormalized(normalized);
        return self.min + clamped * (self.max - self.min);
    }

    pub fn defaultNormalized(self: FloatParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPercent(self: FloatParam, normalized: f64, buffer: []u8) ![]const u8 {
        const percent = @as(u32, @intFromFloat(@round(self.normalize(self.denormalize(normalized)) * 100.0)));
        return std.fmt.bufPrint(buffer, "{d}%", .{percent});
    }

    pub fn formatPlain(self: FloatParam, normalized: f64, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{d:.3}", .{self.denormalize(normalized)});
    }

    pub fn parsePlain(self: FloatParam, text: []const u8) !f64 {
        const value = try std.fmt.parseFloat(f64, std.mem.trim(u8, text, " \t\r\n"));
        return self.normalize(value);
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
        const clamped = clampNormalized(normalized);
        const range = @as(f64, @floatFromInt(self.max - self.min));
        return self.min + @as(i64, @intFromFloat(@round(clamped * range)));
    }

    pub fn defaultNormalized(self: IntParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPlain(self: IntParam, normalized: f64, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{d}", .{self.denormalize(normalized)});
    }

    pub fn parsePlain(self: IntParam, text: []const u8) !f64 {
        const value = try std.fmt.parseInt(i64, std.mem.trim(u8, text, " \t\r\n"), 10);
        return self.normalize(value);
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

    pub fn formatPlain(self: BoolParam, normalized: f64) []const u8 {
        return if (self.denormalize(normalized)) "On" else "Off";
    }

    pub fn parsePlain(self: BoolParam, text: []const u8) !f64 {
        const trimmed = std.mem.trim(u8, text, " \t\r\n");
        if (std.ascii.eqlIgnoreCase(trimmed, "on") or
            std.ascii.eqlIgnoreCase(trimmed, "true") or
            std.mem.eql(u8, trimmed, "1"))
        {
            return self.normalize(true);
        }
        if (std.ascii.eqlIgnoreCase(trimmed, "off") or
            std.ascii.eqlIgnoreCase(trimmed, "false") or
            std.mem.eql(u8, trimmed, "0"))
        {
            return self.normalize(false);
        }
        return error.InvalidBool;
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
            const clamped = clampNormalized(normalized);
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

        pub fn formatPlain(self: Self, normalized: f64) []const u8 {
            return self.label(self.denormalize(normalized));
        }

        pub fn parsePlain(self: Self, text: []const u8) !f64 {
            const trimmed = std.mem.trim(u8, text, " \t\r\n");
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, trimmed, field.name)) {
                    return self.normalize(@enumFromInt(field.value));
                }
            }
            return error.InvalidEnumTag;
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

test "normalized value clamps and updates atomically" {
    var value = NormalizedValue.init(2.0);

    try std.testing.expectEqual(@as(f64, 1.0), value.load());
    value.store(-1.0);
    try std.testing.expectEqual(@as(f64, 0.0), value.load());
    value.store(0.25);
    try std.testing.expectEqual(@as(f64, 0.25), value.load());
}

test "linear smoother reaches target after requested samples" {
    var smoother = LinearSmoother.init(0.0);

    smoother.setTarget(1.0, 4);
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "linear smoother handles immediate and clamped targets" {
    var smoother = LinearSmoother.init(0.25);

    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(-1.0, 2);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
}

test "exponential smoother approaches target by coefficient" {
    var smoother = ExponentialSmoother.init(0.0, 0.25);

    smoother.setTarget(1.0);
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.4375, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.578125, smoother.next(), 0.000001);
}

test "exponential smoother clamps initial value target and coefficient" {
    var smoother = ExponentialSmoother.init(2.0, 2.0);

    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.coefficient, 0.000001);
    smoother.setTarget(-1.0);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
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

test "parameters format and parse plain values" {
    const gain = FloatParam.init(0, "Gain", 0.0, 1.0, 0.25);
    const voices = IntParam.init(1, "Voices", 1, 16, 4);
    const bypass = BoolParam{ .id = 2, .name = "Bypass" };
    const Mode = enum { clean, crunch, lead };
    const ModeParam = EnumParam(Mode);
    const mode = ModeParam{ .id = 3, .name = "Mode", .default = .clean };
    var buffer: [16]u8 = undefined;

    try std.testing.expectEqualStrings("0.500", try gain.formatPlain(0.5, &buffer));
    try std.testing.expectApproxEqAbs(0.75, try gain.parsePlain(" 0.75 "), 0.000001);
    try std.testing.expectEqualStrings("9", try voices.formatPlain(0.5, &buffer));
    try std.testing.expectApproxEqAbs(1.0, try voices.parsePlain("16"), 0.000001);
    try std.testing.expectEqualStrings("On", bypass.formatPlain(1.0));
    try std.testing.expectEqual(@as(f64, 0.0), try bypass.parsePlain("off"));
    try std.testing.expectEqualStrings("crunch", mode.formatPlain(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), try mode.parsePlain("lead"));
}
