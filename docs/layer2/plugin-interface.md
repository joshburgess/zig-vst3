# Layer 2 Plugin Interface

The current `zig-plug` plugin prototype is a compile-time spec helper with a narrow Layer 1 integration path. The gain plugin now uses a reflected `PluginSpec` for factory metadata, controller parameter metadata, parameter string conversion, normalized/plain conversion, default parameter state, host automation delivery, state serialization, and audio process context construction.

## Current API

A plugin type declares:

- `name`: display name
- `vendor`: vendor string
- `Params`: struct of `zig-plug` parameter descriptors
- optional lifecycle methods

`PluginSpec(Plugin)` validates those declarations at compile time and exposes:

- `ParameterSet`: reflected descriptor metadata
- `ParameterValues`: atomic normalized values initialized from descriptor defaults
- lifecycle flags for optional `init`, `prepare`, `process`, `process64`, and `deinit` declarations
- `init(params)`: builds the reflected set and value storage

`validateLifecycle(Plugin)` currently accepts:

- `init(allocator: std.mem.Allocator) !Plugin`
- `prepare(self: *Plugin, config: PrepareConfig) void`
- `process(self: *Plugin, context: *process.ProcessContext(f32)) void`
- `process64(self: *Plugin, context: *process.ProcessContext(f64)) void`
- `deinit(self: *Plugin) void`

`process.ProcessContext(Sample)` carries typed input and output channel views, parameter changes, and the current sample rate. The input and output views validate that each channel has the same frame count before a context is created. Parameter changes validate normalized values and sample offsets within the current block.

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

- Generalize the gain-specific Layer 1 bridge into reusable component/controller glue.
- Generalize VST3 audio context construction beyond the gain component.
- Add example plugins that use the public `zig-plug-core` API directly.
