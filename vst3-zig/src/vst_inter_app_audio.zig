const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const ivstinterappaudio = @import("pluginterfaces/vst/ivstinterappaudio.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstinterappaudio.iinter_app_audio_connection_notification_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IInterAppAudioConnectionNotification");
        }

        fn onInterAppAudioConnectionStateChange(ptr: *anyopaque, state: types.TBool) callconv(.C) void {
            const self = owner(ptr);
            self.connected = state != 0;
            self.change_count += 1;
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

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &ivstinterappaudio.iinter_app_audio_preset_manager_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IInterAppAudioPresetManager");
        }

        fn runLoadPresetBrowser(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.load_browser_count += 1;
            if (@hasDecl(Config, "runLoadPresetBrowser")) return Config.runLoadPresetBrowser(self);
            return types.kResultOk;
        }

        fn runSavePresetBrowser(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.save_browser_count += 1;
            if (@hasDecl(Config, "runSavePresetBrowser")) return Config.runSavePresetBrowser(self);
            return types.kResultOk;
        }

        fn loadNextPreset(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.next_count += 1;
            if (@hasDecl(Config, "loadNextPreset")) return Config.loadNextPreset(self);
            return types.kResultOk;
        }

        fn loadPreviousPreset(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.previous_count += 1;
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

test "inter-app audio connection notification supports query interface" {
    const Notification = InterAppAudioConnectionNotification(struct {});
    var notification = Notification{};
    const iface = notification.asInterface();

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &ivstinterappaudio.iinter_app_audio_connection_notification_iid, &queried));
    try std.testing.expect(queried != null);
    const out: *ivstinterappaudio.IInterAppAudioConnectionNotification = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), out.vtable.release(out));
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
}
