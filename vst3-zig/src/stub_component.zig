const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const types = @import("pluginterfaces/base/types.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

pub const cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401);
const kEmptyArrangement: vsttypes.SpeakerArrangement = 0;
const kStereoArrangement: vsttypes.SpeakerArrangement = 3;

const Component = extern struct {
    iface: ivstcomponent.IComponent = .{ .vtable = &component_vtable },
    processor: ivstaudioprocessor.IAudioProcessor = .{ .vtable = &processor_vtable },
    ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
};

var component = Component{};

pub fn create(requested_iid: types.FIDString, out: *?*anyopaque) callconv(.C) types.tresult {
    return query(&component.iface, @ptrCast(requested_iid), out);
}

const component_vtable = ivstcomponent.IComponentVTable{
    .queryInterface = query,
    .addRef = addRef,
    .release = release,
    .initialize = initialize,
    .terminate = terminate,
    .getControllerClassId = getControllerClassId,
    .setIoMode = setIoMode,
    .getBusCount = getBusCount,
    .getBusInfo = getBusInfo,
    .getRoutingInfo = getRoutingInfo,
    .activateBus = activateBus,
    .setActive = setActive,
    .setState = setState,
    .getState = getState,
};

fn owner(ptr: *anyopaque) *Component {
    const iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("iface", iface);
}

fn ownerFromProcessor(ptr: *anyopaque) *Component {
    const iface: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(ptr));
    return @fieldParentPtr("processor", iface);
}

fn query(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
    const self = owner(ptr);
    if (std.mem.eql(u8, requested_iid, &funknown.iid) or
        std.mem.eql(u8, requested_iid, &ipluginbase.iplugin_base_iid) or
        std.mem.eql(u8, requested_iid, &ivstcomponent.icomponent_iid))
    {
        _ = addRef(ptr);
        out.* = ptr;
        return types.kResultOk;
    }
    if (std.mem.eql(u8, requested_iid, &ivstaudioprocessor.iaudio_processor_iid)) {
        _ = addRef(ptr);
        out.* = &self.processor;
        return types.kResultOk;
    }

    out.* = null;
    return types.kNoInterface;
}

fn queryFromProcessor(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
    return query(&ownerFromProcessor(ptr).iface, requested_iid, out);
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

fn getControllerClassId(_: *anyopaque, out: *tuid.TUID) callconv(.C) types.tresult {
    out.* = [_]u8{0} ** 16;
    return types.kNoInterface;
}

fn setIoMode(_: *anyopaque, _: vsttypes.IoMode) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getBusCount(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) callconv(.C) types.int32 {
    if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and
        (direction == @intFromEnum(ivstcomponent.BusDirections.kInput) or direction == @intFromEnum(ivstcomponent.BusDirections.kOutput)))
    {
        return 1;
    }
    return 0;
}

fn getBusInfo(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) callconv(.C) types.tresult {
    if (media_type != @intFromEnum(ivstcomponent.MediaTypes.kAudio) or index != 0) {
        out.* = .{};
        return types.kInvalidArgument;
    }
    if (direction != @intFromEnum(ivstcomponent.BusDirections.kInput) and direction != @intFromEnum(ivstcomponent.BusDirections.kOutput)) {
        out.* = .{};
        return types.kInvalidArgument;
    }

    out.* = .{
        .mediaType = media_type,
        .direction = direction,
        .channelCount = 2,
        .busType = @intFromEnum(ivstcomponent.BusTypes.kMain),
        .flags = ivstcomponent.BusFlags.kDefaultActive,
    };
    if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) {
        copyAscii16(&out.name, "Stereo In");
    } else {
        copyAscii16(&out.name, "Stereo Out");
    }
    return types.kResultOk;
}

fn getRoutingInfo(_: *anyopaque, _: *ivstcomponent.RoutingInfo, _: *ivstcomponent.RoutingInfo) callconv(.C) types.tresult {
    return types.kNoInterface;
}

fn activateBus(_: *anyopaque, _: vsttypes.MediaType, _: vsttypes.BusDirection, _: types.int32, _: types.TBool) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setActive(_: *anyopaque, _: types.TBool) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setState(_: *anyopaque, _: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getState(_: *anyopaque, _: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn copyAscii16(dest: *vsttypes.String128, source: []const u8) void {
    @memset(dest, 0);
    const len = @min(source.len, dest.len - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

const processor_vtable = ivstaudioprocessor.IAudioProcessorVTable{
    .queryInterface = queryFromProcessor,
    .addRef = addRefFromProcessor,
    .release = releaseFromProcessor,
    .setBusArrangements = setBusArrangements,
    .getBusArrangement = getBusArrangement,
    .canProcessSampleSize = canProcessSampleSize,
    .getLatencySamples = getLatencySamples,
    .setupProcessing = setupProcessing,
    .setProcessing = setProcessing,
    .process = process,
    .getTailSamples = getTailSamples,
};

fn addRefFromProcessor(ptr: *anyopaque) callconv(.C) types.uint32 {
    return addRef(&ownerFromProcessor(ptr).iface);
}

fn releaseFromProcessor(ptr: *anyopaque) callconv(.C) types.uint32 {
    return release(&ownerFromProcessor(ptr).iface);
}

fn setBusArrangements(_: *anyopaque, inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) callconv(.C) types.tresult {
    if (num_inputs != 1 or num_outputs != 1 or inputs == null or outputs == null) {
        return types.kResultFalse;
    }
    if (inputs.?[0] != kStereoArrangement or outputs.?[0] != kStereoArrangement) {
        return types.kResultFalse;
    }
    return types.kResultOk;
}

fn getBusArrangement(_: *anyopaque, direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) callconv(.C) types.tresult {
    if (index != 0 or
        (direction != @intFromEnum(ivstcomponent.BusDirections.kInput) and direction != @intFromEnum(ivstcomponent.BusDirections.kOutput)))
    {
        out.* = kEmptyArrangement;
        return types.kInvalidArgument;
    }
    out.* = kStereoArrangement;
    return types.kResultOk;
}

fn canProcessSampleSize(_: *anyopaque, symbolic_sample_size: types.int32) callconv(.C) types.tresult {
    if (symbolic_sample_size == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32) or
        symbolic_sample_size == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64))
    {
        return types.kResultOk;
    }
    return types.kResultFalse;
}

fn getLatencySamples(_: *anyopaque) callconv(.C) types.uint32 {
    return 0;
}

fn setupProcessing(_: *anyopaque, _: *ivstaudioprocessor.ProcessSetup) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setProcessing(_: *anyopaque, _: types.TBool) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn process(_: *anyopaque, _: *ivstaudioprocessor.ProcessData) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getTailSamples(_: *anyopaque) callconv(.C) types.uint32 {
    return ivstaudioprocessor.kNoTail;
}

test "stub component can be created as IComponent" {
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}
