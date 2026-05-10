# Layer 2 State

`zig-plug` state serialization stores reflected parameter values as normalized scalars. The current binary format is intentionally small:

- 8-byte magic header
- 16-bit format version
- 16-bit parameter entry count
- repeated entries of parameter id plus normalized `f64` bits

Loading ignores unknown parameter ids, which lets newer plugin versions remove parameters without breaking older saved states. Missing parameters keep their current value, so newer plugin versions can add parameters and keep descriptor defaults when loading older state. Renamed parameters can be restored through explicit old-id to new-id migrations, including chained migrations across multiple plugin versions.

The VST3 bridge reads and writes this format directly through `IBStream`, so state loading is not tied to the current parameter count. Older shorter states can load into newer plugins, and newer states with extra ids can load into older plugins. `vst_stream.zig` provides a reusable fixed-buffer `IBStream`/`ISizeableStream` object for exercising this path without per-test stream mocks.

Malformed state headers, unsupported format versions, truncated entries, duplicate restored parameter entries, non-finite or out-of-range normalized values, and failed `IBStream` writes are rejected. Failed reads do not apply partial parameter entries.

## Current API

- `state.encoded_header_size`: byte count for the binary state header.
- `state.encoded_entry_size`: byte count for one binary parameter entry.
- `state.encodedSizeForCount(count)`: byte count for a binary state with `count` entries, saturating at `usize` max on overflow.
- `state.encodedSizeForCountChecked(count)`: checked byte count for a binary state with `count` entries.
- `state.encodedSize(Params)`: byte count for a full parameter snapshot.
- `state.format_version`: current binary and debug JSON state format version.
- `state.ParameterStateHeader`: decoded binary header metadata with version, entry count, entry-count presence and emptiness checks, current-version checks, and encoded-size helpers.
- `state.ReadParameterStateReport`: counts decoded, restored, and ignored entries from a state load, with decoded/restored/ignored presence and absence helpers plus `restoredPartialEntries`, `restoredAllEntries`, and `ignoredAllEntries` helpers for classifying host state loads.
- `state.writeParameterStateHeaderForCount(count, writer)`: writes the binary header for tools that need a header-only state fixture.
- `state.readParameterStateHeader(reader)`: validates the magic header and returns version and entry count without decoding parameter entries.
- `state.writeParameterState(Params, set, values, writer)`: writes all reflected parameter values.
- `state.writeParameterStateJson(Params, set, values, writer)`: writes the same reflected parameter values as compact debug JSON.
- `state.readParameterState(Params, set, values, reader)`: reads entries and updates matching reflected values.
- `state.readParameterStateWithMigrations(Params, set, values, reader, migrations)`: validates the migration list, reads entries, and maps renamed parameter ids before lookup.
- `state.readParameterStateReport(Params, set, values, reader)`: reads entries and returns a report with restored and ignored counts.
- `state.readParameterStateWithMigrationsReport(Params, set, values, reader, migrations)`: reads migrated entries and returns the same report.
- `state.validateParameterIdMigrations(migrations)`: rejects identity mappings, duplicate old ids, ambiguous target ids, and cyclic migration chains before state loading mutates parameter values.
- `state.migratedParameterId(id, migrations)`: resolves a saved parameter id through the same old-id to new-id migration list used by state loading.

Program lists can remain metadata-only, or each program can carry a finite normalized parameter snapshot through `plug.units.ProgramParameter`. `PluginInstance.applyProgram`, `applyProgramByName`, and the unit-based program application helpers validate the complete snapshot and then apply matching parameter ids.
