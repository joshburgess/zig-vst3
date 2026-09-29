const plug = @import("zig-vst3-plugin-core");

pub const level_param_id: u32 = 0;
pub const step_param_ids = [_]u32{ 100, 101, 102, 103, 104, 105, 106, 107 };

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

pub const Spec = plug.plugin.PluginSpec(SineSynthPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const level_param_index = parameter_set.indexOfId(level_param_id) orelse @compileError("Level parameter ID is missing from the parameter set");
pub const default_level = parameter_set.defaultNormalized(level_param_index) orelse @compileError("Level parameter default is unavailable");
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
