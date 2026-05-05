# zig-vst3

Zig bindings and framework experiments for building VST3 audio plugins.

The project is at the repository scaffold stage. The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan

## Current Status

Phase 1 COM/vtable groundwork is in progress:

- TUID/FUID byte layout with SDK fixture comparison
- Explicit `FUnknown` vtable prototype
- Atomic reference counting with allocator-backed destruction tests
- Synthetic multi-interface query dispatch
- C ABI harnesses for `FUnknown` and multi-interface dispatch
- Initial `pluginterfaces/base` translations for `FUnknown`, `IPluginBase`, and plugin factory structs

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
zig build phase1
zig build pluginbase-abi
```
