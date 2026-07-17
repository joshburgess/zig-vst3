# Plugin GUI Plan

This plan adds visible, useful plugin editors without turning `zig-vst3` into a GUI toolkit. The framework will own editor lifecycle, host integration, parameter gestures, and real-time-safe data exchange. Rendering and widgets will live behind adapters.

The first product milestone is a resizable gain editor that works in a real host, keeps multiple plugin instances independent, and reports automation gestures correctly. Cross-platform and analyzer support follow after that path is proven.

## Scope

### Goals

- Create one controller, parameter store, component, and editor per plugin instance.
- Expose a toolkit-neutral editor API from `zig-vst3-plugin`.
- Provide a reference GUI adapter without making it a required dependency.
- Support `NSView`, `HWND`, X11 embed windows, and Wayland surfaces.
- Keep GUI work off the audio thread.
- Bind controls to reflected parameter metadata and host automation.
- Handle resize, content scale, focus, keyboard input, and surface recreation.
- Establish real-host and performance gates for editor changes.

### Non-goals

- A general-purpose Zig widget toolkit.
- A plugin host.
- A custom renderer for the first visible editor unless the adapter spike shows that existing toolkits cannot meet the requirements.
- Analyzer graphs, animated backgrounds, or custom shaders in the first milestone.
- Sharing editor or parameter state between plugin instances.

## Current Baseline

The raw VST3 layer already provides most of the host-facing protocol:

- `vst_plug_view.zig` implements `IPlugView` attachment, removal, input, focus, sizing, frame assignment, and size constraints.
- `vst_content_scale_support.zig` implements `IPlugViewContentScaleSupport`.
- `vst_plug_frame.zig` implements host resize delegation.
- `vst_linux_run_loop.zig` implements Linux event and timer handlers.
- `vst_wayland_frame.zig` implements the VST3 Wayland host and frame interfaces.
- `editor_smoke` creates a protocol-only view for all four platform identifiers.

The missing pieces are native child surfaces, rendering, widget input, toolkit integration, per-instance editor ownership, and a parameter-binding API intended for GUI controls.

There is also an architectural prerequisite. `ReflectedEditController`, its parameter state, `SimpleStereoEffect`, and the smoke view currently use module-level storage. A host can create multiple instances, so production GUI work must not build on those singletons.

## Architecture

```text
Host
  |
  | VST3 lifecycle, resize, scale, focus
  v
Per-instance controller and IPlugView
  |
  +--> GuiContext --> beginEdit / performEdit / endEdit
  |        |
  |        +--> reflected parameter metadata and values
  |
  +--> Editor adapter
           |
           +--> native child surface and event integration
           +--> toolkit widgets and drawing
           +--> optional renderer backend

Audio processor --> bounded telemetry snapshot/queue --> editor
```

The controller remains the authority for GUI-visible parameter values. A control gesture follows this sequence:

1. Call `beginParameterEdit(id)` when manipulation starts.
2. Call `setParameterNormalized(id, value)` for each accepted change.
3. Call `endParameterEdit(id)` when manipulation ends or is cancelled.

The adapter must not mutate processor state directly. The host receives GUI edits through `IComponentHandler` and forwards them through its normal automation path.

## Design Rules

- Every factory call returns an independent object with an independent lifetime.
- Editor callbacks run on the host GUI thread unless a platform contract states otherwise.
- The audio thread never waits for the GUI, renderer, allocator, or operating system.
- Closing an editor stops editor-only timers, analysis, and repaint work.
- Static editors repaint on invalidation, exposure, resize, or scale changes. They do not run a permanent animation loop.
- Logical size and physical pixel size stay distinct.
- Surface loss and recreation are normal lifecycle events, especially on Linux and during display changes.
- Host rejection leaves the last accepted parameter value, size, and scale unchanged.
- The reference editor supports pointer and keyboard operation, precise text entry, reset to default, and a visible focus state.
- Toolkit-specific types do not enter the core plugin API.

## Lessons From Existing Systems

### VSTGUI and third-party framework

Use VSTGUI and third-party framework as references for editor lifetime, resize constraints, content scaling, parameter attachments, and host automation gestures. VSTGUI is the leading candidate for the first adapter because it is plugin-focused, uses a permissive license, and already understands VST3 editor behavior. third-party framework is a useful design reference, but its size and licensing make it a less attractive default dependency.

### NIH-plug

Follow NIH-plug's separation between a toolkit-neutral editor contract and optional egui, iced, and VIZIA adapters. Its `GuiContext` and parameter setter model are especially relevant: widgets report complete gestures through the framework, while editor size and open state remain editor-specific persistent state.

### Ghostty

Ghostty is useful as a rendering architecture reference because it combines a shared Zig core with platform-native application shells and separate Metal and OpenGL paths. The following ideas transfer well:

- Keep platform windowing separate from shared render and model logic.
- Share renderer behavior across graphics backends so features do not drift.
- Track dirty state and skip work when nothing visible changed.
- Build render snapshots that minimize time holding shared-state locks.
- Reuse CPU and GPU buffers instead of allocating every frame.
- Keep multiple frame states when GPU and CPU overlap requires it.
- Treat surface teardown and recreation as tested lifecycle operations.
- Optimize against recorded real workloads, not only synthetic stress tests.
- Keep native platform behavior outside the renderer.

Do not adopt these Ghostty choices without plugin-specific evidence:

- A dedicated render thread per editor. Hosts impose GUI-thread rules, and most plugin editors do not need terminal-scale update rates.
- Multiple graphics APIs in the first milestone.
- Continuous high-refresh rendering for a static control panel.
- Terminal-specific text shaping, glyph atlas, grid, and scrollback machinery.
- GPU buffering complexity before frame captures show CPU or GPU contention.

## Work Plan

Each phase should land independently. Do not start the next phase until the exit criteria for the current phase pass.

### Phase 0: Record Decisions and Baselines

Deliverables:

- [x] Write an ADR for toolkit-neutral core APIs and optional GUI adapters.
- [x] Compare a VSTGUI C ABI shim with one lightweight custom-renderer prototype.
- [x] Record adapter license, build, cross-compilation, text, accessibility, X11, and Wayland constraints.
- [x] Capture current `editor-smoke` validator and pluginval results.
- [x] Define a repeatable host launch and editor open/close procedure on macOS.
- [x] Add a small benchmark harness for parameter updates and GUI telemetry transport before optimizing either.

Decision gate:

- Prefer the VSTGUI adapter if it can be built and bundled without infecting the core package, can receive Zig callbacks through a narrow C ABI, and has a credible path across the target platforms.
- Choose a custom renderer only if the spike identifies a concrete blocker. Document that blocker in the ADR.

Exit criteria:

- The chosen first adapter and its dependency boundary are documented.
- Baseline commands and host observations are reproducible.
- No toolkit dependency has been added to `zig-vst3` or `zig-vst3-plugin`.

### Phase 1: Per-instance Plugin Objects

Deliverables:

- [x] Replace module-level controller storage with allocated per-instance controller objects.
- [x] Move parameter state and retained host interfaces into each controller instance.
- [x] Replace module-level component storage with allocated per-instance component objects.
- [x] Make `release` destroy an object exactly once when its reference count reaches zero.
- [x] Remove direct component reads from controller module globals.
- [x] Give every created editor its own state and lifetime.
- [x] Keep factory and ABI entry points unchanged from the host's perspective.

Tests:

- [x] Create two components and prove their activation and process state are independent.
- [x] Create two controllers and prove parameter edits do not cross instances.
- [x] Attach different component handlers to two controllers and verify callback isolation.
- [x] Create, release, and recreate controllers and components repeatedly.
- [x] Create two views from one controller and document whether both are supported or the second is rejected.
- [x] Run `zig build test`, `zig build raw-api-abi`, validator, and pluginval gates.

Exit criteria:

- Multiple instances do not share mutable plugin, host, parameter, or editor state.
- Reference counts control real object lifetimes.
- Existing example bundles still pass their current gates.

### Phase 2: Toolkit-neutral Editor API

Deliverables:

- [x] Add a framework editor factory invoked by the per-instance edit controller.
- [x] Define logical size, scale, resize policy, and editor-open state types.
- [x] Define `GuiContext` operations for parameter gestures, current values, metadata, resize requests, repaint requests, and host context menus.
- [x] Define an adapter lifecycle for attach, detach, resize, scale, focus, and destruction.
- [x] Route GUI changes through `beginEdit`, `performEdit`, and `endEdit`.
- [x] Notify an open editor when the host changes a parameter.
- [x] Specify gesture cancellation and host-rejection behavior.
- [x] Keep toolkit and operating-system handles behind adapter-facing types.

Tests:

- [x] Verify the exact ordering of begin, perform, and end callbacks.
- [x] Verify rejected edits restore the prior accepted value.
- [x] Verify host-originated changes reach an open editor without producing a new host gesture.
- [x] Verify detach and destruction end active gestures safely.
- [x] Verify size and scale changes preserve the last accepted state when rejected.

Exit criteria:

- A fake adapter can exercise the complete editor lifecycle without native windowing.
- Parameter controls can be implemented without importing raw VST3 interfaces.
- Editor APIs have instance ownership and thread contracts in their public documentation.

### Phase 3: Visible macOS Reference Editor

Deliverables:

- [x] Create an `NSView` child inside the host-provided parent.
- [x] Render a background, title, gain control, value label, and focus indicator.
- [x] Support pointer dragging, arrow keys, Home/End, precise text entry, and reset to default.
- [x] Use logical coordinates and apply host content scale correctly.
- [x] Request host resize through `IPlugFrame` and obey size constraints.
- [x] Destroy all surface, timer, and toolkit resources on detach.
- [x] Keep the reference adapter in a separate package or integration directory.

UX acceptance criteria:

- The current value and units are visible without hovering.
- Keyboard focus is visible.
- A user can enter an exact value without pixel-precise dragging.
- Reset to default is discoverable and undoable through the host gesture path.
- The editor remains usable at minimum and maximum supported sizes.
- Failure to create the surface returns a clean editor-open failure instead of a blank interactive area.

Host tests:

- [x] Open, close, and reopen the editor while transport is stopped and running.
- [ ] Resize from the host and from the editor.
- [ ] Change display scale or move between displays when the host permits it.
- [ ] Record automation from pointer and keyboard edits, then play it back.
- [x] Save and restore the project with the editor open and closed.
- [x] Repeat with two plugin instances open at once.

Exit criteria:

- The gain editor passes the macOS host row in `docs/host-matrix.md`.
- Static idle does not continuously repaint.
- Closing the editor leaves audio processing and state restoration intact.

### Phase 4: Parameter Binding and Reusable Controls

Deliverables:

- [x] Add a parameter attachment that observes one parameter and owns one active gesture.
- [x] Derive display name, units, range, default, step count, and text conversion from reflected metadata.
- [x] Add reference bindings for float, integer, boolean, and enum parameters.
- [x] Support modifier-based fine adjustment without making it the only precise input method.
- [x] Expose host-provided parameter context menus where available.
- [x] Add a generic parameter panel for development and debugging.

Tests:

- [x] Cover continuous and stepped normalization.
- [x] Cover invalid IDs and rejected values.
- [x] Cover automation playback during an open editor.
- [x] Cover a host state load while controls are visible.
- [x] Cover opening and closing during an active transport session through pluginval's open-editor-while-processing test for all reference editors.

Exit criteria:

- Gain, bypass, mode-gain, and voice-mix can create functional controls from the same binding layer.
- Toolkit adapters do not duplicate gesture and normalization logic.

### Phase 5: Windows Backend

Deliverables:

- [x] Create and destroy a child `HWND` using the host parent.
- [x] Forward focus, keyboard, pointer, wheel, resize, and scale events.
- [x] Handle device or surface loss if the chosen renderer requires it. VSTGUI owns the platform drawing surface, so the adapter has no separate graphics device to recover.
- [x] Bundle adapter resources in the Windows VST3 bundle. The current adapter is resource-free and links into the module.
- [x] Add Windows-specific diagnostics for surface creation failures.

Exit criteria:

- The same reference editor passes validator, pluginval, and a real Windows host row.
- Two simultaneous instances remain isolated.
- DPI changes and repeated editor recreation do not leak or crash.

### Phase 6: Linux X11 and Wayland Backends

Deliverables:

- [x] Create an X11 child window for `X11EmbedWindowID`.
- [x] Register required file descriptors and timers through the host `IRunLoop`.
- [x] Implement `WaylandSurfaceID` attachment through `IWaylandFrame`.
- [x] Handle surface realization, unrealization, and recreation through idempotent close and repeatable attach operations.
- [x] Avoid assuming that a standalone application event loop is available inside the host.
- [x] Document toolkit and host limitations separately for X11 and Wayland.

Exit criteria:

- X11 and Wayland each have a recorded real-host result.
- Repeated attach, detach, and surface recreation do not leave registered handlers behind.
- Missing host capabilities produce an explicit unsupported result.

### Phase 7: Real-time-safe Telemetry

Start this phase only when a reference editor needs a meter or analyzer. Parameter controls do not require a general message bus.

Deliverables:

- [x] Add atomic snapshots for scalar meters.
- [x] Add a bounded single-producer/single-consumer queue only for data that cannot fit a snapshot.
- [x] Define overflow as dropped or coalesced visualization data, never blocked audio.
- [x] Stop producing editor-only analysis when the editor is closed.
- [x] Add repaint coalescing so multiple updates schedule at most one pending frame.
- [x] Reuse visualization and upload buffers across frames.

Exit criteria:

- Audio processing performs no GUI locks, allocations, operating-system calls, or unbounded work.
- Closing the editor removes recurring visualization work.
- Queue overflow has a test and a documented visual consequence.

### Phase 8: Rendering Performance Pass

Apply Ghostty-inspired techniques only after measurements identify a cost.

Deliverables:

- [x] Capture CPU profiles and frame timings with representative editors. A 50-repeat pluginval stress run, a three-second macOS sample, and opt-in per-editor timing are recorded in `docs/gui-baseline.md`.
- [x] Track invalid regions or dirty widgets if full redraw is measurable. Measured draws are under 0.3 milliseconds after the cold frame, so VSTGUI invalidation remains sufficient.
- [x] Separate model snapshot creation from renderer submission. Parameter state remains in the toolkit-neutral editor model, and adapter callbacks submit accepted values on the GUI thread.
- [x] Minimize lock hold time while building render state. The parameter editor render path holds no application lock. Telemetry uses atomic snapshots or a bounded SPSC queue.
- [x] Add double or triple buffered frame state only if CPU/GPU overlap stalls are observed. No overlap stall was observed, so no additional buffering was retained.
- [x] Record buffer growth, texture upload, draw-call, and frame pacing metrics. The opt-in profiler records draw pacing, invalidated area, lifecycle events, and parameter updates. Buffer growth, texture uploads, and custom draw calls do not exist in the VSTGUI reference path.
- [x] Test surface loss and recreation under instrumentation. VSTGUI owns the platform surface, so repeated instrumented open, close, resize, and scale cycles are the applicable recreation test.

Provisional budgets:

- Closed editor: no periodic GUI or analysis work.
- Open static editor: no continuous repaint loop.
- Parameter interaction: one coalesced repaint per display interval at most.
- Audio thread: no regression outside benchmark noise when the editor is open but idle.
- Frame building: below 4 milliseconds for the 400 by 300 reference editor. The measured cold maximum is 2.60 milliseconds, and measured warm maxima are below 0.3 milliseconds.

Exit criteria:

- Every retained optimization has profile or benchmark evidence.
- Performance tests cover both static parameter panels and active meter updates.
- Backend-specific optimizations preserve shared behavior and visual output.

### Phase 9: Release and Maintenance

Deliverables:

- [x] Document the editor API and one complete adapter integration.
- [x] Add the visible editor to build, bundle, validator, and pluginval steps.
- [ ] Record all four real-host platform rows.
- [x] Add editor lifecycle checks to the release checklist.
- [x] Document toolkit version and license policy.
- [x] Add migration notes for the per-instance framework API changes.
- [x] Keep the protocol-only `editor-smoke` example separate from the visible reference editor.

Exit criteria:

- A plugin author can add the reference editor by following one maintained guide.
- GUI dependencies remain optional.
- Known host and platform limitations are explicit.

## Work Item Index

| ID | Work item | Depends on | Completion evidence |
| --- | --- | --- | --- |
| GUI-001 | Adapter ADR and spike | None | ADR with selected adapter and rejected alternatives |
| GUI-002 | Baseline host and performance measurements | None | Reproducible commands and recorded results |
| GUI-003 | Per-instance controller | GUI-001 | Two-controller isolation tests |
| GUI-004 | Per-instance component | GUI-003 | Two-component isolation tests |
| GUI-005 | Per-instance view lifetime | GUI-003 | Multi-view lifecycle tests |
| GUI-006 | Toolkit-neutral editor contract | GUI-003 | Fake-adapter tests |
| GUI-007 | `GuiContext` parameter gestures | GUI-006 | Gesture ordering and rejection tests |
| GUI-008 | Host-to-editor parameter notifications | GUI-007 | Automation and state-load tests |
| GUI-009 | macOS native attachment | GUI-006 | Visible editor in a macOS host |
| GUI-010 | Reference gain control | GUI-007, GUI-009 | Pointer, keyboard, text, and reset tests |
| GUI-011 | Parameter attachment layer | GUI-008, GUI-010 | Four parameter-kind examples |
| GUI-012 | Windows native attachment | GUI-010 | Windows real-host row |
| GUI-013 | X11 native attachment and run loop | GUI-010 | X11 real-host row |
| GUI-014 | Wayland native attachment | GUI-013 | Wayland real-host row |
| GUI-015 | Scalar telemetry snapshot | GUI-010 | Meter test with no audio-thread blocking |
| GUI-016 | Bounded visualization queue | GUI-015 | Overflow and shutdown tests |
| GUI-017 | Rendering performance pass | GUI-012, GUI-014, GUI-016 | Profiles, budgets, and retained benchmark tests |
| GUI-018 | Public integration guide | GUI-011, GUI-012, GUI-014 | Guide verified from a clean checkout |

## Validation Matrix

Run the smallest applicable tier on each change. Run the full matrix before declaring a platform complete.

| Area | Unit or harness | Validator/pluginval | Real host |
| --- | --- | --- | --- |
| Object lifetime | Multi-instance and ref-count tests | All example bundles | Two instances, repeated open/close |
| Parameter gestures | Fake component handler | Parameter fuzz and state tests | Record, undo, and playback automation |
| Resize and scale | `IPlugView` and scale helper tests | Editor bundle | Host resize and display-scale change |
| Input and focus | Adapter event tests | Editor bundle | Pointer, wheel, keyboard, text entry |
| Surface lifecycle | Attach/detach/recreate harness | Editor bundle | Reopen, display move, project reload |
| Telemetry | Overflow and shutdown tests | Analyzer bundle when added | Transport running during open/close |
| Performance | Benchmarks and frame metrics | Not applicable | Idle and active-editor profiles |

## Risks

| Risk | Mitigation |
| --- | --- |
| Host-specific lifetime behavior | Allocate per instance, make destruction idempotent, and test repeated recreation in real hosts |
| Toolkit event loop conflicts | Use host-provided loops and adapter callbacks; do not start a standalone application loop |
| GUI dependency spreads into core | Keep adapters in separate packages with narrow Zig or C boundaries |
| Linux backend divergence | Share editor and render logic; isolate X11 and Wayland surface code |
| GUI blocks audio | Allow only atomic snapshots or bounded queues across the boundary |
| Unnecessary renderer complexity | Start with a static gain editor and require profile evidence for threading, damage tracking, or multiple frame states |
| Inaccessible custom controls | Require keyboard operation, text entry, visible focus, and semantic labeling in the reference design |
| Blank editor after renderer failure | Return an explicit attach failure and emit adapter diagnostics |
| Cross-compilation becomes fragile | Exercise adapter bundles in CI and pin toolkit versions |

## Source Material

- [Steinberg VST3 editing model](https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/API%2BDocumentation/Index.html)
- [VSTGUI overview](https://steinbergmedia.github.io/vst3_dev_portal/pages/What%2Bis%2Bthe%2BVST%2B3%2BSDK/VSTGUI.html)
- [VSTGUI `VST3Editor`](https://steinbergmedia.github.io/vst3_doc/vstgui/html/class_v_s_t_g_u_i_1_1_v_s_t3_editor.html)
- [third-party framework `AudioProcessorEditor`](https://docs.third-party framework.com/master/classthird-party framework_1_1AudioProcessorEditor.html)
- [third-party framework parameter attachments](https://docs.third-party framework.com/master/classthird-party framework_1_1AudioProcessorValueTreeState_1_1SliderAttachment.html)
- [NIH-plug repository and GUI adapters](https://github.com/robbert-vdh/nih-plug)
- [NIH-plug GUI context](https://nih-plug.robbertvanderhelm.nl/nih_plug/context/gui/index.html)
- [NIH-plug egui editor state](https://nih-plug.robbertvanderhelm.nl/nih_plug_egui/struct.EguiState.html)
- [Ghostty architecture summary](https://github.com/ghostty-org/ghostty#competitive-performance)
- [Ghostty shared Metal and OpenGL renderer rework](https://ghostty.org/docs/install/release-notes/1-2-0#renderer-rework)
- [Ghostty dirty-state and lock reduction](https://ghostty.org/docs/install/release-notes/1-3-0#performance-improvements)
- [Ghostty generic renderer source](https://github.com/ghostty-org/ghostty/blob/main/src/renderer/generic.zig)
