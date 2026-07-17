const builtin = @import("builtin");
const std = @import("std");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

const Editor = opaque {};

const Platform = enum(c_int) {
    macos,
    windows,
    x11,
    wayland,
};

pub const Callbacks = extern struct {
    userdata: ?*anyopaque,
    begin_edit: *const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void,
    perform_edit: *const fn (?*anyopaque, vsttypes.ParamID, f64) callconv(.c) types.int32,
    end_edit: *const fn (?*anyopaque, vsttypes.ParamID) callconv(.c) void,
    format_value: *const fn (?*anyopaque, vsttypes.ParamID, f64, [*]u8, types.uint32) callconv(.c) types.int32,
    parse_value: *const fn (?*anyopaque, vsttypes.ParamID, [*:0]const u8, *f64) callconv(.c) types.int32,
};

pub const ParameterInfo = extern struct {
    title: [*:0]const u8,
    step_count: types.int32,
    default_normalized: f64,
};

pub const ParameterDescription = extern struct {
    parameter_id: vsttypes.ParamID,
    initial_normalized: f64,
    info: ParameterInfo,
};

pub const ParameterValue = extern struct {
    parameter_id: vsttypes.ParamID,
    normalized: f64,
};

pub const max_parameters = 64;

pub const ObserverCallbacks = struct {
    userdata: *anyopaque,
    subscribe: *const fn (*anyopaque, *anyopaque) bool,
    unsubscribe: *const fn (*anyopaque, *anyopaque) void,
};

const ResizeCallbacks = extern struct {
    userdata: ?*anyopaque,
    request_resize: *const fn (?*anyopaque, types.uint32, types.uint32) callconv(.c) types.int32,
};

extern fn zig_vstgui_editor_create([*]const ParameterDescription, types.uint32, Callbacks) ?*Editor;
extern fn zig_vstgui_editor_open(*Editor, ?*anyopaque, Platform) types.int32;
extern fn zig_vstgui_editor_close(*Editor) void;
extern fn zig_vstgui_editor_destroy(*Editor) void;
extern fn zig_vstgui_editor_resize(*Editor, types.uint32, types.uint32) types.int32;
extern fn zig_vstgui_editor_set_scale(*Editor, f64) types.int32;
extern fn zig_vstgui_editor_set_parameter(*Editor, vsttypes.ParamID, f64) types.int32;
extern fn zig_vstgui_editor_refresh_parameters(*Editor, [*]const ParameterValue, types.uint32) types.int32;
extern fn zig_vstgui_editor_key_down(*Editor, types.char16, types.int16, types.int16) types.int32;
extern fn zig_vstgui_editor_set_focus(*Editor, types.int32) void;
extern fn zig_vstgui_editor_set_frame(*Editor, ?*iplugview.IPlugFrame) void;
extern fn zig_vstgui_editor_set_wayland_host(*Editor, ?*anyopaque) void;
extern fn zig_vstgui_editor_set_resize_callbacks(*Editor, ResizeCallbacks) void;

const Binding = struct {
    editor: *Editor,
    controller: *ivsteditcontroller.IEditController,
    observer_callbacks: ObserverCallbacks,
};

fn binding(self: anytype) ?*Binding {
    return @ptrCast(@alignCast(self.context orelse return null));
}

const View = vst_plug_view.PlugView(1, struct {
    pub fn attached(self: anytype, parent: ?*anyopaque, platform_type: types.FIDString) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        const platform: Platform = if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeNSView)))
            .macos
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeHWND)))
            .windows
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID)))
            .x11
        else if (std.mem.eql(u8, std.mem.span(platform_type), std.mem.span(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID)))
            .wayland
        else
            return types.kResultFalse;
        if (zig_vstgui_editor_open(state.editor, parent, platform) != 0) {
            std.log.err("VSTGUI editor attachment failed for {s}", .{@tagName(platform)});
            return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn removed(self: anytype) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        zig_vstgui_editor_close(state.editor);
        return types.kResultOk;
    }

    pub fn onSize(self: anytype, rect: *iplugview.ViewRect) types.tresult {
        const width = rect.right - rect.left;
        const height = rect.bottom - rect.top;
        if (width < 320 or height < 240) return types.kResultFalse;
        const state = binding(self) orelse return types.kResultFalse;
        if (zig_vstgui_editor_resize(state.editor, @intCast(width), @intCast(height)) != 0) {
            std.log.err("VSTGUI editor rejected size {d}x{d}", .{ width, height });
            return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn onKeyDown(self: anytype, key: types.char16, key_code: types.int16, modifiers: types.int16) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        return if (zig_vstgui_editor_key_down(state.editor, key, key_code, modifiers) == 0)
            types.kResultOk
        else
            types.kResultFalse;
    }

    pub fn onKeyUp(_: anytype, _: types.char16, key_code: types.int16, _: types.int16) types.tresult {
        return switch (key_code) {
            iplugview.VirtualKeyCode.end,
            iplugview.VirtualKeyCode.home,
            iplugview.VirtualKeyCode.left,
            iplugview.VirtualKeyCode.up,
            iplugview.VirtualKeyCode.right,
            iplugview.VirtualKeyCode.down,
            => types.kResultOk,
            else => types.kResultFalse,
        };
    }

    pub fn onFocus(self: anytype, state: types.TBool) types.tresult {
        const editor_state = binding(self) orelse return types.kResultFalse;
        zig_vstgui_editor_set_focus(editor_state.editor, state);
        return types.kResultOk;
    }

    pub fn checkSizeConstraint(_: anytype, rect: *iplugview.ViewRect) types.tresult {
        rect.right = std.math.clamp(rect.right, 320, 1_000);
        rect.bottom = std.math.clamp(rect.bottom, 240, 700);
        return types.kResultOk;
    }

    pub fn setContentScaleFactor(self: anytype, factor: f32) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        if (zig_vstgui_editor_set_scale(state.editor, factor) != 0) {
            std.log.err("VSTGUI editor rejected content scale {d}", .{factor});
            return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn setFrame(self: anytype, frame: ?*iplugview.IPlugFrame) types.tresult {
        const state = binding(self) orelse return types.kResultFalse;
        zig_vstgui_editor_set_frame(state.editor, frame);
        return types.kResultOk;
    }

    pub fn destroy(self: anytype) void {
        if (self.context) |context| {
            const state: *Binding = @ptrCast(@alignCast(context));
            state.observer_callbacks.unsubscribe(state.observer_callbacks.userdata, state.editor);
            zig_vstgui_editor_destroy(state.editor);
            _ = state.controller.vtable.release(state.controller);
            std.heap.page_allocator.destroy(state);
            self.context = null;
        }
    }
});

pub fn create(controller: *ivsteditcontroller.IEditController, parameters: []const ParameterInfoBinding, callbacks: Callbacks, observer_callbacks: ObserverCallbacks, wayland_host: ?*anyopaque) ?*iplugview.IPlugView {
    if (builtin.os.tag != .macos and builtin.os.tag != .windows and builtin.os.tag != .linux) return null;
    if (parameters.len == 0 or parameters.len > max_parameters) return null;
    var descriptions: [max_parameters]ParameterDescription = undefined;
    for (parameters, 0..) |parameter, index| {
        descriptions[index] = .{
            .parameter_id = parameter.id,
            .initial_normalized = controller.vtable.getParamNormalized(controller, parameter.id),
            .info = parameter.info,
        };
    }
    const editor = zig_vstgui_editor_create(&descriptions, @intCast(parameters.len), callbacks) orelse return null;
    zig_vstgui_editor_set_wayland_host(editor, wayland_host);
    const state = std.heap.page_allocator.create(Binding) catch {
        zig_vstgui_editor_destroy(editor);
        return null;
    };
    state.* = .{ .editor = editor, .controller = controller, .observer_callbacks = observer_callbacks };
    if (!observer_callbacks.subscribe(observer_callbacks.userdata, editor)) {
        std.heap.page_allocator.destroy(state);
        zig_vstgui_editor_destroy(editor);
        return null;
    }
    const view = View.create() orelse {
        observer_callbacks.unsubscribe(observer_callbacks.userdata, editor);
        std.heap.page_allocator.destroy(state);
        zig_vstgui_editor_destroy(editor);
        return null;
    };
    view.context = state;
    zig_vstgui_editor_set_resize_callbacks(editor, .{
        .userdata = view,
        .request_resize = requestEditorResize,
    });
    _ = controller.vtable.addRef(controller);
    const platform_result = switch (builtin.os.tag) {
        .macos => view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView),
        .windows => view.addPlatform(iplugview.PlatformType.kPlatformTypeHWND),
        .linux => blk: {
            if (view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID) != types.kResultOk) break :blk types.kResultFalse;
            break :blk view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID);
        },
        else => types.kResultFalse,
    };
    if (platform_result != types.kResultOk) {
        _ = view.iface.vtable.release(&view.iface);
        return null;
    }
    return view.asInterface();
}

fn requestEditorResize(userdata: ?*anyopaque, width: types.uint32, height: types.uint32) callconv(.c) types.int32 {
    const view: *View = @ptrCast(@alignCast(userdata orelse return -1));
    const result = view.requestResize(.{
        .left = 0,
        .top = 0,
        .right = @intCast(width),
        .bottom = @intCast(height),
    });
    if (result != types.kResultOk) {
        std.log.err("host rejected VSTGUI editor resize {d}x{d}", .{ width, height });
        return -1;
    }
    return 0;
}

pub const ParameterInfoBinding = struct {
    id: vsttypes.ParamID,
    info: ParameterInfo,
};

pub fn setParameter(observer_userdata: *anyopaque, parameter_id: vsttypes.ParamID, value: f64) void {
    const editor: *Editor = @ptrCast(@alignCast(observer_userdata));
    _ = zig_vstgui_editor_set_parameter(editor, parameter_id, value);
}

pub fn refreshParameters(observer_userdata: *anyopaque, parameters: []const ParameterValue) bool {
    if (parameters.len > max_parameters) return false;
    const editor: *Editor = @ptrCast(@alignCast(observer_userdata));
    return zig_vstgui_editor_refresh_parameters(editor, parameters.ptr, @intCast(parameters.len)) == 0;
}
