const std = @import("std");
const common = @import("common.zig");

const clampNormalized = common.clampNormalized;

fn trimPlainText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

pub const FloatParam = struct {
    id: u32,
    name: []const u8,
    short_name: []const u8 = "",
    units: []const u8 = "",
    min: f64 = 0.0,
    max: f64 = 1.0,
    default: f64 = 0.0,
    is_bypass: bool = false,
    can_automate: bool = true,
    is_read_only: bool = false,
    unit_id: i32 = 0,

    /// Use `initChecked` when any argument is known only at runtime.
    pub fn init(
        comptime id: u32,
        comptime name: []const u8,
        comptime min: f64,
        comptime max: f64,
        comptime default: f64,
    ) FloatParam {
        if (comptime !common.isValidRange(min, max))
            @compileError("invalid float parameter range");
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn initChecked(id: u32, name: []const u8, min: f64, max: f64, default: f64) !FloatParam {
        if (!common.isValidRange(min, max)) return error.InvalidParameterRange;
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn containsPlain(self: FloatParam, plain: f64) bool {
        return self.rangeValid() and common.isFiniteInRange(f64, plain, self.min, self.max);
    }

    fn valid(self: FloatParam) bool {
        return self.rangeValid() and common.isFiniteInRange(f64, self.default, self.min, self.max);
    }

    pub fn clampPlain(self: FloatParam, plain: f64) f64 {
        if (!self.rangeValid()) return 0.0;
        if (std.math.isNan(plain)) return self.min;
        return std.math.clamp(plain, self.min, self.max);
    }

    pub fn normalize(self: FloatParam, plain: f64) f64 {
        if (!self.rangeValid()) return 0.0;
        const clamped = self.clampPlain(plain);
        return (clamped - self.min) / (self.max - self.min);
    }

    pub fn denormalize(self: FloatParam, normalized: f64) f64 {
        if (!self.rangeValid()) return 0.0;
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

    pub fn plainFromNormalized(self: FloatParam, normalized: f64) f64 {
        return self.denormalize(normalized);
    }

    pub fn normalizedFromPlain(self: FloatParam, plain: f64) f64 {
        return self.normalize(plain);
    }

    pub fn parsePlain(self: FloatParam, text: []const u8) !f64 {
        const value = try std.fmt.parseFloat(f64, trimPlainText(text));
        return self.normalize(value);
    }

    fn clampPlainInRange(min: f64, max: f64, plain: f64) f64 {
        if (std.math.isNan(plain)) return min;
        return std.math.clamp(plain, min, max);
    }

    fn rangeValid(self: FloatParam) bool {
        return common.isValidRange(self.min, self.max);
    }
};

pub const LogFloatParam = struct {
    id: u32,
    name: []const u8,
    short_name: []const u8 = "",
    units: []const u8 = "",
    min: f64,
    max: f64,
    default: f64,
    is_bypass: bool = false,
    can_automate: bool = true,
    is_read_only: bool = false,
    unit_id: i32 = 0,

    /// Use `initChecked` when any argument is known only at runtime.
    pub fn init(
        comptime id: u32,
        comptime name: []const u8,
        comptime min: f64,
        comptime max: f64,
        comptime default: f64,
    ) LogFloatParam {
        if (comptime !validRange(min, max))
            @compileError("invalid logarithmic parameter range");
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn initChecked(id: u32, name: []const u8, min: f64, max: f64, default: f64) !LogFloatParam {
        if (!validRange(min, max)) return error.InvalidParameterRange;
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn containsPlain(self: LogFloatParam, plain: f64) bool {
        return validRange(self.min, self.max) and
            common.isFiniteInRange(f64, plain, self.min, self.max);
    }

    fn valid(self: LogFloatParam) bool {
        return validRange(self.min, self.max) and
            common.isFiniteInRange(f64, self.default, self.min, self.max);
    }

    pub fn clampPlain(self: LogFloatParam, plain: f64) f64 {
        if (!validRange(self.min, self.max)) return 0.0;
        if (std.math.isNan(plain)) return self.min;
        return std.math.clamp(plain, self.min, self.max);
    }

    pub fn normalize(self: LogFloatParam, plain: f64) f64 {
        if (!validRange(self.min, self.max)) return 0.0;
        return @log(self.clampPlain(plain) / self.min) / @log(self.max / self.min);
    }

    pub fn denormalize(self: LogFloatParam, normalized: f64) f64 {
        if (!validRange(self.min, self.max)) return 0.0;
        return self.min * std.math.pow(f64, self.max / self.min, clampNormalized(normalized));
    }

    pub fn defaultNormalized(self: LogFloatParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPlain(self: LogFloatParam, normalized: f64, buffer: []u8) ![]const u8 {
        const value = self.denormalize(normalized);
        return if (value >= 1_000.0)
            std.fmt.bufPrint(buffer, "{d:.2}k", .{value / 1_000.0})
        else
            std.fmt.bufPrint(buffer, "{d:.1}", .{value});
    }

    pub fn plainFromNormalized(self: LogFloatParam, normalized: f64) f64 {
        return self.denormalize(normalized);
    }

    pub fn normalizedFromPlain(self: LogFloatParam, plain: f64) f64 {
        return self.normalize(plain);
    }

    pub fn parsePlain(self: LogFloatParam, text: []const u8) !f64 {
        const trimmed = trimPlainText(text);
        if (trimmed.len == 0) return error.InvalidCharacter;
        const suffix = trimmed[trimmed.len - 1];
        const has_kilohertz_suffix = suffix == 'k' or suffix == 'K';
        const number = if (has_kilohertz_suffix) trimmed[0 .. trimmed.len - 1] else trimmed;
        const multiplier: f64 = if (has_kilohertz_suffix) 1_000.0 else 1.0;
        return self.normalize((try std.fmt.parseFloat(f64, number)) * multiplier);
    }

    fn validRange(min: f64, max: f64) bool {
        if (!common.isFinite(f64, min) or
            !common.isFinite(f64, max) or
            min <= 0.0 or
            max <= min)
            return false;
        const ratio = max / min;
        return common.isFinite(f64, ratio) and ratio > 1.0;
    }

    fn clampPlainInRange(min: f64, max: f64, plain: f64) f64 {
        if (std.math.isNan(plain)) return min;
        return std.math.clamp(plain, min, max);
    }
};

pub const IntParam = struct {
    id: u32,
    name: []const u8,
    short_name: []const u8 = "",
    units: []const u8 = "",
    min: i64,
    max: i64,
    default: i64,
    is_bypass: bool = false,
    can_automate: bool = true,
    is_read_only: bool = false,
    unit_id: i32 = 0,

    /// Use `initChecked` when any argument is known only at runtime.
    pub fn init(
        comptime id: u32,
        comptime name: []const u8,
        comptime min: i64,
        comptime max: i64,
        comptime default: i64,
    ) IntParam {
        if (comptime max <= min)
            @compileError("invalid integer parameter range");
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn initChecked(id: u32, name: []const u8, min: i64, max: i64, default: i64) !IntParam {
        if (max <= min) return error.InvalidParameterRange;
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = clampPlainInRange(min, max, default),
        };
    }

    pub fn containsPlain(self: IntParam, plain: i64) bool {
        return self.rangeValid() and plain >= self.min and plain <= self.max;
    }

    fn valid(self: IntParam) bool {
        return self.rangeValid() and self.default >= self.min and self.default <= self.max;
    }

    pub fn clampPlain(self: IntParam, plain: i64) i64 {
        if (!self.rangeValid()) return 0;
        return std.math.clamp(plain, self.min, self.max);
    }

    pub fn normalize(self: IntParam, plain: i64) f64 {
        if (!self.rangeValid()) return 0.0;
        const clamped = self.clampPlain(plain);
        const range = @as(f64, @floatFromInt(self.max)) - @as(f64, @floatFromInt(self.min));
        const offset = @as(f64, @floatFromInt(clamped)) - @as(f64, @floatFromInt(self.min));
        return offset / range;
    }

    pub fn denormalize(self: IntParam, normalized: f64) i64 {
        if (!self.rangeValid()) return 0;
        const clamped = clampNormalized(normalized);
        const min = @as(f64, @floatFromInt(self.min));
        const max = @as(f64, @floatFromInt(self.max));
        const plain = @round(min + clamped * (max - min));
        if (plain <= min) return self.min;
        if (plain >= max) return self.max;
        return @intFromFloat(plain);
    }

    pub fn defaultNormalized(self: IntParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPlain(self: IntParam, normalized: f64, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{d}", .{self.denormalize(normalized)});
    }

    pub fn plainFromNormalized(self: IntParam, normalized: f64) f64 {
        return @floatFromInt(self.denormalize(normalized));
    }

    pub fn normalizedFromPlain(self: IntParam, plain: f64) f64 {
        if (std.math.isNan(plain)) return self.normalize(self.min);
        if (plain <= @as(f64, @floatFromInt(self.min))) return self.normalize(self.min);
        if (plain >= @as(f64, @floatFromInt(self.max))) return self.normalize(self.max);
        return self.normalize(@intFromFloat(@round(plain)));
    }

    pub fn parsePlain(self: IntParam, text: []const u8) !f64 {
        const value = try std.fmt.parseInt(i64, trimPlainText(text), 10);
        return self.normalize(value);
    }

    fn clampPlainInRange(min: i64, max: i64, plain: i64) i64 {
        return std.math.clamp(plain, min, max);
    }

    fn rangeValid(self: IntParam) bool {
        return self.max > self.min;
    }
};

pub const BoolParam = struct {
    id: u32,
    name: []const u8,
    short_name: []const u8 = "",
    units: []const u8 = "",
    default: bool = false,
    is_bypass: bool = false,
    can_automate: bool = true,
    is_read_only: bool = false,
    unit_id: i32 = 0,

    pub fn normalize(_: BoolParam, plain: bool) f64 {
        return if (plain) 1.0 else 0.0;
    }

    pub fn denormalize(_: BoolParam, normalized: f64) bool {
        return normalized >= 0.5;
    }

    pub fn defaultNormalized(self: BoolParam) f64 {
        return self.normalize(self.default);
    }

    pub fn formatPlain(self: BoolParam, normalized: f64, _: []u8) ![]const u8 {
        return if (self.denormalize(normalized)) "On" else "Off";
    }

    pub fn plainFromNormalized(self: BoolParam, normalized: f64) f64 {
        return if (self.denormalize(normalized)) 1.0 else 0.0;
    }

    pub fn normalizedFromPlain(self: BoolParam, plain: f64) f64 {
        return self.normalize(plain >= 0.5);
    }

    pub fn parsePlain(self: BoolParam, text: []const u8) !f64 {
        const trimmed = trimPlainText(text);
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
    if (info.fields.len == 0) {
        @compileError("EnumParam requires at least one enum field");
    }
    if (!info.is_exhaustive) {
        @compileError("EnumParam requires an exhaustive enum");
    }

    return struct {
        const Self = @This();

        id: u32,
        name: []const u8,
        short_name: []const u8 = "",
        units: []const u8 = "",
        default: Enum,
        is_bypass: bool = false,
        can_automate: bool = true,
        is_read_only: bool = false,
        unit_id: i32 = 0,

        pub fn normalize(_: Self, value: Enum) f64 {
            if (info.fields.len == 1) return 0.0;
            return normalizedFromIndex(indexOf(value));
        }

        pub fn denormalize(_: Self, normalized: f64) Enum {
            const clamped = clampNormalized(normalized);
            const max_index = info.fields.len - 1;
            const index = @as(usize, @intFromFloat(@round(clamped * @as(f64, @floatFromInt(max_index)))));
            return valueAtIndex(index);
        }

        pub fn defaultNormalized(self: Self) f64 {
            return self.normalize(self.default);
        }

        pub fn label(_: Self, value: Enum) []const u8 {
            return @tagName(value);
        }

        pub fn optionCount(_: Self) usize {
            return info.fields.len;
        }

        pub fn indexOfValue(_: Self, value: Enum) usize {
            return indexOf(value);
        }

        pub fn valueAtOptionIndex(_: Self, wanted_index: usize) ?Enum {
            if (wanted_index >= info.fields.len) return null;
            return valueAtIndex(wanted_index);
        }

        pub fn labelAtOptionIndex(_: Self, wanted_index: usize) ?[]const u8 {
            inline for (info.fields, 0..) |field, index| {
                if (index == wanted_index) return field.name;
            }
            return null;
        }

        pub fn normalizedFromOptionIndex(_: Self, wanted_index: usize) ?f64 {
            if (wanted_index >= info.fields.len) return null;
            return normalizedFromIndex(wanted_index);
        }

        pub fn formatPlain(self: Self, normalized: f64, _: []u8) ![]const u8 {
            return self.label(self.denormalize(normalized));
        }

        pub fn plainFromNormalized(self: Self, normalized: f64) f64 {
            return @floatFromInt(indexOf(self.denormalize(normalized)));
        }

        pub fn normalizedFromPlain(_: Self, plain: f64) f64 {
            const max_index = info.fields.len - 1;
            const index = if (std.math.isNan(plain) or plain <= 0)
                0
            else if (plain >= @as(f64, @floatFromInt(max_index)))
                max_index
            else
                @as(usize, @intFromFloat(@round(plain)));
            return normalizedFromIndex(index);
        }

        pub fn parsePlain(_: Self, text: []const u8) !f64 {
            const trimmed = trimPlainText(text);
            inline for (info.fields, 0..) |field, index| {
                if (std.mem.eql(u8, trimmed, field.name)) {
                    return normalizedFromIndex(index);
                }
            }
            return error.InvalidEnumTag;
        }

        fn indexOf(value: Enum) usize {
            inline for (info.fields, 0..) |field, index| {
                if (field.value == @intFromEnum(value)) return index;
            }
            return 0;
        }

        fn valueAtIndex(wanted_index: usize) Enum {
            inline for (info.fields, 0..) |field, index| {
                if (index == wanted_index) return @enumFromInt(field.value);
            }
            return @enumFromInt(info.fields[0].value);
        }

        fn normalizedFromIndex(index: usize) f64 {
            if (info.fields.len == 1) return 0.0;
            return @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(info.fields.len - 1));
        }
    };
}
test "float parameter clamps defaults and values" {
    const param = FloatParam.init(7, "Gain", -12.0, 6.0, 12.0);
    const nan_default = FloatParam.init(8, "Safe", -12.0, 6.0, std.math.nan(f64));
    const checked = try FloatParam.initChecked(9, "Checked", -1.0, 1.0, 3.0);

    try std.testing.expectEqual(@as(u32, 7), param.id);
    try std.testing.expectEqualStrings("Gain", param.name);
    try std.testing.expectEqual(@as(f64, 6.0), param.default);
    try std.testing.expectEqual(@as(f64, -12.0), nan_default.default);
    try std.testing.expectEqual(@as(f64, 1.0), checked.default);
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(-24.0));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(12.0));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(std.math.nan(f64)));
    try std.testing.expect(param.containsPlain(0.0));
    try std.testing.expect(!param.containsPlain(-24.0));
    try std.testing.expect(!param.containsPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, -12.0), param.clampPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 6.0), param.clampPlain(12.0));
    try std.testing.expectEqual(@as(f64, -12.0), param.denormalize(-1.0));
    try std.testing.expectEqual(@as(f64, 6.0), param.denormalize(2.0));
    try std.testing.expectEqual(@as(f64, -12.0), param.denormalize(std.math.nan(f64)));
    try std.testing.expectError(error.InvalidParameterRange, FloatParam.initChecked(1, "Flat", 1.0, 1.0, 1.0));
    try std.testing.expectError(error.InvalidParameterRange, FloatParam.initChecked(1, "Inf", 0.0, std.math.inf(f64), 1.0));
    try std.testing.expectError(error.InvalidParameterRange, FloatParam.initChecked(1, "NaN", std.math.nan(f64), 1.0, 1.0));
    try std.testing.expectError(
        error.InvalidParameterRange,
        FloatParam.initChecked(
            1,
            "Overflowing span",
            -std.math.floatMax(f64),
            std.math.floatMax(f64),
            0.0,
        ),
    );
}

test "logarithmic float parameter maps and formats perceptual ranges" {
    const frequency = try LogFloatParam.initChecked(10, "Frequency", 20.0, 20_000.0, 1_000.0);
    var buffer: [32]u8 = undefined;

    try std.testing.expectApproxEqRel(@as(f64, 632.455532), frequency.denormalize(0.5), 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), frequency.normalize(632.455532), 0.000001);
    try std.testing.expectEqualStrings("1.00k", try frequency.formatPlain(frequency.normalize(1_000.0), &buffer));
    try std.testing.expectApproxEqAbs(frequency.normalize(2_500.0), try frequency.parsePlain("2.5k"), 0.000001);
    try std.testing.expectApproxEqAbs(frequency.normalize(2_500.0), try frequency.parsePlain(" 2.5K "), 0.000001);
    try std.testing.expectEqual(@as(f64, 0.0), frequency.normalize(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 1.0), frequency.normalize(std.math.inf(f64)));
    try std.testing.expectError(error.InvalidParameterRange, LogFloatParam.initChecked(11, "Invalid", 0.0, 20_000.0, 1_000.0));
    try std.testing.expectError(
        error.InvalidParameterRange,
        LogFloatParam.initChecked(
            11,
            "Overflowing ratio",
            std.math.floatMin(f64),
            std.math.floatMax(f64),
            1.0,
        ),
    );
}

test "parameter descriptor parsing trims plain text consistently" {
    const Mode = enum { clean, lead };
    const gain = FloatParam.init(1, "Gain", 0.0, 1.0, 0.0);
    const voices = IntParam.init(2, "Voices", 1, 16, 1);
    const bypass = BoolParam{ .id = 3, .name = "Bypass" };
    const mode = EnumParam(Mode){ .id = 4, .name = "Mode", .default = .clean };

    try std.testing.expectEqual(@as(f64, 0.5), try gain.parsePlain("\t0.5\r\n"));
    try std.testing.expectEqual(@as(f64, 1.0), try voices.parsePlain("\t16\r\n"));
    try std.testing.expectEqual(@as(f64, 1.0), try bypass.parsePlain("\ttrue\r\n"));
    try std.testing.expectEqual(@as(f64, 1.0), try mode.parsePlain("\tlead\r\n"));
}

test "int parameter clamps and rounds normalized values" {
    const param = IntParam.init(2, "Voices", 1, 16, 64);
    const checked = try IntParam.initChecked(3, "Checked", 1, 4, -2);

    try std.testing.expectEqual(@as(u32, 2), param.id);
    try std.testing.expectEqualStrings("Voices", param.name);
    try std.testing.expectEqual(@as(i64, 16), param.default);
    try std.testing.expectEqual(@as(i64, 1), checked.default);
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(-2));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(20));
    try std.testing.expect(param.containsPlain(8));
    try std.testing.expect(!param.containsPlain(0));
    try std.testing.expectEqual(@as(i64, 1), param.clampPlain(-2));
    try std.testing.expectEqual(@as(i64, 16), param.clampPlain(20));
    try std.testing.expectEqual(@as(i64, 1), param.denormalize(-1.0));
    try std.testing.expectEqual(@as(i64, 16), param.denormalize(2.0));
    try std.testing.expectEqual(@as(i64, 9), param.denormalize(0.5));
    try std.testing.expectEqual(@as(i64, 1), param.denormalize(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalizedFromPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalizedFromPlain(-1.0e30));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalizedFromPlain(1.0e30));
    try std.testing.expectError(error.InvalidParameterRange, IntParam.initChecked(1, "Flat", 4, 4, 4));
    try std.testing.expectError(error.InvalidParameterRange, IntParam.initChecked(1, "Reverse", 4, 1, 1));
}

test "int parameter handles full-width ranges without overflow" {
    const param = IntParam.init(9, "Wide", std.math.minInt(i64), std.math.maxInt(i64), 0);

    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(std.math.minInt(i64)));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(std.math.maxInt(i64)));
    try std.testing.expectEqual(std.math.minInt(i64), param.denormalize(0.0));
    try std.testing.expectEqual(std.math.maxInt(i64), param.denormalize(1.0));
    try std.testing.expect(param.defaultNormalized() > 0.49);
    try std.testing.expect(param.defaultNormalized() < 0.51);
}

test "numeric descriptors contain malformed direct state" {
    var buffer: [32]u8 = undefined;

    const flat_float = FloatParam{
        .id = 1,
        .name = "Flat",
        .min = 1.0,
        .max = 1.0,
        .default = 1.0,
    };
    try std.testing.expect(!flat_float.valid());
    try std.testing.expect(!flat_float.containsPlain(1.0));
    try std.testing.expectEqual(@as(f64, 0.0), flat_float.clampPlain(1.0));
    try std.testing.expectEqual(@as(f64, 0.0), flat_float.normalize(1.0));
    try std.testing.expectEqual(@as(f64, 0.0), flat_float.denormalize(0.5));
    try std.testing.expectEqual(@as(f64, 0.0), flat_float.defaultNormalized());
    try std.testing.expectEqualStrings("0%", try flat_float.formatPercent(0.5, &buffer));

    const invalid_log = LogFloatParam{
        .id = 2,
        .name = "Log",
        .min = 0.0,
        .max = 20_000.0,
        .default = 1_000.0,
    };
    try std.testing.expect(!invalid_log.valid());
    try std.testing.expect(!invalid_log.containsPlain(1_000.0));
    try std.testing.expectEqual(@as(f64, 0.0), invalid_log.clampPlain(1_000.0));
    try std.testing.expectEqual(@as(f64, 0.0), invalid_log.normalize(1_000.0));
    try std.testing.expectEqual(@as(f64, 0.0), invalid_log.denormalize(0.5));
    try std.testing.expectEqual(@as(f64, 0.0), invalid_log.defaultNormalized());
    try std.testing.expectEqualStrings("0.0", try invalid_log.formatPlain(0.5, &buffer));

    const reversed_int = IntParam{
        .id = 3,
        .name = "Int",
        .min = 4,
        .max = 1,
        .default = 2,
    };
    try std.testing.expect(!reversed_int.valid());
    try std.testing.expect(!reversed_int.containsPlain(2));
    try std.testing.expectEqual(@as(i64, 0), reversed_int.clampPlain(2));
    try std.testing.expectEqual(@as(f64, 0.0), reversed_int.normalize(2));
    try std.testing.expectEqual(@as(i64, 0), reversed_int.denormalize(0.5));
    try std.testing.expectEqual(@as(f64, 0.0), reversed_int.defaultNormalized());
    try std.testing.expectEqualStrings("0", try reversed_int.formatPlain(0.5, &buffer));
}

test "bool parameter maps around midpoint" {
    const bypass = BoolParam{ .id = 3, .name = "Bypass", .default = true, .is_bypass = true };

    try std.testing.expectEqual(@as(u32, 3), bypass.id);
    try std.testing.expectEqualStrings("Bypass", bypass.name);
    try std.testing.expect(bypass.is_bypass);
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
    try std.testing.expectEqual(Mode.clean, mode.denormalize(std.math.nan(f64)));
    try std.testing.expectEqual(Mode.crunch, mode.denormalize(0.5));
    try std.testing.expectEqual(Mode.lead, mode.denormalize(2.0));
    try std.testing.expectEqual(@as(f64, 0.0), mode.normalizedFromPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), mode.normalizedFromPlain(-100.0));
    try std.testing.expectEqual(@as(f64, 1.0), mode.normalizedFromPlain(100.0));
    try std.testing.expectEqualStrings("lead", mode.label(.lead));
    try std.testing.expectEqual(@as(usize, 3), mode.optionCount());
    try std.testing.expectEqual(@as(usize, 1), mode.indexOfValue(.crunch));
    try std.testing.expectEqual(Mode.lead, mode.valueAtOptionIndex(2).?);
    try std.testing.expectEqual(@as(?Mode, null), mode.valueAtOptionIndex(3));
    try std.testing.expectEqualStrings("clean", mode.labelAtOptionIndex(0).?);
    try std.testing.expectEqual(@as(?[]const u8, null), mode.labelAtOptionIndex(3));
    try std.testing.expectEqual(@as(?f64, 0.5), mode.normalizedFromOptionIndex(1));
    try std.testing.expectEqual(@as(?f64, null), mode.normalizedFromOptionIndex(3));
}

test "enum parameter supports sparse tag values" {
    const Mode = enum(u8) { clean = 2, crunch = 7, lead = 42 };
    const ModeParam = EnumParam(Mode);
    const mode = ModeParam{ .id = 4, .name = "Mode", .default = .crunch };

    try std.testing.expectEqual(@as(f64, 0.5), mode.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), mode.normalize(.clean));
    try std.testing.expectEqual(@as(f64, 0.5), mode.normalize(.crunch));
    try std.testing.expectEqual(@as(f64, 1.0), mode.normalize(.lead));
    try std.testing.expectEqual(Mode.clean, mode.denormalize(0.0));
    try std.testing.expectEqual(Mode.crunch, mode.denormalize(0.5));
    try std.testing.expectEqual(Mode.lead, mode.denormalize(1.0));
    try std.testing.expectEqual(@as(f64, 1.0), mode.plainFromNormalized(0.5));
    try std.testing.expectEqual(@as(f64, 1.0), mode.normalizedFromPlain(2.0));
    try std.testing.expectEqual(@as(f64, 1.0), try mode.parsePlain("lead"));
    try std.testing.expectEqual(@as(usize, 2), mode.indexOfValue(.lead));
    try std.testing.expectEqual(Mode.crunch, mode.valueAtOptionIndex(1).?);
    try std.testing.expectEqualStrings("lead", mode.labelAtOptionIndex(2).?);
    try std.testing.expectEqual(@as(?f64, 1.0), mode.normalizedFromOptionIndex(2));
}

test "single-value enum parameter stays at zero" {
    const Only = enum { value };
    const OnlyParam = EnumParam(Only);
    const only = OnlyParam{ .id = 5, .name = "Only", .default = .value };

    try std.testing.expectEqual(@as(f64, 0.0), only.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), only.normalize(.value));
    try std.testing.expectEqual(Only.value, only.denormalize(1.0));
    try std.testing.expectEqual(@as(usize, 1), only.optionCount());
    try std.testing.expectEqual(@as(?f64, 0.0), only.normalizedFromOptionIndex(0));
}

test "float and integer descriptors normalize generated values within bounds" {
    const float = FloatParam.init(10, "Float", -24.0, 12.0, 0.0);
    const int = IntParam.init(11, "Int", -7, 9, 0);
    const float_inputs = [_]f64{
        -std.math.inf(f64),
        -1.0e12,
        -24.0,
        -6.0,
        0.0,
        12.0,
        1.0e12,
        std.math.inf(f64),
        std.math.nan(f64),
    };
    const int_inputs = [_]i64{
        std.math.minInt(i64),
        -128,
        -7,
        -1,
        0,
        1,
        9,
        128,
        std.math.maxInt(i64),
    };
    const normalized_inputs = [_]f64{
        -std.math.inf(f64),
        -100.0,
        -0.25,
        0.0,
        0.25,
        0.5,
        0.75,
        1.0,
        1.25,
        100.0,
        std.math.inf(f64),
        std.math.nan(f64),
    };

    for (float_inputs) |plain| {
        const normalized = float.normalize(plain);
        try std.testing.expect(normalized >= 0.0);
        try std.testing.expect(normalized <= 1.0);
        try std.testing.expect(float.containsPlain(float.denormalize(normalized)));
    }

    for (int_inputs) |plain| {
        const normalized = int.normalize(plain);
        try std.testing.expect(normalized >= 0.0);
        try std.testing.expect(normalized <= 1.0);
        try std.testing.expect(int.containsPlain(int.denormalize(normalized)));
    }

    for (normalized_inputs) |normalized| {
        try std.testing.expect(float.containsPlain(float.denormalize(normalized)));
        try std.testing.expect(int.containsPlain(int.denormalize(normalized)));
    }
}

test "enum descriptors map generated normalized values to valid options" {
    const Mode = enum(u8) { clean = 2, crunch = 7, lead = 42, fuzz = 99 };
    const ModeParam = EnumParam(Mode);
    const mode = ModeParam{ .id = 12, .name = "Mode", .default = .clean };
    const expected_options = [_]struct {
        value: Mode,
        label: []const u8,
        normalized: f64,
    }{
        .{ .value = .clean, .label = "clean", .normalized = 0.0 },
        .{ .value = .crunch, .label = "crunch", .normalized = 1.0 / 3.0 },
        .{ .value = .lead, .label = "lead", .normalized = 2.0 / 3.0 },
        .{ .value = .fuzz, .label = "fuzz", .normalized = 1.0 },
    };
    const normalized_inputs = [_]f64{
        -std.math.inf(f64),
        -100.0,
        -0.25,
        0.0,
        0.1,
        0.34,
        0.5,
        0.66,
        0.9,
        1.0,
        1.25,
        100.0,
        std.math.inf(f64),
        std.math.nan(f64),
    };
    const plain_inputs = [_]f64{
        -std.math.inf(f64),
        -100.0,
        -0.25,
        0.0,
        1.0,
        2.0,
        3.0,
        4.0,
        100.0,
        std.math.inf(f64),
        std.math.nan(f64),
    };

    try std.testing.expectEqual(expected_options.len, mode.optionCount());
    for (expected_options, 0..) |expected, index| {
        try std.testing.expectEqual(index, mode.indexOfValue(expected.value));
        try std.testing.expectEqual(expected.value, mode.valueAtOptionIndex(index).?);
        try std.testing.expectEqualStrings(expected.label, mode.labelAtOptionIndex(index).?);
        try std.testing.expectEqual(expected.normalized, mode.normalizedFromOptionIndex(index).?);
    }
    try std.testing.expectEqual(@as(?Mode, null), mode.valueAtOptionIndex(expected_options.len));
    try std.testing.expectEqual(@as(?[]const u8, null), mode.labelAtOptionIndex(expected_options.len));
    try std.testing.expectEqual(@as(?f64, null), mode.normalizedFromOptionIndex(expected_options.len));

    for (normalized_inputs) |normalized| {
        const value = mode.denormalize(normalized);
        const index = mode.indexOfValue(value);
        try std.testing.expect(index < mode.optionCount());
        try std.testing.expectEqual(value, mode.valueAtOptionIndex(index).?);
        try std.testing.expectEqual(mode.normalize(value), mode.normalizedFromOptionIndex(index).?);
    }

    for (plain_inputs) |plain| {
        const normalized = mode.normalizedFromPlain(plain);
        try std.testing.expect(normalized >= 0.0);
        try std.testing.expect(normalized <= 1.0);
    }
}
