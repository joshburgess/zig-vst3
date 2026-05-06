const base_types = @import("../base/types.zig");
const iplugview = @import("../gui/iplugview.zig");
const tuid = @import("../../tuid.zig");
const vsttypes = @import("vsttypes.zig");

pub const icomponent_handler3_iid = tuid.inlineUid(0x69F11617, 0xD26B400D, 0xA4B6B964, 0x7B6EBBAB);
pub const icontext_menu_target_iid = tuid.inlineUid(0x3CDF2E75, 0x85D34144, 0xBF86D36B, 0xD7C4894D);
pub const icontext_menu_iid = tuid.inlineUid(0x2E93C863, 0x0C9C4588, 0x97DBECF5, 0xAD17817D);

pub const IComponentHandler3VTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    createContextMenu: *const fn (*anyopaque, ?*iplugview.IPlugView, ?*const vsttypes.ParamID) callconv(.C) ?*IContextMenu,
};

pub const IComponentHandler3 = extern struct {
    vtable: *const IComponentHandler3VTable,
};

pub const IContextMenuTargetVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    executeMenuItem: *const fn (*anyopaque, base_types.int32) callconv(.C) base_types.tresult,
};

pub const IContextMenuItem = extern struct {
    name: vsttypes.String128 = [_]vsttypes.TChar{0} ** 128,
    tag: base_types.int32 = 0,
    flags: base_types.int32 = 0,

    pub const Flags = packed struct(base_types.int32) {
        is_separator: bool = false,
        is_disabled: bool = false,
        is_checked: bool = false,
        is_group_start: bool = false,
        is_group_end: bool = false,
        _: u27 = 0,

        pub const kIsSeparator: base_types.int32 = 1 << 0;
        pub const kIsDisabled: base_types.int32 = 1 << 1;
        pub const kIsChecked: base_types.int32 = 1 << 2;
        pub const kIsGroupStart: base_types.int32 = (1 << 3) | kIsDisabled;
        pub const kIsGroupEnd: base_types.int32 = (1 << 4) | kIsSeparator;
    };
};

pub const IContextMenuVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getItemCount: *const fn (*anyopaque) callconv(.C) base_types.int32,
    getItem: *const fn (*anyopaque, base_types.int32, *IContextMenuItem, *?*IContextMenuTarget) callconv(.C) base_types.tresult,
    addItem: *const fn (*anyopaque, *const IContextMenuItem, ?*IContextMenuTarget) callconv(.C) base_types.tresult,
    removeItem: *const fn (*anyopaque, *const IContextMenuItem, ?*IContextMenuTarget) callconv(.C) base_types.tresult,
    popup: *const fn (*anyopaque, base_types.UCoord, base_types.UCoord) callconv(.C) base_types.tresult,
};

pub const IContextMenu = extern struct {
    vtable: *const IContextMenuVTable,
};

pub const IContextMenuTarget = extern struct {
    vtable: *const IContextMenuTargetVTable,
};

test "context menu struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 264), @sizeOf(IContextMenuItem));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IComponentHandler3));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IContextMenuTarget));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IContextMenu));
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IComponentHandler3VTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IContextMenuTargetVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 8), @typeInfo(IContextMenuVTable).@"struct".fields.len);
}
