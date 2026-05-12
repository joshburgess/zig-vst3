# Layer 2 State

`zig-vst3-plugin` state stores reflected parameter values as normalized scalars. The VST3 bridge reads and writes the same format through `IBStream`, so plugin state does not depend on the current parameter count.

## Format

The binary format is intentionally small:

- 8-byte magic header.
- 16-bit format version.
- 16-bit parameter entry count.
- Repeated entries of parameter id plus normalized `f64` bits.

Loading ignores unknown parameter ids. That lets newer plugin versions remove parameters without breaking older saved states. Missing parameters keep their current values, so newer versions can add parameters and keep descriptor defaults when loading older state.

Malformed headers, unsupported versions, truncated entries, duplicate restored ids, non-finite or out-of-range normalized values, and failed writes are rejected. Failed reads do not apply partial parameter entries.

## Write And Read State

Use `PluginInstance` in tests and adapters:

```zig
var instance = try plug.plugin.PluginInstance(Gain).init(allocator, .{});
var editor = instance.parameterEditor();
_ = editor.storeCount("gain", 0.5);

var out = std.Io.Writer.fixed(buffer[0..]);
try instance.writeParameterState(&out);

var restored = try plug.plugin.PluginInstance(Gain).init(allocator, .{});
var in = std.Io.Reader.fixed(out.buffered());
try restored.readParameterState(&in);
```

Use the module functions when you already have a reflected set and value storage:

```zig
const Set = plug.parameters.ParameterSet(Params);
const set = Set.init(.{});
var values = plug.parameters.ParameterValues(Params).init(&set);

try plug.state.writeParameterState(Params, &set, &values, writer);
try plug.state.readParameterState(Params, &set, &values, reader);
```

`zig-vst3.vst_stream.FixedBufferStream` is useful for exercising the `IBStream` path without writing a stream mock.

## Migrations

Renamed parameters can be restored through explicit old-id to new-id mappings:

```zig
const migrations = &.{
    .{ .old_id = 10, .new_id = 20 },
    .{ .old_id = 20, .new_id = 30 },
};

try instance.readParameterStateWithMigrations(reader, migrations);
```

Migration chains are allowed. Validation rejects identity mappings, duplicate old ids, independently converging target ids, and cycles before loading mutates parameter values. Use `state.migratedParameterId` or the instance-bound equivalent when diagnostics need to show where a saved id will land.

## Restore Reports

Use report variants when state compatibility matters:

```zig
const report = try instance.readParameterStateWithMigrationsReport(reader, migrations);

if (report.restoredAllEntries()) {
    // Every decoded entry restored to a current parameter.
}
```

Reports track decoded, restored, ignored, accounted, and unaccounted entry counts. Classification helpers distinguish empty, fully restored, fully ignored, restored-and-ignored, and partial loads. This is useful when accepting newer state files with extra ignored ids but still detecting truncated or incomplete restores.

Header helpers inspect state without decoding entries:

```zig
const header = try instance.readParameterStateHeader(reader);
const missing = instance.parameterStateHeaderMissingEntryCount(header);
const extra = instance.parameterStateHeaderExtraEntryCount(header);
```

## Debug JSON

For diagnostics and golden tests, write compact debug JSON:

```zig
try instance.writeParameterStateJson(writer);
```

The JSON uses the same format version and reflected parameter values as the binary state path. It is not the host-facing state format.

## API Reference

- `state.encoded_header_size`: binary header size.
- `state.encoded_entry_size`: one parameter entry size.
- `state.encodedSizeForCount(count)` and `state.encodedSizeForCountChecked(count)`: count-based state size helpers.
- `state.encodedSize(Params)`: full reflected parameter snapshot size.
- `state.format_version`: current binary and debug JSON state version.
- `state.ParameterStateHeader`: decoded header metadata and entry-count compatibility helpers.
- `state.ReadParameterStateReport`: decoded/restored/ignored/accounted/unaccounted counts and classification helpers.
- `state.writeParameterStateHeaderForCount(count, writer)`: header-only fixtures.
- `state.readParameterStateHeader(reader)`: header-only inspection.
- `state.writeParameterState`, `readParameterState`, and migration/report variants.
- `state.writeParameterStateJson`: debug JSON output.
- `state.validateParameterIdMigrations` and migration diagnostic helpers.

Program lists can also carry finite normalized parameter snapshots through `plug.units.ProgramParameter`. `PluginInstance.applyProgram` and related helpers validate the complete snapshot, then apply matching parameter ids.
