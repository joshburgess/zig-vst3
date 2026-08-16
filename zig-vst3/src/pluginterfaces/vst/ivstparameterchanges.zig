const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const iparam_value_queue_iid = tuid.inlineUid(0x01263A18, 0xED074F6F, 0x98C9D356, 0x4686F9BA);
pub const iparameter_changes_iid = tuid.inlineUid(0xA4779663, 0x0BB64A56, 0xB44384A8, 0x466FEB9D);

pub const IParamValueQueueVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getParameterId: *const fn (*anyopaque) callconv(.c) vsttypes.ParamID,
    getPointCount: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getPoint: *const fn (*anyopaque, base_types.int32, [*c]base_types.int32, [*c]vsttypes.ParamValue) callconv(.c) base_types.tresult,
    addPoint: *const fn (*anyopaque, base_types.int32, vsttypes.ParamValue, [*c]base_types.int32) callconv(.c) base_types.tresult,
};

pub const IParamValueQueue = extern struct {
    vtable: *const IParamValueQueueVTable,
};

pub const IParameterChangesVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getParameterCount: *const fn (*anyopaque) callconv(.c) base_types.int32,
    getParameterData: *const fn (*anyopaque, base_types.int32) callconv(.c) ?*IParamValueQueue,
    addParameterData: *const fn (*anyopaque, [*c]const vsttypes.ParamID, [*c]base_types.int32) callconv(.c) ?*IParamValueQueue,
};

pub const IParameterChanges = extern struct {
    vtable: *const IParameterChangesVTable,
};

test "parameter change vtable slot counts include FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IParamValueQueue));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IParameterChanges));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IParamValueQueue));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IParameterChanges));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IParamValueQueueVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IParameterChangesVTable).@"struct".fields.len);
}
