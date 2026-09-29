const parameters = @import("../parameters.zig");
const state = @import("../state.zig");
const units_api = @import("../units.zig");
const common = @import("common.zig");
const audio_layout = @import("audio_layout.zig");
const AudioBusLayout = audio_layout.AudioBusLayout;

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
    if (@hasDecl(Plugin, "audio_bus_topology")) {
        if (@hasDecl(Plugin, "audio_input_layout") or
            @hasDecl(Plugin, "audio_output_layout") or
            @hasDecl(Plugin, "audio_input") or
            @hasDecl(Plugin, "audio_output") or
            @hasDecl(Plugin, "audio_sidechain_layout") or
            @hasDecl(Plugin, "audio_auxiliary_input_layouts") or
            @hasDecl(Plugin, "audio_auxiliary_output_layout") or
            @hasDecl(Plugin, "audio_auxiliary_output_layouts"))
            @compileError(
                "audio_bus_topology conflicts with static audio bus declarations",
            );
        if (!Plugin.audio_bus_topology.valid())
            @compileError("audio_bus_topology must be valid");
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
        const declared_auxiliary_audio_bus_capacity =
            if (@hasDecl(Plugin, "maximum_auxiliary_audio_buses"))
                Plugin.maximum_auxiliary_audio_buses
            else
                audio_layout.max_auxiliary_audio_buses;
        pub const AudioBusTopology =
            if (@hasDecl(Plugin, "audio_bus_topology"))
                @TypeOf(Plugin.audio_bus_topology)
            else
                audio_layout.BoundedDynamicAudioBusTopology(
                    declared_auxiliary_audio_bus_capacity,
                );
        pub const AudioBusSnapshot =
            AudioBusTopology.SnapshotType;
        pub const auxiliary_audio_bus_capacity =
            AudioBusTopology.auxiliary_capacity;
        pub const dynamic_audio_bus_topology: ?AudioBusTopology =
            if (@hasDecl(Plugin, "audio_bus_topology"))
                Plugin.audio_bus_topology
            else
                null;
        const dynamic_audio_bus_snapshot: ?AudioBusSnapshot =
            if (dynamic_audio_bus_topology) |topology|
                topology.snapshot() catch
                    @compileError("invalid audio_bus_topology declaration")
            else
                null;
        pub const audio_input_layout: AudioBusLayout =
            if (dynamic_audio_bus_snapshot) |snapshot|
                if (snapshot.input_count != 0)
                    snapshot.input_layouts[0]
                else
                    .none
            else
                declaredAudioLayout(
                    Plugin,
                    "audio_input_layout",
                    "audio_input",
                );
        pub const audio_output_layout: AudioBusLayout =
            if (dynamic_audio_bus_snapshot) |snapshot|
                if (snapshot.output_count != 0)
                    snapshot.output_layouts[0]
                else
                    .none
            else
                declaredAudioLayout(
                    Plugin,
                    "audio_output_layout",
                    "audio_output",
                );
        pub const audio_auxiliary_input_layouts: []const AudioBusLayout =
            if (dynamic_audio_bus_snapshot) |*snapshot|
                snapshot.input_layouts[1..snapshot.input_count]
            else
                declaredAuxiliaryInputLayouts(
                    Plugin,
                    audio_input_layout,
                    auxiliary_audio_bus_capacity,
                );
        pub const audio_auxiliary_output_layouts: []const AudioBusLayout =
            if (dynamic_audio_bus_snapshot) |*snapshot|
                snapshot.output_layouts[1..snapshot.output_count]
            else
                declaredAuxiliaryOutputLayouts(
                    Plugin,
                    audio_output_layout,
                    auxiliary_audio_bus_capacity,
                );
        pub const audio_sidechain_layout: AudioBusLayout =
            firstLayout(audio_auxiliary_input_layouts);
        pub const audio_auxiliary_output_layout: AudioBusLayout =
            firstLayout(audio_auxiliary_output_layouts);
        pub const audio_input = audio_input_layout.hasBus();
        pub const audio_output = audio_output_layout.hasBus();
        pub const event_input = !@hasDecl(Plugin, "event_input") or Plugin.event_input;
        pub const event_output = @hasDecl(Plugin, "event_output") and Plugin.event_output;
        pub const follow_host_transport =
            @hasDecl(Plugin, "follow_host_transport") and
            Plugin.follow_host_transport;
        pub const allow_dynamic_process_mode =
            @hasDecl(Plugin, "allow_dynamic_process_mode") and
            Plugin.allow_dynamic_process_mode;
        pub const unit_config = if (@hasDecl(Plugin, "units")) Plugin.units else units_api.Config{};
        pub const has_init = @hasDecl(Plugin, "init");
        pub const has_prepare = @hasDecl(Plugin, "prepare");
        pub const has_activate = @hasDecl(Plugin, "activate");
        pub const has_deactivate = @hasDecl(Plugin, "deactivate");
        pub const has_reset = @hasDecl(Plugin, "reset");
        pub const has_release_resources =
            @hasDecl(Plugin, "releaseResources");
        pub const has_after_state_restore =
            @hasDecl(Plugin, "afterStateRestore");
        pub const has_latency_samples =
            @hasDecl(Plugin, "latencySamples");
        pub const has_tail_samples =
            @hasDecl(Plugin, "tailSamples");
        pub const has_bind_host_requests =
            @hasDecl(Plugin, "bindHostRequests");
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

        comptime {
            if (@hasDecl(Plugin, "audio_bus_topology") and
                @hasDecl(
                    Plugin,
                    "maximum_auxiliary_audio_buses",
                ) and
                declared_auxiliary_audio_bus_capacity !=
                    auxiliary_audio_bus_capacity)
                @compileError(
                    "maximum_auxiliary_audio_buses must match audio_bus_topology capacity",
                );
        }

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

        /// Use `initChecked` when parameter descriptors are not compile-time constants.
        pub fn init(comptime params: Params) Self {
            return comptime initChecked(params) catch |err|
                @compileError("invalid plugin metadata: " ++ @errorName(err));
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

fn declaredAuxiliaryInputLayouts(
    comptime Plugin: type,
    comptime main_layout: AudioBusLayout,
    comptime maximum_auxiliary_buses: usize,
) []const AudioBusLayout {
    const layouts: []const AudioBusLayout = if (@hasDecl(
        Plugin,
        "audio_auxiliary_input_layouts",
    )) Plugin.audio_auxiliary_input_layouts else if (@hasDecl(
        Plugin,
        "audio_sidechain_layout",
    )) &.{Plugin.audio_sidechain_layout} else &.{};
    if (@hasDecl(Plugin, "audio_auxiliary_input_layouts") and
        @hasDecl(Plugin, "audio_sidechain_layout"))
        @compileError("audio_auxiliary_input_layouts conflicts with audio_sidechain_layout");
    validateAuxiliaryLayouts(
        layouts,
        main_layout,
        maximum_auxiliary_buses,
        "audio_auxiliary_input_layouts",
        "audio input",
    );
    return layouts;
}

fn declaredAuxiliaryOutputLayouts(
    comptime Plugin: type,
    comptime main_layout: AudioBusLayout,
    comptime maximum_auxiliary_buses: usize,
) []const AudioBusLayout {
    const layouts: []const AudioBusLayout = if (@hasDecl(
        Plugin,
        "audio_auxiliary_output_layouts",
    )) Plugin.audio_auxiliary_output_layouts else if (@hasDecl(
        Plugin,
        "audio_auxiliary_output_layout",
    )) &.{Plugin.audio_auxiliary_output_layout} else &.{};
    if (@hasDecl(Plugin, "audio_auxiliary_output_layouts") and
        @hasDecl(Plugin, "audio_auxiliary_output_layout"))
        @compileError("audio_auxiliary_output_layouts conflicts with audio_auxiliary_output_layout");
    validateAuxiliaryLayouts(
        layouts,
        main_layout,
        maximum_auxiliary_buses,
        "audio_auxiliary_output_layouts",
        "audio output",
    );
    return layouts;
}

fn validateAuxiliaryLayouts(
    comptime layouts: []const AudioBusLayout,
    comptime main_layout: AudioBusLayout,
    comptime maximum_auxiliary_buses: usize,
    comptime declaration: []const u8,
    comptime main_name: []const u8,
) void {
    if (layouts.len > maximum_auxiliary_buses)
        @compileError(declaration ++ " exceeds the auxiliary bus limit");
    if (layouts.len != 0 and !main_layout.hasBus())
        @compileError(declaration ++ " requires a main " ++ main_name ++ " bus");
    for (layouts) |layout| {
        if (!layout.hasBus())
            @compileError(declaration ++ " cannot contain .none");
    }
}

fn firstLayout(comptime layouts: []const AudioBusLayout) AudioBusLayout {
    return if (layouts.len == 0) .none else layouts[0];
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
