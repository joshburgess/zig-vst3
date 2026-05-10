const plug = @import("zig-plug-core");

const EventMonitorPlugin = struct {
    pub const name = "zig-vst3 Event Monitor";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const audio_output = false;
    pub const Params = struct {};
};

pub const Spec = plug.plugin.PluginSpec(EventMonitorPlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
