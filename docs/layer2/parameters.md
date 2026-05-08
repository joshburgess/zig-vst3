# Layer 2 Parameters

`zig-plug` parameters expose host-normalized values at the boundary and plain typed values inside plugin code.

## Current API

- `FloatParam`: bounded `f64` values with normalized/plain conversion, percent display, plain formatting, and plain parsing.
- `IntParam`: bounded `i64` values with normalized/plain conversion, rounding on denormalization, plain formatting, and plain parsing.
- `BoolParam`: midpoint-based boolean conversion with `On`/`Off` display and permissive parsing for `on`, `off`, `true`, `false`, `1`, and `0`.
- `EnumParam(Enum)`: comptime enum descriptor with tag-name labels and normalized tag positions.
- `NormalizedValue`: lock-free atomic storage for normalized `f64` values, stored as raw bits.
- `ModulatedValue`: lock-free base value plus bipolar modulation offset, clamped to the normalized range.
- `LinearSmoother`: sample-counted ramp between normalized values.
- `ExponentialSmoother`: coefficient-based smoothing toward a normalized target.
- `LogSmoother`: sample-counted multiplicative ramp for normalized values that must stay above zero.
- `ParameterSet(Params)`: comptime reflection over a struct of descriptors, including host-facing id/name/default lookup, id/name/field index lookup, field metadata helpers, reflected `ParameterChange` construction, string conversion, and normalized/plain conversion by reflected index.
- `ParameterValues(Params)`: atomic normalized value storage initialized from reflected descriptor defaults, with id-based normalized/plain load/store helpers, typed field-name load/store helpers for plugin code, default reset, a `view(set)` helper for bound typed reads, and an `editor(set)` helper for bound typed writes.
- `ParameterView(Params)`: a descriptor/value pair for typed `load`, normalized `loadNormalized`, index-based reads, and id-based reads without passing the set into each call.
- `ParameterEditor(Params)`: a descriptor/value pair for typed, normalized, index-based, plain-id, and normalized-id stores plus default reset without passing the set into each call.

## Boundary Rules

Hosts speak normalized `0.0...1.0` values. Descriptors clamp normalized input before converting it to plain values. Plain input is clamped to each descriptor's declared range before normalization.

VST3 parameter metadata is reflected from descriptors. Float parameters are continuous, bool parameters report one step, int parameters report their integer range as discrete steps, and enum parameters report one step per enum transition with the list flag set.

Parameter state that may be read by the audio thread should use `NormalizedValue`. It uses monotonic atomic loads and stores because parameter values are independent scalars; cross-parameter ordering is not part of the contract.

`BoolParam.is_bypass` marks a boolean parameter as the plugin bypass control for hosts that recognize dedicated bypass metadata.

## Open Work

- Add real-host automation recording coverage for reflected parameter changes.
- Add host-facing parameter grouping once `zig-plug` models units and programs.
