const std = @import("std");
const ibstream = @import("pluginterfaces/base/ibstream.zig");
const ivstaudioprocessor = @import("pluginterfaces/vst/ivstaudioprocessor.zig");
const ivstcomponent = @import("pluginterfaces/vst/ivstcomponent.zig");
const ivsteditcontroller = @import("pluginterfaces/vst/ivsteditcontroller.zig");
const types = @import("pluginterfaces/base/types.zig");
const plug = @import("zig-plug-core");
const audio_processor_algo = @import("pluginterfaces/vst/vstaudioprocessoralgo.zig");
const vsttypes = @import("pluginterfaces/vst/vsttypes.zig");

const max_audio_channels = 64;
const empty_arrangement: vsttypes.SpeakerArrangement = 0;
const stereo_arrangement: vsttypes.SpeakerArrangement = 3;

pub const StereoAudioBuses = struct {
    pub fn busCount(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection) types.int32 {
        if (media_type == @intFromEnum(ivstcomponent.MediaTypes.kAudio) and isInputOrOutput(direction)) {
            return 1;
        }
        return 0;
    }

    pub fn busInfo(media_type: vsttypes.MediaType, direction: vsttypes.BusDirection, index: types.int32, out: *ivstcomponent.BusInfo) types.tresult {
        if (media_type != @intFromEnum(ivstcomponent.MediaTypes.kAudio) or index != 0 or !isInputOrOutput(direction)) {
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
        copyAscii16(&out.name, if (direction == @intFromEnum(ivstcomponent.BusDirections.kInput)) "Stereo In" else "Stereo Out");
        return types.kResultOk;
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
        .defaultNormalizedValue = set.defaultNormalized(parameter_index).?,
        .unitId = 0,
        .flags = ivsteditcontroller.ParameterInfo.ParameterFlags.kCanAutomate,
    };
    copyAscii16(&out.title, set.name(parameter_index).?);
    copyAscii16(&out.shortTitle, set.name(parameter_index).?);
    return types.kResultOk;
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
    };
}

pub fn makeMainAudioProcessContext(
    comptime Sample: type,
    data: *const ivstaudioprocessor.ProcessData,
    parameter_changes: plug.process.ParameterChanges,
) !plug.process.ProcessContext(Sample) {
    if (data.numInputs <= 0 or data.numOutputs <= 0 or data.inputs == null or data.outputs == null) {
        return error.MissingMainAudioBus;
    }
    const input = data.inputs.?[0];
    const output = data.outputs.?[0];
    if (input.numChannels <= 0 or output.numChannels <= 0) {
        return error.MissingMainAudioChannels;
    }
    return makeProcessContext(Sample, input, output, data, parameter_changes);
}

pub fn readParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *plug.parameters.ParameterValues(Params),
) types.tresult {
    const input = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var read: types.int32 = 0;
    const result = input.vtable.read(input, &bytes, bytes.len, &read);
    if (result != types.kResultOk or read != bytes.len) return types.kResultFalse;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.readParameterState(Params, set, values, state_stream.reader()) catch return types.kResultFalse;
    return types.kResultOk;
}

pub fn writeParameterState(
    comptime Params: type,
    stream: ?*ibstream.IBStream,
    set: *const plug.parameters.ParameterSet(Params),
    values: *const plug.parameters.ParameterValues(Params),
) types.tresult {
    const output = stream orelse return types.kInvalidArgument;
    var bytes: [plug.state.encodedSize(Params)]u8 = undefined;
    var state_stream = std.io.fixedBufferStream(&bytes);
    plug.state.writeParameterState(Params, set, values, state_stream.writer()) catch return types.kResultFalse;
    var written: types.int32 = 0;
    const result = output.vtable.write(output, &bytes, bytes.len, &written);
    if (result != types.kResultOk or written != bytes.len) return types.kResultFalse;
    return types.kResultOk;
}

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

fn collectParameterQueue(collector: *ParameterChangeCollector, queue: *@import("pluginterfaces/vst/ivstparameterchanges.zig").IParamValueQueue) void {
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

test "zig-plug bridge round-trips parameter state through IBStream" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const Values = plug.parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var restored = Values.init(&set);
    var stream = MemoryStream{};

    try std.testing.expect(values.store(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, writeParameterState(Params, &stream.iface, &set, &values));
    try std.testing.expectEqual(types.kResultOk, stream.iface.vtable.seek(&stream.iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, readParameterState(Params, &stream.iface, &set, &restored));
    try std.testing.expectEqual(@as(?f64, 0.25), restored.load(0));
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
    var stream = MemoryStream{};

    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(0, 0.25));
    try std.testing.expectEqual(types.kResultOk, source.setNormalizedById(1, 0.75));
    try std.testing.expectEqual(types.kInvalidArgument, source.setNormalizedById(99, 0.5));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), source.getNormalizedById(0));

    try std.testing.expectEqual(types.kResultOk, source.writeToStream(&stream.iface));
    try std.testing.expectEqual(types.kResultOk, stream.iface.vtable.seek(&stream.iface, 0, @intFromEnum(ibstream.IStreamSeekMode.kIBSeekSet), null));
    try std.testing.expectEqual(types.kResultOk, restored.readFromStream(&stream.iface));

    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.25), restored.getNormalizedById(0));
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), restored.getNormalizedById(1));
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
}

test "zig-plug bridge stereo audio buses expose one input and output" {
    var info = ivstcomponent.BusInfo{};

    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput)));
    try std.testing.expectEqual(@as(types.int32, 1), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kOutput)));
    try std.testing.expectEqual(@as(types.int32, 0), StereoAudioBuses.busCount(@intFromEnum(ivstcomponent.MediaTypes.kEvent), @intFromEnum(ivstcomponent.BusDirections.kInput)));

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.busInfo(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 0, &info));
    try std.testing.expectEqual(@as(types.int32, 2), info.channelCount);
    try std.testing.expectEqual(ivstcomponent.BusFlags.kDefaultActive, info.flags);
    try expectString128("Stereo In", &info.name);

    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.busInfo(@intFromEnum(ivstcomponent.MediaTypes.kAudio), @intFromEnum(ivstcomponent.BusDirections.kInput), 1, &info));
}

test "zig-plug bridge stereo audio buses validate arrangements" {
    var inputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var outputs = [_]vsttypes.SpeakerArrangement{stereo_arrangement};
    var arrangement_out: vsttypes.SpeakerArrangement = empty_arrangement;

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.setArrangements(&inputs, 1, &outputs, 1));
    inputs[0] = empty_arrangement;
    try std.testing.expectEqual(types.kResultFalse, StereoAudioBuses.setArrangements(&inputs, 1, &outputs, 1));

    try std.testing.expectEqual(types.kResultOk, StereoAudioBuses.arrangement(@intFromEnum(ivstcomponent.BusDirections.kOutput), 0, &arrangement_out));
    try std.testing.expectEqual(stereo_arrangement, arrangement_out);
    try std.testing.expectEqual(types.kInvalidArgument, StereoAudioBuses.arrangement(@intFromEnum(ivstcomponent.BusDirections.kOutput), 1, &arrangement_out));
    try std.testing.expectEqual(empty_arrangement, arrangement_out);
}

test "zig-plug bridge fills VST3 parameter info from reflected set" {
    const Params = struct {
        gain: plug.parameters.FloatParam = plug.parameters.FloatParam.init(7, "Gain", 0.0, 2.0, 1.0),
    };
    const Set = plug.parameters.ParameterSet(Params);
    const set = Set.init(.{});
    var info = ivsteditcontroller.ParameterInfo{};

    try std.testing.expectEqual(types.kResultOk, fillParameterInfo(Params, &set, 0, &info));
    try std.testing.expectEqual(@as(vsttypes.ParamID, 7), info.id);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.5), info.defaultNormalizedValue);
    try expectString128("Gain", &info.title);
    try std.testing.expectEqual(types.kInvalidArgument, fillParameterInfo(Params, &set, 1, &info));
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

    const context = try makeProcessContext(f32, input, output, &data, .{});

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

    const context = try makeMainAudioProcessContext(f32, &data, .{});

    try std.testing.expectEqual(@as(usize, 2), context.frameCount());
    try std.testing.expectEqual(@as(f32, 4.0), context.inputs.channel(1).?[1]);
}

test "zig-plug bridge rejects missing main process buses" {
    const data = ivstaudioprocessor.ProcessData{
        .numInputs = 0,
        .numOutputs = 1,
        .numSamples = 2,
    };

    try std.testing.expectError(error.MissingMainAudioBus, makeMainAudioProcessContext(f32, &data, .{}));
}

fn expectString128(expected: []const u8, actual: *const vsttypes.String128) !void {
    for (expected, 0..) |char, index| {
        try std.testing.expectEqual(@as(vsttypes.TChar, char), actual[index]);
    }
    try std.testing.expectEqual(@as(vsttypes.TChar, 0), actual[expected.len]);
}

const MemoryStream = extern struct {
    iface: ibstream.IBStream = .{ .vtable = &vtable },
    bytes: [256]u8 = undefined,
    len: usize = 0,
    pos: usize = 0,

    const vtable = ibstream.IBStreamVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .read = read,
        .write = write,
        .seek = seek,
        .tell = tell,
    };

    fn owner(ptr: *anyopaque) *MemoryStream {
        const iface: *ibstream.IBStream = @ptrCast(@alignCast(ptr));
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

    fn read(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_read: ?*types.int32) callconv(.C) types.tresult {
        if (buffer == null or byte_count < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const requested: usize = @intCast(byte_count);
        if (self.pos + requested > self.len) return types.kResultFalse;
        const output = @as([*]u8, @ptrCast(buffer.?))[0..requested];
        @memcpy(output, self.bytes[self.pos..][0..requested]);
        self.pos += requested;
        if (bytes_read) |read_count| read_count.* = @intCast(requested);
        return types.kResultOk;
    }

    fn write(ptr: *anyopaque, buffer: ?*anyopaque, byte_count: types.int32, bytes_written: ?*types.int32) callconv(.C) types.tresult {
        if (buffer == null or byte_count < 0) return types.kInvalidArgument;
        const self = owner(ptr);
        const requested: usize = @intCast(byte_count);
        if (self.pos + requested > self.bytes.len) return types.kResultFalse;
        const input = @as([*]const u8, @ptrCast(buffer.?))[0..requested];
        @memcpy(self.bytes[self.pos..][0..requested], input);
        self.pos += requested;
        self.len = @max(self.len, self.pos);
        if (bytes_written) |write_count| write_count.* = @intCast(requested);
        return types.kResultOk;
    }

    fn seek(ptr: *anyopaque, pos: types.int64, mode: types.int32, result: ?*types.int64) callconv(.C) types.tresult {
        const self = owner(ptr);
        const next = switch (@as(ibstream.IStreamSeekMode, @enumFromInt(mode))) {
            .kIBSeekSet => pos,
            .kIBSeekCur => @as(types.int64, @intCast(self.pos)) + pos,
            .kIBSeekEnd => @as(types.int64, @intCast(self.len)) + pos,
        };
        if (next < 0 or next > self.len) return types.kResultFalse;
        self.pos = @intCast(next);
        if (result) |out| out.* = next;
        return types.kResultOk;
    }

    fn tell(ptr: *anyopaque, pos: *types.int64) callconv(.C) types.tresult {
        pos.* = @intCast(owner(ptr).pos);
        return types.kResultOk;
    }
};
