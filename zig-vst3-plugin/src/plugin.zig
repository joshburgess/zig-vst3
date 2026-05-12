const std = @import("std");
const parameters = @import("parameters.zig");
const process_api = @import("process.zig");
const state = @import("state.zig");
const units_api = @import("units.zig");

pub fn PluginSpec(comptime Plugin: type) type {
    if (!@hasDecl(Plugin, "Params")) {
        @compileError("Plugin must declare Params");
    }
    if (!@hasDecl(Plugin, "name")) {
        @compileError("Plugin must declare name");
    }
    if (!@hasDecl(Plugin, "vendor")) {
        @compileError("Plugin must declare vendor");
    }

    return struct {
        const Self = @This();

        pub const Params = Plugin.Params;
        pub const ParameterSet = parameters.ParameterSet(Params);
        pub const ParameterValues = parameters.ParameterValues(Params);
        pub const Units = units_api.UnitSet(unit_config);
        pub const encoded_parameter_state_size = state.encodedSize(Params);
        pub const name = Plugin.name;
        pub const vendor = Plugin.vendor;
        pub const url = if (@hasDecl(Plugin, "url")) Plugin.url else "";
        pub const email = if (@hasDecl(Plugin, "email")) Plugin.email else "";
        pub const component_class_name = if (@hasDecl(Plugin, "component_class_name")) Plugin.component_class_name else Plugin.name;
        pub const controller_class_name = if (@hasDecl(Plugin, "controller_class_name")) Plugin.controller_class_name else Plugin.name ++ " Controller";
        pub const component_category = if (@hasDecl(Plugin, "component_category")) Plugin.component_category else "Audio Module Class";
        pub const controller_category = if (@hasDecl(Plugin, "controller_category")) Plugin.controller_category else "Component Controller Class";
        pub const audio_input = !@hasDecl(Plugin, "audio_input") or Plugin.audio_input;
        pub const audio_output = !@hasDecl(Plugin, "audio_output") or Plugin.audio_output;
        pub const event_input = !@hasDecl(Plugin, "event_input") or Plugin.event_input;
        pub const event_output = @hasDecl(Plugin, "event_output") and Plugin.event_output;
        pub const unit_config = if (@hasDecl(Plugin, "units")) Plugin.units else units_api.Config{};
        pub const has_init = @hasDecl(Plugin, "init");
        pub const has_prepare = @hasDecl(Plugin, "prepare");
        pub const has_process = @hasDecl(Plugin, "process");
        pub const has_process_with_parameter_view = @hasDecl(Plugin, "processWithParameterView");
        pub const has_process_with_parameters = @hasDecl(Plugin, "processWithParameters");
        pub const has_process64 = @hasDecl(Plugin, "process64");
        pub const has_process64_with_parameter_view = @hasDecl(Plugin, "process64WithParameterView");
        pub const has_process64_with_parameters = @hasDecl(Plugin, "process64WithParameters");
        pub const has_deinit = @hasDecl(Plugin, "deinit");

        parameter_set: ParameterSet,
        values: ParameterValues,
        units: Units = .{},

        pub fn initChecked(params: Params) !Self {
            try validateMetadata();
            const set = ParameterSet.init(params);
            try set.validate();
            const units = Units{};
            try units.validate();
            try set.validateUnitIds(units);
            try units.validateProgramParameterIds(&set);
            return .{
                .parameter_set = set,
                .values = ParameterValues.init(&set),
                .units = units,
            };
        }

        pub fn init(params: Params) Self {
            return initChecked(params) catch @panic("invalid plugin metadata");
        }

        fn validateMetadata() !void {
            try validateRequiredMetadataString(name);
            try validateRequiredMetadataString(vendor);
            try validateOptionalMetadataString(url);
            try validateOptionalMetadataString(email);
            try validateRequiredMetadataString(component_class_name);
            try validateRequiredMetadataString(controller_class_name);
            try validateRequiredMetadataString(component_category);
            try validateRequiredMetadataString(controller_category);
        }
    };
}

fn validateRequiredMetadataString(value: []const u8) !void {
    if (value.len == 0) return error.EmptyPluginMetadata;
    try validateOptionalMetadataString(value);
}

fn validateOptionalMetadataString(value: []const u8) !void {
    if (std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidPluginMetadata;
}

pub const PrepareConfig = struct {
    sample_rate: f64,
    max_block_size: u32,

    pub fn validate(self: PrepareConfig) !void {
        if (self.sample_rate <= 0.0 or !std.math.isFinite(self.sample_rate)) return error.InvalidSampleRate;
        if (self.max_block_size == 0) return error.InvalidMaxBlockSize;
    }
};

pub fn PluginInstance(comptime Plugin: type) type {
    validateLifecycle(Plugin);

    return struct {
        const Self = @This();
        pub const Spec = PluginSpec(Plugin);

        spec: Spec,
        plugin: Plugin,

        pub fn init(allocator: std.mem.Allocator, params: Plugin.Params) !Self {
            const spec = try Spec.initChecked(params);
            const plugin = if (Spec.has_init)
                try Plugin.init(allocator)
            else
                Plugin{};

            return .{
                .spec = spec,
                .plugin = plugin,
            };
        }

        pub fn prepareChecked(self: *Self, config: PrepareConfig) !void {
            try config.validate();
            if (Spec.has_prepare) {
                self.plugin.prepare(config);
            }
        }

        pub fn prepare(self: *Self, config: PrepareConfig) void {
            self.prepareChecked(config) catch @panic("invalid prepare config");
        }

        pub fn hasAudioInput(self: *const Self) bool {
            _ = self;
            return Spec.audio_input;
        }

        pub fn hasAudioOutput(self: *const Self) bool {
            _ = self;
            return Spec.audio_output;
        }

        pub fn hasEventInput(self: *const Self) bool {
            _ = self;
            return Spec.event_input;
        }

        pub fn hasEventOutput(self: *const Self) bool {
            _ = self;
            return Spec.event_output;
        }

        pub fn hasInitHook(self: *const Self) bool {
            _ = self;
            return Spec.has_init;
        }

        pub fn hasPrepareHook(self: *const Self) bool {
            _ = self;
            return Spec.has_prepare;
        }

        pub fn hasProcessHook(self: *const Self) bool {
            _ = self;
            return Spec.has_process or Spec.has_process_with_parameter_view or Spec.has_process_with_parameters;
        }

        pub fn hasProcess64Hook(self: *const Self) bool {
            _ = self;
            return Spec.has_process64 or Spec.has_process64_with_parameter_view or Spec.has_process64_with_parameters;
        }

        pub fn hasAnyProcessHook(self: *const Self) bool {
            return self.hasProcessHook() or self.hasProcess64Hook();
        }

        pub fn hasDeinitHook(self: *const Self) bool {
            _ = self;
            return Spec.has_deinit;
        }

        pub fn pluginName(self: *const Self) []const u8 {
            _ = self;
            return Spec.name;
        }

        pub fn pluginVendor(self: *const Self) []const u8 {
            _ = self;
            return Spec.vendor;
        }

        pub fn pluginUrl(self: *const Self) []const u8 {
            _ = self;
            return Spec.url;
        }

        pub fn pluginEmail(self: *const Self) []const u8 {
            _ = self;
            return Spec.email;
        }

        pub fn componentClassName(self: *const Self) []const u8 {
            _ = self;
            return Spec.component_class_name;
        }

        pub fn controllerClassName(self: *const Self) []const u8 {
            _ = self;
            return Spec.controller_class_name;
        }

        pub fn componentCategory(self: *const Self) []const u8 {
            _ = self;
            return Spec.component_category;
        }

        pub fn controllerCategory(self: *const Self) []const u8 {
            _ = self;
            return Spec.controller_category;
        }

        pub fn parameterSet(self: *const Self) *const Spec.ParameterSet {
            return &self.spec.parameter_set;
        }

        pub fn parameterValues(self: *Self) *Spec.ParameterValues {
            return &self.spec.values;
        }

        pub fn parameterValuesConst(self: *const Self) *const Spec.ParameterValues {
            return &self.spec.values;
        }

        pub fn copyParameterValuesFrom(self: *Self, source: *const Self) void {
            self.spec.values.copyFrom(&source.spec.values);
        }

        pub fn copyParameterValuesFromCount(self: *Self, source: *const Self) usize {
            return self.spec.values.copyFromCount(&source.spec.values);
        }

        pub fn unitSet(self: *const Self) *const Spec.Units {
            return &self.spec.units;
        }

        pub fn unitCount(self: *const Self) usize {
            return self.spec.units.unitCount();
        }

        pub fn unitsEmpty(self: *const Self) bool {
            return self.spec.units.unitsEmpty();
        }

        pub fn hasUnits(self: *const Self) bool {
            return self.spec.units.hasUnits();
        }

        pub fn duplicateUnitId(self: *const Self) ?i32 {
            return self.spec.units.duplicateUnitId();
        }

        pub fn duplicateUnitIdIndex(self: *const Self) ?usize {
            return self.spec.units.duplicateUnitIdIndex();
        }

        pub fn hasDuplicateUnitIds(self: *const Self) bool {
            return self.spec.units.hasDuplicateUnitIds();
        }

        pub fn duplicateUnitName(self: *const Self) ?[]const u8 {
            return self.spec.units.duplicateUnitName();
        }

        pub fn duplicateUnitNameIndex(self: *const Self) ?usize {
            return self.spec.units.duplicateUnitNameIndex();
        }

        pub fn hasDuplicateUnitNames(self: *const Self) bool {
            return self.spec.units.hasDuplicateUnitNames();
        }

        pub fn unit(self: *const Self, index: usize) ?units_api.Unit {
            return self.spec.units.unit(index);
        }

        pub fn unitById(self: *const Self, id: i32) ?units_api.Unit {
            return self.spec.units.unitById(id);
        }

        pub fn unitByName(self: *const Self, name: []const u8) ?units_api.Unit {
            return self.spec.units.unitByName(name);
        }

        pub fn rootUnit(self: *const Self) units_api.Unit {
            return self.spec.units.rootUnit();
        }

        pub fn rootUnitId(self: *const Self) i32 {
            return self.spec.units.rootUnitId();
        }

        pub fn rootUnitName(self: *const Self) []const u8 {
            return self.spec.units.rootUnitName();
        }

        pub fn unitIndexOfId(self: *const Self, id: i32) ?usize {
            return self.spec.units.unitIndexOfId(id);
        }

        pub fn unitIndexOfName(self: *const Self, name: []const u8) ?usize {
            return self.spec.units.unitIndexOfName(name);
        }

        pub fn hasUnit(self: *const Self, id: i32) bool {
            return self.spec.units.hasUnit(id);
        }

        pub fn hasUnitName(self: *const Self, name: []const u8) bool {
            return self.spec.units.hasUnitName(name);
        }

        pub fn unitIsRoot(self: *const Self, id: i32) bool {
            const item = self.unitById(id) orelse return false;
            return item.isRoot();
        }

        pub fn unitIsRootByName(self: *const Self, name: []const u8) bool {
            const item = self.unitByName(name) orelse return false;
            return item.isRoot();
        }

        pub fn unitHasParent(self: *const Self, id: i32) bool {
            const item = self.unitById(id) orelse return false;
            return item.hasParent();
        }

        pub fn unitHasParentByName(self: *const Self, name: []const u8) bool {
            const item = self.unitByName(name) orelse return false;
            return item.hasParent();
        }

        pub fn unitParentId(self: *const Self, id: i32) ?i32 {
            const item = self.unitById(id) orelse return null;
            if (!item.hasParent()) return null;
            return item.parent_id;
        }

        pub fn unitParentIdByName(self: *const Self, name: []const u8) ?i32 {
            const item = self.unitByName(name) orelse return null;
            if (!item.hasParent()) return null;
            return item.parent_id;
        }

        pub fn unitHasProgramList(self: *const Self, id: i32) bool {
            const item = self.unitById(id) orelse return false;
            return item.hasProgramList();
        }

        pub fn unitHasProgramListByName(self: *const Self, name: []const u8) bool {
            const item = self.unitByName(name) orelse return false;
            return item.hasProgramList();
        }

        pub fn programListCount(self: *const Self) usize {
            return self.spec.units.programListCount();
        }

        pub fn programListsEmpty(self: *const Self) bool {
            return self.spec.units.programListsEmpty();
        }

        pub fn hasProgramLists(self: *const Self) bool {
            return self.spec.units.hasProgramLists();
        }

        pub fn duplicateProgramListId(self: *const Self) ?i32 {
            return self.spec.units.duplicateProgramListId();
        }

        pub fn duplicateProgramListIdIndex(self: *const Self) ?usize {
            return self.spec.units.duplicateProgramListIdIndex();
        }

        pub fn hasDuplicateProgramListIds(self: *const Self) bool {
            return self.spec.units.hasDuplicateProgramListIds();
        }

        pub fn duplicateProgramListName(self: *const Self) ?[]const u8 {
            return self.spec.units.duplicateProgramListName();
        }

        pub fn duplicateProgramListNameIndex(self: *const Self) ?usize {
            return self.spec.units.duplicateProgramListNameIndex();
        }

        pub fn hasDuplicateProgramListNames(self: *const Self) bool {
            return self.spec.units.hasDuplicateProgramListNames();
        }

        pub fn programList(self: *const Self, index: usize) ?units_api.ProgramList {
            return self.spec.units.programList(index);
        }

        pub fn programListById(self: *const Self, id: i32) ?units_api.ProgramList {
            return self.spec.units.programListById(id);
        }

        pub fn programListByName(self: *const Self, name: []const u8) ?units_api.ProgramList {
            return self.spec.units.programListByName(name);
        }

        pub fn programListIndexOfId(self: *const Self, id: i32) ?usize {
            return self.spec.units.programListIndexOfId(id);
        }

        pub fn programListIndexOfName(self: *const Self, name: []const u8) ?usize {
            return self.spec.units.programListIndexOfName(name);
        }

        pub fn hasProgramList(self: *const Self, id: i32) bool {
            return self.spec.units.hasProgramList(id);
        }

        pub fn hasProgramListName(self: *const Self, name: []const u8) bool {
            return self.spec.units.hasProgramListName(name);
        }

        pub fn programListHasPrograms(self: *const Self, id: i32) bool {
            return self.spec.units.programListHasPrograms(id);
        }

        pub fn programListHasProgramsByName(self: *const Self, name: []const u8) bool {
            return self.spec.units.programListHasProgramsByName(name);
        }

        pub fn programListEmpty(self: *const Self, id: i32) bool {
            return self.spec.units.programListEmpty(id);
        }

        pub fn programListEmptyByName(self: *const Self, name: []const u8) bool {
            return self.spec.units.programListEmptyByName(name);
        }

        pub fn programListForUnit(self: *const Self, unit_id: i32) ?units_api.ProgramList {
            return self.spec.units.programListForUnit(unit_id);
        }

        pub fn programListForUnitName(self: *const Self, unit_name: []const u8) ?units_api.ProgramList {
            return self.spec.units.programListForUnitName(unit_name);
        }

        pub fn programListIdForUnit(self: *const Self, unit_id: i32) ?i32 {
            return self.spec.units.programListIdForUnit(unit_id);
        }

        pub fn programListIdForUnitName(self: *const Self, unit_name: []const u8) ?i32 {
            return self.spec.units.programListIdForUnitName(unit_name);
        }

        pub fn programListNameForUnit(self: *const Self, unit_id: i32) ?[]const u8 {
            return self.spec.units.programListNameForUnit(unit_id);
        }

        pub fn programListNameForUnitName(self: *const Self, unit_name: []const u8) ?[]const u8 {
            return self.spec.units.programListNameForUnitName(unit_name);
        }

        pub fn programCount(self: *const Self, list_id: i32) ?usize {
            return self.spec.units.programCount(list_id);
        }

        pub fn programCountByName(self: *const Self, list_name: []const u8) ?usize {
            return self.spec.units.programCountByName(list_name);
        }

        pub fn programName(self: *const Self, list_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.programName(list_id, program_index);
        }

        pub fn program(self: *const Self, list_id: i32, program_index: usize) ?units_api.Program {
            return self.spec.units.program(list_id, program_index);
        }

        pub fn programByName(self: *const Self, list_id: i32, name: []const u8) ?units_api.Program {
            return self.spec.units.programByName(list_id, name);
        }

        pub fn programIndexOfName(self: *const Self, list_id: i32, name: []const u8) ?usize {
            return self.spec.units.programIndexOfName(list_id, name);
        }

        pub fn hasProgramName(self: *const Self, list_id: i32, name: []const u8) bool {
            return self.spec.units.hasProgramName(list_id, name);
        }

        pub fn duplicateProgramName(self: *const Self, list_id: i32) ?[]const u8 {
            return self.spec.units.duplicateProgramName(list_id);
        }

        pub fn duplicateProgramNameIndex(self: *const Self, list_id: i32) ?usize {
            return self.spec.units.duplicateProgramNameIndex(list_id);
        }

        pub fn hasDuplicateProgramNames(self: *const Self, list_id: i32) bool {
            return self.spec.units.hasDuplicateProgramNames(list_id);
        }

        pub fn programParameterCount(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.programParameterCount(list_id, program_index);
        }

        pub fn programParameterCountByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programParameterCountByName(list_id, program_name);
        }

        pub fn programHasParameters(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programHasParameters(list_id, program_index);
        }

        pub fn programHasParametersByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasParametersByName(list_id, program_name);
        }

        pub fn programParametersEmpty(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programParametersEmpty(list_id, program_index);
        }

        pub fn programParametersEmptyByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programParametersEmptyByName(list_id, program_name);
        }

        pub fn programParameter(self: *const Self, list_id: i32, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameter(list_id, program_index, parameter_index);
        }

        pub fn programParameterByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByName(list_id, program_name, parameter_index);
        }

        pub fn programParameterById(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterById(list_id, program_index, parameter_id);
        }

        pub fn programParameterIndexOfId(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfId(list_id, program_index, parameter_id);
        }

        pub fn hasProgramParameter(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameter(list_id, program_index, parameter_id);
        }

        pub fn duplicateProgramParameterId(self: *const Self, list_id: i32, program_index: usize) ?u32 {
            return self.spec.units.duplicateProgramParameterId(list_id, program_index);
        }

        pub fn duplicateProgramParameterIdIndex(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndex(list_id, program_index);
        }

        pub fn hasDuplicateProgramParameterIds(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramParameterIds(list_id, program_index);
        }

        pub fn programParameterByNameAndId(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameAndId(list_id, program_name, parameter_id);
        }

        pub fn programParameterIndexOfIdByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByName(list_id, program_name, parameter_id);
        }

        pub fn hasProgramParameterByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByName(list_id, program_name, parameter_id);
        }

        pub fn duplicateProgramParameterIdByName(self: *const Self, list_id: i32, program_name: []const u8) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByName(list_id, program_name);
        }

        pub fn duplicateProgramParameterIdIndexByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByName(list_id, program_name);
        }

        pub fn hasDuplicateProgramParameterIdsByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByName(list_id, program_name);
        }

        pub fn programInfo(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfo(list_id, program_index, key);
        }

        pub fn programInfoEntry(self: *const Self, list_id: i32, program_index: usize, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntry(list_id, program_index, info_index);
        }

        pub fn programInfoIndexOfKey(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKey(list_id, program_index, key);
        }

        pub fn hasProgramInfo(self: *const Self, list_id: i32, program_index: usize, key: []const u8) bool {
            return self.spec.units.hasProgramInfo(list_id, program_index, key);
        }

        pub fn duplicateProgramInfoKey(self: *const Self, list_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKey(list_id, program_index);
        }

        pub fn duplicateProgramInfoKeyIndex(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndex(list_id, program_index);
        }

        pub fn hasDuplicateProgramInfoKeys(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramInfoKeys(list_id, program_index);
        }

        pub fn programInfoByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByName(list_id, program_name, key);
        }

        pub fn programInfoEntryByName(self: *const Self, list_id: i32, program_name: []const u8, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByName(list_id, program_name, info_index);
        }

        pub fn programInfoIndexOfKeyByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByName(list_id, program_name, key);
        }

        pub fn hasProgramInfoByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByName(list_id, program_name, key);
        }

        pub fn duplicateProgramInfoKeyByName(self: *const Self, list_id: i32, program_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByName(list_id, program_name);
        }

        pub fn duplicateProgramInfoKeyIndexByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByName(list_id, program_name);
        }

        pub fn hasDuplicateProgramInfoKeysByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByName(list_id, program_name);
        }

        pub fn programInfoCount(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.programInfoCount(list_id, program_index);
        }

        pub fn programInfoCountByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programInfoCountByName(list_id, program_name);
        }

        pub fn programHasInfoEntries(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programHasInfoEntries(list_id, program_index);
        }

        pub fn programHasInfoEntriesByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasInfoEntriesByName(list_id, program_name);
        }

        pub fn programInfoEmpty(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programInfoEmpty(list_id, program_index);
        }

        pub fn programInfoEmptyByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programInfoEmptyByName(list_id, program_name);
        }

        pub fn applyProgram(self: *Self, list_id: i32, program_index: usize) !bool {
            return (try self.applyProgramCount(list_id, program_index)) != null;
        }

        pub fn applyProgramCount(self: *Self, list_id: i32, program_index: usize) !?usize {
            const item = self.program(list_id, program_index) orelse return null;
            for (item.parameters) |parameter| {
                if (!std.math.isFinite(parameter.normalized) or parameter.normalized < 0.0 or parameter.normalized > 1.0) {
                    return error.ProgramParameterOutsideNormalizedRange;
                }
                if (self.parameterIndexOfId(parameter.parameter_id) == null) return error.UnknownProgramParameter;
            }
            var changed_count: usize = 0;
            for (item.parameters) |parameter| {
                changed_count += self.storeParameterByIdCount(parameter.parameter_id, parameter.normalized) orelse {
                    return error.UnknownProgramParameter;
                };
            }
            return changed_count;
        }

        pub fn applyProgramByName(self: *Self, list_id: i32, program_name: []const u8) !bool {
            return (try self.applyProgramByNameCount(list_id, program_name)) != null;
        }

        pub fn applyProgramByNameCount(self: *Self, list_id: i32, program_name: []const u8) !?usize {
            const index = self.programIndexOfName(list_id, program_name) orelse return null;
            return self.applyProgramCount(list_id, index);
        }

        pub fn applyProgramForUnit(self: *Self, unit_id: i32, program_index: usize) !bool {
            return (try self.applyProgramForUnitCount(unit_id, program_index)) != null;
        }

        pub fn applyProgramForUnitCount(self: *Self, unit_id: i32, program_index: usize) !?usize {
            const list = self.programListForUnit(unit_id) orelse return null;
            return self.applyProgramCount(list.id, program_index);
        }

        pub fn applyProgramByNameForUnit(self: *Self, unit_id: i32, program_name: []const u8) !bool {
            return (try self.applyProgramByNameForUnitCount(unit_id, program_name)) != null;
        }

        pub fn applyProgramByNameForUnitCount(self: *Self, unit_id: i32, program_name: []const u8) !?usize {
            const list = self.programListForUnit(unit_id) orelse return null;
            return self.applyProgramByNameCount(list.id, program_name);
        }

        pub fn applyProgramForUnitName(self: *Self, unit_name: []const u8, program_index: usize) !bool {
            return (try self.applyProgramForUnitNameCount(unit_name, program_index)) != null;
        }

        pub fn applyProgramForUnitNameCount(self: *Self, unit_name: []const u8, program_index: usize) !?usize {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return self.applyProgramCount(list.id, program_index);
        }

        pub fn applyProgramByNameForUnitName(self: *Self, unit_name: []const u8, program_name: []const u8) !bool {
            return (try self.applyProgramByNameForUnitNameCount(unit_name, program_name)) != null;
        }

        pub fn applyProgramByNameForUnitNameCount(self: *Self, unit_name: []const u8, program_name: []const u8) !?usize {
            const list = self.programListForUnitName(unit_name) orelse return null;
            return self.applyProgramByNameCount(list.id, program_name);
        }

        pub fn parameterView(self: *const Self) parameters.ParameterView(Plugin.Params) {
            return self.spec.values.view(&self.spec.parameter_set);
        }

        pub fn parameterEditor(self: *Self) parameters.ParameterEditor(Plugin.Params) {
            return self.spec.values.editor(&self.spec.parameter_set);
        }

        pub fn parameterCount(self: *const Self) usize {
            return self.parameterView().parameterCount();
        }

        pub fn parametersEmpty(self: *const Self) bool {
            return self.parameterView().parametersEmpty();
        }

        pub fn hasParameters(self: *const Self) bool {
            return self.parameterView().hasParameters();
        }

        pub fn parameterNonDefaultCount(self: *const Self) usize {
            return self.parameterView().nonDefaultCount();
        }

        pub fn parametersAllDefaults(self: *const Self) bool {
            return self.parameterView().allDefaults();
        }

        pub fn hasNonDefaultParameters(self: *const Self) bool {
            return self.parameterView().hasNonDefaults();
        }

        pub fn parameterId(self: *const Self, index: usize) ?u32 {
            return self.parameterView().id(index);
        }

        pub fn parameterName(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().name(index);
        }

        pub fn parameterNameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().nameById(wanted_id);
        }

        pub fn parameterIdByName(self: *const Self, wanted_name: []const u8) ?u32 {
            return self.parameterView().idByName(wanted_name);
        }

        pub fn parameterShortName(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().shortName(index);
        }

        pub fn parameterShortNameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().shortNameById(wanted_id);
        }

        pub fn parameterShortNameByName(self: *const Self, wanted_name: []const u8) ?[]const u8 {
            return self.parameterView().shortNameByName(wanted_name);
        }

        pub fn parameterUnits(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().units(index);
        }

        pub fn parameterUnitsById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().unitsById(wanted_id);
        }

        pub fn parameterUnitsByName(self: *const Self, wanted_name: []const u8) ?[]const u8 {
            return self.parameterView().unitsByName(wanted_name);
        }

        pub fn parameterDefaultNormalized(self: *const Self, index: usize) ?f64 {
            return self.parameterView().defaultNormalized(index);
        }

        pub fn parameterDefaultNormalizedById(self: *const Self, wanted_id: u32) ?f64 {
            return self.parameterView().defaultNormalizedById(wanted_id);
        }

        pub fn parameterDefaultNormalizedByName(self: *const Self, wanted_name: []const u8) ?f64 {
            return self.parameterView().defaultNormalizedByName(wanted_name);
        }

        pub fn parameterDefaultPlain(self: *const Self, index: usize) ?f64 {
            return self.parameterView().defaultPlain(index);
        }

        pub fn parameterDefaultPlainById(self: *const Self, wanted_id: u32) ?f64 {
            return self.parameterView().defaultPlainById(wanted_id);
        }

        pub fn parameterDefaultPlainByName(self: *const Self, wanted_name: []const u8) ?f64 {
            return self.parameterView().defaultPlainByName(wanted_name);
        }

        pub fn parameterPlainMinimum(self: *const Self, index: usize) ?f64 {
            return self.parameterView().plainMinimum(index);
        }

        pub fn parameterPlainMinimumById(self: *const Self, wanted_id: u32) ?f64 {
            return self.parameterView().plainMinimumById(wanted_id);
        }

        pub fn parameterPlainMinimumByName(self: *const Self, wanted_name: []const u8) ?f64 {
            return self.parameterView().plainMinimumByName(wanted_name);
        }

        pub fn parameterPlainMaximum(self: *const Self, index: usize) ?f64 {
            return self.parameterView().plainMaximum(index);
        }

        pub fn parameterPlainMaximumById(self: *const Self, wanted_id: u32) ?f64 {
            return self.parameterView().plainMaximumById(wanted_id);
        }

        pub fn parameterPlainMaximumByName(self: *const Self, wanted_name: []const u8) ?f64 {
            return self.parameterView().plainMaximumByName(wanted_name);
        }

        pub fn parameterHasPlainRange(self: *const Self, index: usize) bool {
            return self.parameterView().hasPlainRange(index);
        }

        pub fn parameterHasPlainRangeById(self: *const Self, wanted_id: u32) bool {
            return self.parameterView().hasPlainRangeById(wanted_id);
        }

        pub fn parameterHasPlainRangeByName(self: *const Self, wanted_name: []const u8) bool {
            return self.parameterView().hasPlainRangeByName(wanted_name);
        }

        pub fn parameterIsBypass(self: *const Self, index: usize) ?bool {
            return self.parameterView().isBypass(index);
        }

        pub fn parameterIsBypassById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isBypassById(wanted_id);
        }

        pub fn parameterIsBypassByName(self: *const Self, wanted_name: []const u8) ?bool {
            return self.parameterView().isBypassByName(wanted_name);
        }

        pub fn parameterCanAutomate(self: *const Self, index: usize) ?bool {
            return self.parameterView().canAutomate(index);
        }

        pub fn parameterCanAutomateById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().canAutomateById(wanted_id);
        }

        pub fn parameterCanAutomateByName(self: *const Self, wanted_name: []const u8) ?bool {
            return self.parameterView().canAutomateByName(wanted_name);
        }

        pub fn parameterIsReadOnly(self: *const Self, index: usize) ?bool {
            return self.parameterView().isReadOnly(index);
        }

        pub fn parameterIsReadOnlyById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isReadOnlyById(wanted_id);
        }

        pub fn parameterIsReadOnlyByName(self: *const Self, wanted_name: []const u8) ?bool {
            return self.parameterView().isReadOnlyByName(wanted_name);
        }

        pub fn parameterUnitId(self: *const Self, index: usize) ?i32 {
            return self.parameterView().unitId(index);
        }

        pub fn parameterUnitIdById(self: *const Self, wanted_id: u32) ?i32 {
            return self.parameterView().unitIdById(wanted_id);
        }

        pub fn parameterUnitIdByName(self: *const Self, wanted_name: []const u8) ?i32 {
            return self.parameterView().unitIdByName(wanted_name);
        }

        pub fn parameterStepCount(self: *const Self, index: usize) ?i32 {
            return self.parameterView().stepCount(index);
        }

        pub fn parameterStepCountById(self: *const Self, wanted_id: u32) ?i32 {
            return self.parameterView().stepCountById(wanted_id);
        }

        pub fn parameterStepCountByName(self: *const Self, wanted_name: []const u8) ?i32 {
            return self.parameterView().stepCountByName(wanted_name);
        }

        pub fn parameterIsList(self: *const Self, index: usize) ?bool {
            return self.parameterView().isList(index);
        }

        pub fn parameterIsListById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isListById(wanted_id);
        }

        pub fn parameterIsListByName(self: *const Self, wanted_name: []const u8) ?bool {
            return self.parameterView().isListByName(wanted_name);
        }

        pub fn parameterOptionCount(self: *const Self, index: usize) ?usize {
            return self.parameterView().optionCount(index);
        }

        pub fn parameterOptionCountById(self: *const Self, wanted_id: u32) ?usize {
            return self.parameterView().optionCountById(wanted_id);
        }

        pub fn parameterOptionCountByName(self: *const Self, wanted_name: []const u8) ?usize {
            return self.parameterView().optionCountByName(wanted_name);
        }

        pub fn parameterOptionLabel(self: *const Self, index: usize, option_index: usize) ?[]const u8 {
            return self.parameterView().optionLabel(index, option_index);
        }

        pub fn parameterOptionLabelById(self: *const Self, wanted_id: u32, option_index: usize) ?[]const u8 {
            return self.parameterView().optionLabelById(wanted_id, option_index);
        }

        pub fn parameterOptionLabelByName(self: *const Self, wanted_name: []const u8, option_index: usize) ?[]const u8 {
            return self.parameterView().optionLabelByName(wanted_name, option_index);
        }

        pub fn parameterOptionNormalized(self: *const Self, index: usize, option_index: usize) ?f64 {
            return self.parameterView().optionNormalized(index, option_index);
        }

        pub fn parameterOptionNormalizedById(self: *const Self, wanted_id: u32, option_index: usize) ?f64 {
            return self.parameterView().optionNormalizedById(wanted_id, option_index);
        }

        pub fn parameterOptionNormalizedByName(self: *const Self, wanted_name: []const u8, option_index: usize) ?f64 {
            return self.parameterView().optionNormalizedByName(wanted_name, option_index);
        }

        pub fn parameterHasOptions(self: *const Self, index: usize) bool {
            return self.parameterView().hasOptions(index);
        }

        pub fn parameterOptionsEmpty(self: *const Self, index: usize) bool {
            return self.parameterView().optionsEmpty(index);
        }

        pub fn parameterHasOptionsById(self: *const Self, wanted_id: u32) bool {
            return self.parameterView().hasOptionsById(wanted_id);
        }

        pub fn parameterOptionsEmptyById(self: *const Self, wanted_id: u32) bool {
            return self.parameterView().optionsEmptyById(wanted_id);
        }

        pub fn parameterHasOptionsByName(self: *const Self, wanted_name: []const u8) bool {
            return self.parameterView().hasOptionsByName(wanted_name);
        }

        pub fn parameterOptionsEmptyByName(self: *const Self, wanted_name: []const u8) bool {
            return self.parameterView().optionsEmptyByName(wanted_name);
        }

        pub fn formatParameterPlainIndex(self: *const Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.parameterView().formatPlainIndex(index, normalized, buffer);
        }

        pub fn parseParameterPlainIndex(self: *const Self, index: usize, text: []const u8) !f64 {
            return self.parameterView().parsePlainIndex(index, text);
        }

        pub fn parameterPlainFromNormalizedIndex(self: *const Self, index: usize, normalized: f64) ?f64 {
            return self.parameterView().plainFromNormalizedIndex(index, normalized);
        }

        pub fn parameterNormalizedFromPlainIndex(self: *const Self, index: usize, plain: f64) ?f64 {
            return self.parameterView().normalizedFromPlainIndex(index, plain);
        }

        pub fn formatParameterPlainById(self: *const Self, wanted_id: u32, normalized: f64, buffer: []u8) ![]const u8 {
            return self.parameterView().formatPlainById(wanted_id, normalized, buffer);
        }

        pub fn parseParameterPlainById(self: *const Self, wanted_id: u32, text: []const u8) !f64 {
            return self.parameterView().parsePlainById(wanted_id, text);
        }

        pub fn parameterPlainFromNormalizedById(self: *const Self, wanted_id: u32, normalized: f64) ?f64 {
            return self.parameterView().plainFromNormalizedById(wanted_id, normalized);
        }

        pub fn parameterNormalizedFromPlainById(self: *const Self, wanted_id: u32, plain: f64) ?f64 {
            return self.parameterView().normalizedFromPlainById(wanted_id, plain);
        }

        pub fn formatParameterPlainByName(self: *const Self, wanted_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.parameterView().formatPlainByName(wanted_name, normalized, buffer);
        }

        pub fn parseParameterPlainByName(self: *const Self, wanted_name: []const u8, text: []const u8) !f64 {
            return self.parameterView().parsePlainByName(wanted_name, text);
        }

        pub fn parameterPlainFromNormalizedByName(self: *const Self, wanted_name: []const u8, normalized: f64) ?f64 {
            return self.parameterView().plainFromNormalizedByName(wanted_name, normalized);
        }

        pub fn parameterNormalizedFromPlainByName(self: *const Self, wanted_name: []const u8, plain: f64) ?f64 {
            return self.parameterView().normalizedFromPlainByName(wanted_name, plain);
        }

        pub fn parameterIndexOfId(self: *const Self, wanted_id: u32) ?usize {
            return self.spec.parameter_set.indexOfId(wanted_id);
        }

        pub fn parameterIndexOfName(self: *const Self, name: []const u8) ?usize {
            return self.spec.parameter_set.indexOfName(name);
        }

        pub fn duplicateParameterId(self: *const Self) ?u32 {
            return self.spec.parameter_set.duplicateId();
        }

        pub fn duplicateParameterIdIndex(self: *const Self) ?usize {
            return self.spec.parameter_set.duplicateIdIndex();
        }

        pub fn duplicateParameterName(self: *const Self) ?[]const u8 {
            return self.spec.parameter_set.duplicateName();
        }

        pub fn duplicateParameterNameIndex(self: *const Self) ?usize {
            return self.spec.parameter_set.duplicateNameIndex();
        }

        pub fn hasDuplicateParameterIds(self: *const Self) bool {
            return self.spec.parameter_set.hasDuplicateIds();
        }

        pub fn hasDuplicateParameterNames(self: *const Self) bool {
            return self.spec.parameter_set.hasDuplicateNames();
        }

        pub fn firstParameterDescriptorError(self: *const Self) ?anyerror {
            return self.spec.parameter_set.firstDescriptorError();
        }

        pub fn firstParameterDescriptorErrorIndex(self: *const Self) ?usize {
            return self.spec.parameter_set.firstDescriptorErrorIndex();
        }

        pub fn firstParameterDescriptorErrorName(self: *const Self) ?[]const u8 {
            return self.spec.parameter_set.firstDescriptorErrorName();
        }

        pub fn validateUniqueParameterIds(self: *const Self) !void {
            try self.spec.parameter_set.validateUniqueIds();
        }

        pub fn validateUniqueParameterNames(self: *const Self) !void {
            try self.spec.parameter_set.validateUniqueNames();
        }

        pub fn validateParameterDescriptors(self: *const Self) !void {
            try self.spec.parameter_set.validateDescriptors();
        }

        pub fn validateParameters(self: *const Self) !void {
            try self.spec.parameter_set.validate();
        }

        pub fn validateParameterUnitIds(self: *const Self) !void {
            try self.spec.parameter_set.validateUnitIds(self.spec.units);
        }

        pub fn validateUnits(self: *const Self) !void {
            try self.spec.units.validateUnits();
        }

        pub fn validateProgramLists(self: *const Self) !void {
            try self.spec.units.validateProgramLists();
        }

        pub fn validateUnitSet(self: *const Self) !void {
            try self.spec.units.validate();
        }

        pub fn validateProgramParameterIds(self: *const Self) !void {
            try self.spec.units.validateProgramParameterIds(&self.spec.parameter_set);
        }

        pub fn hasParameterId(self: *const Self, id: u32) bool {
            return self.spec.parameter_set.hasId(id);
        }

        pub fn hasParameterName(self: *const Self, name: []const u8) bool {
            return self.spec.parameter_set.hasName(name);
        }

        pub fn parameterFieldIndex(self: *const Self, comptime field_name: []const u8) usize {
            return self.spec.parameter_set.indexOfField(field_name);
        }

        pub fn parameterFieldDescriptor(self: *const Self, comptime field_name: []const u8) parameters.FieldDescriptor(Plugin.Params, field_name) {
            return self.spec.parameter_set.descriptor(field_name);
        }

        pub fn parameterFieldId(self: *const Self, comptime field_name: []const u8) u32 {
            return self.spec.parameter_set.fieldId(field_name);
        }

        pub fn parameterFieldName(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.spec.parameter_set.fieldName(field_name);
        }

        pub fn parameterFieldShortName(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.spec.parameter_set.fieldShortName(field_name);
        }

        pub fn parameterFieldUnits(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.spec.parameter_set.fieldUnits(field_name);
        }

        pub fn parameterFieldDefaultNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.spec.parameter_set.fieldDefaultNormalized(field_name);
        }

        pub fn parameterFieldDefaultPlain(self: *const Self, comptime field_name: []const u8) parameters.FieldPlainType(Plugin.Params, field_name) {
            return self.spec.parameter_set.fieldDefaultPlain(field_name);
        }

        pub fn parameterFieldPlainMinimum(self: *const Self, comptime field_name: []const u8) ?f64 {
            return self.spec.parameter_set.fieldPlainMinimum(field_name);
        }

        pub fn parameterFieldPlainMaximum(self: *const Self, comptime field_name: []const u8) ?f64 {
            return self.spec.parameter_set.fieldPlainMaximum(field_name);
        }

        pub fn parameterFieldHasPlainRange(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldHasPlainRange(field_name);
        }

        pub fn parameterFieldIsBypass(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldIsBypass(field_name);
        }

        pub fn parameterFieldCanAutomate(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldCanAutomate(field_name);
        }

        pub fn parameterFieldIsReadOnly(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldIsReadOnly(field_name);
        }

        pub fn parameterFieldUnitId(self: *const Self, comptime field_name: []const u8) i32 {
            return self.spec.parameter_set.fieldUnitId(field_name);
        }

        pub fn parameterFieldStepCount(self: *const Self, comptime field_name: []const u8) i32 {
            return self.spec.parameter_set.fieldStepCount(field_name);
        }

        pub fn parameterFieldIsList(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldIsList(field_name);
        }

        pub fn parameterFieldOptionCount(self: *const Self, comptime field_name: []const u8) ?usize {
            return self.spec.parameter_set.fieldOptionCount(field_name);
        }

        pub fn parameterFieldOptionLabel(self: *const Self, comptime field_name: []const u8, option_index: usize) ?[]const u8 {
            return self.spec.parameter_set.fieldOptionLabel(field_name, option_index);
        }

        pub fn parameterFieldOptionNormalized(self: *const Self, comptime field_name: []const u8, option_index: usize) ?f64 {
            return self.spec.parameter_set.fieldOptionNormalized(field_name, option_index);
        }

        pub fn parameterFieldHasOptions(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldHasOptions(field_name);
        }

        pub fn parameterFieldOptionsEmpty(self: *const Self, comptime field_name: []const u8) bool {
            return self.spec.parameter_set.fieldOptionsEmpty(field_name);
        }

        pub fn formatParameterFieldPlain(self: *const Self, comptime field_name: []const u8, normalized: f64, buffer: []u8) ![]const u8 {
            return self.parameterView().formatFieldPlain(field_name, normalized, buffer);
        }

        pub fn parseParameterFieldPlain(self: *const Self, comptime field_name: []const u8, text: []const u8) !f64 {
            return self.parameterView().parseFieldPlain(field_name, text);
        }

        pub fn parameterFieldPlainFromNormalized(self: *const Self, comptime field_name: []const u8, normalized: f64) parameters.FieldPlainType(Plugin.Params, field_name) {
            return self.parameterView().fieldPlainFromNormalized(field_name, normalized);
        }

        pub fn parameterFieldNormalizedFromPlain(self: *const Self, comptime field_name: []const u8, plain: parameters.FieldPlainType(Plugin.Params, field_name)) f64 {
            return self.parameterView().fieldNormalizedFromPlain(field_name, plain);
        }

        pub fn parameterChangeNormalized(
            self: *const Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            normalized: f64,
        ) process_api.ParameterChange {
            return self.spec.parameter_set.parameterChangeNormalized(field_name, sample_offset, normalized);
        }

        pub fn parameterChange(
            self: *const Self,
            comptime field_name: []const u8,
            sample_offset: usize,
            plain: parameters.FieldPlainType(Plugin.Params, field_name),
        ) process_api.ParameterChange {
            return self.spec.parameter_set.parameterChange(field_name, sample_offset, plain);
        }

        pub fn loadParameterNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.parameterView().loadNormalized(field_name);
        }

        pub fn loadParameter(self: *const Self, comptime field_name: []const u8) parameters.FieldPlainType(Plugin.Params, field_name) {
            return self.parameterView().load(field_name);
        }

        pub fn loadParameterIndex(self: *const Self, index: usize) ?f64 {
            return self.parameterView().loadIndex(index);
        }

        pub fn loadParameterPlainIndex(self: *const Self, index: usize) ?f64 {
            return self.parameterView().loadPlainIndex(index);
        }

        pub fn loadParameterById(self: *const Self, id: u32) ?f64 {
            return self.parameterView().loadById(id);
        }

        pub fn loadParameterPlainById(self: *const Self, id: u32) ?f64 {
            return self.parameterView().loadPlainById(id);
        }

        pub fn loadParameterByName(self: *const Self, name: []const u8) ?f64 {
            return self.parameterView().loadByName(name);
        }

        pub fn loadParameterPlainByName(self: *const Self, name: []const u8) ?f64 {
            return self.parameterView().loadPlainByName(name);
        }

        pub fn parameterIsDefaultIndex(self: *const Self, index: usize) ?bool {
            return self.parameterView().isDefaultIndex(index);
        }

        pub fn parameterIsDefaultById(self: *const Self, id: u32) ?bool {
            return self.parameterView().isDefaultById(id);
        }

        pub fn parameterIsDefaultByName(self: *const Self, name: []const u8) ?bool {
            return self.parameterView().isDefaultByName(name);
        }

        pub fn parameterIsDefault(self: *const Self, comptime field_name: []const u8) bool {
            return self.parameterView().isDefault(field_name);
        }

        pub fn storeParameter(self: *Self, comptime field_name: []const u8, plain: parameters.FieldPlainType(Plugin.Params, field_name)) bool {
            return self.parameterEditor().store(field_name, plain);
        }

        pub fn storeParameterCount(self: *Self, comptime field_name: []const u8, plain: parameters.FieldPlainType(Plugin.Params, field_name)) ?usize {
            return self.parameterEditor().storeCount(field_name, plain);
        }

        pub fn storeParameterNormalized(self: *Self, comptime field_name: []const u8, normalized: f64) bool {
            return self.parameterEditor().storeNormalized(field_name, normalized);
        }

        pub fn storeParameterNormalizedCount(self: *Self, comptime field_name: []const u8, normalized: f64) ?usize {
            return self.parameterEditor().storeNormalizedCount(field_name, normalized);
        }

        pub fn storeParameterIndex(self: *Self, index: usize, normalized: f64) bool {
            return self.parameterEditor().storeIndex(index, normalized);
        }

        pub fn storeParameterIndexCount(self: *Self, index: usize, normalized: f64) ?usize {
            return self.parameterEditor().storeIndexCount(index, normalized);
        }

        pub fn storeParameterPlainIndex(self: *Self, index: usize, plain: f64) bool {
            return self.parameterEditor().storePlainIndex(index, plain);
        }

        pub fn storeParameterPlainIndexCount(self: *Self, index: usize, plain: f64) ?usize {
            return self.parameterEditor().storePlainIndexCount(index, plain);
        }

        pub fn storeParameterById(self: *Self, id: u32, normalized: f64) bool {
            return self.parameterEditor().storeById(id, normalized);
        }

        pub fn storeParameterByIdCount(self: *Self, id: u32, normalized: f64) ?usize {
            return self.parameterEditor().storeByIdCount(id, normalized);
        }

        pub fn storeParameterPlainById(self: *Self, id: u32, plain: f64) bool {
            return self.parameterEditor().storePlainById(id, plain);
        }

        pub fn storeParameterPlainByIdCount(self: *Self, id: u32, plain: f64) ?usize {
            return self.parameterEditor().storePlainByIdCount(id, plain);
        }

        pub fn storeParameterByName(self: *Self, name: []const u8, normalized: f64) bool {
            return self.parameterEditor().storeByName(name, normalized);
        }

        pub fn storeParameterByNameCount(self: *Self, name: []const u8, normalized: f64) ?usize {
            return self.parameterEditor().storeByNameCount(name, normalized);
        }

        pub fn storeParameterPlainByName(self: *Self, name: []const u8, plain: f64) bool {
            return self.parameterEditor().storePlainByName(name, plain);
        }

        pub fn storeParameterPlainByNameCount(self: *Self, name: []const u8, plain: f64) ?usize {
            return self.parameterEditor().storePlainByNameCount(name, plain);
        }

        pub fn resetParametersToDefaults(self: *Self) void {
            _ = self.resetParametersToDefaultsCount();
        }

        pub fn resetParametersToDefaultsCount(self: *Self) usize {
            return self.spec.values.resetToDefaultsCount(&self.spec.parameter_set);
        }

        pub fn resetParameterIndexToDefault(self: *Self, index: usize) bool {
            return self.parameterEditor().resetToDefaultIndex(index);
        }

        pub fn resetParameterIndexToDefaultCount(self: *Self, index: usize) ?usize {
            return self.parameterEditor().resetToDefaultIndexCount(index);
        }

        pub fn resetParameterToDefaultIndex(self: *Self, index: usize) bool {
            return self.resetParameterIndexToDefault(index);
        }

        pub fn resetParameterToDefaultIndexCount(self: *Self, index: usize) ?usize {
            return self.resetParameterIndexToDefaultCount(index);
        }

        pub fn resetParameterByIdToDefault(self: *Self, id: u32) bool {
            return self.parameterEditor().resetToDefaultById(id);
        }

        pub fn resetParameterByIdToDefaultCount(self: *Self, id: u32) ?usize {
            return self.parameterEditor().resetToDefaultByIdCount(id);
        }

        pub fn resetParameterToDefaultById(self: *Self, id: u32) bool {
            return self.resetParameterByIdToDefault(id);
        }

        pub fn resetParameterToDefaultByIdCount(self: *Self, id: u32) ?usize {
            return self.resetParameterByIdToDefaultCount(id);
        }

        pub fn resetParameterByNameToDefault(self: *Self, name: []const u8) bool {
            return self.parameterEditor().resetToDefaultByName(name);
        }

        pub fn resetParameterByNameToDefaultCount(self: *Self, name: []const u8) ?usize {
            return self.parameterEditor().resetToDefaultByNameCount(name);
        }

        pub fn resetParameterToDefaultByName(self: *Self, name: []const u8) bool {
            return self.resetParameterByNameToDefault(name);
        }

        pub fn resetParameterToDefaultByNameCount(self: *Self, name: []const u8) ?usize {
            return self.resetParameterByNameToDefaultCount(name);
        }

        pub fn resetParameterToDefault(self: *Self, comptime field_name: []const u8) bool {
            return self.parameterEditor().resetToDefault(field_name);
        }

        pub fn resetParameterToDefaultCount(self: *Self, comptime field_name: []const u8) ?usize {
            return self.parameterEditor().resetToDefaultCount(field_name);
        }

        pub fn applyParameterChanges(self: *Self, changes: process_api.ParameterChanges) void {
            self.spec.values.applyChanges(&self.spec.parameter_set, changes);
        }

        pub fn applyParameterChangesCount(self: *Self, changes: process_api.ParameterChanges) usize {
            return self.spec.values.applyChangesCount(&self.spec.parameter_set, changes);
        }

        pub fn applyParameterChangesChangedCount(self: *Self, changes: process_api.ParameterChanges) usize {
            return self.spec.values.applyChangesChangedCount(&self.spec.parameter_set, changes);
        }

        pub fn encodedParameterStateSize(self: *const Self) usize {
            _ = self;
            return Spec.encoded_parameter_state_size;
        }

        pub fn parameterStateEncodedSize(self: *const Self) usize {
            return self.encodedParameterStateSize();
        }

        pub fn parameterStateEntryCount(self: *const Self) usize {
            return self.spec.parameter_set.parameterCount();
        }

        pub fn parameterStateHeaderEntryCount(self: *const Self, header: state.ParameterStateHeader) usize {
            _ = self;
            return header.entryCount();
        }

        pub fn parameterStateHeaderHasEntries(self: *const Self, header: state.ParameterStateHeader) bool {
            _ = self;
            return header.hasEntries();
        }

        pub fn parameterStateHeaderHasNoEntries(self: *const Self, header: state.ParameterStateHeader) bool {
            _ = self;
            return header.hasNoEntries();
        }

        pub fn parameterStateHeaderEntriesEmpty(self: *const Self, header: state.ParameterStateHeader) bool {
            _ = self;
            return header.entriesEmpty();
        }

        pub fn parameterStateHeaderIsCurrentVersion(self: *const Self, header: state.ParameterStateHeader) bool {
            _ = self;
            return header.isCurrentVersion();
        }

        pub fn parameterStateHeaderEncodedSize(self: *const Self, header: state.ParameterStateHeader) usize {
            _ = self;
            return header.encodedSize();
        }

        pub fn parameterStateHeaderEncodedSizeChecked(self: *const Self, header: state.ParameterStateHeader) !usize {
            _ = self;
            return header.encodedSizeChecked();
        }

        pub fn parameterStateHeaderMatchesEntryCount(self: *const Self, header: state.ParameterStateHeader) bool {
            return header.matchesEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateHeaderHasFewerEntries(self: *const Self, header: state.ParameterStateHeader) bool {
            return header.hasFewerEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateHeaderHasMoreEntries(self: *const Self, header: state.ParameterStateHeader) bool {
            return header.hasMoreEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateHeaderMissingEntryCount(self: *const Self, header: state.ParameterStateHeader) usize {
            return header.missingEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateHeaderExtraEntryCount(self: *const Self, header: state.ParameterStateHeader) usize {
            return header.extraEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMatchesDecodedCount(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.matchesDecodedCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasFewerDecodedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasFewerDecodedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasMoreDecodedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasMoreDecodedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMissingDecodedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.missingDecodedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportExtraDecodedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.extraDecodedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMatchesRestoredCount(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.matchesRestoredCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasFewerRestoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasFewerRestoredEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasMoreRestoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasMoreRestoredEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMissingRestoredEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.missingRestoredEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportExtraRestoredEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.extraRestoredEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMatchesIgnoredCount(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.matchesIgnoredCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasFewerIgnoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasFewerIgnoredEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasMoreIgnoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasMoreIgnoredEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMissingIgnoredEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.missingIgnoredEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportExtraIgnoredEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.extraIgnoredEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMatchesAccountedCount(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.matchesAccountedCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasFewerAccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasFewerAccountedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasMoreAccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasMoreAccountedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMissingAccountedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.missingAccountedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportExtraAccountedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.extraAccountedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMatchesUnaccountedCount(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.matchesUnaccountedCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasFewerUnaccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasFewerUnaccountedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportHasMoreUnaccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasMoreUnaccountedEntriesThan(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportMissingUnaccountedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.missingUnaccountedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportExtraUnaccountedEntryCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            return report.extraUnaccountedEntryCount(self.parameterStateEntryCount());
        }

        pub fn parameterStateReportDecodedCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            _ = self;
            return report.decodedCount();
        }

        pub fn parameterStateReportRestoredCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            _ = self;
            return report.restoredCount();
        }

        pub fn parameterStateReportIgnoredCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            _ = self;
            return report.ignoredCount();
        }

        pub fn parameterStateReportAccountedCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            _ = self;
            return report.accountedCount();
        }

        pub fn parameterStateReportUnaccountedCount(self: *const Self, report: state.ReadParameterStateReport) usize {
            _ = self;
            return report.unaccountedCount();
        }

        pub fn parameterStateReportHasDecodedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasDecodedEntries();
        }

        pub fn parameterStateReportHasNoDecodedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasNoDecodedEntries();
        }

        pub fn parameterStateReportDecodedEntriesEmpty(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.decodedEntriesEmpty();
        }

        pub fn parameterStateReportHasRestoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasRestoredEntries();
        }

        pub fn parameterStateReportHasNoRestoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasNoRestoredEntries();
        }

        pub fn parameterStateReportRestoredEntriesEmpty(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.restoredEntriesEmpty();
        }

        pub fn parameterStateReportHasIgnoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasIgnoredEntries();
        }

        pub fn parameterStateReportHasNoIgnoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasNoIgnoredEntries();
        }

        pub fn parameterStateReportIgnoredEntriesEmpty(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.ignoredEntriesEmpty();
        }

        pub fn parameterStateReportHasAccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasAccountedEntries();
        }

        pub fn parameterStateReportHasNoAccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasNoAccountedEntries();
        }

        pub fn parameterStateReportAccountedEntriesEmpty(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.accountedEntriesEmpty();
        }

        pub fn parameterStateReportHasUnaccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasUnaccountedEntries();
        }

        pub fn parameterStateReportHasNoUnaccountedEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.hasNoUnaccountedEntries();
        }

        pub fn parameterStateReportUnaccountedEntriesEmpty(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.unaccountedEntriesEmpty();
        }

        pub fn parameterStateReportAccountedAllEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.accountedAllEntries();
        }

        pub fn parameterStateReportAccountedPartialEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.accountedPartialEntries();
        }

        pub fn parameterStateReportRestoredAllEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.restoredAllEntries();
        }

        pub fn parameterStateReportRestoredPartialEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.restoredPartialEntries();
        }

        pub fn parameterStateReportIgnoredAllEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.ignoredAllEntries();
        }

        pub fn parameterStateReportIgnoredPartialEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.ignoredPartialEntries();
        }

        pub fn parameterStateReportRestoredAndIgnoredEntries(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.restoredAndIgnoredEntries();
        }

        pub fn parameterStateReportFullyHandled(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.fullyHandled();
        }

        pub fn parameterStateReportClassification(self: *const Self, report: state.ReadParameterStateReport) state.ReadParameterStateClassification {
            _ = self;
            return report.classification();
        }

        pub fn parameterStateReportIsEmptyClassification(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.isEmptyClassification();
        }

        pub fn parameterStateReportIsRestoredAllClassification(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.isRestoredAllClassification();
        }

        pub fn parameterStateReportIsIgnoredAllClassification(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.isIgnoredAllClassification();
        }

        pub fn parameterStateReportIsRestoredAndIgnoredClassification(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.isRestoredAndIgnoredClassification();
        }

        pub fn parameterStateReportIsPartialClassification(self: *const Self, report: state.ReadParameterStateReport) bool {
            _ = self;
            return report.isPartialClassification();
        }

        pub fn readParameterStateHeader(self: *const Self, reader: anytype) !state.ParameterStateHeader {
            _ = self;
            return state.readParameterStateHeader(reader);
        }

        pub fn writeParameterState(self: *const Self, writer: anytype) !void {
            try state.writeParameterState(Plugin.Params, &self.spec.parameter_set, &self.spec.values, writer);
        }

        pub fn writeParameterStateJson(self: *const Self, writer: anytype) !void {
            try state.writeParameterStateJson(Plugin.Params, &self.spec.parameter_set, &self.spec.values, writer);
        }

        pub fn readParameterState(self: *Self, reader: anytype) !void {
            try state.readParameterState(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader);
        }

        pub fn readParameterStateReport(self: *Self, reader: anytype) !state.ReadParameterStateReport {
            return state.readParameterStateReport(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader);
        }

        pub fn readParameterStateWithMigrations(
            self: *Self,
            reader: anytype,
            migrations: []const state.ParameterIdMigration,
        ) !void {
            try state.readParameterStateWithMigrations(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader, migrations);
        }

        pub fn readParameterStateWithMigrationsReport(
            self: *Self,
            reader: anytype,
            migrations: []const state.ParameterIdMigration,
        ) !state.ReadParameterStateReport {
            return state.readParameterStateWithMigrationsReport(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader, migrations);
        }

        pub fn validateParameterIdMigrations(self: *const Self, migrations: []const state.ParameterIdMigration) !void {
            _ = self;
            try state.validateParameterIdMigrations(migrations);
        }

        pub fn identityParameterMigrationIndex(self: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            _ = self;
            return state.identityParameterMigrationIndex(migrations);
        }

        pub fn duplicateParameterMigrationIndex(self: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            _ = self;
            return state.duplicateParameterMigrationIndex(migrations);
        }

        pub fn ambiguousParameterMigrationIndex(self: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            _ = self;
            return state.ambiguousParameterMigrationIndex(migrations);
        }

        pub fn migratedParameterId(self: *const Self, id: u32, migrations: []const state.ParameterIdMigration) u32 {
            _ = self;
            return state.migratedParameterId(id, migrations);
        }

        pub fn process(self: *Self, context: *process_api.ProcessContext(f32)) void {
            self.applyParameterChanges(context.parameterChanges());
            if (Spec.has_process_with_parameter_view) {
                self.plugin.processWithParameterView(context, self.parameterView());
            } else if (Spec.has_process_with_parameters) {
                self.plugin.processWithParameters(context, &self.spec.parameter_set, &self.spec.values);
            } else if (Spec.has_process) {
                self.plugin.process(context);
            }
        }

        pub fn process64(self: *Self, context: *process_api.ProcessContext(f64)) void {
            self.applyParameterChanges(context.parameterChanges());
            if (Spec.has_process64_with_parameter_view) {
                self.plugin.process64WithParameterView(context, self.parameterView());
            } else if (Spec.has_process64_with_parameters) {
                self.plugin.process64WithParameters(context, &self.spec.parameter_set, &self.spec.values);
            } else if (Spec.has_process64) {
                self.plugin.process64(context);
            }
        }

        pub fn deinit(self: *Self) void {
            if (Spec.has_deinit) {
                self.plugin.deinit();
            }
        }
    };
}

pub fn validateLifecycle(comptime Plugin: type) void {
    if (@hasDecl(Plugin, "init")) {
        const init_info = @typeInfo(@TypeOf(Plugin.init)).@"fn";
        if (init_info.params.len != 1 or init_info.params[0].type.? != std.mem.Allocator) {
            @compileError("init must be fn (std.mem.Allocator) !Plugin");
        }
        const return_type = init_info.return_type orelse @compileError("init must return !Plugin");
        const return_info = @typeInfo(return_type);
        if (return_info != .error_union or return_info.error_union.payload != Plugin) {
            @compileError("init must return !Plugin");
        }
    }
    if (@hasDecl(Plugin, "prepare")) {
        const prepare = @typeInfo(@TypeOf(Plugin.prepare)).@"fn";
        if (prepare.params.len != 2 or prepare.params[0].type.? != *Plugin or prepare.params[1].type.? != PrepareConfig or prepare.return_type.? != void) {
            @compileError("prepare must be fn (*Plugin, PrepareConfig) void");
        }
    }
    if (@hasDecl(Plugin, "process")) {
        const process = @typeInfo(@TypeOf(Plugin.process)).@"fn";
        if (process.params.len != 2 or process.params[0].type.? != *Plugin or process.params[1].type.? != *process_api.ProcessContext(f32) or process.return_type.? != void) {
            @compileError("process must be fn (*Plugin, *process.ProcessContext(f32)) void");
        }
    }
    if (@hasDecl(Plugin, "processWithParameterView")) {
        const process = @typeInfo(@TypeOf(Plugin.processWithParameterView)).@"fn";
        if (process.params.len != 3 or
            process.params[0].type.? != *Plugin or
            process.params[1].type.? != *process_api.ProcessContext(f32) or
            process.params[2].type.? != parameters.ParameterView(Plugin.Params) or
            process.return_type.? != void)
        {
            @compileError("processWithParameterView must be fn (*Plugin, *process.ProcessContext(f32), ParameterView) void");
        }
    }
    if (@hasDecl(Plugin, "processWithParameters")) {
        const process = @typeInfo(@TypeOf(Plugin.processWithParameters)).@"fn";
        if (process.params.len != 4 or
            process.params[0].type.? != *Plugin or
            process.params[1].type.? != *process_api.ProcessContext(f32) or
            process.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process.return_type.? != void)
        {
            @compileError("processWithParameters must be fn (*Plugin, *process.ProcessContext(f32), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "process64")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64)).@"fn";
        if (process64.params.len != 2 or process64.params[0].type.? != *Plugin or process64.params[1].type.? != *process_api.ProcessContext(f64) or process64.return_type.? != void) {
            @compileError("process64 must be fn (*Plugin, *process.ProcessContext(f64)) void");
        }
    }
    if (@hasDecl(Plugin, "process64WithParameterView")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64WithParameterView)).@"fn";
        if (process64.params.len != 3 or
            process64.params[0].type.? != *Plugin or
            process64.params[1].type.? != *process_api.ProcessContext(f64) or
            process64.params[2].type.? != parameters.ParameterView(Plugin.Params) or
            process64.return_type.? != void)
        {
            @compileError("process64WithParameterView must be fn (*Plugin, *process.ProcessContext(f64), ParameterView) void");
        }
    }
    if (@hasDecl(Plugin, "process64WithParameters")) {
        const process64 = @typeInfo(@TypeOf(Plugin.process64WithParameters)).@"fn";
        if (process64.params.len != 4 or
            process64.params[0].type.? != *Plugin or
            process64.params[1].type.? != *process_api.ProcessContext(f64) or
            process64.params[2].type.? != *const parameters.ParameterSet(Plugin.Params) or
            process64.params[3].type.? != *const parameters.ParameterValues(Plugin.Params) or
            process64.return_type.? != void)
        {
            @compileError("process64WithParameters must be fn (*Plugin, *process.ProcessContext(f64), *const ParameterSet, *const ParameterValues) void");
        }
    }
    if (@hasDecl(Plugin, "deinit")) {
        const deinit = @typeInfo(@TypeOf(Plugin.deinit)).@"fn";
        if (deinit.params.len != 1 or deinit.params[0].type.? != *Plugin or deinit.return_type.? != void) {
            @compileError("deinit must be fn (*Plugin) void");
        }
    }
}

test "plugin spec exposes metadata and parameter defaults" {
    const Gain = struct {
        pub const name = "Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        };
    };
    const Spec = PluginSpec(Gain);
    var spec = Spec.init(.{});

    try std.testing.expectEqualStrings("Gain", Spec.name);
    try std.testing.expectEqualStrings("zig-vst3", Spec.vendor);
    try std.testing.expectEqualStrings("", Spec.url);
    try std.testing.expectEqualStrings("", Spec.email);
    try std.testing.expectEqualStrings("Gain", Spec.component_class_name);
    try std.testing.expectEqualStrings("Gain Controller", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Audio Module Class", Spec.component_category);
    try std.testing.expectEqualStrings("Component Controller Class", Spec.controller_category);
    try std.testing.expectEqual(@as(usize, 1), Spec.ParameterSet.count);
    try std.testing.expectEqualStrings("Gain", spec.parameter_set.name(0).?);
    try std.testing.expectEqual(@as(?u32, 0), spec.parameter_set.idByName("Gain"));
    try std.testing.expectEqual(@as(f64, 1.0), spec.values.view(&spec.parameter_set).loadNormalized("gain"));
    try std.testing.expect(spec.values.editor(&spec.parameter_set).storeNormalized("gain", 0.5));
    try std.testing.expectEqual(@as(f64, 0.5), spec.values.view(&spec.parameter_set).loadNormalized("gain"));
}

test "plugin spec and instance surface invalid parameter metadata" {
    const Duplicate = struct {
        pub const name = "Duplicate";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
            mix: parameters.FloatParam = .{ .id = 0, .name = "Mix", .min = 0.0, .max = 1.0, .default = 0.25 },
        };
    };
    const DuplicateName = struct {
        pub const name = "Duplicate Name";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.5 },
            output: parameters.FloatParam = .{ .id = 1, .name = "Level", .min = 0.0, .max = 1.0, .default = 0.25 },
        };
    };
    const Invalid = struct {
        pub const name = "Invalid";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 1.0, .max = 1.0, .default = 1.0 },
        };
    };
    const InvalidDefault = struct {
        pub const name = "Invalid Default";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = std.math.inf(f64) },
        };
    };
    const DuplicateNameSpec = PluginSpec(DuplicateName);
    const duplicate_name_set = DuplicateNameSpec.ParameterSet.init(.{});

    try std.testing.expectError(error.DuplicateParameterId, PluginSpec(Duplicate).initChecked(.{}));
    try std.testing.expectError(error.DuplicateParameterName, PluginSpec(DuplicateName).initChecked(.{}));
    try std.testing.expectEqualStrings("Level", duplicate_name_set.duplicateName().?);
    try std.testing.expectEqual(@as(?usize, 1), duplicate_name_set.duplicateNameIndex());
    try std.testing.expect(duplicate_name_set.hasDuplicateNames());
    try std.testing.expectError(error.InvalidParameterRange, PluginInstance(Invalid).init(std.testing.allocator, .{}));
    try std.testing.expectError(error.InvalidParameterDefault, PluginInstance(InvalidDefault).init(std.testing.allocator, .{}));
}

test "plugin spec rejects invalid plugin metadata" {
    const EmptyName = struct {
        pub const name = "";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const EmptyVendor = struct {
        pub const name = "Empty Vendor";
        pub const vendor = "";
        pub const Params = struct {};
    };
    const EmptyComponentName = struct {
        pub const name = "Empty Component";
        pub const vendor = "zig-vst3";
        pub const component_class_name = "";
        pub const Params = struct {};
    };
    const EmptyControllerCategory = struct {
        pub const name = "Empty Controller Category";
        pub const vendor = "zig-vst3";
        pub const controller_category = "";
        pub const Params = struct {};
    };
    const InteriorNull = struct {
        pub const name = "Interior Null";
        pub const vendor = "zig-vst3";
        pub const email = "plugins\x00example.test";
        pub const Params = struct {};
    };

    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyName).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyVendor).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyComponentName).initChecked(.{}));
    try std.testing.expectError(error.EmptyPluginMetadata, PluginSpec(EmptyControllerCategory).initChecked(.{}));
    try std.testing.expectError(error.InvalidPluginMetadata, PluginSpec(InteriorNull).initChecked(.{}));
}

test "plugin instance reports empty parameter metadata" {
    const Empty = struct {
        pub const name = "No Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    var instance = try PluginInstance(Empty).init(std.testing.allocator, .{});
    const view = instance.parameterView();
    const editor = instance.parameterEditor();

    try std.testing.expectEqual(@as(usize, 0), instance.parameterCount());
    try std.testing.expect(instance.parametersEmpty());
    try std.testing.expect(!instance.hasParameters());
    try std.testing.expectEqual(@as(usize, 0), view.parameterCount());
    try std.testing.expect(view.parametersEmpty());
    try std.testing.expect(!view.hasParameters());
    try std.testing.expectEqual(@as(usize, 0), editor.parameterCount());
    try std.testing.expect(editor.parametersEmpty());
    try std.testing.expect(!editor.hasParameters());
}

var invalid_metadata_init_called = false;

test "plugin instance validates metadata before plugin init hook" {
    invalid_metadata_init_called = false;
    const Invalid = struct {
        pub const name = "";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5 },
        };

        pub fn init(_: std.mem.Allocator) !@This() {
            invalid_metadata_init_called = true;
            return .{};
        }
    };

    try std.testing.expectError(error.EmptyPluginMetadata, PluginInstance(Invalid).init(std.testing.allocator, .{}));
    try std.testing.expect(!invalid_metadata_init_called);
}

test "plugin spec exposes optional plugin metadata overrides" {
    const Custom = struct {
        pub const name = "Custom";
        pub const vendor = "Vendor";
        pub const url = "https://example.test/custom";
        pub const email = "plugins@example.test";
        pub const component_class_name = "Custom Processor";
        pub const controller_class_name = "Custom Editor";
        pub const component_category = "Custom Processor Category";
        pub const controller_category = "Custom Controller Category";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Custom);
    var instance = try PluginInstance(Custom).init(std.testing.allocator, .{});

    try std.testing.expectEqualStrings("Custom", instance.pluginName());
    try std.testing.expectEqualStrings("Vendor", instance.pluginVendor());
    try std.testing.expectEqualStrings("https://example.test/custom", instance.pluginUrl());
    try std.testing.expectEqualStrings("plugins@example.test", instance.pluginEmail());
    try std.testing.expectEqualStrings("Custom Processor", instance.componentClassName());
    try std.testing.expectEqualStrings("Custom Editor", instance.controllerClassName());
    try std.testing.expectEqualStrings("Custom Processor Category", instance.componentCategory());
    try std.testing.expectEqualStrings("Custom Controller Category", instance.controllerCategory());
    try std.testing.expectEqualStrings("https://example.test/custom", Spec.url);
    try std.testing.expectEqualStrings("plugins@example.test", Spec.email);
    try std.testing.expectEqualStrings("Custom Processor", Spec.component_class_name);
    try std.testing.expectEqualStrings("Custom Editor", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Custom Processor Category", Spec.component_category);
    try std.testing.expectEqualStrings("Custom Controller Category", Spec.controller_category);
}

test "plugin spec exposes optional bus topology metadata" {
    const DefaultEffect = struct {
        pub const name = "Default Effect";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Analyzer = struct {
        pub const name = "Analyzer";
        pub const vendor = "zig-vst3";
        pub const audio_output = false;
        pub const Params = struct {};
    };
    const Generator = struct {
        pub const name = "Generator";
        pub const vendor = "zig-vst3";
        pub const audio_input = false;
        pub const event_output = true;
        pub const Params = struct {};
    };
    const ControlOnly = struct {
        pub const name = "Control Only";
        pub const vendor = "zig-vst3";
        pub const audio_input = false;
        pub const audio_output = false;
        pub const event_input = false;
        pub const Params = struct {};
    };

    try std.testing.expect(PluginSpec(DefaultEffect).audio_input);
    try std.testing.expect(PluginSpec(DefaultEffect).audio_output);
    try std.testing.expect(PluginSpec(DefaultEffect).event_input);
    try std.testing.expect(!PluginSpec(DefaultEffect).event_output);
    try std.testing.expect(PluginSpec(Analyzer).audio_input);
    try std.testing.expect(!PluginSpec(Analyzer).audio_output);
    try std.testing.expect(!PluginSpec(Generator).audio_input);
    try std.testing.expect(PluginSpec(Generator).audio_output);
    try std.testing.expect(PluginSpec(Generator).event_output);
    try std.testing.expect(!PluginSpec(ControlOnly).audio_input);
    try std.testing.expect(!PluginSpec(ControlOnly).audio_output);
    try std.testing.expect(!PluginSpec(ControlOnly).event_input);
}

test "plugin spec exposes default root unit metadata" {
    const Gain = struct {
        pub const name = "Unitless Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Gain);
    var spec = Spec.init(.{});

    try std.testing.expectEqual(@as(usize, 1), spec.units.unitCount());
    try std.testing.expectEqual(@as(usize, 0), spec.units.programListCount());
    try std.testing.expectEqual(units_api.root_unit_id, spec.units.rootUnit().id);
    try std.testing.expectEqualStrings("Root", spec.units.rootUnit().name);
}

test "plugin spec rejects invalid unit metadata" {
    const InvalidUnits = struct {
        pub const name = "Invalid Units";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Voice", .parent_id = 99 },
            },
        };
    };

    try std.testing.expectError(error.InvalidUnitParent, PluginSpec(InvalidUnits).initChecked(.{}));
}

test "plugin spec rejects ambiguous unit metadata names" {
    const DuplicateUnitNames = struct {
        pub const name = "Duplicate Unit Names";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Root", .parent_id = units_api.root_unit_id },
            },
        };
    };
    const DuplicateProgramListNames = struct {
        pub const name = "Duplicate Program List Names";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .program_lists = &.{
                .{ .id = 1, .name = "Programs" },
                .{ .id = 2, .name = "Programs" },
            },
        };
    };

    try std.testing.expectError(error.DuplicateUnitName, PluginSpec(DuplicateUnitNames).initChecked(.{}));
    try std.testing.expectError(error.DuplicateProgramListName, PluginSpec(DuplicateProgramListNames).initChecked(.{}));
}

test "plugin spec rejects reserved unit metadata ids" {
    const ReservedUnit = struct {
        pub const name = "Reserved Unit";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = units_api.no_parent_unit_id, .name = "Reserved", .parent_id = units_api.root_unit_id },
            },
        };
    };
    const ReservedProgramList = struct {
        pub const name = "Reserved Program List";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = units_api.no_program_list_id, .name = "Reserved" }},
        };
    };

    try std.testing.expectError(error.ReservedUnitId, PluginSpec(ReservedUnit).initChecked(.{}));
    try std.testing.expectError(error.ReservedProgramListId, PluginSpec(ReservedProgramList).initChecked(.{}));
}

test "plugin spec rejects parameters linked to unknown units" {
    const InvalidParameterUnit = struct {
        pub const name = "Invalid Parameter Unit";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{};
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = 0.0, .max = 1.0, .default = 0.5, .unit_id = 99 },
        };
    };

    try std.testing.expectError(error.InvalidParameterUnit, PluginSpec(InvalidParameterUnit).initChecked(.{}));
}

test "plugin instance exposes custom unit and program metadata" {
    const programs = [_]units_api.Program{
        .{
            .name = "Clean",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.25 }},
            .info = &.{.{ .key = "category", .value = "Clean" }},
        },
        .{
            .name = "Lead",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.75 }},
        },
    };
    const Synth = struct {
        pub const name = "Unit Synth";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Main"),
                .{ .id = 1, .name = "Voice", .parent_id = units_api.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{
                .{ .id = 7, .name = "Voice Programs", .programs = &programs },
            },
        };
    };
    const Instance = PluginInstance(Synth);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(usize, 2), instance.unitCount());
    try std.testing.expect(!instance.unitsEmpty());
    try std.testing.expect(instance.hasUnits());
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateUnitId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitIdIndex());
    try std.testing.expect(!instance.hasDuplicateUnitIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateUnitName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateUnitNameIndex());
    try std.testing.expect(!instance.hasDuplicateUnitNames());
    try std.testing.expectEqualStrings("Main", instance.rootUnit().name);
    try std.testing.expectEqual(units_api.root_unit_id, instance.rootUnitId());
    try std.testing.expectEqualStrings("Main", instance.rootUnitName());
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfId(1));
    try std.testing.expectEqual(@as(?usize, null), instance.unitIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 1), instance.unitIndexOfName("Voice"));
    try std.testing.expectEqual(@as(?usize, null), instance.unitIndexOfName("Missing"));
    try std.testing.expectEqualStrings("Voice", instance.unitById(1).?.name);
    try std.testing.expectEqual(@as(i32, 1), instance.unitByName("Voice").?.id);
    try std.testing.expectEqual(@as(?units_api.Unit, null), instance.unitByName("Missing"));
    try std.testing.expect(instance.hasUnit(1));
    try std.testing.expect(!instance.hasUnit(99));
    try std.testing.expect(instance.hasUnitName("Voice"));
    try std.testing.expect(!instance.hasUnitName("Missing"));
    try std.testing.expect(instance.unitIsRoot(units_api.root_unit_id));
    try std.testing.expect(instance.unitIsRootByName("Main"));
    try std.testing.expect(!instance.unitIsRoot(1));
    try std.testing.expect(!instance.unitIsRootByName("Voice"));
    try std.testing.expect(!instance.unitIsRootByName("Missing"));
    try std.testing.expect(!instance.unitHasParent(units_api.root_unit_id));
    try std.testing.expect(instance.unitHasParent(1));
    try std.testing.expect(instance.unitHasParentByName("Voice"));
    try std.testing.expect(!instance.unitHasParentByName("Missing"));
    try std.testing.expectEqual(@as(?i32, units_api.root_unit_id), instance.unitParentId(1));
    try std.testing.expectEqual(@as(?i32, units_api.root_unit_id), instance.unitParentIdByName("Voice"));
    try std.testing.expectEqual(@as(?i32, null), instance.unitParentId(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), instance.unitParentIdByName("Missing"));
    try std.testing.expect(instance.unitHasProgramList(1));
    try std.testing.expect(instance.unitHasProgramListByName("Voice"));
    try std.testing.expect(!instance.unitHasProgramList(units_api.root_unit_id));
    try std.testing.expect(!instance.unitHasProgramListByName("Missing"));
    try std.testing.expectEqual(@as(usize, 1), instance.programListCount());
    try std.testing.expect(!instance.programListsEmpty());
    try std.testing.expect(instance.hasProgramLists());
    try std.testing.expectEqual(@as(?i32, null), instance.duplicateProgramListId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListIdIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListIds());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramListName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramListNameIndex());
    try std.testing.expect(!instance.hasDuplicateProgramListNames());
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfId(7));
    try std.testing.expectEqual(@as(?usize, null), instance.programListIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 0), instance.programListIndexOfName("Voice Programs"));
    try std.testing.expectEqual(@as(?usize, null), instance.programListIndexOfName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListById(7).?.name);
    try std.testing.expectEqual(@as(i32, 7), instance.programListByName("Voice Programs").?.id);
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListByName("Missing"));
    try std.testing.expect(instance.hasProgramList(7));
    try std.testing.expect(!instance.hasProgramList(99));
    try std.testing.expect(instance.hasProgramListName("Voice Programs"));
    try std.testing.expect(!instance.hasProgramListName("Missing"));
    try std.testing.expect(instance.programListHasPrograms(7));
    try std.testing.expect(instance.programListHasProgramsByName("Voice Programs"));
    try std.testing.expect(!instance.programListHasPrograms(99));
    try std.testing.expect(!instance.programListHasProgramsByName("Missing"));
    try std.testing.expect(!instance.programListEmpty(7));
    try std.testing.expect(!instance.programListEmptyByName("Voice Programs"));
    try std.testing.expect(instance.programListEmpty(99));
    try std.testing.expect(instance.programListEmptyByName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListForUnit(1).?.name);
    try std.testing.expectEqualStrings("Voice Programs", instance.programListForUnitName("Voice").?.name);
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListForUnitName("Main"));
    try std.testing.expectEqual(@as(?units_api.ProgramList, null), instance.programListForUnitName("Missing"));
    try std.testing.expectEqual(@as(?i32, 7), instance.programListIdForUnit(1));
    try std.testing.expectEqual(@as(?i32, 7), instance.programListIdForUnitName("Voice"));
    try std.testing.expectEqual(@as(?i32, null), instance.programListIdForUnit(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?i32, null), instance.programListIdForUnitName("Missing"));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListNameForUnit(1).?);
    try std.testing.expectEqualStrings("Voice Programs", instance.programListNameForUnitName("Voice").?);
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programListNameForUnit(units_api.root_unit_id));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programListNameForUnitName("Missing"));
    try std.testing.expectEqual(@as(?usize, 2), instance.programCount(7));
    try std.testing.expectEqual(@as(?usize, 2), instance.programCountByName("Voice Programs"));
    try std.testing.expectEqual(@as(?usize, null), instance.programCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.programCountByName("Missing"));
    try std.testing.expectEqualStrings("Lead", instance.programName(7, 1).?);
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programName(7, 99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programName(99, 0));
    try std.testing.expectEqualStrings("Lead", instance.program(7, 1).?.name);
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.program(7, 99));
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.program(99, 0));
    try std.testing.expectEqualStrings("Lead", instance.programByName(7, "Lead").?.name);
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.programByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.Program, null), instance.programByName(99, "Lead"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programIndexOfName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programIndexOfName(99, "Lead"));
    try std.testing.expect(instance.hasProgramName(7, "Lead"));
    try std.testing.expect(!instance.hasProgramName(7, "Missing"));
    try std.testing.expect(!instance.hasProgramName(99, "Lead"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramName(7));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramNameIndex(7));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramName(99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramNameIndex(99));
    try std.testing.expect(!instance.hasDuplicateProgramNames(7));
    try std.testing.expect(!instance.hasDuplicateProgramNames(99));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCount(7, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCount(99, 0));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCountByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterCountByName(99, "Lead"));
    try std.testing.expect(instance.programHasParameters(7, 0));
    try std.testing.expect(instance.programHasParametersByName(7, "Lead"));
    try std.testing.expect(!instance.programHasParameters(7, 99));
    try std.testing.expect(!instance.programHasParametersByName(7, "Missing"));
    try std.testing.expect(!instance.programParametersEmpty(7, 0));
    try std.testing.expect(!instance.programParametersEmptyByName(7, "Lead"));
    try std.testing.expect(instance.programParametersEmpty(7, 99));
    try std.testing.expect(instance.programParametersEmptyByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameter(7, 1, 99));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameter(99, 0, 0));
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterById(7, 1, 1).?.normalized);
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterById(99, 0, 1));
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterByName(7, "Lead", 0).?.normalized);
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterByNameAndId(7, "Lead", 1).?.normalized);
    try std.testing.expect(instance.hasProgramParameter(7, 1, 1));
    try std.testing.expect(!instance.hasProgramParameter(7, 1, 99));
    try std.testing.expect(!instance.hasProgramParameter(99, 1, 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterId(7, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndex(7, 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterId(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndex(7, 99));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIds(7, 1));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIds(7, 99));
    try std.testing.expect(instance.hasProgramParameterByName(7, "Lead", 1));
    try std.testing.expect(!instance.hasProgramParameterByName(7, "Lead", 99));
    try std.testing.expect(!instance.hasProgramParameterByName(7, "Missing", 1));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterIdByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndexByName(7, "Lead"));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateProgramParameterIdByName(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramParameterIdIndexByName(7, "Missing"));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIdsByName(7, "Lead"));
    try std.testing.expect(!instance.hasDuplicateProgramParameterIdsByName(7, "Missing"));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByName(7, "Missing", 0));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByName(99, "Lead", 0));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByNameAndId(7, "Lead", 99));
    try std.testing.expectEqual(@as(?units_api.ProgramParameter, null), instance.programParameterByNameAndId(99, "Lead", 1));
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfId(7, 1, 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfId(7, 1, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfId(7, 99, 1));
    try std.testing.expectEqual(@as(?usize, 0), instance.programParameterIndexOfIdByName(7, "Lead", 1));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfIdByName(7, "Lead", 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programParameterIndexOfIdByName(7, "Missing", 1));
    try std.testing.expectEqualStrings("Clean", instance.programInfo(7, 0, "category").?);
    try std.testing.expectEqualStrings("category", instance.programInfoEntry(7, 0, 0).?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntry(7, 0, 0).?.value);
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntry(7, 0, 1));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntry(7, 99, 0));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKey(7, 0, "category"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKey(7, 0, "missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKey(7, 99, "category"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programInfoCount(7, 0));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoCountByName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoCountByName(7, "Missing"));
    try std.testing.expect(instance.programHasInfoEntries(7, 0));
    try std.testing.expect(instance.programHasInfoEntriesByName(7, "Clean"));
    try std.testing.expect(!instance.programHasInfoEntries(7, 1));
    try std.testing.expect(!instance.programHasInfoEntriesByName(7, "Lead"));
    try std.testing.expect(!instance.programInfoEmpty(7, 0));
    try std.testing.expect(instance.programInfoEmpty(7, 1));
    try std.testing.expect(instance.programInfoEmpty(7, 99));
    try std.testing.expect(instance.programInfoEmptyByName(7, "Missing"));
    try std.testing.expect(instance.hasProgramInfo(7, 0, "category"));
    try std.testing.expect(!instance.hasProgramInfo(7, 0, "missing"));
    try std.testing.expect(!instance.hasProgramInfo(7, 99, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKey(7, 0));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndex(7, 0));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKey(7, 99));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndex(7, 99));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeys(7, 0));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeys(7, 99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfo(7, 99, "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfo(99, 0, "category"));
    try std.testing.expectEqualStrings("Clean", instance.programInfoByName(7, "Clean", "category").?);
    try std.testing.expectEqualStrings("category", instance.programInfoEntryByName(7, "Clean", 0).?.key);
    try std.testing.expectEqualStrings("Clean", instance.programInfoEntryByName(7, "Clean", 0).?.value);
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByName(7, "Clean", 1));
    try std.testing.expectEqual(@as(?units_api.ProgramInfo, null), instance.programInfoEntryByName(7, "Missing", 0));
    try std.testing.expectEqual(@as(?usize, 0), instance.programInfoIndexOfKeyByName(7, "Clean", "category"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKeyByName(7, "Clean", "missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.programInfoIndexOfKeyByName(7, "Missing", "category"));
    try std.testing.expect(instance.hasProgramInfoByName(7, "Clean", "category"));
    try std.testing.expect(!instance.hasProgramInfoByName(7, "Clean", "missing"));
    try std.testing.expect(!instance.hasProgramInfoByName(7, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKeyByName(7, "Clean"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndexByName(7, "Clean"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateProgramInfoKeyByName(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateProgramInfoKeyIndexByName(7, "Missing"));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeysByName(7, "Clean"));
    try std.testing.expect(!instance.hasDuplicateProgramInfoKeysByName(7, "Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfoByName(7, "Missing", "category"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.programInfoByName(99, "Clean", "category"));
}

test "plugin instance applies program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Low",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.25 }},
        },
        .{
            .name = "High",
            .parameters = &.{.{ .parameter_id = 1, .normalized = 0.75 }},
        },
    };
    const Gain = struct {
        pub const name = "Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .units = &.{
                units_api.Unit.root("Root"),
                .{ .id = 1, .name = "Amp", .parent_id = units_api.root_unit_id, .program_list_id = 7 },
            },
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };
    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramCount(7, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 0), try instance.applyProgramCount(7, 0));
    try std.testing.expect(try instance.applyProgram(7, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameCount(7, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByName(7, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramCount(7, 99));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameCount(7, "Missing"));
    try std.testing.expect(!try instance.applyProgram(7, 99));
    try std.testing.expect(!try instance.applyProgramByName(7, "Missing"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitCount(1, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramForUnit(1, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitCount(1, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByNameForUnit(1, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramForUnitNameCount("Amp", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramForUnitName("Amp", 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, 1), try instance.applyProgramByNameForUnitNameCount("Amp", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByNameForUnitName("Amp", "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramForUnitCount(99, 0));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameForUnitCount(1, "Missing"));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramForUnitNameCount("Root", 0));
    try std.testing.expectEqual(@as(?usize, null), try instance.applyProgramByNameForUnitNameCount("Missing", "High"));
    try std.testing.expect(!try instance.applyProgramForUnit(99, 0));
    try std.testing.expect(!try instance.applyProgramByNameForUnit(1, "Missing"));
    try std.testing.expect(!try instance.applyProgramForUnitName("Root", 0));
    try std.testing.expect(!try instance.applyProgramByNameForUnitName("Missing", "High"));
}

test "plugin spec rejects invalid program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Invalid",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = 0.25 },
                .{ .parameter_id = 2, .normalized = 1.5 },
            },
        },
    };
    const Gain = struct {
        pub const name = "Invalid Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
            mix: parameters.FloatParam = parameters.FloatParam.init(2, "Mix", 0.0, 1.0, 0.5),
        };
    };

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec rejects non-finite program parameter snapshots" {
    const programs = [_]units_api.Program{
        .{
            .name = "Invalid",
            .parameters = &.{
                .{ .parameter_id = 1, .normalized = std.math.inf(f64) },
            },
        },
    };
    const Gain = struct {
        pub const name = "Invalid Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec rejects unknown program parameter ids" {
    const programs = [_]units_api.Program{
        .{
            .name = "Unknown",
            .parameters = &.{
                .{ .parameter_id = 99, .normalized = 0.75 },
            },
        },
    };
    const Gain = struct {
        pub const name = "Unknown Program Gain";
        pub const vendor = "zig-vst3";
        pub const units = units_api.Config{
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };

    try std.testing.expectError(error.UnknownProgramParameter, PluginSpec(Gain).initChecked(.{}));
}

test "plugin spec detects lifecycle declarations" {
    const Meter = struct {
        pub const name = "Meter";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(_: *@This(), _: PrepareConfig) void {}
        pub fn process(_: *@This(), _: *process_api.ProcessContext(f32)) void {}
        pub fn processWithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn process64(_: *@This(), _: *process_api.ProcessContext(f64)) void {}
        pub fn process64WithParameters(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {}
        pub fn deinit(_: *@This()) void {}
    };
    const Spec = PluginSpec(Meter);
    validateLifecycle(Meter);

    try std.testing.expect(Spec.has_init);
    try std.testing.expect(Spec.has_prepare);
    try std.testing.expect(Spec.has_process);
    try std.testing.expect(Spec.has_process_with_parameters);
    try std.testing.expect(Spec.has_process64);
    try std.testing.expect(Spec.has_process64_with_parameters);
    try std.testing.expect(Spec.has_deinit);
}

test "plugin instance exposes bus and lifecycle predicates" {
    const Meter = struct {
        pub const name = "Predicate Meter";
        pub const vendor = "zig-vst3";
        pub const audio_output = false;
        pub const event_output = true;
        pub const Params = struct {};

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(_: *@This(), _: PrepareConfig) void {}
        pub fn processWithParameterView(
            _: *@This(),
            _: *process_api.ProcessContext(f32),
            _: parameters.ParameterView(Params),
        ) void {}
        pub fn process64WithParameterView(
            _: *@This(),
            _: *process_api.ProcessContext(f64),
            _: parameters.ParameterView(Params),
        ) void {}
        pub fn deinit(_: *@This()) void {}
    };

    var instance = try PluginInstance(Meter).init(std.testing.allocator, .{});
    defer instance.deinit();

    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(!instance.hasAudioOutput());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(instance.hasEventOutput());
    try std.testing.expect(instance.hasInitHook());
    try std.testing.expect(instance.hasPrepareHook());
    try std.testing.expect(instance.hasProcessHook());
    try std.testing.expect(instance.hasProcess64Hook());
    try std.testing.expect(instance.hasAnyProcessHook());
    try std.testing.expect(instance.hasDeinitHook());
}

test "plugin spec allows declaration-only plugin types" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Minimal);
    var instance = try PluginInstance(Minimal).init(std.testing.allocator, .{});

    try std.testing.expect(!Spec.has_init);
    try std.testing.expect(!Spec.has_prepare);
    try std.testing.expect(!Spec.has_process);
    try std.testing.expect(!Spec.has_process_with_parameters);
    try std.testing.expect(!Spec.has_process64);
    try std.testing.expect(!Spec.has_process64_with_parameters);
    try std.testing.expect(!Spec.has_deinit);
    try std.testing.expect(instance.hasAudioInput());
    try std.testing.expect(instance.hasAudioOutput());
    try std.testing.expect(instance.hasEventInput());
    try std.testing.expect(!instance.hasEventOutput());
    try std.testing.expect(!instance.hasInitHook());
    try std.testing.expect(!instance.hasPrepareHook());
    try std.testing.expect(!instance.hasProcessHook());
    try std.testing.expect(!instance.hasProcess64Hook());
    try std.testing.expect(!instance.hasAnyProcessHook());
    try std.testing.expect(!instance.hasDeinitHook());
}

test "plugin instance drives declared lifecycle hooks" {
    const Gain = struct {
        prepared: bool = false,
        processed: bool = false,
        deinitialized: bool = false,

        pub const name = "Instance Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn init(_: std.mem.Allocator) !@This() {
            return .{};
        }

        pub fn prepare(self: *@This(), config: PrepareConfig) void {
            self.prepared = config.sample_rate == 48_000.0 and config.max_block_size == 64;
        }

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.processed = true;
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * 0.5;
                }
            }
        }

        pub fn deinit(self: *@This()) void {
            self.deinitialized = true;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f32{ 0.25, 0.5 };
    var output = [_]f32{ 0.0, 0.0 };
    const input_channels = [_][]const f32{&input};
    const output_channels = [_][]f32{&output};
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f32).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f32).init(&output_channels),
    };

    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 64 });
    instance.process(&context);
    instance.deinit();

    try std.testing.expect(instance.plugin.prepared);
    try std.testing.expect(instance.plugin.processed);
    try std.testing.expect(instance.plugin.deinitialized);
    try std.testing.expectEqual(@as(f32, 0.125), output[0]);
    try std.testing.expectEqual(@as(f32, 0.25), output[1]);
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("gain"));
}

test "plugin instance validates prepare configuration" {
    const Gain = struct {
        prepared: bool = false,

        pub const name = "Prepare Validation Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn prepare(self: *@This(), _: PrepareConfig) void {
            self.prepared = true;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = 0.0, .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, (PrepareConfig{ .sample_rate = std.math.inf(f64), .max_block_size = 64 }).validate());
    try std.testing.expectError(error.InvalidMaxBlockSize, (PrepareConfig{ .sample_rate = 48_000.0, .max_block_size = 0 }).validate());
    try std.testing.expectError(error.InvalidSampleRate, instance.prepareChecked(.{ .sample_rate = std.math.nan(f64), .max_block_size = 64 }));
    try std.testing.expect(!instance.plugin.prepared);

    try instance.prepareChecked(.{ .sample_rate = 48_000.0, .max_block_size = 64 });
    try std.testing.expect(instance.plugin.prepared);
}

test "plugin instance applies parameter changes to owned values" {
    const Gain = struct {
        pub const name = "Instance Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
        .{ .id = 99, .sample_offset = 0, .normalized = 1.0 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));
    try std.testing.expectEqual(@as(usize, 0), instance.applyParameterChangesChangedCount(view));

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterView().loadById(99));

    instance.storeParameterNormalized("gain", 0.5);
    instance.applyParameterChanges(view);
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
}

test "plugin instance counts only applied automatable parameter changes" {
    const Gain = struct {
        pub const name = "Instance Parameter Apply Count";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .can_automate = false },
            meter: parameters.FloatParam = .{ .id = 2, .name = "Meter", .is_read_only = true },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        .{ .id = 0, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 1, .sample_offset = 0, .normalized = 1.0 },
        .{ .id = 2, .sample_offset = 0, .normalized = 0.75 },
        .{ .id = 99, .sample_offset = 0, .normalized = 0.5 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));
    try std.testing.expectEqual(@as(usize, 0), instance.applyParameterChangesChangedCount(view));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameterNormalized("bypass"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameterNormalized("meter"));
}

test "plugin instance exposes typed parameter field access" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Field Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .short_name = "G", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .can_automate = false, .is_read_only = true, .is_bypass = true },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 2), instance.parameterIndexOfName("Mode"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfName("Missing"));
    try std.testing.expectEqual(@as(?u32, null), instance.duplicateParameterId());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterIdIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.duplicateParameterName());
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterNameIndex());
    try std.testing.expect(!instance.hasDuplicateParameterIds());
    try std.testing.expect(!instance.hasDuplicateParameterNames());
    try std.testing.expectEqual(@as(?anyerror, null), instance.firstParameterDescriptorError());
    try std.testing.expectEqual(@as(?usize, null), instance.firstParameterDescriptorErrorIndex());
    try std.testing.expectEqual(@as(?[]const u8, null), instance.firstParameterDescriptorErrorName());
    try std.testing.expect(instance.hasParameterId(0));
    try std.testing.expect(!instance.hasParameterId(99));
    try std.testing.expect(instance.hasParameterName("Mode"));
    try std.testing.expect(!instance.hasParameterName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), instance.parameterCount());
    try std.testing.expect(!instance.parametersEmpty());
    try std.testing.expect(instance.hasParameters());
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expect(!instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 0), instance.parameterNonDefaultCount());
    try std.testing.expectEqual(@as(?u32, 0), instance.parameterId(0));
    try std.testing.expectEqualStrings("Bypass", instance.parameterName(1).?);
    try std.testing.expectEqualStrings("Mode", instance.parameterNameById(2).?);
    try std.testing.expectEqual(@as(?u32, 2), instance.parameterIdByName("Mode"));
    try std.testing.expectEqualStrings("G", instance.parameterShortName(0).?);
    try std.testing.expectEqualStrings("G", instance.parameterShortNameById(0).?);
    try std.testing.expectEqualStrings("G", instance.parameterShortNameByName("Gain").?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnits(0).?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnitsById(0).?);
    try std.testing.expectEqualStrings("dB", instance.parameterUnitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalized(2));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedById(2));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlain(0));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlainById(1));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterPlainMinimum(0));
    try std.testing.expectEqual(@as(?f64, 6.0), instance.parameterPlainMaximumById(0));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterPlainMinimumByName("Gain"));
    try std.testing.expect(instance.parameterHasPlainRange(0));
    try std.testing.expect(instance.parameterHasPlainRangeById(0));
    try std.testing.expect(instance.parameterHasPlainRangeByName("Gain"));
    try std.testing.expect(!instance.parameterHasPlainRange(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypass(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterCanAutomateById(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterCanAutomateByName("Bypass"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnlyById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsReadOnlyByName("Bypass"));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitId(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitIdById(0));
    try std.testing.expectEqual(@as(?i32, 0), instance.parameterUnitIdByName("Gain"));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCount(2));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountById(2));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsList(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsListById(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsListByName("Mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCount(2));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountById(2));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterOptionCountByName("Mode"));
    try std.testing.expectEqualStrings("mute", instance.parameterOptionLabel(2, 2).?);
    try std.testing.expectEqualStrings("boost", instance.parameterOptionLabelById(2, 1).?);
    try std.testing.expectEqualStrings("clean", instance.parameterOptionLabelByName("Mode", 0).?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterOptionNormalized(2, 2));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.parameterOptionNormalizedById(2, 1));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterOptionNormalizedByName("Mode", 0));
    try std.testing.expect(instance.parameterHasOptions(2));
    try std.testing.expect(!instance.parameterOptionsEmpty(2));
    try std.testing.expect(instance.parameterHasOptionsById(2));
    try std.testing.expect(!instance.parameterOptionsEmptyById(2));
    try std.testing.expect(instance.parameterHasOptionsByName("Mode"));
    try std.testing.expect(!instance.parameterOptionsEmptyByName("Mode"));
    try std.testing.expect(!instance.parameterHasOptions(0));
    try std.testing.expect(instance.parameterOptionsEmpty(0));
    try std.testing.expectEqual(@as(?u32, null), instance.parameterId(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterName(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterNameById(99));
    try std.testing.expectEqual(@as(?u32, null), instance.parameterIdByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterShortNameByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterUnitsByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultNormalizedById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultNormalizedByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultPlainById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultPlainByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainMinimumById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainMaximumByName("Missing"));
    try std.testing.expect(!instance.parameterHasPlainRangeById(99));
    try std.testing.expect(!instance.parameterHasPlainRangeByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsBypassByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterCanAutomateById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterCanAutomateByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsReadOnlyById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsReadOnlyByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterUnitIdByName("Missing"));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterStepCountById(99));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterStepCountByName("Missing"));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsListById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsListByName("Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterOptionCountById(99));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterOptionCountByName("Missing"));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterOptionLabel(2, 3));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterOptionLabelByName("Missing", 0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterOptionNormalized(2, 3));
    try std.testing.expect(!instance.parameterHasOptionsById(99));
    try std.testing.expect(instance.parameterOptionsEmptyById(99));
    try std.testing.expect(!instance.parameterHasOptionsByName("Missing"));
    try std.testing.expect(instance.parameterOptionsEmptyByName("Missing"));
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("lead", try instance.formatParameterPlainIndex(2, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainIndex(2, "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedIndex(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainIndex(2, 2.0));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlainById(2, 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainById(2, "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedById(2, 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainById(2, 2.0));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterPlainByName("Mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterPlainByName("Mode", "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), instance.parameterPlainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterNormalizedFromPlainByName("Mode", 2.0));
    try std.testing.expectError(error.InvalidParameterIndex, instance.formatParameterPlainIndex(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterIndex, instance.parseParameterPlainIndex(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedIndex(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainIndex(99, 0.0));
    try std.testing.expectError(error.InvalidParameterId, instance.formatParameterPlainById(99, 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterId, instance.parseParameterPlainById(99, "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedById(99, 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainById(99, 0.0));
    try std.testing.expectError(error.InvalidParameterName, instance.formatParameterPlainByName("Missing", 0.0, &buffer));
    try std.testing.expectError(error.InvalidParameterName, instance.parseParameterPlainByName("Missing", "1"));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterPlainFromNormalizedByName("Missing", 0.0));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterNormalizedFromPlainByName("Missing", 0.0));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterFieldIndex("gain"));
    try std.testing.expectEqual(@as(u32, 0), instance.parameterFieldDescriptor("gain").id);
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldDescriptor("gain").name);
    try std.testing.expectEqual(@as(u32, 2), instance.parameterFieldId("mode"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldName("gain"));
    try std.testing.expectEqualStrings("G", instance.parameterFieldShortName("gain"));
    try std.testing.expectEqualStrings("dB", instance.parameterFieldUnits("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.parameterFieldDefaultNormalized("mode"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.parameterFieldDefaultPlain("gain"));
    try std.testing.expectEqual(Mode.clean, instance.parameterFieldDefaultPlain("mode"));
    try std.testing.expectEqual(@as(?f64, -12.0), instance.parameterFieldPlainMinimum("gain"));
    try std.testing.expectEqual(@as(?f64, 6.0), instance.parameterFieldPlainMaximum("gain"));
    try std.testing.expect(instance.parameterFieldHasPlainRange("gain"));
    try std.testing.expect(!instance.parameterFieldHasPlainRange("mode"));
    try std.testing.expect(instance.parameterFieldIsBypass("bypass"));
    try std.testing.expect(instance.parameterFieldCanAutomate("gain"));
    try std.testing.expect(!instance.parameterFieldCanAutomate("bypass"));
    try std.testing.expect(instance.parameterFieldIsReadOnly("bypass"));
    try std.testing.expectEqual(@as(i32, 0), instance.parameterFieldUnitId("gain"));
    try std.testing.expectEqual(@as(i32, 2), instance.parameterFieldStepCount("mode"));
    try std.testing.expect(instance.parameterFieldIsList("mode"));
    try std.testing.expectEqual(@as(?usize, 3), instance.parameterFieldOptionCount("mode"));
    try std.testing.expectEqualStrings("mute", instance.parameterFieldOptionLabel("mode", 2).?);
    try std.testing.expectEqual(@as(?f64, 1.0), instance.parameterFieldOptionNormalized("mode", 2));
    try std.testing.expect(instance.parameterFieldHasOptions("mode"));
    try std.testing.expect(!instance.parameterFieldOptionsEmpty("mode"));
    try std.testing.expect(!instance.parameterFieldHasOptions("gain"));
    try std.testing.expect(instance.parameterFieldOptionsEmpty("gain"));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterFieldPlain("mode", "mute"));
    try std.testing.expectEqual(Mode.mute, instance.parameterFieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldNormalizedFromPlain("mode", .mute));
    try std.testing.expectEqual(process_api.ParameterChange{
        .id = 2,
        .sample_offset = 4,
        .normalized = 1.0,
    }, instance.parameterChange("mode", 4, .mute));
    try std.testing.expectEqual(process_api.ParameterChange{
        .id = 0,
        .sample_offset = 5,
        .normalized = 0.25,
    }, instance.parameterChangeNormalized("gain", 5, 0.25));

    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.5));
    try std.testing.expect(instance.storeParameterIndex(0, 0.75));
    try std.testing.expect(instance.storeParameterPlainIndex(0, 6.0));
    try std.testing.expect(instance.storeParameterById(1, 0.0));
    try std.testing.expect(instance.storeParameterPlainById(0, 6.0));
    try std.testing.expect(instance.storeParameterByName("Mode", 0.5));
    try std.testing.expect(instance.storeParameterPlainByName("Gain", 3.0));
    try std.testing.expect(!instance.storeParameterNormalized("gain", std.math.nan(f64)));
    try std.testing.expect(!instance.storeParameterIndex(0, std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterById(0, -std.math.inf(f64)));
    try std.testing.expect(!instance.storeParameterByName("Gain", std.math.nan(f64)));
    try std.testing.expect(!instance.storeParameterIndex(99, 1.0));
    try std.testing.expect(!instance.storeParameterPlainIndex(99, 1.0));
    try std.testing.expect(!instance.storeParameterById(99, 1.0));
    try std.testing.expect(!instance.storeParameterPlainById(99, 1.0));
    try std.testing.expect(!instance.storeParameterByName("Missing", 1.0));
    try std.testing.expect(!instance.storeParameterPlainByName("Missing", 1.0));

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(f64, 3.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.boost, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("mode"));
    try std.testing.expectApproxEqAbs(0.8333333333333334, instance.loadParameterIndex(0).?, 0.000001);
    try std.testing.expectEqual(@as(?f64, 3.0), instance.loadParameterPlainIndex(0));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterIndex(99));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainIndex(99));
    try std.testing.expectApproxEqAbs(0.8333333333333334, instance.loadParameterById(0).?, 0.000001);
    try std.testing.expectEqual(@as(?f64, 3.0), instance.loadParameterPlainById(0));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainById(99));
    try std.testing.expectEqual(@as(?f64, 0.5), instance.loadParameterByName("Mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), instance.loadParameterPlainByName("Mode"));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterByName("Missing"));
    try std.testing.expectEqual(@as(?f64, null), instance.loadParameterPlainByName("Missing"));
    try std.testing.expectEqual(@as(f64, 3.0), view.load("gain"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.boost, view.load("mode"));
    try std.testing.expectEqual(@as(f64, 0.5), view.loadNormalized("mode"));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultById(2));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsDefaultByName("Mode"));
    try std.testing.expect(!instance.parameterIsDefault("mode"));
    try std.testing.expect(!instance.parametersAllDefaults());
    try std.testing.expect(instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 2), instance.parameterNonDefaultCount());
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultIndex(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsDefaultByName("Missing"));

    try std.testing.expectEqual(@as(usize, 2), instance.resetParametersToDefaultsCount());
    try std.testing.expectEqual(@as(usize, 0), instance.resetParametersToDefaultsCount());
    try std.testing.expect(instance.storeParameter("gain", 3.0));
    instance.resetParametersToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultIndex(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultById(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsDefaultByName("Mode"));
    try std.testing.expect(instance.parameterIsDefault("mode"));
    try std.testing.expect(instance.parametersAllDefaults());
    try std.testing.expect(!instance.hasNonDefaultParameters());
    try std.testing.expectEqual(@as(usize, 0), instance.parameterNonDefaultCount());

    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterCount("gain", 6.0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterCount("gain", 3.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterNormalizedCount("gain", 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterNormalizedCount("gain", 0.5));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterIndexCount(0, 0.5));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainIndexCount(0, 3.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterByIdCount(0, 0.8333333333333334));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByIdCount(0, 6.0));
    try std.testing.expectEqual(@as(?usize, 0), instance.storeParameterByNameCount("Gain", 1.0));
    try std.testing.expectEqual(@as(?usize, 1), instance.storeParameterPlainByNameCount("Gain", 3.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainIndexCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByIdCount(99, 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, null), instance.storeParameterPlainByNameCount("Missing", 1.0));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultCount("gain"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultCount("gain"));
    try std.testing.expect(instance.storeParameter("gain", 6.0));
    try std.testing.expect(instance.resetParameterToDefault("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(true, instance.loadParameter("bypass"));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterIndexToDefaultCount(1));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterIndexToDefaultCount(1));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.resetParameterIndexToDefault(1));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultIndexCount(1));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultIndexCount(1));
    try std.testing.expect(instance.storeParameter("bypass", true));
    try std.testing.expect(instance.resetParameterToDefaultIndex(1));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByIdToDefaultCount(2));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterByIdToDefaultCount(2));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterByIdToDefault(2));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByIdCount(2));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultByIdCount(2));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterToDefaultById(2));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterByNameToDefaultCount("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterByNameToDefaultCount("Mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterByNameToDefault("Mode"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expectEqual(@as(?usize, 1), instance.resetParameterToDefaultByNameCount("Mode"));
    try std.testing.expectEqual(@as(?usize, 0), instance.resetParameterToDefaultByNameCount("Mode"));
    try std.testing.expect(instance.storeParameter("mode", .mute));
    try std.testing.expect(instance.resetParameterToDefaultByName("Mode"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterIndexToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultIndexCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByIdToDefaultCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByIdCount(99));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterByNameToDefaultCount("Missing"));
    try std.testing.expectEqual(@as(?usize, null), instance.resetParameterToDefaultByNameCount("Missing"));
    try std.testing.expect(!instance.resetParameterIndexToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultIndex(99));
    try std.testing.expect(!instance.resetParameterByIdToDefault(99));
    try std.testing.expect(!instance.resetParameterToDefaultById(99));
    try std.testing.expect(!instance.resetParameterByNameToDefault("Missing"));
    try std.testing.expect(!instance.resetParameterToDefaultByName("Missing"));
}

test "plugin instance copies parameter values from another instance" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Parameter Copy";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .default = false },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var source = try Instance.init(std.testing.allocator, .{});
    var target = try Instance.init(std.testing.allocator, .{});

    try std.testing.expect(source.storeParameter("gain", 6.0));
    try std.testing.expect(source.storeParameter("bypass", true));
    try std.testing.expect(source.storeParameter("mode", .mute));

    try std.testing.expectEqual(@as(usize, 3), target.copyParameterValuesFromCount(&source));
    try std.testing.expectEqual(@as(usize, 0), target.copyParameterValuesFromCount(&source));
    target.resetParametersToDefaults();
    target.copyParameterValuesFrom(&source);
    try std.testing.expectEqual(@as(f64, 6.0), target.loadParameter("gain"));
    try std.testing.expectEqual(true, target.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.mute, target.loadParameter("mode"));
    try std.testing.expectEqual(@as(usize, 3), target.parameterNonDefaultCount());

    try std.testing.expect(target.storeParameter("gain", 0.0));
    try std.testing.expectEqual(@as(f64, 6.0), source.loadParameter("gain"));
}

test "plugin instance exposes parameter editor" {
    const Mode = enum { clean, boost, mute };
    const Gain = struct {
        pub const name = "Instance Parameter Editor";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = .{ .id = 0, .name = "Gain", .short_name = "G", .units = "dB", .min = -12.0, .max = 6.0, .default = 0.0 },
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .default = false, .is_bypass = true },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    const editor = instance.parameterEditor();
    try std.testing.expectEqual(@as(usize, 3), editor.parameterCount());
    try std.testing.expect(!editor.parametersEmpty());
    try std.testing.expect(editor.hasParameters());
    try std.testing.expectEqual(@as(?u32, 0), editor.id(0));
    try std.testing.expectEqualStrings("Gain", editor.name(0).?);
    try std.testing.expectEqualStrings("G", editor.shortNameById(0).?);
    try std.testing.expectEqualStrings("dB", editor.unitsByName("Gain").?);
    try std.testing.expectEqual(@as(?f64, 0.0), editor.defaultNormalizedByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), editor.isBypassByName("Bypass"));
    try std.testing.expectEqual(@as(?i32, 2), editor.stepCountByName("Mode"));
    try std.testing.expectEqual(@as(?bool, true), editor.isListById(2));
    try std.testing.expectEqual(@as(?usize, 2), editor.indexOfName("Mode"));
    try std.testing.expect(editor.hasId(1));
    try std.testing.expect(!editor.hasName("Missing"));

    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("mute", try editor.formatPlainByName("Mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try editor.parsePlainByName("Mode", "mute"));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.plainFromNormalizedByName("Mode", 1.0));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.normalizedFromPlainByName("Mode", 2.0));

    try std.testing.expect(editor.store("gain", 6.0));
    try std.testing.expect(editor.storePlainById(1, 1.0));
    try std.testing.expect(editor.storeByName("Mode", 1.0));
    try std.testing.expectEqual(@as(f64, 6.0), editor.load("gain"));
    try std.testing.expectEqual(true, editor.load("bypass"));
    try std.testing.expectEqual(Mode.mute, editor.load("mode"));
    try std.testing.expectEqual(@as(?f64, 1.0), editor.loadById(2));
    try std.testing.expectEqual(@as(?f64, 2.0), editor.loadPlainByName("Mode"));

    try std.testing.expect(!editor.storeIndex(99, 1.0));
    try std.testing.expect(!editor.storePlainByName("Missing", 1.0));
    try std.testing.expectEqual(@as(?f64, null), editor.loadIndex(99));
    try std.testing.expectEqual(@as(?f64, null), editor.loadPlainByName("Missing"));

    try std.testing.expect(editor.resetToDefaultById(1));
    try std.testing.expectEqual(false, editor.load("bypass"));
    editor.resetToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), editor.load("gain"));
    try std.testing.expectEqual(Mode.clean, editor.load("mode"));

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(f64, 0.0), view.load("gain"));
    try std.testing.expectEqual(false, view.load("bypass"));
    try std.testing.expectEqual(Mode.clean, view.load("mode"));
}

test "plugin instance applies process parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process(self: *@This(), context: *process_api.ProcessContext(f32)) void {
            self.observed = context.latestParameterNormalized(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance passes reflected parameters to state-aware process hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.view(set).loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance passes parameter view to state-aware process hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance View Aware Process";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn processWithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed = view.loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
}

test "plugin instance prefers parameter-view process hook over other process hooks" {
    const Gain = struct {
        called: enum { none, raw, parameters, view } = .none,

        pub const name = "Instance Process Hook Priority";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process(self: *@This(), _: *process_api.ProcessContext(f32)) void {
            self.called = .raw;
        }

        pub fn processWithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {
            self.called = .parameters;
        }

        pub fn processWithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f32),
            _: parameters.ParameterView(Params),
        ) void {
            self.called = .view;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var context = process_api.ProcessContext(f32){ .sample_rate = 48_000.0 };

    instance.process(&context);

    try std.testing.expectEqual(.view, instance.plugin.called);
}

test "plugin instance applies process64 parameter changes before dispatch" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance Process64 Parameters";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64(self: *@This(), context: *process_api.ProcessContext(f64)) void {
            self.observed = context.latestParameterNormalized(0);
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance passes reflected parameters to state-aware process64 hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance State Aware Process64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            set: *const parameters.ParameterSet(Params),
            values: *const parameters.ParameterValues(Params),
        ) void {
            self.observed = values.view(set).loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance passes parameter view to state-aware process64 hooks" {
    const Gain = struct {
        observed: ?f64 = null,

        pub const name = "Instance View Aware Process64";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64WithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            view: parameters.ParameterView(Params),
        ) void {
            self.observed = view.loadNormalized("gain");
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    const changes = [_]process_api.ParameterChange{
        instance.parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
}

test "plugin instance prefers parameter-view process64 hook over other process64 hooks" {
    const Gain = struct {
        called: enum { none, raw, parameters, view } = .none,

        pub const name = "Instance Process64 Hook Priority";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
        };

        pub fn process64(self: *@This(), _: *process_api.ProcessContext(f64)) void {
            self.called = .raw;
        }

        pub fn process64WithParameters(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            _: *const parameters.ParameterSet(Params),
            _: *const parameters.ParameterValues(Params),
        ) void {
            self.called = .parameters;
        }

        pub fn process64WithParameterView(
            self: *@This(),
            _: *process_api.ProcessContext(f64),
            _: parameters.ParameterView(Params),
        ) void {
            self.called = .view;
        }
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var context = process_api.ProcessContext(f64){ .sample_rate = 48_000.0 };

    instance.process64(&context);

    try std.testing.expectEqual(.view, instance.plugin.called);
}

test "plugin instance round-trips owned parameter state" {
    const Gain = struct {
        pub const name = "Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 1.0),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var restored = try Instance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(Gain.Params)]u8 = undefined;

    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), Instance.Spec.encoded_parameter_state_size);
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.encodedParameterStateSize());
    try std.testing.expectEqual(@as(usize, state.encodedSize(Gain.Params)), instance.parameterStateEncodedSize());
    try std.testing.expectEqual(@as(usize, 2), instance.parameterStateEntryCount());
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(instance.storeParameterNormalized("mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var header_stream = std.io.fixedBufferStream(&bytes);
    const header = try instance.readParameterStateHeader(header_stream.reader());
    const older_header = state.ParameterStateHeader{ .version = state.format_version, .entry_count = 1 };
    const newer_header = state.ParameterStateHeader{ .version = state.format_version, .entry_count = 3 };
    try std.testing.expect(header.isCurrentVersion());
    try std.testing.expect(header.matchesEntryCount(instance.parameterStateEntryCount()));
    try std.testing.expect(!header.hasFewerEntriesThan(instance.parameterStateEntryCount()));
    try std.testing.expect(!header.hasMoreEntriesThan(instance.parameterStateEntryCount()));
    try std.testing.expect(instance.parameterStateHeaderMatchesEntryCount(header));
    try std.testing.expect(!instance.parameterStateHeaderHasFewerEntries(header));
    try std.testing.expect(!instance.parameterStateHeaderHasMoreEntries(header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderMissingEntryCount(header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderExtraEntryCount(header));
    try std.testing.expect(!instance.parameterStateHeaderMatchesEntryCount(older_header));
    try std.testing.expect(instance.parameterStateHeaderHasFewerEntries(older_header));
    try std.testing.expect(!instance.parameterStateHeaderHasMoreEntries(older_header));
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateHeaderMissingEntryCount(older_header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderExtraEntryCount(older_header));
    try std.testing.expect(!instance.parameterStateHeaderMatchesEntryCount(newer_header));
    try std.testing.expect(!instance.parameterStateHeaderHasFewerEntries(newer_header));
    try std.testing.expect(instance.parameterStateHeaderHasMoreEntries(newer_header));
    try std.testing.expectEqual(@as(usize, 0), instance.parameterStateHeaderMissingEntryCount(newer_header));
    try std.testing.expectEqual(@as(usize, 1), instance.parameterStateHeaderExtraEntryCount(newer_header));

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try restored.readParameterStateReport(in_stream.reader());
    const partial_report = state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 };
    const newer_report = state.ReadParameterStateReport{ .entry_count = 3, .restored_count = 2, .ignored_count = 1 };
    const over_restored_report = state.ReadParameterStateReport{ .entry_count = 3, .restored_count = 3, .ignored_count = 0 };

    try std.testing.expectEqual(state.ReadParameterStateReport{ .entry_count = 2, .restored_count = 2, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(usize, 2), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 2), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasNoRestoredEntries());
    try std.testing.expect(!report.hasIgnoredEntries());
    try std.testing.expect(report.hasNoIgnoredEntries());
    try std.testing.expect(report.hasAccountedEntries());
    try std.testing.expect(!report.hasNoAccountedEntries());
    try std.testing.expect(!report.accountedEntriesEmpty());
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expect(!report.restoredPartialEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expect(restored.parameterStateReportMatchesDecodedCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerDecodedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreDecodedEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingDecodedEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraDecodedEntryCount(report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(report));
    try std.testing.expect(restored.parameterStateReportHasAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportHasNoAccountedEntries(report));
    try std.testing.expect(!restored.parameterStateReportAccountedEntriesEmpty(report));
    try std.testing.expect(!restored.parameterStateReportMatchesDecodedCount(partial_report));
    try std.testing.expect(restored.parameterStateReportHasFewerDecodedEntries(partial_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreDecodedEntries(partial_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingDecodedEntryCount(partial_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraDecodedEntryCount(partial_report));
    try std.testing.expect(!restored.parameterStateReportMatchesRestoredCount(partial_report));
    try std.testing.expect(restored.parameterStateReportHasFewerRestoredEntries(partial_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(partial_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportMissingRestoredEntryCount(partial_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(partial_report));
    try std.testing.expect(!restored.parameterStateReportMatchesDecodedCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerDecodedEntries(newer_report));
    try std.testing.expect(restored.parameterStateReportHasMoreDecodedEntries(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingDecodedEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraDecodedEntryCount(newer_report));
    try std.testing.expect(restored.parameterStateReportMatchesRestoredCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(newer_report));
    try std.testing.expect(!restored.parameterStateReportHasMoreRestoredEntries(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(newer_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportExtraRestoredEntryCount(newer_report));
    try std.testing.expect(!restored.parameterStateReportMatchesRestoredCount(over_restored_report));
    try std.testing.expect(!restored.parameterStateReportHasFewerRestoredEntries(over_restored_report));
    try std.testing.expect(restored.parameterStateReportHasMoreRestoredEntries(over_restored_report));
    try std.testing.expectEqual(@as(usize, 0), restored.parameterStateReportMissingRestoredEntryCount(over_restored_report));
    try std.testing.expectEqual(@as(usize, 1), restored.parameterStateReportExtraRestoredEntryCount(over_restored_report));
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.75), restored.loadParameterNormalized("mix"));
}

test "plugin instance writes parameter state debug json" {
    const Gain = struct {
        pub const name = "Instance State JSON";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 1.0),
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});
    var bytes: [160]u8 = undefined;

    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(instance.storeParameterNormalized("mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterStateJson(out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25},{\"id\":1,\"name\":\"Mix\",\"normalized\":0.75}]}",
        out_stream.getWritten(),
    );
}

test "plugin instance reads parameter state with migrations" {
    const OldGain = struct {
        pub const name = "Old Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(7, "Gain", 0.0, 1.0, 0.5),
        };
    };
    const NewGain = struct {
        pub const name = "New Instance State";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 0.5),
        };
    };
    const OldInstance = PluginInstance(OldGain);
    const NewInstance = PluginInstance(NewGain);
    var old_instance = try OldInstance.init(std.testing.allocator, .{});
    var new_instance = try NewInstance.init(std.testing.allocator, .{});
    var bytes: [state.encodedSize(OldGain.Params)]u8 = undefined;

    try std.testing.expect(old_instance.storeParameterNormalized("gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try old_instance.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try new_instance.readParameterStateWithMigrationsReport(in_stream.reader(), &.{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try std.testing.expectEqual(state.ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 }, report);
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expectEqual(@as(f64, 0.25), new_instance.loadParameterNormalized("output"));
}

test "plugin instance exposes parameter migration diagnostics" {
    const Gain = struct {
        pub const name = "Gain";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 0.5),
        };
    };

    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});
    defer instance.deinit();

    const valid = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 1 },
    };
    const identity = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 7 },
    };
    const duplicate = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 7, .new_id = 1 },
    };
    const ambiguous = [_]state.ParameterIdMigration{
        .{ .old_id = 7, .new_id = 1 },
        .{ .old_id = 9, .new_id = 1 },
    };

    try instance.validateParameterIdMigrations(&valid);
    try std.testing.expectEqual(@as(?usize, null), instance.identityParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(?usize, null), instance.duplicateParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(?usize, null), instance.ambiguousParameterMigrationIndex(&valid));
    try std.testing.expectEqual(@as(u32, 1), instance.migratedParameterId(7, &valid));
    try std.testing.expectEqual(@as(u32, 1), instance.migratedParameterId(9, &valid));
    try std.testing.expectEqual(@as(u32, 12), instance.migratedParameterId(12, &valid));
    try std.testing.expectEqual(@as(?usize, 0), instance.identityParameterMigrationIndex(&identity));
    try std.testing.expectError(error.IdentityParameterMigration, instance.validateParameterIdMigrations(&identity));
    try std.testing.expectEqual(@as(?usize, 1), instance.duplicateParameterMigrationIndex(&duplicate));
    try std.testing.expectError(error.DuplicateParameterMigration, instance.validateParameterIdMigrations(&duplicate));
    try std.testing.expectEqual(@as(?usize, 1), instance.ambiguousParameterMigrationIndex(&ambiguous));
    try std.testing.expectError(error.AmbiguousParameterMigration, instance.validateParameterIdMigrations(&ambiguous));
}

test "plugin instance accepts metadata-only plugins" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Instance = PluginInstance(Minimal);
    var instance = try Instance.init(std.testing.allocator, .{});
    const input = [_]f64{0.25};
    var output = [_]f64{0.0};
    const input_channels = [_][]const f64{&input};
    const output_channels = [_][]f64{&output};
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .inputs = try process_api.AudioInputs(f64).init(&input_channels),
        .outputs = try process_api.AudioOutputs(f64).init(&output_channels),
    };

    instance.prepare(.{ .sample_rate = 48_000.0, .max_block_size = 1 });
    instance.process64(&context);
    instance.deinit();

    try std.testing.expectEqualStrings("Minimal", Instance.Spec.name);
    try std.testing.expectEqual(@as(f64, 0.0), output[0]);
}
