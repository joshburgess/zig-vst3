# ADR 0001: Keep GUI Toolkits Behind an Adapter Boundary

Status: accepted

## Context

`zig-vst3` already implements the VST3 editor protocols, but it does not create native child surfaces or render controls. A production editor also needs parameter gestures, scaling, resizing, input, surface recreation, and real-time-safe communication with the processor.

The framework must support more than one rendering approach without making every plugin link a GUI toolkit. The first integration must also expose enough real host behavior to validate the editor API.

## Decision

`zig-vst3-plugin` will define a toolkit-neutral editor and `GuiContext`. GUI toolkits will live in optional adapter packages. Toolkit types and headers will not enter the core public API.

The first adapter will use VSTGUI through a narrow C ABI shim. The pinned VST3 SDK already includes a matching VSTGUI checkout, VSTGUI implements VST3 editor lifecycle and parameter-control conventions, and its license permits redistribution under its terms.

The shim will own C++ objects. Zig will provide callbacks for:

- Parameter metadata and current values.
- Begin, perform, and end edit gestures.
- Resize and repaint requests.
- Editor attach, detach, scale, focus, and destruction events.

The core framework will remain usable without VSTGUI. Builds that enable the reference adapter must supply the pinned VSTGUI source or an explicitly supported replacement version.

The detailed license, build, text, accessibility, cross-compilation, X11, and Wayland comparison is recorded in [the adapter evaluation](../gui-adapter-evaluation.md).

## Alternatives

### Build a Zig Renderer First

A native renderer would remove the C++ boundary and give full control over batching, damage tracking, and GPU resources. It would also require platform child surfaces, text layout, font discovery, input methods, accessibility semantics, widgets, and at least one graphics backend before the first useful editor could ship.

This remains a supported future adapter. It is not the first implementation because it delays validation of the framework lifecycle and parameter API.

### Use a Broad Cross-Platform Framework

Broad application frameworks provide mature editor and parameter attachment APIs. Their build size, unrelated scope, and licensing constraints make them poor default dependencies for this repository. The project instead derives its contracts from plugin format specifications and its own bounded runtime requirements.

### Bind a Rust GUI Adapter

NIH-plug demonstrates the desired editor abstraction, but importing its Rust adapters would add a second plugin framework and a Rust build boundary. Reusing the architecture is cheaper than reusing the implementation.

## Consequences

- Per-instance controller and component ownership must land before the adapter.
- The build gains an optional C++ path for the reference editor.
- Cross-compilation must test both the Zig plugin and the adapter shim.
- VSTGUI-specific widgets stay outside `zig-vst3-plugin`.
- A future custom renderer can implement the same editor contract.
- Performance work begins with invalidation and buffer reuse. Render threads, damage regions, and multiple buffered frame states require measurements from representative editors.

## Evidence

- Steinberg's `VST3Editor` binds VST3 parameters and handles editor lifecycle.
- NIH-plug supports several GUI toolkits through one framework editor contract.
- Ghostty keeps platform-native application code separate from shared render logic and recently reduced lock time through dirty-state tracking and render-state changes.
- The local pinned SDK contains VSTGUI commit `76823bd`, so the adapter can be developed against a reproducible source revision.
- The narrow shim compiles into the editor bundle without adding VSTGUI types to either Zig package API.
- The macOS editor bundle passes the Steinberg validator and pluginval editor automation tests.
- Native platform mappings cover NSView, HWND, X11 embed IDs, and Wayland surface IDs. Windows, X11, and Wayland still require native build and real-host evidence.
