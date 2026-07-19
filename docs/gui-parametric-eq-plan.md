# Production Parametric EQ Plan

## Outcome

Build a three-band parametric EQ whose editor uses only the public `@import("zig-vst3").vstgui` authoring API. Use it to finish production rotary controls, introduce linked graph handles, validate a bounded spectrum path, and decide whether rotary, bipolar, decibel, asset, font, and custom-drawing contracts are ready for supported status.

The editor must remain understandable without the analyzer. Each band presents Enable, Filter, Frequency, Gain, and Q as one labeled group. The response graph is the primary editing surface, but every graph action has an equivalent knob, exact-entry, keyboard, and accessibility path.

## Invariants

- Parameter edits use standard begin, perform, and end gestures. Host updates never emit a second edit.
- Graph handles and knobs display one accepted parameter state and roll back together after rejection.
- The audio callback allocates no memory, takes no locks, performs no file I/O, and never touches editor-owned state.
- Spectrum transport is fixed-capacity, activity-gated, and bounded to the existing graph point limit.
- Instances own independent processor, controller, editor, analyzer, and resize state.
- Compact layouts keep every label readable and every control reachable. Narrow layouts may scroll vertically but cannot clip controls horizontally.
- Focus, selection, enablement, and clipping state do not rely on color alone.

## Milestone 1: EQ DSP and Plugin Skeleton

- [x] Define three bands, output gain, and bypass with stable parameter IDs and public metadata.
- [x] Implement low shelf, bell, and high shelf coefficient generation for `f32` and `f64` processing.
- [x] Clamp frequency and Q against the active sample rate and reject non-finite configuration.
- [x] Add deterministic magnitude-response evaluation shared by processing tests and GUI response generation.
- [x] Add bounded parameter-transition behavior that avoids discontinuities without audio-thread allocation.
- [x] Register native, Linux, Windows, Steinberg validator, and serialized pluginval build steps.

Exit criteria:

- Bypass is sample-identical.
- Unity settings remain within floating-point tolerance of the input.
- Each band produces the expected gain at its center or shelf reference frequency.
- State and processing remain isolated across two instances.
- The new bundle passes Zig tests, raw entry-symbol checks, and the Steinberg validator.

## Milestone 2: Production Rotary Controls

- [ ] Replace the current generic knob presentation with a production rotary component.
- [ ] Draw a bounded value arc, default marker, center or unity marker where applicable, and modulation overlay.
- [ ] Support drag, fine adjustment, arrow keys, Home and End through laptop-safe alternatives, Command-click reset, exact entry, and context menus.
- [ ] Keep the numeric field and units readable at the minimum accepted size.
- [ ] Expose native adjustable semantics, formatted value, range, default reset, and tooltip text.
- [ ] Exercise the same rotary contract in the component gallery and EQ.

Exit criteria:

- Pointer, keyboard, exact-entry, reset, host-update, rejection, and focus tests pass.
- Normal, hovered, focused, edited, modulated, disabled, and automation-updated states have deterministic visual coverage.
- The rotary warm-render scene stays within its recorded budget.

## Milestone 3: Linked Response Graph

- [ ] Add a toolkit-neutral graph-handle declaration separate from curve points.
- [ ] Bind each handle to frequency and gain parameters, with Q available through keyboard and accessibility adjustment.
- [ ] Render the calculated combined response and three band contributions without allocating during draw.
- [ ] Keep graph and knob gestures synchronized under pointer editing, keyboard editing, host automation, preset loading, and rejected edits.
- [ ] Provide a visible selected-band state in the graph and matching parameter panel.
- [ ] Expose handle name, band state, frequency, gain, Q, selection, and adjustment semantics.

Exit criteria:

- Dragging a handle changes exactly the linked parameters in one grouped gesture.
- Knob changes and host automation move the matching handle without starting a graph gesture.
- A rejected axis update restores both axes and every linked view.
- Fixed-capacity tests cover all handles, curve limits, invalid bindings, gesture ordering, and instance isolation.

## Milestone 4: Analyzer and Shared Skin

- [ ] Add an activity-driven input or output spectrum backed by the existing bounded analyzer transport.
- [ ] Compose the analyzer, combined response, band contributions, grid, and handles in one graph without increasing point limits.
- [ ] Add a public skin with embedded assets, preferred and fallback fonts, and bounded custom drawing.
- [ ] Use the same skin contracts in the gallery, IR loader, and EQ.
- [ ] Keep analyzer absence and disabled state explicit instead of rendering an unexplained empty graph.

Exit criteria:

- Closing every editor stops spectrum production and repaint activity.
- Analyzer snapshots cannot block or allocate in processing.
- Visual references cover analyzer off, no signal, active signal, selected band, bypass, and clipping.
- Assets, fonts, and drawing callbacks survive repeated editor open and close across multiple plugin bundles.

## Milestone 5: Responsive Production Editor

- [ ] Provide compact, standard, and expanded layouts with stable resize round trips.
- [ ] Use labeled band panels and a separate output section so the screen never presents more than five ungrouped decisions.
- [ ] Keep Bypass visually distinct from band enable controls and away from reset actions.
- [ ] Preserve selected band, focus order, scroll position, analyzer state, and accepted host size per instance.
- [ ] Verify repeated open and close, two simultaneous instances, manual resize, compact toggling, and state restoration.
- [ ] Cover macOS accessibility directly and retain toolkit-neutral Windows semantics.

Exit criteria:

- Minimum size has no clipped text, overlapping controls, ambiguous selection, or unreachable action.
- Compact, standard, expanded, manual shrink, and manual grow cycles return to deterministic geometry.
- Pointer, keyboard, and accessibility paths can complete the same EQ-editing tasks.

## Milestone 6: API Decisions and Release Gates

- [ ] Promote rotary only if the gallery and EQ use one public contract and every local exit criterion passes.
- [ ] Promote bipolar and decibel controls only after the EQ becomes their second production consumer.
- [ ] Promote assets, fonts, and custom drawing only if the EQ and IR loader use the same contract successfully.
- [ ] Keep analyzer transport experimental until a second production analyzer consumer establishes its required shape.
- [ ] Document precise blockers for every retained experimental API.
- [ ] Update component reference examples and status tables.

Release gates:

- [ ] `zig build test raw-api-abi validate-examples --summary all`
- [ ] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [ ] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [ ] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [ ] Serialized pluginval strictness 5 and strictness 10, stopping at the first unexpected exit
- [ ] Manual REAPER checks for rendering, graph and knob synchronization, resize cycles, multiple instances, and editor reopen

External checks remain pending when the required environment is unavailable:

- Native Windows host interaction and Narrator
- X11 and Wayland host interaction
- AT-SPI names, roles, values, focus, and actions
- Multi-monitor display-scale changes where the host exposes them

## Completion Evidence

Record each committed milestone here with test counts, performance measurements, host observations, API decisions, and deferred external checks. Do not use pluginval as evidence of visual correctness.

### Milestone 1

- Added a reusable logarithmic float descriptor for frequency and Q, including host plain ranges, parsing, formatting, validation, and tests.
- Added fixed-state low shelf, bell, and high shelf biquads with deterministic response evaluation and bounded 64-sample coefficient transitions.
- Added the public-API `parametric-eq` example with 17 parameters, isolated component state, sample-identical bypass tests, unity processing tests, a bounded analyzer, and native, Linux, and Windows bundles.
- `zig build test --summary all`: 58/58 steps and 3,692/3,692 tests passed.
- Raw ABI and entry-symbol checks passed, including the new EQ library.
- Steinberg validator: 47/47 tests passed for the EQ across single and double precision.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target bundles passed.
- Serialized pluginval strictness 5 and strictness 10 passed through the EQ with no unexpected exit. Artifacts remain under the run-specific `zig-vst3-pluginval` temporary directories.
- Latest shared warm-render measurements during this milestone: visual regression 93.9 us, piano 102.7 us, step sequencer 153.4 us, file drop 49.2 us, action button 39.7 us, progress 13.5 us, signal views 262.4 us, viewport 51.4 us, and range selection 105.5 us.
- Manual visual acceptance of the EQ is deferred until the linked response graph and production rotary milestones are ready for host review.
