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
- A focused importer regression replaces completed media, verifies decoded storage clears before the worker starts, and proves the newer generation publishes without exposing samples from the previous file. The focused importer suite passes 13 of 13 tests.
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
- [x] Add editable labels with commit, cancel, validation, and external-update behavior.
- [x] Add determinate and indeterminate progress indicators with textual semantics.
- [x] Add bounded scrollable and zoomable viewports.
- [x] Add toolbar and grouped-action layout declarations.
- [x] Add confirmation and recoverable-error presentation without modal dependence where an inline choice is sufficient.

Exit criteria:

- [x] Focus order follows visible reading order for the completed action-control slice.
- [x] Enter and Space activate buttons. Escape cancels confirmation and recoverable failure feedback.
- [x] Icon-only actions remain understandable to assistive technology.
- [x] Destructive actions are separated from the dominant constructive action.
- [x] Static action controls do not repaint continuously.

Action-control completion evidence:

- The public `ActionButton` declaration is shared unchanged by the component gallery and IR loader. It covers stable action identifiers, primary, secondary, and destructive roles, icon-only presentation, accessible labels, tooltips, confirmation text, recoverable failure text, and an optional post-success importer focus target.
- The native adapter copies all declaration strings per editor instance, validates unsafe or ambiguous declarations before construction, and exposes button names, descriptions, values, focus, and press actions through the toolkit-neutral accessibility contract.
- Direct interaction tests cover pointer activation, Enter, Space, Escape, destructive confirmation, accepted and rejected callbacks, retry, disabled controls, declaration copying, semantic icon labels, and native validation failures.
- The footer toolbar groups related actions with bounded spacing and separates action buttons from action menus. Focus and accessibility traversal now follow the visible top-to-bottom editor order, including file importers.
- Deterministic visual coverage records primary, destructive confirmation, and recoverable failure states in `action-buttons.png`. The strictness 10 run measured a 40.2 us warm action-button render average against the 300 us budget.
- `zig build test --summary all` passed 54 of 54 steps and 3,631 of 3,631 tests. Raw ABI checks passed 107 of 107 steps, example validation passed 59 of 59 steps, and all eleven bundles passed their 47 Steinberg validator tests.
- Linux and Windows cross-target bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven plugin bundles.

Editable-label and progress completion evidence:

- `EditableLabel` binds a bounded text field to typed editor state. A controller may reject a commit through `validateEditorText`; rejection keeps the last accepted value, presents inline text, and updates the semantic description. Escape restores the accepted value. External state is refreshed when the editor regains focus or its controller values refresh.
- `ProgressIndicator` reads a validated `ProgressSnapshot` at a declared rate from 1 to 60 Hz. Determinate states expose a bounded value and percentage. Indeterminate, idle, complete, and failed states use explicit text, so meaning does not depend on color or motion.
- The gallery and IR loader use the same declarations and callbacks through the public `vstgui` API. The IR loader maps its bounded importer status and generation directly into the generic progress contract.
- Native interaction tests cover accepted and rejected edits, external text refresh, determinate and indeterminate progress, completion, invalid declarations, and component construction. The macOS bridge test verifies native text-field and progress-indicator roles, value editing, and the determinate range.
- `editable-labels-progress.png` records accepted text, inline validation feedback, and idle, determinate, indeterminate, and failed progress states. The strictness 10 gate measured the progress view at 13.5 us against the 300 us budget.
- Post-change validation passed 54 of 54 Zig build steps and 3,646 of 3,646 tests. Raw ABI and Steinberg validation passed 152 of 152 steps. Linux and Windows cross-target bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven bundles.

Viewport completion evidence:

- `Viewport` is an optional public graph composition with horizontal, vertical, or two-axis navigation, a 1x–128x validated zoom range, anchor-preserving zoom, bounded offsets, configurable steps, and optional typed editor-state fields.
- The gallery waveform and IR waveform use the same public declaration. Zoom and offset values restore through one atomic bounded scalar callback, and a rejected callback restores the previous native transform.
- Pointer wheels and trackpads pan. Command-wheel, Control-wheel, and native zoom gestures zoom around the pointer. Plus and minus zoom, arrows pan, Shift accelerates panning, Page Up and Page Down move one visible page, Home and End reach a boundary, and 0 restores the declared view. Editable graphs retain plain-arrow editing and use Command or Control with arrows for viewport navigation.
- A text zoom value and proportional navigator remain visible over the graph. Toolkit-neutral accessibility exposes focus, zoom range, position text, increment, decrement, set-value, and reset actions. The macOS bridge test verifies the native range and increment behavior.
- Native tests cover horizontal bounds, anchor preservation, keyboard, wheel, pinch, accessibility, atomic persistence, callback rejection, invalid declarations, and public editor construction. `graph-viewports.png` records full and zoomed waveform states. The isolated viewport warm-render average is 55.4 us against the 300 us budget.
- Post-change validation passed 54 of 54 Zig build steps and 3,656 of 3,656 tests. Raw ABI and Steinberg validation passed 152 of 152 steps. Linux and Windows cross-target bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven bundles.

Milestone 3 is complete. The next implementation slice uses the viewport in the IR selection and non-destructive edit workflow.

## Milestone 4: IR Waveform Editor

- [x] Add zoom and horizontal navigation with pointer, keyboard, and accessibility actions.
- [x] Add a bounded selection with visible start and end handles.
- [x] Add trim, normalize, reverse, fade-in, fade-out, reset, and clear commands.
- [x] Keep edits non-destructive until committed to a new immutable generation.
- [x] Show original and edited duration, peak, channels, sample rate, and publication state.
- [x] Add deterministic empty, importing, ready, editing, confirming, success, and recoverable-error visuals.

Exit criteria:

- Every edit is reversible through Reset until a different file replaces the source.
- Keyboard users can select and edit the same range as pointer users.
- Clear requires an explicit confirmation and restores focus to Choose IR.
- Waveform rendering and hit testing remain bounded under maximum zoom.

Range-selection completion evidence:

- `RangeSelection` is a graph-generic public composition with ordered start and end handles, x-axis bounds, a minimum span, a keyboard step, and optional paired editor-state fields.
- The component gallery and IR waveform use the same public declaration. Both values persist through one bounded scalar callback, and callback rejection restores the previous range.
- Pointer users can drag either handle or create a replacement range. Keyboard users choose handles with Left and Right Bracket, adjust with arrows, move farther with Shift, reach boundaries with Home and End, and switch handles with Return. Command or Control with arrows preserves viewport panning.
- The selected interval combines shading, boundary lines, and distinct handle shapes. Toolkit-neutral accessibility exposes the interval, active handle, x-axis range, exact value, increment, decrement, and handle selection. The macOS bridge test verifies native range adjustment and value reporting.
- Native tests cover bounds, minimum spans, handle crossing, pointer replacement, keyboard adjustment, viewport coexistence, atomic persistence, callback rejection, accessibility actions, invalid declarations, and public editor construction. `graph-viewports.png` records full and zoomed selection states. The isolated warm-render average is 105.7 us against the 300 us budget.
- Post-change validation passed 54 of 54 Zig build steps and 3,666 of 3,666 tests. Raw ABI and Steinberg validation passed 152 of 152 steps. Linux and Windows cross-target bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed 48 of 48 steps across all eleven bundles.

Immutable-edit completion evidence:

- `gui_ir_editor.Editor` owns fixed-capacity original, edited, and rollback buffers. Trim, normalize, reverse, fade-in, fade-out, and reset operate only on controller-owned memory. A rejected controller-to-processor publication restores the exact previous samples, metadata, dirty state, and generation before the action reports failure.
- The original buffer remains unchanged until another file replaces it. Reset republishes that source as a new immutable processor generation. Clear uses the existing confirmation action and publishes an empty generation before releasing controller state.
- Clear rejects before sending any processor message while importer work is active. This prevents a failed controller reset from silently clearing the processor. An integration test fixes the ordering contract.
- Clear names Choose IR as its post-success focus target. The Zig authoring layer and native adapter reject unknown importer IDs. Native interaction coverage confirms the destructive action, dispatches the accepted command, and verifies that toolkit-neutral focus returns to the importer.
- Every IR edit action depends on the importer Ready state. Empty, validating, importing, cancelled, and failed states remove those buttons from focus traversal and leave the importer action as the recovery path. Trim is the sole primary edit after a successful import. Native tests cover initial disabled and enabled states, focus-driven refresh, rejected activation while disabled, and invalid importer targets.
- The IR editor declares all edit actions, graph selection, live metadata, and importer behavior through the public `@import("zig-vst3").vstgui` authoring surface. Ordinary composition imports no adapter implementation files.
- The shared `EditableLabel` contract now supports read-only live values at a bounded 1–60 Hz rate. The component gallery and IR loader both use it. Read-only values are excluded from keyboard focus, reject native set-value attempts, stop polling on close, and render as plain data rather than editable inputs.
- The IR loader reports sample rate, channel count, original duration, edited duration, original and edited peaks, and publication state. Unit coverage verifies composed edits, reset, silent-selection rejection, rollback, controller publication, processor adoption, metadata, and clear.
- `editable-labels-progress.png` records editable, rejected, and read-only value states. Native interaction and macOS bridge tests cover read-only refresh, semantics, focus exclusion, setter rejection, callback requirements, and invalid refresh rates.
- The automated local gate passed Zig tests, raw ABI checks, native adapter tests, macOS accessibility tests, visual regression, warm-render budgets, and every Steinberg validator. Linux and Windows example bundle matrices each passed 35 of 35 steps. Serialized pluginval strictness 5 and strictness 10 matrices each passed all eleven plugin bundles. These pluginval results prove lifecycle and protocol coverage, not visual correctness. After the responsive resize regressions were added, the full local gate passed 203 of 203 steps and 3,678 of 3,678 tests.
- The latest uncontended full-scene warm render averaged 93.2 microseconds. Signal views averaged 267.7 microseconds, viewport rendering 51.9 microseconds, and range-selection rendering 105.7 microseconds. Each remained below its 300 microsecond budget.
- The IR edit model reserves exactly 3 MiB for its three stereo sample buffers at the 131,072-frame limit. This storage is controller-owned and never accessed by the audio callback.
- A REAPER 7.36 check on macOS exposed missing editor text that pluginval and the headless visual harness had not detected. The adapter now initializes VSTGUI before resolving theme fonts, resolves global font handles only while the runtime is live, and keeps runtime teardown after all theme-owned state. A repeated editor-construction regression covers the host lifecycle that the headless harness previously masked.
- The same REAPER check exposed overlap in the dense component gallery at its accepted 720 by 600 size. Dense editors now use bounded vertical scrolling, while simple editors retain an unscrolled surface. The rebuilt gallery passed top, middle, and bottom inspection in REAPER 7.36.
- REAPER also exposed clipped graph titles and a persistent blank region after compact and manual resize cycles in the channel strip. Group graphs now wrap into bounded responsive rows when their minimum readable width would be violated. Resize layout resets the native scroll container, clamps the retained vertical position to the new content extent, and restores it only after content geometry is synchronized. Native regressions cover narrow and wide graph column counts plus scroll, expand, compact, and manual resize geometry. The rebuilt channel strip passed compact graph labels, manual shrinking, top restoration, toggle reachability, and expansion in REAPER 7.36. The IR loader's complete host workflow still requires confirmation before this milestone is closed.
- The first IR loader host inspection exposed a framework-wide spacing defect. Metadata text began at its border, and seven edit actions were compressed into one unreadable row. Parameter, editable-value, progress, preset, and menu text now use themed inner insets. Footer actions retain the themed minimum button width and wrap into additional rows when needed. Native geometry tests cover every text inset, a seven-action compact footer, button widths, and row creation. The complete automated gate then passed 203 of 203 steps and 3,678 of 3,678 tests. A host audit of every GUI example remains required because the defect affected shared rendering and layout code.
- `ir-workflow-states.png` records Empty, Importing, Ready, Editing, Confirming, Success, and Recoverable Error as one production sequence. Each state names its dominant action or recovery path, and the destructive confirmation remains visually separate from the constructive import and edit path.

## Milestone 5: Production IR Plugin and API Decisions

- [x] Add the IR plugin to native, Linux, and Windows example matrices.
- [x] Exercise assets, fonts, custom drawing, controller graph sources, and audio importing in the gallery and IR plugin.
- [ ] Promote shared contracts only after the gallery and two production consumers use the same public shape.
- [x] Keep single-consumer convolution and waveform-editing details experimental.
- [x] Document authoring, real-time ownership, memory limits, latency, and state restoration.

Exit criteria:

- The plugin remains useful with the editor closed.
- Host state restores parameters without hidden file I/O or stale absolute paths.
- Missing imported media restores as an explicit empty state.
- Asset, font, drawing, importer, and graph status decisions cite their consumers and remaining blockers.

Completion evidence in progress:

- The gallery and IR loader both declare embedded SVG assets, preferred and fallback font families, and parameter drawing callbacks through the public `Skin` contract. The IR callback adds a bounded impulse mark to Bypass without replacing its text state or parameter attachment.
- The IR loader also uses a controller-backed waveform graph and `FileImporter` with decoded-audio handoff in the same public editor declaration. Its focused integration suite passes 4 of 4 tests, including native editor construction with the asset, font, and drawing declarations.
- Asset, font, and custom-drawing promotion remains pending until the rebuilt IR editor passes real-host visual inspection. The callback and asset do not affect the audio thread.
- The framework guide now documents the public authoring path, controller and processor ownership, fixed message payload, per-instance memory ceilings, audio-thread constraints, and explicit empty-media restoration behavior. Decoded transport, editing buffers, and convolution remain experimental because they still have one production consumer.

## Milestone 6: Validation and Evidence

- [x] Add deterministic unit, interaction, accessibility, lifecycle, malformed-input, visual-regression, and performance coverage.
- [x] Run Zig tests, raw ABI checks, native adapter tests, macOS accessibility tests, visual tests, and all Steinberg validators.
- [x] Cross-build every example bundle for Linux and Windows.
- [x] Run pluginval serially at strictness 5 and strictness 10, stopping at the first unexpected exit.
- [x] Record convolution CPU, handoff latency, warm rendering, import throughput, and fixed memory ceilings.
- [ ] Commit each coherent completed milestone.

External checks remain pending when their environments are unavailable:

- VoiceOver workflow in a macOS host.
- Narrator and native Windows host interaction.
- X11 and Wayland host interaction.
- AT-SPI names, states, focus, actions, and progress announcements.

Validation evidence for the bounded convolution milestone:

- `zig build benchmark` measures the production 131,072-frame, 512-sample-partition convolver at 19.02 MiB of fixed processor storage, plus 1.00 MiB for controller decoding and 3.00 MiB for original, edited, and rollback buffers. A local release run measured 1.27 ms for maximum-length preparation and publication, 24 us for pending adoption, 630.9 ns per stereo sample, and 3.0 percent of one 48 kHz core. The bounded 8 MiB PCM WAV fixture decoded at 796.9 MiB/s. These are local regression measurements, not universal hardware guarantees.
- The latest isolated native visual run measured 97.5 us for the full reference scene, 275.3 us for maximum-capacity signal views, 55.8 us for the viewport, and 110.8 us for range selection. Each remained below its 300 us warm-render budget. Aggregate reruns while REAPER remains open are treated as invalid when another renderer pushes a component over budget.
- `zig build test --summary all`: 54 of 54 steps and 3,617 of 3,617 tests passed, including the raw VST latency assertion.
- `zig build raw-api-abi validate-examples --summary all`: 152 of 152 steps passed. All eleven example bundles passed 47 Steinberg validator tests each.
- `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`: 35 of 35 steps passed.
- `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`: 35 of 35 steps passed.
- Serialized pluginval strictness 5 and strictness 10 matrices each completed 48 of 48 steps. All eleven plugins passed lifecycle, processing, automation, state restoration, background-thread state, parameter thread safety, and parameter fuzzing checks. Real-host inspection remains the authority for rendered text, layout, clipping, scrolling, and interaction appearance.

API status after this milestone:

- `FileImporter` is supported. The gallery, channel strip, and IR loader use the same public declaration and lifecycle contract. `FileDrop` remains a compatibility alias for existing source.
- `EditableLabel`, `ProgressIndicator`, and `ProgressSnapshot` are supported. The gallery and IR loader share their public declarations, bounded callbacks, native semantics, and lifecycle behavior.
- `Viewport`, `ViewportAxes`, and persistent graph transforms are supported. The gallery and IR loader share the declaration, interaction, rendering, state, and accessibility contracts.
- `RangeSelection`, `RangeSelectionHandle`, and persistent graph ranges are supported. The gallery and IR loader share the declaration, interaction, rendering, state, and accessibility contracts.
- `DecodedAudioFileImporter`, decoded-audio controller transport, processor lifecycle hooks, and partitioned convolution remain experimental. The decoded importer and transport have only one production consumer.
- Post-success importer focus and importer-readiness action dependencies remain experimental fields on the supported `ActionButton` contract. The IR loader is their only production consumer.
- Existing graph, parameter attachment, and composition declarations keep their current status. This milestone does not promote them.
