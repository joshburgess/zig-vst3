const builtin = @import("builtin");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const iwaylandframe = @import("pluginterfaces/gui/iwaylandframe.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const std = @import("std");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vstgui_editor_view = @import("vstgui_editor_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const vstgui_adapter_enabled = @import("zig-vst3-gui-options").vstgui_adapter_enabled;

const ProtocolView = vst_plug_view.PlugView(4, struct {});

pub const Parameter = struct {
    id: vsttypes.ParamID,
    title: [*:0]const u8,
    step_count: types.int32,
    default_normalized: f64,
};

pub fn createView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameter: Parameter) ?*iplugview.IPlugView {
    return createMultiView(Controller, controller, name, &.{parameter});
}

pub fn createMultiView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameters: []const Parameter) ?*iplugview.IPlugView {
    if (!std.mem.eql(u8, std.mem.span(name), std.mem.span(ivsteditcontroller.ViewType.kEditor))) return null;
    if (comptime vstgui_adapter_enabled) {
        const Bridge = NativeBridge(Controller);
        var wayland_host: ?*anyopaque = null;
        if (comptime builtin.os.tag == .linux) {
            _ = Controller.createHostInstance(
                controller,
                &iwaylandframe.iwayland_host_iid,
                &iwaylandframe.iwayland_host_iid,
                &wayland_host,
            );
        }
        defer if (wayland_host) |host| {
            const iface: *iwaylandframe.IWaylandHost = @ptrCast(@alignCast(host));
            _ = iface.vtable.release(iface);
        };
        if (parameters.len == 0 or parameters.len > vstgui_editor_view.max_parameters) return null;
        var bindings: [vstgui_editor_view.max_parameters]vstgui_editor_view.ParameterInfoBinding = undefined;
        for (parameters, 0..) |parameter, index| {
            bindings[index] = .{ .id = parameter.id, .info = .{
                .title = parameter.title,
                .step_count = parameter.step_count,
                .default_normalized = parameter.default_normalized,
            } };
        }
        return vstgui_editor_view.create(controller, bindings[0..parameters.len], .{
            .userdata = controller,
            .begin_edit = Bridge.beginEdit,
            .perform_edit = Bridge.performEdit,
            .end_edit = Bridge.endEdit,
            .format_value = Bridge.formatValue,
            .parse_value = Bridge.parseValue,
        }, .{
            .userdata = controller,
            .subscribe = Bridge.subscribe,
            .unsubscribe = Bridge.unsubscribe,
        }, wayland_host);
    }

    const view = ProtocolView.create() orelse return null;
    if (view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeHWND) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID) != types.kResultOk or
        view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID) != types.kResultOk)
    {
        _ = view.iface.vtable.release(&view.iface);
        return null;
    }
    return view.asInterface();
}

fn NativeBridge(comptime Controller: type) type {
    return struct {
        fn controller(userdata: ?*anyopaque) ?*ivsteditcontroller.IEditController {
            return @ptrCast(@alignCast(userdata orelse return null));
        }

        fn beginEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID) callconv(.c) void {
            _ = Controller.beginEdit(controller(userdata) orelse return, parameter_id);
        }

        fn performEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, value: f64) callconv(.c) types.int32 {
            return Controller.performEdit(controller(userdata) orelse return types.kResultFalse, parameter_id, value);
        }

        fn endEdit(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID) callconv(.c) void {
            _ = Controller.endEdit(controller(userdata) orelse return, parameter_id);
        }

        fn formatValue(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, value: f64, output: [*]u8, capacity: types.uint32) callconv(.c) types.int32 {
            if (capacity == 0) return -1;
            var utf16: vsttypes.String128 = @splat(0);
            const iface = controller(userdata) orelse return -1;
            if (iface.vtable.getParamStringByValue(iface, parameter_id, value, &utf16) != types.kResultOk) return -1;
            const end = std.mem.indexOfScalar(vsttypes.TChar, &utf16, 0) orelse utf16.len;
            const available: usize = @intCast(capacity - 1);
            const written = std.unicode.utf16LeToUtf8(output[0..available], utf16[0..end]) catch return -1;
            output[written] = 0;
            return @intCast(written);
        }

        fn parseValue(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, text: [*:0]const u8, normalized: *f64) callconv(.c) types.int32 {
            var utf16: vsttypes.String128 = @splat(0);
            const written = std.unicode.utf8ToUtf16Le(utf16[0 .. utf16.len - 1], std.mem.span(text)) catch return -1;
            utf16[written] = 0;
            const iface = controller(userdata) orelse return -1;
            return if (iface.vtable.getParamValueByString(iface, parameter_id, &utf16, normalized) == types.kResultOk) 0 else -1;
        }

        fn subscribe(userdata: *anyopaque, editor: *anyopaque) bool {
            const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(userdata));
            return Controller.addParameterObserver(iface, .{ .userdata = editor, .changed = parameterChanged });
        }

        fn unsubscribe(userdata: *anyopaque, editor: *anyopaque) void {
            const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(userdata));
            Controller.removeParameterObserver(iface, editor);
        }

        fn parameterChanged(editor: *anyopaque, parameter_id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.c) void {
            vstgui_editor_view.setParameter(editor, parameter_id, value);
        }
    };
}
