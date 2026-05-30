const plug = @import("zig-vst3-plugin-core");

pub const gain_param_id: u32 = 0;

const EditorSmokePlugin = struct {
    pub const name = "zig-vst3 Editor Smoke";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = gain_param_id, .name = "Gain", .short_name = "Gain", .units = "x", .min = 0.0, .max = 1.0, .default = 1.0 },
    };
};

pub const Spec = plug.plugin.PluginSpec(EditorSmokePlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
