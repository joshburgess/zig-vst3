# Layer 2 State

`zig-plug` state serialization stores reflected parameter values as normalized scalars. The current binary format is intentionally small:

- 8-byte magic header
- 16-bit format version
- 16-bit parameter entry count
- repeated entries of parameter id plus normalized `f64` bits

Loading ignores unknown parameter ids, which lets newer plugin versions remove parameters without breaking older saved states. Missing parameters keep their current value, so newer plugin versions can add parameters and keep descriptor defaults when loading older state. Renamed parameters can be restored through explicit old-id to new-id migrations.

The VST3 bridge reads and writes this format directly through `IBStream`, so state loading is not tied to the current parameter count. Older shorter states can load into newer plugins, and newer states with extra ids can load into older plugins. `vst_stream.zig` provides a reusable fixed-buffer `IBStream`/`ISizeableStream` object for exercising this path without per-test stream mocks.

Malformed state headers, unsupported format versions, truncated entries, and failed `IBStream` writes are rejected. Failed reads do not apply partial parameter entries.

## Current API

- `state.encodedSize(Params)`: byte count for a full parameter snapshot.
- `state.writeParameterState(Params, set, values, writer)`: writes all reflected parameter values.
- `state.readParameterState(Params, set, values, reader)`: reads entries and updates matching reflected values.
- `state.readParameterStateWithMigrations(Params, set, values, reader, migrations)`: reads entries and maps renamed parameter ids before lookup.

## Open Work

- Add an optional debug JSON format.
