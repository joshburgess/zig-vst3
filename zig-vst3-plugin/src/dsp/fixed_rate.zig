const std = @import("std");
const resampler = @import("resampler.zig");

pub const maximum_rate_ratio = 8.0;
pub const maximum_pending_model_frames = 10;

pub const Config = struct {
    host_rate: f64,
    model_rate: f64,

    pub fn validate(self: Config) error{InvalidConfig}!void {
        try (resampler.Config{ .input_rate = self.host_rate, .output_rate = self.model_rate }).validate();
        const ratio = self.model_rate / self.host_rate;
        if (ratio > maximum_rate_ratio or ratio < 1.0 / maximum_rate_ratio) return error.InvalidConfig;
    }
};

pub fn FixedRatePipeline(comptime Sample: type) type {
    const Resampler = resampler.StreamingResampler(Sample);

    return struct {
        const Self = @This();

        to_model: Resampler = .{},
        to_host: Resampler = .{},
        host_rate: f64 = 0.0,
        model_rate: f64 = 0.0,
        latency_samples: u32 = 0,
        pending_model: [maximum_pending_model_frames]Sample = undefined,
        pending_model_count: usize = 0,
        configured: bool = false,

        pub fn init(config: Config) error{InvalidConfig}!Self {
            var self = Self{};
            try self.configure(config);
            return self;
        }

        pub fn configure(self: *Self, config: Config) error{InvalidConfig}!void {
            try config.validate();
            const first_stage_delay: f64 = resampler.right_radius;
            const second_stage_minimum_host_delay = resampler.right_radius * config.host_rate / config.model_rate;
            const latency = @ceil(first_stage_delay + second_stage_minimum_host_delay);
            if (latency > std.math.maxInt(u32)) return error.InvalidConfig;
            const second_stage_host_delay = latency - first_stage_delay;
            const second_stage_input_delay = second_stage_host_delay * config.model_rate / config.host_rate;

            try self.to_model.configure(.{
                .input_rate = config.host_rate,
                .output_rate = config.model_rate,
                .delay_input_samples = first_stage_delay,
            });
            try self.to_host.configure(.{
                .input_rate = config.model_rate,
                .output_rate = config.host_rate,
                .delay_input_samples = second_stage_input_delay,
            });
            self.host_rate = config.host_rate;
            self.model_rate = config.model_rate;
            self.latency_samples = @intFromFloat(latency);
            self.pending_model_count = 0;
            self.configured = true;
        }

        pub fn reset(self: *Self) void {
            self.to_model.reset();
            self.to_host.reset();
            self.pending_model_count = 0;
        }

        pub fn latencySamples(self: *const Self) u32 {
            return if (self.validState()) self.latency_samples else 0;
        }

        pub fn requiredModelCapacity(self: *const Self, host_frames: usize) error{ NotConfigured, InvalidState, CapacityOverflow }!usize {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            const scaled = @as(f64, @floatFromInt(host_frames)) * self.model_rate / self.host_rate;
            if (!std.math.isFinite(scaled) or scaled > @as(f64, @floatFromInt(std.math.maxInt(usize) - 2))) {
                return error.CapacityOverflow;
            }
            return @as(usize, @intFromFloat(@ceil(scaled))) + 2;
        }

        pub fn convertInput(self: *Self, input: []const Sample, model_output: []Sample) error{
            NotConfigured,
            InvalidState,
            CapacityOverflow,
            InsufficientModelCapacity,
            StreamTooLong,
        }!usize {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            const required = try self.requiredModelCapacity(input.len);
            if (model_output.len < required) return error.InsufficientModelCapacity;
            const result = self.to_model.process(input, model_output) catch |err| switch (err) {
                error.NotConfigured => return error.NotConfigured,
                error.InvalidState => return error.InvalidState,
                error.StreamTooLong => return error.StreamTooLong,
                error.Draining => unreachable,
            };
            if (result.consumed != input.len) return error.InsufficientModelCapacity;
            const remainder = self.to_model.process(&.{}, model_output[result.produced..]) catch |err| switch (err) {
                error.NotConfigured => return error.NotConfigured,
                error.InvalidState => return error.InvalidState,
                error.StreamTooLong => return error.StreamTooLong,
                error.Draining => unreachable,
            };
            return result.produced + remainder.produced;
        }

        pub fn convertOutput(self: *Self, model_input: []const Sample, host_output: []Sample) error{
            NotConfigured,
            InvalidState,
            OutputUnderflow,
            PendingOverflow,
            StreamTooLong,
        }!void {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            var produced: usize = 0;
            if (self.pending_model_count > 0) {
                const pending_result = self.to_host.process(self.pending_model[0..self.pending_model_count], host_output) catch |err| switch (err) {
                    error.NotConfigured => return error.NotConfigured,
                    error.InvalidState => return error.InvalidState,
                    error.StreamTooLong => return error.StreamTooLong,
                    error.Draining => unreachable,
                };
                produced += pending_result.produced;
                self.pending_model_count -= pending_result.consumed;
                if (self.pending_model_count > 0) {
                    std.mem.copyForwards(
                        Sample,
                        self.pending_model[0..self.pending_model_count],
                        self.pending_model[pending_result.consumed .. pending_result.consumed + self.pending_model_count],
                    );
                }
            }

            const result = self.to_host.process(model_input, host_output[produced..]) catch |err| switch (err) {
                error.NotConfigured => return error.NotConfigured,
                error.InvalidState => return error.InvalidState,
                error.StreamTooLong => return error.StreamTooLong,
                error.Draining => unreachable,
            };
            produced += result.produced;
            const remaining = model_input.len - result.consumed;
            if (remaining > self.pending_model.len - self.pending_model_count) return error.PendingOverflow;
            @memcpy(
                self.pending_model[self.pending_model_count .. self.pending_model_count + remaining],
                model_input[result.consumed..],
            );
            self.pending_model_count += remaining;

            if (produced < host_output.len) {
                const ready = self.to_host.process(&.{}, host_output[produced..]) catch |err| switch (err) {
                    error.NotConfigured => return error.NotConfigured,
                    error.InvalidState => return error.InvalidState,
                    error.StreamTooLong => return error.StreamTooLong,
                    error.Draining => unreachable,
                };
                produced += ready.produced;
            }
            if (produced != host_output.len) return error.OutputUnderflow;
        }

        pub fn validState(self: *const Self) bool {
            if (!self.configured or self.pending_model_count > self.pending_model.len) return false;
            const config = Config{ .host_rate = self.host_rate, .model_rate = self.model_rate };
            config.validate() catch return false;
            if (!self.to_model.validState() or !self.to_host.validState()) return false;
            if (self.to_model.input_rate != self.host_rate or self.to_model.output_rate != self.model_rate or
                self.to_host.input_rate != self.model_rate or self.to_host.output_rate != self.host_rate)
            {
                return false;
            }
            const radius: f64 = resampler.right_radius;
            const latency = @ceil(radius + radius * self.host_rate / self.model_rate);
            if (!std.math.isFinite(latency) or latency > std.math.maxInt(u32)) return false;
            return self.latency_samples == @as(u32, @intFromFloat(latency));
        }
    };
}

test "fixed-rate pipeline has exact integer round-trip latency" {
    const rates = [_]f64{ 44_100, 48_000, 88_200, 96_000 };
    for (rates) |host_rate| {
        const Pipeline = FixedRatePipeline(f64);
        var pipeline = try Pipeline.init(.{ .host_rate = host_rate, .model_rate = 48_000 });
        var input: [1024]f64 = @splat(0.0);
        input[0] = 1.0;
        var model: [40_000]f64 = undefined;
        var output: [1024]f64 = undefined;
        const model_frames = try pipeline.convertInput(&input, &model);
        try pipeline.convertOutput(model[0..model_frames], &output);

        var peak_index: usize = 0;
        for (output, 0..) |sample, index| {
            if (@abs(sample) > @abs(output[peak_index])) peak_index = index;
        }
        try std.testing.expectEqual(@as(usize, pipeline.latencySamples()), peak_index);
        try std.testing.expect(pipeline.latencySamples() >= resampler.right_radius);
    }
}

test "fixed-rate pipeline processes randomized host blocks without discontinuities" {
    const Pipeline = FixedRatePipeline(f64);
    const rates = [_]f64{ 44_100, 48_000, 88_200, 96_000 };
    for (rates) |host_rate| {
        var pipeline = try Pipeline.init(.{ .host_rate = host_rate, .model_rate = 48_000 });
        var random = std.Random.DefaultPrng.init(@as(u64, @intFromFloat(host_rate)));
        var input: [257]f64 = undefined;
        var output: [257]f64 = undefined;
        var model: [400]f64 = undefined;
        var absolute_frame: usize = 0;
        for (0..200) |_| {
            const frame_count = random.random().intRangeAtMost(usize, 1, input.len);
            for (input[0..frame_count], 0..) |*sample, frame| {
                const time = @as(f64, @floatFromInt(absolute_frame + frame)) / host_rate;
                const frequency = 80.0 + 8_000.0 * @as(f64, @floatFromInt(absolute_frame + frame)) / 51_400.0;
                sample.* = 0.5 * @sin(std.math.tau * frequency * time);
            }
            const model_frames = try pipeline.convertInput(input[0..frame_count], &model);
            try pipeline.convertOutput(model[0..model_frames], output[0..frame_count]);
            for (output[0..frame_count]) |sample| try std.testing.expect(std.math.isFinite(sample));
            absolute_frame += frame_count;
        }
    }
}

test "fixed-rate pipeline covers arbitrary rates through its ratio boundaries" {
    const Pipeline = FixedRatePipeline(f64);
    const rate_pairs = [_][2]f64{
        .{ 8_000, 64_000 },
        .{ 64_000, 8_000 },
        .{ 12_345.678, 48_000 },
        .{ 176_400, 22_050 },
        .{ 125_000, 1_000_000 },
        .{ 1_000_000, 125_000 },
    };
    for (rate_pairs, 0..) |rates, pair_index| {
        var pipeline = try Pipeline.init(.{ .host_rate = rates[0], .model_rate = rates[1] });
        var random = std.Random.DefaultPrng.init(0x5241_5445_5041_4952 + pair_index);
        var input: [257]f64 = undefined;
        var output: [257]f64 = undefined;
        var model: [2060]f64 = undefined;
        var absolute_frame: usize = 0;
        for (0..100) |_| {
            const frame_count = random.random().intRangeAtMost(usize, 1, input.len);
            for (input[0..frame_count], 0..) |*sample, frame| {
                const phase = @as(f64, @floatFromInt(absolute_frame + frame)) * 0.013;
                sample.* = 0.5 * @sin(phase);
            }
            const required = try pipeline.requiredModelCapacity(frame_count);
            try std.testing.expect(required <= model.len);
            const model_frames = try pipeline.convertInput(input[0..frame_count], &model);
            try pipeline.convertOutput(model[0..model_frames], output[0..frame_count]);
            for (output[0..frame_count]) |sample| try std.testing.expect(std.math.isFinite(sample));
            absolute_frame += frame_count;
        }
    }
}

test "fixed-rate pipeline reset reproduces the same block stream" {
    const Pipeline = FixedRatePipeline(f32);
    var pipeline = try Pipeline.init(.{ .host_rate = 44_100, .model_rate = 48_000 });
    var input: [128]f32 = undefined;
    for (&input, 0..) |*sample, index| sample.* = @sin(@as(f32, @floatFromInt(index)) * 0.09);
    var model: [160]f32 = undefined;
    var first: [128]f32 = undefined;
    const first_model_frames = try pipeline.convertInput(&input, &model);
    try pipeline.convertOutput(model[0..first_model_frames], &first);
    pipeline.reset();
    var second: [128]f32 = undefined;
    const second_model_frames = try pipeline.convertInput(&input, &model);
    try pipeline.convertOutput(model[0..second_model_frames], &second);
    try std.testing.expectEqual(first_model_frames, second_model_frames);
    try std.testing.expectEqualSlices(f32, &first, &second);
}

test "fixed-rate pipeline bounds ratios and caller scratch" {
    const Pipeline = FixedRatePipeline(f32);
    try std.testing.expectError(error.InvalidConfig, Pipeline.init(.{ .host_rate = 1_000, .model_rate = 96_000 }));
    var pipeline = try Pipeline.init(.{ .host_rate = 48_000, .model_rate = 48_000 });
    var short_model: [4]f32 = undefined;
    try std.testing.expectError(error.InsufficientModelCapacity, pipeline.convertInput(&.{ 1, 2, 3, 4 }, &short_model));
}

test "fixed-rate pipeline rejects malformed pending state and reconfiguration clears it" {
    const Pipeline = FixedRatePipeline(f64);
    const config = Config{ .host_rate = 48_000, .model_rate = 48_000 };
    var pipeline = try Pipeline.init(config);
    pipeline.pending_model_count = maximum_pending_model_frames + 1;
    try std.testing.expectError(error.InvalidState, pipeline.convertOutput(&.{}, &.{}));

    pipeline.reset();
    try std.testing.expectEqual(@as(usize, 0), pipeline.pending_model_count);
    pipeline.pending_model[0] = 0.25;
    pipeline.pending_model_count = 1;
    try pipeline.configure(config);
    try std.testing.expectEqual(@as(usize, 0), pipeline.pending_model_count);
}

test "fixed-rate pipeline rejects malformed public configuration state" {
    const Pipeline = FixedRatePipeline(f64);
    var pipeline = try Pipeline.init(.{ .host_rate = 48_000, .model_rate = 48_000 });
    try std.testing.expect(pipeline.validState());

    pipeline.host_rate = 0.0;
    try std.testing.expect(!pipeline.validState());
    try std.testing.expectEqual(@as(u32, 0), pipeline.latencySamples());
    try std.testing.expectError(error.InvalidState, pipeline.requiredModelCapacity(64));

    try pipeline.configure(.{ .host_rate = 48_000, .model_rate = 48_000 });
    pipeline.to_model.output_rate = 96_000;
    try std.testing.expect(!pipeline.validState());
    try std.testing.expectError(error.InvalidState, pipeline.convertInput(&.{}, &.{}));

    try pipeline.configure(.{ .host_rate = 48_000, .model_rate = 48_000 });
    pipeline.latency_samples +%= 1;
    try std.testing.expect(!pipeline.validState());
    try std.testing.expectError(error.InvalidState, pipeline.convertOutput(&.{}, &.{}));
}
