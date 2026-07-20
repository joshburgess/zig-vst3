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

- [ ] Declare the complete editor through `vst3.vstgui.createEditor` without adapter-internal imports.
- [ ] Add File, Waveform, Playback, and Envelope groups with one clear primary import action.
- [ ] Add drag-and-drop and picker entry, progress, cancel, retry, clear confirmation, and concise recovery text.
- [ ] Add a controller waveform, horizontal viewport, start and end selection, loop range, live playhead, scales, and explicit empty and loading states.
- [ ] Add direct bipolar pan, gain, coarse and fine tuning, playback and loop modes, reverse, ADSR, piano audition, and exact entry.

Exit criteria:

- Pointer, keyboard, picker, drop, piano, automation, exact-entry, and accessibility paths update one accepted state.
- Hover, pressed, selected, focused, disabled, loading, ready, and error states remain visibly distinct.
- Clear is separated from Import and Audition and requires confirmation.
- Overlapping waveform markers remain selectable and expose exact accessible values.

## Milestone 3: Responsive Layout and State

- [ ] Define deterministic compact, standard, and expanded layouts with reversible manual resize behavior.
- [ ] Prevent clipped labels, cramped controls, ambiguous selection, excess blank space, poor contrast, and unreachable actions.
- [ ] Persist parameters, layout mode, viewport, start, end, loop range, loop mode, and safe import metadata.
- [ ] Restore missing media as empty without file access and document portability limits.
- [ ] Verify repeated editor open and close, processor restart, replacement import, cancellation during teardown, and two-instance isolation.

Exit criteria:

- Compact and expanded round trips preserve state and access to essential actions.
- Reopening never shows a stale waveform or claims unavailable media is loaded.
- Multiple instances can import, play, edit, resize, close, and reopen independently.

## Milestone 4: Accessibility, Visual, and Performance Coverage

- [ ] Add toolkit-neutral names, roles, values, ranges, grouping, focus order, progress announcements, errors, waveform semantics, and piano state.
- [ ] Add unit, interaction, lifecycle, accessibility, malformed-input, restoration, visual-regression, and performance coverage.
- [ ] Add compact, standard, expanded, empty, importing, ready, looping, selected-handle, disabled, error, and high-contrast references.
- [ ] Measure decoding, waveform construction, transfer, atomic adoption, voice processing, playhead updates, graph rendering, and repeated editor lifecycle.
- [ ] Add a deterministic REAPER smoke project or script with generated audio and MIDI.

Exit criteria:

- Native adapter and macOS accessibility suites pass without lifecycle faults.
- Warm rendering and processing remain within recorded budgets at maximum supported capacity and polyphony.
- Manual validation requires no user-supplied audio.

## Milestone 5: API Decisions and Release Gates

- [ ] Promote decoded-audio transport only if IR Loader and Sample Player pass the same bounded public contract.
- [ ] Promote importer-aware action dependencies only if both production consumers pass interaction, lifecycle, and host checks.
- [ ] Promote the direct bipolar slider only after the gallery and Sample Player pass the same declaration and interaction contract.
- [ ] Keep single-consumer or incomplete surfaces experimental and name each blocker.
- [ ] Update the component reference, example lists, host matrix, and this plan with final evidence.

Release gates:

- [ ] `zig build test raw-api-abi validate-examples --summary all`
- [ ] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [ ] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [ ] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [ ] Serialized pluginval strictness 5 and 10 with stop-on-first-exit diagnosis
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
