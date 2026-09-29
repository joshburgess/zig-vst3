const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iparameter_finder_iid = tuid.inlineUid(0x0F618302, 0x215D4587, 0xA512073C, 0x77B9D383);

pub const IParameterFinderVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    findParameter: *const fn (*anyopaque, base_types.int32, base_types.int32, [*c]vsttypes.ParamID) callconv(.c) base_types.tresult,
};

pub const IParameterFinder = extern struct {
    vtable: *const IParameterFinderVTable,
};

test "parameter finder vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IParameterFinder));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IParameterFinderVTable).@"struct".fields.len);
}
