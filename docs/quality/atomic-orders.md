# Atomic-Order Ledger

This lexical ledger makes changes to explicit Zig atomic orders visible to the
quality gate. The publication and teardown justification for each source family
is recorded in `concurrency.md`. Counts include production and test code and do
not replace semantic review.

`unordered` is limited to resource-exchange generation metadata whose slot
state provides the release-acquire publication edge. `monotonic` is limited to
independent values, statistics, producer- or consumer-owned cursors, and retry
loads whose successful edge has stronger order. Sequentially consistent uses
are test observations, not production synchronization requirements.

| Source | Unordered | Monotonic | Acquire | Release | Acquire-release | Sequentially consistent |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
<!-- atomic-order-counts:start -->
| `examples/fixed_rate_core.zig` | 0 | 0 | 9 | 8 | 1 | 0 |
| `examples/model_shell_core.zig` | 0 | 0 | 8 | 9 | 1 | 0 |
| `examples/resource_swap_core.zig` | 0 | 0 | 5 | 6 | 1 | 0 |
| `zig-vst3-plugin/src/dsp/hrtf.zig` | 0 | 5 | 13 | 12 | 0 | 0 |
| `zig-vst3-plugin/src/dsp/hrtf_stream.zig` | 0 | 8 | 12 | 13 | 0 | 0 |
| `zig-vst3-plugin/src/dsp/realtime_snapshot.zig` | 0 | 5 | 33 | 21 | 5 | 0 |
| `zig-vst3-plugin/src/gui_audio_file_importer.zig` | 0 | 0 | 1 | 0 | 0 | 0 |
| `zig-vst3-plugin/src/gui_audio_sample_store.zig` | 0 | 0 | 11 | 13 | 3 | 0 |
| `zig-vst3-plugin/src/gui_file_importer.zig` | 0 | 0 | 1 | 7 | 0 | 0 |
| `zig-vst3-plugin/src/gui_graph.zig` | 0 | 4 | 9 | 11 | 0 | 0 |
| `zig-vst3-plugin/src/gui_ir_convolution.zig` | 0 | 0 | 19 | 19 | 7 | 0 |
| `zig-vst3-plugin/src/gui_telemetry.zig` | 0 | 5 | 18 | 16 | 3 | 0 |
| `zig-vst3-plugin/src/lv2.zig` | 0 | 0 | 8 | 6 | 5 | 0 |
| `zig-vst3-plugin/src/parameters/value.zig` | 0 | 5 | 0 | 0 | 0 | 0 |
| `zig-vst3-plugin/src/plugin/alsa_midi.zig` | 0 | 3 | 14 | 14 | 1 | 0 |
| `zig-vst3-plugin/src/plugin/alsa_ump.zig` | 0 | 3 | 13 | 13 | 1 | 0 |
| `zig-vst3-plugin/src/plugin/core_audio.zig` | 0 | 5 | 3 | 3 | 0 | 0 |
| `zig-vst3-plugin/src/plugin/core_midi.zig` | 0 | 5 | 16 | 18 | 1 | 0 |
| `zig-vst3-plugin/src/plugin/native_callback_gate.zig` | 0 | 3 | 7 | 4 | 1 | 0 |
| `zig-vst3-plugin/src/plugin/standalone.zig` | 0 | 25 | 23 | 24 | 1 | 0 |
| `zig-vst3-plugin/src/plugin/wasapi.zig` | 0 | 2 | 1 | 1 | 0 | 0 |
| `zig-vst3-plugin/src/plugin/win_midi.zig` | 0 | 3 | 14 | 14 | 1 | 0 |
| `zig-vst3-plugin/src/resource/exchange.zig` | 3 | 0 | 29 | 28 | 12 | 0 |
| `zig-vst3-plugin/src/resource/job.zig` | 0 | 0 | 31 | 39 | 3 | 0 |
| `zig-vst3-plugin/src/resource/recovery.zig` | 0 | 0 | 14 | 15 | 3 | 0 |
| `zig-vst3/src/ara_document_controller.zig` | 0 | 0 | 17 | 10 | 2 | 0 |
| `zig-vst3/src/ara_playback_renderer.zig` | 0 | 2 | 1 | 0 | 0 | 0 |
| `zig-vst3/src/ara_source_cache.zig` | 0 | 4 | 8 | 2 | 0 | 0 |
| `zig-vst3/src/ara_spectral_transform.zig` | 0 | 2 | 4 | 1 | 0 | 0 |
| `zig-vst3/src/factory.zig` | 0 | 3 | 0 | 1 | 0 | 0 |
| `zig-vst3/src/funknown.zig` | 0 | 12 | 4 | 6 | 0 | 0 |
| `zig-vst3/src/gui_note_transport.zig` | 0 | 4 | 1 | 1 | 0 | 0 |
| `zig-vst3/src/vst_capability_support.zig` | 0 | 0 | 0 | 0 | 0 | 5 |
| `zig-vst3/src/vst_cloneable.zig` | 0 | 0 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_content_scale_support.zig` | 0 | 0 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_context_menu.zig` | 0 | 13 | 1 | 0 | 0 | 0 |
| `zig-vst3/src/vst_error_context.zig` | 0 | 0 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_event_list.zig` | 0 | 0 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_inter_app_audio.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_linux_run_loop.zig` | 0 | 13 | 0 | 0 | 0 | 3 |
| `zig-vst3/src/vst_note_expression.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_parameter_changes.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_parameter_finder.zig` | 0 | 0 | 0 | 0 | 0 | 3 |
| `zig-vst3/src/vst_persistent_attributes.zig` | 0 | 0 | 0 | 0 | 0 | 3 |
| `zig-vst3/src/vst_plug_frame.zig` | 0 | 0 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_plug_view.zig` | 0 | 0 | 1 | 0 | 0 | 1 |
| `zig-vst3/src/vst_plugin_compatibility.zig` | 0 | 3 | 0 | 1 | 0 | 1 |
| `zig-vst3/src/vst_stream.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_string_result.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_test_interfaces.zig` | 0 | 9 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_test_plug_provider.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_unit_data.zig` | 0 | 0 | 0 | 0 | 0 | 3 |
| `zig-vst3/src/vst_update_handler.zig` | 0 | 6 | 0 | 0 | 0 | 1 |
| `zig-vst3/src/vst_wayland_frame.zig` | 0 | 0 | 0 | 0 | 0 | 2 |
| `zig-vst3/src/vst_wayland_standalone_frame.zig` | 0 | 0 | 1 | 0 | 0 | 0 |
| `zig-vst3/src/vstgui_headless_host.zig` | 0 | 0 | 4 | 7 | 0 | 0 |
| `zig-vst3/src/zig_vst3_plugin_effect.zig` | 0 | 0 | 2 | 3 | 1 | 0 |
<!-- atomic-order-counts:end -->
