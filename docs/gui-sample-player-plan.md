# Production Sample Player Plan

## Outcome

Build a MIDI-driven sample player whose editor uses only the public `@import("zig-vst3").vstgui` authoring API. The plugin will import bounded PCM WAV and AIFF files, publish decoded audio to the processor without audio-thread locks or allocation, and provide a production waveform editing and playback workflow.

This milestone is the second production consumer for decoded-audio transport and importer-aware action dependencies. It adds the first production consumer for the direct bipolar slider and validates controller-sourced waveform snapshots in an instrument rather than an effect.

## Invariants

- The audio callback allocates no memory, takes no locks, performs no file I/O, calls no host or GUI API, and reads only processor-owned fixed-capacity storage.
- File parsing, decoding, preview construction, and controller-to-processor publication occur outside the audio callback.
- Parameter edits use standard begin, perform, and end gestures. Host updates do not emit another edit.
- Imported media, voices, editor state, callbacks, focus, and resize state remain isolated per plugin instance.
- Host state restores parameters and bounded editor metadata without hidden path access. Missing media restores as an explicit empty state.
- Rendering is deterministic, bounded, and activity-driven. Closing the last editor stops playhead publication and repaint work.
- Compact layouts keep every essential command reachable and never depend on scrolling to recover a lost layout mode.
- Focus, selection, loop state, enablement, progress, errors, and destructive actions do not rely on color alone.

## Milestone 1: Import and Playback Foundation

- [x] Extend the bounded decoder to PCM AIFF without weakening WAV validation or limits.
- [x] Add generated WAV and AIFF fixtures for valid, malformed, truncated, unsupported, oversized, cancelled, and replacement imports.
- [x] Add a fixed-capacity sample store with staged transfer, atomic adoption, cancellation, clear, and generation rejection.
- [x] Implement fixed-polyphony playback, deterministic voice stealing, interpolation, gain, pan, tuning, start and end bounds, looping, reverse, and ADSR.
- [x] Register the sample-player bundle in native, Linux, Windows, validator, and serialized pluginval matrices.

Exit criteria:

- WAV and AIFF decode to the same bounded interleaved representation.
- The processor never observes a partial import or reuses a stale generation.
- Decoded-audio publication rejects any chunk containing NaN or infinity without advancing the staged transfer.
- MIDI note-on and note-off behavior is sample-accurate, bounded, and free of stuck notes.
- Empty media produces silence and every accepted parameter value produces finite output.
- Focused tests, raw ABI checks, the Steinberg validator, and both cross-target bundles pass.

## Milestone 2: Production Waveform Editor

- [x] Declare the complete editor through `vst3.vstgui.createEditor` without adapter-internal imports.
- [x] Add File, Waveform, Playback, and Envelope groups with one clear primary import action.
- [x] Add drag-and-drop and picker entry, progress, cancel, retry, clear confirmation, and concise recovery text.
- [x] Add a controller waveform, horizontal viewport, start and end selection, loop range, live playhead, scales, and explicit empty and loading states.
- [x] Add direct bipolar pan, gain, coarse and fine tuning, playback and loop modes, reverse, ADSR, piano audition, and exact entry.

Exit criteria:

- Pointer, keyboard, picker, drop, piano, automation, exact-entry, and accessibility paths update one accepted state.
- Hover, pressed, selected, focused, disabled, loading, ready, and error states remain visibly distinct.
- Clear is separated from Import and Audition and requires confirmation.
- Overlapping waveform markers remain selectable and expose exact accessible values.

## Milestone 3: Responsive Layout and State

- [x] Define deterministic compact, standard, and expanded layouts with reversible manual resize behavior.
- [x] Prevent clipped labels, cramped controls, ambiguous selection, excess blank space, poor contrast, and unreachable actions in deterministic references.
- [x] Persist parameters, the declared responsive layout, viewport, start, end, loop range, loop mode, and safe import metadata.
- [x] Restore missing media as empty without file access and document portability limits.
- [x] Verify repeated editor open and close, processor restart, replacement import, cancellation during teardown, and two-instance isolation.

Exit criteria:

- Compact and expanded round trips preserve state and access to essential actions.
- Reopening never shows a stale waveform or claims unavailable media is loaded.
- Multiple instances can import, play, edit, resize, close, and reopen independently.

## Milestone 4: Accessibility, Visual, and Performance Coverage

- [x] Add toolkit-neutral names, roles, values, ranges, grouping, focus order, progress announcements, errors, waveform semantics, and piano state.
- [x] Add unit, interaction, lifecycle, accessibility, malformed-input, restoration, visual-regression, and performance coverage.
- [x] Add compact, standard, expanded, empty, importing, ready, looping, selected-handle, disabled, error, and high-contrast references.
- [x] Measure decoding, waveform construction, transfer, atomic adoption, voice processing, playhead updates, graph rendering, and repeated editor lifecycle.
- [x] Add a deterministic REAPER smoke project or script with generated audio and MIDI.

Exit criteria:

- Native adapter and macOS accessibility suites pass without lifecycle faults.
- Warm rendering and processing remain within recorded budgets at maximum supported capacity and polyphony.
- Manual validation requires no user-supplied audio.

## Milestone 5: API Decisions and Release Gates

- [x] Evaluate decoded-audio transport against the IR Loader and Sample Player contract. Keep it experimental until gallery and host coverage are complete.
- [x] Evaluate importer-aware action dependencies across both production consumers. Keep them experimental until gallery and host coverage are complete.
- [x] Evaluate the direct bipolar slider against the gallery and Sample Player. The Channel Strip now supplies the second production consumer.
- [x] Keep single-consumer or incomplete surfaces experimental and name each blocker.
- [x] Update the component reference, example lists, host matrix, and this plan with final evidence.

Release gates:

- [x] `zig build test raw-api-abi validate-examples --summary all`
- [x] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [x] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [x] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [x] Serialized pluginval strictness 5 and 10 with stop-on-first-exit diagnosis
- [ ] Focused REAPER walkthrough for import, playback, MIDI, every control, waveform editing, resize cycles, two instances, teardown, and restoration

External checks remain pending when their environments are unavailable:

- VoiceOver workflow in a macOS host
- Narrator and native Windows host interaction
- X11 and Wayland host interaction
- AT-SPI names, roles, values, focus, actions, and progress announcements
- Movement between displays with different scale factors

## Completion Evidence

Record committed milestones here with test counts, validator results, performance measurements, host observations, API decisions, and deferred checks. Pluginval validates lifecycle and protocol behavior, not visible layout or interaction quality.

### Baseline

- Branch: `feature/plugin-gui`
- Starting commits: graph telemetry lifecycle `8204ceb`; macOS pluginval launch `2becbe8`
- Existing local cache directory remains untracked.
- Parametric EQ validation was complete before this milestone: raw ABI and Steinberg validation passed, the macOS arm64 REAPER 7.36 walkthrough covered rendering, every control, linked editing, resize cycles, two instances, restoration, and repeated reopen, and the accepted installed bundle hash was `582da11205eba6535ad536261a2bce9b92f11496f718974de16f1ee255c3978a`.
- Resonant Filter validation was complete before this milestone: both serialized pluginval matrices passed all 13 examples in 56/56 steps, and the macOS arm64 REAPER 7.36 walkthrough covered every control, graph synchronization, active and bypassed spectrum behavior, sample-identical bypass, presets, resize cycles, two instances, and reopen restoration. The accepted candidate hash was `1ce54a6620aa0a578fd85cfb34870ff7d9c2f5c7e3870902c6429db935c91fb4`.
- The first sandboxed baseline run built the native adapter and passed 1,206 tests before Zig was denied access to its home cache. The repository-local cache rerun passed 62/62 steps and 3,747/3,747 tests.
- Baseline warm renders measured 91.5 us for the full visual scene, 263.1 us for signal views, 228.1 us for linked EQ, 139.8 us for Resonant Filter, 50.7 us for viewport rendering, and 103.8 us for range selection. Every scene remained inside its recorded budget.

### Milestone 1: Import and Playback Foundation

- The shared bounded decoder now accepts PCM WAV, AIFF, and uncompressed AIFC data at 16, 24, or 32 bits, up to two channels and 384 kHz. It rejects malformed chunks, truncation, unsupported encodings, inconsistent frame counts, excess input bytes, and decoded data beyond the caller's fixed capacity.
- Generated WAV and AIFF fixtures cover successful decode, bounded interleaved handoff, malformed and truncated data, unsupported formats, capacity failures, cancellation, replacement, retry, and instance isolation without user-provided media.
- A three-slot fixed-capacity sample store stages controller writes and publishes only complete generations. The audio thread adopts one ready generation at block boundaries and never observes partial or stale media.
- Sample-store writes validate every value before copying or advancing the staged offset. A non-finite chunk can be replaced by a valid chunk in the same generation, while commit remains unavailable until every finite sample arrives.
- Controller transport validates snapshot bounds, callback lengths, finite payloads, and source identity. It cancels publication if the importer generation or media metadata changes before commit.
- Receiver transport rejects host-supplied sample rate, channel count, frame count, and chunk offset values that do not fit the bounded framework types.
- A direct receiver recovery test injects an extreme offset and a non-finite payload into an active transfer, then proves a valid replacement chunk can still commit and become active.
- The reusable player provides eight fixed voices, oldest-voice stealing, linear interpolation, stereo and mono playback, gain, bipolar pan, coarse and fine tuning, bounded playback and loop ranges, forward and reverse playback, gate and one-shot behavior, and ADSR envelopes.
- The sample-player example is registered in native, Linux, Windows, validator, raw entry-symbol, test, and serialized pluginval matrices. Its editor declaration imports only the public `@import("zig-vst3").vstgui` API.
- `zig build test --summary all`: 66/66 build steps and 3,757/3,757 tests passed.
- `zig build raw-api-abi validate-sample-player --summary all`: 117/117 build steps passed. The Steinberg validator reported 47 tests passed and 0 failed for both 32-bit and 64-bit processing.
- `zig build bundle-sample-player-linux -Dtarget=aarch64-linux-gnu --summary all`: 4/4 steps passed.
- `zig build bundle-sample-player-windows -Dtarget=x86_64-windows-gnu --summary all`: 4/4 steps passed.
- Warm visual measurements during the final test run were 97.0 us for the full scene, 276.1 us for signal views, 240.3 us for linked EQ, 149.2 us for Resonant Filter, 54.1 us for viewport rendering, and 111.0 us for range selection. All remained inside their existing budgets.

### Milestone 2: Waveform Range Contract

- Waveform playback start and end now bind directly to their declared parameters through one ordered two-parameter gesture. Host automation moves the handles without emitting another edit, and rejection restores the accepted range.
- A graph may declare an independent secondary range. The sample player uses it for loop start and end. Circular top markers identify playback boundaries, while square bottom markers identify loop boundaries when positions overlap.
- Keyboard focus cycles across all four handles. Toolkit-neutral and native macOS accessibility values name the active playback or loop selection and expose its exact range.
- The ABI contract advanced to adapter version 25. Native validation rejects incomplete bindings, missing parameters, state and parameter persistence conflicts, and parameter reuse across the two ranges.
- Updated graph viewport references cover overlapping primary and secondary markers. The final warm render measurement for the two-range selection scene was 158.1 us, within the existing budget.
- Direct parameter-backed ranges and `secondary_range_selection` remain experimental. The visual gallery and sample player exercise the same public contract, but a second production consumer is still required for promotion.
- The direct bipolar slider is supported. Sample Player pan and Channel Strip drive share the public declaration, signed zero-centered rendering, reset behavior, exact entry, automation attachment, and accessibility contract.
- `zig build test raw-api-abi validate-sample-player --summary all`: 180/180 build steps and 3,758/3,758 tests passed. The Steinberg validator reported 47 tests passed and 0 failed for both processing precisions.
- The native adapter, macOS accessibility bridge, visual references, and warm-render benchmarks passed. The complete scene measured 84.9 us, graph viewport 47.1 us, and dual range selection 158.1 us.
- Linux aarch64 and Windows x86_64 sample-player cross-target bundles each passed 4/4 build steps. These builds are not native host validation.

### Milestone 3: Instrument Workspace and Safe Restoration

- Added the public experimental `.instrument_workspace` layout. It requires one importer and one progress indicator, accepts one optional piano, and places import, waveform editing, parameter panels, audition, metadata, destructive actions, and resize in a stable reading order.
- Compact, standard, and expanded sample-player references exercise the complete public editor declaration. Compact sizes use bounded vertical scrolling. Manual and preset resize tests verify clamped scroll positions, reversible breakpoints, and restoration to the top rather than a blank retained offset.
- Focus and accessibility traversal begin with Import and the waveform before parameter controls. The generic parameter keyboard hint is hidden because it does not describe the primary import workflow.
- Editor-state schema version 2 preserves viewport zoom and offset plus a UTF-8-safe, 64-byte maximum source basename. It never stores an absolute path or decoded audio. Version 1 state restores its viewport and defaults the new metadata field to empty.
- Reopening or restoring an instance performs no file access and restores no waveform. The persisted basename is informational only, so unavailable or moved media always produces the explicit empty state and requires a new import. This is deterministic but not portable media embedding.
- The host owns the accepted editor rectangle. The plugin declares one responsive layout rather than serializing a second layout mode. Reopening derives the same compact, standard, or expanded arrangement from the host-provided logical size.
- `zig build test --summary all`: 66/66 build steps and 3,760/3,760 tests passed, including native layout, macOS accessibility, visual regression, schema restoration, and Unicode-safe metadata coverage.
- The final warm-render pass measured 81.0 us for the full scene, 45.1 us for viewport rendering, and 154.7 us for dual-range rendering. All remained inside their existing budgets.
- `zig build raw-api-abi validate-sample-player --summary all`: 117/117 build steps passed. The Steinberg validator reported 47 tests passed and 0 failed for both processing precisions.
- Linux aarch64 and Windows x86_64 sample-player cross-target bundles each passed 4/4 build steps. These builds are not native host validation.

### Milestone 4: Lifecycle, Accessibility, Visual, and Performance Coverage

- Integration tests create two public editor views and verify independent resize state. They also cover processor reset, replacement imports, controller and processor instance isolation, import cancellation during teardown, editor release while import work is pending, decoded-audio publication, MIDI rendering, Clear, and restoration without hidden media access.
- The sample View menu uses the public action-menu contract to show the entire sample or frame the playback and loop ranges. Its controller test verifies each viewport result and rejects unknown items.
- Production visual references now cover compact, standard, expanded, ready and looping waveform states, overlapping selected handles, empty media, active importing, and recoverable import failure. Shared component references continue to cover disabled and alternate-theme contrast states used by the same public controls.
- A repeated-editor benchmark constructs and destroys 150 complete sample-player editors under one process-owned VSTGUI runtime. It exposed a test-harness lifecycle mismatch in which direct global initialization competed with each editor's runtime guard. The harness now uses one long-lived `RuntimeGuard`; repeated runs measured 8–57 ms per editor across build and machine states. The regression budget is 75 ms, which preserves useful headroom for that variance while still detecting substantial lifecycle regressions.
- `zig build test --summary all`: 66/66 build steps and 3,781/3,781 tests passed. This includes native adapter, macOS accessibility, interaction, malformed-input, restoration, lifecycle, visual-regression, and warm-render coverage.
- The sample pipeline benchmark measured 0.59 ms to decode 262,144 mono frames and build a 256-point preview, 88.2 ns per preview snapshot read, 0.01 ms for bounded controller publication, atomic adoption below the timer's nanosecond resolution, 6.5 ns per playback frame with eight voices available, and 4.6 ns per playhead publish/read update. Fixed storage is 2.01 MiB for the importer and 6.00 MiB for the processor player.
- Direct player tests now separately cover gain, hard pan, combined coarse and fine tuning, playback bounds, one-shot note release, attack, decay, sustain, release, missing media, and all-notes-off behavior in addition to interpolation, deterministic voice stealing, reverse looping, and replacement reset coverage.
- The final release-gate run measured 91.1 us for the complete scene, 263.6 us for signal views, 228.2 us for linked EQ, 141.9 us for Resonant Filter, 51.5 us for viewport rendering, 175.5 us for dual-range rendering, and 47.1 ms per complete Sample Player editor lifecycle. All remained inside their recorded budgets.
- `scripts/reaper_sample_player_smoke.lua` creates a new project tab, generates a bounded 0.5-second PCM WAV, inserts the Sample Player and a MIDI note, opens the editor, and saves a disposable project. The script passes numeric flags to `Main_SaveProjectEx` and requires no user-provided media.
- Run the script from REAPER's Actions window. It reports the generated WAV and project paths, then leaves the editor open so the generated file can be selected through the same picker used by production imports.

### Milestone 5: Pluginval Crash Diagnosis

- The first strictness-10 matrix stopped on the Sample Player during Editor Automation. The failing artifact directory is `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-143425-78826`.
- Pluginval independently automated the parameter-backed Start and End values into crossed extremes. `RangeSelectionModel::set` could then call `std::clamp` with its lower bound greater than its upper bound, which is undefined behavior. The model now clamps the automated handle to the full valid range and moves its companion only as far as needed to preserve the declared minimum span.
- Native regressions drive Start fully past End and End fully before Start. Both preserve a valid visible range without emitting host edits. The complete local suite passes 66/66 build steps and 3,767/3,767 tests after the fix.
- A later strictness-10 run exposed a second failure during `Background thread state`. The host invokes parameter setters from a worker thread, and the shared controller observer previously forwarded them directly into VSTGUI. The editor now coalesces updates through 64 fixed atomic slots and applies them from a 16 ms editor-thread timer. The notification path allocates no memory and takes no lock. Native tests verify deferred delivery and that a newer editor-thread state restore supersedes a stale queued value.
- The next preserved failure artifact is `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-160003-39694`. A debugger run in `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-160643-56403` identified the remaining fault exactly: pluginval called `IEditController::createView(nullptr)`, and the Zig boundary passed that null C string to `std.mem.span`. The VST3 declaration now models the name as nullable, the reflected controller rejects null before dispatch, and a direct ABI regression covers that probe.
- A separate launcher failure at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_gain-strictness-5-20260720-150156-36040` aborted in AppKit application registration before any plugin image loaded. `scripts/pluginval.sh` now uses a one-shot `gui/<uid>` LaunchAgent with captured output, bounded waiting, real exit-status propagation, and explicit cleanup. This distinguishes launcher failures from plugin faults without repeatedly opening a crashing process.
- The repaired Sample Player passed an isolated strictness-10 run at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-161026-70171`. The final serialized strictness-5 and strictness-10 matrices then passed all 14 bundles. Their Sample Player artifacts are `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-5-20260720-161316-86811` and `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-162304-57115`.
- The final raw ABI checks and all 14 Steinberg validators passed. The Sample Player validator reported 47 tests passed and 0 failed for both processing precisions. Full Linux aarch64 and Windows x86_64 example bundle matrices each passed 44/44 steps. Cross-compilation is build coverage, not native host validation.
- Direct parameter-backed ranges and `secondary_range_selection` remain experimental because only the gallery and Sample Player use them. Direct bipolar sliders are supported after the Channel Strip adopted the same public presentation for its signed Drive parameter. `AudioFileImporter`, decoded-audio transport, controller-sourced sample waveforms, and importer-aware action dependencies now have IR Loader and Sample Player production consumers. The gallery also exercises their decoded waveform, progress, retry, reset, and dependency behavior. They remain experimental until the pending Sample Player host walkthrough passes.
- The installed macOS bundle has SHA-256 `43bdfa1c5de798156abf0fb639764b36ecda2fb52f371c38af9940dd3cf67fd0`. Its deterministic REAPER script is installed at `~/Library/Application Support/REAPER/Scripts/zig-vst3-sample-player-smoke.lua`. The interactive walkthrough remains pending because it requires a person to register and run the ReaScript, import its generated file, listen to playback, and inspect the native editor. No host result is inferred from installation alone.

### Autonomous Stabilization Pass

- [x] Move the complete Sample Player editor declaration into `examples/sample_player_editor.zig`, which imports only the public `zig-vst3` package.
- [x] Add a test-time boundary check that rejects adapter-internal imports, native adapter symbols, and C imports in production GUI examples.
- [x] Add exact offline output assertions for sample-accurate MIDI note-on and note-off, forward playback, reverse playback, looping, deterministic voice stealing, and reduced voice limits.
- [x] Add Sample Player controller coverage for malformed WAV and AIFF input, bounded retry, reset, empty metadata, and empty waveform recovery.
- [x] Contain non-finite public playback, envelope, tuning, pan, gain, and range inputs before they reach voice or output state.
- [x] Make the component gallery decode real bounded audio and drive progress, waveform, action dependencies, failure, retry, and reset from one shared importer.
- [x] Add `zig build generate-sample-player-fixtures`, which writes small deterministic WAV and AIFF files under `zig-out/fixtures` without requiring user media.
- [x] Add deterministic pluginval runner tests and record timeout, signal, exit, bootstrap, and interruption classifications in each artifact directory.
- [x] Re-run the complete Zig, ABI, validator, cross-target, benchmark, and serialized pluginval matrices after this stabilization pass.

The final automated suite passed 71/71 build steps and 3,787/3,787 tests. Raw ABI passed 113/113 steps, all 14 Steinberg validators passed in 74/74 steps, and the Linux aarch64 and Windows x86_64 bundle matrices each passed 44/44 steps. Generated fixture outputs remain build artifacts and are not committed. `examples/sample_player_editor.zig` is the reference for ordinary public GUI composition, while `examples/sample_player_plugin.zig` owns host callbacks, persistence, decoded-audio publication, and processing integration.

The final benchmark measured 684.1 MiB/s for the bounded WAV worker, 7.11 ms for decoding 262,144 frames and constructing the waveform preview, 69.2 ns per preview read, 0.01 ms for bounded publication, 12.2 ns per playback frame with eight voices available, and 5.4 ns per playhead update. The isolated visual gate measured 116.5 us for the full scene, 295.7 us for signal views, 264.7 us for linked EQ, 162.5 us for Resonant Filter, 58.5 us for viewport rendering, 201.5 us for range selection, and 58.6 ms per Sample Player editor lifecycle. Every measurement remained within its recorded budget.

The final serialized pluginval rerun produced 28 successful `runner-status.txt` files: all 14 bundles at strictness 5 and all 14 at strictness 10 reported `classification=succeeded` and status 0. The final Sample Player artifacts are `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-5-20260720-181824-97320` and `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-183129-17131`.
