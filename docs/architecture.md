# Architecture

The project has two packages:

- `zig-vst3`: raw Zig bindings for the VST3 COM API
- `zig-vst3-plugin`: a higher-level framework built on top of `zig-vst3`

The raw API owns ABI compatibility, TUID/FUID handling, vtable layout, factory exports, and bundle entry points. The plugin framework owns the user-facing plugin interface, parameters, state, automation, MIDI/event handling, and examples.
