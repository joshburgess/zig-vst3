const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const kTestClass: base_types.FIDString = "Test Class";

pub const itest_iid = tuid.inlineUid(0xFE64FC19, 0x95684F53, 0xAAA78DC8, 0x7228338E);
pub const itest_result_iid = tuid.inlineUid(0x69796279, 0xF651418B, 0xB24D79B7, 0xD7C527F4);
pub const itest_suite_iid = tuid.inlineUid(0x5CA7106F, 0x98784AA5, 0xB4D30D71, 0x2F5F1498);
pub const itest_factory_iid = tuid.inlineUid(0xAB483D3A, 0x15264650, 0xBF86EEF6, 0x9A327A93);

pub const ITestVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    setup: *const fn (*anyopaque) callconv(.c) bool,
    run: *const fn (*anyopaque, ?*ITestResult) callconv(.c) bool,
    teardown: *const fn (*anyopaque) callconv(.c) bool,
    getDescription: *const fn (*anyopaque) callconv(.c) ?[*:0]const base_types.char16,
};

pub const ITestResultVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    addErrorMessage: *const fn (*anyopaque, ?[*:0]const base_types.char16) callconv(.c) void,
    addMessage: *const fn (*anyopaque, ?[*:0]const base_types.char16) callconv(.c) void,
};

pub const ITestSuiteVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    addTest: *const fn (*anyopaque, base_types.FIDString, ?*ITest) callconv(.c) base_types.tresult,
    addTestSuite: *const fn (*anyopaque, base_types.FIDString, ?*ITestSuite) callconv(.c) base_types.tresult,
    setEnvironment: *const fn (*anyopaque, ?*ITest) callconv(.c) base_types.tresult,
};

pub const ITestFactoryVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    createTests: *const fn (*anyopaque, ?*anyopaque, ?*ITestSuite) callconv(.c) base_types.tresult,
};

pub const ITest = extern struct {
    vtable: *const ITestVTable,
};

pub const ITestResult = extern struct {
    vtable: *const ITestResultVTable,
};

pub const ITestSuite = extern struct {
    vtable: *const ITestSuiteVTable,
};

pub const ITestFactory = extern struct {
    vtable: *const ITestFactoryVTable,
};

test "test interface vtable slot counts include FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITest));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITestResult));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITestSuite));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(ITestFactory));
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(ITestVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(ITestResultVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(ITestSuiteVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(ITestFactoryVTable).@"struct".fields.len);
}
