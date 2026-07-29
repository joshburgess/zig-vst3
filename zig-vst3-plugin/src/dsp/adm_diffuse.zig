const std = @import("std");
const adm_render = @import("adm_render.zig");
const fft = @import("fft.zig");

pub const filter_length: usize = 512;
pub const direct_delay_samples: usize = (filter_length - 1) / 2;

const Mt19937 = struct {
    const state_length: usize = 624;
    const recurrence_offset: usize = 397;

    state: [state_length]u32,
    index: usize,

    fn init(seed: u32) Mt19937 {
        var result: Mt19937 = undefined;
        result.state[0] = seed;
        for (1..state_length) |index| {
            const previous = result.state[index - 1];
            result.state[index] = 1_812_433_253 *%
                (previous ^ (previous >> 30)) +%
                @as(u32, @intCast(index));
        }
        result.index = state_length;
        return result;
    }

    fn next(self: *Mt19937) u32 {
        if (self.index == state_length) self.twist();
        var value = self.state[self.index];
        self.index += 1;
        value ^= value >> 11;
        value ^= (value << 7) & 0x9d2c_5680;
        value ^= (value << 15) & 0xefc6_0000;
        value ^= value >> 18;
        return value;
    }

    fn twist(self: *Mt19937) void {
        for (0..state_length) |index| {
            const combined =
                (self.state[index] & 0x8000_0000) |
                (self.state[(index + 1) % state_length] & 0x7fff_ffff);
            self.state[index] =
                self.state[(index + recurrence_offset) % state_length] ^
                (combined >> 1) ^
                (if (combined & 1 == 0) @as(u32, 0) else 0x9908_b0df);
        }
        self.index = 0;
    }
};

pub fn ObjectDiffuseProcessor(
    comptime Sample: type,
    comptime maximum_outputs: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "ObjectDiffuseProcessor supports f32 and f64 samples",
        );
    if (maximum_outputs == 0 or
        maximum_outputs > adm_render.maximum_output_channels)
    {
        @compileError(
            "ObjectDiffuseProcessor output capacity must be from one through the ADM renderer maximum",
        );
    }

    return struct {
        const Self = @This();
        const DesignFft = fft.Transform(f64, filter_length);

        output_count: usize = 0,
        coefficients: [maximum_outputs][filter_length]Sample =
            @splat(@splat(0.0)),
        diffuse_history: [maximum_outputs][filter_length]Sample =
            @splat(@splat(0.0)),
        direct_history: [maximum_outputs][direct_delay_samples]Sample =
            @splat(@splat(0.0)),
        diffuse_remaining: [maximum_outputs]u16 = @splat(0),
        diffuse_write_index: usize = 0,
        direct_write_index: usize = 0,

        pub fn init(outputs: []const adm_render.OutputSpeaker) !Self {
            if (outputs.len == 0 or outputs.len > maximum_outputs)
                return error.InvalidAdmDiffuseOutputCount;

            var labels: [maximum_outputs][]const u8 = undefined;
            for (outputs, 0..) |output, index| {
                labels[index] =
                    adm_render.canonicalSpeakerLabel(output.label) orelse
                    return error.InvalidAdmRendererSpeakerLabel;
                for (labels[0..index]) |previous| {
                    if (std.mem.eql(u8, labels[index], previous))
                        return error.DuplicateAdmRendererSpeakerLabel;
                }
            }

            var result = Self{ .output_count = outputs.len };
            const transform = DesignFft.init();
            for (labels[0..outputs.len], 0..) |label, output_index| {
                var seed: u32 = 0;
                for (labels[0..outputs.len]) |candidate| {
                    if (std.mem.order(u8, candidate, label) == .lt)
                        seed += 1;
                }
                var designed: [filter_length]f64 = undefined;
                try designFilter(seed, &transform, &designed);
                for (
                    &result.coefficients[output_index],
                    designed,
                ) |*coefficient, value| {
                    coefficient.* = @floatCast(value);
                }
            }
            return result;
        }

        pub fn latencySamples(_: *const Self) usize {
            return direct_delay_samples;
        }

        pub fn reset(self: *Self) void {
            self.diffuse_history = @splat(@splat(0.0));
            self.direct_history = @splat(@splat(0.0));
            self.diffuse_remaining = @splat(0);
            self.diffuse_write_index = 0;
            self.direct_write_index = 0;
        }

        pub fn process(
            self: *Self,
            direct_inputs: []const []const Sample,
            diffuse_inputs: []const []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmDiffuseState;
            const frame_count = try validateBuffers(
                Sample,
                self.output_count,
                direct_inputs,
                diffuse_inputs,
                outputs,
            );

            for (0..frame_count) |frame| {
                for (0..self.output_count) |output_index| {
                    const direct_input = finiteOrZero(
                        Sample,
                        direct_inputs[output_index][frame],
                    );
                    const diffuse_input = finiteOrZero(
                        Sample,
                        diffuse_inputs[output_index][frame],
                    );
                    const direct_output =
                        self.direct_history[output_index][self.direct_write_index];
                    self.direct_history[output_index][self.direct_write_index] = direct_input;
                    self.diffuse_history[output_index][self.diffuse_write_index] = diffuse_input;

                    var diffuse_output: f128 = 0.0;
                    if (diffuse_input != 0.0) {
                        self.diffuse_remaining[output_index] =
                            filter_length;
                    }
                    if (self.diffuse_remaining[output_index] > 0) {
                        for (
                            self.coefficients[output_index],
                            0..,
                        ) |coefficient, offset| {
                            const history_index =
                                (self.diffuse_write_index +
                                    filter_length -
                                    offset) %
                                filter_length;
                            diffuse_output +=
                                @as(f128, coefficient) *
                                @as(
                                    f128,
                                    self.diffuse_history[output_index][history_index],
                                );
                        }
                        self.diffuse_remaining[output_index] -= 1;
                    }
                    const combined =
                        @as(f128, direct_output) + diffuse_output;
                    outputs[output_index][frame] =
                        if (std.math.isFinite(combined) and
                        combined >= -std.math.floatMax(Sample) and
                        combined <= std.math.floatMax(Sample))
                            @floatCast(combined)
                        else
                            0.0;
                }
                self.diffuse_write_index =
                    (self.diffuse_write_index + 1) % filter_length;
                self.direct_write_index =
                    (self.direct_write_index + 1) %
                    direct_delay_samples;
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_outputs or
                self.diffuse_write_index >= filter_length or
                self.direct_write_index >= direct_delay_samples)
            {
                return false;
            }
            for (0..self.output_count) |output_index| {
                if (self.diffuse_remaining[output_index] > filter_length)
                    return false;
                for (self.coefficients[output_index]) |coefficient| {
                    if (!std.math.isFinite(coefficient)) return false;
                }
                for (self.diffuse_history[output_index]) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
                for (self.direct_history[output_index]) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
            }
            return true;
        }

        pub fn filterCoefficients(
            self: *const Self,
            output_index: usize,
        ) ![]const Sample {
            if (!self.valid()) return error.InvalidAdmDiffuseState;
            if (output_index >= self.output_count)
                return error.InvalidAdmDiffuseOutputIndex;
            return &self.coefficients[output_index];
        }

        fn designFilter(
            seed: u32,
            transform: *const DesignFft,
            coefficients: *[filter_length]f64,
        ) !void {
            var random = Mt19937.init(seed);
            var spectrum: [filter_length]DesignFft.Value =
                @splat(.{});
            spectrum[0].real = 1.0;
            spectrum[filter_length / 2].real = 1.0;
            for (1..filter_length / 2) |bin| {
                const unit =
                    @as(f64, @floatFromInt(random.next())) /
                    4_294_967_296.0;
                const phase = std.math.tau * unit;
                spectrum[bin] = .{
                    .real = @cos(phase),
                    .imaginary = @sin(phase),
                };
                spectrum[filter_length - bin] = .{
                    .real = spectrum[bin].real,
                    .imaginary = -spectrum[bin].imaginary,
                };
            }
            try transform.inverseReal(&spectrum, coefficients);
        }
    };
}

fn validateBuffers(
    comptime Sample: type,
    output_count: usize,
    direct_inputs: []const []const Sample,
    diffuse_inputs: []const []const Sample,
    outputs: []const []Sample,
) !usize {
    if (direct_inputs.len != output_count or
        diffuse_inputs.len != output_count or
        outputs.len != output_count)
    {
        return error.AdmDiffuseOutputCountMismatch;
    }
    const frame_count = direct_inputs[0].len;
    for (0..output_count) |output_index| {
        if (direct_inputs[output_index].len != frame_count or
            diffuse_inputs[output_index].len != frame_count or
            outputs[output_index].len != frame_count)
        {
            return error.AdmDiffuseBufferLengthMismatch;
        }
        for (outputs[0..output_index]) |previous| {
            if (slicesOverlap(Sample, previous, outputs[output_index]))
                return error.AdmDiffuseAliasedBuffers;
        }
        for (direct_inputs) |input| {
            if (slicesOverlap(Sample, input, outputs[output_index]))
                return error.AdmDiffuseAliasedBuffers;
        }
        for (diffuse_inputs) |input| {
            if (slicesOverlap(Sample, input, outputs[output_index]))
                return error.AdmDiffuseAliasedBuffers;
        }
    }
    return frame_count;
}

fn slicesOverlap(
    comptime Sample: type,
    left: []const Sample,
    right: []const Sample,
) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_bytes = std.math.mul(
        usize,
        left.len,
        @sizeOf(Sample),
    ) catch return true;
    const right_bytes = std.math.mul(
        usize,
        right.len,
        @sizeOf(Sample),
    ) catch return true;
    const left_end = std.math.add(
        usize,
        left_start,
        left_bytes,
    ) catch return true;
    const right_end = std.math.add(
        usize,
        right_start,
        right_bytes,
    ) catch return true;
    return left_start < right_end and right_start < left_end;
}

fn finiteOrZero(comptime Sample: type, value: Sample) Sample {
    return if (std.math.isFinite(value)) value else 0.0;
}

fn testLayout() [2]adm_render.OutputSpeaker {
    return .{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = -1.0, .y = 1.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = 1.0, .y = 1.0 },
        },
    };
}

test "ADM diffuse random generator matches the fixed MT19937 sequence" {
    var random = Mt19937.init(5489);
    var value: u32 = 0;
    for (0..10_000) |_| value = random.next();
    try std.testing.expectEqual(@as(u32, 4_123_659_995), value);
}

test "ADM diffuse filters match independent random-phase vectors" {
    const layout = testLayout();
    var processor =
        try ObjectDiffuseProcessor(f64, layout.len).init(&layout);
    const first = try processor.filterCoefficients(0);
    const second = try processor.filterCoefficients(1);
    const expected_seed_zero = [_]f64{
        -0.069648564155628645,
        0.0092398025542529769,
        -0.044409070199183193,
        0.096743183146590583,
        -0.014717255690727007,
        0.022043568179752827,
        -0.055775694172880801,
        -0.0024163514005843155,
    };
    const expected_seed_one = [_]f64{
        0.026956990215015554,
        0.027660528478274621,
        0.012471361607167032,
        -0.031109590215912652,
        0.037544136878272447,
        -0.025804789283586139,
        -0.017074267038471432,
        -0.051019205518953253,
    };
    for (first[0..expected_seed_zero.len], expected_seed_zero) |
        actual,
        expected,
    | {
        try std.testing.expectApproxEqAbs(expected, actual, 2.0e-15);
    }
    for (second[0..expected_seed_one.len], expected_seed_one) |
        actual,
        expected,
    | {
        try std.testing.expectApproxEqAbs(expected, actual, 2.0e-15);
    }

    var first_energy: f64 = 0.0;
    var second_energy: f64 = 0.0;
    for (first, second) |first_value, second_value| {
        first_energy += first_value * first_value;
        second_energy += second_value * second_value;
    }
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), first_energy, 2.0e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), second_energy, 2.0e-14);
}

test "ADM diffuse seed follows sorted labels instead of layout order" {
    const forward_layout = testLayout();
    const reverse_layout = [_]adm_render.OutputSpeaker{
        forward_layout[1],
        forward_layout[0],
    };
    var forward =
        try ObjectDiffuseProcessor(f32, 2).init(&forward_layout);
    var reverse =
        try ObjectDiffuseProcessor(f32, 2).init(&reverse_layout);
    try std.testing.expectEqualSlices(
        f32,
        try forward.filterCoefficients(0),
        try reverse.filterCoefficients(1),
    );
    try std.testing.expectEqualSlices(
        f32,
        try forward.filterCoefficients(1),
        try reverse.filterCoefficients(0),
    );
}

test "ADM diffuse processing aligns direct and diffuse paths across partitions" {
    const layout = testLayout();
    var whole = try ObjectDiffuseProcessor(f64, 2).init(&layout);
    var partitioned = try ObjectDiffuseProcessor(f64, 2).init(&layout);
    const frame_count = filter_length + 9;
    var direct: [2][frame_count]f64 = @splat(@splat(0.0));
    var diffuse: [2][frame_count]f64 = @splat(@splat(0.0));
    direct[0][0] = 0.5;
    diffuse[0][0] = 1.0;
    direct[1][3] = -0.25;
    diffuse[1][3] = 0.75;
    const direct_inputs = [_][]const f64{ &direct[0], &direct[1] };
    const diffuse_inputs = [_][]const f64{ &diffuse[0], &diffuse[1] };
    var whole_storage: [2][frame_count]f64 = undefined;
    const whole_outputs = [_][]f64{
        &whole_storage[0],
        &whole_storage[1],
    };
    try whole.process(&direct_inputs, &diffuse_inputs, &whole_outputs);

    var partitioned_storage: [2][frame_count]f64 = undefined;
    const cuts = [_]usize{ 0, 1, 17, 256, filter_length, frame_count };
    for (cuts[0 .. cuts.len - 1], cuts[1..]) |start, end| {
        const part_direct = [_][]const f64{
            direct[0][start..end],
            direct[1][start..end],
        };
        const part_diffuse = [_][]const f64{
            diffuse[0][start..end],
            diffuse[1][start..end],
        };
        const part_outputs = [_][]f64{
            partitioned_storage[0][start..end],
            partitioned_storage[1][start..end],
        };
        try partitioned.process(
            &part_direct,
            &part_diffuse,
            &part_outputs,
        );
    }
    try std.testing.expectEqualSlices(
        f64,
        &whole_storage[0],
        &partitioned_storage[0],
    );
    try std.testing.expectEqualSlices(
        f64,
        &whole_storage[1],
        &partitioned_storage[1],
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        whole_storage[0][direct_delay_samples] -
            (try whole.filterCoefficients(0))[direct_delay_samples],
        2.0e-15,
    );
    for (
        whole_storage[0][0..filter_length],
        (try whole.filterCoefficients(0))[0..filter_length],
        0..,
    ) |actual, coefficient, sample| {
        const expected = coefficient +
            (if (sample == direct_delay_samples) @as(f64, 0.5) else 0.0);
        try std.testing.expectApproxEqAbs(expected, actual, 2.0e-15);
    }
    try std.testing.expectEqual(
        direct_delay_samples,
        whole.latencySamples(),
    );
}

test "ADM diffuse reset, non-finite containment, and preflight are stable" {
    const layout = testLayout();
    var processor =
        try ObjectDiffuseProcessor(f32, layout.len).init(&layout);
    const direct_storage = [2][2]f32{
        .{ std.math.nan(f32), 1.0 },
        .{ 0.0, 0.0 },
    };
    const diffuse_storage = [2][2]f32{
        .{ std.math.inf(f32), 0.0 },
        .{ 0.0, 0.0 },
    };
    const direct = [_][]const f32{
        &direct_storage[0],
        &direct_storage[1],
    };
    const diffuse = [_][]const f32{
        &diffuse_storage[0],
        &diffuse_storage[1],
    };
    var output_storage: [2][2]f32 = undefined;
    const outputs = [_][]f32{
        &output_storage[0],
        &output_storage[1],
    };
    try processor.process(&direct, &diffuse, &outputs);
    try std.testing.expectEqualSlices(f32, &.{ 0.0, 0.0 }, &output_storage[0]);

    processor.reset();
    var alias_storage: [2]f32 = @splat(0.0);
    const alias_direct = [_][]const f32{ &alias_storage, &direct_storage[1] };
    const alias_outputs = [_][]f32{ &alias_storage, &output_storage[1] };
    try std.testing.expectError(
        error.AdmDiffuseAliasedBuffers,
        processor.process(&alias_direct, &diffuse, &alias_outputs),
    );
    try std.testing.expectEqual(@as(usize, 0), processor.direct_write_index);
    try std.testing.expectEqual(@as(usize, 0), processor.diffuse_write_index);

    processor.diffuse_write_index = filter_length;
    try std.testing.expectError(
        error.InvalidAdmDiffuseState,
        processor.process(&direct, &diffuse, &outputs),
    );

    const short_outputs = [_][]f32{&output_storage[0]};
    processor.diffuse_write_index = 0;
    try std.testing.expectError(
        error.AdmDiffuseOutputCountMismatch,
        processor.process(&direct, &diffuse, &short_outputs),
    );
    try std.testing.expectEqual(@as(usize, 0), processor.direct_write_index);
}
