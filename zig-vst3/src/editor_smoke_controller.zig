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
var smoke_view = SmokeView{};
var view_initialized = false;

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "EditorSmokeController";
    pub const Params = editor_smoke_spec.Spec.Params;
    pub const parameter_set = &editor_smoke_spec.parameter_set;

    pub fn createView(name: types.FIDString) ?*iplugview.IPlugView {
        if (!std.mem.eql(u8, std.mem.span(name), std.mem.span(ivsteditcontroller.ViewType.kEditor))) return null;
        ensureViewInitialized();
        _ = smoke_view.iface.vtable.addRef(&smoke_view.iface);
        return smoke_view.asInterface();
    }
});

pub const create = Controller.create;

pub fn gain() vsttypes.ParamValue {
    return Controller.getNormalized(gain_param_id);
}

pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(changes);
}

pub fn readState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(state);
}

pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(state);
}

fn ensureViewInitialized() void {
    if (view_initialized) return;
    _ = smoke_view.addPlatform(iplugview.PlatformType.kPlatformTypeNSView);
    _ = smoke_view.addPlatform(iplugview.PlatformType.kPlatformTypeHWND);
    _ = smoke_view.addPlatform(iplugview.PlatformType.kPlatformTypeX11EmbedWindowID);
    _ = smoke_view.addPlatform(iplugview.PlatformType.kPlatformTypeWaylandSurfaceID);
    view_initialized = true;
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
