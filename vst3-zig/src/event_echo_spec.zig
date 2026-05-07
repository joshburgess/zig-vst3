const plug = @import("zig-plug-core");

const EventEchoPlugin = struct {
    pub const name = "zig-vst3 Event Echo";
    pub const vendor = "zig-vst3";
    pub const Params = struct {};
};

pub const Spec = plug.plugin.PluginSpec(EventEchoPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.name;
pub const controller_class_name = Spec.name ++ " Controller";
