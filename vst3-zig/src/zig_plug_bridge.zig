const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-plug-core");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn fillParameterInfo(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    index: types.int32,
    out: *ivsteditcontroller.ParameterInfo,
) types.tresult {
    if (index < 0 or index >= plug.parameters.ParameterSet(Params).count) {
        out.* = .{};
        return types.kInvalidArgument;
    }
    const parameter_index: usize = @intCast(index);
    out.* = .{
        .id = set.id(parameter_index).?,
        .defaultNormalizedValue = set.defaultNormalized(parameter_index).?,
        .unitId = 0,
        .flags = ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate,
    };
    copyAscii16(&out.title, set.name(parameter_index).?);
    copyAscii16(&out.shortTitle, set.name(parameter_index).?);
    return types.kResultOk;
}

pub fn getParamStringByValue(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    value: vsttypes.ParamValue,
    out: [*]vsttypes.TChar,
) types.tresult {
    const index = set.indexOfId(id) orelse return types.kInvalidArgument;
    var buffer: [64]u8 = undefined;
    const text = set.formatPlain(index, value, &buffer) catch return types.kResultFalse;
    copyAscii16Ptr(out, text);
    return types.kResultOk;
}

pub fn getParamValueByString(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    text: [*]vsttypes.TChar,
    out: *vsttypes.ParamValue,
) types.tresult {
    const index = set.indexOfId(id) orelse return types.kInvalidArgument;
    var buffer: [128]u8 = undefined;
    const parsed_text = readAscii16Ptr(text, &buffer);
    out.* = set.parsePlain(index, parsed_text) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn readParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *plug.parameters.ParameterValues(Params),
) types.tresult {
    const input = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var read: types.int32 = 0;
    const result = input.vtable.read(input, &bytes, bytes.len, &read);
    if (result != types.kResultOk or read != bytes.len) return types.kResultFalse;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.readParameterState(Params, set, values, state_stream.reader()) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn writeParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *const plug.parameters.ParameterValues(Params),
) types.tresult {
    const output = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.writeParameterState(Params, set, values, state_stream.writer()) catch return types.kResultFalse;
    var written: types.int32 = 0;
    const result = output.vtable.write(output, &bytes, bytes.len, &written);
    if (result != types.kResultOk or written != bytes.len) return types.kResultFalse;
    return types.kResultOk;
}

fn copyAscii16(dest: *vsttypes.String128, source: []const u8) void {
    @memset(dest, 0);
    const len = @min(source.len, dest.len - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

fn copyAscii16Ptr(dest: [*]vsttypes.TChar, source: []const u8) void {
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
    dest[len] = 0;
}

fn readAscii16Ptr(source: [*]vsttypes.TChar, buffer: []u8) []const u8 {
    var len: usize = 0;
    while (len < buffer.len and source[len] != 0) : (len += 1) {
        buffer[len] = @intCast(@min(source[len], 0xff));
    }
    return buffer[0..len];
}

test "zig-plug bridge round-trips parameter state through IBStream" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var restored = Values.init(&set);
    var stream = MemoryStream{};

    try std.testing.expect(values.store(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, &stream.iface, &set, &values));
    try std.testing.expectEqual(types.kResultOk, stream.iface.vtable.seek(&stream.iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(Params, &stream.iface, &set, &restored));
    try std.testing.expectEqual(@as(?f64, 0.25), restored.load(0));
}

test "zig-plug bridge fills VST3 parameter info from reflected set" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var info = ivsteditcontroller.ParameterInfo{};

    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), info.defaultNormalizedValue);
    try expectString128("Gain", &info.title);
    try std.testing.expectEqual(types.kInvalidArgument, fillParameterInfo(Params, &set, 1, &info));
}

test "zig-plug bridge formats and parses VST3 parameter strings" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var text: vsttypes.String128 = undefined;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(types.kResultOk, getParamStringByValue(Params, &set, 7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(types.kResultOk, getParamValueByString(Params, &set, 7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    try std.testing.expectEqual(types.kInvalidArgument, getParamStringByValue(Params, &set, 8, 0.5, &text));
}

fn expectString128(expected: []const u8, actual: *const vsttypes.String128) !void {
    for (expected, 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, char), actual[index]);
    }
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), actual[expected.len]);
}

const MemoryStream = extern struct {
    iface: ibstream.IBStream = .{ .vtable = &vtable },
    bytes: [256]u8 = undefined,
    len: usize = 0,
    pos: usize = 0,

    const vtable = ibstream.IBStreamVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .read = read,
        .write = write,
        .seek = seek,
        .tell = tell,
    };

    fn owner(ptr: *anyopaque) *MemoryStream {
        const iface: *ibstream.IBStream = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("tuid.zig").TUID, out: *?*anyopaque) callconv(.C) types.tresult {
        out.* = null;
        return types.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn read(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_read: ?*types.int32) callconv(.C) types.tresult {
        if (buffer == null or byte_count < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const requested: usize = @intCast(byte_count);
        if (self.pos + requested > self.len) return types.kResultFalse;
        const output = @as([*]u8, @ptrCast(buffer.?))[0..requested];
        @memcpy(output, self.bytes[self.pos..][0..requested]);
        self.pos += requested;
        if (bytes_read) |read_count| read_count.* = @intCast(requested);
        return types.kResultOk;
    }

    fn write(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_written: ?*types.int32) callconv(.C) types.tresult {
        if (buffer == null or byte_count < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const requested: usize = @intCast(byte_count);
        if (self.pos + requested > self.bytes.len) return types.kResultFalse;
        const input = @as([*]const u8, @ptrCast(buffer.?))[0..requested];
        @memcpy(self.bytes[self.pos..][0..requested], input);
        self.pos += requested;
        self.len = @max(self.len, self.pos);
        if (bytes_written) |write_count| write_count.* = @intCast(requested);
        return types.kResultOk;
    }

    fn seek(ptr: *anyopaque, pos: types.int64, mode: types.int32, result: ?*types.int64) callconv(.C) types.tresult {
        const self = owner(ptr);
        const next = switch (@as(ibstream.IStreamSeekMode, @enumFromInt(mode))) {
            .kIBSeekSet => pos,
            .kIBSeekCur => @as(types.int64, @intCast(self.pos)) + pos,
            .kIBSeekEnd => @as(types.int64, @intCast(self.len)) + pos,
        };
        if (next < 0 or next > self.len) return types.kResultFalse;
        self.pos = @intCast(next);
        if (result) |out| out.* = next;
        return types.kResultOk;
    }

    fn tell(ptr: *anyopaque, pos: *types.int64) callconv(.C) types.tresult {
        pos.* = @intCast(owner(ptr).pos);
        return types.kResultOk;
    }
};
