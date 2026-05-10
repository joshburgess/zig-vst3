# Phase 1 Retrospective

Status: first plugin milestone complete locally on macOS. This document records what the COM/vtable work has proven so far and what remains open before Layer 2 should treat the raw API as stable.

## Completed

- `TUID` and `FUID` primitives mirror Steinberg's `INLINE_UID` byte ordering for Windows and non-Windows targets.
- `zig build tuid-abi` compares Zig TUID bytes with a C++ program compiled against the pinned VST3 SDK.
- `FUnknown` has an explicit ABI vtable, atomic reference counting, and optional destroy callback.
- `zig build funknown-abi` calls the Zig `FUnknown` prototype from C.
- The multi-interface prototype returns distinct interface pointers for synthetic `ITestA`, `ITestB`, and `ITestC` interfaces backed by one object.
- `zig build multi-interface-abi` exercises that query and pointer-recovery path from C.
- `zig build multi-interface-cpp-abi` exercises the same path from C++.
- `zig build multi-interface-sdk-abi` exercises the same path through Steinberg SDK `FUnknown` declarations.
- `zig build phase1` now groups the Phase 1 integration checks.
- A shared raw-layer interface map handles IID dispatch for the synthetic multi-interface object and the gain plugin query paths.
- `FUnknown.release` detects release-after-zero before the atomic refcount can underflow.
- `funknown.allocatorDestroyFn` provides a reusable allocator-owned destruction callback for raw-layer objects.
- Layer 1 builds bundled gain, bypass, mode-gain, voice-mix, note-gate, and event-echo `.vst3` examples with component, controller, processor, factory exports, parameter automation, state persistence, input events, and output events.
- `zig build validate-examples` passes Steinberg's official validator locally on macOS for all bundled examples.
- `zig build phase1` runs the bundled example validator path on macOS.

## Harder Than Expected

- Zig 0.14 module wiring for small ABI fixture tools is particular about `-M` and `--dep` ordering, so build helpers are safer than ad hoc commands.
- The VST3 SDK tag is a superproject with submodules. Fetching the tag alone is not enough for validator or header fixture work.
- It is easy for test-only object layouts to drift from the C view. The C harnesses need to stay close to every ABI-facing change.

## Still Open

- The interface map helper can derive entries from object fields and is used by the synthetic multi-interface harness plus the reusable effect component and controller shells.
- Refcount destruction is still callback-based in the low-level helpers. The raw layer now has a reusable allocator-owned callback, but higher-level object factory ergonomics are still open.
- Windows C ABI harness execution is not wired yet. Cross-compilation passes, but the C harnesses run only on non-Windows CI jobs for now.
- The current SDK C++ harness covers `FUnknown` dispatch but still uses local synthetic extension interfaces for the test-only `callA`/`callB`/`callC` methods.
- REAPER smoke testing has save/reload passes for the non-MIDI examples. `zig_vst3_note_gate.vst3`, `zig_vst3_event_monitor.vst3`, and `zig_vst3_sine_synth.vst3` remain deferred until MIDI/analyzer/instrument host routes are convenient.

## Follow-Up Tasks

- Decide whether Layer 2 hides raw callback-based destruction behind object factory helpers.
- Complete the deferred Note Gate, Event Monitor, and Sine Synth host smoke tests.
