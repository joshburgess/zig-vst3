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
- Every raw ABI harness passed. After validation responsibilities were separated from adapter compilation, the combined `raw-api-abi` command passed 113/113 steps without inheriting an unrelated visual timing gate.

### Autonomous Follow-up: Validation Graph Isolation

- `zig build vstgui-adapter` now configures and compiles only the optional native adapter. Ordinary plugin compilation, entry-symbol checks, and raw ABI validation no longer run interaction, accessibility, visual-regression, performance, or cross-target bridge checks as hidden build side effects.
- `zig build test-vstgui-native` owns the native interaction, macOS accessibility, complete visual matrix, warm-render budgets, and Windows accessibility bridge compile check. The complete `zig build test` graph requires this gate before compiling and running the broader deterministic matrix, preserving the previous validation strength without contaminating unrelated build steps.
- The compile-only adapter gate passed 2/2 steps. The explicit native GUI gate passed 4/4 steps with a 92.8 us aggregate warm render and a 47.35 ms Sample Player editor lifecycle average.
- The raw ABI matrix passed 113/113 steps after the split. The complete deterministic gate passed 80/80 steps and 3,823/3,823 tests, with native GUI validation ordered ahead of the broader workload.
- The Unix script rejects unknown modes with status 2 and passes `sh -n` and ShellCheck. PowerShell execution remains pending on a native Windows host because PowerShell is unavailable locally.

### Autonomous Follow-up: Thread Sanitizer Runner Regression

- The ThreadSanitizer runner now creates its artifact directory before configuring or compiling, so build failures retain stdout, stderr, status, phase, system metadata, and the tested commit instead of exiting without evidence.
- Every instrumented process records its exact executable argument. Bounded build-directory and skip-build overrides allow the runner logic to be tested without fabricating a sanitizer defect or rebuilding VSTGUI.
- A portable deterministic regression verifies three successful repetitions, invalid repetition rejection, exact command artifacts, first-failure classification, and immediate stopping after the first failed process.
- The refactored real runner passed four instrumented processes at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-vstgui-thread-sanitizer/20260721-080934-83313`. No race, deadlock, signal, or unexpected exit was reported.
- The complete deterministic gate passed 81/81 steps and 3,823/3,823 tests with the portable runner regression included. The native visual gate remained within budget at 89.2 us for the aggregate scene and 46.49 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Build Mode Regression and API Audit

- A portable fake-tool regression now enforces the VSTGUI build boundary. Compile-only mode must configure CMake and build only `zig_vstgui_adapter`. Validation mode must additionally run interaction, accessibility, and visual targets and compile the Windows accessibility bridge.
- The regression also verifies that compile-only mode never invokes Zig for the Windows bridge and that unknown modes fail with status 2. It runs under the complete deterministic test graph.
- The current API audit keeps direct parameter-backed graph ranges and `Graph.secondary_range_selection` experimental. The IR Loader is a valid second production consumer for state-backed `RangeSelection`, but converting its destructive edit selection into automatable parameters or adding an unrelated secondary range would create a misleading contract merely to satisfy a consumer count.
- The complete deterministic gate passed 82/82 steps and 3,823/3,823 tests. Native visual measurements remained within budget at 91.8 us for the aggregate scene and 47.31 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Numerical Boundary Hardening

- Toolkit-neutral parameter attachments now quantize both their initial controller value and every host automation update through the same bounded path. NaN maps to zero, positive infinity maps to one, and discrete values remain on declared steps instead of retaining non-finite state.
- Viewport zoom rejects non-finite anchors on active axes before changing zoom or persisted offsets. Invalid input cannot poison later projection, panning, resize restoration, or graph rendering.
- The viewport model now runs 32,768 deterministic generated transitions across anchored zoom, zoom limits, pan, reset, out-of-range values, NaN, and infinity. Every operation must preserve finite zoom and offsets within the visible-span bounds, with a fixed seed and failure coordinates for reproduction.
- The complete deterministic gate passed 82/82 steps and 3,825/3,825 tests. The raw ABI matrix passed 113/113 steps, AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps, and Linux and Windows cross-target matrices each passed 44/44 steps.
- Benchmarks remained within budget: 0.59 ms for maximum sample decode and waveform construction, 6.9 ns per sample-player frame, 4.8 ns per playhead update, and 718.8 ns per IR sample. The native aggregate scene rendered in 81.0 us during the first complete run.

### Autonomous Follow-up: Decoded Audio Boundaries

- The reusable Sample Player store and IR convolver now reject any staged chunk containing NaN or infinity before copying samples or advancing the transfer offset. Malformed decoder output cannot reach interpolation, waveform playback, resampling, FFT preparation, or convolution state.
- Direct recovery tests replace rejected chunks within the same generation, publish the completed media, and verify finite playback or convolution output. The generated sample-store lifecycle also injects non-finite chunks while preserving atomic-generation invariants.
- The complete deterministic gate passed 82/82 steps and 3,827/3,827 tests. The raw ABI matrix passed 113/113 steps, and AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps.
- Linux and Windows cross-target matrices each passed 44/44 steps. The IR Loader and Sample Player each passed all 47 Steinberg validator tests for both processing precisions.
- Benchmarks remained within budget: 0.64 ms for maximum sample decode and waveform construction, 7.2 ns per sample-player frame, 5.0 ns per playhead update, and 609.4 ns per IR sample. The native aggregate scene rendered in 87.2 us, and a complete Sample Player editor lifecycle averaged 45.72 ms.

### Autonomous Follow-up: Transactional Media Transport

- Decoded-audio transport now validates source metadata, checked sample counts, callback-reported lengths, and finite payloads before encoding each message. A callback cannot make the sender slice beyond its fixed chunk buffer.
- The sender compares importer generation and media metadata again after the final copy. Replacement or mutation during publication sends cancel instead of committing a mixed generation to the processor.
- Meter banks normalize a non-finite initial value to zero and reject non-finite publications without replacing the last finite reading. Waveform series already reject non-finite points, while spectrum input maps individual invalid samples to silence.
- Hostile importer regressions cover oversized callback results, NaN payloads, and generation replacement after the first of multiple chunks. Receiver state remains unpublished after every rejected transfer.
- The complete deterministic gate passed 82/82 steps and 3,848/3,848 tests. The raw ABI matrix passed 113/113 steps, AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps, and Linux and Windows cross-target matrices each passed 44/44 steps.
- The IR Loader and Sample Player each passed all 47 Steinberg validator tests. Benchmarks remained within budget: 0.61 ms for maximum sample decode and waveform construction, 7.4 ns per sample-player frame, 4.9 ns per playhead update, and 613.3 ns per IR sample.

### Autonomous Follow-up: Transactional IR Editing

- IR replacement now stages decoded samples in the editor's existing rollback buffer. Live original and edited media change only after every callback returns a valid length, every sample is finite, and the final source snapshot matches the initial generation and metadata.
- Replacement is rejected while an edit publication remains unresolved, so staging cannot destroy the rollback needed after a failed processor transfer. This preserves the existing 3.00 MiB editor storage bound.
- Hostile source regressions cover oversized callback counts, NaN samples, generation replacement during copy, and replacement during a pending edit. Every rejected load retains the previous samples, metadata, generation, and edited state.
- The complete deterministic gate passed 82/82 steps and 3,850/3,850 tests. The raw ABI matrix passed 113/113 steps, AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps, and Linux and Windows cross-target matrices each passed 44/44 steps.
- The IR Loader passed all 47 Steinberg validator tests. Benchmarks remained within budget: 0.93 ms for maximum sample decode and waveform construction, 7.3 ns per sample-player frame, 4.9 ns per playhead update, and 609.4 ns per IR sample.

### Autonomous Follow-up: Host Message Integer Boundaries

- Decoded-audio receive paths now check host-supplied sample rate, channel count, frame count, and chunk offset values before narrowing them to framework storage types. Values outside those types return `kInvalidArgument` instead of trapping.
- Direct regressions cover a channel count above `u8` and a sample rate above `u32`. Both malformed begin messages leave the receiver without staged media.
- The complete deterministic gate passed 82/82 steps and 3,860/3,860 tests. The raw ABI matrix passed 113/113 steps, and AddressSanitizer and UndefinedBehaviorSanitizer passed 2/2 steps.
- Linux and Windows cross-target matrices each passed 44/44 steps. The IR Loader and Sample Player each passed all 47 Steinberg validator tests for both processing precisions.

### Autonomous Follow-up: Receiver Recovery

- A direct hostile-message regression now begins a valid decoded-audio transfer, injects an extreme chunk offset, injects a non-finite payload, and then replaces both with a valid chunk. Rejected chunks do not advance or cancel the staged generation, and the corrected payload commits normally.
- The regression exercises the shared receiver against the Sample Player store. Sender-side hostile callback tests and IR convolver staging tests cover the same contract from the other production paths.
- The complete deterministic gate passed 82/82 steps and 3,870/3,870 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps. Both validators passed all 47 tests for both processing precisions.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 93.6 us for the aggregate scene and 52.96 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Transport Routing Isolation

- Note transport now has direct rejection coverage for null messages, unrelated message IDs, missing attributes, non-finite velocity, and invalid pressed-state encodings. None of those inputs publishes a mailbox command, and a later valid note remains deliverable.
- Decoded-audio transport now proves that an unrelated message ID, wrong target, and unknown operation cannot disturb an active staged transfer. A valid chunk and commit still complete the original generation afterward.
- The note sender and receiver share one fixed-capacity message declaration, keeping its four-attribute bound explicit in both production code and malformed-message tests.
- The complete deterministic gate passed 82/82 steps and 3,890/3,890 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.0 us for the aggregate scene and 46.12 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Data Exchange Callback Bounds

- The reflected `IDataExchangeReceiver` boundary now drops empty deliveries and nonzero block counts with null storage before dispatching to plugin configuration code. Consumers no longer need to guard against dereferencing the first block of an incoherent callback.
- A direct ABI-level regression sends both pointer/count mismatches and verifies that neither reaches the configured receiver. A later valid block still dispatches with its context, block ID, count, and thread flag intact.
- The complete deterministic gate passed 82/82 steps and 3,890/3,890 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 85.6 us for the aggregate scene and 44.31 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Data Exchange Block Validation

- The reflected `IDataExchangeReceiver` boundary now rejects any delivered block with null payload storage, zero bytes, or the SDK invalid block ID before dispatching the batch to plugin configuration code.
- The ABI-level receiver regression covers each malformed block independently, verifies that none reaches the consumer, and then delivers the restored valid block without changing its context or thread flag.
- The complete deterministic gate passed 82/82 steps and 3,890/3,890 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.8 us for the aggregate scene and 47.51 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Data Exchange Queue Validation

- The reflected `IDataExchangeReceiver` boundary now initializes the background-dispatch result to false and rejects zero-sized queues before invoking plugin configuration code.
- The direct ABI regression verifies that an invalid queue does not reach the consumer, then opens a valid 512-byte queue and preserves its configured dispatch policy.
- The complete deterministic gate passed 82/82 steps and 3,890/3,890 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.9 us for the aggregate scene and 47.34 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Data Exchange Lifecycle Inputs

- The reusable host and plugin-facing helpers now reject null processors, zero block sizes, zero block counts, invalid queue IDs, invalid block IDs, and noncanonical send flags before delegation. Zero alignment remains supported by the SDK contract.
- A permissive host regression proves invalid requests cannot be accepted by configuration code. The same test completes a valid open, lock, free, and close sequence afterward.
- The complete deterministic gate passed 82/82 steps and 3,900/3,900 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 95.7 us for the aggregate scene and 47.08 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Data Exchange Boolean Boundaries

- Queue-open dispatch results are now canonicalized to zero or one before returning through the ABI. Received block batches with a background-thread flag above one are rejected before consumer dispatch.
- The direct receiver regression uses a plugin result of two and a host thread flag of two, then verifies a later canonical delivery remains intact.
- The complete deterministic gate passed 82/82 steps and 3,900/3,900 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 96.9 us for the aggregate scene and 48.49 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Component Lifecycle Inputs

- The generic effect now rejects noncanonical component and processing activation states. Invalid calls cannot reset processor state.
- Stereo bus activation now shares a reusable validator for configured media, direction, index, and state. Unsupported and out-of-range buses return `kInvalidArgument`.
- Lifecycle regressions reject malformed calls, preserve the reset count, and then complete valid activate, process, stop, and deactivate transitions.
- The complete deterministic gate passed 82/82 steps and 3,900/3,900 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 95.5 us for the aggregate scene and 55.12 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Controller Host Request Inputs

- Component-handler and public controller boundaries now reject noncanonical dirty states and malformed bus activation media, direction, index, and state values before recording or delegation.
- Regressions prove rejected calls do not increment callback counters. Valid calls still reach available extensions or report an absent extension without changing the validation result.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 98.5 us for the aggregate scene and 54.23 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Progress Callback Inputs

- Progress callbacks now reject unknown task types and non-finite or out-of-range normalized values before recording or host delegation. Rejected starts clear their output ID.
- Direct handler and public controller regressions cover unknown types, negative values, values above one, NaN, and infinity. Valid background-task callbacks retain their existing behavior.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 91.4 us for the aggregate scene and 45.32 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Automation Value Inputs

- Parameter state, public controller edits, and all reusable component handlers now reject non-finite or out-of-range normalized automation values before state mutation, recording, observer notification, or host delegation.
- Regressions cover negative values, values above one, NaN, and infinity. They verify rejected edits preserve the previous parameter value and callback count.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 91.6 us for the aggregate scene and 46.68 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Component Restart Flags

- Reusable component handlers and the public reflected controller now reject negative restart flags and unknown bits before recording, configuration hooks, or host delegation.
- Regressions prove invalid restart requests preserve callback counters. Valid combined SDK flags retain their existing behavior, including the no-handler result at the public controller boundary.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 96.0 us for the aggregate scene and 49.00 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Automation Parameter IDs

- All reusable component handlers and public controller gesture helpers now reject the VST3 `kNoParamId` sentinel before recording or host delegation.
- Begin, perform, and end regressions prove invalid IDs preserve gesture counters. Valid parameter IDs retain their existing callback behavior.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.3 us for the aggregate scene and 47.77 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Context Menu Parameter IDs

- Generic context-menu requests remain valid with no parameter target. Requests with a non-null `kNoParamId` target are rejected before recording, configuration hooks, or host delegation.
- Direct component-handler and public Gain controller regressions prove invalid targets preserve callback counters. A valid Gain target still reaches the host extension.
- The complete deterministic gate passed 82/82 steps and 3,910/3,910 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 95.4 us for the aggregate scene and 47.20 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Context Menu Target Lifetime

- Final context-menu release now clears every stored item and releases its retained target. Removed slots and later slot reuse cannot hide retained references from teardown.
- A direct lifecycle regression covers two targets, item removal, storage reuse, final release, balanced target counts, and empty post-release storage.
- The complete deterministic gate passed 82/82 steps and 3,911/3,911 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 86.6 us for the aggregate scene and 45.99 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Context Menu Item Validation

- Context-menu storage now rejects unknown flag bits and fixed UTF-16 names without a terminator before retaining a target or mutating item storage. Removal rejects the same malformed payloads.
- A recovery regression verifies rejected additions preserve item and reference counts, rejected removal preserves a valid stored item, and a later valid removal balances the target reference.
- The complete deterministic gate passed 82/82 steps and 3,912/3,912 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 95.6 us for the aggregate scene and 46.87 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Context Menu Group Flags

- Group-start markers now require the SDK disabled bit, and group-end markers require the SDK separator bit. Incomplete encodings are rejected before storage or target retention.
- The malformed-item recovery regression covers both incomplete markers, both valid SDK group constants, and an ordinary item after the rejected inputs.
- The complete deterministic gate passed 82/82 steps and 3,912/3,912 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.1 us for the aggregate scene and 46.01 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Plug View Resize Rectangles

- The reusable `IPlugView` boundary now rejects zero-sized, inverted, and coordinate-overflowing rectangles before editor callbacks or host resize requests. Delegated size and constraint hooks that return malformed geometry are rejected without changing the caller rectangle or accepted view size.
- The VSTGUI constraint adapter uses checked coordinate reconstruction after clamping, so valid dimensions combined with extreme origins cannot overflow signed rectangle coordinates.
- Direct regressions prove malformed host input never reaches plugin configuration or the plug frame, accepted geometry remains unchanged, and malformed delegated output is restored transactionally.
- The complete deterministic gate passed 82/82 steps and 3,926/3,926 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 98.3 us for the aggregate scene and 54.97 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Plug Frame Resize Rectangles

- The shared rectangle validator now protects both sides of host resize negotiation. `IPlugFrame::resizeView` rejects empty, inverted, and coordinate-overflowing requests before configuration code runs.
- Delegated failures and malformed successful outputs restore the caller's original rectangle. Rejected geometry cannot replace the last accepted host resize state.
- Direct regressions cover invalid input, suppressed delegation, transactional restoration, recovery, and the shared dimension contract.
- The complete deterministic gate passed 82/82 steps and 3,950/3,950 tests. The combined raw ABI, sanitizer, IR Loader validator, and Sample Player validator invocation passed 123/123 steps, with both validators passing all 47 tests.
- Linux aarch64 and Windows x86_64 cross-target matrices each passed 44/44 steps. Native visual measurements remained within budget at 92.8 us for the aggregate scene and 47.13 ms for a complete Sample Player editor lifecycle.

### Autonomous Follow-up: Sample Player Parameter Continuity

- The Sample Player now keeps accepted parameter values across blocks instead of falling back to declaration defaults when a block has no automation point.
- Sixteen fixed per-instance `BlockParameterLatch` values preserve each pre-block baseline, apply automation at its declared process segment, and retain the final value for the next block without allocation or locking.
- A deterministic stereo regression proves hard-right pan persists through a quiet block and a later hard-left point does not affect earlier frames even when persisted state already contains the final value.
- The complete deterministic gate passed 111/111 steps and 4,100/4,100 tests. The installed-package suite passed 7/7 tests and exercises the public `beginBlock` and `valueAt` contract.

### Autonomous Follow-up: Block-Rate Parameter Timing

- Reflected VST3 processors and standalone `PluginInstance` state-aware hooks now receive a fixed stack snapshot containing persisted state plus offset-zero changes. Later points cannot affect block-rate processing before their declared offset.
- The complete parameter queue still updates persistent state for the next block and remains available through `ProcessContext` for sample-accurate processing. Raw process hooks do not pay the snapshot cost.
- Direct f32 and f64 regressions cover parameter views, parameter-value hooks, offset-zero changes, later points, and quiet-block persistence without allocation or locking.
- The complete deterministic gate passed 111/111 steps and 4,112/4,112 tests. The installed-package suite passed 7/7 tests.

### Autonomous Follow-up: Zero-Sample Parameter Flushes

- The VST3 bridge now preserves valid offset-zero parameter points when the host sends the SDK zero-sample flush form with no audio buffers.
- The reflected processor updates persistent component state without invoking DSP. A following audio block observes the flushed value, while points outside the virtual flush boundary remain rejected.
- Direct collector and processor regressions cover bounded collection, no-buffer dispatch, and next-block visibility. The complete deterministic gate passed 111/111 steps and 4,122/4,122 tests.
- Raw ABI checks passed, the Bypass plugin passed all 47 Steinberg validator tests including both flush forms and bypass persistence, and Linux aarch64 and Windows x86-64 example bundle matrices passed.

### Autonomous Follow-up: Parameter Flush Structure

- Zero-sample flushes now validate signed bus counts, configured bus availability, bus-array presence, channel counts, declared layouts, and sample format before changing persistent parameter state.
- The SDK no-buffer form and zero-channel form remain valid. Malformed flushes return `kInvalidArgument` and a later audio block proves that rejected input did not mutate state.
- Direct bridge and reflected processor regressions cover valid recovery after missing arrays, negative channels, excess buses, and nonzero frame counts. The complete deterministic gate passed 111/111 steps and 4,132/4,132 tests.
- Raw ABI checks passed, the Bypass plugin passed all 47 Steinberg validator tests, and Linux aarch64 and Windows x86-64 example bundle matrices passed.

### Autonomous Follow-up: Telemetry Payload Bounds

- Graph and text telemetry now share explicit framework limits of 256 points and 96 bytes. Both retained consumers and reflected producers enforce those limits before invoking an ABI callback or exposing a Zig slice.
- Regressions pass oversized capacities through both sides of the telemetry boundary, verify the callback receives only the bounded region, and clamp an oversized producer result to the same effective capacity.
- The deterministic test suite and raw ABI checks passed. The telemetry-using Model Shell passed all 47 Steinberg validator tests, and the Linux aarch64 and Windows x86-64 example bundle matrices each passed 59/59 steps.

### Autonomous Follow-up: Import Snapshot Validation

- Toolkit-neutral import snapshots now reject impossible progress, cancellation, preview, channel, sample-rate, frame, and decoded-frame combinations.
- The native editor bridge validates a controller snapshot before narrowing its fields or writing adapter-visible output. A malformed custom controller cannot trap the bridge with an oversized preview count or publish inconsistent progress.
- The deterministic suite passed 4,144/4,144 tests. Raw ABI checks passed, the Sample Player and IR Loader each passed all 47 Steinberg validator tests, and the Linux aarch64 and Windows x86-64 example bundle matrices each passed 59/59 steps.

### Autonomous Follow-up: Native Editor Callback Inputs

- Import snapshot validation now bounds path counts and requires a source path for active, ready, cancelled, and failed jobs.
- Native callbacks decode file entry-point and command integers through explicit allowlists. Unknown C values are rejected before plugin configuration hooks. Controller graph capacities and producer results are clamped to the shared 256-point contract.
- The deterministic suite passed 4,151/4,151 tests. Raw ABI checks passed, the component gallery passed all 47 Steinberg validator tests, and the Linux aarch64 and Windows x86-64 example bundle matrices each passed 59/59 steps.

### Autonomous Follow-up: Native Boolean and Note Inputs

- Persistent editor booleans, checked menu actions, and piano pressed state now accept only the C values 0 and 1. Other integers are rejected before state mutation or plugin and host dispatch.
- Piano callbacks validate channel, pitch, finite velocity, velocity range, and nonzero note-on velocity through the shared GUI note contract before resolving a controller.
- The deterministic suite passed 4,158/4,158 tests. Raw ABI checks passed, the component gallery and Sine Synth each passed all 47 Steinberg validator tests, and the Linux aarch64 and Windows x86-64 example bundle matrices each passed 59/59 steps.

### Autonomous Follow-up: Native Editor Rectangle Arithmetic

- Native editor size, constraint, and content-scale callbacks now widen host coordinates before subtraction and use checked reconstruction for rectangle endpoints.
- Empty, inverted, full-range, and overflowing coordinates are rejected before native resize work. Direct regressions cover both dimension and endpoint overflow.
- The complete deterministic gate passed 111/111 steps and 4,167/4,167 tests. The native address and undefined-behavior sanitizer target passed, the resource ThreadSanitizer target passed 29/29 tests, and all 11 headless editor lifecycle targets passed 39/39 steps and 2,114/2,114 tests.
- The GUI ThreadSanitizer completed four adapter concurrency runs. Raw ABI checks passed 123/123 steps, all 19 example plugins passed all 47 Steinberg validator tests, and the Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps.
- Warm rendering remained within budget at 94.1 us for the aggregate scene, 258.6 us for maximum signal views, 226.7 us for linked EQ, 141.3 us for Resonant Filter, and 46.96 ms for a complete Sample Player editor lifecycle.
- The budgeted microbenchmarks passed. Representative results were 283.4 ns per framework process block, 1,381.2 MiB/s bounded WAV import, 7.2 ns per sample-player frame with eight voices available, and 593.8 ns per IR convolution sample.

### Autonomous Follow-up: Native Focus Boolean

- The VST3 focus callback now accepts only the SDK `TBool` values 0 and 1. Malformed bytes are rejected before native focus state changes.
- Direct boundary cases cover both valid values, the first invalid value, and the maximum byte value. The complete deterministic gate passed 111/111 steps and 4,174/4,174 tests.

### Autonomous Follow-up: Highest MIDI Note Release

- The toolkit-neutral piano model now widens its release iterator, so a valid range ending at MIDI note 127 cannot overflow after processing its final note.
- A direct regression presses and releases note 127 through the bounded `releaseAll` contract. The complete deterministic gate passed 111/111 steps and 4,175/4,175 tests.

### Autonomous Follow-up: Viewport Mutation Validation

- Viewport zoom and pan mutations now validate the supplied configuration before arithmetic, so a malformed replacement configuration is rejected without reaching invalid clamp bounds or changing state.
- Direct regressions cover a reversed zoom range, a non-finite zoom step, and a non-finite scroll step. The complete deterministic gate passed 111/111 steps and 4,176/4,176 tests.

### Autonomous Follow-up: Range Selection Mutation Validation

- Range selection set, adjust, and replace mutations now validate the supplied configuration before clamp and span arithmetic. Malformed replacement configurations leave both handle values and active selection unchanged.
- Direct regressions cover reversed bounds and a non-finite minimum span. The complete deterministic gate passed 111/111 steps and 4,177/4,177 tests.

### Autonomous Follow-up: Graph Range Construction

- Graph ranges now expose one shared validity predicate. Normalization fails closed for malformed directly constructed ranges, and editable envelopes reject invalid axis ranges even when their initial point list is empty.
- Direct regressions cover reversed and non-finite direct range values. The complete deterministic gate passed 111/111 steps and 4,178/4,178 tests.

### Autonomous Follow-up: Model Boundary Release Gates

- Native address and undefined-behavior sanitizers passed. The GUI ThreadSanitizer completed four adapter concurrency runs, and the resource ThreadSanitizer passed 29/29 tests.
- All 11 headless editor lifecycle targets passed 2,120/2,120 tests. Raw ABI checks passed, and all 19 example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps. The C kernel platform matrix also passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 287.4 ns per framework process block, 1,342.3 MiB/s bounded WAV import, 7.1 ns per sample-player frame with eight voices available, and 607.4 ns per IR convolution sample.

### Autonomous Follow-up: Direct Model State Validation

- Viewport projection, zoom, and pan now validate directly constructed public state before division or clamp arithmetic. Malformed state fails closed, while reset remains a recovery path.
- Range-selection set and adjust operations reject malformed current state transactionally. Replacement remains a bounded recovery path, and invariant checks tolerate only representation error at the configured minimum span.
- Direct regressions cover zero and non-finite viewport zoom, reversed range handles, rejection without mutation, and recovery. The complete deterministic gate passed 111/111 steps and 4,180/4,180 tests.

### Autonomous Follow-up: Bounded Inline Storage

- Resource paths, resource metadata, file-drop paths, editor text, and editor envelopes now fail closed when directly constructed public length fields exceed their inline capacity.
- Resource-reference serialization validates path and metadata lengths before writing any bytes. Invalid references report an oversized encoded form, reject recovery classification, and return a specific error without partial output.
- Editor-state serialization validates every retained value before writing its header. File-drop extension counts and lengths are checked before slicing configuration storage.
- Direct regressions cover oversized and empty path lengths, oversized metadata, text, envelope, extension count, and extension length values. The complete deterministic gate passed 111/111 steps and 4,184/4,184 tests.

### Autonomous Follow-up: Bounded GUI Collections

- Editable graph envelopes validate public collection counts, ranges, snap settings, point ordering, identifiers, selections, and transaction backups before mutation. Accessors fail closed, and cancellation discards malformed backup metadata without replacing valid live points.
- Fixed graph series reject oversized direct counts. Preset-browser operations validate retained counts, names, search text, and unique identifiers before collection access.
- Loading a preset now verifies that the selected identifier still exists and matches the active filter. Persistence rejects stale or filtered selections instead of storing inconsistent state.
- Direct regressions cover oversized graph and preset counts, duplicate graph points, malformed transaction backups, oversized preset text, and recovery. The complete deterministic gate passed 111/111 steps and 4,186/4,186 tests.

### Autonomous Follow-up: Importer Collection Integrity

- The import model now requires a bounded nonempty retained path set before starting or retrying work. Path lookup checks both the retained count and compile-time capacity, and malformed inline paths return no value.
- A validating snapshot without a source path is rejected. This aligns the toolkit-neutral model with the native callback contract and prevents impossible work states from reaching a decoder.
- Audio preview and decoded-sample copy accessors validate public counters, channel counts, decoded capacity, multiplication, and backing storage before slicing.
- Direct regressions cover oversized path counts, empty retained paths, oversized preview and frame counts, and invalid channel counts. The complete deterministic gate passed 111/111 steps and 4,188/4,188 tests.

### Autonomous Follow-up: Installed GUI Model Surface

- The staged-package consumer now composes editable graphs, viewport and range-selection models, preset filtering, and persistent resource references through `@import("zig-vst3-plugin")`.
- The test uses only copied package contents and public imports, so missing exports or accidental repository-relative dependencies fail independently of the main workspace.
- The installed-package gate passed 9/9 build steps and 8/8 tests, including effect, instrument, DSP fixture, C kernel, and toolkit-neutral GUI consumers.

### Autonomous Follow-up: Fixed-Rate Pending State

- Fixed-rate output conversion now rejects an oversized direct pending-frame count before slicing inline storage or subtracting capacity.
- Reset and successful reconfiguration clear pending model frames. This prevents buffered data from an old rate configuration from entering a rebuilt model runtime.
- Focused fixed-rate and resampler coverage passed 12/12 tests, including randomized blocks, ratio boundaries, deterministic reset, malformed state, and reconfiguration recovery. The complete deterministic gate passed 111/111 steps and 4,189/4,189 tests.

### Autonomous Follow-up: Resampler Retained State

- Streaming resampler process, drain, and latency entry points validate retained input rate, output rate, and delay values before division or float-to-integer conversion.
- Unconfigured instances retain `NotConfigured` behavior. Corrupted configured state returns `InvalidState`, and the fixed-rate pipeline propagates that distinction through both conversion stages.
- Direct regressions cover invalid output-rate state across process, drain start, drain continuation, and latency queries. The focused fixed-rate and resampler suite passed 12/12 tests, and the complete deterministic gate passed 111/111 steps and 4,189/4,189 tests.

### Autonomous Follow-up: Collection Hardening Release Gates

- Native address and undefined-behavior sanitizers passed. The GUI ThreadSanitizer completed four adapter concurrency runs, and the resource ThreadSanitizer passed.
- All 11 headless editor lifecycle targets and raw ABI checks passed. All 19 example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps. The C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 289.0 ns per framework process block, 1,365.9 MiB/s bounded WAV import, 7.3 ns per sample-player frame with eight voices available, 597.7 ns per IR convolution sample, and 41.3 ns per fixed-rate frame at 48 kHz.

### Autonomous Follow-up: Process Audio View Integrity

- Audio input and output views now validate their public channel count, frame count, and retained slice lengths before access or mutation. Malformed views report no usable channels or frames, and output fill and clear operations become no-ops.
- Process timing helpers return zero for a malformed direct sample rate instead of reaching assertion or invalid division paths.
- Direct regressions cover oversized channel counts, mismatched retained frame counts, rejected output writes, and non-finite sample rates. The complete deterministic gate passed 111/111 steps and 4,192/4,192 tests.

### Autonomous Follow-up: Piano State Integrity

- The bounded piano model now validates its retained note range and current selection before navigation, toggling, release iteration, or bitset access.
- Malformed direct state fails closed. Selecting a valid in-range note remains an explicit recovery path for a stale selection.
- Direct regressions cover zero note count, a range above MIDI note 127, and an out-of-range selection. The focused piano suite passed 4/4 tests.

### Autonomous Follow-up: Output Event Storage Integrity

- Output event writers now validate their public retained count and every exposed event before querying capacity, appending, or publishing an event view.
- Malformed state reports no events or remaining capacity and rejects appends. Clear remains a bounded recovery path.
- Direct regressions cover an oversized count and a retained event outside the process block. The complete deterministic gate passed with 4,194 tests.

### Autonomous Follow-up: Step Sequencer State Integrity

- The step sequencer now validates its retained step count, masks, cursor, anchor, and playhead before navigation or mutation.
- Invalid state fails closed. Select-all can repair a stale selection when the remaining structural state is valid.
- Direct regressions cover zero step count, selection bits above the configured range, and an out-of-range cursor. The focused sequencer suite passed 4/4 tests.

### Autonomous Follow-up: Audio Sample Slot Integrity

- The bounded audio sample store now checks active, pending, replaced, and staging slot indices before array access. Active reads also require the expected slot state and valid bounded metadata.
- Malformed public slot state produces no active metadata or audio. A later valid publication remains adoptable without touching the invalid prior index.
- Direct regressions cover invalid active, pending, and staging indices plus a zero-channel active slot. The focused sample-store suite passed 9/9 tests.

### Autonomous Follow-up: Sample Player Realtime State

- Sample-player note attacks now require a MIDI-range note and a valid prepared output rate. Playback clamps the root note before pitch conversion and discards malformed retained voices before interpolation or loop arithmetic.
- An invalid direct output rate resets active voices and produces silence. Playhead queries reject malformed voice positions and output-rate state.
- Direct regressions cover notes outside 0–127, a non-finite voice position, and a zero output rate. The focused player and sample-store suite passed 20/20 tests.

### Autonomous Follow-up: Installed Realtime Model Surface

- The staged-package consumer now exercises the public piano, step sequencer, process audio view, output event writer, sample store, and sample player contracts.
- The test composes and runs these models only through `@import("zig-vst3-plugin")`, so missing exports and repository-relative dependencies fail at the package boundary.
- The installed-package gate passed 9/9 build steps and 9/9 tests.

### Autonomous Follow-up: Atomic Parameter State

- Atomic normalized-value reads now clamp malformed direct bit patterns instead of asserting that all callers preserved the constructor invariant.
- Direct regressions cover NaN, positive infinity, and a negative value written through the public atomic field.
- The complete deterministic gate passed 111/111 steps and 4,199/4,199 tests.

### Autonomous Follow-up: Convolution Runtime Integrity

- The partitioned convolver now validates active, pending, replaced, and staging slot indices before access. Active slots require the reading state, bounded metadata, prepared counts, and a valid prepared rate.
- Malformed processing cursors reset at the next frame boundary. Non-finite input samples are replaced with silence before entering retained blocks.
- Direct regressions cover invalid slot indices, publication recovery, out-of-range processing cursors, and non-finite input. The focused convolver suite passed 10/10 tests.

### Autonomous Follow-up: IR Editor State Integrity

- IR editor commands, rollback, reset, snapshots, decoded copies, and preview construction now validate retained sample rate, channel count, frame counts, peaks, and rollback bounds before slice arithmetic.
- Malformed state publishes an empty snapshot and no decoded data. Clear remains an explicit recovery path, and an invalid rollback is discarded without replacing the edited buffer.
- Direct regressions cover oversized edited and rollback frame counts plus an invalid channel count. The focused editor and importer suite passed 17/17 tests.

### Autonomous Follow-up: Realtime State Release Gates

- The complete deterministic gate passed 111/111 steps and 4,202/4,202 tests. Native address and undefined-behavior sanitizers passed, the resource ThreadSanitizer passed 31/31 tests, and the GUI ThreadSanitizer completed four adapter concurrency runs.
- All 11 headless editor lifecycle targets passed 39/39 steps and 2,120/2,120 tests. Raw ABI checks passed 123/123 steps, and all 19 example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps. The C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 437.7 ns per framework process block, 1,458.5 MiB/s bounded WAV import, 9.0 ns per sample-player frame with eight voices available, 589.8 ns per IR convolution sample, and 39.7 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched during this autonomous pass.

### Autonomous Follow-up: DSP and Resource State Integrity

- Biquad coefficients, retained delay state, and complex responses now reject non-finite values. Extreme finite responses use scaled magnitude arithmetic instead of overflowing intermediate squares.
- Linear, exponential, and logarithmic smoothers contain malformed retained values at every public access and mutation boundary.
- Streaming resamplers bound their retained timeline before integer conversion. Fixed-rate pipelines verify both conversion stages, matching rates, pending storage, and reported latency before processing.
- Resource jobs validate progress, cancellation, result, status, and failure coherence. Fixed-slot resource exchange validates pending and active indices before every array access.
- Telemetry snapshots reject non-finite values, queue readers recover from malformed public cursors, importer progress is bounded, and process-segment cursors terminate safely.
- Public parameter-change and event collections expose full block validation. Parameter latches reject malformed changes and repair invalid retained normalized values.
- The staged-package consumer exercises the DSP, telemetry, parameter-change, event, resource, and C-kernel contracts through installed public imports. Its gate passed 9/9 steps and 10/10 tests.

### Autonomous Follow-up: DSP State Release Gates

- The complete deterministic gate passed 111/111 steps and 4,213/4,213 tests. Raw ABI checks passed 123/123 steps.
- Native address and undefined-behavior sanitizers passed. The resource ThreadSanitizer passed 33/33 tests, and the GUI ThreadSanitizer completed four adapter concurrency runs.
- All 11 headless editor lifecycle targets passed 39/39 steps and 2,120/2,120 tests. All 19 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 example matrices each passed 59/59 steps. The C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- DSP parity passed for `f32` and `f64` with fixed and randomized block boundaries. The fixture runner also cross-compiled for Linux aarch64, Linux x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 279.9 ns per framework process block, 1,388.2 MiB/s bounded WAV import, 9.1 ns per sample-player frame with eight voices available, 591.8 ns per IR convolution sample, and 44.8 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched during this autonomous pass. Manual host checks remain deferred.

### Autonomous Follow-up: Persistent Snapshot Integrity

- IR editor snapshots now validate nested import state, frame capacity, sample metadata, finite peaks, and edited-state coherence. Decoded import snapshots validate status, failure, metadata, preview, and decoded-frame relationships.
- Sample and convolution handoff metadata now has a public bounded validation contract. Staging validates metadata before overflow-safe chunk arithmetic.
- Empty generic imports now clear work progress. Generated lifecycle transitions call the public snapshot validator after every operation.
- Resource recovery now validates both retained and presentation snapshots. Editor activity counts saturate instead of wrapping to inactive.
- The staged-package consumer exercises these contracts through installed public imports. The deterministic gate passed 111/111 steps and 4,220/4,220 tests.
- Raw ABI, native GUI sanitizers, resource and GUI ThreadSanitizer, all headless editor lifecycles, DSP parity, C-kernel builds, and performance budgets passed in a 185/185-step gate with 2,161/2,161 tests.
- All 19 native plugins passed all 47 Steinberg validator tests. Linux aarch64 and Windows x86-64 matrices each passed 59/59 steps.
- Representative measurements were 292.9 ns per framework block, 1,323.2 MiB/s bounded WAV import, 9.4 ns per sample-player frame, 589.8 ns per IR sample, and 45.2 ns per fixed-rate frame at 48 kHz.
- Commits: `0974ff5`, `ae15cce`, `3374f60`, `ac52df3`, `a480e85`, and `de9c49b`.
- No REAPER or pluginval process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Telemetry, File Drop, and Parameter Boundaries

- SPSC queue and graph snapshot drop counters now saturate at the maximum `usize` value instead of wrapping to zero and hiding earlier data loss.
- Graph snapshot publication recovers a directly corrupted sequence counter at the integer boundary while preserving the odd writing and even stable-state protocol.
- Scalar telemetry loads contain directly corrupted NaN and infinity bit patterns. Spectrum analyzers reset malformed retained ring cursors before indexing or incrementing their fixed storage.
- File-drop paths reject embedded NUL bytes in directly modified storage. Retained extension configuration is revalidated before matching, and completion cannot turn rejected or malformed partial input into an accepted result.
- Directly constructed float, logarithmic, and integer parameter descriptors now validate their ranges before clamp, normalization, denormalization, formatting, or host metadata conversion. Invalid descriptors return neutral values and no plain bounds instead of reaching assertions, division by zero, logarithms, or float-to-integer conversion.
- Direct regressions cover saturated counters, publication after saturation, sequence recovery, corrupted scalar bits, malformed spectrum cursors, invalid paths and extensions, out-of-order completion, malformed numeric descriptors, and valid recovery.
- The complete deterministic gate passed 111/111 steps and 4,227/4,227 tests. Raw ABI checks passed 123/123 steps.
- Native address and undefined-behavior sanitizers passed. The resource ThreadSanitizer passed 34/34 tests, and the GUI ThreadSanitizer completed four adapter concurrency runs.
- All 19 native plugins passed all 47 Steinberg validator tests. Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps.
- Performance budgets passed. Representative measurements were 286.5 ns per framework process block, 1,413.9 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 591.8 ns per IR sample, and 45.5 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Process Attachment Integrity

- Plugin topology, audio layouts, ordered process iterators, parameter-change collections, event collections, audio views, and unit lookup helpers were audited for malformed directly constructed state. Their existing bounded and saturating paths did not require changes.
- Process contexts now reject an output event writer whose retained count or retained events are invalid, even when its frame count matches the process block.
- Direct regressions cover an output writer count beyond storage and a retained event outside the process block. Both setter and constructor attachment paths fail without publishing the invalid writer.
- The complete deterministic gate passed 111/111 steps and 4,227/4,227 tests. The broader Phase 1 integration gate passed 309/309 steps with the same 4,227 tests, and raw ABI checks passed 123/123 steps.
- Native address and undefined-behavior sanitizers passed. The resource ThreadSanitizer passed 34/34 tests, and the GUI ThreadSanitizer completed four adapter concurrency runs.
- All 11 headless editor lifecycle targets passed 39/39 steps and 2,120/2,120 tests. All 19 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps. The C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 279.9 ns per framework process block, 1,441.2 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 584.0 ns per IR sample, and 44.8 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Mutable Boundary Revalidation

- File-import generations now remain nonzero across integer saturation. Begin, retry, and reset all recover from a directly corrupted maximum generation without publishing the zero value reserved for invalid retained paths.
- Process contexts revalidate attached output event writers on every access. Later direct mutations to count, retained events, or frame count hide the writer and reject appends until the writer is repaired.
- Resource paths reject embedded NUL bytes introduced through public inline storage. Resource-reference validation, sizing, classification, and serialization all fail closed without partial output.
- Direct GUI gestures sanitize their initial and performed normalized values. Reversed directly constructed resize bounds are treated as unordered endpoints, preventing a trapping clamp while retaining bounded behavior.
- Fixed-rate pipelines reject publicly exposed resampler stages that have entered a draining state. Conversion now reports `InvalidState` instead of reaching an impossible-error branch.
- Unit metadata, topology, attachment transactions, parameter collections, snapshots, retained GUI collections, and the remaining production `unreachable` sites were audited. Existing validation was sufficient and no additional changes were required.
- Focused path, reference, GUI, importer, process-context, and fixed-rate tests passed. The complete deterministic gate passed 111/111 steps and 4,233/4,233 tests. The broader Phase 1 gate passed 309/309 steps with the same 4,233 tests.
- Raw ABI checks passed 123/123 steps. Native address and undefined-behavior sanitizers passed, the resource ThreadSanitizer passed 36/36 tests, and the GUI ThreadSanitizer completed four adapter concurrency runs.
- All 11 headless editor lifecycle targets passed 39/39 steps and 2,120/2,120 tests. All 19 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps. The C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 282.6 ns per framework process block, 1,413.7 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 597.7 ns per IR sample, and 45.4 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Native, Serialization, and Packaging Boundaries

- Native normalized-value handling now maps NaN to zero before clamping. Initial values, host updates, modulation, and gesture callbacks cannot retain or publish NaN.
- Accessibility ranges reject non-finite endpoints, sort reversed finite endpoints, map a NaN current value to the lower endpoint, and clamp infinities.
- Native editor construction and opening contain C++ allocation failures at the C ABI boundary. Failed opens attempt bounded lifecycle cleanup and return the existing failure result.
- Controller-state serialization validates the editor payload size before writing its envelope or parameter payload. Invalid editor state now leaves the destination stream unchanged.
- macOS, Linux, and Windows bundle scripts validate their library, bundle suffix, platform directory, and executable name before recursively replacing a bundle. A permanent runner covers successful layouts and verifies that rejected arguments preserve existing targets.
- Installed-package, validator, and pluginval test runners now use atomically created temporary directories instead of predictable PID-based paths.
- The complete deterministic gate passed 112/112 steps and 4,243/4,243 tests. Raw ABI checks passed 123/123 steps, and the broader Phase 1 gate passed.
- Native address and undefined-behavior sanitizers passed. The GUI ThreadSanitizer completed four adapter concurrency runs.
- All 11 headless editor lifecycle targets passed 39/39 steps and 2,126/2,126 tests. All 19 native plugins passed all 47 Steinberg validator tests.
- Linux x86-64 and Windows x86-64 bundle matrices each passed 59/59 steps. Performance budgets passed, including a 290.9 ns framework process block, 1,361.0 MiB/s bounded WAV import, 9.4 ns per sample-player frame, 595.7 ns per IR sample, and 45.8 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Rollover and Transition Integrity

- The GUI note mailbox now skips its all-zero sentinel when the packed sequence counter rolls over. A channel-zero note release with zero velocity remains observable instead of disappearing at the integer boundary.
- Sample-player voice ages are rebased in deterministic oldest-to-newest order before exhaustion. Voice stealing and newest-playhead selection remain correct across age rollover, and malformed active voices with a zero age are discarded.
- File-import transitions revalidate their complete retained snapshot before mutating progress, cancellation, or terminal state. Non-progress terminal states clear stale work counters, while begin and reset remain explicit recovery paths.
- Every native editor C entry point now contains C++ exceptions. Canvas drawing entry points also reject non-finite geometry, line widths, and alpha values before calling VSTGUI, and drawing failures cannot unwind across the C ABI.
- The pluginval runner now uses a portable empty `CDPATH` assignment. Its parser tests and warning-level shell checks pass.
- The complete deterministic gate passed 112/112 steps and 4,255/4,255 tests. Raw ABI, Phase 1 integration, native address and undefined-behavior sanitizers, both ThreadSanitizer gates, and all 11 headless editor lifecycle targets passed.
- All 19 native plugins passed all 47 Steinberg validator tests. Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps, and the C-kernel export matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- Performance budgets passed. Representative measurements were 402.9 ns per framework process block, 334.1 MiB/s bounded WAV import, 10.2 ns per sample-player frame, 634.8 ns per IR sample, and 46.7 ns per fixed-rate frame at 48 kHz.
- No REAPER or pluginval application process was launched. Manual host checks remain deferred.

### Autonomous Follow-up: Publication and Graphics State Integrity

- Resource exchange, recovery, decoded-sample publication, and IR convolution now use one bounded serial-generation ordering rule. Generation 1 follows `maxInt(u64)`, zero remains invalid, and the ambiguous half-range distance is rejected.
- Bounded resource adoption uses the same serial ordering on both sides of rollover. A directly corrupted pending generation of zero is retired and reclaimed instead of becoming active or leaving the pending queue wedged.
- Decoded-audio transport preserves the complete unsigned generation bit pattern through VST's signed 64-bit message attribute. IR Loader and Sample Player transfer counters now wrap from `maxInt(u64)` to 1 without entering a permanently rejected range.
- Native drawing callbacks cannot unwind through the C ABI or leak VSTGUI graphics state. Scope guards restore clipping and drawing state after normal drawing, missing-asset fallback, and exceptions from user drawing callbacks.
- Asset-store replacement is transactional. Duplicate identifiers and malformed replacement assets leave the previous valid asset set intact.
- Empty editor envelopes now accept a null data pointer when their point count is zero. Nonempty envelopes still require a valid pointer and retain the existing size and value validation.
- Bundle component names reject separators and unsafe characters on all platforms. macOS bundle identifiers and versions also reject XML metacharacters before `Info.plist` generation, and permanent script regressions verify that every rejected request preserves the existing target.
- Strictness-10 pluginval found subnormal output in the Fixed Rate example at 48 and 96 kHz. Its audio callback now uses the framework's scoped flush-to-zero policy without leaking the host thread's prior floating-point control state. A direct regression covers subnormal containment and exact control-state restoration.
- The complete deterministic gate passed 112/112 steps and 4,283/4,283 tests. Phase 1 passed 310/310 steps, raw ABI passed 123/123 steps, and all 11 headless editor lifecycle targets passed 39/39 steps with 2,144/2,144 tests.
- Native address and undefined-behavior sanitizers passed. The GUI ThreadSanitizer completed four adapter concurrency runs, and the resource ThreadSanitizer passed 40/40 tests.
- All 19 native plugins passed all 47 Steinberg validator tests. Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps, and the C-kernel matrix passed macOS universal, Linux aarch64 and x86-64, and Windows x86-64.
- All 19 plugins passed pluginval serially at strictness 10 after the Fixed Rate repair, including editor, non-releasing processing, state restoration, background-state, parameter-thread-safety, and parameter-fuzzing checks.
- Performance budgets passed. Representative measurements were 301.3 ns per framework process block, 1,418.9 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 603.5 ns per IR convolution sample, and 44.6 ns per fixed-rate frame at 48 kHz.
- Manual REAPER, VoiceOver, Narrator, native Windows, native Linux, and multi-monitor smoke tests remain deferred because they require interactive observation or unavailable native infrastructure.

### Autonomous Follow-up: Soak and Runner Reliability

- The native VSTGUI address and undefined-behavior sanitizer soak completed eight repetitions of the adapter, accessibility, and visual suites. All 24 processes passed. Artifacts were retained under `20260723-215716-70710`.
- The headless GUI lifecycle soak completed three repetitions across all 11 plugin editors, with 12 create, open, close, and destroy cycles per target. All 396 editor lifecycles passed. Artifacts were retained under `20260723-215808-71330`.
- The lifecycle soak runner now has a portable fake-tool regression. It verifies all plugin targets, repetition and lifecycle accounting, per-run command and status artifacts, injected failure propagation, immediate early stop, and invalid repetition rejection.
- The lifecycle script is now executable in the repository, matching its direct invocation by the build and runner scripts.
- The Fixed Rate denormal regression now exercises both `f32` and `f64`. It verifies that every emitted sample is zero or normal and that the host thread's prior flush-to-zero policy is restored exactly.
- The final deterministic gate passed 113/113 steps and 4,283/4,283 tests, including the new lifecycle runner regression. The broader Phase 1 gate passed 311/311 steps with all 19 plugins passing all 47 Steinberg validator tests.
- A 161 GiB repository-local `.zig-cache` was removed after it exhausted the build volume. The cache is entirely regenerable and was rebuilt by the final gate. The separate untracked `.zig-global-cache` was not modified.
- Remaining deferred checks require interactive host, screen-reader, native Windows or Linux desktop, or multi-monitor observation.

### Autonomous Follow-up: Transactional Packaging and Interrupt Artifacts

- macOS, Linux, and Windows bundlers now assemble replacements in unique same-parent staging directories. Validation or copy failure cleans the staging directory and preserves the previous complete bundle.
- Portable regressions inject copy failures into all three bundlers and verify that the previous marker remains present and no staging directory leaks.
- The GUI ThreadSanitizer runner now writes the same bounded interruption artifact as the other soak runners, including signal name, conventional exit status, active iteration, phase, and timestamps.
- Lifecycle, address and undefined-behavior sanitizer, and ThreadSanitizer runner tests now inject `TERM` deterministically. All three verify exit status 143, interrupted classification, active work identity, and absence of a false success artifact.
- The real GUI ThreadSanitizer completed four adapter concurrency runs. Artifacts were retained under `20260724-081540-69233`.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 59/59 steps with transactional replacement enabled.
- The final deterministic gate passed 113/113 steps and 4,283/4,283 tests. The broader Phase 1 gate passed with all ABI checks and all 19 plugins passing all 47 Steinberg validator tests.
- Remaining deferred checks require interactive host, assistive-technology, native desktop, or multi-monitor observation.

### Autonomous Follow-up: Process Modes and Framework Scope

- The high-level framework now exposes VST3 realtime, prefetch, and offline process modes. The mode reaches both `PrepareConfig` and every `ProcessContext`, with direct query helpers for processing policy.
- Setup and per-block bridge paths validate the raw VST3 process-mode value. Invalid values fail closed instead of reaching plugin code, while directly constructed framework contexts retain a realtime default.
- Public installed-package coverage compiles and exercises the new mode type, prepare configuration, context construction, and query helpers.
- A capability matrix now separates missing plugin-authoring features from broader application-framework scope. Multi-bus topology and sidechains are the highest-value remaining VST3 framework work.
- The final deterministic gate passed 113/113 steps and 4,283/4,283 tests. The installed-package consumer passed 14/14 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 19 plugins passed all 47 Steinberg validator tests.
- Performance budgets passed. Representative measurements were 297.8 ns per framework process block, 1,448.8 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 589.8 ns per IR convolution sample, and 44.5 ns per fixed-rate frame at 48 kHz.
- Remaining deferred checks require interactive host, assistive-technology, native desktop, or multi-monitor observation.

### Autonomous Follow-up: Surround Layouts and MIDI Messages

- The public main-bus model now covers quadraphonic, 5.1, 7.1, and first-order ambisonic layouts in addition to absent, mono, and stereo buses. Each layout maps to its exact VST3 speaker arrangement and bounded channel count.
- A public 5.1 Surround Gain example processes all six channels through the high-level framework. Steinberg's validator discovers the exact 5.1 input and output buses, accepts both processing precisions, and rejects mono and stereo arrangements with the correct 5.1 suggestion.
- The framework now parses and generates complete MIDI 1 channel voice messages for notes, polyphonic key pressure, control changes, program changes, channel pressure, and 14-bit pitch bend. Checked normalization helpers preserve controller endpoints and the exact pitch-bend center. An incremental decoder supports running status and interleaved realtime bytes.
- MIDI note, polyphonic pressure, control-change, and pitch-bend messages convert in both directions with typed process events. Zero-velocity note-on converts to note-off. Malformed direct message state fails closed.
- The capability matrix distinguishes concrete plugin gaps from application-level facilities such as devices, hosting, transport, windowing, OpenGL, JavaScript, OSC, analytics, product unlocking, video, networking, cryptography, and interprocess communication.
- The complete deterministic gate passed 117/117 steps and 4,314/4,314 tests. The installed-package consumer passed 15/15 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 20 native plugins passed all 47 Steinberg validator tests.
- Surround Gain passed pluginval at strictness 10, including six-channel bus discovery, processing, state restoration, automation, background-state, parameter-thread-safety, and parameter-fuzzing checks.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 62/62 steps.
- Performance budgets passed. Representative measurements were 306.2 ns per framework process block, 1,269.8 MiB/s bounded WAV import, 9.4 ns per sample-player frame, 625.0 ns per IR convolution sample, and 45.7 ns per fixed-rate frame at 48 kHz.
- Remaining deferred checks require interactive host, assistive-technology, native desktop, or multi-monitor observation.

### Autonomous Follow-up: Bounded Auxiliary Audio Buses

- Plugin declarations now support one optional auxiliary sidechain input and one optional auxiliary output with the same bounded speaker layouts as the main buses. Each auxiliary bus requires its corresponding main bus and is inactive by default.
- `ProcessContext` exposes the sidechain through a separate read-only audio view and channel, sample, count, presence, and frame-count helpers. Main audio and key audio cannot be confused through channel indexing.
- Auxiliary output buffers have their own writable view and channel, sample, count, presence, fill, and clear helpers. Main and auxiliary output indexing remain separate.
- The VST3 bridge reports both optional buses as `kAux`, negotiates their arrangements independently, accepts an omitted or inactive auxiliary bus during processing, and rejects excess buses or channels.
- A public stereo Sidechain Ducker example uses a mono key input in both processing precisions. Direct tests cover active and inactive sidechain processing, topology reflection, arrangement negotiation, parameter flushes, installed-package use, and malformed host buffers.
- A public Auxiliary Output Splitter copies its stereo main bus and writes a separate mono mix. Strict pluginval exposed aliased in-place main buffers, which led to an alias-safe implementation and a permanent direct regression.
- The complete deterministic gate passed 125/125 steps and 4,367/4,367 tests. The broader Phase 1 gate passed 341/341 steps, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- Sidechain Ducker and Auxiliary Output Splitter passed pluginval at strictness 10, including bus enabling, non-main bus disabling, audio processing, state restoration, automation, background-state, parameter-thread-safety, and parameter-fuzzing checks.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 289.3 ns per framework process block, 1,430.4 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 640.6 ns per IR convolution sample, and 44.7 ns per fixed-rate frame at 48 kHz.
- Remaining deferred checks require interactive host, assistive-technology, native desktop, or multi-monitor observation.

### Autonomous Follow-up: Standard MIDI Files

- The public process package now parses Standard MIDI File formats 0, 1, and 2 from caller-owned bytes without allocation. Track iteration covers running status, channel messages, fixed-length validation for defined meta events, and `F0` or `F7` SysEx events.
- Metric and SMPTE divisions are checked. Tempo-aware tick conversion follows conductor-track tempo for format 1 and per-track tempo for format 2, including 29.97 drop-frame timing.
- The bounded writer emits headers, tracks, channel messages, meta events, SysEx events, and end-of-track markers into caller storage. Capacity failures do not partially append an event.
- Malformed structure, truncated prefixes, invalid variable-length quantities, event data after end-of-track, missing end-of-track events, and zero tempos fail closed.
- Public installed-package coverage writes, parses, times, and iterates a file. The installed consumer passed 17/17 tests.
- The complete deterministic gate passed 125/125 steps and 4,374/4,374 tests. The broader Phase 1 gate passed, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 301.0 ns per framework process block, 1,430.1 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 597.7 ns per IR convolution sample, and 45.2 ns per fixed-rate frame at 48 kHz.

### Autonomous Follow-up: MPE Zone Layouts

- The public process package now models lower and upper MPE zones with checked member-channel counts, 0–96 semitone per-note and master pitch-bend ranges, and zero-based channel indexes.
- Zone layouts classify member and master channels without allocation. Two active zones cannot overlap, while a single zone may use all 15 non-master channels.
- Zone replacement is transactional. Invalid pitch ranges, excessive channel counts, reversed zone types, and overlapping replacements leave the previous layout intact.
- Public installed-package coverage constructs and queries a two-zone layout and proves that an overlapping update is rejected transactionally. The installed consumer passed 18/18 tests.
- The complete deterministic gate passed 125/125 steps and 4,377/4,377 tests. The broader Phase 1 gate passed, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 68/68 steps.
- RPN synchronization was completed in the next follow-up, followed by expressive note state and member-channel allocation.

### Autonomous Follow-up: MIDI RPN and MPE Synchronization

- The public process package now decodes MIDI Registered Parameter Number selection and Data Entry independently across all 16 channels. Coarse CC 6 events and complete CC 6 plus CC 38 values retain their exact 14-bit parameter and value fields.
- RPN null selection, NRPN selection, and Reset All Controllers clear stale per-channel selection state. Fixed-size helpers generate coarse, fine, and null RPN message sequences without allocation.
- MPE zone synchronization consumes Configuration RPN 6 only on manager channels 0 and 15. The newest configuration takes precedence, shrinking or disabling the older zone when channel assignments would overlap.
- Pitch Bend Sensitivity RPN 0 updates manager or per-note ranges according to the message channel. Invalid member counts and ranges leave the previous layout unchanged.
- Fixed-size helpers generate MPE configuration and pitch-bend-range messages. Public installed-package coverage exercises generic RPN generation, MPE message generation, overlap priority, and range synchronization.

### Autonomous Follow-up: MPE Expressive Note State

- A fixed-capacity MPE instrument now tracks stable note IDs, key-down and sustained state, note velocities, per-note pitch bend, pressure, timbre, and combined manager plus member pitch bend in semitones.
- Member expression supports last, lowest, highest, and all-note tracking when MIDI Mode 3 places several notes on one channel. Manager pitch bend, pressure, and timbre broadcast across the selected zone.
- Manager-channel sustain retains note-off state until pedal-up. Capacity failure and malformed retained state fail without damaging active notes, and deterministic generated message sequences cover lifecycle invariants.
- A separate sender-side allocator assigns one note per member channel. It selects free channels deterministically and supports explicit rejection or oldest-assignment stealing, including the displaced assignment needed for a note-off.
- The installed-package consumer exercises note tracking, combined bend, allocation, and stealing through the public exports.
- The complete deterministic gate passed 125/125 steps and 4,396/4,396 tests. The installed-package consumer passed 19/19 tests.
- The broader Phase 1 gate passed 341/341 steps, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 301.2 ns per framework process block, 1,361.5 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 584.0 ns per IR convolution sample, and 44.8 ns per fixed-rate frame at 48 kHz.

### Autonomous Follow-up: Universal MIDI Packet Framing

- The public process package now owns checked Universal MIDI Packets in fixed four-word storage and validates the 32, 64, 96, or 128-bit length selected by every Message Type nibble.
- A borrowing iterator walks mixed-size word streams without allocation. Empty packets, incorrect explicit lengths, truncated final packets, and malformed retained cursors fail closed without advancing.
- MIDI 1 channel-voice conversion preserves group, status, channel, and all meaningful data bytes for note, pressure, controller, program, and pitch-bend messages.
- Canonical widening and narrowing covers 7 or 14-bit MIDI 1 values and 8, 16, or 32-bit MIDI 2 values. Exhaustive tests prove that every MIDI 1 source value survives a widen-and-narrow round trip.
- Public accessors distinguish groupless Utility and Stream packets, grouped packets, and channel-bearing MIDI 1 or MIDI 2 packets.
- The installed-package consumer exercises framing, iteration, and MIDI 1 round trips through public exports.
- The complete deterministic gate passed 125/125 steps and 4,402/4,402 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed 341/341 steps, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- The process core compiled directly for Linux aarch64 and Windows x86-64, and both complete example bundle matrices passed 68/68 steps.

### Autonomous Follow-up: Typed MIDI 2 and System Exclusive UMP

- Typed MIDI 2 channel messages cover all defined channel-voice statuses, including per-note controllers, note attributes, 32-bit controllers, program banks, and per-note management.
- Checked System Common and Real-Time packets cover time code, song position and selection, transport, timing, sensing, tuning, and reset messages.
- SysEx7 and SysEx8 packetizers borrow caller storage and emit correct complete, begin, continuation, and end sequences. Fixed-capacity reassemblers reject ordering, capacity, group, and stream mismatches without partial mutation.
- SysEx7 enforces 7-bit data and six-byte packet payloads. SysEx8 preserves arbitrary bytes, stream IDs, and thirteen-byte packet payloads.
- The staged installed-package consumer exercises MIDI 2, system messages, SysEx7, and SysEx8 through public exports.
- The complete deterministic gate passed 125/125 steps and 4,415/4,415 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed 341/341 steps, including all raw ABI checks and all 22 native plugins passing all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps. The Windows MSVC matrix compiled 21 bundles, but the C kernel bundle requires an external MSVC libc installation that is not present locally.
- Performance budgets passed. Representative measurements were 303.0 ns per framework process block, 1,358.0 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 607.4 ns per IR convolution sample, and 45.4 ns per fixed-rate frame at 48 kHz.

### Autonomous Follow-up: UMP Utility And Endpoint Messages

- Groupless Utility messages cover NOOP, JR Clock, JR Timestamp, Delta Clockstamp Ticks Per Quarter Note, and Delta Clockstamp. Parsing rejects the reserved address nibble, reserved data bits, unknown statuses, and zero delta-clock resolution.
- Fixed Stream messages cover endpoint discovery and information, device identity, stream configuration requests and notifications, function block discovery, and function block information. Function block group ranges and reserved fields are checked before publication.
- Bounded endpoint text packetization covers endpoint names, product instance IDs, and function block names. UTF-8 and length are validated before emission. Reassembly rejects malformed forms, padding, capacity, notification-kind, and function-block transitions without partial mutation.
- The staged installed-package consumer exercises Utility, endpoint information, and segmented endpoint names through the public exports.
- [Open Work](open-work.md) now consolidates automated verification, cleanup debt, feature work, and every outstanding manual host, visual, multi-monitor, and assistive-technology check. Automated passes are kept separate from manual confirmation.
- The complete deterministic gate passed 125/125 steps and 4,424/4,424 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 288.8 ns per framework process block, 1,427.0 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 587.9 ns per IR convolution sample, and 44.7 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: UMP Flex Data

- Typed fixed Flex Data messages cover tempo, time signature, metronome configuration, key signature, and chord name. Target requirements, reserved fields, tonic values, chord types, accidentals, and alterations are checked during encoding and parsing.
- Time signatures preserve numerators from 1 through 256. Chord names include four main-chord alterations, an alternate bass note, a bass chord, and two bass-chord alterations.
- Bounded Flex text packetization covers every standardized Metadata Text and Performance Text status. It validates UTF-8 before emission and enforces the 32-packet protocol limit.
- Fixed-capacity Flex text reassembly rejects malformed padding, packet order, target changes, kind changes, capacity overflow, and excess packet counts without partial mutation.
- The staged installed-package consumer exercises fixed Flex messages and segmented Flex text through public exports.
- [Open Work](open-work.md) records Mixed Data Sets, endpoint sessions, MIDI-CI work, device I/O, cleanup debt, and every outstanding manual confirmation separately.
- The complete deterministic gate passed 125/125 steps and 4,433/4,433 tests. The installed-package consumer passed 20/20 tests.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from the automated gate.

### Autonomous Follow-up: UMP Endpoint Responder Sessions

- `MidiEndpointResponder` validates borrowed endpoint identity, names, configuration, and up to 32 function-block descriptors before serving requests.
- Endpoint discovery replies, configuration notifications, function-block information, and segmented names are emitted lazily without allocation or an intermediate packet queue.
- Supported configuration requests update responder state only after the notification packet is constructed. Unsupported requests retain and report the current configuration.
- Maximum-response coverage emits 256 packets for 32 function blocks with 91-byte names. Another 32,768 generated requests check responder invariants and byte-for-byte state preservation after rejected transitions.
- The installed-package consumer runs requester and responder discovery, configuration, and function-block transactions entirely through public exports.
- [Open Work](open-work.md) now keeps the remaining MIDI-CI categories, device I/O, segmented-message cleanup, and every manual confirmation separate.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from this automated work.

### Autonomous Follow-up: MIDI-CI Discovery

- Typed MIDI-CI messages cover mandatory Discovery and Reply to Discovery in message format versions 1 and 2.
- `MidiCiInvalidation` covers the mandatory broadcast Invalidate MUID message and checked target matching.
- Validation covers 28-bit MUID restrictions, broadcast addressing, device identity, category bitmap reserved bits, the 128-byte minimum receivable SysEx size, output paths, and function-block association.
- Initiator and responder transaction helpers reject MUID collisions, mismatched destinations, mismatched output paths, invalid constructed messages, and fields unavailable in message format version 1.
- Encoded messages omit `F0` and `F7` for direct UMP SysEx7 carriage. The installed-package consumer packetizes, reassembles, parses, responds to, and correlates a discovery exchange through public exports.
- [Open Work](open-work.md) keeps Profiles, Property Exchange, Process Inquiry, remaining MIDI-CI management messages, device I/O, cleanup debt, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,451/4,451 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 297.4 ns per framework process block, 1,442.0 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 589.8 ns per IR convolution sample, and 44.9 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from this automated work.

### Autonomous Follow-up: UMP Mixed Data Sets

- Checked Mixed Data Set headers preserve group, MDS ID, valid byte count, chunk count and number, manufacturer ID, device ID, and both sub-IDs.
- A borrowing packetizer emits the header followed by 14-byte payload packets. It supports binary payloads through the largest byte count representable by the protocol header.
- A fixed-capacity reassembler derives the exact payload size from the header. It rejects invalid chunk numbering, capacity overflow, early or extra payloads, group or MDS ID changes, and nonzero final padding without partial mutation.
- Boundary tests cover every payload length from 0 through 128 bytes, including header-only chunks and every final-packet padding width.
- The staged installed-package consumer packetizes and reassembles a Mixed Data Set through public exports.
- The complete deterministic gate passed 125/125 steps and 4,433/4,433 tests. The installed-package consumer passed 20/20 tests.
- Endpoint sessions, MIDI-CI work, and device-facing MIDI I/O remain tracked in [Open Work](open-work.md).
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 300.1 ns per framework process block, 1,444.6 MiB/s bounded WAV import, 9.1 ns per sample-player frame, 599.6 ns per IR convolution sample, and 44.6 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: UMP Endpoint Requester Sessions

- Fixed Stream validation now enforces the protocol's 32-block limit, one-or-all discovery selector, nonreserved direction, single-group MIDI 1 proxy rule, and printable-ASCII product instance IDs.
- Fixed Stream messages now include Start of Clip and End of Clip boundary markers. Higher-level MIDI Clip timing and Delta Clockstamp sequencing remain caller policy.
- Endpoint names now cover the full 98-byte protocol limit. Function-block names reject reserved block numbers.
- `MidiEndpointRequester` tracks endpoint discovery, current and requested configurations, declared function blocks, text replies, and outstanding reply masks without allocation. Independent endpoint replies can arrive in any order.
- Configuration requests do not change current state before a notification. Unsupported protocol or JR timestamp selections, changed block counts, undeclared blocks, inactive static blocks, and later changes to static block information fail transactionally.
- Deterministic generated coverage exercises 32,768 mixed valid and invalid transitions and checks the session invariant after every accepted transition and byte-for-byte state preservation after every rejected transition.
- The installed-package consumer exercises requester discovery, negotiation, all-block discovery, fixed notifications, and completed function-block text through public exports.
- Shared UMP byte access is consolidated for SysEx7, SysEx8, Stream, endpoint text, Flex Data, Flex text, and Mixed Data Set implementations.
- [Open Work](open-work.md) keeps responder-side sessions, MIDI-CI work, device I/O, remaining segmented-message cleanup, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,438/4,438 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 310.2 ns per framework process block, 1,257.3 MiB/s bounded WAV import, 9.6 ns per sample-player frame, 623.0 ns per IR convolution sample, and 46.4 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from the automated gate.

### Autonomous Follow-up: MIDI-CI Management And Process Inquiry

- MIDI-CI Endpoint Information request and reply messages validate version 2 addressing, status, exact lengths, and printable Product Instance IDs up to 16 bytes. Correlated initiator and responder helpers reject MUID mismatches and collisions.
- ACK and NAK messages cover channel, group, and function-block addressing, bounded 103-byte text, timeout-wait status data, version 2 extensions, and the shorter version 1 NAK form.
- Process Inquiry capability negotiation reports MIDI Message Report support through a fixed request and reply transaction.
- MIDI Message Report envelopes cover capability-only, non-default, and full requests; System, Channel Controller, and Note Data bitmaps; supported-subset replies; and correlated Begin and End state transitions. Device-specific MIDI state remains caller-provided between the markers.
- Encoding and parsing reject reserved data controls, bitmap bits, address ranges, versions, lengths, MUIDs, reply supersets, repeated transitions, and mismatched endpoints without advancing transaction state.
- The installed-package consumer exercises Endpoint Information, ACK, Process Inquiry capability negotiation, and a complete report envelope through public exports.
- [Open Work](open-work.md) now keeps MIDI-CI Profiles, Property Exchange, device I/O, cleanup debt, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,465/4,465 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 301.8 ns per framework process block, 1,413.9 MiB/s bounded WAV import, 9.2 ns per sample-player frame, 599.6 ns per IR convolution sample, and 45.0 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from the automated gates.

### Autonomous Follow-up: MIDI-CI Profiles And Property Exchange Transport

- Profile Configuration now covers Profile Inquiry and bounded enabled and disabled lists, Set Profile On and Off, Enabled and Disabled reports, Added and Removed reports, Profile Details, registered channel-count details, and bounded Profile Specific Data.
- Profile transactions correlate MUIDs, versions, addresses, Profile IDs, and Details targets. Function-block discovery enforces channel replies before group replies and requires the function-block reply as the final marker.
- Property Exchange capability transactions negotiate request limits and version fields across MIDI-CI message formats 1 and 2, including responder downgrade.
- Bounded Property Exchange messages cover Get, Set, Subscription, their replies, and Notify. Validation covers request IDs, exact lengths, 7-bit data, header placement, known and unknown chunk counts, early completion, and aborted transfers.
- Transactional Property Exchange reassembly preserves retained bytes after rejected chunks. A fixed request-ID allocator bounds concurrent requests without heap allocation.
- The installed-package consumer exercises Profile discovery, Profile state changes, Details, Profile Specific Data, Property Exchange capabilities, data envelopes, reassembly, and request IDs through public exports.
- [Open Work](open-work.md) keeps Property Exchange JSON resource semantics, device I/O, cleanup debt, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,488/4,488 tests. The installed-package consumer passed 20/20 tests.
- The broader Phase 1 gate passed all raw ABI checks, and all 22 native plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- Performance budgets passed. Representative measurements were 300.6 ns per framework process block, 1,273.9 MiB/s bounded WAV import, 9.3 ns per sample-player frame, 605.5 ns per IR convolution sample, and 45.6 ns per fixed-rate frame at 48 kHz.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from the automated gates.

### Autonomous Follow-up: Property Exchange Semantics

- Strict common JSON headers cover Get and Set requests, pagination, partial updates, replies, subscriptions, and Notify. Parsing checks first-property ordering, structural whitespace, 7-bit transport bytes, constrained identifiers, field types, encoding names, and defined status values.
- Mcoded7 encoding and decoding use caller storage, cover every short-group boundary, reject noncanonical prefixes, and validate the complete input before changing destination bytes.
- ResourceList models apply the standard capability, media-type, and encoding defaults. They reject duplicate resources and the forbidden ResourceList self-entry.
- Foundational models cover DeviceInfo identity fields, ChannelList programs and clusters, resource links, escaped Unicode output, and bounded JSON Schema documents.
- The installed-package consumer exercises common headers, Mcoded7, ResourceList, and ChannelList through public exports.
- [Open Work](open-work.md) now keeps Property Exchange 1.2 review, higher-level request and subscription sessions, additional standardized resources, zlib compression, device I/O, cleanup debt, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,500/4,500 tests. The installed-package consumer passed 20/20 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Property Exchange Sessions And Compression

- `MidiCiPropertyInitiator` owns a bounded request-ID pool, sequences outgoing Get, Set, and Subscription chunks, correlates replies by version and both MUIDs, retains completed responses until release, and handles wait, terminate, and timeout notifications.
- `MidiCiPropertyResponder` bounds simultaneous remote requests, reassembles each request by remote MUID and request ID, rejects duplicate or mismatched transitions without changing retained data, and sequences the corresponding reply.
- `MidiCiPropertySubscriptionRegistry` owns resource and subscription identifiers, correlates partial, full, notify, and end commands, and releases all state for a disconnected remote.
- `MidiCiPropertyZlibMcoded7` combines the standardized zlib container with canonical Mcoded7. It uses caller-owned compression, history, staging, and destination buffers, checks the zlib header and checksum, rejects trailing or malformed data, and leaves the published destination unchanged on failure.
- The installed-package consumer completes a request and reply through both session caches, exercises subscription ownership, and round trips zlib+Mcoded7 through public exports.
- [Open Work](open-work.md) now keeps Property Exchange 1.2 review, the unified Device and Property Host facade, persistent remote resource caching, additional standardized resources, device I/O, cleanup debt, environment-limited validation, and every manual confirmation separate.
- The focused Property Exchange suite passed 27/27 tests. The complete deterministic gate passed 125/125 steps and 4,505/4,505 tests. The installed-package consumer passed 20/20 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Static Multi-Bus Topology

- Plugin declarations and the reusable VST3 effect shell accept static lists of up to eight auxiliary audio buses in each direction. The original sidechain and auxiliary-output declarations remain compatibility aliases for the first bus.
- Process contexts retain flattened compatibility accessors and add bounded per-bus views. Host routing preserves bus boundaries, supports inactive trailing buses, and rejects excess buses, channels, invalid partitions, and malformed ranges.
- The layout catalog now covers mono, stereo, 3.0, quadraphonic, 5.0, 5.1, 7.0, 7.1, 5.1.2, 7.1.4, and first- through third-order ambisonics with exact VST3 speaker arrangements.
- The auxiliary-output splitter now exposes a stereo main output, mono auxiliary downmix, and stereo auxiliary copy. Unit, bridge, installed-package, metadata, arrangement, processing, and compatibility coverage exercise multiple buses.
- The host tracker keeps real routing and audible confirmation of the sidechain ducker and all splitter outputs deferred. Automated validation does not close those rows.
- The complete deterministic gate passed 125/125 steps and 4,539/4,539 tests. The installed-package consumer passed 20/20 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Unified MIDI-CI Device And Remote Cache

- `MidiCiDevice` owns a fixed-capacity remote registry and composes Discovery, Endpoint Information, Profile Configuration, Property Exchange, Process Inquiry, subscriptions, and negotiated remote state behind stable handles.
- The device answers endpoint, property-capability, and process-capability inquiries from its local configuration. It rejects operations that either participant did not advertise.
- Invalidate MUID and explicit removal release the remote, outstanding initiator and responder sessions, subscriptions, and cached property values together. A changed rediscovery clears state that no longer belongs to the reported participant.
- `MidiCiPropertyRemoteCache` stores bounded remote resource values by MUID, resource, and optional resource ID. Replacement is transactional, updates receive nonzero generations, and capacity failures preserve existing values.
- The installed-package consumer exercises the device registry, profile inquiry, invalidation cleanup, and remote cache through public exports.
- [Open Work](open-work.md) keeps Property Exchange 1.2 review, delegate-driven Property Host policy, cross-session cache persistence, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,545/4,545 tests. The installed-package consumer passed 20/20 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: MIDI-CI Profile And Property Hosts

- `MidiCiProfileHost` owns bounded local profile state, produces presence and enablement reports, answers address-scoped inquiries, and dispatches enablement, details, and profile-specific data through a typed delegate.
- `MidiCiPropertyHost` reassembles bounded Get, Set, and Subscription requests, parses strict JSON headers, invokes a typed delegate, produces checked replies, and applies subscription changes transactionally.
- `MidiCiDevice` exposes borrowed Profile and Property Hosts over device-owned state. Its outgoing Property Get path enforces negotiated capabilities, handles reply and Notify completion, and caches successful non-paginated values.
- The installed-package consumer exercises both delegate hosts and the Device Get-to-cache path through public exports.
- [Open Work](open-work.md) keeps Property Exchange 1.2 review, cross-session cache persistence, additional standardized resources, device I/O, cleanup debt, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,551/4,551 tests. The installed-package consumer passed 20/20 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Persistent MIDI-CI Cache And DSP Primitives

- `MidiCiPropertyRemoteCache` now writes a versioned snapshot into caller storage and restores generations, resource IDs, and values without allocation. Restore parses into temporary state and publishes only after the complete input is valid.
- Snapshot validation rejects bad magic, unsupported versions, invalid MUIDs, duplicate keys, impossible lengths, zero generations, truncation, trailing bytes, and undersized output buffers. Rejected input leaves the live cache unchanged.
- `MidiCiDevice` exposes cache lookup, sizing, write, and restore operations without exposing its internal cache. The installed-package consumer exercises the complete public snapshot round trip.
- `Oscillator(f32)` and `Oscillator(f64)` provide sine, triangle, saw, and square generation with checked configuration and continuous phase across blocks. The nonsine waveforms are direct forms and are not bandlimited.
- `Compressor(f32)` and `Compressor(f64)` provide checked threshold, ratio, attack, release, and makeup controls with a peak envelope. Lookahead, soft knee, sidechain filtering, and channel linking remain future DSP work.
- Additional standardized Property Exchange resources were not implemented from inferred schemas. ResourceList, DeviceInfo, ChannelList, and JSONSchema remain the foundational typed set until normative schemas for other resources are available to the project.
- The complete deterministic gate passed 125/125 steps and 4,557/4,557 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Reusable Delay, Panning, Dynamics, And Convolution

- `DelayLine(f32, capacity)` and `DelayLine(f64, capacity)` own fixed inline history, preserve positions across blocks, and support checked linear and four-point cubic fractional reads.
- `StereoPanner(f32)` and `StereoPanner(f64)` apply an equal-power mono-to-stereo law with checked positions and exact buffer-length validation.
- `NoiseGate` adds peak-envelope downward expansion. `Limiter` adds instantaneous sample-peak reduction with a checked release stage. The limiter has no lookahead, oversampling, inter-sample peak detection, or channel linking.
- The IR Loader's three-slot partitioned convolver is now exported through `zig-vst3-plugin.dsp`. Its staging, generation publication, resampling, bounded memory, and fixed partition latency remain unchanged.
- The installed-package consumer exercises delay, panning, gating, limiting, and staged convolution through public DSP exports.
- The complete deterministic gate passed 125/125 steps and 4,566/4,566 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Shared FFT And FIR

- `Fft(f32, size)` and `Fft(f64, size)` provide fixed-size radix-2 forward, inverse, and real-input transforms with precomputed twiddles. The inverse transform is normalized, and invalid input is rejected before the caller's buffer changes.
- The spectrum analyzer and partitioned convolver now use the public transform. Their duplicate private FFT implementations were removed.
- `FirFilter(f32, capacity)` and `FirFilter(f64, capacity)` own fixed coefficient and history storage, replace coefficients transactionally, reset history after reconfiguration, and process samples with direct time-domain convolution.
- The installed-package consumer exercises the public FFT and FIR exports.
- [Open Work](open-work.md) keeps optimized and arbitrary-size transform backends, broader modulation and oversampling families, inter-sample limiting, audio file writing and codec support, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,572/4,572 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Window Functions, FIR Design, And Oversampling

- Public window functions cover rectangular, triangular, Hann, Hamming, Blackman, Blackman-Harris, flat-top, and configurable Kaiser shapes with symmetric or periodic layout and optional unit-sum or unit-peak normalization.
- `FirDesigner(f32)` and `FirDesigner(f64)` produce checked odd-length low-pass, high-pass, band-pass, and band-stop coefficients and evaluate their magnitude response.
- The public FFT adds real inverse and nonnegative-frequency magnitude helpers. Both reject invalid input before changing caller output.
- `Oversampler(Sample, maximum_frames, factor)` provides bounded single-channel 2x, 4x, 8x, or 16x FIR oversampling. It owns high-rate storage, retains filter state across blocks, reports eight base-rate samples of latency, and checks upsample and downsample sequencing.
- The installed-package consumer exercises window generation, FIR design, and mutable high-rate oversampling through public exports.
- [Open Work](open-work.md) keeps optimized transform and multistage polyphase backends, modulation effects, inter-sample limiting, audio writers and codecs, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,585/4,585 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Mixing, Waveshaping, Chorus, And Phaser

- `DryWetMixer` pairs bounded dry and wet blocks, compensates zero through a compile-time maximum fractional wet latency, and applies linear or equal-power gains. Invalid input, frame mismatches, and reconfiguration while a block is pending preserve the retained dry block.
- `WaveShaper` provides hard-clip, hyperbolic-tangent, arctangent, and cubic curves with checked drive, output gain, dry/wet mix, and derived public state.
- `Chorus` uses sine-modulated cubic delay with checked center, depth, rate, feedback, and mix. It preserves modulation, delay, and feedback state across block boundaries.
- `Phaser` cascades one through sixteen first-order all-pass stages with a logarithmic sine sweep, bounded feedback, and checked mixing.
- The installed-package consumer exercises all four capabilities through public exports.
- [Open Work](open-work.md) keeps parameter smoothing, TPT, ladder, and crossover filters, reverb, additional modulation effects and mixing laws, processor composition and lookup utilities, optimized backends, inter-sample limiting, audio writers and codecs, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,597/4,597 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Filters, Reverb, Lookup, And Composition

- `StateVariableFilter` provides topology-preserving low-pass, band-pass, high-pass, notch, and all-pass processing with checked cutoff and Q.
- `LinkwitzRileyFilter` splits one input through fourth-order low-pass and high-pass cascades. Both branches meet at 6 dB below unity and can transition to new coefficients over a bounded sample count.
- `Reverb` owns a bounded stereo network of damped comb and serial all-pass filters. It checks sample-rate-derived delay lengths and retains its tail across host block boundaries.
- `LookupTable` samples a finite-range function into fixed storage and linearly interpolates scalar or block input. `ProcessorChain` owns a nonempty processor tuple with indexed access, bypass mutation, and bypass inspection.
- Dry/wet mixing now covers linear, balanced, equal-power, sine-based 3 dB, 4.5 dB, and 6 dB laws, plus square-root 3 dB and 4.5 dB laws.
- The installed-package consumer exercises all five capabilities through public exports.
- [Open Work](open-work.md) keeps ladder and higher-order filter design, additional modulation effects and panner laws, block and multichannel composition, SIMD and fast-math utilities, optimized backends, inter-sample limiting, audio writers and codecs, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,612/4,612 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: TPT, Ballistics, Ramping, And Duplication

- `FirstOrderTptFilter` provides checked low-pass, high-pass, and all-pass processing with retained state and immediate coefficient replacement.
- `BallisticsFilter` tracks peak or RMS magnitude with independent attack and release times. `Gain` provides bounded linear and decibel control with sample-counted ramps, while `Bias` adds a checked finite offset.
- `LogRampedValue` interpolates strictly positive values geometrically and supports exact single-sample or grouped advancement.
- `StereoPanner` now exposes all eight shared linear, balanced, sine, and square-root gain laws.
- `ProcessorDuplicator` owns bounded independent copies of one scalar processor, validates active-channel changes, and rejects malformed public bounds before indexing.
- The installed-package consumer exercises all six capabilities through public exports.
- [Open Work](open-work.md) keeps ladder and higher-order filter design, additional modulation effects, block processing contexts and shared processor state, matrices and polynomials, SIMD and fast-math utilities, optimized backends, inter-sample limiting, audio writers and codecs, device I/O, environment-limited validation, and every manual confirmation separate.
- The complete deterministic gate passed 125/125 steps and 4,628/4,628 tests. The installed-package consumer passed 21/21 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from this automated gate.

### Autonomous Follow-up: Blocks, Contexts, Fixed Math, And Ladder Filtering

- `AudioBlock` and `ConstAudioBlock` provide allocation-free bounded views over caller-owned planar channels. Checked sub-block and channel-subset views preserve aliasing.
- `ProcessSpec` validates preparation bounds. Replacing and non-replacing process contexts expose matching block contracts and checked bypass copying without owning sample storage.
- `Matrix` provides fixed-dimension addition, scaling, transpose, identity, and multiplication. `Polynomial` provides capacity-bounded evaluation, derivative, addition, and multiplication with finite-result checks.
- `LadderFilter` provides nonlinear 12 dB and 24 dB low-pass, high-pass, and band-pass modes with checked cutoff, resonance, drive, block continuity, and hostile-state containment.
- `Phase` provides a checked wrapped phase accumulator. The Kaiser window's private Bessel I0 implementation moved into a tested public special-function utility.
- The installed-package consumer exercises all of these capabilities through public exports.
- [Framework Capability Matrix](capability-matrix.md) now separates the remaining focused DSP gaps by high-order design, fast math, SIMD, shared state, elliptic functions, advanced matrix and polynomial operations, multichannel oversampling, convolution modes, dynamics, modulation, and audio files.
- [Open Work](open-work.md) retains every environment-limited and manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,648/4,648 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Butterworth Design, Multichannel Oversampling, And WAV Writing

- `ButterworthDesigner` writes transactional cascades for even-order low-pass and high-pass filters from order 2 through order 16. Response tests cover cutoff magnitude and pass-band separation.
- `MultichannelOversampler` owns independent bounded conversion state for each active planar channel. It validates the complete shape before advancing and exposes mutable high-rate storage per channel.
- `Matrix.solve` adds partial-pivot solution of fixed square linear systems with singular and non-finite rejection.
- `writeInterleavedWav` writes checked PCM16 or IEEE f32 RIFF data into caller-owned storage. Size arithmetic, sample shape, finite input, and destination capacity are validated before mutation.
- The installed-package consumer exercises all four additions through public exports.
- [Framework Capability Matrix](capability-matrix.md) now narrows the remaining filter-design gap to odd-order, specification-derived, Chebyshev, elliptic, least-squares, equiripple, and polyphase methods. Oversampling differences are limited to filter selection, custom stages, quality controls, and latency policy. Audio-file differences now exclude basic WAV writing.
- [Open Work](open-work.md) retains every cleanup, environment-limited, and manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,659/4,659 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Odd-Order Cascades, Block Arithmetic, And Incremental WAV Output

- `ButterworthDesigner` now returns bounded low-pass and high-pass cascades for every order from 1 through 16. Odd orders use a first-order section followed by second-order pole pairs.
- `AudioBlock` adds transactional addition, scaled addition, and pointwise product operations across matching planar views. Shape, input, and result checks complete before mutation.
- `WavWriter` appends complete interleaved frames to fixed caller storage while maintaining a valid RIFF header. Capacity, shape, finite conversion, size arithmetic, and public state are checked before encoded data changes.
- The installed-package consumer exercises all three additions through public exports.
- The remaining high-order design differences are specification-derived Butterworth order selection, Chebyshev I and II, elliptic IIR, least-squares and equiripple FIR, and polyphase all-pass design. The fixed-capacity writer remains narrower than general stream-backed audio format writers.
- [Framework Capability Matrix](capability-matrix.md) and [Open Work](open-work.md) retain these feature differences, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,667/4,667 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Chebyshev Design, AIFF Writing, And Block Aggregates

- `ChebyshevDesigner` returns bounded Type I low-pass and high-pass cascades for orders 1 through 16 with checked pass-band ripple. Tests cover odd and even normalization, first-order and higher-order separation, maximum order, and invalid requests.
- `writeInterleavedAiff` writes checked big-endian PCM16, PCM24, or PCM32 AIFF data into caller-owned storage. `AiffWriter` adds fixed-capacity incremental output and overwrites prior odd-byte padding before extending PCM24 data. Tests cover extended sample-rate encoding, interleaving, padding transitions, size limits, malformed state, and transactional failure.
- `AudioBlock` adds transactional subtraction and pointwise sum. `ConstAudioBlock` reports checked minimum, maximum, peak magnitude, and sum of squares.
- The installed-package consumer exercises all three additions through public exports.
- Remaining high-order design differences include specification-derived order selection, Chebyshev Type II, elliptic IIR, least-squares and equiripple FIR, and polyphase all-pass design. Audio-file differences now exclude basic PCM AIFF output but retain file-backed streams, codecs, metadata, and growable buffering.
- [Framework Capability Matrix](capability-matrix.md) and [Open Work](open-work.md) retain these feature differences, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,677/4,677 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Flanging, Vibrato, And Complete Elliptic Integrals

- `ModulatedDelay` provides one bounded sine-modulated cubic delay with checked rate, center, depth, feedback, mix, block continuity, and malformed-state recovery.
- `Flanger` configures the shared core for short feedback delays. `Vibrato` exposes only the modulated delayed path. Focused tests cover comb echoes, static delay, arbitrary block partitions, invalid delay ranges, and public-state containment.
- `ellipticIntegralK` computes the complete elliptic integral of the first kind for a checked real modulus and its complement through arithmetic-geometric mean iteration. Tests cover known values, the self-complementary modulus, endpoints, f32 and f64, and invalid input.
- The installed-package consumer exercises all three public capabilities.
- Jacobian elliptic cd and sn plus inverse sn remain outside the special-function subset. Modulation differences now focus on stereo LFO relationships, tempo synchronization, parameter smoothing, and channel linking rather than basic flanging or vibrato.
- [Framework Capability Matrix](capability-matrix.md) and [Open Work](open-work.md) retain these feature differences, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,687/4,687 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Fast Math And Stereo Modulation

- `FastMathApproximations` implements the documented limited-range Padé family for hyperbolic, trigonometric, exponential, and `log(1 + x)` operations with checked f32 and f64 scalar calls.
- The in-place fast-math path validates every sample before mutation. Tests cover approximation error, symmetry, documented range rejection, non-finite input, and transactional buffer failure.
- `StereoModulation` coordinates two matching modulation processors with a checked fractional-cycle phase offset. Tests cover distinct channel modulation, exact arbitrary-block partitioning, invalid offsets, and length failure without phase advancement.
- The installed-package consumer exercises both additions through public exports.
- [Framework Capability Matrix](capability-matrix.md) now records scalar and buffer fast math plus fixed-offset stereo modulation as covered. SIMD fast math, tempo synchronization, modulation smoothing, and dynamics-style channel linking remain open.
- [Open Work](open-work.md) retains these feature differences, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,694/4,694 tests. The installed-package consumer passed 22/22 tests.
- Raw ABI passed 129/129 steps. All 22 native example plugins passed all 47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Fixed-Lane SIMD Registers

- `SimdRegister` wraps Zig vectors with explicit f32 or f64 lane counts. It provides splat, checked unaligned slice load and store, addition, subtraction, multiplication, multiply-add, horizontal sum, and dot product.
- Tests cover f32 and f64 arithmetic, unaligned input, exact destination bounds, non-finite input and result rejection, and store failure without mutation.
- The installed-package consumer exercises vector construction and reduction through the public export.
- [Framework Capability Matrix](capability-matrix.md) now records the fixed-lane SIMD subset. Target-native widths, masks, comparisons, aligned APIs, complex lanes, and higher-level processor dispatch remain open.
- [Open Work](open-work.md) retains these narrower SIMD differences, other feature work, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,697/4,697 tests. The installed-package consumer passed 22/22 tests.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- The prior same-pass integration gate passed raw ABI at 129/129 steps, all 22 native plugins at 47/47 Steinberg validator tests, and both example cross-target bundle matrices at 68/68 steps. The SIMD register does not enter plugin ABI or example bundle code.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Tempo-Synchronized Modulation And Butterworth Specifications

- `ModulationNoteDivision` covers straight, dotted, and triplet values from whole notes through thirty-second notes. Checked BPM conversion is also available for arbitrary positive beats per cycle.
- `ModulationRateSmoother` reaches an exact target over a bounded sample count without depending on host block boundaries. Chorus, flanger, vibrato, modulated delay, and phaser expose immediate, smoothed, and note-division tempo configuration.
- `ButterworthDesigner` now derives the minimum order and adjusted cutoff from checked passband loss and stopband attenuation constraints for low-pass and high-pass filters. Requests requiring more than sixteen poles are rejected.
- Tests cover tempo conversion, exact smoothing, partition independence, invalid-change rollback, wrapper integration, passband and stopband response constraints, high-pass and low-pass design, invalid specifications, and maximum-order rejection.
- The installed-package consumer exercises tempo synchronization and specification-derived Butterworth design through public exports.
- [Framework Capability Matrix](capability-matrix.md) now narrows modulation work to host-transport following, smoothing of non-rate effect parameters, and dynamics linking. High-order filter work now excludes Butterworth order derivation.
- [Open Work](open-work.md) retains these narrower feature differences, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology item.
- The complete deterministic gate passed 125/125 steps and 4,707/4,707 tests. The installed-package consumer passed 22/22 tests.
- The broader Phase 1 gate passed 341/341 steps with all 4,707 tests, raw ABI at 129/129 steps, and all 22 native plugins at 47/47 Steinberg validator tests.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### Autonomous Follow-up: Chebyshev Specifications, Shared State, And SIMD Masks

- `ChebyshevDesigner` now derives the minimum Type I order from passband loss and stopband attenuation specifications for low-pass and high-pass responses.
- `SharedProcessorDuplicator` retains independent bounded processor histories while passing one caller-owned immutable state pointer to every channel. State replacement validates before publication.
- `SimdRegister` adds checked division, extrema, absolute value, square root, comparison masks, mask selection, and runtime lane access.
- Tests cover low-pass and high-pass attenuation constraints, maximum-order rejection, shared state replacement, independent channel histories, invalid state rollback, SIMD masks, roots, extrema, zero divisors, negative roots, and lane bounds.
- The installed-package consumer exercises all three additions through public exports.
- [Framework Capability Matrix](capability-matrix.md) now removes specification-derived Type I orders, basic shared coefficient state, masks, and comparisons from the open list.
- [Open Work](open-work.md) retains Chebyshev Type II, elliptic and advanced FIR design, richer shared-state publication, target-native SIMD dispatch, cleanup candidates, environment-limited gates, and every manual confirmation.
- The complete deterministic gate passed 125/125 steps and 4,714/4,714 tests. The installed-package consumer passed 22/22 tests.
- The broader Phase 1 gate passed 341/341 steps with all 4,714 tests, raw ABI at 129/129 steps, and all 22 native plugins at 47/47 Steinberg validator tests.

### 2026-07-25: inverse-Chebyshev, transport following, and modulation smoothing

- Added bounded order 1 through 16 Chebyshev Type II low-pass and high-pass SOS design. Fixed-order requests use the first stopband point at the requested attenuation. Specification requests derive the minimum order and adjusted critical frequency.
- Added checked host transport to the public process context and VST3 validity-flag adapter. `follow_host_transport` requests musical position, bar, cycle, tempo, time signature, and transport state through `IProcessContextRequirements`.
- Chorus, flanger, vibrato, modulated delay, and phaser can follow host tempo with a fallback. Repeated block updates do not restart an unchanged rate ramp.
- Added a reusable bounded linear smoother. Chorus, flanger, vibrato, and modulated delay now smooth center delay, depth, feedback, and wet mix as well as LFO rate.
- Focused filter and public DSP tests passed. Linux aarch64 and Windows x86-64 GNU public DSP cross-compilation passed.
- The complete deterministic gate passed 125/125 steps and 4,744/4,744 tests. The installed-package consumer passed 22/22 tests.
- [Open Work](open-work.md) retains advanced FIR and polyphase design, remaining smoothing families, mutable shared-state publication, target-native SIMD dispatch, advanced dynamics, file-backed streams and codecs, platform wrappers, cleanup candidates, environment-limited gates, and all manual confirmations.
- Added checked real Jacobian elliptic `sn`, `cn`, `dn`, and principal-amplitude evaluation with endpoint formulas, period reduction, known-value tests, and identity tests.
- Added bounded order 1 through 16 elliptic low-pass and high-pass SOS design with specification-derived minimum orders. Passband and stopband sweeps cover 257 points per band.
- The complete deterministic gate passed 125/125 steps and 4,749/4,749 tests. The installed-package consumer passed 22/22 tests, and the public DSP module cross-compiles for Linux aarch64 and Windows x86-64 GNU.
- Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- The complete public DSP test module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-25: realtime publication, native SIMD, advanced dynamics, and least-squares FIR

- Added a fixed-storage three-slot snapshot publisher for one non-realtime writer and one realtime reader. Reader pinning and publication verification prevent torn copies. A 100,000-publication stress test also passes ThreadSanitizer.
- Added target-native SIMD width selection, aligned access, split-real complex lanes, and runtime AVX2 or NEON dispatch for transactional buffer gain processing.
- Added exact-latency lookahead limiting, oversampled inter-sample limiting with a reconstruction guard, and independent two-band Linkwitz-Riley compression.
- Added weighted linear-phase least-squares FIR design through 255 taps. The bounded incremental QR solve avoids allocation and normal equations. Tests sweep passbands and stopbands, exercise transactional failures, and cover the maximum tap count.
- Added fixed-capacity FIR polyphase decomposition, exact reconstruction, per-phase processing, and direct low-pass prototype design.
- The public DSP module passed 326/326 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- The complete deterministic gate passed 125/125 steps and 4,769/4,769 tests. The installed-package consumer passed 22/22 tests.
- [Open Work](open-work.md) retains equiripple FIR and polyphase all-pass IIR design, reference-counted publication, broader SIMD dispatch, remaining smoothing families, arbitrary multiband dynamics and channel linking, file-backed streams and codecs, platform wrappers, cleanup candidates, environment-limited gates, and all manual confirmations.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-25: equiripple FIR and file-backed 64-bit audio output

- Added a bounded Parks-McClellan exchange designer for odd-length, even-symmetry FIR filters through 255 taps and as many as eight weighted bands.
- Tests cover weighted low-pass ripple equality across 4,097-point passband and stopband sweeps, high-pass and three-band responses, maximum tap count, invalid bands, deliberate non-convergence, and unchanged output after failure.
- Added file-backed WAV and AIFF writers with incremental header maintenance, fixed staging storage, recovery, exact truncation, and final sync.
- Added RF64 and Wave64 file writers with 64-bit accounting, PCM16, PCM24, PCM32, IEEE f32, container-specific padding, and synthetic headers beyond classic RIFF limits.
- Added strict RIFF INFO and AIFF text metadata codecs with known and unknown FourCC preservation. WAV, AIFF, and RF64 file writers can embed metadata without retaining caller storage.
- Added an allocation-free file-backed WAV, AIFF, uncompressed AIFC, RF64, and Wave64 reader with checked chunk traversal, random frame access, and interleaved f32 or f64 conversion for PCM16, PCM24, PCM32, and IEEE f32 RIFF-derived files.
- Added the complete EBU Tech 3285 version 0 through 2 `bext` layout, including typed date and time, time reference, UMID, loudness metadata, reserved bytes, coding history, strict encoding, and borrowed parsing.
- Added UTF-8 iXML and aXML chunk framing, composed RIFF metadata packages, compliant BWF/RF64 chunk ordering, and caller-buffer metadata retrieval from file-backed WAV and RF64 readers.
- Added registered Wave64 BEXT and LIST/INFO metadata writing and canonicalized reading. Eight-byte chunk alignment, outer padding, caller-buffer bounds, unsupported unregistered XML kinds, and malformed public writer state have direct coverage.
- Added phase-compensated Linkwitz-Riley compression for two through eight compile-time bands. Frequency sweeps cover unity recombination through every crossover, with direct coverage for independent gain reduction, partition independence, transactional configuration, invalid band access, and hostile-state recovery.
- Added shared-detector channel linking for the compressor primitive and multiband graphs with as many as 16 compile-time channels. Tests cover stereo image preservation under gain reduction, channel isolation, exact interleaved partition independence, malformed buffer rejection without mutation, and invalid detector recovery.
- Added exact-latency, fixed-capacity lookahead compression with the full threshold, ratio, attack, release, and makeup curve. Tests cover future-transient anticipation, latency, exact partition independence, capacity rejection without state mutation, and hostile-state recovery.
- The public DSP module passed 373/373 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- The complete deterministic gate passed 125/125 steps and 4,816/4,816 tests. The installed-package consumer passed 23/23 tests.
- Independent SciPy coefficient parity remains explicitly open because SciPy is not installed in the local workspace.
- The dependency audit found no local Xiph codec libraries or existing package dependency surface. Later work added native FLAC, Ogg transport, and complete structural Vorbis setup parsing. Vorbis audio-packet decoding and synthesis remain open.
- Schema-level ADM and iXML helpers, ID3, dithering, and shared file-I/O internals remain explicitly open.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-26: native bounded FLAC and Vorbis comments

- Added native FLAC encoding for signed 8-, 16-, 24-, and 32-bit PCM with constant, verbatim, and fixed predictors, optimized Rice parameters, fixed-size frame blocking, streaminfo bounds, PCM MD5, header CRC-8, and frame CRC-16.
- Added checked decoding for constant, verbatim, fixed-predictor, and LPC subframes, Rice and Rice2 partitions, escaped residuals, wasted bits, and the three standard stereo decorrelation assignments.
- Added bounded whole-file read and write helpers using caller-provided encoded storage.
- Added incremental file output with caller-owned pending PCM and encoded-frame storage, final short-block handling, STREAMINFO and MD5 patching, positional-write recovery from the last committed frame, and initialization-time Vorbis comments.
- Added bounded seek-table reservation to incremental output. Points are published only after their target frame write succeeds, capacity exhaustion fails before mutation, comments compose ahead of the table, and unused entries remain placeholders.
- Added frame-at-a-time file decoding with retained caller-owned seek metadata, compressed and decoded frame scratch, whole-stream MD5 verification, optional 33-bit side scratch, and seek-assisted range reads.
- Added UTF-8 FLAC Vorbis-comment encoding and borrowed iteration with metadata-size limits, printable field-name validation, duplicate-block rejection, and malformed payload coverage.
- Added fixed and variable blocking support, canonical multi-byte frame and sample numbers, checked seek-table generation and borrowed iteration, and range decoding from the nearest preceding seek point.
- Added file-backed range decoding with separate bounded storage for the compressed file and one decoded frame.
- Added composed FLAC metadata so Vorbis comments and generated seek tables can coexist in one checked file.
- Added caller-owned wide side-channel scratch for full 32-bit left-side, side-right, and mid-side decoding, including bounded range and file-range APIs.
- Twenty-six focused codec tests cover every supported PCM width, one through eight channels, uncommon and multi-frame boundaries, compression selection, LPC and escaped-residual decoding, wasted bits, stereo restoration, incremental input, output, recovery, and seek metadata, file-backed round trips, caller contracts, truncated files, CRC failures, and MD5 validation.
- The public DSP module passed 431/431 native tests. The complete deterministic gate passed 125/125 steps and 4,922/4,922 tests, and the installed-package consumer passed 24/24 tests.
- The FLAC module cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- macOS `afinfo` recognized a generated stereo probe as 48 kHz FLAC from a 16-bit source with 256 valid frames. This confirms external file and streaminfo recognition, not full independent sample decode parity.
- macOS `afplay` and `afconvert` returned `fmt?` before producing independent PCM output for constant and verbatim probes. No Xiph, FFmpeg, libFLAC, or Python codec is installed locally, so exact external decoder parity remains environment-limited and must stay open.
- External Xiph-tool parity and DAW or player audition remain manual because the local environment has no FLAC reference binary.
- The implementation follows [RFC 9639](https://www.rfc-editor.org/rfc/rfc9639.html). Ogg Vorbis, ID3, dithering, and schema-level ADM/iXML helpers remain open.
- No audible or third-party interoperability result was inferred from the internal round trips.

### 2026-07-26: bounded Ogg transport and Vorbis headers

- Added RFC 3533 page writing and parsing with lacing, continuation across maximum-size pages, BOS/EOS, serial and sequence validation, granule positions, and Ogg CRC verification.
- Added caller-buffer packet reconstruction plus positional file-backed page and packet readers.
- Added Vorbis identification, UTF-8 comment, and setup-header validation for the three required header packets.
- Added allocation-free least-significant-bit-first parsing for ordered, unordered, and sparse codebooks, lookup tables, floor 0 and floor 1, all residue types, mappings, channel coupling, submaps, modes, framing, and component references. Caller-owned storage retains bounded codebook summaries.
- Added retained mode summaries and bounded audio-packet header parsing for packet type, multi-bit mode selection, long-window transition flags, block size, and hostile public setup state.
- Added caller-owned canonical Huffman entries and exact-size decode trees. The transactional packet cursor follows one branch per packet bit and covers one-bit and deeper trees, zero-count ordered levels, sparse entries, the single-entry erratum, truncation, invalid codewords, invalid codebook selection, and hostile retained tree state.
- Added caller-owned lookup multiplicands, Vorbis float unpacking, and transactional type 1 lattice and type 2 explicit vector reconstruction with sequence accumulation.
- Added caller-owned floor 0 and floor 1 configuration, transactional packet decoding, nominal truncation handling, the full 63-bit floor 0 amplitude field, bounded LSP coefficient reconstruction, Bark-mapped floor 0 synthesis, and floor 1 prediction, integer line rendering, and inverse-dB synthesis.
- Twelve focused tests cover continued and empty packets, transactional output and setup-storage bounds, file streaming, corruption, sequence gaps, identification bounds, comments, all codebook packing forms, scalar and vector entropy decoding, both floor types, floor packet decoding and synthesis, residues, stereo coupling, submaps, audio packet modes and windows, truncation, malformed trees, duplicate floor points, reserved mapping bits, and framing.
- The public DSP module passed 437/437 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU. The complete deterministic gate passed 125/125 steps and 4,928/4,928 tests, and the installed-package consumer passed 24/24 tests.
- Vorbis residue packet decoding, channel decoupling, inverse MDCT, overlap-add, PCM seeking, audio encoding, and third-party interoperability remain open. The Ogg transport layer is not reported as a complete Vorbis codec.
- No audible or third-party interoperability result was inferred from these automated gates.

### 2026-07-25: expanded runtime buffer dispatch

- Extended `KernelDispatcher` with transactional in-place affine processing and weighted two-buffer mixing on scalar, NEON-width, and AVX2-width paths. Exact source-to-destination mix aliases are supported, while shifted overlap is rejected before mutation.
- Added stereo planar-to-interleaved and interleaved-to-planar conversion in runtime-selected backend-width blocks. Shape, finite-input, and writable-overlap validation completes before any destination changes.
- Tests cover scalar and vector parity, vector tails, unaligned slices, empty buffers, exact aliases, shifted overlap, invalid shapes, non-finite input, arithmetic overflow, transactional preservation, native feature detection, and public installed-package use.
- The public DSP module passed 382/382 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- The complete deterministic gate passed 125/125 steps and 4,825/4,825 tests. The installed-package consumer passed 23/23 tests.
- [Open Work](open-work.md) retains broader processor dispatch, SIMD fast math, dispatcher backend optimization, optimized transform and resampling backends, cleanup candidates, environment-limited gates, and every manual host, audible, visual, multi-monitor, and assistive-technology confirmation.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.
- Extended the release microbenchmark with scalar and detected-backend gain, affine, weighted-mix, and stereo-layout measurements at 8, 32, 128, and 512 samples. Every new measurement passed its 100 ns/sample regression ceiling.
- On the local Apple Silicon runner, scalar arithmetic measured 0.11 through 0.93 ns/sample and checked NEON-width arithmetic measured 0.10 through 1.21 ns/sample. There was no stable arithmetic crossover through 512 samples. Stereo layout round trips improved from 0.94 to 0.71 ns/sample at 512 frames.
- [Open Work](open-work.md) records direct vector loading, validation fusion, and backend specialization as performance work. The benchmark evidence does not justify describing the current checked arithmetic dispatcher as faster than scalar.

### 2026-07-25: retained realtime shared-state generations

- Added `RealtimeReferencePublisher(State, slot_count)` with three through 64 inline slots, one non-realtime writer, and multiple concurrent realtime readers.
- Reader handles pin an immutable generation, support explicit bounded retention, and release independently. Publication atomically writer-locks only a non-active slot with zero references and returns `RealtimeReferenceUnavailable` instead of waiting when readers pin every reusable slot.
- The acquisition protocol closes the load-before-refcount reclamation race: a reader increments only an unlocked active slot and verifies that it remains active, while the writer can mutate only after atomically changing a zero reference count to its reserved writer state.
- Tests cover retained historical values, exact slot exhaustion and reclamation, generation rollover, idempotent release, hostile active state, and 100,000 publications with four concurrent readers. The dedicated `test-dsp-thread-sanitizer` target passes all six publication tests.
- The installed-package consumer acquires old and new generations through the public export. The public DSP module passed 386/386 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU.
- The complete deterministic gate passed 125/125 steps and 4,829/4,829 tests. The installed-package consumer passed 23/23 tests.
- [Open Work](open-work.md) no longer lists reference-counted publication as missing. Heap-owned polymorphic state, multi-writer publication, and automatic lifetime management for pointers stored inside published state remain outside this fixed-storage contract.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-25: bounded dynamic audio topology model

- Added `AudioBusLayoutSet`, `DynamicAudioBus`, and `DynamicAudioBusTopology` as the shared bounded state model required before live VST3 topology can be safe.
- Each bus owns a current layout, checked supported-layout set, and activation state. Each direction supports an optional main bus and as many as eight auxiliary buses.
- Layout negotiation, activation, auxiliary insertion, and auxiliary removal validate the complete request before mutation. Effective changes advance a rollover-safe generation; rejected and no-op changes preserve both topology and generation.
- Tests cover layout negotiation, inactive-to-active transitions, insertion, removal and compaction, missing-main rejection, unsupported layout rollback, out-of-range rollback, exact capacity, generation rollover, and hostile public state.
- The public plugin module passed 223/223 native tests and cross-compiled for Linux aarch64 and Windows x86-64 GNU. The installed-package consumer passed 24/24 tests.
- The complete deterministic gate passed 125/125 steps and 4,833/4,833 tests.
- [Open Work](open-work.md) retained live shell integration across component metadata, arrangement negotiation, activation, flush validation, process-context construction, component/controller synchronization, and state. The later 2026-07-26 section closes that implementation gap.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-25: coalesced host restart transport

- Added a typed component-to-controller restart message carrying a validated nonzero VST3 restart-flag mask. Unknown bits and malformed attributes are rejected before any host callback.
- Component-owned atomic marks now track latency and I/O changes independently. One non-realtime dispatch combines pending `kLatencyChanged` and `kIoChanged` flags into one controller notification and one host `restartComponent` call.
- Missing peers and failed sends restore each consumed pending flag independently. Repeated marks remain coalesced, and the older latency-only message remains accepted for compatibility.
- The Fixed Rate Processor integration test exercises the processor-bound `HostRequestSink`, duplicate latency and I/O marks, combined callback flags, and callback coalescing.
- The complete deterministic gate passed 125/125 steps and 4,843/4,843 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- [Open Work](open-work.md) still tracked binding the runtime topology model to every VST3 shell path at this point. The later 2026-07-26 section closes that implementation gap.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-26: live bounded VST3 audio topology

- `SimpleEffect` now owns one bounded dynamic topology and publishes fixed-size immutable snapshots to realtime processing. Static declarations are converted to fixed-layout topology for source compatibility.
- Component bus counts and metadata, whole-arrangement negotiation, activation, zero-sample flush validation, and nonzero process-context construction consume the same topology contract.
- Plugin control code receives `setAudioBusLayout`, `addAuxiliaryAudioBus`, and `removeAuxiliaryAudioBus` through the existing component-owned `HostRequestSink`. Effective changes publish once and mark one coalesced `kIoChanged` restart.
- Host-initiated arrangement and activation changes publish without sending a redundant restart. Default activation metadata remains distinct from current activation state.
- Dynamic topology is encoded in a versioned component-state envelope. Decoding validates parameters, processor payload, topology structure, supported-layout masks, and activation values before publishing topology. Reflected controllers remain able to read the parameter section.
- Tests cover supported and rejected arrangements, activation, default-active metadata, auxiliary insertion, published process bus boundaries, zero-sample validation, malformed state rollback, save and restore, installed-package serialization, and end-to-end host restart flags.
- `PluginSpec` now carries a plugin's topology declaration into every example and installed-package `SimpleEffect` wrapper configuration.
- A high-contention rerun exposed a load-before-reader-registration race in the fixed-storage snapshot publisher. Publication and copying now use per-slot atomic reader counts plus a reserved writer state. The focused stress case passed 20 consecutive reruns, and `test-dsp-thread-sanitizer` passed 7/7 tests.
- The complete deterministic gate passed 125/125 steps and 4,866/4,866 tests. The installed-package consumer passed 24/24 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps.
- [Open Work](open-work.md) now retains only manual real-host topology confirmation, broader speaker-layout coverage, and arbitrary bus counts for this capability.
- No manual host, audible, visual, multi-monitor, or assistive-technology result was inferred from these automated gates.

### 2026-07-26: half-band polyphase all-pass IIR design

- Added a bounded half-band polyphase IIR designer based on two parallel cascades of stable second-order all-pass sections. Requests specify normalized transition width and stopband attenuation, derive an odd order, and fail explicitly when more than 32 sections would be required.
- The design exposes direct and one-sample-delayed path coefficients plus analytic unity-gain low-pass and complementary high-pass magnitude evaluation.
- Added a stateful processor with low-pass block processing, simultaneous low/high sample output, retained block continuity, transactional reconfiguration, explicit reset, finite-input checks, and hostile-state containment.
- Dense 4,097-point sweeps cover 60 dB, 90 dB, and 120 dB requests. Tests also cover power complementarity at 2,049 frequencies, 8,192-sample low/high impulse agreement with the analytic transfer functions, exact partition independence, invalid specifications, section-capacity failure, and rejected reconfiguration without mutation.
- The public core suite passed 853/853 tests, and the installed-package consumer constructs and processes the design through public exports.
- The complete deterministic gate passed 125/125 steps and 4,871/4,871 tests. The installed-package consumer passed 24/24 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps, and the installed DSP fixture containing the new API cross-compiled for both targets.
- At this point, [Open Work](open-work.md) retained even-length and odd-symmetry equiripple filters, independent trusted polyphase reference fixtures, dummy and custom oversampling stages, optional integer-latency adjustment, and optimized resampling backends for this area. The following section closes the integer-latency item.

## 2026-07-26 Polyphase IIR Oversampling Follow-up

- Added a bounded single-channel 2x, 4x, 8x, and 16x polyphase IIR oversampler. Each 2x stage runs at its natural rate, has independent interpolation and decimation history, validates mutable high-rate storage before decimation, and reports analytic fractional base-rate latency.
- Added common and per-stage transition-width and stopband-attenuation configurations. Construction is transactional, and invalid specifications fail before a processor is returned.
- Added a bounded multichannel wrapper with independent channel histories and runtime channel-count changes. Complete planar shapes are validated before state advances, and all channels decimate into internal scratch storage before caller output changes.
- Added optional integer-latency adjustment with a stable first-order all-pass fractional delay after decimation. The reported integer delay agrees with the impulse-response first moment while preserving compensation-filter magnitude.
- Added deterministic coverage for gain, channel isolation, partition independence, fractional-latency agreement with an impulse first moment, stopband rejection, sequencing, malformed high-rate data, invalid specifications, capacity limits, and hostile public state.
- The installed-package fixture now compiles and runs both single-channel per-stage configuration and multichannel processing through the public package API.
- The complete deterministic gate passed 125/125 steps and 4,883/4,883 tests. The installed-package consumer passed 24/24 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps, and the installed DSP fixture cross-compiled for both targets.
- [Open Work](open-work.md) retains independent reference parity, audible FIR-versus-IIR comparison, dummy and custom stages, and optimized resampling backends.
- No manual audible result was inferred from these automated gates.

## 2026-07-26 Complete Linear-Phase Equiripple Forms

- Extended the bounded exchange solver from Type I filters to all four real linear-phase forms. Odd and even tap counts select Type I and Type II even symmetry, while the explicit odd-symmetry API selects Type III and Type IV.
- The grid and basis construction now account for integer and half-integer cosine and sine bases. Forced zeros at DC or Nyquist are omitted from the exchange grid, and incompatible nonzero endpoint requests fail before output changes.
- Dense response tests cover even-length symmetric low-pass design, odd-length antisymmetric Hilbert design, and even-length antisymmetric differentiator design. Symmetry, forced endpoints, weighted ripple, maximum capacity, convergence failure, and transactional validation remain covered.
- The installed-package fixture constructs a Type IV differentiator through the public symmetry export.
- The complete deterministic gate passed 125/125 steps and 4,886/4,886 tests. The installed-package consumer passed 24/24 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps, and the installed DSP fixture cross-compiled for both targets.
- [Open Work](open-work.md) retains independent reference fixtures and manual audible confirmation for the advanced filter-design families.
- No manual audible result was inferred from these automated gates.

## 2026-07-26 Principal Inverse Jacobian Functions

- Added the checked real incomplete elliptic integral of the first kind. The implementation reduces general amplitudes by the complete period and evaluates the principal interval through Carlson's symmetric integral.
- Added principal real inverses for `sn`, `cn`, and `dn`. Their branches cover `[-K, K]`, `[0, 2K]`, and `[0, K]`, with explicit parameter-zero and parameter-one behavior and checked finite domains.
- Fixed endpoint paths return the complete quarter period directly instead of losing accuracy through inverse trigonometric cancellation near a constrained endpoint.
- Tests cover a known incomplete-integral value, amplitude periodicity, divergent and invalid domains, exact endpoints, `f32` behavior, and dense forward/inverse round trips for parameters `0`, `0.25`, `0.75`, and `0.99`.
- The installed-package fixture exercises the incomplete integral, forward `sn`, and inverse `sn` through public exports.
- The intermediate complete deterministic gate passed 125/125 steps and 4,889/4,889 tests. The installed-package consumer passed 24/24 tests, and its DSP fixture cross-compiled for Linux and Windows.

## 2026-07-26 Phaser Parameter Smoothing

- Extended phaser smoothing from LFO rate to the minimum and maximum sweep frequencies, feedback, and wet mix.
- The sweep endpoints share one exact sample count. Retargeting restarts both from their current values so the minimum never crosses the maximum, including when one endpoint keeps the same target.
- Immediate configuration, sample-rate changes, failed retargeting, and hostile desynchronized ramp state remain transactional or self-containing.
- Tests cover exact intermediate and final values for every new smoother, invalid-duration rollback, ordered endpoints, and hostile-state recovery.
- The final complete deterministic gate passed 125/125 steps and 4,890/4,890 tests. The installed-package consumer passed 24/24 tests. Linux aarch64 and Windows x86-64 GNU example bundle matrices each passed 68/68 steps, and the installed DSP fixture cross-compiled for both targets.
- [Open Work](open-work.md) retains smoothing outside the modulation family plus manual audible modulation confirmation.
- No manual audible result was inferred from these automated gates.

## 2026-07-26 Vorbis Residue Packet Decoding

- Retained complete residue 0, 1, and 2 setup configuration, including begin and end bounds, partition size, classifications, classbook, cascades, and pass books.
- Added caller-scratch residue decoding for classification words and all eight passes. Type 0 interleaving, type 1 sequential placement, type 2 channel interleaving, skipped floor channels, and additive vector reconstruction follow the Vorbis I packet layouts.
- Added exact classification-scratch sizing, output shape checks, output-to-output and output-to-scratch alias rejection, hostile retained-state validation, and transactional cursor behavior.
- Nominal end-of-packet consumes the packet and returns the decoded prefix with a truncation flag. Other packet failures clear output and preserve the original cursor, while preflight failures preserve both cursor and output.
- Retained mapping submaps, per-channel mux assignments, and ordered coupling steps. Inverse magnitude-angle coupling runs in reverse step order through exact-size caller scratch and is transactional for malformed mappings, aliasing, non-finite values, and arithmetic overflow.
- Added checked Vorbis small-block, large-block, small-to-large, and large-to-small window synthesis. Tests cover transition zero regions, unity regions, the complementary overlap identity, and unchanged output after invalid shape or flag state.
- Added transactional floor application, a radix-2 FFT inverse MDCT for every legal Vorbis block size, precomputed transform rotations and transition-window plans, and a combined windowed transform path without audio-thread trigonometric calls.
- Added fixed-storage variable-block overlap-add with exact center-to-center output ranges, first-block priming, reset, short/long transition alignment, and transactional capacity, alias, finite-value, overflow, and hostile-state handling.
- The inverse MDCT matches its direct defining transform across dense deterministic and seeded randomized vectors in `f32` and `f64`. Release measurements were 2.87, 4.37, and 5.31 ns/sample at block sizes 64, 256, and 2,048.
- Seventeen focused Ogg/Vorbis tests and four shared FFT tests pass. The public DSP module passes 442/442 native tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The installed-package consumer passes 24/24 tests, and the complete deterministic gate passes 125/125 steps and 4,933/4,933 tests.
- At this checkpoint, [Open Work](open-work.md) retained full packet orchestration, granule-position trimming, chained-stream PCM decode, seeking, encoding, independent Xiph parity, third-party interoperability, and audible confirmation.
- No complete codec, interoperability, or audible result was inferred at this checkpoint.

## 2026-07-26 Vorbis Packet And PCM Stream Decoding

- Added one transactional packet decoder that sequences channel floors, coupling nonzero propagation, submap residue bundles, reverse coupling, floor multiplication, precomputed transition windows, and inverse MDCT.
- Added exact scratch requirements for spectrum, floor, coupling, time-domain, and residue-classification storage. Large classification buffers remain caller-owned.
- Added atomic multichannel overlap. Every channel prepares successfully before any output or retained history commits.
- Added signed granule tracking for inferred stream starts, delayed positions, short streams, final-frame trimming, overflow, invalid regressions, reset, and EOS.
- Added a bounded PCM stream decoder that combines packet synthesis, overlap, granule trimming, priming, and end-state containment.
- Added sequential chained Ogg page and packet readers for memory and positional files. Each page and packet identifies its logical stream, and serial and sequence validation restart only after EOS followed by BOS.
- Added an in-memory end-to-end stream test that writes three Vorbis headers and two audio packets into Ogg pages, parses retained setup, and decodes the result to granule-trimmed PCM.
- Twenty-two focused Ogg/Vorbis tests and four shared FFT tests pass. The public DSP module passes 447/447 native tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The installed-package consumer passes 24/24 tests, and the complete deterministic gate passes 125/125 steps and 4,938/4,938 tests.
- Release inverse-MDCT measurements pass their budget at 2.93, 4.36, and 5.22 ns/sample for block sizes 64, 256, and 2,048.
- [Open Work](open-work.md) retains PCM seeking, Vorbis encoding, independent Xiph parity, third-party interoperability, and audible confirmation.
- No external interoperability, seeking, encoding, or audible result was inferred from the internal stream tests.

## 2026-07-26 Vorbis Positional Seeking

- Added caller-owned memory and file seek indexes for sequential chained Ogg streams. Points retain the target granule packet and the preceding audio packet required to prime Vorbis overlap.
- Added validated transactional repositioning to the positional packet reader. It checks the retained page offset, serial, sequence, continuation state, and packet bounds before changing reader state, then discards earlier packet completions on the start page.
- Added a decode-forward PCM cursor that rejects unavailable or inconsistent positions and returns the exact source suffix at or after a requested signed PCM sample.
- The end-to-end stream test now builds matching memory and file indexes, proves failed seeking preserves the reader, seeks to a retained prime packet, resets and primes the PCM decoder, and clips the decoded target packet at the requested sample.
- The public DSP exports and staged installed-package consumer exercise index sizing, construction, lookup, and PCM selection. The focused 27-test Ogg/Vorbis and FFT suite passes, the public DSP module passes 448/448 tests and both cross-compiles, the installed-package consumer passes 24/24 tests, and the complete deterministic gate passes 125/125 steps and 4,939/4,939 tests.
- [Open Work](open-work.md) now retains Vorbis encoding, independent Xiph parity, third-party interoperability, and audible confirmation. External seeking behavior remains a manual interoperability check.

## 2026-07-26 Advanced DSP Reference Parity

- Added fixed SciPy 1.17 response vectors for low-pass and high-pass Chebyshev Type II and elliptic designs, a 63-tap weighted least-squares FIR, Type I through Type IV equiripple FIR designs, polyphase interpolation, forward real Jacobian functions, and all three principal real inverses.
- The least-squares comparison exposed an objective-weighting defect. Equal grid counts per band had given narrow and wide bands equal total influence. Midpoint rows now include the represented band width, matching the continuous weighted integral and the independent response to tight tolerance.
- Added independent dynamics coverage through a scalar lookahead vector, a 16x Lanczos reconstruction probe for inter-sample containment, and a SciPy-generated three-band Linkwitz-Riley impulse response.
- Added ReleaseFast regression budgets for advanced IIR and FIR setup, lookahead and 4x inter-sample limiting, four-band compression, and mutable-snapshot publication with and without a concurrent reader.
- On the current macOS development machine, representative measurements were 133 ns for Chebyshev Type II setup, 21.0 us for elliptic setup, 44.4 ms for a 63-tap least-squares design at grid density 1,024, 1.39 ms for a 63-tap equiripple design, 84.8 ns/sample for lookahead limiting, 254.8 ns/sample for 4x inter-sample limiting, 163.9 ns/sample for four-band compression, 2.7 ns/uncontended publication, 5.5 ns/read, and 50.2 ns/publication with a concurrent reader.
- The public DSP module passes 458/458 tests. The complete deterministic gate passes 125/125 steps and 4,949/4,949 tests, the installed-package consumer passes 24/24 tests, the installed DSP fixture cross-compiles for Linux aarch64 and Windows x86-64 GNU, and both 22-example bundle matrices pass 68/68 steps.
- [Open Work](open-work.md) retains optimized dispatch plus manual filter and dynamics confirmation.
- No audible or host result was inferred from these automated gates.

## 2026-07-26 Checked SIMD Dispatch Hot Path

- Kept the dispatcher's complete finite-input and finite-result preflight, overlap checks, exact-alias policy, and unchanged-on-failure contract.
- Replaced checked-register calls inside the already validated gain, affine, and weighted-mix loops with direct unaligned Zig vectors. Scalar tails retain the same arithmetic.
- Added f32 and f64 differential coverage for scalar, NEON-width, and AVX2-width execution at every length from 0 through 73. The matrix covers empty input, unaligned starts, every vector boundary, and every scalar-tail length while retaining the existing hostile-value and overlap tests.
- On the current Apple Silicon machine at 128 samples, ReleaseFast NEON-width gain, affine, and weighted mix measured 0.41, 0.43, and 0.65 ns/sample. Their scalar paths measured 0.66, 0.66, and 0.87 ns/sample. The vector paths also remained faster at 512 samples.
- The public DSP module passes 459/459 tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The complete deterministic gate passes 125/125 steps and 4,950/4,950 tests, and the installed-package consumer passes 24/24 tests.
- [Open Work](open-work.md) retains broader processor and fast-math dispatch, but no longer carries duplicate checked-register overhead as unresolved cleanup.

## 2026-07-26 SIMD Fast Math

- Added fixed-width and target-native in-place SIMD paths for all eight checked Padé operations. Complete-slice input and result validation occurs before mutation, vector blocks accept unaligned storage, and scalar tails use the original approximation.
- Added runtime selection through `KernelDispatcher.applyFastMath`.
- Differential tests cover f32 and f64, all operations, lane counts 2, 4, and 8, every length from 0 through 17, unaligned starts, scalar tails, native-width selection, and unchanged output after an out-of-range lane.
- At 128 samples on the current Apple Silicon machine, ReleaseFast NEON-width fast sine measured 1.12 ns/sample versus 1.81 ns/sample scalar. The vector path remained faster at 8, 32, and 512 samples.
- The installed-package consumers exercise both target-native and runtime-dispatched fast math. The public DSP module passes 462/462 tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The complete deterministic gate passes 125/125 steps and 4,953/4,953 tests, and the installed-package consumer passes 24/24 tests.
- [Open Work](open-work.md) now limits the SIMD backlog to additional buffer primitives. Smoothing outside the modulation family remains separate from the completed modulation-parameter requirement.

## 2026-07-26 Dispatched Buffer Arithmetic

- Added runtime-dispatched copy, add, and pointwise multiply for f32 and f64 buffers on scalar, NEON-width, and AVX2-width paths.
- Complete shape, finite-input, and finite-result preflight occurs before mutation. Exact aliases are supported: copy becomes a validated no-op, add doubles the destination, and multiply squares it. Shifted overlaps are rejected without changing the destination.
- Differential tests cover every length from 0 through 73, unaligned starts, vector boundaries, scalar tails, exact aliases, shifted overlaps, malformed shapes, invalid inputs, and overflowing results.
- At 128 samples on the current Apple Silicon machine, ReleaseFast NEON-width copy, add, and multiply measured 0.31, 0.53, and 0.54 ns/sample. Scalar paths measured 0.32, 0.79, and 0.77 ns/sample. Copy matches the compiler-optimized scalar memory copy, while add and multiply retain vector gains at both 128 and 512 samples.
- The installed-package consumer exercises all three public operations. The public DSP module passes 463/463 tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The complete deterministic gate passes 125/125 steps and 4,954/4,954 tests, and the installed-package consumer passes 24/24 tests.
- [Open Work](open-work.md) now narrows dispatcher expansion to specialized reductions and domain-specific processors. It continues to track every external interoperability, audible, host, visual, cleanup, and broader framework item separately.

## 2026-07-26 Complex Jacobian Elliptic Functions

- Added checked f32 and f64 complex `sn`, `cn`, `dn`, `cd`, and principal inverse `sn` for real parameters from zero through one while retaining the module's raw-argument and parameter conventions.
- Forward evaluation uses exact endpoint formulas or the real AGM core through Jacobi's imaginary transformation and addition theorem. The inverse uses a bounded descending-modulus transform and explicit principal complex branches.
- Non-finite input, non-finite output, unresolved poles, quotient poles, branch singularities, and convergence failures return errors.
- Fixed vectors came from independent complex ODE integration at 20,000 and 40,000 RK4 steps. Their maximum refinement delta was below 1.8e-14. Tests also cover both parameter endpoints, algebraic identities, conjugation, real periods, agreement with the real implementation, generic and endpoint poles, and 1,105 dense principal-rectangle round trips.
- ReleaseFast complex `sn`/`cn`/`dn` measured 163.7 ns per call, and principal inverse `sn` measured 154.3 ns per call on the current Apple Silicon machine.
- The installed-package consumer exercises every new public operation. The public DSP module passes 468/468 tests and cross-compiles for Linux aarch64 and Windows x86-64 GNU. The complete deterministic gate passes 125/125 steps and 4,959/4,959 tests, and the installed-package consumer passes 24/24 tests.
- A 151 GB generated repository Zig cache was removed after it exhausted the development volume. The full gate then rebuilt from empty local and global caches, so the final result does not depend on stale compiler artifacts.
- [Open Work](open-work.md) no longer lists the implemented complex Jacobian functions as missing. Complex parameters and the remaining subsidiary ratios are optional work.

## 2026-07-26 Linux ALSA Device Backends

- Added optional runtime-loaded ALSA PCM and RawMIDI modules. Ordinary plugin binaries do not contain libasound symbols or backend code.
- ALSA PCM covers directional hint discovery, hashed stable identifiers, independent defaults and selection, f32 and f64 format negotiation, preallocated planar callback adaptation, topology polling, optional realtime priority, nonblocking stop, stream recovery, failure silence, and retained statistics.
- ALSA RawMIDI covers directional hint discovery, monotonic input timestamps, fragmented channel messages, running status, interleaved realtime bytes, bounded System Common and SysEx containment, fixed-capacity timestamp-scheduled output with stable ordering and nonblocking admission, queue cancellation and statistics, topology polling, transactional output replacement, stop, retry, and retained input and output failures.
- Both modules compile and fully link for Linux x86-64 and AArch64 without ALSA development headers. The installed-package consumer imports both public modules.
- The complete deterministic gate passed 189/189 steps and 5,082/5,083 tests with one expected CoreAudio platform-branch skip. ALSA PCM passed 7/7 focused tests, ALSA RawMIDI passed 8/8, and the installed-package consumer passed 36/36. Linux-native branches also load the optional library and build real discovery snapshots when libasound is present.
- [Open Work](open-work.md) records physical Linux audio and MIDI confirmation, native UMP transport, PipeWire runtime confirmation, cross-device drift, automatic recovery, and duplicated ALSA control-thread helper cleanup separately.
- No physical-device, audible, hot-plug, realtime-priority, or external Linux result was inferred from cross-builds and injected tests.

## 2026-07-26 Windows MIDI And Standalone Recovery

- Added an optional WinMM MIDI 1 module with directional discovery, interface-path identifiers, QueryPerformanceCounter-based input timestamps, 32-bit relative-timestamp wrap handling, fixed-capacity timestamp-scheduled short-message output with stable ordering and nonblocking admission, queue cancellation and statistics, topology polling, transactional output replacement, and retained input and output driver errors.
- The module compiles and fully links for Windows x86-64 GNU. The installed-package consumer imports the public module, while an ordinary Windows Gain VST3 contains no WinMM backend symbols.
- Added a format-neutral control-thread recovery coordinator. Initial selection, disappearance fallback, failed-restart rollback and retry, preferred-device restoration, and explicit same-selection restart are covered directly. Candidate state is published only after the application callback completes successfully.
- The complete deterministic gate passed 194/194 steps and 5,090/5,091 tests with one expected CoreAudio platform-branch skip. WinMM passed 6/6 focused tests and the installed-package consumer passed 36/36.
- [Open Work](open-work.md) records physical Windows MIDI confirmation, backend failure-signal integration, physical recovery confirmation, Windows MIDI Services and UMP, and application windows separately.
- No physical Windows enumeration, MIDI delivery, hot-plug, busy-device, long-session timing, audible, or recovery result was inferred from cross-builds and injected tests.

## 2026-07-26 Native MIDI 1 Output Scheduling

- WinMM and ALSA RawMIDI now share a fixed-capacity 256-message native queue with timestamp ordering, stable equal-time submission order, due-time removal, validation, saturation rejection, and cancellation.
- Each backend owns a native worker that accepts current, late, and future timestamps without blocking on delivery. Producer lock contention or queue saturation returns a backend-specific queue-full error.
- Replacement and close stop and join the worker before closing the native output handle. Queued messages are canceled and counted. Queued, delivered, past-due-at-dispatch, rejected, canceled, and driver or write failures remain queryable after teardown.
- Direct native C queue tests and injected Zig backend tests pass. ReleaseSafe link executables compile for Windows x86-64 GNU, Linux x86-64, and Linux AArch64. The combined focused gate passes 14/14 steps and 14/14 Zig tests.
- The complete deterministic gate passes 297/297 steps and 5,538/5,539 tests with one expected CoreAudio service-availability skip. The installed-package consumer passes 42/42 tests.
- [Open Work](open-work.md) retains physical current and future delivery timing, equal-time order, saturation, cancellation, failure-triggered recovery, hot-plug, reconnect, and teardown confirmation for both platforms.
- No physical-device delivery accuracy or timer-resolution claim was inferred from deterministic queue tests and cross-builds.

## 2026-07-26 Standalone Window Shell

- Added a format-neutral top-level window backend, window lifecycle, and bounded control loop around the shared editor and device-recovery contracts.
- Tests cover native-parent creation, failed-attachment rollback, idempotent visibility, constrained resize requests, native resize, display scale, focus, close requests, recovery suppression after close, and exact-once editor and backend teardown.
- The installed-package consumer exposes the shell and backend boundary.
- Added an optional Win32 top-level backend with UTF-8 title conversion, hidden parent creation, visibility, client-area resize, bounded message dispatch, coalesced DPI, focus, resize, and close events, and close-before-destroy ordering.
- Focused tests pass 4/4. A ReleaseSafe Windows x86-64 GNU executable fully links the backend against User32, the installed-package consumer imports it, and ordinary Windows VST3 binaries contain no standalone-window symbols.
- The complete deterministic gate passed 199/199 steps and 5,097/5,098 tests with one expected CoreAudio platform-branch skip.
- [Open Work](open-work.md) now limits missing native implementations to Cocoa, X11, and Wayland while retaining physical Win32 input, DPI, lifecycle, accessibility, and visual confirmation.

## 2026-07-26 Cocoa Standalone Window

- Added an optional AppKit top-level backend with a bounded UTF-8 title, hidden resizable `NSWindow`, content `NSView` parent, visibility, content resize, and coalesced resize, backing-scale, focus, and close events.
- The AppKit poll dispatches at most 32 events per call. Close remains a request so the format-neutral shell can stop audio and detach the editor before native teardown.
- Focused tests pass 4/4 across 6/6 build steps. A native ReleaseSafe executable fully links against AppKit and Foundation, and Linux and Windows portability builds compile the unsupported path.
- The installed-package consumer passes 36/36 with the public module imported. An ordinary macOS Gain VST3 contains no Cocoa backend or delegate symbols.
- The complete deterministic gate passed 205/205 steps and 5,107/5,108 tests with one expected CoreAudio platform-branch skip after the subsequent polynomial root-solving and device-failure monitor suites were added.
- [Open Work](open-work.md) now limits missing native window implementations to X11 and Wayland. Physical macOS parent attachment, Retina transitions, input, lifecycle, VoiceOver, appearance, and visual confirmation remain explicit external checks.

## 2026-07-26 Automatic Device-Failure Recovery

- Added a format-neutral monotonic failure snapshot, source, monitor, report, and fixed-capacity multi-source monitor set.
- Multi-source polling is transactional. A failed source read leaves every baseline unchanged, counter increases are combined by device domain, and counter resets after restart do not create false recovery requests.
- `StandaloneShell` accepts as many as eight backend sources, reports new failures, requests a same-selection restart, and then uses the existing rollback-safe recovery callback.
- CoreAudio exposes device-side AUHAL callback failures while keeping processor rejection separate. WASAPI and ALSA PCM expose configured-direction device failures. CoreMIDI, WinMM, and ALSA RawMIDI expose retained input disconnect, driver, or read failures.
- The installed-package consumer exercises the public declarations. Native and cross-target backend gates pass, and the complete deterministic gate passes 205/205 steps and 5,107/5,108 tests with one expected CoreAudio platform-branch skip.
- Physical CoreAudio, Windows, Linux, and macOS MIDI recovery remains manual.

## 2026-07-26 Timestamped UMP Device Scheduling

- Added format-neutral timestamped UMP input and output device contracts, a bounded single-producer and single-consumer input queue, and allocation-free audio-block scheduling.
- The block buffer preserves complete 32, 64, 96, and 128-bit packets rather than narrowing Utility, System, SysEx, Flex Data, Stream, or MIDI 2 messages into plugin events.
- Tests cover device callbacks, every packet width, late and current placement, future retention, block-buffer capacity, queue capacity, rejected callback counting, invalid packets, timestamp order, reset, and corrupted queue containment.
- `UmpOutputDevice.sendBlock` converts sample offsets back to absolute device timestamps, reports invalid and rejected packets separately, and contains timestamp overflow.
- The installed-package consumer passes 37/37. The complete deterministic gate passes 205/205 steps and 5,111/5,112 tests with one expected CoreAudio platform-branch skip. The public core passes 1,047/1,047 tests.
- Native Windows MIDI Services and Linux UMP bindings remain implementation work. Physical UMP device delivery, timestamp accuracy, hot-plug, and scheduled output remain manual confirmation after those bindings exist.
- The structurally parallel MIDI 1 and UMP queue and scheduler implementations remain a cleanup candidate if a shared private generic can preserve the current public error contracts without obscuring either path.

## 2026-07-26 X11 Standalone Window

- Added an optional Linux X11 top-level backend with bounded UTF-8 titles, hidden parent creation, visibility, resize, focus, `WM_DELETE_WINDOW`, bounded event dispatch, and teardown.
- The C shim loads Xlib at runtime and uses no X11 development headers. Ordinary plugin binaries do not import the optional module or gain a hard X11 dependency.
- Focused tests pass 5/5 across 8/8 build steps. ReleaseSafe Linux x86-64 and AArch64 executables fully link the backend, the Windows unsupported path compiles, and the installed-package consumer passes 37/37.
- The complete deterministic gate passes 213/213 steps and 5,116/5,117 tests with one expected CoreAudio platform-branch skip.
- Physical display connection, parent attachment, window-manager behavior, input, DPI policy, AT-SPI, XWayland, reopen, and teardown remain manual. Native Wayland remains implementation work.

## 2026-07-26 Standalone Linux Run Loop

- Added a fixed-capacity driver around the existing Steinberg `IRunLoop` implementation for standalone VSTGUI editors on Linux.
- The driver snapshots registered file descriptors into caller-owned storage, bounds every poll wait by the next timer deadline, dispatches ready handlers, fires each due periodic timer once per pump, and coalesces missed periods without timer drift.
- Registration rejects zero timer intervals and capacity exhaustion. Dispatch rejects clock regression and malformed retained entries. Duplicate timer registration resets its deadline without adding a second retained reference.
- Teardown releases all retained event and timer handlers exactly once. Injected tests also cover callback self-removal, timestamp overflow containment, ready-descriptor dispatch, and idle pumps.
- Focused tests pass 34/34 across 6/6 build steps. ReleaseSafe Linux x86-64, Linux AArch64, and unsupported Windows builds compile, and the installed-package consumer passes 38/38.
- The complete deterministic gate passes 219/219 steps and 5,153/5,154 tests with one expected CoreAudio platform-branch skip.
- Physical VSTGUI handler registration, X11 input delivery, timer cadence under load, close ordering, and teardown remain manual Linux confirmation.

## 2026-07-26 File-Backed PCM Fault Containment

- Added `FileWriterOperations`, a counted positional-write and length-change boundary shared by the WAV, AIFF, RF64, and Wave64 file writers.
- Short writes retry at the next exact file offset. Zero progress, over-reported counts, positional overflow, partial-write errors, and truncate failures are contained.
- Audio-write rollback restores the committed file length, caller dither state, and any AIFF, RF64, or Wave64 padding overwritten by the failed append.
- Header, padding, or truncate failures leave the writer failed but recoverable. A later successful `recover` restores exact length and current headers before allowing another append.
- The focused fault suite passes 59/59. The public DSP suite passes 520/520, Linux AArch64 and Windows x86-64 GNU compile the complete DSP module, and the installed-package consumer passes 39/39.
- The complete deterministic gate passes 219/219 steps and 5,157/5,158 tests with one expected CoreAudio platform-branch skip. The public core passes 1,051/1,051.

## 2026-07-26 Incremental File-Backed Ogg Output

- Added `OggFileWriter` with caller-owned maximum-page storage and the same page encoder used by the bounded memory writer.
- Packet layout arithmetic validates before file mutation. Packets may span multiple maximum-sized pages while preserving CRC, lacing, continuation, sequence, granule, BOS, and EOS fields.
- Counted positional writes retry short progress. A failed page write truncates every page from that packet back to the committed boundary, and a failed rollback leaves explicit recoverable state.
- Finalization requires EOS, repairs the exact committed length, and synchronizes the file. The file-backed packet reader round-trips a continued 65,100-byte packet plus its terminal packet.
- Focused Ogg coverage passes 32/32, including shared FFT and positional-I/O tests. The installed-package consumer passes 40/40.
- The complete deterministic gate passes 219/219 steps and 5,160/5,161 tests with one expected CoreAudio platform-branch skip. The public DSP module passes 523/523 and the public core passes 1,054/1,054.

## 2026-07-26 Complete Typed VST3 Host Restarts

- Replaced separate latency and I/O pending booleans with the format-neutral `HostChange` contract. It covers all twelve VST3 restart categories.
- The component coalesces duplicate changes into one atomic set. Failed host calls and missing peers restore the entire consumed set with atomic OR, preserving changes marked during dispatch.
- Integration coverage maps every category to the matching Steinberg flag and exercises duplicate marks, explicit host rejection, disconnection, retry, and the installed-package export.
- The complete deterministic gate passes 219/219 steps and 5,161/5,162 tests with one expected CoreAudio platform-branch skip. The public core passes 1,055/1,055 and the installed-package consumer passes 40/40.

## 2026-07-26 High-Level VST3 Payload Forwarding

- `Vst3Processor` now reflects optional resource-path and decoded-audio receivers from the high-level plugin without fixing their result types.
- Scalar, graph, and bounded text telemetry plus editor-open and editor-close notifications use the same adapter. Explicit capability flags keep unsupported interfaces undiscoverable while preserving the low-level processor contract.
- Direct adapter tests cover every forwarded hook. VST3 integration coverage sends resource, audio-import, telemetry, and editor lifecycle payloads through the component, and the installed-package consumer exercises the public surface.
- Fixed Rate now reports its latency through high-level scalar telemetry. Its Linux x86-64 GNU and Windows x86-64 GNU bundles each pass all 4 build steps.
- The complete deterministic gate passes 219/219 steps and 5,197/5,198 tests with one expected CoreAudio platform-branch skip. The public core passes 1,055/1,055 and the installed-package consumer passes 41/41.
- Specialized controller migration and Model Shell's self-referential construction remain tracked cleanup and feature work. No manual host or visual result was inferred from these automated checks.

## 2026-07-26 IR Loader Runtime Migration

- IR Loader now owns its large in-place convolution engine through a stable heap allocation inside the checked high-level processor runtime.
- `Vst3Processor` forwards the decoded-audio receiver while the existing controller retains import, edit, clear, rollback, state, and view ownership. Both f32 and f64 processing remain advertised.
- The migration exposed that the headless host stress harness called `process` without activating the component. The harness now follows VST3 order: setup, component activation, processing activation, processing stop, and component deactivation.
- The corrected concurrent editor and processing stress passes with 12 editor lifecycles and at least 128 process blocks. Existing import publication, edit, clear, restore, and busy-worker rejection tests also pass.
- Native bundling passes 6/6 steps. Linux x86-64 GNU and Windows x86-64 GNU bundles each pass 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,197/5,198 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- Existing manual IR Loader host and visual results remain recorded separately. This migration adds automated lifecycle evidence and does not replace native host confirmation.

## 2026-07-26 Resource Swap Stable Runtime Ownership

- Resource Swap now allocates its engine at the final address before initialization submits a background request containing a pointer to the engine's publication exchange.
- The high-level runtime forwards both f32 and f64 processing. Teardown joins the preparation worker, retires active and pending resources, deinitializes the exchange, and then destroys the engine through its allocator.
- A focused runtime regression completes initial and replacement preparation, adopts the replacement at a block boundary, verifies f64 output, and reclaims the retired generation.
- Native bundling passes 4/4 steps. Linux x86-64 GNU and Windows x86-64 GNU bundles each pass 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,199/5,200 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- This establishes the stable-address ownership pattern needed by larger self-referential processors. Model Shell still requires a separate migration that preserves recovery, state, telemetry, and host requests.

## 2026-07-26 Sample Player Runtime Migration

- Sample Player now heap-owns its bounded voice, decoded-sample, parameter-latch, and playhead engine through the checked high-level runtime.
- `Vst3Processor` forwards decoded-audio import, playhead graph loads, and editor-open and editor-close activity. MIDI events and sample-accurate parameter changes still segment both f32 and f64 processing.
- Capability regressions require all four optional forwarding flags and f64 processing. Existing controller and processor tests retain import isolation, malformed input, retry, replacement across editor teardown, clear, note lifecycle, voice stealing, reverse and loop behavior, non-finite containment, persisted parameter continuity, and graph activity coverage.
- Concurrent headless stress passes 12 editor lifecycles and at least 128 process blocks. The complete focused plugin root passes 16/16 tests.
- Native bundling passes 6/6 steps. Linux x86-64 GNU and Windows x86-64 GNU bundles each pass 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,199/5,200 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- The deferred REAPER walkthrough still covers audible playback, waveform interaction, two instances, state restore, resizing, and teardown. No manual result was inferred from this migration.

## 2026-07-26 Channel Strip Runtime Migration

- Channel Strip now processes typed parameter views through the checked high-level runtime for f32 and f64.
- The adapter forwards three scalar meters, waveform and spectrum graphs, and editor-open and editor-close activity. The controller retains its importer, imported waveform, view state, presets, actions, and specialized editor declaration.
- Capability regressions require scalar, graph, and both editor-activity hooks. Existing tests retain mode processing, importer reopen, instance isolation, serialized controller state, activity gating, retained telemetry across editor teardown, and concurrent headless lifecycle coverage.
- Native bundling passes 6/6 steps. Linux x86-64 GNU and Windows x86-64 GNU bundles each pass 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,199/5,200 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- Existing Channel Strip REAPER observations remain the manual visual evidence. This migration does not infer a new host result.

## 2026-07-26 EQ And Resonant Filter Runtime Migration

- Parametric EQ and Resonant Filter now process typed parameter views through the checked high-level runtime for f32 and f64.
- The adapter forwards each activity-gated spectrum graph plus editor-open and editor-close activity. Their specialized controllers retain response curves, linked handles, presets, view state, and responsive editor declarations.
- Capability regressions require graph and both editor-activity hooks. Existing graph gating, processor isolation, DSP behavior, controller state, headless lifecycle, GUI, and host-focused regressions remain unchanged.
- Each native bundle passes 6/6 steps. Each Linux x86-64 GNU and Windows x86-64 GNU bundle passes 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,199/5,200 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- Existing REAPER results remain the manual visual evidence. This migration does not infer new visual, interaction, or audible confirmation.

## 2026-07-26 Model Shell Runtime Migration

- Model Shell now allocates its recovery engine at its final address before initializing the worker and processor-owned approval pointers.
- The high-level runtime forwards bounded component state, resource import and relink commands, latency host requests, scalar and bounded text telemetry, and typed f32 and f64 processing.
- Focused regressions require the resource and telemetry capabilities, both processing precisions, stable receiver ownership, successful recovery publication, and equivalent f32 and f64 output.
- Existing connected component and controller tests retain editor-independent restoration, changed and missing resource handling, relink, retry, telemetry truncation, retained metadata after failure, latency approval, realtime silence, repeated replacement, and pending-worker teardown coverage.
- Native, Linux x86-64 GNU, and Windows x86-64 GNU bundles each pass 4/4 steps.
- The complete deterministic gate passes 219/219 steps and 5,201/5,202 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- Real-host resource workflows, audible processing, telemetry presentation, and teardown remain in the manual high-level runtime check. No host or visual result was inferred from this migration.

## 2026-07-26 High-Level VST3 Configuration Consolidation

- `Vst3Effect` now derives main and auxiliary topology, event buses, host-transport requirements, parameter metadata, and the checked processor adapter from one high-level declaration.
- `Vst3Controller` derives the ordinary reflected-controller configuration. Configured-parameter variants build controller and processor parameter sets from the same descriptor value used by their runtime adapters.
- Resource-path and decoded-audio target IDs, GUI note input, and extra process-context requirements remain explicit VST3 integration choices.
- Twelve high-level examples use the constructor across mono, surround, sidechain, auxiliary-output, worker, recovery, import, telemetry, analyzer, and instrument paths. Specialized controllers retain their editor-specific declarations. The C-kernel probe remains a direct `SimpleEffect` conformance integration.
- Focused coverage checks configured parameter defaults, derived mono and 5.1 layouts, optional resource and decoded-audio transports, telemetry, public package construction, and public controller construction.
- Native example bundling passes 70/70 steps. Linux x86-64 GNU and Windows x86-64 GNU example matrices each pass 68/68 steps.
- The complete deterministic gate passes 219/219 steps and 5,211/5,212 tests with one expected CoreAudio platform-branch skip. The installed-package consumer passes 41/41.
- Existing real-host and visual checks remain unchanged because the constructors preserve the generated component and controller contracts.

## 2026-07-26 Standalone Wayland Window Backend

- Added the optional `zig-vst3-waylandwindow` module. It discovers libwayland-client at runtime and carries the stable xdg-shell protocol metadata needed for a top-level surface.
- The C shim binds the compositor, shared-memory, seat, keyboard, and as many as eight output objects. It handles xdg-shell ping and configure, maps and unmaps the parent surface tree through a fixed one-pixel shared-memory buffer, and tears down every proxy before disconnecting.
- Native callbacks coalesce compositor resize, integer output scale, keyboard focus, and close state. The poll path reads the display without blocking and returns one retained standalone event at a time.
- The public backend validates bounded UTF-8 titles, rolls failed opens back completely, exposes the native display, `xdg_surface`, and `xdg_toplevel` objects, and keeps Wayland dependencies out of ordinary plugin binaries.
- Injected lifecycle coverage passes 5/5. Strict-C11 Linux x86-64 and AArch64 test and link-smoke builds pass, as does the unsupported Windows portability build. The installed-package consumer remains 41/41.
- The complete deterministic gate passes 227/227 steps and 5,216/5,217 tests with one expected CoreAudio platform-branch skip.
- Native GNOME, KDE, Sway, Weston, output-scale, focus, close ordering, input, accessibility, reopen, and teardown checks remain manual. A reusable standalone VSTGUI `IWaylandHost`, `IWaylandFrame`, and run-loop bridge remains implementation work.

## 2026-07-26 Standalone VST3 Wayland Frame Bridge

- Added `vst_wayland_standalone_frame.StandaloneBridge`, which presents one ref-counted `IPlugFrame`, `IWaylandFrame`, and `IWaylandHost` identity and delegates `IRunLoop` queries to the standalone driver.
- Native-object queries accept only the active backend display. Display connections use matched borrow tracking, and `validateDetached` rejects retained interfaces or outstanding borrows before backend teardown.
- Child resize requests validate the VST3 rectangle, pass the logical size through the backend, return the accepted dimensions, and retain bounded diagnostic state.
- Focused bridge coverage passes 40/40 tests across 6/6 steps. Native execution plus Linux x86-64, Linux AArch64, and Windows portability builds pass.
- The installed-package consumer composes the public Wayland backend, run loop, and bridge and passes 42/42 tests.
- The complete deterministic gate passes 233/233 steps and 5,261/5,262 tests with one expected CoreAudio platform-branch skip.
- GNOME, KDE, Sway, Weston, VSTGUI child attachment, output-scale, input, focus, close ordering, retained-object teardown, accessibility, appearance, and repeated reopen checks remain manual.

## 2026-07-26 Expanded VST3 Speaker Layout Catalog

- `AudioBusLayout` now exposes 39 non-empty layouts: mono, five stereo roles, cinematic and music surround variants through 7.1, 5.x and 7.x immersive arrangements through 7.1.4, and first- through seventh-order ACN ambisonics.
- Every legacy enum identifier remains unchanged. `AudioBusLayoutSet` now uses a 64-bit mask, and topology state version 2 restores version-1 16-bit masks before validating the complete topology.
- Exhaustive tests verify every public channel count, layout-set membership, legacy identifier, old-state fixture, extended-state round trip, VST3 speaker arrangement round trip, and generated bus channel count.
- The installed-package consumer constructs an extended layout set and observes the 64-channel seventh-order ambisonic contract.
- Native CoreAudio and CoreMIDI availability probes now skip when the operating-system service or hardware is absent. Mocked lifecycle, malformed-state, and cross-target tests continue to fail normally.
- The complete deterministic gate passes 233/233 steps and 5,273/5,276 tests. The three skips are explicit macOS service or device availability branches.
- Arbitrary bus counts and specialized arrangements outside the expanded catalog remain product-driven work. Physical dynamic-topology host confirmation remains manual.

## 2026-07-26 Production LV2 VSTGUI Parameter UI

- Added a production backend that binds the toolkit-neutral LV2 editor contract to VSTGUI parameter controls. It supports continuous, integer, and decibel sliders, toggles, enum menus, reflected names and units, tooltips, formatting, parsing, context menus, gestures, host parameter updates, idle flushing, focus, scale, resize, detach, and destruction.
- The native boundary now publishes VSTGUI's platform widget and exposes checked idle processing. Widget lookup remains unavailable until attachment succeeds, and failed open or widget publication rolls the complete operation back.
- Mono Gain now builds a separately linked LV2 VSTGUI UI library. Generated bundle metadata selects the native LV2 UI class, names the UI binary, requires the parent feature, and retains the declaration-derived core ports and presets.
- Injected backend tests cover metadata construction, inferred control kinds, missing parents, open and widget failures, gesture ordering, formatting, parsing, context menus, host automation, constrained resize, focus, scale validation, and exact teardown.
- Dynamic smoke coverage loads the real UI library, validates `lv2ui_descriptor`, checks the idle, resize, and show interfaces, and rejects malformed construction inputs. The focused LV2 gate passes 41/41 steps, including the declaration-driven freewheeling port and dynamically loaded realtime/offline transitions. The installed-package consumer passes 42/42.
- The complete deterministic gate passes 239/239 steps and 5,275/5,278 tests. The three skips are explicit macOS service or device availability branches.
- External confirmation remains required in at least two LV2 hosts. It must cover native parent embedding, host automation, UI gestures and touch, idle delivery, host-requested and UI-requested resize, show and hide behavior, two instances, close and reopen, accessibility, and visual appearance on each supported platform.
- Advanced VSTGUI component composition and product-specific editors remain extension work. The current backend is intentionally parameter driven.

## 2026-07-26 ARA Controller Foundation

- Vendored the official ARA API declarations and license files. The build translates the C API per target, while the VST3 companion declarations retain exact interface IDs and C++ layout parity.
- Added a fixed-capacity document model for musical contexts, region sequences, audio sources, audio modifications, and playback regions. Editing transactions, generational references, persistent-ID uniqueness, sample-access state, dependency-aware destruction, and no-op revisions are checked.
- Added the complete ARA document-controller callback table and a fixed-capacity factory pool. Invalid host properties and callback failures are retained instead of crossing the C ABI as traps.
- Added versioned full and filtered archive transport, persistent-ID remapping validation, host progress callbacks, corruption rejection, planar f32 and f64 host audio readers, deterministic reader teardown, and typed content providers for all six standard event families.
- Added bounded playback-renderer and editor-renderer assignments, mutually exclusive editor assignment modes, copied editor-view selection and hidden-sequence state, retained callback errors, and revisioned product publication callbacks. Legacy and role-specific VST3 entry points bind the same stable extension instance and expose only assigned modern roles.
- Corrected the `IPlugInEntryPoint` vtable to include `getFactory`, extended the ABI harness to verify its vtable position, added matching main-factory class registration, and aggregated both entry-point generations into the canonical audio component identity.
- The focused ARA gate passes 42/42 steps and 135/135 tests, including Linux AArch64, Linux x86-64, and Windows x86-64 GNU builds plus exact official ABI comparison. The installed-package consumer passes 42/42.
- The complete deterministic gate passes 281/281 steps and 5,465/5,468 tests. The three skips are explicit platform service or device availability branches.
- Product analysis and editing state, audio rendering from published assignments, product class-list assembly, and external ARA-host validation remain open. No host, audible, or visual result was inferred from the internal gate.

## 2026-07-26 ARA Playback Renderer Foundation

- Added complete render descriptions that resolve a generational playback-region reference through its modification and source, including timing, source format, sample-access state, and transformation flags.
- Replaced the former one-reader-per-source policy with a bounded generational reader pool. Multiple renderer instances can open the same source independently, and stale reader handles fail deterministically. Each read takes an atomic lease. Synchronous source-access disable rejects new leases, waits for every in-flight read, and then closes all matching readers as required by the official ARA threading contract.
- Added bounded model-publication observers. Graph edits and source-access transitions rebuild product render plans, while private document-data notifications remain queued until the host calls `notifyModelUpdates`.
- Added `ara_playback_renderer.Renderer` for f32 and f64 products. It publishes immutable plans through `RealtimeSnapshotPublisher` and reads through a product-owned realtime source provider, never through ARA's potentially blocking host reader. It uses fixed planar scratch storage, maps playback time into modification and source time, linearly interpolates source samples, sums overlapping regions, and clears every output after a render failure. Cache readiness is checked on the control thread and can be republished explicitly.
- `SimpleEffect` and `HighLevelEffect` now initialize ARA extension state only after it reaches its final component address and release observer and reader state before processor teardown. A lifecycle regression checks both hooks through canonical ARA component identity.
- `appendMainFactoryClass` appends the registered ARA main factory to a compile-time product class list and rejects a class-ID collision. The factory regression enumerates the combined list and creates the ARA main-factory interface through ordinary VST3 dispatch.
- The product-style fixture runs the same full lifecycle for f32 and f64. Each path binds the role-specific VST3 entry point, assigns a real controller region, verifies exact stereo samples from a cache provider, republishes a timing edit, proves host source-access disable does not invalidate already cached playback, publishes silence while the provider reports unavailable data, recovers after cache readiness returns, rejects a deleted region, and confirms that playback opened no host reader. A separate controller concurrency regression blocks a non-realtime host read, starts source disable on the model thread, proves disable cannot finish early, releases the read, and verifies ordered reader destruction.
- The focused ARA gate passes 47/47 steps and 178/178 tests, including native execution, exact official ABI comparison, and Linux AArch64, Linux x86-64, and Windows x86-64 GNU builds. The complete deterministic gate passes 286/286 steps and 5,512/5,515 tests. The three skips are explicit platform service or device availability branches.
- Product cache filling, analysis and editing, tempo-reflection and content-fade rendering, higher-quality resampling or stretching, and external ARA-host validation remain open. Audition and host behavior remain manual. No audible, host, or visual result was inferred from the automated gate.

## 2026-07-26 ARA Transactional Source Cache

- Extended `RealtimeReferencePublisher` with `beginPublish`, an in-place control-thread writer reservation. Large states can be filled directly in an inactive unreferenced slot, committed as one immutable generation, or cancelled without changing the active generation. Existing by-value publication now uses the same transaction.
- Added `ara_source_cache.Cache` for f32 and f64 products. Its compile-time limits bound sources, channels, frames per source, and publication slots. `loadSource` performs all ARA reader creation, host I/O, and teardown on the calling non-realtime thread. A complete fill is published atomically, while capacity, open, read, or publication failure preserves the previous generation.
- The cache renderer provider performs only bounded atomic reference acquisition, validation, planar copies, and release. Generational source identity rejects recycled model slots. Explicit invalidation publishes unavailability without exposing partially changed audio.
- The renderer lifecycle fixture now uses the production cache rather than a synthetic direct-array provider. Both precisions prove exact stereo rendering, cached playback across host sample-access disable and re-enable, explicit cache loss and reload, model timing updates, deterministic silence, and exact host-reader teardown. Rendering itself opens no ARA host reader.
- Renderer limits now select linear, Catmull-Rom cubic, or normalized eight-tap windowed-sinc interpolation. Cubic mode reads the bounded neighboring samples needed by its four-point kernel. Windowed-sinc mode selects normalized Lanczos weights from a compile-time 1,024-phase table, reads three preceding and four following samples, preserves constants and exact sample points, safely duplicates source endpoints, and reduces analytic high-frequency fractional-position RMS error by more than tenfold relative to linear interpolation. It performs one lookup and eight multiply-adds per sample and channel without realtime trigonometry. The complete cache-backed lifecycle runs in all three modes for f32 and f64.
- ARA-enabled effect configs may now bind the finalized extension address into processor-owned product state and remove that link before teardown through optional `bindAraExtension` and `unbindAraExtension` hooks. The component lifecycle regression checks one initialization, bind, unbind, and deinitialization.
- Added `test-vst3-module`, a focused public-module target that builds the native adapter without running visual benchmarks. It passes 7/7 steps and 714/714 tests after the effect wiring change.
- A concurrent regression runs four realtime readers while the control writer attempts 10,000 cache generations. Every successful read sees one complete internally consistent generation. Transactional read failure, invalidation, stale generation rejection, writer cancellation, writer reuse rejection, slot exhaustion, and reclamation are also covered. The dedicated realtime publication thread-sanitizer gate passes 10/10.
- The focused ARA gate passes 52/52 steps and 187/187 tests, including official ABI comparison and Linux AArch64, Linux x86-64, and Windows x86-64 GNU builds. The installed-package consumer passes 42/42. The complete deterministic gate passes 291/291 steps and 5,530/5,533 tests. The three skips are explicit platform service or device availability branches.
- Added `ara_source_cache.PagedCache` for bounded sources larger than a practical whole-source generation. It owns a fixed LRU page working set plus a reference-counted immutable directory. Region loads include interpolation padding. Range loads preserve matching pages and replace only unprotected least-recently-used pages. Forced refresh reserves every page writer and the next directory writer before host I/O, fills all pages, commits their generations, and publishes the directory last.
- Paged realtime reads pin one directory and validate every page's recorded generation, source identity, format, and logical index. Publication races can return a checked miss but cannot return a successful mixed-page buffer. Tests cover cross-page reads, eviction, failed-refresh rollback, invalidation, page-capacity rejection, and four concurrent readers across 2,000 three-page refresh attempts without a mixed successful read. The concrete ARA product now uses this paged provider.
- Product-specific analysis and editing behavior, tempo-reflecting or spectral transformations, content-based fades, and external ARA-host validation remain open. Audible and host behavior remain manual. No audible, host, or visual result was inferred from the automated gate.
- Two later aggregate retries passed the focused ARA, installed-package, platform, DSP, LV2, and runner branches that executed but stopped at the native VSTGUI visual timing budget. Every visual measurement was about twice the preceding clean run, including unrelated controls and editors. This is tracked as an environment-limited post-wiring aggregate recheck, not as a code pass or an inferred visual regression.

## 2026-07-27 ARA Static-Tuning Analysis

- Extended the typed content-provider contract with analysis-incomplete queries, validated analysis requests, and source-content invalidation callbacks. Requests must be nonempty, contain distinct valid types, and remain a subset of the factory's advertised analysis types.
- Added checked source-analysis progress and source-content-change notifications through the host model-update controller. Invalid progress states, non-finite or out-of-range progress, malformed time ranges, and unknown update flags fail before the host callback.
- Factories now accept a validated `analyzeable_content_types` list and an optional fixed per-controller extension type. Extension state attaches after controller construction, detaches during controller release, and reports lifecycle failure through the factory error channel.
- Added `ara_tuning_analysis.Analyzer`. It bounds sources, channels, input frames, and copied display names at compile time. Non-realtime analysis reads one fixed source window, validates every channel, selects the channel with the greatest AC energy to avoid phase-cancellation loss, removes DC, rejects quiet input, and estimates a monophonic fundamental through normalized autocorrelation and parabolic lag interpolation.
- Detected frequency is mapped to the nearest pitch number and an equal-temperament concert pitch. The analyzer publishes the official single `ARAContentTuning` event with detected grade. A checked 300–500 Hz manual override publishes approved grade and a copied name.
- Source-content updates preserve results only when the host guarantees the tuning scope is unchanged. Other updates invalidate the result without sending a notification back in response to the host's own change.
- The playback reference factory advertises static-tuning analysis and gives every factory-created controller its own bounded analyzer. Installed consumers verify both the analyzer type and pure detection function through the public package.
- Focused detection covers a DC-offset 442 Hz tuning, silence, malformed configuration, integrated host audio reads, progress and content notifications, typed reader publication, invalidation, and approved overrides. Factory tests cover advertised types and extension ownership. The focused ARA gate passes 57/57 steps and 214/214 tests. The ARA playback product passes 10/10 steps and 4/4 tests. Installed consumers pass 48/48. The complete deterministic gate passes 313/313 steps and 5,661/5,664 tests with three expected platform-service skips.
- Analysis and approved-edit archive persistence, polyphonic note or tempo analysis, advanced transformations, and external ARA-host confirmation remain open. No host-observed or audible behavior was inferred from the automated gate.

## 2026-07-27 ARA Analysis Persistence

- Advanced the controller archive to version 2 while retaining version-1 decoding. The new format appends one length-delimited provider payload after the generic source and modification identifiers.
- Added `archive_extension_bytes` to controller limits. It defaults to zero and bounds both inline archive storage and accepted provider data. The playback product reserves 512 bytes per controller.
- Content providers can calculate an exact payload size, write into controller-owned storage, and restore from immutable bytes plus resolved source mappings. Full restore maps stored persistent IDs against the graph. Filtered restore honors host-provided archive-to-current persistent-ID mappings.
- The tuning analyzer stores only selected source records. Each record contains its selected-source index, detected or approved grade, checked concert pitch, and bounded UTF-8 name.
- Restore first validates the complete magic, version, count, unique indexes, mappings, statuses, pitch bounds, names, and end position into staged fixed storage. It clears only mapped selected sources and commits once. A malformed payload leaves all current analysis and approved edits unchanged.
- Controller tests exercise version-2 storage and version-1 compatibility. The integrated analyzer lifecycle exercises a full approved-state round trip, filtered restore, and corrupt-extension rollback while retaining a newer approved value.
- The focused ARA gate remains 57/57 steps and 214/214 tests because persistence extends existing lifecycle tests rather than adding a new top-level test. The playback product remains 10/10 steps and 4/4 tests, and installed consumers remain 48/48. The complete post-wiring aggregate is recorded in `docs/open-work.md`.
- Polyphonic note or tempo analysis, advanced transformations, and external ARA-host confirmation remain open. Manual validation must include save and reopen, partial archives, remapping, and failure containment.
