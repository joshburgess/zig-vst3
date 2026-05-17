const std = @import("std");
const shared = @import("../common.zig");
const process = @import("../process.zig");
const descriptors = @import("descriptors.zig");
const access = @import("access.zig");

pub const FloatParam = descriptors.FloatParam;
pub const IntParam = descriptors.IntParam;
pub const BoolParam = descriptors.BoolParam;
pub const EnumParam = descriptors.EnumParam;
pub const ParameterValues = access.ParameterValues;

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
                inline for (fields[left_index + 1 ..]) |right_field| {
                    if (@field(self.params, right_field.name).id == left_id) {
                        return left_id;
                    }
                }
            }
            return null;
        }

        pub fn duplicateIdIndex(self: *const Self) ?usize {
            inline for (fields, 0..) |left_field, left_index| {
                const left_id = @field(self.params, left_field.name).id;
                inline for (fields[left_index + 1 ..], left_index + 1..) |right_field, right_index| {
                    if (@field(self.params, right_field.name).id == left_id) {
                        return right_index;
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
                inline for (fields[left_index + 1 ..]) |right_field| {
                    if (std.mem.eql(u8, @field(self.params, right_field.name).name, left_name)) {
                        return left_name;
                    }
                }
            }
            return null;
        }

        pub fn duplicateNameIndex(self: *const Self) ?usize {
            inline for (fields, 0..) |left_field, left_index| {
                const left_name = @field(self.params, left_field.name).name;
                inline for (fields[left_index + 1 ..], left_index + 1..) |right_field, right_index| {
                    if (std.mem.eql(u8, @field(self.params, right_field.name).name, left_name)) {
                        return right_index;
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

        pub fn firstDescriptorErrorIndex(self: *const Self) ?usize {
            inline for (fields, 0..) |field, field_index| {
                if (parameterDescriptorError(@field(self.params, field.name)) != null) return field_index;
            }
            return null;
        }

        pub fn firstDescriptorErrorName(self: *const Self) ?[]const u8 {
            inline for (fields) |field| {
                const param = @field(self.params, field.name);
                if (parameterDescriptorError(param) != null) return param.name;
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

        pub fn defaultPlain(self: *const Self, index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) {
                    const param = @field(self.params, field.name);
                    return param.plainFromNormalized(param.defaultNormalized());
                }
            }
            return null;
        }

        pub fn defaultPlainById(self: *const Self, wanted_id: u32) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.defaultPlain(index);
        }

        pub fn defaultPlainByName(self: *const Self, wanted_name: []const u8) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.defaultPlain(index);
        }

        pub fn plainMinimum(self: *const Self, index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterPlainMinimum(@field(self.params, field.name));
            }
            return null;
        }

        pub fn plainMinimumById(self: *const Self, wanted_id: u32) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.plainMinimum(index);
        }

        pub fn plainMinimumByName(self: *const Self, wanted_name: []const u8) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.plainMinimum(index);
        }

        pub fn plainMaximum(self: *const Self, index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterPlainMaximum(@field(self.params, field.name));
            }
            return null;
        }

        pub fn plainMaximumById(self: *const Self, wanted_id: u32) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.plainMaximum(index);
        }

        pub fn plainMaximumByName(self: *const Self, wanted_name: []const u8) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.plainMaximum(index);
        }

        pub fn hasPlainRange(self: *const Self, index: usize) bool {
            return self.plainMinimum(index) != null and self.plainMaximum(index) != null;
        }

        pub fn hasPlainRangeById(self: *const Self, wanted_id: u32) bool {
            const index = self.indexOfId(wanted_id) orelse return false;
            return self.hasPlainRange(index);
        }

        pub fn hasPlainRangeByName(self: *const Self, wanted_name: []const u8) bool {
            const index = self.indexOfName(wanted_name) orelse return false;
            return self.hasPlainRange(index);
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

        pub fn optionCount(self: *const Self, index: usize) ?usize {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterOptionCount(@field(self.params, field.name));
            }
            return null;
        }

        pub fn optionCountById(self: *const Self, wanted_id: u32) ?usize {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.optionCount(index);
        }

        pub fn optionCountByName(self: *const Self, wanted_name: []const u8) ?usize {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.optionCount(index);
        }

        pub fn optionLabel(self: *const Self, index: usize, option_index: usize) ?[]const u8 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterOptionLabel(@field(self.params, field.name), option_index);
            }
            return null;
        }

        pub fn optionLabelById(self: *const Self, wanted_id: u32, option_index: usize) ?[]const u8 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.optionLabel(index, option_index);
        }

        pub fn optionLabelByName(self: *const Self, wanted_name: []const u8, option_index: usize) ?[]const u8 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.optionLabel(index, option_index);
        }

        pub fn optionNormalized(self: *const Self, index: usize, option_index: usize) ?f64 {
            inline for (fields, 0..) |field, field_index| {
                if (index == field_index) return parameterOptionNormalized(@field(self.params, field.name), option_index);
            }
            return null;
        }

        pub fn optionNormalizedById(self: *const Self, wanted_id: u32, option_index: usize) ?f64 {
            const index = self.indexOfId(wanted_id) orelse return null;
            return self.optionNormalized(index, option_index);
        }

        pub fn optionNormalizedByName(self: *const Self, wanted_name: []const u8, option_index: usize) ?f64 {
            const index = self.indexOfName(wanted_name) orelse return null;
            return self.optionNormalized(index, option_index);
        }

        pub fn hasOptions(self: *const Self, index: usize) bool {
            return self.optionCount(index) != null;
        }

        pub fn optionsEmpty(self: *const Self, index: usize) bool {
            return !self.hasOptions(index);
        }

        pub fn hasOptionsById(self: *const Self, wanted_id: u32) bool {
            const index = self.indexOfId(wanted_id) orelse return false;
            return self.hasOptions(index);
        }

        pub fn optionsEmptyById(self: *const Self, wanted_id: u32) bool {
            const index = self.indexOfId(wanted_id) orelse return true;
            return self.optionsEmpty(index);
        }

        pub fn hasOptionsByName(self: *const Self, wanted_name: []const u8) bool {
            const index = self.indexOfName(wanted_name) orelse return false;
            return self.hasOptions(index);
        }

        pub fn optionsEmptyByName(self: *const Self, wanted_name: []const u8) bool {
            const index = self.indexOfName(wanted_name) orelse return true;
            return self.optionsEmpty(index);
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

        pub fn descriptorAt(self: *const Self, comptime index: usize) fields[index].type {
            return @field(self.params, fields[index].name);
        }

        pub fn idAt(self: *const Self, comptime index: usize) u32 {
            return self.descriptorAt(index).id;
        }

        pub fn nameAt(self: *const Self, comptime index: usize) []const u8 {
            return self.descriptorAt(index).name;
        }

        pub fn defaultNormalizedAt(self: *const Self, comptime index: usize) f64 {
            return self.descriptorAt(index).defaultNormalized();
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
            const param = self.descriptor(field_name);
            return if (param.short_name.len == 0) param.name else param.short_name;
        }

        pub fn fieldUnits(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.descriptor(field_name).units;
        }

        pub fn fieldDefaultNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.descriptor(field_name).defaultNormalized();
        }

        pub fn fieldDefaultPlain(self: *const Self, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            const param = self.descriptor(field_name);
            return param.denormalize(param.defaultNormalized());
        }

        pub fn fieldPlainMinimum(self: *const Self, comptime field_name: []const u8) ?f64 {
            return parameterPlainMinimum(self.descriptor(field_name));
        }

        pub fn fieldPlainMaximum(self: *const Self, comptime field_name: []const u8) ?f64 {
            return parameterPlainMaximum(self.descriptor(field_name));
        }

        pub fn fieldHasPlainRange(self: *const Self, comptime field_name: []const u8) bool {
            return self.fieldPlainMinimum(field_name) != null and self.fieldPlainMaximum(field_name) != null;
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

        pub fn fieldOptionCount(self: *const Self, comptime field_name: []const u8) ?usize {
            return parameterOptionCount(self.descriptor(field_name));
        }

        pub fn fieldOptionLabel(self: *const Self, comptime field_name: []const u8, option_index: usize) ?[]const u8 {
            return parameterOptionLabel(self.descriptor(field_name), option_index);
        }

        pub fn fieldOptionNormalized(self: *const Self, comptime field_name: []const u8, option_index: usize) ?f64 {
            return parameterOptionNormalized(self.descriptor(field_name), option_index);
        }

        pub fn fieldHasOptions(self: *const Self, comptime field_name: []const u8) bool {
            return self.fieldOptionCount(field_name) != null;
        }

        pub fn fieldOptionsEmpty(self: *const Self, comptime field_name: []const u8) bool {
            return !self.fieldHasOptions(field_name);
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

        pub fn parameterChangeNormalizedById(
            self: *const Self,
            wanted_id: u32,
            sample_offset: usize,
            normalized: f64,
        ) ?process.ParameterChange {
            if (!self.hasId(wanted_id)) return null;
            return .{
                .id = wanted_id,
                .sample_offset = sample_offset,
                .normalized = normalized,
            };
        }

        pub fn parameterChangePlainById(
            self: *const Self,
            wanted_id: u32,
            sample_offset: usize,
            plain: f64,
        ) ?process.ParameterChange {
            const normalized = self.normalizedFromPlainById(wanted_id, plain) orelse return null;
            return self.parameterChangeNormalizedById(wanted_id, sample_offset, normalized);
        }

        pub fn parameterChangeNormalizedByName(
            self: *const Self,
            wanted_name: []const u8,
            sample_offset: usize,
            normalized: f64,
        ) ?process.ParameterChange {
            const id_value = self.idByName(wanted_name) orelse return null;
            return self.parameterChangeNormalizedById(id_value, sample_offset, normalized);
        }

        pub fn parameterChangePlainByName(
            self: *const Self,
            wanted_name: []const u8,
            sample_offset: usize,
            plain: f64,
        ) ?process.ParameterChange {
            const normalized = self.normalizedFromPlainByName(wanted_name, plain) orelse return null;
            return self.parameterChangeNormalizedByName(wanted_name, sample_offset, normalized);
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

pub fn parameterStepCount(param: anytype) i32 {
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

pub fn parameterPlainMinimum(param: anytype) ?f64 {
    const Param = @TypeOf(param);
    if (Param == FloatParam) return param.min;
    if (Param == IntParam) return @floatFromInt(param.min);
    return null;
}

pub fn parameterPlainMaximum(param: anytype) ?f64 {
    const Param = @TypeOf(param);
    if (Param == FloatParam) return param.max;
    if (Param == IntParam) return @floatFromInt(param.max);
    return null;
}

pub fn parameterIsList(param: anytype) bool {
    const Param = @TypeOf(param);
    if (Param == BoolParam) return false;
    const info = @typeInfo(Param);
    if (info == .@"struct" and @hasDecl(Param, "label")) {
        return @typeInfo(@TypeOf(param.default)) == .@"enum";
    }
    return false;
}

pub fn parameterOptionCount(param: anytype) ?usize {
    const Param = @TypeOf(param);
    if (parameterIsList(param) and @hasDecl(Param, "optionCount")) {
        return param.optionCount();
    }
    return null;
}

pub fn parameterOptionLabel(param: anytype, option_index: usize) ?[]const u8 {
    const Param = @TypeOf(param);
    if (parameterIsList(param) and @hasDecl(Param, "labelAtOptionIndex")) {
        return param.labelAtOptionIndex(option_index);
    }
    return null;
}

pub fn parameterOptionNormalized(param: anytype, option_index: usize) ?f64 {
    const Param = @TypeOf(param);
    if (parameterIsList(param) and @hasDecl(Param, "normalizedFromOptionIndex")) {
        return param.normalizedFromOptionIndex(option_index);
    }
    return null;
}

pub fn parameterDescriptorError(param: anytype) ?anyerror {
    const Param = @TypeOf(param);
    if (param.name.len == 0) return error.EmptyParameterName;
    if (shared.containsNul(param.name) or
        shared.containsNul(param.short_name) or
        shared.containsNul(param.units))
    {
        return error.InvalidParameterMetadata;
    }
    if (Param == FloatParam) {
        if (!std.math.isFinite(param.min) or !std.math.isFinite(param.max) or param.max <= param.min) {
            return error.InvalidParameterRange;
        }
        if (!shared.isFiniteInRange(f64, param.default, param.min, param.max)) return error.InvalidParameterDefault;
    } else if (Param == IntParam) {
        if (param.max <= param.min) return error.InvalidParameterRange;
        if (param.default < param.min or param.default > param.max) return error.InvalidParameterDefault;
    }
    return null;
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
    try std.testing.expectEqual(@as(?f64, 0.0), set.plainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 16.0), set.plainMaximumById(1));
    try std.testing.expectEqual(@as(?f64, 1.0), set.plainMinimumByName("Voices"));
    try std.testing.expectEqual(@as(?f64, null), set.plainMinimum(2));
    try std.testing.expectEqual(@as(?f64, null), set.plainMaximumById(99));
    try std.testing.expectEqual(@as(?f64, null), set.plainMinimumByName("Missing"));
    try std.testing.expectEqual(@as(?f64, 0.0), set.fieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 16.0), set.fieldPlainMaximum("voices"));
    try std.testing.expectEqual(@as(?f64, null), set.fieldPlainMinimum("bypass"));
    try std.testing.expect(set.fieldHasPlainRange("gain"));
    try std.testing.expect(set.fieldHasPlainRange("voices"));
    try std.testing.expect(!set.fieldHasPlainRange("bypass"));
    try std.testing.expect(set.hasPlainRange(0));
    try std.testing.expect(set.hasPlainRangeById(1));
    try std.testing.expect(set.hasPlainRangeByName("Voices"));
    try std.testing.expect(!set.hasPlainRange(2));
    try std.testing.expect(!set.hasPlainRangeById(99));
    try std.testing.expect(!set.hasPlainRangeByName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), set.indexOfId(2));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), set.indexOfName("Voices"));
    try std.testing.expectEqual(@as(?usize, null), set.indexOfName("Missing"));
    try std.testing.expect(set.hasId(2));
    try std.testing.expect(!set.hasId(99));
    try std.testing.expect(set.hasName("Voices"));
    try std.testing.expect(!set.hasName("Missing"));
    try std.testing.expectEqual(@as(usize, 0), set.indexOfField("gain"));
    try std.testing.expectEqual(@as(u32, 0), set.idAt(0));
    try std.testing.expectEqualStrings("Gain", set.nameAt(0));
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
    try std.testing.expectEqual(@as(?f64, 0.75), set.defaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 4.0), set.defaultPlainById(1));
    try std.testing.expectEqual(@as(?f64, 1.0), set.defaultPlainByName("Bypass"));
    try std.testing.expectEqual(@as(?f64, 1.0), set.defaultPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), set.defaultPlain(99));
    try std.testing.expectEqual(@as(?f64, null), set.defaultPlainById(99));
    try std.testing.expectEqual(@as(?f64, null), set.defaultPlainByName("Missing"));
    try std.testing.expectEqual(@as(f64, 0.75), set.fieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(i64, 4), set.fieldDefaultPlain("voices"));
    try std.testing.expectEqual(true, set.fieldDefaultPlain("bypass"));
    try std.testing.expectEqual(Mode.lead, set.fieldDefaultPlain("mode"));
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
    try std.testing.expectEqual(@as(?usize, 2), set.optionCount(3));
    try std.testing.expectEqual(@as(?usize, 2), set.optionCountById(3));
    try std.testing.expectEqual(@as(?usize, 2), set.optionCountByName("Mode"));
    try std.testing.expectEqual(@as(?usize, null), set.optionCount(2));
    try std.testing.expectEqual(@as(?usize, null), set.optionCountById(99));
    try std.testing.expectEqualStrings("lead", set.optionLabel(3, 1).?);
    try std.testing.expectEqualStrings("clean", set.optionLabelById(3, 0).?);
    try std.testing.expectEqualStrings("lead", set.optionLabelByName("Mode", 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), set.optionLabel(3, 2));
    try std.testing.expectEqual(@as(?[]const u8, null), set.optionLabelByName("Missing", 0));
    try std.testing.expectEqual(@as(?f64, 1.0), set.optionNormalized(3, 1));
    try std.testing.expectEqual(@as(?f64, 0.0), set.optionNormalizedById(3, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), set.optionNormalizedByName("Mode", 1));
    try std.testing.expectEqual(@as(?f64, null), set.optionNormalized(3, 2));
    try std.testing.expectEqual(@as(?usize, 2), set.fieldOptionCount("mode"));
    try std.testing.expectEqualStrings("lead", set.fieldOptionLabel("mode", 1).?);
    try std.testing.expectEqual(@as(?f64, 1.0), set.fieldOptionNormalized("mode", 1));
    try std.testing.expectEqual(@as(?usize, null), set.fieldOptionCount("bypass"));
    try std.testing.expect(set.fieldHasOptions("mode"));
    try std.testing.expect(!set.fieldOptionsEmpty("mode"));
    try std.testing.expect(!set.fieldHasOptions("bypass"));
    try std.testing.expect(set.fieldOptionsEmpty("bypass"));
    try std.testing.expect(set.hasOptions(3));
    try std.testing.expect(!set.optionsEmpty(3));
    try std.testing.expect(set.hasOptionsById(3));
    try std.testing.expect(!set.optionsEmptyById(3));
    try std.testing.expect(set.hasOptionsByName("Mode"));
    try std.testing.expect(!set.optionsEmptyByName("Mode"));
    try std.testing.expect(!set.hasOptions(0));
    try std.testing.expect(set.optionsEmpty(0));
    try std.testing.expect(!set.hasOptionsById(99));
    try std.testing.expect(set.optionsEmptyById(99));
    try std.testing.expect(!set.hasOptionsByName("Missing"));
    try std.testing.expect(set.optionsEmptyByName("Missing"));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 2,
        .normalized = 0.25,
    }, set.parameterChangeNormalized("gain", 2, 0.25));
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 6,
        .normalized = 0.5,
    }, set.parameterChangeNormalizedById(0, 6, 0.5).?);
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 7,
        .normalized = 1.0,
    }, set.parameterChangePlainByName("Gain", 7, 6.0).?);
    try std.testing.expectEqual(@as(?process.ParameterChange, null), set.parameterChangeNormalizedById(99, 0, 0.5));
    try std.testing.expectEqual(@as(?process.ParameterChange, null), set.parameterChangePlainByName("Missing", 0, 6.0));
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
    var values = ParameterValues(Params).init(&set);
    const view = values.view(&set);
    var editor = values.editor(&set);

    try std.testing.expectEqual(@as(?u32, 7), set.duplicateId());
    try std.testing.expectEqual(@as(?usize, 1), set.duplicateIdIndex());
    try std.testing.expect(set.hasDuplicateIds());
    try std.testing.expectError(error.DuplicateParameterId, set.validateUniqueIds());
    try std.testing.expectError(error.DuplicateParameterId, view.validateUniqueIds());
    try std.testing.expectError(error.DuplicateParameterId, editor.validateUniqueIds());
}

test "parameter set accepts unique ids" {
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        mix: FloatParam = .{ .id = 1, .name = "Mix", .min = 0.0, .max = 1.0, .default = 0.25 },
    };
    const Set = ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(?u32, null), set.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), set.duplicateIdIndex());
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
    var values = ParameterValues(Params).init(&set);
    const view = values.view(&set);
    var editor = values.editor(&set);

    try std.testing.expectEqualStrings("Level", set.duplicateName().?);
    try std.testing.expectEqual(@as(?usize, 1), set.duplicateNameIndex());
    try std.testing.expect(set.hasDuplicateNames());
    try std.testing.expectError(error.DuplicateParameterName, set.validateUniqueNames());
    try std.testing.expectError(error.DuplicateParameterName, set.validate());
    try std.testing.expectError(error.DuplicateParameterName, view.validateUniqueNames());
    try std.testing.expectError(error.DuplicateParameterName, editor.validateUniqueNames());
    try std.testing.expectError(error.DuplicateParameterName, view.validate());
    try std.testing.expectError(error.DuplicateParameterName, editor.validate());
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
    try std.testing.expectEqual(@as(?usize, 0), empty_name_set.firstDescriptorErrorIndex());
    try std.testing.expectEqualStrings("", empty_name_set.firstDescriptorErrorName().?);
    try std.testing.expectError(error.EmptyParameterName, empty_name_set.validateDescriptors());
    try std.testing.expectEqual(@as(?usize, 0), invalid_name_set.firstDescriptorErrorIndex());
    try std.testing.expectEqualStrings("Ga\x00in", invalid_name_set.firstDescriptorErrorName().?);
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

    try std.testing.expect(set.firstDescriptorError() == null);
    try std.testing.expect(set.firstDescriptorErrorIndex() == null);
    try std.testing.expect(set.firstDescriptorErrorName() == null);
    try set.validate();
}

test "parameter set validates unit ids against reflected units" {
    const unit_api = @import("../units.zig");
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
    var values = ParameterValues(Params).init(&set);
    const view = values.view(&set);
    var editor = values.editor(&set);
    var invalid_values = ParameterValues(InvalidParams).init(&invalid_set);
    const invalid_view = invalid_values.view(&invalid_set);
    var invalid_editor = invalid_values.editor(&invalid_set);

    try set.validateUnitIds(units);
    try view.validateUnitIds(units);
    try editor.validateUnitIds(units);
    try std.testing.expectError(error.InvalidParameterUnit, invalid_set.validateUnitIds(units));
    try std.testing.expectError(error.InvalidParameterUnit, invalid_view.validateUnitIds(units));
    try std.testing.expectError(error.InvalidParameterUnit, invalid_editor.validateUnitIds(units));
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
