const std = @import("std");
const parameters = @import("parameters.zig");

const magic = "ZPLGSTAT";
const version: u16 = 1;

pub const ParameterIdMigration = struct {
    old_id: u32,
    new_id: u32,
};

pub fn encodedSize(comptime Params: type) usize {
    return magic.len + @sizeOf(u16) + @sizeOf(u16) + parameters.ParameterSet(Params).count * (@sizeOf(u32) + @sizeOf(u64));
}

pub fn writeParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    try writer.writeAll(magic);
    try writer.writeInt(u16, version, .little);
    try writer.writeInt(u16, @intCast(parameters.ParameterSet(Params).count), .little);
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        try writer.writeInt(u32, set.id(index).?, .little);
        try writer.writeInt(u64, @bitCast(values.load(index).?), .little);
    }
}

pub fn readParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
) !void {
    try readParameterStateWithMigrations(Params, set, values, reader, &.{});
}

pub fn readParameterStateWithMigrations(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
    migrations: []const ParameterIdMigration,
) !void {
    var header: [magic.len]u8 = undefined;
    try reader.readNoEof(&header);
    if (!std.mem.eql(u8, &header, magic)) return error.InvalidStateMagic;
    const state_version = try reader.readInt(u16, .little);
    if (state_version != version) return error.UnsupportedStateVersion;
    const count = try reader.readInt(u16, .little);
    for (0..count) |_| {
        const id = try reader.readInt(u32, .little);
        const normalized: f64 = @bitCast(try reader.readInt(u64, .little));
        if (set.indexOfId(migratedId(id, migrations))) |index| {
            _ = values.store(index, normalized);
        }
    }
}

fn migratedId(id: u32, migrations: []const ParameterIdMigration) u32 {
    for (migrations) |migration| {
        if (migration.old_id == id) return migration.new_id;
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

    try std.testing.expect(values.store(0, 0.25));
    try std.testing.expect(values.store(1, 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(Params, &set, &values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try readParameterState(Params, &set, &restored, in_stream.reader());

    try std.testing.expectEqual(@as(?f64, 0.25), restored.load(0));
    try std.testing.expectEqual(@as(?f64, 0.75), restored.load(1));
}

test "parameter state ignores unknown parameter ids" {
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

    try writer.writeAll(magic);
    try writer.writeInt(u16, version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 999, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try readParameterState(Params, &set, &values, in_stream.reader());

    try std.testing.expectEqual(@as(?f64, 1.0), values.load(0));
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

    try std.testing.expect(old_values.storeById(&old_set, 1, 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try readParameterStateWithMigrations(NewParams, &new_set, &new_values, in_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
    });

    try std.testing.expectEqual(@as(?f64, 0.25), new_values.loadById(&new_set, 9));
}
