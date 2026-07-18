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
    units: [*:0]const u8 = "",
    step_count: types.int32,
    default_normalized: f64,
    control_kind: vstgui_editor_view.ControlKind = .linear_slider,
};

pub const Meter = struct {
    title: [*:0]const u8,
    kind: vstgui_editor_view.MeterKind,
    first_source_id: types.uint32,
    second_source_id: types.uint32 = 0,
};

pub const Asset = vstgui_editor_view.Asset;
pub const AssetFormat = vstgui_editor_view.AssetFormat;
pub const AssetScale = vstgui_editor_view.AssetScale;
pub const Canvas = vstgui_editor_view.Canvas;
pub const DrawingCallbacks = vstgui_editor_view.DrawingCallbacks;
pub const DrawingComponent = vstgui_editor_view.DrawingComponent;
pub const DrawingState = vstgui_editor_view.DrawingState;
pub const DrawRequest = vstgui_editor_view.DrawRequest;
pub const Fonts = vstgui_editor_view.Fonts;
pub const Skin = vstgui_editor_view.Skin;
pub const Theme = vstgui_editor_view.Theme;
pub const Layout = vstgui_editor_view.Layout;
pub const StyleOverride = vstgui_editor_view.StyleOverride;
pub const Group = vstgui_editor_view.Group;
pub const Composition = vstgui_editor_view.Composition;

pub const EditorDescription = struct {
    parameters: []const Parameter,
    meters: []const Meter = &.{},
    skin: Skin = .{},
    composition: Composition = .{},
};
pub const drawAsset = vstgui_editor_view.drawAsset;
pub const fillEllipse = vstgui_editor_view.fillEllipse;
pub const fillRect = vstgui_editor_view.fillRect;
pub const line = vstgui_editor_view.line;
pub const strokeRect = vstgui_editor_view.strokeRect;

pub fn createView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameter: Parameter) ?*iplugview.IPlugView {
    return createMultiView(Controller, controller, name, &.{parameter});
}

pub fn createMultiView(comptime Controller: type, controller: *ivsteditcontroller.IEditController, name: types.FIDString, parameters: []const Parameter) ?*iplugview.IPlugView {
    return createMultiViewWithMeters(Controller, controller, name, parameters, &.{});
}

pub fn createMultiViewWithMeters(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
) ?*iplugview.IPlugView {
    return createMultiViewWithSkin(Controller, controller, name, parameters, meters, .{});
}

pub fn createMultiViewWithSkin(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
    skin: Skin,
) ?*iplugview.IPlugView {
    return createConfiguredView(Controller, controller, name, parameters, meters, skin, .{});
}

pub fn createEditor(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    description: EditorDescription,
) ?*iplugview.IPlugView {
    return createConfiguredView(
        Controller,
        controller,
        name,
        description.parameters,
        description.meters,
        description.skin,
        description.composition,
    );
}

fn createConfiguredView(
    comptime Controller: type,
    controller: *ivsteditcontroller.IEditController,
    name: types.FIDString,
    parameters: []const Parameter,
    meters: []const Meter,
    skin: Skin,
    composition: Composition,
) ?*iplugview.IPlugView {
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
            bindings[index] = .{ .id = parameter.id, .control_kind = parameter.control_kind, .info = .{
                .title = parameter.title,
                .units = parameter.units,
                .step_count = parameter.step_count,
                .default_normalized = parameter.default_normalized,
            } };
        }
        if (meters.len > vstgui_editor_view.max_meters) return null;
        var meter_descriptions: [vstgui_editor_view.max_meters]vstgui_editor_view.MeterDescription = undefined;
        for (meters, 0..) |meter, index| {
            meter_descriptions[index] = .{
                .title = meter.title,
                .kind = meter.kind,
                .first_source_id = meter.first_source_id,
                .second_source_id = meter.second_source_id,
            };
        }
        return vstgui_editor_view.create(controller, bindings[0..parameters.len], meter_descriptions[0..meters.len], skin, composition, .{
            .userdata = controller,
            .begin_edit = Bridge.beginEdit,
            .perform_edit = Bridge.performEdit,
            .end_edit = Bridge.endEdit,
            .format_value = Bridge.formatValue,
            .parse_value = Bridge.parseValue,
            .show_context_menu = Bridge.showContextMenu,
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

        fn showContextMenu(userdata: ?*anyopaque, parameter_id: vsttypes.ParamID, x: types.int32, y: types.int32) callconv(.c) types.int32 {
            const iface = controller(userdata) orelse return -1;
            const menu = Controller.createContextMenu(iface, null, &parameter_id) orelse return -1;
            defer _ = menu.vtable.release(menu);
            return if (menu.vtable.popup(menu, @intCast(@max(0, x)), @intCast(@max(0, y))) == types.kResultOk) 0 else -1;
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
