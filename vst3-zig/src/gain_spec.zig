const plug = @import("zig-plug-core");

pub const gain_param_id: u32 = 0;

const GainPlugin = struct {
    pub const name = "zig-vst3 Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = gain_param_id, .name = "Gain", .short_name = "Gain", .units = "x", .min = 0.0, .max = 1.0, .default = 1.0 },
    };
};

pub const Spec = plug.plugin.PluginSpec(GainPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const gain_param_index = parameter_set.indexOfId(gain_param_id).?;
pub const default_gain = parameter_set.defaultNormalized(gain_param_index).?;
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
