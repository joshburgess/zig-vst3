const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");
const tuid = @import("tuid.zig");
const gui_graph = @import("zig-vst3-plugin-core").gui_graph;

pub const iid = tuid.inlineUid(0x7CB6A8A1, 0x532E49D8, 0xA32BD0B4, 0x21D827F6);

pub const VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) types.uint32,
    release: *const fn (*anyopaque) callconv(.c) types.uint32,
    load: *const fn (*anyopaque, types.uint32) callconv(.c) f64,
    editorOpened: *const fn (*anyopaque) callconv(.c) void,
    editorClosed: *const fn (*anyopaque) callconv(.c) void,
    loadGraph: *const fn (*anyopaque, types.uint32, [*]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
    loadText: *const fn (*anyopaque, types.uint32, [*]u8, types.uint32) callconv(.c) types.uint32,
};

pub const Interface = extern struct {
    vtable: *const VTable,
};

pub const RetainedSource = struct {
    iface: *Interface,

    pub fn clone(self: RetainedSource) RetainedSource {
        _ = self.iface.vtable.addRef(self.iface);
        return self;
    }

    pub fn release(self: RetainedSource) void {
        _ = self.iface.vtable.release(self.iface);
    }

    pub fn load(self: RetainedSource, source_id: types.uint32) f64 {
        return self.iface.vtable.load(self.iface, source_id);
    }

    pub fn editorOpened(self: RetainedSource) void {
        self.iface.vtable.editorOpened(self.iface);
    }

    pub fn editorClosed(self: RetainedSource) void {
        self.iface.vtable.editorClosed(self.iface);
    }

    pub fn loadGraph(self: RetainedSource, source_id: types.uint32, output: []gui_graph.Point) usize {
        if (output.len > std.math.maxInt(types.uint32)) return 0;
        return @min(self.iface.vtable.loadGraph(self.iface, source_id, output.ptr, @intCast(output.len)), output.len);
    }

    pub fn loadText(self: RetainedSource, source_id: types.uint32, output: []u8) usize {
        if (output.len > std.math.maxInt(types.uint32)) return 0;
        return @min(self.iface.vtable.loadText(self.iface, source_id, output.ptr, @intCast(output.len)), output.len);
    }
};

pub fn query(peer: anytype) ?RetainedSource {
    var out: ?*anyopaque = null;
    if (peer.vtable.queryInterface(peer, &iid, &out) != types.kResultOk) return null;
    return .{ .iface = @ptrCast(@alignCast(out orelse return null)) };
}

test "telemetry interface has an FUnknown prefix" {
    try std.testing.expectEqual(@as(usize, 8), @typeInfo(VTable).@"struct".fields.len);
    try std.testing.expectEqual(@sizeOf(usize), @sizeOf(Interface));
}
