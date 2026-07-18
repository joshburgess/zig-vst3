# VSTGUI Component Authoring

The reference component API is available as `@import("zig-vst3").vstgui`. A controller describes parameters, meters, and presentation choices in Zig. It does not include VSTGUI headers, allocate C++ widgets, or call VST3 gesture functions directly.

The component gallery is the `zig_vst3_editor_smoke` example. The Voice Mix example is the smaller production-style editor used to verify that the same API works with a different composition and theme.

## Build a Parameter Editor

Add a `createView` function to a reflected edit controller. This example uses the compact alternate presentation from Voice Mix:

```zig
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const ui = @import("zig-vst3").vstgui;

pub fn createView(
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
) ?*iplugview.IPlugView {
    return ui.createMultiViewWithSkin(Controller, controller, name, &.{.{
        .id = voices_param_id,
        .title = "Voices",
        .units = "voices",
        .step_count = 3,
        .default_normalized = 0.0,
        .control_kind = .segmented_enum,
    }}, &.{}, .{
        .theme = .alternate,
        .layout = .compact_strip,
    });
}
```

Use `createView` for one default slider, `createMultiView` for standard parameter controls, `createMultiViewWithMeters` for telemetry, or `createMultiViewWithSkin` for explicit theme, layout, fonts, assets, and drawing.

Use `createEditor` when the editor needs an explicit composition. `EditorDescription` combines parameter and meter slices with a skin and a bounded `Composition`. Each `Group` names a contiguous range of parameters and meters. Groups must cover both slices once, in order. Invalid, overlapping, incomplete, or empty groups reject editor creation.

```zig
return ui.createEditor(Controller, controller, name, .{
    .parameters = parameters,
    .meters = meters,
    .skin = .{ .theme = .alternate },
    .composition = .{
        .title = "Channel Strip",
        .groups = &.{
            .{ .title = "Input", .parameter_count = 1 },
            .{ .title = "Character", .first_parameter = 1, .parameter_count = 2 },
            .{ .title = "Output", .first_parameter = 3, .meter_count = 2 },
        },
    },
});
```

At widths below 620 logical units, groups form one vertical reading order. Wider editors use two columns while preserving declaration and Tab order. Group headings provide structure but are not focus stops. The resize action remains last.

Each `Parameter` needs the stable parameter ID used by the controller, its display metadata, its step count, its normalized default, and a presentation kind:

| Kind | Intended parameter | Exact entry |
| --- | --- | --- |
| `linear_slider` | Continuous or stepped scalar | Yes |
| `rotary_knob` | Continuous scalar | Yes |
| `toggle` | Boolean | No |
| `enum_dropdown` | Enum with several choices | No |
| `segmented_enum` | Small enum whose choices fit visibly | No |
| `bipolar_slider` | Signed scalar with a meaningful zero center | Yes |
| `decibel_slider` | Gain expressed in decibels with unity at the normalized default | Yes |

All presentations use the same parameter attachment behavior. Pointer and keyboard gestures call the host in begin, perform, end order. Rejected changes roll back. Host automation updates the visible value without producing another gesture. Formatting, parsing, default reset, context menus, focus, and semantic metadata remain attached when the presentation changes.

The bipolar and decibel presentations fill from the center instead of from the minimum. This makes negative and positive movement distinguishable and keeps unity visible for a symmetric decibel range. Decibel parameters should normalize a plain dB range, such as -24 to +24. Equal slider travel then represents equal dB steps and therefore equal gain ratios.

`Parameter.modulation_normalized` adds a non-editable outlined marker without replacing the base parameter value or its thumb. Runtime modulation updates use the separate adapter modulation path and do not begin a host parameter gesture. The marker is presentation only; parameter formatting and automation still describe the base value.

`Parameter.tooltip` adds delayed native tooltip text to the primary control and exact field. The same text becomes the control's semantic description. Keep the visible label sufficient on its own. Tooltips are appropriate for reset gestures, scale details, or other secondary guidance, not for the control name or current value.

## Themes and Layouts

`Skin.theme` selects `.default` or `.alternate`. The default is a dark theme and the alternate is a light theme. Both resolve semantic colors, typography, spacing, radii, and control metrics for each visual state. The `ZIG_VSTGUI_THEME=alternate` environment override remains useful for testing an editor that requests the default theme, but production editors should select their theme in `Skin`.

`Skin.layout` selects one of two tested compositions:

- `.adaptive` switches the full parameter editor between compact and expanded arrangements at 520 by 360. It is intended for multi-parameter editors and telemetry.
- `.compact_strip` keeps a title and dense label, control, value rows. It is intended for small production editors that should not inherit the gallery's large single-control composition.

Both layouts accept host resize requests from 320 by 240 through 1000 by 700, use logical coordinates, and keep Tab order aligned with visible reading order. The host can reject a requested size. The editor preserves its last accepted size when that happens.

`Composition.style` and `Group.style` override semantic background, foreground, border, and accent colors using `0xRRGGBBAA` values. Editor values apply first and group values apply to controls within that group. Typography, state contrast, spacing, radii, and control metrics still come from the selected theme. Prefer changing the accent or border at group scope. Replacing every color increases the chance of losing hover, focus, disabled, or editing contrast.

## Component Gallery

`zig_vst3_editor_smoke` exercises the broad surface in one real plugin:

| Gallery area | Components and behavior |
| --- | --- |
| Continuous | Rotary gain control and exact numeric entry |
| Discrete | Bypass toggle, mode dropdown, and segmented voice count |
| Telemetry | Peak, stereo, and gain-reduction meters |
| Resources | Embedded PNG, deterministic SVG, font fallback, and custom overlay drawing |
| Lifecycle | Adaptive breakpoint, resize action, drag handle, scaling, and independent editor instances |

Use the gallery as a regression fixture and API example. It is intentionally denser than a production editor. The Voice Mix editor demonstrates the opposite case: one musical choice, the alternate palette, and the compact-strip composition.

## Telemetry

Meters consume scalar snapshots from `zig-vst3-plugin.gui_telemetry`. A `SimpleStereoEffect` processor opts in by implementing `guiTelemetryLoad`, `guiTelemetryEditorOpened`, and `guiTelemetryEditorClosed`. Its reflected controller discovers that source through the normal component connection point, and `createEditor` retains it automatically. Plugin editor composition does not need adapter-specific wiring.

The audio thread publishes bounded atomic values. The editor's 33 millisecond timer applies ballistics, formats accessibility text, and invalidates only when the displayed result changes. Peak and stereo meters show dB reference ticks and a clipping indicator. Gain-reduction meters show a 0 to 24 dB scale. Clicking a meter or focusing it and pressing Return or Space resets its held peak without changing a parameter.

Describe each `Meter` as `.peak`, `.stereo`, or `.gain_reduction` and assign its source IDs. Do not draw, allocate, lock, call the operating system, or request a repaint from the processor. `MeterBank` stops editor-only publication when all editors are closed.

## Assets and Custom Drawing

A `Skin` may own up to 16 PNG or supported SVG assets. Asset bytes are copied when the editor is created and remain owned by that editor across frame recreation. Each asset selects `pixel_exact`, `contain`, `cover`, or `stretch` scaling.

The drawing callback receives a component kind, visual state, parameter ID, normalized value, logical size, scale factor, and opaque `Canvas`. Canvas operations provide rectangles, ellipses, lines, and registered assets. The callback adds a non-interactive overlay. The standard control underneath retains parameter gestures, keyboard input, exact entry, theme resolution, focus, and semantic metadata.

Keep drawing callbacks deterministic, bounded, and allocation-free. Return a nonzero result when drawing cannot complete. An unknown asset ID paints a visible red crossed placeholder instead of leaving a blank interactive area. The supported SVG subset and font fallback rules are documented in [Plugin Editors](gui.md#assets-fonts-and-custom-drawing).

## API Status

The project remains pre-1.0, so even the supported surface does not yet carry a long-term compatibility promise. Milestone 10 narrows the component API according to evidence from both the gallery and Voice Mix editors.

Supported authoring surface:

- `Parameter`, `ControlKind`, `Theme`, `Layout`, and the four `create*View` functions.
- `EditorDescription`, `Composition`, `Group`, `StyleOverride`, and `createEditor`.
- `Meter`, meter source wiring, `MeterBank`, and GUI telemetry presentation.
- Standard parameter binding, host updates, formatting, parsing, focus, resizing, and per-instance lifecycle.
- Theme and layout selection through `Skin`.

Experimental extensions:

- `Asset`, `Fonts`, `DrawingCallbacks`, `DrawRequest`, and `Canvas` drawing functions.
- Native assistive-technology bridges. Toolkit-neutral semantics exist, but platform screen-reader exposure does not.
- New analyzer, modulation, timeline, GPU, preset-browser, and drag-and-drop components.

Experimental extensions may change when a second production editor establishes their required shape. They are kept out of the supported list even though the gallery validates their current implementation.

## Verification

Run the native adapter tests and example validation after changing a component declaration:

```sh
zig build vstgui-adapter
zig build test raw-api-abi validate-examples
zig build pluginval-examples
```

The native suite covers parameter routing, interaction, layout selection, theme selection, assets, accessibility semantics, visual references, and the warm-render budget. The example suites verify both editor styles through real plugin bundles.
