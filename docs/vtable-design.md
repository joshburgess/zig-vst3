# Vtable Scaffolding Design

Phase 1 needs a way for Zig objects to expose VST3 COM-style interfaces with ABI-compatible vtables. The design must handle `FUnknown` first, then scale to multiple interfaces on one object.

## Option 1: Declarative Interface Descriptions

Each VST3 interface is described as comptime data: IID, parent, method names, and function signatures. A generator builds vtable structs and adapters from that metadata.

Pros:

- One canonical metadata source can drive code, docs, and ABI tests
- Future interface translations become data entry plus method bodies
- Good fit for generated bindings later

Cons:

- Highest upfront complexity
- Harder compiler errors for users implementing methods
- More custom machinery before the first working plugin

ABI risks:

- Any metadata bug silently creates a wrong vtable
- Generated signatures must still be checked against C++ fixtures

## Option 2: Interface Types With Reflected Methods

Each interface is a Zig type with method declarations. The framework reflects over declarations and derives the vtable layout.

Pros:

- Ergonomic for framework users
- Interface declarations look close to normal Zig APIs
- Less repetition than explicit vtable structs

Cons:

- Zig does not have a native trait system, so method contract errors can become indirect
- Reflection over declarations can hide ordering mistakes
- The ABI-facing layout is less obvious during review

ABI risks:

- Declaration order and adapter generation must be locked down by tests
- C calling conventions need explicit checks for every method

## Option 3: Explicit Vtable Structs With Helpers

Each interface translation declares the ABI vtable struct explicitly. Helpers provide common `FUnknown` wiring, query dispatch, and object pointer recovery.

Pros:

- ABI layout is visible in code review
- Smallest viable starting point for Phase 1
- C++ fixture tests can map directly to explicit fields
- User-facing helpers can improve ergonomics later without hiding the raw layer

Cons:

- More boilerplate per interface
- Manual method order must be reviewed carefully
- Multi-interface pointer adjustment relies on the shared interface-map helpers and must stay covered by ABI fixtures

ABI risks:

- Human error in vtable field order
- Incorrect object pointer recovery for interfaces whose pointer is not at object offset zero

## Recommendation

Start with Option 3 for Layer 1. The raw binding layer should make ABI layout obvious and testable, even if that means more boilerplate. Once P0/P1 interfaces are translated and tested, `zig-plug` can build a more ergonomic API over the explicit raw layer.

The initial implementation should:

- Define the exact `FUnknown` vtable layout
- Provide an `FUnknown.Header` that can be embedded as the first field of prototype objects
- Implement `queryInterface`, `addRef`, and `release` for a test object
- Store the reference count in the ABI header as `std.atomic.Value(u32)`
- Call an optional destroy callback when `release` reaches zero

The implementation now uses shared interface-map helpers for pointer fixup and query dispatch across both synthetic ABI fixtures and production component/controller shells.

## Refcount Policy

`addRef` uses a monotonic atomic increment and returns the new count. `release` uses a guarded compare-exchange decrement; when the count reaches zero it performs an acquire load before calling the destroy callback. Release-after-zero panics before the counter can underflow.

Objects that own an allocator store it in their concrete object and use `funknown.allocatorDestroyFn` as their destroy callback. This keeps allocator ownership outside the ABI header while giving the raw COM helper a single destruction hook.
