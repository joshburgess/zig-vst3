const ibstream = @import("pluginterfaces/base/ibstream.zig");
const edit_controller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_core = @import("zig-vst3-plugin-core");
const sine_synth_spec = @import("sine_synth_spec.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");
const vstgui = @import("vstgui.zig");

pub const cid = tuid.inlineUid(0x21D4E8B3, 0x7A5846C1, 0x9F20B6D4, 0x0E2A75C9);
pub const level_param_id: vsttypes.ParamID = sine_synth_spec.level_param_id;
pub const step_selection_state_id: u32 = 1;

pub const SineSynthEditorState = plug_core.editor_state.Store(1, &.{
    .{ .id = step_selection_state_id, .default = .{ .index = 1 } },
});

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "SineSynthController";
    pub const Params = sine_synth_spec.Spec.Params;
    pub const parameter_set = &sine_synth_spec.parameter_set;
    pub const EditorState = SineSynthEditorState;

    pub fn createView(controller: *edit_controller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return vstgui.createEditor(Controller, controller, name, .{
            .parameters = &.{.{
                .id = level_param_id,
                .title = "Level",
                .step_count = 0,
                .default_normalized = sine_synth_spec.default_level,
            }},
            .pianos = &.{.{
                .title = "Sine Synth Keyboard",
                .first_note = 48,
                .note_count = 24,
                .computer_base_pitch = 60,
            }},
            .step_sequencers = &.{.{
                .title = "Eight Step Gate",
                .step_parameter_ids = &sine_synth_spec.step_param_ids,
                .selection_state_id = step_selection_state_id,
                .playhead_source_id = 0x100,
            }},
            .composition = .{ .title = "zig-vst3 Sine Synth" },
        });
    }
});

pub const create = Controller.create;

pub fn level(iface: *edit_controller.IEditController) vsttypes.ParamValue {
    return Controller.getNormalized(iface, level_param_id);
}

pub fn setLevel(iface: *edit_controller.IEditController, value: vsttypes.ParamValue) void {
    _ = Controller.setNormalized(iface, level_param_id, value);
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

test "sine synth controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 9), controller_iface.vtable.getParameterCount(controller_iface));
    const view = controller_iface.vtable.createView(controller_iface, ivsteditcontroller.ViewType.kEditor) orelse return error.MissingEditorView;
    try std.testing.expectEqual(@as(types.uint32, 0), view.vtable.release(view));
    try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
}

test "sine synth controller exposes default level" {
    const std = @import("std");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&edit_controller.iedit_controller_iid), &out));
    const controller_iface: *edit_controller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);
    setLevel(controller_iface, sine_synth_spec.default_level);

    try std.testing.expectApproxEqAbs(@as(vsttypes.ParamValue, 0.1), level(controller_iface), 0.000001);
}
