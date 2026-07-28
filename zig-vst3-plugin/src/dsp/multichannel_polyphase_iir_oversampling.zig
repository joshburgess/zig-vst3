const std = @import("std");
const polyphase_oversampling =
    @import("polyphase_iir_oversampling.zig");

pub fn MultichannelOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime factor: usize,
    comptime maximum_channels: usize,
) type {
    if (maximum_channels == 0)
        @compileError(
            "multichannel polyphase IIR oversampling requires channels",
        );

    const ChannelProcessor = polyphase_oversampling.Oversampler(
        Sample,
        maximum_frames,
        factor,
    );

    return struct {
        const Self = @This();

        pub const oversampling_factor = factor;
        pub const maximum_channel_count = maximum_channels;

        processors: [maximum_channels]ChannelProcessor,
        high_rate_views: [maximum_channels][]Sample = undefined,
        output_scratch: [maximum_channels][maximum_frames]Sample = undefined,
        channel_count: usize,
        pending_frames: usize = 0,

        pub fn init(
            channel_count: usize,
            config: polyphase_oversampling.Config,
        ) !Self {
            return initWithOptions(channel_count, config, .{});
        }

        pub fn initWithOptions(
            channel_count: usize,
            config: polyphase_oversampling.Config,
            options: polyphase_oversampling.Options,
        ) !Self {
            return initStagesWithOptions(
                channel_count,
                @splat(config),
                options,
            );
        }

        pub fn initStages(
            channel_count: usize,
            configs: [ChannelProcessor.oversampling_stage_count]polyphase_oversampling.Config,
        ) !Self {
            return initStagesWithOptions(channel_count, configs, .{});
        }

        pub fn initStagesWithOptions(
            channel_count: usize,
            configs: [ChannelProcessor.oversampling_stage_count]polyphase_oversampling.Config,
            options: polyphase_oversampling.Options,
        ) !Self {
            if (channel_count == 0 or
                channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            const prototype =
                try ChannelProcessor.initStagesWithOptions(
                    configs,
                    options,
                );
            return .{
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn setChannelCount(
            self: *Self,
            channel_count: usize,
        ) !void {
            if (channel_count == 0 or
                channel_count > maximum_channels)
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

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidOversamplerState;
            return self.processors[0].latencySamples();
        }

        pub fn upsample(
            self: *Self,
            input: []const []const Sample,
        ) ![]const []Sample {
            try self.validateInput(input);
            errdefer self.reset();
            for (input, 0..) |channel_samples, index| {
                self.high_rate_views[index] =
                    try self.processors[index].upsample(
                        channel_samples,
                    );
            }
            self.pending_frames = input[0].len;
            return self.high_rate_views[0..self.channel_count];
        }

        pub fn downsample(
            self: *Self,
            output: []const []Sample,
        ) !void {
            try self.validateOutput(output);
            for (self.processors[0..self.channel_count]) |*processor| {
                const high_rate = try processor.pendingHighRate();
                for (high_rate) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.NonFiniteOversamplingInput;
                }
            }

            errdefer self.reset();
            for (0..self.channel_count) |index| {
                try self.processors[index].downsample(
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
            for (output, 0..) |channel_samples, index| {
                @memcpy(
                    channel_samples,
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
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
            if (!self.valid())
                return error.InvalidOversamplerState;
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

        fn validateOutput(
            self: *const Self,
            output: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            for (output) |channel_samples| {
                if (channel_samples.len != self.pending_frames)
                    return error.OversamplingFrameMismatch;
            }
        }
    };
}

pub fn RuntimeMultichannelOversampler(
    comptime Sample: type,
    comptime maximum_frames: usize,
    comptime maximum_stages: usize,
    comptime maximum_channels: usize,
) type {
    if (maximum_channels == 0)
        @compileError(
            "runtime multichannel polyphase IIR oversampling requires channels",
        );

    const ChannelProcessor =
        polyphase_oversampling.RuntimeOversampler(
            Sample,
            maximum_frames,
            maximum_stages,
        );

    return struct {
        const Self = @This();

        pub const maximum_channel_count = maximum_channels;
        pub const maximum_stage_count = maximum_stages;
        pub const maximum_oversampling_factor =
            ChannelProcessor.maximum_oversampling_factor;

        processors: [maximum_channels]ChannelProcessor,
        high_rate_views: [maximum_channels][]Sample = undefined,
        output_scratch: [maximum_channels][maximum_frames]Sample = undefined,
        channel_count: usize,
        pending_frames: usize = 0,

        pub fn init(
            channel_count: usize,
            configs: []const polyphase_oversampling.Config,
        ) !Self {
            return initWithOptions(
                channel_count,
                configs,
                .{},
            );
        }

        pub fn initWithOptions(
            channel_count: usize,
            configs: []const polyphase_oversampling.Config,
            options: polyphase_oversampling.Options,
        ) !Self {
            if (channel_count == 0 or
                channel_count > maximum_channels)
                return error.InvalidOversamplingChannelCount;
            const prototype =
                try ChannelProcessor.initWithOptions(
                    configs,
                    options,
                );
            return .{
                .processors = @splat(prototype),
                .channel_count = channel_count,
            };
        }

        pub fn reconfigure(
            self: *Self,
            configs: []const polyphase_oversampling.Config,
            options: polyphase_oversampling.Options,
        ) !void {
            if (!self.valid())
                return error.InvalidOversamplerState;
            if (self.pending_frames != 0)
                return error.OversampledBlockPending;
            const prototype =
                try ChannelProcessor.initWithOptions(
                    configs,
                    options,
                );
            self.processors = @splat(prototype);
        }

        pub fn setChannelCount(
            self: *Self,
            channel_count: usize,
        ) !void {
            if (channel_count == 0 or
                channel_count > maximum_channels)
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

        pub fn oversamplingFactor(self: *const Self) !usize {
            if (!self.valid())
                return error.InvalidOversamplerState;
            return self.processors[0].oversamplingFactor();
        }

        pub fn latencySamples(self: *const Self) !f64 {
            if (!self.valid())
                return error.InvalidOversamplerState;
            return self.processors[0].latencySamples();
        }

        pub fn upsample(
            self: *Self,
            input: []const []const Sample,
        ) ![]const []Sample {
            try self.validateInput(input);
            errdefer self.reset();
            for (input, 0..) |channel_samples, index| {
                self.high_rate_views[index] =
                    try self.processors[index].upsample(
                        channel_samples,
                    );
            }
            self.pending_frames = input[0].len;
            return self.high_rate_views[0..self.channel_count];
        }

        pub fn downsample(
            self: *Self,
            output: []const []Sample,
        ) !void {
            try self.validateOutput(output);
            for (self.processors[0..self.channel_count]) |*processor| {
                const high_rate = try processor.pendingHighRate();
                for (high_rate) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.NonFiniteOversamplingInput;
                }
            }

            errdefer self.reset();
            for (0..self.channel_count) |index| {
                try self.processors[index].downsample(
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
            for (output, 0..) |channel_samples, index| {
                @memcpy(
                    channel_samples,
                    self.output_scratch[index][0..self.pending_frames],
                );
            }
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
            if (!self.valid())
                return error.InvalidOversamplerState;
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

        fn validateOutput(
            self: *const Self,
            output: []const []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidOversamplerState;
            if (self.pending_frames == 0)
                return error.NoOversampledBlock;
            if (output.len != self.channel_count)
                return error.OversamplingChannelMismatch;
            for (output) |channel_samples| {
                if (channel_samples.len != self.pending_frames)
                    return error.OversamplingFrameMismatch;
            }
        }
    };
}

test "multichannel polyphase IIR oversampling isolates channels" {
    const Processor =
        MultichannelOversampler(f64, 32, 4, 4);
    var processor = try Processor.init(3, .{
        .normalized_transition_width = 0.08,
        .stopband_attenuation_db = -90.0,
    });
    var first: [32]f64 = @splat(0.25);
    var second: [32]f64 = @splat(-0.5);
    var third: [32]f64 = @splat(0.125);
    var output_first: [32]f64 = undefined;
    var output_second: [32]f64 = undefined;
    var output_third: [32]f64 = undefined;
    for (0..16) |_| {
        const high_rate = try processor.upsample(&.{
            first[0..],
            second[0..],
            third[0..],
        });
        for (high_rate[0]) |*sample| sample.* *= 2.0;
        for (high_rate[1]) |*sample| sample.* *= 0.5;
        try processor.downsample(&.{
            output_first[0..],
            output_second[0..],
            output_third[0..],
        });
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        output_first[31],
        1.0e-9,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -0.25),
        output_second[31],
        1.0e-9,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        output_third[31],
        1.0e-9,
    );
}

test "multichannel polyphase IIR processing is partition independent" {
    const Processor =
        MultichannelOversampler(f32, 129, 8, 2);
    var left: [129]f32 = undefined;
    var right: [129]f32 = undefined;
    for (&left, &right, 0..) |*left_sample, *right_sample, index| {
        const position: f32 = @floatFromInt(index);
        left_sample.* = @sin(std.math.tau * 0.027 * position);
        right_sample.* = @cos(std.math.tau * 0.113 * position);
    }

    var whole = try Processor.init(2, .{});
    _ = try whole.upsample(&.{ left[0..], right[0..] });
    var whole_left: [129]f32 = undefined;
    var whole_right: [129]f32 = undefined;
    try whole.downsample(&.{ whole_left[0..], whole_right[0..] });

    var partitioned = try Processor.init(2, .{});
    var split_left: [129]f32 = undefined;
    var split_right: [129]f32 = undefined;
    _ = try partitioned.upsample(&.{
        left[0..41],
        right[0..41],
    });
    try partitioned.downsample(&.{
        split_left[0..41],
        split_right[0..41],
    });
    _ = try partitioned.upsample(&.{
        left[41..],
        right[41..],
    });
    try partitioned.downsample(&.{
        split_left[41..],
        split_right[41..],
    });
    try std.testing.expectEqualSlices(f32, &whole_left, &split_left);
    try std.testing.expectEqualSlices(
        f32,
        &whole_right,
        &split_right,
    );
}

test "multichannel polyphase IIR validation precedes mutation" {
    const Processor =
        MultichannelOversampler(f32, 8, 2, 2);
    var processor = try Processor.init(2, .{});
    var left: [8]f32 = @splat(0.25);
    var right: [8]f32 = @splat(-0.25);
    var short: [7]f32 = @splat(0.0);
    try std.testing.expectError(
        error.OversamplingFrameMismatch,
        processor.upsample(&.{ left[0..], short[0..] }),
    );
    try std.testing.expect(processor.valid());

    const high_rate =
        try processor.upsample(&.{ left[0..], right[0..] });
    high_rate[1][3] = std.math.nan(f32);
    var output_left: [8]f32 = @splat(123.0);
    var output_right: [8]f32 = @splat(456.0);
    try std.testing.expectError(
        error.NonFiniteOversamplingInput,
        processor.downsample(&.{
            output_left[0..],
            output_right[0..],
        }),
    );
    try std.testing.expectEqual(
        [_]f32{123.0} ** 8,
        output_left,
    );
    try std.testing.expectEqual(
        [_]f32{456.0} ** 8,
        output_right,
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        processor.pending_frames,
    );
    processor.reset();
    try std.testing.expect(processor.valid());
}

test "multichannel polyphase IIR channel changes are bounded" {
    const Processor =
        MultichannelOversampler(f64, 16, 2, 4);
    try std.testing.expectError(
        error.InvalidOversamplingChannelCount,
        Processor.init(0, .{}),
    );
    var processor = try Processor.init(2, .{});
    try processor.setChannelCount(4);
    try std.testing.expectEqual(@as(usize, 4), processor.channel_count);
    try std.testing.expectError(
        error.OversamplingChannelOutOfRange,
        processor.channel(4),
    );
    try std.testing.expect((try processor.latencySamples()) > 0.0);
}

test "runtime multichannel stages match fixed-factor processing" {
    const Fixed =
        MultichannelOversampler(f64, 9, 4, 2);
    const Runtime =
        RuntimeMultichannelOversampler(f64, 9, 4, 2);
    const configs = [_]polyphase_oversampling.Config{
        .{ .normalized_transition_width = 0.12 },
        .{ .normalized_transition_width = 0.08 },
    };
    var fixed = try Fixed.initStages(2, configs);
    var runtime = try Runtime.init(2, &configs);
    try std.testing.expectEqual(
        @as(usize, 4),
        try runtime.oversamplingFactor(),
    );
    try std.testing.expectEqual(
        try fixed.latencySamples(),
        try runtime.latencySamples(),
    );

    var left: [9]f64 = undefined;
    var right: [9]f64 = undefined;
    for (&left, &right, 0..) |*left_sample, *right_sample, index| {
        const position: f64 = @floatFromInt(index);
        left_sample.* = @sin(std.math.tau * 0.1 * position);
        right_sample.* = @cos(std.math.tau * 0.13 * position);
    }
    const fixed_high_rate =
        try fixed.upsample(&.{ left[0..], right[0..] });
    const runtime_high_rate =
        try runtime.upsample(&.{ left[0..], right[0..] });
    for (fixed_high_rate, runtime_high_rate) |
        fixed_channel,
        runtime_channel,
    | {
        try std.testing.expectEqualSlices(
            f64,
            fixed_channel,
            runtime_channel,
        );
    }
    var fixed_left: [9]f64 = undefined;
    var fixed_right: [9]f64 = undefined;
    var runtime_left: [9]f64 = undefined;
    var runtime_right: [9]f64 = undefined;
    try fixed.downsample(&.{ fixed_left[0..], fixed_right[0..] });
    try runtime.downsample(&.{
        runtime_left[0..],
        runtime_right[0..],
    });
    try std.testing.expectEqualSlices(f64, &fixed_left, &runtime_left);
    try std.testing.expectEqualSlices(f64, &fixed_right, &runtime_right);
}

test "runtime multichannel reconfiguration is block transactional" {
    const Runtime =
        RuntimeMultichannelOversampler(f32, 8, 3, 4);
    var runtime = try Runtime.init(2, &.{});
    try std.testing.expectEqual(
        @as(usize, 1),
        try runtime.oversamplingFactor(),
    );
    var left: [8]f32 = @splat(0.25);
    var right: [8]f32 = @splat(-0.25);
    var output_left: [8]f32 = undefined;
    var output_right: [8]f32 = undefined;
    _ = try runtime.upsample(&.{ left[0..], right[0..] });
    try std.testing.expectError(
        error.OversampledBlockPending,
        runtime.reconfigure(&.{.{}}, .{}),
    );
    try runtime.downsample(&.{
        output_left[0..],
        output_right[0..],
    });

    try runtime.reconfigure(
        &.{ .{}, .{}, .{} },
        .{ .use_integer_latency = true },
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        try runtime.oversamplingFactor(),
    );
    const latency = try runtime.latencySamples();
    try std.testing.expectEqual(@ceil(latency), latency);
    try runtime.setChannelCount(4);
    try std.testing.expectEqual(@as(usize, 4), runtime.channel_count);

    try std.testing.expectError(
        error.InvalidPolyphaseIirOversamplingConfig,
        runtime.reconfigure(
            &.{.{ .stopband_attenuation_db = 1.0 }},
            .{},
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 8),
        try runtime.oversamplingFactor(),
    );
}
