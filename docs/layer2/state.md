# Layer 2 State

`zig-plug` state serialization stores reflected parameter values as normalized scalars. The current binary format is intentionally small:

- 8-byte magic header
- 16-bit format version
- 16-bit parameter entry count
- repeated entries of parameter id plus normalized `f64` bits

Loading ignores unknown parameter ids, which lets newer plugin versions remove parameters without breaking older saved states. Missing parameters keep their current value, so newer plugin versions can add parameters and keep descriptor defaults when loading older state. Renamed parameters can be restored through explicit old-id to new-id migrations, including chained migrations across multiple plugin versions.

The VST3 bridge reads and writes this format directly through `IBStream`, so state loading is not tied to the current parameter count. Older shorter states can load into newer plugins, and newer states with extra ids can load into older plugins. `vst_stream.zig` provides a reusable fixed-buffer `IBStream`/`ISizeableStream` object for exercising this path without per-test stream mocks.

Malformed state headers, unsupported format versions, truncated entries, denormalized values, and failed `IBStream` writes are rejected. Failed reads do not apply partial parameter entries.

## Current API

- `state.encoded_header_size`: byte count for the binary state header.
- `state.encoded_entry_size`: byte count for one binary parameter entry.
- `state.encodedSizeForCount(count)`: byte count for a binary state with `count` entries.
- `state.encodedSize(Params)`: byte count for a full parameter snapshot.
- `state.format_version`: current binary and debug JSON state format version.
- `state.writeParameterState(Params, set, values, writer)`: writes all reflected parameter values.
- `state.writeParameterStateJson(Params, set, values, writer)`: writes the same reflected parameter values as compact debug JSON.
- `state.readParameterState(Params, set, values, reader)`: reads entries and updates matching reflected values.
- `state.readParameterStateWithMigrations(Params, set, values, reader, migrations)`: validates the migration list, reads entries, and maps renamed parameter ids before lookup.
- `state.validateParameterIdMigrations(migrations)`: rejects duplicate old ids, ambiguous target ids, and cyclic migration chains before state loading mutates parameter values.
- `state.migratedParameterId(id, migrations)`: resolves a saved parameter id through the same old-id to new-id migration list used by state loading.

Program lists can remain metadata-only, or each program can carry a normalized parameter snapshot through `plug.units.ProgramParameter`. `PluginInstance.applyProgram` and `applyProgramByName` validate the complete snapshot and then apply matching parameter ids.
