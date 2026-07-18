const plug = @import("zig-vst3-plugin-core");

pub const gain_param_id: u32 = 0;
pub const voices_param_id: u32 = 1;
pub const bypass_param_id: u32 = 2;
pub const mode_param_id: u32 = 3;
pub const step_param_ids = [_]u32{ 100, 101, 102, 103, 104, 105, 106, 107 };
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
        step_1: plug.parameters.BoolParam = .{ .id = step_param_ids[0], .name = "Step 1", .default = true },
        step_2: plug.parameters.BoolParam = .{ .id = step_param_ids[1], .name = "Step 2", .default = false },
        step_3: plug.parameters.BoolParam = .{ .id = step_param_ids[2], .name = "Step 3", .default = true },
        step_4: plug.parameters.BoolParam = .{ .id = step_param_ids[3], .name = "Step 4", .default = false },
        step_5: plug.parameters.BoolParam = .{ .id = step_param_ids[4], .name = "Step 5", .default = true },
        step_6: plug.parameters.BoolParam = .{ .id = step_param_ids[5], .name = "Step 6", .default = false },
        step_7: plug.parameters.BoolParam = .{ .id = step_param_ids[6], .name = "Step 7", .default = true },
        step_8: plug.parameters.BoolParam = .{ .id = step_param_ids[7], .name = "Step 8", .default = false },
    };
};

pub const Spec = plug.plugin.PluginSpec(EditorSmokePlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
