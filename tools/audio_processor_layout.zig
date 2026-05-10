const std = @import("std");
const base = @import("zig-vst3").pluginterfaces.base.types;
const audio_processor = @import("zig-vst3").pluginterfaces.vst.ivstaudioprocessor;
const audio_processor_algo = @import("zig-vst3").pluginterfaces.vst.vstaudioprocessoralgo;
const events = @import("zig-vst3").pluginterfaces.vst.ivstevents;
const parameter_changes = @import("zig-vst3").pluginterfaces.vst.ivstparameterchanges;
const vsttypes = @import("zig-vst3").pluginterfaces.vst.vsttypes;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("kVstAudioEffectClass {s}\n", .{audio_processor.kVstAudioEffectClass});
    try stdout.print("ComponentFlags.kDistributable {}\n", .{audio_processor.ComponentFlags.kDistributable});
    try stdout.print("ComponentFlags.kSimpleModeSupported {}\n", .{audio_processor.ComponentFlags.kSimpleModeSupported});
    try stdout.print("SymbolicSampleSizes.kSample32 {}\n", .{@intFromEnum(audio_processor.SymbolicSampleSizes.kSample32)});
    try stdout.print("SymbolicSampleSizes.kSample64 {}\n", .{@intFromEnum(audio_processor.SymbolicSampleSizes.kSample64)});
    try stdout.print("ProcessModes.kRealtime {}\n", .{@intFromEnum(audio_processor.ProcessModes.kRealtime)});
    try stdout.print("ProcessModes.kPrefetch {}\n", .{@intFromEnum(audio_processor.ProcessModes.kPrefetch)});
    try stdout.print("ProcessModes.kOffline {}\n", .{@intFromEnum(audio_processor.ProcessModes.kOffline)});
    try stdout.print("kNoTail {}\n", .{audio_processor.kNoTail});
    try stdout.print("kInfiniteTail {}\n", .{audio_processor.kInfiniteTail});
    try stdout.print("IProcessContextRequirements.kNeedSystemTime {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedSystemTime});
    try stdout.print("IProcessContextRequirements.kNeedContinousTimeSamples {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedContinousTimeSamples});
    try stdout.print("IProcessContextRequirements.kNeedProjectTimeMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedProjectTimeMusic});
    try stdout.print("IProcessContextRequirements.kNeedBarPositionMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedBarPositionMusic});
    try stdout.print("IProcessContextRequirements.kNeedCycleMusic {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedCycleMusic});
    try stdout.print("IProcessContextRequirements.kNeedSamplesToNextClock {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedSamplesToNextClock});
    try stdout.print("IProcessContextRequirements.kNeedTempo {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTempo});
    try stdout.print("IProcessContextRequirements.kNeedTimeSignature {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTimeSignature});
    try stdout.print("IProcessContextRequirements.kNeedChord {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedChord});
    try stdout.print("IProcessContextRequirements.kNeedFrameRate {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedFrameRate});
    try stdout.print("IProcessContextRequirements.kNeedTransportState {}\n", .{audio_processor.ProcessContextRequirementFlags.kNeedTransportState});

    try printType(stdout, "ProcessSetup", audio_processor.ProcessSetup);
    try printOffset(stdout, "ProcessSetup", "processMode", audio_processor.ProcessSetup, "processMode");
    try printOffset(stdout, "ProcessSetup", "symbolicSampleSize", audio_processor.ProcessSetup, "symbolicSampleSize");
    try printOffset(stdout, "ProcessSetup", "maxSamplesPerBlock", audio_processor.ProcessSetup, "maxSamplesPerBlock");
    try printOffset(stdout, "ProcessSetup", "sampleRate", audio_processor.ProcessSetup, "sampleRate");

    try printType(stdout, "AudioBusBuffers", audio_processor.AudioBusBuffers);
    try printOffset(stdout, "AudioBusBuffers", "numChannels", audio_processor.AudioBusBuffers, "numChannels");
    try printOffset(stdout, "AudioBusBuffers", "silenceFlags", audio_processor.AudioBusBuffers, "silenceFlags");
    try printOffset(stdout, "AudioBusBuffers", "channelBuffers32", audio_processor.AudioBusBuffers, "channelBuffers");
    try printOffset(stdout, "AudioBusBuffers", "channelBuffers64", audio_processor.AudioBusBuffers, "channelBuffers");

    try printType(stdout, "ProcessData", audio_processor.ProcessData);
    try printOffset(stdout, "ProcessData", "processMode", audio_processor.ProcessData, "processMode");
    try printOffset(stdout, "ProcessData", "symbolicSampleSize", audio_processor.ProcessData, "symbolicSampleSize");
    try printOffset(stdout, "ProcessData", "numSamples", audio_processor.ProcessData, "numSamples");
    try printOffset(stdout, "ProcessData", "numInputs", audio_processor.ProcessData, "numInputs");
    try printOffset(stdout, "ProcessData", "numOutputs", audio_processor.ProcessData, "numOutputs");
    try printOffset(stdout, "ProcessData", "inputs", audio_processor.ProcessData, "inputs");
    try printOffset(stdout, "ProcessData", "outputs", audio_processor.ProcessData, "outputs");
    try printOffset(stdout, "ProcessData", "inputParameterChanges", audio_processor.ProcessData, "inputParameterChanges");
    try printOffset(stdout, "ProcessData", "outputParameterChanges", audio_processor.ProcessData, "outputParameterChanges");
    try printOffset(stdout, "ProcessData", "inputEvents", audio_processor.ProcessData, "inputEvents");
    try printOffset(stdout, "ProcessData", "outputEvents", audio_processor.ProcessData, "outputEvents");
    try printOffset(stdout, "ProcessData", "processContext", audio_processor.ProcessData, "processContext");

    try printType(stdout, "IAudioProcessor", audio_processor.IAudioProcessor);
    try printType(stdout, "IAudioPresentationLatency", audio_processor.IAudioPresentationLatency);
    try printType(stdout, "IProcessContextRequirements", audio_processor.IProcessContextRequirements);

    var setup32 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32) };
    var setup64 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample64) };
    var channel32 = [_]f32{0} ** 4;
    var channel64 = [_]f64{0} ** 4;
    var channels32 = [_][*]f32{&channel32};
    var channels64 = [_][*]f64{&channel64};
    var buffers32 = audio_processor.AudioBusBuffers{ .channelBuffers = .{ .channelBuffers32 = &channels32 } };
    var buffers64 = audio_processor.AudioBusBuffers{ .channelBuffers = .{ .channelBuffers64 = &channels64 } };
    try stdout.print("AudioProcessorAlgo.getChannelBuffersPointer.32 {}\n", .{@intFromBool(audio_processor_algo.getChannelBuffersPointer(&setup32, &buffers32) == @as(?*anyopaque, @ptrCast(&channels32)))});
    try stdout.print("AudioProcessorAlgo.getChannelBuffersPointer.64 {}\n", .{@intFromBool(audio_processor_algo.getChannelBuffersPointer(&setup64, &buffers64) == @as(?*anyopaque, @ptrCast(&channels64)))});
    try stdout.print("AudioProcessorAlgo.getSampleFramesSizeInBytes.32 {}\n", .{audio_processor_algo.getSampleFramesSizeInBytes(&setup32, 8)});
    try stdout.print("AudioProcessorAlgo.getSampleFramesSizeInBytes.64 {}\n", .{audio_processor_algo.getSampleFramesSizeInBytes(&setup64, 8)});
    try stdout.print("AudioProcessorAlgo.getChannelMask.0 {}\n", .{audio_processor_algo.getChannelMask(0)});
    try stdout.print("AudioProcessorAlgo.getChannelMask.6 {}\n", .{audio_processor_algo.getChannelMask(6)});
    try stdout.print("AudioProcessorAlgo.getChannelMask.64 {}\n", .{audio_processor_algo.getChannelMask(64)});
    var src32_ch0 = [_]f32{ 1, 2, 3, 4 };
    var src32_ch1 = [_]f32{ 5, 6, 7, 8 };
    var dest32_ch0 = [_]f32{0} ** 6;
    var dest32_ch1 = [_]f32{0} ** 6;
    var src32_channels = [_][*]f32{ &src32_ch0, &src32_ch1 };
    var dest32_channels = [_][*]f32{ &dest32_ch0, &dest32_ch1 };
    var src32 = audio_processor.AudioBusBuffers{ .numChannels = 2, .channelBuffers = .{ .channelBuffers32 = &src32_channels } };
    var dest32 = audio_processor.AudioBusBuffers{ .numChannels = 2, .channelBuffers = .{ .channelBuffers32 = &dest32_channels } };
    audio_processor_algo.copy32(&src32, &dest32, 3, 2);
    try stdout.print("AudioProcessorAlgo.copy32.dest0.2 {d:.1}\n", .{dest32_ch0[2]});
    try stdout.print("AudioProcessorAlgo.copy32.dest1.4 {d:.1}\n", .{dest32_ch1[4]});
    audio_processor_algo.mix32(&src32, &dest32, 3);
    try stdout.print("AudioProcessorAlgo.mix32.dest0.0 {d:.1}\n", .{dest32_ch0[0]});
    try stdout.print("AudioProcessorAlgo.mix32.dest1.2 {d:.1}\n", .{dest32_ch1[2]});
    audio_processor_algo.multiply32(&src32, &dest32, 3, 2);
    try stdout.print("AudioProcessorAlgo.multiply32.dest0.1 {d:.1}\n", .{dest32_ch0[1]});
    try stdout.print("AudioProcessorAlgo.isSilent32.before {}\n", .{@intFromBool(audio_processor_algo.isSilent32(&dest32, 3, 0))});
    audio_processor_algo.clear32(@ptrCast(&dest32), 3, 1);
    try stdout.print("AudioProcessorAlgo.clear32.dest0.1 {d:.1}\n", .{dest32_ch0[1]});
    try stdout.print("AudioProcessorAlgo.isSilent32.after {}\n", .{@intFromBool(audio_processor_algo.isSilent32(&dest32, 3, 0))});
    var src64_ch0 = [_]f64{ 1.5, 2.5, 3.5 };
    var dest64_ch0 = [_]f64{0} ** 5;
    var src64_channels = [_][*]f64{&src64_ch0};
    var dest64_channels = [_][*]f64{&dest64_ch0};
    var src64 = audio_processor.AudioBusBuffers{ .numChannels = 1, .channelBuffers = .{ .channelBuffers64 = &src64_channels } };
    var dest64 = audio_processor.AudioBusBuffers{ .numChannels = 1, .channelBuffers = .{ .channelBuffers64 = &dest64_channels } };
    audio_processor_algo.copy64(&src64, &dest64, 2, 1);
    try stdout.print("AudioProcessorAlgo.copy64.dest0.2 {d:.1}\n", .{dest64_ch0[2]});
    audio_processor_algo.multiply64(&src64, &dest64, 2, 3);
    try stdout.print("AudioProcessorAlgo.multiply64.dest0.1 {d:.1}\n", .{dest64_ch0[1]});
    try stdout.print("AudioProcessorAlgo.isSilent64.before {}\n", .{@intFromBool(audio_processor_algo.isSilent64(&dest64, 2, 0))});
    audio_processor_algo.clear64(@ptrCast(&dest64), 2, 1);
    try stdout.print("AudioProcessorAlgo.isSilent64.after {}\n", .{@intFromBool(audio_processor_algo.isSilent64(&dest64, 2, 0))});
    var event_list = MockEventList.init();
    var event_context = EventContext{};
    audio_processor_algo.forEachEvent(&event_list.iface, &event_context, collectEvent);
    try stdout.print("AudioProcessorAlgo.foreachEvent.offsetSum {}\n", .{event_context.offset_sum});
    var param_queue = MockParamValueQueue.init(1234);
    var param_context = ParamContext{};
    audio_processor_algo.forEachParamValueQueue(&param_queue.iface, &param_context, collectParamPoint);
    try stdout.print("AudioProcessorAlgo.foreachParam.paramId {}\n", .{param_context.param_id});
    try stdout.print("AudioProcessorAlgo.foreachParam.offsetSum {}\n", .{param_context.offset_sum});
    try stdout.print("AudioProcessorAlgo.foreachParam.valueSum {d:.2}\n", .{param_context.value_sum});
    var last_context = LastParamContext{};
    audio_processor_algo.forEachLastParamValueQueue(&param_queue.iface, &last_context, collectLastParamPoint);
    try stdout.print("AudioProcessorAlgo.foreachLast.offset {}\n", .{last_context.offset});
    try stdout.print("AudioProcessorAlgo.foreachLast.value {d:.2}\n", .{last_context.value});
    var changes = MockParameterChanges.init();
    var changes_context = ChangesContext{};
    audio_processor_algo.forEachParameterChanges(&changes.iface, &changes_context, collectParamQueue);
    try stdout.print("AudioProcessorAlgo.foreachChanges.paramIdSum {}\n", .{changes_context.param_id_sum});

    try printTuid(stdout, "IAudioProcessor", audio_processor.iaudio_processor_iid);
    try printTuid(stdout, "IAudioPresentationLatency", audio_processor.iaudio_presentation_latency_iid);
    try printTuid(stdout, "IProcessContextRequirements", audio_processor.iprocess_context_requirements_iid);
}

fn printType(writer: anytype, comptime name: []const u8, comptime Type: type) !void {
    try writer.print("{s} size {} align {}\n", .{ name, @sizeOf(Type), @alignOf(Type) });
}

fn printOffset(writer: anytype, comptime type_name: []const u8, comptime field_label: []const u8, comptime Type: type, comptime field_name: []const u8) !void {
    try writer.print("{s}.{s} offset {}\n", .{ type_name, field_label, @offsetOf(Type, field_name) });
}

fn printTuid(writer: anytype, comptime name: []const u8, bytes: [16]u8) !void {
    try writer.print("{s} iid", .{name});
    for (bytes) |byte| {
        try writer.print(" {X:0>2}", .{byte});
    }
    try writer.writeByte('\n');
}

const EventContext = struct {
    offset_sum: base.int32 = 0,
};

fn collectEvent(context: *EventContext, event: *const events.Event) void {
    context.offset_sum += event.sampleOffset;
}

const ParamContext = struct {
    param_id: vsttypes.ParamID = 0,
    offset_sum: base.int32 = 0,
    value_sum: vsttypes.ParamValue = 0,
};

fn collectParamPoint(context: *ParamContext, param_id: vsttypes.ParamID, sample_offset: base.int32, value: vsttypes.ParamValue) void {
    context.param_id = param_id;
    context.offset_sum += sample_offset;
    context.value_sum += value;
}

const LastParamContext = struct {
    offset: base.int32 = 0,
    value: vsttypes.ParamValue = 0,
};

fn collectLastParamPoint(context: *LastParamContext, _: vsttypes.ParamID, sample_offset: base.int32, value: vsttypes.ParamValue) void {
    context.offset = sample_offset;
    context.value = value;
}

const ChangesContext = struct {
    param_id_sum: vsttypes.ParamID = 0,
};

fn collectParamQueue(context: *ChangesContext, queue: *parameter_changes.IParamValueQueue) void {
    context.param_id_sum += queue.vtable.getParameterId(queue);
}

const MockEventList = struct {
    iface: events.IEventList,
    event_storage: [3]events.Event,

    fn init() MockEventList {
        return .{
            .iface = .{ .vtable = &event_list_vtable },
            .event_storage = .{
                .{ .sampleOffset = 10, .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent) },
                .{ .sampleOffset = 20, .type = @intFromEnum(events.Event.EventTypes.kNoteOffEvent) },
                .{ .sampleOffset = 30, .type = @intFromEnum(events.Event.EventTypes.kDataEvent) },
            },
        };
    }

    const event_list_vtable = events.IEventListVTable{
        .queryInterface = eventListQueryInterface,
        .addRef = eventListAddRef,
        .release = eventListRelease,
        .getEventCount = eventListGetEventCount,
        .getEvent = eventListGetEvent,
        .addEvent = eventListAddEvent,
    };
};

fn eventListSelf(self: *anyopaque) *MockEventList {
    return @ptrCast(@alignCast(self));
}

fn eventListQueryInterface(_: *anyopaque, _: *const @import("zig-vst3").tuid.TUID, obj: *?*anyopaque) callconv(.C) base.tresult {
    obj.* = null;
    return base.kNoInterface;
}

fn eventListAddRef(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn eventListRelease(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn eventListGetEventCount(_: *anyopaque) callconv(.C) base.int32 {
    return 3;
}

fn eventListGetEvent(self: *anyopaque, index: base.int32, event: *events.Event) callconv(.C) base.tresult {
    if (index == 1) return base.kResultFalse;
    event.* = eventListSelf(self).event_storage[@intCast(index)];
    return base.kResultOk;
}

fn eventListAddEvent(_: *anyopaque, _: *events.Event) callconv(.C) base.tresult {
    return base.kResultFalse;
}

const MockParamValueQueue = struct {
    iface: parameter_changes.IParamValueQueue,
    param_id: vsttypes.ParamID,
    sample_offsets: [3]base.int32 = .{ 4, 8, 12 },
    values: [3]vsttypes.ParamValue = .{ 0.25, 0.5, 0.75 },

    fn init(param_id: vsttypes.ParamID) MockParamValueQueue {
        return .{
            .iface = .{ .vtable = &param_queue_vtable },
            .param_id = param_id,
        };
    }

    const param_queue_vtable = parameter_changes.IParamValueQueueVTable{
        .queryInterface = paramQueueQueryInterface,
        .addRef = paramQueueAddRef,
        .release = paramQueueRelease,
        .getParameterId = paramQueueGetParameterId,
        .getPointCount = paramQueueGetPointCount,
        .getPoint = paramQueueGetPoint,
        .addPoint = paramQueueAddPoint,
    };
};

fn paramQueueSelf(self: *anyopaque) *MockParamValueQueue {
    return @ptrCast(@alignCast(self));
}

fn paramQueueQueryInterface(_: *anyopaque, _: *const @import("zig-vst3").tuid.TUID, obj: *?*anyopaque) callconv(.C) base.tresult {
    obj.* = null;
    return base.kNoInterface;
}

fn paramQueueAddRef(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn paramQueueRelease(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn paramQueueGetParameterId(self: *anyopaque) callconv(.C) vsttypes.ParamID {
    return paramQueueSelf(self).param_id;
}

fn paramQueueGetPointCount(_: *anyopaque) callconv(.C) base.int32 {
    return 3;
}

fn paramQueueGetPoint(self: *anyopaque, index: base.int32, sample_offset: *base.int32, value: *vsttypes.ParamValue) callconv(.C) base.tresult {
    if (index == 1) return base.kResultFalse;
    const queue = paramQueueSelf(self);
    sample_offset.* = queue.sample_offsets[@intCast(index)];
    value.* = queue.values[@intCast(index)];
    return base.kResultOk;
}

fn paramQueueAddPoint(_: *anyopaque, _: base.int32, _: vsttypes.ParamValue, _: *base.int32) callconv(.C) base.tresult {
    return base.kResultFalse;
}

const MockParameterChanges = struct {
    iface: parameter_changes.IParameterChanges,
    queues: [2]MockParamValueQueue,

    fn init() MockParameterChanges {
        return .{
            .iface = .{ .vtable = &parameter_changes_vtable },
            .queues = .{
                MockParamValueQueue.init(1234),
                MockParamValueQueue.init(5678),
            },
        };
    }

    const parameter_changes_vtable = parameter_changes.IParameterChangesVTable{
        .queryInterface = parameterChangesQueryInterface,
        .addRef = parameterChangesAddRef,
        .release = parameterChangesRelease,
        .getParameterCount = parameterChangesGetParameterCount,
        .getParameterData = parameterChangesGetParameterData,
        .addParameterData = parameterChangesAddParameterData,
    };
};

fn parameterChangesSelf(self: *anyopaque) *MockParameterChanges {
    return @ptrCast(@alignCast(self));
}

fn parameterChangesQueryInterface(_: *anyopaque, _: *const @import("zig-vst3").tuid.TUID, obj: *?*anyopaque) callconv(.C) base.tresult {
    obj.* = null;
    return base.kNoInterface;
}

fn parameterChangesAddRef(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn parameterChangesRelease(_: *anyopaque) callconv(.C) base.uint32 {
    return 1;
}

fn parameterChangesGetParameterCount(_: *anyopaque) callconv(.C) base.int32 {
    return 3;
}

fn parameterChangesGetParameterData(self: *anyopaque, index: base.int32) callconv(.C) ?*parameter_changes.IParamValueQueue {
    if (index == 1) return null;
    const changes = parameterChangesSelf(self);
    return &changes.queues[if (index == 0) 0 else 1].iface;
}

fn parameterChangesAddParameterData(_: *anyopaque, _: *const vsttypes.ParamID, _: *base.int32) callconv(.C) ?*parameter_changes.IParamValueQueue {
    return null;
}
