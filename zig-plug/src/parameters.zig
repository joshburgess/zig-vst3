const std = @import("std");
const process = @import("process.zig");

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

pub const LinearSmoother = struct {
    current: f64,
    target: f64,
    step: f64 = 0.0,
    remaining: usize = 0,

    pub fn init(value: f64) LinearSmoother {
        const clamped = clampNormalized(value);
        return .{ .current = clamped, .target = clamped };
    }

    pub fn reset(self: *LinearSmoother, value: f64) void {
        const clamped = clampNormalized(value);
        self.current = clamped;
        self.target = clamped;
        self.step = 0.0;
        self.remaining = 0;
    }

    pub fn currentValue(self: LinearSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: LinearSmoother) f64 {
        return self.target;
    }

    pub fn remainingSamples(self: LinearSmoother) usize {
        return self.remaining;
    }

    pub fn active(self: LinearSmoother) bool {
        return self.remaining != 0;
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

    pub fn reset(self: *ExponentialSmoother, value: f64) void {
        const clamped = clampNormalized(value);
        self.current = clamped;
        self.target = clamped;
    }

    pub fn currentValue(self: ExponentialSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: ExponentialSmoother) f64 {
        return self.target;
    }

    pub fn setCoefficient(self: *ExponentialSmoother, coefficient: f64) void {
        self.coefficient = clampNormalized(coefficient);
    }

    pub fn setTarget(self: *ExponentialSmoother, target: f64) void {
        self.target = clampNormalized(target);
    }

    pub fn next(self: *ExponentialSmoother) f64 {
        self.current += (self.target - self.current) * self.coefficient;
        return self.current;
    }
};

pub const LogSmoother = struct {
    current: f64,
    target: f64,
    ratio: f64 = 1.0,
    remaining: usize = 0,

    pub fn init(value: f64) LogSmoother {
        const clamped = clampNormalizedNonZero(value);
        return .{ .current = clamped, .target = clamped };
    }

    pub fn reset(self: *LogSmoother, value: f64) void {
        const clamped = clampNormalizedNonZero(value);
        self.current = clamped;
        self.target = clamped;
        self.ratio = 1.0;
        self.remaining = 0;
    }

    pub fn currentValue(self: LogSmoother) f64 {
        return self.current;
    }

    pub fn targetValue(self: LogSmoother) f64 {
        return self.target;
    }

    pub fn remainingSamples(self: LogSmoother) usize {
        return self.remaining;
    }

    pub fn active(self: LogSmoother) bool {
        return self.remaining != 0;
    }

    pub fn setTarget(self: *LogSmoother, target: f64, samples: usize) void {
        self.target = clampNormalizedNonZero(target);
        self.remaining = samples;
        if (samples == 0) {
            self.current = self.target;
            self.ratio = 1.0;
        } else {
            self.ratio = std.math.pow(f64, self.target / self.current, 1.0 / @as(f64, @floatFromInt(samples)));
        }
    }

    pub fn next(self: *LogSmoother) f64 {
        if (self.remaining == 0) return self.current;
        self.remaining -= 1;
        if (self.remaining == 0) {
            self.current = self.target;
        } else {
            self.current *= self.ratio;
        }
        return self.current;
    }
};

fn clampNormalized(value: f64) f64 {
    if (std.math.isNan(value)) return 0.0;
    return std.math.clamp(value, 0.0, 1.0);
}

fn clampNormalizedNonZero(value: f64) f64 {
    if (std.math.isNan(value)) return std.math.floatEps(f64);
    return std.math.clamp(value, std.math.floatEps(f64), 1.0);
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

    pub fn init(id: u32, name: []const u8, min: f64, max: f64, default: f64) FloatParam {
        std.debug.assert(max > min);
        return .{
            .id = id,
            .name = name,
            .min = min,
            .max = max,
            .default = if (std.math.isNan(default)) min else std.math.clamp(default, min, max),
        };
    }

    pub fn normalize(self: FloatParam, plain: f64) f64 {
        if (std.math.isNan(plain)) return 0.0;
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

    pub fn plainFromNormalized(self: FloatParam, normalized: f64) f64 {
        return self.denormalize(normalized);
    }

    pub fn normalizedFromPlain(self: FloatParam, plain: f64) f64 {
        return self.normalize(plain);
    }

    pub fn parsePlain(self: FloatParam, text: []const u8) !f64 {
        const value = try std.fmt.parseFloat(f64, std.mem.trim(u8, text, " \t\r\n"));
        return self.normalize(value);
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
        const range = @as(f64, @floatFromInt(self.max)) - @as(f64, @floatFromInt(self.min));
        const offset = @as(f64, @floatFromInt(clamped)) - @as(f64, @floatFromInt(self.min));
        return offset / range;
    }

    pub fn denormalize(self: IntParam, normalized: f64) i64 {
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
        const value = try std.fmt.parseInt(i64, std.mem.trim(u8, text, " \t\r\n"), 10);
        return self.normalize(value);
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
            const trimmed = std.mem.trim(u8, text, " \t\r\n");
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
            unreachable;
        }

        fn valueAtIndex(wanted_index: usize) Enum {
            inline for (info.fields, 0..) |field, index| {
                if (index == wanted_index) return @enumFromInt(field.value);
            }
            unreachable;
        }

        fn normalizedFromIndex(index: usize) f64 {
            if (info.fields.len == 1) return 0.0;
            return @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(info.fields.len - 1));
        }
    };
}

pub fn ParameterSet(comptime Params: type) type {
    const fields = @typeInfo(Params).@"struct".fields;

    return struct {
        const Self = @This();

        pub const count = fields.len;

        params: Params,

        pub fn init(params: Params) Self {
            return .{ .params = params };
        }

        pub fn parameterCount(_: *const Self) usize {
            return count;
        }

        pub fn parametersEmpty(_: *const Self) bool {
            return count == 0;
        }

        pub fn hasParameters(_: *const Self) bool {
            return count != 0;
        }

        pub fn duplicateId(self: *const Self) ?u32 {
            inline for (fields, 0..) |left_field, left_index| {
                const left_id = @field(self.params, left_field.name).id;
                inline for (fields, 0..) |right_field, right_index| {
                    if (right_index > left_index and @field(self.params, right_field.name).id == left_id) {
                        return left_id;
                    }
                }
            }
            return null;
        }

        pub fn hasDuplicateIds(self: *const Self) bool {
            return self.duplicateId() != null;
        }

        pub fn validateUniqueIds(self: *const Self) !void {
            if (self.hasDuplicateIds()) return error.DuplicateParameterId;
        }

        pub fn duplicateName(self: *const Self) ?[]const u8 {
            inline for (fields, 0..) |left_field, left_index| {
                const left_name = @field(self.params, left_field.name).name;
                inline for (fields, 0..) |right_field, right_index| {
                    if (right_index > left_index and std.mem.eql(u8, @field(self.params, right_field.name).name, left_name)) {
                        return left_name;
                    }
                }
            }
            return null;
        }

        pub fn hasDuplicateNames(self: *const Self) bool {
            return self.duplicateName() != null;
        }

        pub fn validateUniqueNames(self: *const Self) !void {
            if (self.hasDuplicateNames()) return error.DuplicateParameterName;
        }

        pub fn firstDescriptorError(self: *const Self) ?anyerror {
            inline for (fields) |field| {
                if (parameterDescriptorError(@field(self.params, field.name))) |err| return err;
            }
            return null;
        }

        pub fn validateDescriptors(self: *const Self) !void {
            if (self.firstDescriptorError()) |err| return err;
        }

        pub fn validate(self: *const Self) !void {
            try self.validateUniqueIds();
            try self.validateUniqueNames();
            try self.validateDescriptors();
        }

        pub fn validateUnitIds(self: *const Self, unit_set: anytype) !void {
            inline for (fields) |field| {
                const unit_id = @field(self.params, field.name).unit_id;
                if (!unit_set.hasUnit(unit_id)) return error.InvalidParameterUnit;
            }
        }

        pub fn id(self: *const Self, index: usize) ?u32 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).id;
            }
            return null;
        }

        pub fn name(self: *const Self, index: usize) ?[]const u8 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).name;
            }
            return null;
        }

        pub fn nameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.name(index);
        }

        pub fn idByName(self: *const Self, wanted_name: []const u8) ?u32 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.id(index);
        }

        pub fn shortName(self: *const Self, index: usize) ?[]const u8 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) {
                    const value = @field(self.params, field.name).short_name;
                    return if (value.len == 0) @field(self.params, field.name).name else value;
                }
            }
            return null;
        }

        pub fn shortNameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.shortName(index);
        }

        pub fn shortNameByName(self: *const Self, wanted_name: []const u8) ?[]const u8 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.shortName(index);
        }

        pub fn units(self: *const Self, index: usize) ?[]const u8 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).units;
            }
            return null;
        }

        pub fn unitsById(self: *const Self, wanted_id: u32) ?[]const u8 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.units(index);
        }

        pub fn unitsByName(self: *const Self, wanted_name: []const u8) ?[]const u8 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.units(index);
        }

        pub fn defaultNormalized(self: *const Self, index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).defaultNormalized();
            }
            return null;
        }

        pub fn defaultNormalizedById(self: *const Self, wanted_id: u32) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.defaultNormalized(index);
        }

        pub fn defaultNormalizedByName(self: *const Self, wanted_name: []const u8) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.defaultNormalized(index);
        }

        pub fn isBypass(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).is_bypass;
            }
            return null;
        }

        pub fn isBypassById(self: *const Self, wanted_id: u32) ?bool {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.isBypass(index);
        }

        pub fn isBypassByName(self: *const Self, wanted_name: []const u8) ?bool {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.isBypass(index);
        }

        pub fn canAutomate(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).can_automate;
            }
            return null;
        }

        pub fn canAutomateById(self: *const Self, wanted_id: u32) ?bool {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.canAutomate(index);
        }

        pub fn canAutomateByName(self: *const Self, wanted_name: []const u8) ?bool {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.canAutomate(index);
        }

        pub fn isReadOnly(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).is_read_only;
            }
            return null;
        }

        pub fn isReadOnlyById(self: *const Self, wanted_id: u32) ?bool {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.isReadOnly(index);
        }

        pub fn isReadOnlyByName(self: *const Self, wanted_name: []const u8) ?bool {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.isReadOnly(index);
        }

        pub fn unitId(self: *const Self, index: usize) ?i32 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).unit_id;
            }
            return null;
        }

        pub fn unitIdById(self: *const Self, wanted_id: u32) ?i32 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.unitId(index);
        }

        pub fn unitIdByName(self: *const Self, wanted_name: []const u8) ?i32 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.unitId(index);
        }

        pub fn stepCount(self: *const Self, index: usize) ?i32 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterStepCount(@field(self.params, field.name));
            }
            return null;
        }

        pub fn stepCountById(self: *const Self, wanted_id: u32) ?i32 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.stepCount(index);
        }

        pub fn stepCountByName(self: *const Self, wanted_name: []const u8) ?i32 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.stepCount(index);
        }

        pub fn isList(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterIsList(@field(self.params, field.name));
            }
            return null;
        }

        pub fn isListById(self: *const Self, wanted_id: u32) ?bool {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.isList(index);
        }

        pub fn isListByName(self: *const Self, wanted_name: []const u8) ?bool {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.isList(index);
        }

        pub fn indexOfId(self: *const Self, wanted_id: u32) ?usize {
            inline for (fields, 0..) |field, index| {
                if (@field(self.params, field.name).id == wanted_id) return index;
            }
            return null;
        }

        pub fn indexOfName(self: *const Self, wanted_name: []const u8) ?usize {
            inline for (fields, 0..) |field, index| {
                if (std.mem.eql(u8, @field(self.params, field.name).name, wanted_name)) return index;
            }
            return null;
        }

        pub fn hasId(self: *const Self, wanted_id: u32) bool {
            return self.indexOfId(wanted_id) != null;
        }

        pub fn hasName(self: *const Self, wanted_name: []const u8) bool {
            return self.indexOfName(wanted_name) != null;
        }

        pub fn indexOfField(_: *const Self, comptime field_name: []const u8) usize {
            inline for (fields, 0..) |field, index| {
                if (comptime std.mem.eql(u8, field.name, field_name)) return index;
            }
            @compileError("unknown parameter field: " ++ field_name);
        }

        pub fn descriptor(self: *const Self, comptime field_name: []const u8) FieldDescriptor(Params, field_name) {
            return @field(self.params, field_name);
        }

        pub fn fieldId(self: *const Self, comptime field_name: []const u8) u32 {
            return self.descriptor(field_name).id;
        }

        pub fn fieldName(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.descriptor(field_name).name;
        }

        pub fn fieldShortName(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.shortName(self.indexOfField(field_name)).?;
        }

        pub fn fieldUnits(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.descriptor(field_name).units;
        }

        pub fn fieldDefaultNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.descriptor(field_name).defaultNormalized();
        }

        pub fn fieldIsBypass(self: *const Self, comptime field_name: []const u8) bool {
            return self.descriptor(field_name).is_bypass;
        }

        pub fn fieldCanAutomate(self: *const Self, comptime field_name: []const u8) bool {
            return self.descriptor(field_name).can_automate;
        }

        pub fn fieldIsReadOnly(self: *const Self, comptime field_name: []const u8) bool {
            return self.descriptor(field_name).is_read_only;
        }

        pub fn fieldUnitId(self: *const Self, comptime field_name: []const u8) i32 {
            return self.descriptor(field_name).unit_id;
        }

        pub fn fieldStepCount(self: *const Self, comptime field_name: []const u8) i32 {
            return parameterStepCount(self.descriptor(field_name));
        }

        pub fn fieldIsList(self: *const Self, comptime field_name: []const u8) bool {
            return parameterIsList(self.descriptor(field_name));
        }

        pub fn parameterChangeNormalized(
            self: *const Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            normalized: f64,
        ) process.ParameterChange {
            return .{
                .id = self.descriptor(field_name).id,
                .sample_offset = sample_offset,
                .normalized = normalized,
            };
        }

        pub fn parameterChange(
            self: *const Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            plain: FieldPlainType(Params, field_name),
        ) process.ParameterChange {
            const param = self.descriptor(field_name);
            return self.parameterChangeNormalized(field_name, sample_offset, param.normalize(plain));
        }

        pub fn formatFieldPlain(self: *const Self, comptime field_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.descriptor(field_name).formatPlain(normalized, buffer);
        }

        pub fn parseFieldPlain(self: *const Self, comptime field_name: []const u8, text: []const u8) !f64 {
            return self.descriptor(field_name).parsePlain(text);
        }

        pub fn fieldPlainFromNormalized(self: *const Self, comptime field_name: []const u8, normalized: f64) FieldPlainType(Params, field_name) {
            return self.descriptor(field_name).denormalize(normalized);
        }

        pub fn fieldNormalizedFromPlain(self: *const Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) f64 {
            return self.descriptor(field_name).normalize(plain);
        }

        pub fn formatPlain(self: *const Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).formatPlain(normalized, buffer);
            }
            return error.InvalidParameterIndex;
        }

        pub fn formatPlainById(self: *const Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            const index = self.indexOfId(wanted_id) orelse return error.InvalidParameterId;
            return self.formatPlain(index, normalized, buffer);
        }

        pub fn formatPlainByName(self: *const Self, wanted_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            const index = self.indexOfName(wanted_name) orelse return error.InvalidParameterName;
            return self.formatPlain(index, normalized, buffer);
        }

        pub fn parsePlain(self: *const Self, index: usize, text: []const u8) !f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).parsePlain(text);
            }
            return error.InvalidParameterIndex;
        }

        pub fn parsePlainById(self: *const Self, wanted_id: u32, text: []const u8) !f64 {
            const index = self.indexOfId(wanted_id) orelse return error.InvalidParameterId;
            return self.parsePlain(index, text);
        }

        pub fn parsePlainByName(self: *const Self, wanted_name: []const u8, text: []const u8) !f64 {
            const index = self.indexOfName(wanted_name) orelse return error.InvalidParameterName;
            return self.parsePlain(index, text);
        }

        pub fn plainFromNormalized(self: *const Self, index: usize, normalized: f64) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).plainFromNormalized(normalized);
            }
            return null;
        }

        pub fn plainFromNormalizedById(self: *const Self, wanted_id: u32, normalized: f64) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.plainFromNormalized(index, normalized);
        }

        pub fn plainFromNormalizedByName(self: *const Self, wanted_name: []const u8, normalized: f64) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.plainFromNormalized(index, normalized);
        }

        pub fn normalizedFromPlain(self: *const Self, index: usize, plain: f64) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).normalizedFromPlain(plain);
            }
            return null;
        }

        pub fn normalizedFromPlainById(self: *const Self, wanted_id: u32, plain: f64) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.normalizedFromPlain(index, plain);
        }

        pub fn normalizedFromPlainByName(self: *const Self, wanted_name: []const u8, plain: f64) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.normalizedFromPlain(index, plain);
        }
    };
}

fn parameterStepCount(param: anytype) i32 {
    const Param = @TypeOf(param);
    if (Param == FloatParam) return 0;
    if (Param == BoolParam) return 1;
    if (Param == IntParam) {
        const range = std.math.sub(i64, param.max, param.min) catch return std.math.maxInt(i32);
        return std.math.cast(i32, range) orelse std.math.maxInt(i32);
    }

    const info = @typeInfo(Param);
    if (info == .@"struct" and @hasDecl(Param, "denormalize")) {
        const default_type = @TypeOf(param.default);
        if (@typeInfo(default_type) == .@"enum") {
            return std.math.cast(i32, @typeInfo(default_type).@"enum".fields.len - 1) orelse std.math.maxInt(i32);
        }
    }
    return 0;
}

fn parameterIsList(param: anytype) bool {
    const Param = @TypeOf(param);
    if (Param == BoolParam) return false;
    const info = @typeInfo(Param);
    if (info == .@"struct" and @hasDecl(Param, "label")) {
        return @typeInfo(@TypeOf(param.default)) == .@"enum";
    }
    return false;
}

fn parameterDescriptorError(param: anytype) ?anyerror {
    const Param = @TypeOf(param);
    if (param.name.len == 0) return error.EmptyParameterName;
    if (std.mem.indexOfScalar(u8, param.name, 0) != null or
        std.mem.indexOfScalar(u8, param.short_name, 0) != null or
        std.mem.indexOfScalar(u8, param.units, 0) != null)
    {
        return error.InvalidParameterMetadata;
    }
    if (Param == FloatParam) {
        if (!std.math.isFinite(param.min) or !std.math.isFinite(param.max) or param.max <= param.min) {
            return error.InvalidParameterRange;
        }
        if (!std.math.isFinite(param.default)) return error.InvalidParameterDefault;
        if (param.default < param.min or param.default > param.max) return error.InvalidParameterDefault;
    } else if (Param == IntParam) {
        if (param.max <= param.min) return error.InvalidParameterRange;
        if (param.default < param.min or param.default > param.max) return error.InvalidParameterDefault;
    }
    return null;
}

pub fn ParameterValues(comptime Params: type) type {
    const Set = ParameterSet(Params);

    return struct {
        const Self = @This();

        values: [Set.count]NormalizedValue,

        pub fn init(set: *const Set) Self {
            var self: Self = undefined;
            inline for (0..Set.count) |index| {
                self.values[index] = NormalizedValue.init(set.defaultNormalized(index).?);
            }
            return self;
        }

        pub fn load(self: *const Self, index: usize) ?f64 {
            if (index >= Set.count) return null;
            return self.values[index].load();
        }

        pub fn loadPlain(self: *const Self, set: *const Set, index: usize) ?f64 {
            const normalized = self.load(index) orelse return null;
            return set.plainFromNormalized(index, normalized);
        }

        pub fn store(self: *Self, index: usize, value: f64) bool {
            if (index >= Set.count) return false;
            if (!std.math.isFinite(value)) return false;
            self.values[index].store(value);
            return true;
        }

        pub fn storePlain(self: *Self, set: *const Set, index: usize, plain: f64) bool {
            const normalized = set.normalizedFromPlain(index, plain) orelse return false;
            return self.store(index, normalized);
        }

        pub fn copyFrom(self: *Self, source: *const Self) void {
            inline for (0..Set.count) |index| {
                self.values[index].store(source.values[index].load());
            }
        }

        pub fn resetToDefaults(self: *Self, set: *const Set) void {
            inline for (0..Set.count) |index| {
                self.values[index].store(set.defaultNormalized(index).?);
            }
        }

        pub fn resetToDefault(self: *Self, set: *const Set, index: usize) bool {
            const default = set.defaultNormalized(index) orelse return false;
            self.values[index].store(default);
            return true;
        }

        pub fn loadById(self: *const Self, set: *const Set, id: u32) ?f64 {
            const index = set.indexOfId(id) orelse return null;
            return self.load(index);
        }

        pub fn loadPlainById(self: *const Self, set: *const Set, id: u32) ?f64 {
            const index = set.indexOfId(id) orelse return null;
            return self.loadPlain(set, index);
        }

        pub fn loadByName(self: *const Self, set: *const Set, name: []const u8) ?f64 {
            const index = set.indexOfName(name) orelse return null;
            return self.load(index);
        }

        pub fn loadPlainByName(self: *const Self, set: *const Set, name: []const u8) ?f64 {
            const index = set.indexOfName(name) orelse return null;
            return self.loadPlain(set, index);
        }

        pub fn loadFieldNormalized(self: *const Self, set: *const Set, comptime field_name: []const u8) f64 {
            return self.load(set.indexOfField(field_name)).?;
        }

        pub fn loadField(self: *const Self, set: *const Set, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            const param = set.descriptor(field_name);
            return param.denormalize(self.loadFieldNormalized(set, field_name));
        }

        pub fn isDefault(self: *const Self, set: *const Set, index: usize) ?bool {
            const current = self.load(index) orelse return null;
            const default = set.defaultNormalized(index) orelse return null;
            return current == default;
        }

        pub fn isDefaultById(self: *const Self, set: *const Set, id: u32) ?bool {
            const index = set.indexOfId(id) orelse return null;
            return self.isDefault(set, index);
        }

        pub fn isDefaultByName(self: *const Self, set: *const Set, name: []const u8) ?bool {
            const index = set.indexOfName(name) orelse return null;
            return self.isDefault(set, index);
        }

        pub fn fieldIsDefault(self: *const Self, set: *const Set, comptime field_name: []const u8) bool {
            return self.isDefault(set, set.indexOfField(field_name)).?;
        }

        pub fn storeById(self: *Self, set: *const Set, id: u32, value: f64) bool {
            const index = set.indexOfId(id) orelse return false;
            return self.store(index, value);
        }

        pub fn storePlainById(self: *Self, set: *const Set, id: u32, plain: f64) bool {
            const index = set.indexOfId(id) orelse return false;
            return self.storePlain(set, index, plain);
        }

        pub fn storeByName(self: *Self, set: *const Set, name: []const u8, normalized: f64) bool {
            const index = set.indexOfName(name) orelse return false;
            return self.store(index, normalized);
        }

        pub fn storePlainByName(self: *Self, set: *const Set, name: []const u8, plain: f64) bool {
            const index = set.indexOfName(name) orelse return false;
            return self.storePlain(set, index, plain);
        }

        pub fn storeField(self: *Self, set: *const Set, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) bool {
            const param = set.descriptor(field_name);
            return self.store(set.indexOfField(field_name), param.normalize(plain));
        }

        pub fn storeFieldNormalized(self: *Self, set: *const Set, comptime field_name: []const u8, normalized: f64) bool {
            return self.store(set.indexOfField(field_name), normalized);
        }

        pub fn resetToDefaultById(self: *Self, set: *const Set, id: u32) bool {
            const index = set.indexOfId(id) orelse return false;
            return self.resetToDefault(set, index);
        }

        pub fn resetToDefaultByName(self: *Self, set: *const Set, name: []const u8) bool {
            const index = set.indexOfName(name) orelse return false;
            return self.resetToDefault(set, index);
        }

        pub fn resetFieldToDefault(self: *Self, set: *const Set, comptime field_name: []const u8) bool {
            return self.resetToDefault(set, set.indexOfField(field_name));
        }

        pub fn applyChangesCount(self: *Self, set: *const Set, changes: process.ParameterChanges) usize {
            var applied: usize = 0;
            for (changes.items) |change| {
                if (!(set.canAutomateById(change.id) orelse false)) continue;
                if (set.isReadOnlyById(change.id) orelse true) continue;
                if (self.storeById(set, change.id, change.normalized)) applied += 1;
            }
            return applied;
        }

        pub fn applyChanges(self: *Self, set: *const Set, changes: process.ParameterChanges) void {
            _ = self.applyChangesCount(set, changes);
        }

        pub fn view(self: *const Self, set: *const Set) ParameterView(Params) {
            return ParameterView(Params).init(set, self);
        }

        pub fn editor(self: *Self, set: *const Set) ParameterEditor(Params) {
            return ParameterEditor(Params).init(set, self);
        }
    };
}

pub fn ParameterView(comptime Params: type) type {
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);

    return struct {
        const Self = @This();

        set: *const Set,
        values: *const Values,

        pub fn init(set: *const Set, values: *const Values) Self {
            return .{
                .set = set,
                .values = values,
            };
        }

        pub fn parameterCount(_: Self) usize {
            return Set.count;
        }

        pub fn parametersEmpty(_: Self) bool {
            return Set.count == 0;
        }

        pub fn hasParameters(_: Self) bool {
            return Set.count != 0;
        }

        pub fn id(self: Self, index: usize) ?u32 {
            return self.set.id(index);
        }

        pub fn name(self: Self, index: usize) ?[]const u8 {
            return self.set.name(index);
        }

        pub fn nameById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.nameById(wanted_id);
        }

        pub fn idByName(self: Self, wanted_name: []const u8) ?u32 {
            return self.set.idByName(wanted_name);
        }

        pub fn shortName(self: Self, index: usize) ?[]const u8 {
            return self.set.shortName(index);
        }

        pub fn shortNameById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.shortNameById(wanted_id);
        }

        pub fn shortNameByName(self: Self, wanted_name: []const u8) ?[]const u8 {
            return self.set.shortNameByName(wanted_name);
        }

        pub fn units(self: Self, index: usize) ?[]const u8 {
            return self.set.units(index);
        }

        pub fn unitsById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.unitsById(wanted_id);
        }

        pub fn unitsByName(self: Self, wanted_name: []const u8) ?[]const u8 {
            return self.set.unitsByName(wanted_name);
        }

        pub fn defaultNormalized(self: Self, index: usize) ?f64 {
            return self.set.defaultNormalized(index);
        }

        pub fn defaultNormalizedById(self: Self, wanted_id: u32) ?f64 {
            return self.set.defaultNormalizedById(wanted_id);
        }

        pub fn defaultNormalizedByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.defaultNormalizedByName(wanted_name);
        }

        pub fn isBypass(self: Self, index: usize) ?bool {
            return self.set.isBypass(index);
        }

        pub fn isBypassById(self: Self, wanted_id: u32) ?bool {
            return self.set.isBypassById(wanted_id);
        }

        pub fn isBypassByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isBypassByName(wanted_name);
        }

        pub fn canAutomate(self: Self, index: usize) ?bool {
            return self.set.canAutomate(index);
        }

        pub fn canAutomateById(self: Self, wanted_id: u32) ?bool {
            return self.set.canAutomateById(wanted_id);
        }

        pub fn canAutomateByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.canAutomateByName(wanted_name);
        }

        pub fn isReadOnly(self: Self, index: usize) ?bool {
            return self.set.isReadOnly(index);
        }

        pub fn isReadOnlyById(self: Self, wanted_id: u32) ?bool {
            return self.set.isReadOnlyById(wanted_id);
        }

        pub fn isReadOnlyByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isReadOnlyByName(wanted_name);
        }

        pub fn unitId(self: Self, index: usize) ?i32 {
            return self.set.unitId(index);
        }

        pub fn unitIdById(self: Self, wanted_id: u32) ?i32 {
            return self.set.unitIdById(wanted_id);
        }

        pub fn unitIdByName(self: Self, wanted_name: []const u8) ?i32 {
            return self.set.unitIdByName(wanted_name);
        }

        pub fn stepCount(self: Self, index: usize) ?i32 {
            return self.set.stepCount(index);
        }

        pub fn stepCountById(self: Self, wanted_id: u32) ?i32 {
            return self.set.stepCountById(wanted_id);
        }

        pub fn stepCountByName(self: Self, wanted_name: []const u8) ?i32 {
            return self.set.stepCountByName(wanted_name);
        }

        pub fn isList(self: Self, index: usize) ?bool {
            return self.set.isList(index);
        }

        pub fn isListById(self: Self, wanted_id: u32) ?bool {
            return self.set.isListById(wanted_id);
        }

        pub fn isListByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isListByName(wanted_name);
        }

        pub fn indexOfId(self: Self, wanted_id: u32) ?usize {
            return self.set.indexOfId(wanted_id);
        }

        pub fn indexOfName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.indexOfName(wanted_name);
        }

        pub fn hasId(self: Self, wanted_id: u32) bool {
            return self.set.hasId(wanted_id);
        }

        pub fn hasName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasName(wanted_name);
        }

        pub fn indexOfField(self: Self, comptime field_name: []const u8) usize {
            return self.set.indexOfField(field_name);
        }

        pub fn descriptor(self: Self, comptime field_name: []const u8) FieldDescriptor(Params, field_name) {
            return self.set.descriptor(field_name);
        }

        pub fn fieldId(self: Self, comptime field_name: []const u8) u32 {
            return self.set.fieldId(field_name);
        }

        pub fn fieldName(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldName(field_name);
        }

        pub fn fieldShortName(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldShortName(field_name);
        }

        pub fn fieldUnits(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldUnits(field_name);
        }

        pub fn fieldDefaultNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.set.fieldDefaultNormalized(field_name);
        }

        pub fn fieldIsBypass(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsBypass(field_name);
        }

        pub fn fieldCanAutomate(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldCanAutomate(field_name);
        }

        pub fn fieldIsReadOnly(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsReadOnly(field_name);
        }

        pub fn fieldUnitId(self: Self, comptime field_name: []const u8) i32 {
            return self.set.fieldUnitId(field_name);
        }

        pub fn fieldStepCount(self: Self, comptime field_name: []const u8) i32 {
            return self.set.fieldStepCount(field_name);
        }

        pub fn fieldIsList(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsList(field_name);
        }

        pub fn formatFieldPlain(self: Self, comptime field_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatFieldPlain(field_name, normalized, buffer);
        }

        pub fn parseFieldPlain(self: Self, comptime field_name: []const u8, text: []const u8) !f64 {
            return self.set.parseFieldPlain(field_name, text);
        }

        pub fn fieldPlainFromNormalized(self: Self, comptime field_name: []const u8, normalized: f64) FieldPlainType(Params, field_name) {
            return self.set.fieldPlainFromNormalized(field_name, normalized);
        }

        pub fn fieldNormalizedFromPlain(self: Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) f64 {
            return self.set.fieldNormalizedFromPlain(field_name, plain);
        }

        pub fn parameterChangeNormalized(
            self: Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            normalized: f64,
        ) process.ParameterChange {
            return self.set.parameterChangeNormalized(field_name, sample_offset, normalized);
        }

        pub fn parameterChange(
            self: Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            plain: FieldPlainType(Params, field_name),
        ) process.ParameterChange {
            return self.set.parameterChange(field_name, sample_offset, plain);
        }

        pub fn formatPlainIndex(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlain(index, normalized, buffer);
        }

        pub fn formatPlainById(self: Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainById(wanted_id, normalized, buffer);
        }

        pub fn formatPlainByName(self: Self, wanted_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainByName(wanted_name, normalized, buffer);
        }

        pub fn parsePlainIndex(self: Self, index: usize, text: []const u8) !f64 {
            return self.set.parsePlain(index, text);
        }

        pub fn parsePlainById(self: Self, wanted_id: u32, text: []const u8) !f64 {
            return self.set.parsePlainById(wanted_id, text);
        }

        pub fn parsePlainByName(self: Self, wanted_name: []const u8, text: []const u8) !f64 {
            return self.set.parsePlainByName(wanted_name, text);
        }

        pub fn plainFromNormalizedIndex(self: Self, index: usize, normalized: f64) ?f64 {
            return self.set.plainFromNormalized(index, normalized);
        }

        pub fn plainFromNormalizedById(self: Self, wanted_id: u32, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedById(wanted_id, normalized);
        }

        pub fn plainFromNormalizedByName(self: Self, wanted_name: []const u8, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedByName(wanted_name, normalized);
        }

        pub fn normalizedFromPlainIndex(self: Self, index: usize, plain: f64) ?f64 {
            return self.set.normalizedFromPlain(index, plain);
        }

        pub fn normalizedFromPlainById(self: Self, wanted_id: u32, plain: f64) ?f64 {
            return self.set.normalizedFromPlainById(wanted_id, plain);
        }

        pub fn normalizedFromPlainByName(self: Self, wanted_name: []const u8, plain: f64) ?f64 {
            return self.set.normalizedFromPlainByName(wanted_name, plain);
        }

        pub fn loadNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.values.loadFieldNormalized(self.set, field_name);
        }

        pub fn load(self: Self, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            return self.values.loadField(self.set, field_name);
        }

        pub fn loadIndex(self: Self, index: usize) ?f64 {
            return self.values.load(index);
        }

        pub fn loadPlainIndex(self: Self, index: usize) ?f64 {
            return self.values.loadPlain(self.set, index);
        }

        pub fn loadById(self: Self, wanted_id: u32) ?f64 {
            return self.values.loadById(self.set, wanted_id);
        }

        pub fn loadPlainById(self: Self, wanted_id: u32) ?f64 {
            return self.values.loadPlainById(self.set, wanted_id);
        }

        pub fn loadByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.values.loadByName(self.set, wanted_name);
        }

        pub fn loadPlainByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.values.loadPlainByName(self.set, wanted_name);
        }

        pub fn isDefaultIndex(self: Self, index: usize) ?bool {
            return self.values.isDefault(self.set, index);
        }

        pub fn isDefaultById(self: Self, wanted_id: u32) ?bool {
            return self.values.isDefaultById(self.set, wanted_id);
        }

        pub fn isDefaultByName(self: Self, wanted_name: []const u8) ?bool {
            return self.values.isDefaultByName(self.set, wanted_name);
        }

        pub fn isDefault(self: Self, comptime field_name: []const u8) bool {
            return self.values.fieldIsDefault(self.set, field_name);
        }
    };
}

pub fn ParameterEditor(comptime Params: type) type {
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);

    return struct {
        const Self = @This();

        set: *const Set,
        values: *Values,

        pub fn init(set: *const Set, values: *Values) Self {
            return .{
                .set = set,
                .values = values,
            };
        }

        pub fn view(self: Self) ParameterView(Params) {
            return self.values.view(self.set);
        }

        pub fn parameterCount(_: Self) usize {
            return Set.count;
        }

        pub fn parametersEmpty(_: Self) bool {
            return Set.count == 0;
        }

        pub fn hasParameters(_: Self) bool {
            return Set.count != 0;
        }

        pub fn id(self: Self, index: usize) ?u32 {
            return self.set.id(index);
        }

        pub fn name(self: Self, index: usize) ?[]const u8 {
            return self.set.name(index);
        }

        pub fn nameById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.nameById(wanted_id);
        }

        pub fn idByName(self: Self, wanted_name: []const u8) ?u32 {
            return self.set.idByName(wanted_name);
        }

        pub fn shortName(self: Self, index: usize) ?[]const u8 {
            return self.set.shortName(index);
        }

        pub fn shortNameById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.shortNameById(wanted_id);
        }

        pub fn shortNameByName(self: Self, wanted_name: []const u8) ?[]const u8 {
            return self.set.shortNameByName(wanted_name);
        }

        pub fn units(self: Self, index: usize) ?[]const u8 {
            return self.set.units(index);
        }

        pub fn unitsById(self: Self, wanted_id: u32) ?[]const u8 {
            return self.set.unitsById(wanted_id);
        }

        pub fn unitsByName(self: Self, wanted_name: []const u8) ?[]const u8 {
            return self.set.unitsByName(wanted_name);
        }

        pub fn defaultNormalized(self: Self, index: usize) ?f64 {
            return self.set.defaultNormalized(index);
        }

        pub fn defaultNormalizedById(self: Self, wanted_id: u32) ?f64 {
            return self.set.defaultNormalizedById(wanted_id);
        }

        pub fn defaultNormalizedByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.defaultNormalizedByName(wanted_name);
        }

        pub fn isBypass(self: Self, index: usize) ?bool {
            return self.set.isBypass(index);
        }

        pub fn isBypassById(self: Self, wanted_id: u32) ?bool {
            return self.set.isBypassById(wanted_id);
        }

        pub fn isBypassByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isBypassByName(wanted_name);
        }

        pub fn canAutomate(self: Self, index: usize) ?bool {
            return self.set.canAutomate(index);
        }

        pub fn canAutomateById(self: Self, wanted_id: u32) ?bool {
            return self.set.canAutomateById(wanted_id);
        }

        pub fn canAutomateByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.canAutomateByName(wanted_name);
        }

        pub fn isReadOnly(self: Self, index: usize) ?bool {
            return self.set.isReadOnly(index);
        }

        pub fn isReadOnlyById(self: Self, wanted_id: u32) ?bool {
            return self.set.isReadOnlyById(wanted_id);
        }

        pub fn isReadOnlyByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isReadOnlyByName(wanted_name);
        }

        pub fn unitId(self: Self, index: usize) ?i32 {
            return self.set.unitId(index);
        }

        pub fn unitIdById(self: Self, wanted_id: u32) ?i32 {
            return self.set.unitIdById(wanted_id);
        }

        pub fn unitIdByName(self: Self, wanted_name: []const u8) ?i32 {
            return self.set.unitIdByName(wanted_name);
        }

        pub fn stepCount(self: Self, index: usize) ?i32 {
            return self.set.stepCount(index);
        }

        pub fn stepCountById(self: Self, wanted_id: u32) ?i32 {
            return self.set.stepCountById(wanted_id);
        }

        pub fn stepCountByName(self: Self, wanted_name: []const u8) ?i32 {
            return self.set.stepCountByName(wanted_name);
        }

        pub fn isList(self: Self, index: usize) ?bool {
            return self.set.isList(index);
        }

        pub fn isListById(self: Self, wanted_id: u32) ?bool {
            return self.set.isListById(wanted_id);
        }

        pub fn isListByName(self: Self, wanted_name: []const u8) ?bool {
            return self.set.isListByName(wanted_name);
        }

        pub fn indexOfId(self: Self, wanted_id: u32) ?usize {
            return self.set.indexOfId(wanted_id);
        }

        pub fn indexOfName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.indexOfName(wanted_name);
        }

        pub fn hasId(self: Self, wanted_id: u32) bool {
            return self.set.hasId(wanted_id);
        }

        pub fn hasName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasName(wanted_name);
        }

        pub fn indexOfField(self: Self, comptime field_name: []const u8) usize {
            return self.set.indexOfField(field_name);
        }

        pub fn descriptor(self: Self, comptime field_name: []const u8) FieldDescriptor(Params, field_name) {
            return self.set.descriptor(field_name);
        }

        pub fn fieldId(self: Self, comptime field_name: []const u8) u32 {
            return self.set.fieldId(field_name);
        }

        pub fn fieldName(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldName(field_name);
        }

        pub fn fieldShortName(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldShortName(field_name);
        }

        pub fn fieldUnits(self: Self, comptime field_name: []const u8) []const u8 {
            return self.set.fieldUnits(field_name);
        }

        pub fn fieldDefaultNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.set.fieldDefaultNormalized(field_name);
        }

        pub fn fieldIsBypass(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsBypass(field_name);
        }

        pub fn fieldCanAutomate(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldCanAutomate(field_name);
        }

        pub fn fieldIsReadOnly(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsReadOnly(field_name);
        }

        pub fn fieldUnitId(self: Self, comptime field_name: []const u8) i32 {
            return self.set.fieldUnitId(field_name);
        }

        pub fn fieldStepCount(self: Self, comptime field_name: []const u8) i32 {
            return self.set.fieldStepCount(field_name);
        }

        pub fn fieldIsList(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldIsList(field_name);
        }

        pub fn formatFieldPlain(self: Self, comptime field_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatFieldPlain(field_name, normalized, buffer);
        }

        pub fn parseFieldPlain(self: Self, comptime field_name: []const u8, text: []const u8) !f64 {
            return self.set.parseFieldPlain(field_name, text);
        }

        pub fn fieldPlainFromNormalized(self: Self, comptime field_name: []const u8, normalized: f64) FieldPlainType(Params, field_name) {
            return self.set.fieldPlainFromNormalized(field_name, normalized);
        }

        pub fn fieldNormalizedFromPlain(self: Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) f64 {
            return self.set.fieldNormalizedFromPlain(field_name, plain);
        }

        pub fn parameterChangeNormalized(
            self: Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            normalized: f64,
        ) process.ParameterChange {
            return self.set.parameterChangeNormalized(field_name, sample_offset, normalized);
        }

        pub fn parameterChange(
            self: Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            plain: FieldPlainType(Params, field_name),
        ) process.ParameterChange {
            return self.set.parameterChange(field_name, sample_offset, plain);
        }

        pub fn formatPlainIndex(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlain(index, normalized, buffer);
        }

        pub fn formatPlainById(self: Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainById(wanted_id, normalized, buffer);
        }

        pub fn formatPlainByName(self: Self, wanted_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainByName(wanted_name, normalized, buffer);
        }

        pub fn parsePlainIndex(self: Self, index: usize, text: []const u8) !f64 {
            return self.set.parsePlain(index, text);
        }

        pub fn parsePlainById(self: Self, wanted_id: u32, text: []const u8) !f64 {
            return self.set.parsePlainById(wanted_id, text);
        }

        pub fn parsePlainByName(self: Self, wanted_name: []const u8, text: []const u8) !f64 {
            return self.set.parsePlainByName(wanted_name, text);
        }

        pub fn plainFromNormalizedIndex(self: Self, index: usize, normalized: f64) ?f64 {
            return self.set.plainFromNormalized(index, normalized);
        }

        pub fn plainFromNormalizedById(self: Self, wanted_id: u32, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedById(wanted_id, normalized);
        }

        pub fn plainFromNormalizedByName(self: Self, wanted_name: []const u8, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedByName(wanted_name, normalized);
        }

        pub fn normalizedFromPlainIndex(self: Self, index: usize, plain: f64) ?f64 {
            return self.set.normalizedFromPlain(index, plain);
        }

        pub fn normalizedFromPlainById(self: Self, wanted_id: u32, plain: f64) ?f64 {
            return self.set.normalizedFromPlainById(wanted_id, plain);
        }

        pub fn normalizedFromPlainByName(self: Self, wanted_name: []const u8, plain: f64) ?f64 {
            return self.set.normalizedFromPlainByName(wanted_name, plain);
        }

        pub fn resetToDefaults(self: Self) void {
            self.values.resetToDefaults(self.set);
        }

        pub fn resetToDefaultIndex(self: Self, index: usize) bool {
            return self.values.resetToDefault(self.set, index);
        }

        pub fn resetToDefaultById(self: Self, wanted_id: u32) bool {
            return self.values.resetToDefaultById(self.set, wanted_id);
        }

        pub fn resetToDefaultByName(self: Self, wanted_name: []const u8) bool {
            return self.values.resetToDefaultByName(self.set, wanted_name);
        }

        pub fn resetToDefault(self: Self, comptime field_name: []const u8) bool {
            return self.values.resetFieldToDefault(self.set, field_name);
        }

        pub fn applyChangesCount(self: Self, changes: process.ParameterChanges) usize {
            return self.values.applyChangesCount(self.set, changes);
        }

        pub fn applyChanges(self: Self, changes: process.ParameterChanges) void {
            self.values.applyChanges(self.set, changes);
        }

        pub fn loadNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.values.loadFieldNormalized(self.set, field_name);
        }

        pub fn load(self: Self, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            return self.values.loadField(self.set, field_name);
        }

        pub fn loadIndex(self: Self, index: usize) ?f64 {
            return self.values.load(index);
        }

        pub fn loadPlainIndex(self: Self, index: usize) ?f64 {
            return self.values.loadPlain(self.set, index);
        }

        pub fn loadById(self: Self, wanted_id: u32) ?f64 {
            return self.values.loadById(self.set, wanted_id);
        }

        pub fn loadPlainById(self: Self, wanted_id: u32) ?f64 {
            return self.values.loadPlainById(self.set, wanted_id);
        }

        pub fn loadByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.values.loadByName(self.set, wanted_name);
        }

        pub fn loadPlainByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.values.loadPlainByName(self.set, wanted_name);
        }

        pub fn isDefaultIndex(self: Self, index: usize) ?bool {
            return self.values.isDefault(self.set, index);
        }

        pub fn isDefaultById(self: Self, wanted_id: u32) ?bool {
            return self.values.isDefaultById(self.set, wanted_id);
        }

        pub fn isDefaultByName(self: Self, wanted_name: []const u8) ?bool {
            return self.values.isDefaultByName(self.set, wanted_name);
        }

        pub fn isDefault(self: Self, comptime field_name: []const u8) bool {
            return self.values.fieldIsDefault(self.set, field_name);
        }

        pub fn storeNormalized(self: Self, comptime field_name: []const u8, normalized: f64) bool {
            return self.values.storeFieldNormalized(self.set, field_name, normalized);
        }

        pub fn store(self: Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) bool {
            return self.values.storeField(self.set, field_name, plain);
        }

        pub fn storeIndex(self: Self, index: usize, normalized: f64) bool {
            return self.values.store(index, normalized);
        }

        pub fn storePlainIndex(self: Self, index: usize, plain: f64) bool {
            return self.values.storePlain(self.set, index, plain);
        }

        pub fn storeById(self: Self, wanted_id: u32, normalized: f64) bool {
            return self.values.storeById(self.set, wanted_id, normalized);
        }

        pub fn storePlainById(self: Self, wanted_id: u32, plain: f64) bool {
            return self.values.storePlainById(self.set, wanted_id, plain);
        }

        pub fn storeByName(self: Self, wanted_name: []const u8, normalized: f64) bool {
            return self.values.storeByName(self.set, wanted_name, normalized);
        }

        pub fn storePlainByName(self: Self, wanted_name: []const u8, plain: f64) bool {
            return self.values.storePlainByName(self.set, wanted_name, plain);
        }
    };
}

pub fn FieldDescriptor(comptime Params: type, comptime field_name: []const u8) type {
    inline for (@typeInfo(Params).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, field_name)) return field.type;
    }
    @compileError("unknown parameter field: " ++ field_name);
}

pub fn FieldPlainType(comptime Params: type, comptime field_name: []const u8) type {
    const Descriptor = FieldDescriptor(Params, field_name);
    return @TypeOf(@as(Descriptor, undefined).denormalize(0.0));
}

test "float parameter clamps defaults and values" {
    const param = FloatParam.init(7, "Gain", -12.0, 6.0, 12.0);
    const nan_default = FloatParam.init(8, "Safe", -12.0, 6.0, std.math.nan(f64));

    try std.testing.expectEqual(@as(u32, 7), param.id);
    try std.testing.expectEqualStrings("Gain", param.name);
    try std.testing.expectEqual(@as(f64, 6.0), param.default);
    try std.testing.expectEqual(@as(f64, -12.0), nan_default.default);
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(-24.0));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalize(12.0));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalize(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, -12.0), param.denormalize(-1.0));
    try std.testing.expectEqual(@as(f64, 6.0), param.denormalize(2.0));
    try std.testing.expectEqual(@as(f64, -12.0), param.denormalize(std.math.nan(f64)));
}

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

test "linear smoother reaches target after requested samples" {
    var smoother = LinearSmoother.init(0.0);

    smoother.setTarget(1.0, 4);
    try std.testing.expect(smoother.active());
    try std.testing.expectEqual(@as(usize, 4), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(0.0, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expectEqual(@as(usize, 0), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "linear smoother handles immediate and clamped targets" {
    var smoother = LinearSmoother.init(0.25);

    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(-1.0, 2);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
    smoother.reset(0.75);
    try std.testing.expectApproxEqAbs(0.75, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, smoother.targetValue(), 0.000001);
    try std.testing.expect(!smoother.active());
}

test "exponential smoother approaches target by coefficient" {
    var smoother = ExponentialSmoother.init(0.0, 0.25);

    smoother.setTarget(1.0);
    try std.testing.expectApproxEqAbs(0.0, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.25, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.4375, smoother.next(), 0.000001);
    smoother.setCoefficient(0.5);
    try std.testing.expectApproxEqAbs(0.578125, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.coefficient, 0.000001);
}

test "exponential smoother clamps initial value target and coefficient" {
    var smoother = ExponentialSmoother.init(2.0, 2.0);

    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.coefficient, 0.000001);
    smoother.setTarget(-1.0);
    try std.testing.expectApproxEqAbs(0.0, smoother.next(), 0.000001);
    smoother.reset(0.5);
    try std.testing.expectApproxEqAbs(0.5, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.targetValue(), 0.000001);
    smoother.setCoefficient(std.math.nan(f64));
    try std.testing.expectApproxEqAbs(0.0, smoother.coefficient, 0.000001);
}

test "log smoother reaches multiplicative target after requested samples" {
    var smoother = LogSmoother.init(0.25);

    smoother.setTarget(1.0, 2);
    try std.testing.expect(smoother.active());
    try std.testing.expectEqual(@as(usize, 2), smoother.remainingSamples());
    try std.testing.expectApproxEqAbs(0.25, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.targetValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expect(!smoother.active());
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "log smoother clamps zero and handles immediate target" {
    var smoother = LogSmoother.init(0.0);

    try std.testing.expect(smoother.current > 0.0);
    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(std.math.nan(f64), 0);
    try std.testing.expectApproxEqAbs(std.math.floatEps(f64), smoother.current, 0.0);
    smoother.reset(0.5);
    try std.testing.expectApproxEqAbs(0.5, smoother.currentValue(), 0.000001);
    try std.testing.expectApproxEqAbs(0.5, smoother.targetValue(), 0.000001);
    try std.testing.expect(!smoother.active());
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
    try std.testing.expectEqual(@as(i64, 1), param.denormalize(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalizedFromPlain(std.math.nan(f64)));
    try std.testing.expectEqual(@as(f64, 0.0), param.normalizedFromPlain(-1.0e30));
    try std.testing.expectEqual(@as(f64, 1.0), param.normalizedFromPlain(1.0e30));
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
}

test "single-value enum parameter stays at zero" {
    const Only = enum { value };
    const OnlyParam = EnumParam(Only);
    const only = OnlyParam{ .id = 5, .name = "Only", .default = .value };

    try std.testing.expectEqual(@as(f64, 0.0), only.defaultNormalized());
    try std.testing.expectEqual(@as(f64, 0.0), only.normalize(.value));
    try std.testing.expectEqual(Only.value, only.denormalize(1.0));
}

test "parameter set reflects descriptor fields" {
    const Mode = enum { clean, lead };
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .short_name = "Gain", .units = "dB", .min = 0.0, .max = 1.0, .default = 0.75 },
        voices: IntParam = .{ .id = 1, .name = "Voices", .short_name = "Vox", .min = 1, .max = 16, .default = 4, .can_automate = false, .is_read_only = true, .unit_id = 2 },
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .lead },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(usize, 4), Set.count);
    try std.testing.expectEqual(@as(usize, 4), set.parameterCount());
    try std.testing.expect(!set.parametersEmpty());
    try std.testing.expect(set.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), set.id(0));
    try std.testing.expectEqualStrings("Voices", set.name(1).?);
    try std.testing.expectEqualStrings("Bypass", set.nameById(2).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.nameById(99));
    try std.testing.expectEqual(@as(?u32, 1), set.idByName("Voices"));
    try std.testing.expectEqual(@as(?u32, null), set.idByName("Missing"));
    try std.testing.expectEqualStrings("Vox", set.shortName(1).?);
    try std.testing.expectEqualStrings("Mode", set.shortNameById(3).?);
    try std.testing.expectEqualStrings("Vox", set.shortNameByName("Voices").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.shortNameById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), set.shortNameByName("Missing"));
    try std.testing.expectEqualStrings("dB", set.units(0).?);
    try std.testing.expectEqualStrings("", set.unitsById(1).?);
    try std.testing.expectEqualStrings("dB", set.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.unitsById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), set.unitsByName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), set.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), set.indexOfName("Voices"));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfName("Missing"));
    try std.testing.expect(set.hasId(2));
    try std.testing.expect(!set.hasId(99));
    try std.testing.expect(set.hasName("Voices"));
    try std.testing.expect(!set.hasName("Missing"));
    try std.testing.expectEqual(@as(usize, 0), set.indexOfField("gain"));
    try std.testing.expectEqual(@as(u32, 3), set.descriptor("mode").id);
    try std.testing.expectEqual(@as(u32, 0), set.fieldId("gain"));
    try std.testing.expectEqualStrings("Mode", set.fieldName("mode"));
    try std.testing.expectApproxEqAbs(1.0, set.fieldDefaultNormalized("mode"), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, set.defaultNormalized(0).?, 0.000001);
    try std.testing.expectApproxEqAbs(0.2, set.defaultNormalized(1).?, 0.000001);
    try std.testing.expectApproxEqAbs(0.0, set.defaultNormalized(2).?, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, set.defaultNormalized(3).?, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, set.defaultNormalizedById(3).?, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, set.defaultNormalizedByName("Mode").?, 0.000001);
    try std.testing.expectEqual(@as(?f64, null), set.defaultNormalizedById(99));
    try std.testing.expectEqual(@as(?f64, null), set.defaultNormalizedByName("Missing"));
    try std.testing.expectEqual(@as(?bool, true), set.canAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), set.canAutomateById(1));
    try std.testing.expectEqual(@as(?bool, false), set.canAutomateByName("Voices"));
    try std.testing.expectEqual(@as(?bool, true), set.isReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), set.isReadOnlyById(0));
    try std.testing.expectEqual(@as(?bool, true), set.isReadOnlyByName("Voices"));
    try std.testing.expectEqual(@as(?bool, null), set.canAutomateById(99));
    try std.testing.expectEqual(@as(?bool, null), set.canAutomateByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), set.isReadOnlyById(99));
    try std.testing.expectEqual(@as(?bool, null), set.isReadOnlyByName("Missing"));
    try std.testing.expectEqual(@as(?bool, false), set.isBypass(0));
    try std.testing.expectEqual(@as(?bool, null), set.isBypass(99));
    try std.testing.expectEqual(@as(?bool, false), set.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, false), set.isBypassByName("Gain"));
    try std.testing.expectEqual(@as(?bool, null), set.isBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), set.isBypassByName("Missing"));
    try std.testing.expectEqual(@as(?i32, 0), set.unitId(0));
    try std.testing.expectEqual(@as(?i32, 2), set.unitId(1));
    try std.testing.expectEqual(@as(?i32, 2), set.unitIdById(1));
    try std.testing.expectEqual(@as(?i32, 2), set.unitIdByName("Voices"));
    try std.testing.expectEqual(@as(?i32, null), set.unitIdById(99));
    try std.testing.expectEqual(@as(?i32, null), set.unitIdByName("Missing"));
    try std.testing.expectEqual(@as(?i32, 0), set.stepCount(0));
    try std.testing.expectEqual(@as(?i32, 15), set.stepCount(1));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCount(2));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCount(3));
    try std.testing.expectEqual(@as(?i32, null), set.stepCount(99));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCountById(3));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCountByName("Mode"));
    try std.testing.expectEqual(@as(?i32, null), set.stepCountById(99));
    try std.testing.expectEqual(@as(?i32, null), set.stepCountByName("Missing"));
    try std.testing.expectEqual(@as(?bool, false), set.isList(1));
    try std.testing.expectEqual(@as(?bool, true), set.isList(3));
    try std.testing.expectEqual(@as(?bool, null), set.isList(99));
    try std.testing.expectEqual(@as(?bool, true), set.isListById(3));
    try std.testing.expectEqual(@as(?bool, true), set.isListByName("Mode"));
    try std.testing.expectEqual(@as(?bool, null), set.isListById(99));
    try std.testing.expectEqual(@as(?bool, null), set.isListByName("Missing"));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 2,
        .normalized = 0.25,
    }, set.parameterChangeNormalized("gain", 2, 0.25));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 1,
        .sample_offset = 3,
        .normalized = 1.0,
    }, set.parameterChange("voices", 3, 16));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 2,
        .sample_offset = 4,
        .normalized = 1.0,
    }, set.parameterChange("bypass", 4, true));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 3,
        .sample_offset = 5,
        .normalized = 1.0,
    }, set.parameterChange("mode", 5, .lead));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("lead", try set.formatFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try set.parseFieldPlain("mode", "lead"));
    try std.testing.expectEqual(Mode.lead, set.fieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), set.fieldNormalizedFromPlain("mode", .lead));
}

test "parameter set reports duplicate ids" {
    const Params = struct {
        gain: FloatParam = .{ .id = 7, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        mix: FloatParam = .{ .id = 7, .name = "Mix", .min = 0.0, .max = 1.0, .default = 0.25 },
        output: FloatParam = .{ .id = 8, .name = "Output", .min = 0.0, .max = 1.0, .default = 1.0 },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?u32, 7), set.duplicateId());
    try std.testing.expect(set.hasDuplicateIds());
    try std.testing.expectError(error.DuplicateParameterId, set.validateUniqueIds());
}

test "parameter set accepts unique ids" {
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        mix: FloatParam = .{ .id = 1, .name = "Mix", .min = 0.0, .max = 1.0, .default = 0.25 },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?u32, null), set.duplicateId());
    try std.testing.expect(!set.hasDuplicateIds());
    try set.validateUniqueIds();
}

test "parameter set reports duplicate names" {
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.5 },
        output: FloatParam = .{ .id = 1, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.25 },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqualStrings("Level", set.duplicateName().?);
    try std.testing.expect(set.hasDuplicateNames());
    try std.testing.expectError(error.DuplicateParameterName, set.validateUniqueNames());
    try std.testing.expectError(error.DuplicateParameterName, set.validate());
}

test "parameter set validates descriptor names and ranges" {
    const EmptyNameParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "", .min = 0.0, .max = 1.0, .default = 0.5 },
    };
    const InvalidNameParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Ga\x00in", .min = 0.0, .max = 1.0, .default = 0.5 },
    };
    const InvalidShortNameParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .short_name = "G\x00n", .min = 0.0, .max = 1.0, .default = 0.5 },
    };
    const InvalidUnitsParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .units = "d\x00B", .min = 0.0, .max = 1.0, .default = 0.5 },
    };
    const InvalidFloatParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 1.0, .max = 1.0, .default = 1.0 },
    };
    const InvalidFloatDefaultParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = std.math.inf(f64) },
    };
    const OutOfRangeFloatDefaultParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 2.0 },
    };
    const InvalidIntParams = struct {
        voices: IntParam = .{ .id = 0, .name = "Voices", .min = 4, .max = 4, .default = 4 },
    };
    const InvalidIntDefaultParams = struct {
        voices: IntParam = .{ .id = 0, .name = "Voices", .min = 1, .max = 4, .default = 8 },
    };

    const empty_name_set = ParameterSet(EmptyNameParams).init(.{});
    const invalid_name_set = ParameterSet(InvalidNameParams).init(.{});
    const invalid_short_name_set = ParameterSet(InvalidShortNameParams).init(.{});
    const invalid_units_set = ParameterSet(InvalidUnitsParams).init(.{});
    const invalid_float_set = ParameterSet(InvalidFloatParams).init(.{});
    const invalid_float_default_set = ParameterSet(InvalidFloatDefaultParams).init(.{});
    const out_of_range_float_default_set = ParameterSet(OutOfRangeFloatDefaultParams).init(.{});
    const invalid_int_set = ParameterSet(InvalidIntParams).init(.{});
    const invalid_int_default_set = ParameterSet(InvalidIntDefaultParams).init(.{});

    try std.testing.expectEqual(error.EmptyParameterName, empty_name_set.firstDescriptorError().?);
    try std.testing.expectError(error.EmptyParameterName, empty_name_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterMetadata, invalid_name_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterMetadata, invalid_short_name_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterMetadata, invalid_units_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterRange, invalid_float_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterDefault, invalid_float_default_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterDefault, out_of_range_float_default_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterRange, invalid_int_set.validateDescriptors());
    try std.testing.expectError(error.InvalidParameterDefault, invalid_int_default_set.validateDescriptors());
}

test "parameter set validates complete metadata" {
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        bypass: BoolParam = .{ .id = 1, .name = "Bypass" },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try set.validate();
}

test "parameter set validates unit ids against reflected units" {
    const unit_api = @import("units.zig");
    const Units = unit_api.UnitSet(.{
        .units = &.{
            unit_api.Unit.root("Root"),
            .{ .id = 2, .name = "Voice", .parent_id = unit_api.root_unit_id },
        },
    });
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5, .unit_id = 2 },
    };
    const InvalidParams = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5, .unit_id = 99 },
    };

    const units = Units{};
    const set = ParameterSet(Params).init(.{});
    const invalid_set = ParameterSet(InvalidParams).init(.{});

    try set.validateUnitIds(units);
    try std.testing.expectError(error.InvalidParameterUnit, invalid_set.validateUnitIds(units));
}

test "integer parameter step count saturates to VST limit" {
    const Params = struct {
        huge: IntParam = IntParam.init(0, "Huge", 0, @as(i64, std.math.maxInt(i32)) + 1, 0),
        full_width: IntParam = IntParam.init(1, "Full Width", std.math.minInt(i64), std.math.maxInt(i64), 0),
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), set.stepCount(0));
    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), set.stepCount(1));
}

test "parameter values initialize from reflected defaults" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 1.0, 0.25),
        bypass: BoolParam = .{ .id = 1, .name = "Bypass", .default = true },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expectEqual(@as(?f64, null), values.load(2));
    try std.testing.expect(values.store(0, 2.0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(0));
    try std.testing.expect(!values.store(0, std.math.nan(f64)));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(0));
    try std.testing.expect(!values.storeById(&set, 0, std.math.inf(f64)));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 0));
    try std.testing.expect(!values.store(2, 0.5));
    try std.testing.expect(values.storeById(&set, 0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expect(!values.storeById(&set, 99, 0.5));
    try std.testing.expectEqual(@as(?f64, null), values.loadById(&set, 99));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadPlain(&set, 0));
    try std.testing.expect(values.storePlain(&set, 0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadPlain(&set, 0));
    try std.testing.expectEqual(@as(?f64, null), values.loadPlain(&set, 99));
    try std.testing.expect(!values.storePlain(&set, 99, 0.5));

    var copied = Values.init(&set);
    copied.copyFrom(&values);
    try std.testing.expectEqual(@as(?f64, 0.75), copied.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), copied.load(1));

    values.resetToDefaults(&set);
    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expect(values.store(0, 1.0));
    try std.testing.expect(values.store(1, 0.0));
    try std.testing.expect(values.resetToDefault(&set, 0));
    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(?f64, 0.0), values.load(1));
    try std.testing.expect(values.resetToDefaultById(&set, 1));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expect(!values.resetToDefault(&set, 99));
    try std.testing.expect(!values.resetToDefaultById(&set, 99));
}

test "parameter values expose plain value access by id" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    try std.testing.expectEqual(@as(?f64, 0.0), values.loadPlainById(&set, 0));
    try std.testing.expect(values.storePlainById(&set, 0, 6.0));
    try std.testing.expectEqual(@as(?f64, 6.0), values.loadPlainById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 0));

    try std.testing.expect(values.storePlainById(&set, 1, 8.8));
    try std.testing.expectEqual(@as(?f64, 9.0), values.loadPlainById(&set, 1));

    try std.testing.expect(values.storePlainById(&set, 2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadPlainById(&set, 2));
    try std.testing.expect(!values.storePlainById(&set, 99, 1.0));
    try std.testing.expectEqual(@as(?f64, null), values.loadPlainById(&set, 99));
}

test "parameter values expose plain value access by name" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    try std.testing.expectEqual(@as(?f64, 0.0), values.loadPlainByName(&set, "Gain"));
    try std.testing.expect(values.storePlainByName(&set, "Gain", 6.0));
    try std.testing.expectEqual(@as(?f64, 6.0), values.loadPlainByName(&set, "Gain"));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadByName(&set, "Gain"));

    try std.testing.expect(values.storePlainByName(&set, "Voices", 8.8));
    try std.testing.expectEqual(@as(?f64, 9.0), values.loadPlainByName(&set, "Voices"));

    try std.testing.expect(values.storePlainByName(&set, "Bypass", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadPlainByName(&set, "Bypass"));
    try std.testing.expect(!values.storePlainByName(&set, "Missing", 1.0));
    try std.testing.expectEqual(@as(?f64, null), values.loadPlainByName(&set, "Missing"));
}

test "parameter values expose typed field access" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = .{ .id = 1, .name = "Voices", .min = 1, .max = 4, .default = 1, .unit_id = 2 },
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    try std.testing.expectEqual(@as(f64, 0.0), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(i64, 1), values.loadField(&set, "voices"));
    try std.testing.expectEqual(false, values.loadField(&set, "bypass"));
    try std.testing.expectEqual(Mode.clean, values.loadField(&set, "mode"));
    try std.testing.expectEqual(@as(?bool, true), values.isDefault(&set, 0));
    try std.testing.expectEqual(@as(?bool, true), values.isDefaultById(&set, 3));
    try std.testing.expectEqual(@as(?bool, true), values.isDefaultByName(&set, "Mode"));
    try std.testing.expect(values.fieldIsDefault(&set, "mode"));

    try std.testing.expect(values.storeField(&set, "gain", 6.0));
    try std.testing.expect(values.storeField(&set, "voices", 4));
    try std.testing.expect(values.storeField(&set, "bypass", true));
    try std.testing.expect(values.storeField(&set, "mode", .mute));

    try std.testing.expectEqual(@as(f64, 6.0), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(i64, 4), values.loadField(&set, "voices"));
    try std.testing.expectEqual(true, values.loadField(&set, "bypass"));
    try std.testing.expectEqual(Mode.mute, values.loadField(&set, "mode"));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadFieldNormalized(&set, "mode"));
    try std.testing.expectEqual(@as(?bool, false), values.isDefault(&set, 0));
    try std.testing.expectEqual(@as(?bool, false), values.isDefaultById(&set, 3));
    try std.testing.expectEqual(@as(?bool, false), values.isDefaultByName(&set, "Mode"));
    try std.testing.expect(!values.fieldIsDefault(&set, "mode"));
    try std.testing.expect(values.storeFieldNormalized(&set, "mode", 0.0));
    try std.testing.expectEqual(Mode.clean, values.loadField(&set, "mode"));
    try std.testing.expect(values.fieldIsDefault(&set, "mode"));
    try std.testing.expectEqual(@as(?bool, null), values.isDefault(&set, 99));
    try std.testing.expectEqual(@as(?bool, null), values.isDefaultById(&set, 99));
    try std.testing.expectEqual(@as(?bool, null), values.isDefaultByName(&set, "Missing"));
}

test "parameter view binds reflected set and values" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
        voices: IntParam = .{ .id = 1, .name = "Voices", .short_name = "Vox", .min = 1, .max = 4, .default = 1, .can_automate = false, .is_read_only = true },
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    try std.testing.expect(values.storeField(&set, "gain", 6.0));
    try std.testing.expect(values.storeField(&set, "voices", 4));
    try std.testing.expect(values.storeField(&set, "bypass", true));
    try std.testing.expect(values.storeField(&set, "mode", .mute));

    const view = values.view(&set);
    try std.testing.expectEqual(@as(usize, 4), view.parameterCount());
    try std.testing.expect(!view.parametersEmpty());
    try std.testing.expect(view.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), view.id(0));
    try std.testing.expectEqualStrings("Voices", view.name(1).?);
    try std.testing.expectEqualStrings("Bypass", view.nameById(2).?);
    try std.testing.expectEqual(@as(?u32, 1), view.idByName("Voices"));
    try std.testing.expectEqualStrings("Vox", view.shortName(1).?);
    try std.testing.expectEqualStrings("Mode", view.shortNameById(3).?);
    try std.testing.expectEqualStrings("Vox", view.shortNameByName("Voices").?);
    try std.testing.expectEqualStrings("dB", view.units(0).?);
    try std.testing.expectEqualStrings("", view.unitsById(1).?);
    try std.testing.expectEqualStrings("dB", view.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultNormalized(3));
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultNormalizedById(3));
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?bool, false), view.isBypass(0));
    try std.testing.expectEqual(@as(?bool, false), view.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, false), view.isBypassByName("Gain"));
    try std.testing.expectEqual(@as(?bool, true), view.canAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), view.canAutomateById(1));
    try std.testing.expectEqual(@as(?bool, false), view.canAutomateByName("Voices"));
    try std.testing.expectEqual(@as(?bool, true), view.isReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), view.isReadOnlyById(0));
    try std.testing.expectEqual(@as(?bool, true), view.isReadOnlyByName("Voices"));
    try std.testing.expectEqual(@as(?i32, 2), view.unitId(1));
    try std.testing.expectEqual(@as(?i32, 2), view.unitIdById(1));
    try std.testing.expectEqual(@as(?i32, 2), view.unitIdByName("Voices"));
    try std.testing.expectEqual(@as(?i32, 3), view.stepCount(1));
    try std.testing.expectEqual(@as(?i32, 2), view.stepCountById(3));
    try std.testing.expectEqual(@as(?i32, 2), view.stepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), view.isList(3));
    try std.testing.expectEqual(@as(?bool, true), view.isListById(3));
    try std.testing.expectEqual(@as(?bool, true), view.isListByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 2), view.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, 1), view.indexOfName("Voices"));
    try std.testing.expect(view.hasId(2));
    try std.testing.expect(view.hasName("Voices"));
    try std.testing.expectEqual(@as(?u32, null), view.id(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.name(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.nameById(99));
    try std.testing.expectEqual(@as(?u32, null), view.idByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), view.shortNameById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.shortNameByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), view.unitsById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.unitsByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), view.defaultNormalizedById(99));
    try std.testing.expectEqual(@as(?f64, null), view.defaultNormalizedByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), view.isBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), view.isBypassByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), view.canAutomateById(99));
    try std.testing.expectEqual(@as(?bool, null), view.canAutomateByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), view.isReadOnlyById(99));
    try std.testing.expectEqual(@as(?bool, null), view.isReadOnlyByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), view.unitIdById(99));
    try std.testing.expectEqual(@as(?i32, null), view.unitIdByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), view.stepCountById(99));
    try std.testing.expectEqual(@as(?i32, null), view.stepCountByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), view.isListById(99));
    try std.testing.expectEqual(@as(?bool, null), view.isListByName("Missing"));
    try std.testing.expectEqual(@as(?usize, null), view.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, null), view.indexOfName("Missing"));
    try std.testing.expect(!view.hasId(99));
    try std.testing.expect(!view.hasName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), view.indexOfField("mode"));
    try std.testing.expectEqual(@as(u32, 0), view.descriptor("gain").id);
    try std.testing.expectEqual(@as(u32, 3), view.fieldId("mode"));
    try std.testing.expectEqualStrings("Bypass", view.fieldName("bypass"));
    try std.testing.expectEqualStrings("Vox", view.fieldShortName("voices"));
    try std.testing.expectEqualStrings("dB", view.fieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), view.fieldDefaultNormalized("mode"));
    try std.testing.expect(!view.fieldIsBypass("gain"));
    try std.testing.expect(view.fieldCanAutomate("gain"));
    try std.testing.expect(!view.fieldCanAutomate("voices"));
    try std.testing.expect(view.fieldIsReadOnly("voices"));
    try std.testing.expectEqual(@as(i32, 0), view.fieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), view.fieldStepCount("mode"));
    try std.testing.expect(view.fieldIsList("mode"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("mute", try view.formatFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parseFieldPlain("mode", "mute"));
    try std.testing.expectEqual(Mode.mute, view.fieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), view.fieldNormalizedFromPlain("mode", .mute));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 3,
        .sample_offset = 4,
        .normalized = 1.0,
    }, view.parameterChange("mode", 4, .mute));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 5,
        .normalized = 0.25,
    }, view.parameterChangeNormalized("gain", 5, 0.25));
    try std.testing.expectEqualStrings("4", try view.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqualStrings("4", try view.formatPlainById(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainById(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedById(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainById(3, 2.0));
    try std.testing.expectEqualStrings("4", try view.formatPlainByName("Voices", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainByName("Voices", "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainByName("Mode", 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, view.formatPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, view.parsePlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), view.plainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.normalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, view.formatPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, view.parsePlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), view.plainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.normalizedFromPlainById(99, 0.0));
    try std.testing.expectError(error.InvalidParameterName, view.formatPlainByName("Missing", 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterName, view.parsePlainByName("Missing", "1"));
    try std.testing.expectEqual(@as(?f64, null), view.plainFromNormalizedByName("Missing", 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.normalizedFromPlainByName("Missing", 0.0));
    try std.testing.expectEqual(@as(f64, 6.0), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), view.load("voices"));
    try std.testing.expectEqual(true, view.load("bypass"));
    try std.testing.expectEqual(Mode.mute, view.load("mode"));
    try std.testing.expectEqual(@as(f64, 1.0), view.loadNormalized("mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), view.loadIndex(3));
    try std.testing.expectEqual(@as(?f64, 2.0), view.loadPlainIndex(3));
    try std.testing.expectEqual(@as(?f64, null), view.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), view.loadPlainIndex(99));
    try std.testing.expectEqual(@as(?f64, 1.0), view.loadById(3));
    try std.testing.expectEqual(@as(?f64, 2.0), view.loadPlainById(3));
    try std.testing.expectEqual(@as(?f64, 1.0), view.loadByName("Mode"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.loadPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), view.loadByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), view.loadPlainByName("Missing"));
}

test "parameter editor binds reflected set and mutable values" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
        voices: IntParam = .{ .id = 1, .name = "Voices", .short_name = "Vox", .min = 1, .max = 4, .default = 1, .can_automate = false, .is_read_only = true },
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const editor = values.editor(&set);

    try std.testing.expectEqual(@as(usize, 4), editor.parameterCount());
    try std.testing.expect(!editor.parametersEmpty());
    try std.testing.expect(editor.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), editor.id(0));
    try std.testing.expectEqualStrings("Voices", editor.name(1).?);
    try std.testing.expectEqualStrings("Bypass", editor.nameById(2).?);
    try std.testing.expectEqual(@as(?u32, 1), editor.idByName("Voices"));
    try std.testing.expectEqualStrings("Vox", editor.shortName(1).?);
    try std.testing.expectEqualStrings("Mode", editor.shortNameById(3).?);
    try std.testing.expectEqualStrings("Vox", editor.shortNameByName("Voices").?);
    try std.testing.expectEqualStrings("dB", editor.units(0).?);
    try std.testing.expectEqualStrings("", editor.unitsById(1).?);
    try std.testing.expectEqualStrings("dB", editor.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalized(3));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalizedById(3));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?bool, false), editor.isBypass(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isBypassById(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isBypassByName("Gain"));
    try std.testing.expectEqual(@as(?bool, true), editor.canAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), editor.canAutomateById(1));
    try std.testing.expectEqual(@as(?bool, false), editor.canAutomateByName("Voices"));
    try std.testing.expectEqual(@as(?bool, true), editor.isReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), editor.isReadOnlyById(0));
    try std.testing.expectEqual(@as(?bool, true), editor.isReadOnlyByName("Voices"));
    try std.testing.expectEqual(@as(?i32, 2), editor.unitIdByName("Voices"));
    try std.testing.expectEqual(@as(?i32, 3), editor.stepCount(1));
    try std.testing.expectEqual(@as(?i32, 2), editor.stepCountById(3));
    try std.testing.expectEqual(@as(?i32, 2), editor.stepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), editor.isList(3));
    try std.testing.expectEqual(@as(?bool, true), editor.isListById(3));
    try std.testing.expectEqual(@as(?bool, true), editor.isListByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 2), editor.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, 1), editor.indexOfName("Voices"));
    try std.testing.expect(editor.hasId(2));
    try std.testing.expect(editor.hasName("Voices"));
    try std.testing.expectEqual(@as(?u32, null), editor.id(99));
    try std.testing.expectEqual(@as(?[]const u8, null), editor.name(99));
    try std.testing.expectEqual(@as(?[]const u8, null), editor.nameById(99));
    try std.testing.expectEqual(@as(?u32, null), editor.idByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), editor.defaultNormalizedById(99));
    try std.testing.expectEqual(@as(?f64, null), editor.defaultNormalizedByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), editor.isBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isBypassByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), editor.unitIdByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), editor.stepCountById(99));
    try std.testing.expectEqual(@as(?i32, null), editor.stepCountByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), editor.isListById(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isListByName("Missing"));
    try std.testing.expectEqual(@as(?usize, null), editor.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, null), editor.indexOfName("Missing"));
    try std.testing.expect(!editor.hasId(99));
    try std.testing.expect(!editor.hasName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), editor.indexOfField("mode"));
    try std.testing.expectEqual(@as(u32, 0), editor.descriptor("gain").id);
    try std.testing.expectEqual(@as(u32, 3), editor.fieldId("mode"));
    try std.testing.expectEqualStrings("Bypass", editor.fieldName("bypass"));
    try std.testing.expectEqualStrings("Vox", editor.fieldShortName("voices"));
    try std.testing.expectEqualStrings("dB", editor.fieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), editor.fieldDefaultNormalized("mode"));
    try std.testing.expect(!editor.fieldIsBypass("gain"));
    try std.testing.expect(editor.fieldCanAutomate("gain"));
    try std.testing.expect(!editor.fieldCanAutomate("voices"));
    try std.testing.expect(editor.fieldIsReadOnly("voices"));
    try std.testing.expectEqual(@as(i32, 0), editor.fieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), editor.fieldStepCount("mode"));
    try std.testing.expect(editor.fieldIsList("mode"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("mute", try editor.formatFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parseFieldPlain("mode", "mute"));
    try std.testing.expectEqual(Mode.mute, editor.fieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), editor.fieldNormalizedFromPlain("mode", .mute));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 3,
        .sample_offset = 4,
        .normalized = 1.0,
    }, editor.parameterChange("mode", 4, .mute));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 5,
        .normalized = 0.25,
    }, editor.parameterChangeNormalized("gain", 5, 0.25));
    try std.testing.expectEqualStrings("4", try editor.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqualStrings("4", try editor.formatPlainById(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainById(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedById(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainById(3, 2.0));
    try std.testing.expectEqualStrings("4", try editor.formatPlainByName("Voices", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainByName("Voices", "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainByName("Mode", 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, editor.formatPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, editor.parsePlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), editor.normalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, editor.formatPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, editor.parsePlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), editor.normalizedFromPlainById(99, 0.0));
    try std.testing.expectError(error.InvalidParameterName, editor.formatPlainByName("Missing", 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterName, editor.parsePlainByName("Missing", "1"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainFromNormalizedByName("Missing", 0.0));
    try std.testing.expectEqual(@as(?f64, null), editor.normalizedFromPlainByName("Missing", 0.0));
    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.store("voices", 4));
    try std.testing.expect(editor.store("bypass", true));
    try std.testing.expect(editor.store("mode", .mute));
    try std.testing.expect(editor.storeNormalized("gain", 0.5));
    try std.testing.expect(editor.storeIndex(0, 0.75));
    try std.testing.expect(editor.storePlainIndex(1, 2.0));
    try std.testing.expect(editor.storeById(2, 0.0));
    try std.testing.expect(editor.storePlainById(1, 3.0));
    try std.testing.expect(editor.storeByName("Gain", 0.75));
    try std.testing.expect(editor.storePlainByName("Voices", 4.0));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultById(3));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultByName("Mode"));
    try std.testing.expect(!editor.isDefault("mode"));
    try std.testing.expect(!editor.storeNormalized("gain", std.math.nan(f64)));
    try std.testing.expect(!editor.storeIndex(0, std.math.inf(f64)));
    try std.testing.expect(!editor.storeById(0, -std.math.inf(f64)));
    try std.testing.expect(!editor.storeByName("Gain", std.math.nan(f64)));
    try std.testing.expect(!editor.storeIndex(99, 1.0));
    try std.testing.expect(!editor.storePlainIndex(99, 1.0));
    try std.testing.expect(!editor.storeById(99, 1.0));
    try std.testing.expect(!editor.storePlainById(99, 1.0));
    try std.testing.expect(!editor.storeByName("Missing", 1.0));
    try std.testing.expect(!editor.storePlainByName("Missing", 1.0));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultIndex(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultById(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultByName("Missing"));

    try std.testing.expectEqual(@as(f64, 1.5), editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), editor.load("voices"));
    try std.testing.expectEqual(false, editor.load("bypass"));
    try std.testing.expectEqual(Mode.mute, editor.load("mode"));
    try std.testing.expectEqual(@as(f64, 1.0), editor.loadNormalized("mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.loadIndex(3));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.loadPlainIndex(3));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.loadById(2));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.loadPlainById(2));
    try std.testing.expectEqual(@as(?f64, null), editor.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlainIndex(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadById(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlainById(99));
    try std.testing.expectEqual(@as(?f64, 0.75), editor.loadByName("Gain"));
    try std.testing.expectEqual(@as(?f64, 4.0), editor.loadPlainByName("Voices"));
    try std.testing.expectEqual(@as(?f64, null), editor.loadByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlainByName("Missing"));

    const view = editor.view();
    try std.testing.expectEqual(@as(f64, 1.5), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), view.load("voices"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.mute, view.load("mode"));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultById(3));
    try std.testing.expectEqual(@as(?bool, false), view.isDefaultByName("Mode"));
    try std.testing.expect(!view.isDefault("mode"));

    const changes = [_]process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.0 },
        .{ .id = 1, .sample_offset = 0, .normalized = 0.0 },
        .{ .id = 2, .sample_offset = 0, .normalized = 1.0 },
        .{ .id = 3, .sample_offset = 0, .normalized = 0.5 },
    };
    const parameter_changes = try process.ParameterChanges.init(&changes, 1);
    try std.testing.expectEqual(@as(usize, 3), editor.applyChangesCount(parameter_changes));
    try std.testing.expectEqual(@as(f64, -12.0), editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), editor.load("voices"));
    try std.testing.expectEqual(true, editor.load("bypass"));
    try std.testing.expectEqual(Mode.boost, editor.load("mode"));

    editor.resetToDefaults();
    editor.applyChanges(parameter_changes);
    try std.testing.expectEqual(@as(f64, -12.0), editor.load("gain"));
    try std.testing.expectEqual(true, editor.load("bypass"));

    editor.resetToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 1), view.load("voices"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
    try std.testing.expectEqual(@as(?bool, true), view.isDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, true), view.isDefaultById(3));
    try std.testing.expectEqual(@as(?bool, true), view.isDefaultByName("Mode"));
    try std.testing.expect(view.isDefault("mode"));

    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.store("voices", 4));
    try std.testing.expect(editor.store("bypass", true));
    try std.testing.expect(editor.store("mode", .mute));
    try std.testing.expect(editor.resetToDefault("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), view.load("voices"));
    try std.testing.expect(editor.resetToDefaultIndex(1));
    try std.testing.expectEqual(@as(i64, 1), view.load("voices"));
    try std.testing.expect(editor.resetToDefaultById(2));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expect(editor.resetToDefaultByName("Mode"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
    try std.testing.expect(!editor.resetToDefaultIndex(99));
    try std.testing.expect(!editor.resetToDefaultById(99));
    try std.testing.expect(!editor.resetToDefaultByName("Missing"));
}

test "parameter values apply reflected parameter changes by id" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 1.0, 0.25),
        mix: FloatParam = FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
        manual: FloatParam = .{ .id = 2, .name = "Manual", .min = 0.0, .max = 1.0, .default = 0.25, .can_automate = false },
        meter: FloatParam = .{ .id = 3, .name = "Meter", .min = 0.0, .max = 1.0, .default = 0.5, .is_read_only = true },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const items = [_]process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.75 },
        .{ .id = 99, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 1, .sample_offset = 4, .normalized = 1.0 },
        .{ .id = 2, .sample_offset = 5, .normalized = 1.0 },
        .{ .id = 3, .sample_offset = 6, .normalized = 1.0 },
    };
    const changes = try process.ParameterChanges.init(&items, 8);

    try std.testing.expectEqual(@as(usize, 2), values.applyChangesCount(&set, changes));

    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 1));
    try std.testing.expectEqual(@as(?f64, 0.25), values.loadById(&set, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadById(&set, 3));

    values.resetToDefaults(&set);
    values.applyChanges(&set, changes);
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 1));
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
    try std.testing.expectEqualStrings("On", try bypass.formatPlain(1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 0.0), try bypass.parsePlain("off"));
    try std.testing.expectError(error.InvalidBool, bypass.parsePlain("maybe"));
    try std.testing.expectEqualStrings("crunch", try mode.formatPlain(0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try mode.parsePlain("lead"));
    try std.testing.expectError(error.InvalidEnumTag, mode.parsePlain("solo"));
}

test "parameter sets convert normalized and plain values by reflected index" {
    const Mode = enum { clean, crunch, lead };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 2.0, 1.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalized(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), set.normalizedFromPlain(0, 1.0));
    try std.testing.expectEqual(@as(?f64, 9.0), set.plainFromNormalized(1, 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlain(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalized(3, 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlain(3, 2.0));
}

test "parameter sets convert normalized and plain values by reflected id" {
    const Mode = enum { clean, crunch, lead };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 2.0, 1.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1.000", try set.formatPlainById(0, 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try set.parsePlainById(1, "16"));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalizedById(0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), set.normalizedFromPlainById(0, 1.0));
    try std.testing.expectEqual(@as(?f64, 9.0), set.plainFromNormalizedById(1, 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlainById(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalizedById(3, 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlainById(3, 2.0));
    try std.testing.expectError(error.InvalidParameterId, set.formatPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, set.parsePlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), set.plainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), set.normalizedFromPlainById(99, 0.0));
}

test "parameter sets convert normalized and plain values by reflected name" {
    const Mode = enum { clean, crunch, lead };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 2.0, 1.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("1.000", try set.formatPlainByName("Gain", 0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try set.parsePlainByName("Voices", "16"));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalizedByName("Gain", 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), set.normalizedFromPlainByName("Gain", 1.0));
    try std.testing.expectEqual(@as(?f64, 9.0), set.plainFromNormalizedByName("Voices", 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlainByName("Bypass", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainFromNormalizedByName("Mode", 0.5));
    try std.testing.expectEqual(@as(?f64, 1.0), set.normalizedFromPlainByName("Mode", 2.0));
    try std.testing.expectError(error.InvalidParameterName, set.formatPlainByName("Missing", 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterName, set.parsePlainByName("Missing", "1"));
    try std.testing.expectEqual(@as(?f64, null), set.plainFromNormalizedByName("Missing", 0.0));
    try std.testing.expectEqual(@as(?f64, null), set.normalizedFromPlainByName("Missing", 0.0));
}
