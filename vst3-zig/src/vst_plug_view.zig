const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");

pub fn PlugView(comptime max_platforms: usize, comptime Config: type) type {
    if (max_platforms == 0) @compileError("PlugView requires at least one platform slot");

    return extern struct {
        const Self = @This();

        iface: iplugview.IPlugView = .{ .vtable = &vtable },
        ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        platforms: [max_platforms]types.FIDString = [_]types.FIDString{iplugview.PlatformType.kPlatformTypeNSView} ** max_platforms,
        platform_count: types.uint32 = 0,
        frame: ?*iplugview.IPlugFrame = null,
        attached_parent: ?*anyopaque = null,
        attached_platform: ?types.FIDString = null,
        rect: iplugview.ViewRect = .{ .left = 0, .top = 0, .right = 400, .bottom = 300 },
        attached_count: types.uint32 = 0,
        removed_count: types.uint32 = 0,
        wheel_count: types.uint32 = 0,
        key_down_count: types.uint32 = 0,
        key_up_count: types.uint32 = 0,
        focus_count: types.uint32 = 0,
        last_wheel_distance: f32 = 0,
        last_key: types.char16 = 0,
        last_key_code: types.int16 = 0,
        last_key_modifiers: types.int16 = 0,
        has_focus: bool = false,

        pub fn asInterface(self: *Self) *iplugview.IPlugView {
            return &self.iface;
        }

        pub fn addPlatform(self: *Self, platform: types.FIDString) types.tresult {
            if (self.platform_count >= max_platforms) return types.kResultFalse;
            self.platforms[self.platform_count] = platform;
            self.platform_count += 1;
            return types.kResultOk;
        }

        fn owner(ptr: *anyopaque) *Self {
            const iface: *iplugview.IPlugView = @ptrCast(@alignCast(ptr));
            return @fieldParentPtr("iface", iface);
        }

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = ptr },
                .{ .iid = &iplugview.iplug_view_iid, .ptr = ptr },
            };
            return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
            return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
        }

        fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
            return funknown.decrementRefCount(&owner(ptr).ref_count, "IPlugView");
        }

        fn isPlatformTypeSupported(ptr: *anyopaque, platform: types.FIDString) callconv(.C) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "isPlatformTypeSupported")) return Config.isPlatformTypeSupported(self, platform);
            const count = @min(self.platform_count, max_platforms);
            for (self.platforms[0..count]) |supported| {
                if (std.mem.eql(u8, std.mem.span(supported), std.mem.span(platform))) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn attached(ptr: *anyopaque, parent: ?*anyopaque, platform: types.FIDString) callconv(.C) types.tresult {
            const self = owner(ptr);
            if (isPlatformTypeSupported(ptr, platform) != types.kResultOk) return types.kInvalidArgument;
            if (@hasDecl(Config, "attached")) {
                const result = Config.attached(self, parent, platform);
                if (result != types.kResultOk) return result;
            }
            self.attached_count += 1;
            self.attached_parent = parent;
            self.attached_platform = platform;
            return types.kResultOk;
        }

        fn removed(ptr: *anyopaque) callconv(.C) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "removed")) {
                const result = Config.removed(self);
                if (result != types.kResultOk) return result;
            }
            self.removed_count += 1;
            self.attached_parent = null;
            self.attached_platform = null;
            return types.kResultOk;
        }

        fn onWheel(ptr: *anyopaque, distance: f32) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.wheel_count += 1;
            self.last_wheel_distance = distance;
            if (@hasDecl(Config, "onWheel")) return Config.onWheel(self, distance);
            return types.kResultOk;
        }

        fn onKeyDown(ptr: *anyopaque, key: types.char16, key_code: types.int16, modifiers: types.int16) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.key_down_count += 1;
            self.last_key = key;
            self.last_key_code = key_code;
            self.last_key_modifiers = modifiers;
            if (@hasDecl(Config, "onKeyDown")) return Config.onKeyDown(self, key, key_code, modifiers);
            return types.kResultOk;
        }

        fn onKeyUp(ptr: *anyopaque, key: types.char16, key_code: types.int16, modifiers: types.int16) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.key_up_count += 1;
            self.last_key = key;
            self.last_key_code = key_code;
            self.last_key_modifiers = modifiers;
            if (@hasDecl(Config, "onKeyUp")) return Config.onKeyUp(self, key, key_code, modifiers);
            return types.kResultOk;
        }

        fn getSize(ptr: *anyopaque, out: *iplugview.ViewRect) callconv(.C) types.tresult {
            out.* = owner(ptr).rect;
            return types.kResultOk;
        }

        fn onSize(ptr: *anyopaque, rect: *iplugview.ViewRect) callconv(.C) types.tresult {
            if (@hasDecl(Config, "onSize")) {
                const result = Config.onSize(owner(ptr), rect);
                if (result != types.kResultOk) return result;
            }
            owner(ptr).rect = rect.*;
            return types.kResultOk;
        }

        fn onFocus(ptr: *anyopaque, state: types.TBool) callconv(.C) types.tresult {
            const self = owner(ptr);
            self.focus_count += 1;
            if (@hasDecl(Config, "onFocus")) {
                const result = Config.onFocus(self, state);
                if (result != types.kResultOk) return result;
            }
            self.has_focus = state != 0;
            return types.kResultOk;
        }

        fn setFrame(ptr: *anyopaque, frame: ?*iplugview.IPlugFrame) callconv(.C) types.tresult {
            if (@hasDecl(Config, "setFrame")) {
                const result = Config.setFrame(owner(ptr), frame);
                if (result != types.kResultOk) return result;
            }
            owner(ptr).frame = frame;
            return types.kResultOk;
        }

        fn canResize(_: *anyopaque) callconv(.C) types.tresult {
            if (@hasDecl(Config, "canResize")) return Config.canResize();
            return types.kResultOk;
        }

        fn checkSizeConstraint(ptr: *anyopaque, rect: *iplugview.ViewRect) callconv(.C) types.tresult {
            if (@hasDecl(Config, "checkSizeConstraint")) return Config.checkSizeConstraint(owner(ptr), rect);
            return types.kResultOk;
        }

        const vtable = iplugview.IPlugViewVTable{
            .queryInterface = query,
            .addRef = addRef,
            .release = release,
            .isPlatformTypeSupported = isPlatformTypeSupported,
            .attached = attached,
            .removed = removed,
            .onWheel = onWheel,
            .onKeyDown = onKeyDown,
            .onKeyUp = onKeyUp,
            .getSize = getSize,
            .onSize = onSize,
            .onFocus = onFocus,
            .setFrame = setFrame,
            .canResize = canResize,
            .checkSizeConstraint = checkSizeConstraint,
        };
    };
}

test "plug view stores platform attachment and removal" {
    const View = PlugView(2, struct {});
    var view = View{};
    try std.testing.expectEqual(types.kResultOk, view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView));
    try std.testing.expectEqual(types.kResultOk, view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID));
    try std.testing.expectEqual(types.kResultFalse, view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID));
    const iface = view.asInterface();

    try std.testing.expectEqual(types.kResultOk, iface.vtable.isPlatformTypeSupported(iface, iplugview.PlatformType.kPlatformTypeX11EmbedWindowID));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.isPlatformTypeSupported(iface, iplugview.PlatformType.kPlatformTypeWaylandSurfaceID));
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.attached(iface, null, iplugview.PlatformType.kPlatformTypeWaylandSurfaceID));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.attached(iface, @ptrFromInt(0x1234), iplugview.PlatformType.kPlatformTypeNSView));
    try std.testing.expectEqual(@as(types.uint32, 1), view.attached_count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1234)), view.attached_parent);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.removed(iface));
    try std.testing.expectEqual(@as(types.uint32, 1), view.removed_count);
    try std.testing.expectEqual(@as(?*anyopaque, null), view.attached_parent);
}

test "plug view tracks input size focus and frame state" {
    const View = PlugView(1, struct {});
    var view = View{};
    try std.testing.expectEqual(types.kResultOk, view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView));
    const iface = view.asInterface();

    var rect = iplugview.ViewRect{ .left = 0, .top = 0, .right = 640, .bottom = 480 };
    try std.testing.expectEqual(types.kResultOk, iface.vtable.onSize(iface, &rect));
    var size = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, iface.vtable.getSize(iface, &size));
    try std.testing.expectEqual(rect, size);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.onWheel(iface, -1.5));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.onKeyDown(iface, 'a', 12, 3));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.onKeyUp(iface, 'a', 12, 3));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.onFocus(iface, 1));
    try std.testing.expectEqual(@as(types.uint32, 1), view.wheel_count);
    try std.testing.expectEqual(@as(types.uint32, 1), view.key_down_count);
    try std.testing.expectEqual(@as(types.uint32, 1), view.key_up_count);
    try std.testing.expect(view.has_focus);
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setFrame(iface, null));
    try std.testing.expectEqual(@as(?*iplugview.IPlugFrame, null), view.frame);
}

test "plug view preserves accepted state when delegated hooks reject changes" {
    const View = PlugView(1, struct {
        pub fn attached(_: anytype, _: ?*anyopaque, _: types.FIDString) types.tresult {
            return types.kResultFalse;
        }

        pub fn removed(_: anytype) types.tresult {
            return types.kResultFalse;
        }

        pub fn onFocus(_: anytype, _: types.TBool) types.tresult {
            return types.kResultFalse;
        }

        pub fn setFrame(_: anytype, _: ?*iplugview.IPlugFrame) types.tresult {
            return types.kResultFalse;
        }
    });
    var view = View{};
    try std.testing.expectEqual(types.kResultOk, view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView));
    const iface = view.asInterface();

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.attached(iface, @ptrFromInt(0x1234), iplugview.PlatformType.kPlatformTypeNSView));
    try std.testing.expectEqual(@as(types.uint32, 0), view.attached_count);
    try std.testing.expectEqual(@as(?*anyopaque, null), view.attached_parent);
    view.attached_parent = @ptrFromInt(0x1234);
    view.attached_platform = iplugview.PlatformType.kPlatformTypeNSView;
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.removed(iface));
    try std.testing.expectEqual(@as(types.uint32, 0), view.removed_count);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1234)), view.attached_parent);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.onFocus(iface, 1));
    try std.testing.expect(!view.has_focus);
    try std.testing.expectEqual(@as(types.uint32, 1), view.focus_count);

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setFrame(iface, @ptrFromInt(0x1234)));
    try std.testing.expectEqual(@as(?*iplugview.IPlugFrame, null), view.frame);
}

test "plug view delegates size constraints and query interface" {
    const View = PlugView(1, struct {
        pub fn canResize() types.tresult {
            return types.kResultFalse;
        }

        pub fn checkSizeConstraint(_: anytype, rect: *iplugview.ViewRect) types.tresult {
            rect.right = rect.left + 320;
            rect.bottom = rect.top + 200;
            return types.kResultOk;
        }
    });
    var view = View{};
    const iface = view.asInterface();
    var rect = iplugview.ViewRect{ .left = 10, .top = 20, .right = 30, .bottom = 40 };

    try std.testing.expectEqual(types.kResultFalse, iface.vtable.canResize(iface));
    try std.testing.expectEqual(types.kResultOk, iface.vtable.checkSizeConstraint(iface, &rect));
    try std.testing.expectEqual(@as(types.int32, 330), rect.right);
    try std.testing.expectEqual(@as(types.int32, 220), rect.bottom);

    var queried: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &iplugview.iplug_view_iid, &queried));
    try std.testing.expect(queried != null);
    const queried_view: *iplugview.IPlugView = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_view.vtable.release(queried_view));
}
