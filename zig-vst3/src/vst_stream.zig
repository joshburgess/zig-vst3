const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const interface_map = @import("interface_map.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn byteCount(len: usize) ?types.int32 {
    return std.math.cast(types.int32, len);
}

pub fn writeAll(stream: ?*ibstream.IBStream, bytes: []const u8) types.tresult {
    const out = stream orelse return types.kInvalidArgument;
    const byte_count_value = byteCount(bytes.len) orelse return types.kInvalidArgument;
    var bytes_written: types.int32 = 0;
    const result = out.vtable.write(out, @constCast(bytes.ptr), byte_count_value, &bytes_written);
    if (result != types.kResultOk) return result;
    return if (bytes_written == byte_count_value) types.kResultOk else types.kResultFalse;
}

pub fn FixedBufferStream(comptime capacity: usize) type {
    if (capacity == 0) @compileError("FixedBufferStream requires at least one byte of capacity");

    return extern struct {
        const Self = @This();
        const ByteRange = struct {
            start: usize,
            len: usize,
        };

        iface: ibstream.IBStream = .{ .vtable = &stream_vtable },
        sizeable_iface: ibstream.ISizeableStream = .{ .vtable = &sizeable_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        bytes: [capacity]u8 = [_]u8{0} ** capacity,
        len: usize = 0,
        pos: usize = 0,
        write_limit: usize = capacity,

        pub fn asStream(self: *Self) *ibstream.IBStream {
            return &self.iface;
        }

        pub fn asSizeableStream(self: *Self) *ibstream.ISizeableStream {
            return &self.sizeable_iface;
        }

        pub fn data(self: *const Self) []const u8 {
            return self.bytes[0..self.boundedLen()];
        }

        fn boundedLen(self: *const Self) usize {
            return @min(self.len, capacity);
        }

        fn boundedPos(self: *const Self) usize {
            return @min(self.pos, capacity);
        }

        fn boundedWriteLimit(self: *const Self) usize {
            return @min(self.write_limit, capacity);
        }

        fn boundedRange(position: usize, limit: usize, requested: usize) ?ByteRange {
            if (position > capacity or position > limit) return null;
            if (requested > limit - position) return null;
            return .{ .start = position, .len = requested };
        }

        fn readableSlice(self: *const Self, requested: usize) ?[]const u8 {
            const range = boundedRange(self.pos, self.boundedLen(), requested) orelse return null;
            return self.bytes[range.start..][0..range.len];
        }

        fn writableSlice(self: *Self, requested: usize) ?[]u8 {
            const range = boundedRange(self.pos, self.boundedWriteLimit(), requested) orelse return null;
            return self.bytes[range.start..][0..range.len];
        }

        fn seekTarget(base: usize, offset: types.int64) ?types.int64 {
            const start = std.math.cast(types.int64, base) orelse return null;
            const next = @addWithOverflow(start, offset);
            return if (next[1] == 0) next[0] else null;
        }

        fn failPosition(out: ?*types.int64, result: types.tresult) types.tresult {
            if (out) |value| value.* = -1;
            return result;
        }

        fn failByteCount(out: ?*types.int32, result: types.tresult) types.tresult {
            if (out) |value| value.* = 0;
            return result;
        }

        const ownerFromStream = interface_map.ownerFromField(Self, ibstream.IBStream, "iface");
        const ownerFromSizeable = interface_map.ownerFromField(Self, ibstream.ISizeableStream, "sizeable_iface");

        fn queryStream(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromStream(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ibstream.ibstream_iid, .ptr = &self.iface },
                .{ .iid = &ibstream.isizeable_stream_iid, .ptr = &self.sizeable_iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRefStream, &entries, requested_iid, out);
        }

        fn querySizeable(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromSizeable(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ibstream.ibstream_iid, .ptr = &self.iface },
                .{ .iid = &ibstream.isizeable_stream_iid, .ptr = &self.sizeable_iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRefStream, &entries, requested_iid, out);
        }

        fn addRefStream(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromStream(ptr).ref_count, "FUnknown");
        }

        fn addRefSizeable(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromSizeable(ptr).ref_count, "FUnknown");
        }

        fn releaseStream(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromStream(ptr).ref_count, "IBStream");
        }

        fn releaseSizeable(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromSizeable(ptr).ref_count, "ISizeableStream");
        }

        fn read(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_read: ?*types.int32) callconv(.c) types.tresult {
            if (byte_count < 0) return failByteCount(bytes_read, types.kInvalidArgument);
            const requested: usize = @intCast(byte_count);
            if (requested > 0 and buffer == null) return failByteCount(bytes_read, types.kInvalidArgument);
            const self = ownerFromStream(ptr);
            const source = self.readableSlice(requested) orelse return failByteCount(bytes_read, types.kResultFalse);
            if (requested > 0) {
                const target = buffer orelse return types.kInvalidArgument;
                const output = @as([*]u8, @ptrCast(target))[0..requested];
                @memcpy(output, source);
            }
            self.pos += requested;
            if (bytes_read) |out| out.* = @intCast(requested);
            return types.kResultOk;
        }

        fn write(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_written: ?*types.int32) callconv(.c) types.tresult {
            if (byte_count < 0) return failByteCount(bytes_written, types.kInvalidArgument);
            const requested: usize = @intCast(byte_count);
            if (requested > 0 and buffer == null) return failByteCount(bytes_written, types.kInvalidArgument);
            const self = ownerFromStream(ptr);
            const target = self.writableSlice(requested) orelse return failByteCount(bytes_written, types.kResultFalse);
            if (requested > 0) {
                const source = buffer orelse return types.kInvalidArgument;
                const input = @as([*]const u8, @ptrCast(source))[0..requested];
                @memcpy(target, input);
            }
            self.pos += requested;
            self.len = @max(self.len, self.pos);
            if (bytes_written) |out| out.* = @intCast(requested);
            return types.kResultOk;
        }

        fn seek(ptr: *anyopaque, offset: types.int64, mode: types.int32, result: ?*types.int64) callconv(.c) types.tresult {
            const self = ownerFromStream(ptr);
            const next = switch (mode) {
                @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet) => offset,
                @intFromEnum(ibstream.IStreamSeekMode.kIBSeekCur) => seekTarget(self.pos, offset) orelse {
                    return failPosition(result, types.kResultFalse);
                },
                @intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd) => seekTarget(self.boundedLen(), offset) orelse {
                    return failPosition(result, types.kResultFalse);
                },
                else => {
                    return failPosition(result, types.kInvalidArgument);
                },
            };
            if (next < 0 or next > self.boundedLen()) {
                return failPosition(result, types.kResultFalse);
            }
            self.pos = @intCast(next);
            if (result) |out| out.* = next;
            return types.kResultOk;
        }

        fn tell(ptr: *anyopaque, pos: *types.int64) callconv(.c) types.tresult {
            pos.* = std.math.cast(types.int64, ownerFromStream(ptr).pos) orelse {
                return failPosition(pos, types.kResultFalse);
            };
            return types.kResultOk;
        }

        fn getStreamSize(ptr: *anyopaque, size: *types.int64) callconv(.c) types.tresult {
            size.* = std.math.cast(types.int64, ownerFromSizeable(ptr).boundedLen()) orelse {
                return failPosition(size, types.kResultFalse);
            };
            return types.kResultOk;
        }

        fn setStreamSize(ptr: *anyopaque, size: types.int64) callconv(.c) types.tresult {
            if (size < 0 or size > capacity) return types.kResultFalse;
            const self = ownerFromSizeable(ptr);
            const next: usize = @intCast(size);
            const old_len = self.boundedLen();
            if (next > old_len) @memset(self.bytes[old_len..next], 0);
            self.len = next;
            self.pos = @min(self.pos, self.len);
            return types.kResultOk;
        }

        const stream_vtable = ibstream.IBStreamVTable{
            .queryInterface = queryStream,
            .addRef = addRefStream,
            .release = releaseStream,
            .read = read,
            .write = write,
            .seek = seek,
            .tell = tell,
        };

        const sizeable_vtable = ibstream.ISizeableStreamVTable{
            .queryInterface = querySizeable,
            .addRef = addRefSizeable,
            .release = releaseSizeable,
            .getStreamSize = getStreamSize,
            .setStreamSize = setStreamSize,
        };
    };
}

test "fixed buffer stream reads writes seeks and reports size" {
    const Stream = FixedBufferStream(8);
    var stream = Stream{};
    const iface = stream.asStream();
    var written: types.int32 = 0;
    var input = [_]u8{ 1, 2, 3 };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, &written));
    try std.testing.expectEqual(@as(types.int32, 3), written);

    var pos: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);

    var output = [_]u8{0} ** 3;
    var read_count: types.int32 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.read(iface, &output, output.len, &read_count));
    try std.testing.expectEqual(@as(types.int32, 3), read_count);
    try std.testing.expectEqualSlices(u8, &input, &output);

    const sizeable = stream.asSizeableStream();
    var size: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.getStreamSize(sizeable, &size));
    try std.testing.expectEqual(@as(types.int64, 3), size);
}

test "writeAll reports missing and short streams" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{};

    try std.testing.expectEqual(types.kInvalidArgument, writeAll(null, "abc"));
    try std.testing.expectEqual(types.kResultOk, writeAll(stream.asStream(), "abcd"));
    try std.testing.expectEqualStrings("abcd", stream.data());
    try std.testing.expectEqual(types.kResultFalse, writeAll(stream.asStream(), "x"));
}

test "byteCount rejects sizes that cannot fit IBStream" {
    try std.testing.expectEqual(@as(?types.int32, 0), byteCount(0));
    try std.testing.expectEqual(@as(?types.int32, std.math.maxInt(types.int32)), byteCount(std.math.maxInt(types.int32)));
    try std.testing.expectEqual(@as(?types.int32, null), byteCount(@as(usize, std.math.maxInt(types.int32)) + 1));
}

test "fixed buffer stream round-trips generated chunked IO" {
    const Stream = FixedBufferStream(64);
    var stream = Stream{};
    const iface = stream.asStream();
    const sizeable = stream.asSizeableStream();
    var prng = std.Random.DefaultPrng.init(0x1b57_4330_5a17_0001);
    const random = prng.random();
    var input: [64]u8 = undefined;
    var output: [64]u8 = [_]u8{0} ** 64;
    random.bytes(&input);

    var offset: usize = 0;
    while (offset < input.len) {
        const chunk = @min(input.len - offset, 1 + random.uintLessThan(usize, 8));
        var written: types.int32 = -1;
        try std.testing.expectEqual(
            types.kResultOk,
            iface.vtable.write(iface, &input[offset], @intCast(chunk), &written),
        );
        try std.testing.expectEqual(@as(types.int32, @intCast(chunk)), written);
        offset += chunk;
    }

    var size: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.getStreamSize(sizeable, &size));
    try std.testing.expectEqual(@as(types.int64, input.len), size);

    var pos: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);

    offset = 0;
    while (offset < output.len) {
        const chunk = @min(output.len - offset, 1 + random.uintLessThan(usize, 11));
        var read_count: types.int32 = -1;
        try std.testing.expectEqual(
            types.kResultOk,
            iface.vtable.read(iface, &output[offset], @intCast(chunk), &read_count),
        );
        try std.testing.expectEqual(@as(types.int32, @intCast(chunk)), read_count);
        offset += chunk;
    }

    try std.testing.expectEqualSlices(u8, &input, &output);
}

test "fixed buffer stream handles generated seek positions" {
    const Stream = FixedBufferStream(16);
    var stream = Stream{};
    const iface = stream.asStream();
    var input = [_]u8{0} ** 16;
    for (&input, 0..) |*byte, index| byte.* = @intCast(index);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, null));

    const set_offsets = [_]types.int64{ -1, 0, 1, 7, 15, 16, 17 };
    for (set_offsets) |offset| {
        var reported: types.int64 = -99;
        const result = iface.vtable.seek(iface, offset, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &reported);
        if (offset < 0 or offset > input.len) {
            try std.testing.expectEqual(types.kResultFalse, result);
            try std.testing.expectEqual(@as(types.int64, -1), reported);
        } else {
            try std.testing.expectEqual(types.kResultOk, result);
            try std.testing.expectEqual(offset, reported);
        }
    }

    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 8, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    const current_offsets = [_]types.int64{ -9, -8, -1, 0, 1, 8, 9 };
    for (current_offsets) |offset| {
        try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 8, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
        var reported: types.int64 = -99;
        const result = iface.vtable.seek(iface, offset, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekCur), &reported);
        const expected = 8 + offset;
        if (expected < 0 or expected > input.len) {
            try std.testing.expectEqual(types.kResultFalse, result);
            try std.testing.expectEqual(@as(types.int64, -1), reported);
        } else {
            try std.testing.expectEqual(types.kResultOk, result);
            try std.testing.expectEqual(expected, reported);
        }
    }

    const end_offsets = [_]types.int64{ -17, -16, -1, 0, 1 };
    for (end_offsets) |offset| {
        var reported: types.int64 = -99;
        const result = iface.vtable.seek(iface, offset, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd), &reported);
        const expected = @as(types.int64, input.len) + offset;
        if (expected < 0 or expected > input.len) {
            try std.testing.expectEqual(types.kResultFalse, result);
            try std.testing.expectEqual(@as(types.int64, -1), reported);
        } else {
            try std.testing.expectEqual(types.kResultOk, result);
            try std.testing.expectEqual(expected, reported);
        }
    }
}

test "fixed buffer stream rejects overflowing relative seeks" {
    const Stream = FixedBufferStream(16);
    var stream = Stream{};
    const iface = stream.asStream();
    var input = [_]u8{0} ** 8;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 4, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));

    var reported: types.int64 = 99;
    try std.testing.expectEqual(
        types.kResultFalse,
        iface.vtable.seek(iface, std.math.maxInt(types.int64), @intFromEnum(ibstream.IStreamSeekMode.kIBSeekCur), &reported),
    );
    try std.testing.expectEqual(@as(types.int64, -1), reported);

    reported = 99;
    try std.testing.expectEqual(
        types.kResultFalse,
        iface.vtable.seek(iface, std.math.maxInt(types.int64), @intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd), &reported),
    );
    try std.testing.expectEqual(@as(types.int64, -1), reported);
}

test "fixed buffer stream resizes with zero fill and clamps cursor" {
    const Stream = FixedBufferStream(8);
    var stream = Stream{};
    const iface = stream.asStream();
    const sizeable = stream.asSizeableStream();
    var input = [_]u8{ 1, 2, 3, 4 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, null));
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 6));
    try std.testing.expectEqual(@as(usize, 6), stream.len);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 0, 0 }, stream.data());

    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekEnd), null));
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 2));
    try std.testing.expectEqual(@as(usize, 2), stream.len);
    try std.testing.expectEqual(@as(usize, 2), stream.pos);

    var pos: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, 2), pos);
}

test "fixed buffer stream sizeable interface can query stream interface" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{};
    const sizeable = stream.asSizeableStream();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.queryInterface(sizeable, &ibstream.ibstream_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_stream: *ibstream.IBStream = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_stream.vtable.release(queried_stream));
}

test "fixed buffer stream query interfaces share object refcount" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{};
    const sizeable = stream.asSizeableStream();

    var queried_stream: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.queryInterface(sizeable, &ibstream.ibstream_iid, &queried_stream));
    try std.testing.expectEqual(@as(?*anyopaque, stream.asStream()), queried_stream);
    try std.testing.expectEqual(@as(types.uint32, 2), stream.ref_count.load(.seq_cst));

    var queried_unknown: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.queryInterface(sizeable, &funknown.iid, &queried_unknown));
    try std.testing.expectEqual(@as(?*anyopaque, stream.asStream()), queried_unknown);
    try std.testing.expectEqual(@as(types.uint32, 3), stream.ref_count.load(.seq_cst));

    const stream_iface: *ibstream.IBStream = @ptrCast(@alignCast(queried_stream.?));
    try std.testing.expectEqual(@as(types.uint32, 2), stream_iface.vtable.release(stream_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), stream.asStream().vtable.release(stream.asStream()));
}

test "fixed buffer stream clears unsupported query output from both interfaces" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{};
    const iface = stream.asStream();
    const sizeable = stream.asSizeableStream();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, sizeable.vtable.queryInterface(sizeable, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "fixed buffer stream enforces bounds and supports query interface" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{ .write_limit = 2 };
    const iface = stream.asStream();
    var input = [_]u8{ 1, 2, 3 };
    var count: types.int32 = 99;

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.write(iface, &input, -1, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    count = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.write(iface, null, input.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    count = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.write(iface, &input, input.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    stream.write_limit = 4;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, 2, null));
    count = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.read(iface, &input, -1, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    count = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.read(iface, null, 1, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    count = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.read(iface, &input, 3, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);

    var pos: types.int64 = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.seek(iface, 0, 99, &pos));
    try std.testing.expectEqual(@as(types.int64, -1), pos);
    pos = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.seek(iface, 100, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), &pos));
    try std.testing.expectEqual(@as(types.int64, -1), pos);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ibstream.isizeable_stream_iid, &queried));
    try std.testing.expect(queried != null);
    const sizeable: *ibstream.ISizeableStream = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 4));
    try std.testing.expectEqual(@as(types.uint32, 1), sizeable.vtable.release(sizeable));
}

test "fixed buffer stream rejects writes when position is past write limit" {
    const Stream = FixedBufferStream(8);
    var stream = Stream{ .write_limit = 4 };
    const iface = stream.asStream();
    const sizeable = stream.asSizeableStream();
    var input = [_]u8{ 1, 2 };
    var count: types.int32 = 99;

    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 8));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 6, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.write(iface, &input, input.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
}

test "fixed buffer stream zero-byte IO permits null buffers" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{};
    const iface = stream.asStream();
    var count: types.int32 = -1;
    var pos: types.int64 = -1;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, null, 0, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);

    count = -1;
    pos = -1;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.read(iface, null, 0, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);
}

test "fixed buffer stream failed IO preserves cursor" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{ .write_limit = 2 };
    const iface = stream.asStream();
    var input = [_]u8{ 1, 2, 3 };
    var pos: types.int64 = -1;
    var count: types.int32 = -1;

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.write(iface, &input, input.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);

    stream.write_limit = 4;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, 2, null));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.seek(iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));

    pos = -1;
    count = -1;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.read(iface, &input, input.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, 0), pos);
}

test "fixed buffer stream generated IO bounds match visible buffer limits" {
    const Stream = FixedBufferStream(4);
    const positions = [_]usize{ 0, 1, 3, 4, 5 };
    const lengths = [_]usize{ 0, 1, 3, 4, 5 };
    const requests = [_]types.int32{ 0, 1, 2, 4 };
    var input = [_]u8{ 9, 8, 7, 6 };

    for (positions) |position| {
        for (lengths) |length| {
            for (requests) |request| {
                var stream = Stream{
                    .bytes = [_]u8{ 1, 2, 3, 4 },
                    .len = length,
                    .pos = position,
                };
                const iface = stream.asStream();
                var output = [_]u8{0} ** 4;
                var count: types.int32 = -1;
                const visible_len = @min(length, stream.bytes.len);
                const readable = position <= visible_len and @as(usize, @intCast(request)) <= visible_len - position;
                const expected = if (readable) types.kResultOk else types.kResultFalse;

                try std.testing.expectEqual(expected, iface.vtable.read(iface, &output, request, &count));
                try std.testing.expectEqual(if (readable) request else 0, count);
                try std.testing.expectEqual(if (readable) position + @as(usize, @intCast(request)) else position, stream.pos);
            }
        }
    }

    for (positions) |position| {
        for (lengths) |write_limit| {
            for (requests) |request| {
                var stream = Stream{
                    .pos = position,
                    .write_limit = write_limit,
                };
                const iface = stream.asStream();
                var count: types.int32 = -1;
                const visible_limit = @min(write_limit, stream.bytes.len);
                const writable = position <= visible_limit and @as(usize, @intCast(request)) <= visible_limit - position;
                const expected = if (writable) types.kResultOk else types.kResultFalse;

                try std.testing.expectEqual(expected, iface.vtable.write(iface, &input, request, &count));
                try std.testing.expectEqual(if (writable) request else 0, count);
                try std.testing.expectEqual(if (writable) position + @as(usize, @intCast(request)) else position, stream.pos);
            }
        }
    }
}

test "fixed buffer stream clamps corrupted cursors and sizes" {
    const Stream = FixedBufferStream(8);
    var stream = Stream{};
    const iface = stream.asStream();
    const sizeable = stream.asSizeableStream();
    var input = [_]u8{ 1, 2, 3, 4 };

    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, input.len, null));

    stream.len = 99;
    stream.pos = 7;
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4, 0, 0, 0, 0 }, stream.data());

    var output = [_]u8{0} ** 2;
    var count: types.int32 = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.read(iface, &output, output.len, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);

    var size: types.int64 = -1;
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.getStreamSize(sizeable, &size));
    try std.testing.expectEqual(@as(types.int64, 8), size);

    stream.pos = std.math.maxInt(usize);
    var pos: types.int64 = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.tell(iface, &pos));
    try std.testing.expectEqual(@as(types.int64, -1), pos);

    stream.pos = 2;
    stream.write_limit = 1;
    count = 99;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.write(iface, &input, 1, &count));
    try std.testing.expectEqual(@as(types.int32, 0), count);
}

test "fixed buffer stream zero fills after corrupted oversized length" {
    const Stream = FixedBufferStream(8);
    var stream = Stream{};
    const sizeable = stream.asSizeableStream();
    stream.bytes = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    stream.len = std.math.maxInt(usize);
    stream.pos = 6;

    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 4));
    try std.testing.expectEqual(@as(usize, 4), stream.len);
    try std.testing.expectEqual(@as(usize, 4), stream.pos);

    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 8));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 0, 0, 0, 0 }, stream.data());
}
