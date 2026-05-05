const base_types = @import("../base/types.zig");
const tuid = @import("../../tuid.zig");

pub const iplug_view_iid = tuid.inlineUid(0x5BC32507, 0xD06049EA, 0xA6151B52, 0x2B755B29);
pub const iplug_frame_iid = tuid.inlineUid(0x367FAF01, 0xAFA94693, 0x8D4DA2A0, 0xED0882A3);
pub const ievent_handler_iid = tuid.inlineUid(0x561E65C9, 0x13A0496F, 0x813A2C35, 0x654D7983);
pub const itimer_handler_iid = tuid.inlineUid(0x10BDD94F, 0x41424774, 0x821FAD8F, 0xECA72CA9);
pub const irun_loop_iid = tuid.inlineUid(0x18C35366, 0x97764F1A, 0x9C5B8385, 0x7A871389);

pub const ViewRect = extern struct {
    left: base_types.int32 = 0,
    top: base_types.int32 = 0,
    right: base_types.int32 = 0,
    bottom: base_types.int32 = 0,
};

pub const PlatformType = struct {
    pub const kPlatformTypeHWND: base_types.FIDString = "HWND";
    pub const kPlatformTypeHIView: base_types.FIDString = "HIView";
    pub const kPlatformTypeNSView: base_types.FIDString = "NSView";
    pub const kPlatformTypeUIView: base_types.FIDString = "UIView";
    pub const kPlatformTypeX11EmbedWindowID: base_types.FIDString = "X11EmbedWindowID";
    pub const kPlatformTypeWaylandSurfaceID: base_types.FIDString = "WaylandSurfaceID";
};

pub const IPlugViewVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    isPlatformTypeSupported: *const fn (*anyopaque, base_types.FIDString) callconv(.C) base_types.tresult,
    attached: *const fn (*anyopaque, ?*anyopaque, base_types.FIDString) callconv(.C) base_types.tresult,
    removed: *const fn (*anyopaque) callconv(.C) base_types.tresult,
    onWheel: *const fn (*anyopaque, f32) callconv(.C) base_types.tresult,
    onKeyDown: *const fn (*anyopaque, base_types.char16, base_types.int16, base_types.int16) callconv(.C) base_types.tresult,
    onKeyUp: *const fn (*anyopaque, base_types.char16, base_types.int16, base_types.int16) callconv(.C) base_types.tresult,
    getSize: *const fn (*anyopaque, *ViewRect) callconv(.C) base_types.tresult,
    onSize: *const fn (*anyopaque, *ViewRect) callconv(.C) base_types.tresult,
    onFocus: *const fn (*anyopaque, base_types.TBool) callconv(.C) base_types.tresult,
    setFrame: *const fn (*anyopaque, ?*IPlugFrame) callconv(.C) base_types.tresult,
    canResize: *const fn (*anyopaque) callconv(.C) base_types.tresult,
    checkSizeConstraint: *const fn (*anyopaque, *ViewRect) callconv(.C) base_types.tresult,
};

pub const IPlugView = extern struct {
    vtable: *const IPlugViewVTable,
};

pub const IPlugFrameVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
    resizeView: *const fn (*anyopaque, ?*IPlugView, *ViewRect) callconv(.C) base_types.tresult,
};

pub const IPlugFrame = extern struct {
    vtable: *const IPlugFrameVTable,
};

pub const Linux = struct {
    pub const TimerInterval = base_types.uint64;
    pub const FileDescriptor = c_int;

    pub const IEventHandlerVTable = extern struct {
        queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
        addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        onFDIsSet: *const fn (*anyopaque, FileDescriptor) callconv(.C) void,
    };

    pub const IEventHandler = extern struct {
        vtable: *const IEventHandlerVTable,
    };

    pub const ITimerHandlerVTable = extern struct {
        queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
        addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        onTimer: *const fn (*anyopaque) callconv(.C) void,
    };

    pub const ITimerHandler = extern struct {
        vtable: *const ITimerHandlerVTable,
    };

    pub const IRunLoopVTable = extern struct {
        queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.C) base_types.tresult,
        addRef: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        release: *const fn (*anyopaque) callconv(.C) base_types.uint32,
        registerEventHandler: *const fn (*anyopaque, ?*IEventHandler, FileDescriptor) callconv(.C) base_types.tresult,
        unregisterEventHandler: *const fn (*anyopaque, ?*IEventHandler) callconv(.C) base_types.tresult,
        registerTimer: *const fn (*anyopaque, ?*ITimerHandler, TimerInterval) callconv(.C) base_types.tresult,
        unregisterTimer: *const fn (*anyopaque, ?*ITimerHandler) callconv(.C) base_types.tresult,
    };

    pub const IRunLoop = extern struct {
        vtable: *const IRunLoopVTable,
    };
};

test "plug view struct sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, 16), @sizeOf(ViewRect));
    try @import("std").testing.expectEqual(@as(usize, 15), @typeInfo(IPlugViewVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IPlugFrameVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(Linux.IEventHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(Linux.ITimerHandlerVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(Linux.IRunLoopVTable).@"struct".fields.len);
}
