# Production Sample Player Plan

## Outcome

Build a MIDI-driven sample player whose editor uses only the public `@import("zig-vst3").vstgui` authoring API. The plugin will import bounded PCM WAV and AIFF files, publish decoded audio to the processor without audio-thread locks or allocation, and provide a production waveform editing and playback workflow.

This milestone is the second production consumer for decoded-audio transport, importer-aware action dependencies, and the direct bipolar slider. It also validates controller-sourced waveform snapshots in an instrument rather than an effect.

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

- [ ] Promote decoded-audio transport only if IR Loader and Sample Player pass the same bounded public contract.
- [ ] Promote importer-aware action dependencies only if both production consumers pass interaction, lifecycle, and host checks.
- [ ] Promote the direct bipolar slider only after the gallery and Sample Player pass the same declaration and interaction contract.
- [x] Keep single-consumer or incomplete surfaces experimental and name each blocker.
- [ ] Update the component reference, example lists, host matrix, and this plan with final evidence.

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
- A repeated-editor benchmark constructs and destroys 150 complete sample-player editors under one process-owned VSTGUI runtime. It exposed a test-harness lifecycle mismatch in which direct global initialization competed with each editor's runtime guard. The harness now uses one long-lived `RuntimeGuard`; the regression completes without a lifecycle fault and averages 42.1 ms per editor against a 50 ms budget.
- `zig build test --summary all`: 66/66 build steps and 3,767/3,767 tests passed. This includes native adapter, macOS accessibility, interaction, malformed-input, restoration, lifecycle, visual-regression, and warm-render coverage.
- The sample pipeline benchmark measured 0.59 ms to decode 262,144 mono frames and build a 256-point preview, 88.2 ns per preview snapshot read, 0.01 ms for bounded controller publication, atomic adoption below the timer's nanosecond resolution, 6.5 ns per playback frame with eight voices available, and 4.6 ns per playhead publish/read update. Fixed storage is 2.01 MiB for the importer and 6.00 MiB for the processor player.
- Final warm rendering measured 83.2 us for the complete scene, 46.6 us for viewport rendering, and 160.0 us for dual-range rendering. All remained inside their recorded budgets.
- `scripts/reaper_sample_player_smoke.lua` creates a new project tab, generates a bounded 0.5-second PCM WAV, inserts the Sample Player and a MIDI note, opens the editor, and saves a disposable project. The script passes numeric flags to `Main_SaveProjectEx` and requires no user-provided media.
- Run the script from REAPER's Actions window. It reports the generated WAV and project paths, then leaves the editor open so the generated file can be selected through the same picker used by production imports.

### Milestone 5: Pluginval Crash Diagnosis

- The first strictness-10 matrix stopped on the Sample Player during Editor Automation. The failing artifact directory is `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-143425-78826`.
- Pluginval independently automated the parameter-backed Start and End values into crossed extremes. `RangeSelectionModel::set` could then call `std::clamp` with its lower bound greater than its upper bound, which is undefined behavior. The model now clamps the automated handle to the full valid range and moves its companion only as far as needed to preserve the declared minimum span.
- Native regressions drive Start fully past End and End fully before Start. Both preserve a valid visible range without emitting host edits. The complete local suite passes 66/66 build steps and 3,767/3,767 tests after the fix.
- The repaired strictness-10 serialized matrix passed all 14 bundles in 60/60 steps. The Sample Player artifact is `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-10-20260720-144223-92940`.
- The post-fix strictness-5 serialized matrix also passed all 14 bundles in 60/60 steps. The Sample Player artifact is `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_sample_player-strictness-5-20260720-144457-97366`.
- The post-fix full raw ABI and 14-example Steinberg validator matrix passed. Full Linux aarch64 and Windows x86_64 example bundle matrices also passed. Cross-compilation is build coverage, not native host validation.
- Direct parameter-backed ranges and `secondary_range_selection` remain experimental because only the gallery and Sample Player use them. Direct bipolar sliders remain experimental for the same reason. `AudioFileImporter`, decoded-audio transport, controller-sourced sample waveforms, and importer-aware action dependencies now have IR Loader and Sample Player production consumers, but the gallery does not exercise their full decoded or dependency behavior and the Sample Player host walkthrough is pending. They therefore remain experimental.
