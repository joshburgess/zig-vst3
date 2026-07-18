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

Use `createEditor` when the editor needs an explicit composition. `EditorDescription` combines parameter, meter, graph, and XY-pad slices with a skin and a bounded `Composition`. Each `Group` names contiguous ranges from those slices. Groups must cover every slice once, in order. Invalid, overlapping, incomplete, or empty groups reject editor creation.

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

## Build a Channel Strip

The complete [channel strip example](../../examples/channel_strip_plugin.zig) uses only `@import("zig-vst3").vstgui`. It does not import adapter headers or implementation files.

1. Define stable parameter IDs and the reflected parameter set as usual.

2. Declare the controls, meters, and graphs in one `EditorDescription`. Source IDs are local to the processor instance.

3. Group contiguous ranges in visible reading order. Set every `first_*` index explicitly after the first group so later edits cannot silently change ownership.

4. Publish meter values through `MeterBank`. Guard extra audio-thread calculations with `producing()` and publish only bounded atomic values.

5. Keep fixed graph points in static storage. For dynamic data, use `SnapshotSeries`, stop publication when the last editor closes, and cap editor refresh at 60 Hz or less.

6. Select a theme and layout in `Skin`, then use editor and group style overrides only for semantic colors.

The channel strip combines gain and drive controls, a linked XY pad, bypass toggle, mode dropdown, stereo and gain-reduction meters, and a fixed transfer graph. The component gallery exercises the same description, grouping, XY interaction, telemetry, graph, resize, focus, and lifecycle contracts with different component variants. Ordinary editor composition should require changes only to the plugin's public declarations.

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

## XY Pads

Add an `XYPad` to `EditorDescription.xy_pads` with two distinct parameter IDs. Both IDs must also appear in `EditorDescription.parameters`. A group owns a contiguous XY-pad range through `first_xy_pad` and `xy_pad_count`, following the same complete, ordered coverage rule as parameters, meters, and graphs.

```zig
.xy_pads = &.{.{
    .title = "Gain and Drive",
    .x_parameter_id = gain_param_id,
    .y_parameter_id = drive_param_id,
    .x_label = "Gain",
    .y_label = "Drive",
}},
```

Dragging edits both parameters as one ordered gesture. Left and Right adjust the horizontal axis. Up and Down adjust the vertical axis. Home moves both axes to their minima, End moves both to their maxima, and Shift enables fine adjustment. Each axis is exposed as a separately named accessible slider with its own value and adjustment actions. Host automation updates the pad without starting a new gesture. A rejected axis update restores both axes to their values at gesture start.

## Component Gallery

`zig_vst3_editor_smoke` exercises the broad surface in one real plugin:

| Gallery area | Components and behavior |
| --- | --- |
| Continuous | Bipolar control, modulation marker, exact numeric entry, and linked XY pad |
| Discrete | Bypass toggle, mode dropdown, and segmented voice count |
| Telemetry | Peak, stereo, and gain-reduction meters plus a live waveform graph |
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

## Graphs

Add graphs through `EditorDescription.graphs`. A `Graph` declares a title, series kind, style role, x and y axes, and either fixed points or a dynamic source ID. `Group` places contiguous graph ranges alongside parameters and meters.

```zig
.graphs = &.{.{
    .title = "Transfer",
    .kind = .transfer_function,
    .x_axis = .{ .minimum = -2.0, .maximum = 2.0, .label = "Input" },
    .y_axis = .{ .minimum = -1.2, .maximum = 1.2, .label = "Output" },
    .points = &transfer_points,
}},
```

Fixed graphs copy at most 256 finite points when the editor is created and never create a refresh timer. Use `gui_graph.SnapshotSeries` for waveforms or spectra produced at runtime. Dynamic graphs require `maximum_refresh_hz` from 1 through 60. Publication stops while no editor is open, and a busy reader may drop a visualization frame rather than blocking the producer.

A `SimpleStereoEffect` processor exposes dynamic points with `guiGraphLoad`. Its existing telemetry open and close hooks should update the graph snapshot activity count:

```zig
pub fn guiGraphLoad(self: *Processor, source_id: u32, output: []gui_graph.Point) usize {
    if (source_id != waveform_source) return 0;
    return self.waveform.read(output) orelse 0;
}
```

The renderer clamps coordinates to the declared range, supports linear and logarithmic axes, and treats decibel axes as linear dB values. An empty series displays `No graph data` instead of a blank panel. Axis labels, graph title, update mode, and point count are available through toolkit-neutral semantics.

### Editable Envelopes

An envelope becomes editable when `point_capacity` is nonzero. Supply stable, nonzero point IDs through `editable_points`, declare the minimum point count, and optionally set positive x and y snap intervals. Points must be finite, inside both axis ranges, ordered by x, unique by ID, and no more numerous than the declared capacity.

```zig
.graphs = &.{.{
    .title = "Envelope",
    .kind = .envelope,
    .x_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Time" },
    .y_axis = .{ .minimum = 0.0, .maximum = 1.0, .label = "Level" },
    .editable_points = &.{
        .{ .point_id = 1, .x = 0.0, .y = 0.0 },
        .{ .point_id = 2, .x = 1.0, .y = 1.0 },
    },
    .point_capacity = 8,
    .minimum_point_count = 2,
    .snap_x = 0.05,
    .snap_y = 0.05,
}},
```

Clicking an empty location creates and selects a point. Dragging moves the selected point, and right-clicking it deletes it when the minimum count permits. Brackets select adjacent points. Arrow keys adjust coordinates, Shift enables fine movement, Home and End select boundary points, Return creates a point, and Delete removes the selection. A canceled pointer gesture restores points, selection, and ID allocation from the transaction snapshot.

The graph semantic value reports point count, selected ID, and selected coordinates. Standard focus, press, increment, decrement, and set-value actions operate the selected point. Toolkit-neutral actions also expose previous, next, add, and delete operations. Static graphs remain read-only and never acquire an edit timer.

To bind a point to two automatable parameters, set `parameter_mask = 3` with distinct `x_parameter_id` and `y_parameter_id` values. Both parameters must be declared in the same editor. Movement then uses the standard ordered multi-parameter gesture, rejection restores both coordinates, and host automation updates the handle without emitting another gesture.

Set `selection_state_id` and `envelope_state_id` to fields in the controller's public `editor_state.Store` to persist non-parameter selection and geometry. The store restores before each view is built. VSTGUI writes completed envelope transactions and selection changes back through toolkit-neutral callbacks. Parameter-backed points recover their declared bindings by stable point ID, so restoring UI geometry does not emit automation or change parameter state.

## Native Accessibility

Every component keeps its role, name, description, value, range, enabled state, focus state, checked state, and read-only state in the toolkit-neutral accessibility model. Focus, press, increment, decrement, and set-value actions use the same model. Native bridges observe and operate it only while an editor is open. They do not create a second parameter attachment or gesture path.

On macOS, the adapter attaches an `NSAccessibilityElement` hierarchy to VSTGUI's editor `NSView`. AppKit receives mapped roles, labels, help text, values, ranges, state, focus, and bounds. Native focus, press, increment, decrement, and value methods dispatch toolkit-neutral actions. Value, focus, semantic, and layout changes post native accessibility notifications. An AppKit integration test opens a real editor view and verifies properties, actions, host gesture counts, resize geometry, and teardown.

On Windows, the adapter provides a UI Automation fragment tree through `WM_GETOBJECT`. It maps the same semantic properties, exposes screen-space bounds and focus, and raises property, focus, and structure events. Sliders expose RangeValue, toggles expose Toggle, actionable buttons expose Invoke, and editable or choice values expose Value. The Windows provider cross-compiles with Zig's Windows SDK headers during the native adapter test, but Narrator behavior has not been tested in a native Windows host.

X11 and Wayland retain the toolkit-neutral semantics, keyboard focus order, and visible focus rendering. No AT-SPI bridge is implemented yet. VoiceOver navigation, Narrator navigation, and AT-SPI host verification remain release checks for their respective platform environments.

## API Status

The project remains pre-1.0, so even the supported surface does not yet carry a long-term compatibility promise. The supported list is limited to contracts exercised by both the component gallery and a production-style editor.

Supported authoring surface:

- `Parameter`, the linear, toggle, dropdown, and segmented control kinds, `Theme`, `Layout`, and the four `create*View` functions.
- `EditorDescription`, `Composition`, `Group`, `StyleOverride`, and `createEditor`.
- `Meter`, meter source wiring, `MeterBank`, and GUI telemetry presentation.
- `Graph`, graph axes and style roles, and grouped graph composition.
- `EnvelopePoint`, bounded editable envelopes, stable selection, snapping, and parameter-backed point gestures.
- `editor_state.Store`, typed editor values, bounded serialization, migrations, and persistent envelope bindings.
- `XYPad`, ordered two-parameter gestures, per-axis semantics, and grouped XY-pad composition.
- Standard parameter binding, host updates, formatting, parsing, focus, resizing, and per-instance lifecycle.
- Theme and layout selection through `Skin`.

Experimental extensions:

- `Asset`, `Fonts`, `DrawingCallbacks`, `DrawRequest`, and `Canvas` drawing functions.
- Rotary controls currently have no plugin consumer. Bipolar and decibel controls each have one.
- Fixed graph point storage, dynamic graph sources, and `SnapshotSeries`. Each source mode currently has one production consumer.
- Native assistive-technology bridges. macOS is integration-tested, Windows is cross-compiled, and native screen-reader workflows remain unverified.
- New analyzer, modulation, timeline, GPU, preset-browser, and drag-and-drop components.
- `gui_preset_browser.Browser`, pending a native component and a second production consumer.

Experimental extensions may change when a second production editor establishes their required shape. They are kept out of the supported list even though the gallery validates their current implementation.

## Verification

Run the native adapter tests and example validation after changing a component declaration:

```sh
zig build vstgui-adapter
zig build test raw-api-abi validate-examples
zig build pluginval-channel-strip
```

The native suite covers parameter routing, interaction, layout selection, theme selection, assets, accessibility semantics, visual references, and the warm-render budget. The example suites verify both editor styles through real plugin bundles. Run pluginval examples one at a time on macOS. Stop after the first crash dialog rather than relaunching the application or using the aggregate parallel target.
