const plug = @import("zig-plug-core");

pub const bypass_param_id: u32 = 0;

const BypassPlugin = struct {
    pub const name = "zig-vst3 Bypass";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        bypass: plug.parameters.BoolParam = .{ .id = bypass_param_id, .name = "Bypass", .default = false, .is_bypass = true },
    };
};

pub const Spec = plug.plugin.PluginSpec(BypassPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const bypass_param_index = parameter_set.indexOfId(bypass_param_id).?;
pub const component_class_name = Spec.name;
pub const controller_class_name = Spec.name ++ " Controller";
