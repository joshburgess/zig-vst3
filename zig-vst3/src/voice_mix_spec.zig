const plug = @import("zig-vst3-plugin-core");

pub const voices_param_id: u32 = 0;

const VoiceMixPlugin = struct {
    pub const name = "zig-vst3 Voice Mix";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        voices: plug.parameters.IntParam = plug.parameters.IntParam.init(voices_param_id, "Voices", 1, 4, 1),
    };
};

pub const Spec = plug.plugin.PluginSpec(VoiceMixPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const voices_param_index = parameter_set.indexOfId(voices_param_id) orelse @compileError("Voices parameter ID is missing from the parameter set");
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
