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
