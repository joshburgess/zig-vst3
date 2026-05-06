const base_types = @import("../base/types.zig");
const noteexpression = @import("ivstnoteexpression.zig");
const tuid = @import("../../tuid.zig");

pub const inote_expression_physical_ui_mapping_iid = tuid.inlineUid(0xB03078FF, 0x94D24AC8, 0x90CCD303, 0xD4133324);

pub const PhysicalUITypeID = base_types.uint32;

pub const PhysicalUITypeIDs = enum(base_types.uint32) {
    kPUIXMovement = 0,
    kPUIYMovement = 1,
    kPUIPressure = 2,
    kPUITypeCount = 3,
    kInvalidPUITypeID = 0xFFFFFFFF,
};

pub const PhysicalUIMap = extern struct {
    physicalUITypeID: PhysicalUITypeID = 0,
    noteExpressionTypeID: noteexpression.NoteExpressionTypeID = 0,
};

pub const PhysicalUIMapList = extern struct {
    count: base_types.uint32 = 0,
    map: ?[*]PhysicalUIMap = null,
};

pub const INoteExpressionPhysicalUIMappingVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getPhysicalUIMapping: *const fn (*anyopaque, base_types.int32, base_types.int16, *PhysicalUIMapList) callconv(.C) base_types.tresult,
};

pub const INoteExpressionPhysicalUIMapping = extern struct {
    vtable: *const INoteExpressionPhysicalUIMappingVTable,
};

test "physical UI mapping struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 8), @sizeOf(PhysicalUIMap));
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(PhysicalUIMapList));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(INoteExpressionPhysicalUIMappingVTable).@"struct".fields.len);
}
