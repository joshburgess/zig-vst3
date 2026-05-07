const gain_spec = @import("gain_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_plug_effect = @import("zig_plug_effect.zig");

pub const cid = tuid.inlineUid(0xF0B8107A, 0x7E654828, 0x9113340B, 0x912D9E70);
pub const gain_param_id: vsttypes.ParamID = gain_spec.gain_param_id;

const Controller = zig_plug_effect.ReflectedEditController(struct {
    pub const controller_name = "GainController";
    pub const Params = gain_spec.Spec.Params;
    pub const parameter_set = &gain_spec.parameter_set;
});

pub const create = Controller.create;

pub fn gain() vsttypes.ParamValue {
    return Controller.getNormalized(gain_param_id);
}

pub fn setGain(value: vsttypes.ParamValue) void {
    _ = Controller.setNormalized(gain_param_id, value);
}

pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(changes);
}

pub fn readGainState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(state);
}

pub fn writeGainState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(state);
}

test "gain controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
