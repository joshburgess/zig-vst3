const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
const ivstmidicontrollers = @import("pluginterfaces/vst/ivstmidicontrollers.zig");
const ivstparameterchanges = @import("pluginterfaces/vst/ivstparameterchanges.zig");
const ivstprocesscontext = @import("pluginterfaces/vst/ivstprocesscontext.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-vst3-plugin-core");
const audio_processor_algo = @import("pluginterfaces/vst/vstaudioprocessoralgo.zig");
const events_helper = @import("pluginterfaces/vst/vsteventshelper.zig");
const fixed_string = @import("fixed_string.zig");
const vstspeaker = @import("pluginterfaces/vst/vstspeaker.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const string128 = @import("string128.zig");
const vst_event_list = @import("vst_event_list.zig");
const vst_index = @import("vst_index.zig");
const vst_parameter_changes = @import("vst_parameter_changes.zig");
const vst_stream = @import("vst_stream.zig");

const max_audio_channels = plug.process.max_audio_channels;
const max_data_event_bytes = plug.process.max_data_event_bytes;
const empty_arrangement = vstspeaker.SpeakerArr.kEmpty;
const stereo_arrangement = vstspeaker.SpeakerArr.kStereo;
const test_sample_rate: f64 = 48_000.0;
const formatted_parameter_value_bytes = 64;
const parsed_parameter_value_bytes = 128;
const ibstream_buffer_bytes = 4096;

const FixedBufferStream = struct {
    buffer: []u8,
    reader_interface: std.Io.Reader,
    writer_interface: std.Io.Writer,

    fn init(buffer: []u8) FixedBufferStream {
        return .{
            .buffer = buffer,
            .reader_interface = std.Io.Reader.fixed(buffer),
            .writer_interface = std.Io.Writer.fixed(buffer),
        };
    }

    fn reader(self: *FixedBufferStream) *std.Io.Reader {
        self.reader_interface = std.Io.Reader.fixed(self.buffer);
        return &self.reader_interface;
    }

    fn writer(self: *FixedBufferStream) *std.Io.Writer {
        self.writer_interface = std.Io.Writer.fixed(self.buffer);
        return &self.writer_interface;
    }

    fn getWritten(self: *const FixedBufferStream) []const u8 {
        return self.writer_interface.buffered();
    }
};

pub const StereoAudioBuses = struct {
    pub const Config = struct {
        audio_input: bool = true,
        audio_output: bool = true,
        event_input: bool = true,
        event_output: bool = false,
    };

    pub fn busCount(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) types.int32 {
        return busCountWithEventOutput(media_type, direction, false);
    }

    pub fn busCountWithEventOutput(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, event_output: bool) types.int32 {
        return busCountConfigured(media_type, direction, .{ .event_output = event_output });
    }

    pub fn busCountConfigured(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, config: Config) types.int32 {
        if (config.audio_input and media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) {
            return 1;
        }
        if (config.audio_output and media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput)) {
            return 1;
        }
        if (config.event_input and media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) {
            return 1;
        }
        if (config.event_output and media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput)) {
            return 1;
        }
        return 0;
    }

    pub fn busInfo(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) types.tresult {
        return busInfoWithEventOutput(media_type, direction, index, out, false);
    }

    pub fn busInfoWithEventOutput(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo, event_output: bool) types.tresult {
        return busInfoConfigured(media_type, direction, index, out, .{ .event_output = event_output });
    }

    pub fn busInfoConfigured(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo, config: Config) types.tresult {
        if (index != 0) {
            out.* = .{};
            return types.kInvalidArgument;
        }

        const has_audio_bus =
            (config.audio_input and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) or
            (config.audio_output and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput));
        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and has_audio_bus) {
            out.* = .{
                .mediaType = media_type,
                .direction = direction,
                .channelCount = 2,
                .busType = @intFromEnum(ivstcomponent.BusTypes.kMain),
                .flags = ivstcomponent.BusFlags.kDefaultActive,
            };
            string128.copy(&out.name, if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) "Stereo In" else "Stereo Out");
            return types.kResultOk;
        }

        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and
            ((config.event_input and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) or
                (config.event_output and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput))))
        {
            out.* = .{
                .mediaType = media_type,
                .direction = direction,
                .channelCount = 1,
                .busType = @intFromEnum(ivstcomponent.BusTypes.kMain),
                .flags = ivstcomponent.BusFlags.kDefaultActive,
            };
            string128.copy(&out.name, if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) "Event In" else "Event Out");
            return types.kResultOk;
        }

        out.* = .{};
        return types.kInvalidArgument;
    }

    pub fn setArrangements(inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) types.tresult {
        return setArrangementsConfigured(inputs, num_inputs, outputs, num_outputs, .{});
    }

    pub fn setArrangementsConfigured(inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32, config: Config) types.tresult {
        const expected_inputs: types.int32 = if (config.audio_input) 1 else 0;
        const expected_outputs: types.int32 = if (config.audio_output) 1 else 0;
        if (num_inputs != expected_inputs or num_outputs != expected_outputs) {
            return types.kResultFalse;
        }
        if (config.audio_input) {
            const input_arrangements = inputs orelse return types.kResultFalse;
            if (input_arrangements[0] != stereo_arrangement) return types.kResultFalse;
        }
        if (config.audio_output) {
            const output_arrangements = outputs orelse return types.kResultFalse;
            if (output_arrangements[0] != stereo_arrangement) return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn arrangement(direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) types.tresult {
        return arrangementConfigured(direction, index, out, .{});
    }

    pub fn arrangementConfigured(direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement, config: Config) types.tresult {
        const has_audio_bus =
            (config.audio_input and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) or
            (config.audio_output and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput));
        if (index != 0 or !has_audio_bus) {
            out.* = empty_arrangement;
            return types.kInvalidArgument;
        }
        out.* = stereo_arrangement;
        return types.kResultOk;
    }
};

pub const RealtimeProcessorDefaults = struct {
    pub fn canProcessSampleSize(symbolic_sample_size: types.int32) types.tresult {
        if (symbolic_sample_size == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32) or
            symbolic_sample_size == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64))
        {
            return types.kResultOk;
        }
        return types.kResultFalse;
    }

    pub fn validateProcessSetup(setup: *const ivstaudioprocessor.ProcessSetup) types.tresult {
        const sample_size_result = canProcessSampleSize(setup.symbolicSampleSize);
        if (sample_size_result != types.kResultOk) return sample_size_result;

        if (setup.maxSamplesPerBlock <= 0) return types.kInvalidArgument;
        const prepare_config = plug.plugin.PrepareConfig{
            .sample_rate = setup.sampleRate,
            .max_block_size = @intCast(setup.maxSamplesPerBlock),
        };
        prepare_config.validate() catch return types.kInvalidArgument;
        return types.kResultOk;
    }

    pub fn latencySamples() types.uint32 {
        return 0;
    }

    pub fn tailSamples() types.uint32 {
        return ivstaudioprocessor.kNoTail;
    }
};

pub fn ParameterState(comptime Params: type) type {
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);

    return struct {
        const Self = @This();

        set: *const Set,
        values: Values,

        pub fn init(set: *const Set) Self {
            return .{
                .set = set,
                .values = Values.init(set),
            };
        }

        pub fn getNormalizedById(self: *const Self, id: vsttypes.ParamID) vsttypes.ParamValue {
            return self.values.loadById(self.set, id) orelse 0;
        }

        pub fn setNormalizedById(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            if (self.set.isReadOnlyById(id) orelse return types.kInvalidArgument) return types.kResultFalse;
            if (!self.values.storeById(self.set, id, value)) return types.kInvalidArgument;
            return types.kResultOk;
        }

        pub fn applyChanges(self: *Self, changes: plug.process.ParameterChanges) void {
            self.values.applyChanges(self.set, changes);
        }

        pub fn encodedSize(_: *const Self) usize {
            return plug.state.encodedSize(Params);
        }

        pub fn readFromStream(self: *Self, stream: ?*ibstream.IBStream) types.tresult {
            var restored = Values.init(self.set);
            const result = readParameterState(Params, stream, self.set, &restored);
            if (result != types.kResultOk) return result;
            self.values.copyFrom(&restored);
            return types.kResultOk;
        }

        pub fn writeToStream(self: *const Self, stream: ?*ibstream.IBStream) types.tresult {
            return writeParameterState(Params, stream, self.set, &self.values);
        }
    };
}

pub fn ParameterController(comptime Params: type) type {
    const Set = plug.parameters.ParameterSet(Params);
    const State = ParameterState(Params);

    return struct {
        const Self = @This();

        set: *const Set,
        state: *State,

        pub fn parameterCount(_: *const Self) types.int32 {
            return @intCast(Set.count);
        }

        pub fn parameterInfo(self: *const Self, index: types.int32, out: *ivsteditcontroller.ParameterInfo) types.tresult {
            return fillParameterInfo(Params, self.set, index, out);
        }

        pub fn stringByValue(self: *const Self, id: vsttypes.ParamID, value: vsttypes.ParamValue, out: [*]vsttypes.TChar) types.tresult {
            return getParamStringByValue(Params, self.set, id, value, out);
        }

        pub fn valueByString(self: *const Self, id: vsttypes.ParamID, text: [*]vsttypes.TChar, out: *vsttypes.ParamValue) types.tresult {
            return getParamValueByString(Params, self.set, id, text, out);
        }

        pub fn plainFromNormalized(self: *const Self, id: vsttypes.ParamID, normalized: vsttypes.ParamValue) vsttypes.ParamValue {
            return normalizedParamToPlain(Params, self.set, id, normalized);
        }

        pub fn normalizedFromPlain(self: *const Self, id: vsttypes.ParamID, plain: vsttypes.ParamValue) vsttypes.ParamValue {
            return plainParamToNormalized(Params, self.set, id, plain);
        }

        pub fn getNormalized(self: *const Self, id: vsttypes.ParamID) vsttypes.ParamValue {
            return self.state.getNormalizedById(id);
        }

        pub fn setNormalized(self: *Self, id: vsttypes.ParamID, value: vsttypes.ParamValue) types.tresult {
            return self.state.setNormalizedById(id, value);
        }

        pub fn applyChanges(self: *Self, changes: plug.process.ParameterChanges) void {
            self.state.applyChanges(changes);
        }

        pub fn readState(self: *Self, stream: ?*ibstream.IBStream) types.tresult {
            return self.state.readFromStream(stream);
        }

        pub fn writeState(self: *const Self, stream: ?*ibstream.IBStream) types.tresult {
            return self.state.writeToStream(stream);
        }
    };
}

pub fn fillParameterInfo(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    index: types.int32,
    out: *ivsteditcontroller.ParameterInfo,
) types.tresult {
    const parameter_index = parameterIndex(Params, index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const id = set.id(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const step_count = set.stepCount(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const default_normalized = set.defaultNormalized(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const unit_id = set.unitId(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const name = set.name(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const short_name = set.shortName(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    const units = set.units(parameter_index) orelse {
        out.* = .{};
        return types.kInvalidArgument;
    };
    out.* = .{
        .id = id,
        .stepCount = step_count,
        .defaultNormalizedValue = default_normalized,
        .unitId = unit_id,
        .flags = parameterInfoFlags(Params, set, parameter_index),
    };
    string128.copy(&out.title, name);
    string128.copy(&out.shortTitle, short_name);
    string128.copy(&out.units, units);
    return types.kResultOk;
}

fn parameterIndex(comptime Params: type, index: types.int32) ?usize {
    return vst_index.bounded(index, plug.parameters.ParameterSet(Params).count);
}

fn parameterInfoFlags(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    index: usize,
) types.int32 {
    var flags: types.int32 = 0;
    if (set.canAutomate(index) orelse false) {
        flags |= ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate;
    }
    if (set.isReadOnly(index) orelse false) {
        flags |= ivsteditcontroller.ParameterInfo.ParameterFlags.kIsReadOnly;
    }
    if (set.isList(index) orelse false) {
        flags |= ivsteditcontroller.ParameterInfo.ParameterFlags.kIsList;
    }
    if (set.isBypass(index) orelse false) {
        flags |= ivsteditcontroller.ParameterInfo.ParameterFlags.kIsBypass;
    }
    return flags;
}

pub fn getParamStringByValue(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    value: vsttypes.ParamValue,
    out: [*]vsttypes.TChar,
) types.tresult {
    string128.copyPtr(out, "");
    const index = set.indexOfId(id) orelse return types.kInvalidArgument;
    var buffer: [formatted_parameter_value_bytes]u8 = undefined;
    const text = set.formatPlain(index, value, &buffer) catch return types.kResultFalse;
    string128.copyPtr(out, text);
    return types.kResultOk;
}

pub fn getParamValueByString(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    text: [*]vsttypes.TChar,
    out: *vsttypes.ParamValue,
) types.tresult {
    out.* = 0;
    const index = set.indexOfId(id) orelse return types.kInvalidArgument;
    var buffer: [parsed_parameter_value_bytes]u8 = undefined;
    const parsed_text = fixed_string.readUtf16ZAsAscii(text, &buffer);
    out.* = set.parsePlain(index, parsed_text) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn normalizedParamToPlain(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    normalized: vsttypes.ParamValue,
) vsttypes.ParamValue {
    const index = set.indexOfId(id) orelse return 0;
    return set.plainFromNormalized(index, normalized) orelse 0;
}

pub fn plainParamToNormalized(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    id: vsttypes.ParamID,
    plain: vsttypes.ParamValue,
) vsttypes.ParamValue {
    const index = set.indexOfId(id) orelse return 0;
    return set.normalizedFromPlain(index, plain) orelse 0;
}

pub fn frameCountOrZero(data: *const ivstaudioprocessor.ProcessData) usize {
    return if (data.numSamples <= 0) 0 else @intCast(data.numSamples);
}

fn validFrameCount(data: *const ivstaudioprocessor.ProcessData) !usize {
    if (data.numSamples < 0) return error.InvalidFrameCount;
    return @intCast(data.numSamples);
}

pub fn collectInputParameterChanges(data: *ivstaudioprocessor.ProcessData, storage: []plug.process.ParameterChange) plug.process.ParameterChanges {
    var collector = ParameterChangeCollector{
        .storage = storage,
        .frame_count = frameCountOrZero(data),
    };
    audio_processor_algo.forEachParameterChanges(data.inputParameterChanges, &collector, collectParameterQueue);
    return plug.process.ParameterChanges.init(storage[0..collector.count], collector.frame_count) catch .{};
}

pub fn collectInputEvents(data: *ivstaudioprocessor.ProcessData, storage: []plug.process.Event) plug.process.Events {
    var collector = EventCollector{
        .storage = storage,
        .frame_count = frameCountOrZero(data),
    };
    audio_processor_algo.forEachEvent(data.inputEvents, &collector, collectEvent);
    return plug.process.Events.init(storage[0..collector.count], collector.frame_count) catch .{};
}

pub fn writeOutputEvents(data: *ivstaudioprocessor.ProcessData, events: plug.process.Events) types.tresult {
    const output_events = data.outputEvents orelse return types.kResultOk;
    const frame_count = validFrameCount(data) catch return types.kInvalidArgument;
    for (events.items) |event| {
        if (event.sample_offset >= frame_count) return types.kInvalidArgument;
        event.validate(frame_count) catch continue;
        var vst_event = toVstEvent(event) orelse continue;
        if (output_events.vtable.addEvent(output_events, &vst_event) != types.kResultOk) return types.kResultFalse;
    }
    return types.kResultOk;
}

pub fn makeProcessContext(
    comptime Sample: type,
    input: ivstaudioprocessor.AudioBusBuffers,
    output: ivstaudioprocessor.AudioBusBuffers,
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
) !plug.process.ProcessContext(Sample) {
    const frame_count = try validFrameCount(data);
    const channel_count = try boundedPairedAudioChannelCount(input, output);
    var input_channels: [max_audio_channels][]const Sample = undefined;
    var output_channels: [max_audio_channels][]Sample = undefined;
    const input_buffers = vstAudioBuffers(Sample, input) orelse return error.MissingInputBuffers;
    const output_buffers = vstAudioBuffers(Sample, output) orelse return error.MissingOutputBuffers;

    for (0..channel_count) |channel| {
        input_channels[channel] = input_buffers[channel][0..frame_count];
        output_channels[channel] = output_buffers[channel][0..frame_count];
    }

    return try plug.process.ProcessContext(Sample).initWith(
        if (data.processContext) |process_context| process_context.sampleRate else 0,
        input_channels[0..channel_count],
        output_channels[0..channel_count],
        .{
            .parameter_changes = parameter_changes.items,
            .events = events.items,
            .output_events = output_events,
        },
    );
}

fn fillInputChannels(comptime Sample: type, bus: ivstaudioprocessor.AudioBusBuffers, frame_count: usize, out: *[max_audio_channels][]const Sample) !usize {
    const channel_count = try boundedAudioChannelCount(bus);
    if (channel_count == 0) return 0;
    const buffers = vstAudioBuffers(Sample, bus) orelse return error.MissingInputBuffers;
    for (0..channel_count) |channel| {
        out[channel] = buffers[channel][0..frame_count];
    }
    return channel_count;
}

fn fillOutputChannels(comptime Sample: type, bus: ivstaudioprocessor.AudioBusBuffers, frame_count: usize, out: *[max_audio_channels][]Sample) !usize {
    const channel_count = try boundedAudioChannelCount(bus);
    if (channel_count == 0) return 0;
    const buffers = vstAudioBuffers(Sample, bus) orelse return error.MissingOutputBuffers;
    for (0..channel_count) |channel| {
        out[channel] = buffers[channel][0..frame_count];
    }
    return channel_count;
}

pub fn makeMainAudioProcessContext(
    comptime Sample: type,
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
) !plug.process.ProcessContext(Sample) {
    return makeMainAudioProcessContextConfigured(Sample, data, parameter_changes, events, output_events, .{});
}

pub fn makeMainAudioProcessContextConfigured(
    comptime Sample: type,
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
    bus_config: StereoAudioBuses.Config,
) !plug.process.ProcessContext(Sample) {
    const frame_count = try validFrameCount(data);
    var input_channels: [max_audio_channels][]const Sample = undefined;
    var output_channels: [max_audio_channels][]Sample = undefined;
    const input_count = if (bus_config.audio_input) input: {
        if (data.numInputs <= 0) return error.MissingMainAudioBus;
        const inputs = data.inputs orelse return error.MissingMainAudioBus;
        break :input try fillInputChannels(Sample, inputs[0], frame_count, &input_channels);
    } else 0;
    const output_count = if (bus_config.audio_output) output: {
        if (data.numOutputs <= 0) return error.MissingMainAudioBus;
        const outputs = data.outputs orelse return error.MissingMainAudioBus;
        break :output try fillOutputChannels(Sample, outputs[0], frame_count, &output_channels);
    } else 0;
    if ((bus_config.audio_input and input_count == 0) or (bus_config.audio_output and output_count == 0)) {
        return error.MissingMainAudioChannels;
    }
    return try plug.process.ProcessContext(Sample).initWith(
        if (data.processContext) |process_context| process_context.sampleRate else 0,
        input_channels[0..input_count],
        output_channels[0..output_count],
        .{
            .parameter_changes = parameter_changes.items,
            .events = events.items,
            .output_events = output_events,
        },
    );
}

pub fn processMainAudio(
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
    processor: anytype,
) types.tresult {
    return processMainAudioConfigured(data, parameter_changes, events, output_events, processor, .{});
}

pub fn processMainAudioConfigured(
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
    processor: anytype,
    bus_config: StereoAudioBuses.Config,
) types.tresult {
    const sample_size_result = RealtimeProcessorDefaults.canProcessSampleSize(data.symbolicSampleSize);
    if (sample_size_result != types.kResultOk) return sample_size_result;

    if (data.symbolicSampleSize == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32)) {
        var context = makeMainAudioProcessContextConfigured(f32, data, parameter_changes, events, output_events, bus_config) catch |err| return processContextErrorResult(err);
        processor.process(f32, &context);
    } else {
        var context = makeMainAudioProcessContextConfigured(f64, data, parameter_changes, events, output_events, bus_config) catch |err| return processContextErrorResult(err);
        processor.process(f64, &context);
    }
    return types.kResultOk;
}

fn processContextErrorResult(err: anyerror) types.tresult {
    return switch (err) {
        error.MissingMainAudioBus,
        error.MissingMainAudioChannels,
        error.MissingInputBuffers,
        error.MissingOutputBuffers,
        error.InvalidSampleRate,
        => types.kResultOk,
        error.InvalidFrameCount,
        error.InvalidChannelCount,
        error.MismatchedFrameCount,
        error.ParameterChangeOutsideBlock,
        error.ParameterChangeOutsideNormalizedRange,
        error.EventOutsideBlock,
        error.InvalidEventBusIndex,
        error.InvalidEventChannel,
        error.InvalidEventPitch,
        error.InvalidEventControlNumber,
        error.EventValueOutsideNormalizedRange,
        error.EventStorageFull,
        => types.kInvalidArgument,
        else => types.kResultFalse,
    };
}

pub fn readParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *plug.parameters.ParameterValues(Params),
) types.tresult {
    const input = stream orelse return types.kInvalidArgument;
    var input_reader: IBStreamReader = undefined;
    input_reader.init(input);
    plug.state.readParameterState(Params, set, values, input_reader.reader()) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn writeParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *const plug.parameters.ParameterValues(Params),
) types.tresult {
    const output = stream orelse return types.kInvalidArgument;
    var output_writer: IBStreamWriter = undefined;
    output_writer.init(output);
    plug.state.writeParameterState(Params, set, values, output_writer.writer()) catch return types.kResultFalse;
    return types.kResultOk;
}

const IBStreamReader = struct {
    stream: *ibstream.IBStream,
    buffer: [ibstream_buffer_bytes]u8,
    interface: std.Io.Reader,

    fn init(self: *IBStreamReader, stream: *ibstream.IBStream) void {
        self.stream = stream;
        self.buffer = undefined;
        self.interface = .{
            .vtable = &.{
                .stream = streamImpl,
                .readVec = readVec,
            },
            .buffer = &self.buffer,
            .seek = 0,
            .end = 0,
        };
    }

    fn reader(self: *IBStreamReader) *std.Io.Reader {
        return &self.interface;
    }

    fn read(self: *IBStreamReader, buffer: []u8) std.Io.Reader.Error!usize {
        if (buffer.len == 0) return 0;
        const byte_count = vst_stream.byteCount(buffer.len) orelse return error.ReadFailed;
        var bytes_read: types.int32 = 0;
        const result = self.stream.vtable.read(self.stream, buffer.ptr, byte_count, &bytes_read);
        if (bytes_read < 0) return error.ReadFailed;
        if (bytes_read == 0) return error.EndOfStream;
        if (result != types.kResultOk) return error.ReadFailed;
        return @intCast(bytes_read);
    }

    fn streamImpl(reader_interface: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *IBStreamReader = @alignCast(@fieldParentPtr("interface", reader_interface));
        var buffer: [ibstream_buffer_bytes]u8 = undefined;
        const limit_count: usize = @intCast(@min(@intFromEnum(limit), buffer.len));
        const read_count = try self.read(buffer[0..limit_count]);
        try writer.writeAll(buffer[0..read_count]);
        return read_count;
    }

    fn readVec(reader_interface: *std.Io.Reader, data: [][]u8) std.Io.Reader.Error!usize {
        const self: *IBStreamReader = @alignCast(@fieldParentPtr("interface", reader_interface));
        if (data.len > 0 and data[0].len == 0) {
            const writable = reader_interface.buffer[reader_interface.end..];
            if (writable.len == 0) return error.ReadFailed;
            const read_count = try self.read(writable[0..1]);
            reader_interface.end += read_count;
            return 0;
        }
        var total: usize = 0;
        for (data) |buffer| {
            const read_count = try self.read(buffer);
            total += read_count;
            if (read_count < buffer.len) break;
        }
        return total;
    }
};

const IBStreamWriter = struct {
    stream: *ibstream.IBStream,
    interface: std.Io.Writer,

    fn init(self: *IBStreamWriter, stream: *ibstream.IBStream) void {
        self.stream = stream;
        self.interface = .{
            .vtable = &.{
                .drain = drain,
            },
            .buffer = &.{},
        };
    }

    fn writer(self: *IBStreamWriter) *std.Io.Writer {
        return &self.interface;
    }

    fn write(self: *IBStreamWriter, bytes: []const u8) std.Io.Writer.Error!usize {
        if (bytes.len == 0) return 0;
        const byte_count = vst_stream.byteCount(bytes.len) orelse return error.WriteFailed;
        var bytes_written: types.int32 = 0;
        const result = self.stream.vtable.write(self.stream, @constCast(bytes.ptr), byte_count, &bytes_written);
        if (result != types.kResultOk or bytes_written < 0) return error.WriteFailed;
        return @intCast(bytes_written);
    }

    fn drain(writer_interface: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *IBStreamWriter = @alignCast(@fieldParentPtr("interface", writer_interface));
        var total: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            total += try self.write(bytes);
        }
        const repeated = data[data.len - 1];
        for (0..splat) |_| {
            total += try self.write(repeated);
        }
        return total;
    }
};

fn vstAudioBuffers(comptime Sample: type, buffer: ivstaudioprocessor.AudioBusBuffers) ?[*][*]Sample {
    return switch (Sample) {
        f32 => buffer.channelBuffers.channelBuffers32,
        f64 => buffer.channelBuffers.channelBuffers64,
        else => @compileError("unsupported VST3 sample type"),
    };
}

fn boundedAudioChannelCount(bus: ivstaudioprocessor.AudioBusBuffers) !usize {
    if (bus.numChannels < 0) return error.InvalidChannelCount;
    return @intCast(@min(bus.numChannels, max_audio_channels));
}

fn boundedPairedAudioChannelCount(input: ivstaudioprocessor.AudioBusBuffers, output: ivstaudioprocessor.AudioBusBuffers) !usize {
    const input_count = try boundedAudioChannelCount(input);
    const output_count = try boundedAudioChannelCount(output);
    return @min(input_count, output_count);
}

const ParameterChangeCollector = struct {
    storage: []plug.process.ParameterChange,
    count: usize = 0,
    frame_count: usize,

    fn append(self: *ParameterChangeCollector, change: plug.process.ParameterChange) bool {
        if (self.count >= self.storage.len) return false;
        self.storage[self.count] = change;
        self.count +|= 1;
        return true;
    }
};

const EventCollector = struct {
    storage: []plug.process.Event,
    count: usize = 0,
    frame_count: usize,

    fn append(self: *EventCollector, event: plug.process.Event) bool {
        if (self.count >= self.storage.len) return false;
        self.storage[self.count] = event;
        self.count +|= 1;
        return true;
    }
};

fn collectParameterQueue(collector: *ParameterChangeCollector, queue: *ivstparameterchanges.IParamValueQueue) void {
    audio_processor_algo.forEachParamValueQueue(queue, collector, collectParameterPoint);
}

fn collectParameterPoint(collector: *ParameterChangeCollector, id: vsttypes.ParamID, sample_offset: types.int32, value: vsttypes.ParamValue) void {
    const offset = sampleOffsetInBlock(sample_offset, collector.frame_count) orelse return;
    if (!isNormalizedValue(value)) return;
    _ = collector.append(.{
        .id = id,
        .sample_offset = offset,
        .normalized = value,
    });
}

fn collectEvent(collector: *EventCollector, event: *const ivstevents.Event) void {
    const offset = sampleOffsetInBlock(event.sampleOffset, collector.frame_count) orelse return;
    const converted: ?plug.process.Event = switch (event.type) {
        @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent) => if (isNormalizedValue(event.data.noteOn.velocity))
            plug.process.Event.noteOn(offset, event.data.noteOn.channel, event.data.noteOn.pitch, event.data.noteOn.velocity).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent) => if (isNormalizedValue(event.data.noteOff.velocity))
            plug.process.Event.noteOff(offset, event.data.noteOff.channel, event.data.noteOff.pitch, event.data.noteOff.velocity).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kDataEvent) => if (dataEventBytes(event.data.data)) |bytes|
            plug.process.Event.dataEvent(offset, event.data.data.type, bytes).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent) => collectLegacyMidiCcEvent(event, offset),
        @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent) => if (isNormalizedValue(event.data.polyPressure.pressure))
            plug.process.Event.aftertouch(offset, event.data.polyPressure.channel, event.data.polyPressure.pitch, event.data.polyPressure.pressure).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent) => if (isFiniteValue(event.data.noteExpressionValue.value))
            plug.process.Event.noteExpressionValue(offset, event.data.noteExpressionValue.noteId, event.data.noteExpressionValue.typeId, @floatCast(event.data.noteExpressionValue.value)).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionIntValueEvent) => plug.process.Event.noteExpressionInt(offset, event.data.noteExpressionIntValue.noteId, event.data.noteExpressionIntValue.typeId, event.data.noteExpressionIntValue.value).withBusIndex(event.busIndex),
        @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionTextEvent) => plug.process.Event.noteExpressionText(offset, event.data.noteExpressionText.noteId, event.data.noteExpressionText.typeId).withBusIndex(event.busIndex),
        else => plug.process.Event.other(offset).withBusIndex(event.busIndex),
    };
    const output = converted orelse return;
    output.validate(collector.frame_count) catch return;
    _ = collector.append(output);
}

fn collectLegacyMidiCcEvent(event: *const ivstevents.Event, offset: usize) plug.process.Event {
    const midi = &event.data.midiCCOut;
    const control_number: i16 = @intCast(midi.controlNumber);
    const value = events_helper.getMIDINormValue(@intCast(@max(midi.value, 0)));
    return switch (midi.controlNumber) {
        ivstmidicontrollers.kPitchBend => plug.process.Event.pitchBend(offset, midi.channel, @floatCast(events_helper.getNormPitchBendValue(midi)))
            .withBusIndex(event.busIndex)
            .withControlNumber(control_number),
        ivstmidicontrollers.kAfterTouch => plug.process.Event.aftertouch(offset, midi.channel, 0, @floatCast(value))
            .withBusIndex(event.busIndex)
            .withControlNumber(control_number),
        else => plug.process.Event.midiCc(offset, midi.channel, control_number, @floatCast(value)).withBusIndex(event.busIndex),
    };
}

fn sampleOffsetInBlock(sample_offset: types.int32, frame_count: usize) ?usize {
    if (sample_offset < 0) return null;
    const offset: usize = @intCast(sample_offset);
    if (offset >= frame_count) return null;
    return offset;
}

fn vstSampleOffset(sample_offset: usize) ?types.int32 {
    return std.math.cast(types.int32, sample_offset);
}

pub fn isNormalizedValue(value: anytype) bool {
    return std.math.isFinite(value) and value >= 0.0 and value <= 1.0;
}

fn isFiniteValue(value: anytype) bool {
    return std.math.isFinite(value);
}

fn toVstEvent(event: plug.process.Event) ?ivstevents.Event {
    const offset = vstSampleOffset(event.sample_offset) orelse return null;
    var result = ivstevents.Event{
        .busIndex = event.bus_index,
        .sampleOffset = offset,
    };
    switch (event.kind) {
        .note_on => {
            if (!isNormalizedValue(event.velocity)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent);
            result.data = .{ .noteOn = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .velocity = event.velocity,
            } };
        },
        .note_off => {
            if (!isNormalizedValue(event.velocity)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent);
            result.data = .{ .noteOff = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .velocity = event.velocity,
            } };
        },
        .midi_cc => {
            const control_number = std.math.cast(types.uint8, event.control_number) orelse return null;
            const channel = std.math.cast(types.int8, event.channel) orelse return null;
            if (!isNormalizedValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent);
            result.data = .{ .midiCCOut = .{
                .controlNumber = control_number,
                .channel = channel,
                .value = events_helper.getMIDICCOutValue(event.value),
            } };
        },
        .pitch_bend => {
            const channel = std.math.cast(types.int8, event.channel) orelse return null;
            if (!isNormalizedValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent);
            result.data = .{ .midiCCOut = .{
                .controlNumber = ivstmidicontrollers.kPitchBend,
                .channel = channel,
                .value = 0,
            } };
            events_helper.setPitchBendValue(&result.data.midiCCOut, event.value);
        },
        .aftertouch => {
            if (!isNormalizedValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent);
            result.data = .{ .polyPressure = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .pressure = event.value,
                .noteId = event.note_id,
            } };
        },
        .note_expression_value => {
            if (!isFiniteValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent);
            result.data = .{ .noteExpressionValue = .{
                .typeId = event.expression_type_id,
                .noteId = event.note_id,
                .value = event.value,
            } };
        },
        .note_expression_int => {
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionIntValueEvent);
            result.data = .{ .noteExpressionIntValue = .{
                .typeId = event.expression_type_id,
                .noteId = event.note_id,
                .value = event.int_value,
            } };
        },
        .note_expression_text => {
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionTextEvent);
            result.data = .{ .noteExpressionText = .{
                .typeId = event.expression_type_id,
                .noteId = event.note_id,
                .textLen = 0,
                .text = null,
            } };
        },
        .data => {
            if (event.data.len > max_data_event_bytes) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent);
            result.data = .{ .data = .{
                .size = @intCast(@min(event.data.len, std.math.maxInt(types.uint32))),
                .type = event.data_type,
                .bytes = if (event.data.len == 0) null else event.data.ptr,
            } };
        },
        .other => return null,
    }
    return result;
}

fn dataEventBytes(data: ivstevents.DataEvent) ?[]const u8 {
    if (data.size == 0) return &.{};
    if (data.size > max_data_event_bytes) return null;
    const bytes = data.bytes orelse return null;
    return bytes[0..data.size];
}

test "zig-vst3-plugin bridge round-trips parameter state through IBStream" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var restored = Values.init(&set);
    const Stream = vst_stream.FixedBufferStream(plug.state.encodedSize(Params));
    var stream = Stream{};

    try std.testing.expect(values.storeField(&set, "gain", 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, stream.asStream(), &set, &values));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(Params, stream.asStream(), &set, &restored));
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadField(&set, "gain"));
}

test "zig-vst3-plugin bridge reads older parameter state without requiring current encoded size" {
    const OldParams = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: plug.parameters.FloatParam = plug.parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const OldSet = plug.parameters.ParameterSet(OldParams);
    const OldValues = plug.parameters.ParameterValues(OldParams);
    const NewSet = plug.parameters.ParameterSet(NewParams);
    const NewValues = plug.parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{};

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(OldParams, stream.asStream(), &old_set, &old_values));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(NewParams, stream.asStream(), &new_set, &new_values));

    try std.testing.expectEqual(@as(f64, 0.25), new_values.loadField(&new_set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.5), new_values.loadField(&new_set, "mix"));
}

test "zig-vst3-plugin bridge rejects truncated IBStream state" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: plug.parameters.FloatParam = plug.parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var source = Values.init(&set);
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{};

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));
    try std.testing.expect(source.storeField(&set, "gain", 0.25));
    try std.testing.expect(source.storeField(&set, "mix", 0.75));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, stream.asStream(), &set, &source));
    stream.len -= 1;
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, readParameterState(Params, stream.asStream(), &set, &values));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "zig-vst3-plugin bridge rejects invalid normalized IBStream state" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: plug.parameters.FloatParam = plug.parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var source = ParameterState(Params).init(&set);
    var restored = ParameterState(Params).init(&set);
    const Stream = vst_stream.FixedBufferStream(plug.state.encodedSize(Params));
    var stream = Stream{};

    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(1, 0.75));
    try std.testing.expectEqual(types.kResultOk, restored.setNormalizedById(0, 0.8));
    try std.testing.expectEqual(types.kResultOk, restored.setNormalizedById(1, 0.6));

    try std.testing.expectEqual(types.kResultOk, source.writeToStream(stream.asStream()));
    const second_value_offset = plug.state.encoded_header_size + plug.state.encoded_entry_size + @sizeOf(u32);
    var invalid_value = FixedBufferStream.init(stream.bytes[second_value_offset..][0..@sizeOf(u64)]);
    try invalid_value.writer().writeInt(u64, @bitCast(@as(f64, 1.5)), .little);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, restored.readFromStream(stream.asStream()));

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.8), restored.getNormalizedById(0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.6), restored.getNormalizedById(1));
}

test "zig-vst3-plugin bridge reports failed IBStream writes" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{ .write_limit = 4 };

    try std.testing.expectEqual(types.kResultFalse, writeParameterState(Params, stream.asStream(), &set, &values));
}

test "zig-vst3-plugin bridge parameter state stores ids and persists streams" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: plug.parameters.FloatParam = plug.parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var source = ParameterState(Params).init(&set);
    var restored = ParameterState(Params).init(&set);
    const Stream = vst_stream.FixedBufferStream(plug.state.encodedSize(Params));
    var stream = Stream{};

    try std.testing.expectEqual(@as(usize, plug.state.encodedSize(Params)), source.encodedSize());
    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(1, 0.75));
    try std.testing.expectEqual(types.kInvalidArgument, source.setNormalizedById(99, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), source.getNormalizedById(0));

    try std.testing.expectEqual(types.kResultOk, source.writeToStream(stream.asStream()));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, restored.readFromStream(stream.asStream()));

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), restored.getNormalizedById(0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), restored.getNormalizedById(1));
}

test "zig-vst3-plugin bridge collects VST3 parameter changes" {
    const Changes = vst_parameter_changes.ParameterChanges(2, 2);
    var changes = Changes{};
    const gain_queue = changes.addQueue(7).?;
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(3, 0.75));
    const mix_queue = changes.addQueue(8).?;
    try std.testing.expectEqual(types.kResultOk, mix_queue.appendPoint(2, 1.0));
    var storage: [4]plug.process.ParameterChange = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputParameterChanges = changes.asInterface(),
    };

    const collected = collectInputParameterChanges(&data, &storage);

    try std.testing.expectEqual(@as(usize, 3), collected.changeCount());
    try std.testing.expectEqual(@as(u32, 7), collected.items[0].id);
    try std.testing.expectEqual(@as(usize, 0), collected.items[0].sample_offset);
    try std.testing.expectEqual(@as(f64, 0.25), collected.items[0].normalized);
    try std.testing.expectEqual(@as(u32, 7), collected.items[1].id);
    try std.testing.expectEqual(@as(usize, 3), collected.items[1].sample_offset);
    try std.testing.expectEqual(@as(u32, 8), collected.items[2].id);
    try std.testing.expectEqual(@as(usize, 2), collected.items[2].sample_offset);
}

test "zig-vst3-plugin bridge drops invalid and overflowing VST3 parameter changes" {
    const Changes = vst_parameter_changes.ParameterChanges(2, 6);
    var changes = Changes{};
    const gain_queue = changes.addQueue(7).?;
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(-1, 0.5));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(4, 0.75));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(2, 1.5));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(2, std.math.inf(vsttypes.ParamValue)));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(3, 0.5));
    const mix_queue = changes.addQueue(8).?;
    try std.testing.expectEqual(types.kResultOk, mix_queue.appendPoint(1, 0.0));
    var storage: [2]plug.process.ParameterChange = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputParameterChanges = changes.asInterface(),
    };

    const collected = collectInputParameterChanges(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.changeCount());
    try std.testing.expectEqual(@as(usize, 0), collected.items[0].sample_offset);
    try std.testing.expectEqual(@as(usize, 3), collected.items[1].sample_offset);
}

test "zig-vst3-plugin bridge collects VST3 input events" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 2, .pitch = 60, .velocity = 0.75 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 3,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .channel = 2, .pitch = 60, .velocity = 0.25 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 4,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{} },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [4]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.note_on, collected.items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), collected.items[0].sample_offset);
    try std.testing.expectEqual(@as(i16, 2), collected.items[0].channel);
    try std.testing.expectEqual(@as(i16, 60), collected.items[0].pitch);
    try std.testing.expectEqual(@as(f32, 0.75), collected.items[0].velocity);
    try std.testing.expectEqual(plug.process.EventKind.note_off, collected.items[1].kind);
    try std.testing.expectEqual(@as(usize, 3), collected.items[1].sample_offset);
}

test "zig-vst3-plugin bridge drops invalid and overflowing VST3 input events" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = -1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 0, .pitch = 59, .velocity = 0.5 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 0, .pitch = 60, .velocity = 0.75 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 4,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .channel = 0, .pitch = 60, .velocity = 0.25 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 0, .pitch = 61, .velocity = std.math.nan(f32) } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 0, .pitch = 61, .velocity = std.math.inf(f32) } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .channel = 0, .pitch = 61, .velocity = -0.1 } },
        },
        .{
            .busIndex = 1,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent),
            .data = .{ .polyPressure = .{ .channel = 1, .pitch = 64, .pressure = 0.5 } },
        },
        .{
            .busIndex = 1,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent),
            .data = .{ .polyPressure = .{ .channel = 1, .pitch = 64, .pressure = 1.1 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent),
            .data = .{ .noteExpressionValue = .{
                .typeId = 5,
                .noteId = 42,
                .value = std.math.nan(vsttypes.ParamValue),
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent),
            .data = .{ .noteExpressionValue = .{
                .typeId = 5,
                .noteId = 42,
                .value = std.math.inf(vsttypes.ParamValue),
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 3,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{} },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [2]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.note_on, collected.items[0].kind);
    try std.testing.expectEqual(@as(usize, 0), collected.items[0].sample_offset);
    try std.testing.expectEqual(plug.process.EventKind.aftertouch, collected.items[1].kind);
    try std.testing.expectEqual(@as(i32, 1), collected.items[1].bus_index);
    try std.testing.expectEqual(@as(usize, 2), collected.items[1].sample_offset);
}

test "zig-vst3-plugin bridge keeps valid events around malformed MIDI metadata" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 0, .pitch = 60, .velocity = 0.75 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .channel = 16, .pitch = 61, .velocity = 0.75 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .channel = 0, .pitch = 128, .velocity = 0.25 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 3,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .channel = 0, .pitch = 60, .velocity = 0.25 } },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [items.len]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.note_on, collected.items[0].kind);
    try std.testing.expectEqual(@as(usize, 0), collected.items[0].sample_offset);
    try std.testing.expectEqual(plug.process.EventKind.note_off, collected.items[1].kind);
    try std.testing.expectEqual(@as(usize, 3), collected.items[1].sample_offset);
}

test "zig-vst3-plugin bridge preserves unknown VST3 input events as other" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 2,
            .sampleOffset = 1,
            .type = 9999,
            .data = .{ .noteOn = .{} },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [1]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 1), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.other, collected.items[0].kind);
    try std.testing.expectEqual(@as(i32, 2), collected.items[0].bus_index);
    try std.testing.expectEqual(@as(usize, 1), collected.items[0].sample_offset);
}

test "zig-vst3-plugin bridge maps legacy MIDI controller events" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent),
            .data = .{ .midiCCOut = .{
                .controlNumber = ivstmidicontrollers.kCtrlModWheel,
                .channel = 2,
                .value = 64,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent),
            .data = .{ .midiCCOut = .{
                .controlNumber = ivstmidicontrollers.kPitchBend,
                .channel = 2,
                .value = 127,
                .value2 = 127,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent),
            .data = .{ .midiCCOut = .{
                .controlNumber = ivstmidicontrollers.kAfterTouch,
                .channel = 2,
                .value = 32,
            } },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [3]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 3,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 3), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.midi_cc, collected.items[0].kind);
    try std.testing.expectEqual(@as(i16, ivstmidicontrollers.kCtrlModWheel), collected.items[0].control_number);
    try std.testing.expectApproxEqAbs(@as(f32, 64.0 / 127.0), collected.items[0].value, 0.0001);
    try std.testing.expectEqual(plug.process.EventKind.pitch_bend, collected.items[1].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), collected.items[1].value, 0.0001);
    try std.testing.expectEqual(plug.process.EventKind.aftertouch, collected.items[2].kind);
    try std.testing.expectApproxEqAbs(@as(f32, 32.0 / 127.0), collected.items[2].value, 0.0001);
}

test "zig-vst3-plugin bridge maps poly pressure and note expression events" {
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent),
            .data = .{ .polyPressure = .{
                .channel = 1,
                .pitch = 64,
                .pressure = 0.625,
                .noteId = 42,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 1,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent),
            .data = .{ .noteExpressionValue = .{
                .typeId = 5,
                .noteId = 42,
                .value = 0.5,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionIntValueEvent),
            .data = .{ .noteExpressionIntValue = .{
                .typeId = 8,
                .noteId = 42,
                .value = 12345,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 3,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionTextEvent),
            .data = .{ .noteExpressionText = .{
                .typeId = 6,
                .noteId = 42,
                .textLen = 0,
                .text = null,
            } },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [4]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 4), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.aftertouch, collected.items[0].kind);
    try std.testing.expectEqual(@as(i16, 64), collected.items[0].pitch);
    try std.testing.expectApproxEqAbs(@as(f32, 0.625), collected.items[0].value, 0.0001);
    try std.testing.expectEqual(plug.process.EventKind.note_expression_value, collected.items[1].kind);
    try std.testing.expectEqual(@as(i32, 42), collected.items[1].note_id);
    try std.testing.expectEqual(@as(u32, 5), collected.items[1].expression_type_id);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), collected.items[1].value, 0.0001);
    try std.testing.expectEqual(plug.process.EventKind.note_expression_int, collected.items[2].kind);
    try std.testing.expectEqual(@as(u64, 12345), collected.items[2].int_value);
    try std.testing.expectEqual(plug.process.EventKind.note_expression_text, collected.items[3].kind);
    try std.testing.expectEqual(@as(u32, 6), collected.items[3].expression_type_id);
}

test "zig-vst3-plugin bridge preserves VST3 data event payloads" {
    const payload = [_]u8{ 0xF0, 0x7D, 0x01, 0xF7 };
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{
                .size = payload.len,
                .type = @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx),
                .bytes = &payload,
            } },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [1]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 1,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 1), collected.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.data, collected.items[0].kind);
    try std.testing.expectEqual(@as(u32, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx)), collected.items[0].data_type);
    try std.testing.expectEqualSlices(u8, &payload, collected.items[0].data);
}

test "zig-vst3-plugin bridge drops malformed VST3 data event payloads" {
    const payload = [_]u8{0xF0} ** (max_data_event_bytes + 1);
    const items = [_]ivstevents.Event{
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{
                .size = 1,
                .type = @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx),
                .bytes = null,
            } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 0,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{
                .size = payload.len,
                .type = @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx),
                .bytes = &payload,
            } },
        },
    };
    const List = vst_event_list.EventList(items.len);
    var list = List{};
    for (&items) |event| try std.testing.expectEqual(types.kResultOk, list.append(event));
    var storage: [2]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 1,
        .inputEvents = list.asInterface(),
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 0), collected.eventCount());
}

test "zig-vst3-plugin bridge writes output events to VST3 event lists" {
    const payload = [_]u8{ 0xF0, 0x7D, 0x02, 0xF7 };
    const items = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 1, 60, 0.75),
        plug.process.Event.midiCc(1, 1, ivstmidicontrollers.kCtrlModWheel, 0.5),
        plug.process.Event.pitchBend(2, 1, 1.0),
        plug.process.Event.noteExpressionValue(3, 42, 5, 0.25),
        plug.process.Event.noteExpressionInt(3, 42, 5, 7),
        plug.process.Event.noteExpressionText(3, 42, 5),
        plug.process.Event.dataEvent(3, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx), &payload),
        plug.process.Event.other(3),
    };
    const List = vst_event_list.EventList(7);
    var list = List{};
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .outputEvents = list.asInterface(),
    };

    try std.testing.expectEqual(types.kResultOk, writeOutputEvents(&data, .{ .items = &items }));

    const written = list.items();
    try std.testing.expectEqual(@as(usize, 7), written.len);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent), written[0].type);
    try std.testing.expectEqual(@as(i16, 60), written[0].data.noteOn.pitch);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), written[1].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kCtrlModWheel), written[1].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), written[2].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kPitchBend), written[2].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@as(types.int16, 0x3FFF), events_helper.getPitchBendValue(&written[2].data.midiCCOut));
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent), written[3].type);
    try std.testing.expectEqual(@as(u32, 5), written[3].data.noteExpressionValue.typeId);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionIntValueEvent), written[4].type);
    try std.testing.expectEqual(@as(u64, 7), written[4].data.noteExpressionIntValue.value);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionTextEvent), written[5].type);
    try std.testing.expectEqual(@as(u32, 5), written[5].data.noteExpressionText.typeId);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kDataEvent), written[6].type);
    try std.testing.expectEqual(@as(u32, payload.len), written[6].data.data.size);
    try std.testing.expectEqual(@as(u32, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx)), written[6].data.data.type);
    try std.testing.expectEqualSlices(u8, &payload, written[6].data.data.bytes.?[0..payload.len]);
}

test "zig-vst3-plugin bridge drops output MIDI events with invalid legacy fields" {
    const large_payload = [_]u8{0xF0} ** (max_data_event_bytes + 1);
    const items = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 1, 60, 0.5).withBusIndex(-1),
        plug.process.Event.dataEvent(0, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx), &large_payload),
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 1, .control_number = -1, .value = 0.5 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 1, .control_number = 256, .value = 0.5 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 128, .control_number = ivstmidicontrollers.kCtrlModWheel, .value = 0.5 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 1, .control_number = ivstmidicontrollers.kCtrlModWheel, .value = std.math.nan(f32) },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 1, .control_number = ivstmidicontrollers.kCtrlModWheel, .value = -0.1 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 0, .channel = 1, .control_number = ivstmidicontrollers.kCtrlModWheel, .value = 1.1 },
        .{ .kind = .pitch_bend, .bus_index = 0, .sample_offset = 0, .channel = 128, .value = 0.5 },
        .{ .kind = .pitch_bend, .bus_index = 0, .sample_offset = 0, .channel = 1, .value = std.math.nan(f32) },
        .{ .kind = .pitch_bend, .bus_index = 0, .sample_offset = 1, .channel = 1, .control_number = 512, .value = 0.5 },
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .velocity = std.math.nan(f32) },
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 16, .pitch = 60, .velocity = 0.5 },
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 128, .velocity = 0.5 },
        .{ .kind = .note_off, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .velocity = -0.1 },
        .{ .kind = .note_off, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 61, .velocity = 0.25 },
        .{ .kind = .aftertouch, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .value = 1.1 },
        .{ .kind = .aftertouch, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = -1, .value = 0.5 },
        .{ .kind = .note_expression_value, .bus_index = 0, .sample_offset = 0, .note_id = 42, .expression_type_id = 5, .value = std.math.inf(f32) },
    };
    const List = vst_event_list.EventList(2);
    var list = List{};
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
        .outputEvents = list.asInterface(),
    };

    try std.testing.expectEqual(types.kResultOk, writeOutputEvents(&data, .{ .items = &items }));

    const written = list.items();
    try std.testing.expectEqual(@as(usize, 2), written.len);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), written[0].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kPitchBend), written[0].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@as(types.int8, 1), written[0].data.midiCCOut.channel);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent), written[1].type);
    try std.testing.expectEqual(@as(types.int16, 61), written[1].data.noteOff.pitch);
}

test "zig-vst3-plugin bridge reports output event write failures" {
    const items = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
    };
    const List = vst_event_list.EventList(1);
    var list = List{ .fail_add_index = 0 };
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 1,
        .outputEvents = list.asInterface(),
    };

    try std.testing.expectEqual(types.kResultFalse, writeOutputEvents(&data, .{ .items = &items }));
}

test "zig-vst3-plugin bridge rejects output events for negative process frame counts" {
    const items = [_]plug.process.Event{
        plug.process.Event.noteOn(0, 0, 60, 0.75),
    };
    const List = vst_event_list.EventList(1);
    var list = List{};
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = -1,
        .outputEvents = list.asInterface(),
    };

    try std.testing.expectEqual(types.kInvalidArgument, writeOutputEvents(&data, .{ .items = &items }));
    try std.testing.expectEqual(@as(usize, 0), list.items().len);
}

test "zig-vst3-plugin bridge parameter controller exposes reflected edit operations" {
    const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = 7, .name = "Gain", .short_name = "Gn", .units = "dB", .min = 0.0, .max = 2.0, .default = 1.0, .unit_id = 2 },
        bypass: plug.parameters.BoolParam = .{ .id = 8, .name = "Bypass" },
        meter: plug.parameters.FloatParam = .{ .id = 9, .name = "Meter", .min = 0.0, .max = 1.0, .default = 0.5, .is_read_only = true },
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var state = ParameterState(Params).init(&set);
    var controller = ParameterController(Params){
        .set = &set,
        .state = &state,
    };
    var info = ivsteditcontroller.ParameterInfo{};
    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(@as(types.int32, 3), controller.parameterCount());
    try std.testing.expectEqual(types.kResultOk, controller.parameterInfo(0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try std.testing.expectEqual(@as(vsttypes.UnitID, 2), info.unitId);
    try expectString128("Gain", &info.title);
    try expectString128("Gn", &info.shortTitle);
    try expectString128("dB", &info.units);
    try std.testing.expectEqual(types.kInvalidArgument, controller.parameterInfo(-1, &info));
    try std.testing.expectEqual(types.kInvalidArgument, controller.parameterInfo(3, &info));

    try std.testing.expectEqual(types.kResultOk, controller.stringByValue(7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[6]);
    try std.testing.expectEqual(types.kResultOk, controller.valueByString(7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), controller.plainFromNormalized(7, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), controller.normalizedFromPlain(7, 1.0));

    try std.testing.expectEqual(types.kResultOk, controller.setNormalized(8, 1.0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), controller.getNormalized(8));
    try std.testing.expectEqual(types.kResultFalse, controller.setNormalized(9, 0.9));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), controller.getNormalized(9));
    try std.testing.expectEqual(types.kInvalidArgument, controller.setNormalized(99, 0.5));

    const changes = [_]plug.process.ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.0 },
        .{ .id = 9, .sample_offset = 2, .normalized = 1.0 },
    };
    controller.applyChanges(try plug.process.ParameterChanges.init(&changes, 3));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), controller.getNormalized(7));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.0), controller.getNormalized(8));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), controller.getNormalized(9));
}

test "zig-vst3-plugin bridge stereo buses expose audio and event input metadata" {
    var info = ivstcomponent.BusInfo{};

    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 0), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCountWithEventOutput(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput), true));

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfo(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 2), info.channelCount);
    try std.testing.expectEqual(ivstcomponent.BusFlags.kDefaultActive, info.flags);
    try expectString128("Stereo In", &info.name);

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfo(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
    try std.testing.expectEqual(ivstcomponent.BusFlags.kDefaultActive, info.flags);
    try expectString128("Event In", &info.name);

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfoWithEventOutput(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &info, true));
    try std.testing.expectEqual(@as(types.int32, 1), info.channelCount);
    try std.testing.expectEqual(ivstcomponent.BusFlags.kDefaultActive, info.flags);
    try expectString128("Event Out", &info.name);

    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.busInfo(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 1, &info));
}

test "zig-vst3-plugin bridge stereo audio buses validate arrangements" {
    var inputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var outputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var arrangement_out: vsttypes.SpeakerArrangement = empty_arrangement;

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.setArrangements(&inputs, 1, &outputs, 1));
    inputs[0] = empty_arrangement;
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(&inputs, 1, &outputs, 1));
    inputs[0] = stereo_arrangement;
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(null, 1, &outputs, 1));
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(&inputs, 0, &outputs, 1));
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(&inputs, 1, null, 1));
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(&inputs, 1, &outputs, 0));

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.arrangement(@intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &arrangement_out));
    try std.testing.expectEqual(stereo_arrangement, arrangement_out);
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.arrangement(@intFromEnum(ivstcomponent.BusDirections.kOutput), 1, &arrangement_out));
    try std.testing.expectEqual(empty_arrangement, arrangement_out);
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.arrangement(99, 0, &arrangement_out));
    try std.testing.expectEqual(empty_arrangement, arrangement_out);
}

test "zig-vst3-plugin bridge stereo buses can be output only" {
    var info = ivstcomponent.BusInfo{};
    var outputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var arrangement_out: vsttypes.SpeakerArrangement = empty_arrangement;
    const output_only = StereoAudioBuses.Config{ .audio_input = false };

    try std.testing.expectEqual(@as(types.int32, 0), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), output_only));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput), output_only));
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info, output_only));
    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &info, output_only));
    try expectString128("Stereo Out", &info.name);

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.setArrangementsConfigured(null, 0, &outputs, 1, output_only));
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangementsConfigured(&outputs, 1, &outputs, 1, output_only));
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.arrangementConfigured(@intFromEnum(ivstcomponent.BusDirections.kInput), 0, &arrangement_out, output_only));
    try std.testing.expectEqual(empty_arrangement, arrangement_out);
    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.arrangementConfigured(@intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &arrangement_out, output_only));
    try std.testing.expectEqual(stereo_arrangement, arrangement_out);
}

test "zig-vst3-plugin bridge stereo buses can be input only" {
    var info = ivstcomponent.BusInfo{};
    var inputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var arrangement_out: vsttypes.SpeakerArrangement = empty_arrangement;
    const input_only = StereoAudioBuses.Config{ .audio_output = false };

    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), input_only));
    try std.testing.expectEqual(@as(types.int32, 0), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput), input_only));
    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info, input_only));
    try expectString128("Stereo In", &info.name);
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &info, input_only));

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.setArrangementsConfigured(&inputs, 1, null, 0, input_only));
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangementsConfigured(&inputs, 1, &inputs, 1, input_only));
    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.arrangementConfigured(@intFromEnum(ivstcomponent.BusDirections.kInput), 0, &arrangement_out, input_only));
    try std.testing.expectEqual(stereo_arrangement, arrangement_out);
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.arrangementConfigured(@intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &arrangement_out, input_only));
    try std.testing.expectEqual(empty_arrangement, arrangement_out);
}

test "zig-vst3-plugin bridge stereo buses can disable event input" {
    var info = ivstcomponent.BusInfo{};
    const no_event_input = StereoAudioBuses.Config{ .event_input = false };

    try std.testing.expectEqual(@as(types.int32, 0), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput), no_event_input));
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info, no_event_input));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCountConfigured(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput), .{ .event_input = false, .event_output = true }));
    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfoConfigured(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &info, .{ .event_input = false, .event_output = true }));
    try expectString128("Event Out", &info.name);
}

test "zig-vst3-plugin bridge realtime processor defaults accept 32 and 64 bit samples" {
    try std.testing.expectEqual(types.kResultOk, RealtimeProcessorDefaults.canProcessSampleSize(@intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32)));
    try std.testing.expectEqual(types.kResultOk, RealtimeProcessorDefaults.canProcessSampleSize(@intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64)));
    try std.testing.expectEqual(types.kResultFalse, RealtimeProcessorDefaults.canProcessSampleSize(99));
    try std.testing.expectEqual(@as(types.uint32, 0), RealtimeProcessorDefaults.latencySamples());
    try std.testing.expectEqual(@as(types.uint32, ivstaudioprocessor.kNoTail), RealtimeProcessorDefaults.tailSamples());
}

test "zig-vst3-plugin bridge realtime processor defaults validate process setup" {
    var setup = ivstaudioprocessor.ProcessSetup{
        .processMode = @intFromEnum(ivstaudioprocessor.ProcessModes.kRealtime),
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .maxSamplesPerBlock = 64,
        .sampleRate = 48_000.0,
    };

    try std.testing.expectEqual(types.kResultOk, RealtimeProcessorDefaults.validateProcessSetup(&setup));

    setup.symbolicSampleSize = 99;
    try std.testing.expectEqual(types.kResultFalse, RealtimeProcessorDefaults.validateProcessSetup(&setup));

    setup.symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32);
    setup.maxSamplesPerBlock = 0;
    try std.testing.expectEqual(types.kInvalidArgument, RealtimeProcessorDefaults.validateProcessSetup(&setup));

    setup.maxSamplesPerBlock = 64;
    setup.sampleRate = 0.0;
    try std.testing.expectEqual(types.kInvalidArgument, RealtimeProcessorDefaults.validateProcessSetup(&setup));
}

test "zig-vst3-plugin bridge process data frame counts are explicit" {
    var data = ivstaudioprocessor.ProcessData{ .numSamples = 16 };
    try std.testing.expectEqual(@as(usize, 16), frameCountOrZero(&data));
    try std.testing.expectEqual(@as(usize, 16), try validFrameCount(&data));

    data.numSamples = 0;
    try std.testing.expectEqual(@as(usize, 0), frameCountOrZero(&data));
    try std.testing.expectEqual(@as(usize, 0), try validFrameCount(&data));

    data.numSamples = -1;
    try std.testing.expectEqual(@as(usize, 0), frameCountOrZero(&data));
    try std.testing.expectError(error.InvalidFrameCount, validFrameCount(&data));
}

test "zig-vst3-plugin bridge normalized values are finite unit range" {
    try std.testing.expect(isNormalizedValue(@as(f64, 0.0)));
    try std.testing.expect(isNormalizedValue(@as(f64, 0.5)));
    try std.testing.expect(isNormalizedValue(@as(f64, 1.0)));
    try std.testing.expect(!isNormalizedValue(@as(f64, -0.01)));
    try std.testing.expect(!isNormalizedValue(@as(f64, 1.01)));
    try std.testing.expect(!isNormalizedValue(std.math.nan(f32)));
    try std.testing.expect(!isNormalizedValue(std.math.inf(f64)));
}

test "zig-vst3-plugin bridge VST sample offsets are explicit" {
    try std.testing.expectEqual(@as(usize, 0), sampleOffsetInBlock(0, 4).?);
    try std.testing.expectEqual(@as(usize, 3), sampleOffsetInBlock(3, 4).?);
    try std.testing.expectEqual(null, sampleOffsetInBlock(-1, 4));
    try std.testing.expectEqual(null, sampleOffsetInBlock(4, 4));
    try std.testing.expectEqual(null, sampleOffsetInBlock(0, 0));
}

test "zig-vst3-plugin bridge plugin sample offsets fit VST int32" {
    try std.testing.expectEqual(@as(types.int32, 0), vstSampleOffset(0).?);
    try std.testing.expectEqual(std.math.maxInt(types.int32), vstSampleOffset(std.math.maxInt(types.int32)).?);
    try std.testing.expectEqual(null, vstSampleOffset(@as(usize, std.math.maxInt(types.int32)) + 1));
}

test "zig-vst3-plugin bridge stream byte counts fit VST int32" {
    try std.testing.expectEqual(@as(types.int32, 0), vst_stream.byteCount(0).?);
    try std.testing.expectEqual(std.math.maxInt(types.int32), vst_stream.byteCount(std.math.maxInt(types.int32)).?);
    try std.testing.expectEqual(null, vst_stream.byteCount(@as(usize, std.math.maxInt(types.int32)) + 1));
}

test "zig-vst3-plugin bridge fills VST3 parameter info from reflected set" {
    const Mode = enum { clean, boost, mute };
    const Params = struct {
        gain: plug.parameters.FloatParam = .{ .id = 7, .name = "Gain", .short_name = "Gn", .units = "dB", .min = 0.0, .max = 2.0, .default = 1.0 },
        bypass: plug.parameters.BoolParam = .{ .id = 8, .name = "Bypass", .is_bypass = true },
        voices: plug.parameters.IntParam = .{ .id = 9, .name = "Voices", .min = 1, .max = 4, .default = 1, .can_automate = false, .is_read_only = true },
        mode: plug.parameters.EnumParam(Mode) = .{ .id = 10, .name = "Mode", .default = .clean },
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var info = ivsteditcontroller.ParameterInfo{};

    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try std.testing.expectEqual(@as(types.int32, 0), info.stepCount);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), info.defaultNormalizedValue);
    try expectString128("Gain", &info.title);
    try expectString128("Gn", &info.shortTitle);
    try expectString128("dB", &info.units);
    try std.testing.expectEqual(ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate, info.flags);
    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 1, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.stepCount);
    try std.testing.expect((info.flags & ivsteditcontroller.ParameterInfo.ParameterFlags.kIsBypass) != 0);
    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 2, &info));
    try std.testing.expectEqual(@as(types.int32, 3), info.stepCount);
    try std.testing.expect((info.flags & ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate) == 0);
    try std.testing.expect((info.flags & ivsteditcontroller.ParameterInfo.ParameterFlags.kIsReadOnly) != 0);
    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 3, &info));
    try std.testing.expectEqual(@as(types.int32, 2), info.stepCount);
    try std.testing.expect((info.flags & ivsteditcontroller.ParameterInfo.ParameterFlags.kIsList) != 0);
    try std.testing.expectEqual(types.kInvalidArgument, fillParameterInfo(Params, &set, 4, &info));
}

test "zig-vst3-plugin bridge formats and parses VST3 parameter strings" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** string128.code_units;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(types.kResultOk, getParamStringByValue(Params, &set, 7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[6]);
    try std.testing.expectEqual(types.kResultOk, getParamValueByString(Params, &set, 7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    text = [_]vsttypes.TChar{'x'} ** string128.code_units;
    try std.testing.expectEqual(types.kInvalidArgument, getParamStringByValue(Params, &set, 8, 0.5, &text));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[string128.payload_units]);

    value = 99;
    try std.testing.expectEqual(types.kInvalidArgument, getParamValueByString(Params, &set, 8, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0), value);
}

test "zig-vst3-plugin bridge converts VST3 normalized and plain values" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), normalizedParamToPlain(Params, &set, 7, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), plainParamToNormalized(Params, &set, 7, 1.0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.0), normalizedParamToPlain(Params, &set, 8, 0.5));
}

test "zig-vst3-plugin bridge builds process context from VST3 buffers" {
    var in_left = [_]f32{ 1.0, 2.0 };
    var in_right = [_]f32{ 3.0, 4.0 };
    var out_left = [_]f32{ 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{ &in_left, &in_right };
    var output_channel_ptrs = [_][*]f32{ &out_left, &out_right };
    const input = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    };
    const output = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    };
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
        .processContext = &process_context,
    };

    const context = try makeProcessContext(f32, input, output, &data, .{}, .{}, null);

    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 3.0), context.inputChannel(1).?[0]);
    context.outputChannel(0).?[1] = 9.0;
    try std.testing.expectEqual(@as(f32, 9.0), out_left[1]);
}

test "zig-vst3-plugin bridge rejects negative process channel counts" {
    const input = ivstaudioprocessor.AudioBusBuffers{ .numChannels = -1 };
    const output = ivstaudioprocessor.AudioBusBuffers{ .numChannels = 1 };
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{ .numSamples = 2, .processContext = &process_context };

    try std.testing.expectError(error.InvalidChannelCount, makeProcessContext(f32, input, output, &data, .{}, .{}, null));
}

test "zig-vst3-plugin bridge rejects invalid process context sample rates" {
    var in_left = [_]f32{ 1.0, 2.0 };
    var out_left = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{&in_left};
    var output_channel_ptrs = [_][*]f32{&out_left};
    const input = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    };
    const output = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    };
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = 0.0 };
    const data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
        .processContext = &process_context,
    };

    try std.testing.expectError(error.InvalidSampleRate, makeProcessContext(f32, input, output, &data, .{}, .{}, null));
}

test "zig-vst3-plugin bridge builds process context from main VST3 buses" {
    var in_left = [_]f32{ 1.0, 2.0 };
    var in_right = [_]f32{ 3.0, 4.0 };
    var out_left = [_]f32{ 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{ &in_left, &in_right };
    var output_channel_ptrs = [_][*]f32{ &out_left, &out_right };
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .processContext = &process_context,
    };

    const context = try makeMainAudioProcessContext(f32, &data, .{}, .{}, null);

    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 4.0), context.inputChannel(1).?[1]);
}

test "zig-vst3-plugin bridge rejects missing main process buses" {
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .numSamples = 2,
        .processContext = &process_context,
    };

    try std.testing.expectError(error.MissingMainAudioBus, makeMainAudioProcessContext(f32, &data, .{}, .{}, null));
}

test "zig-vst3-plugin bridge builds output-only main process context" {
    var out_left = [_]f32{ 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0 };
    var output_channel_ptrs = [_][*]f32{ &out_left, &out_right };
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &outputs,
        .numSamples = 2,
        .processContext = &process_context,
    };

    const context = try makeMainAudioProcessContextConfigured(f32, &data, .{}, .{}, null, .{ .audio_input = false });

    try std.testing.expectEqual(@as(usize, 0), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.outputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    context.outputChannel(1).?[0] = 0.75;
    try std.testing.expectEqual(@as(f32, 0.75), out_right[0]);
}

test "zig-vst3-plugin bridge builds input-only main process context" {
    var in_left = [_]f32{ 0.25, 0.5 };
    var in_right = [_]f32{ 0.75, 1.0 };
    var input_channel_ptrs = [_][*]f32{ &in_left, &in_right };
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 0,
        .inputs = &inputs,
        .numSamples = 2,
        .processContext = &process_context,
    };

    const context = try makeMainAudioProcessContextConfigured(f32, &data, .{}, .{}, null, .{ .audio_output = false });

    try std.testing.expectEqual(@as(usize, 2), context.inputChannelCount());
    try std.testing.expectEqual(@as(usize, 0), context.outputChannelCount());
    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 1.0), context.inputChannel(1).?[1]);
}

test "zig-vst3-plugin bridge dispatches main audio processing by sample size" {
    const Doubler = struct {
        pub fn process(_: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * 2;
                }
            }
        }
    };

    var input_samples = [_]f32{ 1.0, 2.0 };
    var output_samples = [_]f32{ 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, null, Doubler{}));
    try std.testing.expectEqual(@as(f32, 2.0), output_samples[0]);
    try std.testing.expectEqual(@as(f32, 4.0), output_samples[1]);
}

test "zig-vst3-plugin bridge dispatches double precision main audio" {
    const Doubler = struct {
        calls: *usize,

        pub fn process(self: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            self.calls.* += 1;
            for (0..context.outputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = input[sample] * 2;
                }
            }
        }
    };

    var input_samples = [_]f64{ 1.5, 2.5 };
    var output_samples = [_]f64{ 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .processContext = &process_context,
    };

    var calls: usize = 0;
    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, null, Doubler{ .calls = &calls }));
    try std.testing.expectEqual(@as(usize, 1), calls);
    try std.testing.expectEqual(@as(f64, 3.0), output_samples[0]);
    try std.testing.expectEqual(@as(f64, 5.0), output_samples[1]);
}

test "zig-vst3-plugin bridge passes double precision process context inputs" {
    const Recorder = struct {
        saw_double: *bool,
        parameter_count: *usize,
        parameter_offset: *usize,
        event_count: *usize,
        event_pitch: *i16,

        pub fn process(self: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            self.saw_double.* = Sample == f64;
            self.parameter_count.* = context.parameterChangeCount();
            if (context.firstParameterChange(9)) |change| {
                self.parameter_offset.* = change.sample_offset;
            }
            self.event_count.* = context.inputEventCount();
            if (context.firstEvent(.note_on)) |event| {
                self.event_pitch.* = event.pitch;
                context.appendOutputEvent(plug.process.Event.noteOff(event.sample_offset + 1, event.channel, event.pitch, 0.0)) catch {};
            }
        }
    };

    var input_samples = [_]f64{ 0.0, 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64),
        .processContext = &process_context,
    };
    const parameter_items = [_]plug.process.ParameterChange{.{
        .id = 9,
        .sample_offset = 1,
        .normalized = 0.5,
    }};
    const event_items = [_]plug.process.Event{
        plug.process.Event.noteOn(1, 0, 67, 0.5),
    };
    const parameter_changes = try plug.process.ParameterChanges.init(&parameter_items, input_samples.len);
    const events = try plug.process.Events.init(&event_items, input_samples.len);
    var output_event_storage: [1]plug.process.Event = undefined;
    var output_events = plug.process.EventWriter.init(&output_event_storage, input_samples.len);
    var saw_double = false;
    var parameter_count: usize = 0;
    var parameter_offset: usize = 99;
    var event_count: usize = 0;
    var event_pitch: i16 = -1;

    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, parameter_changes, events, &output_events, Recorder{
        .saw_double = &saw_double,
        .parameter_count = &parameter_count,
        .parameter_offset = &parameter_offset,
        .event_count = &event_count,
        .event_pitch = &event_pitch,
    }));
    try std.testing.expect(saw_double);
    try std.testing.expectEqual(@as(usize, 1), parameter_count);
    try std.testing.expectEqual(@as(usize, 1), parameter_offset);
    try std.testing.expectEqual(@as(usize, 1), event_count);
    try std.testing.expectEqual(@as(i16, 67), event_pitch);
    try std.testing.expectEqual(@as(usize, 1), output_events.eventCount());
    try std.testing.expectEqual(@as(usize, 2), output_events.events().items[0].sample_offset);
    try std.testing.expectEqual(@as(i16, 67), output_events.events().items[0].pitch);
}

test "zig-vst3-plugin bridge passes automation and events to main audio processors" {
    const Recorder = struct {
        parameter_count: *usize,
        parameter_offset: *usize,
        parameter_value: *f64,
        event_count: *usize,
        event_offset: *usize,
        event_pitch: *i16,

        pub fn process(self: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            self.parameter_count.* = context.parameterChangeCount();
            if (context.firstParameterChange(7)) |change| {
                self.parameter_offset.* = change.sample_offset;
                self.parameter_value.* = change.normalized;
            }
            self.event_count.* = context.inputEventCount();
            if (context.firstEvent(.note_on)) |event| {
                self.event_offset.* = event.sample_offset;
                self.event_pitch.* = event.pitch;
            }
        }
    };

    var input_samples = [_]f32{ 0.0, 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = input_samples.len,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };
    const parameter_items = [_]plug.process.ParameterChange{.{
        .id = 7,
        .sample_offset = 1,
        .normalized = 0.25,
    }};
    const event_items = [_]plug.process.Event{
        plug.process.Event.noteOn(2, 0, 64, 0.5),
    };
    const parameter_changes = try plug.process.ParameterChanges.init(&parameter_items, input_samples.len);
    const events = try plug.process.Events.init(&event_items, input_samples.len);
    var parameter_count: usize = 0;
    var parameter_offset: usize = 99;
    var parameter_value: f64 = 99;
    var event_count: usize = 0;
    var event_offset: usize = 99;
    var event_pitch: i16 = -1;

    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, parameter_changes, events, null, Recorder{
        .parameter_count = &parameter_count,
        .parameter_offset = &parameter_offset,
        .parameter_value = &parameter_value,
        .event_count = &event_count,
        .event_offset = &event_offset,
        .event_pitch = &event_pitch,
    }));
    try std.testing.expectEqual(@as(usize, 1), parameter_count);
    try std.testing.expectEqual(@as(usize, 1), parameter_offset);
    try std.testing.expectEqual(@as(f64, 0.25), parameter_value);
    try std.testing.expectEqual(@as(usize, 1), event_count);
    try std.testing.expectEqual(@as(usize, 2), event_offset);
    try std.testing.expectEqual(@as(i16, 64), event_pitch);
}

test "zig-vst3-plugin bridge reports malformed main process data" {
    const Noop = struct {
        pub fn process(_: @This(), comptime Sample: type, _: *plug.process.ProcessContext(Sample)) void {}
    };

    var input_samples = [_]f32{ 1.0, 2.0 };
    var output_samples = [_]f32{ 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    var data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };

    data.numSamples = -1;
    try std.testing.expectEqual(types.kInvalidArgument, processMainAudio(&data, .{}, .{}, null, Noop{}));

    data.numSamples = 2;
    process_context.sampleRate = 0.0;
    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, null, Noop{}));

    process_context.sampleRate = test_sample_rate;
    inputs[0].numChannels = -1;
    try std.testing.expectEqual(types.kInvalidArgument, processMainAudio(&data, .{}, .{}, null, Noop{}));

    inputs[0].numChannels = 1;
    data.inputs = null;
    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, null, Noop{}));
}

test "zig-vst3-plugin bridge processes output-only main audio" {
    const Generator = struct {
        pub fn process(_: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            for (0..context.outputChannelCount()) |channel| {
                const output = context.outputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    output[sample] = @floatFromInt(sample + channel);
                }
            }
        }
    };

    var left = [_]f32{ 0.0, 0.0 };
    var right = [_]f32{ 0.0, 0.0 };
    var output_channel_ptrs = [_][*]f32{ &left, &right };
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = output_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };

    try std.testing.expectEqual(types.kResultOk, processMainAudioConfigured(&data, .{}, .{}, null, Generator{}, .{ .audio_input = false }));
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 1.0 }, &left);
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 2.0 }, &right);
}

test "zig-vst3-plugin bridge processes input-only main audio" {
    const Analyzer = struct {
        total: *f32,

        pub fn process(self: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            for (0..context.inputChannelCount()) |channel| {
                const input = context.inputChannel(channel) orelse continue;
                for (0..context.frameCount()) |sample| {
                    self.total.* += @floatCast(input[sample]);
                }
            }
        }
    };

    var left = [_]f32{ 0.25, 0.5 };
    var right = [_]f32{ 0.75, 1.0 };
    var input_channel_ptrs = [_][*]f32{ &left, &right };
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = input_channel_ptrs[0..].ptr },
    }};
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 0,
        .inputs = &inputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };
    var total: f32 = 0.0;

    try std.testing.expectEqual(types.kResultOk, processMainAudioConfigured(&data, .{}, .{}, null, Analyzer{ .total = &total }, .{ .audio_output = false }));
    try std.testing.expectEqual(@as(f32, 2.5), total);
}

test "zig-vst3-plugin bridge exposes output event writer to processors" {
    const EventEmitter = struct {
        pub fn process(_: @This(), comptime Sample: type, context: *plug.process.ProcessContext(Sample)) void {
            context.appendOutputEvent(plug.process.Event.noteOn(1, 0, 60, 0.75)) catch {};
        }
    };

    var input_samples = [_]f32{ 1.0, 2.0 };
    var output_samples = [_]f32{ 0.0, 0.0 };
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
    var process_context = ivstprocesscontext.ProcessContext{ .sampleRate = test_sample_rate };
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
        .processContext = &process_context,
    };
    var event_storage: [1]plug.process.Event = undefined;
    var writer = plug.process.EventWriter.init(&event_storage, 2);

    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, &writer, EventEmitter{}));
    try std.testing.expectEqual(@as(usize, 1), writer.eventCount());
    try std.testing.expectEqual(plug.process.EventKind.note_on, writer.events().items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), writer.events().items[0].sample_offset);
}

fn expectString128(expected: []const u8, actual: *const vsttypes.String128) !void {
    for (expected, 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, char), actual[index]);
    }
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), actual[expected.len]);
}
