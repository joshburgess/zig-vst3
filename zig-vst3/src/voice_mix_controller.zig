const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const plug = @import("zig-vst3-plugin-core");
const edit_controller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_process = plug.process;
const single_parameter_editor = @import("vstgui_single_parameter_controller.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const voice_mix_spec = @import("voice_mix_spec.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x6DB3AC2C, 0xB0884FC2, 0x8C38C61C, 0xE76014D4);
pub const voices_param_id: vsttypes.ParamID = voice_mix_spec.voices_param_id;

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "VoiceMixController";
    pub const Params = voice_mix_spec.Spec.Params;
    pub const parameter_set = &voice_mix_spec.parameter_set;

    pub fn createView(controller: *edit_controller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return single_parameter_editor.createView(Controller, controller, name, .{
            .id = voices_param_id,
            .title = "zig-vst3 Voice Mix",
            .units = "voices",
            .step_count = 3,
            .default_normalized = 0.0,
            .control_kind = .segmented_enum,
        });
    }
});

pub const create = Controller.create;

pub fn voiceGain(iface: *edit_controller.IEditController) f64 {
    const voices_param = plug.parameters.IntParam.init(voices_param_id, "Voices", 1, 4, 1);
    return @floatFromInt(voices_param.denormalize(Controller.getNormalized(iface, voices_param_id)));
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

test "voice mix controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
}
