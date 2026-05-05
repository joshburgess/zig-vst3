# Architecture

The project has two layers:

- `vst3-zig`: raw Zig bindings for the VST3 COM API
- `nih-zig`: a higher-level framework built on top of `vst3-zig`

The raw layer owns ABI compatibility, TUID/FUID handling, vtable layout, factory exports, and bundle entry points. The framework layer owns the user-facing plugin interface, parameters, state, automation, MIDI/event handling, and examples.
