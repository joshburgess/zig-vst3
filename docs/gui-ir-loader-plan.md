# Production IR Loader Plan

Build a convolution reference plugin that imports PCM WAV impulse responses through the public `@import("zig-vst3").vstgui` authoring API. The same work establishes reusable importer composition, waveform editing, action controls, progress presentation, zoomable viewports, and a bounded controller-to-processor data path.

## Invariants

- File I/O, decoding, resampling, and convolution preparation stay outside the audio callback.
- Processing performs no allocation, lock acquisition, operating-system call, or unbounded work.
- Controller-to-processor messages have fixed payload and count limits.
- Rapid replacement never overwrites data used by the audio thread.
- Editor close does not cancel controller-owned work. Controller teardown cancels and joins it.
- Every interactive control has pointer, keyboard, focus, disabled, error, and accessibility behavior.
- Each screen state has one dominant action. Empty state chooses an IR, ready state edits or auditions it, and recoverable failure retries.
- Toolkit-specific types remain behind the adapter boundary.

## Milestone 1: Bounded IR Data and Convolution

- [x] Add a decoded-audio store with explicit channel, sample-rate, frame, and memory limits.
- [x] Add fixed-size controller-to-processor begin, chunk, commit, clear, and rejection messages.
- [x] Add a triple-buffer publication contract with free, writing, ready, and reading ownership.
- [x] Resample and prepare partitioned convolution outside the audio callback.
- [x] Adopt prepared generations atomically at process-block boundaries.
- [x] Add wet/dry, output, bypass, and audition-safe parameter smoothing.
- [x] Cover rapid replacement, stale generation rejection, malformed chunks, cancellation, teardown, sample-rate changes, reset, and instance isolation.

Exit criteria:

- The audio callback only reads the active immutable slot.
- Publishing a newer generation cannot mutate the active or pending generation.
- Processing cost is bounded by declared IR and partition capacities.
- The processor produces deterministic mono and stereo convolution results.

Completion evidence:

- `DecodedAudioFileImporter(131_072)` stores at most two interleaved channels and rejects decoded input above its declared frame capacity.
- `gui_ir_transport` uses 1,024-sample little-endian chunks with explicit begin, commit, cancel, and clear operations. The public controller wrapper hides VST message details from editor composition code.
- `PartitionedConvolver(131_072, 512)` owns three immutable IR slots. Only the producer prepares spectra, and only the audio callback changes the active slot at a process boundary.
- Unit tests cover mono and stereo convolution, pending replacement, stale generations, malformed chunks, sample-rate republication, decoded storage, controller-to-component transport, component teardown, and independent framework instances.
- The reference processor reports a fixed 512-sample VST latency through its raw `IAudioProcessor` interface and delays the dry path by the same amount. pluginval 1.0.3 prints latency as zero through its hosting wrapper despite the raw interface test, so this discrepancy remains tracked for manual host verification.

## Milestone 2: Reusable Importer Composition

- [x] Extract a public `FileImporter` composition declaration from the channel-strip importer.
- [x] Keep picker, drop, progress, cancellation, retry, reset, and graph preview on one shared contract.
- [x] Migrate the channel strip and component gallery to the reusable declaration.
- [x] Use the same declaration in the IR plugin without adapter-internal imports or edits.
- [x] Cover declaration validation, instance ownership, callback rejection, editor reopen, resize, and state restoration.

Exit criteria:

- Authors declare an importer as one composition component rather than coordinating separate adapter hooks.
- The gallery, channel strip, and IR plugin share the same public declaration.
- Unsupported formats and capacity failures remain recoverable.

Completion evidence:

- `FileImporter` is exported from the public `vstgui` module. Its validation rejects missing identifiers or labels, malformed or duplicate extensions, excessive extension counts, and invalid file-count limits before native editor creation.
- The component gallery, channel strip, and IR loader declare `EditorDescription.file_importers`. Ordinary composition needs no adapter-internal imports or edits.
- Picker and drop entry paths lower to the same bounded callback, status, progress, cancel, retry, and reset contract. Existing native interaction, accessibility, resize, rejection, teardown, and repeated-editor tests exercise that shared implementation.
- `FileDrop` and `EditorDescription.file_drops` remain compatibility aliases. A description that sets both the current and compatibility fields is rejected instead of silently choosing one.
- Host state restores parameters and editor state only. Imported paths and media are intentionally excluded, preventing hidden file I/O and stale absolute-path restoration.
- Post-change validation passed 3,624 of 3,624 Zig tests, 152 of 152 raw ABI and Steinberg validation steps, 35 of 35 Linux cross-build steps, and 35 of 35 Windows cross-build steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven plugin bundles.

## Milestone 3: General UI Primitives

- [x] Add action buttons with primary, secondary, and destructive roles.
- [x] Add icon buttons with required accessible labels and optional visible text.
- [ ] Add editable labels with commit, cancel, validation, and external-update behavior.
- [ ] Add determinate and indeterminate progress indicators with textual semantics.
- [ ] Add bounded scrollable and zoomable viewports.
- [x] Add toolbar and grouped-action layout declarations.
- [x] Add confirmation and recoverable-error presentation without modal dependence where an inline choice is sufficient.

Exit criteria:

- [x] Focus order follows visible reading order for the completed action-control slice.
- [x] Enter and Space activate buttons. Escape cancels confirmation and recoverable failure feedback.
- [x] Icon-only actions remain understandable to assistive technology.
- [x] Destructive actions are separated from the dominant constructive action.
- [x] Static action controls do not repaint continuously.

Action-control completion evidence:

- The public `ActionButton` declaration is shared unchanged by the component gallery and IR loader. It covers stable action identifiers, primary, secondary, and destructive roles, icon-only presentation, accessible labels, tooltips, confirmation text, and recoverable failure text.
- The native adapter copies all declaration strings per editor instance, validates unsafe or ambiguous declarations before construction, and exposes button names, descriptions, values, focus, and press actions through the toolkit-neutral accessibility contract.
- Direct interaction tests cover pointer activation, Enter, Space, Escape, destructive confirmation, accepted and rejected callbacks, retry, disabled controls, declaration copying, semantic icon labels, and native validation failures.
- The footer toolbar groups related actions with bounded spacing and separates action buttons from action menus. Focus and accessibility traversal now follow the visible top-to-bottom editor order, including file importers.
- Deterministic visual coverage records primary, destructive confirmation, and recoverable failure states in `action-buttons.png`. The strictness 10 run measured a 40.2 us warm action-button render average against the 300 us budget.
- `zig build test --summary all` passed 54 of 54 steps and 3,631 of 3,631 tests. Raw ABI checks passed 107 of 107 steps, example validation passed 59 of 59 steps, and all eleven bundles passed their 47 Steinberg validator tests.
- Linux and Windows cross-target bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven plugin bundles.
- Editable labels, progress indicators, and bounded viewports remain open. Milestone 3 is not complete until those independent primitives meet the same exit criteria.

## Milestone 4: IR Waveform Editor

- [ ] Add zoom and horizontal navigation with pointer, keyboard, and accessibility actions.
- [ ] Add a bounded selection with visible start and end handles.
- [ ] Add trim, normalize, reverse, fade-in, fade-out, reset, and clear commands.
- [ ] Keep edits non-destructive until committed to a new immutable generation.
- [ ] Show original and edited duration, peak, channels, sample rate, and pending state.
- [ ] Add deterministic empty, importing, ready, editing, confirming, success, and recoverable-error visuals.

Exit criteria:

- Every edit is reversible through Reset until a different file replaces the source.
- Keyboard users can select and edit the same range as pointer users.
- Clear requires an explicit confirmation and restores focus to Choose IR.
- Waveform rendering and hit testing remain bounded under maximum zoom.

## Milestone 5: Production IR Plugin and API Decisions

- [x] Add the IR plugin to native, Linux, and Windows example matrices.
- [ ] Exercise assets, fonts, custom drawing, controller graph sources, and audio importing in the gallery and IR plugin.
- [ ] Promote shared contracts only after the gallery and two production consumers use the same public shape.
- [ ] Keep single-consumer convolution and waveform-editing details experimental.
- [ ] Document authoring, real-time ownership, memory limits, latency, and state restoration.

Exit criteria:

- The plugin remains useful with the editor closed.
- Host state restores parameters without hidden file I/O or stale absolute paths.
- Missing imported media restores as an explicit empty state.
- Asset, font, drawing, importer, and graph status decisions cite their consumers and remaining blockers.

## Milestone 6: Validation and Evidence

- [ ] Add deterministic unit, interaction, accessibility, lifecycle, malformed-input, visual-regression, and performance coverage.
- [x] Run Zig tests, raw ABI checks, native adapter tests, macOS accessibility tests, visual tests, and all Steinberg validators.
- [x] Cross-build every example bundle for Linux and Windows.
- [x] Run pluginval serially at strictness 5 and strictness 10, stopping at the first unexpected exit.
- [ ] Record convolution CPU, handoff latency, warm rendering, import throughput, and fixed memory ceilings.
- [ ] Commit each coherent completed milestone.

External checks remain pending when their environments are unavailable:

- VoiceOver workflow in a macOS host.
- Narrator and native Windows host interaction.
- X11 and Wayland host interaction.
- AT-SPI names, states, focus, actions, and progress announcements.

Validation evidence for the bounded convolution milestone:

- `zig build test --summary all`: 54 of 54 steps and 3,617 of 3,617 tests passed, including the raw VST latency assertion.
- `zig build raw-api-abi validate-examples --summary all`: 152 of 152 steps passed. All eleven example bundles passed 47 Steinberg validator tests each.
- `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`: 35 of 35 steps passed.
- `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`: 35 of 35 steps passed.
- Serialized pluginval strictness 5 and strictness 10 matrices each completed 48 of 48 steps. All eleven plugins passed, including the IR loader's editor, processing, automation, state restoration, background-thread state, parameter thread safety, and parameter fuzzing checks.

API status after this milestone:

- `FileImporter` is supported. The gallery, channel strip, and IR loader use the same public declaration and lifecycle contract. `FileDrop` remains a compatibility alias for existing source.
- `DecodedAudioFileImporter`, decoded-audio controller transport, processor lifecycle hooks, and partitioned convolution remain experimental. The decoded importer and transport have only one production consumer.
- Existing graph, parameter attachment, and composition declarations keep their current status. This milestone does not promote them.
