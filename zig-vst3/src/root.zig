const std = @import("std");

pub const entry = @import("entry.zig");
pub const ara_document_controller =
    @import("ara_document_controller.zig");
pub const ara_content_fades =
    @import("ara_content_fades.zig");
pub const ara_extension = @import("ara_extension.zig");
pub const ara_factory = @import("ara_factory.zig");
pub const ara_model = @import("ara_model.zig");
pub const ara_playback_renderer =
    @import("ara_playback_renderer.zig");
pub const ara_registration = @import("ara_registration.zig");
pub const ara_source_cache = @import("ara_source_cache.zig");
pub const ara_spectral_transform =
    @import("ara_spectral_transform.zig");
pub const ara_tuning_analysis =
    @import("ara_tuning_analysis.zig");
pub const ara_music_analysis = ara_tuning_analysis;
pub const ara_tempo_warp =
    @import("ara_tempo_warp.zig");
pub const ara_vst3 = @import("ara_vst3.zig");
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
pub const editor_smoke_component = @import("editor_smoke_component.zig");
pub const editor_smoke_controller = @import("editor_smoke_controller.zig");
pub const editor_smoke_plugin = @import("editor_smoke_plugin.zig");
pub const editor_smoke_spec = @import("editor_smoke_spec.zig");
pub const factory = @import("factory.zig");
pub const funknown = @import("funknown.zig");
pub const gain_component = @import("gain_component.zig");
pub const gain_controller = @import("gain_controller.zig");
pub const gain_spec = @import("gain_spec.zig");
pub const gui_telemetry_source = @import("gui_telemetry_source.zig");
pub const gui_note_transport = @import("gui_note_transport.zig");
pub const latency_transport = @import("latency_transport.zig");
pub const host_restart_transport =
    @import("host_restart_transport.zig");
pub const gui_ir_transport = @import("gui_ir_transport.zig");
pub const resource_path_transport = @import("resource_path_transport.zig");
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
pub const version = "0.3.0";
pub const vst_capability_support = @import("vst_capability_support.zig");
pub const vstgui = @import("vstgui.zig");
pub const vstgui_lv2_backend =
    @import("vstgui_lv2_backend.zig");
pub const testing = struct {
    pub const vstgui_headless_host = @import("vstgui_headless_host.zig");
};
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
pub const vst_value = @import("vst_value.zig");
pub const vst_wayland_frame = @import("vst_wayland_frame.zig");
pub const vst_wayland_standalone_frame = @import(
    "vst_wayland_standalone_frame.zig",
);
pub const voice_mix_component = @import("voice_mix_component.zig");
pub const voice_mix_controller = @import("voice_mix_controller.zig");
pub const voice_mix_plugin = @import("voice_mix_plugin.zig");
pub const voice_mix_spec = @import("voice_mix_spec.zig");
pub const zig_vst3_plugin_bridge = @import("zig_vst3_plugin_bridge.zig");
pub const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");
pub const zig_vst3_plugin_runtime_adapter =
    @import("zig_vst3_plugin_runtime_adapter.zig");

pub fn targetName() []const u8 {
    return @tagName(@import("builtin").target.os.tag);
}

test "zig-vst3 module exposes the package version" {
    try std.testing.expectEqualStrings("0.3.0", version);
}

test {
    std.testing.refAllDecls(ara_document_controller);
    std.testing.refAllDecls(ara_content_fades);
    std.testing.refAllDecls(ara_extension);
    std.testing.refAllDecls(ara_factory);
    std.testing.refAllDecls(ara_model);
    std.testing.refAllDecls(ara_playback_renderer);
    std.testing.refAllDecls(ara_registration);
    std.testing.refAllDecls(ara_source_cache);
    std.testing.refAllDecls(ara_spectral_transform);
    std.testing.refAllDecls(ara_tuning_analysis);
    std.testing.refAllDecls(ara_tempo_warp);
    std.testing.refAllDecls(ara_vst3);
    std.testing.refAllDecls(entry);
    std.testing.refAllDecls(bypass_component);
    std.testing.refAllDecls(bypass_controller);
    std.testing.refAllDecls(bypass_plugin);
    std.testing.refAllDecls(bypass_spec);
    std.testing.refAllDecls(event_echo_component);
    std.testing.refAllDecls(event_echo_controller);
    std.testing.refAllDecls(event_echo_plugin);
    std.testing.refAllDecls(event_echo_spec);
    std.testing.refAllDecls(event_monitor_component);
    std.testing.refAllDecls(event_monitor_controller);
    std.testing.refAllDecls(event_monitor_plugin);
    std.testing.refAllDecls(event_monitor_spec);
    std.testing.refAllDecls(editor_smoke_component);
    std.testing.refAllDecls(editor_smoke_controller);
    std.testing.refAllDecls(editor_smoke_plugin);
    std.testing.refAllDecls(editor_smoke_spec);
    std.testing.refAllDecls(factory);
    std.testing.refAllDecls(funknown);
    std.testing.refAllDecls(gain_component);
    std.testing.refAllDecls(gain_controller);
    std.testing.refAllDecls(gain_spec);
    std.testing.refAllDecls(gui_telemetry_source);
    std.testing.refAllDecls(gui_note_transport);
    std.testing.refAllDecls(gui_ir_transport);
    std.testing.refAllDecls(resource_path_transport);
    std.testing.refAllDecls(interface_map);
    std.testing.refAllDecls(mode_gain_component);
    std.testing.refAllDecls(mode_gain_controller);
    std.testing.refAllDecls(mode_gain_plugin);
    std.testing.refAllDecls(mode_gain_spec);
    std.testing.refAllDecls(multi_interface);
    std.testing.refAllDecls(note_gate_component);
    std.testing.refAllDecls(note_gate_controller);
    std.testing.refAllDecls(note_gate_plugin);
    std.testing.refAllDecls(note_gate_spec);
    std.testing.refAllDecls(sine_synth_component);
    std.testing.refAllDecls(sine_synth_controller);
    std.testing.refAllDecls(sine_synth_plugin);
    std.testing.refAllDecls(sine_synth_spec);
    std.testing.refAllDecls(pluginterfaces);
    std.testing.refAllDecls(tuid);
    std.testing.refAllDecls(vst_capability_support);
    std.testing.refAllDecls(vstgui);
    std.testing.refAllDecls(vstgui_lv2_backend);
    std.testing.refAllDecls(testing);
    std.testing.refAllDecls(vst_cloneable);
    std.testing.refAllDecls(vst_component_handler);
    std.testing.refAllDecls(vst_content_scale_support);
    std.testing.refAllDecls(vst_context_menu);
    std.testing.refAllDecls(vst_error_context);
    std.testing.refAllDecls(vst_event_list);
    std.testing.refAllDecls(vst_host_application);
    std.testing.refAllDecls(vst_host_context);
    std.testing.refAllDecls(vst_inter_app_audio);
    std.testing.refAllDecls(vst_linux_run_loop);
    std.testing.refAllDecls(vst_message);
    std.testing.refAllDecls(vst_note_expression);
    std.testing.refAllDecls(vst_parameter_finder);
    std.testing.refAllDecls(vst_unit_data);
    std.testing.refAllDecls(vst_parameter_changes);
    std.testing.refAllDecls(vst_persistent_attributes);
    std.testing.refAllDecls(vst_plug_frame);
    std.testing.refAllDecls(vst_plug_view);
    std.testing.refAllDecls(vst_plugin_compatibility);
    std.testing.refAllDecls(vst_representation);
    std.testing.refAllDecls(vst_string_result);
    std.testing.refAllDecls(vst_stream);
    std.testing.refAllDecls(vst_test_interfaces);
    std.testing.refAllDecls(vst_test_plug_provider);
    std.testing.refAllDecls(vst_update_handler);
    std.testing.refAllDecls(vst_value);
    std.testing.refAllDecls(vst_wayland_frame);
    std.testing.refAllDecls(vst_wayland_standalone_frame);
    std.testing.refAllDecls(voice_mix_component);
    std.testing.refAllDecls(voice_mix_controller);
    std.testing.refAllDecls(voice_mix_plugin);
    std.testing.refAllDecls(voice_mix_spec);
    std.testing.refAllDecls(zig_vst3_plugin_bridge);
    std.testing.refAllDecls(zig_vst3_plugin_effect);
    std.testing.refAllDecls(zig_vst3_plugin_runtime_adapter);
}
