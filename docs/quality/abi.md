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
| A-VSTGUI-RAW | Raw VSTGUI and Wayland host bridges | Pinned declarations, interface identity, native-handle behavior, attach-detach and callback teardown |
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
Q01	zig-vst3/src/bypass_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/bypass_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/editor_smoke_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/editor_smoke_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/effect_support.zig	REVIEW	A-VST3
Q01	zig-vst3/src/entry.zig	REVIEW	A-VST3
Q01	zig-vst3/src/event_echo_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/event_echo_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/event_monitor_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/event_monitor_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/factory.zig	REVIEW	A-VST3
Q01	zig-vst3/src/fixed_string.zig	REVIEW	A-VST3
Q01	zig-vst3/src/funknown.zig	REVIEW	A-VST3
Q01	zig-vst3/src/gain_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/gain_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/gui_ir_transport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/gui_note_transport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/gui_telemetry_source.zig	REVIEW	A-VST3
Q01	zig-vst3/src/host_restart_transport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/interface_map.zig	REVIEW	A-VST3
Q01	zig-vst3/src/latency_transport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/mode_gain_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/mode_gain_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/multi_interface.zig	REVIEW	A-VST3
Q01	zig-vst3/src/note_gate_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/note_gate_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/funknown.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/fvariant.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ibstream.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/icloneable.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ierrorcontext.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ipersistent.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/ipluginbase.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/iplugincompatibility.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/istringresult.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/iupdatehandler.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/root.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/base/types.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iplugview.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iplugviewcontentscalesupport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/iwaylandframe.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/gui/root.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/test/itest.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/test/root.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstattributes.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstaudioprocessor.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstautomationstate.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstchannelcontextinfo.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstcomponent.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstcontextmenu.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstdataexchange.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsteditcontroller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstevents.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsthostapplication.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstinterappaudio.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmessage.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidicontrollers.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidilearn.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstmidimapping2.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstnoteexpression.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstparameterchanges.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstparameterfunctionname.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstphysicalui.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstpluginterfacesupport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstplugview.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstprefetchablesupport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstprocesscontext.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstremapparamid.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstrepresentation.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivsttestplugprovider.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/ivstunits.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/root.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstaudioprocessoralgo.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstbypassprocessor.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vsteventshelper.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstpresetfile.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstpresetkeys.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vstspeaker.zig	REVIEW	A-VST3
Q01	zig-vst3/src/pluginterfaces/vst/vsttypes.zig	REVIEW	A-VST3
Q01	zig-vst3/src/resource_path_transport.zig	REVIEW	A-VST3
Q01	zig-vst3/src/root.zig	REVIEW	A-VST3
Q01	zig-vst3/src/sine_synth_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/sine_synth_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/string128.zig	REVIEW	A-VST3
Q01	zig-vst3/src/tuid.zig	REVIEW	A-VST3
Q01	zig-vst3/src/voice_mix_component.zig	REVIEW	A-VST3
Q01	zig-vst3/src/voice_mix_controller.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_capability_support.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_cloneable.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_component_handler.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_content_scale_support.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_context_menu.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_error_context.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_event_list.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_host_application.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_host_context.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_index.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_inter_app_audio.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_linux_run_loop.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_message.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_note_expression.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_parameter_changes.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_parameter_finder.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_persistent_attributes.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_plug_frame.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_plug_view.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_plugin_compatibility.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_representation.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_stream.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_string_result.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_test_interfaces.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_test_plug_provider.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_unit_data.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_update_handler.zig	REVIEW	A-VST3
Q01	zig-vst3/src/vst_value.zig	REVIEW	A-VST3
Q01	zig-vst3/src/zig_vst3_edit_controller.zig	REVIEW	A-VST3
Q02	vendor/ARA_API/ARAInterface.h	REVIEW	A-ARA
Q02	vendor/ARA_API/ARAVST3.h	REVIEW	A-ARA
Q02	zig-vst3/src/ara_analysis_common.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_analysis_model.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_api.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_content_fades.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_document_controller.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_extension.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_factory.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_harmony_analysis.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_model.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_note_analysis.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_playback_renderer.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_registration.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_source_cache.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_spectral_transform.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_tempo_analysis.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_tempo_warp.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_tuning_analysis.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_tuning_detector.zig	REVIEW	A-ARA
Q02	zig-vst3/src/ara_vst3.zig	REVIEW	A-ARA
Q03	zig-vst3/src/vst_wayland_frame.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vst_wayland_standalone_frame.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_editor_view.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_headless_host.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_lv2_backend.zig	REVIEW	A-VSTGUI-RAW
Q03	zig-vst3/src/vstgui_single_parameter_controller.zig	REVIEW	A-VSTGUI-RAW
Q04	zig-vst3/src/zig_vst3_plugin_bridge.zig	REVIEW	A-VST3-FRAMEWORK
Q04	zig-vst3/src/zig_vst3_plugin_effect.zig	REVIEW	A-VST3-FRAMEWORK
Q04	zig-vst3/src/zig_vst3_plugin_runtime_adapter.zig	REVIEW	A-VST3-FRAMEWORK
Q06	zig-vst3-plugin/src/common.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/core.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/audio_layout.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/common.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/config.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/host_requests.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/instance.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/lifecycle.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/offline_renderer.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/runtime.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/spec.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/plugin/tests.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/realtime_audit.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/root.zig	REVIEW	A-RUNTIME
Q06	zig-vst3-plugin/src/serial_generation.zig	REVIEW	A-RUNTIME
Q17	zig-vst3-plugin/src/audio_unit.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2/abi.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/audio_unit_v2_class_info.c	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2/abi.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2/uris.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2_metadata.zig	REVIEW	A-PLUGIN-ABI
Q17	zig-vst3-plugin/src/lv2_ui.zig	REVIEW	A-PLUGIN-ABI
Q18	zig-vst3-plugin/src/alsa.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/alsa_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/alsa_ump.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/cocoa_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/core_audio.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/core_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/pipewire.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_midi_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/alsa_ump_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/cocoa_window_shim.m	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_audio_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/core_midi_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/device_catalog.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/midi_scheduler_queue.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/native_callback_gate.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/pipewire_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone/capture.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone/common.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/standalone_shell.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/ump_scheduler_queue.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wasapi_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/wayland_window_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_midi_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_ref_count.hpp	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_shim.cpp	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_ump_unavailable.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/win_window_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window_shim.c	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/plugin/x11_window_shim.h	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/wasapi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/wayland_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/win_midi.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/win_ump.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/win_window.zig	REVIEW	A-NATIVE
Q18	zig-vst3-plugin/src/x11_window.zig	REVIEW	A-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi_bridge_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_atspi_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_bridge.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_bridge.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_clipboard.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_linux_clipboard.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_linux_clipboard_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_macos.mm	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_macos_tests.mm	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard.c	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_clipboard_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_wayland_fake.c	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_accessibility_windows.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_button.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_button.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_menu.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_action_menu.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_adapter_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_assets.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_assets.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_component.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_component.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_controls.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_controls.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_drawing.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_drawing.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_editor.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_editor.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_file_drop.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_file_drop.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_fonts.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_fonts.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_graphs.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_graphs.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_layout.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_layout.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_meters.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_meters.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_no_process_file_selector.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_piano.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_piano.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_platform_macos.mm	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_preset_browser.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_preset_browser.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_range_selection.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_range_selection.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_step_sequencer.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_step_sequencer.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_text_progress.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_text_progress.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_theme.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_theme.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_viewport.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_viewport.h	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_visual_tests.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_windows_crt.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_xy_pad.cpp	REVIEW	A-VSTGUI-NATIVE
Q19	gui-adapters/vstgui/zig_vstgui_xy_pad.h	REVIEW	A-VSTGUI-NATIVE
<!-- abi-files:end -->

## Active A-VST3 Evidence

The raw declaration and interoperability matrix is accepted as one part of
the A-VST3 review. It does not yet disposition implementation sources.

| Boundary | Declaration source | Automated evidence | Result |
| --- | --- | --- | --- |
| VST3 base, GUI, test, and VST interfaces | Pinned Steinberg VST3 SDK `v3.8.0_build_66` at `9fad9770f2ae8542ab1a548a68c1ad1ac690abe0`, with the exact interface and IID ledger in `docs/interface-inventory.md` | 32 SDK-backed constant, IID, struct, vtable, helper, and calling-convention comparators | Passed in the bounded raw ABI matrix |
| ARA companion declarations used by VST3 | Vendored `ARAInterface.h` and `ARAVST3.h` | Translated-header and native C++ layout comparison | Passed in the bounded raw ABI matrix |
| `FUnknown` and shared controlling identity | Steinberg `FUnknown`, the Zig `funknown.zig` implementation, and `multi_interface.zig` | Native C harness, native C++ harness, pinned-SDK C++ harness, saturated-reference regressions, and aggregate TSan reference-count coverage | Passed |
| Plugin module entry symbols | Steinberg platform entry contracts and `entry.zig` | Symbol inspection across every configured example and C-kernel product | Passed in the bounded raw ABI matrix |
| ABI verifier cache ownership | Build graph cache roots and all 33 ABI scripts | Checked routing fixture plus a complete matrix using explicit temporary local and global caches | Passed; Q-VER-014 is closed |

The complete matrix at `af412dda` passed 135/135 build steps with one job.
Every script-generated ABI directory appeared beneath the supplied temporary
local cache. The initial restricted run separately proved all 33 script
comparators passed, but its top-level `translate-c` step was denied by the
execution sandbox. The accepted complete result is the rerun with that cache
access available. No repository cache is treated as evidence.

## Current Disposition

The initial ledger contains 301 `REVIEW` records. Review proceeds by boundary
family, replacing each record with accepted evidence or a precise exclusion.
Phase 6 remains open until no `REVIEW` record remains, every boundary has a
declaration source and the strongest technically possible automated check,
every skip is explicit, and no critical or high platform or ABI finding is
open.
