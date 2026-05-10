const ibstream = @import("pluginterfaces/base/ibstream.zig");
const note_gate_spec = @import("note_gate_spec.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xC580D6D4, 0x04D94F3F, 0x81E91EB4, 0xC94F91F0);

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "NoteGateController";
    pub const Params = note_gate_spec.Spec.Params;
    pub const parameter_set = &note_gate_spec.parameter_set;
});

pub const create = Controller.create;

pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(changes);
}

pub fn readState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(state);
}

pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(state);
}

test "note gate controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 0), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
