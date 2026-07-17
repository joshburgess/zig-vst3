# Plugin Editors

`zig-vst3-plugin` separates editor behavior from rendering. The framework API owns parameter gestures, accepted state, resize rules, scale, and lifecycle. A GUI adapter owns native embedding, widgets, input, and drawing.

The reference integration uses VSTGUI behind a narrow C ABI. It is enabled only for native macOS, Windows, and Linux builds. Cross-target bundles keep the protocol-only editor because the native VSTGUI static library cannot be reused for another target.

## Framework API

Import the editor types from `zig-vst3-plugin`:

```zig
const plug = @import("zig-vst3-plugin");

const Editor = plug.gui.Editor;
const ParameterAttachment = plug.gui.ParameterAttachment;
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

Overflow is a visual quality loss, never a reason to wait on the audio thread. The processor must not allocate, lock a GUI mutex, call the operating system, or perform unbounded work for an editor.

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
