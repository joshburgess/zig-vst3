const ibstream = @import("pluginterfaces/base/ibstream.zig");
const mode_gain_spec = @import("mode_gain_spec.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
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
});

pub const create = Controller.create;

pub fn gain() f64 {
    const mode_param = mode_gain_spec.ModeParam{ .id = mode_param_id, .name = "Mode", .default = .clean };
    return switch (mode_param.denormalize(Controller.getNormalized(mode_param_id))) {
        .clean => 1.0,
        .boost => 2.0,
        .mute => 0.0,
    };
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

test "mode gain controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
