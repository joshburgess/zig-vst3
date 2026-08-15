# Concurrency and Realtime Inventory

This record maps cross-thread ownership, publication, synchronization, and
teardown contracts. `scripts/check_quality_concurrency_inventory.sh` keeps the
lexical source appendix synchronized with tracked code. Lexical classification
finds review candidates; it does not prove that unlisted code is thread-safe or
that every listed file contains production concurrency.

## Phase 2 Review Result

The semantic review covers every source selected by the checked concurrency
inventory. Publication and teardown contracts below are paired with the
explicit Zig and native atomic-order ledger, deterministic overlap tests,
repeated ThreadSanitizer gates, and the complete asynchronous teardown matrix.
GitHub Actions run `31858188014` at `4466af3d` passed all 19 jobs, including the
complete pinned macOS 15 sanitizer suite. No critical or high concurrency
finding remains open.

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
| COM and VST3 reference counts in `zig-vst3/src/funknown.zig`, `factory.zig`, `ara_vst3.zig`, `vst_*.zig`, `zig_vst3_plugin_effect.zig`, and the Windows UMP callback | Object lifetime count | Any interface holder increments or decrements; the last releaser destroys | Monotonic increment changes only lifetime count. Release decrement publishes prior use; an acquire observation at zero precedes destruction. A saturated count is a permanent pinned sentinel because further references cannot be represented. Static interface counters never own dynamic storage. | Callers must hold a reference across concurrent use. Final release cannot overlap an uncounted borrow. Saturation deliberately leaks rather than permitting premature destruction. No allocation or blocking occurs in add or release before the final destructor. |
| Parameter scalars in `parameters/value.zig` and Fixed Rate state | One independent normalized value, desired mode, requested mode, or latency | Host or control callbacks write; processing reads | Single-word monotonic parameter access is atomic but intentionally establishes no relationship with other fields. Fixed Rate uses release stores and acquire loads where a mode change accompanies latency publication. | Each value is independently coherent. Multi-field transitions occur through lifecycle callbacks or block-boundary adoption, not by assuming a composite scalar snapshot. |
| GUI scalar telemetry and editor activity in `gui_telemetry.zig` | Latest finite scalar and number of open editors | Processing publishes scalar values; GUI reads them. Editor lifecycle callbacks increment and decrement activity; processing reads whether any editor is active. | Scalar payload bits use release stores and acquire loads. The activity count uses acquire-release transitions because each transition consumes and republishes shared lifecycle state. Saturation is permanently pinned because further opens cannot be represented. | Processing may skip editor-only analysis only when the count is zero. Saturation conservatively keeps analysis active. Operations are fixed-size and never allocate, lock, or wait. |
| SPSC telemetry, MIDI, HRTF, graph, and capture queues | Fixed slots plus producer and consumer indices | One producer owns the write index and slot writes; one consumer owns the read index and slot reads | Producer writes payload, then release-publishes the write index. Consumer acquire-loads it before reading. Consumer release-publishes reclaimed capacity through the read index; producer acquire-loads it. Dropped counters are monotonic statistics only. | No reclamation occurs while either endpoint can run. Queue operations are bounded, allocate nothing, and never wait. Teardown stops the producer before endpoint storage is released. |
| `gui_note_transport.zig` | Per-pitch packed note payload and sequence | GUI producer updates a pitch slot; process consumer drains it | One `u64` CAS release-publishes the complete packed payload. The consumer acquire-loads or exchanges the slot before decoding, so fields cannot tear. | Every call touches at most one fixed slot. Destruction starts only after GUI publication and processing stop. |
| DSP snapshots and generation publishers in `dsp/realtime_snapshot.zig`, `gui_audio_sample_store.zig`, `dsp/convolution.zig`, ARA source cache, and spectral transform | Immutable slot payload, active slot, reader or reference count, and generation | Control or worker writer publishes; one or more realtime readers acquire and release leases | Payload is completed before release publication of slot or generation. Reader admission uses acquire or acquire-release operations. Reader release publishes completion; writers acquire that release before reuse. Serial generation comparison rejects stale and ambiguous identities. | Writers never mutate an acquired slot. Reuse waits only on non-realtime writers or returns busy; realtime acquisition is bounded by configured slot count and never blocks. Teardown closes publication, drains readers, then frees slot storage. |
| Resource exchange, job, and recovery | Prepared pointers, queue status, generations, cancellation, completion, and active resource | Worker prepares and publishes; control thread submits, polls, and reclaims; process thread adopts and reads | Exchange slot states and generations use release publication and acquire adoption. Job and recovery compound state is protected by their mutexes; atomic generations and cancellation flags let workers detect replacement without taking a control mutex. | Only exchange adoption, active access, and block-boundary retirement are realtime. Public control APIs reject instrumented realtime scopes before locks, joins, allocation, file access, callbacks, or state mutation. A worker publishes stopped only after disposal and its final queue check. A completed worker is joined before its handle can be replaced. Teardown cancels and joins the worker before reclaiming resources. |
| VST3 component connection, topology, and pending host changes in `zig_vst3_plugin_effect.zig` | Borrowed peer, immutable topology snapshot, and pending restart bits | Host lifecycle and control callbacks write; processing reads topology; control thread dispatches pending work | Connection and topology compound state use separate mutexes. Completed topology is release-published and acquire-read. Pending bits are atomically coalesced and restored on failed dispatch. | Realtime paths read only the published topology. Public topology mutation and host dispatch reject instrumented realtime scopes before locking or invoking the host. Disconnect removes the peer before component release. |
| Native callback admission in `plugin/native_callback_gate.zig`, CoreAudio, CoreMIDI, ALSA MIDI, Windows MIDI, and UMP adapters | Closed bit plus admitted callback count; callback-visible pointers and parser state | Control thread opens or closes; foreign callback threads acquire and release admission | Opening initializes callback-visible state before release publication. Admission acquires it while incrementing the same atomic word. Closure and admission share one modification order. Callback release is a release operation; the drain acquire-observes zero. | Stop or unregister the platform source, close admission, drain admitted callbacks, then clear pointers and state. Foreign platform contracts must also prevent callbacks after unregister returns. Callback bodies are bounded and do not allocate or lock. |
| Standalone device queues and statistics | Audio or MIDI queue slots, indices, running state, and cumulative counters | Device callbacks produce or consume; engine thread owns the opposite endpoint; control thread starts and stops | Queue indices follow the SPSC release/acquire contract. Running and stop state release-publish callback-visible configuration. Statistics are independent monotonic or saturating counters. | Stop closes callback admission and joins owned threads before queue or callback storage is cleared. Realtime queue operations do not block. Device discovery and reconfiguration remain control-thread work. |
| ARA reader leases and renderer counters | Reader slot, closed bit, active lease count, immutable cache or transform generation, and failure statistics | Host control callbacks open and close; render or analysis threads acquire; cache writers publish generations | Reader closure and lease admission use one atomic word. Open release-publishes the host reader. Successful admission acquires it. Lease release synchronizes with the control-thread drain. Cache and transform slots use immutable release/acquire publication. Renderer failure counts are monotonic statistics. | Close prevents new leases, drains existing leases, then destroys the host reader. Render paths use bounded cache and transform reads and do not take control mutexes. |
| Model Shell and Resource Swap examples | Host configuration, approved or running generation, prepared runtime pointer, latency, and host-request address | Lifecycle callbacks and workers publish; process thread adopts and reads | Host configuration and generation changes are release-published and acquire-read. Prepared objects cross through the resource exchange contract. The host-request address is cleared before its owner can be released. | Requests and preparation are control-thread work. Processing only adopts approved generations and uses immutable prepared state. Teardown joins preparation before destroying the stable engine. |
| VSTGUI runtime and parameter bridge | Global runtime count, pending parameter values and dirty flags, editor registry, and Windows accessibility references | Host parameter callbacks produce; UI thread consumes; editor creation and destruction mutate global runtime state | One mutex serializes global VSTGUI initialization, exit, and editor registry changes. Parameter value storage precedes release publication of its dirty flag; the UI acquire-observes dirty before reading the value. Windows native objects use atomic COM references. | Editor close unregisters callbacks and timers before destroying bridge state. No VSTGUI or GUI call is permitted from processing. Sanitizer tests cover runtime transition, queue, snapshot, and detach overlap. |
| Native C and C++ shims | Platform callback pointers, thread handles, condition state, and shutdown flags | Zig control code configures and stops; platform or owned native threads use | Shim mutexes and condition variables protect compound native state. C atomics publish shutdown and callback state where callbacks cannot take the control mutex. Thread creation transfers a stable context until join. | Stop or close signals shutdown, unregisters callbacks, joins owned threads, and only then frees the context. Audio callbacks do not take shim control mutexes. Platform-specific unavailability shims own no live thread. |
| Test-only synchronization in example, ARA, VSTGUI, DSP, GUI, and resource test blocks | Barriers, completion flags, observation counters, and injected overlap state | Test threads coordinate deterministic interleavings | Release/acquire flags form explicit test barriers. Monotonic counters record observations that do not publish payloads. | Every spawned test thread is joined before fixture storage leaves scope. These values are evidence machinery, not shipped runtime state. |

## Atomic Order Review

The explicit order tokens checked in `atomic-orders.md` have these semantic
dispositions. The ledger is lexical and deliberately over-counts tokens such as
VST table fields named `release`; a changed count still requires renewed review.

| Family | Reviewed sources | Order disposition | Result |
| --- | --- | --- | --- |
| Lifetime counts | `factory.zig`, `funknown.zig`, `vst_context_menu.zig`, `vst_plug_view.zig`, `vst_plugin_compatibility.zig`, `vst_wayland_standalone_frame.zig`, `zig_vst3_plugin_effect.zig`, `win_ump_ref_count.hpp`, `win_ump_shim.cpp` | Increments are independent monotonic lifetime changes. Release decrements publish prior use, and final destruction follows an acquire observation. Maximum count is pinned because accepted references beyond it cannot be represented. | Q-CONC-007 and Q-CONC-010 fix unstable or wrapping saturation. |
| Independent scalars and counters | `parameters/value.zig`, `gui_telemetry.zig`, `ara_playback_renderer.zig`, native backend statistics in the checked Zig, C, and C++ sources | Parameter words and statistics do not publish other fields. Their monotonic or relaxed order is sufficient. Telemetry values use release and acquire consistently, although no weaker-order claim depends on them. | Reviewed; no additional defect found. |
| Single-producer queues | `gui_graph.zig`, `gui_telemetry.zig`, `hrtf/motion.zig`, `hrtf_stream.zig`, `standalone.zig`, `gui_note_transport.zig`, `pipewire_shim.c` | Each endpoint reads its own cursor with monotonic or relaxed order. A producer release-publishes payload through its cursor, and the consumer acquires that cursor before reading. The consumer release-publishes reclaimed storage in the opposite direction. Reset requires stopped endpoints. | Reviewed; publication and reuse edges are matched. |
| Immutable slots and resource exchange | `realtime_snapshot.zig`, `gui_audio_sample_store.zig`, `dsp/convolution.zig`, `resource/exchange.zig`, `fixed_rate_core.zig`, `model_shell_core.zig`, `resource_swap_core.zig`, `ara_document_controller.zig` | Writers claim inactive storage before mutation and release-publish completed payload. Readers acquire state or active-slot publication before access and release leases before reuse. Resource generation uses unordered access only while slot state supplies the release and acquire edge. | Reviewed; ARA lease admission and saturated reader counts remain indivisible. |
| Workers and staged control state | `gui_file_importer.zig`, `resource/job.zig`, `resource/recovery.zig`, `lv2.zig` | Mutexes protect compound state. Release and acquire values carry cancellation, generation, shutdown, or staged-state transitions to workers without replacing mutex ownership. LV2 staged restore advances through one CAS-controlled phase at a time. | Reviewed; Q-CONC-009 fixed the completed-worker handle handoff. |
| Native callback admission and shutdown | `native_callback_gate.zig`, `alsa_midi.zig`, `alsa_ump.zig`, `core_audio.zig`, `core_midi.zig`, `win_midi.zig`, `wasapi.zig`, and the checked native audio and MIDI shims | Closure and admission share one atomic word where callbacks borrow Zig-owned state. Release of the final admission synchronizes with the acquire drain. Owned native threads acquire-observe release-published stop state before join. | Reviewed; Q-CONC-003, Q-CONC-004, and Q-CONC-006 established the current gates. |
| VSTGUI parameter handoff | `zig_vstgui_editor.cpp` | The producer writes the atomic value before release-publishing dirty. The UI exchange acquires dirty before loading the value. UI teardown stops parameter delivery before destroying arrays. | Reviewed; no defect found. |
| Test-only observations | `gui_audio_file_importer.zig`, `ara_source_cache.zig`, `ara_spectral_transform.zig`, `vst_capability_support.zig`, `vst_cloneable.zig`, `vst_content_scale_support.zig`, `vst_error_context.zig`, `vst_event_list.zig`, `vst_inter_app_audio.zig`, `vst_linux_run_loop.zig`, `vst_note_expression.zig`, `vst_parameter_changes.zig`, `vst_parameter_finder.zig`, `vst_persistent_attributes.zig`, `vst_plug_frame.zig`, `vst_stream.zig`, `vst_string_result.zig`, `vst_test_interfaces.zig`, `vst_test_plug_provider.zig`, `vst_unit_data.zig`, `vst_update_handler.zig`, `vst_wayland_frame.zig`, `vstgui_headless_host.zig`, and the checked VSTGUI test sources | Release and acquire pairs coordinate test threads. Monotonic, relaxed, and sequentially consistent operations record independent evidence. They do not define shipped publication contracts. | Reviewed as test machinery. |

## Teardown Order

| Asynchronous owner | Required order | Evidence family |
| --- | --- | --- |
| Native callback source | Close local admission, stop or unregister source, drain admitted callbacks, clear callback-visible state, release handles | Native callback gate unit tests, CoreAudio overlap tests, complete MIDI matrix, repeated TSan |
| Resource or importer worker | Publish cancellation or shutdown, join worker, dispose unclaimed result, retire active and pending resources, destroy stable owner | Resource ownership tests, importer lifecycle tests, owning-example tests, resource TSan |
| Immutable slot publisher | Stop writer, prevent new readers when required, acquire-observe all lease releases, reclaim retired slots | Snapshot stress, resource exchange stress, ARA cache and transform stress, DSP and resource TSan |
| VSTGUI editor | Stop timers and publications, detach parameter and native accessibility callbacks, unregister editor, release global runtime user | Native VSTGUI lifecycle, ASan, UBSan, and TSan gates |
| COM object | Prevent new uncounted borrows, release retained interfaces, release final reference, acquire-observe zero before freeing storage | Raw ABI lifecycle tests, component and controller teardown tests, ARA lifecycle tests |

## Teardown Coverage Matrix

This matrix is exhaustive over the asynchronous publication families above.
It separates owners that must stop or drain work from bounded transports whose
caller owns both endpoint lifetimes.

| ID | Asynchronous family | Closure or lifetime boundary | Deterministic overlap evidence | Sanitizer evidence |
| --- | --- | --- | --- | --- |
| T01 | Native callback admission: CoreAudio session and topology, CoreMIDI, ALSA MIDI and UMP, Windows MIDI and UMP | Close the indivisible admission word, unregister or stop the platform source, drain admitted callbacks, then clear callback-visible state | The callback-gate stale-admission and blocking-drain tests; each MIDI backend's `input stop drains` test; CoreAudio native callback admission test; Windows UMP pinned-reference stress | `test-midi-thread-sanitizers`, CoreAudio's focused TSan module, and the portable UMP TSan executable. Native Windows CI executes the SDK-backed UMP module. |
| T02 | Standalone audio, capture-rate bridge, MIDI queue, and application device ownership | Stop the device callback source before runtime and queue teardown; restart reinitializes callback-visible configuration | `standalone application contains callbacks across stop and restart`, device lifecycle tests, and bounded capture and MIDI SPSC stress | The aggregate Phase 2 TSan gate selects bounded capture and MIDI queue transfers. Backend C shims run with full C undefined-behavior instrumentation. |
| T03 | Resource jobs, recovery, decoded-audio importers, Model Shell, and Resource Swap | Publish cancellation, join the worker, dispose any unclaimed result, stop processing, then retire exchange slots and destroy stable owners | Job replacement and cancellation tests, decoded importer cancellation acknowledgment, repeated Model Shell preparation teardown, and owning-example lifecycle tests | `test-resource-thread-sanitizer` covers job, recovery, exchange, and decoded importer cancellation plus join. |
| T04 | Immutable snapshots, graph and telemetry publications, sample and IR stores, and resource exchange | Stop the writer or processing endpoint, prevent new leases where required, observe every release, then reclaim retired slots | Realtime-reference release and malformed-copy tests, coherent-generation stress, resource replacement stress, and IR preparation queue stress | `test-phase2-thread-sanitizers`, `test-resource-thread-sanitizer`, and `test-dsp-thread-sanitizer`. |
| T05 | ARA host readers, source cache, and spectral publications | Close lease admission, drain active readers, destroy the foreign reader, then reclaim cache or transform generations | `ARA controller reads host audio and closes readers safely`, cache generation stress, and spectral coherent-read stress | The aggregate Phase 2 TSan gate runs the reader close and cache overlap selections. Spectral publication runs in the ARA and DSP concurrency suites. |
| T06 | HRTF motion and prepared-filter streams | The caller stops and joins its producer before renderer or database storage ends. The transport itself owns no thread or heap allocation. | Motion-point and prepared-filter producer tests join before scope teardown and verify ordered complete transfer | `test-dsp-thread-sanitizer` runs both HRTF concurrent transfer families. No internal worker teardown exists. |
| T07 | VSTGUI runtime users, editor callbacks, timers, native accessibility objects, and foreign registrations | Stop timers and publications, detach parameter and accessibility callbacks, unregister the editor, destroy views, then release the serialized global runtime user | Concurrent headless editor lifecycle tests, retained accessibility object tests, registration rollback tests, and runtime transition tests | Four repeated native VSTGUI TSan processes plus ASan and UBSan lifecycle suites. The runner now fails if any evidence artifact cannot be written. |
| T08 | VST3 COM lifetimes and connection peers | Prevent new uncounted borrows, retain a peer across each unlocked host call, disconnect under the peer mutex, then release the final component reference | Saturated and concurrent COM reference tests, replaced-peer release tests, disconnect and reconnect host-request lifecycle | The aggregate Phase 2 TSan gate runs concurrent reference changes. VST3 module lifecycle tests exercise peer retention and release. |

ALSA, PipeWire, WASAPI, and CoreAudio audio backends delegate callback-source
quiescence to their synchronous platform stop or destroy contracts. T02 covers
the framework-owned state transition independently of hardware. Phase 6 retains
the native ABI and platform-contract audit; it is not treated as an untested
framework teardown interval here.

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
- `zig-vst3-plugin/src/dsp/hrtf/motion.zig`
- `zig-vst3-plugin/src/dsp/hrtf_stream.zig`
- `zig-vst3-plugin/src/dsp/realtime_snapshot.zig`
- `zig-vst3-plugin/src/gui_audio_file_importer.zig`
- `zig-vst3-plugin/src/gui_audio_sample_store.zig`
- `zig-vst3-plugin/src/gui_file_importer.zig`
- `zig-vst3-plugin/src/gui_graph.zig`
- `zig-vst3-plugin/src/dsp/convolution.zig`
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
- `zig-vst3-plugin/src/plugin/win_ump_ref_count.hpp`
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
