# Layer 2 Plugin Interface

The current `zig-vst3-plugin` layer is a compile-time plugin interface with a reusable Layer 1 bridge for reflected parameter metadata, string conversion, normalized/plain conversion, state, host automation and event collection, configurable stereo audio bus metadata for effects, input-only analyzers, and output-only generators, VST3 audio buffer views, optional process-state reset hooks, optional plug-view and XML representation creation, reusable error-context, string-result, cloneable, update-handler, persistent, persistent-attribute, unit-info, unit-data, inter-app-audio, test-interface, test-plug-provider, plugin-compatibility, plug-frame, context-menu, parameter-finder, content-scale, Linux run-loop, and Wayland host/frame helpers for custom editors and SDK callbacks, and main audio sample-size dispatch. The bundled examples use reusable simple stereo effect and reflected edit-controller shells.

## Current API

A plugin type declares:

- `name`: display name
- `vendor`: vendor string
- optional `url` and `email`: factory contact metadata
- optional `component_class_name` and `controller_class_name`: host-facing VST3 class names
- optional `component_category` and `controller_category`: host-facing VST3 class categories
- optional `audio_input`, `audio_output`, `event_input`, and `event_output`: public bus topology metadata
- `Params`: struct of `zig-vst3-plugin` parameter descriptors
- optional lifecycle methods

`PluginSpec(Plugin)` validates those declarations at compile time, including non-empty plugin/class/category metadata, NUL-free contact strings, reserved unit/program-list sentinel ids, program snapshot parameter ids, and normalized values, and exposes:

- `ParameterSet`: reflected descriptor metadata
- `ParameterValues`: atomic normalized values initialized from descriptor defaults
- `Units`: reflected unit and program-list metadata
- normalized plugin, factory, component, and controller metadata with conservative defaults
- bus topology metadata with stereo audio input, stereo audio output, event input, and no event output as defaults
- `encoded_parameter_state_size`: byte count for a full reflected parameter snapshot
- lifecycle flags for optional `init`, `prepare`, `process`, `process64`, and `deinit` declarations
- `initChecked(params)`: validates plugin, parameter, unit, and program metadata, then builds the reflected set and value storage
- `init(params)`: builds the reflected set and value storage, panicking if metadata is invalid

`PluginInstance(Plugin)` owns a plugin value plus its reflected spec, exposes bus-topology and lifecycle-hook predicates, exposes the instance parameter set and mutable or const value storage, copies parameter values from another same-plugin instance, exposes bound parameter view/editor handles, provides reflected parameter metadata by index or id, count and emptiness checks, index and existence lookup, plain/normalized conversion by index, id, display name, or field, and plain text formatting/parsing helpers, provides typed, normalized, index-based, id-based, name-based, and plain parameter load/store helpers by id or display name, exposes reflected unit and program-list metadata, applies reflected parameter changes to instance-owned values before process dispatch, can return accepted-change and changed-value counts for automatable writable parameter changes, exposes default-state checks plus bulk and single-parameter default reset helpers with counted variants, exposes reflected parameter-state entry count and encoded size, reads and writes reflected parameter state for the instance, supports migrated state reads, migration diagnostics, and migrated-id resolution, can report decoded, restored, ignored, and unaccounted state entries with presence, emptiness, and classification helpers, supports header-only state inspection plus instance-bound header, decoded-report, and restored-report entry-count compatibility checks through the state module, writes debug JSON for reflected parameter state, and drives only the lifecycle hooks the plugin declares. It creates the plugin through `init(allocator)` when present, otherwise it uses a default struct value for declaration-only plugin types.

`PrepareConfig.validate` and `PluginInstance.prepareChecked` reject non-positive or non-finite sample rates and zero maximum block sizes before a plugin's `prepare` hook runs. `PluginInstance.prepare` remains the convenience wrapper for callers that already trust the configuration. The VST3 shell applies the same checks to host process setup before accepting it and rejects unsupported process sample-size tags before dispatch.

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

`process.ProcessContext(Sample)` carries typed input/output channel views, parameter changes, input events, optional output events, and the current sample rate. It exposes sample rate, sample duration, block duration, sample-offset seconds, and remaining-frame/second timing helpers. `ProcessContext(Sample).init(sample_rate, input_channels, output_channels)` builds the audio views, rejects non-positive or non-finite sample rates, validates matching frame counts within each side, and rejects side-to-side frame-count mismatches for processors with both audio inputs and outputs. `ProcessContext(Sample).initWith(sample_rate, input_channels, output_channels, .{ ... })` also attaches parameter changes, input events, and output-event storage while validating them against the context frame count.

Unit and program helpers:

- Plugins may declare `pub const units = plug.units.Config{ ... }`.
- `plug.units.Unit.root("Root")` declares the root unit. Additional units can attach to the root or another unit and may point at a program list.
- `plug.units.ProgramList`, `plug.units.Program`, `plug.units.ProgramParameter`, and `plug.units.ProgramInfo` describe host-facing program names, optional normalized parameter snapshots, and program metadata.
- `Unit.isRoot`, `Unit.hasParent`, `Unit.hasProgramList`, `Program.parameterCount`, `Program.infoCount`, `Program.hasParameters`, `Program.parametersEmpty`, `Program.hasInfo`, `Program.infoEmpty`, `ProgramList.programCount`, `ProgramList.isEmpty`, and `ProgramList.hasPrograms` provide value-level metadata checks for reflected unit and program values.
- Unit metadata validation rejects missing or duplicate root units, empty unit or program names, embedded NUL bytes in host-facing unit and program strings, duplicate unit names, duplicate program-list ids or names, duplicate program names, duplicate program parameter ids, duplicate program info keys, missing or cyclic unit parents, and unit links to unknown program lists.
- Unit and program metadata helpers can identify duplicate unit ids/names, program-list ids/names, program names, program parameter ids, and program info keys by value, duplicate item index, and boolean predicates before strict validation is run. Value-level `ProgramList` and `Program` helpers also expose direct program, parameter snapshot, parameter-id index, info entry, and info-key index lookups without constructing a plugin instance.
- Parameter metadata validation rejects descriptors whose `unit_id` does not match a reflected unit.
- Program snapshot validation rejects non-finite or out-of-range normalized values and parameter ids that do not match reflected parameters.
- `PluginInstance.unitCount`, unit emptiness checks, `unit`, `unitById`, `unitByName`, `rootUnit`, direct root unit id/name lookups, unit index and existence checks by id or name, duplicate unit id/name diagnostics, `programListCount`, program-list emptiness and presence checks, `programList`, `programListById`, `programListByName`, program-list index and existence checks by id or name, duplicate program-list id/name diagnostics, `programListForUnit`, `programListForUnitName`, direct unit-to-program-list id/name lookups, `programCount`, `program`, `programByName`, `programName`, program index and existence checks by name, duplicate program-name value/index checks, program parameter/info count and emptiness checks, `programParameter`, `programParameterByName`, `programParameterById`, `programParameterByNameAndId`, program-parameter id index and existence checks, duplicate program-parameter id value/index checks, `programInfo`, `programInfoByName`, program-info entry/key index and existence checks, and duplicate program-info key value/index checks expose the reflected metadata.
- `PluginInstance.applyProgram`, `applyProgramByName`, `applyProgramForUnit`, `applyProgramByNameForUnit`, `applyProgramForUnitName`, and `applyProgramByNameForUnitName` apply a program's finite normalized parameter snapshot to reflected parameter ids after validating the whole snapshot. Their `*Count` variants return `null` for a missing target or the number of parameter values that changed.

Timing and audio helpers:

- `sampleRate`, `sampleDurationSeconds`, `blockDurationSeconds`, `blockSegment`, `sampleOffsetSeconds`, sample-offset containment/end predicates, `remainingFramesFromOffset`, and `remainingSecondsFromOffset`
- `inputChannel`, `outputChannel`, input/output per-index channel presence and emptiness checks, `inputChannelCount`, `outputChannelCount`, input/output channel presence and emptiness checks, `inputFrameCount`, `outputFrameCount`, and `frameCount`
- `fillOutputs` and `clearOutputs`
- `frameCount` uses the shared input/output frame count for effects, the output frame count for generators with no audio inputs, and the input frame count for analyzers with no audio outputs.
- `BlockSegment` and `ParameterSegment` expose frame-count, empty, sample-containment, start, and end helpers for segmented processors.

Parameter helpers:

- `ParameterSet.parameterChange`, `ParameterSet.parameterChangeNormalized`, `PluginInstance.parameterChange`, and `PluginInstance.parameterChangeNormalized` construct finite normalized changes from reflected field names for tests and non-host callers.
- Parameter descriptors can set `unit_id` to group host-facing parameters under a reflected unit.
- `ParameterValues.view(set)` and `PluginInstance.parameterView()` bind descriptors and values into a `ParameterView`.
- `ParameterValues.editor(set)` and `PluginInstance.parameterEditor()` bind descriptors and mutable values into a `ParameterEditor`.
- `ParameterSet`, `ParameterView`, `ParameterEditor`, and `PluginInstance` expose parameter counts and parameter metadata by index, id, display name, and reflected field name for ids, short names, units, normalized and plain defaults, numeric ranges, enum options, option presence and emptiness, bypass flags, automation/read-only flags, unit ids, step counts, and list flags, plus id and display-name existence checks, duplicate id/name diagnostics, and first descriptor-error diagnostics.
- `PluginInstance.parameterFieldDescriptor`, `parameterFieldId`, `parameterFieldName`, `parameterFieldShortName`, `parameterFieldUnits`, `parameterFieldDefaultNormalized`, `parameterFieldDefaultPlain`, `parameterFieldPlainMinimum`, `parameterFieldPlainMaximum`, `parameterFieldOptionCount`, `parameterFieldOptionLabel`, `parameterFieldOptionNormalized`, field option presence and emptiness checks, `parameterFieldIsBypass`, `parameterFieldCanAutomate`, `parameterFieldIsReadOnly`, `parameterFieldUnitId`, `parameterFieldStepCount`, and `parameterFieldIsList` expose reflected parameter metadata from comptime field names.
- `ParameterValues`, `ParameterView`, `ParameterEditor`, and `PluginInstance` expose default-state checks by index, id, display name, and comptime field name, plus aggregate all-defaults, non-default presence, non-default count, counted store helpers, and counted bulk and single-parameter reset helpers for reset buttons and dirty-state UI. Counted store helpers return `null` for an invalid target or value, `0` for a no-op store, and `1` when the stored normalized value changes.
- `ParameterValues.applyChangesCount` and `PluginInstance.applyParameterChangesCount` apply process changes and return the number accepted by reflected metadata. `applyChangesChangedCount` and `applyParameterChangesChangedCount` return how many accepted changes actually changed stored normalized values. Unknown, non-automatable, and read-only parameters are ignored.
- `ProcessContext.parameterChanges`, `parameterChangeCount`, parameter-change id/offset predicates, parameter-change presence and emptiness checks, first/latest/next parameter-change offsets, per-id first/latest/next offsets, overall first/latest reads, per-offset and id-at-offset first/latest reads, `latestParameterChange`, `firstParameterChange`, `countParameterChanges`, `hasParameterChange`, per-id and per-offset parameter-change count/presence/emptiness checks, `onlyParameterChangesForId`, overall first/latest normalized reads, `latestParameterNormalized`, `firstParameterNormalized`, per-offset and id-at-offset normalized reads, clamped defaulted normalized reads including exact-offset and at-or-before variants, `latestParameterChangeAtOrBefore`, `latestParameterNormalizedAtOrBefore`, `parameterNormalizedAtOrBeforeOr`, `parameterSegmentAt`, `parameterSegments`, `parameterBlockSegments`, and `processBlockSegments` expose common process-time reads and no-allocation stable automation ranges.

Event helpers:

- `Event.noteOn`, `Event.noteOff`, `Event.midiCc`, `Event.pitchBend`, `Event.aftertouch`, `Event.noteExpressionValue`, `Event.noteExpressionInt`, `Event.noteExpressionText`, `Event.dataEvent`, and `Event.other` construct common input and output events.
- `Event.asNoteOn`, `asNoteAttack`, `asNoteOff`, `asNoteRelease`, `asMidiCC`, `asPitchBend`, `asAftertouch`, `asNoteExpressionValue`, `asNoteExpressionInt`, `asNoteExpressionText`, and `asData` expose typed payload views for processors that do not want to switch on the broad event struct directly. `Event.noteLifecycle` classifies note attacks, note releases, and non-note events, and `asNoteRelease` handles both note-off and zero-velocity note-on releases.
- `Event.withBusIndex`, `withSampleOffset`, `withChannel`, `withPitch`, `withValue`, `withIntValue`, `withVelocity`, `withNoteId`, `withExpressionTypeId`, `withDataType`, and `withData` retarget constructed events for generated output-event routing.
- `Event.withControlNumber` preserves legacy MIDI controller numbers when a host bridge needs to keep them attached to converted events.
- `Event.isKind`, `Event.isAtOffset`, `Event.isKindAtOffset`, `Event.isNoteAttack`, `Event.isNoteRelease`, `Event.isNote`, `Event.isMidi`, `Event.isNoteExpression`, `Event.isData`, `Event.isOther`, `Event.hasChannel`, `Event.isForChannel`, `Event.isForBus`, `Event.isForBusChannel`, and `Event.isNoteForPitch` cover common event routing checks, including the zero-velocity note-on release convention.
- `Event.validate`, `Events.init`, and `EventWriter` reject events outside the current process block, negative bus indexes, invalid MIDI channel/pitch/controller metadata, and non-finite or out-of-range normalized event values. The VST3 bridge drops malformed or oversized host data-event payloads before exposing them to plugin code.
- `ProcessContext.inputEvents`, `inputEventsOfKind`, `inputEventsAtOffset`, `inputEventBlockSegments`, `inputEventCount`, input-event presence and emptiness checks, first/latest/next event offsets, first/latest input-event reads, per-offset first/latest reads, per-kind first/latest/next offsets and kind-at-offset first/latest reads, per-bus/channel/bus-channel first/latest/next offsets and reads, `firstEvent`, `latestEvent`, `hasEvent`, `countEvents`, note-attack and note-release count/presence/emptiness/only helpers, per-offset and kind-at-offset event count/presence/emptiness/only checks, and bus/channel/bus-channel event presence, emptiness, count, and only-event helpers expose input-event reads without reaching into the event view field.
- `EventWriter.append`, `appendCount`, `appendAll`, and `appendAllCount` copy validated event views into bounded output storage. Its count, empty/full, capacity, remaining-capacity, frame-count, count-based and validated append planning, clear count, written-event view, first/latest-event reads, per-offset and kind-at-offset first/latest reads, per-bus/channel/bus-channel first/latest/next offsets and reads, block segment, offset, kind-query, note-attack and note-release queries, per-offset and kind-at-offset queries including only-event checks, and bus/channel/bus-channel presence, emptiness, count, and only-event helpers support direct tests and non-context adapters.
- `ProcessContext.setOutputEvents`, `appendOutputEvent`, `appendOutputEventCount`, `appendOutputEvents`, `appendOutputEventsCount`, `canAppendOutputEvent`, `canAppendOutputEvents`, validated output-event append planning, `writtenOutputEvents`, `outputEventsOfKind`, `clearOutputEvents`, `clearOutputEventsCount`, output-event first/latest reads, per-offset first/latest reads, kind and first/latest/next per-kind offset reads, kind-at-offset first/latest reads, per-bus/channel/bus-channel first/latest/next offsets and reads, bus/channel/bus-channel presence, emptiness, count, and only-event helpers, per-offset and kind-at-offset count/presence/emptiness/only helpers, note-attack and note-release helpers, `outputEventCount`, `outputEventCapacity`, `outputEventRemainingCapacity`, `outputEventFrameCount`, output-event presence and emptiness checks, and `outputEventsFull` let processors write, inspect, reset, and plan output events without unwrapping the optional writer. Output-event writers must use the same frame count as the process context.

The VST3 shell gives processors a bounded output-event writer and flushes written events to the host after audio processing. It maps malformed process frame counts, channel counts, frame-count mismatches, invalid automation, and invalid event attachments to host-visible invalid-argument results, while retaining host-compatible no-op handling for process calls that omit usable audio buffers or per-block sample-rate context.

Use `processWithParameterView` when a processor needs block-latest reflected parameter state. `processWithParameters` remains available for code that needs direct access to the reflected set and raw value storage. Use `context.parameterBlockSegments`, `context.inputEventBlockSegments`, or `context.processBlockSegments` when sample-accurate automation, MIDI timing, or both matter, and use `context.parameterNormalizedAtOrBeforeOr` at the segment start to resolve the descriptor/default value before the first automation point.

## Example

```zig
const plug = @import("zig-vst3-plugin");

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

`examples/gain_core.zig`, `examples/bypass_core.zig`, `examples/mode_gain_core.zig`, `examples/voice_mix_core.zig`, `examples/note_gate_core.zig`, `examples/event_echo_core.zig`, `examples/event_monitor_core.zig`, and `examples/sine_synth_core.zig` are checked examples for the public `zig-vst3-plugin` API. Together they cover float, bool, enum, and int parameters, runtime reflected metadata counts, id-based parameter changes, sample-offset parameter changes, overall automation reads, block-split automation, state-aware process hooks, state restore reports, classification, and classification predicates, state debug JSON, input events, typed event payload views, note lifecycle helpers, event bus and channel predicates, event routing offset helpers, channel-aware held-note state, zero-velocity note-on release behavior, event-kind iteration, combined event and automation segment processing, output events, input-only processing, output-only processing, and audio processing through `process.ProcessContext(f32)`. `zig-vst3/src/gain_plugin.zig`, `zig-vst3/src/bypass_plugin.zig`, `zig-vst3/src/mode_gain_plugin.zig`, `zig-vst3/src/voice_mix_plugin.zig`, `zig-vst3/src/note_gate_plugin.zig`, `zig-vst3/src/event_echo_plugin.zig`, `zig-vst3/src/event_monitor_plugin.zig`, and `zig-vst3/src/sine_synth_plugin.zig` are bundled VST3 examples using the reusable shells. The shells query and retain `IHostApplication` during initialization, retain host channel-context, automation-state, and data-exchange interfaces, expose conservative defaults for host/plugin connection points, map public bus topology metadata onto audio and event buses, support standard stereo effects, input-only analyzers, and output-only stereo generators, validate process setup and sample-size dispatch, bound VST3 data-event payloads, reset stateful processors during setup, deactivation, and processing stop when a reset hook is provided, store the host component handler, and can send `beginEdit`, `performEdit`, `endEdit`, `setDirty`, `requestOpenEditor`, `startGroupEdit`, `finishGroupEdit`, context-menu, bus activation, system-time, progress, unit-selection, program-list, channel-context, automation-state, data-exchange, and unit-by-bus callbacks for plugin-side edits. Reflected `zig-vst3-plugin` unit and program-list metadata is exposed through `IUnitInfo`. `zig-vst3.vst_message` provides reusable `IMessage`, `IAttributeList`, and `IStreamAttributes` objects for future connection-point notifications and state/preset metadata. The shells also expose the optional VST3 controller and processor interfaces commonly queried by hosts, while still returning no-data/no-assignment results where the Layer 2 API does not yet model a feature. `zig build validate-examples` validates the bundled examples locally on macOS, and each bundle has Linux and Windows bundle steps.

## Open Work

- Complete the deferred Note Gate MIDI-routing host smoke test.
- Add a host smoke test that directly observes Event Echo output events.
