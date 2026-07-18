# Production GUI Phase Plan

## Objective

Prove the component system with a production-style channel strip, then extend the public authoring API only where that editor supplies a concrete requirement. The completed component gallery remains the broad regression fixture. The channel strip becomes the second consumer for composition, telemetry, resources, and custom presentation.

The phase is complete when both editors use the public `@import("zig-vst3").vstgui` surface, the channel strip receives real per-instance processor telemetry, the requested production controls and graph foundation have deterministic coverage, and every locally executable platform gate passes.

## Constraints

- Plugin authors must not include adapter headers, construct VSTGUI objects, or call VST3 gesture functions for standard controls.
- Audio processing may perform bounded arithmetic and atomic publication only. It may not allocate, lock, call the operating system, draw, format text, or request repaint.
- Every component, controller, editor, telemetry source, gesture, and resource belongs to one plugin instance unless its data is immutable.
- Keyboard order follows visible reading order. Tooltips supplement labels and never carry essential information alone.
- New API stays experimental until the gallery and channel strip both use the same contract successfully.
- pluginval runs serially. Stop after the first macOS crash dialog and continue with non-pluginval gates.

## Milestone 1: Production Channel Strip

- [x] Add a `zig_vst3_channel_strip` example with gain, bypass, and mode parameters.
- [x] Create its editor entirely through the public `@import("zig-vst3").vstgui` API.
- [x] Include stereo level and gain-reduction meter declarations.
- [x] Use an explicit production theme and responsive layout distinct from the gallery.
- [x] Cover parameter processing, state, automation, independent instances, and editor creation.
- [x] Add the example to native validation and Linux and Windows cross-target bundles.

Exit criteria:

- The plugin processes audio and exposes a working multi-parameter editor without importing an adapter-internal Zig file.
- The editor declares every required channel-strip control and meter, even if live processor telemetry remains scheduled for Milestone 4.
- Unit tests, native adapter tests, visual tests, the Steinberg validator, and cross-target bundle builds pass.

Completion evidence:

- `examples/channel_strip_plugin.zig` is an external example module that imports `@import("zig-vst3").vstgui`; it cannot reach a relative adapter implementation file.
- The editor declares a rotary gain control, bypass toggle, mode dropdown, stereo meter, and gain-reduction meter through `createMultiViewWithSkin`. It selects the alternate theme and compact-strip layout while the gallery retains the default adaptive presentation.
- The processor implements clean, console-shaped, and limited audio paths with a -24 dB to +24 dB gain range and bypass. Unit tests cover DSP behavior, two independent editor views, and parameter isolation between two component instances.
- `zig build test` passes with the native unit, interaction, visual, and warm-render harness. The channel-strip bundle passes all 47 Steinberg validator tests. Linux and Windows example bundle sets cross-compile successfully.
- Meter declarations are present, but live processor snapshots remain intentionally deferred to Milestone 4. The current editor-local telemetry bank cannot receive processor data without violating instance ownership, so it is not represented as production-ready yet.

## Milestone 2: Reusable Composition and Styling

- [x] Add public editor, group, and section descriptions with bounded storage.
- [x] Support titled parameter groups and meter groups without exposing VSTGUI types.
- [x] Add a channel-strip layout that responds across the supported size range.
- [x] Add semantic theme overrides at editor and group scope.
- [x] Derive focus order from the composed visible tree.
- [x] Preserve the last accepted size when a host rejects resize.
- [x] Verify two simultaneous channel-strip editors do not share focus, layout, size, or theme state.

Exit criteria:

- The channel strip has scannable Input, Character, Output, and Meter sections instead of one flat control list.
- The gallery can express its Continuous, Discrete, and Telemetry groups through the same API.
- Grouping reduces visual search without adding extra interactive stops.

Completion evidence:

- Adapter ABI version 7 accepts up to eight ordered groups, an editor title, and semantic RGBA overrides for background, foreground, border, and accent. Unknown style bits, empty groups, gaps, overlaps, incomplete coverage, and out-of-range spans reject editor creation.
- The public `EditorDescription`, `Composition`, `Group`, `StyleOverride`, and `createEditor` declarations contain no VSTGUI types. The adapter copies group titles and style data into each editor.
- Both the component gallery and channel strip use `createEditor`. The gallery declares Continuous, Discrete, and Telemetry groups. The channel strip declares Input, Character, and Output groups with distinct accents.
- Grouped editors use one column below 620 logical units and two columns at wider sizes. Headings are semantic groups rather than focus stops. Parameter controls retain declaration order, exact fields follow their controls, and resize remains the final action.
- Native tests cover valid grouped construction, independent grouped and ungrouped instances, ordered focus, responsive resize, style masks, and rejected group descriptions. Channel-strip tests resize one of two simultaneous editor views and verify the second remains at its original size.

## Milestone 3: Production Parameter Controls

- [x] Add bipolar slider presentation with a visible center and symmetric keyboard behavior.
- [x] Add decibel presentation with plain-value formatting and a useful perceptual scale.
- [x] Add a distinct modulation-value overlay that does not overwrite the base value.
- [x] Add concise tooltips for controls whose labels do not explain interaction or units.
- [x] Preserve exact entry, default reset, context menu, automation playback, and gesture ordering.
- [x] Add deterministic state and interaction references for every new presentation.

Exit criteria:

- Base, modulated, default, and current values remain visually distinguishable.
- A user can identify zero, unity, and the active value without moving the control.
- Tooltips are optional guidance, not the only source of a control name or value.

Completion evidence:

- Adapter ABI version 8 adds bipolar and decibel presentation kinds plus optional tooltip and modulation metadata. Unknown presentation values reject editor creation.
- Centered presentations draw a visible zero or unity line and fill symmetrically from that line to the base value. Their arrow-key path remains the standard host begin, perform, end gesture, and opposite arrow steps return to the starting value.
- Decibel normalization remains linear in plain dB. Equal travel therefore produces equal dB steps and multiplicative gain ratios without introducing a second hidden value mapping.
- A separate outlined marker displays the modulated normalized value. `setModulation` invalidates only the slider and never changes the base parameter model or emits a host gesture.
- Tooltips use VSTGUI's delayed platform tooltip support and also populate the semantic control description. The gallery and channel strip retain visible labels and exact values without relying on hover.
- The channel strip uses the decibel presentation and a modulation marker for Gain. The gallery uses the bipolar presentation and modulation marker as a regression fixture. A committed `production-controls.png` reference covers negative, centered, positive, and modulated states.
- Native tests cover symmetric keyboard gestures, tooltip semantics, modulation routing, invalid presentation rejection, exact entry, default reset, context menus, host updates, and state-specific drawing. The warm-render benchmark includes the same slider rendering path.

## Milestone 4: Production Telemetry and Meter Interaction

- [x] Connect processor telemetry to each editor through a per-instance bounded snapshot contract.
- [x] Publish stereo peak and gain reduction from the channel-strip processor without locks or allocation.
- [x] Add decibel meter scales and clipping indicators.
- [x] Add resettable held peaks with keyboard and pointer operation.
- [x] Coalesce repaint work and stop publication when no editor is open.
- [x] Test open, close, reopen, multiple editors, bounded source handling, and retained-source teardown.
- [x] Promote the shared meter and telemetry API only after both editors use it.

Exit criteria:

- Channel-strip meters respond to processed audio and remain isolated between plugin instances.
- Peak reset is an explicit accessible action and never changes an audio parameter.
- The audio-thread path has bounded atomic work and no GUI dependency.

Completion evidence:

- `SimpleStereoEffect` exposes a toolkit-neutral telemetry source only when its processor implements the telemetry contract. `ReflectedEditController` obtains that source from its connected component and each editor retains its own source reference through teardown.
- The channel strip publishes left peak, right peak, and gain reduction through a four-operation bounded path: one activity check and three atomic stores per active block. The component gallery uses the same connection and activity contract for its four meter sources.
- Meter polling remains fixed at 33 milliseconds. Ballistics invalidate only after a displayed value changes, and both producers skip editor-only analysis while no view is attached.
- Native interaction tests cover held-peak reset, invalid meter indices, accessible reset guidance, focus order, and meter ballistics. Zig tests cover two open views, close without underflow, inactive publication, source bounds, component isolation, disconnect, and a source retained past connection teardown.
- The meter visual reference covers peak and stereo dB ticks, reduction ticks, peak holds, and the clipping indicator. The warm-render result remains below the 300 microsecond budget.
- Zig tests, raw ABI checks, all native Steinberg validator runs, adapter interaction and visual tests, and the Linux and Windows example bundle cross-builds pass. Native Windows, X11, and Wayland host interaction remain deferred to their platform environments.
- The custom telemetry interface is an in-process connection-point extension. A host that isolates the component behind a proxy may not expose it; the editor remains functional with zero-valued meters. A future cross-process transport can implement the same editor-facing source contract.

## Milestone 5: Toolkit-neutral Graph Foundation

- [x] Define bounded graph series, axes, ranges, and style roles without toolkit types.
- [x] Support static transfer functions and envelopes from fixed point storage.
- [x] Support waveform and spectrum snapshots through bounded latest-value transport.
- [x] Add activity-driven invalidation and an explicit maximum update rate.
- [x] Render a channel-strip transfer curve and a gallery waveform fixture.
- [x] Add empty, invalid-data, clipped-data, resize, scale, and visual-regression tests.

Exit criteria:

- Static graphs perform no continuous repaint.
- Dynamic graph publication is bounded and may drop visualization data instead of waiting.
- A custom graph reuses theme resolution, layout, semantic metadata, and editor lifecycle.

Completion evidence:

- `gui_graph` defines finite points, validated linear, logarithmic, and decibel axes, fixed series, style roles, and a fixed-capacity atomic snapshot. Snapshot reads retry at most three times. Producers drop inactive, invalid, or oversized visualization frames. Readers abandon contended frames instead of waiting.
- `EditorDescription.graphs` and `Group` graph ranges expose composition without VSTGUI types. Native descriptions copy titles, labels, and static points per editor instance.
- Static graphs allocate no timer. Dynamic graphs require a 1 to 60 Hz cap, poll only while the editor is open, and invalidate only when their bounded point set changes.
- The channel strip renders a 33-point console transfer curve. The component gallery publishes a 64-point waveform snapshot from processed audio through the same per-instance connection used by meters.
- Native tests cover empty graphs, invalid ranges and points, clipped coordinates, static versus dynamic scheduling, source refresh, resize, scale, semantics, and ABI limits. The graph visual reference covers primary, modulation, logarithmic, decibel, and empty-state rendering.
- The warm-render benchmark includes controls, a meter, and a graph and remains below the 300 microsecond budget.
- Zig tests, raw ABI checks, every native Steinberg validator run, native adapter and visual tests, and Linux and Windows example bundle cross-builds pass. Native Windows, X11, and Wayland graph interaction checks remain deferred to their platform environments.

## Milestone 6: Native Accessibility Bridges

- [x] Map toolkit-neutral roles, names, descriptions, values, ranges, and state changes to the best locally available VSTGUI or platform API.
- [x] Implement and test the macOS bridge when the pinned VSTGUI and local SDK expose a viable route.
- [x] Implement compile-time Windows bridge support when it can be cross-compiled without a native host.
- [x] Preserve keyboard access and visible focus when no native bridge exists.
- [x] Document exact VoiceOver, Narrator, X11, and Wayland verification status without claiming untested support.

Exit criteria:

- Locally implementable platform semantics are connected without changing component behavior.
- Unsupported native exposure remains an explicit release limitation rather than a silent fallback claim.

Completion evidence:

- Each editor owns a native bridge that observes existing toolkit-neutral nodes only while its native frame is open. Close detaches the native hierarchy and unregisters every observer before VSTGUI views are released.
- The AppKit bridge exposes an `NSAccessibilityElement` hierarchy on VSTGUI's child `NSView`, maps all current component roles and semantic properties, derives bounds from live view layout, and posts value, focus, semantic, and layout notifications.
- The AppKit integration test covers sliders, exact text fields, toggles, choices, meters, graphs, buttons, value and checked-state changes, focus, resize geometry, and teardown.
- The Windows UI Automation bridge exposes a fragment tree through `WM_GETOBJECT`, maps semantic properties, bounds, and focus, and raises property, focus, and structure events. The source cross-compiles for `x86_64-windows-gnu` in `scripts/build_vstgui.sh`.
- Existing keyboard focus order, arrow-key editing, exact entry, meter peak reset, and visible focus rendering remain unchanged. Linux retains these paths without claiming an AT-SPI bridge.
- VoiceOver navigation is not manually verified. Narrator, X11 AT-SPI, and Wayland AT-SPI verification require native platform hosts and remain pending.
- Native adapter, AppKit accessibility, interaction, visual, and warm-render tests pass. Zig tests, raw ABI checks, every Steinberg validator run, and Linux and Windows example bundle cross-builds also pass.

## Milestone 7: Stability Review and Final Validation

- [x] Document the channel-strip author workflow and each promoted API.
- [x] Keep single-consumer and platform-incomplete capabilities marked experimental.
- [x] Run native unit, interaction, accessibility, visual, and performance tests.
- [x] Run Zig tests, raw ABI checks, and every Steinberg example validator.
- [x] Cross-build all example bundles for Linux and Windows.
- [x] Diagnose pluginval serially and stop after the first crash dialog.
- [x] Record manual macOS and unavailable native Windows, X11, and Wayland host checks.
- [x] Confirm the worktree contains no uncommitted milestone work.

Exit criteria:

- Both production and gallery editors compile exclusively against documented public declarations.
- Every promoted API has two real consumers and deterministic coverage.
- Every local gate passes, and external deferrals state the missing environment and required future check.

Completion evidence:

- `zig-vst3/src/vstgui.zig` is the public authoring facade. The package root exports it as `@import("zig-vst3").vstgui`, and the component gallery compiles against the same facade instead of importing the implementation file.
- The channel-strip workflow documents parameter, meter, graph, grouping, telemetry, theme, and validation responsibilities. The API status keeps assets, fonts, custom drawing, bipolar and decibel variants, graph source modes, and native accessibility bridges experimental where they have one consumer or incomplete platform verification.
- Native unit, interaction, AppKit accessibility, visual-regression, and warm-render tests pass. The final warm-render average remained below 40 microseconds against a 300 microsecond budget.
- Zig tests, raw ABI checks, every Steinberg example validator, and Linux and Windows example bundle cross-builds pass.
- One isolated pluginval 1.0.4 channel-strip run passed strictness 5, including editor open, open while processing, automation, and editor automation. Earlier crash reports abort in AppKit application startup before plugin loading and correlate with concurrent aggregate invocations. No additional pluginval processes were launched after the isolated pass.
- Prior manual REAPER checks cover parameter editing, resize, focus, keyboard adjustment, exact entry, reset gestures, instance isolation, automation, and state restoration on macOS. Manual graph rendering and VoiceOver remain pending. Native Narrator, X11, Wayland, and AT-SPI host checks remain pending because those environments are unavailable locally.
- The final milestone commit leaves no uncommitted implementation or documentation work.

## Validation Commands

Run after each milestone as applicable:

```sh
scripts/build_vstgui.sh
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build test raw-api-abi validate-examples
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu
```

Run pluginval examples one at a time only after the other gates pass. Do not use the aggregate parallel target on macOS while its crash behavior remains unresolved.

Also verify:

- `git diff --check`
- No em dashes in user-facing project documentation
- No continuous repaint for static components
- No audio-thread allocation, lock, operating-system call, formatting, or unbounded work
- No shared mutable editor, telemetry, parameter, focus, layout, or resource state
- No toolkit-specific type in toolkit-neutral declarations
