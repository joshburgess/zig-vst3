const editor_smoke_spec = @import("editor_smoke_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const std = @import("std");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_plug_view = @import("vst_plug_view.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xE14D2D24, 0x9BC84C72, 0x8A522122, 0x121C781D);
pub const gain_param_id: vsttypes.ParamID = editor_smoke_spec.gain_param_id;

const SmokeView = vst_plug_view.PlugView(4, struct {});

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "EditorSmokeController";
    pub const Params = editor_smoke_spec.Spec.Params;
    pub const parameter_set = &editor_smoke_spec.parameter_set;

    pub fn createView(controller: *ivsteditcontroller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        _ = controller;
        if (!std.mem.eql(u8, std.mem.span(name), std.mem.span(ivsteditcontroller.ViewType.kEditor))) return null;
        const view = SmokeView.create() orelse return null;
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
});

pub const create = Controller.create;

pub fn gain(iface: *ivsteditcontroller.IEditController) vsttypes.ParamValue {
    return Controller.getNormalized(iface, gain_param_id);
}

pub fn applyParameterChanges(iface: *ivsteditcontroller.IEditController, changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(iface, changes);
}

pub fn readState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(iface, state);
}

pub fn writeState(iface: *ivsteditcontroller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(iface, state);
}

test "editor smoke controller creates an editor view" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    const view = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);

    try std.testing.expectEqual(types.kResultOk, view.vtable.isPlatformTypeSupported(view, iplugview.PlatformType.kPlatformTypeNSView));
    var rect = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, view.vtable.getSize(view, &rect));
    try std.testing.expectEqual(@as(types.int32, 400), rect.right);
    try std.testing.expectEqual(@as(types.int32, 300), rect.bottom);
}

test "editor smoke controller creates independent views" {
    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    const first = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = first.vtable.release(first);
    const second = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = second.vtable.release(second);
    try std.testing.expect(first != second);

    var changed = iplugview.ViewRect{ .left = 0, .top = 0, .right = 640, .bottom = 360 };
    try std.testing.expectEqual(types.kResultOk, first.vtable.onSize(first, &changed));
    var second_size = iplugview.ViewRect{};
    try std.testing.expectEqual(types.kResultOk, second.vtable.getSize(second, &second_size));
    try std.testing.expectEqual(@as(types.int32, 400), second_size.right);
    try std.testing.expectEqual(@as(types.int32, 300), second_size.bottom);
}
