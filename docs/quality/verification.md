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
