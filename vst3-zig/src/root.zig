const std = @import("std");

pub const entry = @import("entry.zig");
pub const bypass_component = @import("bypass_component.zig");
pub const bypass_controller = @import("bypass_controller.zig");
pub const bypass_plugin = @import("bypass_plugin.zig");
pub const bypass_spec = @import("bypass_spec.zig");
pub const event_echo_component = @import("event_echo_component.zig");
pub const event_echo_controller = @import("event_echo_controller.zig");
pub const event_echo_plugin = @import("event_echo_plugin.zig");
pub const event_echo_spec = @import("event_echo_spec.zig");
pub const factory = @import("factory.zig");
pub const funknown = @import("funknown.zig");
pub const gain_component = @import("gain_component.zig");
pub const gain_controller = @import("gain_controller.zig");
pub const gain_spec = @import("gain_spec.zig");
pub const interface_map = @import("interface_map.zig");
pub const mode_gain_component = @import("mode_gain_component.zig");
pub const mode_gain_controller = @import("mode_gain_controller.zig");
pub const mode_gain_plugin = @import("mode_gain_plugin.zig");
pub const mode_gain_spec = @import("mode_gain_spec.zig");
pub const multi_interface = @import("multi_interface.zig");
pub const note_gate_component = @import("note_gate_component.zig");
pub const note_gate_controller = @import("note_gate_controller.zig");
pub const note_gate_plugin = @import("note_gate_plugin.zig");
pub const note_gate_spec = @import("note_gate_spec.zig");
pub const pluginterfaces = struct {
    pub const base = @import("pluginterfaces/base/root.zig");
    pub const gui = @import("pluginterfaces/gui/root.zig");
    pub const @"test" = @import("pluginterfaces/test/root.zig");
    pub const vst = @import("pluginterfaces/vst/root.zig");
};
pub const tuid = @import("tuid.zig");
pub const version = "0.1.0-dev";
pub const vst_content_scale_support = @import("vst_content_scale_support.zig");
pub const vst_message = @import("vst_message.zig");
pub const vst_parameter_finder = @import("vst_parameter_finder.zig");
pub const vst_persistent_attributes = @import("vst_persistent_attributes.zig");
pub const vst_plugin_compatibility = @import("vst_plugin_compatibility.zig");
pub const vst_string_result = @import("vst_string_result.zig");
pub const vst_wayland_frame = @import("vst_wayland_frame.zig");
pub const voice_mix_component = @import("voice_mix_component.zig");
pub const voice_mix_controller = @import("voice_mix_controller.zig");
pub const voice_mix_plugin = @import("voice_mix_plugin.zig");
pub const voice_mix_spec = @import("voice_mix_spec.zig");
pub const zig_plug_bridge = @import("zig_plug_bridge.zig");
pub const zig_plug_effect = @import("zig_plug_effect.zig");

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "vst3-zig module exposes a development version" {
    try std.testing.expect(std.mem.endsWith(u8, version, "-dev"));
}
