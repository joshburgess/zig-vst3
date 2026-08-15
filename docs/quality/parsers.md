# Parser and Persistent-State Inventory

This ledger is the exhaustive Phase 3 review boundary for production sources
that parse, decode, restore, import, or transport externally supplied data. It
also records lexical false positives so the source set is mechanically closed.
The inventory is not a claim that every family is complete. A family is closed
only when its limits, failure behavior, fuzzing, sanitizer evidence, and any
required independent oracle are recorded in the other quality evidence files.

`scripts/check_parser_inventory.sh` derives candidates from the repository-wide
parser metric and from persistence- and input-oriented filenames. It rejects
missing, stale, duplicate, untracked, and out-of-scope entries. Its negative
fixture proves that omitting either a lexical candidate or a semantic filename
candidate fails the gate.

## Semantic Families

| Family | Input boundary | Limits and failure contract | Evidence and disposition |
| --- | --- | --- | --- |
| P-STATE | Generic parameter state, migration tables, and runtime delegates | The encoded count is 16-bit, migration tables are capped at 256, all migration work is bounded, and publication occurs only after complete validation. | Closed by Q-STATE-001. Native fuzzing, truncation, hostile migration, cross-build, and installed-package evidence are recorded in `verification.md`. |
| P-EDITOR | Typed editor-state envelopes and migrations | The wire header caps entries at 64. Every payload has a fixed maximum, schema declarations are compile-time bounded, and migration tables are capped at 256. Reads validate migrations into fixed storage, decode into a temporary state, and publish only after complete success. | Closed by Q-EDITOR-001. Exact limits, ordering semantics, duplicate rejection, truncation, generated corruption, native fuzzing, cross-compilation, and installed-package evidence are recorded. |
| P-RESOURCE | Resource paths, reference metadata, recovery records, bounded byte accumulation, exchange, and job delegates | Paths and metadata use compile-time capacities, reference records reject oversized lengths before payload reads, and byte accumulation has a caller-selected maximum with checked arithmetic. Exchanges have at most 255 slots. Jobs require positive work and result limits, expose cooperative cancellation and deadlines, and publish only accepted generations. Recovery validates complete state before mutation or worker submission. | Closed by Q-RESOURCE-001. Exact capacities, truncation, malformed direct state, allocation failure, bounded reference-model operations, generated transport commands, native state fuzzing, ThreadSanitizer, cross-compilation, and installed-package evidence are recorded. |
| P-ADAPTER | VST3, LV2, and AUv2 state or host-option adapters | Parameter and editor state delegate to closed bounded families. AUv2 component state has fixed maximum storage. LV2 features and options stop at 256 entries and require terminators, audio blocks cannot exceed the negotiated maximum, UI atoms are bounded before body traversal, and state restoration is staged. VST3 bus arrays are checked against topology capacities, input queues and events stop after 64 visits, data events cap payload bytes, and data-exchange callbacks accept at most 64 blocks. | Closed by Q-ADAPTER-001. Exact-limit, one-over, malformed option, state failure, native host, ABI, cross-target, and installed-package evidence are recorded. |
| P-MIDI | Fixed MIDI packets, UMP byte streams, SysEx assemblers, Standard MIDI Files, and native MIDI delegates | MIDI 1 messages and UMP packets use fixed three-byte and four-word storage. Standard MIDI Files and UMP streams have caller-selected whole-input and item limits plus retained linear traversal witnesses. SysEx7, SysEx8, Mixed Data Set, Flex Data text, and Stream text assemblers use compile-time storage capacities, checked append arithmetic, packet-count limits where the protocol defines them, and failure-atomic updates. Native callbacks accept at most 256 MIDI 1 bytes, 64 UMP words, or the CoreMIDI 16-bit packet length. Scheduler queues hold 256 fixed messages or packets. ALSA drains recheck stop and accept at most 64 reads per poll wake. | Closed by Q-MIDI-001, Q-MIDI-002, and Q-MIDI-003. Exact limits, scaling, two native mutation targets, five-assembler state preservation, native lifecycle, ThreadSanitizer, cross-target, ABI, and installed-package evidence are recorded. |
| P-MIDI-CI | MIDI-CI discovery, profiles, process inquiry, property exchange, JSON, caches, resources, and sessions | Wire lengths and counts use 7-, 14-, or 28-bit protocol fields plus compile-time capacities. Headers reject more than 16,383 bytes before allocation, resource JSON rejects more than 65,535 bytes, sessions and reassembly use fixed storage, and cache restore publishes only a completely validated fixed-capacity replacement. | Closed by Q-MIDI-CI-001. Exact limits, allocation failure, three native fuzz targets, cross-compilation, and installed-package evidence are recorded. |
| P-AUDIO | Ogg/Vorbis, MP3, FLAC, WAV/RF64/Wave64/AIFF, ID3, broadcast metadata, iXML, and XML metadata import | Public default and caller-selected byte, frame, channel, metadata, and XML limits are enforced before publication. Iterators require progress, arithmetic is checked, and decoding uses bounded caller storage or bounded allocation. | Closed by Q-CODEC-001, Q-PARSE-001, Q-IXML-001, Q-MP3-001, Q-OGG-001, Q-AUDIO-001, Q-FLAC-001, and Q-META-001. Fuzz, sanitizer, independent oracle, cross-build, and installed-package evidence are recorded. |
| P-ADM | ADM XML, time forms, document construction, render planning, and bounded render delegates | XML source, document capacities, reference resolution, interpolation, and render work have explicit limits. Validation and construction are transactional. | Closed by Q-ADM-001. Fuzz, sanitizer, independent libear comparison, and installed-package evidence are recorded. |
| P-SOFA | NetCDF SOFA HRTF containers | The public default is 1 GiB with a caller-selected override. The file is checked before NetCDF opens it, dimensions are bounded by fixed capacities, and destination publication is transactional. | Closed by Q-SOFA-001 with two public datasets and independent NetCDF, libmysofa, and libspatialaudio comparisons. |
| P-ARA | ARA host archives, tuning-analysis archives, audio-source caches, transforms, and model delegates | Controller archives use a compile-time buffer derived from model limits. Host filter counts are capped before pointer traversal, strings and extensions are bounded, and the complete envelope is decoded before extension callbacks. Tuning analysis restores into staged fixed-capacity slots and publishes only after all records pass wire, count, range, and finiteness checks. Source caches, renderers, and transforms use fixed capacities and checked ranges. | Closed by Q-ARA-001. Exact limit regressions, two archive fuzz targets, the complete ARA gate, TSan, cross-compilation, and installed-package evidence are recorded. |
| P-CONFIG | Device-selection records and textual VST3 IDs | Device identifiers and names accept at most 128 UTF-8 bytes without allocation. Device-selection records accept exactly one complete versioned record of at most 656 bytes, decode into temporary fixed storage, reject trailing bytes, and publish only after complete validation. VST3 textual IDs accept exactly 32 hexadecimal bytes and decode into 16 fixed bytes without allocation. | Closed by Q-CONFIG-001. Every truncation of a maximum-size record, invalid encodings, exact textual-ID lengths, native execution, and ReleaseSafe Windows compilation pass. Numeric preparation configuration and the bounded standalone event pump are reviewed non-parser inputs. Compatibility JSON is compile-time output. |
| N-OUTPUT | Encoders, writers, writer fault injection, and output I/O adapters | These sources produce data and do not accept a structured untrusted-input format. Short-write and transactional-output evidence remains tracked by the owning review units. | Reviewed exclusion from the parser set. |
| N-TEST | Production-located fixtures or test support selected by lexical heuristics | No shipping untrusted-input entry point. | Reviewed exclusion from the parser set. |
| N-DELEGATE | Export surfaces, GUI transport, import routing, and views that delegate validation to an inventoried family | No independent structured parser. Any external bytes cross an inventoried downstream boundary. | Reviewed delegate. |
| N-NONINPUT | Lexical matches such as state variables, numeric parsing helpers, raw interface declarations, and runtime lifecycle state | No structured untrusted-input parser or persistent-state restore implementation. | Reviewed lexical exclusion. |

## Checked Source Set

The block below is machine-readable. Each line assigns exactly one tracked
candidate to a semantic family or reviewed exclusion.

<!-- parser-inventory-begin -->
```text
P-MIDI zig-vst3-plugin/src/alsa_midi.zig
P-MIDI zig-vst3-plugin/src/alsa_ump.zig
P-MIDI zig-vst3-plugin/src/core_midi.zig
N-DELEGATE zig-vst3-plugin/src/dsp.zig
P-ADM zig-vst3-plugin/src/dsp/adm.zig
P-ADM zig-vst3-plugin/src/dsp/adm_binaural.zig
P-ADM zig-vst3-plugin/src/dsp/adm_direct_speaker_mapping.zig
P-ADM zig-vst3-plugin/src/dsp/adm_hoa_decoder.zig
P-ADM zig-vst3-plugin/src/dsp/adm_hoa_dual_band.zig
P-ADM zig-vst3-plugin/src/dsp/adm_hoa_matrix.zig
P-ADM zig-vst3-plugin/src/dsp/adm_hoa_radial.zig
P-ADM zig-vst3-plugin/src/dsp/adm_render.zig
P-ADM zig-vst3-plugin/src/dsp/adm_sample_time.zig
P-ADM zig-vst3-plugin/src/dsp/adm_time.zig
P-ADM zig-vst3-plugin/src/dsp/adm_xml.zig
N-OUTPUT zig-vst3-plugin/src/dsp/aiff_writer.zig
P-AUDIO zig-vst3-plugin/src/dsp/audio_file_reader.zig
P-AUDIO zig-vst3-plugin/src/dsp/audio_metadata.zig
P-AUDIO zig-vst3-plugin/src/dsp/broadcast_metadata.zig
N-NONINPUT zig-vst3-plugin/src/dsp/denormals.zig
N-NONINPUT zig-vst3-plugin/src/dsp/fft.zig
N-NONINPUT zig-vst3-plugin/src/dsp/file_reader_io.zig
N-OUTPUT zig-vst3-plugin/src/dsp/file_writer_faults.zig
N-OUTPUT zig-vst3-plugin/src/dsp/file_writer_io.zig
N-TEST zig-vst3-plugin/src/dsp/fixture_runner.zig
P-AUDIO zig-vst3-plugin/src/dsp/flac.zig
P-SOFA zig-vst3-plugin/src/dsp/hrtf_sofa.zig
P-AUDIO zig-vst3-plugin/src/dsp/id3.zig
P-AUDIO zig-vst3-plugin/src/dsp/ixml.zig
N-NONINPUT zig-vst3-plugin/src/dsp/kernel_dispatch.zig
P-AUDIO zig-vst3-plugin/src/dsp/mp3.zig
P-AUDIO zig-vst3-plugin/src/dsp/ogg.zig
N-OUTPUT zig-vst3-plugin/src/dsp/pcm_encode.zig
N-OUTPUT zig-vst3-plugin/src/dsp/rf64_writer.zig
N-NONINPUT zig-vst3-plugin/src/dsp/state_variable.zig
N-OUTPUT zig-vst3-plugin/src/dsp/wav_writer.zig
P-AUDIO zig-vst3-plugin/src/dsp/wave64_metadata.zig
N-OUTPUT zig-vst3-plugin/src/dsp/wave64_writer.zig
P-AUDIO zig-vst3-plugin/src/dsp/xml.zig
P-EDITOR zig-vst3-plugin/src/editor_state.zig
N-DELEGATE zig-vst3-plugin/src/gui.zig
P-AUDIO zig-vst3-plugin/src/gui_audio_file_importer.zig
N-DELEGATE zig-vst3-plugin/src/gui_audio_sample_store.zig
N-DELEGATE zig-vst3-plugin/src/gui_file_drop.zig
N-DELEGATE zig-vst3-plugin/src/gui_file_importer.zig
N-DELEGATE zig-vst3-plugin/src/gui_graph.zig
N-NONINPUT zig-vst3-plugin/src/dsp/convolution.zig
N-DELEGATE zig-vst3-plugin/src/gui_ir_editor.zig
N-DELEGATE zig-vst3-plugin/src/gui_preset_browser.zig
N-NONINPUT zig-vst3-plugin/src/hoa_tests.zig
P-ADAPTER zig-vst3-plugin/src/lv2.zig
N-NONINPUT zig-vst3-plugin/src/lv2/abi.zig
N-NONINPUT zig-vst3-plugin/src/lv2/uris.zig
P-ADAPTER zig-vst3-plugin/src/lv2_metadata.zig
P-ADAPTER zig-vst3-plugin/src/lv2_ui.zig
N-NONINPUT zig-vst3-plugin/src/parameters.zig
N-NONINPUT zig-vst3-plugin/src/parameters/access.zig
N-NONINPUT zig-vst3-plugin/src/parameters/common.zig
N-NONINPUT zig-vst3-plugin/src/parameters/descriptors.zig
N-NONINPUT zig-vst3-plugin/src/parameters/set.zig
N-NONINPUT zig-vst3-plugin/src/parameters/smoothing.zig
N-NONINPUT zig-vst3-plugin/src/parameters/value.zig
P-MIDI zig-vst3-plugin/src/plugin/alsa_midi.zig
P-MIDI zig-vst3-plugin/src/plugin/alsa_midi_shim.c
P-MIDI zig-vst3-plugin/src/plugin/alsa_midi_shim.h
P-MIDI zig-vst3-plugin/src/plugin/alsa_ump.zig
P-MIDI zig-vst3-plugin/src/plugin/alsa_ump_shim.c
P-MIDI zig-vst3-plugin/src/plugin/alsa_ump_shim.h
N-NONINPUT zig-vst3-plugin/src/plugin/audio_layout.zig
N-NONINPUT zig-vst3-plugin/src/plugin/config.zig
P-MIDI zig-vst3-plugin/src/plugin/core_midi.zig
P-MIDI zig-vst3-plugin/src/plugin/core_midi_shim.c
P-MIDI zig-vst3-plugin/src/plugin/core_midi_shim.h
P-CONFIG zig-vst3-plugin/src/plugin/device_catalog.zig
P-STATE zig-vst3-plugin/src/plugin/instance.zig
N-NONINPUT zig-vst3-plugin/src/plugin/lifecycle.zig
P-MIDI zig-vst3-plugin/src/plugin/midi_scheduler_queue.h
N-NONINPUT zig-vst3-plugin/src/plugin/pipewire_shim.c
P-STATE zig-vst3-plugin/src/plugin/runtime.zig
N-NONINPUT zig-vst3-plugin/src/plugin/spec.zig
N-NONINPUT zig-vst3-plugin/src/plugin/standalone_shell.zig
N-TEST zig-vst3-plugin/src/plugin/tests.zig
P-MIDI zig-vst3-plugin/src/plugin/ump_scheduler_queue.h
P-MIDI zig-vst3-plugin/src/plugin/win_midi.zig
P-MIDI zig-vst3-plugin/src/plugin/win_midi_shim.c
P-MIDI zig-vst3-plugin/src/plugin/win_midi_shim.h
P-MIDI zig-vst3-plugin/src/plugin/win_ump.zig
P-MIDI zig-vst3-plugin/src/plugin/win_ump_ref_count.hpp
P-MIDI zig-vst3-plugin/src/plugin/win_ump_shim.cpp
P-MIDI zig-vst3-plugin/src/plugin/win_ump_shim.h
P-MIDI zig-vst3-plugin/src/plugin/win_ump_unavailable.c
P-MIDI zig-vst3-plugin/src/process.zig
P-MIDI zig-vst3-plugin/src/process/midi1.zig
P-MIDI zig-vst3-plugin/src/process/midi2.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_device.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_process.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_process_report.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_profile.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_profile_host.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_cache.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_controller_resources.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_host.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_json.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_resources.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_session.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_ci_property_standard_resources.zig
P-MIDI-CI zig-vst3-plugin/src/process/midi_endpoint_session.zig
P-MIDI zig-vst3-plugin/src/process/midi_file.zig
P-MIDI zig-vst3-plugin/src/process/midi_flex.zig
P-MIDI zig-vst3-plugin/src/process/midi_flex_text.zig
P-MIDI zig-vst3-plugin/src/process/midi_mixed_data.zig
P-MIDI zig-vst3-plugin/src/process/midi_rpn.zig
P-MIDI zig-vst3-plugin/src/process/midi_segmented.zig
P-MIDI zig-vst3-plugin/src/process/midi_stream.zig
P-MIDI zig-vst3-plugin/src/process/midi_stream_fuzz.zig
P-MIDI zig-vst3-plugin/src/process/midi_stream_text.zig
P-MIDI zig-vst3-plugin/src/process/midi_sysex7.zig
P-MIDI zig-vst3-plugin/src/process/midi_sysex8.zig
P-MIDI zig-vst3-plugin/src/process/midi_system.zig
P-MIDI zig-vst3-plugin/src/process/midi_ump.zig
P-MIDI zig-vst3-plugin/src/process/midi_ump_bytes.zig
P-MIDI zig-vst3-plugin/src/process/midi_utility.zig
P-MIDI zig-vst3-plugin/src/process/mpe.zig
N-NONINPUT zig-vst3-plugin/src/realtime_audit.zig
P-RESOURCE zig-vst3-plugin/src/resource.zig
P-RESOURCE zig-vst3-plugin/src/resource/byte_accumulator.zig
P-RESOURCE zig-vst3-plugin/src/resource/exchange.zig
P-RESOURCE zig-vst3-plugin/src/resource/job.zig
P-RESOURCE zig-vst3-plugin/src/resource/path.zig
P-RESOURCE zig-vst3-plugin/src/resource/recovery.zig
P-RESOURCE zig-vst3-plugin/src/resource/reference.zig
N-DELEGATE zig-vst3-plugin/src/root.zig
P-STATE zig-vst3-plugin/src/state.zig
P-STATE zig-vst3-plugin/src/state/codec.zig
P-STATE zig-vst3-plugin/src/state/format.zig
P-STATE zig-vst3-plugin/src/state/migrations.zig
P-STATE zig-vst3-plugin/src/state/tests.zig
P-MIDI zig-vst3-plugin/src/win_midi.zig
P-MIDI zig-vst3-plugin/src/win_ump.zig
P-ARA zig-vst3/src/ara_api.zig
P-ARA zig-vst3/src/ara_content_fades.zig
P-ARA zig-vst3/src/ara_document_controller.zig
P-ARA zig-vst3/src/ara_extension.zig
P-ARA zig-vst3/src/ara_factory.zig
P-ARA zig-vst3/src/ara_model.zig
P-ARA zig-vst3/src/ara_playback_renderer.zig
P-ARA zig-vst3/src/ara_registration.zig
P-ARA zig-vst3/src/ara_source_cache.zig
P-ARA zig-vst3/src/ara_spectral_transform.zig
P-ARA zig-vst3/src/ara_tempo_warp.zig
P-ARA zig-vst3/src/ara_tuning_analysis.zig
P-ARA zig-vst3/src/ara_vst3.zig
N-NONINPUT zig-vst3/src/editor_smoke_controller.zig
N-DELEGATE zig-vst3/src/gui_ir_transport.zig
N-DELEGATE zig-vst3/src/gui_note_transport.zig
N-NONINPUT zig-vst3/src/host_restart_transport.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/ivstautomationstate.zig
P-MIDI zig-vst3/src/pluginterfaces/vst/ivstmidicontrollers.zig
P-MIDI zig-vst3/src/pluginterfaces/vst/ivstmidilearn.zig
P-MIDI zig-vst3/src/pluginterfaces/vst/ivstmidimapping2.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/ivstparameterchanges.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/ivstparameterfunctionname.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/ivstremapparamid.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/vstaudioprocessoralgo.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/vstpresetfile.zig
N-NONINPUT zig-vst3/src/pluginterfaces/vst/vstpresetkeys.zig
P-RESOURCE zig-vst3/src/resource_path_transport.zig
P-CONFIG zig-vst3/src/tuid.zig
N-NONINPUT zig-vst3/src/vst_parameter_changes.zig
N-NONINPUT zig-vst3/src/vst_parameter_finder.zig
N-OUTPUT zig-vst3/src/vst_plugin_compatibility.zig
N-DELEGATE zig-vst3/src/vstgui.zig
N-DELEGATE zig-vst3/src/vstgui_editor_view.zig
N-DELEGATE zig-vst3/src/vstgui_lv2_backend.zig
N-DELEGATE zig-vst3/src/vstgui_single_parameter_controller.zig
P-ADAPTER zig-vst3/src/zig_vst3_plugin_bridge.zig
P-ADAPTER zig-vst3/src/zig_vst3_plugin_effect.zig
P-ADAPTER zig-vst3/src/zig_vst3_plugin_runtime_adapter.zig
```
<!-- parser-inventory-end -->
