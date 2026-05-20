const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const events = @import("pluginterfaces/vst/ivstevents.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivstinterappaudio = @import("pluginterfaces/vst/ivstinterappaudio.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn InterAppAudioHost(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstinterappaudio.IInterAppAudioHost = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        screen: iplugview.ViewRect = .{},
        scale_factor: f32 = 1.0,
        connected_count: types.uint32 = 0,
        switch_count: types.uint32 = 0,
        settings_count: types.uint32 = 0,
        remote_control_count: types.uint32 = 0,
        last_remote_control_event: types.uint32 = 0,
        scheduled_event_count: types.uint32 = 0,
        last_preset_uid: tuid.TUID = tuid.zero,
        has_last_preset_uid: bool = false,
        host_icon: ?*anyopaque = null,
        preset_manager: ?*ivstinterappaudio.IInterAppAudioPresetManager = null,

        pub fn asInterface(self: *Self) *ivstinterappaudio.IInterAppAudioHost {
            return &self.iface;
        }

        fn recordPresetManagerRequest(self: *Self, uid: *const tuid.TUID) void {
            self.last_preset_uid = uid.*;
            self.has_last_preset_uid = true;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstinterappaudio.IInterAppAudioHost = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstinterappaudio.iinter_app_audio_host_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IInterAppAudioHost");
        }

        fn failScreenSize(self: *Self, out_rect: *iplugview.ViewRect, out_scale: *f32, result: types.tresult) types.tresult {
            out_rect.* = self.screen;
            out_scale.* = self.scale_factor;
            return result;
        }

        fn getScreenSize(ptr: *anyopaque, out_rect: *iplugview.ViewRect, out_scale: *f32) callconv(.c) types.tresult {
            const self = owner(ptr);
            out_rect.* = self.screen;
            out_scale.* = self.scale_factor;
            if (@hasDecl(Config, "getScreenSize")) {
                const result = Config.getScreenSize(self, out_rect, out_scale);
                if (result != types.kResultOk) return self.failScreenSize(out_rect, out_scale, result);
                return result;
            }
            return types.kResultOk;
        }

        fn connectedToHost(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.connected_count +|= 1;
            if (@hasDecl(Config, "connectedToHost")) return Config.connectedToHost(self);
            return types.kResultOk;
        }

        fn switchToHost(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.switch_count +|= 1;
            if (@hasDecl(Config, "switchToHost")) return Config.switchToHost(self);
            return types.kResultOk;
        }

        fn sendRemoteControlEvent(ptr: *anyopaque, event_id: types.uint32) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.remote_control_count +|= 1;
            if (@hasDecl(Config, "sendRemoteControlEvent")) {
                const result = Config.sendRemoteControlEvent(self, event_id);
                if (result != types.kResultOk) return result;
            }
            self.last_remote_control_event = event_id;
            return types.kResultOk;
        }

        fn failHostIcon(self: *Self, out_icon: *?*anyopaque, result: types.tresult) types.tresult {
            out_icon.* = self.host_icon;
            return result;
        }

        fn getHostIcon(ptr: *anyopaque, out_icon: *?*anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            out_icon.* = self.host_icon;
            if (@hasDecl(Config, "getHostIcon")) {
                const result = Config.getHostIcon(self, out_icon);
                if (result != types.kResultOk) return self.failHostIcon(out_icon, result);
                return result;
            }
            return if (self.host_icon == null) types.kResultFalse else types.kResultOk;
        }

        fn scheduleEventFromUI(ptr: *anyopaque, event: *events.Event) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.scheduled_event_count +|= 1;
            if (@hasDecl(Config, "scheduleEventFromUI")) return Config.scheduleEventFromUI(self, event);
            return types.kResultOk;
        }

        fn createPresetManager(ptr: *anyopaque, uid: *const tuid.TUID) callconv(.c) ?*ivstinterappaudio.IInterAppAudioPresetManager {
            const self = owner(ptr);
            self.recordPresetManagerRequest(uid);
            if (@hasDecl(Config, "createPresetManager")) return Config.createPresetManager(self, uid);
            return self.preset_manager;
        }

        fn showSettingsView(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.settings_count +|= 1;
            if (@hasDecl(Config, "showSettingsView")) return Config.showSettingsView(self);
            return types.kResultOk;
        }

        const vtable = ivstinterappaudio.IInterAppAudioHostVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .getScreenSize = getScreenSize,
            .connectedToHost = connectedToHost,
            .switchToHost = switchToHost,
            .sendRemoteControlEvent = sendRemoteControlEvent,
            .getHostIcon = getHostIcon,
            .scheduleEventFromUI = scheduleEventFromUI,
            .createPresetManager = createPresetManager,
            .showSettingsView = showSettingsView,
        };
    };
}

pub fn InterAppAudioConnectionNotification(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstinterappaudio.IInterAppAudioConnectionNotification = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        connected: bool = false,
        change_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ivstinterappaudio.IInterAppAudioConnectionNotification {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstinterappaudio.IInterAppAudioConnectionNotification = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstinterappaudio.iinter_app_audio_connection_notification_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IInterAppAudioConnectionNotification");
        }

        fn onInterAppAudioConnectionStateChange(ptr: *anyopaque, state: types.TBool) callconv(.c) void {
            const self = owner(ptr);
            self.connected = state != 0;
            self.change_count +|= 1;
            if (@hasDecl(Config, "onInterAppAudioConnectionStateChange")) {
                Config.onInterAppAudioConnectionStateChange(self, self.connected);
            }
        }

        const vtable = ivstinterappaudio.IInterAppAudioConnectionNotificationVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .onInterAppAudioConnectionStateChange = onInterAppAudioConnectionStateChange,
        };
    };
}

pub fn InterAppAudioPresetManager(comptime Config: type) type {
    return extern struct {
        const Self = @This();

        iface: ivstinterappaudio.IInterAppAudioPresetManager = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        load_browser_count: types.uint32 = 0,
        save_browser_count: types.uint32 = 0,
        next_count: types.uint32 = 0,
        previous_count: types.uint32 = 0,

        pub fn asInterface(self: *Self) *ivstinterappaudio.IInterAppAudioPresetManager {
            return &self.iface;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *ivstinterappaudio.IInterAppAudioPresetManager = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstinterappaudio.iinter_app_audio_preset_manager_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IInterAppAudioPresetManager");
        }

        fn runLoadPresetBrowser(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.load_browser_count +|= 1;
            if (@hasDecl(Config, "runLoadPresetBrowser")) return Config.runLoadPresetBrowser(self);
            return types.kResultOk;
        }

        fn runSavePresetBrowser(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.save_browser_count +|= 1;
            if (@hasDecl(Config, "runSavePresetBrowser")) return Config.runSavePresetBrowser(self);
            return types.kResultOk;
        }

        fn loadNextPreset(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.next_count +|= 1;
            if (@hasDecl(Config, "loadNextPreset")) return Config.loadNextPreset(self);
            return types.kResultOk;
        }

        fn loadPreviousPreset(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.previous_count +|= 1;
            if (@hasDecl(Config, "loadPreviousPreset")) return Config.loadPreviousPreset(self);
            return types.kResultOk;
        }

        const vtable = ivstinterappaudio.IInterAppAudioPresetManagerVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .runLoadPresetBrowser = runLoadPresetBrowser,
            .runSavePresetBrowser = runSavePresetBrowser,
            .loadNextPreset = loadNextPreset,
            .loadPreviousPreset = loadPreviousPreset,
        };
    };
}

test "inter-app audio host returns default state and tracks callbacks" {
    const Host = InterAppAudioHost(struct {});
    var host = Host{ .screen = .{ .left = 1, .top = 2, .right = 101, .bottom = 202 }, .scale_factor = 2.0 };
    const iface = host.asInterface();

    var screen = iplugview.ViewRect{};
    var scale: f32 = 0;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getScreenSize(iface, &screen, &scale));
    try std.testing.expectEqual(@as(types.int32, 101), screen.right);
    try std.testing.expectEqual(@as(f32, 2.0), scale);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.connectedToHost(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.switchToHost(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.sendRemoteControlEvent(iface, 42));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.showSettingsView(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.connected_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.switch_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.remote_control_count);
    try std.testing.expectEqual(@as(types.uint32, 42), host.last_remote_control_event);
    try std.testing.expectEqual(@as(types.uint32, 1), host.settings_count);
}

test "inter-app audio host returns icon and preset manager" {
    const Host = InterAppAudioHost(struct {});
    const Presets = InterAppAudioPresetManager(struct {});
    var host = Host{};
    var presets = Presets{};
    const icon: *anyopaque = @ptrFromInt(0x1000);
    const preset_uid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    host.host_icon = icon;
    host.preset_manager = presets.asInterface();
    const iface = host.asInterface();

    var out_icon: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getHostIcon(iface, &out_icon));
    try std.testing.expectEqual(icon, out_icon.?);
    try std.testing.expectEqual(presets.asInterface(), iface.vtable.createPresetManager(iface, &preset_uid).?);
    try std.testing.expect(host.has_last_preset_uid);
    try std.testing.expectEqualSlices(u8, &preset_uid, &host.last_preset_uid);
}

test "inter-app audio host delegates hooks and supports query interface" {
    const Host = InterAppAudioHost(struct {
        pub fn connectedToHost(self: anytype) types.tresult {
            _ = self;
            return types.kResultFalse;
        }

        pub fn showSettingsView(self: anytype) types.tresult {
            _ = self;
            return types.kInvalidArgument;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.connectedToHost(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.showSettingsView(iface));

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstinterappaudio.iinter_app_audio_host_iid, &queried));
    try std.testing.expect(queried != null);
    const out: *ivstinterappaudio.IInterAppAudioHost = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), out.vtable.release(out));
}

test "inter-app audio host clears unsupported query output" {
    const Host = InterAppAudioHost(struct {});
    var host = Host{};
    const iface = host.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "inter-app audio host resets delegated failure outputs" {
    const Host = InterAppAudioHost(struct {
        pub fn getScreenSize(self: anytype, out_rect: *iplugview.ViewRect, out_scale: *f32) types.tresult {
            _ = self;
            out_rect.* = .{ .left = 10, .top = 20, .right = 30, .bottom = 40 };
            out_scale.* = 9.0;
            return types.kResultFalse;
        }

        pub fn getHostIcon(self: anytype, out_icon: *?*anyopaque) types.tresult {
            _ = self;
            out_icon.* = @ptrFromInt(0x2000);
            return types.kResultFalse;
        }
    });
    var host = Host{ .screen = .{ .left = 1, .top = 2, .right = 101, .bottom = 202 }, .scale_factor = 2.0 };
    const icon: *anyopaque = @ptrFromInt(0x1000);
    host.host_icon = icon;
    const iface = host.asInterface();

    var screen = iplugview.ViewRect{};
    var scale: f32 = 0;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getScreenSize(iface, &screen, &scale));
    try std.testing.expectEqual(@as(types.int32, 1), screen.left);
    try std.testing.expectEqual(@as(types.int32, 202), screen.bottom);
    try std.testing.expectEqual(@as(f32, 2.0), scale);

    var out_icon: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.getHostIcon(iface, &out_icon));
    try std.testing.expectEqual(icon, out_icon.?);
}

test "inter-app audio host delegates scheduled UI events" {
    const Host = InterAppAudioHost(struct {
        pub fn scheduleEventFromUI(self: anytype, event: *events.Event) types.tresult {
            _ = self;
            _ = event;
            return types.kResultFalse;
        }
    });
    var host = Host{};
    const iface = host.asInterface();
    var event = events.Event{
        .sampleOffset = 128,
        .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent),
        .data = .{ .noteOn = .{ .pitch = 64, .velocity = 0.75 } },
    };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.scheduleEventFromUI(iface, &event));
    try std.testing.expectEqual(@as(types.uint32, 1), host.scheduled_event_count);
    try std.testing.expectEqual(@as(types.int32, 128), event.sampleOffset);
    try std.testing.expectEqual(@intFromEnum(events.Event.EventTypes.kNoteOnEvent), event.type);
}

test "inter-app audio host delegates remote control and preset manager creation" {
    const Presets = InterAppAudioPresetManager(struct {});
    const Host = InterAppAudioHost(struct {
        pub fn sendRemoteControlEvent(self: anytype, event_id: types.uint32) types.tresult {
            _ = self;
            _ = event_id;
            return types.kInvalidArgument;
        }

        pub fn createPresetManager(self: anytype, uid: *const tuid.TUID) ?*ivstinterappaudio.IInterAppAudioPresetManager {
            _ = uid;
            return self.preset_manager;
        }
    });
    var presets = Presets{};
    var host = Host{ .preset_manager = presets.asInterface() };
    const iface = host.asInterface();
    const preset_uid = tuid.inlineUid(0x12345678, 0x90abcdef, 0x11223344, 0x55667788);

    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.sendRemoteControlEvent(iface, 0x1234));
    try std.testing.expectEqual(@as(types.uint32, 1), host.remote_control_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.last_remote_control_event);
    try std.testing.expectEqual(presets.asInterface(), iface.vtable.createPresetManager(iface, &preset_uid).?);
    try std.testing.expect(host.has_last_preset_uid);
    try std.testing.expectEqualSlices(u8, &preset_uid, &host.last_preset_uid);
}

test "inter-app audio host preserves last accepted remote control event on rejection" {
    const Host = InterAppAudioHost(struct {
        pub fn sendRemoteControlEvent(_: anytype, event_id: types.uint32) types.tresult {
            return if (event_id == 42) types.kResultOk else types.kInvalidArgument;
        }
    });
    var host = Host{};
    const iface = host.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.sendRemoteControlEvent(iface, 42));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.sendRemoteControlEvent(iface, 99));
    try std.testing.expectEqual(@as(types.uint32, 2), host.remote_control_count);
    try std.testing.expectEqual(@as(types.uint32, 42), host.last_remote_control_event);
}

test "inter-app audio connection notification stores state" {
    const Notification = InterAppAudioConnectionNotification(struct {});
    var notification = Notification{};
    const iface = notification.asInterface();

    iface.vtable.onInterAppAudioConnectionStateChange(iface, 1);
    try std.testing.expect(notification.connected);
    try std.testing.expectEqual(@as(types.uint32, 1), notification.change_count);

    iface.vtable.onInterAppAudioConnectionStateChange(iface, 0);
    try std.testing.expect(!notification.connected);
    try std.testing.expectEqual(@as(types.uint32, 2), notification.change_count);
}

test "inter-app audio connection notification delegates state changes" {
    const NotificationConfig = struct {
        var callback_count: types.uint32 = 0;
        var last_connected = false;
        var last_change_count: types.uint32 = 0;

        pub fn onInterAppAudioConnectionStateChange(self: anytype, connected: bool) void {
            callback_count += 1;
            last_connected = connected;
            last_change_count = self.change_count;
        }
    };
    const Notification = InterAppAudioConnectionNotification(NotificationConfig);
    var notification = Notification{};
    const iface = notification.asInterface();

    iface.vtable.onInterAppAudioConnectionStateChange(iface, 1);
    try std.testing.expectEqual(@as(types.uint32, 1), NotificationConfig.callback_count);
    try std.testing.expectEqual(@as(types.uint32, 1), NotificationConfig.last_change_count);
    try std.testing.expect(NotificationConfig.last_connected);

    iface.vtable.onInterAppAudioConnectionStateChange(iface, 0);
    try std.testing.expectEqual(@as(types.uint32, 2), NotificationConfig.callback_count);
    try std.testing.expectEqual(@as(types.uint32, 2), NotificationConfig.last_change_count);
    try std.testing.expect(!NotificationConfig.last_connected);
}

test "inter-app audio connection notification supports query interface" {
    const Notification = InterAppAudioConnectionNotification(struct {});
    var notification = Notification{};
    const iface = notification.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstinterappaudio.iinter_app_audio_connection_notification_iid, &queried));
    try std.testing.expect(queried != null);
    const out: *ivstinterappaudio.IInterAppAudioConnectionNotification = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), out.vtable.release(out));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), notification.ref_count.load(.seq_cst));
    const queried_unknown: *ivstinterappaudio.IInterAppAudioConnectionNotification = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "inter-app audio connection notification clears unsupported query output" {
    const Notification = InterAppAudioConnectionNotification(struct {});
    var notification = Notification{};
    const iface = notification.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}

test "inter-app audio preset manager counts default actions" {
    const Presets = InterAppAudioPresetManager(struct {});
    var presets = Presets{};
    const iface = presets.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.runLoadPresetBrowser(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.runSavePresetBrowser(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.loadNextPreset(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.loadPreviousPreset(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), presets.load_browser_count);
    try std.testing.expectEqual(@as(types.uint32, 1), presets.save_browser_count);
    try std.testing.expectEqual(@as(types.uint32, 1), presets.next_count);
    try std.testing.expectEqual(@as(types.uint32, 1), presets.previous_count);
}

test "inter-app audio preset manager delegates hooks" {
    const Presets = InterAppAudioPresetManager(struct {
        pub fn runLoadPresetBrowser(self: anytype) types.tresult {
            _ = self;
            return types.kResultFalse;
        }

        pub fn loadNextPreset(self: anytype) types.tresult {
            _ = self;
            return types.kInvalidArgument;
        }
    });
    var presets = Presets{};
    const iface = presets.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.runLoadPresetBrowser(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.runSavePresetBrowser(iface));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.loadNextPreset(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.loadPreviousPreset(iface));
}

test "inter-app audio preset manager supports query interface" {
    const Presets = InterAppAudioPresetManager(struct {});
    var presets = Presets{};
    const iface = presets.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstinterappaudio.iinter_app_audio_preset_manager_iid, &queried));
    try std.testing.expect(queried != null);
    const out: *ivstinterappaudio.IInterAppAudioPresetManager = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), out.vtable.release(out));

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), presets.ref_count.load(.seq_cst));
    const queried_unknown: *ivstinterappaudio.IInterAppAudioPresetManager = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "inter-app audio preset manager clears unsupported query output" {
    const Presets = InterAppAudioPresetManager(struct {});
    var presets = Presets{};
    const iface = presets.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
