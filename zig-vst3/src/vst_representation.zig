const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstrepresentation = @import("pluginterfaces/vst/ivstrepresentation.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_stream = @import("vst_stream.zig");

pub fn XmlRepresentation(comptime xml: []const u8) type {
    if (xml.len > std.math.maxInt(types.int32)) @compileError("XML representation must fit in int32 bytes");

    return extern struct {
        const Self = @This();

        iface: ivstrepresentation.IXmlRepresentationController = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        request_count: types.uint32 = 0,
        last_info: ivstrepresentation.RepresentationInfo = .{},

        pub fn asInterface(self: *Self) *ivstrepresentation.IXmlRepresentationController {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstrepresentation.IXmlRepresentationController = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstrepresentation.ixml_representation_controller_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IXmlRepresentationController");
        }

        fn getXmlRepresentationStream(ptr: *anyopaque, info: *ivstrepresentation.RepresentationInfo, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.request_count += 1;
            self.last_info = info.*;
            const out = stream orelse return types.kInvalidArgument;
            var bytes_written: types.int32 = 0;
            const result = out.vtable.write(out, @constCast(xml.ptr), @intCast(xml.len), &bytes_written);
            if (result != types.kResultOk) return result;
            return if (bytes_written == xml.len) types.kResultOk else types.kResultFalse;
        }

        const vtable = ivstrepresentation.IXmlRepresentationControllerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getXmlRepresentationStream = getXmlRepresentationStream,
        };
    };
}

test "xml representation writes XML and records host info" {
    const Xml = XmlRepresentation("<vstXML/>");
    const Stream = vst_stream.FixedBufferStream(64);
    var xml = Xml{};
    var stream = Stream{};
    var info = ivstrepresentation.RepresentationInfo{};
    @memcpy(info.vendor[0..4], "Host");

    try std.testing.expectEqual(types.kResultOk, xml.asInterface().vtable.getXmlRepresentationStream(xml.asInterface(), &info, stream.asStream()));
    try std.testing.expectEqualStrings("<vstXML/>", stream.data());
    try std.testing.expectEqual(@as(types.uint32, 1), xml.request_count);
    try std.testing.expectEqualStrings("Host", std.mem.sliceTo(&xml.last_info.vendor, 0));
}

test "xml representation rejects missing and short streams" {
    const Xml = XmlRepresentation("<vstXML/>");
    const Stream = vst_stream.FixedBufferStream(4);
    var xml = Xml{};
    var stream = Stream{};
    var info = ivstrepresentation.RepresentationInfo{};

    try std.testing.expectEqual(types.kInvalidArgument, xml.asInterface().vtable.getXmlRepresentationStream(xml.asInterface(), &info, null));
    try std.testing.expectEqual(types.kResultFalse, xml.asInterface().vtable.getXmlRepresentationStream(xml.asInterface(), &info, stream.asStream()));
    try std.testing.expectEqualStrings("", stream.data());
}

test "xml representation supports query interface" {
    const Xml = XmlRepresentation("<vstXML/>");
    var xml = Xml{};
    const iface = xml.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstrepresentation.ixml_representation_controller_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivstrepresentation.IXmlRepresentationController = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));
}
