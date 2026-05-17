const plug = @import("zig-vst3-plugin-core");

pub const bypass_param_id: u32 = 0;

const BypassPlugin = struct {
    pub const name = "zig-vst3 Bypass";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .default = false, .is_bypass = true },
    };
};

pub const Spec = plug.plugin.PluginSpec(BypassPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const bypass_param_index = parameter_set.indexOfId(bypass_param_id) orelse @compileError("Bypass parameter ID is missing from the parameter set");
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
