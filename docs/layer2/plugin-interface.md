# Layer 2 Plugin Interface

The current `zig-plug` plugin prototype is a compile-time spec helper with a reusable Layer 1 bridge for reflected parameter metadata, string conversion, normalized/plain conversion, state, host automation collection and application, stereo audio bus metadata, VST3 audio buffer views, and main audio sample-size dispatch. The gain plugin now uses reusable simple stereo effect and reflected edit-controller shells.

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

`examples/gain_core.zig`, `examples/bypass_core.zig`, `examples/mode_gain_core.zig`, and `examples/voice_mix_core.zig` are checked examples for the pure `zig-plug-core` API. Together they cover float, bool, enum, and int parameters, lifecycle validation, id-based parameter changes, and audio processing through `process.ProcessContext(f32)`. `vst3-zig/src/bypass_plugin.zig` is the second bundled VST3 example using the reusable shells. `zig build validate-examples` validates both bundled examples locally on macOS, and the bypass bundle also has Linux and Windows bundle steps.

## Open Work

- Add more bundled VST3 examples that use the reusable component and controller shells.
