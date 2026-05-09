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
            const set = ParameterSet.init(params);
            try set.validate();
            const units = Units{};
            try units.validate();
            try set.validateUnitIds(units);
            return .{
                .parameter_set = set,
                .values = ParameterValues.init(&set),
                .units = units,
            };
        }

        pub fn init(params: Params) Self {
            return initChecked(params) catch @panic("invalid parameter metadata");
        }
    };
}

pub const PrepareConfig = struct {
    sample_rate: f64,
    max_block_size: u32,
};

pub fn PluginInstance(comptime Plugin: type) type {
    validateLifecycle(Plugin);

    return struct {
        const Self = @This();
        pub const Spec = PluginSpec(Plugin);

        spec: Spec,
        plugin: Plugin,

        pub fn init(allocator: std.mem.Allocator, params: Plugin.Params) !Self {
            const plugin = if (Spec.has_init)
                try Plugin.init(allocator)
            else
                Plugin{};

            return .{
                .spec = try Spec.initChecked(params),
                .plugin = plugin,
            };
        }

        pub fn prepare(self: *Self, config: PrepareConfig) void {
            if (Spec.has_prepare) {
                self.plugin.prepare(config);
            }
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

        pub fn unitSet(self: *const Self) *const Spec.Units {
            return &self.spec.units;
        }

        pub fn unitCount(self: *const Self) usize {
            return self.spec.units.unitCount();
        }

        pub fn unit(self: *const Self, index: usize) ?units_api.Unit {
            return self.spec.units.unit(index);
        }

        pub fn unitById(self: *const Self, id: i32) ?units_api.Unit {
            return self.spec.units.unitById(id);
        }

        pub fn hasUnit(self: *const Self, id: i32) bool {
            return self.spec.units.hasUnit(id);
        }

        pub fn programListCount(self: *const Self) usize {
            return self.spec.units.programListCount();
        }

        pub fn programList(self: *const Self, index: usize) ?units_api.ProgramList {
            return self.spec.units.programList(index);
        }

        pub fn programListById(self: *const Self, id: i32) ?units_api.ProgramList {
            return self.spec.units.programListById(id);
        }

        pub fn hasProgramList(self: *const Self, id: i32) bool {
            return self.spec.units.hasProgramList(id);
        }

        pub fn programListForUnit(self: *const Self, unit_id: i32) ?units_api.ProgramList {
            return self.spec.units.programListForUnit(unit_id);
        }

        pub fn programCount(self: *const Self, list_id: i32) ?usize {
            return self.spec.units.programCount(list_id);
        }

        pub fn programName(self: *const Self, list_id: i32, program_index: usize) ?[]const u8 {
            return self.spec.units.programName(list_id, program_index);
        }

        pub fn program(self: *const Self, list_id: i32, program_index: usize) ?units_api.Program {
            return self.spec.units.program(list_id, program_index);
        }

        pub fn programIndexOfName(self: *const Self, list_id: i32, name: []const u8) ?usize {
            return self.spec.units.programIndexOfName(list_id, name);
        }

        pub fn programParameterCount(self: *const Self, list_id: i32, program_index: usize) ?usize {
            return self.spec.units.programParameterCount(list_id, program_index);
        }

        pub fn programParameter(self: *const Self, list_id: i32, program_index: usize, parameter_index: usize) ?units_api.ProgramParameter {
            return self.spec.units.programParameter(list_id, program_index, parameter_index);
        }

        pub fn programParameterById(self: *const Self, list_id: i32, program_index: usize, parameter_id: u32) ?units_api.ProgramParameter {
            return self.spec.units.programParameterById(list_id, program_index, parameter_id);
        }

        pub fn programInfo(self: *const Self, list_id: i32, program_index: usize, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfo(list_id, program_index, key);
        }

        pub fn programInfoByName(self: *const Self, list_id: i32, program_name: []const u8, key: []const u8) ?[]const u8 {
            return self.spec.units.programInfoByName(list_id, program_name, key);
        }

        pub fn applyProgram(self: *Self, list_id: i32, program_index: usize) !bool {
            const item = self.program(list_id, program_index) orelse return false;
            for (item.parameters) |parameter| {
                if (parameter.normalized < 0.0 or parameter.normalized > 1.0 or std.math.isNan(parameter.normalized)) {
                    return error.ProgramParameterOutsideNormalizedRange;
                }
            }
            for (item.parameters) |parameter| {
                _ = self.storeParameterById(parameter.parameter_id, parameter.normalized);
            }
            return true;
        }

        pub fn applyProgramByName(self: *Self, list_id: i32, program_name: []const u8) !bool {
            const index = self.programIndexOfName(list_id, program_name) orelse return false;
            return self.applyProgram(list_id, index);
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

        pub fn parameterId(self: *const Self, index: usize) ?u32 {
            return self.parameterView().id(index);
        }

        pub fn parameterName(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().name(index);
        }

        pub fn parameterNameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().nameById(wanted_id);
        }

        pub fn parameterShortName(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().shortName(index);
        }

        pub fn parameterShortNameById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().shortNameById(wanted_id);
        }

        pub fn parameterUnits(self: *const Self, index: usize) ?[]const u8 {
            return self.parameterView().units(index);
        }

        pub fn parameterUnitsById(self: *const Self, wanted_id: u32) ?[]const u8 {
            return self.parameterView().unitsById(wanted_id);
        }

        pub fn parameterDefaultNormalized(self: *const Self, index: usize) ?f64 {
            return self.parameterView().defaultNormalized(index);
        }

        pub fn parameterDefaultNormalizedById(self: *const Self, wanted_id: u32) ?f64 {
            return self.parameterView().defaultNormalizedById(wanted_id);
        }

        pub fn parameterIsBypass(self: *const Self, index: usize) ?bool {
            return self.parameterView().isBypass(index);
        }

        pub fn parameterIsBypassById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isBypassById(wanted_id);
        }

        pub fn parameterCanAutomate(self: *const Self, index: usize) ?bool {
            return self.parameterView().canAutomate(index);
        }

        pub fn parameterCanAutomateById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().canAutomateById(wanted_id);
        }

        pub fn parameterIsReadOnly(self: *const Self, index: usize) ?bool {
            return self.parameterView().isReadOnly(index);
        }

        pub fn parameterIsReadOnlyById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isReadOnlyById(wanted_id);
        }

        pub fn parameterUnitId(self: *const Self, index: usize) ?i32 {
            return self.parameterView().unitId(index);
        }

        pub fn parameterUnitIdById(self: *const Self, wanted_id: u32) ?i32 {
            return self.parameterView().unitIdById(wanted_id);
        }

        pub fn parameterStepCount(self: *const Self, index: usize) ?i32 {
            return self.parameterView().stepCount(index);
        }

        pub fn parameterStepCountById(self: *const Self, wanted_id: u32) ?i32 {
            return self.parameterView().stepCountById(wanted_id);
        }

        pub fn parameterIsList(self: *const Self, index: usize) ?bool {
            return self.parameterView().isList(index);
        }

        pub fn parameterIsListById(self: *const Self, wanted_id: u32) ?bool {
            return self.parameterView().isListById(wanted_id);
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

        pub fn parameterFieldIndex(self: *const Self, comptime field_name: []const u8) usize {
            return self.spec.parameter_set.indexOfField(field_name);
        }

        pub fn parameterFieldId(self: *const Self, comptime field_name: []const u8) u32 {
            return self.spec.parameter_set.fieldId(field_name);
        }

        pub fn parameterFieldName(self: *const Self, comptime field_name: []const u8) []const u8 {
            return self.spec.parameter_set.fieldName(field_name);
        }

        pub fn parameterFieldDefaultNormalized(self: *const Self, comptime field_name: []const u8) f64 {
            return self.spec.parameter_set.fieldDefaultNormalized(field_name);
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

        pub fn storeParameter(self: *Self, comptime field_name: []const u8, plain: parameters.FieldPlainType(Plugin.Params, field_name)) bool {
            return self.parameterEditor().store(field_name, plain);
        }

        pub fn storeParameterNormalized(self: *Self, comptime field_name: []const u8, normalized: f64) bool {
            return self.parameterEditor().storeNormalized(field_name, normalized);
        }

        pub fn storeParameterIndex(self: *Self, index: usize, normalized: f64) bool {
            return self.parameterEditor().storeIndex(index, normalized);
        }

        pub fn storeParameterPlainIndex(self: *Self, index: usize, plain: f64) bool {
            return self.parameterEditor().storePlainIndex(index, plain);
        }

        pub fn storeParameterById(self: *Self, id: u32, normalized: f64) bool {
            return self.parameterEditor().storeById(id, normalized);
        }

        pub fn storeParameterPlainById(self: *Self, id: u32, plain: f64) bool {
            return self.parameterEditor().storePlainById(id, plain);
        }

        pub fn storeParameterByName(self: *Self, name: []const u8, normalized: f64) bool {
            return self.parameterEditor().storeByName(name, normalized);
        }

        pub fn storeParameterPlainByName(self: *Self, name: []const u8, plain: f64) bool {
            return self.parameterEditor().storePlainByName(name, plain);
        }

        pub fn resetParametersToDefaults(self: *Self) void {
            self.spec.values.resetToDefaults(&self.spec.parameter_set);
        }

        pub fn applyParameterChanges(self: *Self, changes: process_api.ParameterChanges) void {
            self.spec.values.applyChanges(&self.spec.parameter_set, changes);
        }

        pub fn applyParameterChangesCount(self: *Self, changes: process_api.ParameterChanges) usize {
            return self.spec.values.applyChangesCount(&self.spec.parameter_set, changes);
        }

        pub fn encodedParameterStateSize(self: *const Self) usize {
            _ = self;
            return Spec.encoded_parameter_state_size;
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

        pub fn readParameterStateWithMigrations(
            self: *Self,
            reader: anytype,
            migrations: []const state.ParameterIdMigration,
        ) !void {
            try state.readParameterStateWithMigrations(Plugin.Params, &self.spec.parameter_set, &self.spec.values, reader, migrations);
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

    try std.testing.expectError(error.DuplicateParameterId, PluginSpec(Duplicate).initChecked(.{}));
    try std.testing.expectError(error.DuplicateParameterName, PluginSpec(DuplicateName).initChecked(.{}));
    try std.testing.expectError(error.InvalidParameterRange, PluginInstance(Invalid).init(std.testing.allocator, .{}));
    try std.testing.expectError(error.InvalidParameterDefault, PluginInstance(InvalidDefault).init(std.testing.allocator, .{}));
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

    try std.testing.expectEqualStrings("https://example.test/custom", Spec.url);
    try std.testing.expectEqualStrings("plugins@example.test", Spec.email);
    try std.testing.expectEqualStrings("Custom Processor", Spec.component_class_name);
    try std.testing.expectEqualStrings("Custom Editor", Spec.controller_class_name);
    try std.testing.expectEqualStrings("Custom Processor Category", Spec.component_category);
    try std.testing.expectEqualStrings("Custom Controller Category", Spec.controller_category);
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
    try std.testing.expectEqualStrings("Voice", instance.unitById(1).?.name);
    try std.testing.expect(instance.hasUnit(1));
    try std.testing.expect(!instance.hasUnit(99));
    try std.testing.expectEqual(@as(usize, 1), instance.programListCount());
    try std.testing.expectEqualStrings("Voice Programs", instance.programListById(7).?.name);
    try std.testing.expect(instance.hasProgramList(7));
    try std.testing.expect(!instance.hasProgramList(99));
    try std.testing.expectEqualStrings("Voice Programs", instance.programListForUnit(1).?.name);
    try std.testing.expectEqual(@as(?usize, 2), instance.programCount(7));
    try std.testing.expectEqualStrings("Lead", instance.programName(7, 1).?);
    try std.testing.expectEqualStrings("Lead", instance.program(7, 1).?.name);
    try std.testing.expectEqual(@as(?usize, 1), instance.programIndexOfName(7, "Lead"));
    try std.testing.expectEqual(@as(?usize, 1), instance.programParameterCount(7, 1));
    try std.testing.expectEqual(@as(f64, 0.75), instance.programParameterById(7, 1, 1).?.normalized);
    try std.testing.expectEqualStrings("Clean", instance.programInfo(7, 0, "category").?);
    try std.testing.expectEqualStrings("Clean", instance.programInfoByName(7, "Clean", "category").?);
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
            .program_lists = &.{.{ .id = 7, .name = "Programs", .programs = &programs }},
        };
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
        };
    };
    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});

    try std.testing.expect(try instance.applyProgram(7, 0));
    try std.testing.expectEqual(@as(f64, 0.25), instance.loadParameterNormalized("gain"));
    try std.testing.expect(try instance.applyProgramByName(7, "High"));
    try std.testing.expectEqual(@as(f64, 0.75), instance.loadParameterNormalized("gain"));
    try std.testing.expect(!try instance.applyProgram(7, 99));
    try std.testing.expect(!try instance.applyProgramByName(7, "Missing"));
}

test "plugin instance rejects invalid program parameter snapshots without partial updates" {
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
    var instance = try PluginInstance(Gain).init(std.testing.allocator, .{});

    try std.testing.expectError(error.ProgramParameterOutsideNormalizedRange, instance.applyProgram(7, 0));
    try std.testing.expectEqual(@as(f64, 1.0), instance.loadParameterNormalized("gain"));
    try std.testing.expectEqual(@as(f64, 0.5), instance.loadParameterNormalized("mix"));
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

test "plugin spec allows declaration-only plugin types" {
    const Minimal = struct {
        pub const name = "Minimal";
        pub const vendor = "zig-vst3";
        pub const Params = struct {};
    };
    const Spec = PluginSpec(Minimal);

    try std.testing.expect(!Spec.has_init);
    try std.testing.expect(!Spec.has_prepare);
    try std.testing.expect(!Spec.has_process);
    try std.testing.expect(!Spec.has_process_with_parameters);
    try std.testing.expect(!Spec.has_process64);
    try std.testing.expect(!Spec.has_process64_with_parameters);
    try std.testing.expect(!Spec.has_deinit);
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
        instance.parameterSet().parameterChange("gain", 0, 0.25),
        .{ .id = 99, .sample_offset = 0, .normalized = 1.0 },
    };
    const view = try process_api.ParameterChanges.init(&changes, 1);

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));

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

    try std.testing.expectEqual(@as(usize, 1), instance.applyParameterChangesCount(view));
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
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", -12.0, 6.0, 0.0),
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass", .can_automate = false, .is_read_only = true },
            mode: parameters.EnumParam(Mode) = .{ .id = 2, .name = "Mode", .default = .clean },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    try std.testing.expectEqual(@as(?usize, 0), instance.parameterIndexOfId(0));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 2), instance.parameterIndexOfName("Mode"));
    try std.testing.expectEqual(@as(?usize, null), instance.parameterIndexOfName("Missing"));
    try std.testing.expectEqual(@as(usize, 3), instance.parameterCount());
    try std.testing.expectEqual(@as(?u32, 0), instance.parameterId(0));
    try std.testing.expectEqualStrings("Bypass", instance.parameterName(1).?);
    try std.testing.expectEqualStrings("Mode", instance.parameterNameById(2).?);
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalized(2));
    try std.testing.expectEqual(@as(?f64, 0.0), instance.parameterDefaultNormalizedById(2));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypass(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsBypassById(0));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterCanAutomate(0));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterCanAutomateById(1));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsReadOnly(1));
    try std.testing.expectEqual(@as(?bool, false), instance.parameterIsReadOnlyById(0));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCount(2));
    try std.testing.expectEqual(@as(?i32, 2), instance.parameterStepCountById(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsList(2));
    try std.testing.expectEqual(@as(?bool, true), instance.parameterIsListById(2));
    try std.testing.expectEqual(@as(?u32, null), instance.parameterId(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterName(99));
    try std.testing.expectEqual(@as(?[]const u8, null), instance.parameterNameById(99));
    try std.testing.expectEqual(@as(?f64, null), instance.parameterDefaultNormalizedById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsBypassById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterCanAutomateById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsReadOnlyById(99));
    try std.testing.expectEqual(@as(?i32, null), instance.parameterStepCountById(99));
    try std.testing.expectEqual(@as(?bool, null), instance.parameterIsListById(99));
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
    try std.testing.expectEqual(@as(u32, 2), instance.parameterFieldId("mode"));
    try std.testing.expectEqualStrings("Gain", instance.parameterFieldName("gain"));
    try std.testing.expectEqual(@as(f64, 0.0), instance.parameterFieldDefaultNormalized("mode"));
    try std.testing.expectEqualStrings("mute", try instance.formatParameterFieldPlain("mode", 1.0, &buffer));
    try std.testing.expectEqual(@as(f64, 1.0), try instance.parseParameterFieldPlain("mode", "mute"));
    try std.testing.expectEqual(Mode.mute, instance.parameterFieldPlainFromNormalized("mode", 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), instance.parameterFieldNormalizedFromPlain("mode", .mute));

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

    instance.resetParametersToDefaults();
    try std.testing.expectEqual(@as(f64, 0.0), instance.loadParameter("gain"));
    try std.testing.expectEqual(false, instance.loadParameter("bypass"));
    try std.testing.expectEqual(Mode.clean, instance.loadParameter("mode"));
}

test "plugin instance exposes parameter editor" {
    const Gain = struct {
        pub const name = "Instance Parameter Editor";
        pub const vendor = "zig-vst3";
        pub const Params = struct {
            gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 0.5),
            bypass: parameters.BoolParam = .{ .id = 1, .name = "Bypass" },
        };
    };
    const Instance = PluginInstance(Gain);
    var instance = try Instance.init(std.testing.allocator, .{});

    const editor = instance.parameterEditor();
    try std.testing.expect(editor.store("gain", 0.75));
    try std.testing.expect(editor.storePlainById(1, 1.0));

    const view = instance.parameterView();
    try std.testing.expectEqual(@as(f64, 0.75), view.load("gain"));
    try std.testing.expectEqual(true, view.load("bypass"));
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
        instance.parameterSet().parameterChange("gain", 0, 0.25),
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
        instance.parameterSet().parameterChange("gain", 0, 0.25),
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
        instance.parameterSet().parameterChange("gain", 0, 0.25),
    };
    var context = process_api.ProcessContext(f32){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process(&context);

    try std.testing.expectEqual(@as(?f64, 0.25), instance.plugin.observed);
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
        instance.parameterSet().parameterChange("gain", 0, 0.75),
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
        instance.parameterSet().parameterChange("gain", 0, 0.75),
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
        instance.parameterSet().parameterChange("gain", 0, 0.75),
    };
    var context = process_api.ProcessContext(f64){
        .sample_rate = 48_000.0,
        .parameter_changes = try process_api.ParameterChanges.init(&changes, 1),
    };

    instance.process64(&context);

    try std.testing.expectEqual(@as(?f64, 0.75), instance.plugin.observed);
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
    try std.testing.expect(instance.storeParameterNormalized("gain", 0.25));
    try std.testing.expect(instance.storeParameterNormalized("mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try instance.writeParameterState(out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try restored.readParameterState(in_stream.reader());

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
    try new_instance.readParameterStateWithMigrations(in_stream.reader(), &.{
        .{ .old_id = 7, .new_id = 9 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try std.testing.expectEqual(@as(f64, 0.25), new_instance.loadParameterNormalized("output"));
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
