const event_monitor_spec = @import("event_monitor_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const edit_controller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xA39F0C6D, 0x1B7245E9, 0x8C30F2A4, 0xD7150B68);

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "EventMonitorController";
    pub const Params = event_monitor_spec.Spec.Params;
    pub const parameter_set = &event_monitor_spec.parameter_set;
});

pub const create = Controller.create;

pub fn applyParameterChanges(iface: *edit_controller.IEditController, changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(iface, changes);
}

pub fn readState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(iface, state);
}

pub fn writeState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(iface, state);
}

test "event monitor controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 0), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
}
