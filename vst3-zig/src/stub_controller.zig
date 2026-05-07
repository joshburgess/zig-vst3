const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const types = @import("pluginterfaces/base/types.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const cid = tuid.inlineUid(0xF0B8107A, 0x7E654828, 0x9113340B, 0x912D9E70);

const Controller = extern struct {
    iface: ivsteditcontroller.IEditController = .{ .vtable = &controller_vtable },
    ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
};

var controller = Controller{};

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
    if (std.mem.eql(u8, requested_iid, &funknown.iid) or
        std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_base_iid) or
        std.mem.eql(u8, requested_iid, &ivsteditcontroller.iedit_controller_iid))
    {
        _ = addRef(ptr);
        out.* = ptr;
        return types.kResultOk;
    }

    out.* = null;
    return types.kNoInterface;
}

fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
    return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
}

fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
    const previous = owner(ptr).ref_count.fetchSub(1, .release);
    if (previous == 0) {
        owner(ptr).ref_count.store(0, .monotonic);
        return 0;
    }
    return previous - 1;
}

fn initialize(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn terminate(_: *anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setComponentState(_: *anyopaque, _: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setState(_: *anyopaque, _: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getState(_: *anyopaque, _: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getParameterCount(_: *anyopaque) callconv(.C) types.int32 {
    return 0;
}

fn getParameterInfo(_: *anyopaque, _: types.int32, out: *ivsteditcontroller.ParameterInfo) callconv(.C) types.tresult {
    out.* = .{};
    return types.kInvalidArgument;
}

fn getParamStringByValue(_: *anyopaque, _: vsttypes.ParamID, _: vsttypes.ParamValue, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
    out[0] = 0;
    return types.kResultOk;
}

fn getParamValueByString(_: *anyopaque, _: vsttypes.ParamID, _: [*]vsttypes.TChar, out: *vsttypes.ParamValue) callconv(.C) types.tresult {
    out.* = 0;
    return types.kResultOk;
}

fn normalizedParamToPlain(_: *anyopaque, _: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    return normalized;
}

fn plainParamToNormalized(_: *anyopaque, _: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    return plain;
}

fn getParamNormalized(_: *anyopaque, _: vsttypes.ParamID) callconv(.C) vsttypes.ParamValue {
    return 0;
}

fn setParamNormalized(_: *anyopaque, _: vsttypes.ParamID, _: vsttypes.ParamValue) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setComponentHandler(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn createView(_: *anyopaque, _: types.FIDString) callconv(.C) ?*iplugview.IPlugView {
    return null;
}

test "stub controller can be created as IEditController" {
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 0), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
