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

- [x] Add deterministic generated cases for WAV and AIFF chunk structure, truncation, size limits, and decoded bounds.
- [x] Add serialized-state cases for truncation, unknown fields, version migration, non-finite values, and maximum-capacity text.
- [x] Add range and menu state-machine properties, including crossed handles, unavailable actions, cancellation, and stale callbacks.
- [x] Add malformed host callback probes for nullable pointers, invalid indices, invalid sizes, and out-of-order lifecycle calls.

Exit criteria:

- Generated tests use fixed seeds and print the seed and case index on failure.
- Invalid input cannot escape declared bounds, leave partial state, or reach undefined behavior.
- Every fixed crash receives a minimal direct regression in addition to broader generated coverage.

## Milestone 3: Visual and Real-Time Gates

- [x] Cover compact, standard, expanded, 1x, 2x, and high-contrast output with deterministic references.
- [x] Assert minimum text padding, action spacing, clipping bounds, focus visibility, and disabled-state contrast where geometry can be checked directly.
- [x] Instrument processing, telemetry publication, and decoded-audio adoption for allocation, lock, file-access, logging, host-call, and GUI-call violations.
- [x] Record lifecycle, warm render, import, waveform construction, telemetry, and maximum-polyphony baselines with explicit budgets.

Exit criteria:

- Visual references and geometry assertions cover all production editors at every supported layout mode.
- Audio-thread tests fail at the violating operation instead of relying only on code review.
- Benchmarks report stable units, iteration counts, and regression budgets.

## Milestone 4: Public API and Installed Consumer

- [ ] Audit the public GUI API for duplicate concepts, adapter leakage, ambiguous ownership, and unsupported single-consumer surfaces.
- [ ] Split broad examples into focused composition, importer, graph, accessibility, and lifecycle examples where that improves discoverability.
- [x] Test a consumer against the installed package layout rather than the repository source tree.
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

### Milestone 2: Property and Boundary Tests

- The bounded audio parser now receives 512 fixed-seed arbitrary, RIFF, AIFF, and AIFC inputs. Every strict prefix of known-valid WAV and AIFF data is also rejected, while complete fixtures return metadata contained within the file and declared format limits.
- Editor-state tests reject every truncated prefix without partial updates and run 512 fixed-seed bit mutations. Successful mutations must still decode finite, capacity-bounded values. Failed mutations preserve the destination exactly.
- Range selection runs 32,768 generated set, adjust, replace, crossed, and non-finite operations. File import runs 32,768 generated lifecycle transitions. Decoded sample handoff runs 32,768 generated begin, write, commit, cancel, clear, adopt, stale-generation, and malformed-metadata operations.
- Native action menus run 4,096 generated keyboard operations and never focus or activate disabled entries or separators. Failures print their fixed seed and case index.
- The all-editor host harness now probes null and unknown editor names, invalid parameter indices, malformed process data, and inverted size constraints before each lifecycle completes.
- Generated import transitions exposed a terminal-state defect: acknowledged cancellation retained `cancellation_pending=true`. Completion, failure, and acknowledged cancellation now clear the request atomically, with a direct regression beside the generated test.
- `zig build test --summary all` passed 71/71 steps and 3,810/3,810 tests after the fix. Native adapter, macOS accessibility, visual regression, warm rendering, fixture generation, public-boundary checks, and runner parsing all passed in the same invocation.

### Milestone 3: Visual and Real-Time Gates

- Parametric EQ, Resonant Filter, and Sample Player now have standard 2x references at 1440 by 1320 pixels and alternate high-contrast references in addition to their compact, standard, and expanded 1x workspaces. Existing component references continue to cover both themes, focus, disabled, pressed, selected, error, and import states.
- Native geometry tests enforce label and value insets, control-to-value spacing, non-overlapping layout cells, footer clearance, focus propagation, and selected-text contrast. The production workspace references add pixel-level coverage for clipping and responsive composition.
- The framework process dispatcher opens a thread-local real-time audit scope around every production processor call in test and debug builds. Telemetry publication and decoded-audio adoption are allowed and counted. Instrumented file access, worker allocation, locks, GUI creation, logging, and host calls cause processing to return failure. Release builds compile the instrumentation out.
- The decoded importer directly proves that file access, allocation, and locking are rejected in a real-time scope. Telemetry and decoded-audio handoff prove their lock-free paths remain allowed. A separate fixed source audit rejects direct forbidden operations in the Channel Strip, Parametric EQ, Resonant Filter, IR Loader, and Sample Player process bodies.
- `zig build test-gui-lifecycle --summary all` passed 37/37 steps and 1,957/1,957 tests with the process audit active. The visual gate passed all new and existing references. Warm measurements were 98.2 us for the aggregate scene, 279.9 us for maximum signal views, 242.9 us for linked EQ, 187.9 us for Resonant Filter, 58.3 us for viewport rendering, 184.8 us for range selection, and 54.5 ms per complete Sample Player editor lifecycle.
- `zig build benchmark --summary all` now fails explicit regression ceilings instead of printing informational numbers only. The first budgeted run measured 795.8 MiB/s import throughput, 10.03 ms for maximum sample decode and waveform construction, 109.8 ns per preview read, 9.1 ns per playback frame with eight voices available, 5.5 ns per playhead update, and 673.8 ns per IR sample.
- `zig build test --summary all` passed 73/73 steps and 3,816/3,816 tests with the new visual, runtime, and source gates enabled.

Remaining before the milestone exit is declared complete: add full compact, standard, expanded, 2x, and high-contrast workspace references for Channel Strip and IR Loader. Their shared components and state sequences are covered now, but their complete production compositions are not yet represented at every size.

### Milestone 4: Installed Consumer

- `scripts/test_installed_package.sh` stages only the files declared by the package manifest, copies a separate consumer beside that package, and gives the consumer its own build graph and caches. A failure preserves the staged tree for diagnosis.
- The consumer imports only `zig-vst3` and `zig-vst3-plugin`. It compiles a parameter-workspace effect editor with a transfer graph and an instrument-workspace editor with a controller waveform, bounded WAV and AIFF importer, bipolar pan, and piano audition declaration.
- The first complete run passed 4/4 build steps and its effect and instrument declaration test. The check now runs as part of `zig build test`.
- The complete gate passed 74/74 steps and 3,816/3,816 tests after adding the staged-package consumer.
