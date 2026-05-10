# Layer 2 Plugin Interface

The current `zig-plug` layer is a compile-time plugin interface with a reusable Layer 1 bridge for reflected parameter metadata, string conversion, normalized/plain conversion, state, host automation and event collection, stereo audio bus metadata, VST3 audio buffer views, optional plug-view and XML representation creation, reusable error-context, string-result, cloneable, update-handler, persistent, persistent-attribute, unit-info, unit-data, inter-app-audio, test-interface, test-plug-provider, plugin-compatibility, plug-frame, context-menu, parameter-finder, content-scale, Linux run-loop, and Wayland host/frame helpers for custom editors and SDK callbacks, and main audio sample-size dispatch. The bundled examples use reusable simple stereo effect and reflected edit-controller shells.

## Current API

A plugin type declares:

- `name`: display name
- `vendor`: vendor string
- optional `url` and `email`: factory contact metadata
- optional `component_class_name` and `controller_class_name`: host-facing VST3 class names
- optional `component_category` and `controller_category`: host-facing VST3 class categories
- `Params`: struct of `zig-plug` parameter descriptors
- optional lifecycle methods

`PluginSpec(Plugin)` validates those declarations at compile time, including reserved unit/program-list sentinel ids, program snapshot parameter ids, and normalized values, and exposes:

- `ParameterSet`: reflected descriptor metadata
- `ParameterValues`: atomic normalized values initialized from descriptor defaults
- `Units`: reflected unit and program-list metadata
- normalized plugin, factory, component, and controller metadata with conservative defaults
- `encoded_parameter_state_size`: byte count for a full reflected parameter snapshot
- lifecycle flags for optional `init`, `prepare`, `process`, `process64`, and `deinit` declarations
- `initChecked(params)`: validates parameter metadata, then builds the reflected set and value storage
- `init(params)`: builds the reflected set and value storage, panicking if metadata is invalid

`PluginInstance(Plugin)` owns a plugin value plus its reflected spec, exposes the instance parameter set and mutable or const value storage, exposes bound parameter view/editor handles, provides reflected parameter metadata by index or id, index and existence lookup, plain/normalized conversion by index, id, display name, or field, and plain text formatting/parsing helpers, provides typed, normalized, index-based, id-based, name-based, and plain parameter load/store helpers by id or display name, exposes reflected unit and program-list metadata, applies reflected parameter changes to instance-owned values before process dispatch, can return the count of actually applied automatable writable parameter changes, exposes bulk and single-parameter default reset helpers, exposes the encoded reflected parameter-state size, reads and writes reflected parameter state for the instance, can report decoded, restored, and ignored state entries, writes debug JSON for reflected parameter state, and drives only the lifecycle hooks the plugin declares. It creates the plugin through `init(allocator)` when present, otherwise it uses a default struct value for declaration-only plugin types.

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

`process.ProcessContext(Sample)` carries typed input/output channel views, parameter changes, input events, optional output events, and the current sample rate. `ProcessContext(Sample).init(sample_rate, input_channels, output_channels)` builds the audio views, rejects non-positive or non-finite sample rates, and validates matching frame counts within each side. `ProcessContext(Sample).initWith(sample_rate, input_channels, output_channels, .{ ... })` also attaches parameter changes, input events, and output-event storage while validating them against the context frame count.

Unit and program helpers:

- Plugins may declare `pub const units = plug.units.Config{ ... }`.
- `plug.units.Unit.root("Root")` declares the root unit. Additional units can attach to the root or another unit and may point at a program list.
- `plug.units.ProgramList`, `plug.units.Program`, `plug.units.ProgramParameter`, and `plug.units.ProgramInfo` describe host-facing program names, optional normalized parameter snapshots, and program metadata.
- Unit metadata validation rejects missing or duplicate root units, empty unit or program names, duplicate unit names, duplicate program-list ids or names, duplicate program names, duplicate program parameter ids, duplicate program info keys, missing or cyclic unit parents, and unit links to unknown program lists.
- Parameter metadata validation rejects descriptors whose `unit_id` does not match a reflected unit.
- Program snapshot validation rejects parameter ids that do not match reflected parameters.
- `PluginInstance.unitCount`, `unit`, `unitById`, `unitByName`, `rootUnit`, unit index and existence checks by id or name, `programListCount`, `programList`, `programListById`, `programListByName`, program-list index and existence checks by id or name, `programListForUnit`, `programListForUnitName`, `programCount`, `program`, `programByName`, `programName`, program index and existence checks by name, `programParameterCount`, `programParameterCountByName`, `programParameter`, `programParameterByName`, `programParameterById`, `programParameterByNameAndId`, `programInfo`, and `programInfoByName` expose the reflected metadata.
- `PluginInstance.applyProgram`, `applyProgramByName`, `applyProgramForUnit`, `applyProgramByNameForUnit`, `applyProgramForUnitName`, and `applyProgramByNameForUnitName` apply a program's normalized parameter snapshot to reflected parameter ids after validating the whole snapshot.

Audio helpers:

- `inputChannel`, `outputChannel`, `inputChannelCount`, `outputChannelCount`, input/output channel emptiness checks, `inputFrameCount`, `outputFrameCount`, and `frameCount`
- `fillOutputs` and `clearOutputs`
- `frameCount` uses the shared input/output frame count for effects, the output frame count for generators with no audio inputs, and the input frame count for analyzers with no audio outputs.

Parameter helpers:

- `ParameterSet.parameterChange`, `ParameterSet.parameterChangeNormalized`, `PluginInstance.parameterChange`, and `PluginInstance.parameterChangeNormalized` construct changes from reflected field names for tests and non-host callers.
- Parameter descriptors can set `unit_id` to group host-facing parameters under a reflected unit.
- `ParameterValues.view(set)` and `PluginInstance.parameterView()` bind descriptors and values into a `ParameterView`.
- `ParameterValues.editor(set)` and `PluginInstance.parameterEditor()` bind descriptors and mutable values into a `ParameterEditor`.
- `ParameterSet`, `ParameterView`, `ParameterEditor`, and `PluginInstance` expose parameter counts and parameter metadata by index, id, and display name for ids, short names, units, defaults, bypass flags, automation/read-only flags, unit ids, step counts, and list flags, plus id and display-name existence checks.
- `PluginInstance.parameterFieldId`, `parameterFieldName`, `parameterFieldShortName`, `parameterFieldUnits`, `parameterFieldDefaultNormalized`, `parameterFieldIsBypass`, `parameterFieldCanAutomate`, `parameterFieldIsReadOnly`, `parameterFieldUnitId`, `parameterFieldStepCount`, and `parameterFieldIsList` expose reflected parameter metadata from comptime field names.
- `ParameterValues.applyChangesCount` and `PluginInstance.applyParameterChangesCount` apply process changes and return the number accepted by reflected metadata. Unknown, non-automatable, and read-only parameters are ignored.
- `ProcessContext.parameterChanges`, `parameterChangeCount`, `parameterChangesEmpty`, first/latest/next parameter-change offsets, per-id first/latest/next offsets, `latestParameterChange`, `firstParameterChange`, `countParameterChanges`, `hasParameterChange`, `latestParameterNormalized`, `firstParameterNormalized`, clamped defaulted normalized reads, `latestParameterChangeAtOrBefore`, `latestParameterNormalizedAtOrBefore`, `parameterNormalizedAtOrBeforeOr`, `parameterSegmentAt`, `parameterSegments`, `parameterBlockSegments`, and `processBlockSegments` expose common process-time reads and no-allocation stable automation ranges.

Event helpers:

- `Event.noteOn`, `Event.noteOff`, `Event.midiCc`, `Event.pitchBend`, `Event.aftertouch`, `Event.noteExpressionValue`, `Event.noteExpressionInt`, `Event.noteExpressionText`, `Event.dataEvent`, and `Event.other` construct common input and output events.
- `Event.withBusIndex` retargets a constructed event to another event bus.
- `Event.withControlNumber` preserves legacy MIDI controller numbers when a host bridge needs to keep them attached to converted events.
- `Event.validate`, `Events.init`, and `EventWriter` reject events outside the current process block, negative bus indexes, invalid MIDI channel/pitch/controller metadata, and non-finite or out-of-range normalized event values.
- `ProcessContext.inputEvents`, `inputEventsOfKind`, `inputEventsAtOffset`, `inputEventBlockSegments`, `inputEventCount`, `inputEventsEmpty`, first/latest/next event offsets, per-kind first/latest/next offsets, `firstEvent`, `latestEvent`, `hasEvent`, and `countEvents` expose input-event reads without reaching into the event view field.
- `EventWriter.appendAll` copies validated event views into bounded output storage. Its count, empty/full, capacity, remaining-capacity, frame-count, `canAppend`, written-event view, block segment, offset, and kind-query helpers support direct tests and non-context adapters.
- `ProcessContext.setOutputEvents`, `appendOutputEvent`, `appendOutputEvents`, `canAppendOutputEvent`, `canAppendOutputEvents`, `writtenOutputEvents`, `outputEventsOfKind`, `clearOutputEvents`, output-event kind and first/latest/next per-kind offset reads, `outputEventCount`, `outputEventCapacity`, `outputEventRemainingCapacity`, `outputEventFrameCount`, `outputEventsEmpty`, and `outputEventsFull` let processors write, inspect, reset, and plan output events without unwrapping the optional writer. Output-event writers must use the same frame count as the process context.

The VST3 shell gives processors a bounded output-event writer and flushes written events to the host after audio processing.

Use `processWithParameterView` when a processor needs block-latest reflected parameter state. `processWithParameters` remains available for code that needs direct access to the reflected set and raw value storage. Use `context.parameterBlockSegments`, `context.inputEventBlockSegments`, or `context.processBlockSegments` when sample-accurate automation, MIDI timing, or both matter, and use `context.parameterNormalizedAtOrBeforeOr` at the segment start to resolve the descriptor/default value before the first automation point.

## Example

```zig
const plug = @import("zig-plug");

const Gain = struct {
    pub const name = "Gain";
    pub const vendor = "zig-vst3";
    pub const url = "https://github.com/joshburgess/zig-vst3";
    pub const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
};

const GainSpec = plug.plugin.PluginSpec(Gain);
```

`examples/gain_core.zig`, `examples/bypass_core.zig`, `examples/mode_gain_core.zig`, `examples/voice_mix_core.zig`, `examples/note_gate_core.zig`, `examples/event_echo_core.zig`, `examples/event_monitor_core.zig`, and `examples/sine_synth_core.zig` are checked examples for the public `zig-plug` API. Together they cover float, bool, enum, and int parameters, runtime reflected metadata counts, id-based parameter changes, sample-offset parameter changes, block-split automation, state-aware process hooks, state restore reports, state debug JSON, input events, held-note state, zero-velocity note-on release behavior, event-kind iteration, combined event and automation segment processing, output events, output-only processing, and audio processing through `process.ProcessContext(f32)`. `vst3-zig/src/gain_plugin.zig`, `vst3-zig/src/bypass_plugin.zig`, `vst3-zig/src/mode_gain_plugin.zig`, `vst3-zig/src/voice_mix_plugin.zig`, `vst3-zig/src/note_gate_plugin.zig`, and `vst3-zig/src/event_echo_plugin.zig` are bundled VST3 examples using the reusable shells. The shells query and retain `IHostApplication` during initialization, retain host channel-context, automation-state, and data-exchange interfaces, expose conservative defaults for host/plugin connection points, store the host component handler, and can send `beginEdit`, `performEdit`, `endEdit`, `setDirty`, `requestOpenEditor`, `startGroupEdit`, `finishGroupEdit`, context-menu, bus activation, system-time, progress, unit-selection, program-list, channel-context, automation-state, data-exchange, and unit-by-bus callbacks for plugin-side edits. Reflected `zig-plug` unit and program-list metadata is exposed through `IUnitInfo`. `vst3-zig.vst_message` provides reusable `IMessage`, `IAttributeList`, and `IStreamAttributes` objects for future connection-point notifications and state/preset metadata. The shells also expose the optional VST3 controller and processor interfaces commonly queried by hosts, while still returning no-data/no-assignment results where the Layer 2 API does not yet model a feature. `zig build validate-examples` validates the bundled examples locally on macOS, and each bundle has Linux and Windows bundle steps.

## Open Work

- Complete the deferred Note Gate MIDI-routing host smoke test.
- Add a host smoke test that directly observes Event Echo output events.
