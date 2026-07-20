# GUI Autonomous Hardening Plan

## Outcome

Make editor lifecycle, rendering, public-package use, and real-time behavior reproducible without relying on an interactive DAW session. Manual host checks remain a final confirmation, not the primary way to discover crashes or layout regressions.

## Milestone 1: Headless Host Stress

- [x] Add one reusable host harness for component, controller, connection-point, processor, automation, and editor lifecycles.
- [x] Run processing and parameter automation while each editor is repeatedly created, constrained, resized, focused, closed, and recreated.
- [x] Cover every editor-bearing example through the same harness.
- [x] Add a bounded soak mode with per-plugin progress and failure artifacts.

Exit criteria:

- Every editor completes the deterministic lifecycle test under normal test runs.
- The soak runner identifies the plugin, iteration, lifecycle phase, and last successful operation after an unexpected exit.
- The harness does not open REAPER or require a visible native window.

## Milestone 2: Property and Boundary Tests

- [ ] Add deterministic generated cases for WAV and AIFF chunk structure, truncation, size limits, and decoded bounds.
- [ ] Add serialized-state cases for truncation, unknown fields, version migration, non-finite values, and maximum-capacity text.
- [ ] Add range and menu state-machine properties, including crossed handles, unavailable actions, cancellation, and stale callbacks.
- [ ] Add malformed host callback probes for nullable pointers, invalid indices, invalid sizes, and out-of-order lifecycle calls.

Exit criteria:

- Generated tests use fixed seeds and print the seed and case index on failure.
- Invalid input cannot escape declared bounds, leave partial state, or reach undefined behavior.
- Every fixed crash receives a minimal direct regression in addition to broader generated coverage.

## Milestone 3: Visual and Real-Time Gates

- [ ] Cover compact, standard, expanded, 1x, 2x, and high-contrast output with deterministic references.
- [ ] Assert minimum text padding, action spacing, clipping bounds, focus visibility, and disabled-state contrast where geometry can be checked directly.
- [ ] Instrument processing, telemetry publication, and decoded-audio adoption for allocation, lock, file-access, logging, host-call, and GUI-call violations.
- [ ] Record lifecycle, warm render, import, waveform construction, telemetry, and maximum-polyphony baselines with explicit budgets.

Exit criteria:

- Visual references and geometry assertions cover all production editors at every supported layout mode.
- Audio-thread tests fail at the violating operation instead of relying only on code review.
- Benchmarks report stable units, iteration counts, and regression budgets.

## Milestone 4: Public API and Installed Consumer

- [ ] Audit the public GUI API for duplicate concepts, adapter leakage, ambiguous ownership, and unsupported single-consumer surfaces.
- [ ] Split broad examples into focused composition, importer, graph, accessibility, and lifecycle examples where that improves discoverability.
- [ ] Test a consumer against the installed package layout rather than the repository source tree.
- [ ] Update public component documentation with ownership, threading, lifecycle, and API-status decisions.

Exit criteria:

- Ordinary consumers import only `@import("zig-vst3").vstgui` plus clearly named public test support.
- Installed-package tests build at least one effect editor and one instrument editor.
- Supported, experimental, and internal APIs are named consistently in code and documentation.

## Milestone 5: Validation and Evidence

- [ ] Extend validator and soak runners with command, bundle hash, phase, iteration, status, signal, stdout, stderr, and crash-log metadata.
- [ ] Run Zig tests, raw ABI checks, native adapter and accessibility tests, visual tests, benchmarks, Steinberg validators, and Linux and Windows bundle builds.
- [ ] Run pluginval serially at strictness 5 and 10 only after deterministic lifecycle coverage is clean.
- [ ] Record unavailable native host checks without treating cross-compilation as host validation.

Exit criteria:

- All locally executable gates pass from a clean checkout with repository-local caches.
- Each unexpected exit preserves enough information to reproduce the exact plugin and phase.
- Remaining checks require unavailable infrastructure or a manual host observation.

## Completion Evidence

Record commit IDs, test counts, artifact paths, benchmark measurements, API decisions, and deferred checks here as each milestone lands.

### Baseline

- Starting branch: `feature/plugin-gui`
- Starting commit: `5c2838f` (`Harden sample player GUI validation`)
- Existing automated baseline: 3,787 Zig tests, 113 raw ABI steps, all 14 Steinberg validators, Linux and Windows bundle matrices, and 28 serialized pluginval runs.
- Interactive REAPER work is deferred while autonomous hardening is in progress.

### Milestone 1: Headless Host Stress

- `vst3.testing.vstgui_headless_host` now owns the shared host model. Each invocation connects a component and controller, starts the processor, queues bounded automation, and runs audio blocks on a worker while the calling thread repeatedly creates and destroys editor views.
- Each editor lifecycle checks focus changes, keyboard dispatch, size constraints, compact, standard, expanded, and return sizes, accepted dimensions, and teardown. The audio worker uses fixed stack buffers and fixed-capacity parameter queues.
- All 11 editor-bearing plugins use the same test contract. `zig build test-gui-lifecycle --summary all` passed 37/37 steps and 1,957/1,957 plugin-root tests, including 132 editor lifecycles and at least 1,408 overlapped process blocks.
- `scripts/gui_lifecycle_soak.sh` runs plugins serially, stops on the first failure, and records plugin, repetition, phase, exit classification, stdout, stderr, commit, Zig version, and system metadata. Its first complete pass recorded 11 successful per-plugin statuses and 132 editor lifecycles at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-gui-lifecycle/20260720-185835-67397`.
- `zig build test --summary failures` passed after adding all lifecycle regressions. No DAW or visible native window was opened.
