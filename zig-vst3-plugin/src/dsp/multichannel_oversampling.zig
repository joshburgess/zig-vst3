const std = @import("std");
const oversampling = @import("oversampling.zig");

pub fn MultichannelOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
    comptime maximum_channels: usize,
) type {
    if (maximum_channels == 0)
        @compileError("multichannel oversampling requires channels");

    const ChannelProcessor = oversampling.Oversampler(
        Sample,
        maximum_frames,
        factor,
    );

    return struct {
        const Self = @This();

        pub const oversampling_factor = factor;
        pub const latency_samples = ChannelProcessor.latency_samples;

        processors: [maximum_channels]ChannelProcessor,
        high_rate_views: [maximum_channels][]Sample = undefined,
        channel_count: usize,
        pending_frames: usize = 0,

        pub fn init(channel_count: usize) !Self {
            if (channel_count == 0 or channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            const prototype = try ChannelProcessor.init();
            return .{
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn setChannelCount(self: *Self, channel_count: usize) !void {
            if (channel_count == 0 or channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            self.channel_count = channel_count;
            self.reset();
        }

        pub fn reset(self: *Self) void {
            for (&self.processors) |*processor| processor.reset();
            self.pending_frames = 0;
        }

        pub fn upsample(
            self: *Self,
            input: []const []const Sample,
        ) ![]const []Sample {
            try self.validateInput(input);
            for (input, 0..) |channel_samples, index|
                self.high_rate_views[index] =
                    try self.processors[index].upsample(channel_samples);
            self.pending_frames = input[0].len;
            return self.high_rate_views[0..self.channel_count];
        }

        pub fn downsample(
            self: *Self,
            output: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames == 0) return error.NoOversampledBlock;
            if (output.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            for (output) |channel_samples| {
                if (channel_samples.len != self.pending_frames)
                    return error.OversamplingFrameMismatch;
            }
            for (output, 0..) |channel_samples, index|
                try self.processors[index].downsample(channel_samples);
            self.pending_frames = 0;
        }

        pub fn channel(
            self: *Self,
            index: usize,
        ) !*ChannelProcessor {
            if (index >= self.channel_count)
                return error.OversamplingChannelOutOfRange;
            return &self.processors[index];
        }

        pub fn valid(self: *const Self) bool {
            if (self.channel_count == 0 or
                self.channel_count > maximum_channels or
                self.pending_frames > maximum_frames)
                return false;
            for (self.processors[0..self.channel_count]) |processor| {
                if (!processor.valid() or
                    processor.pending_frames != self.pending_frames)
                    return false;
            }
            return true;
        }

        fn validateInput(
            self: *const Self,
            input: []const []const Sample,
        ) !void {
            if (!self.valid()) return error.InvalidOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            if (input.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            const frame_count = input[0].len;
            if (frame_count == 0 or frame_count > maximum_frames)
                return error.OversamplingCapacityExceeded;
            for (input) |channel_samples| {
                if (channel_samples.len != frame_count)
                    return error.OversamplingFrameMismatch;
                for (channel_samples) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.NonFiniteOversamplingInput;
                }
            }
        }
    };
}

test "multichannel oversampling preserves independent channel signals" {
    const Processor = MultichannelOversampler(f32, 16, 2, 2);
    var processor = try Processor.init(2);
    var left: [16]f32 = @splat(0.25);
    var right: [16]f32 = @splat(-0.5);
    var output_left: [16]f32 = undefined;
    var output_right: [16]f32 = undefined;
    for (0..8) |_| {
        const high_rate = try processor.upsample(
            &.{ left[0..], right[0..] },
        );
        try std.testing.expectEqual(@as(usize, 2), high_rate.len);
        try processor.downsample(
            &.{ output_left[0..], output_right[0..] },
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        output_left[output_left.len - 1],
        0.000_01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -0.5),
        output_right[output_right.len - 1],
        0.000_01,
    );
}

test "multichannel high-rate views allow per-channel processing" {
    const Processor = MultichannelOversampler(f64, 8, 4, 2);
    var processor = try Processor.init(2);
    var left: [8]f64 = @splat(0.25);
    var right: [8]f64 = @splat(0.5);
    var output_left: [8]f64 = undefined;
    var output_right: [8]f64 = undefined;
    for (0..8) |_| {
        const high_rate = try processor.upsample(
            &.{ left[0..], right[0..] },
        );
        for (high_rate[0]) |*sample| sample.* *= 2.0;
        for (high_rate[1]) |*sample| sample.* *= 0.5;
        try processor.downsample(
            &.{ output_left[0..], output_right[0..] },
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        output_left[output_left.len - 1],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        output_right[output_right.len - 1],
        0.000_001,
    );
}

test "multichannel oversampling validates the complete shape before mutation" {
    const Processor = MultichannelOversampler(f32, 8, 2, 2);
    var processor = try Processor.init(2);
    var left: [8]f32 = @splat(0.0);
    var short: [7]f32 = @splat(0.0);
    try std.testing.expectError(
        error.OversamplingFrameMismatch,
        processor.upsample(&.{ left[0..], short[0..] }),
    );
    try std.testing.expectEqual(@as(usize, 0), processor.pending_frames);
    try std.testing.expectError(
        error.OversamplingChannelMismatch,
        processor.upsample(&.{left[0..]}),
    );
    try std.testing.expect(processor.valid());
}
