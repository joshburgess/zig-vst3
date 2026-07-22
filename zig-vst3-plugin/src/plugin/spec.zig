const parameters = @import("../parameters.zig");
const state = @import("../state.zig");
const units_api = @import("../units.zig");
const common = @import("common.zig");
const AudioBusLayout = @import("audio_layout.zig").AudioBusLayout;

const validateRequiredMetadataString = common.validateRequiredMetadataString;
const validateOptionalMetadataString = common.validateOptionalMetadataString;

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
        pub const audio_input_layout: AudioBusLayout = declaredAudioLayout(Plugin, "audio_input_layout", "audio_input");
        pub const audio_output_layout: AudioBusLayout = declaredAudioLayout(Plugin, "audio_output_layout", "audio_output");
        pub const audio_input = audio_input_layout.hasBus();
        pub const audio_output = audio_output_layout.hasBus();
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
        pub const has_process32_hook = has_process or has_process_with_parameter_view or has_process_with_parameters;
        pub const has_process64_hook = has_process64 or has_process64_with_parameter_view or has_process64_with_parameters;
        pub const has_any_process_hook = has_process32_hook or has_process64_hook;
        pub const has_deinit = @hasDecl(Plugin, "deinit");

        parameter_set: ParameterSet,
        values: ParameterValues,
        units: Units = .{},

        pub fn initChecked(params: Params) !Self {
            const set = ParameterSet.init(params);
            const units = Units{};
            const spec = Self{
                .parameter_set = set,
                .values = ParameterValues.init(&set),
                .units = units,
            };
            try spec.validate();
            return spec;
        }

        pub fn init(params: Params) Self {
            return initChecked(params) catch @panic("invalid plugin metadata");
        }

        pub fn validate(self: *const Self) !void {
            try validateMetadata();
            try self.parameter_set.validate();
            try self.units.validate();
            try self.parameter_set.validateUnitIds(self.units);
            try self.units.validateProgramParameterIds(&self.parameter_set);
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

fn declaredAudioLayout(comptime Plugin: type, comptime layout_name: []const u8, comptime legacy_name: []const u8) AudioBusLayout {
    if (@hasDecl(Plugin, layout_name)) {
        const layout: AudioBusLayout = @field(Plugin, layout_name);
        if (@hasDecl(Plugin, legacy_name) and @field(Plugin, legacy_name) != layout.hasBus()) {
            @compileError(layout_name ++ " conflicts with " ++ legacy_name);
        }
        return layout;
    }
    if (@hasDecl(Plugin, legacy_name) and !@field(Plugin, legacy_name)) return .none;
    return .stereo;
}
