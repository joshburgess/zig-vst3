const plug = @import("zig-vst3-plugin-core");

pub const mode_param_id: u32 = 0;
pub const Mode = enum { clean, boost, mute };
pub const ModeParam = plug.parameters.EnumParam(Mode);

const ModeGainPlugin = struct {
    pub const name = "zig-vst3 Mode Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        mode: ModeParam = .{ .id = mode_param_id, .name = "Mode", .default = .clean },
    };
};

pub const Spec = plug.plugin.PluginSpec(ModeGainPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const mode_param_index = parameter_set.indexOfId(mode_param_id) orelse @compileError("Mode parameter ID is missing from the parameter set");
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
