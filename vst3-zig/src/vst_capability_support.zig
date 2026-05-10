const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstmidilearn = @import("pluginterfaces/vst/ivstmidilearn.zig");
const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");
const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");
const ivstprefetchablesupport = @import("pluginterfaces/vst/ivstprefetchablesupport.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn PlugInterfaceSupport(comptime max_iids: usize) type {
    if (max_iids == 0) @compileError("PlugInterfaceSupport requires at least one IID slot");

    return extern struct {
        const Self = @This();

        iface: ivstpluginterfacesupport.IPlugInterfaceSupport = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        count: types.uint32 = 0,
        supported: [max_iids]tuid.TUID = [_]tuid.TUID{[_]u8{0} ** 16} ** max_iids,

        pub fn asInterface(self: *Self) *ivstpluginterfacesupport.IPlugInterfaceSupport {
            return &self.iface;
        }

        pub fn addSupported(self: *Self, iid: *const tuid.TUID) types.tresult {
            if (self.count >= max_iids) return types.kResultFalse;
            self.supported[self.count] = iid.*;
            self.count += 1;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstpluginterfacesupport.iplug_interface_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugInterfaceSupport");
        }

        fn isPlugInterfaceSupported(ptr: *anyopaque, iid: *const tuid.TUID) callconv(.C) types.tresult {
            const self = owner(ptr);
            const count = @min(self.count, max_iids);
            for (self.supported[0..count]) |supported| {
                if (std.mem.eql(u8, &supported, iid)) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        const vtable = ivstpluginterfacesupport.IPlugInterfaceSupportVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .isPlugInterfaceSupported = isPlugInterfaceSupported,
        };
    };
}

pub fn PrefetchableSupport(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstprefetchablesupport.IPrefetchableSupport = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        state: ivstprefetchablesupport.PrefetchableSupport = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNeverPrefetchable),
        get_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ivstprefetchablesupport.IPrefetchableSupport {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstprefetchablesupport.IPrefetchableSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstprefetchablesupport.iprefetchable_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPrefetchableSupport");
        }

        fn getPrefetchableSupport(ptr: *anyopaque, out: *ivstprefetchablesupport.PrefetchableSupport) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.get_count += 1;
            out.* = self.state;
            if (@hasDecl(Config, "getPrefetchableSupport")) {
                const result = Config.getPrefetchableSupport(self, out);
                if (result != types.kResultOk) out.* = self.state;
                return result;
            }
            return types.kResultOk;
        }

        const vtable = ivstprefetchablesupport.IPrefetchableSupportVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getPrefetchableSupport = getPrefetchableSupport,
        };
    };
}

pub fn MidiLearn(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstmidilearn.IMidiLearn = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        input_count: types.uint32 = 0,
        last_bus: types.int32 = 0,
        last_channel: types.int16 = 0,
        last_controller: vsttypes.CtrlNumber = 0,

        pub fn asInterface(self: *Self) *ivstmidilearn.IMidiLearn {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstmidilearn.IMidiLearn = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstmidilearn.imidi_learn_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IMidiLearn");
        }

        fn onLiveMIDIControllerInput(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, controller: vsttypes.CtrlNumber) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.input_count += 1;
            self.last_bus = bus_index;
            self.last_channel = channel;
            self.last_controller = controller;
            if (@hasDecl(Config, "onLiveMIDIControllerInput")) {
                return Config.onLiveMIDIControllerInput(self, bus_index, channel, controller);
            }
            return types.kResultOk;
        }

        const vtable = ivstmidilearn.IMidiLearnVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .onLiveMIDIControllerInput = onLiveMIDIControllerInput,
        };
    };
}

pub fn PhysicalUIMapping(comptime max_maps: usize, comptime Config: type) type {
    if (max_maps == 0) @compileError("PhysicalUIMapping requires at least one map slot");

    return extern struct {
        const Self = @This();

        iface: ivstphysicalui.INoteExpressionPhysicalUIMapping = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        maps: [max_maps]ivstphysicalui.PhysicalUIMap = [_]ivstphysicalui.PhysicalUIMap{.{}} ** max_maps,
        map_count: types.uint32 = 0,
        request_count: types.uint32 = 0,
        last_bus: types.int32 = 0,
        last_channel: types.int16 = 0,

        pub fn asInterface(self: *Self) *ivstphysicalui.INoteExpressionPhysicalUIMapping {
            return &self.iface;
        }

        pub fn addMap(self: *Self, map: ivstphysicalui.PhysicalUIMap) types.tresult {
            if (self.map_count >= max_maps) return types.kResultFalse;
            self.maps[self.map_count] = map;
            self.map_count += 1;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstphysicalui.INoteExpressionPhysicalUIMapping = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstphysicalui.inote_expression_physical_ui_mapping_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "INoteExpressionPhysicalUIMapping");
        }

        fn getPhysicalUIMapping(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, out: *ivstphysicalui.PhysicalUIMapList) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.request_count += 1;
            self.last_bus = bus_index;
            self.last_channel = channel;
            out.* = .{
                .count = @min(self.map_count, max_maps),
                .map = &self.maps,
            };
            if (@hasDecl(Config, "getPhysicalUIMapping")) {
                const result = Config.getPhysicalUIMapping(self, bus_index, channel, out);
                if (result != types.kResultOk) out.* = .{};
                return result;
            }
            return if (out.count == 0) types.kResultFalse else types.kResultOk;
        }

        const vtable = ivstphysicalui.INoteExpressionPhysicalUIMappingVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getPhysicalUIMapping = getPhysicalUIMapping,
        };
    };
}

test "plug interface support stores supported IIDs" {
    const Support = PlugInterfaceSupport(1);
    var support = Support{};
    const iface = support.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.isPlugInterfaceSupported(iface, &ivstpluginterfacesupport.iplug_interface_support_iid));
    try std.testing.expectEqual(types.kResultOk, support.addSupported(&ivstpluginterfacesupport.iplug_interface_support_iid));
    try std.testing.expectEqual(types.kResultFalse, support.addSupported(&ivstprefetchablesupport.iprefetchable_support_iid));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.isPlugInterfaceSupported(iface, &ivstpluginterfacesupport.iplug_interface_support_iid));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.isPlugInterfaceSupported(iface, &ivstprefetchablesupport.iprefetchable_support_iid));

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstpluginterfacesupport.iplug_interface_support_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));
}

test "prefetchable support reports state and clears delegated failure" {
    const Support = PrefetchableSupport(struct {
        pub fn getPrefetchableSupport(_: anytype, out: *ivstprefetchablesupport.PrefetchableSupport) types.tresult {
            out.* = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsYetPrefetchable);
            return types.kResultFalse;
        }
    });
    var support = Support{ .state = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNotYetPrefetchable) };
    const iface = support.asInterface();
    var state: ivstprefetchablesupport.PrefetchableSupport = 99;

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getPrefetchableSupport(iface, &state));
    try std.testing.expectEqual(@intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNotYetPrefetchable), state);
    try std.testing.expectEqual(@as(types.uint32, 1), support.get_count);
}

test "midi learn tracks live controller input and delegates result" {
    const Learn = MidiLearn(struct {
        pub fn onLiveMIDIControllerInput(_: anytype, bus_index: types.int32, channel: types.int16, controller: vsttypes.CtrlNumber) types.tresult {
            return if (bus_index == 1 and channel == 2 and controller == 64) types.kResultOk else types.kInvalidArgument;
        }
    });
    var learn = Learn{};
    const iface = learn.asInterface();

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.onLiveMIDIControllerInput(iface, 0, 2, 64));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.onLiveMIDIControllerInput(iface, 1, 2, 64));
    try std.testing.expectEqual(@as(types.uint32, 2), learn.input_count);
    try std.testing.expectEqual(@as(types.int32, 1), learn.last_bus);
    try std.testing.expectEqual(@as(types.int16, 2), learn.last_channel);
    try std.testing.expectEqual(@as(vsttypes.CtrlNumber, 64), learn.last_controller);
}

test "physical UI mapping exposes fixed map list and clears delegated failures" {
    const Mapping = PhysicalUIMapping(1, struct {
        pub fn getPhysicalUIMapping(_: anytype, _: types.int32, _: types.int16, out: *ivstphysicalui.PhysicalUIMapList) types.tresult {
            out.* = .{ .count = 99, .map = @ptrFromInt(0x1000) };
            return types.kResultFalse;
        }
    });
    var mapping = Mapping{};
    const iface = mapping.asInterface();
    try std.testing.expectEqual(types.kResultOk, mapping.addMap(.{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), .noteExpressionTypeID = 12 }));
    try std.testing.expectEqual(types.kResultFalse, mapping.addMap(.{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIXMovement), .noteExpressionTypeID = 13 }));

    var list = ivstphysicalui.PhysicalUIMapList{};
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getPhysicalUIMapping(iface, 3, 4, &list));
    try std.testing.expectEqual(@as(types.uint32, 0), list.count);
    try std.testing.expectEqual(@as(?[*]ivstphysicalui.PhysicalUIMap, null), list.map);
    try std.testing.expectEqual(@as(types.int32, 3), mapping.last_bus);
    try std.testing.expectEqual(@as(types.int16, 4), mapping.last_channel);

    const DefaultMapping = PhysicalUIMapping(1, struct {});
    var default_mapping = DefaultMapping{};
    try std.testing.expectEqual(types.kResultOk, default_mapping.addMap(.{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), .noteExpressionTypeID = 12 }));
    try std.testing.expectEqual(types.kResultOk, default_mapping.asInterface().vtable.getPhysicalUIMapping(default_mapping.asInterface(), 0, 1, &list));
    try std.testing.expectEqual(@as(types.uint32, 1), list.count);
    try std.testing.expectEqual(@intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), list.map.?[0].physicalUITypeID);
    try std.testing.expectEqual(@as(types.uint32, 12), list.map.?[0].noteExpressionTypeID);
}
