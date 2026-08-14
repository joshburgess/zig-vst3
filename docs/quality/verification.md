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
