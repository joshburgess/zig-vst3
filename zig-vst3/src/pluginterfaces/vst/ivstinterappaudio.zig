const base_types = @import("../base/types.zig");
const events = @import("ivstevents.zig");
const iplugview = @import("../gui/iplugview.zig");
const tuid = @import("../../tuid.zig");

pub const iinter_app_audio_host_iid = tuid.inlineUid(0x0CE5743D, 0x68DF415E, 0xAE285BD4, 0xE2CDC8FD);
pub const iinter_app_audio_connection_notification_iid = tuid.inlineUid(0x6020C72D, 0x5FC24AA1, 0xB0950DB5, 0xD7D6D5CF);
pub const iinter_app_audio_preset_manager_iid = tuid.inlineUid(0xADE6FCC4, 0x46C94E1D, 0xB3B49A80, 0xC93FEFDD);

pub const IInterAppAudioHostVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    getScreenSize: *const fn (*anyopaque, *iplugview.ViewRect, *f32) callconv(.c) base_types.tresult,
    connectedToHost: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    switchToHost: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    sendRemoteControlEvent: *const fn (*anyopaque, base_types.uint32) callconv(.c) base_types.tresult,
    getHostIcon: *const fn (*anyopaque, *?*anyopaque) callconv(.c) base_types.tresult,
    scheduleEventFromUI: *const fn (*anyopaque, *events.Event) callconv(.c) base_types.tresult,
    createPresetManager: *const fn (*anyopaque, *const tuid.TUID) callconv(.c) ?*IInterAppAudioPresetManager,
    showSettingsView: *const fn (*anyopaque) callconv(.c) base_types.tresult,
};

pub const IInterAppAudioConnectionNotificationVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    onInterAppAudioConnectionStateChange: *const fn (*anyopaque, base_types.TBool) callconv(.c) void,
};

pub const IInterAppAudioPresetManagerVTable = extern struct {
    queryInterface: *const fn (*anyopaque, *const tuid.TUID, *?*anyopaque) callconv(.c) base_types.tresult,
    addRef: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    release: *const fn (*anyopaque) callconv(.c) base_types.uint32,
    runLoadPresetBrowser: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    runSavePresetBrowser: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    loadNextPreset: *const fn (*anyopaque) callconv(.c) base_types.tresult,
    loadPreviousPreset: *const fn (*anyopaque) callconv(.c) base_types.tresult,
};

pub const IInterAppAudioHost = extern struct {
    vtable: *const IInterAppAudioHostVTable,
};

pub const IInterAppAudioConnectionNotification = extern struct {
    vtable: *const IInterAppAudioConnectionNotificationVTable,
};

pub const IInterAppAudioPresetManager = extern struct {
    vtable: *const IInterAppAudioPresetManagerVTable,
};

test "inter-app audio vtable sizes match SDK layout" {
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IInterAppAudioHost));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IInterAppAudioConnectionNotification));
    try @import("std").testing.expectEqual(@as(usize, @sizeOf(usize)), @sizeOf(IInterAppAudioPresetManager));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IInterAppAudioHost));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IInterAppAudioConnectionNotification));
    try @import("std").testing.expectEqual(@as(usize, @alignOf(usize)), @alignOf(IInterAppAudioPresetManager));
    try @import("std").testing.expectEqual(@as(usize, 11), @typeInfo(IInterAppAudioHostVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 4), @typeInfo(IInterAppAudioConnectionNotificationVTable).@"struct".fields.len);
    try @import("std").testing.expectEqual(@as(usize, 7), @typeInfo(IInterAppAudioPresetManagerVTable).@"struct".fields.len);
}
