const std = @import("std");
const funknown = @import("funknown.zig");
const interface_map = @import("interface_map.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const scale_support = @import("pluginterfaces/gui/iplugviewcontentscalesupport.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_index = @import("vst_index.zig");

fn validViewRect(rect: iplugview.ViewRect) bool {
    const width = @as(i64, rect.right) - @as(i64, rect.left);
    const height = @as(i64, rect.bottom) - @as(i64, rect.top);
    return width > 0 and width <= std.math.maxInt(types.int32) and
        height > 0 and height <= std.math.maxInt(types.int32);
}

pub fn PlugView(comptime max_platforms: usize, comptime Config: type) type {
    if (max_platforms == 0) @compileError("PlugView requires at least one platform slot");
    vst_index.requireUint32Capacity(max_platforms, "PlugView platform capacity");

    return struct {
        const Self = @This();

        iface: iplugview.IPlugView = .{ .vtable = &vtable },
        scale_iface: scale_support.IPlugViewContentScaleSupport = .{ .vtable = &scale_vtable },
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
        owned: bool = false,
        context: ?*anyopaque = null,
        owner_context: ?*anyopaque = null,
        scale_factor: scale_support.ScaleFactor = 1.0,

        pub fn create() ?*Self {
            const self = std.heap.page_allocator.create(Self) catch return null;
            self.* = .{ .owned = true };
            return self;
        }

        pub fn asInterface(self: *Self) *iplugview.IPlugView {
            return &self.iface;
        }

        fn safePlatformCount(self: *const Self) usize {
            return vst_index.clampedCountU32(self.platform_count, max_platforms);
        }

        fn appendPlatformIndex(self: *Self, platform: types.FIDString) ?usize {
            const index = vst_index.appendIndexU32(self.platform_count, max_platforms) orelse return null;
            self.platforms[index] = platform;
            self.platform_count = vst_index.uint32NextCount(index);
            return index;
        }

        pub fn addPlatform(self: *Self, platform: types.FIDString) types.tresult {
            _ = self.appendPlatformIndex(platform) orelse return types.kResultFalse;
            return types.kResultOk;
        }

        pub fn requestResize(self: *Self, requested: iplugview.ViewRect) types.tresult {
            var constrained = requested;
            const constraint_result = checkSizeConstraint(&self.iface, &constrained);
            if (constraint_result != types.kResultOk) return constraint_result;
            const frame = self.frame orelse return types.kResultFalse;
            return frame.vtable.resizeView(frame, &self.iface, &constrained);
        }

        fn acceptAttachment(self: *Self, parent: ?*anyopaque, platform: types.FIDString) void {
            self.attached_count +|= 1;
            self.attached_parent = parent;
            self.attached_platform = platform;
        }

        fn acceptRemoval(self: *Self) void {
            self.removed_count +|= 1;
            self.attached_parent = null;
            self.attached_platform = null;
        }

        fn acceptKey(self: *Self, key: types.char16, key_code: types.int16, modifiers: types.int16) void {
            self.last_key = key;
            self.last_key_code = key_code;
            self.last_key_modifiers = modifiers;
        }

        fn acceptWheel(self: *Self, distance: f32) void {
            self.last_wheel_distance = distance;
        }

        fn acceptSize(self: *Self, rect: *const iplugview.ViewRect) void {
            self.rect = rect.*;
        }

        fn acceptFocus(self: *Self, state: types.TBool) void {
            self.has_focus = state != 0;
        }

        fn acceptFrame(self: *Self, frame: ?*iplugview.IPlugFrame) void {
            self.frame = frame;
        }

        const owner = interface_map.ownerFromField(Self, iplugview.IPlugView, "iface");
        const ownerFromScale = interface_map.ownerFromField(Self, scale_support.IPlugViewContentScaleSupport, "scale_iface");

        fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryInstance(owner(ptr), ptr, addRef, requested_iid, out);
        }

        fn queryFromScale(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            return queryInstance(ownerFromScale(ptr), ptr, addRefFromScale, requested_iid, out);
        }

        fn queryInstance(self: *Self, ptr: *anyopaque, add_ref: *const fn (*anyopaque) callconv(.c) types.uint32, requested_iid: *const tuid.TUID, out: *?*anyopaque) types.tresult {
            const entries = [_]interface_map.Entry{
                interface_map.fieldEntry("iface", self, &funknown.iid),
                interface_map.fieldEntry("iface", self, &iplugview.iplug_view_iid),
                interface_map.fieldEntry("scale_iface", self, &scale_support.iplug_view_content_scale_support_iid),
            };
            return interface_map.queryWithAddRef(ptr, add_ref, &entries, requested_iid, out);
        }

        fn addRef(ptr: *anyopaque) callconv(.c) types.uint32 {
            return funknown.incrementRefCount(&owner(ptr).ref_count, "FUnknown");
        }

        fn release(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = owner(ptr);
            const next = funknown.decrementRefCount(&self.ref_count, "IPlugView");
            if (next == 0 and self.owned) {
                _ = self.ref_count.load(.acquire);
                if (@hasDecl(Config, "destroy")) Config.destroy(self);
                std.heap.page_allocator.destroy(self);
            }
            return next;
        }

        fn addRefFromScale(ptr: *anyopaque) callconv(.c) types.uint32 {
            return addRef(&ownerFromScale(ptr).iface);
        }

        fn releaseFromScale(ptr: *anyopaque) callconv(.c) types.uint32 {
            return release(&ownerFromScale(ptr).iface);
        }

        fn setContentScaleFactor(ptr: *anyopaque, factor: scale_support.ScaleFactor) callconv(.c) types.tresult {
            const self = ownerFromScale(ptr);
            if (!std.math.isFinite(factor) or factor <= 0) return types.kInvalidArgument;
            if (@hasDecl(Config, "setContentScaleFactor")) {
                const result = Config.setContentScaleFactor(self, factor);
                if (result != types.kResultOk) return result;
            }
            self.scale_factor = factor;
            return types.kResultOk;
        }

        fn isPlatformTypeSupported(ptr: *anyopaque, platform: types.FIDString) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "isPlatformTypeSupported")) return Config.isPlatformTypeSupported(self, platform);
            for (self.platforms[0..self.safePlatformCount()]) |supported| {
                if (std.mem.eql(u8, std.mem.span(supported), std.mem.span(platform))) return types.kResultOk;
            }
            return types.kResultFalse;
        }

        fn attached(ptr: *anyopaque, parent: ?*anyopaque, platform: types.FIDString) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (isPlatformTypeSupported(ptr, platform) != types.kResultOk) return types.kInvalidArgument;
            if (@hasDecl(Config, "attached")) {
                const result = Config.attached(self, parent, platform);
                if (result != types.kResultOk) return result;
            }
            self.acceptAttachment(parent, platform);
            return types.kResultOk;
        }

        fn removed(ptr: *anyopaque) callconv(.c) types.tresult {
            const self = owner(ptr);
            if (@hasDecl(Config, "removed")) {
                const result = Config.removed(self);
                if (result != types.kResultOk) return result;
            }
            self.acceptRemoval();
            return types.kResultOk;
        }

        fn onWheel(ptr: *anyopaque, distance: f32) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.wheel_count +|= 1;
            if (@hasDecl(Config, "onWheel")) {
                const result = Config.onWheel(self, distance);
                if (result != types.kResultOk) return result;
            }
            self.acceptWheel(distance);
            return types.kResultOk;
        }

        fn onKeyDown(ptr: *anyopaque, key: types.char16, key_code: types.int16, modifiers: types.int16) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.key_down_count +|= 1;
            if (@hasDecl(Config, "onKeyDown")) {
                const result = Config.onKeyDown(self, key, key_code, modifiers);
                if (result != types.kResultOk) return result;
            }
            self.acceptKey(key, key_code, modifiers);
            return types.kResultOk;
        }

        fn onKeyUp(ptr: *anyopaque, key: types.char16, key_code: types.int16, modifiers: types.int16) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.key_up_count +|= 1;
            if (@hasDecl(Config, "onKeyUp")) {
                const result = Config.onKeyUp(self, key, key_code, modifiers);
                if (result != types.kResultOk) return result;
            }
            self.acceptKey(key, key_code, modifiers);
            return types.kResultOk;
        }

        fn getSize(ptr: *anyopaque, out: *iplugview.ViewRect) callconv(.c) types.tresult {
            out.* = owner(ptr).rect;
            return types.kResultOk;
        }

        fn onSize(ptr: *anyopaque, rect: *iplugview.ViewRect) callconv(.c) types.tresult {
            const requested = rect.*;
            if (!validViewRect(requested)) return types.kInvalidArgument;
            if (@hasDecl(Config, "onSize")) {
                const result = Config.onSize(owner(ptr), rect);
                if (result != types.kResultOk) {
                    rect.* = requested;
                    return result;
                }
            }
            if (!validViewRect(rect.*)) {
                rect.* = requested;
                return types.kInvalidArgument;
            }
            owner(ptr).acceptSize(rect);
            return types.kResultOk;
        }

        fn onFocus(ptr: *anyopaque, state: types.TBool) callconv(.c) types.tresult {
            const self = owner(ptr);
            self.focus_count +|= 1;
            if (@hasDecl(Config, "onFocus")) {
                const result = Config.onFocus(self, state);
                if (result != types.kResultOk) return result;
            }
            self.acceptFocus(state);
            return types.kResultOk;
        }

        fn setFrame(ptr: *anyopaque, frame: ?*iplugview.IPlugFrame) callconv(.c) types.tresult {
            if (@hasDecl(Config, "setFrame")) {
                const result = Config.setFrame(owner(ptr), frame);
                if (result != types.kResultOk) return result;
            }
            owner(ptr).acceptFrame(frame);
            return types.kResultOk;
        }

        fn canResize(_: *anyopaque) callconv(.c) types.tresult {
            if (@hasDecl(Config, "canResize")) return Config.canResize();
            return types.kResultOk;
        }

        fn checkSizeConstraint(ptr: *anyopaque, rect: *iplugview.ViewRect) callconv(.c) types.tresult {
            const requested = rect.*;
            if (!validViewRect(requested)) return types.kInvalidArgument;
            if (@hasDecl(Config, "checkSizeConstraint")) {
                const result = Config.checkSizeConstraint(owner(ptr), rect);
                if (result != types.kResultOk) {
                    rect.* = requested;
                    return result;
                }
            }
            if (!validViewRect(rect.*)) {
                rect.* = requested;
                return types.kInvalidArgument;
            }
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

        const scale_vtable = scale_support.IPlugViewContentScaleSupportVTable{
            .queryInterface = queryFromScale,
            .addRef = addRefFromScale,
            .release = releaseFromScale,
            .setContentScaleFactor = setContentScaleFactor,
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

test "plug view exposes content scale support with shared lifetime" {
    const View = PlugView(1, struct {});
    var view = View{};
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, view.iface.vtable.queryInterface(&view.iface, &scale_support.iplug_view_content_scale_support_iid, &out));
    const scale: *scale_support.IPlugViewContentScaleSupport = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(types.kResultOk, scale.vtable.setContentScaleFactor(scale, 2.0));
    try std.testing.expectEqual(@as(scale_support.ScaleFactor, 2.0), view.scale_factor);
    try std.testing.expectEqual(types.kInvalidArgument, scale.vtable.setContentScaleFactor(scale, 0.0));
    try std.testing.expectEqual(@as(types.uint32, 1), scale.vtable.release(scale));
}

test "plug view clamps inflated platform counts" {
    const View = PlugView(1, struct {});
    var view = View{};
    const iface = view.asInterface();
    view.platforms[0] = iplugview.PlatformType.kPlatformTypeNSView;
    view.platform_count = 99;

    try std.testing.expectEqual(types.kResultOk, iface.vtable.isPlatformTypeSupported(iface, iplugview.PlatformType.kPlatformTypeNSView));
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.isPlatformTypeSupported(iface, iplugview.PlatformType.kPlatformTypeWaylandSurfaceID));
    try std.testing.expectEqual(types.kResultFalse, view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID));
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

test "plug view requests constrained host resize" {
    const Frame = @import("vst_plug_frame.zig").PlugFrame(struct {
        pub fn resizeView(_: ?*iplugview.IPlugView, rect: *iplugview.ViewRect) types.tresult {
            return if (rect.right == 600 and rect.bottom == 400) types.kResultOk else types.kResultFalse;
        }
    });
    const View = PlugView(1, struct {
        pub fn checkSizeConstraint(_: anytype, rect: *iplugview.ViewRect) types.tresult {
            rect.right = std.math.clamp(rect.right, 320, 600);
            rect.bottom = std.math.clamp(rect.bottom, 240, 400);
            return types.kResultOk;
        }
    });
    var frame = Frame{};
    var view = View{};
    try std.testing.expectEqual(types.kResultFalse, view.requestResize(.{ .right = 800, .bottom = 600 }));
    try std.testing.expectEqual(types.kResultOk, view.iface.vtable.setFrame(&view.iface, frame.asInterface()));
    try std.testing.expectEqual(types.kResultOk, view.requestResize(.{ .right = 800, .bottom = 600 }));
    try std.testing.expectEqual(@as(types.int32, 400), view.rect.right);
    try std.testing.expectEqual(@as(types.int32, 300), view.rect.bottom);
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

        pub fn onWheel(_: anytype, distance: f32) types.tresult {
            return if (distance > 0) types.kResultOk else types.kResultFalse;
        }

        pub fn onKeyDown(_: anytype, key: types.char16, _: types.int16, _: types.int16) types.tresult {
            return if (key == 'a') types.kResultOk else types.kResultFalse;
        }

        pub fn onKeyUp(_: anytype, key: types.char16, _: types.int16, _: types.int16) types.tresult {
            return if (key == 'a') types.kResultOk else types.kResultFalse;
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

    try std.testing.expectEqual(types.kResultOk, iface.vtable.onWheel(iface, 1.5));
    try std.testing.expectEqual(@as(f32, 1.5), view.last_wheel_distance);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.onWheel(iface, -1.0));
    try std.testing.expectEqual(@as(types.uint32, 2), view.wheel_count);
    try std.testing.expectEqual(@as(f32, 1.5), view.last_wheel_distance);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.onKeyDown(iface, 'a', 12, 3));
    try std.testing.expectEqual(@as(types.char16, 'a'), view.last_key);
    try std.testing.expectEqual(@as(types.int16, 12), view.last_key_code);
    try std.testing.expectEqual(@as(types.int16, 3), view.last_key_modifiers);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.onKeyDown(iface, 'b', 13, 4));
    try std.testing.expectEqual(@as(types.uint32, 2), view.key_down_count);
    try std.testing.expectEqual(@as(types.char16, 'a'), view.last_key);
    try std.testing.expectEqual(@as(types.int16, 12), view.last_key_code);
    try std.testing.expectEqual(@as(types.int16, 3), view.last_key_modifiers);

    try std.testing.expectEqual(types.kResultOk, iface.vtable.onKeyUp(iface, 'a', 14, 5));
    try std.testing.expectEqual(@as(types.char16, 'a'), view.last_key);
    try std.testing.expectEqual(@as(types.int16, 14), view.last_key_code);
    try std.testing.expectEqual(@as(types.int16, 5), view.last_key_modifiers);
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.onKeyUp(iface, 'b', 15, 6));
    try std.testing.expectEqual(@as(types.uint32, 2), view.key_up_count);
    try std.testing.expectEqual(@as(types.char16, 'a'), view.last_key);
    try std.testing.expectEqual(@as(types.int16, 14), view.last_key_code);
    try std.testing.expectEqual(@as(types.int16, 5), view.last_key_modifiers);

    var frame = iplugview.IPlugFrame{ .vtable = undefined };
    try std.testing.expectEqual(types.kResultFalse, iface.vtable.setFrame(iface, &frame));
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

    queried = null;
    try std.testing.expectEqual(types.kResultOk, iface.vtable.queryInterface(iface, &funknown.iid, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, iface), queried);
    try std.testing.expectEqual(@as(types.uint32, 2), view.ref_count.load(.seq_cst));
    const queried_unknown: *iplugview.IPlugView = @ptrCast(@alignCast(queried.?));
    try std.testing.expectEqual(@as(types.uint32, 1), queried_unknown.vtable.release(queried_unknown));
}

test "plug view rejects malformed resize rectangles before delegation" {
    const Frame = @import("vst_plug_frame.zig").PlugFrame(struct {});
    const Config = struct {
        var size_calls: usize = 0;
        var constraint_calls: usize = 0;

        pub fn onSize(_: anytype, _: *iplugview.ViewRect) types.tresult {
            size_calls += 1;
            return types.kResultOk;
        }

        pub fn checkSizeConstraint(_: anytype, _: *iplugview.ViewRect) types.tresult {
            constraint_calls += 1;
            return types.kResultOk;
        }
    };
    const View = PlugView(1, Config);
    var frame = Frame{};
    var view = View{};
    const iface = view.asInterface();
    try std.testing.expectEqual(types.kResultOk, iface.vtable.setFrame(iface, frame.asInterface()));
    const accepted = view.rect;
    const malformed = [_]iplugview.ViewRect{
        .{ .left = 10, .top = 0, .right = 10, .bottom = 100 },
        .{ .left = 20, .top = 0, .right = 10, .bottom = 100 },
        .{ .left = std.math.minInt(types.int32), .top = 0, .right = std.math.maxInt(types.int32), .bottom = 100 },
    };

    for (malformed) |input| {
        var rect = input;
        try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.onSize(iface, &rect));
        try std.testing.expectEqual(input, rect);
        try std.testing.expectEqual(accepted, view.rect);

        try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.checkSizeConstraint(iface, &rect));
        try std.testing.expectEqual(input, rect);
        try std.testing.expectEqual(types.kInvalidArgument, view.requestResize(input));
    }
    try std.testing.expectEqual(@as(usize, 0), Config.size_calls);
    try std.testing.expectEqual(@as(usize, 0), Config.constraint_calls);
    try std.testing.expectEqual(@as(types.uint32, 0), frame.resize_count);
}

test "plug view rejects malformed rectangles produced by delegated hooks" {
    const Config = struct {
        pub fn onSize(_: anytype, rect: *iplugview.ViewRect) types.tresult {
            rect.right = rect.left;
            return types.kResultOk;
        }

        pub fn checkSizeConstraint(_: anytype, rect: *iplugview.ViewRect) types.tresult {
            rect.bottom = rect.top - 1;
            return types.kResultOk;
        }
    };
    const View = PlugView(1, Config);
    var view = View{};
    const iface = view.asInterface();
    const accepted = view.rect;
    const requested = iplugview.ViewRect{ .left = 10, .top = 20, .right = 650, .bottom = 500 };

    var size = requested;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.onSize(iface, &size));
    try std.testing.expectEqual(requested, size);
    try std.testing.expectEqual(accepted, view.rect);

    var constrained = requested;
    try std.testing.expectEqual(types.kInvalidArgument, iface.vtable.checkSizeConstraint(iface, &constrained));
    try std.testing.expectEqual(requested, constrained);
}

test "plug view clears unsupported query output" {
    const View = PlugView(1, struct {});
    var view = View{};
    const iface = view.asInterface();

    var queried: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, iface.vtable.queryInterface(iface, &tuid.zero, &queried));
    try std.testing.expectEqual(@as(?*anyopaque, null), queried);
}
