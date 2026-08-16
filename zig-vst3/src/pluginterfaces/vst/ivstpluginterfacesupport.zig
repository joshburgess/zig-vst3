const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const iplug_interface_support_iid = tuid.inlineUid(0x4FB58B9E, 0x9EAA4E0F, 0xAB361C1C, 0xCCB56FEA);

pub const IPlugInterfaceSupportVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    isPlugInterfaceSupported: *const fn (*anyopaque, [*c]const tuid.TUID) callconv(.c) base_types.tresult,
};

pub const IPlugInterfaceSupport = extern struct {
    vtable: *const IPlugInterfaceSupportVTable,
};

test "plug interface support vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPlugInterfaceSupport));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IPlugInterfaceSupportVTable).@"struct".fields.len);
}
