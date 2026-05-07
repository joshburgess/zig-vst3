const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-plug-core");

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
