const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const ivstevents = @import("pluginterfaces/vst/ivstevents.zig");
const ivstmidicontrollers = @import("pluginterfaces/vst/ivstmidicontrollers.zig");
const ivstparameterchanges = @import("pluginterfaces/vst/ivstparameterchanges.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-plug-core");
const audio_processor_algo = @import("pluginterfaces/vst/vstaudioprocessoralgo.zig");
const events_helper = @import("pluginterfaces/vst/vsteventshelper.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");
const vst_event_list = @import("vst_event_list.zig");
const vst_parameter_changes = @import("vst_parameter_changes.zig");
const vst_stream = @import("vst_stream.zig");

const max_audio_channels = 64;
const empty_arrangement: vsttypes.SpeakerArrangement = 0;
const stereo_arrangement: vsttypes.SpeakerArrangement = 3;

pub const StereoAudioBuses = struct {
    pub fn busCount(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) types.int32 {
        return busCountWithEventOutput(media_type, direction, false);
    }

    pub fn busCountWithEventOutput(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, event_output: bool) types.int32 {
        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and isInputOrOutput(direction)) {
            return 1;
        }
        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) {
            return 1;
        }
        if (event_output and media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput)) {
            return 1;
        }
        return 0;
    }

    pub fn busInfo(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) types.tresult {
        return busInfoWithEventOutput(media_type, direction, index, out, false);
    }

    pub fn busInfoWithEventOutput(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo, event_output: bool) types.tresult {
        if (index != 0) {
            out.* = .{};
            return types.kInvalidArgument;
        }

        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and isInputOrOutput(direction)) {
            out.* = .{
                .mediaType = media_type,
                .direction = direction,
                .channelCount = 2,
                .busType = @intFromEnum(ivstcomponent.BusTypes.kMain),
                .flags = ivstcomponent.BusFlags.kDefaultActive,
            };
            copyAscii16(&out.name, if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) "Stereo In" else "Stereo Out");
            return types.kResultOk;
        }

        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kEvent) and
            (direction == @intFromEnum(ivstcomponent.BusDirections.kInput) or
                (event_output and direction == @intFromEnum(ivstcomponent.BusDirections.kOutput))))
        {
            out.* = .{
                .mediaType = media_type,
                .direction = direction,
                .channelCount = 1,
                .busType = @intFromEnum(ivstcomponent.BusTypes.kMain),
                .flags = ivstcomponent.BusFlags.kDefaultActive,
            };
            copyAscii16(&out.name, if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) "Event In" else "Event Out");
            return types.kResultOk;
        }

        out.* = .{};
        return types.kInvalidArgument;
    }

    pub fn setArrangements(inputs: ?[*]vsttypes.SpeakerArrangement, num_inputs: types.int32, outputs: ?[*]vsttypes.SpeakerArrangement, num_outputs: types.int32) types.tresult {
        if (num_inputs != 1 or num_outputs != 1 or inputs == null or outputs == null) {
            return types.kResultFalse;
        }
        if (inputs.?[0] != stereo_arrangement or outputs.?[0] != stereo_arrangement) {
            return types.kResultFalse;
        }
        return types.kResultOk;
    }

    pub fn arrangement(direction: vsttypes.BusDirection, index: types.int32, out: *vsttypes.SpeakerArrangement) types.tresult {
        if (index != 0 or !isInputOrOutput(direction)) {
            out.* = empty_arrangement;
            return types.kInvalidArgument;
        }
        out.* = stereo_arrangement;
        return types.kResultOk;
    }

    fn isInputOrOutput(direction: vsttypes.BusDirection) bool {
        return direction == @intFromEnum(ivstcomponent.BusDirections.kInput) or
            direction == @intFromEnum(ivstcomponent.BusDirections.kOutput);
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
    if (index < 0 or index >= plug.parameters.ParameterSet(Params).count) {
        out.* = .{};
        return types.kInvalidArgument;
    }
    const parameter_index: usize = @intCast(index);
    out.* = .{
        .id = set.id(parameter_index).?,
        .stepCount = set.stepCount(parameter_index).?,
        .defaultNormalizedValue = set.defaultNormalized(parameter_index).?,
        .unitId = set.unitId(parameter_index).?,
        .flags = parameterInfoFlags(Params, set, parameter_index),
    };
    copyAscii16(&out.title, set.name(parameter_index).?);
    copyAscii16(&out.shortTitle, set.shortName(parameter_index).?);
    copyAscii16(&out.units, set.units(parameter_index).?);
    return types.kResultOk;
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
    copyAscii16Ptr(out, "");
    const index = set.indexOfId(id) orelse return types.kInvalidArgument;
    var buffer: [64]u8 = undefined;
    const text = set.formatPlain(index, value, &buffer) catch return types.kResultFalse;
    copyAscii16Ptr(out, text);
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
    var buffer: [128]u8 = undefined;
    const parsed_text = readAscii16Ptr(text, &buffer);
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

pub fn collectInputParameterChanges(data: *ivstaudioprocessor.ProcessData, storage: []plug.process.ParameterChange) plug.process.ParameterChanges {
    var collector = ParameterChangeCollector{
        .storage = storage,
        .frame_count = if (data.numSamples <= 0) 0 else @intCast(data.numSamples),
    };
    audio_processor_algo.forEachParameterChanges(data.inputParameterChanges, &collector, collectParameterQueue);
    return plug.process.ParameterChanges.init(storage[0..collector.count], collector.frame_count) catch .{};
}

pub fn collectInputEvents(data: *ivstaudioprocessor.ProcessData, storage: []plug.process.Event) plug.process.Events {
    var collector = EventCollector{
        .storage = storage,
        .frame_count = if (data.numSamples <= 0) 0 else @intCast(data.numSamples),
    };
    audio_processor_algo.forEachEvent(data.inputEvents, &collector, collectEvent);
    return plug.process.Events.init(storage[0..collector.count], collector.frame_count) catch .{};
}

pub fn writeOutputEvents(data: *ivstaudioprocessor.ProcessData, events: plug.process.Events) types.tresult {
    const output_events = data.outputEvents orelse return types.kResultOk;
    for (events.items) |event| {
        if (data.numSamples >= 0 and event.sample_offset >= @as(usize, @intCast(data.numSamples))) return types.kInvalidArgument;
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
    if (data.numSamples < 0) return error.InvalidFrameCount;
    if (input.numChannels < 0 or output.numChannels < 0) return error.InvalidChannelCount;
    const frame_count: usize = @intCast(data.numSamples);
    const channel_count: usize = @intCast(@min(@min(input.numChannels, output.numChannels), max_audio_channels));
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

pub fn makeMainAudioProcessContext(
    comptime Sample: type,
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
) !plug.process.ProcessContext(Sample) {
    if (data.numInputs <= 0 or data.numOutputs <= 0 or data.inputs == null or data.outputs == null) {
        return error.MissingMainAudioBus;
    }
    const input = data.inputs.?[0];
    const output = data.outputs.?[0];
    if (input.numChannels <= 0 or output.numChannels <= 0) {
        return error.MissingMainAudioChannels;
    }
    return makeProcessContext(Sample, input, output, data, parameter_changes, events, output_events);
}

pub fn processMainAudio(
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
    events: plug.process.Events,
    output_events: ?*plug.process.EventWriter,
    processor: anytype,
) types.tresult {
    if (data.symbolicSampleSize == @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32)) {
        var context = makeMainAudioProcessContext(f32, data, parameter_changes, events, output_events) catch return types.kResultOk;
        processor.process(f32, &context);
    } else {
        var context = makeMainAudioProcessContext(f64, data, parameter_changes, events, output_events) catch return types.kResultOk;
        processor.process(f64, &context);
    }
    return types.kResultOk;
}

pub fn readParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *plug.parameters.ParameterValues(Params),
) types.tresult {
    const input = stream orelse return types.kInvalidArgument;
    var input_reader = IBStreamReader{ .stream = input };
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
    var output_writer = IBStreamWriter{ .stream = output };
    plug.state.writeParameterState(Params, set, values, output_writer.writer()) catch return types.kResultFalse;
    return types.kResultOk;
}

const StreamError = error{ StreamReadFailed, StreamWriteFailed };

const IBStreamReader = struct {
    stream: *ibstream.IBStream,

    const Reader = std.io.Reader(*IBStreamReader, StreamError, read);

    fn reader(self: *IBStreamReader) Reader {
        return .{ .context = self };
    }

    fn read(self: *IBStreamReader, buffer: []u8) StreamError!usize {
        if (buffer.len == 0) return 0;
        if (buffer.len > std.math.maxInt(types.int32)) return error.StreamReadFailed;
        var bytes_read: types.int32 = 0;
        const result = self.stream.vtable.read(self.stream, buffer.ptr, @intCast(buffer.len), &bytes_read);
        if (result != types.kResultOk or bytes_read < 0) return error.StreamReadFailed;
        return @intCast(bytes_read);
    }
};

const IBStreamWriter = struct {
    stream: *ibstream.IBStream,

    const Writer = std.io.Writer(*IBStreamWriter, StreamError, write);

    fn writer(self: *IBStreamWriter) Writer {
        return .{ .context = self };
    }

    fn write(self: *IBStreamWriter, bytes: []const u8) StreamError!usize {
        if (bytes.len == 0) return 0;
        if (bytes.len > std.math.maxInt(types.int32)) return error.StreamWriteFailed;
        var bytes_written: types.int32 = 0;
        const result = self.stream.vtable.write(self.stream, @constCast(bytes.ptr), @intCast(bytes.len), &bytes_written);
        if (result != types.kResultOk or bytes_written < 0) return error.StreamWriteFailed;
        return @intCast(bytes_written);
    }
};

fn copyAscii16(dest: *vsttypes.String128, source: []const u8) void {
    @memset(dest, 0);
    const len = @min(source.len, dest.len - 1);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

fn copyAscii16Ptr(dest: [*]vsttypes.TChar, source: []const u8) void {
    @memset(dest[0..128], 0);
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
}

fn readAscii16Ptr(source: [*]vsttypes.TChar, buffer: []u8) []const u8 {
    var len: usize = 0;
    while (len < buffer.len and source[len] != 0) : (len += 1) {
        buffer[len] = @intCast(@min(source[len], 0xff));
    }
    return buffer[0..len];
}

fn vstAudioBuffers(comptime Sample: type, buffer: ivstaudioprocessor.AudioBusBuffers) ?[*][*]Sample {
    return switch (Sample) {
        f32 => buffer.channelBuffers.channelBuffers32,
        f64 => buffer.channelBuffers.channelBuffers64,
        else => @compileError("unsupported VST3 sample type"),
    };
}

const ParameterChangeCollector = struct {
    storage: []plug.process.ParameterChange,
    count: usize = 0,
    frame_count: usize,
};

const EventCollector = struct {
    storage: []plug.process.Event,
    count: usize = 0,
    frame_count: usize,
};

fn collectParameterQueue(collector: *ParameterChangeCollector, queue: *ivstparameterchanges.IParamValueQueue) void {
    audio_processor_algo.forEachParamValueQueue(queue, collector, collectParameterPoint);
}

fn collectParameterPoint(collector: *ParameterChangeCollector, id: vsttypes.ParamID, sample_offset: types.int32, value: vsttypes.ParamValue) void {
    if (collector.count >= collector.storage.len) return;
    if (sample_offset < 0) return;
    const offset: usize = @intCast(sample_offset);
    if (offset >= collector.frame_count) return;
    if (value < 0.0 or value > 1.0 or std.math.isNan(value)) return;
    collector.storage[collector.count] = .{
        .id = id,
        .sample_offset = offset,
        .normalized = value,
    };
    collector.count += 1;
}

fn collectEvent(collector: *EventCollector, event: *const ivstevents.Event) void {
    if (collector.count >= collector.storage.len) return;
    if (event.sampleOffset < 0) return;
    const offset: usize = @intCast(event.sampleOffset);
    if (offset >= collector.frame_count) return;
    const converted: ?plug.process.Event = switch (event.type) {
        @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent) => if (isUnitValue(event.data.noteOn.velocity))
            plug.process.Event.noteOn(offset, event.data.noteOn.channel, event.data.noteOn.pitch, event.data.noteOn.velocity).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent) => if (isUnitValue(event.data.noteOff.velocity))
            plug.process.Event.noteOff(offset, event.data.noteOff.channel, event.data.noteOff.pitch, event.data.noteOff.velocity).withBusIndex(event.busIndex)
        else
            null,
        @intFromEnum(ivstevents.Event.EventTypes.kDataEvent) => plug.process.Event.dataEvent(offset, event.data.data.type, dataEventBytes(event.data.data)).withBusIndex(event.busIndex),
        @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent) => collectLegacyMidiCcEvent(event, offset),
        @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent) => if (isUnitValue(event.data.polyPressure.pressure))
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
    collector.storage[collector.count] = converted orelse return;
    collector.count += 1;
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

fn isUnitValue(value: f32) bool {
    return !std.math.isNan(value) and value >= 0.0 and value <= 1.0;
}

fn isFiniteValue(value: anytype) bool {
    return !std.math.isNan(value) and !std.math.isInf(value);
}

fn toVstEvent(event: plug.process.Event) ?ivstevents.Event {
    if (event.sample_offset > std.math.maxInt(types.int32)) return null;
    const offset: types.int32 = @intCast(event.sample_offset);
    var result = ivstevents.Event{
        .busIndex = event.bus_index,
        .sampleOffset = offset,
    };
    switch (event.kind) {
        .note_on => {
            if (!isUnitValue(event.velocity)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent);
            result.data = .{ .noteOn = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .velocity = event.velocity,
            } };
        },
        .note_off => {
            if (!isUnitValue(event.velocity)) return null;
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
            if (!isUnitValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent);
            result.data = .{ .midiCCOut = .{
                .controlNumber = control_number,
                .channel = channel,
                .value = events_helper.getMIDICCOutValue(event.value),
            } };
        },
        .pitch_bend => {
            const channel = std.math.cast(types.int8, event.channel) orelse return null;
            if (!isUnitValue(event.value)) return null;
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent);
            result.data = .{ .midiCCOut = .{
                .controlNumber = ivstmidicontrollers.kPitchBend,
                .channel = channel,
                .value = 0,
            } };
            events_helper.setPitchBendValue(&result.data.midiCCOut, event.value);
        },
        .aftertouch => {
            if (!isUnitValue(event.value)) return null;
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

fn dataEventBytes(data: ivstevents.DataEvent) []const u8 {
    const bytes = data.bytes orelse return &.{};
    return bytes[0..data.size];
}

test "zig-plug bridge round-trips parameter state through IBStream" {
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

test "zig-plug bridge reads older parameter state without requiring current encoded size" {
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

test "zig-plug bridge rejects truncated IBStream state" {
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

test "zig-plug bridge rejects invalid normalized IBStream state" {
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
    const second_value_offset = 8 + @sizeOf(u16) + @sizeOf(u16) + @sizeOf(u32) + @sizeOf(u64) + @sizeOf(u32);
    var invalid_value = std.io.fixedBufferStream(stream.bytes[second_value_offset..][0..@sizeOf(u64)]);
    try invalid_value.writer().writeInt(u64, @bitCast(@as(f64, 1.5)), .little);
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, restored.readFromStream(stream.asStream()));

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.8), restored.getNormalizedById(0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.6), restored.getNormalizedById(1));
}

test "zig-plug bridge reports failed IBStream writes" {
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

test "zig-plug bridge parameter state stores ids and persists streams" {
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

test "zig-plug bridge collects VST3 parameter changes" {
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

test "zig-plug bridge drops invalid and overflowing VST3 parameter changes" {
    const Changes = vst_parameter_changes.ParameterChanges(2, 5);
    var changes = Changes{};
    const gain_queue = changes.addQueue(7).?;
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(-1, 0.5));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(4, 0.75));
    try std.testing.expectEqual(types.kResultOk, gain_queue.appendPoint(2, 1.5));
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

test "zig-plug bridge collects VST3 input events" {
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

test "zig-plug bridge drops invalid and overflowing VST3 input events" {
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

test "zig-plug bridge preserves unknown VST3 input events as other" {
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

test "zig-plug bridge maps legacy MIDI controller events" {
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

test "zig-plug bridge maps poly pressure and note expression events" {
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

test "zig-plug bridge preserves VST3 data event payloads" {
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

test "zig-plug bridge writes output events to VST3 event lists" {
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

test "zig-plug bridge drops output MIDI events with invalid legacy fields" {
    const items = [_]plug.process.Event{
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
        .{ .kind = .note_off, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .velocity = -0.1 },
        .{ .kind = .aftertouch, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .value = 1.1 },
        .{ .kind = .note_expression_value, .bus_index = 0, .sample_offset = 0, .note_id = 42, .expression_type_id = 5, .value = std.math.inf(f32) },
    };
    const List = vst_event_list.EventList(1);
    var list = List{};
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
        .outputEvents = list.asInterface(),
    };

    try std.testing.expectEqual(types.kResultOk, writeOutputEvents(&data, .{ .items = &items }));

    const written = list.items();
    try std.testing.expectEqual(@as(usize, 1), written.len);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), written[0].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kPitchBend), written[0].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@as(types.int8, 1), written[0].data.midiCCOut.channel);
}

test "zig-plug bridge reports output event write failures" {
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

test "zig-plug bridge parameter controller exposes reflected edit operations" {
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
    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** 128;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(@as(types.int32, 3), controller.parameterCount());
    try std.testing.expectEqual(types.kResultOk, controller.parameterInfo(0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try std.testing.expectEqual(@as(vsttypes.UnitID, 2), info.unitId);
    try expectString128("Gain", &info.title);
    try expectString128("Gn", &info.shortTitle);
    try expectString128("dB", &info.units);

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

test "zig-plug bridge stereo buses expose audio and event input metadata" {
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

test "zig-plug bridge stereo audio buses validate arrangements" {
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

test "zig-plug bridge realtime processor defaults accept 32 and 64 bit samples" {
    try std.testing.expectEqual(types.kResultOk, RealtimeProcessorDefaults.canProcessSampleSize(@intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32)));
    try std.testing.expectEqual(types.kResultOk, RealtimeProcessorDefaults.canProcessSampleSize(@intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample64)));
    try std.testing.expectEqual(types.kResultFalse, RealtimeProcessorDefaults.canProcessSampleSize(99));
    try std.testing.expectEqual(@as(types.uint32, 0), RealtimeProcessorDefaults.latencySamples());
    try std.testing.expectEqual(@as(types.uint32, ivstaudioprocessor.kNoTail), RealtimeProcessorDefaults.tailSamples());
}

test "zig-plug bridge fills VST3 parameter info from reflected set" {
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

test "zig-plug bridge formats and parses VST3 parameter strings" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var text: vsttypes.String128 = [_]vsttypes.TChar{'x'} ** 128;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(types.kResultOk, getParamStringByValue(Params, &set, 7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[6]);
    try std.testing.expectEqual(types.kResultOk, getParamValueByString(Params, &set, 7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    text = [_]vsttypes.TChar{'x'} ** 128;
    try std.testing.expectEqual(types.kInvalidArgument, getParamStringByValue(Params, &set, 8, 0.5, &text));
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[0]);
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), text[127]);

    value = 99;
    try std.testing.expectEqual(types.kInvalidArgument, getParamValueByString(Params, &set, 8, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0), value);
}

test "zig-plug bridge converts VST3 normalized and plain values" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), normalizedParamToPlain(Params, &set, 7, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), plainParamToNormalized(Params, &set, 7, 1.0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.0), normalizedParamToPlain(Params, &set, 8, 0.5));
}

test "zig-plug bridge builds process context from VST3 buffers" {
    var in_left = [_]f32{ 1.0, 2.0 };
    var in_right = [_]f32{ 3.0, 4.0 };
    var out_left = [_]f32{ 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{ &in_left, &in_right };
    var output_channel_ptrs = [_][*]f32{ &out_left, &out_right };
    const input = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    };
    const output = ivstaudioprocessor.AudioBusBuffers{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    };
    const data = ivstaudioprocessor.ProcessData{
        .numSamples = 2,
    };

    const context = try makeProcessContext(f32, input, output, &data, .{}, .{}, null);

    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 3.0), context.inputChannel(1).?[0]);
    context.outputChannel(0).?[1] = 9.0;
    try std.testing.expectEqual(@as(f32, 9.0), out_left[1]);
}

test "zig-plug bridge rejects negative process channel counts" {
    const input = ivstaudioprocessor.AudioBusBuffers{ .numChannels = -1 };
    const output = ivstaudioprocessor.AudioBusBuffers{ .numChannels = 1 };
    const data = ivstaudioprocessor.ProcessData{ .numSamples = 2 };

    try std.testing.expectError(error.InvalidChannelCount, makeProcessContext(f32, input, output, &data, .{}, .{}, null));
}

test "zig-plug bridge builds process context from main VST3 buses" {
    var in_left = [_]f32{ 1.0, 2.0 };
    var in_right = [_]f32{ 3.0, 4.0 };
    var out_left = [_]f32{ 0.0, 0.0 };
    var out_right = [_]f32{ 0.0, 0.0 };
    var input_channel_ptrs = [_][*]f32{ &in_left, &in_right };
    var output_channel_ptrs = [_][*]f32{ &out_left, &out_right };
    var inputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 2,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    }};
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
    };

    const context = try makeMainAudioProcessContext(f32, &data, .{}, .{}, null);

    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 4.0), context.inputChannel(1).?[1]);
}

test "zig-plug bridge rejects missing main process buses" {
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .numSamples = 2,
    };

    try std.testing.expectError(error.MissingMainAudioBus, makeMainAudioProcessContext(f32, &data, .{}, .{}, null));
}

test "zig-plug bridge dispatches main audio processing by sample size" {
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
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    }};
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
    };

    try std.testing.expectEqual(types.kResultOk, processMainAudio(&data, .{}, .{}, null, Doubler{}));
    try std.testing.expectEqual(@as(f32, 2.0), output_samples[0]);
    try std.testing.expectEqual(@as(f32, 4.0), output_samples[1]);
}

test "zig-plug bridge exposes output event writer to processors" {
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
        .channelBuffers = .{ .channelBuffers32 = &input_channel_ptrs },
    }};
    var outputs = [_]ivstaudioprocessor.AudioBusBuffers{.{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = &output_channel_ptrs },
    }};
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 1,
        .numOutputs = 1,
        .inputs = &inputs,
        .outputs = &outputs,
        .numSamples = 2,
        .symbolicSampleSize = @intFromEnum(ivstaudioprocessor.SymbolicSampleSizes.kSample32),
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
