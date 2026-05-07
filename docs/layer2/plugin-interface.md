# Layer 2 Plugin Interface

The current `zig-plug` plugin prototype is a compile-time spec helper, not a VST3 wrapper generator yet.

## Current API

A plugin type declares:

- `name`: display name
- `vendor`: vendor string
- `Params`: struct of `zig-plug` parameter descriptors
- optional lifecycle methods

`PluginSpec(Plugin)` validates those declarations at compile time and exposes:

- `ParameterSet`: reflected descriptor metadata
- `ParameterValues`: atomic normalized values initialized from descriptor defaults
- lifecycle flags for optional `init`, `prepare`, `process`, and `deinit` declarations
- `init(params)`: builds the reflected set and value storage

`validateLifecycle(Plugin)` currently accepts:

- `init(allocator: std.mem.Allocator) !Plugin`
- `prepare(self: *Plugin, config: PrepareConfig) void`
- `process(self: *Plugin, context: *process.ProcessContext(f32)) void`
- `deinit(self: *Plugin) void`

`process.ProcessContext(Sample)` carries typed input and output channel views plus the current sample rate. The input and output views validate that each channel has the same frame count before a context is created.

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

- Add parameter-change delivery to the process callback contract.
- Add double-precision process callback support.
- Generate Layer 1 component/controller glue from `PluginSpec`.
