const std = @import("std");
const funknown = @import("funknown.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");
const types = @import("pluginterfaces/base/types.zig");
const gain_controller = @import("gain_controller.zig");
const interface_map = @import("interface_map.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const plug_process = @import("zig-plug-core").process;
const tuid = @import("tuid.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const zig_plug_bridge = @import("zig_plug_bridge.zig");

pub const cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401);

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
    const entries = [_]interface_map.Entry{
        .{ .iid = &funknown.iid, .ptr = ptr },
        .{ .iid = &ipluginbase.iplugin_base_iid, .ptr = ptr },
        .{ .iid = &ivstcomponent.icomponent_iid, .ptr = ptr },
        .{ .iid = &ivstaudioprocessor.iaudio_processor_iid, .ptr = &self.processor },
    };
    return interface_map.queryWithAddRef(ptr, addRef, &entries, requested_iid, out);
}

fn queryFromProcessor(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.C) types.tresult {
    return query(&ownerFromProcessor(ptr).iface, requested_iid, out);
}

fn addRef(ptr: *anyopaque) callconv(.C) types.uint32 {
    return owner(ptr).ref_count.fetchAdd(1, .monotonic) + 1;
}

fn release(ptr: *anyopaque) callconv(.C) types.uint32 {
    return funknown.decrementRefCount(&owner(ptr).ref_count, "GainComponent");
}

fn initialize(_: *anyopaque, _: ?*anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn terminate(_: *anyopaque) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getControllerClassId(_: *anyopaque, out: *tuid.TUID) callconv(.C) types.tresult {
    out.* = gain_controller.cid;
    return types.kResultOk;
}

fn setIoMode(_: *anyopaque, _: vsttypes.IoMode) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn getBusCount(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) callconv(.C) types.int32 {
    return zig_plug_bridge.StereoAudioBuses.busCount(media_type, direction);
}

fn getBusInfo(_: *anyopaque, media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) callconv(.C) types.tresult {
    return zig_plug_bridge.StereoAudioBuses.busInfo(media_type, direction, index, out);
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

fn setState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return gain_controller.readGainState(state);
}

fn getState(_: *anyopaque, state: ?*ibstream.IBStream) callconv(.C) types.tresult {
    return gain_controller.writeGainState(state);
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
    return zig_plug_bridge.StereoAudioBuses.setArrangements(inputs, num_inputs, outputs, num_outputs);
}

fn getBusArrangement(_: *anyopaque, direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) callconv(.C) types.tresult {
    return zig_plug_bridge.StereoAudioBuses.arrangement(direction, index, out);
}

fn canProcessSampleSize(_: *anyopaque, symbolic_sample_size: types.int32) callconv(.C) types.tresult {
    return zig_plug_bridge.RealtimeProcessorDefaults.canProcessSampleSize(symbolic_sample_size);
}

fn getLatencySamples(_: *anyopaque) callconv(.C) types.uint32 {
    return zig_plug_bridge.RealtimeProcessorDefaults.latencySamples();
}

fn setupProcessing(_: *anyopaque, _: *ivstaudioprocessor.ProcessSetup) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn setProcessing(_: *anyopaque, _: types.TBool) callconv(.C) types.tresult {
    return types.kResultOk;
}

fn process(_: *anyopaque, data: *ivstaudioprocessor.ProcessData) callconv(.C) types.tresult {
    var parameter_change_storage: [64]plug_process.ParameterChange = undefined;
    const parameter_changes = zig_plug_bridge.collectInputParameterChanges(data, &parameter_change_storage);
    if (parameter_changes.latest(gain_controller.gain_param_id)) |change| {
        gain_controller.setGain(change.normalized);
    }

    if (data.symbolicSampleSize == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32)) {
        var context = zig_plug_bridge.makeMainAudioProcessContext(f32, data, parameter_changes) catch return types.kResultOk;
        applyGain(f32, &context, @floatCast(gain_controller.gain()));
    } else {
        var context = zig_plug_bridge.makeMainAudioProcessContext(f64, data, parameter_changes) catch return types.kResultOk;
        applyGain(f64, &context, gain_controller.gain());
    }

    return types.kResultOk;
}

fn getTailSamples(_: *anyopaque) callconv(.C) types.uint32 {
    return zig_plug_bridge.RealtimeProcessorDefaults.tailSamples();
}

fn applyGain(comptime Sample: type, context: *plug_process.ProcessContext(Sample), gain: Sample) void {
    for (0..context.outputs.channels.len) |channel| {
        const input = context.inputs.channel(channel) orelse continue;
        const output = context.outputs.channel(channel) orelse continue;
        for (0..context.frameCount()) |sample| {
            output[sample] = input[sample] * gain;
        }
    }
}

test "gain component can be created as IComponent" {
    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expect(component_iface.vtable.release(component_iface) >= 1);
}
