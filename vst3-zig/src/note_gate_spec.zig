const plug = @import("zig-plug-core");

const NoteGatePlugin = struct {
    pub const name = "zig-vst3 Note Gate";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {};
};

pub const Spec = plug.plugin.PluginSpec(NoteGatePlugin);
pub const parameter_set = Spec.ParameterSet.init(.{});
pub const component_class_name = Spec.component_class_name;
pub const controller_class_name = Spec.controller_class_name;
