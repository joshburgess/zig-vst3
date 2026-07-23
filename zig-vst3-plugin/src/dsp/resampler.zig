const std = @import("std");

pub const tap_count = 32;
pub const phase_count = 256;
pub const left_radius = tap_count / 2 - 1;
pub const right_radius = tap_count / 2;

pub const Config = struct {
    input_rate: f64,
    output_rate: f64,
    delay_input_samples: f64 = right_radius,

    pub fn validate(self: Config) error{InvalidConfig}!void {
        if (!validRate(self.input_rate) or !validRate(self.output_rate) or
            !std.math.isFinite(self.delay_input_samples) or
            self.delay_input_samples < right_radius)
        {
            return error.InvalidConfig;
        }
    }
};

pub const ProcessResult = struct {
    consumed: usize,
    produced: usize,
};

pub const DrainResult = struct {
    produced: usize,
    finished: bool,
};

pub fn StreamingResampler(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64) @compileError("resampler sample type must be f32 or f64");

    return struct {
        const Self = @This();

        coefficients: [phase_count][tap_count]Sample = undefined,
        history: [tap_count]Sample = @splat(0.0),
        input_rate: f64 = 0.0,
        output_rate: f64 = 0.0,
        delay_input_samples: f64 = right_radius,
        input_count: u64 = 0,
        next_output_index: u64 = 0,
        drain_target: ?u64 = null,
        configured: bool = false,

        pub fn init(config: Config) error{InvalidConfig}!Self {
            var self = Self{};
            try self.configure(config);
            return self;
        }

        pub fn configure(self: *Self, config: Config) error{InvalidConfig}!void {
            try config.validate();
            self.input_rate = config.input_rate;
            self.output_rate = config.output_rate;
            self.delay_input_samples = config.delay_input_samples;
            self.buildCoefficients();
            self.configured = true;
            self.reset();
        }

        pub fn reset(self: *Self) void {
            self.history = @splat(0.0);
            self.input_count = 0;
            self.next_output_index = 0;
            self.drain_target = null;
        }

        pub fn latencyOutputSamples(self: *const Self) f64 {
            if (!self.validState()) return 0.0;
            return self.delay_input_samples * self.output_rate / self.input_rate;
        }

        pub fn process(self: *Self, input: []const Sample, output: []Sample) error{ NotConfigured, InvalidState, Draining, StreamTooLong }!ProcessResult {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            if (self.drain_target != null) return error.Draining;

            var consumed: usize = 0;
            var produced: usize = 0;
            while (produced < output.len) {
                produced += self.produceReady(output[produced..]);
                if (produced == output.len or consumed == input.len) break;
                try self.push(input[consumed]);
                consumed += 1;
            }
            return .{ .consumed = consumed, .produced = produced };
        }

        pub fn beginDrain(self: *Self) error{ NotConfigured, InvalidState }!void {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            if (self.drain_target != null) return;
            if (self.input_count == 0) {
                self.drain_target = 0;
                return;
            }
            const last_input: f64 = @floatFromInt(self.input_count - 1);
            const last_output_time = last_input + self.delay_input_samples + right_radius;
            const last_output_index = @floor(last_output_time * self.output_rate / self.input_rate);
            self.drain_target = @intFromFloat(last_output_index + 1.0);
        }

        pub fn drain(self: *Self, output: []Sample) error{ NotConfigured, InvalidState, DrainNotStarted, StreamTooLong }!DrainResult {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            const target = self.drain_target orelse return error.DrainNotStarted;
            var produced: usize = 0;
            while (produced < output.len and self.next_output_index < target) {
                const ready = self.produceReadyBounded(output[produced..], target);
                produced += ready;
                if (produced == output.len or self.next_output_index >= target) break;
                if (ready == 0) try self.push(0.0);
            }
            return .{ .produced = produced, .finished = self.next_output_index >= target };
        }

        pub fn validState(self: *const Self) bool {
            if (!self.configured) return false;
            (Config{
                .input_rate = self.input_rate,
                .output_rate = self.output_rate,
                .delay_input_samples = self.delay_input_samples,
            }).validate() catch return false;
            return true;
        }

        fn push(self: *Self, sample: Sample) error{StreamTooLong}!void {
            if (self.input_count == std.math.maxInt(u64)) return error.StreamTooLong;
            self.history[self.input_count % tap_count] = if (std.math.isFinite(sample)) sample else 0.0;
            self.input_count += 1;
        }

        fn produceReady(self: *Self, output: []Sample) usize {
            return self.produceReadyBounded(output, std.math.maxInt(u64));
        }

        fn produceReadyBounded(self: *Self, output: []Sample, limit: u64) usize {
            var produced: usize = 0;
            while (produced < output.len and self.next_output_index < limit and self.outputReady()) {
                output[produced] = self.renderNext();
                produced += 1;
            }
            return produced;
        }

        fn outputReady(self: *const Self) bool {
            if (self.input_count == 0) return false;
            const center = self.outputInputTime(self.next_output_index) - self.delay_input_samples;
            const base: i64 = @intFromFloat(@floor(center));
            const maximum_source_index = base + right_radius;
            const latest_input: i64 = @intCast(self.input_count - 1);
            return maximum_source_index <= latest_input;
        }

        fn renderNext(self: *Self) Sample {
            const center = self.outputInputTime(self.next_output_index) - self.delay_input_samples;
            const base_floor = @floor(center);
            const base: i64 = @intFromFloat(base_floor);
            const fraction = center - base_floor;
            const phase_position = fraction * (phase_count - 1);
            const phase: usize = @intFromFloat(@round(phase_position));
            var result: Sample = 0.0;
            for (0..tap_count) |tap| {
                const offset: i64 = @as(i64, @intCast(tap)) - left_radius;
                result += self.sampleAt(base + offset) * self.coefficients[phase][tap];
            }
            self.next_output_index += 1;
            return if (std.math.isFinite(result)) result else 0.0;
        }

        fn sampleAt(self: *const Self, index: i64) Sample {
            if (index < 0) return 0.0;
            const source_index: u64 = @intCast(index);
            if (source_index >= self.input_count) return 0.0;
            const oldest = self.input_count -| tap_count;
            if (source_index < oldest) return 0.0;
            return self.history[source_index % tap_count];
        }

        fn outputInputTime(self: *const Self, output_index: u64) f64 {
            return @as(f64, @floatFromInt(output_index)) * self.input_rate / self.output_rate;
        }

        fn buildCoefficients(self: *Self) void {
            const rate_ratio = self.output_rate / self.input_rate;
            const cutoff = 0.94 * @min(1.0, rate_ratio);
            for (0..phase_count) |phase| {
                const fraction = @as(f64, @floatFromInt(phase)) / (phase_count - 1);
                var sum: f64 = 0.0;
                for (0..tap_count) |tap| {
                    const offset = @as(f64, @floatFromInt(tap)) - left_radius;
                    const distance = fraction - offset;
                    const coefficient = cutoff * sinc(cutoff * distance) * blackman(distance / right_radius);
                    self.coefficients[phase][tap] = @floatCast(coefficient);
                    sum += coefficient;
                }
                const inverse_sum = 1.0 / sum;
                for (0..tap_count) |tap| {
                    self.coefficients[phase][tap] *= @floatCast(inverse_sum);
                }
            }
        }
    };
}

fn validRate(rate: f64) bool {
    return std.math.isFinite(rate) and rate >= 1_000.0 and rate <= 2_000_000.0;
}

fn sinc(value: f64) f64 {
    if (@abs(value) < 1.0e-12) return 1.0;
    const angle = std.math.pi * value;
    return @sin(angle) / angle;
}

fn blackman(normalized_distance: f64) f64 {
    if (@abs(normalized_distance) > 1.0) return 0.0;
    return 0.42 + 0.5 * @cos(std.math.pi * normalized_distance) +
        0.08 * @cos(std.math.tau * normalized_distance);
}

test "streaming resampler reports and renders its causal impulse latency" {
    const Resampler = StreamingResampler(f64);
    var resampler = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    var input: [64]f64 = @splat(0.0);
    input[0] = 1.0;
    var output: [64]f64 = undefined;
    const result = try resampler.process(&input, &output);
    try std.testing.expectEqual(input.len, result.consumed);
    try std.testing.expectEqual(output.len, result.produced);
    try std.testing.expectEqual(@as(f64, right_radius), resampler.latencyOutputSamples());

    var peak_index: usize = 0;
    for (output, 0..) |sample, index| {
        if (@abs(sample) > @abs(output[peak_index])) peak_index = index;
    }
    try std.testing.expectEqual(@as(usize, right_radius), peak_index);
    try std.testing.expectApproxEqAbs(@as(f64, 0.94), output[peak_index], 0.01);
}

test "streaming resampler is independent of input block boundaries" {
    const Resampler = StreamingResampler(f64);
    var input: [2048]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        const time = @as(f64, @floatFromInt(index)) / 44_100.0;
        sample.* = 0.6 * @sin(std.math.tau * 997.0 * time) + 0.2 * @sin(std.math.tau * 7_123.0 * time);
    }

    var contiguous = try Resampler.init(.{ .input_rate = 44_100, .output_rate = 48_000 });
    var expected: [2300]f64 = undefined;
    const contiguous_result = try contiguous.process(&input, &expected);
    try std.testing.expectEqual(input.len, contiguous_result.consumed);

    var blocked = try Resampler.init(.{ .input_rate = 44_100, .output_rate = 48_000 });
    var actual: [2300]f64 = undefined;
    var input_offset: usize = 0;
    var output_offset: usize = 0;
    var random = std.Random.DefaultPrng.init(0x9f17_a4c2);
    while (input_offset < input.len) {
        const input_count = @min(input.len - input_offset, random.random().intRangeAtMost(usize, 1, 37));
        const output_count = @min(actual.len - output_offset, random.random().intRangeAtMost(usize, 1, 41));
        const result = try blocked.process(
            input[input_offset .. input_offset + input_count],
            actual[output_offset .. output_offset + output_count],
        );
        input_offset += result.consumed;
        output_offset += result.produced;
    }
    while (output_offset < contiguous_result.produced) {
        const result = try blocked.process(&.{}, actual[output_offset..]);
        if (result.produced == 0) break;
        output_offset += result.produced;
    }
    try std.testing.expectEqual(contiguous_result.produced, output_offset);
    try std.testing.expectEqualSlices(f64, expected[0..contiguous_result.produced], actual[0..output_offset]);
}

test "streaming resampler preserves common-rate passband tones" {
    const pairs = [_][2]f64{
        .{ 44_100, 48_000 },
        .{ 48_000, 44_100 },
        .{ 88_200, 48_000 },
        .{ 96_000, 48_000 },
        .{ 48_000, 96_000 },
    };
    for (pairs) |rates| {
        const Resampler = StreamingResampler(f64);
        var resampler = try Resampler.init(.{ .input_rate = rates[0], .output_rate = rates[1] });
        var input: [4096]f64 = undefined;
        for (&input, 0..) |*sample, index| {
            sample.* = @sin(std.math.tau * 1_000.0 * @as(f64, @floatFromInt(index)) / rates[0]);
        }
        var output: [9000]f64 = undefined;
        const result = try resampler.process(&input, &output);
        try std.testing.expectEqual(input.len, result.consumed);
        const skip = @as(usize, @intFromFloat(@ceil(resampler.latencyOutputSamples()))) + 64;
        var sum_squares: f64 = 0.0;
        for (output[skip..result.produced]) |sample| sum_squares += sample * sample;
        const rms = @sqrt(sum_squares / @as(f64, @floatFromInt(result.produced - skip)));
        try std.testing.expectApproxEqAbs(1.0 / @sqrt(2.0), rms, 0.015);
    }
}

test "streaming resampler attenuates frequencies above the destination Nyquist limit" {
    const Resampler = StreamingResampler(f64);
    var resampler = try Resampler.init(.{ .input_rate = 96_000, .output_rate = 48_000 });
    var input: [8192]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @sin(std.math.tau * 30_000.0 * @as(f64, @floatFromInt(index)) / 96_000.0);
    }
    var output: [4200]f64 = undefined;
    const result = try resampler.process(&input, &output);
    var sum_squares: f64 = 0.0;
    for (output[128..result.produced]) |sample| sum_squares += sample * sample;
    const rms = @sqrt(sum_squares / @as(f64, @floatFromInt(result.produced - 128)));
    try std.testing.expect(rms < 0.015);
}

test "streaming resampler reset and drain are deterministic" {
    const Resampler = StreamingResampler(f32);
    var resampler = try Resampler.init(.{ .input_rate = 96_000, .output_rate = 48_000 });
    var input: [127]f32 = undefined;
    for (&input, 0..) |*sample, index| sample.* = @sin(@as(f32, @floatFromInt(index)) * 0.13);
    var first: [256]f32 = undefined;
    const first_result = try resampler.process(&input, &first);
    resampler.reset();
    var second: [256]f32 = undefined;
    const second_result = try resampler.process(&input, &second);
    try std.testing.expectEqual(first_result, second_result);
    try std.testing.expectEqualSlices(f32, first[0..first_result.produced], second[0..second_result.produced]);

    try resampler.beginDrain();
    var tail: [128]f32 = undefined;
    const drain_result = try resampler.drain(&tail);
    try std.testing.expect(drain_result.finished);
    try std.testing.expect(drain_result.produced > 0);
    const finished = try resampler.drain(&tail);
    try std.testing.expect(finished.finished);
    try std.testing.expectEqual(@as(usize, 0), finished.produced);
}

test "streaming resampler rejects invalid configuration and state transitions" {
    const Resampler = StreamingResampler(f32);
    try std.testing.expectError(error.InvalidConfig, Resampler.init(.{ .input_rate = 0, .output_rate = 48_000 }));
    try std.testing.expectError(error.InvalidConfig, Resampler.init(.{ .input_rate = 48_000, .output_rate = std.math.nan(f64) }));
    try std.testing.expectError(error.InvalidConfig, Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000, .delay_input_samples = right_radius - 0.01 }));
    var unconfigured = Resampler{};
    var output: [4]f32 = undefined;
    try std.testing.expectError(error.NotConfigured, unconfigured.process(&.{1.0}, &output));
    try std.testing.expectError(error.NotConfigured, unconfigured.beginDrain());

    var resampler = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    _ = try resampler.process(&.{1.0}, &output);
    try resampler.beginDrain();
    try std.testing.expectError(error.Draining, resampler.process(&.{1.0}, &output));

    var malformed = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    malformed.output_rate = 0.0;
    try std.testing.expect(!malformed.validState());
    try std.testing.expectEqual(@as(f64, 0.0), malformed.latencyOutputSamples());
    try std.testing.expectError(error.InvalidState, malformed.process(&.{1.0}, &output));
    try std.testing.expectError(error.InvalidState, malformed.beginDrain());
    malformed.drain_target = 1;
    try std.testing.expectError(error.InvalidState, malformed.drain(&output));
}
