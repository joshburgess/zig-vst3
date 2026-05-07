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
- `ParameterSet(Params)`: comptime reflection over a struct of descriptors, including host-facing id/name/default lookup, string conversion, and normalized/plain conversion by reflected index.
- `ParameterValues(Params)`: atomic normalized value storage initialized from reflected descriptor defaults.

## Boundary Rules

Hosts speak normalized `0.0...1.0` values. Descriptors clamp normalized input before converting it to plain values. Plain input is clamped to each descriptor's declared range before normalization.

Parameter state that may be read by the audio thread should use `NormalizedValue`. It uses monotonic atomic loads and stores because parameter values are independent scalars; cross-parameter ordering is not part of the contract.

## Open Work

- Replace the remaining gain-specific VST3 controller shell with a reusable plugin wrapper.
- Add host smoke test notes for reflected string conversion and automation behavior.
