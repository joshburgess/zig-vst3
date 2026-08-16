const std = @import("std");
const process = @import("../process.zig");
const common = @import("common.zig");
const value_mod = @import("value.zig");
const descriptors = @import("descriptors.zig");
const set_mod = @import("set.zig");

pub const NormalizedValue = value_mod.NormalizedValue;
pub const FloatParam = descriptors.FloatParam;
pub const IntParam = descriptors.IntParam;
pub const BoolParam = descriptors.BoolParam;
pub const EnumParam = descriptors.EnumParam;
pub const ParameterSet = set_mod.ParameterSet;
pub const FieldDescriptor = set_mod.FieldDescriptor;
pub const FieldPlainType = set_mod.FieldPlainType;

const clampNormalized = common.clampNormalized;

pub fn ParameterValues(comptime Params: type) type {
    const Set = ParameterSet(Params);

    return struct {
        const Self = @This();

        values: [Set.count]NormalizedValue,

        pub fn init(set: *const Set) Self {
            var self: Self = undefined;
            inline for (0..Set.count) |index| {
                self.values[index] = NormalizedValue.init(set.defaultNormalizedAt(index));
            }
            return self;
        }

        pub fn load(self: *const Self, index: usize) ?f64 {
            if (index >= Set.count) return null;
            return self.values[index].load();
        }

        pub fn loadAt(self: *const Self, comptime index: usize) f64 {
            return self.values[index].load();
        }

        pub fn loadIndex(self: *const Self, index: usize) ?f64 {
            return self.load(index);
        }

        pub fn loadPlain(self: *const Self, set: *const Set, index: usize) ?f64 {
            const normalized = self.load(index) orelse return null;
            return set.plainFromNormalized(index, normalized);
        }

        pub fn loadPlainIndex(self: *const Self, set: *const Set, index: usize) ?f64 {
            return self.loadPlain(set, index);
        }

        pub fn store(self: *Self, index: usize, value: f64) bool {
            return self.storeCount(index, value) != null;
        }

        pub fn storeIndex(self: *Self, index: usize, value: f64) bool {
            return self.store(index, value);
        }

        pub fn storeCount(self: *Self, index: usize, value: f64) ?usize {
            if (index >= Set.count) return null;
            if (!std.math.isFinite(value)) return null;
            const normalized = clampNormalized(value);
            return self.storeNormalizedAt(index, normalized);
        }

        pub fn storeIndexCount(self: *Self, index: usize, value: f64) ?usize {
            return self.storeCount(index, value);
        }

        pub fn storePlain(self: *Self, set: *const Set, index: usize, plain: f64) bool {
            return self.storePlainCount(set, index, plain) != null;
        }

        pub fn storePlainIndex(self: *Self, set: *const Set, index: usize, plain: f64) bool {
            return self.storePlain(set, index, plain);
        }

        pub fn storePlainCount(self: *Self, set: *const Set, index: usize, plain: f64) ?usize {
            if (!std.math.isFinite(plain)) return null;
            const normalized = set.normalizedFromPlain(index, plain) orelse return null;
            return self.storeCount(index, normalized);
        }

        pub fn storePlainIndexCount(self: *Self, set: *const Set, index: usize, plain: f64) ?usize {
            return self.storePlainCount(set, index, plain);
        }

        pub fn copyFrom(self: *Self, source: *const Self) void {
            _ = self.copyFromCount(source);
        }

        pub fn copyFromCount(self: *Self, source: *const Self) usize {
            var changed: usize = 0;
            inline for (0..Set.count) |index| {
                changed += self.storeNormalizedAt(index, source.values[index].load());
            }
            return changed;
        }

        pub fn resetToDefaults(self: *Self, set: *const Set) void {
            _ = self.resetToDefaultsCount(set);
        }

        pub fn resetToDefaultsCount(self: *Self, set: *const Set) usize {
            var changed: usize = 0;
            inline for (0..Set.count) |index| {
                changed += self.storeNormalizedAt(index, set.defaultNormalizedAt(index));
            }
            return changed;
        }

        pub fn resetToDefault(self: *Self, set: *const Set, index: usize) bool {
            return self.resetToDefaultCount(set, index) != null;
        }

        pub fn resetToDefaultIndex(self: *Self, set: *const Set, index: usize) bool {
            return self.resetToDefault(set, index);
        }

        pub fn resetToDefaultCount(self: *Self, set: *const Set, index: usize) ?usize {
            const default = set.defaultNormalized(index) orelse return null;
            return self.storeNormalizedAt(index, default);
        }

        pub fn resetToDefaultIndexCount(self: *Self, set: *const Set, index: usize) ?usize {
            return self.resetToDefaultCount(set, index);
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
            return self.values[set.indexOfField(field_name)].load();
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

        pub fn isDefaultIndex(self: *const Self, set: *const Set, index: usize) ?bool {
            return self.isDefault(set, index);
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
            const index = set.indexOfField(field_name);
            return self.values[index].load() == set.fieldDefaultNormalized(field_name);
        }

        pub fn nonDefaultCount(self: *const Self, set: *const Set) usize {
            var count: usize = 0;
            inline for (0..Set.count) |index| {
                if (self.values[index].load() != set.defaultNormalizedAt(index)) count += 1;
            }
            return count;
        }

        pub fn allDefaults(self: *const Self, set: *const Set) bool {
            return self.nonDefaultCount(set) == 0;
        }

        pub fn hasNonDefaults(self: *const Self, set: *const Set) bool {
            return !self.allDefaults(set);
        }

        pub fn storeById(self: *Self, set: *const Set, id: u32, value: f64) bool {
            return self.storeByIdCount(set, id, value) != null;
        }

        pub fn storeByIdCount(self: *Self, set: *const Set, id: u32, value: f64) ?usize {
            const index = set.indexOfId(id) orelse return null;
            return self.storeCount(index, value);
        }

        pub fn storePlainById(self: *Self, set: *const Set, id: u32, plain: f64) bool {
            return self.storePlainByIdCount(set, id, plain) != null;
        }

        pub fn storePlainByIdCount(self: *Self, set: *const Set, id: u32, plain: f64) ?usize {
            const index = set.indexOfId(id) orelse return null;
            return self.storePlainCount(set, index, plain);
        }

        pub fn storeByName(self: *Self, set: *const Set, name: []const u8, normalized: f64) bool {
            return self.storeByNameCount(set, name, normalized) != null;
        }

        pub fn storeByNameCount(self: *Self, set: *const Set, name: []const u8, normalized: f64) ?usize {
            const index = set.indexOfName(name) orelse return null;
            return self.storeCount(index, normalized);
        }

        pub fn storePlainByName(self: *Self, set: *const Set, name: []const u8, plain: f64) bool {
            return self.storePlainByNameCount(set, name, plain) != null;
        }

        pub fn storePlainByNameCount(self: *Self, set: *const Set, name: []const u8, plain: f64) ?usize {
            const index = set.indexOfName(name) orelse return null;
            return self.storePlainCount(set, index, plain);
        }

        pub fn storeField(self: *Self, set: *const Set, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) bool {
            return self.storeFieldCount(set, field_name, plain) != null;
        }

        pub fn storeFieldCount(self: *Self, set: *const Set, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) ?usize {
            if (comptime @typeInfo(FieldPlainType(Params, field_name)) == .float) {
                if (!std.math.isFinite(plain)) return null;
            }
            const param = set.descriptor(field_name);
            return self.storeCount(set.indexOfField(field_name), param.normalize(plain));
        }

        pub fn storeFieldNormalized(self: *Self, set: *const Set, comptime field_name: []const u8, normalized: f64) bool {
            return self.storeFieldNormalizedCount(set, field_name, normalized) != null;
        }

        pub fn storeFieldNormalizedCount(self: *Self, set: *const Set, comptime field_name: []const u8, normalized: f64) ?usize {
            return self.storeCount(set.indexOfField(field_name), normalized);
        }

        pub fn resetToDefaultById(self: *Self, set: *const Set, id: u32) bool {
            return self.resetToDefaultByIdCount(set, id) != null;
        }

        pub fn resetToDefaultByIdCount(self: *Self, set: *const Set, id: u32) ?usize {
            const index = set.indexOfId(id) orelse return null;
            return self.resetToDefaultCount(set, index);
        }

        pub fn resetToDefaultByName(self: *Self, set: *const Set, name: []const u8) bool {
            return self.resetToDefaultByNameCount(set, name) != null;
        }

        pub fn resetToDefaultByNameCount(self: *Self, set: *const Set, name: []const u8) ?usize {
            const index = set.indexOfName(name) orelse return null;
            return self.resetToDefaultCount(set, index);
        }

        pub fn resetFieldToDefault(self: *Self, set: *const Set, comptime field_name: []const u8) bool {
            return self.resetFieldToDefaultCount(set, field_name) != null;
        }

        pub fn resetFieldToDefaultCount(self: *Self, set: *const Set, comptime field_name: []const u8) ?usize {
            return self.resetToDefaultCount(set, set.indexOfField(field_name));
        }

        const AppliedChange = struct {
            changed: usize,
        };

        fn automatedChangeIndex(_: *Self, set: *const Set, change: process.ParameterChange) ?usize {
            const index = set.indexOfId(change.id) orelse return null;
            const can_automate = set.canAutomate(index) orelse return null;
            const read_only = set.isReadOnly(index) orelse return null;
            if (!can_automate or read_only) return null;
            return index;
        }

        fn applyChange(self: *Self, set: *const Set, change: process.ParameterChange) ?AppliedChange {
            const index = self.automatedChangeIndex(set, change) orelse return null;
            const changed = self.storeCount(index, change.normalized) orelse return null;
            return .{ .changed = changed };
        }

        pub fn applyChangesCount(self: *Self, set: *const Set, changes: process.ParameterChanges) usize {
            var applied: usize = 0;
            for (changes.items) |change| {
                if (self.applyChange(set, change) != null) applied += 1;
            }
            return applied;
        }

        pub fn applyChangesAtOffsetCount(self: *Self, set: *const Set, changes: process.ParameterChanges, sample_offset: usize) usize {
            var applied: usize = 0;
            for (changes.items) |change| {
                if (change.sample_offset != sample_offset) continue;
                if (self.applyChange(set, change) != null) applied += 1;
            }
            return applied;
        }

        pub fn applyChangesChangedCount(self: *Self, set: *const Set, changes: process.ParameterChanges) usize {
            var changed: usize = 0;
            for (changes.items) |change| {
                if (self.applyChange(set, change)) |applied| changed += applied.changed;
            }
            return changed;
        }

        pub fn applyChanges(self: *Self, set: *const Set, changes: process.ParameterChanges) void {
            _ = self.applyChangesCount(set, changes);
        }

        pub fn applyChangesAtOffset(self: *Self, set: *const Set, changes: process.ParameterChanges, sample_offset: usize) void {
            _ = self.applyChangesAtOffsetCount(set, changes, sample_offset);
        }

        fn storeNormalizedAt(self: *Self, index: usize, normalized: f64) usize {
            if (index >= Set.count) return 0;
            const changed: usize = if (self.values[index].load() != normalized) 1 else 0;
            self.values[index].store(normalized);
            return changed;
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

        pub fn duplicateId(self: Self) ?u32 {
            return self.set.duplicateId();
        }

        pub fn duplicateIdIndex(self: Self) ?usize {
            return self.set.duplicateIdIndex();
        }

        pub fn duplicateName(self: Self) ?[]const u8 {
            return self.set.duplicateName();
        }

        pub fn duplicateNameIndex(self: Self) ?usize {
            return self.set.duplicateNameIndex();
        }

        pub fn hasDuplicateIds(self: Self) bool {
            return self.set.hasDuplicateIds();
        }

        pub fn hasDuplicateNames(self: Self) bool {
            return self.set.hasDuplicateNames();
        }

        pub fn firstDescriptorError(self: Self) ?anyerror {
            return self.set.firstDescriptorError();
        }

        pub fn firstDescriptorErrorIndex(self: Self) ?usize {
            return self.set.firstDescriptorErrorIndex();
        }

        pub fn firstDescriptorErrorName(self: Self) ?[]const u8 {
            return self.set.firstDescriptorErrorName();
        }

        pub fn validateUniqueIds(self: Self) !void {
            try self.set.validateUniqueIds();
        }

        pub fn validateUniqueNames(self: Self) !void {
            try self.set.validateUniqueNames();
        }

        pub fn validateDescriptors(self: Self) !void {
            try self.set.validateDescriptors();
        }

        pub fn validate(self: Self) !void {
            try self.set.validate();
        }

        pub fn validateUnitIds(self: Self, unit_set: anytype) !void {
            try self.set.validateUnitIds(unit_set);
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

        pub fn defaultPlain(self: Self, index: usize) ?f64 {
            return self.set.defaultPlain(index);
        }

        pub fn defaultPlainById(self: Self, wanted_id: u32) ?f64 {
            return self.set.defaultPlainById(wanted_id);
        }

        pub fn defaultPlainByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.defaultPlainByName(wanted_name);
        }

        pub fn plainMinimum(self: Self, index: usize) ?f64 {
            return self.set.plainMinimum(index);
        }

        pub fn plainMinimumById(self: Self, wanted_id: u32) ?f64 {
            return self.set.plainMinimumById(wanted_id);
        }

        pub fn plainMinimumByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.plainMinimumByName(wanted_name);
        }

        pub fn plainMaximum(self: Self, index: usize) ?f64 {
            return self.set.plainMaximum(index);
        }

        pub fn plainMaximumById(self: Self, wanted_id: u32) ?f64 {
            return self.set.plainMaximumById(wanted_id);
        }

        pub fn plainMaximumByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.plainMaximumByName(wanted_name);
        }

        pub fn hasPlainRange(self: Self, index: usize) bool {
            return self.set.hasPlainRange(index);
        }

        pub fn hasPlainRangeById(self: Self, wanted_id: u32) bool {
            return self.set.hasPlainRangeById(wanted_id);
        }

        pub fn hasPlainRangeByName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasPlainRangeByName(wanted_name);
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

        pub fn optionCount(self: Self, index: usize) ?usize {
            return self.set.optionCount(index);
        }

        pub fn optionCountById(self: Self, wanted_id: u32) ?usize {
            return self.set.optionCountById(wanted_id);
        }

        pub fn optionCountByName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.optionCountByName(wanted_name);
        }

        pub fn optionLabel(self: Self, index: usize, option_index: usize) ?[]const u8 {
            return self.set.optionLabel(index, option_index);
        }

        pub fn optionLabelById(self: Self, wanted_id: u32, option_index: usize) ?[]const u8 {
            return self.set.optionLabelById(wanted_id, option_index);
        }

        pub fn optionLabelByName(self: Self, wanted_name: []const u8, option_index: usize) ?[]const u8 {
            return self.set.optionLabelByName(wanted_name, option_index);
        }

        pub fn optionNormalized(self: Self, index: usize, option_index: usize) ?f64 {
            return self.set.optionNormalized(index, option_index);
        }

        pub fn optionNormalizedById(self: Self, wanted_id: u32, option_index: usize) ?f64 {
            return self.set.optionNormalizedById(wanted_id, option_index);
        }

        pub fn optionNormalizedByName(self: Self, wanted_name: []const u8, option_index: usize) ?f64 {
            return self.set.optionNormalizedByName(wanted_name, option_index);
        }

        pub fn hasOptions(self: Self, index: usize) bool {
            return self.set.hasOptions(index);
        }

        pub fn optionsEmpty(self: Self, index: usize) bool {
            return self.set.optionsEmpty(index);
        }

        pub fn hasOptionsById(self: Self, wanted_id: u32) bool {
            return self.set.hasOptionsById(wanted_id);
        }

        pub fn optionsEmptyById(self: Self, wanted_id: u32) bool {
            return self.set.optionsEmptyById(wanted_id);
        }

        pub fn hasOptionsByName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasOptionsByName(wanted_name);
        }

        pub fn optionsEmptyByName(self: Self, wanted_name: []const u8) bool {
            return self.set.optionsEmptyByName(wanted_name);
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

        pub fn fieldDefaultPlain(self: Self, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            return self.set.fieldDefaultPlain(field_name);
        }

        pub fn fieldPlainMinimum(self: Self, comptime field_name: []const u8) ?f64 {
            return self.set.fieldPlainMinimum(field_name);
        }

        pub fn fieldPlainMaximum(self: Self, comptime field_name: []const u8) ?f64 {
            return self.set.fieldPlainMaximum(field_name);
        }

        pub fn fieldHasPlainRange(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldHasPlainRange(field_name);
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

        pub fn fieldOptionCount(self: Self, comptime field_name: []const u8) ?usize {
            return self.set.fieldOptionCount(field_name);
        }

        pub fn fieldOptionLabel(self: Self, comptime field_name: []const u8, option_index: usize) ?[]const u8 {
            return self.set.fieldOptionLabel(field_name, option_index);
        }

        pub fn fieldOptionNormalized(self: Self, comptime field_name: []const u8, option_index: usize) ?f64 {
            return self.set.fieldOptionNormalized(field_name, option_index);
        }

        pub fn fieldHasOptions(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldHasOptions(field_name);
        }

        pub fn fieldOptionsEmpty(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldOptionsEmpty(field_name);
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

        pub fn parameterChangeNormalizedById(self: Self, wanted_id: u32, sample_offset: usize, normalized: f64) ?process.ParameterChange {
            return self.set.parameterChangeNormalizedById(wanted_id, sample_offset, normalized);
        }

        pub fn parameterChangePlainById(self: Self, wanted_id: u32, sample_offset: usize, plain: f64) ?process.ParameterChange {
            return self.set.parameterChangePlainById(wanted_id, sample_offset, plain);
        }

        pub fn parameterChangeNormalizedByName(self: Self, wanted_name: []const u8, sample_offset: usize, normalized: f64) ?process.ParameterChange {
            return self.set.parameterChangeNormalizedByName(wanted_name, sample_offset, normalized);
        }

        pub fn parameterChangePlainByName(self: Self, wanted_name: []const u8, sample_offset: usize, plain: f64) ?process.ParameterChange {
            return self.set.parameterChangePlainByName(wanted_name, sample_offset, plain);
        }

        pub fn formatPlain(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.formatPlainIndex(index, normalized, buffer);
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

        pub fn parsePlain(self: Self, index: usize, text: []const u8) !f64 {
            return self.parsePlainIndex(index, text);
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

        pub fn plainFromNormalized(self: Self, index: usize, normalized: f64) ?f64 {
            return self.plainFromNormalizedIndex(index, normalized);
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

        pub fn normalizedFromPlain(self: Self, index: usize, plain: f64) ?f64 {
            return self.normalizedFromPlainIndex(index, plain);
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

        pub fn loadPlain(self: Self, index: usize) ?f64 {
            return self.loadPlainIndex(index);
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

        pub fn nonDefaultCount(self: Self) usize {
            return self.values.nonDefaultCount(self.set);
        }

        pub fn allDefaults(self: Self) bool {
            return self.values.allDefaults(self.set);
        }

        pub fn hasNonDefaults(self: Self) bool {
            return self.values.hasNonDefaults(self.set);
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

        pub fn copyFrom(self: Self, source: ParameterView(Params)) void {
            self.values.copyFrom(source.values);
        }

        pub fn copyFromCount(self: Self, source: ParameterView(Params)) usize {
            return self.values.copyFromCount(source.values);
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

        pub fn duplicateId(self: Self) ?u32 {
            return self.set.duplicateId();
        }

        pub fn duplicateIdIndex(self: Self) ?usize {
            return self.set.duplicateIdIndex();
        }

        pub fn duplicateName(self: Self) ?[]const u8 {
            return self.set.duplicateName();
        }

        pub fn duplicateNameIndex(self: Self) ?usize {
            return self.set.duplicateNameIndex();
        }

        pub fn hasDuplicateIds(self: Self) bool {
            return self.set.hasDuplicateIds();
        }

        pub fn hasDuplicateNames(self: Self) bool {
            return self.set.hasDuplicateNames();
        }

        pub fn firstDescriptorError(self: Self) ?anyerror {
            return self.set.firstDescriptorError();
        }

        pub fn firstDescriptorErrorIndex(self: Self) ?usize {
            return self.set.firstDescriptorErrorIndex();
        }

        pub fn firstDescriptorErrorName(self: Self) ?[]const u8 {
            return self.set.firstDescriptorErrorName();
        }

        pub fn validateUniqueIds(self: Self) !void {
            try self.set.validateUniqueIds();
        }

        pub fn validateUniqueNames(self: Self) !void {
            try self.set.validateUniqueNames();
        }

        pub fn validateDescriptors(self: Self) !void {
            try self.set.validateDescriptors();
        }

        pub fn validate(self: Self) !void {
            try self.set.validate();
        }

        pub fn validateUnitIds(self: Self, unit_set: anytype) !void {
            try self.set.validateUnitIds(unit_set);
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

        pub fn defaultPlain(self: Self, index: usize) ?f64 {
            return self.set.defaultPlain(index);
        }

        pub fn defaultPlainById(self: Self, wanted_id: u32) ?f64 {
            return self.set.defaultPlainById(wanted_id);
        }

        pub fn defaultPlainByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.defaultPlainByName(wanted_name);
        }

        pub fn plainMinimum(self: Self, index: usize) ?f64 {
            return self.set.plainMinimum(index);
        }

        pub fn plainMinimumById(self: Self, wanted_id: u32) ?f64 {
            return self.set.plainMinimumById(wanted_id);
        }

        pub fn plainMinimumByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.plainMinimumByName(wanted_name);
        }

        pub fn plainMaximum(self: Self, index: usize) ?f64 {
            return self.set.plainMaximum(index);
        }

        pub fn plainMaximumById(self: Self, wanted_id: u32) ?f64 {
            return self.set.plainMaximumById(wanted_id);
        }

        pub fn plainMaximumByName(self: Self, wanted_name: []const u8) ?f64 {
            return self.set.plainMaximumByName(wanted_name);
        }

        pub fn hasPlainRange(self: Self, index: usize) bool {
            return self.set.hasPlainRange(index);
        }

        pub fn hasPlainRangeById(self: Self, wanted_id: u32) bool {
            return self.set.hasPlainRangeById(wanted_id);
        }

        pub fn hasPlainRangeByName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasPlainRangeByName(wanted_name);
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

        pub fn optionCount(self: Self, index: usize) ?usize {
            return self.set.optionCount(index);
        }

        pub fn optionCountById(self: Self, wanted_id: u32) ?usize {
            return self.set.optionCountById(wanted_id);
        }

        pub fn optionCountByName(self: Self, wanted_name: []const u8) ?usize {
            return self.set.optionCountByName(wanted_name);
        }

        pub fn optionLabel(self: Self, index: usize, option_index: usize) ?[]const u8 {
            return self.set.optionLabel(index, option_index);
        }

        pub fn optionLabelById(self: Self, wanted_id: u32, option_index: usize) ?[]const u8 {
            return self.set.optionLabelById(wanted_id, option_index);
        }

        pub fn optionLabelByName(self: Self, wanted_name: []const u8, option_index: usize) ?[]const u8 {
            return self.set.optionLabelByName(wanted_name, option_index);
        }

        pub fn optionNormalized(self: Self, index: usize, option_index: usize) ?f64 {
            return self.set.optionNormalized(index, option_index);
        }

        pub fn optionNormalizedById(self: Self, wanted_id: u32, option_index: usize) ?f64 {
            return self.set.optionNormalizedById(wanted_id, option_index);
        }

        pub fn optionNormalizedByName(self: Self, wanted_name: []const u8, option_index: usize) ?f64 {
            return self.set.optionNormalizedByName(wanted_name, option_index);
        }

        pub fn hasOptions(self: Self, index: usize) bool {
            return self.set.hasOptions(index);
        }

        pub fn optionsEmpty(self: Self, index: usize) bool {
            return self.set.optionsEmpty(index);
        }

        pub fn hasOptionsById(self: Self, wanted_id: u32) bool {
            return self.set.hasOptionsById(wanted_id);
        }

        pub fn optionsEmptyById(self: Self, wanted_id: u32) bool {
            return self.set.optionsEmptyById(wanted_id);
        }

        pub fn hasOptionsByName(self: Self, wanted_name: []const u8) bool {
            return self.set.hasOptionsByName(wanted_name);
        }

        pub fn optionsEmptyByName(self: Self, wanted_name: []const u8) bool {
            return self.set.optionsEmptyByName(wanted_name);
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

        pub fn fieldDefaultPlain(self: Self, comptime field_name: []const u8) FieldPlainType(Params, field_name) {
            return self.set.fieldDefaultPlain(field_name);
        }

        pub fn fieldPlainMinimum(self: Self, comptime field_name: []const u8) ?f64 {
            return self.set.fieldPlainMinimum(field_name);
        }

        pub fn fieldPlainMaximum(self: Self, comptime field_name: []const u8) ?f64 {
            return self.set.fieldPlainMaximum(field_name);
        }

        pub fn fieldHasPlainRange(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldHasPlainRange(field_name);
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

        pub fn fieldOptionCount(self: Self, comptime field_name: []const u8) ?usize {
            return self.set.fieldOptionCount(field_name);
        }

        pub fn fieldOptionLabel(self: Self, comptime field_name: []const u8, option_index: usize) ?[]const u8 {
            return self.set.fieldOptionLabel(field_name, option_index);
        }

        pub fn fieldOptionNormalized(self: Self, comptime field_name: []const u8, option_index: usize) ?f64 {
            return self.set.fieldOptionNormalized(field_name, option_index);
        }

        pub fn fieldHasOptions(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldHasOptions(field_name);
        }

        pub fn fieldOptionsEmpty(self: Self, comptime field_name: []const u8) bool {
            return self.set.fieldOptionsEmpty(field_name);
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

        pub fn parameterChangeNormalizedById(self: Self, wanted_id: u32, sample_offset: usize, normalized: f64) ?process.ParameterChange {
            return self.set.parameterChangeNormalizedById(wanted_id, sample_offset, normalized);
        }

        pub fn parameterChangePlainById(self: Self, wanted_id: u32, sample_offset: usize, plain: f64) ?process.ParameterChange {
            return self.set.parameterChangePlainById(wanted_id, sample_offset, plain);
        }

        pub fn parameterChangeNormalizedByName(self: Self, wanted_name: []const u8, sample_offset: usize, normalized: f64) ?process.ParameterChange {
            return self.set.parameterChangeNormalizedByName(wanted_name, sample_offset, normalized);
        }

        pub fn parameterChangePlainByName(self: Self, wanted_name: []const u8, sample_offset: usize, plain: f64) ?process.ParameterChange {
            return self.set.parameterChangePlainByName(wanted_name, sample_offset, plain);
        }

        pub fn formatPlain(self: Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.formatPlainIndex(index, normalized, buffer);
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

        pub fn parsePlain(self: Self, index: usize, text: []const u8) !f64 {
            return self.parsePlainIndex(index, text);
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

        pub fn plainFromNormalized(self: Self, index: usize, normalized: f64) ?f64 {
            return self.plainFromNormalizedIndex(index, normalized);
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

        pub fn normalizedFromPlain(self: Self, index: usize, plain: f64) ?f64 {
            return self.normalizedFromPlainIndex(index, plain);
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

        pub fn resetToDefaultsCount(self: Self) usize {
            return self.values.resetToDefaultsCount(self.set);
        }

        pub fn resetToDefaultIndex(self: Self, index: usize) bool {
            return self.values.resetToDefault(self.set, index);
        }

        pub fn resetToDefaultIndexCount(self: Self, index: usize) ?usize {
            return self.values.resetToDefaultCount(self.set, index);
        }

        pub fn resetToDefaultById(self: Self, wanted_id: u32) bool {
            return self.values.resetToDefaultById(self.set, wanted_id);
        }

        pub fn resetToDefaultByIdCount(self: Self, wanted_id: u32) ?usize {
            return self.values.resetToDefaultByIdCount(self.set, wanted_id);
        }

        pub fn resetToDefaultByName(self: Self, wanted_name: []const u8) bool {
            return self.values.resetToDefaultByName(self.set, wanted_name);
        }

        pub fn resetToDefaultByNameCount(self: Self, wanted_name: []const u8) ?usize {
            return self.values.resetToDefaultByNameCount(self.set, wanted_name);
        }

        pub fn resetToDefault(self: Self, comptime field_name: []const u8) bool {
            return self.values.resetFieldToDefault(self.set, field_name);
        }

        pub fn resetToDefaultCount(self: Self, comptime field_name: []const u8) ?usize {
            return self.values.resetFieldToDefaultCount(self.set, field_name);
        }

        pub fn applyChangesCount(self: Self, changes: process.ParameterChanges) usize {
            return self.values.applyChangesCount(self.set, changes);
        }

        pub fn applyChangesChangedCount(self: Self, changes: process.ParameterChanges) usize {
            return self.values.applyChangesChangedCount(self.set, changes);
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

        pub fn loadPlain(self: Self, index: usize) ?f64 {
            return self.loadPlainIndex(index);
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

        pub fn nonDefaultCount(self: Self) usize {
            return self.values.nonDefaultCount(self.set);
        }

        pub fn allDefaults(self: Self) bool {
            return self.values.allDefaults(self.set);
        }

        pub fn hasNonDefaults(self: Self) bool {
            return self.values.hasNonDefaults(self.set);
        }

        pub fn storeNormalized(self: Self, comptime field_name: []const u8, normalized: f64) bool {
            return self.values.storeFieldNormalized(self.set, field_name, normalized);
        }

        pub fn storeNormalizedCount(self: Self, comptime field_name: []const u8, normalized: f64) ?usize {
            return self.values.storeFieldNormalizedCount(self.set, field_name, normalized);
        }

        pub fn store(self: Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) bool {
            return self.values.storeField(self.set, field_name, plain);
        }

        pub fn storeCount(self: Self, comptime field_name: []const u8, plain: FieldPlainType(Params, field_name)) ?usize {
            return self.values.storeFieldCount(self.set, field_name, plain);
        }

        pub fn storeIndex(self: Self, index: usize, normalized: f64) bool {
            return self.values.store(index, normalized);
        }

        pub fn storeIndexCount(self: Self, index: usize, normalized: f64) ?usize {
            return self.values.storeCount(index, normalized);
        }

        pub fn storePlain(self: Self, index: usize, plain: f64) bool {
            return self.storePlainIndex(index, plain);
        }

        pub fn storePlainCount(self: Self, index: usize, plain: f64) ?usize {
            return self.storePlainIndexCount(index, plain);
        }

        pub fn storePlainIndex(self: Self, index: usize, plain: f64) bool {
            return self.values.storePlain(self.set, index, plain);
        }

        pub fn storePlainIndexCount(self: Self, index: usize, plain: f64) ?usize {
            return self.values.storePlainCount(self.set, index, plain);
        }

        pub fn storeById(self: Self, wanted_id: u32, normalized: f64) bool {
            return self.values.storeById(self.set, wanted_id, normalized);
        }

        pub fn storeByIdCount(self: Self, wanted_id: u32, normalized: f64) ?usize {
            return self.values.storeByIdCount(self.set, wanted_id, normalized);
        }

        pub fn storePlainById(self: Self, wanted_id: u32, plain: f64) bool {
            return self.values.storePlainById(self.set, wanted_id, plain);
        }

        pub fn storePlainByIdCount(self: Self, wanted_id: u32, plain: f64) ?usize {
            return self.values.storePlainByIdCount(self.set, wanted_id, plain);
        }

        pub fn storeByName(self: Self, wanted_name: []const u8, normalized: f64) bool {
            return self.values.storeByName(self.set, wanted_name, normalized);
        }

        pub fn storeByNameCount(self: Self, wanted_name: []const u8, normalized: f64) ?usize {
            return self.values.storeByNameCount(self.set, wanted_name, normalized);
        }

        pub fn storePlainByName(self: Self, wanted_name: []const u8, plain: f64) bool {
            return self.values.storePlainByName(self.set, wanted_name, plain);
        }

        pub fn storePlainByNameCount(self: Self, wanted_name: []const u8, plain: f64) ?usize {
            return self.values.storePlainByNameCount(self.set, wanted_name, plain);
        }
    };
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

    try std.testing.expectEqual(
        @as(usize, 0),
        values.storeNormalizedAt(Set.count, 0.5),
    );
    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(f64, 0.25), values.loadAt(0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadAt(1));
    try std.testing.expectEqual(@as(?f64, null), values.load(2));
    try std.testing.expect(values.store(0, 2.0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(0));
    try std.testing.expectEqual(@as(?usize, 0), values.storeCount(0, 2.0));
    try std.testing.expectEqual(@as(?usize, 1), values.storeCount(0, 0.75));
    try std.testing.expectEqual(@as(?usize, null), values.storeCount(2, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storeCount(0, std.math.nan(f64)));
    try std.testing.expectEqual(@as(?f64, 0.75), values.load(0));
    try std.testing.expect(!values.store(0, std.math.nan(f64)));
    try std.testing.expectEqual(@as(?f64, 0.75), values.load(0));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadIndex(0));
    try std.testing.expect(!values.storeById(&set, 0, std.math.inf(f64)));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expect(!values.store(2, 0.5));
    try std.testing.expect(!values.storeIndex(2, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storeIndexCount(2, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storeByIdCount(&set, 0, 0.75));
    try std.testing.expect(values.storeById(&set, 0, 0.75));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?usize, null), values.storeByIdCount(&set, 99, 0.5));
    try std.testing.expect(!values.storeById(&set, 99, 0.5));
    try std.testing.expectEqual(@as(?f64, null), values.loadById(&set, 99));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadPlain(&set, 0));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadPlainIndex(&set, 0));
    try std.testing.expectEqual(@as(?usize, 1), values.storePlainCount(&set, 0, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storePlainIndexCount(&set, 0, 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storePlainCount(&set, 0, 0.5));
    try std.testing.expect(values.storePlain(&set, 0, 0.5));
    try std.testing.expect(values.storePlainIndex(&set, 0, 0.5));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadPlain(&set, 0));
    try std.testing.expectEqual(@as(?f64, null), values.loadPlain(&set, 99));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainCount(&set, 99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainIndexCount(&set, 99, 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainCount(&set, 0, std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainIndexCount(&set, 0, -std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainByIdCount(&set, 0, std.math.nan(f64)));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainByNameCount(&set, "Gain", std.math.inf(f64)));
    try std.testing.expect(!values.storePlain(&set, 99, 0.5));
    try std.testing.expect(!values.storePlainIndex(&set, 99, 0.5));
    try std.testing.expect(!values.storePlain(&set, 0, std.math.nan(f64)));
    try std.testing.expect(!values.storePlainIndex(&set, 0, std.math.inf(f64)));
    try std.testing.expect(!values.storePlainById(&set, 0, -std.math.inf(f64)));
    try std.testing.expect(!values.storePlainByName(&set, "Gain", std.math.nan(f64)));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadPlain(&set, 0));

    var copied = Values.init(&set);
    try std.testing.expectEqual(@as(usize, 1), copied.copyFromCount(&values));
    try std.testing.expectEqual(@as(usize, 0), copied.copyFromCount(&values));
    copied.resetToDefaults(&set);
    copied.copyFrom(&values);
    try std.testing.expectEqual(@as(?f64, 0.5), copied.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), copied.load(1));

    try std.testing.expectEqual(@as(usize, 1), values.resetToDefaultsCount(&set));
    try std.testing.expectEqual(@as(usize, 0), values.resetToDefaultsCount(&set));
    try std.testing.expect(values.store(0, 0.5));
    values.resetToDefaults(&set);
    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expect(values.store(0, 1.0));
    try std.testing.expect(values.store(1, 0.0));
    try std.testing.expectEqual(@as(?usize, 1), values.resetToDefaultCount(&set, 0));
    try std.testing.expectEqual(@as(?usize, 0), values.resetToDefaultIndexCount(&set, 0));
    try std.testing.expectEqual(@as(?usize, 0), values.resetToDefaultCount(&set, 0));
    try std.testing.expect(values.storeIndex(0, 1.0));
    try std.testing.expect(values.resetToDefaultIndex(&set, 0));
    try std.testing.expectEqual(@as(?f64, 0.25), values.load(0));
    try std.testing.expectEqual(@as(?f64, 0.0), values.load(1));
    try std.testing.expectEqual(@as(?usize, 1), values.resetToDefaultByIdCount(&set, 1));
    try std.testing.expectEqual(@as(?usize, 0), values.resetToDefaultByIdCount(&set, 1));
    try std.testing.expect(values.store(1, 0.0));
    try std.testing.expect(values.resetToDefaultById(&set, 1));
    try std.testing.expectEqual(@as(?f64, 1.0), values.load(1));
    try std.testing.expectEqual(@as(?usize, null), values.resetToDefaultCount(&set, 99));
    try std.testing.expectEqual(@as(?usize, null), values.resetToDefaultIndexCount(&set, 99));
    try std.testing.expectEqual(@as(?usize, null), values.resetToDefaultByIdCount(&set, 99));
    try std.testing.expect(!values.resetToDefault(&set, 99));
    try std.testing.expect(!values.resetToDefaultIndex(&set, 99));
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
    try std.testing.expectEqual(@as(?usize, 0), values.storePlainByIdCount(&set, 0, 6.0));
    try std.testing.expectEqual(@as(?usize, 1), values.storeByNameCount(&set, "Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 0), values.storeByNameCount(&set, "Gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), values.storePlainByNameCount(&set, "Gain", 6.0));
    try std.testing.expectEqual(@as(?usize, 0), values.storePlainByNameCount(&set, "Gain", 6.0));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainByIdCount(&set, 99, 6.0));
    try std.testing.expectEqual(@as(?usize, null), values.storeByNameCount(&set, "Missing", 0.5));
    try std.testing.expectEqual(@as(?usize, null), values.storePlainByNameCount(&set, "Missing", 6.0));

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
    try std.testing.expect(values.allDefaults(&set));
    try std.testing.expect(!values.hasNonDefaults(&set));
    try std.testing.expectEqual(@as(usize, 0), values.nonDefaultCount(&set));
    try std.testing.expectEqual(@as(?bool, true), values.isDefault(&set, 0));
    try std.testing.expectEqual(@as(?bool, true), values.isDefaultIndex(&set, 0));
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
    try std.testing.expect(!values.allDefaults(&set));
    try std.testing.expect(values.hasNonDefaults(&set));
    try std.testing.expectEqual(@as(usize, 4), values.nonDefaultCount(&set));
    try std.testing.expectEqual(@as(?bool, false), values.isDefault(&set, 0));
    try std.testing.expectEqual(@as(?bool, false), values.isDefaultIndex(&set, 0));
    try std.testing.expectEqual(@as(?bool, false), values.isDefaultById(&set, 3));
    try std.testing.expectEqual(@as(?bool, false), values.isDefaultByName(&set, "Mode"));
    try std.testing.expect(!values.fieldIsDefault(&set, "mode"));
    try std.testing.expect(values.storeFieldNormalized(&set, "mode", 0.0));
    try std.testing.expectEqual(Mode.clean, values.loadField(&set, "mode"));
    try std.testing.expect(values.fieldIsDefault(&set, "mode"));
    try std.testing.expectEqual(@as(usize, 3), values.nonDefaultCount(&set));
    try std.testing.expectEqual(@as(?bool, null), values.isDefault(&set, 99));
    try std.testing.expectEqual(@as(?bool, null), values.isDefaultById(&set, 99));
    try std.testing.expectEqual(@as(?bool, null), values.isDefaultByName(&set, "Missing"));
}

test "parameter view binds reflected set and values" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: FloatParam = .{ .id = 0, .name = "Gain", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
        voices: IntParam = .{ .id = 1, .name = "Voices", .short_name = "Vox", .min = 1, .max = 4, .default = 1, .can_automate = false, .is_read_only = true, .unit_id = 2 },
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
    try std.testing.expectEqual(@as(?u32, null), view.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), view.duplicateIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), view.duplicateName());
    try std.testing.expectEqual(@as(?usize, null), view.duplicateNameIndex());
    try std.testing.expect(!view.hasDuplicateIds());
    try std.testing.expect(!view.hasDuplicateNames());
    try std.testing.expectEqual(@as(?anyerror, null), view.firstDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), view.firstDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), view.firstDescriptorErrorName());
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
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.defaultPlainById(1));
    try std.testing.expectEqual(@as(?f64, 0.0), view.defaultPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), view.defaultPlain(99));
    try std.testing.expectEqual(@as(?f64, null), view.defaultPlainById(99));
    try std.testing.expectEqual(@as(?f64, null), view.defaultPlainByName("Missing"));
    try std.testing.expectEqual(@as(?f64, -12.0), view.plainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 4.0), view.plainMaximumById(1));
    try std.testing.expectEqual(@as(?f64, 1.0), view.plainMinimumByName("Voices"));
    try std.testing.expectEqual(@as(?f64, null), view.plainMaximum(2));
    try std.testing.expectEqual(@as(?f64, null), view.plainMinimumById(99));
    try std.testing.expectEqual(@as(?f64, null), view.plainMaximumByName("Missing"));
    try std.testing.expect(view.hasPlainRange(0));
    try std.testing.expect(view.hasPlainRangeById(1));
    try std.testing.expect(view.hasPlainRangeByName("Voices"));
    try std.testing.expect(!view.hasPlainRange(2));
    try std.testing.expect(!view.hasPlainRangeById(99));
    try std.testing.expect(!view.hasPlainRangeByName("Missing"));
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
    try std.testing.expectEqual(@as(?usize, 3), view.optionCount(3));
    try std.testing.expectEqual(@as(?usize, 3), view.optionCountById(3));
    try std.testing.expectEqual(@as(?usize, 3), view.optionCountByName("Mode"));
    try std.testing.expectEqualStrings("mute", view.optionLabel(3, 2).?);
    try std.testing.expectEqualStrings("boost", view.optionLabelById(3, 1).?);
    try std.testing.expectEqualStrings("clean", view.optionLabelByName("Mode", 0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), view.optionNormalized(3, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), view.optionNormalizedById(3, 1));
    try std.testing.expectEqual(@as(?f64, 0.0), view.optionNormalizedByName("Mode", 0));
    try std.testing.expect(view.hasOptions(3));
    try std.testing.expect(!view.optionsEmpty(3));
    try std.testing.expect(view.hasOptionsById(3));
    try std.testing.expect(!view.optionsEmptyById(3));
    try std.testing.expect(view.hasOptionsByName("Mode"));
    try std.testing.expect(!view.optionsEmptyByName("Mode"));
    try std.testing.expect(!view.hasOptions(0));
    try std.testing.expect(view.optionsEmpty(0));
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
    try std.testing.expectEqual(@as(?usize, null), view.optionCount(2));
    try std.testing.expectEqual(@as(?usize, null), view.optionCountById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), view.optionLabel(3, 3));
    try std.testing.expectEqual(@as(?[]const u8, null), view.optionLabelByName("Missing", 0));
    try std.testing.expectEqual(@as(?f64, null), view.optionNormalized(3, 3));
    try std.testing.expect(!view.hasOptionsById(99));
    try std.testing.expect(view.optionsEmptyById(99));
    try std.testing.expect(!view.hasOptionsByName("Missing"));
    try std.testing.expect(view.optionsEmptyByName("Missing"));
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
    try std.testing.expectEqual(@as(f64, 0.0), view.fieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(i64, 1), view.fieldDefaultPlain("voices"));
    try std.testing.expectEqual(Mode.clean, view.fieldDefaultPlain("mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), view.fieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 4.0), view.fieldPlainMaximum("voices"));
    try std.testing.expectEqual(@as(?f64, null), view.fieldPlainMinimum("bypass"));
    try std.testing.expect(view.fieldHasPlainRange("gain"));
    try std.testing.expect(!view.fieldHasPlainRange("bypass"));
    try std.testing.expect(!view.fieldIsBypass("gain"));
    try std.testing.expect(view.fieldCanAutomate("gain"));
    try std.testing.expect(!view.fieldCanAutomate("voices"));
    try std.testing.expect(view.fieldIsReadOnly("voices"));
    try std.testing.expectEqual(@as(i32, 0), view.fieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), view.fieldStepCount("mode"));
    try std.testing.expect(view.fieldIsList("mode"));
    try std.testing.expectEqual(@as(?usize, 3), view.fieldOptionCount("mode"));
    try std.testing.expectEqualStrings("boost", view.fieldOptionLabel("mode", 1).?);
    try std.testing.expectEqual(@as(?f64, 1.0), view.fieldOptionNormalized("mode", 2));
    try std.testing.expectEqual(@as(?usize, null), view.fieldOptionCount("gain"));
    try std.testing.expect(view.fieldHasOptions("mode"));
    try std.testing.expect(!view.fieldOptionsEmpty("mode"));
    try std.testing.expect(!view.fieldHasOptions("gain"));
    try std.testing.expect(view.fieldOptionsEmpty("gain"));
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
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 6,
        .normalized = 0.5,
    }, view.parameterChangeNormalizedById(0, 6, 0.5).?);
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 7,
        .normalized = 1.0,
    }, view.parameterChangePlainByName("Gain", 7, 6.0).?);
    try std.testing.expectEqual(@as(?process.ParameterChange, null), view.parameterChangeNormalizedByName("Missing", 0, 0.5));
    try std.testing.expectEqual(@as(?process.ParameterChange, null), view.parameterChangePlainById(99, 0, 6.0));
    try std.testing.expectEqualStrings("4", try view.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqualStrings("4", try view.formatPlain(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(f64, 1.0), try view.parsePlain(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 2.0), view.plainFromNormalized(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqual(@as(?f64, 1.0), view.normalizedFromPlain(3, 2.0));
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
    try std.testing.expectEqual(@as(?f64, 2.0), view.loadPlain(3));
    try std.testing.expectEqual(@as(?f64, 2.0), view.loadPlainIndex(3));
    try std.testing.expectEqual(@as(?f64, null), view.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), view.loadPlain(99));
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
        voices: IntParam = .{ .id = 1, .name = "Voices", .short_name = "Vox", .min = 1, .max = 4, .default = 1, .can_automate = false, .is_read_only = true, .unit_id = 2 },
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
    try std.testing.expectEqual(@as(?u32, null), editor.duplicateId());
    try std.testing.expectEqual(@as(?usize, null), editor.duplicateIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), editor.duplicateName());
    try std.testing.expectEqual(@as(?usize, null), editor.duplicateNameIndex());
    try std.testing.expect(!editor.hasDuplicateIds());
    try std.testing.expect(!editor.hasDuplicateNames());
    try std.testing.expectEqual(@as(?anyerror, null), editor.firstDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), editor.firstDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), editor.firstDescriptorErrorName());
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
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.defaultPlainById(1));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), editor.defaultPlain(99));
    try std.testing.expectEqual(@as(?f64, null), editor.defaultPlainById(99));
    try std.testing.expectEqual(@as(?f64, null), editor.defaultPlainByName("Missing"));
    try std.testing.expectEqual(@as(?f64, -12.0), editor.plainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 4.0), editor.plainMaximumById(1));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.plainMinimumByName("Voices"));
    try std.testing.expectEqual(@as(?f64, null), editor.plainMaximum(2));
    try std.testing.expectEqual(@as(?f64, null), editor.plainMinimumById(99));
    try std.testing.expectEqual(@as(?f64, null), editor.plainMaximumByName("Missing"));
    try std.testing.expect(editor.hasPlainRange(0));
    try std.testing.expect(editor.hasPlainRangeById(1));
    try std.testing.expect(editor.hasPlainRangeByName("Voices"));
    try std.testing.expect(!editor.hasPlainRange(2));
    try std.testing.expect(!editor.hasPlainRangeById(99));
    try std.testing.expect(!editor.hasPlainRangeByName("Missing"));
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
    try std.testing.expectEqual(@as(?usize, 3), editor.optionCount(3));
    try std.testing.expectEqual(@as(?usize, 3), editor.optionCountById(3));
    try std.testing.expectEqual(@as(?usize, 3), editor.optionCountByName("Mode"));
    try std.testing.expectEqualStrings("mute", editor.optionLabel(3, 2).?);
    try std.testing.expectEqualStrings("boost", editor.optionLabelById(3, 1).?);
    try std.testing.expectEqualStrings("clean", editor.optionLabelByName("Mode", 0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), editor.optionNormalized(3, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), editor.optionNormalizedById(3, 1));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.optionNormalizedByName("Mode", 0));
    try std.testing.expect(editor.hasOptions(3));
    try std.testing.expect(!editor.optionsEmpty(3));
    try std.testing.expect(editor.hasOptionsById(3));
    try std.testing.expect(!editor.optionsEmptyById(3));
    try std.testing.expect(editor.hasOptionsByName("Mode"));
    try std.testing.expect(!editor.optionsEmptyByName("Mode"));
    try std.testing.expect(!editor.hasOptions(0));
    try std.testing.expect(editor.optionsEmpty(0));
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
    try std.testing.expectEqual(@as(?usize, null), editor.optionCount(2));
    try std.testing.expectEqual(@as(?usize, null), editor.optionCountById(99));
    try std.testing.expectEqual(@as(?[]const u8, null), editor.optionLabel(3, 3));
    try std.testing.expectEqual(@as(?[]const u8, null), editor.optionLabelByName("Missing", 0));
    try std.testing.expectEqual(@as(?f64, null), editor.optionNormalized(3, 3));
    try std.testing.expect(!editor.hasOptionsById(99));
    try std.testing.expect(editor.optionsEmptyById(99));
    try std.testing.expect(!editor.hasOptionsByName("Missing"));
    try std.testing.expect(editor.optionsEmptyByName("Missing"));
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
    try std.testing.expectEqual(@as(f64, 0.0), editor.fieldDefaultPlain("gain"));
    try std.testing.expectEqual(@as(i64, 1), editor.fieldDefaultPlain("voices"));
    try std.testing.expectEqual(Mode.clean, editor.fieldDefaultPlain("mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), editor.fieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 4.0), editor.fieldPlainMaximum("voices"));
    try std.testing.expectEqual(@as(?f64, null), editor.fieldPlainMinimum("bypass"));
    try std.testing.expect(editor.fieldHasPlainRange("gain"));
    try std.testing.expect(!editor.fieldHasPlainRange("bypass"));
    try std.testing.expect(!editor.fieldIsBypass("gain"));
    try std.testing.expect(editor.fieldCanAutomate("gain"));
    try std.testing.expect(!editor.fieldCanAutomate("voices"));
    try std.testing.expect(editor.fieldIsReadOnly("voices"));
    try std.testing.expectEqual(@as(i32, 0), editor.fieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), editor.fieldStepCount("mode"));
    try std.testing.expect(editor.fieldIsList("mode"));
    try std.testing.expectEqual(@as(?usize, 3), editor.fieldOptionCount("mode"));
    try std.testing.expectEqualStrings("boost", editor.fieldOptionLabel("mode", 1).?);
    try std.testing.expectEqual(@as(?f64, 1.0), editor.fieldOptionNormalized("mode", 2));
    try std.testing.expectEqual(@as(?usize, null), editor.fieldOptionCount("gain"));
    try std.testing.expect(editor.fieldHasOptions("mode"));
    try std.testing.expect(!editor.fieldOptionsEmpty("mode"));
    try std.testing.expect(!editor.fieldHasOptions("gain"));
    try std.testing.expect(editor.fieldOptionsEmpty("gain"));
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
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 6,
        .normalized = 0.5,
    }, editor.parameterChangeNormalizedById(0, 6, 0.5).?);
    try std.testing.expectEqual(process.ParameterChange{
        .id = 0,
        .sample_offset = 7,
        .normalized = 1.0,
    }, editor.parameterChangePlainByName("Gain", 7, 6.0).?);
    try std.testing.expectEqual(@as(?process.ParameterChange, null), editor.parameterChangeNormalizedByName("Missing", 0, 0.5));
    try std.testing.expectEqual(@as(?process.ParameterChange, null), editor.parameterChangePlainById(99, 0, 6.0));
    try std.testing.expectEqualStrings("4", try editor.formatPlainIndex(1, 1.0, &buffer));
    try std.testing.expectEqualStrings("4", try editor.formatPlain(1, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainIndex(1, "4"));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlain(1, "4"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedIndex(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalized(3, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainIndex(3, 2.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlain(3, 2.0));
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
    try std.testing.expect(editor.storePlain(1, 2.0));
    try std.testing.expect(editor.storePlainIndex(1, 2.0));
    try std.testing.expect(editor.storeById(2, 0.0));
    try std.testing.expect(editor.storePlainById(1, 3.0));
    try std.testing.expect(editor.storeByName("Gain", 0.75));
    try std.testing.expect(editor.storePlainByName("Voices", 4.0));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultById(3));
    try std.testing.expectEqual(@as(?bool, false), editor.isDefaultByName("Mode"));
    try std.testing.expect(!editor.isDefault("mode"));
    try std.testing.expect(!editor.allDefaults());
    try std.testing.expect(editor.hasNonDefaults());
    try std.testing.expectEqual(@as(usize, 3), editor.nonDefaultCount());
    try std.testing.expect(!editor.storeNormalized("gain", std.math.nan(f64)));
    try std.testing.expect(!editor.storeIndex(0, std.math.inf(f64)));
    try std.testing.expect(!editor.storeById(0, -std.math.inf(f64)));
    try std.testing.expect(!editor.storeByName("Gain", std.math.nan(f64)));
    try std.testing.expect(!editor.storeIndex(99, 1.0));
    try std.testing.expect(!editor.storePlain(99, 1.0));
    try std.testing.expect(!editor.storePlainIndex(99, 1.0));
    try std.testing.expect(!editor.storeById(99, 1.0));
    try std.testing.expect(!editor.storePlainById(99, 1.0));
    try std.testing.expect(!editor.storeByName("Missing", 1.0));
    try std.testing.expect(!editor.storePlainByName("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storeNormalizedCount("gain", std.math.nan(f64)));
    try std.testing.expectEqual(@as(?usize, null), editor.storeIndexCount(0, std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), editor.storeByIdCount(0, -std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), editor.storeByNameCount("Gain", std.math.nan(f64)));
    try std.testing.expectEqual(@as(?usize, 0), editor.storeNormalizedCount("gain", 0.75));
    try std.testing.expectEqual(@as(?usize, 1), editor.storeNormalizedCount("gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 1), editor.storeCount("gain", 0.0));
    try std.testing.expectEqual(@as(?usize, 1), editor.storeCount("gain", 3.0));
    try std.testing.expectEqual(@as(?usize, 0), editor.storeIndexCount(0, 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), editor.storePlainCount(0, 6.0));
    try std.testing.expectEqual(@as(?usize, 0), editor.storePlainIndexCount(0, 6.0));
    try std.testing.expectEqual(@as(?usize, 0), editor.storeByIdCount(0, 1.0));
    try std.testing.expectEqual(@as(?usize, 1), editor.storePlainByIdCount(0, 3.0));
    try std.testing.expectEqual(@as(?usize, 0), editor.storeByNameCount("Gain", 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), editor.storePlainByNameCount("Gain", 1.5));
    try std.testing.expectEqual(@as(?usize, null), editor.storeIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storePlainCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storePlainIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storeByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storePlainByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storeByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, null), editor.storePlainByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultIndex(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultById(99));
    try std.testing.expectEqual(@as(?bool, null), editor.isDefaultByName("Missing"));

    try std.testing.expectEqual(@as(f64, 1.5), editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), editor.load("voices"));
    try std.testing.expectEqual(false, editor.load("bypass"));
    try std.testing.expectEqual(Mode.mute, editor.load("mode"));
    try std.testing.expect(!editor.store("gain", std.math.inf(f64)));
    try std.testing.expectEqual(@as(?usize, null), editor.storeCount("gain", -std.math.inf(f64)));
    try std.testing.expectEqual(@as(f64, 1.5), editor.load("gain"));
    try std.testing.expectEqual(@as(f64, 1.0), editor.loadNormalized("mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.loadIndex(3));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.loadPlain(3));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.loadPlainIndex(3));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.loadById(2));
    try std.testing.expectEqual(@as(?f64, 0.0), editor.loadPlainById(2));
    try std.testing.expectEqual(@as(?f64, null), editor.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlain(99));
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
    try std.testing.expect(!view.allDefaults());
    try std.testing.expect(view.hasNonDefaults());
    try std.testing.expectEqual(@as(usize, 3), view.nonDefaultCount());

    var copied_values = Values.init(&set);
    const copied_editor = copied_values.editor(&set);
    try std.testing.expectEqual(@as(usize, 3), copied_editor.copyFromCount(view));
    try std.testing.expectEqual(@as(usize, 0), copied_editor.copyFromCount(view));
    copied_values.resetToDefaults(&set);
    copied_editor.copyFrom(view);
    try std.testing.expectEqual(@as(f64, 1.5), copied_editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), copied_editor.load("voices"));
    try std.testing.expectEqual(false, copied_editor.load("bypass"));
    try std.testing.expectEqual(Mode.mute, copied_editor.load("mode"));

    const changes = [_]process.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.0 },
        .{ .id = 1, .sample_offset = 0, .normalized = 0.0 },
        .{ .id = 2, .sample_offset = 0, .normalized = 1.0 },
        .{ .id = 3, .sample_offset = 0, .normalized = 0.5 },
    };
    const parameter_changes = try process.ParameterChanges.init(&changes, 1);
    try std.testing.expectEqual(@as(usize, 3), editor.applyChangesChangedCount(parameter_changes));
    try std.testing.expectEqual(@as(usize, 3), editor.applyChangesCount(parameter_changes));
    try std.testing.expectEqual(@as(usize, 0), editor.applyChangesChangedCount(parameter_changes));
    try std.testing.expectEqual(@as(f64, -12.0), editor.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), editor.load("voices"));
    try std.testing.expectEqual(true, editor.load("bypass"));
    try std.testing.expectEqual(Mode.boost, editor.load("mode"));

    try std.testing.expectEqual(@as(usize, 4), editor.resetToDefaultsCount());
    editor.applyChanges(parameter_changes);
    try std.testing.expectEqual(@as(f64, -12.0), editor.load("gain"));
    try std.testing.expectEqual(true, editor.load("bypass"));

    try std.testing.expectEqual(@as(usize, 3), editor.resetToDefaultsCount());
    try std.testing.expectEqual(@as(usize, 0), editor.resetToDefaultsCount());
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
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultCount("gain"));
    try std.testing.expectEqual(@as(?usize, 0), editor.resetToDefaultCount("gain"));
    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.resetToDefault("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(@as(i64, 4), view.load("voices"));
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultIndexCount(1));
    try std.testing.expectEqual(@as(?usize, 0), editor.resetToDefaultIndexCount(1));
    try std.testing.expect(editor.store("voices", 4));
    try std.testing.expect(editor.resetToDefaultIndex(1));
    try std.testing.expectEqual(@as(i64, 1), view.load("voices"));
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultByIdCount(2));
    try std.testing.expectEqual(@as(?usize, 0), editor.resetToDefaultByIdCount(2));
    try std.testing.expect(editor.store("bypass", true));
    try std.testing.expect(editor.resetToDefaultById(2));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(@as(?usize, 1), editor.resetToDefaultByNameCount("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), editor.resetToDefaultByNameCount("Mode"));
    try std.testing.expect(editor.store("mode", .mute));
    try std.testing.expect(editor.resetToDefaultByName("Mode"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
    try std.testing.expectEqual(@as(?usize, null), editor.resetToDefaultIndexCount(99));
    try std.testing.expectEqual(@as(?usize, null), editor.resetToDefaultByIdCount(99));
    try std.testing.expectEqual(@as(?usize, null), editor.resetToDefaultByNameCount("Missing"));
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

    try std.testing.expectEqual(@as(usize, 2), values.applyChangesChangedCount(&set, changes));
    try std.testing.expectEqual(@as(usize, 2), values.applyChangesCount(&set, changes));
    try std.testing.expectEqual(@as(usize, 0), values.applyChangesChangedCount(&set, changes));

    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 1));
    try std.testing.expectEqual(@as(?f64, 0.25), values.loadById(&set, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadById(&set, 3));

    values.resetToDefaults(&set);
    try std.testing.expectEqual(@as(usize, 1), values.applyChangesAtOffsetCount(&set, changes, 0));
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 0.5), values.loadById(&set, 1));
    values.resetToDefaults(&set);
    values.applyChanges(&set, changes);
    try std.testing.expectEqual(@as(?f64, 0.75), values.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 1.0), values.loadById(&set, 1));
}

test "parameter values generated process changes match reference application" {
    const Params = struct {
        gain: FloatParam = FloatParam.init(0, "Gain", 0.0, 1.0, 0.25),
        mix: FloatParam = FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
        manual: FloatParam = .{ .id = 2, .name = "Manual", .min = 0.0, .max = 1.0, .default = 0.25, .can_automate = false },
        meter: FloatParam = .{ .id = 3, .name = "Meter", .min = 0.0, .max = 1.0, .default = 0.5, .is_read_only = true },
    };
    const Set = ParameterSet(Params);
    const Values = ParameterValues(Params);
    const set = Set.init(.{});
    const Reference = struct {
        fn writableIndex(id: u32) ?usize {
            return switch (id) {
                0 => 0,
                1 => 1,
                else => null,
            };
        }

        fn apply(changes: []const process.ParameterChange, values: *[2]f64) struct { applied: usize, changed: usize } {
            var applied: usize = 0;
            var changed: usize = 0;
            for (changes) |change| {
                const index = writableIndex(change.id) orelse continue;
                applied += 1;
                if (values[index] != change.normalized) changed += 1;
                values[index] = change.normalized;
            }
            return .{ .applied = applied, .changed = changed };
        }
    };

    const ids = [_]u32{ 0, 1, 2, 3, 99 };
    const normalized_values = [_]f64{ 0.0, 0.25, 0.5, 0.75, 1.0 };

    for (0..32) |seed| {
        var items: [5]process.ParameterChange = undefined;
        for (&items, 0..) |*item, index| {
            item.* = .{
                .id = ids[(seed + index * 2) % ids.len],
                .sample_offset = (seed * 2 + index) % 8,
                .normalized = normalized_values[(seed + index * 3) % normalized_values.len],
            };
        }

        for (0..items.len + 1) |len| {
            const changes = try process.ParameterChanges.init(items[0..len], 8);
            var reference_values = [_]f64{ 0.25, 0.5 };
            const reference = Reference.apply(items[0..len], &reference_values);

            var applied_values = Values.init(&set);
            try std.testing.expectEqual(reference.applied, applied_values.applyChangesCount(&set, changes));
            try std.testing.expectEqual(@as(?f64, reference_values[0]), applied_values.loadById(&set, 0));
            try std.testing.expectEqual(@as(?f64, reference_values[1]), applied_values.loadById(&set, 1));
            try std.testing.expectEqual(@as(?f64, 0.25), applied_values.loadById(&set, 2));
            try std.testing.expectEqual(@as(?f64, 0.5), applied_values.loadById(&set, 3));

            var changed_values = Values.init(&set);
            try std.testing.expectEqual(reference.changed, changed_values.applyChangesChangedCount(&set, changes));
            try std.testing.expectEqual(@as(?f64, reference_values[0]), changed_values.loadById(&set, 0));
            try std.testing.expectEqual(@as(?f64, reference_values[1]), changed_values.loadById(&set, 1));
            try std.testing.expectEqual(@as(?f64, 0.25), changed_values.loadById(&set, 2));
            try std.testing.expectEqual(@as(?f64, 0.5), changed_values.loadById(&set, 3));
        }
    }
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
