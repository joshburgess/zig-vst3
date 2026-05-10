const std = @import("std");
const parameters = @import("parameters.zig");

const magic = "ZPLGSTAT";
pub const format_version: u16 = 1;
pub const encoded_header_size: usize = magic.len + @sizeOf(u16) + @sizeOf(u16);
pub const encoded_entry_size: usize = @sizeOf(u32) + @sizeOf(u64);

pub const ParameterIdMigration = struct {
    old_id: u32,
    new_id: u32,
};

pub const ReadParameterStateReport = struct {
    entry_count: usize,
    restored_count: usize,
    ignored_count: usize,
};

pub fn encodedSize(comptime Params: type) usize {
    assertEncodableParameterCount(Params);
    return encodedSizeForCount(parameters.ParameterSet(Params).count);
}

pub fn encodedSizeForCount(count: usize) usize {
    return encodedSizeForCountChecked(count) catch std.math.maxInt(usize);
}

pub fn encodedSizeForCountChecked(count: usize) !usize {
    const entries_size = try std.math.mul(usize, count, encoded_entry_size);
    return std.math.add(usize, encoded_header_size, entries_size);
}

fn assertEncodableParameterCount(comptime Params: type) void {
    if (parameters.ParameterSet(Params).count > std.math.maxInt(u16)) {
        @compileError("parameter state format supports at most 65535 parameters");
    }
}

pub fn writeParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    comptime assertEncodableParameterCount(Params);
    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, @intCast(parameters.ParameterSet(Params).count), .little);
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        try writer.writeInt(u32, set.id(index).?, .little);
        try writer.writeInt(u64, @bitCast(values.load(index).?), .little);
    }
}

pub fn writeParameterStateJson(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    try writer.writeAll("{\"version\":");
    try writer.print("{}", .{format_version});
    try writer.writeAll(",\"parameters\":[");
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        if (index != 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":");
        try writer.print("{}", .{set.id(index).?});
        try writer.writeAll(",\"name\":");
        try std.json.stringify(set.name(index).?, .{}, writer);
        try writer.writeAll(",\"normalized\":");
        try writer.print("{d}", .{values.load(index).?});
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
}

pub fn readParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
) !void {
    _ = try readParameterStateReport(Params, set, values, reader);
}

pub fn readParameterStateWithMigrations(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
    migrations: []const ParameterIdMigration,
) !void {
    _ = try readParameterStateWithMigrationsReport(Params, set, values, reader, migrations);
}

pub fn readParameterStateReport(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
) !ReadParameterStateReport {
    return readParameterStateWithMigrationsReport(Params, set, values, reader, &.{});
}

pub fn readParameterStateWithMigrationsReport(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
    migrations: []const ParameterIdMigration,
) !ReadParameterStateReport {
    try validateParameterIdMigrations(migrations);
    var header: [magic.len]u8 = undefined;
    try reader.readNoEof(&header);
    if (!std.mem.eql(u8, &header, magic)) return error.InvalidStateMagic;
    const state_version = try reader.readInt(u16, .little);
    if (state_version != format_version) return error.UnsupportedStateVersion;
    const count = try reader.readInt(u16, .little);
    var restored = parameters.ParameterValues(Params).init(set);
    restored.copyFrom(values);
    var report = ReadParameterStateReport{
        .entry_count = count,
        .restored_count = 0,
        .ignored_count = 0,
    };
    for (0..count) |_| {
        const id = try reader.readInt(u32, .little);
        const normalized: f64 = @bitCast(try reader.readInt(u64, .little));
        if (normalized < 0.0 or normalized > 1.0 or std.math.isNan(normalized)) return error.ParameterStateOutsideNormalizedRange;
        if (set.indexOfId(migratedParameterId(id, migrations))) |index| {
            _ = restored.store(index, normalized);
            report.restored_count += 1;
        } else {
            report.ignored_count += 1;
        }
    }
    values.copyFrom(&restored);
    return report;
}

pub fn validateParameterIdMigrations(migrations: []const ParameterIdMigration) !void {
    for (migrations, 0..) |left, left_index| {
        for (migrations[left_index + 1 ..]) |right| {
            if (left.old_id == right.old_id) return error.DuplicateParameterMigration;
        }
    }
    for (migrations) |migration| {
        var current = migration.old_id;
        for (0..migrations.len + 1) |_| {
            var next: ?u32 = null;
            for (migrations) |candidate| {
                if (candidate.old_id == current) {
                    next = candidate.new_id;
                    break;
                }
            }
            current = next orelse break;
        } else {
            return error.CyclicParameterMigration;
        }
    }
    for (migrations, 0..) |left, left_index| {
        const left_target = migratedParameterId(left.old_id, migrations);
        for (migrations[left_index + 1 ..]) |right| {
            if (left_target == migratedParameterId(right.old_id, migrations)) {
                return error.AmbiguousParameterMigration;
            }
        }
    }
}

pub fn migratedParameterId(id: u32, migrations: []const ParameterIdMigration) u32 {
    var current = id;
    for (0..migrations.len + 1) |_| {
        var next: ?u32 = null;
        for (migrations) |migration| {
            if (migration.old_id == current) {
                next = migration.new_id;
                break;
            }
        }
        current = next orelse return current;
    }
    return id;
}

test "parameter state round-trips normalized values" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var restored = Values.init(&set);
    var bytes: [encodedSize(Params)]u8 = undefined;

    try std.testing.expectEqual(@as(usize, 12), encoded_header_size);
    try std.testing.expectEqual(@as(usize, 12), encoded_entry_size);
    try std.testing.expectEqual(@as(usize, 36), encodedSizeForCount(2));
    try std.testing.expectEqual(@as(usize, 36), try encodedSizeForCountChecked(2));
    try std.testing.expectEqual(@as(usize, 36), encodedSize(Params));
    try std.testing.expectError(error.Overflow, encodedSizeForCountChecked(std.math.maxInt(usize)));
    try std.testing.expectEqual(std.math.maxInt(usize), encodedSizeForCount(std.math.maxInt(usize)));
    try std.testing.expect(values.storeField(&set, "gain", 0.25));
    try std.testing.expect(values.storeField(&set, "mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(Params, &set, &values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateReport(Params, &set, &restored, in_stream.reader());

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 2, .restored_count = 2, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.75), restored.loadField(&set, "mix"));
}

test "parameter state writes debug json" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [160]u8 = undefined;

    try std.testing.expect(values.storeField(&set, "gain", 0.25));
    try std.testing.expect(values.storeField(&set, "mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterStateJson(Params, &set, &values, out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25},{\"id\":1,\"name\":\"Mix\",\"normalized\":0.75}]}",
        out_stream.getWritten(),
    );
}

test "parameter state debug json escapes names" {
    const Params = struct {
        quoted: parameters.FloatParam = parameters.FloatParam.init(0, "Gain \"A\\B\"", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [128]u8 = undefined;

    try std.testing.expect(values.storeField(&set, "quoted", 0.25));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterStateJson(Params, &set, &values, out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain \\\"A\\\\B\\\"\",\"normalized\":0.25}]}",
        out_stream.getWritten(),
    );
}

test "parameter state ignores unknown parameter ids" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + 2 * (@sizeOf(u32) + @sizeOf(u64))]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 999, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.75)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateReport(Params, &set, &values, in_stream.reader());

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 2, .restored_count = 1, .ignored_count = 1 }, report);
    try std.testing.expectEqual(@as(f64, 0.75), values.loadField(&set, "gain"));
}

test "parameter state rejects malformed headers and unsupported versions" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    var bad_magic = [_]u8{0} ** (magic.len + @sizeOf(u16) + @sizeOf(u16));
    var bad_magic_stream = std.io.fixedBufferStream(&bad_magic);
    try std.testing.expectError(error.InvalidStateMagic, readParameterState(Params, &set, &values, bad_magic_stream.reader()));

    var bad_version: [magic.len + @sizeOf(u16) + @sizeOf(u16)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bad_version);
    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version + 1, .little);
    try out_stream.writer().writeInt(u16, 0, .little);
    var in_stream = std.io.fixedBufferStream(&bad_version);
    try std.testing.expectError(error.UnsupportedStateVersion, readParameterState(Params, &set, &values, in_stream.reader()));
}

test "parameter state rejects truncated entries without changing defaults" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + @sizeOf(u32)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);

    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version, .little);
    try out_stream.writer().writeInt(u16, 1, .little);
    try out_stream.writer().writeInt(u32, 0, .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.EndOfStream, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadField(&set, "gain"));
}

test "parameter state rejects later truncated entries without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + (@sizeOf(u32) + @sizeOf(u64)) + @sizeOf(u32)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 1, .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.EndOfStream, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "parameter state rejects normalized values outside range without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + 2 * (@sizeOf(u32) + @sizeOf(u64))]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 1, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 1.5)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "parameter state rejects NaN normalized values without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + @sizeOf(u32) + @sizeOf(u64)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(std.math.nan(f64)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
}

test "parameter state migrates renamed parameter ids" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(9, "Output", 0.0, 1.0, 1.0),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateWithMigrationsReport(NewParams, &new_set, &new_values, in_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
    });

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(f64, 0.25), new_values.loadField(&new_set, "output"));
}

test "parameter state migrates renamed parameter ids through chains" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 1.0),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try readParameterStateWithMigrations(NewParams, &new_set, &new_values, in_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try std.testing.expectEqual(@as(f64, 0.25), new_values.loadField(&new_set, "output"));
}

test "parameter state exposes migration resolution" {
    const migrations = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 10 },
        .{ .old_id = 9, .new_id = 11 },
    };
    const cycle = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    };
    const longer_cycle = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 3 },
        .{ .old_id = 3, .new_id = 2 },
    };
    const converging = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    };
    const chained_converging = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 8 },
        .{ .old_id = 8, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    };

    try std.testing.expectEqual(@as(u32, 11), migratedParameterId(1, &migrations));
    try std.testing.expectEqual(@as(u32, 10), migratedParameterId(2, &migrations));
    try std.testing.expectEqual(@as(u32, 3), migratedParameterId(3, &migrations));
    try std.testing.expectEqual(@as(u32, 1), migratedParameterId(1, &cycle));
    try std.testing.expectEqual(@as(u32, 1), migratedParameterId(1, &longer_cycle));
    try validateParameterIdMigrations(&migrations);
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&cycle));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&longer_cycle));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&converging));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&chained_converging));
}

test "parameter state rejects ambiguous migrations before partial updates" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(9, "Output", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(10, "Mix", 0.0, 1.0, 0.5),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    try std.testing.expect(new_values.storeField(&new_set, "output", 0.8));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var duplicate_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.DuplicateParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, duplicate_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 1, .new_id = 10 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var ambiguous_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.AmbiguousParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, ambiguous_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var cycle_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.CyclicParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, cycle_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));
}
