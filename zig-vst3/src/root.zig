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
pub const event_monitor_component = @import("event_monitor_component.zig");
pub const event_monitor_controller = @import("event_monitor_controller.zig");
pub const event_monitor_plugin = @import("event_monitor_plugin.zig");
pub const event_monitor_spec = @import("event_monitor_spec.zig");
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
pub const sine_synth_component = @import("sine_synth_component.zig");
pub const sine_synth_controller = @import("sine_synth_controller.zig");
pub const sine_synth_plugin = @import("sine_synth_plugin.zig");
pub const sine_synth_spec = @import("sine_synth_spec.zig");
pub const pluginterfaces = struct {
    pub const base = @import("pluginterfaces/base/root.zig");
    pub const gui = @import("pluginterfaces/gui/root.zig");
    pub const @"test" = @import("pluginterfaces/test/root.zig");
    pub const vst = @import("pluginterfaces/vst/root.zig");
};
pub const tuid = @import("tuid.zig");
pub const version = "0.1.0-dev";
pub const vst_capability_support = @import("vst_capability_support.zig");
pub const vst_cloneable = @import("vst_cloneable.zig");
pub const vst_component_handler = @import("vst_component_handler.zig");
pub const vst_content_scale_support = @import("vst_content_scale_support.zig");
pub const vst_context_menu = @import("vst_context_menu.zig");
pub const vst_error_context = @import("vst_error_context.zig");
pub const vst_event_list = @import("vst_event_list.zig");
pub const vst_host_application = @import("vst_host_application.zig");
pub const vst_host_context = @import("vst_host_context.zig");
pub const vst_inter_app_audio = @import("vst_inter_app_audio.zig");
pub const vst_linux_run_loop = @import("vst_linux_run_loop.zig");
pub const vst_message = @import("vst_message.zig");
pub const vst_note_expression = @import("vst_note_expression.zig");
pub const vst_parameter_finder = @import("vst_parameter_finder.zig");
pub const vst_parameter_changes = @import("vst_parameter_changes.zig");
pub const vst_persistent_attributes = @import("vst_persistent_attributes.zig");
pub const vst_plug_frame = @import("vst_plug_frame.zig");
pub const vst_plug_view = @import("vst_plug_view.zig");
pub const vst_plugin_compatibility = @import("vst_plugin_compatibility.zig");
pub const vst_representation = @import("vst_representation.zig");
pub const vst_string_result = @import("vst_string_result.zig");
pub const vst_stream = @import("vst_stream.zig");
pub const vst_test_interfaces = @import("vst_test_interfaces.zig");
pub const vst_test_plug_provider = @import("vst_test_plug_provider.zig");
pub const vst_unit_data = @import("vst_unit_data.zig");
pub const vst_update_handler = @import("vst_update_handler.zig");
pub const vst_wayland_frame = @import("vst_wayland_frame.zig");
pub const voice_mix_component = @import("voice_mix_component.zig");
pub const voice_mix_controller = @import("voice_mix_controller.zig");
pub const voice_mix_plugin = @import("voice_mix_plugin.zig");
pub const voice_mix_spec = @import("voice_mix_spec.zig");
pub const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");
pub const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "zig-vst3 module exposes a development version" {
    try std.testing.expect(std.mem.endsWith(u8, version, "-dev"));
}

test {
    std.testing.refAllDecls(vst_capability_support);
    std.testing.refAllDecls(vst_cloneable);
    std.testing.refAllDecls(vst_component_handler);
    std.testing.refAllDecls(vst_content_scale_support);
    std.testing.refAllDecls(vst_context_menu);
    std.testing.refAllDecls(vst_error_context);
    std.testing.refAllDecls(vst_event_list);
    std.testing.refAllDecls(vst_host_application);
    std.testing.refAllDecls(vst_host_context);
    std.testing.refAllDecls(vst_message);
    std.testing.refAllDecls(vst_note_expression);
    std.testing.refAllDecls(vst_parameter_finder);
    std.testing.refAllDecls(vst_unit_data);
    std.testing.refAllDecls(vst_parameter_changes);
    std.testing.refAllDecls(vst_plug_frame);
    std.testing.refAllDecls(vst_plug_view);
    std.testing.refAllDecls(vst_representation);
    std.testing.refAllDecls(vst_string_result);
    std.testing.refAllDecls(vst_stream);
    std.testing.refAllDecls(vst_test_interfaces);
    std.testing.refAllDecls(vst_update_handler);
    std.testing.refAllDecls(vst_wayland_frame);
}
