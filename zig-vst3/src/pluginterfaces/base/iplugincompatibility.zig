const base_types = @import("types.zig");
const ibstream = @import("ibstream.zig");
const tuid = @import("../../tuid.zig");

pub const iplugin_compatibility_iid = tuid.inlineUid(0x4AFD4B6A, 0x35D7C240, 0xA5C31414, 0xFB7D15E6);

pub const kPluginCompatibilityClass: base_types.FIDString = "Plugin Compatibility Class";

pub const IPluginCompatibilityVTable = extern struct {
    queryInterface: *const fn (*anyopaque, [*c]const tuid.TUID, [*c]?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getCompatibilityJSON: *const fn (*anyopaque, ?*ibstream.IBStream) callconv(.c) base_types.tresult,
};

pub const IPluginCompatibility = extern struct {
    vtable: *const IPluginCompatibilityVTable,
};

test "plugin compatibility vtable size matches SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IPluginCompatibility));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IPluginCompatibility));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IPluginCompatibilityVTable).@"struct".fields.len);
}
