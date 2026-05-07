const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const iplugview = @import("pluginterfaces/gui/iplugview.zig");
const types = @import("pluginterfaces/base/types.zig");
const interface_map = @import("interface_map.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const cid = tuid.inlineUid(0xF0B8107A, 0x7E654828, 0x9113340B, 0x912D9E70);
pub const gain_param_id: vsttypes.ParamID = 0;

const Controller = extern struct {
    iface: ivsteditcontroller.IEditController = .{ .vtable = &controller_vtable },
    ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
    gain: std.atomic.Value(u64) = std.atomic.Value(u64).init(@bitCast(@as(f64, 1.0))),
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
    return 1;
}

fn getParameterInfo(_: *anyopaque, index: types.int32, out: *ivsteditcontroller.ParameterInfo) callconv(.C) types.tresult {
    if (index != 0) {
        out.* = .{};
        return types.kInvalidArgument;
    }

    out.* = .{
        .id = gain_param_id,
        .defaultNormalizedValue = 1.0,
        .unitId = 0,
        .flags = ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate,
    };
    copyAscii16(&out.title, "Gain");
    copyAscii16(&out.shortTitle, "Gain");
    return types.kResultOk;
}

fn getParamStringByValue(_: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*]vsttypes.TChar) callconv(.C) types.tresult {
    if (id != gain_param_id) return types.kInvalidArgument;
    writePercent(out, value);
    return types.kResultOk;
}

fn getParamValueByString(_: *anyopaque, id: vsttypes.ParamID, _: [*]vsttypes.TChar, out: *vsttypes.ParamValue) callconv(.C) types.tresult {
    if (id != gain_param_id) return types.kInvalidArgument;
    out.* = 0;
    return types.kResultOk;
}

fn normalizedParamToPlain(_: *anyopaque, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    if (id != gain_param_id) return 0;
    return normalized;
}

fn plainParamToNormalized(_: *anyopaque, id: vsttypes.ParamID, plain: vsttypes.ParamValue) callconv(.C) vsttypes.ParamValue {
    if (id != gain_param_id) return 0;
    return plain;
}

fn getParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID) callconv(.C) vsttypes.ParamValue {
    if (id != gain_param_id) return 0;
    return @bitCast(owner(ptr).gain.load(.monotonic));
}

fn setParamNormalized(ptr: *anyopaque, id: vsttypes.ParamID, value: vsttypes.ParamValue) callconv(.C) types.tresult {
    if (id != gain_param_id) return types.kInvalidArgument;
    owner(ptr).gain.store(@bitCast(clamp01(value)), .monotonic);
    return types.kResultOk;
}

fn setComponentHandler(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn createView(_: *anyopaque, _: types.FIDString) callconv(.C) ?*iplugview.IPlugView {
    return null;
}

pub fn gain() vsttypes.ParamValue {
    return @bitCast(controller.gain.load(.monotonic));
}

pub fn setGain(value: vsttypes.ParamValue) void {
    controller.gain.store(@bitCast(clamp01(value)), .monotonic);
}

pub fn readGainState(state: ?*ibstream.IBStream) types.tresult {
    const stream = state orelse return types.kInvalidArgument;
    var bytes: [@sizeOf(f64)]u8 = undefined;
    var read: types.int32 = 0;
    const result = stream.vtable.read(stream, &bytes, bytes.len, &read);
    if (result != types.kResultOk or read != bytes.len) return types.kResultFalse;
    setGain(@bitCast(bytes));
    return types.kResultOk;
}

pub fn writeGainState(state: ?*ibstream.IBStream) types.tresult {
    const stream = state orelse return types.kInvalidArgument;
    const bytes: [@sizeOf(f64)]u8 = @bitCast(gain());
    var written: types.int32 = 0;
    const result = stream.vtable.write(stream, @constCast(&bytes), bytes.len, &written);
    if (result != types.kResultOk or written != bytes.len) return types.kResultFalse;
    return types.kResultOk;
}

fn clamp01(value: vsttypes.ParamValue) vsttypes.ParamValue {
    return @min(@max(value, 0), 1);
}

fn copyAscii16(dest: *vsttypes.String128, source: []const u8) void {
    @memset(dest, 0);
    const len = @min(source.len, dest.len - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

fn writePercent(dest: [*]vsttypes.TChar, value: vsttypes.ParamValue) void {
    const percent = @as(u32, @intFromFloat(@round(clamp01(value) * 100)));
    var buffer: [8]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}%", .{percent}) catch "0%";
    for (text, 0..) |char, index| {
        dest[index] = char;
    }
    dest[text.len] = 0;
}

test "gain controller can be created as IEditController" {
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivsteditcontroller.iedit_controller_iid), &out));
    try std.testing.expect(out != null);
    const controller_iface: *ivsteditcontroller.IEditController = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), controller_iface.vtable.getParameterCount(controller_iface));
    try std.testing.expect(controller_iface.vtable.release(controller_iface) >= 1);
}
