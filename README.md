# zig-vst3

Zig bindings and framework experiments for building VST3 audio plugins.

The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan

## Current Status

Layer 1 now builds VST3 example plugins that pass Steinberg's official validator locally on macOS.

Implemented pieces include:

- TUID/FUID byte layout with SDK fixture comparison
- Explicit `FUnknown` vtable prototype
- Atomic reference counting with allocator-backed destruction tests
- Synthetic multi-interface query dispatch
- C ABI harnesses for `FUnknown` and multi-interface dispatch
- `pluginterfaces/base`, `pluginterfaces/gui`, and broad `pluginterfaces/vst` ABI translations
- Platform-specific VST3 module entry exports
- macOS, Linux, and Windows `.vst3` bundle generation for gain, bypass, mode-gain, and voice-mix examples
- Validator-passing example plugins with component, controller, processor, automatable parameters, sample-accurate parameter updates, and state persistence
- Initial `zig-plug` float, int, bool, and enum parameter descriptors with normalization tests
- Initial `zig-plug` plugin spec prototype with reflected parameter defaults

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
zig build phase1
```

Build and validate the example plugins on macOS:

```sh
zig build validator
zig build validate-examples
```

Build platform bundles:

```sh
zig build bundle-gain
zig build bundle-bypass
zig build bundle-mode-gain
zig build bundle-voice-mix
zig build -Dtarget=x86_64-linux-gnu bundle-examples-linux
zig build -Dtarget=x86_64-windows-gnu bundle-examples-windows
```
