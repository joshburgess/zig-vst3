# Layer 2 State

`zig-plug` state serialization stores reflected parameter values as normalized scalars. The current binary format is intentionally small:

- 8-byte magic header
- 16-bit format version
- 16-bit parameter entry count
- repeated entries of parameter id plus normalized `f64` bits

Loading ignores unknown parameter ids, which lets newer plugin versions remove parameters without breaking older saved states. Missing parameters keep their current value, so newer plugin versions can add parameters and keep descriptor defaults when loading older state.

## Current API

- `state.encodedSize(Params)`: byte count for a full parameter snapshot.
- `state.writeParameterState(Params, set, values, writer)`: writes all reflected parameter values.
- `state.readParameterState(Params, set, values, reader)`: reads entries and updates matching reflected values.

## Open Work

- Bridge this binary format to VST3 `IBStream` for component/controller state.
- Add an optional debug JSON format.
- Add explicit migration hooks for parameter renames.
