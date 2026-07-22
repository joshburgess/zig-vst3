const std = @import("std");
const common = @import("../common.zig");
const parameters = @import("../parameters.zig");
const process_api = @import("../process.zig");
const state = @import("../state.zig");
const units_api = @import("../units.zig");
const config_mod = @import("config.zig");
const lifecycle = @import("lifecycle.zig");
const spec_mod = @import("spec.zig");

pub const PrepareConfig = config_mod.PrepareConfig;
pub const PluginSpec = spec_mod.PluginSpec;
pub const validateLifecycle = lifecycle.validateLifecycle;

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

        pub fn hasAudioInput(_: *const Self) bool {
            return Spec.audio_input;
        }

        pub fn audioInputLayout(_: *const Self) process_api.AudioBusLayout {
            return Spec.audio_input_layout;
        }

        pub fn audioInputChannelCount(_: *const Self) u8 {
            return Spec.audio_input_layout.channelCount();
        }

        pub fn hasAudioOutput(_: *const Self) bool {
            return Spec.audio_output;
        }

        pub fn audioOutputLayout(_: *const Self) process_api.AudioBusLayout {
            return Spec.audio_output_layout;
        }

        pub fn audioOutputChannelCount(_: *const Self) u8 {
            return Spec.audio_output_layout.channelCount();
        }

        pub fn hasEventInput(_: *const Self) bool {
            return Spec.event_input;
        }

        pub fn hasEventOutput(_: *const Self) bool {
            return Spec.event_output;
        }

        pub fn hasInitHook(_: *const Self) bool {
            return Spec.has_init;
        }

        pub fn hasPrepareHook(_: *const Self) bool {
            return Spec.has_prepare;
        }

        pub fn hasProcessHook(_: *const Self) bool {
            return Spec.has_process32_hook;
        }

        pub fn hasProcessFunctionHook(_: *const Self) bool {
            return Spec.has_process;
        }

        pub fn hasProcessWithParameterViewHook(_: *const Self) bool {
            return Spec.has_process_with_parameter_view;
        }

        pub fn hasProcessWithParametersHook(_: *const Self) bool {
            return Spec.has_process_with_parameters;
        }

        pub fn hasProcess64Hook(_: *const Self) bool {
            return Spec.has_process64_hook;
        }

        pub fn hasProcess64FunctionHook(_: *const Self) bool {
            return Spec.has_process64;
        }

        pub fn hasProcess64WithParameterViewHook(_: *const Self) bool {
            return Spec.has_process64_with_parameter_view;
        }

        pub fn hasProcess64WithParametersHook(_: *const Self) bool {
            return Spec.has_process64_with_parameters;
        }

        pub fn hasAnyProcessHook(_: *const Self) bool {
            return Spec.has_any_process_hook;
        }

        pub fn hasDeinitHook(_: *const Self) bool {
            return Spec.has_deinit;
        }

        pub fn pluginName(_: *const Self) []const u8 {
            return Spec.name;
        }

        pub fn pluginVendor(_: *const Self) []const u8 {
            return Spec.vendor;
        }

        pub fn pluginUrl(_: *const Self) []const u8 {
            return Spec.url;
        }

        pub fn pluginEmail(_: *const Self) []const u8 {
            return Spec.email;
        }

        pub fn componentClassName(_: *const Self) []const u8 {
            return Spec.component_class_name;
        }

        pub fn controllerClassName(_: *const Self) []const u8 {
            return Spec.controller_class_name;
        }

        pub fn componentCategory(_: *const Self) []const u8 {
            return Spec.component_category;
        }

        pub fn controllerCategory(_: *const Self) []const u8 {
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

        pub fn cyclicUnitParentIndex(self: *const Self) ?usize {
            return self.spec.units.cyclicUnitParentIndex();
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

        pub fn programCountForUnit(self: *const Self, unit_id: i32) ?usize {
            return self.spec.units.programCountForUnit(unit_id);
        }

        pub fn programCountForUnitName(self: *const Self, unit_name: []const u8) ?usize {
            return self.spec.units.programCountForUnitName(unit_name);
        }

        pub fn programName(self: *const Self, list_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.programName(list_id, program_index);
        }

        pub fn programNameByListName(self: *const Self, list_name: []const u8, program_index: usize) ?[]const u8 {
            return self.spec.units.programNameByListName(list_name, program_index);
        }

        pub fn programNameForUnit(self: *const Self, unit_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.programNameForUnit(unit_id, program_index);
        }

        pub fn programNameForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?[]const u8 {
            return self.spec.units.programNameForUnitName(unit_name, program_index);
        }

        pub fn program(self: *const Self, list_id: i32, program_index: usize) ?units_api.Program {
            return self.spec.units.program(list_id, program_index);
        }

        pub fn programByListName(self: *const Self, list_name: []const u8, program_index: usize) ?units_api.Program {
            return self.spec.units.programByListName(list_name, program_index);
        }

        pub fn programForUnit(self: *const Self, unit_id: i32, program_index: usize) ?units_api.Program {
            return self.spec.units.programForUnit(unit_id, program_index);
        }

        pub fn programForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?units_api.Program {
            return self.spec.units.programForUnitName(unit_name, program_index);
        }

        pub fn programByName(self: *const Self, list_id: i32, name: []const u8) ?units_api.Program {
            return self.spec.units.programByName(list_id, name);
        }

        pub fn programByNameForListName(self: *const Self, list_name: []const u8, name: []const u8) ?units_api.Program {
            return self.spec.units.programByNameForListName(list_name, name);
        }

        pub fn programByNameForUnit(self: *const Self, unit_id: i32, name: []const u8) ?units_api.Program {
            return self.spec.units.programByNameForUnit(unit_id, name);
        }

        pub fn programByNameForUnitName(self: *const Self, unit_name: []const u8, name: []const u8) ?units_api.Program {
            return self.spec.units.programByNameForUnitName(unit_name, name);
        }

        pub fn programIndexOfName(self: *const Self, list_id: i32, name: []const u8) ?usize {
            return self.spec.units.programIndexOfName(list_id, name);
        }

        pub fn programIndexOfNameByListName(self: *const Self, list_name: []const u8, name: []const u8) ?usize {
            return self.spec.units.programIndexOfNameByListName(list_name, name);
        }

        pub fn programIndexOfNameForUnit(self: *const Self, unit_id: i32, name: []const u8) ?usize {
            return self.spec.units.programIndexOfNameForUnit(unit_id, name);
        }

        pub fn programIndexOfNameForUnitName(self: *const Self, unit_name: []const u8, name: []const u8) ?usize {
            return self.spec.units.programIndexOfNameForUnitName(unit_name, name);
        }

        pub fn hasProgramName(self: *const Self, list_id: i32, name: []const u8) bool {
            return self.spec.units.hasProgramName(list_id, name);
        }

        pub fn hasProgramNameByListName(self: *const Self, list_name: []const u8, name: []const u8) bool {
            return self.spec.units.hasProgramNameByListName(list_name, name);
        }

        pub fn hasProgramNameForUnit(self: *const Self, unit_id: i32, name: []const u8) bool {
            return self.spec.units.hasProgramNameForUnit(unit_id, name);
        }

        pub fn hasProgramNameForUnitName(self: *const Self, unit_name: []const u8, name: []const u8) bool {
            return self.spec.units.hasProgramNameForUnitName(unit_name, name);
        }

        pub fn duplicateProgramName(self: *const Self, list_id: i32) ?[]const u8 {
            return self.spec.units.duplicateProgramName(list_id);
        }

        pub fn duplicateProgramNameByListName(self: *const Self, list_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramNameByListName(list_name);
        }

        pub fn duplicateProgramNameForUnit(self: *const Self, unit_id: i32) ?[]const u8 {
            return self.spec.units.duplicateProgramNameForUnit(unit_id);
        }

        pub fn duplicateProgramNameForUnitName(self: *const Self, unit_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramNameForUnitName(unit_name);
        }

        pub fn duplicateProgramNameIndex(self: *const Self, list_id: i32) ?usize {
            return self.spec.units.duplicateProgramNameIndex(list_id);
        }

        pub fn duplicateProgramNameIndexByListName(self: *const Self, list_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramNameIndexByListName(list_name);
        }

        pub fn duplicateProgramNameIndexForUnit(self: *const Self, unit_id: i32) ?usize {
            return self.spec.units.duplicateProgramNameIndexForUnit(unit_id);
        }

        pub fn duplicateProgramNameIndexForUnitName(self: *const Self, unit_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramNameIndexForUnitName(unit_name);
        }

        pub fn hasDuplicateProgramNames(self: *const Self, list_id: i32) bool {
            return self.spec.units.hasDuplicateProgramNames(list_id);
        }

        pub fn hasDuplicateProgramNamesByListName(self: *const Self, list_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramNamesByListName(list_name);
        }

        pub fn hasDuplicateProgramNamesForUnit(self: *const Self, unit_id: i32) bool {
            return self.spec.units.hasDuplicateProgramNamesForUnit(unit_id);
        }

        pub fn hasDuplicateProgramNamesForUnitName(self: *const Self, unit_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramNamesForUnitName(unit_name);
        }

        pub fn programParameterCount(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.programParameterCount(list_id, program_index);
        }

        pub fn programParameterCountByListName(self: *const Self, list_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.programParameterCountByListName(list_name, program_index);
        }

        pub fn programParameterCountForUnit(self: *const Self, unit_id: i32, program_index: usize) ?usize {
            return self.spec.units.programParameterCountForUnit(unit_id, program_index);
        }

        pub fn programParameterCountForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.programParameterCountForUnitName(unit_name, program_index);
        }

        pub fn programParameterCountByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programParameterCountByName(list_id, program_name);
        }

        pub fn programParameterCountByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.programParameterCountByNameForListName(list_name, program_name);
        }

        pub fn programParameterCountByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programParameterCountByNameForUnit(unit_id, program_name);
        }

        pub fn programParameterCountByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.programParameterCountByNameForUnitName(unit_name, program_name);
        }

        pub fn programHasParameters(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programHasParameters(list_id, program_index);
        }

        pub fn programHasParametersByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.programHasParametersByListName(list_name, program_index);
        }

        pub fn programHasParametersForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.programHasParametersForUnit(unit_id, program_index);
        }

        pub fn programHasParametersForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.programHasParametersForUnitName(unit_name, program_index);
        }

        pub fn programHasParametersByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasParametersByName(list_id, program_name);
        }

        pub fn programHasParametersByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programHasParametersByNameForListName(list_name, program_name);
        }

        pub fn programHasParametersByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasParametersByNameForUnit(unit_id, program_name);
        }

        pub fn programHasParametersByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programHasParametersByNameForUnitName(unit_name, program_name);
        }

        pub fn programParametersEmpty(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programParametersEmpty(list_id, program_index);
        }

        pub fn programParametersEmptyByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.programParametersEmptyByListName(list_name, program_index);
        }

        pub fn programParametersEmptyForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.programParametersEmptyForUnit(unit_id, program_index);
        }

        pub fn programParametersEmptyForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.programParametersEmptyForUnitName(unit_name, program_index);
        }

        pub fn programParametersEmptyByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programParametersEmptyByName(list_id, program_name);
        }

        pub fn programParametersEmptyByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programParametersEmptyByNameForListName(list_name, program_name);
        }

        pub fn programParametersEmptyByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.programParametersEmptyByNameForUnit(unit_id, program_name);
        }

        pub fn programParametersEmptyByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programParametersEmptyByNameForUnitName(unit_name, program_name);
        }

        pub fn programParameter(self: *const Self, list_id: i32, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameter(list_id, program_index, parameter_index);
        }

        pub fn programParameterByListName(self: *const Self, list_name: []const u8, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByListName(list_name, program_index, parameter_index);
        }

        pub fn programParameterForUnit(self: *const Self, unit_id: i32, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterForUnit(unit_id, program_index, parameter_index);
        }

        pub fn programParameterForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterForUnitName(unit_name, program_index, parameter_index);
        }

        pub fn programParameterByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByName(list_id, program_name, parameter_index);
        }

        pub fn programParameterByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameForListName(list_name, program_name, parameter_index);
        }

        pub fn programParameterByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameForUnit(unit_id, program_name, parameter_index);
        }

        pub fn programParameterByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameForUnitName(unit_name, program_name, parameter_index);
        }

        pub fn programParameterById(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterById(list_id, program_index, parameter_id);
        }

        pub fn programParameterByIdForListName(self: *const Self, list_name: []const u8, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByIdForListName(list_name, program_index, parameter_id);
        }

        pub fn programParameterByIdForUnit(self: *const Self, unit_id: i32, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByIdForUnit(unit_id, program_index, parameter_id);
        }

        pub fn programParameterByIdForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByIdForUnitName(unit_name, program_index, parameter_id);
        }

        pub fn programParameterIndexOfId(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfId(list_id, program_index, parameter_id);
        }

        pub fn programParameterIndexOfIdByListName(self: *const Self, list_name: []const u8, program_index: usize, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByListName(list_name, program_index, parameter_id);
        }

        pub fn programParameterIndexOfIdForUnit(self: *const Self, unit_id: i32, program_index: usize, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdForUnit(unit_id, program_index, parameter_id);
        }

        pub fn programParameterIndexOfIdForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdForUnitName(unit_name, program_index, parameter_id);
        }

        pub fn hasProgramParameter(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameter(list_id, program_index, parameter_id);
        }

        pub fn hasProgramParameterByListName(self: *const Self, list_name: []const u8, program_index: usize, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByListName(list_name, program_index, parameter_id);
        }

        pub fn hasProgramParameterForUnit(self: *const Self, unit_id: i32, program_index: usize, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterForUnit(unit_id, program_index, parameter_id);
        }

        pub fn hasProgramParameterForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterForUnitName(unit_name, program_index, parameter_id);
        }

        pub fn duplicateProgramParameterId(self: *const Self, list_id: i32, program_index: usize) ?u32 {
            return self.spec.units.duplicateProgramParameterId(list_id, program_index);
        }

        pub fn duplicateProgramParameterIdByListName(self: *const Self, list_name: []const u8, program_index: usize) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByListName(list_name, program_index);
        }

        pub fn duplicateProgramParameterIdForUnit(self: *const Self, unit_id: i32, program_index: usize) ?u32 {
            return self.spec.units.duplicateProgramParameterIdForUnit(unit_id, program_index);
        }

        pub fn duplicateProgramParameterIdForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?u32 {
            return self.spec.units.duplicateProgramParameterIdForUnitName(unit_name, program_index);
        }

        pub fn duplicateProgramParameterIdIndex(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndex(list_id, program_index);
        }

        pub fn duplicateProgramParameterIdIndexByListName(self: *const Self, list_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByListName(list_name, program_index);
        }

        pub fn duplicateProgramParameterIdIndexForUnit(self: *const Self, unit_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexForUnit(unit_id, program_index);
        }

        pub fn duplicateProgramParameterIdIndexForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexForUnitName(unit_name, program_index);
        }

        pub fn hasDuplicateProgramParameterIds(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramParameterIds(list_id, program_index);
        }

        pub fn hasDuplicateProgramParameterIdsByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByListName(list_name, program_index);
        }

        pub fn hasDuplicateProgramParameterIdsForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsForUnit(unit_id, program_index);
        }

        pub fn hasDuplicateProgramParameterIdsForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsForUnitName(unit_name, program_index);
        }

        pub fn programParameterByNameAndId(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameAndId(list_id, program_name, parameter_id);
        }

        pub fn programParameterByNameAndIdForListName(self: *const Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameAndIdForListName(list_name, program_name, parameter_id);
        }

        pub fn programParameterByNameAndIdForUnit(self: *const Self, unit_id: i32, program_name: []const u8, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameAndIdForUnit(unit_id, program_name, parameter_id);
        }

        pub fn programParameterByNameAndIdForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterByNameAndIdForUnitName(unit_name, program_name, parameter_id);
        }

        pub fn programParameterIndexOfIdByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByName(list_id, program_name, parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByNameForListName(list_name, program_name, parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByNameForUnit(unit_id, program_name, parameter_id);
        }

        pub fn programParameterIndexOfIdByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) ?usize {
            return self.spec.units.programParameterIndexOfIdByNameForUnitName(unit_name, program_name, parameter_id);
        }

        pub fn hasProgramParameterByName(self: *const Self, list_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByName(list_id, program_name, parameter_id);
        }

        pub fn hasProgramParameterByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByNameForListName(list_name, program_name, parameter_id);
        }

        pub fn hasProgramParameterByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByNameForUnit(unit_id, program_name, parameter_id);
        }

        pub fn hasProgramParameterByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, parameter_id: u32) bool {
            return self.spec.units.hasProgramParameterByNameForUnitName(unit_name, program_name, parameter_id);
        }

        pub fn duplicateProgramParameterIdByName(self: *const Self, list_id: i32, program_name: []const u8) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByName(list_id, program_name);
        }

        pub fn duplicateProgramParameterIdByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByNameForListName(list_name, program_name);
        }

        pub fn duplicateProgramParameterIdByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByNameForUnit(unit_id, program_name);
        }

        pub fn duplicateProgramParameterIdByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?u32 {
            return self.spec.units.duplicateProgramParameterIdByNameForUnitName(unit_name, program_name);
        }

        pub fn duplicateProgramParameterIdIndexByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByName(list_id, program_name);
        }

        pub fn duplicateProgramParameterIdIndexByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByNameForListName(list_name, program_name);
        }

        pub fn duplicateProgramParameterIdIndexByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByNameForUnit(unit_id, program_name);
        }

        pub fn duplicateProgramParameterIdIndexByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramParameterIdIndexByNameForUnitName(unit_name, program_name);
        }

        pub fn hasDuplicateProgramParameterIdsByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByName(list_id, program_name);
        }

        pub fn hasDuplicateProgramParameterIdsByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByNameForListName(list_name, program_name);
        }

        pub fn hasDuplicateProgramParameterIdsByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByNameForUnit(unit_id, program_name);
        }

        pub fn hasDuplicateProgramParameterIdsByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramParameterIdsByNameForUnitName(unit_name, program_name);
        }

        pub fn programInfo(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfo(list_id, program_index, key);
        }

        pub fn programInfoByListName(self: *const Self, list_name: []const u8, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByListName(list_name, program_index, key);
        }

        pub fn programInfoForUnit(self: *const Self, unit_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoForUnit(unit_id, program_index, key);
        }

        pub fn programInfoForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoForUnitName(unit_name, program_index, key);
        }

        pub fn programInfoEntry(self: *const Self, list_id: i32, program_index: usize, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntry(list_id, program_index, info_index);
        }

        pub fn programInfoEntryByListName(self: *const Self, list_name: []const u8, program_index: usize, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByListName(list_name, program_index, info_index);
        }

        pub fn programInfoEntryForUnit(self: *const Self, unit_id: i32, program_index: usize, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryForUnit(unit_id, program_index, info_index);
        }

        pub fn programInfoEntryForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryForUnitName(unit_name, program_index, info_index);
        }

        pub fn programInfoEntryByKey(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByKey(list_id, program_index, key);
        }

        pub fn programInfoEntryByKeyByListName(self: *const Self, list_name: []const u8, program_index: usize, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByKeyByListName(list_name, program_index, key);
        }

        pub fn programInfoEntryByKeyForUnit(self: *const Self, unit_id: i32, program_index: usize, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByKeyForUnit(unit_id, program_index, key);
        }

        pub fn programInfoEntryByKeyForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByKeyForUnitName(unit_name, program_index, key);
        }

        pub fn programInfoIndexOfKey(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKey(list_id, program_index, key);
        }

        pub fn programInfoIndexOfKeyByListName(self: *const Self, list_name: []const u8, program_index: usize, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByListName(list_name, program_index, key);
        }

        pub fn programInfoIndexOfKeyForUnit(self: *const Self, unit_id: i32, program_index: usize, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyForUnit(unit_id, program_index, key);
        }

        pub fn programInfoIndexOfKeyForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyForUnitName(unit_name, program_index, key);
        }

        pub fn hasProgramInfo(self: *const Self, list_id: i32, program_index: usize, key: []const u8) bool {
            return self.spec.units.hasProgramInfo(list_id, program_index, key);
        }

        pub fn hasProgramInfoByListName(self: *const Self, list_name: []const u8, program_index: usize, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByListName(list_name, program_index, key);
        }

        pub fn hasProgramInfoForUnit(self: *const Self, unit_id: i32, program_index: usize, key: []const u8) bool {
            return self.spec.units.hasProgramInfoForUnit(unit_id, program_index, key);
        }

        pub fn hasProgramInfoForUnitName(self: *const Self, unit_name: []const u8, program_index: usize, key: []const u8) bool {
            return self.spec.units.hasProgramInfoForUnitName(unit_name, program_index, key);
        }

        pub fn duplicateProgramInfoKey(self: *const Self, list_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKey(list_id, program_index);
        }

        pub fn duplicateProgramInfoKeyByListName(self: *const Self, list_name: []const u8, program_index: usize) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByListName(list_name, program_index);
        }

        pub fn duplicateProgramInfoKeyForUnit(self: *const Self, unit_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyForUnit(unit_id, program_index);
        }

        pub fn duplicateProgramInfoKeyForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyForUnitName(unit_name, program_index);
        }

        pub fn duplicateProgramInfoKeyIndex(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndex(list_id, program_index);
        }

        pub fn duplicateProgramInfoKeyIndexByListName(self: *const Self, list_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByListName(list_name, program_index);
        }

        pub fn duplicateProgramInfoKeyIndexForUnit(self: *const Self, unit_id: i32, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexForUnit(unit_id, program_index);
        }

        pub fn duplicateProgramInfoKeyIndexForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexForUnitName(unit_name, program_index);
        }

        pub fn hasDuplicateProgramInfoKeys(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramInfoKeys(list_id, program_index);
        }

        pub fn hasDuplicateProgramInfoKeysByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByListName(list_name, program_index);
        }

        pub fn hasDuplicateProgramInfoKeysForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysForUnit(unit_id, program_index);
        }

        pub fn hasDuplicateProgramInfoKeysForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysForUnitName(unit_name, program_index);
        }

        pub fn programInfoByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByName(list_id, program_name, key);
        }

        pub fn programInfoByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByNameForListName(list_name, program_name, key);
        }

        pub fn programInfoByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByNameForUnit(unit_id, program_name, key);
        }

        pub fn programInfoByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByNameForUnitName(unit_name, program_name, key);
        }

        pub fn programInfoEntryByName(self: *const Self, list_id: i32, program_name: []const u8, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByName(list_id, program_name, info_index);
        }

        pub fn programInfoEntryByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameForListName(list_name, program_name, info_index);
        }

        pub fn programInfoEntryByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameForUnit(unit_id, program_name, info_index);
        }

        pub fn programInfoEntryByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, info_index: usize) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameForUnitName(unit_name, program_name, info_index);
        }

        pub fn programInfoEntryByNameAndKey(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameAndKey(list_id, program_name, key);
        }

        pub fn programInfoEntryByNameAndKeyForListName(self: *const Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameAndKeyForListName(list_name, program_name, key);
        }

        pub fn programInfoEntryByNameAndKeyForUnit(self: *const Self, unit_id: i32, program_name: []const u8, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameAndKeyForUnit(unit_id, program_name, key);
        }

        pub fn programInfoEntryByNameAndKeyForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?units_api.ProgramInfo {
            return self.spec.units.programInfoEntryByNameAndKeyForUnitName(unit_name, program_name, key);
        }

        pub fn programInfoIndexOfKeyByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByName(list_id, program_name, key);
        }

        pub fn programInfoIndexOfKeyByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByNameForListName(list_name, program_name, key);
        }

        pub fn programInfoIndexOfKeyByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByNameForUnit(unit_id, program_name, key);
        }

        pub fn programInfoIndexOfKeyByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, key: []const u8) ?usize {
            return self.spec.units.programInfoIndexOfKeyByNameForUnitName(unit_name, program_name, key);
        }

        pub fn hasProgramInfoByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByName(list_id, program_name, key);
        }

        pub fn hasProgramInfoByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByNameForListName(list_name, program_name, key);
        }

        pub fn hasProgramInfoByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByNameForUnit(unit_id, program_name, key);
        }

        pub fn hasProgramInfoByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8, key: []const u8) bool {
            return self.spec.units.hasProgramInfoByNameForUnitName(unit_name, program_name, key);
        }

        pub fn duplicateProgramInfoKeyByName(self: *const Self, list_id: i32, program_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByName(list_id, program_name);
        }

        pub fn duplicateProgramInfoKeyByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByNameForListName(list_name, program_name);
        }

        pub fn duplicateProgramInfoKeyByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByNameForUnit(unit_id, program_name);
        }

        pub fn duplicateProgramInfoKeyByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?[]const u8 {
            return self.spec.units.duplicateProgramInfoKeyByNameForUnitName(unit_name, program_name);
        }

        pub fn duplicateProgramInfoKeyIndexByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByName(list_id, program_name);
        }

        pub fn duplicateProgramInfoKeyIndexByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByNameForListName(list_name, program_name);
        }

        pub fn duplicateProgramInfoKeyIndexByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByNameForUnit(unit_id, program_name);
        }

        pub fn duplicateProgramInfoKeyIndexByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.duplicateProgramInfoKeyIndexByNameForUnitName(unit_name, program_name);
        }

        pub fn hasDuplicateProgramInfoKeysByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByName(list_id, program_name);
        }

        pub fn hasDuplicateProgramInfoKeysByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByNameForListName(list_name, program_name);
        }

        pub fn hasDuplicateProgramInfoKeysByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByNameForUnit(unit_id, program_name);
        }

        pub fn hasDuplicateProgramInfoKeysByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.hasDuplicateProgramInfoKeysByNameForUnitName(unit_name, program_name);
        }

        pub fn programInfoCount(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.programInfoCount(list_id, program_index);
        }

        pub fn programInfoCountByListName(self: *const Self, list_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.programInfoCountByListName(list_name, program_index);
        }

        pub fn programInfoCountForUnit(self: *const Self, unit_id: i32, program_index: usize) ?usize {
            return self.spec.units.programInfoCountForUnit(unit_id, program_index);
        }

        pub fn programInfoCountForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) ?usize {
            return self.spec.units.programInfoCountForUnitName(unit_name, program_index);
        }

        pub fn programInfoCountByName(self: *const Self, list_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programInfoCountByName(list_id, program_name);
        }

        pub fn programInfoCountByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.programInfoCountByNameForListName(list_name, program_name);
        }

        pub fn programInfoCountByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) ?usize {
            return self.spec.units.programInfoCountByNameForUnit(unit_id, program_name);
        }

        pub fn programInfoCountByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) ?usize {
            return self.spec.units.programInfoCountByNameForUnitName(unit_name, program_name);
        }

        pub fn programHasInfoEntries(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programHasInfoEntries(list_id, program_index);
        }

        pub fn programHasInfoEntriesByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.programHasInfoEntriesByListName(list_name, program_index);
        }

        pub fn programHasInfoEntriesForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.programHasInfoEntriesForUnit(unit_id, program_index);
        }

        pub fn programHasInfoEntriesForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.programHasInfoEntriesForUnitName(unit_name, program_index);
        }

        pub fn programHasInfoEntriesByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasInfoEntriesByName(list_id, program_name);
        }

        pub fn programHasInfoEntriesByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programHasInfoEntriesByNameForListName(list_name, program_name);
        }

        pub fn programHasInfoEntriesByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.programHasInfoEntriesByNameForUnit(unit_id, program_name);
        }

        pub fn programHasInfoEntriesByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programHasInfoEntriesByNameForUnitName(unit_name, program_name);
        }

        pub fn programInfoEmpty(self: *const Self, list_id: i32, program_index: usize) bool {
            return self.spec.units.programInfoEmpty(list_id, program_index);
        }

        pub fn programInfoEmptyByListName(self: *const Self, list_name: []const u8, program_index: usize) bool {
            return self.spec.units.programInfoEmptyByListName(list_name, program_index);
        }

        pub fn programInfoEmptyForUnit(self: *const Self, unit_id: i32, program_index: usize) bool {
            return self.spec.units.programInfoEmptyForUnit(unit_id, program_index);
        }

        pub fn programInfoEmptyForUnitName(self: *const Self, unit_name: []const u8, program_index: usize) bool {
            return self.spec.units.programInfoEmptyForUnitName(unit_name, program_index);
        }

        pub fn programInfoEmptyByName(self: *const Self, list_id: i32, program_name: []const u8) bool {
            return self.spec.units.programInfoEmptyByName(list_id, program_name);
        }

        pub fn programInfoEmptyByNameForListName(self: *const Self, list_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programInfoEmptyByNameForListName(list_name, program_name);
        }

        pub fn programInfoEmptyByNameForUnit(self: *const Self, unit_id: i32, program_name: []const u8) bool {
            return self.spec.units.programInfoEmptyByNameForUnit(unit_id, program_name);
        }

        pub fn programInfoEmptyByNameForUnitName(self: *const Self, unit_name: []const u8, program_name: []const u8) bool {
            return self.spec.units.programInfoEmptyByNameForUnitName(unit_name, program_name);
        }

        pub fn applyProgram(self: *Self, list_id: i32, program_index: usize) !bool {
            return (try self.applyProgramCount(list_id, program_index)) != null;
        }

        fn validateProgramParameter(self: *const Self, parameter: units_api.ProgramParameter) !void {
            if (!common.isNormalized(parameter.normalized)) {
                return error.ProgramParameterOutsideNormalizedRange;
            }
            if (self.parameterIndexOfId(parameter.parameter_id) == null) return error.UnknownProgramParameter;
        }

        pub fn applyProgramCount(self: *Self, list_id: i32, program_index: usize) !?usize {
            const item = self.program(list_id, program_index) orelse return null;
            for (item.parameters) |parameter| {
                try self.validateProgramParameter(parameter);
            }
            var changed_count: usize = 0;
            for (item.parameters) |parameter| {
                changed_count += self.storeParameterByIdCount(parameter.parameter_id, parameter.normalized) orelse unreachable;
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

        pub fn applyProgramForListName(self: *Self, list_name: []const u8, program_index: usize) !bool {
            return (try self.applyProgramForListNameCount(list_name, program_index)) != null;
        }

        pub fn applyProgramForListNameCount(self: *Self, list_name: []const u8, program_index: usize) !?usize {
            const list = self.programListByName(list_name) orelse return null;
            return self.applyProgramCount(list.id, program_index);
        }

        pub fn applyProgramByNameForListName(self: *Self, list_name: []const u8, program_name: []const u8) !bool {
            return (try self.applyProgramByNameForListNameCount(list_name, program_name)) != null;
        }

        pub fn applyProgramByNameForListNameCount(self: *Self, list_name: []const u8, program_name: []const u8) !?usize {
            const list = self.programListByName(list_name) orelse return null;
            return self.applyProgramByNameCount(list.id, program_name);
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

        pub fn formatParameterPlain(self: *const Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.formatParameterPlainIndex(index, normalized, buffer);
        }

        pub fn formatParameterPlainIndex(self: *const Self, index: usize, normalized: f64, buffer: []u8) ![]const u8 {
            return self.parameterView().formatPlainIndex(index, normalized, buffer);
        }

        pub fn parseParameterPlain(self: *const Self, index: usize, text: []const u8) !f64 {
            return self.parseParameterPlainIndex(index, text);
        }

        pub fn parseParameterPlainIndex(self: *const Self, index: usize, text: []const u8) !f64 {
            return self.parameterView().parsePlainIndex(index, text);
        }

        pub fn parameterPlainFromNormalized(self: *const Self, index: usize, normalized: f64) ?f64 {
            return self.parameterPlainFromNormalizedIndex(index, normalized);
        }

        pub fn parameterPlainFromNormalizedIndex(self: *const Self, index: usize, normalized: f64) ?f64 {
            return self.parameterView().plainFromNormalizedIndex(index, normalized);
        }

        pub fn parameterNormalizedFromPlain(self: *const Self, index: usize, plain: f64) ?f64 {
            return self.parameterNormalizedFromPlainIndex(index, plain);
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

        pub fn validate(self: *const Self) !void {
            try self.spec.validate();
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

        pub fn parameterChangeNormalizedById(self: *const Self, wanted_id: u32, sample_offset: usize, normalized: f64) ?process_api.ParameterChange {
            return self.spec.parameter_set.parameterChangeNormalizedById(wanted_id, sample_offset, normalized);
        }

        pub fn parameterChangePlainById(self: *const Self, wanted_id: u32, sample_offset: usize, plain: f64) ?process_api.ParameterChange {
            return self.spec.parameter_set.parameterChangePlainById(wanted_id, sample_offset, plain);
        }

        pub fn parameterChangeNormalizedByName(self: *const Self, wanted_name: []const u8, sample_offset: usize, normalized: f64) ?process_api.ParameterChange {
            return self.spec.parameter_set.parameterChangeNormalizedByName(wanted_name, sample_offset, normalized);
        }

        pub fn parameterChangePlainByName(self: *const Self, wanted_name: []const u8, sample_offset: usize, plain: f64) ?process_api.ParameterChange {
            return self.spec.parameter_set.parameterChangePlainByName(wanted_name, sample_offset, plain);
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

        pub fn encodedParameterStateSize(_: *const Self) usize {
            return Spec.encoded_parameter_state_size;
        }

        pub fn parameterStateEncodedSize(self: *const Self) usize {
            return self.encodedParameterStateSize();
        }

        pub fn encodedParameterStateSizeForCount(_: *const Self, count: usize) usize {
            return state.encodedSizeForCount(count);
        }

        pub fn encodedParameterStateSizeForCountChecked(_: *const Self, count: usize) !usize {
            return state.encodedSizeForCountChecked(count);
        }

        pub fn parameterStateEncodedSizeForCount(self: *const Self, count: usize) usize {
            return self.encodedParameterStateSizeForCount(count);
        }

        pub fn parameterStateEncodedSizeForCountChecked(self: *const Self, count: usize) !usize {
            return self.encodedParameterStateSizeForCountChecked(count);
        }

        pub fn parameterStateEntryCount(self: *const Self) usize {
            return self.spec.parameter_set.parameterCount();
        }

        pub fn parameterStateHeaderEntryCount(_: *const Self, header: state.ParameterStateHeader) usize {
            return header.entryCount();
        }

        pub fn parameterStateHeaderHasEntries(_: *const Self, header: state.ParameterStateHeader) bool {
            return header.hasEntries();
        }

        pub fn parameterStateHeaderHasNoEntries(_: *const Self, header: state.ParameterStateHeader) bool {
            return header.hasNoEntries();
        }

        pub fn parameterStateHeaderEntriesEmpty(_: *const Self, header: state.ParameterStateHeader) bool {
            return header.entriesEmpty();
        }

        pub fn parameterStateHeaderIsCurrentVersion(_: *const Self, header: state.ParameterStateHeader) bool {
            return header.isCurrentVersion();
        }

        pub fn parameterStateHeaderEncodedSize(_: *const Self, header: state.ParameterStateHeader) usize {
            return header.encodedSize();
        }

        pub fn parameterStateHeaderEncodedSizeChecked(_: *const Self, header: state.ParameterStateHeader) !usize {
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

        pub fn parameterStateReportDecodedCount(_: *const Self, report: state.ReadParameterStateReport) usize {
            return report.decodedCount();
        }

        pub fn parameterStateReportRestoredCount(_: *const Self, report: state.ReadParameterStateReport) usize {
            return report.restoredCount();
        }

        pub fn parameterStateReportIgnoredCount(_: *const Self, report: state.ReadParameterStateReport) usize {
            return report.ignoredCount();
        }

        pub fn parameterStateReportAccountedCount(_: *const Self, report: state.ReadParameterStateReport) usize {
            return report.accountedCount();
        }

        pub fn parameterStateReportUnaccountedCount(_: *const Self, report: state.ReadParameterStateReport) usize {
            return report.unaccountedCount();
        }

        pub fn parameterStateReportHasDecodedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasDecodedEntries();
        }

        pub fn parameterStateReportHasNoDecodedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasNoDecodedEntries();
        }

        pub fn parameterStateReportDecodedEntriesEmpty(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.decodedEntriesEmpty();
        }

        pub fn parameterStateReportHasRestoredEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasRestoredEntries();
        }

        pub fn parameterStateReportHasNoRestoredEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasNoRestoredEntries();
        }

        pub fn parameterStateReportRestoredEntriesEmpty(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.restoredEntriesEmpty();
        }

        pub fn parameterStateReportHasIgnoredEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasIgnoredEntries();
        }

        pub fn parameterStateReportHasNoIgnoredEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasNoIgnoredEntries();
        }

        pub fn parameterStateReportIgnoredEntriesEmpty(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.ignoredEntriesEmpty();
        }

        pub fn parameterStateReportHasAccountedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasAccountedEntries();
        }

        pub fn parameterStateReportHasNoAccountedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasNoAccountedEntries();
        }

        pub fn parameterStateReportAccountedEntriesEmpty(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.accountedEntriesEmpty();
        }

        pub fn parameterStateReportHasUnaccountedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasUnaccountedEntries();
        }

        pub fn parameterStateReportHasNoUnaccountedEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.hasNoUnaccountedEntries();
        }

        pub fn parameterStateReportUnaccountedEntriesEmpty(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.unaccountedEntriesEmpty();
        }

        pub fn parameterStateReportAccountedAllEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.accountedAllEntries();
        }

        pub fn parameterStateReportAccountedPartialEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.accountedPartialEntries();
        }

        pub fn parameterStateReportRestoredAllEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.restoredAllEntries();
        }

        pub fn parameterStateReportRestoredPartialEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.restoredPartialEntries();
        }

        pub fn parameterStateReportIgnoredAllEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.ignoredAllEntries();
        }

        pub fn parameterStateReportIgnoredPartialEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.ignoredPartialEntries();
        }

        pub fn parameterStateReportRestoredAndIgnoredEntries(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.restoredAndIgnoredEntries();
        }

        pub fn parameterStateReportFullyHandled(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.fullyHandled();
        }

        pub fn parameterStateReportClassification(_: *const Self, report: state.ReadParameterStateReport) state.ReadParameterStateClassification {
            return report.classification();
        }

        pub fn parameterStateReportIsEmptyClassification(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.isEmptyClassification();
        }

        pub fn parameterStateReportIsRestoredAllClassification(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.isRestoredAllClassification();
        }

        pub fn parameterStateReportIsIgnoredAllClassification(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.isIgnoredAllClassification();
        }

        pub fn parameterStateReportIsRestoredAndIgnoredClassification(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.isRestoredAndIgnoredClassification();
        }

        pub fn parameterStateReportIsPartialClassification(_: *const Self, report: state.ReadParameterStateReport) bool {
            return report.isPartialClassification();
        }

        pub fn readParameterStateHeader(_: *const Self, reader: anytype) !state.ParameterStateHeader {
            return state.readParameterStateHeader(reader);
        }

        pub fn writeParameterState(self: *const Self, writer: anytype) !void {
            try state.writeParameterState(Plugin.Params, &self.spec.parameter_set, &self.spec.values, writer);
        }

        pub fn writeParameterStateHeader(self: *const Self, writer: anytype) !void {
            try self.writeParameterStateHeaderForCount(self.parameterStateEntryCount(), writer);
        }

        pub fn writeParameterStateHeaderForCount(_: *const Self, count: usize, writer: anytype) !void {
            try state.writeParameterStateHeaderForCount(count, writer);
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

        pub fn validateParameterIdMigrations(_: *const Self, migrations: []const state.ParameterIdMigration) !void {
            try state.validateParameterIdMigrations(migrations);
        }

        pub fn identityParameterMigrationIndex(_: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            return state.identityParameterMigrationIndex(migrations);
        }

        pub fn duplicateParameterMigrationIndex(_: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            return state.duplicateParameterMigrationIndex(migrations);
        }

        pub fn cyclicParameterMigrationIndex(_: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            return state.cyclicParameterMigrationIndex(migrations);
        }

        pub fn ambiguousParameterMigrationIndex(_: *const Self, migrations: []const state.ParameterIdMigration) ?usize {
            return state.ambiguousParameterMigrationIndex(migrations);
        }

        pub fn migratedParameterId(_: *const Self, id: u32, migrations: []const state.ParameterIdMigration) u32 {
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
