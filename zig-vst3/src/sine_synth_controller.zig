const ibstream = @import("pluginterfaces/base/ibstream.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const sine_synth_spec = @import("sine_synth_spec.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0x21D4E8B3, 0x7A5846C1, 0x9F20B6D4, 0x0E2A75C9);
pub const level_param_id: vsttypes.ParamID = sine_synth_spec.level_param_id;

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "SineSynthController";
    pub const Params = sine_synth_spec.Spec.Params;
    pub const parameter_set = &sine_synth_spec.parameter_set;
});

pub const create = Controller.create;

pub fn level() vsttypes.ParamValue {
    return Controller.getNormalized(level_param_id);
}

pub fn setLevel(value: vsttypes.ParamValue) void {
    _ = Controller.setNormalized(level_param_id, value);
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

test "sine synth controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}

test "sine synth controller exposes default level" {
    const std = @import("std");

    setLevel(sine_synth_spec.default_level);

    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.1), level(), 0.000001);
}
