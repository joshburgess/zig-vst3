const base_types = @import("../base/types.zig");
const iplugview = @import("iplugview.zig");
const tuid = @import("../../tuid.zig");

pub const iwayland_host_iid = tuid.inlineUid(0x5E9582EE, 0x86594652, 0xB213678E, 0x7F1A705E);
pub const iwayland_frame_iid = tuid.inlineUid(0x809FAEC6, 0x231C4FFA, 0x98ED046C, 0x6E9E2003);

pub const wl_display = opaque {};
pub const wl_surface = opaque {};
pub const xdg_surface = opaque {};
pub const xdg_toplevel = opaque {};

pub const IWaylandHostVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    openWaylandConnection: *const fn (*anyopaque) callconv(.C) ?*wl_display,
    closeWaylandConnection: *const fn (*anyopaque, ?*wl_display) callconv(.C) base_types.tresult,
};

pub const IWaylandFrameVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    getWaylandSurface: *const fn (*anyopaque, ?*wl_display) callconv(.C) ?*wl_surface,
    getParentSurface: *const fn (*anyopaque, *iplugview.ViewRect, ?*wl_display) callconv(.C) ?*xdg_surface,
    getParentToplevel: *const fn (*anyopaque, ?*wl_display) callconv(.C) ?*xdg_toplevel,
};

pub const IWaylandHost = extern struct {
    vtable: *const IWaylandHostVTable,
};

pub const IWaylandFrame = extern struct {
    vtable: *const IWaylandFrameVTable,
};

test "wayland frame vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 5), @typeInfo(IWaylandHostVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 6), @typeInfo(IWaylandFrameVTable).@"struct".fields.len);
}
