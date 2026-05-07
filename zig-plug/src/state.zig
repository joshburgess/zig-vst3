const std = @import("std");
const parameters = @import("parameters.zig");

const magic = "ZPLGSTAT";
const version: u16 = 1;

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
    var header: [magic.len]u8 = undefined;
    try reader.readNoEof(&header);
    if (!std.mem.eql(u8, &header, magic)) return error.InvalidStateMagic;
    const state_version = try reader.readInt(u16, .little);
    if (state_version != version) return error.UnsupportedStateVersion;
    const count = try reader.readInt(u16, .little);
    for (0..count) |_| {
        const id = try reader.readInt(u32, .little);
        const normalized: f64 = @bitCast(try reader.readInt(u64, .little));
        if (set.indexOfId(id)) |index| {
            _ = values.store(index, normalized);
        }
    }
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
