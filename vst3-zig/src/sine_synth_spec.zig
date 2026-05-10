const plug = @import("zig-plug-core");

pub const level_param_id: u32 = 0;

const SineSynthPlugin = struct {
    pub const name = "zig-vst3 Sine Synth";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_input = false;
    pub const Params = struct {
        level: plug.parameters.FloatParam = .{
            .id = level_param_id,
            .name = "Level",
            .short_name = "Level",
            .min = 0.0,
            .max = 1.0,
            .default = 0.1,
        },
    };
};

pub const Spec = plug.plugin.PluginSpec(SineSynthPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const level_param_index = parameter_set.indexOfId(level_param_id).?;
pub const default_level = parameter_set.defaultNormalized(level_param_index).?;
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
