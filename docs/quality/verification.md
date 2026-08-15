# Quality Verification Record

## 2026-08-14: Program Baseline

Commit: `08bf883e9d2d324f3a7933fa21851bbd9ffec513`

| Check | Result |
| --- | --- |
| `git status --short --branch` | Clean tracked worktree; branch initially one commit ahead of remote |
| `git rev-parse zig-vst3-0.3.0-rc.1^{}` | `7650781a5625c041ec474a5377d859a427a344f3` |
| `git rev-parse zig-vst3-0.3.0^{}` | `cf3baa5f132df16bdfa5e86d3437e4cfc3295b39` |
| `git push origin feature/plugin-gui` | Pushed `1e42da87..08bf883e` without rewriting history |
| Pull request 6 query | Open, draft, mergeable; head `08bf883e9d2d324f3a7933fa21851bbd9ffec513`; checks had not populated |

## 2026-08-14: Initial Source Classification

Command: `scripts/check_quality_inventory.sh`

Result: the first pass assigned 809 tracked source files. It rejected two
omitted files before explicit rules were added. The codec and spatial units were
then split to keep review scope coherent. With both inventory scripts staged,
the current result is 811 files and 465,508 lines across Q00–Q22.

Command: `scripts/test_quality_inventory_runner.sh`

Result: passed. The fixture accepts known Q01 and Q10 source paths and rejects a
tracked Zig file outside every review unit.

This check establishes classification coverage only. It does not establish
correctness, source provenance, or completion of any review unit.

## 2026-08-14: Initial Dependency Check

Commands:

- relative-import search across `zig-vst3-plugin/src/dsp`
- host-format import search across framework core directories
- import listing for all Q04 adapter files

Results:

- Framework core did not directly import LV2, Audio Unit, or native backend
  implementation files in the searched directories.
- Several modulation DSP modules consume Q08's format-neutral `Transport` type.
  The inventory now records that dependency.
- HRTF imported the partitioned convolver from `gui_ir_convolution.zig`. The
  convolver was reassigned to Q15 by responsibility and the placement problem is
  recorded as Q-ARCH-002.
- Q04 imports raw VST3 and ARA integration plus the format-neutral framework. Its
  dependency row now includes Q02.

## 2026-08-14: Phase 0 Gate

Environment: macOS Darwin 24.4.0 on arm64, Zig 0.16.0.

| Check | Result |
| --- | --- |
| `zig build test --summary all` | Passed: 419/419 build steps, 7,389 tests passed, 4 skipped |
| Main Debug test group | Passed: 1,790 tests, 2 skipped, 47 minutes, 51 MiB maximum resident memory |
| `scripts/check_retired_reference.sh` | Passed |
| `scripts/test_raw_callback_pointer_check.sh` | Passed |
| `scripts/check_raw_callback_pointers.sh` | Passed |
| `scripts/test_production_termination_path_check.sh` | Passed |
| `scripts/check_production_termination_paths.sh` | Passed |
| `scripts/test_quality_inventory_runner.sh` | Passed |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 465,508 lines classified |
| Em dash scan over maintained prose | Passed |
| `zig fmt --check build.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Ogg Container Boundary

Ogg page and packet iteration, chained logical streams, bounded recovery,
seek indexing, stream writing, and positional file I/O now live in
`dsp/ogg/container.zig`. The module owns page continuity, packet assembly,
stream limits, checksums, and reader and writer offsets without importing
Vorbis codec state. The existing `dsp/ogg.zig` declarations remain exact
aliases.

| Check | Result |
| --- | --- |
| `zig build test-vorbis --summary all` | Passed: 10/10 steps and 94/94 tests |
| ReleaseSafe cross-compilation | Passed: Linux AArch64, Linux x86-64, and Windows x86-64 |
| Independent runners | Passed: Xiph Vorbis, stb_vorbis, Tremor preparation, and Tremor interoperability failure coverage |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: MP3 Cohesion Closure

The complete MP3 encoding contract now lives in `dsp/mp3_encoder.zig`.
It owns CBR and VBR analysis and quantization, adaptive reservoir streams,
gapless finalization, Xing and VBRI emission, and both memory and positional
file publication. These variants share encoder configuration, transform
history, bit budgets, frame accounting, rollback storage, and transactional
publication rules.

`dsp/mp3.zig` is now the compatibility facade and its colocated behavioral
suite. Its public declarations remain exact aliases to the syntax, codec,
reader, metadata, reservoir, and encoder modules. The cohesion ledger
classifies both the 518-production-line facade and the 11,747-line encoder
contract as `KEEP`, completing the MP3 portion of Q-ARCH-001.

| Check | Result |
| --- | --- |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 131/131 tests |
| ReleaseSafe cross-compilation | Passed: Linux AArch64, Linux x86-64, and Windows x86-64 |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| Cohesion inventory and fixture | Passed: 34 large handwritten sources classified |
| Quality and concurrency inventories | Passed: 864 files and 477,981 lines classified; 86 concurrency sources classified |
| Parser inventory and fixture | Passed: 199 production sources classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: MP3 Reservoir Credit Boundary

Reservoir quantizer budgets, history-credit validation, and failure-atomic
credit commits now live in `dsp/mp3/reservoir.zig`. The module owns the
available-history and committed-frame state and depends only on passive MPEG
header syntax. The public facade exposes exact aliases for every moved type and
function.

| Check | Result |
| --- | --- |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 131/131 tests |
| ReleaseSafe cross-compilation | Passed: Linux AArch64, Linux x86-64, and Windows x86-64 |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

The four skips were reported inside the Debug groups. Platform and hardware
availability will be accounted for in Phase 6 rather than counted as passes.

The main Debug group remained CPU-bound and made forward progress throughout
its 47-minute run. Inspection found repeated and nested full-document scans in
ADM XML construction and validation, with no document-size limit. Finding
Q-ADM-001 records the production complexity risk for Phase 3.

Phase 0 completion commit: `69403ddd8a41b8a59c6b047f9b87065157e4087d`

## 2026-08-14: Q04 Owning Object Allocation

Command: `zig build test-vst3-module --summary all`

Result: passed, 7/7 build steps and 786/786 tests. The new tests inject failure
at controller allocation, component allocation, and processor-owned storage.
They also release a successfully created component through the stored testing
allocator, which gives the Debug allocator leak visibility over both ownership
levels.

Change commit: `8158b82d60ea22171e338824861329331423dc01`

## 2026-08-14: Native Shim Inventory Correction

Commands:

- `scripts/test_quality_inventory_runner.sh`
- `scripts/check_quality_inventory.sh`

Result: passed. The fixture now requires a representative native shim to map to
Q18. The corrected inventory still classifies 811 files, with 16 files in Q06
and 58 in Q18. The source total is 465,638 lines after the Q04 allocator tests.

Change commit: `dd2ec5b2bd4d200e03d922594527bc6e2cd26c9d`

## 2026-08-14: Q06 Runtime Ownership

Reviewed scope:

- `plugin/instance.zig`
- `plugin/runtime.zig`
- `plugin/lifecycle.zig`
- `plugin/offline_renderer.zig`

The runtime owns exactly one successfully initialized plugin value. Its
terminal teardown orders deactivation, reset, prepared-resource release, state
transition, and plugin deinitialization. The offline renderer's normal and
error cleanup converge on those state-aware operations. A new exhaustive
allocation-failure test covers the initializer transfer boundary.

Commands and results:

| Check | Result |
| --- | --- |
| `zig build test-plugin-core-builds --summary all` | Passed: 2/2 steps; ReleaseSafe Windows test compilation |
| `zig build test-plugin-runtime --summary all` | Passed: 3/3 steps and 12/12 Debug tests |

The focused runtime step includes the new exhaustive allocation-failure test
and the existing lifecycle, terminal-state, state-restore, process-mode, and
dynamic-topology runtime tests. It completes in under a second after
compilation and does not run unrelated parser suites.

Change commit: `ca309fc700543a65b9dacf4a4e8b3e2d8cf33bff`

## 2026-08-14: Q07 Resource Ownership

Reviewed scope: resource job, exchange, recovery, byte accumulator, reference,
state, parameter, unit, and migration ownership boundaries.

Command: `zig build test-resource-ownership --summary all`

Result: passed, 3/3 build steps and 49/49 Debug tests. The focused selection
exercises transfer, abandonment, failure preservation, cancellation, teardown,
generation replacement, bounded state, and allocation-failure behavior without
running unrelated codec and parser tests.

## 2026-08-14: Q02 ARA Ownership

| Check | Result |
| --- | --- |
| `zig build test-ara-native --summary all` | Passed: 28/28 steps and 424/424 Debug tests |
| `zig build test-ara-source-cache --summary all` | Passed: 6/6 steps and 5/5 native tests, plus ReleaseSafe Linux and Windows cross-builds |

The review traced factory slot ownership, release callbacks, bounded controller
storage, host reader leases, provider contexts, fixed source-page publication,
extension binding, and static main-factory identity. Q02 performs no dynamic
allocation itself. Host interfaces and callback contexts are explicit borrows
whose required lifetime is now recorded in the ownership table.

## 2026-08-14: Q03 VSTGUI and Wayland Ownership

Reviewed scope: VST3 VSTGUI view binding, LV2 VSTGUI backend, Wayland raw
wrappers, standalone Wayland bridge, and the headless VSTGUI host.

The audit found that accepted LV2 host peak subscriptions outlived both failed
construction and normal backend destruction. Commit `02038b05` adds explicit
per-subscription ownership, rollback, teardown, and regression tests.

| Check | Result |
| --- | --- |
| `zig build test-vstgui-native --summary all` | Passed: 4/4 native VSTGUI interaction, accessibility, and visual-test build steps |
| `zig build test-vst3-module --summary all` | Passed: 7/7 steps and 787/787 Debug tests |
| `zig build test-gui-lifecycle --summary all` | Passed: 40/40 steps and 2,384/2,384 Debug tests across every example editor |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 465,791 lines classified; Q03 contains 7 files and 6,152 lines |

## 2026-08-14: Q17 LV2 and AUv2 Ownership

Reviewed scope: LV2 processing instance, LV2 UI instance and registrations,
Audio Unit render core, AUv2 component storage and dispatch, native class-info
bridge, and LV2 metadata generation.

Commit `be81b415` adds allocator provenance and outer-allocation failure
coverage to the three host-allocated instance types. It also corrects the LV2
UI teardown order so editor-owned subscriptions unregister while their context
is still valid.

| Check | Result |
| --- | --- |
| `zig build test-lv2 --summary all` | Passed: 56/56 steps and 570/570 tests, including ABI, native host, bundle, metadata, UI, component-state, topology, and ReleaseSafe cross-build checks |
| `zig build test-audio-unit --summary all` | Passed: 30/30 steps and 284/284 tests, including ABI, native host, bundle, multi-output, and ReleaseSafe cross-build checks |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 465,926 lines classified; Q17 contains 6 files and 22,409 lines |

## 2026-08-14: Q18 Native Backend Ownership

Reviewed scope: CoreAudio, WASAPI, ALSA, PipeWire, CoreMIDI, ALSA MIDI and
UMP, Windows MIDI and UMP, scheduler queues, device catalogs, and standalone
Win32, Cocoa, X11, and Wayland windows, including their native shims.

Commit `d28816e4` makes ALSA and Windows MIDI initialization failure-atomic and
closes a PipeWire properties leak on errors before stream construction. Native
test modules now compile their host-platform C or Objective-C shims with Zig's
full C undefined-behavior instrumentation.

Command:

`zig build test-coreaudio test-wasapi test-alsa test-pipewire test-alsamidi test-alsaump test-winmidi test-winump test-coremidi test-winwindow test-cocoawindow test-x11window test-waylandwindow --summary all`

Result: passed, 90/90 build steps and 87/89 tests. The two skips are explicit
opposite-platform branches: unsupported CoreAudio on macOS and native PipeWire
on non-Linux. The matrix also completed ReleaseSafe Linux and Windows cross
compilation and link fixtures for the applicable backends.

The ALSA and Windows MIDI tests inject initial device-query failure, verify a
closed state with zero topology generation, and then reopen the same backend.
PipeWire property ownership follows the upstream contract: the shim frees the
object before stream construction, while a call to `pw_stream_new_simple`
transfers it to PipeWire.

Inventory check: passed, 811 files and 466,001 lines classified. Q18 contains
58 files and 36,654 lines.

## 2026-08-14: Q19 VSTGUI Ownership

Reviewed scope: the C ABI adapter, editor and component tree, control-specific
views, timers, assets and drawing resources, Linux run-loop integration,
native accessibility implementations, and X11 and Wayland clipboard bridges.

Commit `bd48cec4` detaches retained macOS and Windows accessibility objects,
rolls back incomplete editor frames and foreign registrations, closes a
pre-transfer editable-label leak, and preserves one progress timer across
reopen instead of replacing it.

| Check | Result |
| --- | --- |
| `zig build test-vstgui-native --summary all` | Passed: 4/4 native interaction, accessibility, visual, and cross-platform compilation steps |
| `VSTGUI_SANITIZER_SOAK_REPETITIONS=8 scripts/vstgui_sanitizer_soak.sh` | Passed: 24/24 ASan and UBSan process runs across adapter, macOS accessibility, and visual phases |
| `VSTGUI_THREAD_SANITIZER_REPETITIONS=4 scripts/test_vstgui_thread_sanitizer.sh` | Passed: 4/4 TSan adapter process runs |
| `zig build test-vst3-module test-gui-lifecycle --summary all` | Passed: 43/43 build steps and 3,171/3,171 tests |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 466,088 lines classified; Q19 contains 67 files and 32,685 lines |

The macOS regression retains a native accessibility element after editor close
and verifies that visibility, label, value, and frame queries no longer reach
the destroyed semantic node or VSTGUI view. Windows provider detachment and
Linux platform registration rollback are covered by Release cross-compilation;
their real operating-system callback behavior remains part of Phase 6.

## 2026-08-14: Q08 and Q09 Bounded Ownership

Reviewed scope: process audio views, parameter automation, events, output
writers, process segmentation, MIDI 1 and 2, UMP, MIDI-CI, MPE, Standard MIDI
Files, bounded packetizers, reassemblers, caches, and sessions.

All commands used the plugin-core module root so relative imports and the same
Debug allocator configuration as the repository build remained active.

| Check | Result |
| --- | --- |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter process.context` | Passed: 43/43 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter process.events` | Passed: 31/31 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter process.changes` | Passed: 24/24 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter process.midi_` | Passed: 159/159 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter MIDI` | Passed: 98/98 tests, including `midi1`, `midi2`, process-event conversion, and backend integration selected by the filter |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter process.mpe` | Passed: 26/26 tests |

Q08 performs no dynamic allocation. It owns copied slice descriptors and
borrows the referenced host buffers for one process call. Q09's persistent
protocol state is fixed-capacity. Its dynamic parse boundary returns a caller-
owned `std.json.Parsed` arena, and every post-parse rejection releases that
arena before ownership can transfer.

The review found no memory leak or dangling transfer in Q08 or Q09. It did find
quadratic canonical replay in Standard MIDI File iteration. Q-MIDI-001 records
that medium parser-complexity risk for Phase 3.

## 2026-08-14: Q10–Q15 Ownership

Reviewed scope: Ogg and Vorbis, MP3, FLAC, file and metadata formats, ADM,
dynamic spatial matrices, SOFA loading, HRTF and HOA, DSP histories, and the
partitioned-convolution publication path.

| Check | Result |
| --- | --- |
| `zig build test-vorbis --summary all` | Passed: 10/10 steps and 92/92 tests, including native Xiph, stb, and Tremor comparison runners plus ReleaseSafe Linux and Windows builds |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 129/129 tests plus ReleaseSafe Linux and Windows builds |
| `zig build test-matrix --summary all` | Passed: 6/6 steps and 37/37 tests, including exhaustive allocation failures and ReleaseSafe cross-builds |
| `zig build test-hrtf test-hoa --summary all` | Passed: 19/19 steps and 167/169 tests; two platform branches skipped explicitly |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter dsp.flac --test-filter dsp.audio_file_reader --test-filter dsp.audio_metadata --test-filter dsp.broadcast_metadata --test-filter dsp.id3 --test-filter dsp.ixml --test-filter dsp.xml --test-filter writer` | Passed: 164/164 tests; the broad writer filter also selects event, resource, Ogg, snapshot, and integration writer tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter gui_ir_convolution --test-filter realtime_snapshot --test-filter duplicator --test-filter process_context` | Passed: 52/52 tests |

The HOA independent reference checked 336 basis values, 12,672 coefficients,
and 203,544 rendered samples. Q10–Q13 use caller buffers and fixed-capacity
state rather than owning heap allocations. Q14's dynamic matrix and SOFA paths
pair every allocation with stored allocator teardown or lexical rollback. Q15
uses bounded state and fixed publication slots.

## 2026-08-14: Q01 Raw Plug View Ownership

Command: `zig build test-vst3-module --summary all`

Result: passed, 7/7 build steps and 788/788 tests. The new generic plug-view
test rejects its outer allocation through a failing allocator and releases a
successful final COM reference through `std.testing.allocator`.

Change commit: `22a2bd65c244aa634339ecbd402085e4858df926`

## 2026-08-14: Q16 GUI Model Ownership

Commands and results:

| Check | Result |
| --- | --- |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter gui. --test-filter editor_state` | Passed: 36/36 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter gui_` | Passed: 136/136 tests |

The commands used an isolated writable Zig global cache because the execution
sandbox denied writes to the user's default cache. Q16 owns fixed-capacity GUI
models and one-shot adapter callbacks. Its decoded audio importer owns an
optional worker and joins it after acknowledged cancellation. The selections
cover transactional state, malformed retained fields, generation publication,
import teardown, and adapter destruction.

## 2026-08-14: Q20 Owning Examples

Command: `zig build test-example-ownership --summary all`

Result: passed, 17/17 build steps and 44/44 tests. The focused step covers the
resource-swap, fixed-rate, model-shell, IR-loader, and sample-player owning
runtime wrappers. Each now rejects outer allocation failure deterministically,
and the existing successful paths release the stable-address engine through the
same testing allocator.

Change commit: `53b2118a`

## 2026-08-14: VSTGUI Runtime Transition Serialization

The Phase 2 atomic review found that an atomic reference count did not make the
first runtime initialization a publication barrier. A second constructor could
return after incrementing the count but before the first constructor completed
`VSTGUI::init`. Commit `23ad7a26` serializes count changes, initialization, and
exit with one non-realtime mutex.

| Check | Result |
| --- | --- |
| `zig build test-vstgui-sanitizers --summary all` | Passed: address and undefined-behavior sanitizer processes completed |
| `zig build test-vstgui-thread-sanitizer --summary all` | Passed: 2/2 steps and four TSan process runs |
| First `zig build test-vstgui-native --summary all` | Functional adapter and accessibility tests passed; visual performance process returned 6 while concurrent sanitizer and ADM jobs doubled all timing measurements |
| Isolated retry while ADM remained active | Visual fixtures still rendered correctly, but the sample-player editor lifecycle average was 110.6 ms and exceeded its 100 ms threshold |

The native performance gate remains pending until the long ADM process stops.
The two failures are retained here because removing load-related measurements
would overstate the evidence.

## 2026-08-14: Phase 2 Publication Stress

Commit `0902069b` adds ordered and coherent-generation stress for the GUI
telemetry queue, graph snapshot series, and audio sample store. The focused
TSan step also selects standalone bounded capture and MIDI queues, ARA audio
reader close overlap, and ARA source-cache generation publication.

| Check | Result |
| --- | --- |
| `zig build test-phase2-thread-sanitizers --summary all` | Passed: 8/8 steps and 14/14 tests under TSan |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter concurrent` | Passed: 15/15 Debug tests |
| `zig build test-resource-thread-sanitizer test-dsp-thread-sanitizer --summary all` | Passed: 8/8 steps and 206/206 tests |

The new tests use ordered values or related fields from one generation, so a
lost item, duplicate item, torn snapshot, or mixed publication becomes a
deterministic assertion failure in addition to any sanitizer report.

## 2026-08-14: Control-Thread Resource Publication

The concurrency audit traced model-shell resource completion from Q07's worker
through `publicationReady`, host-request dispatch, the VST3 connection point,
and `IComponentHandler::restartComponent`. The pinned VST3 SDK documentation
requires that restart callback in the UI-thread context. Commit `83b88b6e`
makes worker completion data-only and invokes `publicationReady` synchronously
from `poll` or `waitAndPoll` on the calling control thread. Model-shell GUI
telemetry polling now performs that maintenance before reading presentation
state.

| Check | Result |
| --- | --- |
| `zig build test-resource-ownership test-example-ownership --summary all` | Passed: 20/20 steps and 93/93 tests |
| `zig build test-resource-thread-sanitizer --summary all` | Passed: 3/3 steps and 57/57 tests under TSan |
| Native VSTGUI dependency of the owning-example gate | Passed after the fix; visual rendering and the 53.2 ms sample-player lifecycle measurement remained below their thresholds |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 466,450 lines classified |

The resource regression waits for worker completion and verifies that the
publication callback remains untouched until the caller polls. The model-shell
regression records the callback thread and verifies that latency marking and
dispatch run on the thread that called `waitForModel`.

Change commit: `83b88b6e4bdbe9aaed7c454b1d9d20c5b10ce9c8`

## 2026-08-14: Native Callback Drain

The Q18 teardown audit found that CoreAudio relied on platform stop and removal
calls before freeing session and topology-observer contexts, but did not make
callback admission or draining explicit. CoreMIDI input stop could also race a
receive callback that had already observed `input_running` before `close`
cleared its non-atomic callback and timebase fields.

Commit `8674295f` adds lock-free admission and active-callback counters around
all CoreAudio audio and topology callbacks. Teardown publishes closure, stops
or unregisters the platform source, waits for release from admitted callbacks,
and then frees the context. Commit `a27291e0` applies the corresponding input
stop and topology-close protocol to CoreMIDI. Both changes use a second state
check after incrementing the active count so a callback racing closure either
withdraws or becomes part of the drain.

| Check | Result |
| --- | --- |
| `zig build test-coreaudio --summary all` | Passed: 9/9 steps and 10/11 tests; one native device-discovery branch skipped because it depends on available hardware |
| CoreAudio TSan selection inside `test-coreaudio` | Passed: 2/2 selected tests, including the C admission and drain overlap helper |
| `zig build test-coremidi --summary all` | Passed: 9/9 steps and 13/13 tests |
| CoreMIDI TSan selection inside `test-coremidi` | Passed: the blocking receive callback remained admitted until release, and input stop did not return early |
| `scripts/check_quality_inventory.sh` | Passed: 811 files and 466,897 lines classified |

Two sandboxed CoreAudio attempts failed before compilation with Zig
`manifest_create PermissionDenied`, including one attempt with new cache
directories. The approved unsandboxed rerun with fresh cache directories
passed. These were environment failures, not test failures.

Change commits: `8674295f`, `a27291e0`

## 2026-08-14: Phase 1 Candidate Gate Interruption

Candidate commit: `1f29ed00fe8d74bb7075de00025304d9fe63677f`

Command:

`zig build --cache-dir /private/tmp/zig-vst3-phase1-local --global-cache-dir /private/tmp/zig-vst3-phase1-global test --summary all`

The run passed the repository script checks, codec probes, DSP parity checks,
VSTGUI visual dependency, downstream effect and instrument consumers, and
installed-package consumers reached before the long Debug group. It was then
stopped intentionally with exit 130 after the continuing read-only audit found
a retained CoreMIDI callback borrow and a non-indivisible callback admission
scheme. This interrupted run is baseline evidence only and does not satisfy the
Phase 1 exact-commit gate.

The independently running focused ADM selection completed 210/210 tests before
the candidate gate was stopped. It confirms the Q13 ownership paths execute
successfully, while Q-ADM-001 continues to track their unbounded work risk for
Phase 3.

## 2026-08-14: Native MIDI Callback Admission

Change commit: `e4910414`

CoreMIDI retained its caller-borrowed callback after failed connection and
normal stop. ALSA MIDI, Windows MIDI, and the shared ALSA and Windows UMP
backend also depended on their platform stop behavior without a Zig-side
admission and drain contract. The first CoreMIDI drain used separate closing
and count atomics, so closure and admission were not one indivisible state
transition.

The shared callback gate stores a closed bit and active count in one atomic
word. Opening publishes callback-visible fields, admission acquires that
publication while incrementing the same word, closure prevents later
increments, and the control thread waits for release from every admitted
callback before clearing callback or parser state. CoreMIDI topology callbacks
use the same gate. Its partial-open cleanup now closes admission before
disposing foreign registrations.

The audit also found that `test-alsaump` compiled its implementation as a named
dependency but executed only the public wrapper's import test. The corrected
build graph runs the implementation as a test root, so its backend tests now
execute instead of remaining compile-only.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-midi-gate-local --global-cache-dir /private/tmp/zig-vst3-midi-gate-global test-coremidi test-alsamidi test-alsaump test-winmidi test-winump --summary all` | Passed: 45/45 build steps and 60/60 tests, including Debug native behavior, TSan selections, ReleaseSafe Linux and Windows cross-builds, and link fixtures |
| Corrected `test-alsaump` implementation root | Passed: 11/11 implementation tests plus the public wrapper test; the former graph executed only the wrapper test |
| `for repetition in {1..16}; do zig build --cache-dir /private/tmp/zig-vst3-midi-gate-local --global-cache-dir /private/tmp/zig-vst3-midi-gate-global test-midi-thread-sanitizers --summary none \|\| exit; done` | Passed: 16/16 aggregate repetitions, 64 sanitizer process runs, and 112 selected tests |
| `scripts/test_quality_inventory_runner.sh` | Passed |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,373 lines classified; Q18 contains 59 files and 37,403 lines |

The first sandboxed focused matrix reached 25 passing tests but reported eleven
Zig `manifest_create PermissionDenied` cache failures. The approved rerun
outside the sandbox passed completely. These were environment failures, not
test failures.

## 2026-08-14: Installed MIDI Module Identity

Change commit: `42257ac2`

The exact Phase 1 gate at `6f32eea0` found that a relative import of
`native_callback_gate.zig` worked when each backend compiled alone but failed
when the installed consumer imported CoreMIDI, ALSA MIDI, Windows MIDI, and UMP
together. Zig correctly rejected assigning the same source file to several
module identities.

The build now creates one named callback-gate module shared by the public
backend graph. Isolated native, TSan, and cross-target compilations receive a
target-matched instance of that named module. The gate's own tests run as a
dedicated TSan root, so changing the import boundary does not reduce its direct
coverage.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-midi-module-local --global-cache-dir /private/tmp/zig-vst3-midi-module-global test-coremidi test-alsamidi test-alsaump test-winmidi test-winump --summary all` | Passed: 47/47 build steps and 54/54 tests |
| `scripts/test_installed_package.sh --optimize=Debug` | Passed: 18/18 build steps and 96/96 downstream tests across effect, instrument, core, DSP fixture, and C kernel consumers |
| `for repetition in {1..16}; do zig build --cache-dir /private/tmp/zig-vst3-midi-module-local --global-cache-dir /private/tmp/zig-vst3-midi-module-global test-midi-thread-sanitizers --summary none \|\| exit; done` | Passed: 16/16 aggregate repetitions, 80 sanitizer process runs, and 144 selected tests |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,524 lines classified |

The `6f32eea0` repository gate was stopped with exit 130 after this deterministic
installed-consumer failure. It is not Phase 1 completion evidence.

## 2026-08-14: LV2 UI Lifecycle Accounting

Candidate commit: `8d93103a8c3ade237c469b965ab1c15270ae01f0`

The fresh-cache exact Phase 1 gate completed 431/433 build steps. It passed
7,455/7,460 tests, with four explicit skips and one failure. The failure was
`LV2 UI adapter bridges lifecycle automation touch idle and resize`: the fake
host reported two subscriptions where the later scenario expected one.

The same test first constructs an editor that subscribes during creation and
unsubscribes during cleanup. It then reuses the fake host for an independent
subscription scenario, but its cumulative counters were not verified or reset
between the two. Production code made the expected matched host calls. The
test's later absolute count was stale.

Commit `719e82da` asserts that the lifecycle probe made exactly one subscribe
and one unsubscribe call, resets those observations, and preserves the later
scenario's independent absolute assertions. It also adds a named
`test-lv2-ui-adapter` gate so this integrated adapter coverage can be selected
without the complete plugin test root.

| Check | Result |
| --- | --- |
| Exact `zig build test --summary all` at `8d93103a` with fresh caches | Failed as valid baseline evidence: 431/433 steps succeeded and 7,455/7,460 tests passed, with four skips and the one stale LV2 UI host-count assertion |
| `zig build test-vst3-module --summary all` after the repair | Passed: 7/7 steps and 788/788 tests |
| `zig build test-lv2-ui-adapter --summary all` after the repair | Passed: 9/9 steps; the filtered LV2 UI adapter test and its native VSTGUI dependency succeeded |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,549 lines classified |

The first sandboxed focused attempt failed during `translate-c` with
`manifest_create PermissionDenied`. The equivalent run with normal compiler
cache access passed. This was an environment failure, not a test failure.

## 2026-08-14: ARA Audio Reader Lifetime Gate

Change commit: `bbbfb882`

The continuing Q02 audit found that `openAudioReader` required the host create
callback but not the matching destroy callback. A malformed callback table
could therefore return a foreign reader that the controller could not release.
The same slot used separate closing and active-read atomics. A close could see
zero active reads and destroy the foreign reader before a thread that had
already observed the old open flag incremented its count. Because close later
reopened the flag, that thread's second check did not reliably reject the stale
admission.

The slot now stores a closed bit and lease count in one atomic word. Opening
publishes the complete slot with release order. Admission increments only while
that same word is open and acquires the published state. Close atomically sets
the closed bit, drains all release-published leases with acquire order, destroys
the foreign reader, and leaves the vacant slot closed. Creation requires the
host create, read, and destroy callbacks before invoking any of them.

The exact gate at `3790e177` was stopped intentionally with exit 130 after this
audit invalidated the candidate. Before interruption it passed the inventory,
codec probes, native VSTGUI visual dependency, and VSTGUI TSan runner. It is
partial baseline evidence only.

| Check | Result |
| --- | --- |
| `zig build test-ara-native test-phase2-thread-sanitizers --summary all` | Passed: 36/36 steps and 438/438 tests, including 14 TSan-selected tests |
| `zig build test-ara --summary all` | Passed: 77/77 steps and 424/424 tests across Debug native behavior, ReleaseSafe Linux and Windows cross-builds, and the ARA VST3 ABI fixture |
| `for repetition in {1..16}; do zig build test-phase2-thread-sanitizers --summary none \|\| exit 1; done` | Passed: 16/16 repetitions, 48 sanitizer process runs, and 224 selected tests |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,606 lines classified |

## 2026-08-14: CoreAudio Callback Admission Gate

Change commit: `4283284e`

The exact Phase 1 gate at `dee0da68` was stopped intentionally with exit 130
after the continuing atomic review invalidated the candidate. Before the stop,
it passed the repository script checks, codec and DSP reference checks, native
VSTGUI checks, downstream consumers, and the installed-package matrix. The
installed-package selection passed 18/18 steps and 96/96 tests. This run is
partial baseline evidence only.

CoreAudio session and topology callbacks used separate closure and active-count
atomics. A callback could read the old open flag, teardown could close and
observe zero, and the callback could increment after the drain. Commit
`4283284e` replaces both fields with one closed-bit/count word. Admission and
closure now conflict on one atomic modification order. The regression preserves
a stale pre-closure observation, closes the gate, and verifies that the stale
admission CAS cannot succeed.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-coreaudio-gate-local --global-cache-dir /private/tmp/zig-vst3-coreaudio-gate-global test-coreaudio --summary all` | Passed: 9/9 steps and 10/11 tests; the native device-discovery branch skipped because it depends on available hardware |
| Sixteen repeated `test-coreaudio` runs using the same caches | Passed: 16/16 repetitions, including the focused native TSan callback-drain selection |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,605 lines classified |

## 2026-08-14: Realtime Topology Mutation Gate

Change commits: `244e1ae6`, `c4aeda04`, `13b28faf`

The exact Phase 1 gate at `7b2f2882` was stopped intentionally with exit 130
after the continuing realtime call-graph audit invalidated the candidate. It
passed the initial repository scans, VSTGUI build-mode checks, native visual
dependency checks, and autonomous wrapper before the stop. The installed
package and repository-root selections had started but did not complete, so
this run is partial baseline evidence only.

`HostRequestSink.dispatchPending` already rejected realtime use, but the three
public dynamic-topology mutation methods did not. The VST3 component bindings
behind those methods take the audio-topology mutex. Processor code retaining
the sink could therefore perform an unbounded wait on the audio thread without
the realtime audit reporting it.

Commit `244e1ae6` classifies each mutation as a lock operation before invoking
its component binding and documents the non-realtime control-thread contract.
The regression enters a realtime scope, verifies that all three calls fail
without reaching their callbacks, and then verifies that the same calls still
succeed outside that scope.

The next exact gate at `8c82ba27` was stopped intentionally with exit 130 when
the continuing audit found that the documented raw `SimpleEffect` snapshot and
mutation functions reached the same topology mutex without passing through the
guarded sink. Before the stop, the candidate passed the repository scans,
native visual checks, codec interoperability probes, downstream consumers, and
the installed-package runner reached by the gate. This is partial baseline
evidence only.

Commit `c4aeda04` applies the audit guard at all four raw entry points. Its
integration regression verifies that the snapshot and three mutations record
four lock violations without touching topology state in a realtime scope.
Normal control-thread topology publication and processing behavior continue in
the same test.

The exact gate at `b467ff83` was stopped intentionally with exit 130 when the
lower-boundary review found that raw `SimpleEffect.dispatchHostRequests` still
bypassed the sink's host-call guard. The run had reached initial repository and
dependency preparation checks only, so it is partial baseline evidence.
Commit `13b28faf` guards the shared dispatch implementation before it swaps
pending bits, locks the connection peer, or invokes the host. The regression
verifies rejection, one recorded host-call violation, no callback delivery,
and successful later delivery of the preserved pending request.

| Check | Result |
| --- | --- |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter "host request"` | Passed: 9/9 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-host-request-local --global-cache-dir /private/tmp/zig-vst3-host-request-global test-vst3-module --summary all` | Passed before the raw API refinement: 7/7 steps and 788/788 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-raw-topology-local --global-cache-dir /private/tmp/zig-vst3-raw-topology-global test-vst3-module --summary all` | Passed after the raw API refinement: 7/7 steps and 788/788 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-raw-dispatch-local --global-cache-dir /private/tmp/zig-vst3-raw-dispatch-global test-vst3-module --summary all` | Passed after the raw dispatch refinement: 7/7 steps and 788/788 tests |
| `scripts/check_quality_inventory.sh` before the raw API refinement | Passed: 812 files and 467,679 lines classified |
| `scripts/check_quality_inventory.sh` after the raw API refinement | Passed: 812 files and 467,705 lines classified |
| `scripts/check_quality_inventory.sh` after the raw dispatch refinement | Passed: 812 files and 467,719 lines classified |

## 2026-08-14: VST3 Host Thread Contracts

Change commit: `5b0f9271`

The lower-boundary review identified four public raw operations with explicit
non-audio-thread contracts in the pinned VST3 interfaces. Channel-context and
automation-state delegation require the UI thread. Data-exchange queue open and
close require the main thread while the component is inactive. None recorded a
realtime violation before delegating to the host.

The block lifecycle differs intentionally. `IDataExchangeHandler.lockBlock`
and `freeBlock` are specified for use inside `IAudioProcessor::process`, so the
fix must not classify those host calls as forbidden. Commit `5b0f9271` guards
only the four control-thread operations. The combined host regression verifies
four rejections without callback delivery, deterministic invalid queue output,
successful control-thread delegation, and clean block lock and free within a
realtime audit scope.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-host-thread-contract-local --global-cache-dir /private/tmp/zig-vst3-host-thread-contract-global test-vst3-module --summary all` | Passed: 7/7 steps and 788/788 tests |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,772 lines classified |

## 2026-08-14: Phase 1 Completion Gate

Completion candidate: `db511c18`

The first fresh-cache attempt exhausted the shared temporary volume. LLVM,
Zig cache manifests, fixture runners, and temporary-file creation all reported
`NoSpaceLeft`. This was an environment failure rather than code evidence.
Removing only disposable quality-program caches recovered about 12 GiB; the
tracked worktree remained clean.

The same exact commit then passed the complete release-equivalent repository
gate from new local and global cache directories. The long Debug section was
active ADM XML validation work at full CPU utilization, not a deadlock. The
final installed-package selection passed all 18 build steps and 96 tests,
including effect, instrument, core, DSP fixture, and C-kernel consumers. The
preceding gate stages also passed repository hygiene and inventory checks,
native visual and VSTGUI checks, codec interoperability, sanitizer runners,
downstream consumers, and release fixtures.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-phase1-db511-rerun-local --global-cache-dir /private/tmp/zig-vst3-phase1-db511-rerun-global test --summary all` | Passed at `db511c18`; final selection 18/18 steps and 96/96 tests, with all earlier gate stages successful |
| `scripts/check_quality_inventory.sh` | Passed before the gate: 812 files and 467,772 lines classified |

Phase 1 is complete at `db511c18`. Every production review unit has a recorded
ownership disposition, high-risk owning paths have focused allocation or
lifecycle evidence, relevant Debug allocator and native sanitizer suites pass,
and no critical or high memory-safety finding remains open.

## 2026-08-14: Realtime Resource Control Gate

Change commit: `3491f3b9`

Resource job, recovery, and decoded-audio importer methods recorded forbidden
locks only after entering helpers that still acquired the mutex. Waiting could
also join a worker from processing. Resource Swap published a new request
generation before its job rejected realtime allocation, while Fixed Rate could
publish latency and mark a pending restart before host dispatch rejected the
call.

The public control boundaries now reject Debug and test realtime scopes first.
Snapshot APIs return valid inert values, copy APIs leave caller output intact,
state readers do not consume input, and request APIs do not advance generations
or alter desired mode, latency, or pending host work. Resource exchange adoption,
active access, and block-boundary retirement remain the bounded realtime
surface. Teardown retains its explicit post-processing lifecycle precondition.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-rt-resource-local --global-cache-dir /private/tmp/zig-vst3-rt-resource-global test-resource-ownership --summary all` | Passed: 3/3 steps and 50/50 tests |
| `zig test --cache-dir /private/tmp/zig-vst3-rt-importer-local --global-cache-dir /private/tmp/zig-vst3-rt-importer-global -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'decoded importer'` | Passed: 9/9 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-rt-examples-local --global-cache-dir /private/tmp/zig-vst3-rt-examples-global test-example-ownership --summary all` | Passed outside the restricted sandbox after its `translate-c` child was denied cache access: 17/17 steps and 46/46 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-rt003-vst3-local --global-cache-dir /private/tmp/zig-vst3-rt003-vst3-global test-vst3-module --summary all` | Passed outside the restricted sandbox after the same cache denial: 7/7 steps and 788/788 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-rt003-tsan-local --global-cache-dir /private/tmp/zig-vst3-rt003-tsan-global test-resource-thread-sanitizer --summary all` | Passed: 3/3 steps and 58/58 tests under ThreadSanitizer |
| `scripts/check_quality_inventory.sh` | Passed: 812 files and 467,993 lines classified |

## 2026-08-14: Checked Concurrency Inventory

Change commit: `c53790f1`

The Phase 2 inventory classifies every tracked source file selected by the
repository's synchronization-primitive scan. It records publication and
memory-order contracts, teardown order, the permitted realtime surface, and an
exact appendix of 81 reviewed source paths. The repository gate fails when a
matching path is missing or when the record retains a stale path.

| Check | Result |
| --- | --- |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 81 source files classified |
| `scripts/test_quality_concurrency_inventory_runner.sh` | Passed: baseline, missing-path rejection, and stale-path rejection |
| `bash -n scripts/check_quality_concurrency_inventory.sh scripts/test_quality_concurrency_inventory_runner.sh` | Passed |
| `zig fmt --check build.zig` | Passed |
| `scripts/check_quality_inventory.sh` | Passed at the inventory commit: 814 files and 468,112 lines classified |
| `git diff --check` | Passed |

## 2026-08-14: Saturated COM Reference Counts

Change commit: `1f684081`

ThreadSanitizer coverage commit: `294ea628`

The shared dynamic reference-count increment saturated at `u32` maximum, but
the release path could decrement that sentinel. Once another `addRef` had been
accepted without a representable increment, the stored count no longer
covered every live holder. Enough later releases could therefore reach zero
while a holder remained. The static singleton release helpers shared the
unstable sentinel behavior, although those objects do not own dynamic storage.

Maximum count is now a permanent pinned state. Dynamic objects deliberately
leak after saturation instead of risking premature destruction. Tests exercise
the helper state and the complete `release` path, including a destroy callback
that must remain uncalled. The two concurrent refcount stress tests are also
part of the maintained aggregate Phase 2 ThreadSanitizer gate.

| Check | Result |
| --- | --- |
| `zig test --cache-dir /private/tmp/zig-vst3-refcount-funknown-local --global-cache-dir /private/tmp/zig-vst3-refcount-funknown-global -Mroot=zig-vst3/src/funknown.zig` | Passed: 16/16 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-refcount-vst3-local --global-cache-dir /private/tmp/zig-vst3-refcount-vst3-global test-vst3-module --summary all` | Passed outside the restricted sandbox after its `translate-c` child was denied cache access: 7/7 steps and 791/791 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-refcount-phase2-tsan-local --global-cache-dir /private/tmp/zig-vst3-refcount-phase2-tsan-global test-phase2-thread-sanitizers --summary all` | Passed outside the restricted sandbox after the same cache denial: 10/10 steps and 16/16 tests under ThreadSanitizer |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 81 source files classified |
| `scripts/check_quality_inventory.sh` | Passed: 814 files and 468,186 lines classified |
| `zig fmt --check build.zig zig-vst3/src/funknown.zig zig-vst3/src/factory.zig zig-vst3/src/vst_plugin_compatibility.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: Saturated GUI Editor Activity

Change commit: `e4b627a5`

The GUI telemetry activity count rejected wraparound at `usize` maximum, but a
close immediately decremented that saturated state. Opens accepted after
saturation could not be represented, so the count could eventually reach zero
while an editor remained. That would incorrectly disable editor-only analysis.

Maximum activity is now a permanent active sentinel. The focused regression
checks the sentinel directly, and an eight-thread stress test performs 160,000
matched open-close pairs. The concurrent regression is part of the maintained
Phase 2 ThreadSanitizer aggregate.

| Check | Result |
| --- | --- |
| `zig test --cache-dir /private/tmp/zig-vst3-editor-activity-local --global-cache-dir /private/tmp/zig-vst3-editor-activity-global -Mroot=zig-vst3-plugin/src/gui_telemetry.zig` | Passed: 19/19 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-editor-activity-tsan-local --global-cache-dir /private/tmp/zig-vst3-editor-activity-tsan-global test-phase2-thread-sanitizers --summary all` | Passed outside the restricted sandbox: 10/10 steps and 17/17 tests under ThreadSanitizer |
| `zig build --cache-dir /private/tmp/zig-vst3-editor-activity-vst3-local --global-cache-dir /private/tmp/zig-vst3-editor-activity-vst3-global test-vst3-module --summary all` | Passed outside the restricted sandbox: 7/7 steps and 791/791 tests |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 81 source files classified |
| `scripts/check_quality_inventory.sh` | Passed: 814 files and 468,211 lines classified |
| `zig fmt --check build.zig zig-vst3-plugin/src/gui_telemetry.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: Resource Worker Handle Handoff

Change commit: `1ef12711`

Resource submission checked `worker_running` and reaped before taking the job
mutex. The current worker could publish stopped after that check but before
submit acquired the mutex. The submit path then observed no running worker and
assigned a newly spawned handle over the old joinable handle without joining
it. Repetition could exhaust native thread resources.

The worker now retains running ownership through result disposal and one final
mutex-protected queued-work check. A submit that encounters a stopped worker
joins it before assigning a replacement handle. The regression holds the old
worker after stopped publication but before return, enters the post-reap submit
path, and verifies that the second worker neither starts nor returns from submit
until the old worker is allowed to return and the join completes.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-job-handoff-v2-local --global-cache-dir /private/tmp/zig-vst3-job-handoff-v2-global test-resource-ownership --summary all` | Passed: 3/3 steps and 51/51 tests |
| `zig build --cache-dir /private/tmp/zig-vst3-job-handoff-v2-tsan-local --global-cache-dir /private/tmp/zig-vst3-job-handoff-v2-tsan-global test-resource-thread-sanitizer --summary all` | Passed: 3/3 steps and 59/59 tests under ThreadSanitizer |
| `zig build --cache-dir /private/tmp/zig-vst3-job-handoff-examples-local --global-cache-dir /private/tmp/zig-vst3-job-handoff-examples-global test-example-ownership --summary all` | Passed outside the restricted sandbox: 17/17 steps and 46/46 tests |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 81 source files classified |
| `scripts/check_quality_inventory.sh` | Passed: 814 files and 468,305 lines classified |
| `zig fmt --check zig-vst3-plugin/src/resource/job.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: Checked Atomic-Order Ledger

Change commit: `598dbb6f`

The atomic-order ledger records per-source lexical counts for every explicit
Zig unordered, monotonic, acquire, release, acquire-release, and sequentially
consistent order in the checked concurrency inventory. Its family-level
semantic justifications remain in `concurrency.md`. The ledger is deliberately
mechanical evidence: a count change fails the repository gate and requires the
semantic review record to be revisited.

| Check | Result |
| --- | --- |
| `scripts/check_quality_atomic_orders.sh` | Passed: 57 source files tracked |
| `scripts/test_quality_atomic_orders_runner.sh` | Passed: baseline and changed-count rejection |
| `bash -n scripts/check_quality_atomic_orders.sh scripts/test_quality_atomic_orders_runner.sh` | Passed |
| `scripts/test_quality_concurrency_inventory_runner.sh` | Passed: 81 source files classified plus missing-path and stale-path rejection |
| `scripts/check_quality_inventory.sh` | Passed: 816 files and 468,418 lines classified |
| `zig fmt --check build.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: VST3 Realtime Bounds and Transitive Call Chains

Behavior commit: `10ea05e6`

The VST3 adapter now retains the maximum block from successful preparation and
rejects a negative or oversized block before it traverses host input or invokes
the processor. Parameter queue visits, parameter point attempts, and event
attempts are independently capped at 64. Invalid host entries consume those
budgets, so a large invalid host count cannot create unbounded callback work.

The maintained realtime record maps the transitive helper chains for all 26
production example processors. It distinguishes host-negotiated block bounds
from fixed internal limits, records shared-state operations and failure paths,
and is checked against both the direct source audit and source discovery.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-vst3-rt-limits-local --global-cache-dir /private/tmp/zig-vst3-vst3-rt-limits-global test-vst3-module --summary all` | Passed: 7/7 steps and 792/792 tests |
| `scripts/check_realtime_source_inventory.sh` | Passed: 26 processor files audited and documented |
| `scripts/test_realtime_source_inventory_runner.sh` | Passed: missing audit and missing contract entries rejected |
| `scripts/check_quality_inventory.sh` | Passed: 820 files and 468,867 lines classified |
| `scripts/test_quality_inventory_runner.sh` | Passed |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 82 source files classified |
| `scripts/test_quality_concurrency_inventory_runner.sh` | Passed |
| `scripts/check_quality_atomic_orders.sh` | Passed: 57 Zig and 11 native source files tracked |
| `scripts/test_quality_atomic_orders_runner.sh` | Passed |
| `bash -n scripts/check_realtime_source_inventory.sh scripts/test_realtime_source_inventory_runner.sh` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: Realtime Source Audit Coverage

Change commit: `59bced5d`

The realtime source audit previously listed 18 processors manually and
recognized only the basic process callback forms. It omitted eight production
processor files and the public parameter-view entry forms. The audit now
covers all 26 example processor files discovered from six public process entry
forms. A checked inventory keeps that source list exact, rejects duplicates,
and includes a negative fixture that removes one path and requires rejection.

This is direct callback-body evidence. It does not replace the semantic review
of transitive helper calls or the bounded-work record required to complete
Phase 2.

| Check | Result |
| --- | --- |
| `scripts/check_realtime_source_inventory.sh` | Passed: 26 processor files audited |
| `scripts/test_realtime_source_inventory_runner.sh` | Passed: baseline and missing-processor rejection |
| `zig test --cache-dir /private/tmp/zig-vst3-realtime-source-expanded-v3-local --global-cache-dir /private/tmp/zig-vst3-realtime-source-expanded-v3-global -Mroot=examples/realtime_source_audit.zig` | Passed: 1/1 test |
| `scripts/check_quality_inventory.sh` | Passed: 818 files and 468,496 lines classified |
| `scripts/check_quality_atomic_orders.sh` | Passed: 57 source files tracked |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 81 source files classified |
| `bash -n scripts/check_realtime_source_inventory.sh scripts/test_realtime_source_inventory_runner.sh` | Passed |
| `zig fmt --check build.zig examples/realtime_source_audit.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-14: Native Atomic-Order Ledger

Change commit: `a2e87365`

The checked order-token ledger now covers explicit C and C++ memory orders in
the native sources selected by the concurrency inventory. The native table
tracks relaxed, consume, acquire, release, acquire-release, and sequentially
consistent tokens separately from Zig orders. Its fixture mutates a native
count independently of the existing Zig mutation.

| Check | Result |
| --- | --- |
| `scripts/check_quality_atomic_orders.sh` | Passed after Q-CONC-010: 57 Zig and 11 native source files tracked |
| `scripts/test_quality_atomic_orders_runner.sh` | Passed: changed Zig and changed native counts rejected |
| `bash -n scripts/check_quality_atomic_orders.sh scripts/test_quality_atomic_orders_runner.sh` | Passed |
| `scripts/check_quality_concurrency_inventory.sh` | Passed after Q-CONC-010: 82 source files classified |
| `scripts/check_quality_inventory.sh` | Passed after Q-CONC-010: 820 files and 468,716 lines classified |
| `git diff --check` | Passed |

## 2026-08-14: Windows UMP Callback Reference Count

Behavior commit: `71b7c997`

Sanitizer portability commits: `01df6b3b`, `4750d23d`

The Windows UMP receive callback used wrapping COM reference increments and
decrements. It now delegates to a portable pinned counter. Maximum count is a
permanent sentinel, so an unrepresentable reference cannot be followed by a
decrement toward deletion. The regression checks ordinary destruction,
deterministic saturation, stable release after saturation, and 160,000 matched
concurrent add-release pairs while retaining one owner.

The host gate runs the concurrent primitive under ThreadSanitizer on macOS and
Linux. Windows uses full C and C++ sanitizer instrumentation because Zig does
not provide ThreadSanitizer there. CI run `31847011935` failed in the first new
Windows UMP step with the unconditional ThreadSanitizer configuration. Commit
`01df6b3b` selects the supported sanitizer set. Commit `4750d23d` keeps the
portable libc++ stress executable on TSan-capable hosts while Windows compiles
and executes the actual SDK-backed module. GitHub Actions run `31848681596`,
Windows job `94920244792`, passed the native UMP step.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-winump-refcount-tsan-local --global-cache-dir /private/tmp/zig-vst3-winump-refcount-tsan-global test-winump --summary all` | Passed: 7/7 steps and 4/4 tests; portable concurrent refcount ran under ThreadSanitizer, and Windows GNU fallback tests cross-built |
| `scripts/check_quality_atomic_orders.sh` | Passed: 57 Zig and 11 native source files tracked |
| `scripts/test_quality_atomic_orders_runner.sh` | Passed |
| `scripts/check_quality_concurrency_inventory.sh` | Passed: 82 source files classified |
| `scripts/test_quality_concurrency_inventory_runner.sh` | Passed |
| `scripts/test_quality_inventory_runner.sh` | Passed with native-header and native-atomic assertions |
| `scripts/check_quality_inventory.sh` | Passed: 820 files and 468,716 lines classified |
| `zig fmt --check build.zig` | Passed |
| `git diff --check` | Passed |
| GitHub Actions run `31848681596`, Windows job `94920244792`, `Test Windows UMP bridge` | Passed: native Windows SDK-backed module compiled and executed |

## 2026-08-14: Phase 2 Teardown and Callback Overlap

Importer TSan commit: `256087f4`

VSTGUI runner commit: `8f5f1154`

The teardown audit maps every asynchronous publication family to its closure
order, deterministic overlap regression, and sanitizer evidence. Decoded-audio
importer cancellation and worker join now run inside the resource TSan gate.
The VSTGUI TSan runner now treats any metadata or status write failure as a
failed verification run. Its negative fixture recreates the missing-artifact
condition without exhausting the disk.

The first attempt ran three new TSan compilations concurrently with separate
global caches. It exhausted `/private/tmp`; Zig reported `NoSpaceLeft`, and the
VSTGUI runner exposed Q-VER-006. Removing only regenerable repository and test
caches recovered space. Sequential reruns shared one global cache and passed.

| Check | Result |
| --- | --- |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-phase2-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-phase2-thread-sanitizers --summary all` | Passed outside the restricted sandbox: 10/10 steps and 17/17 tests |
| Sixteen repeated aggregate Phase 2 TSan runs | Passed: 16/16 repetitions, 64 sanitizer processes, and 272 selected tests |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-midi-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-midi-thread-sanitizers --summary all` | Passed: 11/11 steps and 9/9 tests |
| Sixteen repeated native MIDI TSan runs | Passed: 16/16 repetitions, 80 sanitizer processes, and 144 selected tests |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-resource-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-resource-thread-sanitizer --summary all` | Passed: 5/5 steps and 60/60 tests |
| Eight repeated resource and importer TSan runs | Passed: 8/8 repetitions, 16 sanitizer processes, and 480 selected tests |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-dsp-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-dsp-thread-sanitizer --summary all` | Passed: 5/5 steps and 149/149 tests |
| Eight repeated DSP, HRTF, and snapshot TSan runs | Passed: 8/8 repetitions, 16 sanitizer processes, and 1,192 selected tests |
| `VSTGUI_THREAD_SANITIZER_REPETITIONS=4 VSTGUI_THREAD_SANITIZER_OUTPUT_DIR=/private/tmp/zig-vst3-teardown-vstgui-artifacts scripts/test_vstgui_thread_sanitizer.sh` | Passed: 4/4 process runs with complete evidence artifacts |
| `scripts/test_vstgui_thread_sanitizer_runner.sh` | Passed: success, test failure, interruption, invalid configuration, owned-build cleanup, and artifact-write failure cases |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-coreaudio-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-coreaudio --summary all` | Passed outside the restricted sandbox: 9/9 steps and 10/11 tests; one hardware-dependent discovery test skipped |
| `zig build --cache-dir /private/tmp/zig-vst3-teardown-examples-local --global-cache-dir /private/tmp/zig-vst3-teardown-shared-global test-example-ownership --summary all` | Passed outside the restricted sandbox: 17/17 steps and 46/46 tests |

## 2026-08-14: First Phase 2 Completion Candidate

Candidate commit: `daa6589cb2594b14474f461e8707593a9e7250dd`

GitHub Actions run `31850045681` tested the pull request merge of the candidate
into unchanged `main`. Its macOS job `94924059503` rejected the candidate. The
main Debug group found that the preliminary LV2 UI lifecycle probe incremented
`Backend.create_count` without resetting it before the independent scenario.
Both realtime inventory commands also failed because the current macOS image
does not provide the undeclared `rg` executable.

The same job reported `SIGSEGV` from six native callback test executables after
restoring a Zig cache: CoreMIDI, CoreAudio, ALSA MIDI, ALSA UMP, Windows MIDI,
and the portable Windows UMP reference-count test. A fresh-cache local run of
those exact six build gates passed 58/58 steps and 64/65 tests, with one
hardware-dependent CoreAudio skip. This narrows the public failure but does not
close Q-VER-008. The replacement public macOS run must execute without restored
Zig artifacts.

The local full gate at the same candidate had passed the repository scripts,
codec and DSP probes, downstream consumers, installed-package matrix, native
VSTGUI checks, and other earlier leaves. Its 1,800-test Debug executable was
still CPU-bound after 48 minutes when the public failures invalidated the
candidate. The obsolete local run was stopped before editing the replacement.

Correction commit: `a79b294a7ad2d55f1ab8b7bff2e0a966f6a3c47c`

| Check | Result |
| --- | --- |
| `scripts/test_realtime_source_inventory_runner.sh` | Passed: baseline, missing processor, and missing contract path |
| `bash -n scripts/check_realtime_source_inventory.sh scripts/test_realtime_source_inventory_runner.sh` | Passed |
| Fresh-cache `zig build test-lv2-ui-adapter --summary all` | Passed outside the restricted sandbox: 9/9 steps |
| Fresh-cache `zig build test-coremidi test-coreaudio test-alsamidi test-alsaump test-winmidi test-winump --summary all` | Passed outside the restricted sandbox: 58/58 steps and 64/65 tests; one hardware-dependent CoreAudio test skipped |
| `scripts/check_quality_inventory.sh` | Passed: 820 files and 468,924 lines classified |
| `zig fmt --check zig-vst3-plugin/src/lv2_ui.zig` | Passed |
| `git diff --check` | Passed |
| GitHub Actions run `31854031396` | Superseded by the evidence-only `eb1b232f` commit and run `31854142882` |

## 2026-08-15: Uncached macOS 26 Sanitizer Reproduction

Candidate commit: `eb1b232f675be17c7c982dfae2cecf528c1c2b9d`

The exact local Phase 2 completion gate passed from its dedicated caches: all
441 build steps completed, 7,506 of 7,510 tests passed, and four tests skipped.
The main Debug group passed 1,798 tests and skipped two. The six native backend
gates, repository scripts, downstream consumers, and installed-package matrix
all passed.

GitHub Actions run `31854142882` tested the pull request merge into unchanged
`main`. Repository hygiene and Windows job `94935626486` passed. The uncached
macOS job `94935626446` used the `macos-26-arm64` image on macOS 26.5.2 and
reproduced seven `SIGSEGV` failures. The failed artifacts were the CoreAudio,
CoreMIDI, ALSA MIDI, ALSA UMP, and Windows MIDI ThreadSanitizer tests, the
shared native callback-gate ThreadSanitizer test, and the portable Windows UMP
ThreadSanitizer executable. The remaining 7,495 tests passed and four skipped.

This result rejects restored cache corruption as the cause and isolates the
failure to ThreadSanitizer execution on the moving `macos-latest` image. The
same artifacts pass on local macOS 15.4. GitHub moved `macos-latest` from macOS
15 to macOS 26 in June and July 2026 and lists `macos-15` as a maintained ARM
runner label. The workflow now pins every macOS job to that stable image. A
fresh public run must pass before Q-VER-008 or Phase 2 closes.

## 2026-08-15: Bounded Standard MIDI File Parsing

Behavior commit: `43b6c79b`

Q-MIDI-001 was reproduced at `4466af3d` by checking the new measurement tool
out in a detached worktree, compiling it against that commit's plugin core,
and running it in report-only mode:

```text
zig build-exe -OReleaseSafe --cache-dir /private/tmp/zig-vst3-midi-baseline-local --global-cache-dir /private/tmp/zig-vst3-midi-benchmark-global --dep zig-vst3-plugin-core -Mroot=tools/midi_file_complexity.zig -Mzig-vst3-plugin-core=zig-vst3-plugin/src/core.zig -lc -femit-bin=/private/tmp/zig-vst3-midi-baseline/midi-file-complexity
/private/tmp/zig-vst3-midi-baseline/midi-file-complexity --report-only
```

| Events | Parse ns/event | Traversal ns/event |
| ---: | ---: | ---: |
| 1,000 | 2,889.72 | 2,895.45 |
| 2,000 | 5,766.12 | 5,796.50 |
| 4,000 | 11,513.72 | 11,556.36 |

Doubling the event count doubled the old per-event cost, which confirms
quadratic total work. Commit `43b6c79b` carries a validated iterator witness,
so ordinary traversal parses each event once. If public cursor state changes,
validation falls back to canonical prefix replay bounded by the track event
limit. Parsing now enforces independently configurable file, track,
track-count, per-track event, total-event, and event-payload limits.

The checked benchmark uses a 2,000 ns/event ceiling and rejects per-event
growth above 1.75 times between adjacent sizes. Both supported safety-oriented
optimization modes passed:

| Command and mode | 1,000 events | 2,000 events | 4,000 events |
| --- | --- | --- | --- |
| `zig build benchmark-midi-file-parser -Doptimize=Debug --summary all` | parse 118.71, traversal 106.27 ns/event | parse 116.28, traversal 122.54 ns/event | parse 117.16, traversal 110.55 ns/event |
| `zig build benchmark-midi-file-parser -Doptimize=ReleaseSafe --summary all` | parse 15.89, traversal 18.47 ns/event | parse 24.12, traversal 16.45 ns/event | parse 15.66, traversal 15.66 ns/event |

The native fuzz target uses two valid seeds plus arbitrary generation,
mutation, truncation, and extension. Accepted inputs must revalidate, expose
every declared track, terminate every iterator, and stay within the total
event limit.

| Check | Result |
| --- | --- |
| `zig build test-midi-file-fuzz --summary all` | Passed: 3/3 steps and 7/7 selected tests |
| `zig build test-midi-file-fuzz --fuzz=100K` | Passed: 100,319 executions, 317 unique runs, and 283 of 21,615 instrumented branches covered without a failure |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'MIDI file'` | Passed: 17/17 tests |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'MIDI track'` | Passed: 8/8 tests |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 downstream tests |
| `zig build test-plugin-core-builds --summary all` | Passed: 2/2 steps, including ReleaseSafe Windows compilation |
| `scripts/check_quality_inventory.sh` | Passed: 821 files and 469,425 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: ARA Analysis Cohesion Closure

Behavior commit: `e3be67c7`

ARA detector families now live in focused tuning, tempo and meter, harmony,
and polyphonic-note modules. They share passive configurations, results, and
limits through `ara_analysis_model.zig`, plus bounded search, correlation,
and tempo-map validation through `ara_analysis_common.zig`.

`ara_tuning_analysis.zig` remains the public facade and owns per-source
analysis state, requests, content publication, invalidation, and archive
persistence. Public configuration and limit types are exact aliases with an
explicit identity regression. The cohesion ledger classifies the remaining
facade as `KEEP` at 2,508 production and 3,054 test lines.

| Check | Result |
| --- | --- |
| `zig build test-ara --summary all` | Passed: 77/77 steps and 445/445 tests, including ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-ara-archive-fuzz --fuzz=100K` | Passed: 100,051 executions and 47 unique inputs without a failure |
| `scripts/test_installed_package.sh` | Passed: 18/18 steps and 96/96 tests |
| Cohesion inventory and fixture | Passed: 33 large handwritten sources classified |
| Quality and concurrency inventories | Passed: 858 files and 477,391 lines classified; 86 concurrency sources classified |
| Production termination scan and fixture | Passed |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: VST3 Effect Cohesion Closure

Behavior commit: `d37f5b51`

Reflected edit-controller construction now lives in
`zig_vst3_edit_controller.zig`. Shared COM query, retain, replacement, and
release operations live in `effect_support.zig`, so controller and component
lifecycles use the same ownership rules without importing each other.

`zig_vst3_plugin_effect.zig` remains the public facade and owns processor and
component construction. `ParameterObserver` and `ReflectedEditController` are
exact aliases, with an explicit type-identity regression. The cohesion ledger
classifies the remaining facade as `KEEP` at 2,015 production and 2,767 test
lines.

| Check | Result |
| --- | --- |
| `zig build test-vst3-module --summary all` | Passed: 7/7 steps and 796/796 tests |
| ReleaseSafe gain bundle cross-builds | Passed: Linux x86-64 and Windows x86-64 |
| `scripts/test_installed_package.sh` | Passed: 18/18 steps and 96/96 tests |
| Cohesion inventory and fixture | Passed: 33 large handwritten sources classified |
| Quality and concurrency inventories | Passed: 852 files and 477,231 lines classified; 86 concurrency sources classified |
| Production termination scan and fixture | Passed |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: MP3 Table Provenance and Integrity

Behavior commit: `6afb44b6`

The Layer III pair-code Huffman tables now identify ISO/IEC 11172-3:1993,
Annex B, Table 3-B.7. The reconstruction procedure enumerates each table by
number and each cell by `x * side + y`, retaining the published codeword length
and unsigned bits. The semantic serialization covers the table index, side,
`linbits`, entry length, and big-endian codeword value. Its SHA-256 is
`9fdeb0ca3c74ac54a8ee9154544e8dced73aef97837de1311572e75866de76ec`.

The synthesis window now identifies Annex B, Table 3-B.3. Reconstruction reads
all 512 `D[i]` coefficients in index order, multiplies each by 65,536, and
rounds to the nearest integer. The big-endian `i32` serialization has SHA-256
`e8d6792457f2a517d0e36a87d29f83610aa00d6cca6281f0b31802faa4b2ccf3`.
Both expected digests live outside the table source files.

| Check | Result |
| --- | --- |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 130/130 tests; native Debug execution plus ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'preserves the'` | Passed: 10/10 selected tests, including both complete table digests |
| One-bit mutation of table 1's first Huffman codeword | Rejected by the focused integrity test with the expected digest mismatch; restoring the bit returned the gate to 10/10 passing tests |
| `scripts/check_quality_inventory.sh` | Passed: 821 files and 469,478 lines classified |
| `zig fmt --check` over the three changed MP3 sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded ADM XML Validation

Behavior commits: `8f1d1750`, `4c34d23f`

The first complexity-gate execution already used fixed-storage ADM graph
indexes, but still used canonical prefix reconstruction in the underlying XML
event iterator. It measured 115,542,863 Debug ns per declaration/reference
pair at 128 pairs and failed the gate. This negative control isolated XML
retained-state replay as a separate quadratic cost.

Commit `8f1d1750` binds normal event traversal to the exact offset, open-element
stack, namespace slices, and borrowed source ranges produced by the preceding
successful step. Attribute traversal similarly binds its exact offset after
validating the complete source. A missing or inconsistent witness takes the
existing canonical reconstruction path. Iterator mutation tests exercise that
fallback and continue to require failure-atomic rejection.

Commit `4c34d23f` adds `AdmXmlLimits`, `default_adm_xml_limits`, and
`AdmXmlDocument.initWithLimits`. The policy independently bounds input bytes,
XML events, every retained metadata category, and graph-validation work. Exact
fixed-storage indexes replace nested scans for duplicate declarations,
reference resolution, cardinality, stream/track reciprocity, Matrix
coefficient targets, and per-channel block sequences. The parser remains
allocation-free and retains the selected limits with its borrowed document.

| Check | Result |
| --- | --- |
| `zig test -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'dsp.adm_xml' --test-filter 'dsp.xml'` | Passed: 110/110 tests, including hostile retained state, every explicit limit family, graph semantics, and the native fuzz corpus |
| `zig build test-adm-xml-fuzz --fuzz=100K` | Passed: 100,668 executions, 666 unique runs, and 968 of 24,354 instrumented branches covered without a failure |
| `zig build benchmark-adm-xml-parser -Doptimize=Debug --summary all` | Passed: 377,214.84, 373,128.91, and 373,533.20 ns per pair at 128, 256, and 512 pairs |
| `zig build benchmark-adm-xml-parser -Doptimize=ReleaseSafe --summary all` | Passed: 66,054.69, 65,943.36, and 67,976.56 ns per pair at 128, 256, and 512 pairs |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit boundary |
| `zig test -target x86_64-windows-gnu -OReleaseSafe -fno-emit-bin -Mroot=zig-vst3-plugin/src/core.zig --test-filter 'dsp.adm_xml' --test-filter 'dsp.xml'` | Passed: Windows x86-64 cross-compilation |
| `scripts/check_quality_inventory.sh` | Passed: 822 files and 470,254 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Phase 2 Completion Gate

Candidate commit: `4466af3de38733dbc549e4b92157949ea52d6e47`

GitHub Actions run `31858188014` completed successfully with all 19 jobs at the
exact candidate commit. The pinned `macos-15` build and test job passed the
complete suite, including the native ThreadSanitizer artifacts that had failed
on the moving macOS 26 image. The separate macOS pluginval job passed normal
validation and strictness 10. Windows and Ubuntu builds, raw ABI checks,
Steinberg validator jobs, Linux and Windows pluginval jobs, LV2 distribution,
and all configured cross-compilation targets also passed.

This public result closes Q-VER-008. Together with the checked concurrency and
realtime inventories, semantic atomic-order ledger, complete teardown matrix,
repeated sanitizer gates, and absence of open critical or high concurrency or
realtime findings, it satisfies every Phase 2 exit criterion.

| Check | Result |
| --- | --- |
| GitHub Actions run `31858188014` | Passed: 19/19 jobs at `4466af3d` |
| Build and test on `macos-15` | Passed: complete suite and native sanitizer gates |
| pluginval on `macos-15` | Passed: normal and strictness-10 validation |
| Build and test on Windows and Ubuntu | Passed |
| Steinberg validator on macOS, Windows, and Ubuntu | Passed |
| Raw API ABI on macOS, Windows, and Ubuntu | Passed |
| Cross-compilation and LV2 distribution jobs | Passed |

## 2026-08-15: Linear Retained Metadata Iteration

Behavior commit: `c62ad25e`

Vorbis-comment, FLAC-comment, ID3v2.3, ID3v2.4, RIFF INFO, and AIFF text
iterators previously reconstructed and parsed their complete retained prefix
before every item. Commit `c62ad25e` records the exact source range and cursor
state after initialization and every successful step. Ordinary traversal now
validates that witness in constant work. Missing or inconsistent witnesses
still use canonical reconstruction, preserving containment of caller-modified
public iterator state.

The checked benchmark constructs all six formats at 256, 512, and 1,024
entries. It rejects any family above 5,000 ns per entry and any 512- or
1,024-entry result above twice that family's 256-entry baseline. Each size is
measured three times and uses the minimum elapsed time to exclude scheduler
preemption without hiding repeatable work.

| Check | Result |
| --- | --- |
| `zig build benchmark-metadata-iterators -Doptimize=Debug --summary all` | Passed: maximum 157.04, 155.78, and 151.27 ns per entry at 256, 512, and 1,024 entries |
| `zig build benchmark-metadata-iterators -Doptimize=ReleaseSafe --summary all` | Passed: maximum 17.62, 17.71, and 18.20 ns per entry at 256, 512, and 1,024 entries |
| Focused metadata selection | Passed: 36/36 tests, including forced canonical fallback and hostile state |
| `zig build test-vorbis --summary all` | Passed: 10/10 steps and 92/92 tests, including Linux and Windows ReleaseSafe compilation plus Xiph, stb_vorbis, and Tremor source gates |
| Q12 FLAC, ID3, and audio-metadata selection | Passed: 59/59 tests |
| Windows x86-64 ReleaseSafe focused cross-compilation | Passed |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 470,770 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded iXML Parsing

Behavior commit: `c1e49fc0`

`requiredIxmlParseStorage` and `parseIxmlMetadata` now apply
`default_ixml_limits`. The corresponding `WithLimits` APIs accept a public
`IxmlLimits` policy for document bytes, conservative structural work, decoded
text, tracks, and sync points. The structural estimate reserves 128 operations
per input byte for fixed-depth analysis and materialization. Every count and
work rejection occurs during analysis, before caller storage is materialized.

The native fuzz target mixes arbitrary input with minimal and structured seed
documents, byte mutation, truncation, and extension. If requirements analysis
accepts a document, exact-size caller storage must materialize it successfully
under the same policy and reproduce the analyzed track and sync-point counts.

| Check | Result |
| --- | --- |
| Focused iXML selection | Passed: 19/19 tests, including every independent limit and failure-atomic storage checks |
| `zig build test-ixml-fuzz --fuzz=100K` | Passed: 100,528 executions, 526 unique runs, and 493 of 21,408 instrumented branches covered without a failure |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit APIs |
| Windows x86-64 ReleaseSafe iXML cross-compilation | Passed |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 470,985 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded MP3 Stream Parsing

Behavior commit: `1695b7e6`

`Mp3Stream` and `Mp3FileReader` now retain one `Mp3Limits` policy for encoded
bytes and completed frames. Default entry points accept at most 4,294,967,295
bytes and 10,000,000 frames. `initWithLimits` and `summarizeWithLimits` expose
the same policy to installed consumers. Byte rejection precedes tag and frame
scanning. Frame-limit rejection occurs before cursor, counter, decoder, or
caller-storage mutation.

The dedicated native fuzz target combines arbitrary input with valid generated
frames, then mutates, truncates, or extends the candidate. Accepted frames must
advance the cursor. CRC and side-information parsing must remain bounded, and
decoder failure must leave the complete decoder state unchanged.

| Check | Result |
| --- | --- |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 131/131 tests; native Debug execution plus ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-mp3-fuzz --fuzz=100K` | Passed: 100,675 further executions; cumulative corpus reached 202,113 runs, 1,984 unique inputs, and 910 of 21,667 instrumented branches without a failure |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit APIs |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 471,198 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Ogg Stream Parsing

Behavior commit: `328adb46`

Ogg memory and positional-file page and packet readers now retain one
`OggLimits` policy for encoded bytes, completed pages, completed packets, and
chained logical streams. The default entry points accept at most 4,294,967,295
bytes, 10,000,000 pages, 10,000,000 packets, and 65,536 logical streams. Public
`WithLimits` constructors and Vorbis seek-index helpers accept a custom policy.
Limit rejection preserves reader state. Byte and count limits that are known
before a file read also preserve caller storage.

The dedicated native fuzz target combines arbitrary input with generated valid
single-stream Ogg pages, then mutates, truncates, or extends the candidate.
Accepted pages must advance the byte cursor, accepted packets must advance the
packet count, and every packet-parser failure must preserve retained state.

| Check | Result |
| --- | --- |
| `zig build test-vorbis --summary all` | Passed: 10/10 steps and 94/94 tests, including native Debug execution, ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation, plus Xiph, stb_vorbis, and Tremor source or interoperability gates |
| `zig build test-ogg-fuzz --fuzz=100K` | Passed: 100,094 executions, 66 unique inputs, and 253 of 21,817 instrumented branches without a failure |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit APIs |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 471,806 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Audio Container Parsing

Behavior commit: `4b326977`

`AudioFileReader` now retains one `AudioFileLimits` policy across WAV, AIFF,
AIFC, RF64, BW64, and Wave64 parsing and metadata scans. Default entry points
accept at most one TiB of encoded file data, 1,000,000 chunks per scan, 256 MiB
for one requested metadata chunk, and 10,000,000,000 PCM frames.
`initWithLimits` exposes the same policy to installed consumers. File-byte
rejection precedes header parsing. Chunk and frame limits precede accepted
reader publication, while requested-metadata limits precede destination writes.

The deterministic mutation suite flips every encoded byte under three masks
and tests every strict truncation prefix for all six supported containers. The
dedicated native fuzz target combines arbitrary input with generated WAV and
AIFF, then mutates, truncates, or extends the candidate before parsing it
through positional file I/O. Accepted readers must retain valid bounded state,
successful reads must report an in-range frame count, and failed transactional
reads must preserve caller output.

| Check | Result |
| --- | --- |
| Focused audio-file reader selection | Passed: 18/18 tests, including every independent limit, hostile retained state, all-container deterministic mutation and truncation, and transactional late-I/O failure |
| Broad Q12 file, metadata, XML, and writer selection | Passed: 168/168 tests |
| `zig build test-audio-file-fuzz --fuzz=100K` | Passed: 100,153 executions, 60 unique inputs, and 411 of 22,216 instrumented branches without a failure |
| `zig build test-plugin-core-builds --summary all` | Passed: Windows x86-64 ReleaseSafe cross-compilation |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit APIs |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 472,111 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded FLAC Parsing and Decoding

Behavior commit: `fa3e5f47`

FLAC memory and positional-file decoders now retain one `FlacLimits` policy
for encoded bytes, metadata blocks, complete metadata bytes, declared PCM
frames, and decoded FLAC frame blocks per operation. Default entry points
accept at most one TiB of encoded data, 1,000,000 metadata blocks, 256 MiB of
metadata, 10,000,000,000 PCM frames, and 10,000,000 decoded frame blocks.
Public `WithLimits` entry points and file-reader constructors accept a custom
policy. File metadata preflight applies determinable limits before retained
metadata storage changes. Accepted file readers retain their exact metadata
totals and policy as validated state.

The dedicated native fuzz target combines arbitrary input with generated mono
and stereo PCM16 or PCM24 FLAC streams, then mutates, truncates, or extends the
candidate. It decodes through the explicit policy and transactional API. Every
failure must preserve complete caller output. Every success must fit both its
decoded sample count and declared frame count within caller capacity.

| Check | Result |
| --- | --- |
| Focused FLAC selection | Passed: 37/37 tests, including independent limits, exact-bound success, hostile retained state, and transactional late frame-block rejection |
| Broad Q12 file, metadata, XML, and writer selection | Passed: 169/169 tests |
| `zig build test-flac-fuzz --fuzz=100K` | Passed: 100,488 executions, 308 unique inputs, and 592 of 21,553 instrumented branches without a failure |
| `zig build test-plugin-core-builds --summary all` | Passed: Windows x86-64 ReleaseSafe cross-compilation |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public custom-limit APIs |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 472,667 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Direct Audio Metadata Parsing

Behavior commit: `6551a601`

Direct ID3v2.3, ID3v2.4, RIFF INFO, AIFF text, and RIFF XML entry points now
apply one `Id3Limits` or `AudioMetadataLimits` encoded-byte policy. Existing
constructors use a 256 MiB default, while public `WithLimits` variants accept a
caller-selected policy. Iterators retain the policy, and ID3 iterators retain
the complete encoded tag extent separately from their frame-only slice.
Hostile mutation cannot reset that retained extent to the compatibility
default. XML elements accept at most 1,024 attributes and 256 KiB of attribute
source, jointly bounding pairwise qualified-name and expanded-name validation.

The dedicated native fuzz target seeds valid ID3v2.3, ID3v2.4, RIFF INFO, AIFF
text, and RIFF XML inputs. It parses arbitrary inputs through every bounded
entry point and requires accepted iterators to make strict cursor progress.

| Check | Result |
| --- | --- |
| Focused ID3, audio-metadata, and XML selection | Passed: 41/41 tests, including exact byte limits, hostile retained policy and extent mutation, XML attribute count and byte limits, and both ID3 versions |
| Broad Q12 file, metadata, XML, and writer selection | Passed: 174/174 tests |
| `zig build test-audio-metadata-fuzz --fuzz=100K` | Passed: 100,017 executions and 141 of 22,043 instrumented branches without a failure |
| `zig build test-plugin-core-builds -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe --summary all` | Passed: 2/2 steps and Windows x86-64 ReleaseSafe cross-compilation |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including every public custom-limit API |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 473,068 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded SOFA Container Loading

Behavior commit: `604e6727`

`HrtfSofaLoader` now applies one `HrtfSofaLimits` file-byte policy before
passing a dataset path to `nc_open`. Existing methods use a 1 GiB default, and
public `WithLimits` methods accept a caller-selected bound. One-byte-under
rejection precedes NetCDF parsing and destination mutation. Exact-byte success
continues into the existing nonzero dimension, checked shape-product,
compile-time measurement and frame capacity, finite-value, geometry, and
failure-atomic publication checks.

Both prepared CC BY 4.0 public datasets exercised the final source. The Viking
fixture contains 1,513 measurements and 128 response frames at 48 kHz. The
HUTUBS fixture contains 440 measurements and 256 response frames at 44.1 kHz.
The native C++ NetCDF reference compared eight complete responses per dataset.

| Check | Result |
| --- | --- |
| `zig build test-hrtf --summary all` with both public fixture paths | Passed: 14/14 steps and 150/150 tests, including exact file limits, both real NetCDF loads, two independent reference executions, and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-hrtf-reference --summary all` with both public fixture paths | Passed: eight full-response comparisons across 440 measurements and 256 frames, plus eight across 1,513 measurements and 128 frames |
| `zig build test-established-spatial-renderers --summary all` with pinned prepared sources | Passed: 6/6 steps, 6,144 libmysofa samples with 7.451e-8 peak error, and 5,654 libspatialaudio samples with 1.192e-7 peak error |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public limits type and bounded method declarations |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 473,173 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Failure-Atomic Parameter State

Behavior commit: `906296e3`

The binary parameter-state format already bounds one input to a 16-bit entry
count and fixed 12-byte entries. Restore already decodes into a private
`ParameterValues` snapshot before publication. This change bounds the remaining
migration multiplier at `maximum_parameter_id_migrations`, currently 256.
Validation rejects a 257th mapping before reading state. It sorts the accepted
table into fixed storage, detects cycles through bounded binary lookups, and
recognizes independent convergence by duplicate destination IDs. Each decoded
state ID then follows its chain through the same index instead of rescanning
the original slice linearly.

The deterministic suite accepts and resolves the complete 256-link chain,
rejects one mapping over the limit without changing prior values, and retains
the existing identity, duplicate-source, cycle, convergence, truncation,
duplicate-entry, range, finite-value, and accounting cases. The dedicated fuzz
target seeds valid and truncated state, supplies arbitrary inputs through 64
KiB, and requires every failed restore to preserve both prior values exactly.

| Check | Result |
| --- | --- |
| Broad state selection | Passed: 198/198 tests across parameter state, migration, LV2, AUv2, editor state, resource state, and retained-state families |
| Focused parameter-state and migration selection | Passed: 41/41 Debug tests |
| `zig build test-state-fuzz --fuzz=100K` | Passed: 100,005 further executions; cumulative corpus reached 200,041 runs, 34 unique inputs, and 170 of 21,675 instrumented branches without a failure |
| `zig build test-plugin-core-builds -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSafe --summary all` | Passed: 2/2 steps and Windows x86-64 ReleaseSafe cross-compilation |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public migration bound |
| `scripts/check_quality_inventory.sh` | Passed: 823 files and 473,445 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Checked Parser and Persistent-State Inventory

Behavior commit: `a2b0bb64`

The Phase 3 ledger assigns every production source selected by the repository
parser metric or by persistence- and input-oriented filenames to one of eleven
semantic input families or four reviewed exclusions. The gate rejects missing,
stale, duplicate, untracked, out-of-scope, and unknown-family entries. Its
fixture independently removes one lexical candidate and one filename-derived
candidate, and requires both omissions to fail.

The ledger distinguishes inventory coverage from review completion. P-STATE,
P-AUDIO, P-ADM, and P-SOFA point to their closed findings and evidence. The
remaining families stay explicitly open, with P-ARA and P-MIDI-CI selected as
the next high-priority audits.

| Check | Result |
| --- | --- |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/test_parser_inventory_runner.sh` | Passed: baseline accepted; omitted lexical candidate, omitted semantic filename candidate, and unknown family rejected |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 473,643 lines classified |
| `scripts/test_quality_inventory_runner.sh` | Passed |
| `bash -n scripts/check_parser_inventory.sh scripts/test_parser_inventory_runner.sh` | Passed |
| `shellcheck scripts/check_parser_inventory.sh scripts/test_parser_inventory_runner.sh` | Passed |
| `zig fmt --check build.zig` | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Failure-Atomic ARA Archives

Behavior commit: `7c392946`

The document-controller archive buffer is derived at compile time from the
model source, modification, persistent-ID, and extension capacities. Host file
size is checked before reading. Store and restore filter counts are now capped
before any host pointer traversal or fixed-array indexing. Strings, object
records, and extension bytes remain bounded by the same capacities, and the
complete envelope must decode before the extension provider receives it.

Tuning-analysis restore decodes into a staged copy of its fixed-capacity slots
and publishes only after the complete reader succeeds. Record, name, and
content counts fit both the 16-bit wire representation and compile-time
capacities. Archive-size calculation saturates so an unrepresentable size is
rejected by the controller instead of overflowing. The wider source-cache,
renderer, analysis, and transform review found fixed storage, checked range
arithmetic, and transactional generation publication throughout.

The deterministic regressions exercise exactly one source or modification
over each store and restore filter limit. Rejected stores preserve the complete
prior host archive. The controller fuzzer requires decoding failure before any
extension callback and deterministic replay after success. The tuning-analysis
fuzzer requires exact prior-slot preservation after every error and
deterministic replay after every success.

| Check | Result |
| --- | --- |
| `zig build test-ara --summary all` | Passed: 77/77 steps and 444/444 tests, including native execution, ARA VST3 ABI checks, and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-ara-controller-archive-fuzz --fuzz=100K` | Passed: 100,006 executions and 148 of 8,995 instrumented branches without a failure |
| `zig build test-ara-archive-fuzz --fuzz=100K` | Passed: 200,048 cumulative executions, 38 unique inputs, and 228 of 9,338 instrumented branches without a failure |
| `zig build test-phase2-thread-sanitizers --summary all` | Passed: 10/10 steps and 17/17 tests |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,064 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded MIDI-CI Inputs and Transactional Restore

Behavior commit: `387204ef`

The P-MIDI-CI review covered discovery, endpoint information, profiles,
process inquiry and reports, Property Exchange messages, chunk reassembly,
request and subscription sessions, JSON headers and resources, remote caches,
and MIDI endpoint sessions. Exact wire messages are bounded by 7-, 14-, and
28-bit fields plus compile-time storage capacities. Resource JSON already
rejected more than 65,535 bytes, and its dynamic schema parser uses the Zig
standard library's iterative heap stack within that source bound.

The remaining direct header JSON entry points accepted an arbitrary slice
before allocation. They now reject an empty source or more than 16,383 bytes at
the shared boundary, matching the wire field, and the public facade exports the
limit. A one-byte-over test uses a failing allocator to prove rejection before
allocation. Exhaustive allocation-failure injection covers a successful header
with retained strings.

Three dedicated fuzz targets cover canonical wire replay, transactional chunk
reassembly, all four constrained header forms, Mcoded7 replay, eleven resource
and controller JSON entry points, and failure-atomic cache snapshots. Failed
cache restores preserve the complete prior cache, and successful restores
replay identically from the same baseline.

| Check | Result |
| --- | --- |
| `zig build test-midi-ci --summary all` | Passed: 6/6 steps and 108/108 tests, including native execution and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| Combined focused and fuzz smoke gate | Passed: 15/15 steps and 129/129 tests |
| `zig build test-midi-ci-wire-fuzz --fuzz=100K` | Passed: 100,024 executions, 22 unique inputs, and 199 of 22,548 instrumented branches without a failure |
| `zig build test-midi-ci-json-fuzz --fuzz=100K` | Passed: 166,853 executions, 47 unique inputs, and 829 of 22,079 instrumented branches without a failure |
| `zig build test-midi-ci-resource-fuzz --fuzz=100K` | Passed: 144,779 executions, 278 unique inputs, and 1,310 of 25,215 instrumented branches without a failure |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the exported header limit |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,477 lines classified |
| `zig build test --summary all` | Incomplete: 444/446 steps succeeded and 7,556/7,562 tests passed with six expected platform skips. The sole failed dependency was the pre-existing production termination-path scan now tracked by Q-VER-009. |
| `git diff --check` | Passed |

## 2026-08-15: Production Termination-Path Gate Restored

Behavior commit: `91a7e2e4`

The zero-tolerance production-source scan found ten constructs introduced after
the gate itself. Seven were mathematically unreachable selector fallbacks in
top-level parser fuzz helpers, but their placement made them production
declarations. They now return bounded arbitrary input for every otherwise
impossible selector value. The ADM identifier hash index now reports an invalid
slot count through `@compileError` inside an explicit compile-time block. Both
Ogg packet readers now derive nullable page exhaustion with an optional match
instead of asserting that a second read of the optional value succeeds.

The first focused rerun caught that a bare `@compileError` is analyzed even for
valid generic instantiations. Moving it into an explicit compile-time block
restored the intended conditional diagnostic. This correction passed the ADM
fuzz gate before the complete rerun.

| Check | Result |
| --- | --- |
| `scripts/check_production_termination_paths.sh` | Passed: no production termination path found |
| `scripts/test_production_termination_path_check.sh` | Passed: unreachable, runtime assertion, panic, debug panic, and trap fixtures rejected; comments, strings, and test blocks accepted |
| Affected parser gates | Passed: complete 94-test Vorbis gate plus ADM XML, iXML, MP3, Ogg, audio-file, FLAC, and MIDI-file fuzz gates |
| `zig build test --summary all` | Passed: 446/446 steps, 7,556 tests passed, and six expected platform skips across the complete repository matrix |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,484 lines classified |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Editor-State Migration

Behavior commit: `88d286da`

The P-EDITOR review covered typed values, encoded field and payload extents,
schema migration, truncation, corruption, and publication. Schema declarations
permit at most 64 fields. The wire count is checked against that limit before
entry traversal, and all payload decoding uses a 641-byte fixed scratch buffer.
Text and envelope values retain their own exact capacities and validity checks.

The remaining caller-provided migration table had no limit. Validation was
quadratic, and field restoration scanned the complete table once for every
schema version. Restoration now rejects more than 256 migrations before reader
access, validates and orders accepted entries once in fixed storage, and visits
that index once per decoded field. Grouped traversal preserves the existing
rule that at most one migration applies to a field in each schema version.

The exact-limit test resolves a 256-link chain and rejects 257 migrations
without consuming input or changing the destination. The dedicated mutation
harness exercises migration, all header and entry lengths, value decoding, and
failure-atomic publication.

| Check | Result |
| --- | --- |
| `zig build test-editor-state --summary all` | Passed: 6/6 steps and 19/19 tests, including native execution and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-editor-state-fuzz --summary all` | Passed: 3/3 steps and 7/7 tests |
| `zig build test-editor-state-fuzz --fuzz=100K` | Passed: 100,059 executions, 57 unique inputs, and 106 of 21,867 instrumented branches without a failure |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests, including the public migration limit |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,691 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Transactional Resource Restore

Behavior commit: `17eb9d39`

The P-RESOURCE review covered fixed paths and metadata, reference and recovery
state, bounded byte accumulation, immutable exchange slots, worker jobs, and
VST3 resource-path transport. Paths reject empty values, embedded zero bytes,
and compile-time-capacity overflow. Reference lengths are checked before fixed
payload reads. The byte accumulator uses checked arithmetic and a
caller-selected maximum, rejects aliased mutation, and preserves content after
allocation failure. Exchange storage is fixed at no more than 255 slots.

Jobs require positive compile-time work and result limits. Progress updates
reject inconsistent or over-limit totals. Cancellation and optional deadlines
are cooperative through the worker context, and results publish only for the
current accepted generation. Existing concurrency coverage exercises work
replacement, cancellation, join ordering, generation rollover, exchange
replacement, and teardown.

The remaining defect was the public `Recovery.restore` boundary. Decoded state
was validated, but a caller could directly mutate the public fixed-storage
fields and pass malformed state to restore. The negative control changed a
valid ready snapshot to restoring. Restore now validates before cancellation,
generation allocation, snapshot mutation, or worker submission. The regression
proves the retained recovery and presentation snapshots remain identical.

The dedicated state mutation target parses bounded arbitrary bytes. Every
successful value must validate, fit the compile-time encoded maximum, and
survive canonical encode and decode.

| Check | Result |
| --- | --- |
| `zig build test-resource --summary all` | Passed: 15/15 steps and 134/134 tests, including native state, worker, exchange, transport, and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-resource-state-fuzz --fuzz=100K` | Passed: 100,027 executions, 25 unique inputs, and 222 of 22,004 instrumented branches without a failure |
| `zig build test-resource-thread-sanitizer --summary all` | Passed: 5/5 steps and 60/60 tests |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,803 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Adapter Input Traversal

Behavior commit: `3a4f718e`

The P-ADAPTER review covered the VST3 processor, controller, and runtime
bridges plus LV2 core, metadata, and UI adapters. Parameter and editor state
delegate to their closed bounded families. AUv2 component state uses fixed
maximum storage. LV2 feature and option arrays stop after 256 entries and
require terminators. LV2 audio blocks reject counts above the negotiated
maximum, UI atom bodies are capped before slicing, and state publication is
transactional. VST3 bus arrays are checked against retained topology counts,
parameter and event collectors stop after 64 host visits, and data event
payloads have a fixed maximum.

The remaining uncovered traversal was the VST3 data-exchange receiver. Its
host-provided 32-bit count previously formed a slice over a raw pointer without
a framework work limit. The callback now accepts at most 64 blocks, matching
the existing per-callback input visitation policy, and rejects zero or
one-over counts before dereferencing the block pointer. The exact-limit test
delivers all 64 blocks. The one-over test intentionally supplies only one
backing block and proves rejection occurs before traversal or delegation.

| Check | Result |
| --- | --- |
| `zig build test-vst3-module --summary all` | Passed: 7/7 steps and 795/795 tests |
| `zig build test-lv2 --summary all` | Passed: 56/56 steps and 578/578 tests, including native hosts, ABI checks, bundles, and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| `scripts/check_parser_inventory.sh` | Passed: 177 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 825 files and 474,830 lines classified |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Linear MIDI Streams and Native Input

Behavior commits: `d316b437`, `4e09e9e1`, `171a1218`, and `b6ac068d`

The remaining P-MIDI review covered MIDI 1 messages, UMP framing, SysEx7,
SysEx8, Mixed Data Set, Flex Data text, Stream messages, native input and
output delegates, fixed scheduler queues, and raw VST3 MIDI declarations.
Messages and packets use fixed three-byte and four-word storage. Segmented
assemblers use compile-time capacities and checked transactional append.
Native output queues hold 256 fixed messages or packets, and raw VST3 files are
ABI declarations with independent SDK layout and constant gates.

The UMP iterator previously traversed its complete source before every packet.
It now accepts a 256 MiB default or caller-selected word and packet policy,
validates the complete source once, and retains an exact source, limits,
cursor, and packet-count witness. Caller-modified state uses bounded canonical
fallback. Exact-limit and one-over tests prove limit rejection leaves cursor
and packet count unchanged. The checked scaling gate remains flat from 1,024
through 4,096 one-word packets at 125.78, 124.79, and 124.83 Debug ns per
packet and 10.09, 10.29, and 10.05 ReleaseSafe ns per packet.

The native review found that ALSA input threads could remain inside a readable
device drain without rechecking stop. Each drain now checks stop before every
read and accepts at most 64 reads per poll wake. MIDI 1 callbacks reject more
than 256 bytes, shared ALSA and Windows UMP callbacks reject more than 64
words, and CoreMIDI rejects a count beyond its 16-bit packet length before
pointer traversal. Direct ALSA C string copies reject an overflowing length
before scanning or allocation.

One generated-input target covers bounded UMP framing and exact deterministic
replay. A second sends arbitrary valid UMP frames through five fixed-capacity
segmented assemblers and compares the complete prior state after every
rejected packet.

| Check | Result |
| --- | --- |
| `zig build test-ump-stream --summary all` | Passed: 6/6 steps and 9/9 tests, including native execution and ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-ump-stream-fuzz --fuzz=100K` | Passed: 100,367 executions, 365 unique inputs, and 90 of 21,719 instrumented branches without a failure |
| `zig build benchmark-ump-stream` in Debug and ReleaseSafe | Passed: checked per-packet cost stayed flat through 4,096 packets |
| `zig build test-midi-stream-fuzz --fuzz=100K` | Passed: 102,591 executions, 2,517 unique inputs, and 496 of 23,109 instrumented branches without a failure |
| Native backend gates | Passed: ALSA MIDI 13/13 steps and 15/15 tests; ALSA UMP 13/13 steps and 11/11 tests; Windows MIDI 9/9 steps and 11/11 tests; Windows UMP 7/7 steps and 4/4 tests; CoreMIDI 9/9 steps with 13/14 tests passed and one native-device skip |
| `zig build test-midi-thread-sanitizers --summary all` | Passed: 11/11 steps and 9/9 tests |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| `scripts/check_production_termination_paths.sh` | Passed after `d31a1ed2` removed the editor-state mutation helper's compile-time fallback |
| `scripts/check_parser_inventory.sh` | Passed: 178 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 827 files and 475,456 lines classified |
| `zig fmt --check` over changed Zig and build sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: Bounded Configuration Inputs and Phase 3 Completion

Behavior commit: `5aa87178`

The final P-CONFIG review found two runtime input forms. Device identifiers
and display names accept at most 128 UTF-8 bytes, reject embedded zero bytes,
and copy into fixed storage. A versioned device-selection record contains at
most five identifiers and occupies at most 656 bytes. Restore reads into a
temporary value, requires complete input consumption, and publishes only
after every field passes validation. VST3 textual IDs accept exactly 32
hexadecimal bytes and decode into 16 fixed bytes without allocation.

The new exact-bound test constructs a maximum-size record, verifies its 656
byte extent, rejects every one of its 656 truncated prefixes, rejects trailing
bytes and invalid presence, length, zero-byte, and UTF-8 encodings, and proves
that each failure preserves the prior selection. The dedicated gate also
covers numeric preparation configuration, the standalone window event budget,
textual VST3 IDs, and compile-time compatibility JSON output. Its Windows
portion compiles in ReleaseSafe mode.

The inventory review corrected three false classifications. The framework has
no standalone argument parser. Preparation configuration accepts typed numeric
values, the standalone shell processes typed events under a caller-provided
positive budget, and compatibility JSON is compile-time output. These sources
are now recorded as reviewed non-input or output paths instead of P-CONFIG.

The first complete gate caught stale acquire counts for the ALSA MIDI 1 and
UMP shims in the checked atomic-order ledger. Commit `02e0a43c` refreshed both
counts. The checker and its mutation fixture then passed, followed by a clean
complete repository rerun. This closes Q-CONFIG-001, Q-VER-010, P-CONFIG, and
Phase 3.

| Check | Result |
| --- | --- |
| `zig build test-config-inputs --summary all` | Passed: 8/8 steps and 38/38 tests, including native execution and ReleaseSafe Windows compilation |
| `scripts/check_quality_atomic_orders.sh` | Passed: 57 Zig and 11 native source files tracked |
| `scripts/test_quality_atomic_orders_runner.sh` | Passed: baseline and mutation fixture checks |
| `scripts/check_parser_inventory.sh` | Passed: 178 production sources classified |
| `scripts/check_quality_inventory.sh` | Passed: 827 files and 475,578 lines classified |
| `zig build test --summary all` | Passed: 446/446 steps with 7,647 tests passed and six expected platform skips |
| `zig fmt --check` over changed Zig and build sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: DSP Convolution Dependency Direction

Behavior commit: `6ea6099b`

Q-ARCH-002 identified a DSP-to-GUI dependency: HRTF imported partitioned
convolution, its fixed preparation queue, and realtime publication state from
`gui_ir_convolution.zig`. The implementation now lives in
`dsp/convolution.zig`, `dsp.zig` exports it from that location, and HRTF uses a
sibling DSP import. IR Loader uses the preferred `core.dsp` path.

The existing `gui_ir_convolution` module remains installed as a thin exact
alias. A public-module regression checks that its metadata, instantiated
convolver, and instantiated preparation queue are the same types exposed by
the DSP namespace. The installed DSP fixture already passes metadata from the
old namespace into the DSP convolver, providing a second consumer-level type
identity check. No public root declaration was added, removed, renamed, or
reclassified.

The new focused gate executes convolution processing, generation replacement,
sample-rate publication, invalid retained state, queue ordering and retry,
concurrent transfer, and bounded worker-stack coverage. It also compiles the
same selection in ReleaseSafe mode for Linux AArch64, Linux x86-64, and Windows
x86-64. HRTF, IR Loader lifecycle and all three bundle targets, the complete
DSP publication ThreadSanitizer gate, and the staged package pass.

| Check | Result |
| --- | --- |
| `zig build test-convolution --summary all` | Passed: 6/6 steps and 26/26 tests, including ReleaseSafe Linux AArch64, Linux x86-64, and Windows x86-64 compilation |
| `zig build test-hrtf --summary all` | Passed: 8/8 steps with 148/150 tests passed and two expected dataset skips |
| `zig build test-dsp-thread-sanitizer --summary all` | Passed: 5/5 steps and 149/149 tests |
| `zig build test-gui-lifecycle-ir-loader --summary all` | Passed: 9/9 steps and 6/6 tests |
| IR Loader bundle builds | Passed: native Debug plus ReleaseSafe Linux x86-64 and Windows x86-64 bundles |
| `scripts/test_installed_package.sh --optimize=ReleaseSafe` | Passed: 18/18 steps and 96/96 tests |
| Quality inventory gates | Passed: 828 files and 475,661 lines classified, 178 parser candidates classified, 82 concurrency sources classified, and 57 Zig plus 11 native atomic-order sources tracked |
| `scripts/check_production_termination_paths.sh` | Passed |
| `zig fmt --check` over changed Zig, build, and example sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: ADM XML Cohesion Closure

Behavior commit: `dfeca639`

ADM XML public traversal now lives in two focused modules. `standard.zig`
owns declaration, reference, profile, and tag iteration over an immutable
metadata source. `block.zig` owns block syntax and parameter validation over
the same source. Neither module imports the document implementation or
retains construction, count, limit, index, or graph-validation state.

The remaining core owns bounded document construction, fixed-storage graph
indexes, relationship validation, and emission-profile orchestration. The
public facade preserves every prior type identity. The cohesion ledger now
classifies the core as `KEEP` at 5,155 production and 4,786 test lines.

| Check | Result |
| --- | --- |
| Direct ADM XML gate | Passed: 125/125 tests and the native fuzz test |
| ReleaseSafe cross-compilation | Passed: Linux x86-64 and Windows x86-64 |
| `scripts/test_installed_package.sh` | Passed: 18/18 steps and 96/96 tests |
| Cohesion inventory and fixture | Passed: 33 large handwritten sources classified |
| Quality and concurrency inventories | Passed: 850 files and 477,154 lines classified; 85 concurrency sources classified |
| Production termination scan and fixture | Passed |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |

## 2026-08-15: MP3 Decoder Boundary

The MP3 facade now delegates frame decoding, synthesis, stream recovery,
metadata reads, seeking, and positional file reads to `dsp/mp3/decoder.zig`.
All public declarations retain their prior names and exact identities. The
encoder analysis state remains with the encoder because it owns encoder
configuration and the analysis-side transform history.

The decoder boundary is now refined into three contracts. `decoder.zig` owns
requantization, stereo processing, synthesis, and frame and stream decoder
state. `reader.zig` owns scanning, recovery, seeking, and positional I/O.
`metadata.zig` provides their passive Xing, VBRI, and summary values without a
dependency cycle. Each focused module is below the large-source threshold.
The facade remains `SPLIT` until reservoir ownership is separated from
encoding and file writing.

| Check | Result |
| --- | --- |
| `zig build test-mp3 --summary all` | Passed: 6/6 steps and 131/131 tests |
| ReleaseSafe cross-compilation | Passed: Linux AArch64, Linux x86-64, and Windows x86-64 |
| `zig fmt --check` over changed Zig sources | Passed |
| `git diff --check` | Passed |
