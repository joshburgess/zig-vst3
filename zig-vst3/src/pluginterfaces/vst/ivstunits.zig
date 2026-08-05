const base_types = @import("../base/types.zig");
const ibstream = @import("../base/ibstream.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iunit_handler_iid = tuid.inlineUid(0x4B5147F8, 0x4654486B, 0x8DAB30BA, 0x163A3C56);
pub const iunit_handler2_iid = tuid.inlineUid(0xF89F8CDF, 0x699E4BA5, 0x96AAC9A4, 0x81452B01);
pub const iunit_info_iid = tuid.inlineUid(0x3D4BD6B5, 0x913A4FD2, 0xA886E768, 0xA5EB92C1);
pub const iprogram_list_data_iid = tuid.inlineUid(0x8683B01F, 0x7B354F70, 0xA2651DEC, 0x353AF4FF);
pub const iunit_data_iid = tuid.inlineUid(0x6C389611, 0xD391455D, 0xB870B833, 0x94A0EFDD);

pub const kRootUnitId: vsttypes.UnitID = 0;
pub const kNoParentUnitId: vsttypes.UnitID = -1;
pub const kNoProgramListId: vsttypes.ProgramListID = -1;
pub const kAllProgramInvalid: base_types.int32 = -1;

pub const UnitInfo = extern struct {
    id: vsttypes.UnitID = 0,
    parentUnitId: vsttypes.UnitID = 0,
    name: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    programListId: vsttypes.ProgramListID = 0,
};

pub const ProgramListInfo = extern struct {
    id: vsttypes.ProgramListID = 0,
    name: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    programCount: base_types.int32 = 0,
};

pub const IUnitHandlerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    notifyUnitSelection: *const fn (*anyopaque, vsttypes.UnitID) callconv(.c) base_types.tresult,
    notifyProgramListChange: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32) callconv(.c) base_types.tresult,
};

pub const IUnitHandler = extern struct {
    vtable: *const IUnitHandlerVTable,
};

pub const IUnitHandler2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    notifyUnitByBusChange: *const fn (*anyopaque) callconv(.c) base_types.tresult,
};

pub const IUnitHandler2 = extern struct {
    vtable: *const IUnitHandler2VTable,
};

pub const IUnitInfoVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getUnitCount: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getUnitInfo: *const fn (*anyopaque, base_types.int32, [*c]UnitInfo) callconv(.c) base_types.tresult,
    getProgramListCount: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getProgramListInfo: *const fn (*anyopaque, base_types.int32, [*c]ProgramListInfo) callconv(.c) base_types.tresult,
    getProgramName: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32, [*c]vsttypes.TChar) callconv(.c) base_types.tresult,
    getProgramInfo: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32, ?vsttypes.CString, [*c]vsttypes.TChar) callconv(.c) base_types.tresult,
    hasProgramPitchNames: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32) callconv(.c) base_types.tresult,
    getProgramPitchName: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32, base_types.int16, [*c]vsttypes.TChar) callconv(.c) base_types.tresult,
    getSelectedUnit: *const fn (*anyopaque) callconv(.c) vsttypes.UnitID,
    selectUnit: *const fn (*anyopaque, vsttypes.UnitID) callconv(.c) base_types.tresult,
    getUnitByBus: *const fn (*anyopaque, vsttypes.MediaType, vsttypes.BusDirection, base_types.int32, base_types.int32, [*c]vsttypes.UnitID) callconv(.c) base_types.tresult,
    setUnitProgramData: *const fn (*anyopaque, base_types.int32, base_types.int32, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
};

pub const IUnitInfo = extern struct {
    vtable: *const IUnitInfoVTable,
};

pub const IProgramListDataVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    programDataSupported: *const fn (*anyopaque, vsttypes.ProgramListID) callconv(.c) base_types.tresult,
    getProgramData: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
    setProgramData: *const fn (*anyopaque, vsttypes.ProgramListID, base_types.int32, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
};

pub const IProgramListData = extern struct {
    vtable: *const IProgramListDataVTable,
};

pub const IUnitDataVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    unitDataSupported: *const fn (*anyopaque, vsttypes.UnitID) callconv(.c) base_types.tresult,
    getUnitData: *const fn (*anyopaque, vsttypes.UnitID, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
    setUnitData: *const fn (*anyopaque, vsttypes.UnitID, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
};

pub const IUnitData = extern struct {
    vtable: *const IUnitDataVTable,
};

test "unit struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 268), @sizeOf(UnitInfo));
    try @import("std").testing.expectEqual(@as(usize, 4), @alignOf(UnitInfo));
    try @import("std").testing.expectEqual(@as(usize, 264), @sizeOf(ProgramListInfo));
    try @import("std").testing.expectEqual(@as(usize, 4), @alignOf(ProgramListInfo));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IUnitHandler));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IUnitHandler2));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IUnitInfo));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IProgramListData));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IUnitData));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IUnitHandler));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IUnitHandler2));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IUnitInfo));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IProgramListData));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IUnitData));
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IUnitHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IUnitHandler2VTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 15), @typeInfo(IUnitInfoVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IProgramListDataVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IUnitDataVTable).@"struct".fields.len);
}
