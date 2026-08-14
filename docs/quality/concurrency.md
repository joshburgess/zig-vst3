# Concurrency and Realtime Inventory

This record maps cross-thread ownership, publication, synchronization, and
teardown contracts. `scripts/check_quality_concurrency_inventory.sh` keeps the
lexical source appendix synchronized with tracked code. Lexical classification
finds review candidates; it does not prove that unlisted code is thread-safe or
that every listed file contains production concurrency.

## Memory-Order Rules

- A release publication makes complete non-atomic payload writes visible to an
  acquire observation of the same atomic value or its release sequence.
- An acquire-release transition is used when one operation both consumes a
  prior publication and publishes a new ownership or lifecycle state.
- Monotonic operations are limited to independent scalar values, statistics,
  retry loops whose successful edge has stronger order, and reference-count
  increments that do not publish object contents.
- Release reference-count decrements publish prior object use. The thread that
  observes zero performs an acquire observation before destruction.
- Explicit Zig sequentially consistent loads occur only in tests that inspect
  counters. Native libraries may use their default stronger atomic order, but
  repository algorithms do not rely on a global sequentially consistent order.
- Mutex-protected fields are read and written only while holding the same
  mutex. Atomics beside a mutex exist for lock-free admission, cancellation, or
  fast status checks, not as a substitute for protecting the remaining fields.

## Publication Contracts

| Family and source | Cross-thread value | Writer and readers | Publication and ordering | Teardown and realtime contract |
| --- | --- | --- | --- | --- |
| COM and VST3 reference counts in `zig-vst3/src/funknown.zig`, `factory.zig`, `ara_vst3.zig`, `vst_*.zig`, and `zig_vst3_plugin_effect.zig` | Object lifetime count | Any interface holder increments or decrements; the last releaser destroys | Monotonic increment changes only lifetime count. Release decrement publishes prior use; an acquire observation at zero precedes destruction. A saturated count is a permanent pinned sentinel because further references cannot be represented. Static interface counters never own dynamic storage. | Callers must hold a reference across concurrent use. Final release cannot overlap an uncounted borrow. Saturation deliberately leaks rather than permitting premature destruction. No allocation or blocking occurs in add or release before the final destructor. |
| Parameter scalars in `parameters/value.zig` and Fixed Rate state | One independent normalized value, desired mode, requested mode, or latency | Host or control callbacks write; processing reads | Single-word monotonic parameter access is atomic but intentionally establishes no relationship with other fields. Fixed Rate uses release stores and acquire loads where a mode change accompanies latency publication. | Each value is independently coherent. Multi-field transitions occur through lifecycle callbacks or block-boundary adoption, not by assuming a composite scalar snapshot. |
| SPSC telemetry, MIDI, HRTF, graph, and capture queues | Fixed slots plus producer and consumer indices | One producer owns the write index and slot writes; one consumer owns the read index and slot reads | Producer writes payload, then release-publishes the write index. Consumer acquire-loads it before reading. Consumer release-publishes reclaimed capacity through the read index; producer acquire-loads it. Dropped counters are monotonic statistics only. | No reclamation occurs while either endpoint can run. Queue operations are bounded, allocate nothing, and never wait. Teardown stops the producer before endpoint storage is released. |
| `gui_note_transport.zig` | Per-pitch packed note payload and sequence | GUI producer updates a pitch slot; process consumer drains it | One `u64` CAS release-publishes the complete packed payload. The consumer acquire-loads or exchanges the slot before decoding, so fields cannot tear. | Every call touches at most one fixed slot. Destruction starts only after GUI publication and processing stop. |
| DSP snapshots and generation publishers in `dsp/realtime_snapshot.zig`, `gui_audio_sample_store.zig`, `gui_ir_convolution.zig`, ARA source cache, and spectral transform | Immutable slot payload, active slot, reader or reference count, and generation | Control or worker writer publishes; one or more realtime readers acquire and release leases | Payload is completed before release publication of slot or generation. Reader admission uses acquire or acquire-release operations. Reader release publishes completion; writers acquire that release before reuse. Serial generation comparison rejects stale and ambiguous identities. | Writers never mutate an acquired slot. Reuse waits only on non-realtime writers or returns busy; realtime acquisition is bounded by configured slot count and never blocks. Teardown closes publication, drains readers, then frees slot storage. |
| Resource exchange, job, and recovery | Prepared pointers, queue status, generations, cancellation, completion, and active resource | Worker prepares and publishes; control thread submits, polls, and reclaims; process thread adopts and reads | Exchange slot states and generations use release publication and acquire adoption. Job and recovery compound state is protected by their mutexes; atomic generations and cancellation flags let workers detect replacement without taking a control mutex. | Only exchange adoption, active access, and block-boundary retirement are realtime. Public control APIs reject instrumented realtime scopes before locks, joins, allocation, file access, callbacks, or state mutation. Teardown cancels and joins the worker before reclaiming resources. |
| VST3 component connection, topology, and pending host changes in `zig_vst3_plugin_effect.zig` | Borrowed peer, immutable topology snapshot, and pending restart bits | Host lifecycle and control callbacks write; processing reads topology; control thread dispatches pending work | Connection and topology compound state use separate mutexes. Completed topology is release-published and acquire-read. Pending bits are atomically coalesced and restored on failed dispatch. | Realtime paths read only the published topology. Public topology mutation and host dispatch reject instrumented realtime scopes before locking or invoking the host. Disconnect removes the peer before component release. |
| Native callback admission in `plugin/native_callback_gate.zig`, CoreAudio, CoreMIDI, ALSA MIDI, Windows MIDI, and UMP adapters | Closed bit plus admitted callback count; callback-visible pointers and parser state | Control thread opens or closes; foreign callback threads acquire and release admission | Opening initializes callback-visible state before release publication. Admission acquires it while incrementing the same atomic word. Closure and admission share one modification order. Callback release is a release operation; the drain acquire-observes zero. | Stop or unregister the platform source, close admission, drain admitted callbacks, then clear pointers and state. Foreign platform contracts must also prevent callbacks after unregister returns. Callback bodies are bounded and do not allocate or lock. |
| Standalone device queues and statistics | Audio or MIDI queue slots, indices, running state, and cumulative counters | Device callbacks produce or consume; engine thread owns the opposite endpoint; control thread starts and stops | Queue indices follow the SPSC release/acquire contract. Running and stop state release-publish callback-visible configuration. Statistics are independent monotonic or saturating counters. | Stop closes callback admission and joins owned threads before queue or callback storage is cleared. Realtime queue operations do not block. Device discovery and reconfiguration remain control-thread work. |
| ARA reader leases and renderer counters | Reader slot, closed bit, active lease count, immutable cache or transform generation, and failure statistics | Host control callbacks open and close; render or analysis threads acquire; cache writers publish generations | Reader closure and lease admission use one atomic word. Open release-publishes the host reader. Successful admission acquires it. Lease release synchronizes with the control-thread drain. Cache and transform slots use immutable release/acquire publication. Renderer failure counts are monotonic statistics. | Close prevents new leases, drains existing leases, then destroys the host reader. Render paths use bounded cache and transform reads and do not take control mutexes. |
| Model Shell and Resource Swap examples | Host configuration, approved or running generation, prepared runtime pointer, latency, and host-request address | Lifecycle callbacks and workers publish; process thread adopts and reads | Host configuration and generation changes are release-published and acquire-read. Prepared objects cross through the resource exchange contract. The host-request address is cleared before its owner can be released. | Requests and preparation are control-thread work. Processing only adopts approved generations and uses immutable prepared state. Teardown joins preparation before destroying the stable engine. |
| VSTGUI runtime and parameter bridge | Global runtime count, pending parameter values and dirty flags, editor registry, and Windows accessibility references | Host parameter callbacks produce; UI thread consumes; editor creation and destruction mutate global runtime state | One mutex serializes global VSTGUI initialization, exit, and editor registry changes. Parameter value storage precedes release publication of its dirty flag; the UI acquire-observes dirty before reading the value. Windows native objects use atomic COM references. | Editor close unregisters callbacks and timers before destroying bridge state. No VSTGUI or GUI call is permitted from processing. Sanitizer tests cover runtime transition, queue, snapshot, and detach overlap. |
| Native C and C++ shims | Platform callback pointers, thread handles, condition state, and shutdown flags | Zig control code configures and stops; platform or owned native threads use | Shim mutexes and condition variables protect compound native state. C atomics publish shutdown and callback state where callbacks cannot take the control mutex. Thread creation transfers a stable context until join. | Stop or close signals shutdown, unregisters callbacks, joins owned threads, and only then frees the context. Audio callbacks do not take shim control mutexes. Platform-specific unavailability shims own no live thread. |
| Test-only synchronization in example, ARA, VSTGUI, DSP, GUI, and resource test blocks | Barriers, completion flags, observation counters, and injected overlap state | Test threads coordinate deterministic interleavings | Release/acquire flags form explicit test barriers. Monotonic counters record observations that do not publish payloads. | Every spawned test thread is joined before fixture storage leaves scope. These values are evidence machinery, not shipped runtime state. |

## Teardown Order

| Asynchronous owner | Required order | Evidence family |
| --- | --- | --- |
| Native callback source | Close local admission, stop or unregister source, drain admitted callbacks, clear callback-visible state, release handles | Native callback gate unit tests, CoreAudio overlap tests, complete MIDI matrix, repeated TSan |
| Resource or importer worker | Publish cancellation or shutdown, join worker, dispose unclaimed result, retire active and pending resources, destroy stable owner | Resource ownership tests, importer lifecycle tests, owning-example tests, resource TSan |
| Immutable slot publisher | Stop writer, prevent new readers when required, acquire-observe all lease releases, reclaim retired slots | Snapshot stress, resource exchange stress, ARA cache and transform stress, DSP and resource TSan |
| VSTGUI editor | Stop timers and publications, detach parameter and native accessibility callbacks, unregister editor, release global runtime user | Native VSTGUI lifecycle, ASan, UBSan, and TSan gates |
| COM object | Prevent new uncounted borrows, release retained interfaces, release final reference, acquire-observe zero before freeing storage | Raw ABI lifecycle tests, component and controller teardown tests, ARA lifecycle tests |

## Realtime Surface

Permitted processing-thread synchronization is deliberately narrow:

- independent atomic parameter and statistic access;
- bounded SPSC queue publication and consumption;
- immutable snapshot or resource lease acquisition and release;
- fixed-slot resource adoption and block-boundary retirement;
- VST3 data-exchange block lock and free, which the pinned interface explicitly
  assigns to `IAudioProcessor::process`;
- callback admission and release for callbacks that are themselves realtime.

Allocation, mutex acquisition, thread join, file access, logging, GUI calls,
host control calls, resource reclamation, and state serialization are not part
of this surface. Debug and test realtime scopes must reject reachable public
operations before the forbidden work or any related mutation occurs.

## Lexical Source Appendix

The checked appendix includes production files, files with colocated tests, and
dedicated concurrency fixtures. A new matching file fails the repository gate
until its ownership and publication family is reviewed and the path is added.

<!-- concurrency-files:start -->
- `examples/ara_playback_plugin.zig`
- `examples/fixed_rate_core.zig`
- `examples/model_shell_core.zig`
- `examples/resource_swap_core.zig`
- `gui-adapters/vstgui/zig_vstgui_accessibility_atspi_bridge_tests.cpp`
- `gui-adapters/vstgui/zig_vstgui_accessibility_linux_clipboard_tests.cpp`
- `gui-adapters/vstgui/zig_vstgui_accessibility_windows.cpp`
- `gui-adapters/vstgui/zig_vstgui_adapter_tests.cpp`
- `gui-adapters/vstgui/zig_vstgui_editor.cpp`
- `gui-adapters/vstgui/zig_vstgui_editor.h`
- `gui-adapters/vstgui/zig_vstgui_platform.cpp`
- `zig-vst3-plugin/src/dsp/hrtf.zig`
- `zig-vst3-plugin/src/dsp/hrtf_stream.zig`
- `zig-vst3-plugin/src/dsp/realtime_snapshot.zig`
- `zig-vst3-plugin/src/gui_audio_file_importer.zig`
- `zig-vst3-plugin/src/gui_audio_sample_store.zig`
- `zig-vst3-plugin/src/gui_file_importer.zig`
- `zig-vst3-plugin/src/gui_graph.zig`
- `zig-vst3-plugin/src/gui_ir_convolution.zig`
- `zig-vst3-plugin/src/gui_telemetry.zig`
- `zig-vst3-plugin/src/lv2.zig`
- `zig-vst3-plugin/src/parameters/value.zig`
- `zig-vst3-plugin/src/plugin/alsa_midi.zig`
- `zig-vst3-plugin/src/plugin/alsa_midi_shim.c`
- `zig-vst3-plugin/src/plugin/alsa_shim.c`
- `zig-vst3-plugin/src/plugin/alsa_ump.zig`
- `zig-vst3-plugin/src/plugin/alsa_ump_shim.c`
- `zig-vst3-plugin/src/plugin/core_audio.zig`
- `zig-vst3-plugin/src/plugin/core_audio_shim.c`
- `zig-vst3-plugin/src/plugin/core_midi.zig`
- `zig-vst3-plugin/src/plugin/native_callback_gate.zig`
- `zig-vst3-plugin/src/plugin/pipewire_shim.c`
- `zig-vst3-plugin/src/plugin/standalone.zig`
- `zig-vst3-plugin/src/plugin/wasapi.zig`
- `zig-vst3-plugin/src/plugin/wasapi_shim.c`
- `zig-vst3-plugin/src/plugin/win_midi.zig`
- `zig-vst3-plugin/src/plugin/win_midi_shim.c`
- `zig-vst3-plugin/src/plugin/win_ump_shim.cpp`
- `zig-vst3-plugin/src/resource/exchange.zig`
- `zig-vst3-plugin/src/resource/job.zig`
- `zig-vst3-plugin/src/resource/recovery.zig`
- `zig-vst3/src/ara_document_controller.zig`
- `zig-vst3/src/ara_factory.zig`
- `zig-vst3/src/ara_playback_renderer.zig`
- `zig-vst3/src/ara_source_cache.zig`
- `zig-vst3/src/ara_spectral_transform.zig`
- `zig-vst3/src/ara_vst3.zig`
- `zig-vst3/src/factory.zig`
- `zig-vst3/src/funknown.zig`
- `zig-vst3/src/gain_component.zig`
- `zig-vst3/src/gui_note_transport.zig`
- `zig-vst3/src/vst_capability_support.zig`
- `zig-vst3/src/vst_cloneable.zig`
- `zig-vst3/src/vst_component_handler.zig`
- `zig-vst3/src/vst_content_scale_support.zig`
- `zig-vst3/src/vst_context_menu.zig`
- `zig-vst3/src/vst_error_context.zig`
- `zig-vst3/src/vst_event_list.zig`
- `zig-vst3/src/vst_host_application.zig`
- `zig-vst3/src/vst_host_context.zig`
- `zig-vst3/src/vst_inter_app_audio.zig`
- `zig-vst3/src/vst_linux_run_loop.zig`
- `zig-vst3/src/vst_message.zig`
- `zig-vst3/src/vst_note_expression.zig`
- `zig-vst3/src/vst_parameter_changes.zig`
- `zig-vst3/src/vst_parameter_finder.zig`
- `zig-vst3/src/vst_persistent_attributes.zig`
- `zig-vst3/src/vst_plug_frame.zig`
- `zig-vst3/src/vst_plug_view.zig`
- `zig-vst3/src/vst_plugin_compatibility.zig`
- `zig-vst3/src/vst_representation.zig`
- `zig-vst3/src/vst_stream.zig`
- `zig-vst3/src/vst_string_result.zig`
- `zig-vst3/src/vst_test_interfaces.zig`
- `zig-vst3/src/vst_test_plug_provider.zig`
- `zig-vst3/src/vst_unit_data.zig`
- `zig-vst3/src/vst_update_handler.zig`
- `zig-vst3/src/vst_wayland_frame.zig`
- `zig-vst3/src/vst_wayland_standalone_frame.zig`
- `zig-vst3/src/vstgui_headless_host.zig`
- `zig-vst3/src/zig_vst3_plugin_effect.zig`
<!-- concurrency-files:end -->
