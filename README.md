# zig-vst3

Zig bindings and framework experiments for building VST3 audio plugins.

The project is at the repository scaffold stage. The current tree contains:

- `vst3-zig/`: raw VST3 binding layer
- `zig-plug/`: higher-level plugin framework layer
- `PROJECT_BUILD_PLAN.md`: staged implementation plan

## Development

Required toolchain:

- Zig 0.14.0

Run the local checks:

```sh
zig build
zig build test
```
