# Plugin Editors

`zig-vst3-plugin` separates editor behavior from rendering. The framework API owns parameter gestures, accepted state, resize rules, scale, and lifecycle. A GUI adapter owns native embedding, widgets, input, and drawing.

The reference integration uses VSTGUI behind a narrow C ABI. It is enabled only for native macOS, Windows, and Linux builds. Cross-target bundles keep the protocol-only editor because the native VSTGUI static library cannot be reused for another target.

## Framework API

Import the editor types from `zig-vst3-plugin`:

```zig
const plug = @import("zig-vst3-plugin");

const Editor = plug.gui.Editor;
const ParameterAttachment = plug.gui.ParameterAttachment;
const XYAttachment = plug.gui.MultiParameterAttachment(2);
const EnvelopeAttachment = plug.gui.ParameterEnvelopeAttachment(4);
```

Implement `plug.gui.Context.VTable` in the controller. It provides current values and reflected metadata, formats and parses values, delegates resize and repaint requests, and forwards host parameter context menus. Implement `plug.gui.Adapter.VTable` in the toolkit integration. It receives attach, detach, resize, scale, focus, parameter-change, and destruction callbacks.

All editor, context, and adapter callbacks run on the host GUI thread. A plugin must not call them from its audio processor.

`ParameterAttachment` is the reusable control binding. It owns at most one active gesture and provides:

- Begin, perform, end, and cancellation ordering.
- Rollback to the last accepted value after rejection.
- Continuous and stepped normalization.
- Default reset through a complete host gesture.
- Fine adjustment without replacing exact text entry.
- Host automation updates that do not emit a second gesture.
- Formatting and parsing through controller metadata.

`MultiParameterAttachment(count)` composes a fixed, duplicate-free set of parameter attachments into one interaction. It begins, publishes, and ends every parameter in declaration order. If any host edit is rejected, it restores every visible value to the gesture's initial values and ends every parameter that began. Host automation can update either axis without emitting a gesture. This is the toolkit-neutral binding used by the XY pad and future linked controls.

`ParameterEnvelopeAttachment(count)` associates stable envelope point IDs with pairs of parameter IDs. Point movement delegates to `MultiParameterAttachment(2)`, so both coordinates share ordered begin, perform, rollback, and end behavior. This is appropriate when an envelope handle represents automatable plugin parameters. `gui_graph.EditableEnvelope(capacity)` is the fixed-capacity transactional model for non-parameter envelopes. It owns stable IDs, selection, snapping, insertion order, rollback, and bounded point storage without a rendering dependency.

`ParameterPanel(count)` creates a fixed-size development panel model from reflected parameter IDs. Adapters can use its attachments to generate ordinary float, integer, boolean, and enum controls without duplicating gesture logic.

## Reference VSTGUI Adapter

The adapter lives in `gui-adapters/vstgui`. Its C++ objects do not enter the public Zig API. The adapter maps VST3 platform parents to the matching VSTGUI type:

| VST3 parent | VSTGUI platform |
| --- | --- |
| `NSView` | `kNSView` |
| `HWND` | `kHWND` |
| `X11EmbedWindowID` | `kX11EmbedWindowID` |
| `WaylandSurfaceID` | `kWaylandSurfaceID` |

On X11, the view queries the host `IPlugFrame` for `IRunLoop` and adapts VSTGUI event and timer registrations to it. The adapter does not start a standalone application loop inside the host. On Wayland, the controller also requests `IWaylandHost` from the host application and the adapter queries the plug frame for `IWaylandFrame`. Native Linux builds require Wayland development libraries, `wayland-scanner`, protocol descriptions, and the pinned `wayland-server-delegate` source fetched by VSTGUI's CMake build.

Build the pinned native library with:

```sh
zig build vstgui-adapter
```

Build and validate the reference editor with:

```sh
zig build bundle-gain
zig build validate-gain
zig build pluginval-gain
```

The current visible reference control supports pointer dragging, arrow keys, Home and End, exact text entry, resize constraints, and content scale. Default reset uses Command-click on macOS and Control-click on Windows and Linux. Host parameter changes are broadcast through a bounded per-controller observer list, so open views follow automation and restored state without producing a new gesture.

The native adapter creation contract at ABI version 14 accepts 1–64 parameter descriptions, up to eight XY pads, up to two preset browsers with 64 entries each, up to four action menus with 16 items each, up to two piano keyboards with 48 notes each, bounded editable-envelope metadata, and persistent field IDs for editor-local state. Each parameter carries its ID, initial normalized value, label, units, step count, default, and presentation kind. Host updates and bulk state refreshes are addressed by parameter ID. The adapter rejects duplicate parameter IDs, invalid XY axis references, malformed point IDs, unbounded envelopes, invalid parameter-backed points, duplicate preset or menu IDs, malformed menu items, invalid piano ranges, invalid persistent state fields, and persistent bindings without a declared controller store before creating an editor. `zig_vst3_editor_smoke` is the multi-parameter integration fixture. Its editor binds continuous, integer, boolean, enum, linked XY, editable-envelope, preset-browser, action-menu, piano-keyboard, and persistent editor-state interactions.

Each description also selects a presentation kind: `linear_slider`, `rotary_knob`, `toggle`, `enum_dropdown`, or `segmented_enum`. The control keeps reflected formatting, parsing, quantization, automation gestures, host playback, default reset, focus, and context-menu behavior regardless of presentation. Numeric controls include exact text entry. Labels append units when supplied. Editors provide both a compact/expand action and a draggable lower-right resize handle.

The VSTGUI adapter resolves semantic color, spacing, typography, radius, and control-metric tokens through a component theme. Editor-wide and component-specific overrides compose with normal, hovered, pressed, focused, disabled, and editing states. `Skin.theme` selects the default dark theme or alternate light theme. Set `ZIG_VSTGUI_THEME=alternate` when launching a validator or host to override an editor that requests the default theme during testing.

The adapter also provides fixed-capacity row, column, and grid layout primitives. Stack items define minimum main-axis and cross-axis sizes plus flexible growth. Grid tracks define minimum sizes and flexible growth, and grid items can span rows or columns. Padding, gaps, and alignment use logical coordinates. VSTGUI applies display scaling after layout through the editor zoom factor.

The `.adaptive` layout uses a compact composition below 520 by 360 and an expanded composition at or above that size. The `.compact_strip` layout keeps dense label, control, and value rows for smaller production editors. Their supported range is 320 by 240 through 1000 by 700. Editors with a preset browser require at least 480 by 480 and initially request 720 by 600. Tab and Shift+Tab follow visible reading order: each parameter's primary control, its exact value field when present, each composite component, and the resize action. Focus wraps at either end.

See [VSTGUI Component Authoring](vstgui-components.md) for the public Zig declarations, the component gallery, a production-style editor, and the supported versus experimental API boundary.

### Assets, Fonts, and Custom Drawing

`createMultiViewWithSkin` accepts the ordinary parameter and meter descriptions plus a `Skin`. A skin can provide up to 16 immutable assets, font-family preferences, and a component drawing callback. The adapter copies every asset byte during editor creation. The editor owns the decoded PNGs, parsed SVG paths, font descriptors, and drawing overlays until that editor is destroyed. Reopening an editor rebuilds its views against the same owned resources, so callbacks never depend on temporary Zig slices or a previous native frame.

PNG is the portable bitmap format. Each bitmap or SVG selects one scale rule:

- `pixel_exact` keeps one asset unit per logical GUI unit and centers the result.
- `contain` preserves aspect ratio and fits the whole asset inside the destination.
- `cover` preserves aspect ratio and fills the destination, clipping the excess.
- `stretch` maps the asset directly to the destination on both axes.

VSTGUI does not provide a portable SVG loader in the pinned revision. The adapter therefore parses a deterministic vector subset itself. SVG files must provide a `viewBox` and one or more `path` elements. Path data supports absolute and relative `M`, `L`, `H`, `V`, `C`, and `Z` commands. Fill and stroke accept `#RRGGBB`, `#RRGGBBAA`, or `none`; `stroke-width` is supported. Arcs, transforms, filters, text, external references, scripts, and animation are rejected during editor creation. Convert unsupported artwork to cubic paths or PNG before embedding it.

Invalid asset data rejects editor creation. A drawing callback that requests an unknown asset ID receives `false`, and the adapter paints a red crossed placeholder in the requested bounds. Missing artwork therefore cannot leave an invisible interactive control.

Font preferences are family names for title, body, and value text, plus one fallback family. The adapter uses the preferred family when the operating system reports it, then the fallback family, then the theme's system font. It does not register font files or bypass operating-system font rules. Plugin authors are responsible for confirming that a font license permits the intended use and redistribution before packaging a font outside this API.

The drawing callback receives a toolkit-neutral component kind, visual state, parameter ID, normalized value, logical dimensions, scale factor, and opaque canvas. Canvas functions draw rectangles, ellipses, lines, and registered assets. The canvas is valid only for that synchronous callback. Returning a nonzero result paints the missing-art placeholder. The overlay is non-interactive and leaves the standard parameter control, host gesture attachment, keyboard input, exact entry, focus, and accessibility metadata in place. Keep callbacks bounded and allocation-free during drawing.

Filmstrip and sprite controls are not part of the current skin API. No accepted reference design requires them, and the vector, bitmap, and primitive drawing paths already cover the gallery. Add a multi-frame abstraction only when a production control defines its frame layout, scale behavior, and interaction states.

### Visual Regression Tests

The native adapter test build renders fixed headless references through VSTGUI. `control-states-1x.png` and `control-states-2x.png` show normal, hovered, pressed, focused, disabled, and editing slider states from left to right. `meters-assets.png` covers SVG, the visible missing-asset placeholder, and peak, stereo, and gain-reduction meters. The PNG asset is also decoded and validated by the native resource tests.

Each run compares decoded pixels with a channel tolerance of 80 and allows at most 2 percent of pixels to exceed it. The broad channel tolerance absorbs macOS display-profile conversion while exact theme token colors remain covered by unit tests. Geometry, missing regions, large color changes, and state changes still fail the image comparison. A failure writes the actual image and a magenta difference mask under `.vst3-sdk/vstgui-adapter-build/visual-regression`.

`zig build vstgui-adapter` runs interaction tests and visual comparisons. After intentionally reviewing an appearance change, update the references with:

```sh
cmake --build .vst3-sdk/vstgui-adapter-build --target zig_vstgui_visual_tests_update
```

The same harness measures repeated warm drawing of a live slider and active peak meter. It fails above the 300 microsecond warm-frame budget recorded in `docs/gui-baseline.md`.

### Accessibility Semantics

Every VSTGUI component carries toolkit-neutral accessibility metadata. Semantic roles cover sliders, buttons, toggles, choices, text fields, meters, graphs, and groups. Nodes expose a name, description, formatted value, optional range, enabled state, focus state, toggle state, selection state, and read-only state. Nodes also expose supported focus, press, increment, decrement, and set-value actions. Value, focus, and state changes invoke a backend observer while native actions use the same component behavior as pointer and keyboard input.

The reference adapter supplies native semantic bridges because the pinned VSTGUI revision does not provide them for custom controls. macOS uses an `NSAccessibilityElement` hierarchy. Windows uses a UI Automation fragment provider with RangeValue, Toggle, Invoke, and Value patterns. X11 and Wayland retain keyboard operation, visible focus, and internal semantics but have no AT-SPI bridge. VoiceOver, Narrator, and AT-SPI behavior still require manual verification before claiming accessible release support.

VSTGUI dependencies remain optional at the package boundary. A plugin can implement the same framework adapter with another toolkit or a custom renderer.

### Rendering Measurements

Set `ZIG_VSTGUI_PROFILE=1` in the host environment to emit one summary when each editor is destroyed:

```sh
ZIG_VSTGUI_PROFILE=1 pluginval --strictness-level 5 path/to/plugin.vst3
```

The summary reports content draw count, average and maximum draw time, total invalidated pixel area, successful opens and closes, accepted resizes and scale changes, and parameter updates. Timing is disabled unless the environment variable is present. The counters stay on the GUI thread and do not affect audio processing.

Use these measurements before adding render threads, dirty-region bookkeeping, or multiple buffered frame states. The reference parameter editor has no continuous animation loop, texture uploads, or graphics device owned by the adapter. Those mechanisms should be introduced only when a representative editor demonstrates a measurable need.

## Real-time-safe Telemetry

Parameter controls do not need an audio-to-GUI message queue. For meters and analyzers, use `plug.gui_telemetry`:

- `ScalarSnapshot(f32)` or `ScalarSnapshot(f64)` stores the latest scalar without a lock.
- `SpscQueue(T, capacity)` transports bounded visualization records from one producer to one consumer. A full queue drops new records and counts them.
- `RepaintCoalescer` allows only one pending repaint request.
- `EditorActivity` lets the processor skip editor-only analysis while every editor is closed.
- `MeterBank(Float, count)` combines fixed scalar snapshots with editor activity. `publish` is a bounded atomic store while any editor is open and a no-op while all editors are closed.

The VSTGUI adapter provides peak, stereo, and gain-reduction meters. Meter descriptions select one or two scalar source IDs. A 33 millisecond GUI timer loads the latest snapshots, applies peak hold and decay, updates semantic value text, and invalidates only when the displayed state changes. The timer starts after attachment and stops before removal. Editors without meters create no timer.

Peak and gain-reduction sources use normalized values from 0 to 1. Stereo meters use two independent normalized sources. Audio-thread publishers should compute one bounded scalar per source and call `MeterBank.publish`; all ballistics, formatting, drawing, and repaint work stays on the GUI thread.

Overflow is a visual quality loss, never a reason to wait on the audio thread. The processor must not allocate, lock a GUI mutex, call the operating system, or perform unbounded work for an editor.

Spectrum analyzers are intentionally not part of the current component set. Define a representative plugin, bin count, update rate, queue capacity, and overflow behavior before adding one.

## Persistent Editor State

Use `plug.editor_state.Store(schema_version, fields)` for bounded state that belongs to the editor rather than the processor. A schema declares stable nonzero field IDs, types, and defaults at compile time. Supported values cover booleans, signed integers, finite scalars, indexes, selected point IDs, finite points, short text, and envelopes with up to 32 points.

```zig
const EditorState = plug.editor_state.Store(1, &.{
    .{ .id = 1, .default = .{ .boolean = true } },
    .{ .id = 2, .default = .{ .index = 0 } },
    .{ .id = 3, .default = .{ .point_id = 2 } },
    .{ .id = 4, .default = .{ .envelope = default_envelope } },
});
```

Declare `pub const EditorState = EditorStateType` on a reflected controller configuration. The VST3 controller `getState` and `setState` methods then serialize a composite with separate parameter and editor sections, while `setComponentState` continues to accept the processor's parameter-only snapshot. Editor state never enters the processor, process callback, or audio thread.

The binary format carries independent wire and schema versions. Decode limits entry count and payload size, validates every known value, ignores unknown field IDs and value kinds, supports explicit field-ID migrations, and commits only after the complete payload succeeds. Malformed or truncated data leaves the live store unchanged. A controller owns one store per plugin instance, and every view created by that controller observes the same restored state.

`gui_preset_browser.Browser(capacity)` supplies the bounded search, selection, keyboard navigation, and load-status model used by the native preset browser. It persists search text and selection through declared editor-state fields. Both the component gallery and channel strip exercise the shared model and native component contract.

## Lifecycle Checklist

For every editor implementation:

1. Allocate a view per `createView` call.
2. Retain its controller while the view exists.
3. Attach one native child to the host parent.
4. Preserve the last accepted size and scale when a callback rejects a change.
5. End or cancel active gestures before detaching.
6. Unregister parameter observers before destroying controls.
7. Stop timers, analysis, and repaint production when the editor closes.
8. Release the native surface, toolkit objects, controller, and view exactly once.

## Migration From Singleton Helpers

Controllers, components, processors, and views are allocated per factory call. Controller helper functions now receive `*IEditController`, and component helper functions receive `*IComponent`. Code that read a module-level parameter store must instead use the instance passed to the callback. Stateful processors keep their mutable state in the processor value owned by the component.

This is an intentional API correction. It prevents parameter values, host interfaces, note state, and editor lifetime from leaking between two instances of the same plugin.
