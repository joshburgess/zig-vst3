const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");

fn failInfo(out: anytype) types.tresult {
    out.* = .{};
    return types.kInvalidArgument;
}

pub fn UnitInfo(comptime max_units: usize, comptime max_program_lists: usize, comptime Config: type) type {
    if (max_units == 0) @compileError("UnitInfo requires at least one unit slot");
    vst_index.requireInt32Capacity(max_units, "UnitInfo unit capacity");
    vst_index.requireInt32Capacity(max_program_lists, "UnitInfo program list capacity");

    return extern struct {
        const Self = @This();

        iface: ivstunits.IUnitInfo = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        units: [max_units]ivstunits.UnitInfo = rootUnits(),
        unit_count: types.int32 = 1,
        program_lists: [max_program_lists]ivstunits.ProgramListInfo = [_]ivstunits.ProgramListInfo{.{}} ** max_program_lists,
        program_list_count: types.int32 = 0,
        selected_unit: vsttypes.UnitID = ivstunits.kRootUnitId,
        unit_program_data_count: types.uint32 = 0,
        last_unit_program_list_id: types.int32 = ivstunits.kNoProgramListId,
        last_unit_program_index: types.int32 = ivstunits.kAllProgramInvalid,

        pub fn asInterface(self: *Self) *ivstunits.IUnitInfo {
            return &self.iface;
        }

        fn recordUnitProgramData(self: *Self, list_id: types.int32, program_index: types.int32) void {
            self.unit_program_data_count +|= 1;
            self.last_unit_program_list_id = list_id;
            self.last_unit_program_index = program_index;
        }

        pub fn setRootName(self: *Self, name: []const u8) void {
            string128.copy(&self.units[0].name, name);
        }

        fn appendUnitIndex(self: *Self, id: vsttypes.UnitID, parent_id: vsttypes.UnitID, name: []const u8, program_list_id: vsttypes.ProgramListID) ?usize {
            const index = vst_index.appendIndex(self.unit_count, max_units) orelse return null;
            self.units[index] = .{
                .id = id,
                .parentUnitId = parent_id,
                .programListId = program_list_id,
            };
            string128.copy(&self.units[index].name, name);
            self.unit_count = vst_index.int32NextCount(index);
            return index;
        }

        pub fn addUnit(self: *Self, id: vsttypes.UnitID, parent_id: vsttypes.UnitID, name: []const u8, program_list_id: vsttypes.ProgramListID) types.tresult {
            _ = self.appendUnitIndex(id, parent_id, name, program_list_id) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn appendProgramListIndex(self: *Self, id: vsttypes.ProgramListID, name: []const u8, program_count: types.int32) ?usize {
            _ = vst_index.nonNegativeCount(program_count) orelse return null;
            const index = vst_index.appendIndex(self.program_list_count, max_program_lists) orelse return null;
            self.program_lists[index] = .{
                .id = id,
                .programCount = program_count,
            };
            string128.copy(&self.program_lists[index].name, name);
            self.program_list_count = vst_index.int32NextCount(index);
            return index;
        }

        pub fn addProgramList(self: *Self, id: vsttypes.ProgramListID, name: []const u8, program_count: types.int32) types.tresult {
            _ = self.appendProgramListIndex(id, name, program_count) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        fn safeUnitCount(self: *const Self) usize {
            return vst_index.clampedCount(self.unit_count, max_units);
        }

        fn safeProgramListCount(self: *const Self) usize {
            return vst_index.clampedCount(self.program_list_count, max_program_lists);
        }

        pub fn unitIndexOfId(self: *const Self, id: vsttypes.UnitID) ?usize {
            for (self.units[0..self.safeUnitCount()], 0..) |unit, unit_index| {
                if (unit.id == id) return unit_index;
            }
            return null;
        }

        pub fn programListIndexOfId(self: *const Self, id: vsttypes.ProgramListID) ?usize {
            for (self.program_lists[0..self.safeProgramListCount()], 0..) |list, list_index| {
                if (list.id == id) return list_index;
            }
            return null;
        }

        pub fn unitByIndex(self: *const Self, index: types.int32) ?ivstunits.UnitInfo {
            const unit_index = vst_index.bounded(index, self.safeUnitCount()) orelse return null;
            return self.units[unit_index];
        }

        pub fn programListByIndex(self: *const Self, index: types.int32) ?ivstunits.ProgramListInfo {
            const list_index = vst_index.bounded(index, self.safeProgramListCount()) orelse return null;
            return self.program_lists[list_index];
        }

        fn rootUnits() [max_units]ivstunits.UnitInfo {
            var values: [max_units]ivstunits.UnitInfo = [_]ivstunits.UnitInfo{.{}} ** max_units;
            values[0] = .{
                .id = ivstunits.kRootUnitId,
                .parentUnitId = ivstunits.kNoParentUnitId,
                .programListId = ivstunits.kNoProgramListId,
            };
            string128.copy(&values[0].name, "Root");
            return values;
        }

        const owner = interface_map.ownerFromField(Self, ivstunits.IUnitInfo, "iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstunits.iunit_info_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IUnitInfo");
        }

        fn getUnitCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(owner(ptr).safeUnitCount());
        }

        fn getUnitInfo(ptr: *anyopaque, index: types.int32, out: *ivstunits.UnitInfo) callconv(.c) types.tresult {
            const self = owner(ptr);
            out.* = self.unitByIndex(index) orelse return failInfo(out);
            return types.kResultOk;
        }

        fn getProgramListCount(ptr: *anyopaque) callconv(.c) types.int32 {
            return vst_index.int32Count(owner(ptr).safeProgramListCount());
        }

        fn getProgramListInfo(ptr: *anyopaque, index: types.int32, out: *ivstunits.ProgramListInfo) callconv(.c) types.tresult {
            if (max_program_lists == 0) return failInfo(out);
            const self = owner(ptr);
            out.* = self.programListByIndex(index) orelse return failInfo(out);
            return types.kResultOk;
        }

        fn failProgramString(out: [*]vsttypes.TChar, result: types.tresult) types.tresult {
            string128.clearPtr(out);
            return result;
        }

        fn getProgramName(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            const self = owner(ptr);
            string128.clearPtr(out);
            if (@hasDecl(Config, "getProgramName")) {
                const result = Config.getProgramName(self, list_id, program_index, out);
                if (result != types.kResultOk) return failProgramString(out, result);
                return result;
            }
            return types.kInvalidArgument;
        }

        fn getProgramInfo(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, attribute_id: ?vsttypes.CString, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            const self = owner(ptr);
            string128.clearPtr(out);
            const id = attribute_id orelse return types.kInvalidArgument;
            if (@hasDecl(Config, "getProgramInfo")) {
                const result = Config.getProgramInfo(self, list_id, program_index, id, out);
                if (result != types.kResultOk) return failProgramString(out, result);
                return result;
            }
            return types.kInvalidArgument;
        }

        fn hasProgramPitchNames(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "hasProgramPitchNames")) return Config.hasProgramPitchNames(self, list_id, program_index);
            return types.kResultFalse;
        }

        fn getProgramPitchName(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, pitch: types.int16, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            const self = owner(ptr);
            string128.clearPtr(out);
            if (@hasDecl(Config, "getProgramPitchName")) {
                const result = Config.getProgramPitchName(self, list_id, program_index, pitch, out);
                if (result != types.kResultOk) return failProgramString(out, result);
                return result;
            }
            return types.kInvalidArgument;
        }

        fn getSelectedUnit(ptr: *anyopaque) callconv(.c) vsttypes.UnitID {
            return owner(ptr).selected_unit;
        }

        fn selectUnit(ptr: *anyopaque, id: vsttypes.UnitID) callconv(.c) types.tresult {
            const self = owner(ptr);
            _ = self.unitIndexOfId(id) orelse return types.kInvalidArgument;
            self.selected_unit = id;
            return types.kResultOk;
        }

        fn failUnitByBus(out: *vsttypes.UnitID, result: types.tresult) types.tresult {
            out.* = ivstunits.kRootUnitId;
            return result;
        }

        fn getUnitByBus(ptr: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, bus_index: types.int32, channel: types.int32, out: *vsttypes.UnitID) callconv(.c) types.tresult {
            const self = owner(ptr);
            out.* = ivstunits.kRootUnitId;
            if (@hasDecl(Config, "getUnitByBus")) {
                const result = Config.getUnitByBus(self, media_type, direction, bus_index, channel, out);
                if (result != types.kResultOk) return failUnitByBus(out, result);
                return result;
            }
            return types.kResultOk;
        }

        fn setUnitProgramData(ptr: *anyopaque, list_id: types.int32, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.recordUnitProgramData(list_id, program_index);
            if (@hasDecl(Config, "setUnitProgramData")) return Config.setUnitProgramData(self, list_id, program_index, stream);
            return types.kResultFalse;
        }

        const vtable = ivstunits.IUnitInfoVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getUnitCount = getUnitCount,
            .getUnitInfo = getUnitInfo,
            .getProgramListCount = getProgramListCount,
            .getProgramListInfo = getProgramListInfo,
            .getProgramName = getProgramName,
            .getProgramInfo = getProgramInfo,
            .hasProgramPitchNames = hasProgramPitchNames,
            .getProgramPitchName = getProgramPitchName,
            .getSelectedUnit = getSelectedUnit,
            .selectUnit = selectUnit,
            .getUnitByBus = getUnitByBus,
            .setUnitProgramData = setUnitProgramData,
        };
    };
}

pub fn UnitProgramData(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        program_iface: ivstunits.IProgramListData = .{ .vtable = &program_vtable },
        unit_iface: ivstunits.IUnitData = .{ .vtable = &unit_vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        program_get_count: types.uint32 = 0,
        program_set_count: types.uint32 = 0,
        unit_get_count: types.uint32 = 0,
        unit_set_count: types.uint32 = 0,
        last_program_list_id: vsttypes.ProgramListID = ivstunits.kNoProgramListId,
        last_program_index: types.int32 = ivstunits.kAllProgramInvalid,
        last_unit_id: vsttypes.UnitID = ivstunits.kRootUnitId,

        pub fn asProgramListData(self: *Self) *ivstunits.IProgramListData {
            return &self.program_iface;
        }

        pub fn asUnitData(self: *Self) *ivstunits.IUnitData {
            return &self.unit_iface;
        }

        fn recordProgramListRequest(self: *Self, list_id: vsttypes.ProgramListID) void {
            self.last_program_list_id = list_id;
        }

        fn recordProgramDataRequest(self: *Self, list_id: vsttypes.ProgramListID, program_index: types.int32) void {
            self.last_program_list_id = list_id;
            self.last_program_index = program_index;
        }

        fn recordUnitRequest(self: *Self, unit_id: vsttypes.UnitID) void {
            self.last_unit_id = unit_id;
        }

        const ownerFromProgram = interface_map.ownerFromField(Self, ivstunits.IProgramListData, "program_iface");
        const ownerFromUnit = interface_map.ownerFromField(Self, ivstunits.IUnitData, "unit_iface");

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.program_iface },
                .{ .iid = &ivstunits.iprogram_list_data_iid, .ptr = &self.program_iface },
                .{ .iid = &ivstunits.iunit_data_iid, .ptr = &self.unit_iface },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, programAddRef, &entries, requested_iid, out);
        }

        fn programQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return ownerFromProgram(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn unitQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            return self.queryCanonical(&self.program_iface, requested_iid, out);
        }

        fn programAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromProgram(ptr).ref_count, "FUnknown");
        }

        fn unitAddRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&ownerFromUnit(ptr).ref_count, "FUnknown");
        }

        fn programRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromProgram(ptr).ref_count, "IProgramListData");
        }

        fn unitRelease(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&ownerFromUnit(ptr).ref_count, "IUnitData");
        }

        fn programDataSupported(ptr: *anyopaque, list_id: vsttypes.ProgramListID) callconv(.c) types.tresult {
            const self = ownerFromProgram(ptr);
            self.recordProgramListRequest(list_id);
            if (@hasDecl(Config, "programDataSupported")) return Config.programDataSupported(self, list_id);
            return types.kResultFalse;
        }

        fn getProgramData(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = ownerFromProgram(ptr);
            self.program_get_count +|= 1;
            self.recordProgramDataRequest(list_id, program_index);
            if (@hasDecl(Config, "getProgramData")) return Config.getProgramData(self, list_id, program_index, stream);
            return types.kResultFalse;
        }

        fn setProgramData(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = ownerFromProgram(ptr);
            self.program_set_count +|= 1;
            self.recordProgramDataRequest(list_id, program_index);
            if (@hasDecl(Config, "setProgramData")) return Config.setProgramData(self, list_id, program_index, stream);
            return types.kResultFalse;
        }

        fn unitDataSupported(ptr: *anyopaque, unit_id: vsttypes.UnitID) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            self.recordUnitRequest(unit_id);
            if (@hasDecl(Config, "unitDataSupported")) return Config.unitDataSupported(self, unit_id);
            return types.kResultFalse;
        }

        fn getUnitData(ptr: *anyopaque, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            self.unit_get_count +|= 1;
            self.recordUnitRequest(unit_id);
            if (@hasDecl(Config, "getUnitData")) return Config.getUnitData(self, unit_id, stream);
            return types.kResultFalse;
        }

        fn setUnitData(ptr: *anyopaque, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) callconv(.c) types.tresult {
            const self = ownerFromUnit(ptr);
            self.unit_set_count +|= 1;
            self.recordUnitRequest(unit_id);
            if (@hasDecl(Config, "setUnitData")) return Config.setUnitData(self, unit_id, stream);
            return types.kResultFalse;
        }

        const program_vtable = ivstunits.IProgramListDataVTable{
            .queryInterface = programQuery,
            .addRef = programAddRef,
            .release = programRelease,
            .programDataSupported = programDataSupported,
            .getProgramData = getProgramData,
            .setProgramData = setProgramData,
        };

        const unit_vtable = ivstunits.IUnitDataVTable{
            .queryInterface = unitQuery,
            .addRef = unitAddRef,
            .release = unitRelease,
            .unitDataSupported = unitDataSupported,
            .getUnitData = getUnitData,
            .setUnitData = setUnitData,
        };
    };
}

test "unit info exposes root unit defaults" {
    const Info = UnitInfo(2, 1, struct {});
    var info = Info{};
    const iface = info.asInterface();

    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getUnitCount(iface));
    var root = ivstunits.UnitInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getUnitInfo(iface, 0, &root));
    try std.testing.expectEqual(ivstunits.kRootUnitId, root.id);
    try std.testing.expectEqual(ivstunits.kNoParentUnitId, root.parentUnitId);
    try std.testing.expectEqual(ivstunits.kNoProgramListId, root.programListId);
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Root")[0..4], std.mem.sliceTo(&root.name, 0));

    var missing = ivstunits.UnitInfo{};
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getUnitInfo(iface, 1, &missing));
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getProgramListCount(iface));

    var program_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramName(iface, ivstunits.kNoProgramListId, 0, &program_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_name[1]);

    var program_info: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramInfo(iface, ivstunits.kNoProgramListId, 0, null, &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);
    program_info = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramInfo(iface, ivstunits.kNoProgramListId, 0, "name", &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[1]);

    var pitch_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramPitchName(iface, ivstunits.kNoProgramListId, 0, 60, &pitch_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[1]);

    try std.testing.expectEqual(ivstunits.kRootUnitId, iface.vtable.getSelectedUnit(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.selectUnit(iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.selectUnit(iface, 99));
}

test "unit info stores program list entries and selected unit" {
    const Info = UnitInfo(2, 1, struct {});
    var info = Info{};
    info.setRootName("Main");
    try std.testing.expectEqual(types.kResultOk, info.addProgramList(4, "Programs", 3));
    try std.testing.expectEqual(types.kResultOk, info.addUnit(7, ivstunits.kRootUnitId, "Layer", 4));
    const iface = info.asInterface();

    var unit = ivstunits.UnitInfo{};
    var list = ivstunits.ProgramListInfo{};
    try std.testing.expectEqual(@as(vsttypes.UnitID, 7), info.unitByIndex(1).?.id);
    try std.testing.expect(info.unitByIndex(2) == null);
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 4), info.programListByIndex(0).?.id);
    try std.testing.expect(info.programListByIndex(1) == null);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getUnitInfo(iface, 1, &unit));
    try std.testing.expectEqual(@as(vsttypes.UnitID, 7), unit.id);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramListInfo(iface, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 4), list.id);
    try std.testing.expectEqual(@as(types.int32, 3), list.programCount);
    try std.testing.expectEqual(@as(?usize, 0), info.unitIndexOfId(ivstunits.kRootUnitId));
    try std.testing.expectEqual(@as(?usize, 1), info.unitIndexOfId(7));
    try std.testing.expectEqual(@as(?usize, null), info.unitIndexOfId(99));
    try std.testing.expectEqual(@as(?usize, 0), info.programListIndexOfId(4));
    try std.testing.expectEqual(@as(?usize, null), info.programListIndexOfId(99));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.selectUnit(iface, 7));
    try std.testing.expectEqual(@as(vsttypes.UnitID, 7), iface.vtable.getSelectedUnit(iface));
}

test "unit info rejects extra unit and program-list entries" {
    const Info = UnitInfo(2, 1, struct {});
    var info = Info{};
    try std.testing.expectEqual(types.kResultOk, info.addUnit(2, ivstunits.kRootUnitId, "Child", ivstunits.kNoProgramListId));
    try std.testing.expectEqual(types.kResultFalse, info.addUnit(3, ivstunits.kRootUnitId, "Overflow", ivstunits.kNoProgramListId));
    try std.testing.expectEqual(types.kResultOk, info.addProgramList(1, "Programs", 2));
    try std.testing.expectEqual(types.kResultFalse, info.addProgramList(2, "More", 1));

    const iface = info.asInterface();
    try std.testing.expectEqual(@as(types.int32, 2), iface.vtable.getUnitCount(iface));
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getProgramListCount(iface));

    var unit = ivstunits.UnitInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getUnitInfo(iface, 1, &unit));
    try std.testing.expectEqual(@as(vsttypes.UnitID, 2), unit.id);

    var list = ivstunits.ProgramListInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramListInfo(iface, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 1), list.id);
}

test "unit info rejects invalid program-list counts" {
    const Info = UnitInfo(1, 1, struct {});
    var info = Info{};
    const iface = info.asInterface();

    try std.testing.expectEqual(types.kResultFalse, info.addProgramList(1, "Invalid", -1));
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getProgramListCount(iface));

    var list = ivstunits.ProgramListInfo{ .id = 99, .programCount = 99 };
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramListInfo(iface, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 0), list.id);
    try std.testing.expectEqual(@as(types.int32, 0), list.programCount);
}

test "unit info truncates long unit and program-list names" {
    const Info = UnitInfo(2, 1, struct {});
    var info = Info{};
    const long_name = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz";
    info.setRootName(long_name);
    try std.testing.expectEqual(types.kResultOk, info.addProgramList(1, long_name, 1));
    try std.testing.expectEqual(types.kResultOk, info.addUnit(2, ivstunits.kRootUnitId, long_name, 1));
    const iface = info.asInterface();

    var root = ivstunits.UnitInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getUnitInfo(iface, 0, &root));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'a'), root.name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'w'), root.name[string128.payload_units - 1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), root.name[string128.payload_units]);

    var unit = ivstunits.UnitInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getUnitInfo(iface, 1, &unit));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'a'), unit.name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'w'), unit.name[string128.payload_units - 1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), unit.name[string128.payload_units]);

    var list = ivstunits.ProgramListInfo{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramListInfo(iface, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.TChar, 'a'), list.name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'w'), list.name[string128.payload_units - 1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), list.name[string128.payload_units]);
}

test "unit info clamps corrupted counts" {
    const Info = UnitInfo(2, 1, struct {});
    var info = Info{};
    const iface = info.asInterface();
    var unit = ivstunits.UnitInfo{ .id = 99 };
    var list = ivstunits.ProgramListInfo{ .id = 99 };

    info.unit_count = -1;
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getUnitCount(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getUnitInfo(iface, 0, &unit));
    try std.testing.expectEqual(@as(vsttypes.UnitID, 0), unit.id);
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.selectUnit(iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultFalse, info.addUnit(2, ivstunits.kRootUnitId, "Child", ivstunits.kNoProgramListId));

    info.unit_count = 3;
    try std.testing.expectEqual(@as(types.int32, 2), iface.vtable.getUnitCount(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getUnitInfo(iface, 2, &unit));

    info.program_list_count = -1;
    try std.testing.expectEqual(@as(types.int32, 0), iface.vtable.getProgramListCount(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramListInfo(iface, 0, &list));
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 0), list.id);
    try std.testing.expectEqual(types.kResultFalse, info.addProgramList(1, "Programs", 1));

    info.program_list_count = 2;
    try std.testing.expectEqual(@as(types.int32, 1), iface.vtable.getProgramListCount(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramListInfo(iface, 1, &list));
}

test "unit info delegates optional callbacks and supports query interface" {
    const Info = UnitInfo(1, 0, struct {
        pub fn getProgramName(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            if (list_id != 1 or program_index != 2) return types.kInvalidArgument;
            const name = std.unicode.utf8ToUtf16LeStringLiteral("Init");
            @memcpy(out[0..name.len], name);
            out[name.len] = 0;
            return types.kResultOk;
        }

        pub fn getProgramInfo(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, attribute_id: vsttypes.CString, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            if (list_id != 1 or program_index != 2 or !std.mem.eql(u8, std.mem.span(attribute_id), "category")) return types.kInvalidArgument;
            const value = std.unicode.utf8ToUtf16LeStringLiteral("Lead");
            @memcpy(out[0..value.len], value);
            out[value.len] = 0;
            return types.kResultOk;
        }

        pub fn hasProgramPitchNames(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32) types.tresult {
            _ = self;
            return if (list_id == 1 and program_index == 2) types.kResultOk else types.kResultFalse;
        }

        pub fn getProgramPitchName(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, pitch: types.int16, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            if (list_id != 1 or program_index != 2 or pitch != 60) return types.kInvalidArgument;
            const value = std.unicode.utf8ToUtf16LeStringLiteral("C3");
            @memcpy(out[0..value.len], value);
            out[value.len] = 0;
            return types.kResultOk;
        }
    });
    var info = Info{};
    const iface = info.asInterface();

    var name: vsttypes.String128 = string128.zero;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramName(iface, 1, 2, &name));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Init")[0..4], std.mem.sliceTo(&name, 0));

    var program_info: vsttypes.String128 = string128.zero;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramInfo(iface, 1, 2, "category", &program_info));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("Lead")[0..4], std.mem.sliceTo(&program_info, 0));

    var pitch_name: vsttypes.String128 = string128.zero;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.hasProgramPitchNames(iface, 1, 2));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.hasProgramPitchNames(iface, 1, 3));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getProgramPitchName(iface, 1, 2, 60, &pitch_name));
    try std.testing.expectEqualSlices(vsttypes.TChar, std.unicode.utf8ToUtf16LeStringLiteral("C3")[0..2], std.mem.sliceTo(&pitch_name, 0));

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstunits.iunit_info_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_info: *ivstunits.IUnitInfo = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_info.vtable.release(queried_info));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), info.ref_count.load(.seq_cst));
    const queried_unknown: *ivstunits.IUnitInfo = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "unit info clears unsupported query output" {
    const Info = UnitInfo(1, 0, struct {});
    var info = Info{};
    const iface = info.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "unit info clears delegated failure outputs" {
    const Info = UnitInfo(1, 0, struct {
        pub fn getProgramName(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            _ = list_id;
            _ = program_index;
            out[0] = 'x';
            return types.kInvalidArgument;
        }

        pub fn getProgramInfo(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, attribute_id: vsttypes.CString, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            _ = list_id;
            _ = program_index;
            _ = attribute_id;
            out[0] = 'x';
            return types.kInvalidArgument;
        }

        pub fn getProgramPitchName(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, pitch: types.int16, out: [*]vsttypes.TChar) types.tresult {
            _ = self;
            _ = list_id;
            _ = program_index;
            _ = pitch;
            out[0] = 'x';
            return types.kInvalidArgument;
        }

        pub fn getUnitByBus(self: anytype, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, bus_index: types.int32, channel: types.int32, out: *vsttypes.UnitID) types.tresult {
            _ = self;
            _ = media_type;
            _ = direction;
            _ = bus_index;
            _ = channel;
            out.* = 99;
            return types.kInvalidArgument;
        }
    });
    var info = Info{};
    const iface = info.asInterface();

    var name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramName(iface, 1, 2, &name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), name[string128.payload_units]);

    var program_info: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramInfo(iface, 1, 2, "name", &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[string128.payload_units]);

    var pitch_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getProgramPitchName(iface, 1, 2, 60, &pitch_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[string128.payload_units]);

    var unit_id: vsttypes.UnitID = 99;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.getUnitByBus(iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 0, &unit_id));
    try std.testing.expectEqual(ivstunits.kRootUnitId, unit_id);
}

test "unit program data tracks default calls" {
    const Data = UnitProgramData(struct {});
    var data = Data{};
    const programs = data.asProgramListData();
    const units = data.asUnitData();

    try std.testing.expectEqual(types.kResultFalse, programs.vtable.programDataSupported(programs, 7));
    try std.testing.expectEqual(types.kResultFalse, programs.vtable.getProgramData(programs, 7, 3, null));
    try std.testing.expectEqual(types.kResultFalse, programs.vtable.setProgramData(programs, 7, 4, null));
    try std.testing.expectEqual(types.kResultFalse, units.vtable.unitDataSupported(units, 9));
    try std.testing.expectEqual(types.kResultFalse, units.vtable.getUnitData(units, 9, null));
    try std.testing.expectEqual(types.kResultFalse, units.vtable.setUnitData(units, 10, null));
    try std.testing.expectEqual(@as(types.uint32, 1), data.program_get_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.program_set_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.unit_get_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.unit_set_count);
    try std.testing.expectEqual(@as(vsttypes.ProgramListID, 7), data.last_program_list_id);
    try std.testing.expectEqual(@as(types.int32, 4), data.last_program_index);
    try std.testing.expectEqual(@as(vsttypes.UnitID, 10), data.last_unit_id);
}

test "unit program data delegates hooks and supports query interface" {
    const Data = UnitProgramData(struct {
        pub fn programDataSupported(self: anytype, list_id: vsttypes.ProgramListID) types.tresult {
            _ = self;
            return if (list_id == 1) types.kResultOk else types.kResultFalse;
        }

        pub fn unitDataSupported(self: anytype, unit_id: vsttypes.UnitID) types.tresult {
            _ = self;
            return if (unit_id == 2) types.kResultOk else types.kResultFalse;
        }

        pub fn getProgramData(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) types.tresult {
            _ = stream;
            return if (self.program_get_count == 1 and list_id == 1 and program_index == 4) types.kResultOk else types.kInvalidArgument;
        }

        pub fn setProgramData(self: anytype, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) types.tresult {
            _ = stream;
            return if (self.program_set_count == 1 and list_id == 1 and program_index == 5) types.kResultOk else types.kInvalidArgument;
        }

        pub fn getUnitData(self: anytype, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) types.tresult {
            _ = stream;
            return if (self.unit_get_count == 1 and unit_id == 2) types.kResultOk else types.kInvalidArgument;
        }

        pub fn setUnitData(self: anytype, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) types.tresult {
            _ = stream;
            return if (self.unit_set_count == 1 and unit_id == 3) types.kResultOk else types.kInvalidArgument;
        }
    });
    var data = Data{};
    const programs = data.asProgramListData();
    const units = data.asUnitData();

    try std.testing.expectEqual(types.kResultOk, programs.vtable.programDataSupported(programs, 1));
    try std.testing.expectEqual(types.kResultFalse, units.vtable.unitDataSupported(units, 3));
    try std.testing.expectEqual(types.kResultOk, programs.vtable.getProgramData(programs, 1, 4, null));
    try std.testing.expectEqual(types.kResultOk, programs.vtable.setProgramData(programs, 1, 5, null));
    try std.testing.expectEqual(types.kResultOk, units.vtable.getUnitData(units, 2, null));
    try std.testing.expectEqual(types.kResultOk, units.vtable.setUnitData(units, 3, null));
    try std.testing.expectEqual(@as(types.uint32, 1), data.program_get_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.program_set_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.unit_get_count);
    try std.testing.expectEqual(@as(types.uint32, 1), data.unit_set_count);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, programs.vtable.queryInterface(programs, &ivstunits.iunit_data_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_units: *ivstunits.IUnitData = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_units.vtable.release(queried_units));
}

test "unit program data clears unsupported query output from both interfaces" {
    const Data = UnitProgramData(struct {});
    var data = Data{};
    const programs = data.asProgramListData();
    const units = data.asUnitData();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, programs.vtable.queryInterface(programs, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);

    queried = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, units.vtable.queryInterface(units, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "unit program data query interfaces share object refcount" {
    const Data = UnitProgramData(struct {});
    var data = Data{};

    var queried_programs: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, data.asUnitData().vtable.queryInterface(data.asUnitData(), &ivstunits.iprogram_list_data_iid, &queried_programs));
    try std.testing.expectEqual(@as(?*anyopaque, data.asProgramListData()), queried_programs);
    try std.testing.expectEqual(@as(types.uint32, 2), data.ref_count.load(.seq_cst));

    var queried_unknown: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, data.asUnitData().vtable.queryInterface(data.asUnitData(), &funknown.iid, &queried_unknown));
    try std.testing.expectEqual(@as(?*anyopaque, data.asProgramListData()), queried_unknown);
    try std.testing.expectEqual(@as(types.uint32, 3), data.ref_count.load(.seq_cst));

    const programs: *ivstunits.IProgramListData = @ptrCast(@alignCast(queried_programs.?));
    try std.testing.expectEqual(@as(types.uint32, 2), programs.vtable.release(programs));
    try std.testing.expectEqual(@as(types.uint32, 1), data.asProgramListData().vtable.release(data.asProgramListData()));
}
