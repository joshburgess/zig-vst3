const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iremap_param_id_iid = tuid.inlineUid(0x2B88021E, 0x6286B646, 0xB49DF76A, 0x5663061C);

pub const IRemapParamIDVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getCompatibleParamID: *const fn (*anyopaque, *const tuid.TUID, vsttypes.ParamID, *vsttypes.ParamID) callconv(.C) base_types.tresult,
};

pub const IRemapParamID = extern struct {
    vtable: *const IRemapParamIDVTable,
};

test "remap param ID vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IRemapParamIDVTable).@"struct".fields.len);
}
