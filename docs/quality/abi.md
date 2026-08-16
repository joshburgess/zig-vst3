# Platform and ABI Review

This ledger is the checked Phase 6 source scope for Q01, Q02, Q03, Q04, Q06,
Q17, Q18, and Q19. The inventory script requires one record for every source
assigned to those platform-facing review units and rejects missing, stale,
duplicate, malformed, or misassigned records.

States have narrow meanings:

- `EVIDENCE`: declarations, layouts, calling conventions, lifetimes, failure
  translation, reentrancy, and teardown have accepted Phase 6 evidence.
- `REVIEW`: the source still needs Phase 6 inspection.
- `EXCLUDED`: the source contains no foreign boundary after inspection. The
  final field records the exclusion reason.

An `EVIDENCE` record does not by itself close a boundary family. Each family
must identify its declaration source and strongest technically possible layout
or behavior check. Reference counting and callback teardown also require
adversarial lifecycle evidence.

## Boundary Families

| ID | Scope | Required evidence |
| --- | --- | --- |
| A-VST3 | Raw VST3 and COM mirrors, helpers, and host interfaces | Pinned SDK declarations, layout and vtable parity, calling convention, reference lifetime, callback behavior, validators |
| A-ARA | ARA declarations and integration | Pinned ARA headers, translated-layout parity, VST3 binding behavior, reference and callback lifecycle |
| A-VSTGUI-RAW | Raw VSTGUI and Wayland host bridges | Translated C-header parity, interface identity, native-handle behavior, attach-detach and callback teardown |
| A-VST3-FRAMEWORK | Framework component, controller, and bridge exports | Factory and interface behavior, reference saturation, reentrancy, failure translation, process and teardown lifecycle |
| A-RUNTIME | Plugin runtime and dynamic-library boundaries | Symbol and entry-point contracts, loader ownership, error translation, unload ordering |
| A-PLUGIN-ABI | LV2 and Audio Unit v2 adapters | Published C and Objective-C declarations, layout and constant parity, dynamic host behavior, state, worker, render, and teardown lifecycle |
| A-NATIVE | System audio, MIDI, windows, schedulers, and native shims | Platform declarations, C or C++ shim parity, callback admission and drain, handle ownership, failure and teardown behavior |
| A-VSTGUI-NATIVE | VSTGUI C++ adapter and native UI integrations | C bridge declarations, C++ ownership, accessibility and platform callbacks, sanitizer lifecycle, visual and unavailable-platform accounting |

## Checked Source Inventory

The records are tab-separated so the checker can compare exact paths without
interpreting prose or Markdown tables. Initial `REVIEW` records establish
scope. They do not assert that prior broad test coverage is sufficient.

<!-- abi-files:start -->
Q01	zig-vst3/src/bypass_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/bypass_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/editor_smoke_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/editor_smoke_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/effect_support.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/entry.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/event_echo_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/event_echo_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/event_monitor_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/event_monitor_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/factory.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/fixed_string.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/funknown.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/gain_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/gain_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/gui_ir_transport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/gui_note_transport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/gui_telemetry_source.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/host_restart_transport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/interface_map.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/latency_transport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/mode_gain_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/mode_gain_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/multi_interface.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/note_gate_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/note_gate_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/funknown.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/fvariant.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ibstream.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/icloneable.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ierrorcontext.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ipersistent.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ipluginbase.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/iplugincompatibility.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/istringresult.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/iupdatehandler.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/root.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/types.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iplugview.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iplugviewcontentscalesupport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iwaylandframe.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/root.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/test/itest.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/test/root.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstattributes.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstaudioprocessor.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstautomationstate.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstchannelcontextinfo.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstcomponent.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstcontextmenu.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstdataexchange.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsteditcontroller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstevents.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsthostapplication.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstinterappaudio.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmessage.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidicontrollers.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidilearn.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidimapping2.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstnoteexpression.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstparameterchanges.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstparameterfunctionname.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstphysicalui.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstpluginterfacesupport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstplugview.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstprefetchablesupport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstprocesscontext.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstremapparamid.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstrepresentation.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsttestplugprovider.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstunits.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/root.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstaudioprocessoralgo.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstbypassprocessor.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vsteventshelper.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstpresetfile.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstpresetkeys.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstspeaker.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vsttypes.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/resource_path_transport.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/root.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/sine_synth_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/sine_synth_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/string128.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/tuid.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/voice_mix_component.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/voice_mix_controller.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_capability_support.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_cloneable.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_component_handler.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_content_scale_support.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_context_menu.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_error_context.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_event_list.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_host_application.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_host_context.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_index.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_inter_app_audio.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_linux_run_loop.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_message.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_note_expression.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_parameter_changes.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_parameter_finder.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_persistent_attributes.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_plug_frame.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_plug_view.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_plugin_compatibility.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_representation.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_stream.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_string_result.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_test_interfaces.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_test_plug_provider.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_unit_data.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_update_handler.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/vst_value.zig	EVIDENCE	A-VST3
Q01	zig-vst3/src/zig_vst3_edit_controller.zig	EVIDENCE	A-VST3
Q02	vendor/ARA_API/ARAInterface.h	EVIDENCE	A-ARA
Q02	vendor/ARA_API/ARAVST3.h	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_analysis_common.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_analysis_model.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_api.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_content_fades.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_document_controller.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_extension.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_factory.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_harmony_analysis.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_model.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_note_analysis.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_playback_renderer.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_registration.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_source_cache.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_spectral_transform.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_tempo_analysis.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_tempo_warp.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_tuning_analysis.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_tuning_detector.zig	EVIDENCE	A-ARA
Q02	zig-vst3/src/ara_vst3.zig	EVIDENCE	A-ARA
Q03	zig-vst3/src/vst_wayland_frame.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vst_wayland_standalone_frame.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_editor_view.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_headless_host.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_lv2_backend.zig	EVIDENCE	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_single_parameter_controller.zig	EVIDENCE	A-VSTGUI-RAW
Q04	zig-vst3/src/zig_vst3_plugin_bridge.zig	EVIDENCE	A-VST3-FRAMEWORK
Q04	zig-vst3/src/zig_vst3_plugin_effect.zig	EVIDENCE	A-VST3-FRAMEWORK
Q04	zig-vst3/src/zig_vst3_plugin_runtime_adapter.zig	EVIDENCE	A-VST3-FRAMEWORK
Q06	zig-vst3-plugin/src/common.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/core.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/audio_layout.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/common.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/config.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/host_requests.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/instance.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/lifecycle.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/offline_renderer.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/runtime.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/spec.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/tests.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/realtime_audit.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/root.zig	EVIDENCE	A-RUNTIME
Q06	zig-vst3-plugin/src/serial_generation.zig	EVIDENCE	A-RUNTIME
Q17	zig-vst3-plugin/src/audio_unit.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2/abi.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2_class_info.c	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2/abi.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2/uris.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2_metadata.zig	EVIDENCE	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2_ui.zig	EVIDENCE	A-PLUGIN-ABI
Q18	zig-vst3-plugin/src/alsa.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/alsa_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/alsa_ump.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/cocoa_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/core_audio.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/core_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/pipewire.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window_shim.m	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/device_catalog.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/midi_scheduler_queue.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/native_callback_gate.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone/capture.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone/common.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone_shell.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/ump_scheduler_queue.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_ref_count.hpp	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_shim.cpp	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_unavailable.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window_shim.c	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window_shim.h	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/wasapi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/wayland_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/win_midi.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/win_ump.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/win_window.zig	EVIDENCE	A-NATIVE
Q18	zig-vst3-plugin/src/x11_window.zig	EVIDENCE	A-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi_bridge_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_bridge.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_bridge.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_clipboard.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_linux_clipboard.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_linux_clipboard_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_macos.mm	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_macos_tests.mm	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard.c	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_fake.c	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_windows.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_button.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_button.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_menu.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_menu.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_assets.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_assets.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_component.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_component.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_controls.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_controls.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_drawing.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_drawing.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_editor.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_editor.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_file_drop.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_file_drop.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_fonts.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_fonts.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_graphs.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_graphs.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_layout.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_layout.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_meters.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_meters.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_no_process_file_selector.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_piano.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_piano.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform_macos.mm	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_preset_browser.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_preset_browser.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_range_selection.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_range_selection.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_step_sequencer.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_step_sequencer.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_text_progress.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_text_progress.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_theme.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_theme.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_viewport.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_viewport.h	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_visual_tests.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_windows_crt.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_xy_pad.cpp	EVIDENCE	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_xy_pad.h	EVIDENCE	A-VSTGUI-NATIVE
<!-- abi-files:end -->

## Accepted A-VST3 Evidence

The raw declaration and interoperability matrix, implementation lifecycle
suite, and native validator results complete the automated A-VST3 review.

| Boundary | Declaration source | Automated evidence | Result |
| --- | --- | --- | --- |
| VST3 base, GUI, test, and VST interfaces | Pinned Steinberg VST3 SDK `v3.8.0_build_66` at `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`, with the exact interface and IID ledger in `docs/interface-inventory.md` | 32 SDK-backed constant, IID, struct, vtable, helper, and calling-convention comparators | Passed in the bounded raw ABI matrix |
| ARA companion declarations used by VST3 | Vendored `ARAInterface.h` and `ARAVST3.h` | Translated-header and native C++ layout comparison | Passed in the bounded raw ABI matrix |
| `FUnknown` and shared controlling identity | Steinberg `FUnknown`, the Zig `funknown.zig` implementation, and `multi_interface.zig` | Native C harness, native C++ harness, pinned-SDK C++ harness, saturated-reference regressions, and aggregate TSan reference-count coverage | Passed |
| Plugin module entry symbols | Steinberg platform entry contracts and `entry.zig` | Symbol inspection across every configured example and C-kernel product | Passed in the bounded raw ABI matrix |
| ABI verifier cache ownership | Build graph cache roots and all 33 ABI scripts | Checked routing fixture plus a complete matrix using explicit temporary local and global caches | Passed; Q-VER-014 is closed |
| Q01 implementation behavior | Repository implementations against the pinned raw interfaces | 565 colocated tests across 116 Q01 sources, including factory identity, reference saturation, callback reentrancy, host output initialization, state transitions, connection replacement, teardown, and concurrent headless-host lifecycle | Passed in Debug and ReleaseSafe: 800/800 module tests in each mode |
| Native host validation | Steinberg validator built from the pinned SDK | All 23 native example bundles, including effects, instruments, event processors, editor protocols, ARA, model-shell, and C-kernel products | Passed with 23/23 successful per-bundle verdicts after Q-VER-015 was fixed |

The complete matrix at `af412dda` passed 135/135 build steps with one job.
Every script-generated ABI directory appeared beneath the supplied temporary
local cache. The initial restricted run separately proved all 33 script
comparators passed, but its top-level `translate-c` step was denied by the
execution sandbox. The accepted complete result is the rerun with that cache
access available. No repository cache is treated as evidence.

The Q01 implementation review covers 53 raw declaration and aggregation files
and 63 implementation files. Raw files are accepted through the pinned SDK
comparators, native harnesses, and aggregate compilation. Implementation files
are accepted through their colocated behavior tests, the adversarial ownership
and concurrency evidence retained from Phases 1 and 2, entry-symbol inspection,
and current native validator results. Direct tests added in `2fbdebfa` close the
remaining shared-helper gap by checking successful and failed interface queries,
balanced optional release, retain-before-release peer replacement, mismatched
disconnect behavior, and reset of host-visible failure outputs.

The first fresh validator attempt was not accepted because Q-VER-015 allowed
validation to race its tool build. Commit `b16bb585` adds the required graph
edge. From a deleted SDK build directory, the exact combined command then built
the validator before every example check and produced 23 successful verdict
artifacts with no failure classification. Actual DAW embedding, visual editor
inspection, and host-specific callback traces remain external checks. They are
not inferred from the validator.

## Accepted A-ARA Evidence

The ARA boundary is pinned to the official ARA SDK 2.3.001 declaration subset.
`ARAInterface.h` is translated for each target during the build; x86 targets
also run the checked packing adjustment required by the header's ABI policy.
The handwritten VST3 companion is compared directly with `ARAVST3.h` and the
pinned Steinberg declarations.

| Boundary | Declaration source | Automated evidence | Result |
| --- | --- | --- | --- |
| ARA C API | Vendored official `ARAInterface.h` from ARA SDK 2.3.001 | Target-specific `translate-c`, generation and configuration validation, full native compilation, and ReleaseSafe AArch64 Linux, x86-64 Linux, and x86-64 Windows compilation | Passed |
| ARA VST3 companion | Vendored `ARAVST3.h` plus pinned Steinberg VST3 SDK declarations | Native C++ and Zig size, alignment, IID, vtable-slot, selected offset, role, and generation comparison | Passed |
| Factory, controller, model, and extension lifecycle | Official ARA factory, host-instance, controller-instance, and extension declarations | Bounded pool exhaustion, rollback and reuse, static identity, graph lifecycle through C callbacks, reentrant observer mutation, role-specific and legacy binding, and teardown tests | Passed in Debug and ReleaseSafe |
| Host reader and publication concurrency | Official host audio-reader callback table and repository cache, renderer, and transform contracts | Missing-callback rejection, indivisible close and lease admission, synchronous drain, immutable generation publication, coherent-reader stress, and current TSan selection | Passed; Q-MEM-010 and Q-CONC-005 remain closed |
| Archives and callback input | Official archive, filter, content-reader, analysis-request, and notification declarations | Capacity-before-pointer-traversal tests, failure-atomic round trips, staged publication, exact one-over limits, current controller and analysis archive fuzzing, content-provider behavior, and host notification routing | Passed; Q-ARA-001 remains closed |
| Cached and analyzed playback behavior | Official source, modification, playback-region, content, renderer, and analysis declarations | Transactional f32 and f64 caches, paged eviction, linear, cubic, and sinc playback, fades, tempo maps, spectral publication, tuning, tempo, harmony, and polyphonic-note behavior | Passed in native tests and cross-target compilation |

The 19 Zig sources contain 89 direct test blocks. Their current aggregate ARA
gate executes 445 tests because imported API and shared behavior tests are also
selected. The current Debug ARA gate plus Phase 2 sanitizer selection passed
87/87 steps and 463/463 tests. Native ReleaseSafe separately passed 77/77 steps
and 445/445 tests. An actual ARA-capable DAW, host-owned media, and host-specific
callback traces remain external checks. The ARA playback example's Steinberg
validator result does not substitute for those checks.

## Current Disposition

The ledger contains 137 `EVIDENCE` and 164 `REVIEW` records. All Q01 and Q02
sources are accepted. Review proceeds through the remaining boundary families,
replacing each record with accepted evidence or a precise exclusion. Phase 6
remains open until no `REVIEW` record remains, every boundary has a declaration
source and the strongest technically possible automated check, every skip is
explicit, and no critical or high platform or ABI finding is open.
