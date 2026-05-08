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

    pub fn storeModulation(self: *ModulatedValue, offset: f64) void {
        const safe_offset = if (std.math.isNan(offset)) 0.0 else std.math.clamp(offset, -1.0, 1.0);
        self.modulation.store((safe_offset + 1.0) * 0.5);
    }

    pub fn load(self: *const ModulatedValue) f64 {
        const offset = self.modulation.load() * 2.0 - 1.0;
        return clampNormalized(self.base.load() + offset);
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

pub const LogSmoother = struct {
    current: f64,
    target: f64,
    ratio: f64 = 1.0,
    remaining: usize = 0,

    pub fn init(value: f64) LogSmoother {
        const clamped = clampNormalizedNonZero(value);
        return .{ .current = clamped, .target = clamped };
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
    min: f64 = 0.0,
    max: f64 = 1.0,
    default: f64 = 0.0,
    is_bypass: bool = false,

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
    min: i64,
    max: i64,
    default: i64,
    is_bypass: bool = false,

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
    default: bool = false,
    is_bypass: bool = false,

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
        default: Enum,
        is_bypass: bool = false,

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

        pub fn formatPlain(self: Self, normalized: f64, _: []u8) ![]const u8 {
            return self.label(self.denormalize(normalized));
        }

        pub fn plainFromNormalized(self: Self, normalized: f64) f64 {
            return @floatFromInt(@intFromEnum(self.denormalize(normalized)));
        }

        pub fn normalizedFromPlain(self: Self, plain: f64) f64 {
            const max_index = info.fields.len - 1;
            const index = if (std.math.isNan(plain) or plain <= 0)
                0
            else if (plain >= @as(f64, @floatFromInt(max_index)))
                max_index
            else
                @as(usize, @intFromFloat(@round(plain)));
            return self.normalize(@enumFromInt(index));
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

pub fn ParameterSet(comptime Params: type) type {
    const fields = @typeInfo(Params).@"struct".fields;

    return struct {
        const Self = @This();

        pub const count = fields.len;

        params: Params,

        pub fn init(params: Params) Self {
            return .{ .params = params };
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

        pub fn defaultNormalized(self: *const Self, index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).defaultNormalized();
            }
            return null;
        }

        pub fn isBypass(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return @field(self.params, field.name).is_bypass;
            }
            return null;
        }

        pub fn stepCount(self: *const Self, index: usize) ?i32 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterStepCount(@field(self.params, field.name));
            }
            return null;
        }

        pub fn isList(self: *const Self, index: usize) ?bool {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterIsList(@field(self.params, field.name));
            }
            return null;
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

        pub fn fieldDefaultNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.descriptor(field_name).defaultNormalized();
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
    };
}

fn parameterStepCount(param: anytype) i32 {
    const Param = @TypeOf(param);
    if (Param == FloatParam) return 0;
    if (Param == BoolParam) return 1;
    if (Param == IntParam) return std.math.cast(i32, param.max - param.min) orelse std.math.maxInt(i32);

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

        pub fn loadById(self: *const Self, set: *const Set, id: u32) ?f64 {
            const index = set.indexOfId(id) orelse return null;
            return self.load(index);
        }

        pub fn loadPlainById(self: *const Self, set: *const Set, id: u32) ?f64 {
            const index = set.indexOfId(id) orelse return null;
            return self.loadPlain(set, index);
        }

        pub fn loadFieldNormalized(self: *const Self, set: *const Set, comptime field_name: []const u8) f64 {
            return self.load(set.indexOfField(field_name)).?;
        }

        pub fn loadField(self: *const Self, set: *const Set, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            const param = set.descriptor(field_name);
            return param.denormalize(self.loadFieldNormalized(set, field_name));
        }

        pub fn storeById(self: *Self, set: *const Set, id: u32, value: f64) bool {
            const index = set.indexOfId(id) orelse return false;
            return self.store(index, value);
        }

        pub fn storePlainById(self: *Self, set: *const Set, id: u32, plain: f64) bool {
            const index = set.indexOfId(id) orelse return false;
            return self.storePlain(set, index, plain);
        }

        pub fn storeField(self: *Self, set: *const Set, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) bool {
            const param = set.descriptor(field_name);
            return self.store(set.indexOfField(field_name), param.normalize(plain));
        }

        pub fn applyChanges(self: *Self, set: *const Set, changes: process.ParameterChanges) void {
            for (changes.items) |change| {
                _ = self.storeById(set, change.id, change.normalized);
            }
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

        pub fn id(self: Self, index: usize) ?u32 {
            return self.set.id(index);
        }

        pub fn name(self: Self, index: usize) ?[]const u8 {
            return self.set.name(index);
        }

        pub fn defaultNormalized(self: Self, index: usize) ?f64 {
            return self.set.defaultNormalized(index);
        }

        pub fn isBypass(self: Self, index: usize) ?bool {
            return self.set.isBypass(index);
        }

        pub fn stepCount(self: Self, index: usize) ?i32 {
            return self.set.stepCount(index);
        }

        pub fn isList(self: Self, index: usize) ?bool {
            return self.set.isList(index);
        }

        pub fn indexOfId(self: Self, wanted_id: u32) ?usize {
            return self.set.indexOfId(wanted_id);
        }

        pub fn indexOfName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.indexOfName(wanted_name);
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

        pub fn fieldDefaultNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.set.fieldDefaultNormalized(field_name);
        }

        pub fn formatPlainIndex(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlain(index, normalized, buffer);
        }

        pub fn formatPlainById(self: Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainById(wanted_id, normalized, buffer);
        }

        pub fn parsePlainIndex(self: Self, index: usize, text: []const u8) !f64 {
            return self.set.parsePlain(index, text);
        }

        pub fn parsePlainById(self: Self, wanted_id: u32, text: []const u8) !f64 {
            return self.set.parsePlainById(wanted_id, text);
        }

        pub fn plainFromNormalizedIndex(self: Self, index: usize, normalized: f64) ?f64 {
            return self.set.plainFromNormalized(index, normalized);
        }

        pub fn plainFromNormalizedById(self: Self, wanted_id: u32, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedById(wanted_id, normalized);
        }

        pub fn normalizedFromPlainIndex(self: Self, index: usize, plain: f64) ?f64 {
            return self.set.normalizedFromPlain(index, plain);
        }

        pub fn normalizedFromPlainById(self: Self, wanted_id: u32, plain: f64) ?f64 {
            return self.set.normalizedFromPlainById(wanted_id, plain);
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

        pub fn id(self: Self, index: usize) ?u32 {
            return self.set.id(index);
        }

        pub fn name(self: Self, index: usize) ?[]const u8 {
            return self.set.name(index);
        }

        pub fn defaultNormalized(self: Self, index: usize) ?f64 {
            return self.set.defaultNormalized(index);
        }

        pub fn isBypass(self: Self, index: usize) ?bool {
            return self.set.isBypass(index);
        }

        pub fn stepCount(self: Self, index: usize) ?i32 {
            return self.set.stepCount(index);
        }

        pub fn isList(self: Self, index: usize) ?bool {
            return self.set.isList(index);
        }

        pub fn indexOfId(self: Self, wanted_id: u32) ?usize {
            return self.set.indexOfId(wanted_id);
        }

        pub fn indexOfName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.indexOfName(wanted_name);
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

        pub fn fieldDefaultNormalized(self: Self, comptime field_name: []const u8) f64 {
            return self.set.fieldDefaultNormalized(field_name);
        }

        pub fn formatPlainIndex(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlain(index, normalized, buffer);
        }

        pub fn formatPlainById(self: Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            return self.set.formatPlainById(wanted_id, normalized, buffer);
        }

        pub fn parsePlainIndex(self: Self, index: usize, text: []const u8) !f64 {
            return self.set.parsePlain(index, text);
        }

        pub fn parsePlainById(self: Self, wanted_id: u32, text: []const u8) !f64 {
            return self.set.parsePlainById(wanted_id, text);
        }

        pub fn plainFromNormalizedIndex(self: Self, index: usize, normalized: f64) ?f64 {
            return self.set.plainFromNormalized(index, normalized);
        }

        pub fn plainFromNormalizedById(self: Self, wanted_id: u32, normalized: f64) ?f64 {
            return self.set.plainFromNormalizedById(wanted_id, normalized);
        }

        pub fn normalizedFromPlainIndex(self: Self, index: usize, plain: f64) ?f64 {
            return self.set.normalizedFromPlain(index, plain);
        }

        pub fn normalizedFromPlainById(self: Self, wanted_id: u32, plain: f64) ?f64 {
            return self.set.normalizedFromPlainById(wanted_id, plain);
        }

        pub fn resetToDefaults(self: Self) void {
            self.values.resetToDefaults(self.set);
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

        pub fn storeNormalized(self: Self, comptime field_name: []const u8, normalized: f64) bool {
            return self.values.store(self.set.indexOfField(field_name), normalized);
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

    try std.testing.expectEqual(@as(f64, 0.5), value.load());
    value.storeModulation(0.25);
    try std.testing.expectEqual(@as(f64, 0.75), value.load());
    value.storeBase(0.1);
    value.storeModulation(-0.5);
    try std.testing.expectEqual(@as(f64, 0.0), value.load());
    value.storeModulation(2.0);
    try std.testing.expectEqual(@as(f64, 1.0), value.load());
    value.storeBase(0.25);
    value.storeModulation(std.math.nan(f64));
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

test "log smoother reaches multiplicative target after requested samples" {
    var smoother = LogSmoother.init(0.25);

    smoother.setTarget(1.0, 2);
    try std.testing.expectApproxEqAbs(0.5, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
    try std.testing.expectApproxEqAbs(1.0, smoother.next(), 0.000001);
}

test "log smoother clamps zero and handles immediate target" {
    var smoother = LogSmoother.init(0.0);

    try std.testing.expect(smoother.current > 0.0);
    smoother.setTarget(2.0, 0);
    try std.testing.expectApproxEqAbs(1.0, smoother.current, 0.000001);
    smoother.setTarget(std.math.nan(f64), 0);
    try std.testing.expectApproxEqAbs(std.math.floatEps(f64), smoother.current, 0.0);
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
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 1.0, 0.75),
        voices: IntParam = IntParam.init(1, "Voices", 1, 16, 4),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .lead },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(usize, 4), Set.count);
    try std.testing.expectEqual(@as(?u32, 0), set.id(0));
    try std.testing.expectEqualStrings("Voices", set.name(1).?);
    try std.testing.expectEqual(@as(?usize, 2), set.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), set.indexOfName("Voices"));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfName("Missing"));
    try std.testing.expectEqual(@as(usize, 0), set.indexOfField("gain"));
    try std.testing.expectEqual(@as(u32, 3), set.descriptor("mode").id);
    try std.testing.expectEqual(@as(u32, 0), set.fieldId("gain"));
    try std.testing.expectEqualStrings("Mode", set.fieldName("mode"));
    try std.testing.expectApproxEqAbs(1.0, set.fieldDefaultNormalized("mode"), 0.000001);
    try std.testing.expectApproxEqAbs(0.75, set.defaultNormalized(0).?, 0.000001);
    try std.testing.expectApproxEqAbs(0.2, set.defaultNormalized(1).?, 0.000001);
    try std.testing.expectApproxEqAbs(0.0, set.defaultNormalized(2).?, 0.000001);
    try std.testing.expectApproxEqAbs(1.0, set.defaultNormalized(3).?, 0.000001);
    try std.testing.expectEqual(@as(?bool, false), set.isBypass(0));
    try std.testing.expectEqual(@as(?bool, null), set.isBypass(99));
    try std.testing.expectEqual(@as(?i32, 0), set.stepCount(0));
    try std.testing.expectEqual(@as(?i32, 15), set.stepCount(1));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCount(2));
    try std.testing.expectEqual(@as(?i32, 1), set.stepCount(3));
    try std.testing.expectEqual(@as(?i32, null), set.stepCount(99));
    try std.testing.expectEqual(@as(?bool, false), set.isList(1));
    try std.testing.expectEqual(@as(?bool, true), set.isList(3));
    try std.testing.expectEqual(@as(?bool, null), set.isList(99));
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
}

test "integer parameter step count saturates to VST limit" {
    const Params = struct {
        huge: IntParam = IntParam.init(0, "Huge", 0, @as(i64, std.math.maxInt(i32)) + 1, 0),
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?i32, std.math.maxInt(i32)), set.stepCount(0));
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

test "parameter values expose typed field access" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 4, 1),
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

    try std.testing.expect(values.storeField(&set, "gain", 6.0));
    try std.testing.expect(values.storeField(&set, "voices", 4));
    try std.testing.expect(values.storeField(&set, "bypass", true));
    try std.testing.expect(values.storeField(&set, "mode", .mute));

    try std.testing.expectEqual(@as(f64, 6.0), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(i64, 4), values.loadField(&set, "voices"));
    try std.testing.expectEqual(true, values.loadField(&set, "bypass"));
    try std.testing.expectEqual(Mode.mute, values.loadField(&set, "mode"));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadFieldNormalized(&set, "mode"));
}

test "parameter view binds reflected set and values" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 4, 1),
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
    try std.testing.expectEqual(@as(?u32, 0), view.id(0));
    try std.testing.expectEqualStrings("Voices", view.name(1).?);
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultNormalized(3));
    try std.testing.expectEqual(@as(?bool, false), view.isBypass(0));
    try std.testing.expectEqual(@as(?i32, 3), view.stepCount(1));
    try std.testing.expectEqual(@as(?bool, true), view.isList(3));
    try std.testing.expectEqual(@as(?usize, 2), view.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, 1), view.indexOfName("Voices"));
    try std.testing.expectEqual(@as(?u32, null), view.id(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.name(99));
    try std.testing.expectEqual(@as(?usize, null), view.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, null), view.indexOfName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), view.indexOfField("mode"));
    try std.testing.expectEqual(@as(u32, 0), view.descriptor("gain").id);
    try std.testing.expectEqual(@as(u32, 3), view.fieldId("mode"));
    try std.testing.expectEqualStrings("Bypass", view.fieldName("bypass"));
    try std.testing.expectEqual(@as(f64, 0.0), view.fieldDefaultNormalized("mode"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("4", try view.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqualStrings("4", try view.formatPlainById(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainById(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedById(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainById(3, 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, view.formatPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, view.parsePlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), view.plainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.normalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, view.formatPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, view.parsePlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), view.plainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), view.normalizedFromPlainById(99, 0.0));
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
}

test "parameter editor binds reflected set and mutable values" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
        voices: IntParam = IntParam.init(1, "Voices", 1, 4, 1),
        bypass: BoolParam = .{ .id = 2, .name = "Bypass" },
        mode: EnumParam(Mode) = .{ .id = 3, .name = "Mode", .default = .clean },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const editor = values.editor(&set);

    try std.testing.expectEqual(@as(usize, 4), editor.parameterCount());
    try std.testing.expectEqual(@as(?u32, 0), editor.id(0));
    try std.testing.expectEqualStrings("Voices", editor.name(1).?);
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalized(3));
    try std.testing.expectEqual(@as(?bool, false), editor.isBypass(0));
    try std.testing.expectEqual(@as(?i32, 3), editor.stepCount(1));
    try std.testing.expectEqual(@as(?bool, true), editor.isList(3));
    try std.testing.expectEqual(@as(?usize, 2), editor.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, 1), editor.indexOfName("Voices"));
    try std.testing.expectEqual(@as(?u32, null), editor.id(99));
    try std.testing.expectEqual(@as(?[]const u8, null), editor.name(99));
    try std.testing.expectEqual(@as(?usize, null), editor.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, null), editor.indexOfName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), editor.indexOfField("mode"));
    try std.testing.expectEqual(@as(u32, 0), editor.descriptor("gain").id);
    try std.testing.expectEqual(@as(u32, 3), editor.fieldId("mode"));
    try std.testing.expectEqualStrings("Bypass", editor.fieldName("bypass"));
    try std.testing.expectEqual(@as(f64, 0.0), editor.fieldDefaultNormalized("mode"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("4", try editor.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqualStrings("4", try editor.formatPlainById(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainById(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedById(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainById(3, 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, editor.formatPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, editor.parsePlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), editor.normalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, editor.formatPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, editor.parsePlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), editor.normalizedFromPlainById(99, 0.0));
    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.store("voices", 4));
    try std.testing.expect(editor.store("bypass", true));
    try std.testing.expect(editor.store("mode", .mute));
    try std.testing.expect(editor.storeNormalized("gain", 0.5));
    try std.testing.expect(editor.storeIndex(0, 0.75));
    try std.testing.expect(editor.storePlainIndex(1, 2.0));
    try std.testing.expect(editor.storeById(2, 0.0));
    try std.testing.expect(editor.storePlainById(1, 3.0));
    try std.testing.expect(!editor.storeIndex(99, 1.0));
    try std.testing.expect(!editor.storePlainIndex(99, 1.0));
    try std.testing.expect(!editor.storeById(99, 1.0));
    try std.testing.expect(!editor.storePlainById(99, 1.0));

    try std.testing.expectEqual(@as(f64, 1.5), editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 3), editor.load("voices"));
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

    const view = editor.view();
    try std.testing.expectEqual(@as(f64, 1.5), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 3), view.load("voices"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.mute, view.load("mode"));

    editor.resetToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 1), view.load("voices"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
}

test "parameter values apply reflected parameter changes by id" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 1.0, 0.25),
        mix: FloatParam = FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const items = [_]process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.75 },
        .{ .id = 99, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 1, .sample_offset = 4, .normalized = 1.0 },
    };
    const changes = try process.ParameterChanges.init(&items, 8);

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
    try std.testing.expectEqualStrings("crunch", try mode.formatPlain(0.5, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try mode.parsePlain("lead"));
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
