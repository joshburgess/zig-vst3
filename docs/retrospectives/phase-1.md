# Phase 1 Retrospective

Status: in progress. This document records what the early COM/vtable work has proven so far and what remains open before Phase 1 can be considered complete.

## Completed

- `TUID` and `FUID` primitives mirror Steinberg's `INLINE_UID` byte ordering for Windows and non-Windows targets.
- `zig build tuid-abi` compares Zig TUID bytes with a C++ program compiled against the pinned VST3 SDK.
- `FUnknown` has an explicit ABI vtable, atomic reference counting, and optional destroy callback.
- `zig build funknown-abi` calls the Zig `FUnknown` prototype from C.
- The multi-interface prototype returns distinct interface pointers for synthetic `ITestA`, `ITestB`, and `ITestC` interfaces backed by one object.
- `zig build multi-interface-abi` exercises that query and pointer-recovery path from C.
- `zig build phase1` now groups the Phase 1 integration checks.

## Harder Than Expected

- Zig 0.14 module wiring for small ABI fixture tools is particular about `-M` and `--dep` ordering, so build helpers are safer than ad hoc commands.
- The VST3 SDK tag is a superproject with submodules. Fetching the tag alone is not enough for validator or header fixture work.
- It is easy for test-only object layouts to drift from the C view. The C harnesses need to stay close to every ABI-facing change.

## Still Open

- The multi-interface prototype is still synthetic. It proves pointer recovery and dispatch shape, but it is not yet a reusable interface registration API.
- Refcount destruction is callback-based. Real plugin objects still need a stable allocator ownership pattern around concrete object creation.
- Windows C ABI harness execution is not wired yet. Cross-compilation passes, but the C harnesses run only on non-Windows CI jobs for now.
- There is no C++ harness yet for Phase 1's full synthetic object. The current harnesses are C ABI checks.

## Follow-Up Tasks

- Add a reusable interface map helper that takes IID and interface header offsets as comptime data.
- Add a C++ harness once the interface map helper exists.
- Add debug-only double-release detection that reports a clear failure before atomic underflow.
- Decide whether the raw layer exposes callback-based destruction directly or hides it behind object factory helpers.
