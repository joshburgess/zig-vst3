const funknown = @import("funknown.zig");
const types = @import("types.zig");
const tuid = @import("../../tuid.zig");

pub const iplugin_base_iid = tuid.inlineUid(0x22888DDB, 0x156E45AE, 0x8358B348, 0x08190625);
pub const iplugin_factory_iid = tuid.inlineUid(0x7A4D811C, 0x52114A1F, 0xAED9D2EE, 0x0B43BF9F);
pub const iplugin_factory2_iid = tuid.inlineUid(0x0007B650, 0xF24B4C0B, 0xA464EDB9, 0xF00B2ABB);
pub const iplugin_factory3_iid = tuid.inlineUid(0x4555A2AB, 0xC1234E57, 0x9B122910, 0x36878931);

pub const IPluginBaseVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    initialize: *const fn (*anyopaque, ?*funknown.Header) callconv(.C) types.tresult,
    terminate: *const fn (*anyopaque) callconv(.C) types.tresult,
};

pub const IPluginFactoryVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    getFactoryInfo: *const fn (*anyopaque, *PFactoryInfo) callconv(.C) types.tresult,
    countClasses: *const fn (*anyopaque) callconv(.C) types.int32,
    getClassInfo: *const fn (*anyopaque, types.int32, *PClassInfo) callconv(.C) types.tresult,
    createInstance: *const fn (*anyopaque, types.FIDString, types.FIDString, *?*anyopaque) callconv(.C) types.tresult,
};

pub const IPluginFactory = extern struct {
    vtable: *const IPluginFactoryVTable,
};

pub const IPluginFactory2VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    getFactoryInfo: *const fn (*anyopaque, *PFactoryInfo) callconv(.C) types.tresult,
    countClasses: *const fn (*anyopaque) callconv(.C) types.int32,
    getClassInfo: *const fn (*anyopaque, types.int32, *PClassInfo) callconv(.C) types.tresult,
    createInstance: *const fn (*anyopaque, types.FIDString, types.FIDString, *?*anyopaque) callconv(.C) types.tresult,
    getClassInfo2: *const fn (*anyopaque, types.int32, *PClassInfo2) callconv(.C) types.tresult,
};

pub const IPluginFactory2 = extern struct {
    vtable: *const IPluginFactory2VTable,
};

pub const IPluginFactory3VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) types.uint32,
    release: *const fn (*anyopaque) callconv(.C) types.uint32,
    getFactoryInfo: *const fn (*anyopaque, *PFactoryInfo) callconv(.C) types.tresult,
    countClasses: *const fn (*anyopaque) callconv(.C) types.int32,
    getClassInfo: *const fn (*anyopaque, types.int32, *PClassInfo) callconv(.C) types.tresult,
    createInstance: *const fn (*anyopaque, types.FIDString, types.FIDString, *?*anyopaque) callconv(.C) types.tresult,
    getClassInfo2: *const fn (*anyopaque, types.int32, *PClassInfo2) callconv(.C) types.tresult,
    getClassInfoUnicode: *const fn (*anyopaque, types.int32, *PClassInfoW) callconv(.C) types.tresult,
    setHostContext: *const fn (*anyopaque, ?*funknown.Header) callconv(.C) types.tresult,
};

pub const IPluginFactory3 = extern struct {
    vtable: *const IPluginFactory3VTable,
};

pub const PFactoryInfo = extern struct {
    pub const kURLSize = 256;
    pub const kEmailSize = 128;
    pub const kNameSize = 64;

    pub const kNoFlags = 0;
    pub const kClassesDiscardable = 1 << 0;
    pub const kLicenseCheck = 1 << 1;
    pub const kComponentNonDiscardable = 1 << 3;
    pub const kUnicode = 1 << 4;

    vendor: [kNameSize]types.char8 = [_]types.char8{0} ** kNameSize,
    url: [kURLSize]types.char8 = [_]types.char8{0} ** kURLSize,
    email: [kEmailSize]types.char8 = [_]types.char8{0} ** kEmailSize,
    flags: types.int32 = 0,
};

pub const PClassInfo = extern struct {
    pub const kManyInstances = 0x7FFFFFFF;
    pub const kCategorySize = 32;
    pub const kNameSize = 64;

    cid: tuid.TUID = [_]u8{0} ** 16,
    cardinality: types.int32 = 0,
    category: [kCategorySize]types.char8 = [_]types.char8{0} ** kCategorySize,
    name: [kNameSize]types.char8 = [_]types.char8{0} ** kNameSize,
};

pub const PClassInfo2 = extern struct {
    pub const kVendorSize = 64;
    pub const kVersionSize = 64;
    pub const kSubCategoriesSize = 128;

    cid: tuid.TUID = [_]u8{0} ** 16,
    cardinality: types.int32 = 0,
    category: [PClassInfo.kCategorySize]types.char8 = [_]types.char8{0} ** PClassInfo.kCategorySize,
    name: [PClassInfo.kNameSize]types.char8 = [_]types.char8{0} ** PClassInfo.kNameSize,
    classFlags: types.uint32 = 0,
    subCategories: [kSubCategoriesSize]types.char8 = [_]types.char8{0} ** kSubCategoriesSize,
    vendor: [kVendorSize]types.char8 = [_]types.char8{0} ** kVendorSize,
    version: [kVersionSize]types.char8 = [_]types.char8{0} ** kVersionSize,
    sdkVersion: [kVersionSize]types.char8 = [_]types.char8{0} ** kVersionSize,
};

pub const PClassInfoW = extern struct {
    pub const kVendorSize = 64;
    pub const kVersionSize = 64;
    pub const kSubCategoriesSize = 128;

    cid: tuid.TUID = [_]u8{0} ** 16,
    cardinality: types.int32 = 0,
    category: [PClassInfo.kCategorySize]types.char8 = [_]types.char8{0} ** PClassInfo.kCategorySize,
    name: [PClassInfo.kNameSize]types.char16 = [_]types.char16{0} ** PClassInfo.kNameSize,
    classFlags: types.uint32 = 0,
    subCategories: [kSubCategoriesSize]types.char8 = [_]types.char8{0} ** kSubCategoriesSize,
    vendor: [kVendorSize]types.char16 = [_]types.char16{0} ** kVendorSize,
    version: [kVersionSize]types.char16 = [_]types.char16{0} ** kVersionSize,
    sdkVersion: [kVersionSize]types.char16 = [_]types.char16{0} ** kVersionSize,
};

test "pluginbase struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPluginFactory));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPluginFactory2));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPluginFactory3));
    try @import("std").testing.expectEqual(@as(usize, 452), @sizeOf(PFactoryInfo));
    try @import("std").testing.expectEqual(@as(usize, 116), @sizeOf(PClassInfo));
    try @import("std").testing.expectEqual(@as(usize, 440), @sizeOf(PClassInfo2));
    try @import("std").testing.expectEqual(@as(usize, 696), @sizeOf(PClassInfoW));
}
