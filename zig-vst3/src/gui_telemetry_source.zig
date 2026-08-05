const std = @import("std");
const funknown = @import("funknown.zig");
const types = @import("pluginterfaces/base/types.zig");
const tuid = @import("tuid.zig");
const plug_core = @import("zig-vst3-plugin-core");
const gui_graph = plug_core.gui_graph;

pub const maximum_graph_points: usize = 256;
pub const maximum_text_bytes: usize = plug_core.editor_state.maximum_text_bytes;

pub const iid = tuid.inlineUid(0x7CB6A8A1, 0x532E49D8, 0xA32BD0B4, 0x21D827F6);

pub const VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) types.uint32,
    release: *const fn (*anyopaque) callconv(.c) types.uint32,
    load: *const fn (*anyopaque, types.uint32) callconv(.c) f64,
    editorOpened: *const fn (*anyopaque) callconv(.c) void,
    editorClosed: *const fn (*anyopaque) callconv(.c) void,
    loadGraph: *const fn (*anyopaque, types.uint32, [*c]gui_graph.Point, types.uint32) callconv(.c) types.uint32,
    loadText: *const fn (*anyopaque, types.uint32, [*c]u8, types.uint32) callconv(.c) types.uint32,
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
        const bounded_output = output[0..@min(output.len, maximum_graph_points)];
        return @min(self.iface.vtable.loadGraph(self.iface, source_id, bounded_output.ptr, @intCast(bounded_output.len)), bounded_output.len);
    }

    pub fn loadText(self: RetainedSource, source_id: types.uint32, output: []u8) usize {
        const bounded_output = output[0..@min(output.len, maximum_text_bytes)];
        return @min(self.iface.vtable.loadText(self.iface, source_id, bounded_output.ptr, @intCast(bounded_output.len)), bounded_output.len);
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

test "retained telemetry source bounds graph and text capacities" {
    const MockSource = struct {
        iface: Interface,
        graph_capacity: types.uint32 = 0,
        text_capacity: types.uint32 = 0,

        const vtable = VTable{
            .queryInterface = queryInterface,
            .addRef = addRef,
            .release = release,
            .load = load,
            .editorOpened = editorOpened,
            .editorClosed = editorClosed,
            .loadGraph = loadGraph,
            .loadText = loadText,
        };

        fn owner(ptr: *anyopaque) *@This() {
            return @ptrCast(@alignCast(ptr));
        }

        fn queryInterface(_: *anyopaque, requested_iid: [*c]const tuid.TUID, out_raw: [*c]?*anyopaque) callconv(.c) types.tresult {
            const arguments = funknown.queryArguments(requested_iid, out_raw) orelse return types.kInvalidArgument;
            arguments.out.* = null;
            return types.kNoInterface;
        }

        fn addRef(_: *anyopaque) callconv(.c) types.uint32 {
            return 1;
        }

        fn release(_: *anyopaque) callconv(.c) types.uint32 {
            return 1;
        }

        fn load(_: *anyopaque, _: types.uint32) callconv(.c) f64 {
            return 0.0;
        }

        fn editorOpened(_: *anyopaque) callconv(.c) void {}

        fn editorClosed(_: *anyopaque) callconv(.c) void {}

        fn loadGraph(ptr: *anyopaque, _: types.uint32, output: [*c]gui_graph.Point, capacity: types.uint32) callconv(.c) types.uint32 {
            if (output == null) return 0;
            owner(ptr).graph_capacity = capacity;
            return std.math.maxInt(types.uint32);
        }

        fn loadText(ptr: *anyopaque, _: types.uint32, output: [*c]u8, capacity: types.uint32) callconv(.c) types.uint32 {
            if (output == null) return 0;
            owner(ptr).text_capacity = capacity;
            return std.math.maxInt(types.uint32);
        }
    };

    var mock = MockSource{ .iface = .{ .vtable = &MockSource.vtable } };
    const source = RetainedSource{ .iface = &mock.iface };
    var graph_output: [maximum_graph_points + 1]gui_graph.Point = undefined;
    var text_output: [maximum_text_bytes + 1]u8 = undefined;

    try std.testing.expectEqual(@as(types.uint32, 0), mock.iface.vtable.loadGraph(&mock.iface, 1, null, 8));
    try std.testing.expectEqual(@as(types.uint32, 0), mock.iface.vtable.loadText(&mock.iface, 1, null, 8));
    try std.testing.expectEqual(@as(types.uint32, 0), mock.graph_capacity);
    try std.testing.expectEqual(@as(types.uint32, 0), mock.text_capacity);

    try std.testing.expectEqual(maximum_graph_points, source.loadGraph(1, &graph_output));
    try std.testing.expectEqual(@as(types.uint32, maximum_graph_points), mock.graph_capacity);
    try std.testing.expectEqual(maximum_text_bytes, source.loadText(2, &text_output));
    try std.testing.expectEqual(@as(types.uint32, maximum_text_bytes), mock.text_capacity);
}
