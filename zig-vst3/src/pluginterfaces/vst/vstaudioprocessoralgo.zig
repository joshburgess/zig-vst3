const std = @import("std");
const base = @import("../base/types.zig");
const audio_processor = @import("ivstaudioprocessor.zig");
const events = @import("ivstevents.zig");
const parameter_changes = @import("ivstparameterchanges.zig");
const vsttypes = @import("vsttypes.zig");

pub const max_supported_channels: base.int32 = 64;

pub fn getChannelBuffersPointer(
    process_setup: *const audio_processor.ProcessSetup,
    buffers: *const audio_processor.AudioBusBuffers,
) ?*anyopaque {
    if (process_setup.symbolicSampleSize == @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32)) {
        return @ptrCast(buffers.channelBuffers.channelBuffers32);
    }
    return @ptrCast(buffers.channelBuffers.channelBuffers64);
}

fn sampleSizeInBytes(process_setup: *const audio_processor.ProcessSetup) base.uint32 {
    return if (process_setup.symbolicSampleSize == @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32))
        @intCast(@sizeOf(vsttypes.Sample32))
    else
        @intCast(@sizeOf(vsttypes.Sample64));
}

pub fn getSampleFramesSizeInBytes(
    process_setup: *const audio_processor.ProcessSetup,
    num_samples: base.int32,
) base.uint32 {
    if (num_samples <= 0) return 0;
    const sample_size = sampleSizeInBytes(process_setup);
    const max_samples = std.math.maxInt(base.uint32) / sample_size;
    const safe_samples: base.uint32 = @min(@as(base.uint32, @intCast(num_samples)), max_samples);
    return safe_samples * sample_size;
}

pub fn getChannelMask(num_channels: base.int32) base.uint64 {
    if (num_channels >= max_supported_channels) return @as(base.uint64, 0xFFFFFFFFFFFFFFFF);
    if (num_channels <= 0) return 0;
    return (@as(base.uint64, 1) << @intCast(num_channels)) - 1;
}

fn sampleRangeEnd(sample_count: base.int32, start_index: base.int32) ?base.int32 {
    if (sample_count <= 0 or start_index < 0) return null;
    const end = @addWithOverflow(start_index, sample_count);
    return if (end[1] == 0) end[0] else null;
}

fn channelCount(count: base.int32) base.int32 {
    if (count <= 0) return 0;
    return @min(count, max_supported_channels);
}

fn pairedChannelCount(first: base.int32, second: base.int32) base.int32 {
    return @min(channelCount(first), channelCount(second));
}

fn copySamples(
    comptime Sample: type,
    src_channels: [*][*]Sample,
    dest_channels: [*][*]Sample,
    num_channels: base.int32,
    slice_size: base.int32,
    start_index: base.int32,
) void {
    var channel: base.int32 = 0;
    while (channel < num_channels) : (channel += 1) {
        const src_channel = src_channels[@intCast(channel)];
        const dest_channel = dest_channels[@intCast(channel)];
        var sample: base.int32 = 0;
        while (sample < slice_size) : (sample += 1) {
            dest_channel[@intCast(start_index + sample)] = src_channel[@intCast(sample)];
        }
    }
}

fn clearSamples(comptime Sample: type, channels: [*][*]Sample, num_channels: base.int32, sample_count: base.int32) void {
    var channel: base.int32 = 0;
    while (channel < num_channels) : (channel += 1) {
        const channel_buffer = channels[@intCast(channel)];
        var sample: base.int32 = 0;
        while (sample < sample_count) : (sample += 1) {
            channel_buffer[@intCast(sample)] = 0;
        }
    }
}

fn mixSamples(comptime Sample: type, src_channels: [*][*]Sample, dest_channels: [*][*]Sample, num_channels: base.int32, sample_count: base.int32) void {
    var channel: base.int32 = 0;
    while (channel < num_channels) : (channel += 1) {
        const src_channel = src_channels[@intCast(channel)];
        const dest_channel = dest_channels[@intCast(channel)];
        var sample: base.int32 = 0;
        while (sample < sample_count) : (sample += 1) {
            dest_channel[@intCast(sample)] += src_channel[@intCast(sample)];
        }
    }
}

fn multiplySamples(comptime Sample: type, src_channels: [*][*]Sample, dest_channels: [*][*]Sample, num_channels: base.int32, sample_count: base.int32, factor: Sample) void {
    var channel: base.int32 = 0;
    while (channel < num_channels) : (channel += 1) {
        const src_channel = src_channels[@intCast(channel)];
        const dest_channel = dest_channels[@intCast(channel)];
        var sample: base.int32 = 0;
        while (sample < sample_count) : (sample += 1) {
            dest_channel[@intCast(sample)] = src_channel[@intCast(sample)] * factor;
        }
    }
}

fn isSilentSamples(comptime Sample: type, channels: [*][*]Sample, num_channels: base.int32, start_index: base.int32, end: base.int32) bool {
    var channel: base.int32 = 0;
    while (channel < num_channels) : (channel += 1) {
        const channel_buffer = channels[@intCast(channel)];
        var sample = start_index;
        while (sample < end) : (sample += 1) {
            if (@abs(channel_buffer[@intCast(sample)]) > 1e-10) return false;
        }
    }
    return true;
}

pub fn copy32(
    src: ?*audio_processor.AudioBusBuffers,
    dest: ?*audio_processor.AudioBusBuffers,
    slice_size: base.int32,
    start_index: base.int32,
) void {
    _ = sampleRangeEnd(slice_size, start_index) orelse return;
    const src_buffer = src orelse return;
    const dest_buffer = dest orelse return;
    const src_channels = src_buffer.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest_buffer.channelBuffers.channelBuffers32 orelse return;
    const num_channels = pairedChannelCount(src_buffer.numChannels, dest_buffer.numChannels);
    copySamples(vsttypes.Sample32, src_channels, dest_channels, num_channels, slice_size, start_index);
}

pub fn copy64(
    src: ?*audio_processor.AudioBusBuffers,
    dest: ?*audio_processor.AudioBusBuffers,
    slice_size: base.int32,
    start_index: base.int32,
) void {
    _ = sampleRangeEnd(slice_size, start_index) orelse return;
    const src_buffer = src orelse return;
    const dest_buffer = dest orelse return;
    const src_channels = src_buffer.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest_buffer.channelBuffers.channelBuffers64 orelse return;
    const num_channels = pairedChannelCount(src_buffer.numChannels, dest_buffer.numChannels);
    copySamples(vsttypes.Sample64, src_channels, dest_channels, num_channels, slice_size, start_index);
}

pub fn clear32(audio_bus_buffers: ?[*]audio_processor.AudioBusBuffers, sample_count: base.int32, bus_count: base.int32) void {
    if (sample_count <= 0 or bus_count <= 0) return;
    const buses = audio_bus_buffers orelse return;
    var bus: base.int32 = 0;
    while (bus < bus_count) : (bus += 1) {
        const audio_buffer = &buses[@intCast(bus)];
        const channels = audio_buffer.channelBuffers.channelBuffers32 orelse continue;
        const num_channels = channelCount(audio_buffer.numChannels);
        clearSamples(vsttypes.Sample32, channels, num_channels, sample_count);
    }
}

pub fn clear64(audio_bus_buffers: ?[*]audio_processor.AudioBusBuffers, sample_count: base.int32, bus_count: base.int32) void {
    if (sample_count <= 0 or bus_count <= 0) return;
    const buses = audio_bus_buffers orelse return;
    var bus: base.int32 = 0;
    while (bus < bus_count) : (bus += 1) {
        const audio_buffer = &buses[@intCast(bus)];
        const channels = audio_buffer.channelBuffers.channelBuffers64 orelse continue;
        const num_channels = channelCount(audio_buffer.numChannels);
        clearSamples(vsttypes.Sample64, channels, num_channels, sample_count);
    }
}

pub fn mix32(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers32 orelse return;
    const num_channels = pairedChannelCount(src.numChannels, dest.numChannels);
    mixSamples(vsttypes.Sample32, src_channels, dest_channels, num_channels, sample_count);
}

pub fn mix64(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers64 orelse return;
    const num_channels = pairedChannelCount(src.numChannels, dest.numChannels);
    mixSamples(vsttypes.Sample64, src_channels, dest_channels, num_channels, sample_count);
}

pub fn multiply32(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32, factor: f32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers32 orelse return;
    const num_channels = pairedChannelCount(src.numChannels, dest.numChannels);
    multiplySamples(vsttypes.Sample32, src_channels, dest_channels, num_channels, sample_count, factor);
}

pub fn multiply64(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32, factor: f64) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers64 orelse return;
    const num_channels = pairedChannelCount(src.numChannels, dest.numChannels);
    multiplySamples(vsttypes.Sample64, src_channels, dest_channels, num_channels, sample_count, factor);
}

pub fn isSilent32(audio_buffer: *audio_processor.AudioBusBuffers, sample_count: base.int32, start_index: base.int32) bool {
    const end = sampleRangeEnd(sample_count, start_index) orelse return true;
    const channels = audio_buffer.channelBuffers.channelBuffers32 orelse return true;
    const num_channels = channelCount(audio_buffer.numChannels);
    return isSilentSamples(vsttypes.Sample32, channels, num_channels, start_index, end);
}

pub fn isSilent64(audio_buffer: *audio_processor.AudioBusBuffers, sample_count: base.int32, start_index: base.int32) bool {
    const end = sampleRangeEnd(sample_count, start_index) orelse return true;
    const channels = audio_buffer.channelBuffers.channelBuffers64 orelse return true;
    const num_channels = channelCount(audio_buffer.numChannels);
    return isSilentSamples(vsttypes.Sample64, channels, num_channels, start_index, end);
}

pub fn forEachEvent(event_list: ?*events.IEventList, context: anytype, comptime callback: anytype) void {
    forEachEventUntil(event_list, context, struct {
        fn next(inner_context: @TypeOf(context), event: *const events.Event) bool {
            callback(inner_context, event);
            return true;
        }
    }.next);
}

pub fn forEachEventUntil(event_list: ?*events.IEventList, context: anytype, comptime callback: anytype) void {
    const list = event_list orelse return;
    const event_count = list.vtable.getEventCount(list);
    var event_index: base.int32 = 0;
    while (event_index < event_count) : (event_index += 1) {
        var event = events.Event{};
        const result = list.vtable.getEvent(list, event_index, &event);
        if (result == base.kInvalidArgument) break;
        if (result != base.kResultOk) continue;
        if (!callback(context, &event)) break;
    }
}

pub fn forEachParamValueQueue(param_queue: *parameter_changes.IParamValueQueue, context: anytype, comptime callback: anytype) void {
    forEachParamValueQueueUntil(param_queue, context, struct {
        fn next(inner_context: @TypeOf(context), param_id: vsttypes.ParamID, sample_offset: base.int32, value: vsttypes.ParamValue) bool {
            callback(inner_context, param_id, sample_offset, value);
            return true;
        }
    }.next);
}

pub fn forEachParamValueQueueUntil(param_queue: *parameter_changes.IParamValueQueue, context: anytype, comptime callback: anytype) void {
    const param_id = param_queue.vtable.getParameterId(param_queue);
    const num_points = param_queue.vtable.getPointCount(param_queue);
    var point_index: base.int32 = 0;
    while (point_index < num_points) : (point_index += 1) {
        var sample_offset: base.int32 = 0;
        var value: vsttypes.ParamValue = 0;
        const result = param_queue.vtable.getPoint(param_queue, point_index, &sample_offset, &value);
        if (result == base.kInvalidArgument) break;
        if (result != base.kResultOk) continue;
        if (!callback(context, param_id, sample_offset, value)) break;
    }
}

pub fn forEachLastParamValueQueue(param_queue: *parameter_changes.IParamValueQueue, context: anytype, comptime callback: anytype) void {
    const param_id = param_queue.vtable.getParameterId(param_queue);
    const num_points = param_queue.vtable.getPointCount(param_queue);
    if (num_points <= 0) return;
    var sample_offset: base.int32 = 0;
    var value: vsttypes.ParamValue = 0;
    if (param_queue.vtable.getPoint(param_queue, num_points - 1, &sample_offset, &value) == base.kResultOk) {
        callback(context, param_id, sample_offset, value);
    }
}

pub fn forEachParameterChanges(changes: ?*parameter_changes.IParameterChanges, context: anytype, comptime callback: anytype) void {
    forEachParameterChangesUntil(changes, context, struct {
        fn next(inner_context: @TypeOf(context), param_queue: *parameter_changes.IParamValueQueue) bool {
            callback(inner_context, param_queue);
            return true;
        }
    }.next);
}

pub fn forEachParameterChangesUntil(changes: ?*parameter_changes.IParameterChanges, context: anytype, comptime callback: anytype) void {
    const parameter_changes_list = changes orelse return;
    const param_count = parameter_changes_list.vtable.getParameterCount(parameter_changes_list);
    var param_index: base.int32 = 0;
    while (param_index < param_count) : (param_index += 1) {
        const param_queue = parameter_changes_list.vtable.getParameterData(parameter_changes_list, param_index) orelse continue;
        if (!callback(context, param_queue)) break;
    }
}

const EventCollector = struct {
    count: usize = 0,
    note_on_count: usize = 0,
    last_sample_offset: base.int32 = 0,
    last_param_id: vsttypes.ParamID = 0,
    last_param_value: vsttypes.ParamValue = 0,
};

fn collectEvent(collector: *EventCollector, event: *const events.Event) void {
    collector.count += 1;
    collector.last_sample_offset = event.sampleOffset;
    if (event.type == @intFromEnum(events.Event.EventTypes.kNoteOnEvent)) {
        collector.note_on_count += 1;
    }
}

fn collectParamValue(collector: *EventCollector, param_id: vsttypes.ParamID, sample_offset: base.int32, value: vsttypes.ParamValue) void {
    collector.count += 1;
    collector.last_param_id = param_id;
    collector.last_sample_offset = sample_offset;
    collector.last_param_value = value;
}

test "audio processor helpers match expected core behavior" {
    var setup32 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32) };
    var setup64 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample64) };
    try @import("std").testing.expectEqual(@as(base.uint32, 0), getSampleFramesSizeInBytes(&setup32, -1));
    try @import("std").testing.expectEqual(@as(base.uint32, 32), getSampleFramesSizeInBytes(&setup32, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 64), getSampleFramesSizeInBytes(&setup64, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 0xFFFFFFFC), getSampleFramesSizeInBytes(&setup32, std.math.maxInt(base.int32)));
    setup64.symbolicSampleSize = 99;
    try @import("std").testing.expectEqual(@as(base.uint32, 64), getSampleFramesSizeInBytes(&setup64, 8));
    try @import("std").testing.expectEqual(@as(base.uint64, 0x3f), getChannelMask(6));
    try @import("std").testing.expectEqual(@as(base.uint64, 0xFFFFFFFFFFFFFFFF), getChannelMask(64));
}

test "audio processor helpers clamp channel counts to supported range" {
    try std.testing.expectEqual(@as(base.int32, 0), channelCount(-1));
    try std.testing.expectEqual(@as(base.int32, 0), channelCount(0));
    try std.testing.expectEqual(@as(base.int32, 2), channelCount(2));
    try std.testing.expectEqual(max_supported_channels, channelCount(max_supported_channels + 1));
    try std.testing.expectEqual(@as(base.int32, 2), pairedChannelCount(2, max_supported_channels + 1));
    try std.testing.expectEqual(@as(base.int32, 0), pairedChannelCount(-1, max_supported_channels + 1));
}

test "audio processor buffer helpers ignore invalid ranges" {
    var input_samples = [_]vsttypes.Sample32{ 1, 2 };
    var output_samples = [_]vsttypes.Sample32{ 3, 4 };
    var input_channels = [_][*]vsttypes.Sample32{&input_samples};
    var output_channels = [_][*]vsttypes.Sample32{&output_samples};
    var input = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channels[0..].ptr },
    };
    var output = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channels[0..].ptr },
    };

    copy32(&input, &output, 1, -1);
    mix32(&input, &output, -1);
    multiply32(&input, &output, -1, 0);
    var output_buses = [_]audio_processor.AudioBusBuffers{output};
    clear32(&output_buses, -1, 1);

    try std.testing.expectEqual(@as(vsttypes.Sample32, 3), output_samples[0]);
    try std.testing.expect(isSilent32(&output, 1, -1));
}

test "audio processor buffer helpers reject overflowing ranges" {
    var input_samples32 = [_]vsttypes.Sample32{1};
    var output_samples32 = [_]vsttypes.Sample32{3};
    var input_channels32 = [_][*]vsttypes.Sample32{&input_samples32};
    var output_channels32 = [_][*]vsttypes.Sample32{&output_samples32};
    var input32 = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = input_channels32[0..].ptr },
    };
    var output32 = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers32 = output_channels32[0..].ptr },
    };

    copy32(&input32, &output32, 1, std.math.maxInt(base.int32));
    try std.testing.expectEqual(@as(vsttypes.Sample32, 3), output_samples32[0]);
    try std.testing.expect(isSilent32(&output32, 1, std.math.maxInt(base.int32)));

    var input_samples64 = [_]vsttypes.Sample64{1};
    var output_samples64 = [_]vsttypes.Sample64{3};
    var input_channels64 = [_][*]vsttypes.Sample64{&input_samples64};
    var output_channels64 = [_][*]vsttypes.Sample64{&output_samples64};
    var input64 = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = input_channels64[0..].ptr },
    };
    var output64 = audio_processor.AudioBusBuffers{
        .numChannels = 1,
        .channelBuffers = .{ .channelBuffers64 = output_channels64[0..].ptr },
    };

    copy64(&input64, &output64, 1, std.math.maxInt(base.int32));
    try std.testing.expectEqual(@as(vsttypes.Sample64, 3), output_samples64[0]);
    try std.testing.expect(isSilent64(&output64, 1, std.math.maxInt(base.int32)));
}

test "audio processor clear helpers skip malformed buses" {
    var first_samples32 = [_]vsttypes.Sample32{ 1, 2 };
    var second_samples32 = [_]vsttypes.Sample32{ 3, 4 };
    var first_channels32 = [_][*]vsttypes.Sample32{&first_samples32};
    var second_channels32 = [_][*]vsttypes.Sample32{&second_samples32};
    var buses32 = [_]audio_processor.AudioBusBuffers{
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers32 = first_channels32[0..].ptr },
        },
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers32 = null },
        },
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers32 = second_channels32[0..].ptr },
        },
    };

    clear32(&buses32, 2, @intCast(buses32.len));
    try std.testing.expectEqualSlices(vsttypes.Sample32, &.{ 0, 0 }, &first_samples32);
    try std.testing.expectEqualSlices(vsttypes.Sample32, &.{ 0, 0 }, &second_samples32);

    var first_samples64 = [_]vsttypes.Sample64{ 1, 2 };
    var second_samples64 = [_]vsttypes.Sample64{ 3, 4 };
    var first_channels64 = [_][*]vsttypes.Sample64{&first_samples64};
    var second_channels64 = [_][*]vsttypes.Sample64{&second_samples64};
    var buses64 = [_]audio_processor.AudioBusBuffers{
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers64 = first_channels64[0..].ptr },
        },
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers64 = null },
        },
        .{
            .numChannels = 1,
            .channelBuffers = .{ .channelBuffers64 = second_channels64[0..].ptr },
        },
    };

    clear64(&buses64, 2, @intCast(buses64.len));
    try std.testing.expectEqualSlices(vsttypes.Sample64, &.{ 0, 0 }, &first_samples64);
    try std.testing.expectEqualSlices(vsttypes.Sample64, &.{ 0, 0 }, &second_samples64);
}

test "audio processor helper iterates event lists and skips failed reads" {
    const event_items = [_]events.Event{
        .{
            .sampleOffset = 1,
            .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .pitch = 60, .velocity = 0.75 } },
        },
        .{
            .sampleOffset = 3,
            .type = @intFromEnum(events.Event.EventTypes.kNoteOffEvent),
            .data = .{ .noteOff = .{ .pitch = 60 } },
        },
    };
    var list = TestEventList.init(&event_items, 1);
    var collector = EventCollector{};

    forEachEvent(&list.iface, &collector, collectEvent);

    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(usize, 1), collector.note_on_count);
    try std.testing.expectEqual(@as(base.int32, 1), collector.last_sample_offset);
}

test "audio processor helper stops event iteration at invalid reported boundary" {
    const event_items = [_]events.Event{
        .{
            .sampleOffset = 7,
            .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .pitch = 64, .velocity = 0.5 } },
        },
    };
    var list = TestEventList.init(&event_items, null);
    list.reported_count = 1000;
    var collector = EventCollector{};

    forEachEvent(&list.iface, &collector, collectEvent);

    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(base.int32, 7), collector.last_sample_offset);
    try std.testing.expectEqual(@as(usize, 2), list.read_count);
}

test "audio processor helper can stop event iteration from callback" {
    const event_items = [_]events.Event{
        .{ .sampleOffset = 1, .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent) },
        .{ .sampleOffset = 2, .type = @intFromEnum(events.Event.EventTypes.kNoteOffEvent) },
    };
    var list = TestEventList.init(&event_items, null);
    var collector = EventCollector{};

    forEachEventUntil(&list.iface, &collector, struct {
        fn next(context: *EventCollector, event: *const events.Event) bool {
            collectEvent(context, event);
            return false;
        }
    }.next);

    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(usize, 1), list.read_count);
}

test "audio processor helper stops parameter point iteration at invalid reported boundary" {
    const points = [_]TestParamPoint{
        .{ .sample_offset = 2, .value = 0.25 },
        .{ .sample_offset = 6, .value = 0.75 },
    };
    var queue = TestParamValueQueue.init(11, &points);
    queue.reported_count = 1000;
    var collector = EventCollector{};

    forEachParamValueQueue(&queue.iface, &collector, collectParamValue);

    try std.testing.expectEqual(@as(usize, 2), collector.count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 11), collector.last_param_id);
    try std.testing.expectEqual(@as(base.int32, 6), collector.last_sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), collector.last_param_value);
    try std.testing.expectEqual(@as(usize, 3), queue.read_count);
}

test "audio processor helper can stop parameter point iteration from callback" {
    const points = [_]TestParamPoint{
        .{ .sample_offset = 2, .value = 0.25 },
        .{ .sample_offset = 6, .value = 0.75 },
    };
    var queue = TestParamValueQueue.init(11, &points);
    var collector = EventCollector{};

    forEachParamValueQueueUntil(&queue.iface, &collector, struct {
        fn next(context: *EventCollector, param_id: vsttypes.ParamID, sample_offset: base.int32, value: vsttypes.ParamValue) bool {
            collectParamValue(context, param_id, sample_offset, value);
            return false;
        }
    }.next);

    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(base.int32, 2), collector.last_sample_offset);
    try std.testing.expectEqual(@as(usize, 1), queue.read_count);
}

test "audio processor helper keeps SDK-compatible sparse parameter queue iteration" {
    const first_points = [_]TestParamPoint{
        .{ .sample_offset = 2, .value = 0.25 },
    };
    const second_points = [_]TestParamPoint{
        .{ .sample_offset = 6, .value = 0.75 },
    };
    var first_queue = TestParamValueQueue.init(11, &first_points);
    var second_queue = TestParamValueQueue.init(13, &second_points);
    var queues = [_]?*parameter_changes.IParamValueQueue{
        &first_queue.iface,
        null,
        &second_queue.iface,
    };
    var changes = TestParameterChanges.init(&queues);
    var collector = EventCollector{};

    forEachParameterChanges(&changes.iface, &collector, collectLastParamQueue);

    try std.testing.expectEqual(@as(usize, 2), collector.count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 13), collector.last_param_id);
    try std.testing.expectEqual(@as(base.int32, 6), collector.last_sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), collector.last_param_value);
    try std.testing.expectEqual(@as(usize, 3), changes.read_count);
}

test "audio processor helper can stop parameter queue iteration from callback" {
    const first_points = [_]TestParamPoint{.{ .sample_offset = 2, .value = 0.25 }};
    const second_points = [_]TestParamPoint{.{ .sample_offset = 6, .value = 0.75 }};
    var first_queue = TestParamValueQueue.init(11, &first_points);
    var second_queue = TestParamValueQueue.init(13, &second_points);
    var queues = [_]?*parameter_changes.IParamValueQueue{
        &first_queue.iface,
        &second_queue.iface,
    };
    var changes = TestParameterChanges.init(&queues);
    var collector = EventCollector{};

    forEachParameterChangesUntil(&changes.iface, &collector, struct {
        fn next(context: *EventCollector, queue: *parameter_changes.IParamValueQueue) bool {
            collectLastParamQueue(context, queue);
            return false;
        }
    }.next);

    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 11), collector.last_param_id);
    try std.testing.expectEqual(@as(usize, 1), changes.read_count);
}

test "audio processor helper skips empty last parameter queues" {
    var empty_queue = TestParamValueQueue.init(7, &.{});
    var collector = EventCollector{};

    forEachLastParamValueQueue(&empty_queue.iface, &collector, collectParamValue);
    try std.testing.expectEqual(@as(usize, 0), collector.count);

    const points = [_]TestParamPoint{
        .{ .sample_offset = 4, .value = 0.25 },
        .{ .sample_offset = 8, .value = 0.75 },
    };
    var queue = TestParamValueQueue.init(9, &points);

    forEachLastParamValueQueue(&queue.iface, &collector, collectParamValue);
    try std.testing.expectEqual(@as(usize, 1), collector.count);
    try std.testing.expectEqual(@as(vsttypes.ParamID, 9), collector.last_param_id);
    try std.testing.expectEqual(@as(base.int32, 8), collector.last_sample_offset);
    try std.testing.expectEqual(@as(vsttypes.ParamValue, 0.75), collector.last_param_value);
}

test "audio processor helpers treat negative reported counts as empty" {
    const event_items = [_]events.Event{
        .{
            .sampleOffset = 3,
            .type = @intFromEnum(events.Event.EventTypes.kNoteOnEvent),
            .data = .{ .noteOn = .{ .pitch = 60, .velocity = 0.5 } },
        },
    };
    var list = TestEventList.init(&event_items, null);
    list.reported_count = -1;
    var collector = EventCollector{};

    forEachEvent(&list.iface, &collector, collectEvent);

    try std.testing.expectEqual(@as(usize, 0), collector.count);
    try std.testing.expectEqual(@as(usize, 0), list.read_count);

    const points = [_]TestParamPoint{
        .{ .sample_offset = 2, .value = 0.25 },
    };
    var queue = TestParamValueQueue.init(11, &points);
    queue.reported_count = -1;

    forEachParamValueQueue(&queue.iface, &collector, collectParamValue);
    forEachLastParamValueQueue(&queue.iface, &collector, collectParamValue);

    try std.testing.expectEqual(@as(usize, 0), collector.count);
    try std.testing.expectEqual(@as(usize, 0), queue.read_count);

    var queues = [_]?*parameter_changes.IParamValueQueue{&queue.iface};
    var changes = TestParameterChanges.init(&queues);
    changes.reported_count = -1;

    forEachParameterChanges(&changes.iface, &collector, collectLastParamQueue);

    try std.testing.expectEqual(@as(usize, 0), collector.count);
    try std.testing.expectEqual(@as(usize, 0), changes.read_count);
}

const TestEventList = struct {
    iface: events.IEventList = .{ .vtable = &vtable },
    items: []const events.Event,
    reported_count: ?base.int32 = null,
    fail_index: ?base.int32 = null,
    read_count: usize = 0,

    const vtable = events.IEventListVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .getEventCount = getEventCount,
        .getEvent = getEvent,
        .addEvent = addEvent,
    };

    fn init(items: []const events.Event, fail_index: ?base.int32) TestEventList {
        return .{ .items = items, .fail_index = fail_index };
    }

    fn owner(ptr: *anyopaque) *TestEventList {
        const iface: *events.IEventList = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("../../tuid.zig").TUID, out: *?*anyopaque) callconv(.c) base.tresult {
        out.* = null;
        return base.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn getEventCount(ptr: *anyopaque) callconv(.c) base.int32 {
        const self = owner(ptr);
        return self.reported_count orelse @intCast(self.items.len);
    }

    fn getEvent(ptr: *anyopaque, index: base.int32, event: *events.Event) callconv(.c) base.tresult {
        if (index < 0) return base.kInvalidArgument;
        const self = owner(ptr);
        self.read_count += 1;
        if (self.fail_index) |fail_index| {
            if (index == fail_index) return base.kResultFalse;
        }
        const event_index: usize = @intCast(index);
        if (event_index >= self.items.len) return base.kInvalidArgument;
        event.* = self.items[event_index];
        return base.kResultOk;
    }

    fn addEvent(_: *anyopaque, _: *events.Event) callconv(.c) base.tresult {
        return base.kResultFalse;
    }
};

const TestParamPoint = struct {
    sample_offset: base.int32,
    value: vsttypes.ParamValue,
};

const TestParamValueQueue = struct {
    iface: parameter_changes.IParamValueQueue = .{ .vtable = &vtable },
    param_id: vsttypes.ParamID,
    points: []const TestParamPoint,
    reported_count: ?base.int32 = null,
    read_count: usize = 0,

    const vtable = parameter_changes.IParamValueQueueVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .getParameterId = getParameterId,
        .getPointCount = getPointCount,
        .getPoint = getPoint,
        .addPoint = addPoint,
    };

    fn init(param_id: vsttypes.ParamID, points: []const TestParamPoint) TestParamValueQueue {
        return .{ .param_id = param_id, .points = points };
    }

    fn owner(ptr: *anyopaque) *TestParamValueQueue {
        const iface: *parameter_changes.IParamValueQueue = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("../../tuid.zig").TUID, out: *?*anyopaque) callconv(.c) base.tresult {
        out.* = null;
        return base.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn getParameterId(ptr: *anyopaque) callconv(.c) vsttypes.ParamID {
        return owner(ptr).param_id;
    }

    fn getPointCount(ptr: *anyopaque) callconv(.c) base.int32 {
        const self = owner(ptr);
        return self.reported_count orelse @intCast(self.points.len);
    }

    fn getPoint(ptr: *anyopaque, index: base.int32, sample_offset: *base.int32, value: *vsttypes.ParamValue) callconv(.c) base.tresult {
        if (index < 0) return base.kInvalidArgument;
        const self = owner(ptr);
        self.read_count += 1;
        const point_index: usize = @intCast(index);
        const points = self.points;
        if (point_index >= points.len) return base.kInvalidArgument;
        sample_offset.* = points[point_index].sample_offset;
        value.* = points[point_index].value;
        return base.kResultOk;
    }

    fn addPoint(_: *anyopaque, _: base.int32, _: vsttypes.ParamValue, index: *base.int32) callconv(.c) base.tresult {
        index.* = -1;
        return base.kResultFalse;
    }
};

fn collectLastParamQueue(collector: *EventCollector, queue: *parameter_changes.IParamValueQueue) void {
    forEachLastParamValueQueue(queue, collector, collectParamValue);
}

const TestParameterChanges = struct {
    iface: parameter_changes.IParameterChanges = .{ .vtable = &vtable },
    queues: []const ?*parameter_changes.IParamValueQueue,
    reported_count: ?base.int32 = null,
    read_count: usize = 0,

    const vtable = parameter_changes.IParameterChangesVTable{
        .queryInterface = queryInterface,
        .addRef = addRef,
        .release = release,
        .getParameterCount = getParameterCount,
        .getParameterData = getParameterData,
        .addParameterData = addParameterData,
    };

    fn init(queues: []const ?*parameter_changes.IParamValueQueue) TestParameterChanges {
        return .{ .queues = queues };
    }

    fn owner(ptr: *anyopaque) *TestParameterChanges {
        const iface: *parameter_changes.IParameterChanges = @ptrCast(@alignCast(ptr));
        return @fieldParentPtr("iface", iface);
    }

    fn queryInterface(_: *anyopaque, _: *const @import("../../tuid.zig").TUID, out: *?*anyopaque) callconv(.c) base.tresult {
        out.* = null;
        return base.kNoInterface;
    }

    fn addRef(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn release(_: *anyopaque) callconv(.c) base.uint32 {
        return 1;
    }

    fn getParameterCount(ptr: *anyopaque) callconv(.c) base.int32 {
        const self = owner(ptr);
        return self.reported_count orelse @intCast(self.queues.len);
    }

    fn getParameterData(ptr: *anyopaque, index: base.int32) callconv(.c) ?*parameter_changes.IParamValueQueue {
        if (index < 0) return null;
        const self = owner(ptr);
        self.read_count += 1;
        const queue_index: usize = @intCast(index);
        if (queue_index >= self.queues.len) return null;
        return self.queues[queue_index];
    }

    fn addParameterData(_: *anyopaque, _: *const vsttypes.ParamID, index: *base.int32) callconv(.c) ?*parameter_changes.IParamValueQueue {
        index.* = -1;
        return null;
    }
};
