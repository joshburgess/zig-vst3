# GUI Adapter Evaluation

This spike compares the pinned VSTGUI integration with a lightweight custom renderer at the boundary required by `zig-vst3`.

## Result

VSTGUI is the reference adapter. It produced a visible macOS editor through a narrow C ABI and passed the Steinberg validator and pluginval editor tests. A custom renderer remains a supported future adapter, but the prototype boundary showed that it would need platform text, input, accessibility, window embedding, and graphics work before it could validate the plugin framework.

## Comparison

| Concern | VSTGUI adapter | Lightweight custom renderer |
| --- | --- | --- |
| Core dependency | Optional static C++ library behind `gui-adapters/vstgui` | Optional Zig adapter |
| License | BSD-style VSTGUI license in the pinned SDK | Repository license plus licenses for chosen text and graphics dependencies |
| Native embedding | Built-in NSView, HWND, and X11 frame implementations | Must be implemented for each platform |
| Wayland | Preliminary VSTGUI path requires Wayland support and its server-delegate dependency | Must implement `IWaylandFrame`, surface lifecycle, input, and text input |
| Text | Native VSTGUI platform text and text-edit implementations | Requires font discovery, shaping or platform text, editing, selection, and IME handling |
| Accessibility | Limited framework-level semantic API for custom controls | Must design a semantic tree and native accessibility bridges |
| Input and focus | Toolkit pointer, wheel, keyboard, focus, and text controls | Must normalize every native event path |
| Cross-compilation | Native static toolkit build is reliable. Cross-target builds need a separately built target library | Zig renderer code can cross-compile, but native text and platform libraries still need target artifacts |
| X11 event loop | VSTGUI supplies X11 platform code and dependencies | Must register file descriptors and timers through `IRunLoop` |
| Rendering control | Toolkit-managed CPU/platform rendering | Full control over invalidation, batching, GPU backends, and buffers |
| First useful editor | Implemented | Not implemented because platform foundations dominate the work |

## Build Boundary

`scripts/build_vstgui.sh` configures the core `vstgui` static library and the narrow C++ shim in one CMake build, so both archives use the same C++ compiler and ABI. Standalone applications, examples, tools, unit tests, OpenGL, XML parsing, and UI scripting are disabled. Zig links the two native archives and their platform libraries only into examples that expose the reference editor.

Native macOS uses Cocoa, QuartzCore, Accelerate, and UniformTypeIdentifiers. Native Windows links the Win32 graphics and control libraries required by VSTGUI. Native Linux resolves the X11, XCB, XKB, Cairo, Pango, Fontconfig, FreeType, GLib, Wayland, thread, and dynamic-loader libraries through pkg-config. A Wayland build also requires `wayland-scanner`, the standard Wayland protocol descriptions, and network access the first time CMake fetches VSTGUI's pinned `wayland-server-delegate` dependency.

The normal cross-target editor bundle does not attempt to link a host-built VSTGUI archive into another target. It uses the protocol view instead. A future build option can accept a prebuilt target archive and sysroot when reproducible cross-target GUI bundles become necessary.

## Known Constraints

- The macOS adapter has automated host-like evidence, but no recorded DAW row yet.
- Windows and Linux adapter mappings are implemented but need native build and real-host verification. The X11 path adapts the host `IRunLoop` into VSTGUI file-descriptor and timer handlers, and its Linux translation unit cross-compiles with Zig.
- The Wayland path requests `IWaylandHost` from the host application, obtains `IWaylandFrame` and `IRunLoop` from the plug frame, and passes those interfaces to VSTGUI. The implementation still needs a native Wayland build and real-host result.
- VSTGUI does not provide a strong toolkit-neutral semantic accessibility layer for these custom controls. Keyboard operation, visible focus, exact text entry, and labels are present, but native screen-reader verification remains a release gate.
- The reference editor has no continuous animation loop. VSTGUI invalidates controls only for input, value changes, resize, scale, and exposure.

## Custom Renderer Spike Boundary

The toolkit-neutral `gui.Editor`, `gui.Context`, `gui.Adapter`, parameter attachments, and telemetry types are the custom-renderer prototype. They prove that a renderer can remain outside VST3 and toolkit types. The missing work is intentionally platform-facing:

1. Create native child surfaces for all four parent types.
2. Choose a text and IME strategy.
3. Define accessibility semantics and native bridges.
4. Implement pointer, wheel, keyboard, focus, and context-menu routing.
5. Choose one graphics backend and handle loss and recreation.
6. Measure representative editors before adding render threads, damage regions, or multiple frame states.

Ghostty supports the final point: keep platform shells separate, render from snapshots, reuse buffers, and skip clean frames. Its terminal-specific render threading, glyph atlas, and high-refresh assumptions are not defaults for a static plugin panel.
