const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

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

        fn ownerFromProgram(ptr: *anyopaque) *Self {
            const iface: *ivstunits.IProgramListData = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("program_iface", iface);
        }

        fn ownerFromUnit(ptr: *anyopaque) *Self {
            const iface: *ivstunits.IUnitData = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("unit_iface", iface);
        }

        fn queryCanonical(self: *Self, add_ref_ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.program_iface },
                .{ .iid = &ivstunits.iprogram_list_data_iid, .ptr = &self.program_iface },
                .{ .iid = &ivstunits.iunit_data_iid, .ptr = &self.unit_iface },
            };
            return interface_map.queryWithAddRef(add_ref_ptr, programAddRef, &entries, requested_iid, out);
        }

        fn programQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            return ownerFromProgram(ptr).queryCanonical(ptr, requested_iid, out);
        }

        fn unitQuery(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const self = ownerFromUnit(ptr);
            return self.queryCanonical(&self.program_iface, requested_iid, out);
        }

        fn programAddRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromProgram(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn unitAddRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return ownerFromUnit(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn programRelease(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromProgram(ptr).ref_count, "IProgramListData");
        }

        fn unitRelease(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&ownerFromUnit(ptr).ref_count, "IUnitData");
        }

        fn programDataSupported(ptr: *anyopaque, list_id: vsttypes.ProgramListID) callconv(.C) types.tresult {
            const self = ownerFromProgram(ptr);
            self.last_program_list_id = list_id;
            if (@hasDecl(Config, "programDataSupported")) return Config.programDataSupported(self, list_id);
            return types.kResultFalse;
        }

        fn getProgramData(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.C) types.tresult {
            const self = ownerFromProgram(ptr);
            self.program_get_count += 1;
            self.last_program_list_id = list_id;
            self.last_program_index = program_index;
            if (@hasDecl(Config, "getProgramData")) return Config.getProgramData(self, list_id, program_index, stream);
            return types.kResultFalse;
        }

        fn setProgramData(ptr: *anyopaque, list_id: vsttypes.ProgramListID, program_index: types.int32, stream: ?*ibstream.IBStream) callconv(.C) types.tresult {
            const self = ownerFromProgram(ptr);
            self.program_set_count += 1;
            self.last_program_list_id = list_id;
            self.last_program_index = program_index;
            if (@hasDecl(Config, "setProgramData")) return Config.setProgramData(self, list_id, program_index, stream);
            return types.kResultFalse;
        }

        fn unitDataSupported(ptr: *anyopaque, unit_id: vsttypes.UnitID) callconv(.C) types.tresult {
            const self = ownerFromUnit(ptr);
            self.last_unit_id = unit_id;
            if (@hasDecl(Config, "unitDataSupported")) return Config.unitDataSupported(self, unit_id);
            return types.kResultFalse;
        }

        fn getUnitData(ptr: *anyopaque, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) callconv(.C) types.tresult {
            const self = ownerFromUnit(ptr);
            self.unit_get_count += 1;
            self.last_unit_id = unit_id;
            if (@hasDecl(Config, "getUnitData")) return Config.getUnitData(self, unit_id, stream);
            return types.kResultFalse;
        }

        fn setUnitData(ptr: *anyopaque, unit_id: vsttypes.UnitID, stream: ?*ibstream.IBStream) callconv(.C) types.tresult {
            const self = ownerFromUnit(ptr);
            self.unit_set_count += 1;
            self.last_unit_id = unit_id;
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
    });
    var data = Data{};
    const programs = data.asProgramListData();

    try std.testing.expectEqual(types.kResultOk, programs.vtable.programDataSupported(programs, 1));
    try std.testing.expectEqual(types.kResultFalse, data.asUnitData().vtable.unitDataSupported(data.asUnitData(), 3));

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, programs.vtable.queryInterface(programs, &ivstunits.iunit_data_iid, &queried));
    try std.testing.expect(queried != null);
    const units: *ivstunits.IUnitData = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), units.vtable.release(units));
}
