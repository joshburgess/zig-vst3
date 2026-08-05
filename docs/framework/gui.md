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

`Context.requestHostValue` asks the current host to obtain an infrequently changed value such as a file path. The request uses validated absolute URI strings for its key and optional value type, so toolkit-neutral editor code does not depend on a plugin format's numeric identifiers. It reports accepted, busy, unknown, or unsupported without waiting for the value. Missing format support returns unsupported. Keys and types are limited to 4,096 bytes and reject interior NULs, malformed percent escapes, non-ASCII bytes, control bytes, and URI delimiters that are unsafe in metadata.

`Context.subscribeHostPeak` and `unsubscribeHostPeak` let an editor receive standard host peak measurements by stable port symbol. The default `.dynamic` delivery asks the host to add or remove a runtime subscription. `.static` registers a source that the plugin's generated UI metadata already declares and does not invoke the dynamic host callback. The editor assigns a format-neutral source ID, which is returned with each `HostPeakMeasurement`. A measurement includes the host period start, period size, and nonnegative finite peak value. Symbols use the portable plugin-symbol grammar and are limited to 255 bytes. Each editor can retain up to 16 subscriptions without allocation. Repeating the same registration succeeds without a second host call. A port cannot be reassigned to another source ID or delivery mode, and a source ID cannot identify two ports. `Editor.hostPeakMeasurement` validates every measurement before invoking the optional adapter callback. All registration and delivery calls use the GUI thread.

`Context.registerHostAtomNotification` and `unregisterHostAtomNotification` bind a statically declared event-output notification to a format-neutral source ID. The registration uses a stable port symbol and an absolute Atom type URI. Each editor retains at most 16 unique port-and-type bindings without allocation. Repeating an exact registration is idempotent, while reusing a source ID or assigning a second source to the same binding is rejected. `Editor.hostAtomMessage` passes the message body to the optional adapter callback only during the call. Backends that need the body later must copy it. Bodies larger than 64 KiB and malformed retained messages are rejected.

`Context.sendPluginAtomMessage` sends one typed message from an editor to a plugin event input. The format-neutral message identifies the input by stable port symbol and its type by absolute URI. Bodies are borrowed for the duration of the call and limited to 64 KiB. The result distinguishes accepted, unsupported, and rejected delivery. Invalid symbols, URIs, or sizes return `error.InvalidParameter` before reaching a plugin-format adapter. This is an infrequent UI-thread path, not an audio-thread communication API.

`ParameterAttachment` is the reusable control binding. It owns at most one active gesture and provides:

- Begin, perform, end, and cancellation ordering.
- Rollback to the last accepted value after rejection.
- Continuous and stepped normalization.
- Default reset through a complete host gesture.
- Fine adjustment without replacing exact text entry.
- Host automation updates that do not emit a second gesture.
- Formatting and parsing through controller metadata.

`MultiParameterAttachment(count)` composes a fixed, duplicate-free set of parameter attachments into one interaction. It begins, publishes, and ends every parameter in declaration order. If any host edit is rejected, it restores every visible value to the gesture's initial values and ends every parameter that began. Host automation can update either axis without emitting a gesture. This is the toolkit-neutral binding used by the XY pad and future linked controls.

`ParameterEnvelopeAttachment(count)` associates stable envelope point IDs with pairs of parameter IDs. Point movement delegates to `MultiParameterAttachment(2)`, so both coordinates share ordered begin, perform, rollback, and end behavior. This is appropriate when an envelope handle represents automatable plugin parameters. `gui_graph.EditableEnvelope(capacity)` is the fixed-capacity transactional model for non-parameter envelopes. It owns stable IDs, selection, snapping, insertion order, rollback, and bounded point storage without a rendering dependency. Inactive and vacated points start empty, while finishing or cancelling a transaction clears its rollback snapshot. Its borrowed point view rejects invalid ranges, points, ordering, IDs, selection, and transaction state. `gui_graph.FixedSeries(capacity)` initializes inactive points deterministically and exposes a view only while its retained count and active points are valid.

`ParameterPanel(count)` creates a fixed-size development panel model from reflected parameter IDs. Adapters can use its attachments to generate ordinary float, integer, boolean, and enum controls without duplicating gesture logic.

`gui_audio_sample_store.Store(maximum_frames)` publishes complete decoded mono or stereo audio through three fixed slots. Adoption validates pending metadata and received extent before replacing active audio. Malformed pending state is released without evicting the active generation. Active metadata and interpolated reads fail closed for malformed extents, non-finite samples, or non-finite derived output.

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

Reference comparisons run on the native renderer used to approve the stored images. Other platform renderers use `--platform-smoke`: every scene must produce an accessible native bitmap with nonzero dimensions and nonuniform pixels. This preserves Windows Direct2D coverage without requiring an optional bitmap-codec path or interpreting font rasterization and renderer-specific antialiasing as product appearance regressions. Canonical-renderer tests continue to exercise PNG encoding and decoding. Neither path replaces manual visual confirmation on each platform.

`zig build vstgui-adapter` runs interaction tests and visual comparisons. After intentionally reviewing an appearance change, update the references with:

```sh
cmake --build .vst3-sdk/vstgui-adapter-build --target zig_vstgui_visual_tests_update
```

The same harness measures repeated warm drawing of a live slider, active peak meter, piano, step sequencer, file-drop target, and maximum-capacity waveform and spectrum pair. `file-drops.png` covers idle, acceptable, and recoverable handler-failure states. `signal-views.png` covers a waveform, populated spectrum, and empty spectrum. The harness reports the best of three 100-frame CPU-time batches so an unrelated scheduler pause does not masquerade as rendering cost. Individual scenes fail above a 300 microsecond warm-frame budget. The combined maximum-capacity waveform and spectrum stress scene has a 450 microsecond budget because it draws two full graph surfaces per frame.

### Accessibility Semantics

Every VSTGUI component carries toolkit-neutral accessibility metadata. Semantic roles cover sliders, buttons, toggles, choices, text fields, meters, graphs, and groups. Nodes expose a name, description, formatted value, optional range, enabled state, focus state, toggle state, control selection state, read-only state, and optional Unicode-positioned text anchor and caret. Nodes also expose supported focus, press, increment, decrement, set-value, caret, and text-selection actions. Text positions reject malformed UTF-8 and out-of-range offsets. Shorter replacement values clamp retained positions before observers run. Read-only nodes still permit focus and text navigation when their provider supports those actions, while content mutation remains rejected. Value, focus, state, caret, and selection changes invoke a backend observer while native actions use the same component behavior as pointer and keyboard input.

The reference adapter supplies native semantic bridges because the pinned VSTGUI revision does not provide them for custom controls. macOS uses an `NSAccessibilityElement` hierarchy. Windows uses a UI Automation fragment provider with RangeValue, Toggle, Invoke, and Value patterns. Linux publishes an AT-SPI application tree with component, action, value, checked single-line text-query, editable-text, cache, and event interfaces. X11 supplies clipboard exchange for editable text through UTF-8 targets and conditionally advertises the legacy `STRING` target when the current value is exactly representable as Latin-1. On Wayland, the adapter loads the client library at runtime and uses the version-1 external data-control protocol when the compositor exposes it. The Wayland path retains bounded UTF-8 selections, serves three common text MIME types, rejects malformed or oversized data, limits pipe transfers to 250 milliseconds, and falls back to X11 when data control is unavailable. VoiceOver, Narrator, live Wayland clipboard behavior, and AT-SPI behavior still require manual verification before claiming accessible release support.

VSTGUI dependencies remain optional at the package boundary. A plugin can implement the same framework adapter with another toolkit or a custom renderer.

### Rendering Measurements

Set `ZIG_VSTGUI_PROFILE=1` in the host environment to emit one summary when each editor is destroyed:

```sh
ZIG_VSTGUI_PROFILE=1 pluginval --strictness-level 5 path/to/plugin.vst3
```

The summary reports content draw count, average and maximum draw time, total invalidated pixel area, successful opens and closes, accepted resizes and scale changes, and parameter updates. Timing is disabled unless the environment variable is present. The counters stay on the GUI thread and do not affect audio processing.

Use these measurements before adding render threads, dirty-region bookkeeping, or multiple buffered frame states. The reference parameter editor has no continuous animation loop, texture uploads, or graphics device owned by the adapter. Those mechanisms should be introduced only when a representative editor demonstrates a measurable need.

## Real-time-safe Telemetry

Parameter controls do not need an audio-to-GUI message queue. For meters and analyzers, use `plug.gui_telemetry` and `plug.gui_graph`:

- `ScalarSnapshot(f32)` or `ScalarSnapshot(f64)` stores the latest scalar without a lock. `valid` reports a malformed retained payload while `load` continues to contain it as silence.
- `SpscQueue(T, capacity)` transports bounded visualization records from one producer to one consumer. A full queue drops new records and counts them. Storage starts with the type's zero value. Its quiescent `valid` query checks the wrapping cursor distance, and the consumer resynchronizes malformed cursors without reading unpublished storage. After both endpoints stop, `reset` clears every slot, cursor, and drop count.
- `RepaintCoalescer` allows only one pending repaint request.
- `EditorActivity` lets the processor skip editor-only analysis while every editor is closed.
- `MeterBank(Float, count)` combines fixed scalar snapshots with editor activity. `publish` is a bounded atomic store while any editor is open and a no-op while all editors are closed. Its `valid` query composes every retained snapshot.
- `WaveformCapture(capacity)` performs bounded block reduction and publishes normalized sample points.
- `SpectrumAnalyzer(fft_size)` performs one bounded radix-2 FFT at most once per process call and publishes decibel bins through a fixed snapshot.

Graph snapshot publication and reading both require finite coordinates. Readers also reject a retained point count beyond fixed storage or caller output instead of exposing malformed telemetry.

Quiescent graph validity composes the atomic coordinate payloads with publication phase and active point extent. Waveform capture forwards that query. Spectrum analysis also validates its sample ring, buffered phase, and fixed window while leaving transient FFT scratch outside the retained-state contract.

The VSTGUI adapter provides peak, stereo, and gain-reduction meters. Meter descriptions select one or two scalar source IDs. A 33 millisecond GUI timer loads the latest snapshots, applies peak hold and decay, updates semantic value text, and invalidates only when the displayed state changes. The timer starts after attachment and stops before removal. Editors without meters create no timer.

Peak and gain-reduction sources use normalized values from 0 to 1. Stereo meters use two independent normalized sources. Audio-thread publishers should compute one bounded scalar per source and call `MeterBank.publish`; all ballistics, formatting, drawing, and repaint work stays on the GUI thread.

Overflow is a visual quality loss, never a reason to wait on the audio thread. The processor must not allocate, lock a GUI mutex, call the operating system, or perform unbounded work for an editor.

The gallery and channel-strip processors both use 30 Hz views. The channel strip captures up to 128 waveform points and uses a 128-sample FFT with 64 positive-frequency bins. Snapshot contention or insufficient reader capacity drops a visual frame. It never blocks processing or changes audio output.

## Persistent Editor State

Use `plug.editor_state.Store(schema_version, fields)` for bounded state that belongs to the editor rather than the processor. A schema declares stable nonzero field IDs, types, and defaults at compile time. Supported values cover booleans, signed integers, finite scalars, indexes, selected point IDs, finite points, validated UTF-8 text up to 96 bytes, and envelopes with up to 32 points.

```zig
const EditorState = plug.editor_state.Store(1, &.{
    .{ .id = 1, .default = .{ .boolean = true } },
    .{ .id = 2, .default = .{ .index = 0 } },
    .{ .id = 3, .default = .{ .point_id = 2 } },
    .{ .id = 4, .default = .{ .envelope = default_envelope } },
});
```

Declare `pub const EditorState = EditorStateType` on a reflected controller configuration. The VST3 controller `getState` and `setState` methods then serialize a composite with separate parameter and editor sections, while `setComponentState` continues to accept the processor's parameter-only snapshot. Editor state never enters the processor, process callback, or audio thread.

The binary format carries independent wire and schema versions. Decode limits entry count and payload size, validates every known value, ignores unknown field IDs and value kinds, supports explicit field-ID migrations, and commits only after the complete payload succeeds. Malformed or truncated data leaves the live store unchanged. Public text and envelope values validate their retained lengths before returning slices, and envelope views also reject invalid, non-finite, or unordered points. A controller owns one store per plugin instance, and every view created by that controller observes the same restored state.

`gui_preset_browser.Browser(capacity)` supplies the bounded search, selection, keyboard navigation, and load-status model used by the native preset browser. Preset storage starts deterministically empty, and insertion rejects malformed retained text as well as invalid and duplicate identifiers. It persists search text and selection through declared editor-state fields. Both the component gallery and channel strip exercise the shared model and native component contract.

`gui_file_drop.DropZone(file_capacity, extension_capacity)` copies accepted paths into fixed storage and filters them against validated extensions. Path arrays start at zero. Each inspection clears the previous path set before accepting a replacement, and rejected inspections or explicit reset scrub all retained path bytes.

`gui_audio_file_importer.DecodedImporter(frame_capacity)` keeps preview points and optional decoded interleaved samples in fixed storage for non-audio-thread handoff. Initialization, replacement, failure, cancellation teardown, and reset clear that retained media storage before publishing an empty logical extent.

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
