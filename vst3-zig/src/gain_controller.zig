const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const gain_spec = @import("gain_spec.zig");
const types = @import("pluginterfaces/base/types.zig");
const interface_map = @import("interface_map.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_plug_bridge = @import("zig_plug_bridge.zig");

pub const cid = tuid.inlineUid(0xF0B8107A, 0x7E654828, 0x9113340B, 0x912D9E70);
pub const gain_param_id: vsttypes.ParamID = gain_spec.gain_param_id;

const Controller = extern struct {
    iface: ivsteditcontroller.IEditController = .{ .vtable = &controller_vtable },
    ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
};

var controller = Controller{};
var parameter_values = gain_spec.Spec.ParameterValues.init(&gain_spec.parameter_set);

pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
    return query(&controller.iface, @ptrCast(requested_iid), out);
}

const controller_vtable = ivsteditcontroller.IEditControllerVTable{
    .queryInterface = query,
    .addRef = addRef,
    .release = release,
    .initialize = initialize,
    .terminate = terminate,
    .setComponentState = setComponentState,
    .setState = setState,
    .getState = getState,
    .getParameterCount = getParameterCount,
    .getParameterInfo = getParameterInfo,
    .getParamStringByValue = getParamStringByValue,
    .getParamValueByString = getParamValueByString,
    .normalizedParamToPlain = normalizedParamToPlain,
    .plainParamToNormalized = plainParamToNormalized,
    .getParamNormalized = getParamNormalized,
    .setParamNormalized = setParamNormalized,
    .setComponentHandler = setComponentHandler,
    .createView = createView,
};

fn owner(ptr: *anyopaque) *Controller {
    const iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("iface", iface);
}

fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
    const entries = [_]interface_map.Entry{
        .{ .iid = &funknown.iid, .ptr = ptr },
        .{ .iid = &ipluginbase.iplugin_base_iid, .ptr = ptr },
        .{ .iid = &ivsteditcontroller.iedit_controller_iid, .ptr = ptr },
    };
    return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
}

fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
    return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
}

fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
    return funknown.decrementRefCount(&owner(ptr).ref_count, "GainController");
}

fn initialize(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn terminate(_: *anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setComponentState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return readGainState(state);
}

fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return readGainState(state);
}

fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return writeGainState(state);
}

fn getParameterCount(_: *anyopaque) callconv(.C) types.int32 {
    return @intCast(gain_spec.Spec.ParameterSet.count);
}

fn getParameterInfo(_: *anyopaque, index: types.int32, out: *ivsteditcontroller.ParameterInfo) callconv(.C) types.tresult {
    return zig_plug_bridge.fillParameterInfo(gain_spec.Spec.Params, &gain_spec.parameter_set, index, out);
}

fn getParamStringByValue(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
    return zig_plug_bridge.getParamStringByValue(gain_spec.Spec.Params, &gain_spec.parameter_set, id, value, out);
}

fn getParamValueByString(_: *anyopaque, id: vsttypes.ParamID, text: [*]vsttypes.TChar, out: *vsttypes.ParamValue) callconv(.C) types.tresult {
    return zig_plug_bridge.getParamValueByString(gain_spec.Spec.Params, &gain_spec.parameter_set, id, text, out);
}

fn normalizedParamToPlain(_: *anyopaque, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    return zig_plug_bridge.normalizedParamToPlain(gain_spec.Spec.Params, &gain_spec.parameter_set, id, normalized);
}

fn plainParamToNormalized(_: *anyopaque, id: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    return zig_plug_bridge.plainParamToNormalized(gain_spec.Spec.Params, &gain_spec.parameter_set, id, plain);
}

fn getParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) vsttypes.ParamValue {
    _ = ptr;
    return parameter_values.loadById(&gain_spec.parameter_set, id) orelse 0;
}

fn setParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.C) types.tresult {
    _ = ptr;
    if (!parameter_values.storeById(&gain_spec.parameter_set, id, value)) return types.kInvalidArgument;
    return types.kResultOk;
}

fn setComponentHandler(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn createView(_: *anyopaque, _: types.FIDString) callconv(.C) ?*iplugview.IPlugView {
    return null;
}

pub fn gain() vsttypes.ParamValue {
    return parameter_values.loadById(&gain_spec.parameter_set, gain_param_id) orelse gain_spec.default_gain;
}

pub fn setGain(value: vsttypes.ParamValue) void {
    _ = parameter_values.storeById(&gain_spec.parameter_set, gain_param_id, value);
}

pub fn readGainState(state: ?*ibstream.IBStream) types.tresult {
    var values = gain_spec.Spec.ParameterValues.init(&gain_spec.parameter_set);
    const result = zig_plug_bridge.readParameterState(gain_spec.Spec.Params, state, &gain_spec.parameter_set, &values);
    if (result != types.kResultOk) return result;
    storeParameterValues(&values);
    return types.kResultOk;
}

pub fn writeGainState(state: ?*ibstream.IBStream) types.tresult {
    return zig_plug_bridge.writeParameterState(gain_spec.Spec.Params, state, &gain_spec.parameter_set, &parameter_values);
}

fn storeParameterValues(values: *const gain_spec.Spec.ParameterValues) void {
    inline for (0..gain_spec.Spec.ParameterSet.count) |index| {
        if (values.load(index)) |value| {
            _ = parameter_values.store(index, value);
        }
    }
}

test "gain controller can be created as IEditController" {
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
