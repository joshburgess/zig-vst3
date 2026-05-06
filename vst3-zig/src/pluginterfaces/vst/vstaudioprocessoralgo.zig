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

test "audio processor helpers match expected core behavior" {
    var setup32 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample32) };
    var setup64 = audio_processor.ProcessSetup{ .symbolicSampleSize = @intFromEnum(audio_processor.SymbolicSampleSizes.kSample64) };
    try @import("std").testing.expectEqual(@as(base.uint32, 32), getSampleFramesSizeInBytes(&setup32, 8));
    try @import("std").testing.expectEqual(@as(base.uint32, 64), getSampleFramesSizeInBytes(&setup64, 8));
    try @import("std").testing.expectEqual(@as(base.uint64, 0x3f), getChannelMask(6));
    try @import("std").testing.expectEqual(@as(base.uint64, 0xFFFFFFFFFFFFFFFF), getChannelMask(64));
}
