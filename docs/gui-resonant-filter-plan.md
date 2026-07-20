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

- [x] Add a calculated magnitude-response curve over the live output spectrum.
- [x] Bind one graph handle to cutoff and resonance through standard grouped gestures.
- [x] Keep graph motion synchronized with controls, host automation, exact entry, presets, and rejected edits.
- [x] Provide explicit analyzer-off, waiting-for-signal, active, and bypass states.
- [x] Keep all sources within the existing graph point and analyzer transport limits.

Exit criteria:

- Pointer and keyboard handle edits update exactly Cutoff and Resonance.
- Control and host changes move the handle without beginning a graph gesture.
- Rejected graph edits restore both axes and every linked view.
- Closing the last editor stops analyzer production and repaint activity.

## Milestone 3: Production Editor

- [x] Group Filter controls separately from Drive, Mix, Output, and Bypass.
- [x] Add a compact layout with deterministic compact, expanded, manual shrink, and manual grow round trips.
- [x] Add useful presets for each filter mode and preserve accepted state through editor reopen.
- [x] Support pointer editing, fine adjustment, arrow keys, laptop-safe limits, Command-click reset, exact entry, context menus, tooltips, and visible focus.
- [x] Expose toolkit-neutral names, roles, values, ranges, selection, adjustment, enablement, and bypass semantics.
- [x] Exercise modulation overlays without changing the accepted base value.

Exit criteria:

- The minimum size has no clipped text, overlapping controls, ambiguous state, or unreachable action.
- Pointer, keyboard, exact-entry, preset, automation, and accessibility paths remain equivalent.
- Two simultaneous instances and repeated editor open and close preserve isolated state.

## Milestone 4: Deterministic Coverage

- [x] Add DSP, parameter, gesture, rejection, automation, state, instance, lifecycle, and teardown tests.
- [x] Add compact, standard, expanded, analyzer-state, selection, modulation, bypass, and disabled visual references.
- [x] Add warm-render budgets for the linked response and active-spectrum scenes.
- [x] Test malformed graph sources, point limits, non-finite values, invalid bindings, and stale callbacks.

Exit criteria:

- Every new reusable capability has unit, interaction, accessibility, lifecycle, visual, and performance evidence.
- Rendering and analyzer work remain bounded under repeated updates.
- Native adapter and macOS accessibility suites pass without lifecycle faults.

## Milestone 5: API Decisions and Release Gates

- [x] Promote `GraphHandle` and graph layers only after Parametric EQ and Resonant Filter pass the same public contract and host checks.
- [x] Audit analyzer documentation against its actual Channel Strip, Parametric EQ, and Resonant Filter consumers.
- [x] Promote analyzer transport only if the shared contract, lifecycle tests, and current host checks justify supported status.
- [x] Keep any single-consumer or incomplete surface experimental and name its precise blocker.
- [x] Update the component reference, production plans, example lists, and status tables.

Release gates:

- [x] `zig build test raw-api-abi validate-examples --summary all`
- [x] Native adapter, macOS accessibility, visual-regression, and warm-render tests
- [x] `zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu --summary all`
- [x] `zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu --summary all`
- [x] Serialized pluginval strictness 5 and strictness 10, stopping at the first unexpected exit and preserving its artifacts
- [x] Focused REAPER walkthrough for rendering, every control, graph synchronization, spectrum activity, presets, resize cycles, two instances, and editor reopen

Focused REAPER walkthrough:

- [x] Confirm the default editor renders without clipped labels, overlap, excess space, or ambiguous selection.
- [x] Confirm Cutoff and Resonance stay synchronized between rotary controls, exact entry, and the graph handle.
- [x] Confirm graph dragging changes both parameters and the calculated response follows the accepted values.
- [x] Confirm Low Pass, High Pass, Band Pass, and Notch have visible selected states and distinct responses.
- [x] Confirm Drive, Mix, Output, Bypass, reset, fine adjustment, and keyboard editing.
- [x] Confirm the spectrum enters waiting, active, and bypass states while audio runs.
- [x] Confirm all four presets load visibly and restore one accepted parameter state.
- [x] Confirm compact, expanded, manual shrink, and manual grow round trips preserve usable layouts.
- [x] Confirm two instances remain independent and editor close and reopen restores accepted state.

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

### Milestones 2 and 3

- Added a 97-point calculated response that uses the biquad's complex response for correct wet and dry summation. Bypass produces a flat 0 dB response and Output shifts the accepted curve.
- Added one linked handle for Cutoff and Resonance plus a 64-bin live output spectrum. Spectrum publication remains fixed-capacity and stops when the last editor closes.
- Added a parameter workspace with Response, Filter, and Color groups. Mode uses a four-choice segmented control so selection remains visible without consulting a value field.
- Added Smooth Low Pass, Resonant High Pass, Band Focus, and Notch Cleanup presets. Each preset edits all seven parameters in one host group with rollback through the shared public contract.
- Added deterministic response, preset gesture, analyzer activity, editor-size, editor-state isolation, processor isolation, bypass, and dry-mix tests. Existing native graph tests cover grouped pointer and keyboard edits, automation updates, rejection rollback, accessibility adjustment, selection, and teardown for the same handle contract.
- `zig build test --summary all`: 62/62 steps and 3,730/3,730 tests passed. Raw ABI checks and the Resonant Filter's 47/47 Steinberg tests passed.
- Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` bundles each passed 4/4 build steps.
- Manual REAPER checks and dedicated filter visual references remain required before the responsive-editor exit criteria are accepted.

### Milestone 4

- Added dedicated compact, standard, expanded, and linked response references for Resonant Filter. The response reference includes the selected Cutoff and Resonance handle over an active 64-bin spectrum. Shared analyzer-state, modulation, bypass, disabled, malformed-source, point-limit, non-finite-value, invalid-binding, rejection, and stale-callback coverage exercises the same public graph and parameter contracts.
- Corrected segmented enums to use their own selected segment as the value presentation. They no longer reserve an unrelated exact-value field. Enum captions now convert identifiers such as `low_pass` to `Low Pass`, retain an inner text margin, and receive additional workspace width where needed.
- Added native assertions for the four readable segment captions, persistent selected state, the absence of a redundant value focus target, and the smaller valid compact constraint.
- Native adapter, macOS accessibility, and visual-regression suites passed. `zig build test --summary all` passed 62/62 steps and 3,730/3,730 tests.
- The dedicated resonant-filter warm-render scene measured 131.8 microseconds against a 300 microsecond budget. The same run measured 241.5 microseconds for shared signal views and 210.1 microseconds for the linked EQ scene.
- Manual REAPER checks remain required before the responsive-editor and host interaction exit criteria are accepted.

### Milestone 5 Release Gates

- `zig build test raw-api-abi validate-examples --summary all` passed 223/223 steps and 3,730/3,730 tests. This includes the native adapter, macOS accessibility bridge, visual regression, entry-symbol isolation, every raw ABI harness, and all 13 Steinberg example validators. Resonant Filter passed all 47 Steinberg tests.
- The Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` example bundle matrices each passed 41/41 steps, including Resonant Filter.
- The serialized pluginval strictness 5 matrix passed all 13 examples in 56/56 steps without an unexpected exit or crash dialog.
- The serialized pluginval strictness 10 matrix passed all 13 examples in 56/56 steps. It covered non-releasing processing, state restoration, background-thread state, parameter thread safety, and fuzzed parameters.
- Resonant Filter pluginval artifacts are preserved at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_resonant_filter-strictness-5-20260719-220401-86329` and `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_resonant_filter-strictness-10-20260719-220744-92378`.
- The accepted REAPER candidate has SHA-256 `1ce54a6620aa0a578fd85cfb34870ff7d9c2f5c7e3870902c6429db935c91fb4`.
- The analyzer documentation identifies Channel Strip, Parametric EQ, and Resonant Filter as independent production consumers of the same fixed-capacity, activity-gated transport.
- Parametric EQ and Resonant Filter declare handles and layers through the same public `Graph`, `GraphHandle`, and `GraphLayer` fields. Both use controller-driven parameter curves, a dynamic spectrum layer, selection state, and standard parameter gestures. Channel Strip, Parametric EQ, and Resonant Filter all use `SpectrumAnalyzer(128)` through the same editor-open, editor-close, audio-push, and snapshot-read lifecycle.
- Single-consumer and incomplete APIs remain experimental with explicit blockers in the component reference. Future modulation component types and GPU-backed custom views are not public APIs and have no production consumer. A GPU path also requires profiling evidence.
- The initial REAPER analyzer check exposed two transport lifecycle defects. Editors now retry telemetry discovery after late component connection, and graph-only processors expose the telemetry interface without requiring a scalar meter callback. Regression tests cover both cases.
- The focused REAPER walkthrough passed on macOS arm64 in REAPER 7.36. It covered default rendering, every control, direct graph editing, four filter modes, exact entry, keyboard and reset paths, live and bypassed spectrum states, sample-identical bypass, all presets, compact and expanded layouts, manual resize cycles, two independent instances, and editor close and reopen restoration.
- `GraphHandle`, `GraphLayer`, parameter-driven curves, mixed-source layers, `SpectrumAnalyzer`, and analyzer transport move to supported status. Their production consumers share the public declaration, bounded transport, lifecycle, interaction, accessibility, visual, performance, and host contracts.
- Final local validation passed 223/223 build steps and 3,747/3,747 tests, including all raw ABI checks, native adapter tests, macOS accessibility tests, visual regression, and all 13 Steinberg validators. Resonant Filter passed 47/47 validator tests. The final warm render measured 142.8 microseconds against its 300 microsecond budget.
- The final Linux `aarch64-linux-gnu` and Windows `x86_64-windows-gnu` bundle matrices each passed 41/41 steps.
- The final serialized pluginval strictness 5 run stopped on Gain with exit 134, as required by the stop-on-first-exit policy. The macOS crash report shows pluginval aborting in AppKit application startup before any plugin image loaded. Strictness 10 was not launched. The empty run artifact is preserved at `/var/folders/2r/700z0d517dg3yqy2_px199p00000gn/T/zig-vst3-pluginval/zig_vst3_gain-strictness-5-20260720-073810-66215`, and the crash report is preserved at `~/Library/Logs/DiagnosticReports/pluginval-2026-07-20-073817.ips`. Earlier serialized strictness 5 and 10 matrices passed all 13 examples, but current-build pluginval coverage remains unavailable because the application cannot start reliably in this environment.

## Current Completion Audit

| Requirement | Evidence | Status |
| --- | --- | --- |
| Filter DSP and parameters | Four modes, seven parameters, `f32` and `f64` tests, smoothing, sample-identical bypass, raw ABI, and 47/47 Steinberg tests | Complete locally |
| Linked editing | Parametric EQ and Resonant Filter use the public handle and layer contract; deterministic interaction, accessibility, visual, and REAPER checks pass | Supported |
| Analyzer transport | Three production consumers, fixed-capacity transport, lifecycle and isolation tests, bounded warm rendering, and active REAPER signal | Supported |
| Responsive editor | Compact, standard, expanded, manual shrink, manual grow, scrolling, and state restoration pass in tests and REAPER | Complete on macOS arm64 |
| Cross-target bundles | Linux and Windows matrices each pass 41/41 steps | Complete locally; native host checks remain external |
| Pluginval | Earlier strictness 5 and 10 matrices passed; final rerun aborted in AppKit before loading a plugin | Current-build coverage unavailable |
| External accessibility and hosts | Toolkit-neutral semantics and automated macOS bridge pass | VoiceOver, Narrator, AT-SPI, native Windows, X11, and Wayland remain pending |
