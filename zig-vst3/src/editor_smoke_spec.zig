const plug = @import("zig-vst3-plugin-core");

pub const gain_param_id: u32 = 0;
pub const voices_param_id: u32 = 1;
pub const bypass_param_id: u32 = 2;
pub const mode_param_id: u32 = 3;
pub const Mode = enum { clean, boost, mute };
pub const ModeParam = plug.parameters.EnumParam(Mode);

const EditorSmokePlugin = struct {
    pub const name = "zig-vst3 Editor Smoke";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = gain_param_id, .name = "Gain", .short_name = "Gain", .units = "x", .min = 0.0, .max = 1.0, .default = 1.0 },
        voices: plug.parameters.IntParam = plug.parameters.IntParam.init(voices_param_id, "Voices", 1, 4, 1),
        bypass: plug.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .default = false, .is_bypass = true },
        mode: ModeParam = .{ .id = mode_param_id, .name = "Mode", .default = .clean },
    };
};

pub const Spec = plug.plugin.PluginSpec(EditorSmokePlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
