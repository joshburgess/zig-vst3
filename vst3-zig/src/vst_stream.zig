const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const interface_map = @import("interface_map.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn FixedBufferStream(comptime capacity: usize) type {
    return extern struct {
        const Self = @This();

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
            return self.bytes[0..self.len];
        }

        fn ownerFromStream(ptr: *anyopaque) *Self {
            const iface: *ibstream.IBStream = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn ownerFromSizeable(ptr: *anyopaque) *Self {
            const iface: *ibstream.ISizeableStream = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("sizeable_iface", iface);
        }

        fn queryStream(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromStream(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ibstream.ibstream_iid, .ptr = &self.iface },
                .{ .iid = &ibstream.isizeable_stream_iid, .ptr = &self.sizeable_iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRefStream, &entries, requested_iid, out);
        }

        fn querySizeable(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromSizeable(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ibstream.ibstream_iid, .ptr = &self.iface },
                .{ .iid = &ibstream.isizeable_stream_iid, .ptr = &self.sizeable_iface },
            };
            return interface_map.queryWithAddRef(&self.iface, addRefStream, &entries, requested_iid, out);
        }

        fn addRefStream(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromStream(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn addRefSizeable(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromSizeable(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn releaseStream(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromStream(ptr).ref_count, "IBStream");
        }

        fn releaseSizeable(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromSizeable(ptr).ref_count, "ISizeableStream");
        }

        fn read(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_read: ?*types.int32) callconv(.C) types.tresult {
            if (byte_count < 0) return types.kInvalidArgument;
            const requested: usize = @intCast(byte_count);
            if (requested > 0 and buffer == null) return types.kInvalidArgument;
            const self = ownerFromStream(ptr);
            if (self.pos + requested > self.len) {
                if (bytes_read) |out| out.* = 0;
                return types.kResultFalse;
            }
            if (requested > 0) {
                const output = @as([*]u8, @ptrCast(buffer.?))[0..requested];
                @memcpy(output, self.bytes[self.pos..][0..requested]);
            }
            self.pos += requested;
            if (bytes_read) |out| out.* = @intCast(requested);
            return types.kResultOk;
        }

        fn write(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_written: ?*types.int32) callconv(.C) types.tresult {
            if (byte_count < 0) return types.kInvalidArgument;
            const requested: usize = @intCast(byte_count);
            if (requested > 0 and buffer == null) return types.kInvalidArgument;
            const self = ownerFromStream(ptr);
            if (self.pos + requested > capacity or self.pos + requested > self.write_limit) {
                if (bytes_written) |out| out.* = 0;
                return types.kResultFalse;
            }
            if (requested > 0) {
                const input = @as([*]const u8, @ptrCast(buffer.?))[0..requested];
                @memcpy(self.bytes[self.pos..][0..requested], input);
            }
            self.pos += requested;
            self.len = @max(self.len, self.pos);
            if (bytes_written) |out| out.* = @intCast(requested);
            return types.kResultOk;
        }

        fn seek(ptr: *anyopaque, offset: types.int64, mode: types.int32, result: ?*types.int64) callconv(.C) types.tresult {
            const self = ownerFromStream(ptr);
            const next = switch (@as(ibstream.IStreamSeekMode, @enumFromInt(mode))) {
                .kIBSeekSet => offset,
                .kIBSeekCur => @as(types.int64, @intCast(self.pos)) + offset,
                .kIBSeekEnd => @as(types.int64, @intCast(self.len)) + offset,
            };
            if (next < 0 or next > self.len) return types.kResultFalse;
            self.pos = @intCast(next);
            if (result) |out| out.* = next;
            return types.kResultOk;
        }

        fn tell(ptr: *anyopaque, pos: *types.int64) callconv(.C) types.tresult {
            pos.* = @intCast(ownerFromStream(ptr).pos);
            return types.kResultOk;
        }

        fn getStreamSize(ptr: *anyopaque, size: *types.int64) callconv(.C) types.tresult {
            size.* = @intCast(ownerFromSizeable(ptr).len);
            return types.kResultOk;
        }

        fn setStreamSize(ptr: *anyopaque, size: types.int64) callconv(.C) types.tresult {
            if (size < 0 or size > capacity) return types.kResultFalse;
            const self = ownerFromSizeable(ptr);
            const next: usize = @intCast(size);
            if (next > self.len) @memset(self.bytes[self.len..next], 0);
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

test "fixed buffer stream enforces bounds and supports query interface" {
    const Stream = FixedBufferStream(4);
    var stream = Stream{ .write_limit = 2 };
    const iface = stream.asStream();
    var input = [_]u8{ 1, 2, 3 };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.write(iface, &input, input.len, null));
    stream.write_limit = 4;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.write(iface, &input, 2, null));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.read(iface, &input, 3, null));

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ibstream.isizeable_stream_iid, &queried));
    try std.testing.expect(queried != null);
    const sizeable: *ibstream.ISizeableStream = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(types.kResultOk, sizeable.vtable.setStreamSize(sizeable, 4));
    try std.testing.expectEqual(@as(types.uint32, 1), sizeable.vtable.release(sizeable));
}
