const gain_controller = @import("gain_controller.zig");
const gain_spec = @import("gain_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
const component_api = @import("pluginterfaces/vst/ivstcomponent.zig");
const plug_process = @import("zig-vst3-plugin-core").process;
const plug_state = @import("zig-vst3-plugin-core").state;
const tuid = @import("tuid.zig");
const types = @import("pluginterfaces/base/types.zig");
const vst_host_application = @import("vst_host_application.zig");
const vst_host_context = @import("vst_host_context.zig");
const vst_stream = @import("vst_stream.zig");
const zig_vst3_plugin_effect = @import("zig_vst3_plugin_effect.zig");

pub const cid = tuid.inlineUid(0xA74E7A0D, 0x6B234163, 0xA0A83EBF, 0xD06F1401);

const GainProcessor = struct {
    pub fn process(_: *GainProcessor, parameters: anytype, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(parameters.getNormalizedById(gain_controller.gain_param_id));
        for (0..context.outputChannelCount()) |channel| {
            const input = context.inputChannel(channel) orelse continue;
            const output = context.outputChannel(channel) orelse continue;
            for (0..context.frameCount()) |sample| {
                output[sample] = input[sample] * gain;
            }
        }
    }
};

const Effect = zig_vst3_plugin_effect.SimpleStereoEffect(struct {
    pub const component_name = "GainComponent";
    pub const controller_cid = gain_controller.cid;
    pub const Params = gain_spec.Spec.Params;
    pub const parameter_set = &gain_spec.parameter_set;
    pub const Processor = GainProcessor;
});

pub const create = Effect.create;

pub fn setChannelContextInfos(iface: *component_api.IComponent, attributes: ?*ivstattributes.IAttributeList) types.tresult {
    return Effect.setChannelContextInfos(iface, attributes);
}

pub fn setAutomationState(iface: *component_api.IComponent, state: types.int32) types.tresult {
    return Effect.setAutomationState(iface, state);
}

pub fn openDataExchangeQueue(iface: *component_api.IComponent, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.openDataExchangeQueue(iface, block_size, num_blocks, alignment, user_context_id, out);
}

pub fn closeDataExchangeQueue(iface: *component_api.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.closeDataExchangeQueue(iface, queue_id);
}

pub fn lockDataExchangeBlock(iface: *component_api.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
    return Effect.lockDataExchangeBlock(iface, queue_id, block);
}

pub fn freeDataExchangeBlock(iface: *component_api.IComponent, queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, send_to_receiver: types.TBool) types.tresult {
    return Effect.freeDataExchangeBlock(iface, queue_id, block_id, send_to_receiver);
}

test "gain component can be created as IComponent" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ipluginbase = @import("pluginterfaces/base/ipluginbase.zig");

    var out: ?*anyopaque = null;

    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    try std.testing.expectEqual(@as(types.int32, 1), component_iface.vtable.getBusCount(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));

    var plugin_base_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.queryInterface(component_iface, &ipluginbase.iplugin_base_iid, &plugin_base_out));
    try std.testing.expect(plugin_base_out != null);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrCast(component_iface)), plugin_base_out);
    _ = component_iface.vtable.release(component_iface);

    const missing_iid = tuid.inlineUid(0x11111111, 0x22222222, 0x33333333, 0x44444444);
    var missing_out: ?*anyopaque = @ptrFromInt(0x1000);
    try std.testing.expectEqual(types.kNoInterface, component_iface.vtable.queryInterface(component_iface, &missing_iid, &missing_out));
    try std.testing.expectEqual(@as(?*anyopaque, null), missing_out);

    var controller_cid: tuid.TUID = tuid.zero;
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getControllerClassId(component_iface, &controller_cid));
    try std.testing.expectEqualSlices(u8, &gain_controller.cid, &controller_cid);
    _ = component_iface.vtable.release(component_iface);
}

test "gain component instances isolate parameter state" {
    const std = @import("std");

    var first_out: ?*anyopaque = null;
    var second_out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&component_api.icomponent_iid), &first_out));
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&component_api.icomponent_iid), &second_out));
    const first: *component_api.IComponent = @ptrCast(@alignCast(first_out.?));
    defer _ = first.vtable.release(first);
    const second: *component_api.IComponent = @ptrCast(@alignCast(second_out.?));
    defer _ = second.vtable.release(second);

    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(first, gain_controller.gain_param_id, 0.25));
    try std.testing.expectEqual(@as(f64, 0.25), Effect.getParameterNormalized(first, gain_controller.gain_param_id));
    try std.testing.expectEqual(@as(f64, 1.0), Effect.getParameterNormalized(second, gain_controller.gain_param_id));
}

test "gain components can be repeatedly created and destroyed" {
    const std = @import("std");

    for (0..64) |_| {
        var out: ?*anyopaque = null;
        try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&component_api.icomponent_iid), &out));
        const component_iface: *component_api.IComponent = @ptrCast(@alignCast(out.?));
        try std.testing.expectEqual(@as(types.uint32, 0), component_iface.vtable.release(component_iface));
    }
}

test "gain component reports deterministic component bus defaults" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var input_info = ivstcomponent.BusInfo{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getBusInfo(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &input_info));
    try std.testing.expectEqual(@as(types.int32, 2), input_info.channelCount);

    input_info.channelCount = 99;
    try std.testing.expectEqual(types.kInvalidArgument, component_iface.vtable.getBusInfo(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 1, &input_info));
    try std.testing.expectEqual(@as(types.int32, 0), input_info.channelCount);

    var source = ivstcomponent.RoutingInfo{};
    var destination = ivstcomponent.RoutingInfo{};
    try std.testing.expectEqual(types.kNoInterface, component_iface.vtable.getRoutingInfo(component_iface, &source, &destination));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.activateBus(component_iface, @intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, 1));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setIoMode(component_iface, @intFromEnum(ivstcomponent.IoModes.kSimple)));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setActive(component_iface, 0));
}

test "gain component exposes process context requirements" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iprocess_context_requirements_iid, &requirements_out),
    );
    try std.testing.expect(requirements_out != null);
    const requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(requirements_out.?));
    defer _ = requirements.vtable.release(requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), requirements.vtable.getProcessContextRequirements(requirements));

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var processor_requirements_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        processor.vtable.queryInterface(processor, &ivstaudioprocessor.iprocess_context_requirements_iid, &processor_requirements_out),
    );
    try std.testing.expect(processor_requirements_out != null);
    const processor_requirements: *ivstaudioprocessor.IProcessContextRequirements = @ptrCast(@alignCast(processor_requirements_out.?));
    defer _ = processor_requirements.vtable.release(processor_requirements);

    try std.testing.expectEqual(@as(types.uint32, 0), processor_requirements.vtable.getProcessContextRequirements(processor_requirements));
}

test "gain component validates host process setup" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var setup = ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(ivstaudioprocessor.ProcessModes.kRealtime),
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .maxSamplesPerBlock = 64,
        .sampleRate = 48_000.0,
    };
    try std.testing.expectEqual(types.kResultOk, processor.vtable.setupProcessing(processor, &setup));

    setup.sampleRate = 0.0;
    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.setupProcessing(processor, &setup));

    setup.sampleRate = std.math.inf(f64);
    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.setupProcessing(processor, &setup));

    setup.sampleRate = 48_000.0;
    setup.maxSamplesPerBlock = 0;
    try std.testing.expectEqual(types.kInvalidArgument, processor.vtable.setupProcessing(processor, &setup));

    setup.maxSamplesPerBlock = 64;
    setup.symbolicSampleSize = 99;
    try std.testing.expectEqual(types.kResultFalse, processor.vtable.setupProcessing(processor, &setup));
}

test "gain component rejects unsupported process sample size" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    var data = ivstaudioprocessor.ProcessData{
        .symbolicSampleSize = 99,
        .numSamples = 0,
    };

    try std.testing.expectEqual(types.kResultFalse, processor.vtable.process(processor, &data));
}

test "gain component applies host parameter changes through processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const gain_queue = changes.addQueue(gain_controller.gain_param_id).?;
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(0, 0.5));

    var input_samples = [_]f32{ 1.0, -0.5, 0.25 };
    var output_samples = [_]f32{ 0.0, 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&input_samples};
    var output_channel_ptrs = [_][*]f32{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f32, &.{ 0.5, -0.25, 0.125 }, &output_samples);
    try std.testing.expectEqual(@as(f64, 0.5), Effect.getParameterNormalized(component_iface, gain_controller.gain_param_id));
}

test "gain component applies host parameter changes through double precision processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var processor_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_processor_iid, &processor_out),
    );
    try std.testing.expect(processor_out != null);
    const processor: *ivstaudioprocessor.IAudioProcessor = @ptrCast(@alignCast(processor_out.?));
    defer _ = processor.vtable.release(processor);

    const Changes = vst_parameter_changes.ParameterChanges(1, 1);
    var changes = Changes{};
    const gain_queue = changes.addQueue(gain_controller.gain_param_id).?;
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(0, 0.5));

    var input_samples = [_]f64{ 1.0, -0.5, 0.25 };
    var output_samples = [_]f64{ 0.0, 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f64{&input_samples};
    var output_channel_ptrs = [_][*]f64{&output_samples};
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 48_000.0 };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .inputParameterChanges = changes.asInterface(),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processor.vtable.process(processor, &data));
    try std.testing.expectEqualSlices(f64, &.{ 0.5, -0.25, 0.125 }, &output_samples);
    try std.testing.expectEqual(@as(f64, 0.5), Effect.getParameterNormalized(component_iface, gain_controller.gain_param_id));
}

test "gain component queries host application during initialize" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const HostApplication = vst_host_application.HostApplication("Test Host", struct {});

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostApplication{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 4), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 0), host.release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 8), host.query_count);
    try std.testing.expectEqual(@as(types.uint32, 2), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.release_count);
}

test "gain component stores channel context info listener" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const HostContext = vst_host_context.ChannelContextHost("Test Host", struct {});

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    try std.testing.expectEqual(types.kResultFalse, setChannelContextInfos(component_iface, null));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setChannelContextInfos(component_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.channel_context_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 2), host.info_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.info_release_count);
}

test "gain component stores automation state host interface" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    const HostContext = vst_host_context.AutomationStateHost("Test Host", struct {});

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    try std.testing.expectEqual(types.kResultFalse, setAutomationState(component_iface, ivstautomationstate.AutomationStates.kReadState));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setAutomationState(component_iface, ivstautomationstate.AutomationStates.kReadWriteState));
    try std.testing.expectEqual(ivstautomationstate.AutomationStates.kReadWriteState, host.last_state);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 2), host.automation_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.automation_release_count);
}

test "gain component exposes default connection point" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
    const vst_message = @import("vst_message.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var connection_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstmessage.iconnection_point_iid, &connection_out),
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

test "gain component exposes default processor capability interfaces" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");
    const ivstprefetchablesupport = @import("pluginterfaces/vst/ivstprefetchablesupport.zig");
    const ivstunits = @import("pluginterfaces/vst/ivstunits.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var latency_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstaudioprocessor.iaudio_presentation_latency_iid, &latency_out),
    );
    try std.testing.expect(latency_out != null);
    const latency: *ivstaudioprocessor.IAudioPresentationLatency = @ptrCast(@alignCast(latency_out.?));
    defer _ = latency.vtable.release(latency);
    try std.testing.expectEqual(
        types.kResultOk,
        latency.vtable.setAudioPresentationLatencySamples(latency, @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, 0),
    );

    var support_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstpluginterfacesupport.iplug_interface_support_iid, &support_out),
    );
    try std.testing.expect(support_out != null);
    const support: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(support_out.?));
    defer _ = support.vtable.release(support);
    const ivstmessage = @import("pluginterfaces/vst/ivstmessage.zig");
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstmessage.iconnection_point_iid));
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstaudioprocessor.iaudio_processor_iid));
    try std.testing.expectEqual(types.kResultFalse, support.vtable.isPlugInterfaceSupported(support, &ivstunits.iunit_info_iid));

    var prefetch_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstprefetchablesupport.iprefetchable_support_iid, &prefetch_out),
    );
    try std.testing.expect(prefetch_out != null);
    const prefetch: *ivstprefetchablesupport.IPrefetchableSupport = @ptrCast(@alignCast(prefetch_out.?));
    defer _ = prefetch.vtable.release(prefetch);

    var prefetchable: ivstprefetchablesupport.PrefetchableSupport = 99;
    try std.testing.expectEqual(types.kResultOk, prefetch.vtable.getPrefetchableSupport(prefetch, &prefetchable));
    try std.testing.expectEqual(@as(types.uint32, @intFromEnum(ivstprefetchablesupport.ePrefetchableSupport.kIsNeverPrefetchable)), prefetchable);
}

test "gain component exposes default data exchange receiver" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstpluginterfacesupport = @import("pluginterfaces/vst/ivstpluginterfacesupport.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var receiver_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstdataexchange.idata_exchange_receiver_iid, &receiver_out),
    );
    try std.testing.expect(receiver_out != null);
    const receiver: *ivstdataexchange.IDataExchangeReceiver = @ptrCast(@alignCast(receiver_out.?));
    defer _ = receiver.vtable.release(receiver);

    var accepted: types.TBool = 1;
    receiver.vtable.queueOpened(receiver, 9, 128, &accepted);
    try std.testing.expectEqual(@as(types.TBool, 0), accepted);
    receiver.vtable.queueClosed(receiver, 9);
    receiver.vtable.onDataExchangeBlocksReceived(receiver, 9, 0, null, 0);

    var support_out: ?*anyopaque = null;
    try std.testing.expectEqual(
        types.kResultOk,
        component_iface.vtable.queryInterface(component_iface, &ivstpluginterfacesupport.iplug_interface_support_iid, &support_out),
    );
    try std.testing.expect(support_out != null);
    const support: *ivstpluginterfacesupport.IPlugInterfaceSupport = @ptrCast(@alignCast(support_out.?));
    defer _ = support.vtable.release(support);
    try std.testing.expectEqual(types.kResultOk, support.vtable.isPlugInterfaceSupported(support, &ivstdataexchange.idata_exchange_receiver_iid));

    var queue_id: ivstdataexchange.DataExchangeQueueID = 0;
    try std.testing.expectEqual(types.kResultFalse, openDataExchangeQueue(component_iface, 128, 2, 8, 9, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);
}

test "gain component stores data exchange handler" {
    const std = @import("std");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    const HostContext = vst_host_context.DataExchangeHost("Test Host", struct {
        pub fn openQueue(_: anytype, processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, _: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            if (processor == null or block_size != 128 or num_blocks != 2 or alignment != 8) {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kInvalidArgument;
            }
            out.* = 44;
            return types.kResultOk;
        }

        pub fn closeQueue(_: anytype, queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }

        pub fn lockBlock(_: anytype, _: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            block.* = .{ .blockID = 7 };
            return types.kResultOk;
        }

        pub fn freeBlock(_: anytype, _: ivstdataexchange.DataExchangeQueueID, _: ivstdataexchange.DataExchangeBlockID, _: types.TBool) types.tresult {
            return types.kResultOk;
        }
    });

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.add_ref_count);

    var queue_id: ivstdataexchange.DataExchangeQueueID = 0;
    try std.testing.expectEqual(types.kResultOk, openDataExchangeQueue(component_iface, 128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), queue_id);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), host.last_user_context_id);
    try std.testing.expectEqual(types.kResultOk, closeDataExchangeQueue(component_iface, queue_id));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 2), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.release_count);
}

test "gain component delegates combined advanced host integration lifecycle" {
    const std = @import("std");
    const funknown = @import("funknown.zig");
    const interface_map = @import("interface_map.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstchannelcontextinfo = @import("pluginterfaces/vst/ivstchannelcontextinfo.zig");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivsthostapplication = @import("pluginterfaces/vst/ivsthostapplication.zig");
    const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

    const HostContext = extern struct {
        const Self = @This();

        host_application: ivsthostapplication.IHostApplication = .{ .vtable = &host_vtable },
        info_listener: ivstchannelcontextinfo.IInfoListener = .{ .vtable = &info_vtable },
        automation_state: ivstautomationstate.IAutomationState = .{ .vtable = &automation_vtable },
        data_exchange_handler: ivstdataexchange.IDataExchangeHandler = .{ .vtable = &data_exchange_vtable },
        host_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        info_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        automation_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        data_exchange_ref_count: std.atomic.Value(types.uint32) = std.atomic.Value(types.uint32).init(1),
        host_add_ref_count: types.uint32 = 0,
        host_release_count: types.uint32 = 0,
        info_add_ref_count: types.uint32 = 0,
        info_release_count: types.uint32 = 0,
        automation_add_ref_count: types.uint32 = 0,
        automation_release_count: types.uint32 = 0,
        data_exchange_add_ref_count: types.uint32 = 0,
        data_exchange_release_count: types.uint32 = 0,
        channel_context_count: types.uint32 = 0,
        last_automation_state: types.int32 = ivstautomationstate.AutomationStates.kNoAutomation,
        open_count: types.uint32 = 0,
        close_count: types.uint32 = 0,
        last_user_context_id: ivstdataexchange.DataExchangeUserContextID = 0,
        last_queue_id: ivstdataexchange.DataExchangeQueueID = ivstdataexchange.InvalidDataExchangeQueueID,
        freed_block_id: ivstdataexchange.DataExchangeBlockID = ivstdataexchange.InvalidDataExchangeBlockID,

        fn asHostApplication(self: *Self) *ivsthostapplication.IHostApplication {
            return &self.host_application;
        }

        const ownerFromHost = interface_map.ownerFromField(Self, ivsthostapplication.IHostApplication, "host_application");
        const ownerFromInfo = interface_map.ownerFromField(Self, ivstchannelcontextinfo.IInfoListener, "info_listener");
        const ownerFromAutomation = interface_map.ownerFromField(Self, ivstautomationstate.IAutomationState, "automation_state");
        const ownerFromDataExchange = interface_map.ownerFromField(Self, ivstdataexchange.IDataExchangeHandler, "data_exchange_handler");

        fn queryHost(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromHost(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.host_application },
                .{ .iid = &ivsthostapplication.ihost_application_iid, .ptr = &self.host_application },
                .{ .iid = &ivstchannelcontextinfo.iinfo_listener_iid, .ptr = &self.info_listener },
                .{ .iid = &ivstautomationstate.iautomation_state_iid, .ptr = &self.automation_state },
                .{ .iid = &ivstdataexchange.idata_exchange_handler_iid, .ptr = &self.data_exchange_handler },
            };
            if (std.mem.eql(u8, requested_iid, &ivstchannelcontextinfo.iinfo_listener_iid)) return interface_map.queryWithAddRef(&self.info_listener, addRefInfo, &entries, requested_iid, out);
            if (std.mem.eql(u8, requested_iid, &ivstautomationstate.iautomation_state_iid)) return interface_map.queryWithAddRef(&self.automation_state, addRefAutomation, &entries, requested_iid, out);
            if (std.mem.eql(u8, requested_iid, &ivstdataexchange.idata_exchange_handler_iid)) return interface_map.queryWithAddRef(&self.data_exchange_handler, addRefDataExchange, &entries, requested_iid, out);
            return interface_map.queryWithAddRef(&self.host_application, addRefHost, &entries, requested_iid, out);
        }

        fn queryInfo(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromInfo(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.info_listener },
                .{ .iid = &ivstchannelcontextinfo.iinfo_listener_iid, .ptr = &self.info_listener },
            };
            return interface_map.queryWithAddRef(&self.info_listener, addRefInfo, &entries, requested_iid, out);
        }

        fn queryAutomation(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromAutomation(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.automation_state },
                .{ .iid = &ivstautomationstate.iautomation_state_iid, .ptr = &self.automation_state },
            };
            return interface_map.queryWithAddRef(&self.automation_state, addRefAutomation, &entries, requested_iid, out);
        }

        fn queryDataExchange(ptr: *anyopaque, requested_iid: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            const entries = [_]interface_map.Entry{
                .{ .iid = &funknown.iid, .ptr = &self.data_exchange_handler },
                .{ .iid = &ivstdataexchange.idata_exchange_handler_iid, .ptr = &self.data_exchange_handler },
            };
            return interface_map.queryWithAddRef(&self.data_exchange_handler, addRefDataExchange, &entries, requested_iid, out);
        }

        fn addRefHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHost(ptr);
            self.host_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.host_ref_count, "IHostApplication");
        }

        fn releaseHost(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromHost(ptr);
            self.host_release_count +|= 1;
            return funknown.decrementRefCount(&self.host_ref_count, "IHostApplication");
        }

        fn addRefInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.info_ref_count, "IInfoListener");
        }

        fn releaseInfo(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromInfo(ptr);
            self.info_release_count +|= 1;
            return funknown.decrementRefCount(&self.info_ref_count, "IInfoListener");
        }

        fn addRefAutomation(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.automation_ref_count, "IAutomationState");
        }

        fn releaseAutomation(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromAutomation(ptr);
            self.automation_release_count +|= 1;
            return funknown.decrementRefCount(&self.automation_ref_count, "IAutomationState");
        }

        fn addRefDataExchange(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.data_exchange_add_ref_count +|= 1;
            return funknown.incrementRefCount(&self.data_exchange_ref_count, "IDataExchangeHandler");
        }

        fn releaseDataExchange(ptr: *anyopaque) callconv(.c) types.uint32 {
            const self = ownerFromDataExchange(ptr);
            self.data_exchange_release_count +|= 1;
            return funknown.decrementRefCount(&self.data_exchange_ref_count, "IDataExchangeHandler");
        }

        fn getName(_: *anyopaque, out: [*]vsttypes.TChar) callconv(.c) types.tresult {
            out[0] = 0;
            return types.kResultOk;
        }

        fn createInstance(_: *anyopaque, _: *const tuid.TUID, _: *const tuid.TUID, out: *?*anyopaque) callconv(.c) types.tresult {
            out.* = null;
            return types.kResultFalse;
        }

        fn recordChannelContextInfos(ptr: *anyopaque, _: ?*ivstattributes.IAttributeList) callconv(.c) types.tresult {
            ownerFromInfo(ptr).channel_context_count +|= 1;
            return types.kResultOk;
        }

        fn recordAutomationState(ptr: *anyopaque, state: types.int32) callconv(.c) types.tresult {
            ownerFromAutomation(ptr).last_automation_state = state;
            return types.kResultOk;
        }

        fn openQueue(ptr: *anyopaque, processor: ?*ivstaudioprocessor.IAudioProcessor, block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.open_count +|= 1;
            self.last_user_context_id = user_context_id;
            if (processor == null or block_size != 256 or num_blocks != 3 or alignment != 16) {
                out.* = ivstdataexchange.InvalidDataExchangeQueueID;
                return types.kInvalidArgument;
            }
            out.* = 44;
            return types.kResultOk;
        }

        fn closeQueue(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            self.close_count +|= 1;
            self.last_queue_id = queue_id;
            return if (queue_id == 44) types.kResultOk else types.kInvalidArgument;
        }

        fn lockBlock(_: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) callconv(.c) types.tresult {
            if (queue_id != 44) return types.kInvalidArgument;
            block.* = .{ .blockID = 12, .size = 256, .data = @ptrFromInt(0x1000) };
            return types.kResultOk;
        }

        fn freeBlock(ptr: *anyopaque, queue_id: ivstdataexchange.DataExchangeQueueID, block_id: ivstdataexchange.DataExchangeBlockID, send_to_receiver: types.TBool) callconv(.c) types.tresult {
            const self = ownerFromDataExchange(ptr);
            if (queue_id != 44 or block_id != 12 or send_to_receiver != 1) return types.kInvalidArgument;
            self.freed_block_id = block_id;
            return types.kResultOk;
        }

        const host_vtable = ivsthostapplication.IHostApplicationVTable{
            .queryInterface = queryHost,
            .addRef = addRefHost,
            .release = releaseHost,
            .getName = getName,
            .createInstance = createInstance,
        };

        const info_vtable = ivstchannelcontextinfo.IInfoListenerVTable{
            .queryInterface = queryInfo,
            .addRef = addRefInfo,
            .release = releaseInfo,
            .setChannelContextInfos = recordChannelContextInfos,
        };

        const automation_vtable = ivstautomationstate.IAutomationStateVTable{
            .queryInterface = queryAutomation,
            .addRef = addRefAutomation,
            .release = releaseAutomation,
            .setAutomationState = recordAutomationState,
        };

        const data_exchange_vtable = ivstdataexchange.IDataExchangeHandlerVTable{
            .queryInterface = queryDataExchange,
            .addRef = addRefDataExchange,
            .release = releaseDataExchange,
            .openQueue = openQueue,
            .closeQueue = closeQueue,
            .lockBlock = lockBlock,
            .freeBlock = freeBlock,
        };
    };

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.host_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.data_exchange_add_ref_count);

    try std.testing.expectEqual(types.kResultOk, setChannelContextInfos(component_iface, null));
    try std.testing.expectEqual(@as(types.uint32, 1), host.channel_context_count);
    try std.testing.expectEqual(types.kResultOk, setAutomationState(component_iface, ivstautomationstate.AutomationStates.kReadWriteState));
    try std.testing.expectEqual(ivstautomationstate.AutomationStates.kReadWriteState, host.last_automation_state);

    var queue_id: ivstdataexchange.DataExchangeQueueID = ivstdataexchange.InvalidDataExchangeQueueID;
    try std.testing.expectEqual(types.kResultOk, openDataExchangeQueue(component_iface, 256, 3, 16, 99, &queue_id));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), queue_id);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 99), host.last_user_context_id);

    var block = ivstdataexchange.DataExchangeBlock{};
    try std.testing.expectEqual(types.kResultOk, lockDataExchangeBlock(component_iface, queue_id, &block));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 12), block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 256), block.size);
    try std.testing.expectEqual(@as(?*anyopaque, @ptrFromInt(0x1000)), block.data);
    try std.testing.expectEqual(types.kResultOk, freeDataExchangeBlock(component_iface, queue_id, block.blockID, 1));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeBlockID, 12), host.freed_block_id);
    try std.testing.expectEqual(types.kResultOk, closeDataExchangeQueue(component_iface, queue_id));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 1), host.host_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_release_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.data_exchange_release_count);
}

test "gain component clears failed data exchange outputs" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");

    const HostContext = vst_host_context.DataExchangeHost("Failing Host", struct {
        pub fn openQueue(_: anytype, _: ?*ivstaudioprocessor.IAudioProcessor, _: types.uint32, _: types.uint32, _: types.uint32, _: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
            out.* = 44;
            return types.kResultFalse;
        }

        pub fn lockBlock(_: anytype, _: ivstdataexchange.DataExchangeQueueID, block: *ivstdataexchange.DataExchangeBlock) types.tresult {
            block.* = .{ .blockID = 12, .size = 64, .data = @ptrFromInt(0x1000) };
            return types.kResultFalse;
        }
    });

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    defer _ = component_iface.vtable.terminate(component_iface);

    var queue_id: ivstdataexchange.DataExchangeQueueID = 1;
    try std.testing.expectEqual(types.kResultFalse, openDataExchangeQueue(component_iface, 128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeQueueID, queue_id);

    var block = ivstdataexchange.DataExchangeBlock{ .blockID = 7, .size = 8, .data = @ptrFromInt(0x2000) };
    try std.testing.expectEqual(types.kResultFalse, lockDataExchangeBlock(component_iface, 44, &block));
    try std.testing.expectEqual(ivstdataexchange.InvalidDataExchangeBlockID, block.blockID);
    try std.testing.expectEqual(@as(types.uint32, 0), block.size);
    try std.testing.expectEqual(@as(?*anyopaque, null), block.data);
}

test "gain component round-trips gain state through host callbacks" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);
    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(component_iface, gain_controller.gain_param_id, 0.5));

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(gain_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encodedSize(gain_spec.Spec.Params)), stream.data().len);

    try std.testing.expectEqual(types.kResultOk, Effect.setParameterNormalized(component_iface, gain_controller.gain_param_id, 1.0));
    try std.testing.expectEqual(@as(f64, 1.0), Effect.getParameterNormalized(component_iface, gain_controller.gain_param_id));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), Effect.getParameterNormalized(component_iface, gain_controller.gain_param_id), 0.000001);
}
