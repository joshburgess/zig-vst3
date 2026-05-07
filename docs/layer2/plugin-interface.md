# Layer 2 Plugin Interface

The current `zig-plug` plugin prototype is a compile-time spec helper, not a VST3 wrapper generator yet.

## Current API

A plugin type declares:

- `name`: display name
- `vendor`: vendor string
- `Params`: struct of `zig-plug` parameter descriptors

`PluginSpec(Plugin)` validates those declarations at compile time and exposes:

- `ParameterSet`: reflected descriptor metadata
- `ParameterValues`: atomic normalized values initialized from descriptor defaults
- `init(params)`: builds the reflected set and value storage

## Example

```zig
const plug = @import("zig-plug");

const Gain = struct {
    pub const name = "Gain";
    pub const vendor = "zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
};

const GainSpec = plug.plugin.PluginSpec(Gain);
```

## Open Work

- Add lifecycle hooks for init, prepare, process, and deinit.
- Define the process callback contract for audio buffers and parameter changes.
- Generate Layer 1 component/controller glue from `PluginSpec`.
