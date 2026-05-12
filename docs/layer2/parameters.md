# Layer 2 Parameters

`zig-vst3-plugin` parameters expose host-normalized values at the boundary and plain typed values inside plugin code.

## Current API

- `FloatParam`: bounded `f64` values with plain range checks/clamping, normalized/plain conversion, percent display, plain formatting, and plain parsing.
- `IntParam`: bounded `i64` values with plain range checks/clamping, normalized/plain conversion, rounding on denormalization, plain formatting, and plain parsing.
- `BoolParam`: midpoint-based boolean conversion with `On`/`Off` display and permissive parsing for `on`, `off`, `true`, `false`, `1`, and `0`.
- `EnumParam(Enum)`: comptime enum descriptor with tag-name labels, option-count and index lookup helpers, and normalized declaration-order positions, including enums with sparse explicit tag values.
- `NormalizedValue`: lock-free atomic storage for normalized `f64` values, stored as raw bits.
- `ModulatedValue`: lock-free base value plus bipolar modulation offset, clamped to the normalized range, with base/modulation accessors.
- `LinearSmoother`: sample-counted ramp between normalized values, with reset, current/target, target-delta, tolerance-based target checks, active/finished, and remaining-sample helpers.
- `ExponentialSmoother`: coefficient-based smoothing toward a normalized target, with reset, current/target, target-delta, tolerance-based target checks, coefficient read, and coefficient update helpers.
- `LogSmoother`: sample-counted multiplicative ramp for normalized values that must stay above zero, with reset, current/target, target-delta, tolerance-based target checks, active/finished, and remaining-sample helpers.
- `ParameterSet(Params)`: comptime reflection over a struct of descriptors, including parameter count, host-facing id/name/short-name/units/default lookup by reflected index, id, or display name, reflected default plain values, optional plain-range lookup and predicates for numeric descriptors, optional enum option metadata lookup and predicates, id/name/field index and existence lookup, duplicate id/name value and index reporting, descriptor validation checks with first-error index/name reporting, field metadata helpers, reflected `ParameterChange` construction, string conversion, and normalized/plain conversion by reflected index, id, display name, or field.
- `ParameterValues(Params)`: atomic normalized value storage initialized from reflected descriptor defaults, with index-based, id-based, and name-based normalized/plain load/store helpers, typed field-name load/store helpers for plugin code, normalized field-name stores, counted store helpers, value copying from another storage value with changed-count reporting, default-state checks, aggregate non-default counts, bulk and single-parameter default reset, accepted-count and changed-count process-change application, a `view(set)` helper for bound typed reads, and an `editor(set)` helper for bound typed writes.
- `ParameterView(Params)`: a descriptor/value pair for parameter metadata, id/name/field index lookup, the same validation helpers as `ParameterSet`, index-based, id-based, name-based, and field-based metadata helpers including optional numeric plain ranges and enum options, reflected `ParameterChange` construction, plain/normalized conversion, id-based, name-based, and field-based plain conversion, plain text formatting/parsing, typed `load`, normalized `loadNormalized`, default-state and aggregate non-default checks, index-based reads, and id-based/name-based reads without passing the set into each call.
- `ParameterEditor(Params)`: a descriptor/value pair for parameter metadata, id/name/field index lookup, the same validation helpers as `ParameterSet`, index-based, id-based, name-based, and field-based metadata helpers including optional numeric plain ranges and enum options, reflected `ParameterChange` construction, plain/normalized conversion, id-based, name-based, and field-based plain conversion, plain text formatting/parsing, typed, normalized, index-based, id-based, and name-based reads and stores plus counted store helpers, value copying from a bound view with changed-count reporting, default-state and aggregate non-default checks, accepted-count and changed-count process-change application, and bulk or single-parameter default reset without passing the set into each call.

The checked gain example covers direct `FloatParam` descriptor utilities, direct `ParameterSet` metadata, validation, diagnostics, and conversion helpers, direct `PluginInstance` metadata, validation, and conversion wrappers, direct `ParameterValues` storage and alias helpers, instance-bound parameter handles, copying with changed-count reporting, default-state helpers, counted stores/resets, reset aliases, direct field descriptor, flag, unit, option, and range metadata, bound `ParameterView` metadata, validation, diagnostics, conversions, reads, and index aliases, bound `ParameterEditor` metadata, validation, diagnostics, conversions, edits, copy-from-view with changed-count reporting, and index aliases, and editor-level process-change application counts.
The checked mode-gain example covers direct enum descriptor utilities and enum option metadata through direct `ParameterSet`, instance, and bound view/editor helpers.
The checked bypass example covers direct bool descriptor utilities and bool flag metadata through direct instance helpers and bound view/editor helpers.
The checked voice-mix example covers direct int descriptor utilities alongside unit metadata, program metadata, unit/program validation, and counted or boolean program snapshot application.

## Boundary Rules

Hosts speak normalized `0.0...1.0` values. Descriptors clamp normalized input before converting it to plain values, and direct normalized stores reject non-finite values. Plain input is clamped to each descriptor's declared range before normalization. Counted store helpers return `null` for invalid targets or non-finite normalized values, `0` when the clamped stored value is unchanged, and `1` when the stored value changes. Counted copy helpers return the number of normalized values changed by the copy.

VST3 parameter metadata is reflected from descriptors. Float parameters are continuous, bool parameters report one step, int parameters report their integer range as discrete steps, and enum parameters report one step per enum transition with the list flag set. Descriptor validation rejects empty display names, embedded NUL bytes in host-facing strings, duplicate ids or names, invalid ranges, non-finite defaults, and defaults outside their declared range. Descriptors can set `short_name` and `units` for host parameter displays; empty `short_name` falls back to the full display name. Descriptors also expose `can_automate` and `is_read_only` so framework users can control the matching host parameter flags without dropping to the VST3 layer. Applying process-time parameter changes ignores non-automatable and read-only parameters. The VST3 bridge also rejects direct host-side edits for read-only parameters while still allowing state restore and plugin-owned value updates.

Each descriptor has a `unit_id` field. It defaults to the root unit and is reflected into host parameter metadata when the VST3 shell builds `ParameterInfo`.

Parameter state that may be read by the audio thread should use `NormalizedValue`. It uses monotonic atomic loads and stores because parameter values are independent scalars; cross-parameter ordering is not part of the contract.

`BoolParam.is_bypass` marks a boolean parameter as the plugin bypass control for hosts that recognize dedicated bypass metadata.

## Open Work

- Add real-host automation recording coverage for reflected parameter changes.
