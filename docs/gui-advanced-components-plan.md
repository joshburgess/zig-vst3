# Advanced GUI Components Plan

This phase extends the production GUI foundation with native assistive actions, multi-parameter interaction, editable graphs, persistent editor state, and higher-level components. Work stays behind the public `@import("zig-vst3").vstgui` authoring API. Adapter internals may implement toolkit behavior, but plugin authors must not depend on them.

## Invariants

- Parameter edits use host begin, perform, and end gestures. Rejected edits restore the accepted value.
- Audio processing does not allocate, lock, draw, format text, call the operating system, or request repaint.
- Editors, attachments, telemetry, and persistent state remain isolated per plugin instance.
- Keyboard, pointer, and assistive actions share component behavior instead of maintaining parallel edit paths.
- Dynamic rendering is bounded, activity-driven, and stopped when the editor closes.
- Native platform support is documented from executed evidence. Cross-compilation does not count as host verification.

## Milestone 8: Accessible Actions and Native Control Patterns

- [x] Add toolkit-neutral focus, press, increment, decrement, and set-value actions.
- [x] Connect parameter controls, exact-value fields, resettable meters, and editor resizing to those actions.
- [x] Route parameter actions through normal host gestures and rejection rollback.
- [x] Implement AppKit focus, press, increment, decrement, and value setters.
- [x] Implement Windows UIA RangeValue, Toggle, Invoke, and Value providers.
- [x] Add deterministic semantic, interaction, and AppKit integration tests.
- [ ] Verify actions manually with VoiceOver.
- [ ] Verify UIA patterns manually with Narrator.

Exit criteria:

- Assistive actions and keyboard or pointer actions produce the same component state and host callback ordering.
- Disabled and read-only nodes reject mutation.
- macOS tests execute native actions against a real editor view.
- The Windows provider cross-compiles with all four control patterns.

Completion evidence:

- `AccessibilityNode` owns action capabilities and a synchronous action callback independent of VSTGUI and native platform types.
- Native and generic tests cover focus, value changes, toggling, unsupported actions, disabled and read-only rejection, callback counts, and bridge teardown.
- Local Zig tests, raw ABI checks, native adapter tests, AppKit integration tests, visual regression, and all Steinberg example validators pass. The warm-render average remained below 45 microseconds against the 300 microsecond budget.
- Linux and Windows example bundles cross-build for `x86_64-linux-gnu` and `x86_64-windows-gnu`. The Windows UIA provider also cross-compiles directly with all four pattern interfaces.
- Pluginval was not run for this milestone. Historical concurrent startup crashes occurred before plugin loading, but they do not explain recent isolated exits. Treat an isolated exit as a plugin regression until diagnosis proves otherwise. Native action behavior is outside pluginval's coverage.
- VoiceOver and Narrator navigation remain external checks because no automated screen-reader driver is available locally.

## Milestone 9: Multi-Parameter Gestures and XY Pad

- [x] Define a public multi-parameter attachment that owns an ordered set of parameter IDs.
- [x] Begin each parameter once, publish accepted values in stable order, and end every begun parameter once.
- [x] Roll back the complete visible gesture when a host rejects any value.
- [x] Cancel active gestures during editor close without leaving host edits open.
- [x] Build a reusable XY pad with pointer, keyboard, and accessible axis actions.
- [x] Add the XY pad to the component gallery and channel strip through the public API.
- [x] Test automation, cancellation, rejection, focus order, resize, and instance isolation.

Exit criteria:

- One interaction can edit two parameters without adapter-specific composition code.
- Host callback order is deterministic for success, partial rejection, cancellation, and teardown.
- Each axis has an accessible name, value, range, and independent adjustment path.

Completion evidence:

- `MultiParameterAttachment(count)` rejects duplicate IDs and provides ordered begin, set, finish, cancel, host-update, and value operations without depending on a rendering toolkit.
- Adapter ABI version 9 adds up to eight XY pads. The public `XYPad` declaration references two ordinary editor parameters, while the adapter owns pointer, keyboard, theme, layout, host-update, and accessibility behavior.
- The component gallery links Bipolar and Voices. The channel strip links Gain and Drive and processes Drive as an independent reflected parameter. Neither editor imports adapter internals.
- Zig and native interaction tests cover success order, partial rejection rollback, cancellation, host automation, keyboard input, per-axis accessible edits, invalid descriptions, resize, scale, focus order, and instance isolation.
- The `xy-pad.png` visual reference covers the grid, themed surface, and position handle. The final warm-render average was 32.2 microseconds against the 300 microsecond budget.
- Zig tests, raw ABI checks, native adapter tests, AppKit integration tests, all ten Steinberg example validators, and Linux and Windows example cross-bundles pass.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Native Windows, X11, Wayland, VoiceOver, and Narrator interaction remain external checks.

## Milestone 10: Editable Envelope Graph

- [x] Extend the graph contract with bounded editable points and stable point identifiers.
- [x] Implement hit testing, point creation, dragging, deletion, selection, and snapping.
- [x] Add keyboard traversal and adjustment with a visible selected-point state.
- [x] Expose point count, selection, coordinates, and edit actions through toolkit-neutral semantics.
- [x] Reuse multi-parameter gestures for parameter-backed envelopes and editor state for non-parameter envelopes.
- [x] Add deterministic interaction, visual, resize, scale, and performance coverage.

Exit criteria:

- Editing remains bounded by a declared point capacity.
- Pointer, keyboard, and assistive edits share snapping, validation, and undoable gesture boundaries.
- Static graphs retain zero continuous repaint, and editable graphs repaint only changed regions during activity.

Completion evidence:

- `gui_graph.EditableEnvelope(capacity)` owns fixed storage, stable IDs, ordered points, selection, snapping, capacity checks, minimum-count deletion, and transactional finish or rollback behavior.
- `ParameterEnvelopeAttachment(count)` maps stable point IDs to the existing two-parameter attachment contract. Native parameter-backed handles use the same ordered model for host gestures, rejection rollback, and automation updates.
- Adapter ABI version 10 carries bounded editable points, minimum count, snap intervals, and optional parameter bindings. Validation rejects malformed IDs, ordering, ranges, capacities, masks, and parameter references before editor creation.
- The VSTGUI envelope supports pointer creation, hit testing, drag, right-click deletion, keyboard traversal and editing, accessible selection and value actions, visible selected handles, and bounded partial invalidation.
- Both the component gallery and channel strip declare editable envelopes through `@import("zig-vst3").vstgui`. Each includes an unbound editor-state handle and a point backed by two ordinary parameters.
- Unit and interaction tests cover stable IDs, insertion, snapping, movement constraints, capacity, selection wrap, minimum counts, cancellation, pointer editing, keyboard editing, accessible actions, parameter callback order, partial rejection, automation, focus order, invalid descriptions, resize, and scale.
- The `editable-envelope.png` reference covers populated, selected, and empty states. The warm benchmark draws an editable envelope in its steady state and completed at 42.2 microseconds against the 300 microsecond budget.
- Zig tests, raw ABI checks, native adapter tests, AppKit integration tests, all ten Steinberg example validators, and Linux and Windows example cross-bundles pass.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Native Windows, X11, Wayland, VoiceOver, and Narrator interaction remain external checks.

## Milestone 11: Persistent Editor State

- [x] Define a versioned, per-instance store for non-parameter editor state.
- [x] Support typed values needed for panel expansion, analyzer settings, tabs, graph selection, and envelopes.
- [x] Keep editor state separate from automatable parameter state and audio-thread processing.
- [x] Define controller serialization hooks with size bounds, validation, and migration.
- [x] Exercise the contract in both the gallery and channel strip.
- [x] Build the preset-browser state model on this contract.
- [x] Test round trips, unknown fields, invalid data, migration, instance isolation, and editor reopen.

Exit criteria:

- Closing and reopening an editor restores declared UI state without changing plugin parameters.
- State decoding is bounded and rejects malformed payloads without partial mutation.
- Plugin authors can use the feature without importing adapter internals.

Completion evidence:

- `editor_state.Store(schema_version, fields)` provides compile-time schemas, typed defaults, fixed storage, bounded text and envelopes, transactional decode, unknown-field handling, and explicit field-ID migrations.
- Reflected controllers keep UI state in a per-instance store. VST3 `getState` and `setState` use a bounded composite with separate parameter and editor sections, while `setComponentState` remains the parameter-only path. UI mutations do not change automatable values, and composite decode commits neither section until both validate.
- Adapter ABI version 11 adds toolkit-neutral persistence callbacks and stable field bindings for editable-envelope selection and geometry. Completed VSTGUI edits update the controller store, and reopened views restore points, selection, and parameter bindings.
- The component gallery and channel strip declare panel, analyzer, tab, graph-selection, and envelope fields through the public core API. Both bind editable graphs without importing adapter internals.
- `gui_preset_browser.Browser(capacity)` adds bounded search, filtered selection navigation, and load status on top of persistent text and selection fields. It remains experimental until the native component milestone.
- Unit and native interaction tests cover every value type, successful and malformed round trips, unknown fields, migration, instance isolation, parameter separation, editor reopen, restored selection, and envelope callbacks.
- Zig tests, raw ABI checks, native adapter tests, AppKit integration tests, all ten Steinberg example validators, and Linux and Windows example cross-bundles pass. The final measured warm-render average was 61.3 microseconds against the 300 microsecond budget.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Native Windows, X11, Wayland, VoiceOver, and Narrator interaction remain external checks.

## Milestone 12: Higher-Level Components

- [x] Add a preset browser with search, selection, load status, and keyboard navigation.
- [x] Add anchored popovers and richer menus with focus containment and restoration.
- [x] Add a piano keyboard with pointer, computer-keyboard, and accessible note input.
- [x] Add a bounded step sequencer with multi-selection and clear playhead semantics.
- [x] Add file drag-and-drop with type filtering, rejection feedback, and host-safe lifetimes.
- [x] Add waveform and spectrum views on the graph source contract.
- [x] Exercise every promoted component in both the gallery and a production editor.
- [x] Add interaction, visual-regression, performance, lifecycle, and instance-isolation coverage.
- [x] Restore serial pluginval strictness 5 and 10 coverage, isolating the first plugin that exits unexpectedly.

Exit criteria:

- Each component has a complete pointer, keyboard, focus, empty, disabled, error, and accessibility experience.
- Repaint and data-transfer costs remain bounded under declared capacities.
- Single-consumer contracts remain experimental until a second production use establishes the shared API.

Preset browser completion evidence:

- `PresetBrowser` is a supported public authoring declaration. The component gallery and channel-strip editor both use the same bounded catalog, persistent search and selection fields, and host-automated load callback.
- Adapter ABI version 12 adds bounded preset catalogs, persisted text and selection callbacks, and preset-load dispatch. Version 11 remains the persistent editor-state foundation used by the browser.
- The browser is one composite focus stop. Typing filters the catalog, Backspace edits the query, Escape clears it, arrows and Home or End move selection, and Enter loads the selected preset. A single click selects and a double-click loads. Native accessibility focus, value, increment, decrement, and press actions use the same state machine.
- Empty results and failed loads remain visible and recoverable. A failed load keeps the selection and lets Enter retry.
- Filtering and visible-row selection use fixed-capacity storage. Drawing does not allocate, and keyboard navigation keeps the selected row in view.
- Native interaction tests cover filtering, persisted state callbacks, keyboard selection, accessible search and load actions, empty results, successful load, failed load, retry status, invalid declarations, and editor integration. `preset-browsers.png` covers populated, filtered-error, and empty states.
- All Zig tests, raw API ABI checks, native adapter tests, macOS accessibility bridge tests, visual regression tests, and all ten Steinberg example validators pass. The final warm-render average, including the browser, is 77.9 microseconds against the 300 microsecond budget.
- All examples cross-build for `x86_64-linux-gnu` and `x86_64-windows-gnu`. The Windows UI Automation provider also cross-compiles through the native adapter test script.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Manual host interaction and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.
- Action menus, piano input, sequencing, file drop, and production waveform or spectrum components remain separate slices of this milestone.

Action menu completion evidence:

- `ActionMenu` is a supported public authoring declaration shared by the component gallery and channel-strip editor. Plugin code declares bounded action, toggle, separator, disabled, and destructive items without importing adapter internals.
- Adapter ABI version 13 adds up to four menus with 16 items each, menu-action dispatch, and persisted boolean toggle state. Invalid IDs, empty labels, duplicate items, malformed separators, destructive toggles, missing handlers, and mismatched state fields reject editor creation.
- The overlay anchors above or below its trigger, clamps to the editor, dismisses on outside clicks, and coordinates one open menu per editor. The closed trigger is one focus stop. While open, Tab remains contained, arrows skip unavailable items, Home and End select boundaries, Enter or Space activates, and Escape closes and restores trigger focus.
- Accessible press, increment, decrement, and focus actions use the same menu state machine. Failed actions and failed persistence keep the menu open with a retry message. Failed toggle persistence restores the prior checked state.
- Menu descriptions and display labels are copied into instance-owned storage. Warm drawing uses cached labels and performs no menu-owned allocation. Generic arbitrary-content popovers remain unexposed because the two consumers establish only the action-menu contract.
- Native tests cover keyboard and pointer activation, disabled and separator skipping, toggle persistence, action rejection, store rollback, retry, outside dismissal, maximum-size scrolling, accessibility actions, invalid declarations, multiple-menu coordination, editor integration, and instance-owned descriptions.
- `action-menu-closed.png` covers the closed trigger. `action-menus.png` covers checked, disabled, separator, destructive, selected, and recoverable error states. The final warm-render average, including an open menu, was 82.7 microseconds against the 300 microsecond budget.
- Zig tests, raw API ABI checks, native adapter tests, macOS accessibility bridge tests, visual regression tests, and all ten Steinberg example validators pass. All examples cross-build for `x86_64-linux-gnu` and `x86_64-windows-gnu`.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Manual menu interaction in a macOS plugin host and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.
- Piano input is complete. Sequencing, file drop, and production waveform or spectrum components remain separate slices of this milestone.

Piano keyboard completion evidence:

- `Piano` is a supported public authoring declaration shared by the component gallery and sine-synth editor. Authors declare a bounded note range, MIDI channel, velocity, and computer-keyboard base pitch without importing adapter internals.
- Adapter ABI version 14 adds up to two 48-note keyboards and key-up forwarding. The existing ABI version 13 creation entry remains available, while the full creation entry carries piano descriptions.
- The native control draws conventional white and black key geometry. Pointer press and drag support velocity and glissando, the `awsedftgyhujkolp;` mapping plays chromatic notes, arrows and Home or End select notes, and Return or Space plays the selected note.
- Focus loss, editor close, pointer cancellation, and key release send note-off commands. Selected and playing states use outlines and text in addition to color.
- `gui_note_transport.Mailbox` carries the latest desired state for each MIDI pitch through the VST3 component connection. The audio thread performs bounded atomic reads without locks or allocation, emits releases before presses, and merges GUI events at sample zero with stable host-event ordering.
- `gui_piano.Keyboard(capacity)` supplies the toolkit-neutral note-range, selection, pressed-state, computer-key mapping, and bounded release model. The native choice semantic exposes the selected note, range, playing state, focus, press, increment, and decrement through the shared accessibility action path.
- Unit and native tests cover range validation, selection wrap, idempotent presses, bounded release, note naming, key mapping, pointer hit testing, key-up behavior, accessibility actions, invalid declarations, processor delivery, note-off delivery, and editor integration.
- `piano-keyboard.png` covers standard key geometry, octave labels, selection, and a pressed note. Zig tests, raw API ABI checks, native adapter tests, macOS accessibility bridge tests, visual regression tests, all ten Steinberg validators, and Linux and Windows example cross-bundles pass. The final piano-only warm-render average was 120.6 microseconds against the 300 microsecond budget. The complete warm-render scene averaged 201.8 microseconds during the same final validation run.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Manual piano interaction in a macOS host and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.
- Sequencing, file drop, and production waveform or spectrum components remain separate slices of this milestone.

Step sequencer completion evidence:

- `StepSequencer` is a supported public authoring declaration shared by the component gallery and sine-synth editor. Authors bind 1–32 distinct boolean parameters, a persistent selection field, and optional activity-gated playhead telemetry without importing adapter internals.
- Adapter ABI version 15 adds up to two sequencers while retaining the version 14 full creation entry. Active steps remain automatable processor parameters, selection remains editor state, and the playhead remains read-only telemetry. Host parameter updates refresh hidden step bindings without creating duplicate standalone controls.
- `gui_step_sequencer.Sequencer(capacity)` keeps the active mask, selection mask, cursor, anchor, and optional playhead independent. The native control applies the same model to click toggling, drag painting, additive and range selection, wrapped cursor movement, multi-step toggling, select all, and selection reset.
- The component is one focus stop. Choice semantics report cursor, active count, selection count, stopped or current playhead, focus, press, increment, and decrement. Disabled declarations expose read-only semantics and reject edits. Rejected parameter edits retain the old state and show visible and semantic error feedback. Zero-step declarations are invalid, so no ambiguous empty state is rendered.
- The sine synth uses eight boolean parameters as an audio-rate gate pattern and publishes its externally read playhead only while an editor is active. The gallery uses the same public declaration, persistence, automation, and telemetry contracts with a separate instance.
- Unit and native tests cover bounded masks, navigation, range and additive selection, painting, multi-parameter gestures, external host updates, rejected edits, disabled behavior, accessibility actions, invalid declarations, DSP gating, telemetry activity, editor integration, teardown, and instance-owned descriptions.
- `step-sequencer.png` covers active, inactive, multi-selected, and playhead states without relying on color alone. The dedicated 16-step warm-render benchmark completed at 145.1 microseconds against the 300 microsecond budget during final release validation.
- Zig tests, raw API ABI checks, native adapter tests, macOS accessibility bridge tests, visual regression tests, and all ten Steinberg validators pass. All examples cross-build for `x86_64-linux-gnu` and `x86_64-windows-gnu`. The benchmark harness now uses the best of three fixed-size batches so scheduler preemption does not create a false regression.
- Pluginval coverage is pending because recent isolated runs quit unexpectedly. Treat that as an unresolved plugin defect, separate from historical concurrent startup crashes. Manual sequencer interaction in a macOS host and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.
- Production waveform and spectrum components remain the final separate slice of this milestone.

File drop completion evidence:

- `FileDrop` began as an experimental public authoring declaration in the component gallery. Authors declare a stable target ID, visible title and prompt, picker labels, 1–8 case-insensitive extensions, a maximum of 1–8 files, and enabled state without importing adapter internals.
- Adapter ABI version 16 adds up to two file targets while retaining the version 15 full creation entry. Native validation rejects missing callbacks, duplicate IDs, malformed or duplicate extensions, excessive counts, and invalid enabled states before editor creation.
- The VSTGUI control accepts only file-path packages, copies at most eight 1,024-byte paths into instance-owned storage, filters before dispatch, and invokes plugin code synchronously. No host-owned pointer escapes the callback.
- Idle, acceptable, rejected type, rejected count, rejected path, handler failure, accepted, and disabled states expose visible text and toolkit-neutral semantics. The production extension adds validating, importing, ready, empty, cancelled, and recoverable failure states. The operating-system picker is the primary keyboard and accessibility action, while drag and drop remains an equivalent shortcut.
- Toolkit-neutral unit tests cover copied caller lifetimes, count and path bounds, case-insensitive filtering, malformed declarations, duplicate extensions, and handler rejection. Native tests exercise real VSTGUI drag enter and drop events, unsupported data packages, copied storage, callback failure and retry semantics, invalid ABI declarations, and editor integration.
- `file-drops.png` covers idle, acceptable, and recoverable failure states. `file-import-states.png` covers the nine production validation, progress, success, capacity, cancellation, and error states. The production file-drop scene rendered in 48.6 microseconds during the final strictness 10 gate, against the 300 microsecond budget.
- `FileDrop` is promoted to supported status because the gallery and channel strip now use the same public declaration, bounded callback, operating-system picker fallback, keyboard and accessibility actions, focus restoration, and teardown contract. The controller-owned WAV worker and controller graph-source hooks remain experimental because the channel strip is their only authoring consumer.
- Serialized pluginval strictness 5 and 10 coverage passed all ten plugins after the production importer slice. Manual file import in a macOS host and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.
- Production waveform and spectrum components complete the local slices of this milestone.

Waveform and spectrum completion evidence:

- `gui_graph.WaveformCapture(capacity)` reduces an audio block to at most 256 evenly spaced points. `gui_graph.SpectrumAnalyzer(fft_size)` accepts power-of-two sizes from 8 through 512, applies a Hann window, performs an in-place radix-2 FFT, and publishes up to 256 positive-frequency decibel bins.
- Both sources own fixed storage, allocate no memory, acquire no locks, publish through the existing nonblocking snapshot contract, and skip reduction and spectral work while no editor is open. The spectrum performs at most one transform per process call with a 50 percent hop.
- The gallery and production channel-strip processors use the same public source types and declare their waveform and spectrum through `@import("zig-vst3").vstgui.Graph`. Neither consumer imports adapter internals. Source activity, snapshots, and FFT work remain isolated per processor instance.
- Native rendering gives waveforms a zero line and spectra magnitude bars. Curve, bar, and grid geometry use batched graphics paths so draw-call count stays constant as the bounded point count grows. Unchanged dynamic frames do not invalidate the view.
- Empty waveform and spectrum states are explicit. Toolkit-neutral graph semantics report sample count and peak magnitude, or bin count and the strongest frequency and decibel level. Read-only signal views do not add misleading keyboard stops.
- Unit tests cover activity gating, deterministic waveform reduction, maximum capacity, deterministic FFT peak frequency and level, invalid sample rate, source selection, editor counts, and instance isolation. Native tests cover empty and populated semantics, dynamic refresh, invalid data, timer lifecycle, and unchanged-frame suppression.
- `signal-views.png` covers populated waveform, populated spectrum, and empty spectrum states. A dedicated benchmark renders a maximum-capacity 256-point waveform and 256-bin spectrum against the 300 microsecond warm-frame budget.
- Final local measurements were 273.7 microseconds for the maximum-capacity signal pair, 263 nanoseconds for 128-point waveform capture plus snapshot read, and 2.19 microseconds for a 128-point FFT plus snapshot read. All Zig tests, raw API ABI checks, native adapter tests, macOS accessibility bridge tests, visual regression tests, and all ten Steinberg validators pass. All examples cross-build for `x86_64-linux-gnu` and `x86_64-windows-gnu`.
- Pluginval coverage was pending after recent isolated runs quit unexpectedly. The recovery run below restored local coverage without assigning those earlier exits a root cause. Manual signal-view interaction in a macOS plugin host and native Windows, X11, Wayland, VoiceOver, Narrator, and AT-SPI checks remain pending.

Pluginval recovery evidence:

- On July 18, 2026, the serialized aggregate suite passed all ten example plugins at strictness 5 and strictness 10. Both GUI examples passed editor creation, editor-while-processing, and editor automation. Strictness 10 also passed non-releasing processing, state restoration, background-thread state, parameter thread safety, and parameter fuzzing.
- Each invocation wrote to a separate artifact directory. The aggregate target completed 44 of 44 build steps at both strictness levels, and no unexpected exit occurred. The earlier isolated failure was not reproduced, so no plugin root cause is claimed.

## Validation After Each Milestone

- Run Zig tests and raw ABI checks.
- Run native adapter, accessibility, interaction, visual-regression, and warm-render tests.
- Cross-compile the Windows accessibility provider.
- Run every Steinberg validator example.
- Cross-build Linux and Windows example bundles.
- Run pluginval examples serially. Stop after the first unexpected exit or crash dialog, preserve its artifacts, and treat it as a plugin failure until isolation proves otherwise.
- Perform manual macOS host checks when practical.
- Record native Windows, VoiceOver, Narrator, X11, Wayland, and AT-SPI checks as pending when their environments are unavailable.

## Deferred External Checks

- VoiceOver action navigation on macOS.
- Narrator navigation and UIA control-pattern behavior on Windows.
- X11 and Wayland host interaction.
- AT-SPI semantics and actions on Linux.
- Manual graph rendering in a production host.
- Manual preset-browser interaction in a production host.
- Manual action-menu interaction in a production host.
- Manual piano-keyboard interaction in a production host.
- Manual step-sequencer interaction in a production host.
- Manual file-drop interaction in a production host.
- Manual waveform and spectrum interaction in a production host.
