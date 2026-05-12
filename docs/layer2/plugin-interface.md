# Layer 2 Plugin Interface

`zig-vst3-plugin` is the framework layer for writing plugins without hand-writing VST3 COM objects. A plugin is a Zig type with host metadata, a `Params` declaration, and optional lifecycle hooks. The framework reflects that type into parameter metadata, state, automation, events, bus topology, units, programs, and the reusable Layer 1 VST3 shells.

Use this layer for normal effects, instruments, analyzers, and event processors. Drop to `zig-vst3` only when you need direct SDK interface control.

## Minimal Plugin

```zig
const plug = @import("zig-vst3-plugin");

pub const Gain = struct {
    pub const name = "Simple Gain";
    pub const vendor = "Example Audio";

    pub const Params = struct {
        gain: plug.parameters.FloatParam = .{
            .id = 0,
            .name = "Gain",
            .min = 0.0,
            .max = 1.0,
            .default = 1.0,
        },
    };

    pub fn processWithParameterView(
        _: *Gain,
        context: *plug.process.ProcessContext(f32),
        params: plug.parameters.ParameterView(Params),
    ) void {
        const gain: f32 = @floatCast(params.load("gain"));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

pub const Spec = plug.plugin.PluginSpec(Gain);
pub const Instance = plug.plugin.PluginInstance(Gain);
```

`PluginSpec(Plugin)` validates and reflects the declaration. `PluginInstance(Plugin)` owns a plugin value, parameter storage, state helpers, and bound metadata handles used by tests and the VST3 shell.

## Metadata

Every plugin declares:

- `name`: host-facing plugin name.
- `vendor`: factory vendor string.
- `Params`: a struct of parameter descriptors. Use `struct {}` for plugins without parameters.

Optional declarations include:

- `url` and `email`: factory contact metadata.
- `component_class_name` and `controller_class_name`: VST3 class names.
- `component_category` and `controller_category`: VST3 class categories.
- `audio_input`, `audio_output`, `event_input`, and `event_output`: bus topology flags.
- `units`: unit and program-list metadata.

Default topology is a stereo effect with audio input, audio output, event input, and no event output. Set `audio_output = false` for an input-only analyzer, set `audio_input = false` for a generator, and set `event_output = true` for processors that emit events.

## Lifecycle Hooks

The framework calls only the hooks a plugin declares:

```zig
pub fn init(allocator: std.mem.Allocator) !Plugin
pub fn prepare(self: *Plugin, config: plug.plugin.PrepareConfig) void
pub fn process(self: *Plugin, context: *plug.process.ProcessContext(f32)) void
pub fn process64(self: *Plugin, context: *plug.process.ProcessContext(f64)) void
pub fn processWithParameterView(
    self: *Plugin,
    context: *plug.process.ProcessContext(f32),
    params: plug.parameters.ParameterView(Plugin.Params),
) void
pub fn process64WithParameterView(
    self: *Plugin,
    context: *plug.process.ProcessContext(f64),
    params: plug.parameters.ParameterView(Plugin.Params),
) void
pub fn processWithParameters(
    self: *Plugin,
    context: *plug.process.ProcessContext(f32),
    set: *const plug.parameters.ParameterSet(Plugin.Params),
    values: *const plug.parameters.ParameterValues(Plugin.Params),
) void
pub fn process64WithParameters(
    self: *Plugin,
    context: *plug.process.ProcessContext(f64),
    set: *const plug.parameters.ParameterSet(Plugin.Params),
    values: *const plug.parameters.ParameterValues(Plugin.Params),
) void
pub fn deinit(self: *Plugin) void
```

Use `processWithParameterView` for most plugins. Use the plain `process` hook when you want to read sample-accurate automation from the `ProcessContext`. Use the `process64` variants when the plugin supports 64-bit processing.

`PrepareConfig` rejects non-finite or non-positive sample rates and zero maximum block sizes before `prepare` runs. The VST3 shell applies the same checks when hosts set up processing.

## Process Context

`process.ProcessContext(Sample)` carries typed audio buffers, parameter changes, input events, optional output-event storage, and sample-rate timing helpers.

For sample-accurate automation, split the block at automation points:

```zig
pub fn process(_: *Gain, context: *plug.process.ProcessContext(f32)) void {
    var segments = context.parameterBlockSegments();
    while (segments.next()) |segment| {
        const gain: f32 = @floatCast(
            context.parameterNormalizedAtOrBeforeOr(0, segment.start_offset, 1.0),
        );
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (segment.start_offset..segment.end_offset) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
}
```

Useful context helpers include:

- `sampleRate`, `sampleDurationSeconds`, `blockDurationSeconds`, and `sampleOffsetSeconds`.
- `inputChannel`, `outputChannel`, `inputSample`, `outputSample`, and `setOutputSample`.
- `fillOutputs` and `clearOutputs`.
- `parameterBlockSegments`, `eventBlockSegments`, `inputEventBlockSegments`, and `processBlockSegments`.

`frameCount` uses the shared input/output frame count for effects, the output frame count for generators, and the input frame count for analyzers.

## Events

Events are value types. Processors can inspect typed payloads, route by offset, bus, channel, or kind, and append validated output events when an output writer is attached.

```zig
pub const EventEcho = struct {
    pub const name = "Event Echo";
    pub const vendor = "Example Audio";
    pub const event_output = true;
    pub const Params = struct {};

    pub fn process(_: *EventEcho, context: *plug.process.ProcessContext(f32)) void {
        const events = context.inputEvents();
        if (!context.canAppendOutputEventValues(events)) return;
        context.appendOutputEvents(events) catch return;
    }
};
```

Constructors include `Event.noteOn`, `Event.noteOff`, `Event.midiCc`, `Event.pitchBend`, `Event.aftertouch`, `Event.noteExpressionValue`, `Event.dataEvent`, and `Event.other`. `Event.asNoteOn`, `asNoteOff`, `asMidiCC`, and related helpers expose typed views without switching on the whole event struct.

The VST3 bridge validates event offsets, channels, pitches, normalized values, and bounded data-event payloads before exposing events to plugin code.

## Units And Programs

Units group host-facing parameters. Program lists can publish named parameter snapshots.

```zig
const voice_unit_id: i32 = 1;
const voice_program_list_id: i32 = 7;

pub const VoiceMix = struct {
    pub const name = "Voice Mix";
    pub const vendor = "Example Audio";
    pub const units = plug.units.Config{
        .units = &.{
            plug.units.Unit.root("Main"),
            .{
                .id = voice_unit_id,
                .name = "Voices",
                .parent_id = plug.units.root_unit_id,
                .program_list_id = voice_program_list_id,
            },
        },
        .program_lists = &.{.{
            .id = voice_program_list_id,
            .name = "Voice Presets",
            .programs = &.{
                .{ .name = "Single", .parameters = &.{.{ .parameter_id = 0, .normalized = 0.0 }} },
                .{ .name = "Quad", .parameters = &.{.{ .parameter_id = 0, .normalized = 1.0 }} },
            },
        }},
    };

    pub const Params = struct {
        voices: plug.parameters.IntParam = .{
            .id = 0,
            .name = "Voices",
            .min = 1,
            .max = 4,
            .default = 1,
            .unit_id = voice_unit_id,
        },
    };
};
```

`PluginInstance.unitSet()` and the direct `plug.units.UnitSet` helpers expose unit, program-list, program, parameter snapshot, and metadata lookups by index, id, name, unit, or list.

## Local Checks

Use these checks while changing framework declarations or examples:

```sh
zig build test
zig build validate-examples
```

The checked examples in `examples/*_core.zig` cover the public framework API. The bundled VST3 examples in `zig-vst3/src/*_plugin.zig` exercise the reusable VST3 shells.

## Current Limits

- The API is pre-release. Names and helper organization can still change before a public compatibility promise.
- Host smoke rows for Note Gate, Event Echo output observation, Event Monitor, and Sine Synth are still deferred.
- There is no bundled GUI toolkit. The raw layer exposes editor protocols and the framework can delegate editor creation, but plugin authors bring their own UI stack.
