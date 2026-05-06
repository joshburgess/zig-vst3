const ipluginbase = @import("../base/ipluginbase.zig");
const istringresult = @import("../base/istringresult.zig");
const component = @import("ivstcomponent.zig");
const edit_controller = @import("ivsteditcontroller.zig");
const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const itest_plug_provider_iid = tuid.inlineUid(0x86BE70EE, 0x4E99430F, 0x978F1E6E, 0xD68FB5BA);
pub const itest_plug_provider2_iid = tuid.inlineUid(0xC7C75364, 0x7B8343AC, 0xA4495B0A, 0x3E5A46C7);

pub const ITestPlugProviderVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getComponent: *const fn (*anyopaque) callconv(.C) ?*component.IComponent,
    getController: *const fn (*anyopaque) callconv(.C) ?*edit_controller.IEditController,
    releasePlugIn: *const fn (*anyopaque, ?*component.IComponent, ?*edit_controller.IEditController) callconv(.C) base_types.tresult,
    getSubCategories: *const fn (*anyopaque, *istringresult.IStringResult) callconv(.C) base_types.tresult,
    getComponentUID: *const fn (*anyopaque, *anyopaque) callconv(.C) base_types.tresult,
};

pub const ITestPlugProvider2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getComponent: *const fn (*anyopaque) callconv(.C) ?*component.IComponent,
    getController: *const fn (*anyopaque) callconv(.C) ?*edit_controller.IEditController,
    releasePlugIn: *const fn (*anyopaque, ?*component.IComponent, ?*edit_controller.IEditController) callconv(.C) base_types.tresult,
    getSubCategories: *const fn (*anyopaque, *istringresult.IStringResult) callconv(.C) base_types.tresult,
    getComponentUID: *const fn (*anyopaque, *anyopaque) callconv(.C) base_types.tresult,
    getPluginFactory: *const fn (*anyopaque) callconv(.C) ?*ipluginbase.IPluginFactory,
};

pub const ITestPlugProvider = extern struct {
    vtable: *const ITestPlugProviderVTable,
};

pub const ITestPlugProvider2 = extern struct {
    vtable: *const ITestPlugProvider2VTable,
};

test "test plug provider vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITestPlugProvider));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITestPlugProvider2));
    try @import("std").testing.expectEqual(@as(usize, 8), @typeInfo(ITestPlugProviderVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 9), @typeInfo(ITestPlugProvider2VTable).@"struct".fields.len);
}
