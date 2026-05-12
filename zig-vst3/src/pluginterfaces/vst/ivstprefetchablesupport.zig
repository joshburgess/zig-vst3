const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const iprefetchable_support_iid = tuid.inlineUid(0x8AE54FDA, 0xE93046B9, 0xA28555BC, 0xDC98E21E);

pub const PrefetchableSupport = base_types.uint32;

pub const ePrefetchableSupport = enum(base_types.int32) {
    kIsNeverPrefetchable = 0,
    kIsYetPrefetchable = 1,
    kIsNotYetPrefetchable = 2,
    kNumPrefetchableSupport = 3,
};

pub const IPrefetchableSupportVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getPrefetchableSupport: *const fn (*anyopaque, *PrefetchableSupport) callconv(.c) base_types.tresult,
};

pub const IPrefetchableSupport = extern struct {
    vtable: *const IPrefetchableSupportVTable,
};

test "prefetchable support vtable slot count includes FUnknown prefix" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPrefetchableSupport));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IPrefetchableSupportVTable).@"struct".fields.len);
}
