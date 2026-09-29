# Framework Parameters

`zig-vst3-plugin` parameters expose normalized VST3 values to hosts and typed plain values to plugin code. Declare parameters as fields in `Plugin.Params`; the framework reflects that struct into metadata, storage, automation, state, and host parameter info.

## Declare Parameters

```zig
const plug = @import("zig-vst3-plugin");

pub const Params = struct {
    gain: plug.parameters.FloatParam = .{
        .id = 0,
        .name = "Gain",
        .short_name = "Gain",
        .units = "x",
        .min = 0.0,
        .max = 1.0,
        .default = 1.0,
    },
    bypass: plug.parameters.BoolParam = .{
        .id = 1,
        .name = "Bypass",
        .default = false,
        .is_bypass = true,
    },
    voices: plug.parameters.IntParam = .{
        .id = 2,
        .name = "Voices",
        .min = 1,
        .max = 4,
        .default = 1,
    },
};
```

For list parameters, use `EnumParam`:

```zig
const Mode = enum { clean, warm, bright };

pub const Params = struct {
    mode: plug.parameters.EnumParam(Mode) = .{
        .id = 3,
        .name = "Mode",
        .default = .clean,
    },
};
```

Descriptors can also set `can_automate`, `is_read_only`, and `unit_id`. `unit_id` links a parameter to `plug.units` metadata.

## Descriptor Types

- `FloatParam`: bounded `f64` values with normalized/plain conversion and text formatting/parsing.
- `IntParam`: bounded `i64` values with normalized/plain conversion and rounded denormalization.
- `BoolParam`: midpoint conversion with `On` and `Off` display text. `is_bypass` marks a dedicated bypass control.
- `EnumParam(Enum)`: declaration-order list parameter for exhaustive Zig enums, including enums with sparse explicit tag values.

Float parameters are continuous. Bool parameters report one step. Int parameters report their integer range as discrete steps. Enum parameters report one step per enum transition and set the VST3 list flag.

Use `FloatParam.initChecked`, `LogFloatParam.initChecked`, and `IntParam.initChecked` when constructing descriptors from runtime input. A linear floating-point range must have a finite positive span. A logarithmic range must be positive and have a finite ratio. The shorter `init` constructors accept only compile-time arguments and turn an invalid fixed declaration into a compiler error.

## Read Parameters In Process

Most processors should accept a `ParameterView`:

```zig
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
```

Use `process.ProcessContext` automation helpers when sample timing matters:

```zig
const latest_gain = context.parameterNormalizedAtOrBeforeOr(0, sample_offset, 1.0);
```

`ProcessAttachments.parameter_ramps` carries bounded linear ramps without expanding them into per-sample points. Each `ParameterRamp` has a signed start offset, a nonzero duration, normalized endpoints, and a sequence number for deterministic ties with point changes. Negative starts represent a ramp already in progress at the beginning of the block. `parameterNormalizedAtOrBeforeOr` interpolates active ramps and returns their endpoint after completion.

`ParameterChanges.changeCount` reports the combined point and ramp total. The older point-query APIs, including `count`, `firstChange`, `latestChange`, `forId`, and the offset iterators, continue to enumerate point changes. Use `rampCount`, `hasRamp`, and `ProcessContext.parameterRamps` to inspect native ramps. Value-resolution and segment-boundary helpers combine both forms of automation and resolve equal-offset events by sequence number.

`ParameterView` provides typed field reads with `load("field_name")`, normalized reads with `loadNormalized("field_name")`, and id/name/index reads for code that is not tied to reflected field names.

## Edit Parameters Outside Process

`ParameterEditor` binds descriptors and mutable values:

```zig
var instance = try plug.plugin.PluginInstance(Gain).init(allocator, .{});
var editor = instance.parameterEditor();

_ = editor.storeCount("gain", 0.5);
_ = editor.storeNormalizedCount("gain", 0.25);
_ = editor.resetToDefaultCount("gain");
```

Counted stores return:

- `null` for an invalid target or invalid normalized value.
- `0` when the stored value is unchanged.
- `1` when the stored value changes.

`ParameterValues`, `ParameterView`, `ParameterEditor`, and `PluginInstance` expose matching default-state checks, non-default counts, counted copy helpers, and default resets. Prefer `PluginInstance.parameterView()` and `PluginInstance.parameterEditor()` in tests and host adapters because they keep the set and value storage bound together.

## Metadata And Conversion

`ParameterSet(Params)` is the reflected descriptor table. Use it when you need metadata without an instance:

```zig
const Set = plug.parameters.ParameterSet(Params);
const set = Set.init(.{});

const gain_id = set.id(0);
const gain_name = set.name(0);
const normalized = set.normalizePlainByName("Gain", 0.5);
const display = try set.formatPlainById(0, 0.5, buffer[0..]);
```

`ParameterSet`, `ParameterView`, `ParameterEditor`, and `PluginInstance` expose parameter metadata by index, id, display name, and reflected field name:

- id, display name, short name, units, default normalized value, and default plain value.
- plain numeric range for numeric descriptors.
- enum option count, label, and normalized value for list parameters.
- bypass, automatable, read-only, unit id, step count, and list flags.
- duplicate id/name diagnostics and first descriptor-error diagnostics.

## Boundary Rules

Hosts speak normalized `0.0...1.0` values. Descriptors clamp normalized input before converting it to plain values. Mutable parameter stores reject non-finite normalized and plain values. Finite plain input is clamped to each descriptor's declared range before normalization.

Descriptor validation rejects empty display names, embedded NUL bytes in host-facing strings, duplicate ids or names, invalid ranges, non-finite defaults, and defaults outside their declared range. Empty `short_name` falls back to the display name.

Applying process-time parameter changes ignores unknown, non-automatable, and read-only parameters. The VST3 bridge rejects direct host edits for read-only parameters while still allowing state restore and plugin-owned value updates.

## Smoothing And Modulation

- `NormalizedValue`: atomic normalized storage for audio-thread reads.
- `ModulatedValue`: atomic base value plus bipolar modulation offset, clamped to normalized range.
- `normalizedFromBipolar` and `bipolarFromNormalized`: conversion helpers for `-1.0...1.0` modulation values.
- `LinearSmoother`: sample-counted ramp between normalized values.
- `ExponentialSmoother`: coefficient-based smoothing toward a normalized target.
- `LogSmoother`: sample-counted multiplicative ramp for normalized values above zero.

Use smoothers in plugin state when abrupt parameter changes would click or cause unstable DSP behavior.

## Current Limits

- Real-host automation recording coverage is still pending.
