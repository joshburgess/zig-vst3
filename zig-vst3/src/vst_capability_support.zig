const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivstmidilearn = @import("pluginterfaces/vst/ivstmidilearn.zig");
const ivstmidimapping2 = @import("pluginterfaces/vst/ivstmidimapping2.zig");
const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");
const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");
const ivstprefetchablesupport = @import("pluginterfaces/vst/ivstprefetchablesupport.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub fn PlugInterfaceSupport(comptime max_iids: usize) type {
    if (max_iids == 0) @compileError("PlugInterfaceSupport requires at least one IID slot");
    vst_index.requireUint32Capacity(max_iids, "PlugInterfaceSupport capacity");

    return extern struct {
        const Self = @This();

        iface: ivstpluginterfacesupport.IPlugInterfaceSupport = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        count: types.uint32 = 0,
        supported: [max_iids]tuid.TUID = [_]tuid.TUID{tuid.zero} ** max_iids,

        pub fn asInterface(self: *Self) *ivstpluginterfacesupport.IPlugInterfaceSupport {
            return &self.iface;
        }

        fn safeCount(self: *const Self) usize {
            return vst_index.clampedCountU32(self.count, max_iids);
        }

        fn appendSupportedIndex(self: *Self, iid: *const tuid.TUID) ?usize {
            const index = vst_index.appendIndexU32(self.count, max_iids) orelse return null;
            self.supported[index] = iid.*;
            self.count +|= 1;
            return index;
        }

        pub fn addSupported(self: *Self, iid: *const tuid.TUID) types.tresult {
            _ = self.appendSupportedIndex(iid) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstpluginterfacesupport.iplug_interface_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugInterfaceSupport");
        }

        fn isPlugInterfaceSupported(ptr: *anyopaque, iid: *const tuid.TUID) callconv(.c) types.tresult {
            const self = owner(ptr);
            for (self.supported[0..self.safeCount()]) |supported| {
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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstprefetchablesupport.iprefetchable_support_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPrefetchableSupport");
        }

        fn failPrefetchableSupport(out: *ivstprefetchablesupport.PrefetchableSupport, fallback: ivstprefetchablesupport.PrefetchableSupport, result: types.tresult) types.tresult {
            out.* = fallback;
            return result;
        }

        fn getPrefetchableSupport(ptr: *anyopaque, out: *ivstprefetchablesupport.PrefetchableSupport) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.get_count +|= 1;
            out.* = self.state;
            if (@hasDecl(Config, "getPrefetchableSupport")) {
                const result = Config.getPrefetchableSupport(self, out);
                if (result != types.kResultOk) return failPrefetchableSupport(out, self.state, result);
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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstmidilearn.imidi_learn_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IMidiLearn");
        }

        fn onLiveMIDIControllerInput(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, controller: vsttypes.CtrlNumber) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.input_count +|= 1;
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

pub fn Midi2Mapping(comptime max_midi2: usize, comptime max_midi1: usize, comptime Config: type) type {
    if (max_midi2 == 0 and max_midi1 == 0) @compileError("Midi2Mapping requires at least one assignment slot");
    vst_index.requireUint32Capacity(max_midi2, "Midi2Mapping MIDI 2 capacity");
    vst_index.requireUint32Capacity(max_midi1, "Midi2Mapping MIDI 1 capacity");

    return extern struct {
        const Self = @This();

        iface: ivstmidimapping2.IMidiMapping2 = .{ .vtable = &mapping_vtable },
        learn_iface: ivstmidimapping2.IMidiLearn2 = .{ .vtable = &learn_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        midi2_count: types.uint32 = 0,
        midi1_count: types.uint32 = 0,
        midi2: [max_midi2]ivstmidimapping2.Midi2ControllerParamIDAssignment = [_]ivstmidimapping2.Midi2ControllerParamIDAssignment{.{}} ** max_midi2,
        midi1: [max_midi1]ivstmidimapping2.Midi1ControllerParamIDAssignment = [_]ivstmidimapping2.Midi1ControllerParamIDAssignment{.{}} ** max_midi1,
        midi2_input_count: types.uint32 = 0,
        midi1_input_count: types.uint32 = 0,
        last_bus: ivstmidimapping2.BusIndex = 0,
        last_channel: ivstmidimapping2.MidiChannel = 0,
        last_midi2_controller: ivstmidimapping2.Midi2Controller = .{},
        last_midi1_controller: vsttypes.CtrlNumber = 0,

        pub fn asMapping(self: *Self) *ivstmidimapping2.IMidiMapping2 {
            return &self.iface;
        }

        pub fn asLearn(self: *Self) *ivstmidimapping2.IMidiLearn2 {
            return &self.learn_iface;
        }

        fn safeMidi2Count(self: *const Self) usize {
            return vst_index.clampedCountU32(self.midi2_count, max_midi2);
        }

        fn safeMidi1Count(self: *const Self) usize {
            return vst_index.clampedCountU32(self.midi1_count, max_midi1);
        }

        fn appendMidi2Index(self: *Self, assignment: ivstmidimapping2.Midi2ControllerParamIDAssignment) ?usize {
            const index = vst_index.appendIndexU32(self.midi2_count, max_midi2) orelse return null;
            self.midi2[index] = assignment;
            self.midi2_count +|= 1;
            return index;
        }

        pub fn addMidi2(self: *Self, assignment: ivstmidimapping2.Midi2ControllerParamIDAssignment) types.tresult {
            _ = self.appendMidi2Index(assignment) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn appendMidi1Index(self: *Self, assignment: ivstmidimapping2.Midi1ControllerParamIDAssignment) ?usize {
            const index = vst_index.appendIndexU32(self.midi1_count, max_midi1) orelse return null;
            self.midi1[index] = assignment;
            self.midi1_count +|= 1;
            return index;
        }

        pub fn addMidi1(self: *Self, assignment: ivstmidimapping2.Midi1ControllerParamIDAssignment) types.tresult {
            _ = self.appendMidi1Index(assignment) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn ownerFromMapping(ptr: *anyopaque) *Self {
            const iface: *ivstmidimapping2.IMidiMapping2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn ownerFromLearn(ptr: *anyopaque) *Self {
            const iface: *ivstmidimapping2.IMidiLearn2 = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("learn_iface", iface);
        }

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.iface },
                .{ .iid = &ivstmidimapping2.imidi_mapping2_iid, .ptr = &self.iface },
                .{ .iid = &ivstmidimapping2.imidi_learn2_iid, .ptr = &self.learn_iface },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, mappingAddRef, &entries, requested_iid, out);
        }

        fn mappingQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return ownerFromMapping(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn learnQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromLearn(ptr);
            return self.queryCanonical(&self.iface, requested_iid, out);
        }

        fn mappingAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromMapping(ptr).ref_count, "FUnknown");
        }

        fn learnAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromLearn(ptr).ref_count, "FUnknown");
        }

        fn mappingRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromMapping(ptr).ref_count, "IMidiMapping2");
        }

        fn learnRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromLearn(ptr).ref_count, "IMidiLearn2");
        }

        fn acceptsDirection(direction: vsttypes.BusDirection) bool {
            if (@hasDecl(Config, "direction")) return direction == Config.direction;
            return direction == @intFromEnum(ivstcomponent.BusDirections.kInput);
        }

        fn getNumMidi2ControllerAssignments(ptr: *anyopaque, direction: vsttypes.BusDirection) callconv(.c) types.uint32 {
            const self = ownerFromMapping(ptr);
            return if (acceptsDirection(direction)) @intCast(self.safeMidi2Count()) else 0;
        }

        fn getMidi2ControllerAssignments(ptr: *anyopaque, direction: vsttypes.BusDirection, list: *const ivstmidimapping2.Midi2ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            const self = ownerFromMapping(ptr);
            if (!acceptsDirection(direction)) return types.kResultFalse;
            const count = self.safeMidi2Count();
            if (count == 0) return types.kResultFalse;
            const assignments = list.map orelse return types.kInvalidArgument;
            if (list.count < count) return types.kResultFalse;
            @memcpy(assignments[0..count], self.midi2[0..count]);
            return types.kResultOk;
        }

        fn getNumMidi1ControllerAssignments(ptr: *anyopaque, direction: vsttypes.BusDirection) callconv(.c) types.uint32 {
            const self = ownerFromMapping(ptr);
            return if (acceptsDirection(direction)) @intCast(self.safeMidi1Count()) else 0;
        }

        fn getMidi1ControllerAssignments(ptr: *anyopaque, direction: vsttypes.BusDirection, list: *const ivstmidimapping2.Midi1ControllerParamIDAssignmentList) callconv(.c) types.tresult {
            const self = ownerFromMapping(ptr);
            if (!acceptsDirection(direction)) return types.kResultFalse;
            const count = self.safeMidi1Count();
            if (count == 0) return types.kResultFalse;
            const assignments = list.map orelse return types.kInvalidArgument;
            if (list.count < count) return types.kResultFalse;
            @memcpy(assignments[0..count], self.midi1[0..count]);
            return types.kResultOk;
        }

        fn onLiveMidi2ControllerInput(ptr: *anyopaque, bus_index: ivstmidimapping2.BusIndex, channel: ivstmidimapping2.MidiChannel, controller: ivstmidimapping2.Midi2Controller) callconv(.c) types.tresult {
            const self = ownerFromLearn(ptr);
            self.midi2_input_count +|= 1;
            self.last_bus = bus_index;
            self.last_channel = channel;
            self.last_midi2_controller = controller;
            if (@hasDecl(Config, "onLiveMidi2ControllerInput")) return Config.onLiveMidi2ControllerInput(self, bus_index, channel, controller);
            return types.kResultOk;
        }

        fn onLiveMidi1ControllerInput(ptr: *anyopaque, bus_index: ivstmidimapping2.BusIndex, channel: ivstmidimapping2.MidiChannel, controller: vsttypes.CtrlNumber) callconv(.c) types.tresult {
            const self = ownerFromLearn(ptr);
            self.midi1_input_count +|= 1;
            self.last_bus = bus_index;
            self.last_channel = channel;
            self.last_midi1_controller = controller;
            if (@hasDecl(Config, "onLiveMidi1ControllerInput")) return Config.onLiveMidi1ControllerInput(self, bus_index, channel, controller);
            return types.kResultOk;
        }

        const mapping_vtable = ivstmidimapping2.IMidiMapping2VTable{
            .queryInterface = mappingQuery,
            .addRef = mappingAddRef,
            .release = mappingRelease,
            .getNumMidi2ControllerAssignments = getNumMidi2ControllerAssignments,
            .getMidi2ControllerAssignments = getMidi2ControllerAssignments,
            .getNumMidi1ControllerAssignments = getNumMidi1ControllerAssignments,
            .getMidi1ControllerAssignments = getMidi1ControllerAssignments,
        };

        const learn_vtable = ivstmidimapping2.IMidiLearn2VTable{
            .queryInterface = learnQuery,
            .addRef = learnAddRef,
            .release = learnRelease,
            .onLiveMidi2ControllerInput = onLiveMidi2ControllerInput,
            .onLiveMidi1ControllerInput = onLiveMidi1ControllerInput,
        };
    };
}

pub fn PhysicalUIMapping(comptime max_maps: usize, comptime Config: type) type {
    if (max_maps == 0) @compileError("PhysicalUIMapping requires at least one map slot");
    vst_index.requireUint32Capacity(max_maps, "PhysicalUIMapping capacity");

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

        fn safeMapCount(self: *const Self) usize {
            return vst_index.clampedCountU32(self.map_count, max_maps);
        }

        fn appendMapIndex(self: *Self, map: ivstphysicalui.PhysicalUIMap) ?usize {
            const index = vst_index.appendIndexU32(self.map_count, max_maps) orelse return null;
            self.maps[index] = map;
            self.map_count +|= 1;
            return index;
        }

        pub fn addMap(self: *Self, map: ivstphysicalui.PhysicalUIMap) types.tresult {
            _ = self.appendMapIndex(map) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstphysicalui.INoteExpressionPhysicalUIMapping = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstphysicalui.inote_expression_physical_ui_mapping_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "INoteExpressionPhysicalUIMapping");
        }

        fn failPhysicalUIMapping(out: *ivstphysicalui.PhysicalUIMapList, result: types.tresult) types.tresult {
            out.* = .{};
            return result;
        }

        fn getPhysicalUIMapping(ptr: *anyopaque, bus_index: types.int32, channel: types.int16, out: *ivstphysicalui.PhysicalUIMapList) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.request_count +|= 1;
            self.last_bus = bus_index;
            self.last_channel = channel;
            out.* = .{
                .count = @intCast(self.safeMapCount()),
                .map = &self.maps,
            };
            if (@hasDecl(Config, "getPhysicalUIMapping")) {
                const result = Config.getPhysicalUIMapping(self, bus_index, channel, out);
                if (result != types.kResultOk) return failPhysicalUIMapping(out, result);
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

test "plug interface support clamps inflated counts" {
    const Support = PlugInterfaceSupport(1);
    var support = Support{};
    const iface = support.asInterface();
    support.supported[0] = ivstprefetchablesupport.iprefetchable_support_iid;
    support.count = 99;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.isPlugInterfaceSupported(iface, &ivstprefetchablesupport.iprefetchable_support_iid));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.isPlugInterfaceSupported(iface, &ivstpluginterfacesupport.iplug_interface_support_iid));
    try std.testing.expectEqual(types.kResultFalse, support.addSupported(&ivstpluginterfacesupport.iplug_interface_support_iid));
}

test "prefetchable support reports default state and supports query interface" {
    const Support = PrefetchableSupport(struct {});
    var support = Support{ .state = @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsYetPrefetchable) };
    const iface = support.asInterface();
    var state: ivstprefetchablesupport.PrefetchableSupport = 0;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.getPrefetchableSupport(iface, &state));
    try std.testing.expectEqual(@as(ivstprefetchablesupport.PrefetchableSupport, @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsYetPrefetchable)), state);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstprefetchablesupport.iprefetchable_support_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivstprefetchablesupport.IPrefetchableSupport = @ptrCast(@alignCast(queried.?));
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
    try std.testing.expectEqual(@as(ivstprefetchablesupport.PrefetchableSupport, @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNotYetPrefetchable)), state);
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

test "midi 2 mapping copies midi 1 and midi 2 assignment lists" {
    const Mapping = Midi2Mapping(1, 1, struct {});
    var mapping = Mapping{};
    const iface = mapping.asMapping();

    try std.testing.expectEqual(types.kResultOk, mapping.addMidi2(.{
        .pId = 100,
        .busIndex = 1,
        .channel = 2,
        .controller = .{ .bank_registered = 3, .index_reserved = 4 },
    }));
    try std.testing.expectEqual(types.kResultOk, mapping.addMidi1(.{
        .pId = 200,
        .busIndex = 1,
        .channel = 2,
        .controller = 64,
    }));
    try std.testing.expectEqual(types.kResultFalse, mapping.addMidi2(.{ .pId = 101 }));
    try std.testing.expectEqual(types.kResultFalse, mapping.addMidi1(.{ .pId = 201 }));

    try std.testing.expectEqual(@as(types.uint32, 1), iface.vtable.getNumMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.uint32, 0), iface.vtable.getNumMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kOutput)));

    var midi2_out = [_]ivstmidimapping2.Midi2ControllerParamIDAssignment{.{}} ** 1;
    const midi2_list = ivstmidimapping2.Midi2ControllerParamIDAssignmentList{ .count = midi2_out.len, .map = &midi2_out };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &midi2_list));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 100), midi2_out[0].pId);
    try std.testing.expectEqual(@as(ivstmidimapping2.MidiChannel, 2), midi2_out[0].channel);
    try std.testing.expectEqual(@as(types.uint8, 3), midi2_out[0].controller.bank_registered);

    var midi1_out = [_]ivstmidimapping2.Midi1ControllerParamIDAssignment{.{}} ** 1;
    const midi1_list = ivstmidimapping2.Midi1ControllerParamIDAssignmentList{ .count = midi1_out.len, .map = &midi1_out };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getMidi1ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &midi1_list));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 200), midi1_out[0].pId);
    try std.testing.expectEqual(@as(vsttypes.CtrlNumber, 64), midi1_out[0].controller);
}

test "midi 2 mapping reports invalid assignment outputs deterministically" {
    const Mapping = Midi2Mapping(1, 1, struct {});
    var mapping = Mapping{};
    const iface = mapping.asMapping();
    try std.testing.expectEqual(types.kResultOk, mapping.addMidi2(.{ .pId = 100 }));
    try std.testing.expectEqual(types.kResultOk, mapping.addMidi1(.{ .pId = 200 }));

    var empty_midi2 = [_]ivstmidimapping2.Midi2ControllerParamIDAssignment{.{}} ** 0;
    const short_midi2 = ivstmidimapping2.Midi2ControllerParamIDAssignmentList{ .count = 0, .map = &empty_midi2 };
    const null_midi2 = ivstmidimapping2.Midi2ControllerParamIDAssignmentList{ .count = 1, .map = null };
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &short_midi2));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &null_midi2));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kOutput), &null_midi2));

    var empty_midi1 = [_]ivstmidimapping2.Midi1ControllerParamIDAssignment{.{}} ** 0;
    const short_midi1 = ivstmidimapping2.Midi1ControllerParamIDAssignmentList{ .count = 0, .map = &empty_midi1 };
    const null_midi1 = ivstmidimapping2.Midi1ControllerParamIDAssignmentList{ .count = 1, .map = null };
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getMidi1ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &short_midi1));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getMidi1ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &null_midi1));
}

test "midi 2 mapping clamps inflated assignment counts" {
    const Mapping = Midi2Mapping(1, 1, struct {});
    var mapping = Mapping{};
    const iface = mapping.asMapping();
    mapping.midi2[0] = .{ .pId = 100 };
    mapping.midi1[0] = .{ .pId = 200 };
    mapping.midi2_count = 99;
    mapping.midi1_count = 99;

    try std.testing.expectEqual(@as(types.uint32, 1), iface.vtable.getNumMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.uint32, 1), iface.vtable.getNumMidi1ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(types.kResultFalse, mapping.addMidi2(.{ .pId = 101 }));
    try std.testing.expectEqual(types.kResultFalse, mapping.addMidi1(.{ .pId = 201 }));

    var midi2_out = [_]ivstmidimapping2.Midi2ControllerParamIDAssignment{.{}} ** 1;
    const midi2_list = ivstmidimapping2.Midi2ControllerParamIDAssignmentList{ .count = midi2_out.len, .map = &midi2_out };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &midi2_list));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 100), midi2_out[0].pId);

    var midi1_out = [_]ivstmidimapping2.Midi1ControllerParamIDAssignment{.{}} ** 1;
    const midi1_list = ivstmidimapping2.Midi1ControllerParamIDAssignmentList{ .count = midi1_out.len, .map = &midi1_out };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getMidi1ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput), &midi1_list));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 200), midi1_out[0].pId);
}

test "midi 2 mapping honors configured assignment direction" {
    const Mapping = Midi2Mapping(1, 1, struct {
        pub const direction = @intFromEnum(ivstcomponent.BusDirections.kOutput);
    });
    var mapping = Mapping{};
    const iface = mapping.asMapping();
    try std.testing.expectEqual(types.kResultOk, mapping.addMidi2(.{ .pId = 100 }));
    try std.testing.expectEqual(types.kResultOk, mapping.addMidi1(.{ .pId = 200 }));

    try std.testing.expectEqual(@as(types.uint32, 0), iface.vtable.getNumMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.uint32, 1), iface.vtable.getNumMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kOutput)));

    var midi2_out = [_]ivstmidimapping2.Midi2ControllerParamIDAssignment{.{}} ** 1;
    const midi2_list = ivstmidimapping2.Midi2ControllerParamIDAssignmentList{ .count = midi2_out.len, .map = &midi2_out };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getMidi2ControllerAssignments(iface, @intFromEnum(ivstcomponent.BusDirections.kOutput), &midi2_list));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 100), midi2_out[0].pId);
}

test "midi learn 2 tracks midi 1 and midi 2 controller input" {
    const Mapping = Midi2Mapping(1, 1, struct {
        pub fn onLiveMidi2ControllerInput(_: anytype, bus_index: ivstmidimapping2.BusIndex, channel: ivstmidimapping2.MidiChannel, controller: ivstmidimapping2.Midi2Controller) types.tresult {
            _ = controller;
            return if (bus_index == 1 and channel == 2) types.kResultOk else types.kInvalidArgument;
        }

        pub fn onLiveMidi1ControllerInput(_: anytype, bus_index: ivstmidimapping2.BusIndex, channel: ivstmidimapping2.MidiChannel, controller: vsttypes.CtrlNumber) types.tresult {
            return if (bus_index == 4 and channel == 5 and controller == 6) types.kResultOk else types.kInvalidArgument;
        }
    });
    var mapping = Mapping{};
    const learn = mapping.asLearn();
    const midi2_controller = ivstmidimapping2.Midi2Controller{ .bank_registered = 3, .index_reserved = 7 };

    try std.testing.expectEqual(types.kInvalidArgument, learn.vtable.onLiveMidi2ControllerInput(learn, 0, 2, midi2_controller));
    try std.testing.expectEqual(types.kResultOk, learn.vtable.onLiveMidi2ControllerInput(learn, 1, 2, midi2_controller));
    try std.testing.expectEqual(types.kResultOk, learn.vtable.onLiveMidi1ControllerInput(learn, 4, 5, 6));
    try std.testing.expectEqual(@as(types.uint32, 2), mapping.midi2_input_count);
    try std.testing.expectEqual(@as(types.uint32, 1), mapping.midi1_input_count);
    try std.testing.expectEqual(@as(ivstmidimapping2.BusIndex, 4), mapping.last_bus);
    try std.testing.expectEqual(@as(ivstmidimapping2.MidiChannel, 5), mapping.last_channel);
    try std.testing.expectEqual(@as(vsttypes.CtrlNumber, 6), mapping.last_midi1_controller);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, mapping.asMapping().vtable.queryInterface(mapping.asMapping(), &ivstmidimapping2.imidi_learn2_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_learn: *ivstmidimapping2.IMidiLearn2 = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_learn.vtable.release(queried_learn));
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

test "physical UI mapping clamps inflated map counts" {
    const Mapping = PhysicalUIMapping(1, struct {});
    var mapping = Mapping{};
    const iface = mapping.asInterface();
    mapping.maps[0] = .{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), .noteExpressionTypeID = 12 };
    mapping.map_count = 99;

    var list = ivstphysicalui.PhysicalUIMapList{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getPhysicalUIMapping(iface, 0, 1, &list));
    try std.testing.expectEqual(@as(types.uint32, 1), list.count);
    try std.testing.expectEqual(@intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), list.map.?[0].physicalUITypeID);
    try std.testing.expectEqual(types.kResultFalse, mapping.addMap(.{}));
}

test "physical UI mapping reports empty lists and supports query interface" {
    const Mapping = PhysicalUIMapping(1, struct {});
    var mapping = Mapping{};
    const iface = mapping.asInterface();
    var list = ivstphysicalui.PhysicalUIMapList{ .count = 99, .map = @ptrFromInt(0x1000) };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getPhysicalUIMapping(iface, 8, 9, &list));
    try std.testing.expectEqual(@as(types.uint32, 0), list.count);
    try std.testing.expect(list.map != null);
    try std.testing.expectEqual(@as(types.uint32, 1), mapping.request_count);
    try std.testing.expectEqual(@as(types.int32, 8), mapping.last_bus);
    try std.testing.expectEqual(@as(types.int16, 9), mapping.last_channel);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstphysicalui.inote_expression_physical_ui_mapping_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_iface: *ivstphysicalui.INoteExpressionPhysicalUIMapping = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_iface.vtable.release(queried_iface));
}
