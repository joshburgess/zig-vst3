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

- [x] Audit the public GUI API for duplicate concepts, adapter leakage, ambiguous ownership, and unsupported single-consumer surfaces.
- [x] Split broad examples into focused composition, importer, graph, accessibility, and lifecycle examples where that improves discoverability.
- [x] Test a consumer against the installed package layout rather than the repository source tree.
- [x] Update public component documentation with ownership, threading, lifecycle, and API-status decisions.

Exit criteria:

- Ordinary consumers import only `@import("zig-vst3").vstgui` plus clearly named public test support.
- Installed-package tests build at least one effect editor and one instrument editor.
- Supported, experimental, and internal APIs are named consistently in code and documentation.

## Milestone 5: Validation and Evidence

- [x] Extend validator and soak runners with command, bundle hash, phase, iteration, status, signal, stdout, stderr, and crash-log metadata.
- [x] Run Zig tests, raw ABI checks, native adapter and accessibility tests, visual tests, benchmarks, Steinberg validators, and Linux and Windows bundle builds.
- [x] Run pluginval serially at strictness 5 and 10 only after deterministic lifecycle coverage is clean.
- [x] Record unavailable native host checks without treating cross-compilation as host validation.

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

- Channel Strip and IR Loader now each have complete compact, standard, expanded, 2x, and alternate-contrast workspace references. The snapshots use their production parameter, group, graph, meter, importer, preset, action, label, progress, and layout declarations rather than isolated component scenes.
- The complete visual matrix passes with the same bounded warm-render budgets. The full deterministic gate passed 77/77 steps and 3,822/3,822 tests after the ten production workspace references were added.

### Milestone 4: Installed Consumer

- `scripts/test_installed_package.sh` stages only the files declared by the package manifest, copies a separate consumer beside that package, and gives the consumer its own build graph and caches. A failure preserves the staged tree for diagnosis.
- The consumer imports only `zig-vst3` and `zig-vst3-plugin`. It compiles a parameter-workspace effect editor with a transfer graph and an instrument-workspace editor with a controller waveform, bounded WAV and AIFF importer, bipolar pan, and piano audition declaration.
- The first complete run passed 4/4 build steps and its effect and instrument declaration test. The check now runs as part of `zig build test`.
- The complete gate passed 74/74 steps and 3,816/3,816 tests after adding the staged-package consumer.

### Milestone 4: Public API and Focused Examples

- `@import("zig-vst3").vstgui` is the documented component-authoring surface. `EditorDescription` with `createEditor` is the main composition path. The four `create*View` functions remain supported conveniences for small editors.
- `FileImporter` and `EditorDescription.file_importers` are the current file-input names. `FileDrop` and `file_drops` remain compatibility aliases. Unsupported single-consumer extensions remain listed as experimental instead of being promoted by proximity to a production editor.
- `@import("zig-vst3-plugin").gui` is documented as the toolkit-neutral adapter and renderer contract. Ordinary plugin composition does not import it. The focused lifecycle example uses it specifically to demonstrate adapter-facing size and scale rules.
- Focused composition, graph, importer, accessibility, and lifecycle examples now compile together under `zig build test`. The documentation links each example and states declaration lifetime, editor ownership, worker-thread responsibility, and audio-thread restrictions.
- The complete deterministic gate passed 77/77 steps and 3,822/3,822 tests. This included the installed-package consumer, public-boundary scan, native adapter and macOS accessibility tests, all visual references, runner regressions, and the focused examples.

### Milestone 5: Crash Evidence

- The pluginval runner now records exact indexed arguments, plugin path, bundle hash, strictness, phase, iteration, timeout, status, signal, stdout, stderr, commit, and system metadata on every platform. Direct invocations now capture output files consistently with the macOS launch service path.
- Unexpected macOS validator or pluginval exits copy only crash reports created after the recorded run marker. Existing diagnostic reports are not mixed into the artifact directory.
- The Steinberg validator runner now produces the same command, bundle, phase, iteration, status, signal, output, commit, and system evidence instead of replacing itself with an unrecorded process.
- The lifecycle soak runner records exact command arguments, cache location, working directory, start and finish times, signal classification, and output paths for every plugin and repetition.
- Fake success and signal exits exercise both validator runners without launching GUI tools. `scripts/test_validator_runner.sh` and the expanded `scripts/test_pluginval_runner.sh` pass and verify the preserved files and classifications.
- The complete deterministic gate passed 75/75 steps and 3,816/3,816 tests with both runner artifact regressions enabled.

### Milestone 5: Release Validation

- The final deterministic gate passed 77/77 steps and 3,822/3,822 tests. Native adapter tests, automated macOS accessibility tests, the complete visual matrix, installed-package consumers, runner regressions, and public-boundary checks passed in the same invocation.
- `zig build raw-api-abi --summary all` passed 113/113 steps, including entry symbols for all 14 bundles, the pinned SDK declaration comparisons, and the C, C++, and SDK multi-interface harnesses.
- `zig build benchmark --summary all` passed every explicit budget. The final run measured 1,489.8 MiB/s import throughput, 0.62 ms for maximum sample decode and waveform construction, 7.2 ns per sample-player frame with eight voices available, 4.8 ns per playhead update, and 591.8 ns per IR sample.
- Linux and Windows cross-target matrices each passed 44/44 steps and produced all 14 bundles. These are build checks, not native host validation.
- All 14 native macOS bundles passed the Steinberg validator in a 74/74-step run.
- All 14 plugins passed pluginval serially at strictness 5. Artifacts run from `zig_vst3_gain-strictness-5-20260720-200218-17165` through `zig_vst3_sample_player-strictness-5-20260720-200437-37589` under the local `zig-vst3-pluginval` temporary directory.
- All 14 plugins then passed pluginval serially at strictness 10, including non-releasing processing, state restoration, background-thread state, parameter thread safety, and parameter fuzzing. Artifacts run from `zig_vst3_gain-strictness-10-20260720-200513-40178` through `zig_vst3_sample_player-strictness-10-20260720-201654-51617`. No validator or pluginval crash occurred in either final suite.
- Manual REAPER, VoiceOver, Narrator, native Windows, native X11, native Wayland, AT-SPI, and multi-monitor checks remain deferred. They require interactive observation or unavailable native infrastructure. Cross-compilation is not counted as completing them.

### Autonomous Follow-up: Native Sanitizers

- `zig build test-vstgui-sanitizers --summary all` builds VSTGUI and the adapter with AddressSanitizer and UndefinedBehaviorSanitizer, then runs native interaction, macOS accessibility, and the complete visual comparison matrix. Visual performance ceilings remain owned by the unsanitized release gate because instrumentation changes their timing.
- The first instrumented run found a stale `GraphView` call during destruction of an editor that had never attached to a native frame. The editor now clears every component binding before the frame destroys its view tree, whether or not the host opened the frame.
- The runner uses VSTGUI's exact Release configuration with debug symbols. VSTGUI publishes layout-affecting definitions only for its Debug and Release configurations, so using another CMake configuration would produce an invalid test ABI.
- Enum-value instrumentation is disabled because the C-facing adapter tests deliberately inject unknown numeric enum values and verify rejection. Address, vptr, bounds, arithmetic, and the remaining undefined-behavior checks stay enabled.
- The final sanitizer run passed 2/2 build steps. The normal test and raw ABI matrix then passed 187/187 steps and 3,822/3,822 tests. The visual performance gate remained within budget, and the benchmark measured 0.60 ms maximum sample decode, 7.2 ns per sample-player frame, and 597.7 ns per IR sample.

### Autonomous Follow-up: Bipolar Slider Promotion

- Channel Strip Drive now uses the public `bipolar_slider` presentation. Its signed -12 dB to +12 dB range has the same meaningful zero center, exact entry, reset gesture, automation attachment, and accessibility behavior as Sample Player pan.
- The direct bipolar slider is supported after independent production use in the Channel Strip and Sample Player. Direct parameter-backed graph ranges and `Graph.secondary_range_selection` remain experimental because the Sample Player is still their only production consumer.
- The deterministic and raw ABI gate passed 187/187 steps and 3,822/3,822 tests. The sanitizer gate passed 2/2 steps. Linux and Windows bundle matrices each passed 44/44 steps, and all 14 Steinberg validators passed in a 74/74-step run.
- Benchmarks stayed within budget: 1.27 ms for maximum sample decode and waveform construction, 7.7 ns per sample-player frame, 5.1 ns per playhead update, and 636.7 ns per IR sample.
- The serialized strictness-5 dependency chain through Channel Strip passed, ending with artifact `zig_vst3_channel_strip-strictness-5-20260720-210621-868`. The strictness-10 chain also passed, ending with `zig_vst3_channel_strip-strictness-10-20260720-211736-4048`. No unexpected exit or crash occurred.

### Autonomous Follow-up: Sanitizer Soak

- `zig build soak-vstgui-sanitizers --summary all` builds the instrumented native adapter once, then repeats interaction, macOS accessibility, and complete visual comparison processes. `VSTGUI_SANITIZER_SOAK_REPETITIONS` controls the bounded repetition count and defaults to eight.
- Every process records exact arguments, sanitizer options, phase, repetition, timestamps, stdout, stderr, and status. The runner stops on the first failure or signal and leaves the failing visual output beside its status. Interrupted runs record the active phase and repetition.
- The final full run passed 24/24 instrumented processes at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-vstgui-sanitizer/20260720-230804-93268`. The artifact contains 24 successful phase records and a successful final status. No sanitizer diagnostic or unexpected exit occurred.
- The existing one-shot `test-vstgui-sanitizers` gate still passed 2/2 steps after its build-only mode was added for the soak runner.
- A portable fake-executable regression verifies successful repetition accounting, invalid repetition rejection, and first-failure classification without requiring an actual sanitizer defect.
- The deterministic and raw ABI gate passed 188/188 steps and 3,822/3,822 tests, including the runner regression. Linux and Windows bundle matrices each passed 44/44 steps. Benchmarks remained within budget, including 0.61 ms maximum sample decode, 7.4 ns per sample-player frame, and 601.6 ns per IR sample.

### Autonomous Follow-up: Thread Sanitizer

- `zig build test-vstgui-thread-sanitizer --summary all` uses a separate exact-Release CMake tree with ThreadSanitizer instrumentation. CMake rejects attempts to combine it with the address and undefined-behavior sanitizer build.
- The native adapter regression overlaps 4,096 worker-thread parameter publications with 4,096 editor-thread queue drains and value reads. It verifies finite values and accepted publications while ThreadSanitizer observes the atomic handoff and VSTGUI update boundary.
- Four instrumented process runs passed at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-vstgui-thread-sanitizer/20260721-004355-57719`. Each run preserves stdout, stderr, timestamps, status, sanitizer options, system metadata, and the tested commit. No race, deadlock, signal, or unexpected exit was reported.
- The existing AddressSanitizer and UndefinedBehaviorSanitizer gate passed 2/2 steps after the separate ThreadSanitizer configuration was added.
- The deterministic and raw ABI gate passed 188/188 steps and 3,822/3,822 tests. Linux and Windows cross-target bundle matrices each passed 44/44 steps and produced all 14 example bundles. These remain build checks rather than native host validation.
- Benchmarks remained within budget: 0.58 ms for maximum sample decode and waveform construction, 7.2 ns per sample-player frame, 5.1 ns per playhead update, and 593.8 ns per IR sample.

### Autonomous Follow-up: Generated Playback Lifecycles

- The reusable sample player now runs 32,768 deterministic generated lifecycle operations across note-on, note-off, all-notes-off, reset, sample-rate changes, bounded media replacement, looping, reverse playback, voice limits, and hostile parameter values.
- The generated invariant requires finite stereo output within the documented gain bound and a finite normalized playhead whenever a voice is active. Its fixed seed and failing operation coordinates make any regression reproducible.
- Non-finite sustain values now fall back before clamping, so they cannot propagate into audio. Pitch calculation widens the note and root note before subtraction, preventing overflow at the public `i16` boundaries.
- The full deterministic test suite passed with the new lifecycle regression. AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps. Linux and Windows cross-target matrices each passed 44/44 steps.
- Benchmarks remained within budget: 0.60 ms for maximum sample decode and waveform construction, 7.3 ns per sample-player frame, 4.9 ns per playhead update, and 535.2 ns per IR sample.
- Every raw ABI harness passed. The combined `raw-api-abi` command remains to be repeated when the machine is idle because its embedded visual timing gate ran at about 2.4 times the normal standalone measurement under active system load. No ABI mismatch, sanitizer diagnostic, functional test failure, or standalone performance regression occurred.
