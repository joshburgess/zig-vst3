const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugincompatibility = @import("pluginterfaces/base/iplugincompatibility.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn PluginCompatibility(comptime json: []const u8) type {
    return extern struct {
        const Self = @This();

        iface: iplugincompatibility.IPluginCompatibility = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),

        pub fn asInterface(self: *Self) *iplugincompatibility.IPluginCompatibility {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *iplugincompatibility.IPluginCompatibility = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugincompatibility.iplugin_compatibility_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPluginCompatibility");
        }

        fn getCompatibilityJSON(_: *anyopaque, stream: ?*ibstream.IBStream) callconv(.C) types.tresult {
            const out = stream orelse return types.kInvalidArgument;
            var bytes_written: types.int32 = 0;
            const result = out.vtable.write(out, @constCast(json.ptr), @intCast(json.len), &bytes_written);
            if (result != types.kResultOk) return result;
            return if (bytes_written == json.len) types.kResultOk else types.kResultFalse;
        }

        const vtable = iplugincompatibility.IPluginCompatibilityVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getCompatibilityJSON = getCompatibilityJSON,
        };
    };
}

const TestStream = extern struct {
    iface: ibstream.IBStream = .{ .vtable = &vtable },
    data: [256]u8 = [_]u8{0} ** 256,
    len: usize = 0,

    fn asStream(self: *TestStream) *ibstream.IBStream {
        return &self.iface;
    }

    fn owner(ptr: *anyopaque) *TestStream {
        const iface: *ibstream.IBStream = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn query(_: *anyopaque, _: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
        out.* = null;
        return types.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn read(_: *anyopaque, _: ?*anyopaque, _: types.int32, bytes_read: ?*types.int32) callconv(.C) types.tresult {
        if (bytes_read) |out| out.* = 0;
        return types.kResultFalse;
    }

    fn write(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_written: ?*types.int32) callconv(.C) types.tresult {
        if (byte_count < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const size: usize = @intCast(byte_count);
        if (size > 0 and buffer == null) return types.kInvalidArgument;
        if (self.len + size > self.data.len) return types.kResultFalse;
        if (size > 0) {
            const bytes: [*]const u8 = @ptrCast(buffer.?);
            @memcpy(self.data[self.len..][0..size], bytes[0..size]);
        }
        self.len += size;
        if (bytes_written) |out| out.* = byte_count;
        return types.kResultOk;
    }

    fn seek(_: *anyopaque, _: types.int64, _: types.int32, result: ?*types.int64) callconv(.C) types.tresult {
        if (result) |out| out.* = 0;
        return types.kResultFalse;
    }

    fn tell(ptr: *anyopaque, pos: *types.int64) callconv(.C) types.tresult {
        pos.* = @intCast(owner(ptr).len);
        return types.kResultOk;
    }

    const vtable = ibstream.IBStreamVTable{
        .queryInterface = query,
        .addRef = addRef,
        .release = release,
        .read = read,
        .write = write,
        .seek = seek,
        .tell = tell,
    };
};

test "plugin compatibility writes JSON to stream" {
    const Compatibility = PluginCompatibility("{\"vendor\":\"zig-vst3\"}");
    var compatibility = Compatibility{};
    var stream = TestStream{};

    try std.testing.expectEqual(types.kResultOk, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), stream.asStream()));
    try std.testing.expectEqualStrings("{\"vendor\":\"zig-vst3\"}", stream.data[0..stream.len]);
}

test "plugin compatibility rejects missing stream" {
    const Compatibility = PluginCompatibility("{}");
    var compatibility = Compatibility{};

    try std.testing.expectEqual(types.kInvalidArgument, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), null));
}

test "plugin compatibility supports query interface" {
    const Compatibility = PluginCompatibility("{}");
    var compatibility = Compatibility{};
    const iface = compatibility.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iplugincompatibility.iplugin_compatibility_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *iplugincompatibility.IPluginCompatibility = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));
}
