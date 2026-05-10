const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugincompatibility = @import("pluginterfaces/base/iplugincompatibility.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_stream = @import("vst_stream.zig");

fn validateJsonStringLiteral(comptime field: []const u8, comptime value: []const u8) void {
    for (value) |char| {
        if (char < 0x20 or char == '"' or char == '\\') @compileError(field ++ " must not contain control characters, quotes, or backslashes");
    }
}

pub fn basicMetadataJson(comptime vendor: []const u8, comptime name: []const u8, comptime version: []const u8) []const u8 {
    validateJsonStringLiteral("vendor", vendor);
    validateJsonStringLiteral("name", name);
    validateJsonStringLiteral("version", version);
    return "{\"vendor\":\"" ++ vendor ++ "\",\"name\":\"" ++ name ++ "\",\"version\":\"" ++ version ++ "\"}";
}

pub fn PluginCompatibility(comptime json: []const u8) type {
    if (json.len > std.math.maxInt(types.int32)) @compileError("PluginCompatibility JSON must fit in int32 bytes");

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

test "plugin compatibility writes JSON to stream" {
    const Compatibility = PluginCompatibility("{\"vendor\":\"zig-vst3\"}");
    const Stream = vst_stream.FixedBufferStream(256);
    var compatibility = Compatibility{};
    var stream = Stream{};

    try std.testing.expectEqual(types.kResultOk, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), stream.asStream()));
    try std.testing.expectEqualStrings("{\"vendor\":\"zig-vst3\"}", stream.data());
}

test "plugin compatibility basic metadata JSON is valid and streamable" {
    const json = basicMetadataJson("zig-vst3", "Mode Gain", "0.1.0");
    const Compatibility = PluginCompatibility(json);
    const Stream = vst_stream.FixedBufferStream(256);
    var compatibility = Compatibility{};
    var stream = Stream{};

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("zig-vst3", parsed.value.object.get("vendor").?.string);
    try std.testing.expectEqualStrings("Mode Gain", parsed.value.object.get("name").?.string);
    try std.testing.expectEqualStrings("0.1.0", parsed.value.object.get("version").?.string);

    try std.testing.expectEqual(types.kResultOk, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), stream.asStream()));
    try std.testing.expectEqualStrings(json, stream.data());
}

test "plugin compatibility rejects missing stream" {
    const Compatibility = PluginCompatibility("{}");
    var compatibility = Compatibility{};

    try std.testing.expectEqual(types.kInvalidArgument, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), null));
}

test "plugin compatibility reports short stream writes as failure" {
    const Compatibility = PluginCompatibility("{\"vendor\":\"zig-vst3\"}");
    const Stream = vst_stream.FixedBufferStream(8);
    var compatibility = Compatibility{};
    var stream = Stream{};

    try std.testing.expectEqual(types.kResultFalse, compatibility.asInterface().vtable.getCompatibilityJSON(compatibility.asInterface(), stream.asStream()));
    try std.testing.expectEqualStrings("", stream.data());
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
