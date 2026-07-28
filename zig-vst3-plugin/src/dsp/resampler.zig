const std = @import("std");
const kernel_dispatch = @import("kernel_dispatch.zig");

pub const tap_count = 32;
pub const phase_count = 256;
pub const left_radius = tap_count / 2 - 1;
pub const right_radius = tap_count / 2;
pub const maximum_timeline_index: u64 = std.math.maxInt(i64);
pub const maximum_rate_correction_ppm = 2_000.0;

pub const Config = struct {
    input_rate: f64,
    output_rate: f64,
    delay_input_samples: f64 = right_radius,

    pub fn validate(self: Config) error{InvalidResamplerConfig}!void {
        if (!validRate(self.input_rate) or !validRate(self.output_rate) or
            !std.math.isFinite(self.delay_input_samples) or
            self.delay_input_samples < right_radius)
        {
            return error.InvalidResamplerConfig;
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

        coefficients: [phase_count][tap_count]Sample = @splat(@splat(0.0)),
        history: [tap_count * 2]Sample = @splat(0.0),
        input_rate: f64 = 0.0,
        output_rate: f64 = 0.0,
        delay_input_samples: f64 = right_radius,
        input_count: u64 = 0,
        next_output_index: u64 = 0,
        next_input_position: f64 = 0.0,
        rate_correction_ppm: f64 = 0.0,
        input_step: f64 = 0.0,
        drain_target: ?u64 = null,
        backend: kernel_dispatch.Backend = .scalar,
        configured: bool = false,

        pub fn init(config: Config) error{InvalidResamplerConfig}!Self {
            var self = Self{};
            try self.configure(config);
            return self;
        }

        pub fn initBackend(
            config: Config,
            backend: kernel_dispatch.Backend,
        ) error{InvalidResamplerConfig}!Self {
            var self = Self{};
            try self.configureBackend(config, backend);
            return self;
        }

        pub fn configure(self: *Self, config: Config) error{InvalidResamplerConfig}!void {
            return self.configureBackend(
                config,
                kernel_dispatch.preferred(kernel_dispatch.detectNative()),
            );
        }

        pub fn configureBackend(
            self: *Self,
            config: Config,
            backend: kernel_dispatch.Backend,
        ) error{InvalidResamplerConfig}!void {
            try config.validate();
            self.input_rate = config.input_rate;
            self.output_rate = config.output_rate;
            self.delay_input_samples = config.delay_input_samples;
            self.backend = backend;
            self.rate_correction_ppm = 0.0;
            self.input_step =
                config.input_rate / config.output_rate;
            self.buildCoefficients();
            self.configured = true;
            self.reset();
        }

        pub fn reset(self: *Self) void {
            self.history = @splat(0.0);
            self.input_count = 0;
            self.next_output_index = 0;
            self.next_input_position = 0.0;
            self.drain_target = null;
        }

        pub fn latencyOutputSamples(self: *const Self) f64 {
            if (!self.validState()) return 0.0;
            return self.delay_input_samples / self.inputStep();
        }

        /// Returns the exact additional input needed to make `output_count`
        /// consecutive output samples ready at the current phase.
        pub fn requiredInputSamples(
            self: *const Self,
            output_count: usize,
        ) error{
            NotConfigured,
            InvalidState,
            Draining,
            StreamTooLong,
            CapacityOverflow,
        }!usize {
            return self.requiredInputSamplesAtCorrection(
                output_count,
                self.rate_correction_ppm,
            ) catch |err| switch (err) {
                error.InvalidRateCorrection => unreachable,
                else => |forwarded| return forwarded,
            };
        }

        /// Preflights input demand for a correction without changing state.
        pub fn requiredInputSamplesAtCorrection(
            self: *const Self,
            output_count: usize,
            correction_ppm: f64,
        ) error{
            NotConfigured,
            InvalidState,
            Draining,
            InvalidRateCorrection,
            StreamTooLong,
            CapacityOverflow,
        }!usize {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            if (self.drain_target != null) return error.Draining;
            if (!validRateCorrection(correction_ppm))
                return error.InvalidRateCorrection;
            if (output_count == 0) return 0;
            const output_count_u64 = std.math.cast(
                u64,
                output_count,
            ) orelse return error.CapacityOverflow;
            if (output_count_u64 >=
                maximum_timeline_index - self.next_output_index)
                return error.StreamTooLong;

            const position_delta =
                @as(f64, @floatFromInt(output_count - 1)) *
                self.correctedInputStep(correction_ppm);
            const final_position =
                self.next_input_position + position_delta;
            const center = final_position - self.delay_input_samples;
            const minimum: f64 =
                @floatFromInt(std.math.minInt(i64) + left_radius);
            const maximum: f64 =
                @floatFromInt(std.math.maxInt(i64) - right_radius);
            if (!std.math.isFinite(position_delta) or
                !std.math.isFinite(final_position) or
                center < minimum or
                center > maximum)
                return error.StreamTooLong;
            const base: i64 = @intFromFloat(@floor(center));
            const maximum_source = base + right_radius;
            const required_total: u64 = if (maximum_source < 0)
                1
            else
                @as(u64, @intCast(maximum_source)) + 1;
            if (required_total > maximum_timeline_index)
                return error.StreamTooLong;
            if (required_total <= self.input_count) return 0;
            return std.math.cast(
                usize,
                required_total - self.input_count,
            ) orelse error.CapacityOverflow;
        }

        /// Adjusts the consumption rate without resetting history or phase.
        pub fn setRateCorrectionPpm(
            self: *Self,
            correction_ppm: f64,
        ) error{
            NotConfigured,
            InvalidState,
            Draining,
            InvalidRateCorrection,
        }!void {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            if (self.drain_target != null) return error.Draining;
            if (!validRateCorrection(correction_ppm))
                return error.InvalidRateCorrection;
            const previous = self.rate_correction_ppm;
            const previous_step = self.input_step;
            self.rate_correction_ppm = correction_ppm;
            self.input_step = self.correctedInputStep(
                correction_ppm,
            );
            if (!self.validState()) {
                self.rate_correction_ppm = previous;
                self.input_step = previous_step;
                return error.InvalidState;
            }
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

        pub fn beginDrain(self: *Self) error{ NotConfigured, InvalidState, StreamTooLong }!void {
            if (!self.configured) return error.NotConfigured;
            if (!self.validState()) return error.InvalidState;
            if (self.drain_target != null) return;
            if (self.input_count == 0) {
                self.drain_target = self.next_output_index;
                return;
            }
            const last_input: f64 = @floatFromInt(self.input_count - 1);
            const last_output_position =
                last_input + self.delay_input_samples + right_radius;
            if (!std.math.isFinite(last_output_position))
                return error.StreamTooLong;
            const remaining_outputs = if (self.next_input_position >
                last_output_position)
                0.0
            else
                @floor(
                    (last_output_position - self.next_input_position) /
                        self.inputStep(),
                ) + 1.0;
            if (!std.math.isFinite(remaining_outputs) or
                remaining_outputs < 0.0 or
                remaining_outputs >
                    @as(f64, @floatFromInt(
                        maximum_timeline_index -
                            self.next_output_index,
                    )))
                return error.StreamTooLong;
            self.drain_target = self.next_output_index +
                @as(u64, @intFromFloat(remaining_outputs));
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
            if (self.input_count > maximum_timeline_index or
                self.next_output_index > maximum_timeline_index or
                (self.next_output_index == maximum_timeline_index and
                    self.drain_target != maximum_timeline_index) or
                !validRateCorrection(self.rate_correction_ppm) or
                self.input_step != self.correctedInputStep(
                    self.rate_correction_ppm,
                ) or
                !self.validInputPosition())
            {
                return false;
            }
            if (self.drain_target) |target| {
                if (target > maximum_timeline_index or self.next_output_index > target) return false;
            }
            return true;
        }

        fn push(self: *Self, sample: Sample) error{StreamTooLong}!void {
            if (self.input_count == maximum_timeline_index) return error.StreamTooLong;
            const history_index: usize = @intCast(self.input_count % tap_count);
            const finite_sample = if (std.math.isFinite(sample)) sample else 0.0;
            self.history[history_index] = finite_sample;
            self.history[history_index + tap_count] = finite_sample;
            self.input_count += 1;
        }

        fn produceReady(self: *Self, output: []Sample) usize {
            return self.produceReadyBounded(output, std.math.maxInt(u64));
        }

        fn produceReadyBounded(self: *Self, output: []Sample, limit: u64) usize {
            var produced: usize = 0;
            while (produced < output.len and
                self.next_output_index < limit and
                self.next_output_index < maximum_timeline_index and
                self.outputReady())
            {
                output[produced] = self.renderNext();
                produced += 1;
            }
            return produced;
        }

        fn outputReady(self: *const Self) bool {
            if (self.input_count == 0) return false;
            const center =
                self.next_input_position - self.delay_input_samples;
            const minimum: f64 =
                @floatFromInt(std.math.minInt(i64) + left_radius);
            const maximum: f64 =
                @floatFromInt(std.math.maxInt(i64) - right_radius);
            if (!std.math.isFinite(center) or
                center < minimum or
                center > maximum)
                return false;
            const base: i64 = @intFromFloat(@floor(center));
            const maximum_source_index = base + right_radius;
            const latest_input: i64 = @intCast(self.input_count - 1);
            return maximum_source_index <= latest_input;
        }

        fn renderNext(self: *Self) Sample {
            const center =
                self.next_input_position - self.delay_input_samples;
            const base_floor = @floor(center);
            const base: i64 = @intFromFloat(base_floor);
            const fraction = center - base_floor;
            const phase_position = fraction * (phase_count - 1);
            const phase: usize = @intFromFloat(@round(phase_position));
            const first_index = base - left_radius;
            const result = if (self.historyWindow(first_index)) |samples|
                dotProduct(
                    Sample,
                    self.backend,
                    samples,
                    &self.coefficients[phase],
                )
            else
                self.renderStartup(base, phase);
            self.next_output_index += 1;
            self.next_input_position += self.inputStep();
            return if (std.math.isFinite(result)) result else 0.0;
        }

        fn renderStartup(self: *const Self, base: i64, phase: usize) Sample {
            var result: Sample = 0.0;
            for (0..tap_count) |tap| {
                const offset: i64 = @as(i64, @intCast(tap)) - left_radius;
                result += self.sampleAt(base + offset) *
                    self.coefficients[phase][tap];
            }
            return result;
        }

        fn historyWindow(
            self: *const Self,
            first_index: i64,
        ) ?[]const Sample {
            if (first_index < 0) return null;
            const source_index: u64 = @intCast(first_index);
            const oldest = self.input_count -| tap_count;
            if (source_index < oldest or
                source_index > self.input_count or
                self.input_count - source_index < tap_count)
            {
                return null;
            }
            const history_index: usize = @intCast(source_index % tap_count);
            return self.history[history_index .. history_index + tap_count];
        }

        fn sampleAt(self: *const Self, index: i64) Sample {
            if (index < 0) return 0.0;
            const source_index: u64 = @intCast(index);
            if (source_index >= self.input_count) return 0.0;
            const oldest = self.input_count -| tap_count;
            if (source_index < oldest) return 0.0;
            return self.history[source_index % tap_count];
        }

        fn inputStep(self: *const Self) f64 {
            return self.input_step;
        }

        fn correctedInputStep(
            self: *const Self,
            correction_ppm: f64,
        ) f64 {
            return self.input_rate / self.output_rate *
                (1.0 + correction_ppm / 1_000_000.0);
        }

        fn validInputPosition(self: *const Self) bool {
            if (!std.math.isFinite(self.next_input_position) or
                self.next_input_position < 0.0)
                return false;
            const minimum: f64 = @floatFromInt(std.math.minInt(i64) + left_radius);
            const maximum: f64 = @floatFromInt(std.math.maxInt(i64) - right_radius);
            const center =
                self.next_input_position - self.delay_input_samples;
            if (center < minimum or center > maximum)
                return false;
            const step = self.inputStep();
            if (!std.math.isFinite(step) or step <= 0.0)
                return false;
            const maximum_ready_position =
                @as(f64, @floatFromInt(self.input_count)) +
                self.delay_input_samples + right_radius +
                self.input_rate / self.output_rate *
                    (1.0 +
                        maximum_rate_correction_ppm /
                            1_000_000.0);
            return std.math.isFinite(maximum_ready_position) and
                self.next_input_position <= maximum_ready_position and
                (self.next_output_index != 0 or
                    self.next_input_position == 0.0);
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

fn dotProduct(
    comptime Sample: type,
    backend: kernel_dispatch.Backend,
    left: []const Sample,
    right: []const Sample,
) Sample {
    return switch (backend) {
        .scalar => dotProductScalar(Sample, left, right),
        .neon => dotProductVector(
            Sample,
            16 / @sizeOf(Sample),
            left,
            right,
        ),
        .avx2 => dotProductVector(
            Sample,
            32 / @sizeOf(Sample),
            left,
            right,
        ),
    };
}

fn dotProductScalar(
    comptime Sample: type,
    left: []const Sample,
    right: []const Sample,
) Sample {
    var result: Sample = 0.0;
    for (left, right) |left_sample, right_sample|
        result += left_sample * right_sample;
    return result;
}

fn dotProductVector(
    comptime Sample: type,
    comptime lane_count: usize,
    left: []const Sample,
    right: []const Sample,
) Sample {
    const Vector = @Vector(lane_count, Sample);
    var accumulator: Vector = @splat(0.0);
    var offset: usize = 0;
    while (offset + lane_count <= left.len) : (offset += lane_count) {
        const left_vector: *align(@alignOf(Sample)) const Vector =
            @ptrCast(left[offset..].ptr);
        const right_vector: *align(@alignOf(Sample)) const Vector =
            @ptrCast(right[offset..].ptr);
        accumulator += left_vector.* * right_vector.*;
    }
    return @reduce(.Add, accumulator) +
        dotProductScalar(Sample, left[offset..], right[offset..]);
}

fn validRate(rate: f64) bool {
    return std.math.isFinite(rate) and rate >= 1_000.0 and rate <= 2_000_000.0;
}

fn validRateCorrection(correction_ppm: f64) bool {
    return std.math.isFinite(correction_ppm) and
        @abs(correction_ppm) <= maximum_rate_correction_ppm;
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

test "streaming resampler reports exact phase-dependent input demand" {
    const rate_pairs = [_][2]f64{
        .{ 44_100, 48_000 },
        .{ 48_000, 44_100 },
        .{ 96_000, 48_000 },
        .{ 48_000, 96_000 },
    };
    for (rate_pairs) |rates| {
        const Resampler = StreamingResampler(f64);
        var stream = try Resampler.init(.{
            .input_rate = rates[0],
            .output_rate = rates[1],
        });
        try stream.setRateCorrectionPpm(875.0);
        var prefix: [73]f64 = @splat(0.25);
        var prefix_output: [19]f64 = undefined;
        _ = try stream.process(&prefix, &prefix_output);

        for ([_]usize{ 1, 2, 17, 64, 127 }) |output_count| {
            var trial = stream;
            const required =
                try trial.requiredInputSamples(output_count);
            var input: [300]f64 = @splat(0.5);
            var output: [127]f64 = undefined;
            try std.testing.expect(required <= input.len);
            const result = try trial.process(
                input[0..required],
                output[0..output_count],
            );
            try std.testing.expectEqual(required, result.consumed);
            try std.testing.expectEqual(
                output_count,
                result.produced,
            );

            if (required != 0) {
                var insufficient = stream;
                const short_result = try insufficient.process(
                    input[0 .. required - 1],
                    output[0..output_count],
                );
                try std.testing.expect(
                    short_result.produced < output_count,
                );
            }
        }
    }

    const Resampler = StreamingResampler(f32);
    var unconfigured = Resampler{};
    try std.testing.expectError(
        error.NotConfigured,
        unconfigured.requiredInputSamples(1),
    );
    var malformed = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    malformed.input_step = 0.0;
    try std.testing.expectError(
        error.InvalidState,
        malformed.requiredInputSamples(1),
    );
    try malformed.configure(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    try malformed.beginDrain();
    try std.testing.expectError(
        error.Draining,
        malformed.requiredInputSamples(1),
    );
}

test "streaming resampler rejects malformed public timeline state" {
    const Resampler = StreamingResampler(f64);
    var resampler = try Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000 });
    try std.testing.expect(resampler.validState());

    resampler.input_count = maximum_timeline_index + 1;
    try std.testing.expect(!resampler.validState());
    try std.testing.expectError(error.InvalidState, resampler.process(&.{}, &.{}));

    try resampler.configure(.{ .input_rate = 2_000_000, .output_rate = 1_000 });
    resampler.next_output_index = maximum_timeline_index;
    try std.testing.expect(!resampler.validState());
    try std.testing.expectEqual(@as(f64, 0.0), resampler.latencyOutputSamples());

    try resampler.configure(.{ .input_rate = 48_000, .output_rate = 48_000 });
    resampler.drain_target = 4;
    resampler.next_output_index = 5;
    try std.testing.expect(!resampler.validState());
    try std.testing.expectError(error.InvalidState, resampler.drain(&.{}));
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
    try std.testing.expectError(error.InvalidResamplerConfig, Resampler.init(.{ .input_rate = 0, .output_rate = 48_000 }));
    try std.testing.expectError(error.InvalidResamplerConfig, Resampler.init(.{ .input_rate = 48_000, .output_rate = std.math.nan(f64) }));
    try std.testing.expectError(error.InvalidResamplerConfig, Resampler.init(.{ .input_rate = 48_000, .output_rate = 48_000, .delay_input_samples = right_radius - 0.01 }));
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

    try malformed.configure(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    malformed.input_step = 0.0;
    try std.testing.expect(!malformed.validState());
    try std.testing.expectError(
        error.InvalidState,
        malformed.setRateCorrectionPpm(1.0),
    );
}

test "streaming resampler changes rate correction without resetting phase" {
    const Resampler = StreamingResampler(f64);
    var resampler = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var input: [512]f64 = undefined;
    for (&input, 0..) |*sample, index|
        sample.* = @sin(@as(f64, @floatFromInt(index)) * 0.07);
    var output: [128]f64 = undefined;
    const first = try resampler.process(&input, &output);
    try std.testing.expectEqual(output.len, first.produced);

    const input_count = resampler.input_count;
    const output_index = resampler.next_output_index;
    const input_position = resampler.next_input_position;
    const history = resampler.history;
    try resampler.setRateCorrectionPpm(750.0);
    try std.testing.expectEqual(input_count, resampler.input_count);
    try std.testing.expectEqual(output_index, resampler.next_output_index);
    try std.testing.expectEqual(
        input_position,
        resampler.next_input_position,
    );
    try std.testing.expectEqualSlices(
        f64,
        &history,
        &resampler.history,
    );
    try std.testing.expectApproxEqAbs(
        resampler.input_rate / resampler.output_rate * 1.00075,
        resampler.inputStep(),
        1.0e-15,
    );

    const correction_before = resampler.rate_correction_ppm;
    try std.testing.expectError(
        error.InvalidRateCorrection,
        resampler.setRateCorrectionPpm(
            maximum_rate_correction_ppm + 0.001,
        ),
    );
    try std.testing.expectError(
        error.InvalidRateCorrection,
        resampler.setRateCorrectionPpm(std.math.nan(f64)),
    );
    try std.testing.expectEqual(
        correction_before,
        resampler.rate_correction_ppm,
    );
    var frontier = resampler;
    try frontier.setRateCorrectionPpm(
        maximum_rate_correction_ppm,
    );
    _ = try frontier.process(
        input[first.consumed..],
        &output,
    );
    try frontier.setRateCorrectionPpm(
        -maximum_rate_correction_ppm,
    );
    try std.testing.expect(frontier.validState());

    resampler.reset();
    try std.testing.expectEqual(
        correction_before,
        resampler.rate_correction_ppm,
    );
    try std.testing.expectEqual(@as(u64, 0), resampler.input_count);
    try std.testing.expectEqual(@as(u64, 0), resampler.next_output_index);
    try std.testing.expectEqual(
        @as(f64, 0.0),
        resampler.next_input_position,
    );
    try resampler.configure(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    try std.testing.expectEqual(
        @as(f64, 0.0),
        resampler.rate_correction_ppm,
    );
    _ = try resampler.process(&input, &output);
    try resampler.beginDrain();
    try std.testing.expectError(
        error.Draining,
        resampler.setRateCorrectionPpm(1.0),
    );
}

test "rate-corrected resampling is independent of input partitioning" {
    const Resampler = StreamingResampler(f64);
    var input: [4096]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        const position: f64 = @floatFromInt(index);
        sample.* = 0.6 * @sin(position * 0.031) +
            0.2 * @cos(position * 0.137);
    }
    var contiguous = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var partitioned = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var expected: [2048]f64 = undefined;
    var actual: [2048]f64 = undefined;
    const contiguous_consumed = try renderCorrectionSchedule(
        f64,
        &contiguous,
        &input,
        &expected,
        input.len,
        -1_250.0,
    );
    const partitioned_consumed = try renderCorrectionSchedule(
        f64,
        &partitioned,
        &input,
        &actual,
        37,
        -1_250.0,
    );
    try std.testing.expectEqual(
        contiguous_consumed,
        partitioned_consumed,
    );
    try std.testing.expectEqualSlices(f64, &expected, &actual);
    try std.testing.expectEqual(
        contiguous.next_input_position,
        partitioned.next_input_position,
    );
}

test "rate correction changes long-run input consumption by bounded ppm" {
    const Resampler = StreamingResampler(f64);
    var input: [12_000]f64 = @splat(0.25);
    var nominal_output: [10_000]f64 = undefined;
    var fast_output: [10_000]f64 = undefined;
    var slow_output: [10_000]f64 = undefined;
    var nominal = try Resampler.init(.{
        .input_rate = 48_000,
        .output_rate = 48_000,
    });
    var fast = nominal;
    var slow = nominal;
    try fast.setRateCorrectionPpm(1_000.0);
    try slow.setRateCorrectionPpm(-1_000.0);
    const nominal_result = try nominal.process(
        &input,
        &nominal_output,
    );
    const fast_result = try fast.process(&input, &fast_output);
    const slow_result = try slow.process(&input, &slow_output);
    try std.testing.expectEqual(
        nominal_output.len,
        nominal_result.produced,
    );
    try std.testing.expectEqual(
        fast_output.len,
        fast_result.produced,
    );
    try std.testing.expectEqual(
        slow_output.len,
        slow_result.produced,
    );
    try std.testing.expect(fast_result.consumed >
        nominal_result.consumed);
    try std.testing.expect(slow_result.consumed <
        nominal_result.consumed);
    try std.testing.expectApproxEqAbs(
        @as(f64, @floatFromInt(fast_output.len)) * 1.001,
        fast.next_input_position,
        5.0e-9,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, @floatFromInt(slow_output.len)) * 0.999,
        slow.next_input_position,
        5.0e-9,
    );
}

test "streaming resampler backends preserve streaming results across ring wraps" {
    try expectBackendParity(f32, 2.0e-6);
    try expectBackendParity(f64, 2.0e-14);
}

fn renderCorrectionSchedule(
    comptime Sample: type,
    resampler: *StreamingResampler(Sample),
    input: []const Sample,
    output: []Sample,
    input_chunk_size: usize,
    second_half_correction_ppm: f64,
) !usize {
    const change_output = output.len / 2;
    var input_offset: usize = 0;
    var output_offset: usize = 0;
    while (output_offset < change_output) {
        const input_end = @min(
            input.len,
            input_offset + @min(
                input_chunk_size,
                input.len - input_offset,
            ),
        );
        const result = try resampler.process(
            input[input_offset..input_end],
            output[output_offset..change_output],
        );
        if (result.consumed == 0 and result.produced == 0)
            return error.TestInputExhausted;
        input_offset += result.consumed;
        output_offset += result.produced;
    }
    try resampler.setRateCorrectionPpm(
        second_half_correction_ppm,
    );
    while (output_offset < output.len) {
        const input_end = @min(
            input.len,
            input_offset + @min(
                input_chunk_size,
                input.len - input_offset,
            ),
        );
        const result = try resampler.process(
            input[input_offset..input_end],
            output[output_offset..],
        );
        if (result.consumed == 0 and result.produced == 0)
            return error.TestInputExhausted;
        input_offset += result.consumed;
        output_offset += result.produced;
    }
    return input_offset;
}

fn expectBackendParity(comptime Sample: type, tolerance: Sample) !void {
    const Resampler = StreamingResampler(Sample);
    const config = Config{
        .input_rate = 44_100,
        .output_rate = 96_000,
    };
    var input: [513]Sample = undefined;
    for (&input, 0..) |*sample, index| {
        const position: Sample = @floatFromInt(index);
        sample.* = 0.6 * @sin(position * 0.071) +
            0.2 * @cos(position * 0.193);
    }

    var scalar = try Resampler.initBackend(config, .scalar);
    var neon = try Resampler.initBackend(config, .neon);
    var avx2 = try Resampler.initBackend(config, .avx2);
    try scalar.setRateCorrectionPpm(875.0);
    try neon.setRateCorrectionPpm(875.0);
    try avx2.setRateCorrectionPpm(875.0);
    var expected: [1200]Sample = undefined;
    var neon_output: [1200]Sample = undefined;
    var avx2_output: [1200]Sample = undefined;
    const expected_result = try scalar.process(&input, &expected);
    const neon_result = try neon.process(&input, &neon_output);
    const avx2_result = try avx2.process(&input, &avx2_output);

    try std.testing.expectEqual(input.len, expected_result.consumed);
    try std.testing.expectEqual(expected_result, neon_result);
    try std.testing.expectEqual(expected_result, avx2_result);
    for (
        expected[0..expected_result.produced],
        neon_output[0..neon_result.produced],
        avx2_output[0..avx2_result.produced],
    ) |expected_sample, neon_sample, avx2_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            neon_sample,
            tolerance,
        );
        try std.testing.expectApproxEqAbs(
            expected_sample,
            avx2_sample,
            tolerance,
        );
    }

    try scalar.beginDrain();
    try neon.beginDrain();
    try avx2.beginDrain();
    const expected_tail = try scalar.drain(&expected);
    const neon_tail = try neon.drain(&neon_output);
    const avx2_tail = try avx2.drain(&avx2_output);
    try std.testing.expect(expected_tail.finished);
    try std.testing.expectEqual(expected_tail, neon_tail);
    try std.testing.expectEqual(expected_tail, avx2_tail);
    for (
        expected[0..expected_tail.produced],
        neon_output[0..neon_tail.produced],
        avx2_output[0..avx2_tail.produced],
    ) |expected_sample, neon_sample, avx2_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            neon_sample,
            tolerance,
        );
        try std.testing.expectApproxEqAbs(
            expected_sample,
            avx2_sample,
            tolerance,
        );
    }
}
