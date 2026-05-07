# Layer 2 Plugin Interface

The current `zig-plug` plugin prototype is a compile-time spec helper with a reusable Layer 1 bridge for reflected parameter metadata, string conversion, normalized/plain conversion, state, host automation and event collection, stereo audio bus metadata, VST3 audio buffer views, optional plug-view creation, parameter-finder helpers for custom editors, and main audio sample-size dispatch. The gain plugin now uses reusable simple stereo effect and reflected edit-controller shells.

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

`process.ProcessContext(Sample)` carries typed input and output channel views, parameter changes, input events, optional output events, and the current sample rate. The input and output views validate that each channel has the same frame count before a context is created. Parameter changes validate normalized values and sample offsets within the current block, expose block-latest lookup, expose latest-at-sample lookup, and expose the next sample offset with an automation change. Events currently expose note-on, note-off, MIDI CC, pitch bend, aftertouch, note-expression value/int/text, data payloads such as SysEx, and other event kinds with block-offset validation. The VST3 shell gives processors a bounded output-event writer and flushes written events to the host after audio processing.

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

`examples/gain_core.zig`, `examples/bypass_core.zig`, `examples/mode_gain_core.zig`, `examples/voice_mix_core.zig`, `examples/note_gate_core.zig`, and `examples/event_echo_core.zig` are checked examples for the pure `zig-plug-core` API. Together they cover float, bool, enum, and int parameters, lifecycle validation, id-based parameter changes, sample-offset parameter changes, input events, output events, and audio processing through `process.ProcessContext(f32)`. `vst3-zig/src/gain_plugin.zig`, `vst3-zig/src/bypass_plugin.zig`, `vst3-zig/src/mode_gain_plugin.zig`, `vst3-zig/src/voice_mix_plugin.zig`, `vst3-zig/src/note_gate_plugin.zig`, and `vst3-zig/src/event_echo_plugin.zig` are bundled VST3 examples using the reusable shells. The shells query and retain `IHostApplication` during initialization, retain host channel-context and automation-state interfaces, expose conservative defaults for host/plugin connection points, store the host component handler, and can send `beginEdit`, `performEdit`, `endEdit`, `setDirty`, `requestOpenEditor`, `startGroupEdit`, `finishGroupEdit`, context-menu, bus activation, system-time, unit-selection, program-list, channel-context, automation-state, and unit-by-bus callbacks for plugin-side edits. `vst3-zig.vst_message` provides reusable `IMessage`, `IAttributeList`, and `IStreamAttributes` objects for future connection-point notifications and state/preset metadata. The shells also expose the optional VST3 controller and processor interfaces commonly queried by hosts, while still returning no-data/no-assignment results where the Layer 2 API does not yet model a feature. `zig build validate-examples` validates the bundled examples locally on macOS, and each bundle has Linux and Windows bundle steps.

## Open Work

- Record host smoke test notes for the reusable component and controller shells.
