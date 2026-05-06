const base = @import("../base/types.zig");
const audio_processor = @import("ivstaudioprocessor.zig");
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
    const sample_size: base.int32 = if (process_setup.symbolicSampleSize == @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32))
        @intCast(@sizeOf(vsttypes.Sample32))
    else
        @intCast(@sizeOf(vsttypes.Sample64));
    return @intCast(num_samples * sample_size);
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

test "audio processor helpers match expected core behavior" {
    var setup32 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32) };
    var setup64 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample64) };
    try @import("std").testing.expectEqual(@as(base.uint32, 32), getSampleFramesSizeInBytes(&setup32, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 64), getSampleFramesSizeInBytes(&setup64, 8));
    try @import("std").testing.expectEqual(@as(base.uint64, 0x3f), getChannelMask(6));
    try @import("std").testing.expectEqual(@as(base.uint64, 0xFFFFFFFFFFFFFFFF), getChannelMask(64));
}
