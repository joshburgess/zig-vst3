const std = @import("std");
const base = @import("../base/types.zig");
const audio_processor = @import("ivstaudioprocessor.zig");
const events = @import("ivstevents.zig");
const parameter_changes = @import("ivstparameterchanges.zig");
const vsttypes = @import("vsttypes.zig");

pub fn getChannelBuffersPointer(
    process_setup: *const audio_processor.ProcessSetup,
    buffers: *const audio_processor.AudioBusBuffers,
) ?*anyopaque {
    if (process_setup.symbolicSampleSize == @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32)) {
        return @ptrCast(buffers.channelBuffers.channelBuffers32);
    }
    return @ptrCast(buffers.channelBuffers.channelBuffers64);
}

pub fn getSampleFramesSizeInBytes(
    process_setup: *const audio_processor.ProcessSetup,
    num_samples: base.int32,
) base.uint32 {
    if (num_samples <= 0) return 0;
    const sample_size: base.int32 = if (process_setup.symbolicSampleSize == @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32))
        @intCast(@sizeOf(vsttypes.Sample32))
    else
        @intCast(@sizeOf(vsttypes.Sample64));
    const max_samples = std.math.maxInt(base.uint32) / @as(base.uint32, @intCast(sample_size));
    const safe_samples: base.uint32 = @min(@as(base.uint32, @intCast(num_samples)), max_samples);
    return safe_samples * @as(base.uint32, @intCast(sample_size));
}

pub fn getChannelMask(num_channels: base.int32) base.uint64 {
    if (num_channels >= 64) return @as(base.uint64, 0xFFFFFFFFFFFFFFFF);
    if (num_channels <= 0) return 0;
    return (@as(base.uint64, 1) << @intCast(num_channels)) - 1;
}

pub fn copy32(
    src: ?*audio_processor.AudioBusBuffers,
    dest: ?*audio_processor.AudioBusBuffers,
    slice_size: base.int32,
    start_index: base.int32,
) void {
    if (slice_size <= 0 or start_index < 0) return;
    const src_buffer = src orelse return;
    const dest_buffer = dest orelse return;
    const src_channels = src_buffer.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest_buffer.channelBuffers.channelBuffers32 orelse return;
    const num_channels = @min(src_buffer.numChannels, dest_buffer.numChannels);
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

pub fn copy64(
    src: ?*audio_processor.AudioBusBuffers,
    dest: ?*audio_processor.AudioBusBuffers,
    slice_size: base.int32,
    start_index: base.int32,
) void {
    if (slice_size <= 0 or start_index < 0) return;
    const src_buffer = src orelse return;
    const dest_buffer = dest orelse return;
    const src_channels = src_buffer.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest_buffer.channelBuffers.channelBuffers64 orelse return;
    const num_channels = @min(src_buffer.numChannels, dest_buffer.numChannels);
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

pub fn clear32(audio_bus_buffers: ?[*]audio_processor.AudioBusBuffers, sample_count: base.int32, bus_count: base.int32) void {
    if (sample_count <= 0 or bus_count <= 0) return;
    const buses = audio_bus_buffers orelse return;
    var bus: base.int32 = 0;
    while (bus < bus_count) : (bus += 1) {
        const audio_buffer = &buses[@intCast(bus)];
        const channels = audio_buffer.channelBuffers.channelBuffers32 orelse return;
        var channel: base.int32 = 0;
        while (channel < audio_buffer.numChannels) : (channel += 1) {
            const channel_buffer = channels[@intCast(channel)];
            var sample: base.int32 = 0;
            while (sample < sample_count) : (sample += 1) {
                channel_buffer[@intCast(sample)] = 0;
            }
        }
    }
}

pub fn clear64(audio_bus_buffers: ?[*]audio_processor.AudioBusBuffers, sample_count: base.int32, bus_count: base.int32) void {
    if (sample_count <= 0 or bus_count <= 0) return;
    const buses = audio_bus_buffers orelse return;
    var bus: base.int32 = 0;
    while (bus < bus_count) : (bus += 1) {
        const audio_buffer = &buses[@intCast(bus)];
        const channels = audio_buffer.channelBuffers.channelBuffers64 orelse return;
        var channel: base.int32 = 0;
        while (channel < audio_buffer.numChannels) : (channel += 1) {
            const channel_buffer = channels[@intCast(channel)];
            var sample: base.int32 = 0;
            while (sample < sample_count) : (sample += 1) {
                channel_buffer[@intCast(sample)] = 0;
            }
        }
    }
}

pub fn mix32(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers32 orelse return;
    const num_channels = @min(src.numChannels, dest.numChannels);
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

pub fn mix64(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers64 orelse return;
    const num_channels = @min(src.numChannels, dest.numChannels);
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

pub fn multiply32(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32, factor: f32) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers32 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers32 orelse return;
    const num_channels = @min(src.numChannels, dest.numChannels);
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

pub fn multiply64(src: *audio_processor.AudioBusBuffers, dest: *audio_processor.AudioBusBuffers, sample_count: base.int32, factor: f64) void {
    if (sample_count <= 0) return;
    const src_channels = src.channelBuffers.channelBuffers64 orelse return;
    const dest_channels = dest.channelBuffers.channelBuffers64 orelse return;
    const num_channels = @min(src.numChannels, dest.numChannels);
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

pub fn isSilent32(audio_buffer: *audio_processor.AudioBusBuffers, sample_count: base.int32, start_index: base.int32) bool {
    if (sample_count <= 0 or start_index < 0) return true;
    const channels = audio_buffer.channelBuffers.channelBuffers32 orelse return true;
    const end = sample_count + start_index;
    var channel: base.int32 = 0;
    while (channel < audio_buffer.numChannels) : (channel += 1) {
        const channel_buffer = channels[@intCast(channel)];
        var sample = start_index;
        while (sample < end) : (sample += 1) {
            if (@abs(channel_buffer[@intCast(sample)]) > 1e-10) return false;
        }
    }
    return true;
}

pub fn isSilent64(audio_buffer: *audio_processor.AudioBusBuffers, sample_count: base.int32, start_index: base.int32) bool {
    if (sample_count <= 0 or start_index < 0) return true;
    const channels = audio_buffer.channelBuffers.channelBuffers64 orelse return true;
    const end = sample_count + start_index;
    var channel: base.int32 = 0;
    while (channel < audio_buffer.numChannels) : (channel += 1) {
        const channel_buffer = channels[@intCast(channel)];
        var sample = start_index;
        while (sample < end) : (sample += 1) {
            if (@abs(channel_buffer[@intCast(sample)]) > 1e-10) return false;
        }
    }
    return true;
}

pub fn forEachEvent(event_list: ?*events.IEventList, context: anytype, comptime callback: anytype) void {
    const list = event_list orelse return;
    const event_count = list.vtable.getEventCount(list);
    var event_index: base.int32 = 0;
    while (event_index < event_count) : (event_index += 1) {
        var event = events.Event{};
        if (list.vtable.getEvent(list, event_index, &event) != base.kResultOk) continue;
        callback(context, &event);
    }
}

pub fn forEachParamValueQueue(param_queue: *parameter_changes.IParamValueQueue, context: anytype, comptime callback: anytype) void {
    const param_id = param_queue.vtable.getParameterId(param_queue);
    const num_points = param_queue.vtable.getPointCount(param_queue);
    var point_index: base.int32 = 0;
    while (point_index < num_points) : (point_index += 1) {
        var sample_offset: base.int32 = 0;
        var value: vsttypes.ParamValue = 0;
        if (param_queue.vtable.getPoint(param_queue, point_index, &sample_offset, &value) != base.kResultOk) continue;
        callback(context, param_id, sample_offset, value);
    }
}

pub fn forEachLastParamValueQueue(param_queue: *parameter_changes.IParamValueQueue, context: anytype, comptime callback: anytype) void {
    const param_id = param_queue.vtable.getParameterId(param_queue);
    const num_points = param_queue.vtable.getPointCount(param_queue);
    var sample_offset: base.int32 = 0;
    var value: vsttypes.ParamValue = 0;
    if (param_queue.vtable.getPoint(param_queue, num_points - 1, &sample_offset, &value) == base.kResultOk) {
        callback(context, param_id, sample_offset, value);
    }
}

pub fn forEachParameterChanges(changes: ?*parameter_changes.IParameterChanges, context: anytype, comptime callback: anytype) void {
    const parameter_changes_list = changes orelse return;
    const param_count = parameter_changes_list.vtable.getParameterCount(parameter_changes_list);
    var param_index: base.int32 = 0;
    while (param_index < param_count) : (param_index += 1) {
        const param_queue = parameter_changes_list.vtable.getParameterData(parameter_changes_list, param_index) orelse continue;
        callback(context, param_queue);
    }
}

const EventCollector = struct {
    count: usize = 0,
    note_on_count: usize = 0,
    last_sample_offset: base.int32 = 0,
};

fn collectEvent(collector: *EventCollector, event: *const events.Event) void {
    collector.count += 1;
    collector.last_sample_offset = event.sampleOffset;
    if (event.type == @intFromEnum(events.Event.EventTypes.kNoteOnEvent)) {
        collector.note_on_count += 1;
    }
}

test "audio processor helpers match expected core behavior" {
    var setup32 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32) };
    var setup64 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample64) };
    try @import("std").testing.expectEqual(@as(base.uint32, 0), getSampleFramesSizeInBytes(&setup32, -1));
    try @import("std").testing.expectEqual(@as(base.uint32, 32), getSampleFramesSizeInBytes(&setup32, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 64), getSampleFramesSizeInBytes(&setup64, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 0xFFFFFFFC), getSampleFramesSizeInBytes(&setup32, std.math.maxInt(base.int32)));
    try @import("std").testing.expectEqual(@as(base.uint64, 0x3f), getChannelMask(6));
    try @import("std").testing.expectEqual(@as(base.uint64, 0xFFFFFFFFFFFFFFFF), getChannelMask(64));
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

const TestEventList = struct {
    iface: events.IEventList = .{ .vtable = &vtable },
    items: []const events.Event,
    fail_index: ?base.int32 = null,

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
        return @intCast(owner(ptr).items.len);
    }

    fn getEvent(ptr: *anyopaque, index: base.int32, event: *events.Event) callconv(.c) base.tresult {
        if (index < 0) return base.kInvalidArgument;
        const self = owner(ptr);
        if (self.fail_index != null and index == self.fail_index.?) return base.kResultFalse;
        const event_index: usize = @intCast(index);
        if (event_index >= self.items.len) return base.kInvalidArgument;
        event.* = self.items[event_index];
        return base.kResultOk;
    }

    fn addEvent(_: *anyopaque, _: *events.Event) callconv(.c) base.tresult {
        return base.kResultFalse;
    }
};
