# Production Resonant Filter Plan

## Outcome

Build a resonant filter whose editor uses only the public `@import("zig-vst3").vstgui` authoring API. The plugin will provide low-pass, high-pass, band-pass, and notch modes, production filter controls, a linked response handle, and a live output spectrum.

This is the second production consumer for `GraphHandle` and graph layers. Analyzer transport already has production consumers in Channel Strip and Parametric EQ, so this milestone validates another independent analyzer shape rather than establishing its second use.

## Invariants

- Parameter edits use standard begin, perform, and end gestures. Host updates do not emit a second edit.
- The graph handle, controls, exact-entry fields, automation state, and presets display one accepted parameter state.
- The audio callback allocates no memory, takes no locks, performs no file I/O, and never touches editor-owned state.
- Analyzer transport and graph rendering remain fixed-capacity, bounded, and activity-driven.
- Bypass is sample-identical. Filter coefficient transitions and gain changes are bounded and smoothed.
- Instances own independent processor, controller, analyzer, editor, preset, focus, and resize state.
- Compact layouts keep labels readable and controls reachable. Focus, selection, enablement, and bypass do not rely on color alone.

## Milestone 1: DSP and Plugin Skeleton

- [x] Extend the shared biquad with low-pass, high-pass, band-pass, and notch coefficient generation.
- [x] Add deterministic response tests at cutoff, passband, stopband, and notch frequencies.
- [x] Define stable IDs and metadata for Mode, Cutoff, Resonance, Drive, Mix, Output, and Bypass.
- [x] Implement `f32` and `f64` processing with bounded coefficient and scalar smoothing.
- [x] Register native, Linux, Windows, Steinberg validator, and serialized pluginval build steps.

Exit criteria:

- Every filter mode has finite coefficients throughout the accepted parameter and sample-rate ranges.
- Bypass is sample-identical, unity dry mix preserves input, and two instances remain isolated.
- The plugin uses no adapter-internal imports.
- Zig tests, raw ABI checks, the Steinberg validator, and both cross-target bundles pass.

## Milestone 2: Linked Response and Spectrum

- [ ] Add a calculated magnitude-response curve over the live output spectrum.
- [ ] Bind one graph handle to cutoff and resonance through standard grouped gestures.
- [ ] Keep graph motion synchronized with controls, host automation, exact entry, presets, and rejected edits.
- [ ] Provide explicit analyzer-off, waiting-for-signal, active, and bypass states.
- [ ] Keep all sources within the existing graph point and analyzer transport limits.

Exit criteria:

- Pointer and keyboard handle edits update exactly Cutoff and Resonance.
- Control and host changes move the handle without beginning a graph gesture.
- Rejected graph edits restore both axes and every linked view.
- Closing the last editor stops analyzer production and repaint activity.

## Milestone 3: Production Editor

- [ ] Group Filter controls separately from Drive, Mix, Output, and Bypass.
- [ ] Add a compact layout with deterministic compact, expanded, manual shrink, and manual grow round trips.
- [ ] Add useful presets for each filter mode and preserve accepted state through editor reopen.
- [ ] Support pointer editing, fine adjustment, arrow keys, laptop-safe limits, Command-click reset, exact entry, context menus, tooltips, and visible focus.
- [ ] Expose toolkit-neutral names, roles, values, ranges, selection, adjustment, enablement, and bypass semantics.
- [ ] Exercise modulation overlays without changing the accepted base value.

Exit criteria:

- The minimum size has no clipped text, overlapping controls, ambiguous state, or unreachable action.
- Pointer, keyboard, exact-entry, preset, automation, and accessibility paths remain equivalent.
- Two simultaneous instances and repeated editor open and close preserve isolated state.

## Milestone 4: Deterministic Coverage

- [ ] Add DSP, parameter, gesture, rejection, automation, state, instance, lifecycle, and teardown tests.
- [ ] Add compact, standard, expanded, analyzer-state, selection, modulation, bypass, and disabled visual references.
- [ ] Add warm-render budgets for the linked response and active-spectrum scenes.
- [ ] Test malformed graph sources, point limits, non-finite values, invalid bindings, and stale callbacks.

Exit criteria:

- Every new reusable capability has unit, interaction, accessibility, lifecycle, visual, and performance evidence.
- Rendering and analyzer work remain bounded under repeated updates.
- Native adapter and macOS accessibility suites pass without lifecycle faults.

## Milestone 5: API Decisions and Release Gates

- [ ] Promote `GraphHandle` and graph layers only after Parametric EQ and Resonant Filter pass the same public contract and host checks.
- [ ] Audit analyzer documentation against its actual Channel Strip, Parametric EQ, and Resonant Filter consumers.
- [ ] Promote analyzer transport only if the shared contract, lifecycle tests, and current host checks justify supported status.
- [ ] Keep any single-consumer or incomplete surface experimental and name its precise blocker.
- [ ] Update the component reference, production plans, example lists, and status tables.

Release gates:

- [ ] `zig build test raw-api-abi validate-examples --summary all`
- [ ] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [ ] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [ ] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [ ] Serialized pluginval strictness 5 and strictness 10, stopping at the first unexpected exit and preserving its artifacts
- [ ] Focused REAPER walkthrough for rendering, every control, graph synchronization, spectrum activity, presets, resize cycles, two instances, and editor reopen

External checks remain pending when their environments are unavailable:

- Native Windows host interaction and Narrator
- X11 and Wayland host interaction
- AT-SPI names, roles, values, focus, and actions
- macOS movement between displays with different scale factors

## Completion Evidence

Record each committed milestone here with test counts, validator results, performance measurements, host observations, API decisions, and deferred external checks. Do not use pluginval as evidence of visual correctness.

### Milestone 1

- Added shared low-pass, high-pass, constant-peak band-pass, and notch biquad modes. Tests cover Butterworth cutoff level, passbands, stopbands, band-pass center gain, notch rejection, finite clamping, and bounded coefficient transitions.
- Added the public-API Resonant Filter bundle with seven stable parameters, native editor composition, `f32` and `f64` processing, 64-sample coefficient and scalar smoothing, sample-identical bypass, dry-mix convergence, and two-instance mode isolation.
- Registered native, Linux, Windows, Steinberg validator, and serialized pluginval steps through the standard example matrix.
- `zig build test --summary all`: 62/62 steps and 3,725/3,725 tests passed. Native adapter, macOS accessibility, and visual-regression suites passed.
- Raw ABI and entry-symbol checks passed. The Resonant Filter Steinberg validator passed 47/47 tests across single and double precision.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` bundles each passed 4/4 build steps.
- Latest shared warm-render measurements: visual suite 89.6 us, rotary 31.5 us, signal views 261.9 us, and linked EQ 230.6 us. Dedicated filter graph performance evidence begins in Milestone 4.
- Pluginval was not run in this milestone. It remains a serialized release gate after the production editor and graph are complete.
