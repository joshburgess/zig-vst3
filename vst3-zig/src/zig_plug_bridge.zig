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
            if (!self.values.storeById(self.set, id, value)) return types.kInvalidArgument;
            return types.kResultOk;
        }

        pub fn applyChanges(self: *Self, changes: plug.process.ParameterChanges) void {
            self.values.applyChanges(self.set, changes);
        }

        pub fn readFromStream(self: *Self, stream: ?*ibstream.IBStream) types.tresult {
            var restored = Values.init(self.set);
            const result = readParameterState(Params, stream, self.set, &restored);
            if (result != types.kResultOk) return result;
            copyParameterValues(Params, &restored, &self.values);
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
        .unitId = 0,
        .flags = parameterInfoFlags(Params, set, parameter_index),
    };
    copyAscii16(&out.title, set.name(parameter_index).?);
    copyAscii16(&out.shortTitle, set.name(parameter_index).?);
    return types.kResultOk;
}

fn parameterInfoFlags(
    comptime Params: type,
    set: *const plug.parameters.ParameterSet(Params),
    index: usize,
) types.int32 {
    var flags = ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate;
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

pub fn copyParameterValues(
    comptime Params: type,
    source: *const plug.parameters.ParameterValues(Params),
    dest: *plug.parameters.ParameterValues(Params),
) void {
    inline for (0..plug.parameters.ParameterSet(Params).count) |index| {
        if (source.load(index)) |value| {
            _ = dest.store(index, value);
        }
    }
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

    return .{
        .sample_rate = if (data.processContext) |context| context.sampleRate else 0,
        .inputs = try plug.process.AudioInputs(Sample).init(input_channels[0..channel_count]),
        .outputs = try plug.process.AudioOutputs(Sample).init(output_channels[0..channel_count]),
        .parameter_changes = parameter_changes,
        .events = events,
        .output_events = output_events,
    };
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
    const len = @min(source.len, 127);
    for (source[0..len], 0..) |char, index| {
        dest[index] = char;
    }
    dest[len] = 0;
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
    collector.storage[collector.count] = switch (@as(ivstevents.Event.EventTypes, @enumFromInt(event.type))) {
        .kNoteOnEvent => .{
            .kind = .note_on,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = event.data.noteOn.channel,
            .pitch = event.data.noteOn.pitch,
            .velocity = event.data.noteOn.velocity,
        },
        .kNoteOffEvent => .{
            .kind = .note_off,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = event.data.noteOff.channel,
            .pitch = event.data.noteOff.pitch,
            .velocity = event.data.noteOff.velocity,
        },
        .kDataEvent => .{
            .kind = .data,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .data_type = event.data.data.type,
            .data = dataEventBytes(event.data.data),
        },
        .kLegacyMIDICCOutEvent => collectLegacyMidiCcEvent(event, offset),
        .kPolyPressureEvent => .{
            .kind = .aftertouch,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = event.data.polyPressure.channel,
            .pitch = event.data.polyPressure.pitch,
            .value = event.data.polyPressure.pressure,
        },
        .kNoteExpressionValueEvent => .{
            .kind = .note_expression_value,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .note_id = event.data.noteExpressionValue.noteId,
            .expression_type_id = event.data.noteExpressionValue.typeId,
            .value = @floatCast(event.data.noteExpressionValue.value),
        },
        .kNoteExpressionIntValueEvent => .{
            .kind = .note_expression_int,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .note_id = event.data.noteExpressionIntValue.noteId,
            .expression_type_id = event.data.noteExpressionIntValue.typeId,
            .int_value = event.data.noteExpressionIntValue.value,
        },
        .kNoteExpressionTextEvent => .{
            .kind = .note_expression_text,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .note_id = event.data.noteExpressionText.noteId,
            .expression_type_id = event.data.noteExpressionText.typeId,
        },
        else => .{
            .kind = .other,
            .bus_index = event.busIndex,
            .sample_offset = offset,
        },
    };
    collector.count += 1;
}

fn collectLegacyMidiCcEvent(event: *const ivstevents.Event, offset: usize) plug.process.Event {
    const midi = &event.data.midiCCOut;
    const control_number: i16 = @intCast(midi.controlNumber);
    const value = events_helper.getMIDINormValue(@intCast(@max(midi.value, 0)));
    return switch (midi.controlNumber) {
        ivstmidicontrollers.kPitchBend => .{
            .kind = .pitch_bend,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = midi.channel,
            .control_number = control_number,
            .value = @floatCast(events_helper.getNormPitchBendValue(midi)),
        },
        ivstmidicontrollers.kAfterTouch => .{
            .kind = .aftertouch,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = midi.channel,
            .control_number = control_number,
            .value = @floatCast(value),
        },
        else => .{
            .kind = .midi_cc,
            .bus_index = event.busIndex,
            .sample_offset = offset,
            .channel = midi.channel,
            .control_number = control_number,
            .value = @floatCast(value),
        },
    };
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
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent);
            result.data = .{ .noteOn = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .velocity = event.velocity,
            } };
        },
        .note_off => {
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kNoteOffEvent);
            result.data = .{ .noteOff = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .velocity = event.velocity,
            } };
        },
        .midi_cc, .pitch_bend => {
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent);
            result.data = .{ .midiCCOut = .{
                .controlNumber = @intCast(event.control_number),
                .channel = @intCast(event.channel),
                .value = events_helper.getMIDICCOutValue(event.value),
            } };
            if (event.kind == .pitch_bend) {
                result.data.midiCCOut.controlNumber = ivstmidicontrollers.kPitchBend;
                events_helper.setPitchBendValue(&result.data.midiCCOut, event.value);
            }
        },
        .aftertouch => {
            result.type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent);
            result.data = .{ .polyPressure = .{
                .channel = event.channel,
                .pitch = event.pitch,
                .pressure = event.value,
                .noteId = event.note_id,
            } };
        },
        .note_expression_value => {
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
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{};

    try std.testing.expect(values.store(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, stream.asStream(), &set, &values));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(Params, stream.asStream(), &set, &restored));
    try std.testing.expectEqual(@as(?f64, 0.25), restored.load(0));
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

    try std.testing.expect(old_values.store(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(OldParams, stream.asStream(), &old_set, &old_values));
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(NewParams, stream.asStream(), &new_set, &new_values));

    try std.testing.expectEqual(@as(?f64, 0.25), new_values.load(0));
    try std.testing.expectEqual(@as(?f64, 0.5), new_values.load(1));
}

test "zig-plug bridge rejects truncated IBStream state" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{};

    try std.testing.expect(values.store(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, stream.asStream(), &set, &values));
    stream.len -= 1;
    try std.testing.expectEqual(types.kResultOk, stream.asStream().vtable.seek(stream.asStream(), 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultFalse, readParameterState(Params, stream.asStream(), &set, &values));
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

test "zig-plug bridge copies reflected parameter values" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: plug.parameters.FloatParam = plug.parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var source = Values.init(&set);
    var dest = Values.init(&set);

    try std.testing.expect(source.storeById(&set, 0, 0.25));
    try std.testing.expect(source.storeById(&set, 1, 0.75));

    copyParameterValues(Params, &source, &dest);

    try std.testing.expectEqual(@as(?f64, 0.25), dest.loadById(&set, 0));
    try std.testing.expectEqual(@as(?f64, 0.75), dest.loadById(&set, 1));
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
    const Stream = vst_stream.FixedBufferStream(256);
    var stream = Stream{};

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

    try std.testing.expectEqual(@as(usize, 3), collected.items.len);
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

    try std.testing.expectEqual(@as(usize, 2), collected.items.len);
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
    var list = TestEventList.init(&items, null);
    var storage: [4]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = &list.iface,
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.items.len);
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
            .busIndex = 1,
            .sampleOffset = 2,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kPolyPressureEvent),
            .data = .{ .polyPressure = .{ .channel = 1, .pitch = 64, .pressure = 0.5 } },
        },
        .{
            .busIndex = 0,
            .sampleOffset = 3,
            .type = @intFromEnum(ivstevents.Event.EventTypes.kDataEvent),
            .data = .{ .data = .{} },
        },
    };
    var list = TestEventList.init(&items, null);
    var storage: [2]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = &list.iface,
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 2), collected.items.len);
    try std.testing.expectEqual(plug.process.EventKind.note_on, collected.items[0].kind);
    try std.testing.expectEqual(@as(usize, 0), collected.items[0].sample_offset);
    try std.testing.expectEqual(plug.process.EventKind.aftertouch, collected.items[1].kind);
    try std.testing.expectEqual(@as(i32, 1), collected.items[1].bus_index);
    try std.testing.expectEqual(@as(usize, 2), collected.items[1].sample_offset);
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
    var list = TestEventList.init(&items, null);
    var storage: [3]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 3,
        .inputEvents = &list.iface,
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 3), collected.items.len);
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
    var list = TestEventList.init(&items, null);
    var storage: [4]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .inputEvents = &list.iface,
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 4), collected.items.len);
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
    var list = TestEventList.init(&items, null);
    var storage: [1]plug.process.Event = undefined;
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 1,
        .inputEvents = &list.iface,
    };

    const collected = collectInputEvents(&data, &storage);

    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
    try std.testing.expectEqual(plug.process.EventKind.data, collected.items[0].kind);
    try std.testing.expectEqual(@as(u32, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx)), collected.items[0].data_type);
    try std.testing.expectEqualSlices(u8, &payload, collected.items[0].data);
}

test "zig-plug bridge writes output events to VST3 event lists" {
    const payload = [_]u8{ 0xF0, 0x7D, 0x02, 0xF7 };
    const items = [_]plug.process.Event{
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 1, .pitch = 60, .velocity = 0.75 },
        .{ .kind = .midi_cc, .bus_index = 0, .sample_offset = 1, .channel = 1, .control_number = ivstmidicontrollers.kCtrlModWheel, .value = 0.5 },
        .{ .kind = .pitch_bend, .bus_index = 0, .sample_offset = 2, .channel = 1, .value = 1.0 },
        .{ .kind = .note_expression_value, .bus_index = 0, .sample_offset = 3, .note_id = 42, .expression_type_id = 5, .value = 0.25 },
        .{ .kind = .data, .bus_index = 0, .sample_offset = 3, .data_type = @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx), .data = &payload },
        .{ .kind = .other, .bus_index = 0, .sample_offset = 3 },
    };
    var storage: [5]ivstevents.Event = undefined;
    var list = TestWritableEventList.init(&storage, null);
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 4,
        .outputEvents = &list.iface,
    };

    try std.testing.expectEqual(types.kResultOk, writeOutputEvents(&data, .{ .items = &items }));

    try std.testing.expectEqual(@as(usize, 5), list.count);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteOnEvent), storage[0].type);
    try std.testing.expectEqual(@as(i16, 60), storage[0].data.noteOn.pitch);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), storage[1].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kCtrlModWheel), storage[1].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kLegacyMIDICCOutEvent), storage[2].type);
    try std.testing.expectEqual(@as(u8, ivstmidicontrollers.kPitchBend), storage[2].data.midiCCOut.controlNumber);
    try std.testing.expectEqual(@as(types.int16, 0x3FFF), events_helper.getPitchBendValue(&storage[2].data.midiCCOut));
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kNoteExpressionValueEvent), storage[3].type);
    try std.testing.expectEqual(@as(u32, 5), storage[3].data.noteExpressionValue.typeId);
    try std.testing.expectEqual(@intFromEnum(ivstevents.Event.EventTypes.kDataEvent), storage[4].type);
    try std.testing.expectEqual(@as(u32, payload.len), storage[4].data.data.size);
    try std.testing.expectEqual(@as(u32, @intFromEnum(ivstevents.DataEvent.DataTypes.kMidiSysEx)), storage[4].data.data.type);
    try std.testing.expectEqualSlices(u8, &payload, storage[4].data.data.bytes.?[0..payload.len]);
}

test "zig-plug bridge reports output event write failures" {
    const items = [_]plug.process.Event{
        .{ .kind = .note_on, .bus_index = 0, .sample_offset = 0, .channel = 0, .pitch = 60, .velocity = 0.75 },
    };
    var storage: [1]ivstevents.Event = undefined;
    var list = TestWritableEventList.init(&storage, 0);
    var data = ivstaudioprocessor.ProcessData{
        .numSamples = 1,
        .outputEvents = &list.iface,
    };

    try std.testing.expectEqual(types.kResultFalse, writeOutputEvents(&data, .{ .items = &items }));
}

test "zig-plug bridge parameter controller exposes reflected edit operations" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
        bypass: plug.parameters.BoolParam = .{ .id = 8, .name = "Bypass" },
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var state = ParameterState(Params).init(&set);
    var controller = ParameterController(Params){
        .set = &set,
        .state = &state,
    };
    var info = ivsteditcontroller.ParameterInfo{};
    var text: vsttypes.String128 = undefined;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(@as(types.int32, 2), controller.parameterCount());
    try std.testing.expectEqual(types.kResultOk, controller.parameterInfo(0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try expectString128("Gain", &info.title);

    try std.testing.expectEqual(types.kResultOk, controller.stringByValue(7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(types.kResultOk, controller.valueByString(7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), controller.plainFromNormalized(7, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), controller.normalizedFromPlain(7, 1.0));

    try std.testing.expectEqual(types.kResultOk, controller.setNormalized(8, 1.0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 1.0), controller.getNormalized(8));
    try std.testing.expectEqual(types.kInvalidArgument, controller.setNormalized(99, 0.5));

    const changes = [_]plug.process.ParameterChange{
        .{ .id = 7, .sample_offset = 0, .normalized = 0.25 },
        .{ .id = 8, .sample_offset = 1, .normalized = 0.0 },
    };
    controller.applyChanges(try plug.process.ParameterChanges.init(&changes, 2));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), controller.getNormalized(7));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.0), controller.getNormalized(8));
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
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
        bypass: plug.parameters.BoolParam = .{ .id = 8, .name = "Bypass", .is_bypass = true },
        voices: plug.parameters.IntParam = plug.parameters.IntParam.init(9, "Voices", 1, 4, 1),
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
    try std.testing.expectEqual(ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate, info.flags);
    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 1, &info));
    try std.testing.expectEqual(@as(types.int32, 1), info.stepCount);
    try std.testing.expect((info.flags & ivsteditcontroller.ParameterInfo.ParameterFlags.kIsBypass) != 0);
    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 2, &info));
    try std.testing.expectEqual(@as(types.int32, 3), info.stepCount);
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
    var text: vsttypes.String128 = undefined;
    var value: vsttypes.ParamValue = 0;

    try std.testing.expectEqual(types.kResultOk, getParamStringByValue(Params, &set, 7, 0.5, &text));
    try expectString128("1.000", &text);
    try std.testing.expectEqual(types.kResultOk, getParamValueByString(Params, &set, 7, &text, &value));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), value);
    try std.testing.expectEqual(types.kInvalidArgument, getParamStringByValue(Params, &set, 8, 0.5, &text));
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
    try std.testing.expectEqual(@as(f32, 3.0), context.inputs.channel(1).?[0]);
    context.outputs.channel(0).?[1] = 9.0;
    try std.testing.expectEqual(@as(f32, 9.0), out_left[1]);
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
    try std.testing.expectEqual(@as(f32, 4.0), context.inputs.channel(1).?[1]);
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
            for (0..context.outputs.channels.len) |channel| {
                const input = context.inputs.channel(channel) orelse continue;
                const output = context.outputs.channel(channel) orelse continue;
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
            const writer = context.output_events orelse return;
            writer.append(.{
                .kind = .note_on,
                .bus_index = 0,
                .sample_offset = 1,
                .channel = 0,
                .pitch = 60,
                .velocity = 0.75,
            }) catch {};
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
    try std.testing.expectEqual(@as(usize, 1), writer.events().items.len);
    try std.testing.expectEqual(plug.process.EventKind.note_on, writer.events().items[0].kind);
    try std.testing.expectEqual(@as(usize, 1), writer.events().items[0].sample_offset);
}

fn expectString128(expected: []const u8, actual: *const vsttypes.String128) !void {
    for (expected, 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, char), actual[index]);
    }
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), actual[expected.len]);
}

const TestEventList = struct {
    iface: ivstevents.IEventList = .{ .vtable = &vtable },
    items: []const ivstevents.Event,
    fail_index: ?types.int32 = null,

    const vtable = ivstevents.IEventListVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .getEventCount = getEventCount,
        .getEvent = getEvent,
        .addEvent = addEvent,
    };

    fn init(items: []const ivstevents.Event, fail_index: ?types.int32) TestEventList {
        return .{ .items = items, .fail_index = fail_index };
    }

    fn owner(ptr: *anyopaque) *TestEventList {
        const iface: *ivstevents.IEventList = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("tuid.zig").TUID, out: *?*anyopaque) callconv(.C) types.tresult {
        out.* = null;
        return types.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn getEventCount(ptr: *anyopaque) callconv(.C) types.int32 {
        return @intCast(owner(ptr).items.len);
    }

    fn getEvent(ptr: *anyopaque, index: types.int32, event: *ivstevents.Event) callconv(.C) types.tresult {
        if (index < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        if (self.fail_index != null and index == self.fail_index.?) return types.kResultFalse;
        const event_index: usize = @intCast(index);
        if (event_index >= self.items.len) return types.kInvalidArgument;
        event.* = self.items[event_index];
        return types.kResultOk;
    }

    fn addEvent(_: *anyopaque, _: *ivstevents.Event) callconv(.C) types.tresult {
        return types.kResultFalse;
    }
};

const TestWritableEventList = struct {
    iface: ivstevents.IEventList = .{ .vtable = &vtable },
    storage: []ivstevents.Event,
    count: usize = 0,
    fail_index: ?usize = null,

    const vtable = ivstevents.IEventListVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .getEventCount = getEventCount,
        .getEvent = getEvent,
        .addEvent = addEvent,
    };

    fn init(storage: []ivstevents.Event, fail_index: ?usize) TestWritableEventList {
        return .{ .storage = storage, .fail_index = fail_index };
    }

    fn owner(ptr: *anyopaque) *TestWritableEventList {
        const iface: *ivstevents.IEventList = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("tuid.zig").TUID, out: *?*anyopaque) callconv(.C) types.tresult {
        out.* = null;
        return types.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.C) types.uint32 {
        return 1;
    }

    fn getEventCount(ptr: *anyopaque) callconv(.C) types.int32 {
        return @intCast(owner(ptr).count);
    }

    fn getEvent(ptr: *anyopaque, index: types.int32, event: *ivstevents.Event) callconv(.C) types.tresult {
        if (index < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const event_index: usize = @intCast(index);
        if (event_index >= self.count) return types.kInvalidArgument;
        event.* = self.storage[event_index];
        return types.kResultOk;
    }

    fn addEvent(ptr: *anyopaque, event: *ivstevents.Event) callconv(.C) types.tresult {
        const self = owner(ptr);
        if (self.fail_index != null and self.count == self.fail_index.?) return types.kResultFalse;
        if (self.count >= self.storage.len) return types.kResultFalse;
        self.storage[self.count] = event.*;
        self.count += 1;
        return types.kResultOk;
    }
};
