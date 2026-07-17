const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const edit_controller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const mode_gain_spec = @import("mode_gain_spec.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const single_parameter_editor = @import("vstgui_single_parameter_controller.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x8EB31D04, 0xC42B4F6F, 0xBC263438, 0x0FC99D4F);
pub const mode_param_id: vsttypes.ParamID = mode_gain_spec.mode_param_id;

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "ModeGainController";
    pub const Params = mode_gain_spec.Spec.Params;
    pub const parameter_set = &mode_gain_spec.parameter_set;

    pub fn createView(controller: *edit_controller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return single_parameter_editor.createView(Controller, controller, name, .{
            .id = mode_param_id,
            .title = "zig-vst3 Mode Gain",
            .step_count = 2,
            .default_normalized = 0.0,
            .control_kind = .enum_dropdown,
        });
    }
});

pub const create = Controller.create;

pub fn gain(iface: *edit_controller.IEditController) f64 {
    const mode_param = mode_gain_spec.ModeParam{ .id = mode_param_id, .name = "Mode", .default = .clean };
    return switch (mode_param.denormalize(Controller.getNormalized(iface, mode_param_id))) {
        .clean => 1.0,
        .boost => 2.0,
        .mute => 0.0,
    };
}

pub fn applyParameterChanges(iface: *edit_controller.IEditController, changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(iface, changes);
}

pub fn readState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(iface, state);
}

pub fn writeState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(iface, state);
}

test "mode gain controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
}
