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

- [x] Replace the current generic knob presentation with a production rotary component.
- [x] Draw a bounded value arc, default marker, center or unity marker where applicable, and modulation overlay.
- [x] Support drag, fine adjustment, arrow keys, Home and End through laptop-safe alternatives, Command-click reset, exact entry, and context menus.
- [x] Keep the numeric field and units readable at the minimum accepted size.
- [x] Expose native adjustable semantics, formatted value, range, default reset, and tooltip text.
- [x] Exercise the same rotary contract in the component gallery and EQ.

Exit criteria:

- Pointer, keyboard, exact-entry, reset, host-update, rejection, and focus tests pass.
- Normal, hovered, focused, edited, modulated, disabled, and automation-updated states have deterministic visual coverage.
- The rotary warm-render scene stays within its recorded budget.

## Milestone 3: Linked Response Graph

- [x] Add a toolkit-neutral graph-handle declaration separate from curve points.
- [x] Bind each handle to frequency and gain parameters, with Q available through keyboard and accessibility adjustment.
- [x] Render the calculated combined response and three band contributions without allocating during draw.
- [x] Keep graph and knob gestures synchronized under pointer editing, keyboard editing, host automation, preset loading, and rejected edits.
- [x] Provide a visible selected-band state in the graph and matching parameter panel.
- [x] Expose handle name, band state, frequency, gain, Q, selection, and adjustment semantics.

Exit criteria:

- Dragging a handle changes exactly the linked parameters in one grouped gesture.
- Knob changes and host automation move the matching handle without starting a graph gesture.
- A rejected axis update restores both axes and every linked view.
- Fixed-capacity tests cover all handles, curve limits, invalid bindings, gesture ordering, and instance isolation.

## Milestone 4: Analyzer and Shared Skin

- [x] Add an activity-driven input or output spectrum backed by the existing bounded analyzer transport.
- [x] Compose the analyzer, combined response, band contributions, grid, and handles in one graph without increasing point limits.
- [x] Add a public skin with embedded assets, preferred and fallback fonts, and bounded custom drawing.
- [x] Use the same skin contracts in the gallery, IR loader, and EQ.
- [x] Keep analyzer absence and disabled state explicit instead of rendering an unexplained empty graph.

Exit criteria:

- Closing every editor stops spectrum production and repaint activity.
- Analyzer snapshots cannot block or allocate in processing.
- Visual references cover analyzer off, no signal, active signal, selected band, bypass, and clipping.
- Assets, fonts, and drawing callbacks survive repeated editor open and close across multiple plugin bundles.

## Milestone 5: Responsive Production Editor

- [x] Provide compact, standard, and expanded layouts with stable resize round trips.
- [x] Use labeled band panels and a separate output section so the screen never presents more than five ungrouped decisions.
- [x] Keep Bypass visually distinct from band enable controls and away from reset actions.
- [x] Preserve selected band, focus order, scroll position, analyzer state, and accepted host size per instance.
- [ ] Verify repeated open and close, two simultaneous instances, manual resize, compact toggling, and state restoration.
- [x] Cover macOS accessibility directly and retain toolkit-neutral Windows semantics.

Exit criteria:

- Minimum size has no clipped text, overlapping controls, ambiguous selection, or unreachable action.
- Compact, standard, expanded, manual shrink, and manual grow cycles return to deterministic geometry.
- Pointer, keyboard, and accessibility paths can complete the same EQ-editing tasks.

## Milestone 6: API Decisions and Release Gates

- [ ] Promote rotary only if the gallery and EQ use one public contract and every local exit criterion passes.
- [ ] Promote decibel controls after the final EQ host checks. The gallery, channel strip, IR loader, and EQ now share one public contract.
- [ ] Keep the direct bipolar slider experimental until a production editor uses that presentation. Bipolar dB rotary behavior does not prove the slider contract.
- [ ] Promote assets, fonts, and custom drawing only if the EQ and IR loader use the same contract successfully.
- [ ] Keep analyzer transport experimental until a second production analyzer consumer establishes its required shape.
- [ ] Document precise blockers for every retained experimental API.
- [ ] Update component reference examples and status tables.

Release gates:

- [x] `zig build test raw-api-abi validate-examples --summary all`
- [x] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [x] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [x] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [ ] Serialized pluginval strictness 5 and strictness 10, stopping at the first unexpected exit
- [ ] Manual REAPER checks for rendering, graph and knob synchronization, resize cycles, multiple instances, and editor reopen

External checks remain pending when the required environment is unavailable:

- Native Windows host interaction and Narrator
- X11 and Wayland host interaction
- AT-SPI names, roles, values, focus, and actions
- Multi-monitor display-scale changes where the host exposes them

## Follow-up: Display Scale and Platform Verification

- [x] Keep layout, breakpoints, and component geometry in logical coordinates.
- [x] Scale `getSize`, host resize requests, and minimum and maximum constraints through `IPlugViewContentScaleSupport`.
- [x] Accept scale changes before and after attachment and roll back rejected host resize requests.
- [x] Cover repeated 1x, 1.5x, and 2x geometry with deterministic tests.
- [ ] Move an attached editor between displays with different scale factors in a native host.
- [ ] Verify the shared semantics with Narrator in a native Windows host.
- [ ] Verify native X11 and Wayland attachment, scale, and AT-SPI behavior.

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

### macOS host lifecycle correction

- REAPER crash reports from July 18 and 19 identified faults in Editor Smoke's VSTGUI `NSViewFrame` tracking and drawing callbacks while the multi-plugin audit chain was loaded.
- The adapter and VSTGUI library used inconsistent conditional virtual-interface definitions. The build now pins and propagates matching deprecated-method and OpenGL settings, with compile-time drift checks.
- macOS frame close now disconnects the native view from its raw C++ frame pointer and removes queued tracking, notification, and delegated-layer paths before destruction.
- The native macOS suite retains native views across 16 open, draw, tracking, and close cycles, calls those views again after teardown, and completes without stale frame access.
- The post-fix automated gate passed 213 of 213 build steps and 3,696 of 3,696 tests, all raw ABI checks, all twelve Steinberg example validators, and both 38-step Linux and Windows cross-target bundle matrices. The rebuilt REAPER multi-plugin rerun remains pending manual confirmation.
- Latest shared warm-render measurements during this milestone: visual regression 93.9 us, piano 102.7 us, step sequencer 153.4 us, file drop 49.2 us, action button 39.7 us, progress 13.5 us, signal views 262.4 us, viewport 51.4 us, and range selection 105.5 us.
- Manual visual acceptance of the EQ is deferred until the linked response graph and production rotary milestones are ready for host review.

### Milestone 2

- Added a dedicated rotary component with a bounded 270-degree track, value arc, default marker, radial indicator, modulation marker, and theme-resolved normal, hover, press, focus, edit, and disabled states.
- Preserved the standard parameter attachment contract for pointer gestures, Shift fine adjustment, arrows, Home and End, Command-click reset, exact text entry, context menus, host updates, and rejected-edit rollback.
- Added adjustable accessibility semantics, formatted values, normalized range and default information, increment and decrement actions, and concise tooltips.
- Added the rotary to both the public-API component gallery and the parametric EQ. Gallery state persistence and production preset paths include its independent parameter.
- Added a six-state rotary visual reference with modulation coverage and native tests for keyboard limits, fine adjustment, rejection rollback, accessibility adjustment, and runtime modulation updates.
- `zig build test --summary all`: 58/58 steps and 3,692/3,692 tests passed.
- Raw ABI checks passed. Every native example passed the Steinberg validator, including 47/47 tests for the parametric EQ.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target matrices each passed 38/38 steps.
- Serialized pluginval strictness 5 and strictness 10 passed all examples without an unexpected exit or GUI crash. The strictness 10 matrix passed 52/52 build steps.
- Latest rotary warm-render measurements ranged from 31.2 us to 38.1 us, within the 250 us scene budget. The final full test run measured 33.1 us.
- Manual REAPER acceptance remains pending until the linked response graph is implemented, so the knob and graph can be reviewed as one production editing flow.

### Milestone 3

- Added a public, toolkit-neutral graph-handle declaration with stable identity, frequency and gain bindings, optional Q and enable bindings, and optional parameter-group highlighting.
- Added fixed-capacity graph layers for the combined response and low, mid, and high band contributions. Parameter-driven curves refresh only after controller parameter notifications and do not use a repaint timer.
- Added grouped pointer gestures, arrow editing, Page Up and Page Down Q adjustment, Shift fine adjustment, selection traversal, host-update synchronization, and rejected-edit rollback.
- Added native accessibility values for handle name, enablement, frequency, gain, Q, and selection. Selecting a handle also highlights its matching band heading.
- Added deterministic native coverage for gestures, rejection, host updates, dependency refresh, invalid bindings, layers, disabled handles, accessibility, and selection. Added the `linked-eq-response.png` visual reference.
- `zig build test raw-api-abi validate-parametric-eq --summary all`: 168/168 steps and 3,692/3,692 tests passed. Raw ABI checks passed, and the Steinberg validator passed 47/47 EQ tests.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` EQ bundles each passed 4/4 build steps.
- The final linked EQ warm-render measurement was 226.5 us, within the 300 us scene budget.
- Pluginval strictness 5 stopped at its first unexpected exit. The preserved macOS crash report shows pluginval 1.0.4 aborting during `NSApplication` registration before loading a zig-vst3 plugin image. Strictness 10 was not run, and pluginval coverage is unavailable for this milestone.
- Manual REAPER acceptance of handle and knob synchronization, band highlighting, resize behavior, multiple instances, and editor reopen remains pending.

### Milestone 4

- Added mixed-source graph layers. The EQ now draws a 64-bin component spectrum behind its combined parameter-driven response, three band contributions, and linked handles in one graph. Dynamic telemetry refreshes only from the bounded timer, while parameter-driven curves refresh only after parameter notifications.
- Kept every graph source under the existing 256-point limit. Source loads stage into fixed-capacity arrays and reject overflow or non-finite data before changing the visible graph. Layer flags and optional axes now reject malformed ABI values, non-finite ranges, and invalid logarithmic minima.
- Reused the existing fixed-capacity, atomic `SpectrumAnalyzer(128)` transport. It performs no allocation, locking, file I/O, or editor access in processing, and skips capture unless at least one editor is open. Nested editor activity and two-instance isolation have deterministic tests.
- Added explicit `Analyzer off`, `Analyzer waiting for signal`, and active analyzer states. Accessibility reports the same state and includes the active bin count, peak frequency, and peak level.
- Added an EQ skin through only the public authoring API. It uses an embedded SVG, Avenir Next and Menlo preferences with Arial fallback, bounded knob and bypass drawing, a dark editor theme, and distinct band accents. The gallery, IR loader, and EQ now exercise the same asset, font, and drawing contract.
- Added `eq-analyzer-states.png` and updated `linked-eq-response.png`. The shared visual suite covers analyzer off, no signal, active signal, selected band, bypass controls, and meter clipping.
- Expanded the macOS lifecycle test to retain native views through 16 open, draw, tracking, and close cycles while an SVG asset, preferred and fallback fonts, and a custom drawing callback are active. Calls against retained native views after teardown complete without stale frame access.
- `zig build test raw-api-abi validate-examples --summary all` passed. The test matrix contains 3,703 passing tests, all raw ABI checks, and all twelve Steinberg example validators.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target bundle matrices each passed 38/38 steps.
- Latest warm-render measurements: full visual suite 97.0 us, signal views 278.2 us, and linked EQ with analyzer 241.5 us. The linked EQ remains within its 300 us scene budget.
- Pluginval was not relaunched. Its preserved unexpected exit occurs during `NSApplication` registration before a zig-vst3 plugin image is loaded, so strictness coverage remains unavailable under the required stop-on-exit policy.
- Manual REAPER confirmation of the rebuilt crash fix, shared skins across bundles, EQ analyzer rendering, and repeated editor reopen remains pending. Native Windows, X11, Wayland, Narrator, AT-SPI, and screen-reader workflows remain deferred to their required environments.

### Milestone 5

- Added the public `.parameter_workspace` layout and advanced the adapter ABI to version 24. Its first group owns one graph and up to three global parameters. Remaining groups contain one through five parameters each.
- The EQ opens at 720 by 660. It accepts 400 by 360 through 1000 by 700 and provides 480 by 480 Compact and 960 by 700 Expanded presets. Compact mode scrolls vertically; standard and expanded presets fit without scrolling.
- Added deterministic geometry coverage for all 17 EQ controls at compact, standard, and expanded sizes. The test checks positive bounds, horizontal containment, label, control, and value separation, graph and group containment, scroll clamping, and resize requests.
- Increased workspace label tracks after the visual test exposed truncation in `Freq (Hz)`, `Output (dB)`, and `Bypass`. The accepted references show complete labels with separate control and value tracks at the default size.
- Restoring a selected graph handle now restores its linked group highlight. The EQ stores Mid as its initial selection and tests editor-state isolation across two controller instances.
- Added `eq-workspace-compact.png`, `eq-workspace-standard.png`, and `eq-workspace-expanded.png`. Full-editor snapshot rendering uses the editor-owned VSTGUI runtime so the harness does not nest or double-close platform initialization.
- `zig build test raw-api-abi validate-examples --summary all`: 213/213 steps and 3,704/3,704 tests passed. Raw ABI checks and all twelve Steinberg example validators passed.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target bundle matrices each passed 38/38 steps.
- Latest warm-render measurements: full visual suite 86.7 us, rotary 31.1 us, signal views 254.1 us, and linked EQ with analyzer 220.7 us. Every scene remains within its recorded budget.
- Pluginval was not relaunched because its preserved startup abort remains under the stop-on-exit policy. Post-fix REAPER confirmation of compact, standard, expanded, manual resize, multiple-instance, and reopen behavior remains pending.

### Display-scale follow-up

- Fixed the shared VSTGUI binding so host rectangles, constraints, and resize requests scale while the component layout remains in logical coordinates.
- Scale changes now work before or after frame attachment. A host rejection restores the prior frame zoom, view rectangle, and accepted scale.
- Added EQ coverage for pre-attach 2x sizing, nonzero-origin constraints, attached 1.5x sizing, host resize notification, accepted `onSize`, and rejected-scale rollback. Native adapter coverage rejects zero, non-finite, and infinite scales and verifies layout remains stable across scale changes.
- `zig build test` passed 58/58 steps and 3,706/3,706 tests. Raw ABI checks, all twelve Steinberg validators, native adapter tests, macOS accessibility tests, visual comparisons, and both 38-step Linux and Windows cross-target bundle matrices passed. The final linked-EQ warm render measured 229.4 us against its 300 us budget.

### Component Gallery contract audit

- Added Output as a public `decibel_slider` in the gallery's Continuous group. Its -24 dB to +24 dB parameter defaults to 0 dB and applies the same dB-to-linear conversion used by production consumers.
- Neutral and Safe Bypass restore 0 dB. Wide Motion sets +6 dB. Preset loading retains standard grouped host gestures.
- Added deterministic coverage for the public declaration, preset values, grouped gesture counts, controller-state round trips, legacy state restoration at 0 dB, and rendered audio gain.
- Corrected the concurrent audio-import replacement test to accept either valid linearization point: cleared media while decoding or the completed replacement. It still rejects exposure of the prior media and passed five additional aggregate runs with fresh seeds.
- Decibel sliders now have one gallery consumer and three production consumers: Channel Strip, IR Loader, and Parametric EQ. Final supported status remains gated on the current EQ bundle's manual REAPER checks.
- The direct bipolar slider remains experimental because only the gallery uses that presentation. The EQ's bipolar dB range uses rotary controls and does not validate the slider-specific contract.
- `zig build test raw-api-abi validate-examples --summary all` passed 213/213 steps and 3,714/3,714 tests. Raw ABI checks and all twelve Steinberg example validators passed.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target bundle matrices each passed 38/38 steps.
- Final warm-render measurements were 98.4 us for the full visual suite, 34.0 us for rotary, 281.0 us for signal views, and 245.0 us for linked EQ. Every scene remained within its recorded budget.
- Pluginval was not relaunched because its preserved startup abort remains under the stop-on-exit policy. Manual REAPER validation of the current crash-fixed EQ bundle remains pending.

### Linked GraphHandle gallery audit

- Added a public-API `Linked Response` graph to the Component Gallery. Its handle binds Tone and Bipolar Amount, uses Output as the third adjustment parameter, persists selection through the controller state store, and highlights the existing Continuous group.
- The controller curve is fixed at 64 points. It rejects undersized output storage, clamps every result to the declared axes, and changes deterministically with each of the three linked parameters.
- The gallery and parametric EQ now exercise the same `GraphHandle`, parameter-driven controller source, selection, third-dimension adjustment, and linked-group highlight contracts. The existing native graph-handle suite covers grouped pointer edits, keyboard adjustment, host automation, rejection rollback, selection traversal, accessibility values, and teardown.
- `zig build test raw-api-abi validate-examples --summary all` passed. The matrix includes 3,716 passing tests, every raw ABI check, all twelve Steinberg example validators, native adapter tests, macOS accessibility tests, and visual regression. Final warm-render measurements were 93.7 us for the full visual suite, 31.4 us for rotary controls, 259.1 us for signal views, and 228.1 us for linked EQ.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` cross-target bundle matrices each passed 38/38 steps.
- `GraphHandle` remains experimental because the gallery is a regression fixture and the parametric EQ is still its only production consumer. Manual validation of the current EQ bundle remains part of the release gate.
