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
- Pluginval was not relaunched for this milestone. Prior concurrent runs produced macOS AppKit startup crashes before plugin loading, while the last isolated channel-strip run passed. Native action behavior is outside pluginval's coverage.
- VoiceOver and Narrator navigation remain external checks because no automated screen-reader driver is available locally.

## Milestone 9: Multi-Parameter Gestures and XY Pad

- [ ] Define a public multi-parameter attachment that owns an ordered set of parameter IDs.
- [ ] Begin each parameter once, publish accepted values in stable order, and end every begun parameter once.
- [ ] Roll back the complete visible gesture when a host rejects any value.
- [ ] Cancel active gestures during editor close without leaving host edits open.
- [ ] Build a reusable XY pad with pointer, keyboard, and accessible axis actions.
- [ ] Add the XY pad to the component gallery and channel strip through the public API.
- [ ] Test automation, cancellation, rejection, focus order, resize, and instance isolation.

Exit criteria:

- One interaction can edit two parameters without adapter-specific composition code.
- Host callback order is deterministic for success, partial rejection, cancellation, and teardown.
- Each axis has an accessible name, value, range, and independent adjustment path.

## Milestone 10: Editable Envelope Graph

- [ ] Extend the graph contract with bounded editable points and stable point identifiers.
- [ ] Implement hit testing, point creation, dragging, deletion, selection, and snapping.
- [ ] Add keyboard traversal and adjustment with a visible selected-point state.
- [ ] Expose point count, selection, coordinates, and edit actions through toolkit-neutral semantics.
- [ ] Reuse multi-parameter gestures for parameter-backed envelopes and editor state for non-parameter envelopes.
- [ ] Add deterministic interaction, visual, resize, scale, and performance coverage.

Exit criteria:

- Editing remains bounded by a declared point capacity.
- Pointer, keyboard, and assistive edits share snapping, validation, and undoable gesture boundaries.
- Static graphs retain zero continuous repaint, and editable graphs repaint only changed regions during activity.

## Milestone 11: Persistent Editor State

- [ ] Define a versioned, per-instance store for non-parameter editor state.
- [ ] Support typed values needed for panel expansion, analyzer settings, tabs, graph selection, and envelopes.
- [ ] Keep editor state separate from automatable parameter state and audio-thread processing.
- [ ] Define controller serialization hooks with size bounds, validation, and migration.
- [ ] Exercise the contract in both the gallery and channel strip.
- [ ] Build the preset-browser state model on this contract.
- [ ] Test round trips, unknown fields, invalid data, migration, instance isolation, and editor reopen.

Exit criteria:

- Closing and reopening an editor restores declared UI state without changing plugin parameters.
- State decoding is bounded and rejects malformed payloads without partial mutation.
- Plugin authors can use the feature without importing adapter internals.

## Milestone 12: Higher-Level Components

- [ ] Add a preset browser with search, selection, load status, and keyboard navigation.
- [ ] Add anchored popovers and richer menus with focus containment and restoration.
- [ ] Add a piano keyboard with pointer, computer-keyboard, and accessible note input.
- [ ] Add a bounded step sequencer with multi-selection and clear playhead semantics.
- [ ] Add file drag-and-drop with type filtering, rejection feedback, and host-safe lifetimes.
- [ ] Add waveform and spectrum views on the graph source contract.
- [ ] Exercise every promoted component in both the gallery and a production editor.
- [ ] Add interaction, visual-regression, performance, lifecycle, and instance-isolation coverage.

Exit criteria:

- Each component has a complete pointer, keyboard, focus, empty, disabled, error, and accessibility experience.
- Repaint and data-transfer costs remain bounded under declared capacities.
- Single-consumer contracts remain experimental until a second production use establishes the shared API.

## Validation After Each Milestone

- Run Zig tests and raw ABI checks.
- Run native adapter, accessibility, interaction, visual-regression, and warm-render tests.
- Cross-compile the Windows accessibility provider.
- Run every Steinberg validator example.
- Cross-build Linux and Windows example bundles.
- Run pluginval examples serially. Stop after the first macOS crash dialog.
- Perform manual macOS host checks when practical.
- Record native Windows, VoiceOver, Narrator, X11, Wayland, and AT-SPI checks as pending when their environments are unavailable.

## Deferred External Checks

- VoiceOver action navigation on macOS.
- Narrator navigation and UIA control-pattern behavior on Windows.
- X11 and Wayland host interaction.
- AT-SPI semantics and actions on Linux.
- Manual graph rendering in a production host.
