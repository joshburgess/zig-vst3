# Phase 1 Retrospective

Status: first plugin milestone complete locally on macOS. This document records what the COM/vtable work has proven so far and what remains open before Layer 2 should treat the raw API as stable.

## Completed

- `TUID` and `FUID` primitives mirror Steinberg's `INLINE_UID` byte ordering for Windows and non-Windows targets.
- `zig build tuid-abi` compares Zig TUID bytes with a C++ program compiled against the pinned VST3 SDK.
- `FUnknown` has an explicit ABI vtable, atomic reference counting, and optional destroy callback.
- `zig build funknown-abi` calls the Zig `FUnknown` prototype from C.
- The multi-interface prototype returns distinct interface pointers for synthetic `ITestA`, `ITestB`, and `ITestC` interfaces backed by one object.
- `zig build multi-interface-abi` exercises that query and pointer-recovery path from C.
- `zig build phase1` now groups the Phase 1 integration checks.
- A shared raw-layer interface map handles IID dispatch for the synthetic multi-interface object and the gain plugin query paths.
- `FUnknown.release` detects release-after-zero before the atomic refcount can underflow.
- Layer 1 builds `zig_vst3_gain.vst3` with component, controller, processor, factory exports, sample-accurate gain automation, and state persistence.
- `zig build validate-gain` passes Steinberg's official validator locally on macOS.
- `zig build phase1` runs `validate-gain` on macOS.

## Harder Than Expected

- Zig 0.14 module wiring for small ABI fixture tools is particular about `-M` and `--dep` ordering, so build helpers are safer than ad hoc commands.
- The VST3 SDK tag is a superproject with submodules. Fetching the tag alone is not enough for validator or header fixture work.
- It is easy for test-only object layouts to drift from the C view. The C harnesses need to stay close to every ABI-facing change.

## Still Open

- The interface map helper is still explicit per object. A future helper should derive interface entries from field offsets once more plugin object shapes exist.
- Refcount destruction is callback-based in the low-level helpers. The gain plugin works, but concrete plugin objects still need a stable allocator ownership pattern.
- Windows C ABI harness execution is not wired yet. Cross-compilation passes, but the C harnesses run only on non-Windows CI jobs for now.
- There is no C++ harness yet for a full multi-interface object. The current harnesses are C ABI checks plus the Steinberg validator.
- Host smoke testing has not been recorded yet. The validator pass proves the bundle and interfaces are structurally valid, but it does not replace DAW loading tests.

## Follow-Up Tasks

- Add a C++ harness once the interface map helper exists.
- Decide whether the raw layer exposes callback-based destruction directly or hides it behind object factory helpers.
- Add `docs/host-matrix.md` after the gain plugin is loaded in at least one real host.
