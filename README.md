# zig-vst3

Zig bindings and framework experiments for building VST3 audio plugins.

The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan

## Current Status

Layer 1 now builds a minimal gain VST3 plugin that passes Steinberg's official validator locally on macOS.

Implemented pieces include:

- TUID/FUID byte layout with SDK fixture comparison
- Explicit `FUnknown` vtable prototype
- Atomic reference counting with allocator-backed destruction tests
- Synthetic multi-interface query dispatch
- C ABI harnesses for `FUnknown` and multi-interface dispatch
- `pluginterfaces/base`, `pluginterfaces/gui`, and broad `pluginterfaces/vst` ABI translations
- Platform-specific VST3 module entry exports
- macOS, Linux, and Windows `.vst3` bundle generation for the gain plugin
- A validator-passing gain plugin with component, controller, processor, one automatable gain parameter, sample-accurate parameter updates, and state persistence
- Initial `zig-plug` float, int, and bool parameter descriptors with normalization tests

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
zig build phase1
```

Build and validate the gain plugin on macOS:

```sh
zig build validator
zig build validate-gain
```

Build platform bundles:

```sh
zig build bundle-gain
zig build -Dtarget=x86_64-linux-gnu bundle-gain-linux
zig build -Dtarget=x86_64-windows-gnu bundle-gain-windows
```
