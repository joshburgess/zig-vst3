const gain_controller = @import("gain_controller.zig");
const gain_spec = @import("gain_spec.zig");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstattributes = @import("pluginterfaces/vst/ivstattributes.zig");
const ivstautomationstate = @import("pluginterfaces/vst/ivstautomationstate.zig");
const ivstdataexchange = @import("pluginterfaces/vst/ivstdataexchange.zig");
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
    pub fn process(_: GainProcessor, comptime Sample: type, context: *plug_process.ProcessContext(Sample)) void {
        const gain: Sample = @floatCast(gain_controller.gain());
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
    pub const Processor = GainProcessor;

    pub fn applyParameterChanges(changes: plug_process.ParameterChanges) void {
        gain_controller.applyParameterChanges(changes);
    }

    pub fn readState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.readGainState(state);
    }

    pub fn writeState(state: ?*ibstream.IBStream) types.tresult {
        return gain_controller.writeGainState(state);
    }
});

pub const create = Effect.create;

pub fn setChannelContextInfos(attributes: ?*ivstattributes.IAttributeList) types.tresult {
    return Effect.setChannelContextInfos(attributes);
}

pub fn setAutomationState(state: types.int32) types.tresult {
    return Effect.setAutomationState(state);
}

pub fn openDataExchangeQueue(block_size: types.uint32, num_blocks: types.uint32, alignment: types.uint32, user_context_id: ivstdataexchange.DataExchangeUserContextID, out: *ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.openDataExchangeQueue(block_size, num_blocks, alignment, user_context_id, out);
}

pub fn closeDataExchangeQueue(queue_id: ivstdataexchange.DataExchangeQueueID) types.tresult {
    return Effect.closeDataExchangeQueue(queue_id);
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

    gain_controller.setGain(1.0);
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
    try std.testing.expectEqual(@as(f64, 0.5), gain_controller.gain());
}

test "gain component applies host parameter changes through double precision processor shell" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
    const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
    const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
    const vst_parameter_changes = @import("vst_parameter_changes.zig");

    gain_controller.setGain(1.0);
    defer gain_controller.setGain(1.0);

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
    try std.testing.expectEqual(@as(f64, 0.5), gain_controller.gain());
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

    try std.testing.expectEqual(types.kResultFalse, setChannelContextInfos(null));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.info_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setChannelContextInfos(null));
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

    try std.testing.expectEqual(types.kResultFalse, setAutomationState(ivstautomationstate.AutomationStates.kReadState));

    var host = HostContext{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 1), host.automation_add_ref_count);
    try std.testing.expectEqual(types.kResultOk, setAutomationState(ivstautomationstate.AutomationStates.kReadWriteState));
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
    try std.testing.expectEqual(types.kInvalidArgument, connection.vtable.connect(connection, null));
    try std.testing.expectEqual(@as(types.uint32, 0), peer.release_count);
    try std.testing.expectEqual(types.kResultOk, connection.vtable.disconnect(connection, peer.asInterface()));
    try std.testing.expectEqual(@as(types.uint32, 1), peer.release_count);
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
    try std.testing.expectEqual(types.kResultFalse, openDataExchangeQueue(128, 2, 8, 9, &queue_id));
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
    try std.testing.expectEqual(types.kResultOk, openDataExchangeQueue(128, 2, 8, 77, &queue_id));
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeQueueID, 44), queue_id);
    try std.testing.expectEqual(@as(ivstdataexchange.DataExchangeUserContextID, 77), host.last_user_context_id);
    try std.testing.expectEqual(types.kResultOk, closeDataExchangeQueue(queue_id));
    try std.testing.expectEqual(@as(types.uint32, 1), host.open_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.close_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.initialize(component_iface, host.asHostApplication()));
    try std.testing.expectEqual(@as(types.uint32, 2), host.add_ref_count);
    try std.testing.expectEqual(@as(types.uint32, 1), host.release_count);

    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.terminate(component_iface));
    try std.testing.expectEqual(@as(types.uint32, 2), host.release_count);
}

test "gain component round-trips gain state through host callbacks" {
    const std = @import("std");
    const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");

    gain_controller.setGain(0.5);
    defer gain_controller.setGain(1.0);

    var out: ?*anyopaque = null;
    try std.testing.expectEqual(types.kResultOk, create(@ptrCast(&ivstcomponent.icomponent_iid), &out));
    try std.testing.expect(out != null);
    const component_iface: *ivstcomponent.IComponent = @ptrCast(@alignCast(out.?));
    defer _ = component_iface.vtable.release(component_iface);

    const Stream = vst_stream.FixedBufferStream(plug_state.encodedSize(gain_spec.Spec.Params));
    var stream = Stream{};
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.getState(component_iface, stream.asStream()));
    try std.testing.expectEqual(@as(usize, plug_state.encodedSize(gain_spec.Spec.Params)), stream.data().len);

    gain_controller.setGain(1.0);
    try std.testing.expectEqual(@as(f64, 1.0), gain_controller.gain());
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, component_iface.vtable.setState(component_iface, stream.asStream()));
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), gain_controller.gain(), 0.000001);
}
