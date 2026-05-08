# Layer 2 Plugin Interface

The current `zig-plug` layer is a compile-time plugin interface with a reusable Layer 1 bridge for reflected parameter metadata, string conversion, normalized/plain conversion, state, host automation and event collection, stereo audio bus metadata, VST3 audio buffer views, optional plug-view and XML representation creation, reusable error-context, string-result, cloneable, update-handler, persistent, persistent-attribute, unit-info, unit-data, inter-app-audio, test-interface, test-plug-provider, plugin-compatibility, plug-frame, context-menu, parameter-finder, content-scale, Linux run-loop, and Wayland host/frame helpers for custom editors and SDK callbacks, and main audio sample-size dispatch. The bundled examples use reusable simple stereo effect and reflected edit-controller shells.

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

`PluginInstance(Plugin)` owns a plugin value plus its reflected spec, exposes the instance parameter set and mutable or const value storage, exposes bound parameter view/editor handles, provides typed, normalized, and id-based parameter load/store helpers, applies reflected parameter changes to instance-owned values before process dispatch, reads and writes reflected parameter state for the instance, and drives only the lifecycle hooks the plugin declares. It creates the plugin through `init(allocator)` when present, otherwise it uses a default struct value for declaration-only plugin types.

`validateLifecycle(Plugin)` currently accepts:

- `init(allocator: std.mem.Allocator) !Plugin`
- `prepare(self: *Plugin, config: PrepareConfig) void`
- `process(self: *Plugin, context: *process.ProcessContext(f32)) void`
- `processWithParameterView(self: *Plugin, context: *process.ProcessContext(f32), view: ParameterView) void`
- `processWithParameters(self: *Plugin, context: *process.ProcessContext(f32), set: *const ParameterSet, values: *const ParameterValues) void`
- `process64(self: *Plugin, context: *process.ProcessContext(f64)) void`
- `process64WithParameterView(self: *Plugin, context: *process.ProcessContext(f64), view: ParameterView) void`
- `process64WithParameters(self: *Plugin, context: *process.ProcessContext(f64), set: *const ParameterSet, values: *const ParameterValues) void`
- `deinit(self: *Plugin) void`

`process.ProcessContext(Sample)` carries typed input and output channel views, parameter changes, input events, optional output events, and the current sample rate. `ProcessContext(Sample).init(sample_rate, input_channels, output_channels)` builds the audio views and validates matching frame counts. `ProcessContext(Sample).initWith(sample_rate, input_channels, output_channels, .{ ... })` also attaches optional parameter changes, input events, and output-event storage while validating against the context frame count. Parameter changes validate normalized values and sample offsets within the current block, expose id presence/count lookup, expose first and block-latest lookup, expose normalized-value shortcuts for first/latest changes, expose latest-at-sample lookup, expose defaulting helpers for block-latest and sample-accurate reads, and expose the next sample offset with an automation change. `ParameterSet.parameterChange` and `ParameterSet.parameterChangeNormalized` construct changes from reflected field names for tests and non-host callers. `ParameterValues.view(set)` and `PluginInstance.parameterView()` bind reflected descriptors and values into a `ParameterView`, which exposes typed `load`, normalized `loadNormalized`, and id-based loads without repeating the set argument. `ParameterValues.editor(set)` and `PluginInstance.parameterEditor()` bind reflected descriptors and mutable values into a `ParameterEditor`, which exposes typed, normalized, plain-id, and normalized-id stores without repeating the set argument. Events currently expose note-on, note-off, MIDI CC, pitch bend, aftertouch, note-expression value/int/text, data payloads such as SysEx, and other event kinds with block-offset validation, first-kind lookup, kind presence checks, and kind counts. `Event.noteOn`, `Event.noteOff`, `Event.midiCc`, `Event.pitchBend`, `Event.aftertouch`, `Event.noteExpressionValue`, `Event.noteExpressionInt`, `Event.noteExpressionText`, `Event.dataEvent`, and `Event.other` construct common input and output events for tests and non-host callers. `Event.withBusIndex` retargets a constructed event to another event bus. `Event.withControlNumber` preserves legacy MIDI controller numbers when a host-specific bridge needs to keep them attached to converted events. `EventWriter.appendAll` copies validated event views into bounded output storage. `ProcessContext.appendOutputEvent`, `ProcessContext.appendOutputEvents`, and `ProcessContext.writtenOutputEvents` let processors write and inspect output events without unwrapping the optional writer. The VST3 shell gives processors a bounded output-event writer and flushes written events to the host after audio processing.

Use `processWithParameterView` when a processor needs block-latest reflected parameter state. `processWithParameters` remains available for code that needs direct access to the reflected set and raw value storage. Use `context.parameter_changes.normalizedAtOrBeforeOr` directly inside the sample loop when sample-accurate automation matters and a descriptor/default value should apply before the first automation point.

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

`examples/gain_core.zig`, `examples/bypass_core.zig`, `examples/mode_gain_core.zig`, `examples/voice_mix_core.zig`, `examples/note_gate_core.zig`, and `examples/event_echo_core.zig` are checked examples for the public `zig-plug` API. Together they cover float, bool, enum, and int parameters, lifecycle validation, id-based parameter changes, sample-offset parameter changes, state-aware process hooks, input events, output events, and audio processing through `process.ProcessContext(f32)`. `vst3-zig/src/gain_plugin.zig`, `vst3-zig/src/bypass_plugin.zig`, `vst3-zig/src/mode_gain_plugin.zig`, `vst3-zig/src/voice_mix_plugin.zig`, `vst3-zig/src/note_gate_plugin.zig`, and `vst3-zig/src/event_echo_plugin.zig` are bundled VST3 examples using the reusable shells. The shells query and retain `IHostApplication` during initialization, retain host channel-context, automation-state, and data-exchange interfaces, expose conservative defaults for host/plugin connection points, store the host component handler, and can send `beginEdit`, `performEdit`, `endEdit`, `setDirty`, `requestOpenEditor`, `startGroupEdit`, `finishGroupEdit`, context-menu, bus activation, system-time, progress, unit-selection, program-list, channel-context, automation-state, data-exchange, and unit-by-bus callbacks for plugin-side edits. `vst3-zig.vst_message` provides reusable `IMessage`, `IAttributeList`, and `IStreamAttributes` objects for future connection-point notifications and state/preset metadata. The shells also expose the optional VST3 controller and processor interfaces commonly queried by hosts, while still returning no-data/no-assignment results where the Layer 2 API does not yet model a feature. `zig build validate-examples` validates the bundled examples locally on macOS, and each bundle has Linux and Windows bundle steps.

## Open Work

- Complete the deferred Note Gate MIDI-routing host smoke test.
- Add a host smoke test that directly observes Event Echo output events.
