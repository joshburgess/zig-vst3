# Plugin GUI Component System Plan

This plan extends the host integration work in [gui-plan.md](gui-plan.md). It builds a reusable, customizable component layer for plugin editors without turning `zig-vst3` into a general desktop GUI toolkit.

The immediate target is a multi-parameter component gallery that runs through the existing VSTGUI adapter. The broader target is NIH-plug-level editor ergonomics with the plugin-focused parts of third-party framework's component and LookAndFeel model.

## Current Position

The framework already provides:

- Per-instance editor and controller state
- Parameter metadata, formatting, parsing, normalization, and quantization
- Complete begin, perform, and end automation gestures
- Host-to-editor parameter notifications
- Host parameter context menus
- Resize, scale, focus, and lifecycle handling
- Scalar snapshots and bounded telemetry queues
- Native VSTGUI attachment on macOS, Windows, X11, and Wayland

The visible adapter remains a hard-coded single-parameter editor in `gui-adapters/vstgui/zig_vstgui_adapter.cpp`. Control construction, layout, styling, parameter behavior, and editor composition are coupled in that file. Adding controls directly to that implementation would produce a collection of one-off widgets instead of a component library.

## Design Targets

### NIH-plug parity

Match the useful shape of NIH-plug's GUI support:

- Keep editor lifecycle and parameter semantics independent of the rendering toolkit.
- Let toolkit adapters provide their own component implementations.
- Provide parameter-aware sliders, buttons, meters, generic panels, and resize controls.
- Notify open editors about host value changes and bulk state changes.
- Keep editor size and scale in logical coordinates.

NIH-plug is a framework and adapter reference, not a complete widget toolkit. Its VIZIA adapter currently includes a generic UI, parameter base, parameter button, parameter slider, peak meter, and resize handle.

### third-party framework-style customization

Adopt the plugin-relevant parts of third-party framework's GUI design:

- A component tree with bounds, visibility, enabled state, child ownership, focus, input, and invalidation
- A separate theme and drawing policy comparable to third-party framework LookAndFeel
- Standard controls that retain behavior when their appearance changes
- Per-editor, per-container, and per-control style overrides
- Semantic accessibility roles, names, values, and states

Do not reproduce third-party framework's application windows, document model, networking, media, or other general desktop facilities.

## Architecture

```text
Plugin editor declaration
  |
  v
VSTGUI editor builder and component tree
  |
  +--> layout and focus order
  +--> theme and component styles
  +--> parameter-aware controls
  +--> telemetry controls
  |
  v
zig-vst3-plugin GUI context
  |
  +--> parameter attachments and gestures
  +--> formatting, parsing, and metadata
  +--> resize and host context menus
  |
  v
VST3 host
```

The toolkit-neutral layer continues to own parameter semantics and host communication. The VSTGUI package owns the component tree, layout, input routing, drawing, and toolkit resources. Toolkit-specific types must not enter `zig-vst3-plugin`.

## Component Contract

Every visible component needs:

- Logical bounds
- Visible and enabled states
- Optional focus participation and deterministic focus order
- Invalidation when visual state changes
- Pointer, wheel, and keyboard event handling where applicable
- Semantic name, description, role, value, and state
- Theme lookup with local overrides

Every parameter control also needs:

- One `ParameterAttachment`
- Reflected name, units, default, step count, and text conversion
- One active gesture at most
- Host automation updates without creating a new gesture
- Default reset
- Fine adjustment
- Exact entry when the value is numeric
- Host context menu access
- Normal, hovered, pressed, focused, disabled, and editing visual states

## Theme and Drawing Model

Use semantic tokens instead of colors and dimensions embedded in controls:

```zig
const theme = Theme{
    .colors = .{
        .surface = rgb(22, 25, 31),
        .surface_raised = rgb(37, 42, 51),
        .control_track = rgb(73, 82, 97),
        .control_fill = rgb(17, 113, 91),
        .text_primary = rgb(238, 241, 246),
        .text_secondary = rgb(157, 166, 181),
        .focus_ring = rgb(89, 201, 165),
    },
    .spacing = .{},
    .typography = .{},
    .radii = .{},
    .control_metrics = .{},
};
```

Resolve styles in this order:

1. Library defaults
2. Editor theme
3. Container override
4. Component-type override
5. Component-instance override
6. Interaction-state override

Appearance changes must not replace parameter behavior. Advanced editors may provide component-specific drawing callbacks after the standard style path works.

## Author-Facing API Direction

The final spelling should follow implementation experience from the gallery. The intended shape is a declarative, adapter-specific builder:

```zig
var editor = try vstgui.Editor.init(allocator, .{
    .size = .{ .width = 640, .height = 420 },
    .theme = studio_theme,
});

try editor.add(.knob(.gain, .{
    .label = "Gain",
    .layout = .{ .column = 0, .row = 0 },
}));

try editor.add(.toggle(.bypass, .{
    .label = "Bypass",
    .layout = .{ .column = 1, .row = 0 },
}));

try editor.add(.choice(.mode, .{
    .label = "Mode",
    .layout = .{ .column = 0, .row = 1, .column_span = 2 },
}));
```

Do not freeze this public API until the gallery uses every core parameter kind and survives a second editor design.

## Work Plan

Each milestone must leave the validator, pluginval, existing examples, and cross-target bundles passing. Real-host rows remain release evidence, but unavailable platform checks do not block component work that can be validated locally.

### Milestone 1: Extract the Component Foundation

- [x] Split the VSTGUI adapter into lifecycle, component, control, theme, and editor-composition units.
- [x] Extract the current slider and numeric field from `ZigVstguiEditor`.
- [x] Define component bounds, visibility, enabled state, focus participation, and invalidation.
- [x] Define shared parameter-control gesture and host-update behavior.
- [x] Preserve the current gain editor appearance and confirmed interactions.
- [x] Add unit tests for state transitions and gesture ownership.

Exit criteria:

- The gain editor is composed from reusable components.
- No control duplicates begin, perform, end, reset, parse, or host-update logic.
- The existing REAPER behavior remains unchanged.

Completion evidence:

- `zig_vstgui_adapter.cpp` now contains only the public C ABI. Editor composition, platform attachment, component state, parameter controls, profiling, and theme values live in separate units.
- `ParameterControlModel` owns accepted values and gesture lifetime. `ParameterControl` binds that model to the reusable slider and numeric field.
- Native adapter tests cover visual-state precedence, single-gesture ownership, rejected values, clamping, idempotent completion, and teardown during an active gesture.
- Unit tests, raw ABI checks, all example validators, pluginval editor and automation checks, and Linux and Windows cross-target bundles pass.

### Milestone 2: Add Theme and Style Resolution

- [x] Define semantic color, spacing, typography, radius, and control-metric tokens.
- [x] Move all current literals into the default theme.
- [x] Add editor-wide and per-component overrides.
- [x] Define styles for normal, hovered, pressed, focused, disabled, and editing states.
- [x] Add one alternate theme that changes appearance without changing component code.

Exit criteria:

- The gain editor contains no embedded presentation colors or sizes outside layout specifications.
- The default and alternate themes render the same component tree.

Completion evidence:

- `Theme` groups semantic colors, spacing, typography, radii, and control metrics. Editor composition and controls resolve presentation through `ThemeResolver`.
- Resolution tests prove editor overrides, component overrides, and interaction-state overrides apply in the documented order.
- The slider resolves normal, hovered, pressed, focused, disabled, and editing states at draw time.
- The alternate theme changes the full palette while retaining the same component styles, metrics, editor composition, and behavior.
- The default and alternate themes pass native adapter tests and pluginval editor checks. Unit tests, raw ABI checks, all example validators, the full default-theme pluginval suite, and Linux and Windows cross-target bundles pass.

### Milestone 3: Support Multi-parameter Editors

- [x] Replace the single-parameter C ABI creation contract with a bounded multi-parameter description or builder.
- [x] Route host updates to the matching attachment and component.
- [x] Cancel all active gestures safely during detach and destruction.
- [x] Preserve per-instance isolation with multiple parameters and multiple editors.
- [x] Support bulk refresh after project or preset state restoration.

Exit criteria:

- One editor binds continuous, integer, boolean, and enum parameters at the same time.
- Host automation updates only the matching controls.
- Two gallery instances remain isolated.

Completion evidence:

- Adapter ABI version 2 accepts up to 64 parameter descriptions and addresses host updates by parameter ID.
- The editor-smoke integration binds float, integer, boolean, and enum parameters in one editor. VST3 validation reports all four reflected parameter kinds.
- Native routing tests verify matching-control updates, duplicate-ID rejection, two-editor isolation, and all-or-nothing bulk refresh.
- Closing an attached editor clears every control and ends its active gesture. Destruction also cancels gestures for editors that were never attached or already detached.
- The editor-smoke plugin passes pluginval editor, processing, state, automation, and editor-automation checks. Unit tests, raw ABI checks, all example validators, and Linux and Windows cross-target bundles pass.

### Milestone 4: Build Core Parameter Components

Implement controls in this order:

- [x] Linear slider
- [x] Numeric value field
- [x] Rotary knob
- [x] Toggle button
- [x] Enum dropdown
- [x] Segmented enum control
- [x] Parameter label with units
- [x] Resize handle

Each interactive control must pass:

- [x] Pointer interaction
- [x] Wheel interaction where appropriate
- [x] Keyboard interaction
- [x] Fine adjustment
- [x] Exact entry where appropriate
- [x] Default reset
- [x] Host context menu
- [x] Correct automation gesture boundaries
- [x] Host automation playback
- [x] Disabled-state behavior
- [x] Visible focus

Exit criteria:

- The component gallery demonstrates all four reflected parameter kinds.
- A plugin author does not write custom gesture or normalization code to use a standard control.

Completion evidence:

- Adapter ABI version 3 adds an explicit presentation kind without coupling widget choice to reflected parameter type. Existing single-parameter declarations default to a linear slider.
- The shared parameter control builds sliders, knobs, toggles, dropdowns, and segmented choices from one attachment model. Numeric entry, formatted labels, units, default reset, fine adjustment, focus, disabled state, host updates, and automation gestures remain shared behavior.
- Right-click events request the host parameter context menu through `IComponentHandler3`. A draggable corner handle and the existing compact/expand action use the same bounded host resize callback.
- Native tests cover gesture boundaries, stepped quantization, rejected edits, host updates, context-menu routing, bulk refresh, and instance isolation. The editor-smoke fixture constructs the knob, toggle, dropdown, and segmented variants together.
- The typed gallery passes VST3 validation and pluginval editor, processing, state, automation, and editor-automation checks.

### Milestone 5: Add Layout and Focus Navigation

- [ ] Add fixed bounds for art-directed interfaces.
- [ ] Add row and column stacks.
- [ ] Add grid layout with spans.
- [ ] Add padding, gap, alignment, minimum size, and flexible growth.
- [ ] Add compact and expanded layout breakpoints.
- [ ] Add deterministic Tab and Shift+Tab traversal.
- [ ] Keep layout coordinates logical and scale-independent.

Exit criteria:

- The gallery remains usable at its minimum and maximum supported sizes.
- Resize does not overlap, clip, or strand interactive controls.
- Focus traversal follows the visible reading order.

### Milestone 6: Add Accessibility Semantics

- [ ] Define semantic roles for sliders, buttons, toggles, choices, text fields, meters, and groups.
- [ ] Expose accessible name, description, value text, range, and state.
- [ ] Notify the platform accessibility layer when values or states change.
- [ ] Ensure custom drawing does not remove native keyboard or accessibility behavior.
- [ ] Document unsupported VSTGUI or platform accessibility paths explicitly.

Exit criteria:

- Every gallery control has a semantic name, role, value, and state.
- Focus and value changes are observable through the platform accessibility API where VSTGUI supports it.

### Milestone 7: Add Audio Visualization Components

- [ ] Add a scalar peak meter using `gui_telemetry.ScalarSnapshot`.
- [ ] Add peak hold and decay on the GUI thread.
- [ ] Stop meter production and repaint requests when the editor closes.
- [ ] Add stereo and gain-reduction meter variants.
- [ ] Add an analyzer component only after defining a representative plugin and data rate.

Exit criteria:

- Meter updates allocate and lock nothing on the audio thread.
- Overflow or coalescing affects only visual freshness.
- Static editors retain no continuous repaint loop.

### Milestone 8: Add Asset and Custom Drawing Support

- [ ] Load bundled bitmap and SVG assets with explicit scale behavior.
- [ ] Support custom fonts with documented licensing and fallback behavior.
- [ ] Add component-specific drawing callbacks.
- [ ] Add filmstrip or sprite controls only if a reference design requires them.
- [ ] Define resource ownership and teardown across editor recreation.

Exit criteria:

- A plugin can create an art-directed skin without replacing parameter attachment behavior.
- Missing assets fail visibly and do not create blank interactive regions.

### Milestone 9: Visual and Interaction Regression Tests

- [ ] Make the gallery render deterministically at fixed logical sizes.
- [ ] Capture reference images for default, hover, pressed, focused, disabled, and editing states where automation permits.
- [ ] Add image comparison with an explicit tolerance.
- [ ] Add scripted gesture, keyboard, resize, and host-update tests.
- [ ] Keep performance profiling available for static controls and active meters.

Exit criteria:

- Component appearance changes produce reviewable image diffs.
- Interaction regressions fail before a real-host test.
- Warm frame cost stays within the budget recorded in `docs/gui-baseline.md`.

### Milestone 10: Author Documentation and Stability Review

- [ ] Document the component gallery and one production-style editor.
- [ ] Document theming, layout, parameter binding, telemetry, and custom drawing.
- [ ] Mark experimental APIs clearly.
- [ ] Test the API against a second editor with a different layout and theme.
- [ ] Stabilize only the pieces used successfully by both editors.

Exit criteria:

- A plugin author can build a multi-parameter editor without editing the adapter internals.
- Standard components require no direct VST3 calls.
- Custom components can reuse standard parameter behavior and theme resolution.

## Component Gallery

The gallery is a real plugin example, not a standalone mockup. It should contain:

| Area | Components | Data source |
| --- | --- | --- |
| Continuous | Linear slider, rotary knob, numeric field | Float parameter |
| Discrete | Toggle, dropdown, segmented control | Boolean and enum parameters |
| Stepped | Slider or stepper with exact value | Integer parameter |
| Telemetry | Peak meter | Scalar snapshot |
| Structure | Labels, groups, row, grid | Editor model |
| Lifecycle | Resize handle and breakpoint change | Host resize contract |

Keep one primary action or value per visual group. Large flat panels make control relationships harder to scan, so group the gallery by continuous, discrete, and telemetry behavior.

## Deeper Capabilities After the Core Library

Add these only when a reference plugin needs them:

- XY pad and multi-parameter gestures
- Modulation value overlays distinct from base parameter values
- Transfer-function and envelope editors
- Waveform and spectrum views
- Piano keyboard and step sequencer
- Tooltips, popovers, and richer host menus
- Preset browser and editor-persistent non-parameter state
- Drag-and-drop files
- Animation timelines with activity-based repaint scheduling
- GPU-backed custom views after profiling demonstrates a need

## Validation Gates

Run for each milestone:

```sh
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build test raw-api-abi validate-examples
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build pluginval-examples
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build bundle-examples-linux -Dtarget=aarch64-linux-gnu
env ZIG_GLOBAL_CACHE_DIR=/tmp/zig-vst3-global-cache zig build bundle-examples-windows -Dtarget=x86_64-windows-gnu
```

Also verify:

- `git diff --check`
- No continuous repaint for static controls
- No audio-thread allocation, lock, operating-system call, or unbounded work
- No shared mutable editor or parameter state across plugin instances
- No toolkit-specific type in the toolkit-neutral API

## References

- [Existing zig-vst3 GUI plan](gui-plan.md)
- [Existing framework GUI guide](framework/gui.md)
- [NIH-plug repository and GUI overview](https://github.com/robbert-vdh/nih-plug)
- [NIH-plug Editor contract](https://nih-plug.robbertvanderhelm.nl/nih_plug/editor/trait.Editor.html)
- [NIH-plug VIZIA widgets](https://github.com/robbert-vdh/nih-plug/tree/master/nih_plug_vizia/src/widgets)
- [third-party framework Component](https://docs.third-party framework.com/master/classthird-party framework_1_1Component.html)
- [third-party framework LookAndFeel](https://docs.third-party framework.com/develop/classthird-party framework_1_1LookAndFeel.html)
- [third-party framework Slider](https://docs.third-party framework.com/master/classthird-party framework_1_1Slider.html)
- [third-party framework AccessibilityHandler](https://docs.third-party framework.com/master/classthird-party framework_1_1AccessibilityHandler.html)
