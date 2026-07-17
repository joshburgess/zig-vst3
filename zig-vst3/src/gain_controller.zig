const gain_spec = @import("gain_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const edit_controller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstnoteexpression = @import("pluginterfaces/vst/ivstnoteexpression.zig");
const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const string128 = @import("string128.zig");
const single_parameter_editor = @import("vstgui_single_parameter_controller.zig");
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_component_handler = @import("vst_component_handler.zig");
const vst_host_application = @import("vst_host_application.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xF0B8107A, 0x7E654828, 0x9113340B, 0x912D9E70);
pub const gain_param_id: vsttypes.ParamID = gain_spec.gain_param_id;

const Controller = zig_vst3_plugin_effect.ReflectedEditController(struct {
    pub const controller_name = "GainController";
    pub const Params = gain_spec.Spec.Params;
    pub const parameter_set = &gain_spec.parameter_set;
    pub const physical_ui_maps = &[_]ivstphysicalui.PhysicalUIMap{
        .{
            .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure),
            .noteExpressionTypeID = @intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kExpressionTypeID),
        },
    };

    pub fn createView(controller: *edit_controller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
        return single_parameter_editor.createView(Controller, controller, name, .{
            .id = gain_param_id,
            .title = "zig-vst3 Gain",
            .step_count = 0,
            .default_normalized = 1.0,
        });
    }
});

pub const create = Controller.create;

pub fn gain(iface: *edit_controller.IEditController) vsttypes.ParamValue {
    return Controller.getNormalized(iface, gain_param_id);
}

pub fn setGain(iface: *edit_controller.IEditController, value: vsttypes.ParamValue) void {
    _ = Controller.setNormalized(iface, gain_param_id, value);
}

pub fn beginEdit(iface: *edit_controller.IEditController, id: vsttypes.ParamID) types.tresult {
    return Controller.beginEdit(iface, id);
}

pub fn performEdit(iface: *edit_controller.IEditController, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
    return Controller.performEdit(iface, id, value);
}

pub fn endEdit(iface: *edit_controller.IEditController, id: vsttypes.ParamID) types.tresult {
    return Controller.endEdit(iface, id);
}

pub fn setDirty(iface: *edit_controller.IEditController, state: types.TBool) types.tresult {
    return Controller.setDirty(iface, state);
}

pub fn requestOpenEditor(iface: *edit_controller.IEditController, name: types.FIDString) types.tresult {
    return Controller.requestOpenEditor(iface, name);
}

pub fn startGroupEdit(iface: *edit_controller.IEditController) types.tresult {
    return Controller.startGroupEdit(iface);
}

pub fn finishGroupEdit(iface: *edit_controller.IEditController) types.tresult {
    return Controller.finishGroupEdit(iface);
}

pub fn createContextMenu(iface: *edit_controller.IEditController, param_id: ?*const vsttypes.ParamID) ?*@import("pluginterfaces/vst/ivstcontextmenu.zig").IContextMenu {
    return Controller.createContextMenu(iface, null, param_id);
}

pub fn requestBusActivation(iface: *edit_controller.IEditController, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, state: types.TBool) types.tresult {
    return Controller.requestBusActivation(iface, media_type, direction, index, state);
}

pub fn getSystemTime(iface: *edit_controller.IEditController, out: *types.int64) types.tresult {
    return Controller.getSystemTime(iface, out);
}

pub fn startProgress(iface: *edit_controller.IEditController, progress_type: types.uint32, title: ?[*]const types.char16, out: *edit_controller.ProgressID) types.tresult {
    return Controller.startProgress(iface, progress_type, title, out);
}

pub fn updateProgress(iface: *edit_controller.IEditController, id: edit_controller.ProgressID, value: vsttypes.ParamValue) types.tresult {
    return Controller.updateProgress(iface, id, value);
}

pub fn finishProgress(iface: *edit_controller.IEditController, id: edit_controller.ProgressID) types.tresult {
    return Controller.finishProgress(iface, id);
}

pub fn notifyUnitSelection(iface: *edit_controller.IEditController, unit_id: vsttypes.UnitID) types.tresult {
    return Controller.notifyUnitSelection(iface, unit_id);
}

pub fn notifyProgramListChange(iface: *edit_controller.IEditController, list_id: vsttypes.ProgramListID, program_index: types.int32) types.tresult {
    return Controller.notifyProgramListChange(iface, list_id, program_index);
}

pub fn notifyUnitByBusChange(iface: *edit_controller.IEditController) types.tresult {
    return Controller.notifyUnitByBusChange(iface);
}

pub fn openView(iface: *edit_controller.IEditController, name: types.FIDString) ?*iplugview.IPlugView {
    return Controller.openView(iface, name);
}

pub fn applyParameterChanges(iface: *edit_controller.IEditController, changes: plug_process.ParameterChanges) void {
    Controller.applyParameterChanges(iface, changes);
}

pub fn readGainState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.readState(iface, state);
}

pub fn writeGainState(iface: *edit_controller.IEditController, state: ?*ibstream.IBStream) types.tresult {
    return Controller.writeState(iface, state);
}

test "gain controller can be created as IEditController" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
}

test "gain controller instances isolate parameters and handlers" {
    const std = @import("std");
    const Handler = vst_component_handler.ComponentHandler(struct {});

    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&edit_controller.iedit_controller_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&edit_controller.iedit_controller_iid), &second_out));
    const first: *edit_controller.IEditController = @ptrCast(@alignCast(first_out.?));
    defer _ = first.vtable.release(first);
    const second: *edit_controller.IEditController = @ptrCast(@alignCast(second_out.?));
    defer _ = second.vtable.release(second);

    try std.testing.expectEqual(types.kResultOk, first.vtable.setParamNormalized(first, gain_param_id, 0.25));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), first.vtable.getParamNormalized(first, gain_param_id));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), second.vtable.getParamNormalized(second, gain_param_id));

    var first_handler = Handler{};
    var second_handler = Handler{};
    try std.testing.expectEqual(types.kResultOk, first.vtable.setComponentHandler(first, first_handler.asHandler()));
    try std.testing.expectEqual(types.kResultOk, second.vtable.setComponentHandler(second, second_handler.asHandler()));
    try std.testing.expectEqual(types.kResultOk, beginEdit(first, gain_param_id));
    try std.testing.expectEqual(@as(types.uint32, 1), first_handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 0), second_handler.begin_count);
}

test "gain controller can be repeatedly created and destroyed" {
    const std = @import("std");

    for (0..64) |_| {
        var out: ?*anyopaque = null;
        try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&edit_controller.iedit_controller_iid), &out));
        const controller_iface: *edit_controller.IEditController = @ptrCast(@alignCast(out.?));
        try std.testing.expectEqual(@as(types.uint32, 0), controller_iface.vtable.release(controller_iface));
    }
}

test "gain controller exposes edit controller extension interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const ivstrepresentation = @import("pluginterfaces/vst/ivstrepresentation.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var controller2_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivsteditcontroller.iedit_controller2_iid, &controller2_out));
    try std.testing.expect(controller2_out != null);
    const controller2: *ivsteditcontroller.IEditController2 = @ptrCast(@alignCast(controller2_out.?));
    defer _ = controller2.vtable.release(controller2);

    try std.testing.expectEqual(types.kResultOk, controller2.vtable.setKnobMode(controller2, @intFromEnum(ivsteditcontroller.KnobModes.kLinearMode)));
    try std.testing.expectEqual(types.kResultFalse, controller2.vtable.openHelp(controller2, 1));
    try std.testing.expectEqual(types.kResultFalse, controller2.vtable.openAboutBox(controller2, 1));

    var host_editing_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivsteditcontroller.iedit_controller_host_editing_iid, &host_editing_out),
    );
    try std.testing.expect(host_editing_out != null);
    const host_editing: *ivsteditcontroller.IEditControllerHostEditing = @ptrCast(@alignCast(host_editing_out.?));
    defer _ = host_editing.vtable.release(host_editing);

    try std.testing.expectEqual(types.kResultOk, host_editing.vtable.beginEditFromHost(host_editing, gain_param_id));
    try std.testing.expectEqual(types.kResultOk, host_editing.vtable.endEditFromHost(host_editing, gain_param_id));

    var xml_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstrepresentation.ixml_representation_controller_iid, &xml_out),
    );
    try std.testing.expect(xml_out != null);
    const xml: *ivstrepresentation.IXmlRepresentationController = @ptrCast(@alignCast(xml_out.?));
    defer _ = xml.vtable.release(xml);

    var info = ivstrepresentation.RepresentationInfo{};
    try std.testing.expectEqual(types.kResultFalse, xml.vtable.getXmlRepresentationStream(xml, &info, null));
}

test "gain controller creates a parameter editor view" {
    const std = @import("std");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&edit_controller.iedit_controller_iid), &out));
    const controller_iface: *edit_controller.IEditController = @ptrCast(@alignCast(out.?));
    defer _ = controller_iface.vtable.release(controller_iface);
    const view = openView(controller_iface, edit_controller.ViewType.kEditor) orelse return error.MissingEditorView;
    defer _ = view.vtable.release(view);
    try std.testing.expectEqual(types.kResultOk, view.vtable.isPlatformTypeSupported(view, iplugview.PlatformType.kPlatformTypeNSView));
}

test "gain controller stores component handler for automation callbacks" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    const HostHandler = vst_component_handler.ComponentHandler(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expectEqual(types.kResultFalse, beginEdit(controller_iface, gain_param_id));

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.add_ref_count);
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.release_count);
    try std.testing.expectEqual(types.kResultOk, beginEdit(controller_iface, gain_param_id));
    try std.testing.expectEqual(types.kResultOk, performEdit(controller_iface, gain_param_id, 0.25));
    try std.testing.expectEqual(types.kResultOk, endEdit(controller_iface, gain_param_id));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.begin_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.end_count);
    try std.testing.expectEqual(gain_param_id, handler.last_param_id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), handler.last_value);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), gain(controller_iface));

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.release_count);
    try std.testing.expectEqual(types.kResultFalse, endEdit(controller_iface, gain_param_id));
}

test "gain controller rolls back perform edit when host rejects automation" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    const HostHandler = vst_component_handler.ComponentHandler(struct {
        pub fn performEdit(_: anytype, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return if (id == gain_param_id and value == 0.25) types.kResultFalse else types.kResultOk;
        }
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    setGain(controller_iface, 0.5);
    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    defer _ = controller_iface.vtable.setComponentHandler(controller_iface, null);
    try std.testing.expectEqual(types.kResultFalse, performEdit(controller_iface, gain_param_id, 0.25));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), gain(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.perform_count);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), handler.last_value);
}

test "gain controller stores component handler 2 callbacks" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    const HostHandler = vst_component_handler.ComponentHandler2(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expectEqual(types.kResultFalse, setDirty(controller_iface, 1));

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.handler2_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler2_release_count);
    try std.testing.expectEqual(types.kResultOk, setDirty(controller_iface, 1));
    try std.testing.expectEqual(types.kResultOk, requestOpenEditor(controller_iface, ""));
    try std.testing.expectEqual(types.kResultOk, startGroupEdit(controller_iface));
    try std.testing.expectEqual(types.kResultOk, finishGroupEdit(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.dirty_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.open_editor_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.start_group_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.finish_group_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 2), handler.handler2_release_count);
    try std.testing.expectEqual(types.kResultFalse, setDirty(controller_iface, 1));
}

test "gain controller stores component handler 3 context menu callback" {
    const std = @import("std");
    const ivstcontextmenu = @import("pluginterfaces/vst/ivstcontextmenu.zig");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    const HostHandler = vst_component_handler.ComponentHandler3(struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenu, null), createContextMenu(controller_iface, null));

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(@as(?*ivstcontextmenu.IContextMenu, null), createContextMenu(controller_iface, &gain_param_id));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.context_menu_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.handler3_release_count);
}

test "gain controller stores bus activation and system time handlers" {
    const std = @import("std");

    const HostHandler = vst_component_handler.ComponentHandlerBusAndTime(struct {
        pub const system_time: types.int64 = 12345;
    });

    var controller_out: ?*anyopaque = null;
    const ivstedit = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstedit.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivstedit.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var time_value: types.int64 = -1;
    try std.testing.expectEqual(types.kResultFalse, getSystemTime(controller_iface, &time_value));
    try std.testing.expectEqual(@as(types.int64, 0), time_value);

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(
        types.kResultOk,
        requestBusActivation(
            controller_iface,
            @intFromEnum(ivstcomponent.MediaTypes.kEvent),
            @intFromEnum(ivstcomponent.BusDirections.kInput),
            0,
            1,
        ),
    );
    try std.testing.expectEqual(types.kResultOk, getSystemTime(controller_iface, &time_value));
    try std.testing.expectEqual(@as(types.int64, 12345), time_value);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.bus_activation_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.system_time_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.bus_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.time_release_count);
}

test "gain controller stores progress callbacks" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    const HostHandler = vst_component_handler.ComponentHandlerProgress(struct {
        pub const progress_id: ivsteditcontroller.ProgressID = 77;
    });

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var progress_id: ivsteditcontroller.ProgressID = 999;
    try std.testing.expectEqual(types.kResultFalse, startProgress(controller_iface, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 0), progress_id);

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(types.kResultOk, startProgress(controller_iface, @intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), null, &progress_id));
    try std.testing.expectEqual(@as(ivsteditcontroller.ProgressID, 77), progress_id);
    try std.testing.expectEqual(types.kResultOk, updateProgress(controller_iface, progress_id, 0.5));
    try std.testing.expectEqual(types.kResultOk, finishProgress(controller_iface, progress_id));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.start_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.update_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.finish_count);
    try std.testing.expectEqual(@intFromEnum(ivsteditcontroller.ProgressType.UIBackgroundTask), handler.last_type);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), handler.last_value);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.progress_release_count);
    try std.testing.expectEqual(types.kResultFalse, updateProgress(controller_iface, progress_id, 1.0));
}

test "gain controller stores unit handler callbacks" {
    const std = @import("std");

    const HostHandler = vst_component_handler.ComponentHandlerUnits(struct {});

    var controller_out: ?*anyopaque = null;
    const ivstedit = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstedit.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivstedit.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    try std.testing.expectEqual(types.kResultFalse, notifyUnitSelection(controller_iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultFalse, notifyProgramListChange(controller_iface, ivstunits.kNoProgramListId, ivstunits.kAllProgramInvalid));
    try std.testing.expectEqual(types.kResultFalse, notifyUnitByBusChange(controller_iface));

    var handler = HostHandler{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, handler.asHandler()));
    try std.testing.expectEqual(types.kResultOk, notifyUnitSelection(controller_iface, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultOk, notifyProgramListChange(controller_iface, ivstunits.kNoProgramListId, ivstunits.kAllProgramInvalid));
    try std.testing.expectEqual(types.kResultOk, notifyUnitByBusChange(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_selection_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.program_list_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_by_bus_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.setComponentHandler(controller_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), handler.unit2_release_count);
}

test "gain controller queries host application during initialize" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const HostApplication = vst_host_application.HostApplication("Test Host", struct {});

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var host = HostApplication{};
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.initialize(controller_iface, host.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.release_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.initialize(controller_iface, host.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 2), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);

    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.terminate(controller_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.release_count);
}

test "gain controller exposes default connection point" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
    const vst_message = @import("vst_message.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstmessage.iconnection_point_iid, &connection_out),
    );
    try std.testing.expect(connection_out != null);
    const connection: *ivstmessage.IConnectionPoint = @ptrCast(@alignCast(connection_out.?));
    defer _ = connection.vtable.release(connection);

    try std.testing.expectEqual(types.kInvalidArgument, connection.vtable.connect(connection, null));
    try std.testing.expectEqual(types.kResultFalse, connection.vtable.notify(connection, null));

    const PeerConnection = vst_message.ConnectionPoint(struct {});
    var peer = PeerConnection{};
    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, peer.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), peer.add_ref_count);
    try std.testing.expectEqual(types.kResultOk, connection.vtable.connect(connection, peer.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), peer.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), peer.release_count);
    try std.testing.expectEqual(types.kInvalidArgument, connection.vtable.connect(connection, null));
    try std.testing.expectEqual(@as(types.uint32, 1), peer.release_count);
    try std.testing.expectEqual(types.kResultOk, connection.vtable.disconnect(connection, peer.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 2), peer.release_count);
}

test "gain controller exposes default root unit info" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var unit_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iunit_info_iid, &unit_out));
    try std.testing.expect(unit_out != null);
    const unit_info: *ivstunits.IUnitInfo = @ptrCast(@alignCast(unit_out.?));
    defer _ = unit_info.vtable.release(unit_info);

    try std.testing.expectEqual(@as(types.int32, 1), unit_info.vtable.getUnitCount(unit_info));

    var root: ivstunits.UnitInfo = .{};
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.getUnitInfo(unit_info, 0, &root));
    try std.testing.expectEqual(ivstunits.kRootUnitId, root.id);
    try std.testing.expectEqual(ivstunits.kNoParentUnitId, root.parentUnitId);
    try std.testing.expectEqual(ivstunits.kNoProgramListId, root.programListId);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'R'), root.name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'o'), root.name[1]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 'o'), root.name[2]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 't'), root.name[3]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), root.name[4]);

    var missing: ivstunits.UnitInfo = .{};
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getUnitInfo(unit_info, 1, &missing));
    try std.testing.expectEqual(@as(types.int32, 0), unit_info.vtable.getProgramListCount(unit_info));

    var program_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramName(unit_info, ivstunits.kNoProgramListId, 0, &program_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_name[1]);

    var program_info: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramInfo(unit_info, ivstunits.kNoProgramListId, 0, "name", &program_info));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), program_info[1]);

    var pitch_name: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.getProgramPitchName(unit_info, ivstunits.kNoProgramListId, 0, 60, &pitch_name));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), pitch_name[1]);

    try std.testing.expectEqual(ivstunits.kRootUnitId, unit_info.vtable.getSelectedUnit(unit_info));
    try std.testing.expectEqual(types.kResultOk, unit_info.vtable.selectUnit(unit_info, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kInvalidArgument, unit_info.vtable.selectUnit(unit_info, 42));

    var unit_by_bus: vsttypes.UnitID = -99;
    try std.testing.expectEqual(
        types.kResultOk,
        unit_info.vtable.getUnitByBus(
            unit_info,
            @intFromEnum(ivstcomponent.MediaTypes.kAudio),
            @intFromEnum(ivstcomponent.BusDirections.kInput),
            0,
            0,
            &unit_by_bus,
        ),
    );
    try std.testing.expectEqual(ivstunits.kRootUnitId, unit_by_bus);
}

test "gain controller exposes default unit data interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var program_data_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iprogram_list_data_iid, &program_data_out));
    try std.testing.expect(program_data_out != null);
    const program_data: *ivstunits.IProgramListData = @ptrCast(@alignCast(program_data_out.?));
    defer _ = program_data.vtable.release(program_data);

    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.programDataSupported(program_data, ivstunits.kNoProgramListId));
    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.getProgramData(program_data, ivstunits.kNoProgramListId, 0, null));
    try std.testing.expectEqual(types.kResultFalse, program_data.vtable.setProgramData(program_data, ivstunits.kNoProgramListId, 0, null));

    var unit_data_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstunits.iunit_data_iid, &unit_data_out));
    try std.testing.expect(unit_data_out != null);
    const unit_data: *ivstunits.IUnitData = @ptrCast(@alignCast(unit_data_out.?));
    defer _ = unit_data.vtable.release(unit_data);

    try std.testing.expectEqual(types.kResultFalse, unit_data.vtable.unitDataSupported(unit_data, ivstunits.kRootUnitId));
    try std.testing.expectEqual(types.kResultFalse, unit_data.vtable.getUnitData(unit_data, ivstunits.kRootUnitId, null));
    try std.testing.expectEqual(types.kResultFalse, unit_data.vtable.setUnitData(unit_data, ivstunits.kRootUnitId, null));
}

test "gain controller exposes default MIDI mapping interface" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const ivstmidicontrollers = @import("pluginterfaces/vst/ivstmidicontrollers.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var mapping_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivsteditcontroller.imidi_mapping_iid, &mapping_out));
    try std.testing.expect(mapping_out != null);
    const mapping: *ivsteditcontroller.IMidiMapping = @ptrCast(@alignCast(mapping_out.?));
    defer _ = mapping.vtable.release(mapping);

    var param_id: vsttypes.ParamID = 0;
    try std.testing.expectEqual(
        types.kResultFalse,
        mapping.vtable.getMidiControllerAssignment(mapping, 0, 0, ivstmidicontrollers.kCtrlModWheel, &param_id),
    );
    try std.testing.expectEqual(vsttypes.kNoParamId, param_id);
}

test "gain controller exposes default MIDI learn and MIDI 2 mapping interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const ivstmidicontrollers = @import("pluginterfaces/vst/ivstmidicontrollers.zig");
    const ivstmidilearn = @import("pluginterfaces/vst/ivstmidilearn.zig");
    const ivstmidimapping2 = @import("pluginterfaces/vst/ivstmidimapping2.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var learn_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstmidilearn.imidi_learn_iid, &learn_out));
    try std.testing.expect(learn_out != null);
    const learn: *ivstmidilearn.IMidiLearn = @ptrCast(@alignCast(learn_out.?));
    defer _ = learn.vtable.release(learn);
    try std.testing.expectEqual(
        types.kResultFalse,
        learn.vtable.onLiveMIDIControllerInput(learn, 0, 0, ivstmidicontrollers.kCtrlModWheel),
    );

    var mapping2_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstmidimapping2.imidi_mapping2_iid, &mapping2_out));
    try std.testing.expect(mapping2_out != null);
    const mapping2: *ivstmidimapping2.IMidiMapping2 = @ptrCast(@alignCast(mapping2_out.?));
    defer _ = mapping2.vtable.release(mapping2);
    try std.testing.expectEqual(@as(types.uint32, 0), mapping2.vtable.getNumMidi1ControllerAssignments(mapping2, @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.uint32, 0), mapping2.vtable.getNumMidi2ControllerAssignments(mapping2, @intFromEnum(ivstcomponent.BusDirections.kInput)));

    var learn2_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, controller_iface.vtable.queryInterface(controller_iface, &ivstmidimapping2.imidi_learn2_iid, &learn2_out));
    try std.testing.expect(learn2_out != null);
    const learn2: *ivstmidimapping2.IMidiLearn2 = @ptrCast(@alignCast(learn2_out.?));
    defer _ = learn2.vtable.release(learn2);
    try std.testing.expectEqual(
        types.kResultFalse,
        learn2.vtable.onLiveMidi1ControllerInput(learn2, 0, 0, ivstmidicontrollers.kCtrlModWheel),
    );
}

test "gain controller exposes default note expression and keyswitch interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var expression_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstnoteexpression.inote_expression_controller_iid, &expression_out),
    );
    try std.testing.expect(expression_out != null);
    const expression: *ivstnoteexpression.INoteExpressionController = @ptrCast(@alignCast(expression_out.?));
    defer _ = expression.vtable.release(expression);

    try std.testing.expectEqual(@as(types.int32, 0), expression.vtable.getNoteExpressionCount(expression, 0, 0));
    var expression_info: ivstnoteexpression.NoteExpressionTypeInfo = .{};
    try std.testing.expectEqual(
        types.kInvalidArgument,
        expression.vtable.getNoteExpressionInfo(expression, 0, 0, 0, &expression_info),
    );
    var expression_text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    const empty_expression_text: [1:0]vsttypes.TChar = .{0};
    var expression_value: ivstnoteexpression.NoteExpressionValue = 1.0;
    try std.testing.expectEqual(
        types.kInvalidArgument,
        expression.vtable.getNoteExpressionStringByValue(expression, 0, 0, 0, 0.5, &expression_text),
    );
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), expression_text[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), expression_text[1]);
    try std.testing.expectEqual(
        types.kInvalidArgument,
        expression.vtable.getNoteExpressionValueByString(expression, 0, 0, 0, &empty_expression_text, &expression_value),
    );
    try std.testing.expectEqual(@as(ivstnoteexpression.NoteExpressionValue, 0), expression_value);

    var keyswitch_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstnoteexpression.ikeyswitch_controller_iid, &keyswitch_out),
    );
    try std.testing.expect(keyswitch_out != null);
    const keyswitch: *ivstnoteexpression.IKeyswitchController = @ptrCast(@alignCast(keyswitch_out.?));
    defer _ = keyswitch.vtable.release(keyswitch);

    try std.testing.expectEqual(@as(types.int32, 0), keyswitch.vtable.getKeyswitchCount(keyswitch, 0, 0));
    var keyswitch_info: ivstnoteexpression.KeyswitchInfo = .{};
    try std.testing.expectEqual(
        types.kInvalidArgument,
        keyswitch.vtable.getKeyswitchInfo(keyswitch, 0, 0, 0, &keyswitch_info),
    );

    var physical_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstphysicalui.inote_expression_physical_ui_mapping_iid, &physical_out),
    );
    try std.testing.expect(physical_out != null);
    const physical: *ivstphysicalui.INoteExpressionPhysicalUIMapping = @ptrCast(@alignCast(physical_out.?));
    defer _ = physical.vtable.release(physical);

    var requested_physical_maps = [_]ivstphysicalui.PhysicalUIMap{
        .{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure) },
        .{ .physicalUITypeID = @intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIXMovement) },
    };
    var physical_mapping: ivstphysicalui.PhysicalUIMapList = .{ .count = requested_physical_maps.len, .map = &requested_physical_maps };
    try std.testing.expectEqual(
        types.kResultOk,
        physical.vtable.getPhysicalUIMapping(physical, 0, 0, &physical_mapping),
    );
    try std.testing.expectEqual(@as(types.uint32, 2), physical_mapping.count);
    try std.testing.expectEqual(@intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIPressure), requested_physical_maps[0].physicalUITypeID);
    try std.testing.expectEqual(@intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kExpressionTypeID), requested_physical_maps[0].noteExpressionTypeID);
    try std.testing.expectEqual(@intFromEnum(ivstphysicalui.PhysicalUITypeIDs.kPUIXMovement), requested_physical_maps[1].physicalUITypeID);
    try std.testing.expectEqual(@intFromEnum(ivstnoteexpression.NoteExpressionTypeIDs.kInvalidTypeID), requested_physical_maps[1].noteExpressionTypeID);
}

test "gain controller exposes default parameter helper interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
    const ivstparameterfunctionname = @import("pluginterfaces/vst/ivstparameterfunctionname.zig");
    const ivstremapparamid = @import("pluginterfaces/vst/ivstremapparamid.zig");

    var controller_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &controller_out));
    try std.testing.expect(controller_out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(controller_out.?));
    defer _ = controller_iface.vtable.release(controller_iface);

    var function_name_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstparameterfunctionname.iparameter_function_name_iid, &function_name_out),
    );
    try std.testing.expect(function_name_out != null);
    const function_name: *ivstparameterfunctionname.IParameterFunctionName = @ptrCast(@alignCast(function_name_out.?));
    defer _ = function_name.vtable.release(function_name);

    var function_param_id: vsttypes.ParamID = gain_param_id;
    try std.testing.expectEqual(
        types.kResultFalse,
        function_name.vtable.getParameterIDFromFunctionName(function_name, 0, ivstparameterfunctionname.FunctionNameType.kDryWetMix, &function_param_id),
    );
    try std.testing.expectEqual(vsttypes.kNoParamId, function_param_id);

    var remap_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        controller_iface.vtable.queryInterface(controller_iface, &ivstremapparamid.iremap_param_id_iid, &remap_out),
    );
    try std.testing.expect(remap_out != null);
    const remap: *ivstremapparamid.IRemapParamID = @ptrCast(@alignCast(remap_out.?));
    defer _ = remap.vtable.release(remap);

    var remapped: vsttypes.ParamID = gain_param_id;
    try std.testing.expectEqual(
        types.kResultFalse,
        remap.vtable.getCompatibleParamID(remap, &cid, gain_param_id, &remapped),
    );
    try std.testing.expectEqual(vsttypes.kNoParamId, remapped);
}
