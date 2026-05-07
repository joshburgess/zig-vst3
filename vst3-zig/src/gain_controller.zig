const gain_spec = @import("gain_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");
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

test "gain controller exposes edit controller extension interfaces" {
    const std = @import("std");
    const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");

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
    const ivstnoteexpression = @import("pluginterfaces/vst/ivstnoteexpression.zig");
    const ivstphysicalui = @import("pluginterfaces/vst/ivstphysicalui.zig");

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

    var physical_mapping: ivstphysicalui.PhysicalUIMapList = .{ .count = 99, .map = null };
    try std.testing.expectEqual(
        types.kResultFalse,
        physical.vtable.getPhysicalUIMapping(physical, 0, 0, &physical_mapping),
    );
    try std.testing.expectEqual(@as(types.uint32, 0), physical_mapping.count);
    try std.testing.expectEqual(@as(?[*]ivstphysicalui.PhysicalUIMap, null), physical_mapping.map);
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
