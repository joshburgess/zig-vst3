# VSTGUI Component Authoring

The reference component API is available as `@import("zig-vst3").vstgui`. A controller describes parameters, meters, and presentation choices in Zig. It does not include VSTGUI headers, allocate C++ widgets, or call VST3 gesture functions directly.

The component gallery is the `zig_vst3_editor_smoke` example. The channel-strip example is the production-style editor used to verify that the same API works with a different composition and theme.

## Choose the Public Surface

Use `@import("zig-vst3").vstgui` for plugin editor declarations. `EditorDescription` and `createEditor` are the main composition path. The four `create*View` helpers remain supported conveniences for small parameter editors. `FileImporter` is the current file-input name. `FileDrop` and `EditorDescription.file_drops` remain compatibility aliases for existing source.

Use `@import("zig-vst3-plugin").gui` only when implementing a GUI adapter or testing toolkit-neutral host lifecycle behavior. It defines renderer, size, scale, and attachment contracts. It is not a second component library, and ordinary plugin composition does not need it.

Focused declarations live in:

- [composition](../../examples/gui/composition.zig)
- [graphs](../../examples/gui/graphs.zig)
- [importer](../../examples/gui/importer.zig)
- [accessibility](../../examples/gui/accessibility.zig)
- [toolkit-neutral lifecycle](../../examples/gui/lifecycle.zig)

Descriptions and their referenced slices must remain alive until `createEditor` returns. Editor creation copies bounded declaration data into instance-owned storage. Every declaration string must terminate within 1,024 bytes and contain complete UTF-8; malformed or oversized text rejects the complete editor before widget allocation. The returned view owns its native widget tree and retained telemetry sources until the host releases the view. File parsing, decoding, and other unbounded work belong on a controller-owned worker. Processor callbacks may publish bounded lock-free telemetry and adopt complete decoded generations, but must not allocate, lock, read files, log, call the host, or perform GUI work.

Custom pointer-driven components reject non-finite native positions, wheel deltas, and zoom changes before hit testing or mutation. A malformed event remains unconsumed and preserves the active editor transaction, selection, viewport, menu, and preset state.

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

Use `createEditor` when the editor needs an explicit composition. `EditorDescription` combines parameter, meter, graph, XY-pad, preset-browser, and action-menu slices with a skin and a bounded `Composition`. Each `Group` names contiguous parameter, meter, graph, and XY-pad ranges. Groups must cover every grouped slice once, in order. Invalid, overlapping, incomplete, or empty groups reject editor creation. Preset browsers occupy a separate responsive editor region. Action menus occupy the footer. Both follow grouped controls in focus order.

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

5. Keep fixed graph points in static storage. For live audio, use `WaveformCapture` or `SpectrumAnalyzer`, stop publication when the last editor closes, and cap editor refresh at 60 Hz or less.

6. Select a theme and layout in `Skin`, then use editor and group style overrides only for semantic colors.

The channel strip combines gain and drive controls, a linked XY pad, bypass toggle, mode dropdown, stereo and gain-reduction meters, and a fixed transfer graph. The component gallery exercises the same description, grouping, XY interaction, telemetry, graph, resize, focus, and lifecycle contracts with different component variants. Ordinary editor composition should require changes only to the plugin's public declarations.

## Preset Browsers

Declare up to two `PresetBrowser` values in `EditorDescription.preset_browsers`. Each browser accepts up to 64 stable, nonzero preset IDs. Search and selection reference declared persistent editor-state fields. The search field must use `editor_state.Text`; the selection field must use `index` or `point_id`.

```zig
.preset_browsers = &.{.{
    .title = "Channel Presets",
    .presets = &.{
        .{ .id = 1, .name = "Clean Start" },
        .{ .id = 2, .name = "Console Push" },
        .{ .id = 3, .name = "Peak Limit" },
    },
    .search_state_id = preset_search_state_id,
    .selection_state_id = preset_selection_state_id,
}},
```

The reflected controller configuration must implement `loadPreset(controller, preset_id)` when it declares a browser. Editor creation rejects a browser without a loader. A production load should edit every affected parameter through the controller's begin, perform, and end methods so the host records automation. The gallery and channel strip open an optional host group edit, begin all affected parameters, roll back accepted values if any perform call fails, end every begun gesture, and finish the group edit.

The browser is one composite focus stop. Type printable characters to filter, use Backspace to edit, Escape to clear, Up and Down to move, Home and End to jump, and Enter to load. A single pointer click selects, and a double-click loads. The accessible press action also loads. Empty results explain how to recover. Failed loads preserve the selected preset and expose a retry instruction.

Search and selection are stored as editor state, separate from parameter state. Reopening an editor restores both. Catalog names and search text are copied into instance-owned bounded storage during editor creation. Filtering and drawing do not allocate.

## Action Menus

Declare up to four `ActionMenu` values in `EditorDescription.action_menus`. A menu accepts up to 16 action, toggle, or separator items. Menu and non-separator item IDs must be stable and nonzero. A toggle references a boolean editor-state field so its checked state survives editor teardown and controller serialization.

```zig
.action_menus = &.{.{
    .id = 1,
    .title = "Options",
    .items = &.{
        .{ .id = 1, .label = "Reset Channel" },
        .{ .id = 2, .label = "Show Analyzer", .kind = .toggle, .checked_state_id = show_analyzer_state_id },
        .{ .id = 3, .label = "Export Preset", .enabled = false },
        .{ .kind = .separator },
        .{ .id = 4, .label = "Reset UI", .destructive = true },
    },
}},
```

The reflected controller configuration must implement `performMenuAction(controller, menu_id, item_id, checked)`. Return `kResultOk` only after the requested action succeeds. For toggles, `checked` is the proposed value. The adapter persists the referenced boolean only after the handler accepts it. A rejected action or failed state write keeps the menu open, restores the previous checked state, and displays a retry message.

Each menu is one focus stop while closed and one contained focus region while open. Return, Space, or Down opens it. Up and Down skip separators and disabled items, Home and End select a boundary item, Return or Space activates, Tab remains contained, and Escape closes and restores trigger focus. Pointer movement highlights and selects enabled rows. Pointer activation occurs on release so the selected state remains visible throughout the click. Pointer clicks outside the panel dismiss it. Opening one menu closes any other menu in the editor. The accessible press, increment, and decrement actions use the same selection and activation path.

Menu storage is copied into the editor instance at creation. Layout anchors the panel above or below its trigger and clamps it to the editor bounds. Warm drawing uses cached labels and does not allocate.

## Action Buttons and Toolbars

Declare up to 12 buttons in `EditorDescription.action_buttons`. Button order is visible order. Adjacent buttons with the same `group_id` form a group; a new group receives wider toolbar spacing.

```zig
.action_buttons = &.{
    .{
        .group_id = 1,
        .id = 1,
        .label = "Apply Edit",
        .accessible_label = "Apply impulse response edit",
        .role = .primary,
    },
    .{
        .group_id = 2,
        .id = 2,
        .icon = .clear,
        .accessible_label = "Clear impulse response",
        .tooltip = "Remove the loaded impulse response.",
        .confirmation_label = "Confirm Clear IR",
        .failure_label = "Clear failed. Try again",
        .role = .destructive,
        .success_focus_importer_id = 1,
        .ready_importer_id = 1,
    },
},
```

The reflected controller implements `performAction(controller, group_id, action_id)`. Existing controllers may route buttons through `performMenuAction`; the framework uses that as a compatibility fallback. Return `kResultOk` only after the command succeeds.

An editor may declare one primary button. Destructive buttons require confirmation text and cannot share a group with the primary action. Icon-only buttons require `accessible_label`; the icon never supplies the semantic name. Return and Space activate the focused button. Escape cancels pending confirmation or dismisses failure feedback. Accepted commands restore the stable action label. The command itself must produce a visible domain result instead of relying on generic completion text. Rejected commands retain focus and use the declared retry label, which should name the failed action. `success_focus_importer_id` may name a declared file importer that receives focus after an accepted command. `ready_importer_id` disables the button until that importer reaches Ready and removes it from focus traversal while unavailable. Disabled buttons use a neutral surface, muted border and text, and disabled alpha in addition to rejecting pointer, keyboard, and accessibility activation. Unknown targets reject editor creation.

The gallery and IR loader use the same public declaration. The gallery covers primary, secondary, destructive, text, and icon-only variants. The IR loader uses the destructive confirmation contract for clearing imported media. Footer actions retain at least the themed button width. When the accepted editor width cannot preserve that minimum, actions wrap into additional rows and the virtual content height grows to keep every label readable. Group boundaries retain wider spacing within a row.

Parameter labels, editable values, progress text, preset rows, and action-menu rows receive a themed inner text inset. Borders are never used as the text origin. Native geometry tests enforce the inset and action-button minimum width so a valid editor cannot silently regress to edge-touching or overlapping labels.

A compact single-parameter editor preserves at least the themed medium gap between its primary control and exact-value field. The layout only shifts the primary control when the available default-size gap is too small, so expanded geometry keeps its existing spacing.

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

All presentations use the same parameter attachment behavior. Pointer and keyboard gestures call the host in begin, perform, end order. Rejected changes roll back. Host automation updates the visible value without producing another gesture. Formatting, parsing, default reset, context menus, focus, and semantic metadata remain attached when the presentation changes. Context-menu callbacks reject non-finite pointer coordinates and saturate finite coordinates to their signed 32-bit contract.

Boolean presentations use persistent on/off button behavior, so one click produces one accepted edit and leaves the new state visible. Segmented enums fill the selected segment with the pressed-state accent instead of relying on a narrow marker or value field alone. Selected and resize-button text use whichever of black or white has the stronger measured contrast against the fill. Kick-style action buttons and menu triggers dispatch only their pressed value. Their release value cannot invoke an action twice or close a menu that was just opened. An open action menu moves to the front of the editor's child-view stack so controls created later cannot intercept its pointer events.

The bipolar and decibel presentations fill from the center instead of from the minimum. This makes negative and positive movement distinguishable and keeps unity visible for a symmetric decibel range. Decibel parameters should normalize a plain dB range, such as -24 to +24. Equal slider travel then represents equal dB steps and therefore equal gain ratios.

`Parameter.modulation_normalized` adds a non-editable outlined marker without replacing the base parameter value or its thumb. Runtime modulation updates use the separate adapter modulation path and do not begin a host parameter gesture. The marker is presentation only; parameter formatting and automation still describe the base value.

`Parameter.tooltip` adds delayed native tooltip text to the primary control and exact field. The same text becomes the control's semantic description. Keep the visible label sufficient on its own. Tooltips are appropriate for reset gestures, scale details, or other secondary guidance, not for the control name or current value.

## Themes and Layouts

`Skin.theme` selects `.default` or `.alternate`. The default is a dark theme and the alternate is a light theme. Both resolve semantic colors, typography, spacing, radii, and control metrics for each visual state. The `ZIG_VSTGUI_THEME=alternate` environment override remains useful for testing an editor that requests the default theme, but production editors should select their theme in `Skin`.

`Skin.layout` selects one of four tested compositions:

- `.adaptive` switches the full parameter editor between compact and expanded arrangements at 520 by 360. It is intended for multi-parameter editors and telemetry.
- `.compact_strip` keeps a title and dense label, control, value rows. It is intended for small production editors that should not inherit the gallery's large single-control composition.
- `.parameter_workspace` gives one graph-backed output group a primary editing region and arranges the remaining parameter groups as panels. It is intended for editors such as an EQ where a shared graph and several linked parameter groups must remain visible together.
- `.instrument_workspace` places one file importer and its progress indicator immediately after the editor title, followed by a graph-backed editing region, parameter panels, optional piano, metadata, and footer actions. It is intended for sample-based instruments where choosing media and editing its waveform are the first tasks.

Adaptive and compact-strip editors accept host resize requests from 320 by 240 through 1000 by 700. A parameter workspace uses a 400 by 360 minimum, opens at 720 by 660, and uses 1000 by 700 as its maximum. Its resize action requests 480 by 480 for Compact and 960 by 700 for Expanded. Widths below 620 use one vertical reading order. Wider editors place the graph beside the output controls and flow parameter panels across the available width. Sizes at or above 840 by 560 use the expanded graph geometry. The default and expanded presets fit without scrolling. Compact sizes use bounded vertical scrolling and never require horizontal scrolling.

A parameter workspace requires at least two groups. The first group owns exactly one graph, up to three parameters, and no meters or XY pads. Each remaining group owns one through five parameters and no graphs, meters, or XY pads. The regular complete, contiguous group-coverage rules still apply. Graph handles may name a `highlight_group_index`; restoring the selected handle then restores the matching panel highlight.

An instrument workspace uses the same group constraints and size limits. It additionally requires exactly one file importer and one progress indicator, and accepts at most one piano keyboard. Compact, standard, and expanded sizes preserve the same reading order. Import comes first, followed by the waveform, its parameter controls, the remaining parameter panels, audition, bounded metadata, destructive actions, and resize. Compact sizes expose lower sections through bounded vertical scrolling without moving Import or the waveform below secondary controls. This layout remains experimental while the sample player is its only production consumer.

All layouts use logical coordinates and keep Tab order aligned with visible reading order. Editors with a preset browser use a 480 by 480 minimum and open at 720 by 600 so the catalog does not displace parameter controls at an unusable size. Dense compositions receive a bounded virtual content height and vertical scrolling when their natural layout exceeds the accepted host size. Editors that fit remain unscrolled. Grouped graphs wrap into additional rows before their readable minimum width is violated. Resize cycles retain a clamped vertical position after synchronizing the viewport and virtual content, so manual and preset resizing cannot leave blank space above the editor. Focus traversal moves the viewport to keep the focused control visible. The host can reject a requested size. The editor preserves its last accepted size when that happens.

The adapter keeps layout dimensions in logical coordinates and reports host rectangles in scaled coordinates. `IPlugViewContentScaleSupport` accepts finite positive scale factors before or after attachment. A scale change updates `getSize`, scales minimum and maximum constraints, and asks the host to resize the view. Host and preset resize requests convert back to logical dimensions before layout. A rejected scale or resize request restores the previous scale and rectangle. Repeated 1x, 1.5x, and 2x changes therefore preserve the same layout breakpoints instead of treating scaled pixels as a wider logical editor.

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
| Continuous | Bipolar slider, rotary control, output dB slider, modulation markers, exact numeric entry, and linked XY pad |
| Discrete | Bypass toggle, mode dropdown, and segmented voice count |
| Telemetry | Peak, stereo, and gain-reduction meters plus live waveform, spectrum, linked-response, and editable-envelope graphs |
| Resources | Embedded PNG, deterministic SVG, font fallback, and custom overlay drawing |
| Lifecycle | Adaptive breakpoint, resize action, drag handle, scaling, independent editor instances, and persistent preset search and selection |

Use the gallery as a regression fixture and API example. It is intentionally denser than a production editor. The channel strip demonstrates the production case with an alternate palette, compact-strip composition, and host-automated presets.

## Telemetry

Meters consume scalar snapshots from `zig-vst3-plugin.gui_telemetry`. A `SimpleStereoEffect` processor exposes the shared telemetry source when it implements `guiTelemetryLoad`, `guiGraphLoad`, or `guiTelemetryLoadText`. `guiTelemetryEditorOpened` and `guiTelemetryEditorClosed` gate processor work while editors are closed. The reflected controller discovers that source through the normal component connection point, and `createEditor` retains it automatically. Source discovery is retried after editor attachment so valid late component connections begin producing without recreating the editor. Plugin editor composition does not need adapter-specific wiring.

`RetainedSource.loadText` copies a processor-provided status or metadata string into caller-owned bounded storage. The framework exposes at most `editor_state.maximum_text_bytes` bytes to the producer, even when an ABI caller supplies a larger capacity. The processor returns the number of bytes copied and must not retain the output slice. Truncation is explicit when the returned count equals the effective capacity. Text loading is for low-rate editor snapshots such as a model name, resource status, or format summary. It must not be called from processing or used as a streaming log channel.

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

Fixed graphs copy at most 256 finite points when the editor is created and never create a refresh timer. Dynamic graph telemetry uses the same 256-point limit at both sides of its ABI boundary, so an oversized caller capacity cannot create an unbounded producer slice. Dynamic graphs require `maximum_refresh_hz` from 1 through 60. Publication stops while no editor is open, and a busy reader may drop a visualization frame rather than blocking the producer.

`gui_graph.WaveformCapture(capacity)` reduces the latest audio block to 1–256 evenly spaced points with normalized frame positions. `gui_graph.SpectrumAnalyzer(fft_size)` accepts power-of-two FFT sizes from 8 through 512, applies a Hann window, publishes the positive-frequency bins as decibels, and performs at most one public `dsp.Fft` transform per process call after a 50 percent hop. Both types use fixed storage and the nonblocking `SnapshotSeries` handoff. They allocate no memory, acquire no locks, and do no sample reduction or spectral work while every editor is closed.

A `SimpleStereoEffect` processor exposes dynamic points with `guiGraphLoad`. Its existing telemetry open and close hooks should update the graph snapshot activity count:

```zig
pub fn guiGraphLoad(self: *Processor, source_id: u32, output: []gui_graph.Point) usize {
    return switch (source_id) {
        waveform_source => self.waveform.read(output) orelse 0,
        spectrum_source => self.spectrum.read(output) orelse 0,
        else => 0,
    };
}
```

Call `waveform.capture(output)` and `spectrum.push(output, context.sampleRate())` after producing the output block. The spectrum excludes DC and emits frequencies from one FFT bin through Nyquist. Declare a logarithmic frequency axis and a decibel y axis that match the intended visible range.

The renderer clamps coordinates to the declared range, supports linear and logarithmic axes, and treats decibel axes as linear dB values. Waveforms receive a visible zero line and a batched curve. Spectra use a batched set of magnitude bars. Batching keeps draw-call count constant as point count grows. Empty views display `No waveform data` or `No spectrum data`. Toolkit-neutral semantics report waveform sample count and peak magnitude, or spectrum bin count and the strongest frequency and level.

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

### Linked Parameter Handles and Layers

A transfer graph may declare fixed `GraphHandle` values independently from its curve points. Each handle binds x and y to distinct parameters. An optional adjustment parameter provides a third dimension such as Q, and an optional enabled parameter dims the handle without removing its accessible state. `highlight_group_index` links selection to a declared parameter group so the matching panel heading receives visible selected styling and selected accessibility state.

Set `parameter_driven = true` and `source = .controller` when the controller calculates the curve from accepted parameter values. The adapter loads it when the editor opens and after parameter notifications. It does not start a refresh timer. Up to four `GraphLayer` overlays may provide bounded band, reference, waveform, or spectrum data. A layer independently declares fixed points, a parameter-driven controller source, or a timer-driven component source. Dynamic and parameter-driven sources in one graph refresh independently, so audio telemetry does not cause response recalculation and parameter changes do not poll the analyzer.

Set a spectrum layer's `kind` to `.spectrum` and give it a decibel `y_axis` when it shares a transfer graph's logarithmic frequency axis. Spectrum bars render behind the response and handles. An empty live layer displays `Analyzer waiting for signal`; a disabled layer displays `Analyzer off`. The graph accessibility value reports the same state and includes bin count, peak frequency, and level when data is active. Every primary or layered source remains limited to 256 finite points.

Pointer movement edits x and y through one ordered grouped gesture. Arrows adjust both axes, Page Up and Page Down adjust the optional third parameter, and brackets select adjacent handles. Host changes update the matching handle without emitting a graph gesture. A rejected edit restores both axes. Accessibility exposes the selected handle name, enabled state, axes, and optional adjustment value.

## Native Accessibility

Every component keeps its role, name, description, value, range, enabled state, focus state, checked state, read-only state, and optional Unicode-positioned text selection in the toolkit-neutral accessibility model. Focus, press, increment, decrement, set-value, caret, and text-selection actions use the same model. Native bridges observe and operate it only while an editor is open. They do not create a second parameter attachment or gesture path.

On macOS, the adapter attaches an `NSAccessibilityElement` hierarchy to VSTGUI's editor `NSView`. AppKit receives mapped roles, labels, help text, values, ranges, state, focus, and bounds. Native focus, press, increment, decrement, and value methods dispatch toolkit-neutral actions. Value, focus, semantic, and layout changes post native accessibility notifications. An AppKit integration test opens a real editor view and verifies properties, actions, host gesture counts, resize geometry, and teardown.

Each macOS bundle keeps its VSTGUI and bridge implementation symbols private. Accessibility elements use an image-unique Objective-C runtime subclass instead of a fixed process-wide class name. This prevents one plugin's runtime, drawing callbacks, or native class methods from being interposed when a host loads several zig-vst3 bundles together.

On Windows, the adapter provides a UI Automation fragment tree through `WM_GETOBJECT`. It maps the same semantic properties, exposes screen-space bounds and focus, and raises property, focus, and structure events. Sliders expose RangeValue, toggles expose Toggle, actionable buttons expose Invoke, and editable or choice values expose Value. The Windows provider cross-compiles with Zig's Windows SDK headers during the native adapter test, but Narrator behavior has not been tested in a native Windows host.

For Linux, `AtspiNodeAdapter` maps every toolkit-neutral role to the corresponding AT-SPI role, encodes the standard state bitset, selects Accessible, Component, Action, Value, Text, and EditableText interfaces from node capabilities, preserves a stable action order, dispatches focus and value changes through the shared action path, and classifies semantic change events. Every text field publishes Text, including read-only fields. The Text surface reports checked UTF-8 character counts, exact range and code-point queries, exact character granularity, Unicode word and sentence segmentation, distinct legacy word-start, word-end, sentence-start, sentence-end, line-start, and line-end traversal, whole-field line and paragraph ranges for current single-line queries, empty attribute sets, clip-aware bounded ranges, point-to-offset mapping, optional caret positions, and one anchor-to-caret selection. Text labels report character and range geometry from the active native font's measured prefix advances, ascent, descent, horizontal alignment, and text inset. Rotated labels transform every glyph corner and invert that transform for point queries. Head- and tail-truncated labels expose the standard truncated state, report unavailable extents for omitted semantic characters, exclude them from bounded ranges, retain the original semantic offsets for visible characters, and emit a truncated state change after layout updates. Generic controls and labels with non-finite inset or rotation state retain an equal-width fallback. Caret and selection methods validate Unicode offsets, preserve state after rejected provider actions, normalize backward selections for queries, and emit `TextCaretMoved` and `TextSelectionChanged` after provider state changes. The native bridge discovers the accessibility bus without activating an unavailable service, publishes the required application root and stable Accessible child objects, completes registry embedding, and dispatches a bounded number of GIO main-context operations from the editor timer. Component reports bounds, hit testing, focus, and read-only geometry operations. Action exposes stable names and dispatch, while Value provides ranges, text, and validated writes. EditableText supports whole-value replacement, UTF-8 character-position insertion and deletion, and provider-backed copy, cut, and paste through the same validated text action. Text changes produce minimal delete-then-insert events with Unicode code-point offsets, lengths, and exact payloads. The bridge owns the provider for its open lifetime. Paste accepts at most 1 MiB of complete UTF-8 without embedded NUL bytes. Invalid ranges and provider failures do not dispatch unintended text actions. The Linux default uses a private XCB connection and hidden window to own the `CLIPBOARD` selection, publish `TARGETS`, `UTF8_STRING`, and `TEXT`, read external UTF-8 or legacy `STRING` selections, and pump selection requests through the editor timer. Reads have a fixed timeout and preserve the destination on failure. No shell utility or additional GUI toolkit is used. XWayland can use this path when `DISPLAY` is available; a pure Wayland session without XWayland remains unsupported. The cache object publishes the root and complete child set in the current typed bulk format, announces each object after successful embedding, and removes the child-first sequence before object teardown. Failed startup never publishes cache lifecycle signals. Toolkit-neutral observers publish AT-SPI property, state, focus, bounds, text-change, caret, and selection signals and detach before object teardown. An isolated D-Bus fixture verifies missing-service recovery, address discovery, registration, application ID, traversal, interface discovery, bounds, actions, numeric values, Unicode Text queries, segmentation, deltas, ordinary and rotated measured geometry, head and tail truncation, non-finite native geometry containment, point-to-offset round trips, caret movement, forward and backward selection, rejected-action rollback, complete UTF-8 text edits, clipboard success and failure, bulk cache contents, cache additions and removals, native events, observer detachment, and teardown contracts. Built-in parameter text fields do not yet mirror the visual editor's private selection because the pinned widget interface does not publish it. Custom providers can use the semantic contract now. Native AT-SPI application testing, built-in visual selection synchronization, and pure-Wayland clipboard ownership remain open.

VoiceOver navigation, Narrator navigation, and AT-SPI host verification remain release checks for their respective platform environments.

## Piano Keyboard

Add a bounded note-input surface through `EditorDescription.pianos`:

```zig
.pianos = &.{.{
    .title = "Instrument Keyboard",
    .first_note = 48,
    .note_count = 24,
    .channel = 0,
    .velocity = 0.8,
    .computer_base_pitch = 60,
}},
```

The visible range may contain 1–48 MIDI notes and must stay within 0–127. Pointer vertical position controls velocity. Dragging across keys releases the previous note before pressing the next. The computer-key mapping `awsedftgyhujkolp;` starts at `computer_base_pitch`. The host must forward both key-down and key-up events so releases cannot remain stuck.

Enable processor delivery with `pub const gui_note_input = true` on `SimpleStereoEffect` configuration. The reflected controller sends fixed VST3 connection messages. The component stores only the latest desired state for each pitch in a bounded atomic mailbox. Processing collects changed states at the next nonempty block, emits note-offs before note-ons, and merges them at sample zero without allocating or locking.

The keyboard is one focus stop. Left and Right wrap selection, Home and End select range limits, and Return or Space plays the selected note. Focus loss, pointer cancellation, and editor teardown release every held note. The choice semantic reports the selected MIDI note and its conventional name, plus whether it is playing. Focus, press, increment, and decrement accessibility actions use the same state machine.

## Step Sequencer

Declare a parameter-backed pattern through `EditorDescription.step_sequencers`:

```zig
.step_sequencers = &.{.{
    .title = "Eight Step Gate",
    .step_parameter_ids = &.{ 100, 101, 102, 103, 104, 105, 106, 107 },
    .selection_state_id = step_selection_state_id,
    .playhead_source_id = playhead_source_id,
}},
```

Each step binds to a distinct boolean parameter. The pattern therefore remains in processor state, automation, and presets when the editor is closed. Selection is non-parameter editor state. The optional playhead is read-only telemetry: publish a zero-based step index, or a negative value while stopped. Editor activity gates polling, and `maximum_refresh_hz` is limited to 1–60 Hz.

Clicking a cell selects and toggles it. Dragging paints the first cell's new state across later cells. Command-click or Control-click changes additive selection, and Shift-click selects a range from the anchor. Left and Right move the cursor, Shift with arrows extends the selection, Home and End move to boundaries, Space toggles every selected step, Command+A or Control+A selects all, and Escape returns to one selected cursor step. Selection, active pattern, cursor, and playhead are rendered and announced as separate states.

The sequencer is one focus stop with choice semantics. Accessibility increment and decrement move the cursor, and press toggles the selected steps. Disabled declarations reject pointer, keyboard, and accessibility edits. A rejected host edit keeps the old parameter value and exposes visible and semantic retry feedback. The component supports 1–32 steps; an empty pattern is rejected at editor creation rather than producing an ambiguous empty control. Playhead telemetry accepts nonnegative finite positions. Values beyond the pattern select its final step, while non-finite and negative values publish no active playhead.

## File Importer

Declare a bounded operating-system file target through `EditorDescription.file_importers`:

```zig
.file_importers = &.{.{
    .id = 1,
    .title = "Audio Import",
    .prompt = "Drop WAV or AIFF files here",
    .picker_title = "Choose Audio File",
    .picker_label = "Choose Audio File",
    .extensions = &.{ ".wav", ".aiff", ".aif" },
    .maximum_files = 2,
}},
```

The adapter accepts only VSTGUI file-path payloads. Matching is case-insensitive and occurs before plugin code runs. One target may accept 1–8 files and 1–8 extensions. Each path must terminate within 1,024 bytes and contain complete UTF-8 before it is copied or passed to plugin code. The callback receives borrowed slices backed by adapter-owned copies and must finish synchronously. Host package storage and pointers never escape the drag callback.

The operating-system picker is the primary action. Pointer activation, Enter, Space, and the accessibility press action all open it. Drag and drop is an equivalent shortcut. Both paths copy and validate files through the same public callback, restore focus after picker completion, and reject late callbacks after teardown.

Idle, drag hover, validating, importing, ready, empty, unsupported type, excessive count, invalid path, cancelled, recoverable failure, and disabled states have distinct visible text and semantic values. Active imports expose bounded progress. Cancel and Retry replace the primary action only while those commands are available. Status, icons or shapes, action labels, and accessibility values carry meaning without relying on color.

`gui_file_importer.Snapshot.validate` rejects impossible path counts, progress, and cancellation states. `gui_audio_file_importer.Snapshot.validate` also enforces the shared preview, frame, channel, sample-rate, and decoded-frame limits. The native bridge validates every snapshot returned by a plugin controller before narrowing fields or exposing it to the adapter. Unknown picker and import-command values are rejected before plugin callbacks. Controller-sourced graph callbacks receive at most 256 points, and oversized results are clamped to that capacity.

Adapter boolean inputs use the C contract values 0 and 1. Other integers are rejected before changing persistent editor state, invoking menu actions, or sending piano notes. Piano commands also validate channel, pitch, finite velocity, velocity range, and note-on velocity before controller or host dispatch.

`FileImporter` is supported. The component gallery, production channel strip, and production IR loader use the same public declaration, bounded path callback, picker fallback, keyboard interaction, accessibility semantics, and lifecycle contract. `FileDrop` remains a source-compatible alias. New code should use `FileImporter` and `EditorDescription.file_importers`.

Import snapshots are validated before publication, including direct native-view updates. Invalid status, failure, entry-point, progress, or preview-count fields preserve the last valid visual and accessibility state.

### IR loader ownership reference

The IR loader composes its importer, progress, waveform graph, viewport, range selection, metadata labels, and edit actions through the public `@import("zig-vst3").vstgui` authoring API. The controller owns the decoded importer and editable source buffers. File reading, WAV decoding, resampling, edits, and convolution preparation run outside the audio callback.

Controller-to-processor transfer uses begin, 1,024-sample chunk, commit, cancel, and clear messages. Each message has fixed attribute counts and at most 4,096 bytes of sample payload. The processor stages data in one of three fixed slots. The audio callback only adopts a complete pending generation and processes precomputed spectra. It performs no file access, allocation, mutex acquisition, or decoding.

The production limit is 131,072 mono or stereo frames with 512-sample convolution partitions. Fixed storage is 1.00 MiB for importer decoding, 3.00 MiB for original, edited, and rollback controller buffers, and 19.02 MiB for the three-slot convolver and its processing history. These capacities are allocated with their owning controller or processor instance, so multiple plugin instances do not share mutable media or work state.

Host state stores parameters and bounded editor metadata, but it does not store an absolute source path or perform hidden file I/O during restoration. Restoring an instance therefore produces an explicit empty-media state until the user imports an IR again. This avoids stale path access and makes missing media deterministic. The IR Loader and Sample Player now share decoded transport. The partitioned convolver is also available through `zig-vst3-plugin.dsp`; the IR Loader remains its production example.

### Sample player ownership reference

The sample player is a second production consumer of `AudioFileImporter`, decoded-audio publication, controller-sourced waveform snapshots, and importer-aware action dependencies. Its full editor declaration lives in `examples/sample_player_editor.zig` and imports only `@import("zig-vst3")`. It accepts one PCM WAV, AIFF, or uncompressed AIFC file with no more than 262,144 mono or stereo frames, 384 kHz sample rate, or the importer and player fixed capacities. Validation, decoding, and preview construction run on the controller-owned worker. Replacement generations and Clear publish complete bounded messages to a three-slot processor store.

The processor adopts a complete generation only at an audio block boundary. Its eight fixed voices provide deterministic oldest-voice stealing, linear interpolation, gain, bipolar pan, tuning, bounded playback and loop ranges, forward or reverse traversal, and ADSR state without allocation, locks, file access, GUI calls, host calls, or logging in processing. Reset and media replacement clear every active voice.

The public `.instrument_workspace` declaration keeps Import, progress, the waveform editor, playback and envelope panels, piano audition, safe metadata, destructive Clear, and resize controls in one reading order. A View action menu frames the entire sample or the parameter-backed playback and loop ranges. Host state stores only parameters, viewport values, and a bounded source basename. It never stores decoded audio or an absolute path, and restoration never opens a file.

## Editable Labels

Declare bounded, persistent text through `EditorDescription.editable_labels`:

```zig
.editable_labels = &.{.{
    .field_id = ir_name_state_id,
    .label = "IR Name",
    .accessible_label = "Impulse response name",
    .placeholder = "Name this impulse response",
    .error_text = "Enter an IR name",
    .maximum_bytes = 64,
}},
```

The field ID addresses a text value in the controller's typed `EditorState`. The maximum is 96 bytes, including only the stored content and not the terminating zero. Field IDs must be nonzero and unique within an editor. Labels, accessible labels, and error text must be nonempty.

Implement `validateEditorText` when a field needs domain validation. A rejected edit stays visible with its inline error so the user can correct it, while the accepted state and accessibility value remain unchanged. Escape restores the accepted value. A successful single-click edit commits on Return or focus loss. External state refreshes when the editor regains focus or its controller values refresh.

Editable labels use the toolkit-neutral text-field role and set-value action. The macOS bridge exposes a native text field. The Windows bridge maps the same node to UI Automation Value semantics.

Use the same declaration for bounded controller-owned values that must update while the editor is open:

```zig
.{
    .field_id = ir_format_state_id,
    .label = "Format",
    .accessible_label = "Impulse response format",
    .read_only = true,
    .maximum_refresh_hz = 10,
},
```

A read-only label polls its typed text field at 1–60 Hz, stops polling when the editor closes, and avoids repainting when the text is unchanged. It has no pointer, keyboard-focus, or set-value action. Native accessibility still exposes the value as a read-only text field. Its plain value presentation does not resemble an editable input. An editor may declare up to eight editable and read-only labels in total.

## Progress Indicators

Declare controller-owned progress through `EditorDescription.progress_indicators`:

```zig
.progress_indicators = &.{.{
    .source_id = ir_import_id,
    .label = "Import",
    .accessible_label = "Impulse response import progress",
    .idle_text = "Choose an IR to begin",
    .running_text = "Importing IR",
    .complete_text = "IR ready",
    .failure_text = "Import failed",
    .maximum_refresh_hz = 20,
}},
```

Implement `loadGuiProgress` and return a `ProgressSnapshot`. Determinate values must be finite and in `[0, 1]`; complete snapshots must equal `1`; indeterminate mode is valid only while running. The generation identifies logical work and lets consumers distinguish replacement from continued progress.

Polling is bounded to 1–60 Hz while the editor is open. Unchanged determinate states do not repaint. Indeterminate state animates a bounded segment. Idle, running, complete, and failed states always expose explicit text, and failure does not rely on color alone. The accessibility node uses meter semantics and exposes a numeric range only for running determinate work.

`EditableLabel`, `ProgressIndicator`, and `ProgressSnapshot` are supported. The gallery and production IR loader use the same public declaration, callback, validation, rendering, lifecycle, and accessibility contracts. External text refresh requires an exact bounded byte count, a terminator at that boundary, no embedded terminator, and complete UTF-8. Malformed callback output preserves the accepted visual and accessibility text. Editable commits reject malformed UTF-8 before invoking the storage callback.

Parameter and XY-pad formatting callbacks use the same exact output contract and must return complete UTF-8. Malformed callback output falls back to bounded numeric text. Exact-value input must terminate within 255 bytes and contain complete UTF-8 before the adapter invokes the parser callback.

## Graph Viewports

Add a bounded viewport to any graph through its public declaration:

```zig
.viewport = .{
    .axes = .horizontal,
    .maximum_zoom = 128.0,
    .zoom_state_id = ir_zoom_state_id,
    .x_offset_state_id = ir_x_offset_state_id,
},
```

The transform supports horizontal, vertical, or uniform two-axis navigation. Zoom is bounded to 1x–128x. Initial offsets must fit the visible span, inactive axes must have zero offsets, zoom multipliers must be in `(1, 4]`, and scroll steps must be in `(0, 1]`. Invalid declarations fail before native editor construction.

State field IDs are optional. When present, each field must be a typed editor-state scalar. Zoom and active offsets commit through one bounded callback so a rejected write cannot leave a partially persisted transform. Reopening the editor restores those values after clamping them to the current declaration.

Use a pointer wheel or trackpad to pan. Command-wheel or Control-wheel zooms around the pointer, as does a native pinch gesture. Plus and minus zoom, arrows pan, Shift with arrows moves faster, Page Up and Page Down move one visible page, Home and End reach a boundary, and 0 restores the initial transform. On an editable graph, plain arrows continue editing the selected point; Command or Control with arrows pans instead.

Each viewport draws a numeric zoom value and a proportional navigator. The accessibility value includes zoom and position. Increment and decrement zoom, set-value selects an exact zoom, and press resets the transform. Zoom changes require finite zoom and anchor values and preserve the complete transform when any value is malformed. The macOS bridge exposes the zoom range and actions through the native graph element. Windows uses the same toolkit-neutral range and action contract.

`Viewport` and `ViewportAxes` are supported. The gallery and production IR loader share their public declaration, bounded model, persistence, interactions, rendering, and accessibility semantics.

## Graph Range Selections

Add a bounded two-handle selection to a graph through its public declaration:

```zig
.range_selection = .{
    .initial_start = 0.2,
    .initial_end = 0.8,
    .minimum_span = 0.01,
    .step = 0.01,
    .start_state_id = selection_start_state_id,
    .end_state_id = selection_end_state_id,
},
```

Selection values use the graph's x-axis units. Both handles remain inside that axis and cannot cross or violate the declared minimum span. Persistent selections require both scalar state fields. The adapter commits them through one bounded callback and restores the prior selection if the controller rejects the write.

Drag either visible handle to adjust one boundary. Drag elsewhere to create a replacement range. Left and Right Bracket choose the start or end handle, Left and Right Arrow adjust it, Shift moves ten steps, Home and End reach a boundary, and Return switches handles. When a viewport is also present, Command or Control with arrows pans without changing the selection.

The selected interval uses a translucent fill plus explicit boundary lines and handle shapes. Focus changes the active handle's weight, so the state does not depend on color. Accessibility exposes the selected interval, active handle, x-axis range, exact set-value, increment, decrement, and handle-selection actions.

A selection may bind directly to two declared parameters instead of editor-state fields:

```zig
.range_selection = .{
    .minimum_span = 0.001,
    .step = 0.001,
    .start_parameter_id = start_parameter_id,
    .end_parameter_id = end_parameter_id,
},
```

Parameter binding uses one ordered two-parameter gesture. Host updates move the matching handle without emitting another edit, and a rejected edit restores both boundaries. Parameter-backed selections cannot also declare editor-state fields.

Hosts may automate the two endpoints independently and in any order. If an update would cross the other endpoint, the automated handle stays within the graph axis and the companion handle moves only far enough to preserve `minimum_span`. This keeps rendering and accessibility values valid even while the host passes through a contradictory intermediate pair. Host-driven repair never emits a gesture back to the host.

Set `secondary_range_selection` to display a second independent range on the same graph. The primary range uses circular markers at the top edge. The secondary range uses square markers at the bottom edge, so overlapping handles remain distinguishable without color. Return cycles through all four handles. Accessibility names the active range as playback or loop selection and exposes its exact value.

`RangeSelection` and `RangeSelectionHandle` with editor-state persistence are supported. The component gallery and production IR loader share their public declaration, bounded model, atomic state callback, interactions, rendering, and accessibility semantics. Direct parameter binding and `secondary_range_selection` remain experimental until another production editor shares those extensions with the sample player.

## API Status

The project remains pre-1.0, so even the supported surface does not yet carry a long-term compatibility promise. The supported list is limited to contracts exercised by both the component gallery and a production-style editor.

Supported authoring surface:

- `Parameter`, the linear, bipolar, rotary, toggle, dropdown, segmented, and decibel control kinds, `Theme`, `Layout`, and the four `create*View` functions.
- `EditorDescription`, `Composition`, `Group`, `StyleOverride`, and `createEditor`.
- `Meter`, meter source wiring, `MeterBank`, and GUI telemetry presentation.
- `Graph`, graph axes and style roles, and grouped graph composition.
- `GraphHandle`, `GraphLayer`, parameter-driven controller curves, mixed-source graph layers, grouped gestures, selection, and linked panel highlighting.
- `WaveformCapture`, activity-gated dynamic graph sources, and production waveform rendering.
- `SpectrumAnalyzer`, fixed-capacity analyzer transport, activity-gated production, bounded snapshot reads, and production spectrum rendering.
- `EnvelopePoint`, bounded editable envelopes, stable selection, snapping, and parameter-backed point gestures.
- `editor_state.Store`, typed editor values, bounded serialization, migrations, and persistent envelope bindings.
- `XYPad`, ordered two-parameter gestures, per-axis semantics, and grouped XY-pad composition.
- `PresetBrowser`, `gui_preset_browser.Browser`, bounded catalogs, persistent filtering and selection, and host-automated loading.
- `ActionMenu`, action, toggle, separator, disabled and destructive item states, anchored overlays, and persistent toggle fields.
- `ActionButton`, primary, secondary, destructive and icon-only roles, grouped toolbar layout, inline confirmation, and recoverable failure feedback.
- `EditableLabel`, bounded typed editor-state text, validation, inline recovery, bounded read-only live values, external refresh, and native text-field semantics.
- `ProgressIndicator` and `ProgressSnapshot`, bounded controller telemetry, determinate and indeterminate presentation, state text, and native progress semantics.
- `Viewport` and `ViewportAxes`, bounded graph zoom and panning, atomic editor-state persistence, visible navigation feedback, and accessible transform actions.
- `RangeSelection` and `RangeSelectionHandle`, bounded two-handle graph selection, atomic editor-state persistence, visible handles, and accessible range editing.
- `Piano`, bounded note ranges, GUI note transport, computer-key input, pointer glissando, and accessible note selection.
- `StepSequencer`, bounded parameter-backed patterns, persistent multi-selection, activity-gated playhead telemetry, and accessible editing.
- `FileImporter`, bounded extension filtering and path copying, an accessible operating-system picker fallback, keyboard interaction, progress presentation, cancellation, retry, and recoverable rejection feedback.
- Standard parameter binding, host updates, formatting, parsing, focus, resizing, and per-instance lifecycle.
- Theme and layout selection through `Skin`.
- `Asset`, `Fonts`, `DrawingCallbacks`, `DrawRequest`, and bounded `Canvas` drawing functions.

Experimental extensions:

- `ActionButton.success_focus_importer_id` and `ActionButton.ready_importer_id`. The gallery, IR loader, and sample player exercise the same dependency behavior. The sample-player host walkthrough remains the promotion blocker.
- Direct parameter-backed graph ranges and `Graph.secondary_range_selection`. The visual gallery and sample player exercise them, but a second production consumer is still required.
- Fixed graph point storage and direct `SnapshotSeries` use. The production signal views use the higher-level bounded capture and analyzer types.
- Native assistive-technology bridges. macOS is integration-tested, Windows is cross-compiled, and Linux has tested semantic mapping plus application-root, Accessible, Component, Action, Value, Unicode-segmented single-line Text queries, Unicode-delta text-change events, X11 clipboard-backed EditableText, bulk Cache publication, cache lifecycle signals, and property, state, focus, and bounds events. Caret and selection integration, exact text layout, pure-Wayland clipboard ownership, and native screen-reader workflows remain unverified.
- `AudioFileImporter`, controller-owned import status and command callbacks, decoded-audio transport, controller-sourced graph snapshots, and importer-aware action dependencies. The gallery now decodes a bounded fixture and exercises idle, progress, ready, failure, retry, reset, waveform, and action-dependency behavior through the same contract used by the IR loader and sample player. The sample-player host walkthrough remains the promotion blocker.
- Additional modulation component types and GPU-backed custom views. Neither has a public declaration or a production consumer. A GPU path also requires profiling evidence that the toolkit-managed renderer is the limiting factor.

Experimental extensions may change when a second production editor establishes their required shape. They are kept out of the supported list even though the gallery validates their current implementation.

## Verification

Run the native adapter tests and example validation after changing a component declaration:

```sh
zig build vstgui-adapter
zig build test raw-api-abi validate-examples
zig build pluginval-channel-strip
```

The native suite covers parameter routing, interaction, layout selection, theme selection, assets, accessibility semantics, visual references, and the warm-render budget. The example suites verify lifecycle and protocol behavior through real plugin bundles. pluginval opens editors, but its pass result does not verify visible text, geometry, clipping, scrolling, or appearance. Inspect the installed bundle in a real host for those claims. The aggregate pluginval target is serialized. Stop after the first unexpected exit, preserve its artifacts, and treat it as a plugin failure until isolation proves otherwise.
