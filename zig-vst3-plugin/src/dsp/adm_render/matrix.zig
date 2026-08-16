const std = @import("std");
const adm = @import("../adm.zig");
const adm_xml = @import("../adm_xml.zig");
const common = @import("common.zig");

const maximum_input_channels = common.maximum_input_channels;
const renderGain = common.renderGain;
const slicesOverlap = common.slicesOverlap;

pub const MatrixVariableKind = enum {
    gain_linear,
    phase_degrees,
    delay_milliseconds,
};

pub const MatrixVariableInterpolation = enum {
    hold,
    linear,
};

pub const MatrixVariablePoint = struct {
    sample: u64,
    value: f64,
};

pub const MatrixVariableTimeline = struct {
    name: []const u8,
    kind: MatrixVariableKind,
    interpolation: MatrixVariableInterpolation = .linear,
    points: []const MatrixVariablePoint,
};

pub fn StaticMatrixMixer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StaticMatrixMixer supports f32 and f64 samples");

    return struct {
        const Self = @This();

        input_count: usize = 0,
        term_count: usize = 0,
        declared_input_count: usize = 0,
        declared_term_count: usize = 0,
        input_indices: [maximum_input_channels]u8 = @splat(0),
        gains: [maximum_input_channels]Sample = @splat(0.0),

        pub fn init(
            block: *const adm_xml.BlockFormat,
            input_channels: []const adm.Identifier,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0002 or
                block.channel_identifier.typeLabel() != 0x0002)
            {
                return error.AdmRendererRequiresMatrixBlock;
            }
            if (input_channels.len == 0 or
                input_channels.len > maximum_input_channels)
            {
                return error.InvalidAdmRendererInputCount;
            }
            for (input_channels, 0..) |channel, index| {
                if (channel.kind != .channel_format)
                    return error.InvalidAdmRendererInputIdentifier;
                for (input_channels[0..index]) |previous| {
                    if (channel.eql(previous))
                        return error.DuplicateAdmRendererInputIdentifier;
                }
            }

            const coefficients = block.matrixCoefficientSlice();
            if (coefficients.len == 0)
                return error.MissingAdmRendererMatrixCoefficient;
            var result = Self{
                .input_count = input_channels.len,
                .term_count = coefficients.len,
                .declared_input_count = input_channels.len,
                .declared_term_count = coefficients.len,
            };
            for (coefficients, 0..) |coefficient, term_index| {
                if (coefficient.gain_variable != null or
                    coefficient.phase_variable != null or
                    coefficient.delay_variable != null or
                    coefficient.phase_degrees != 0.0 or
                    coefficient.delay_milliseconds != 0.0)
                {
                    return error.UnsupportedDynamicAdmMatrixCoefficient;
                }
                const identifier = try coefficient.channelIdentifier();
                const input_index = findInputChannel(
                    input_channels,
                    identifier,
                ) orelse return error.MissingAdmRendererInputChannel;
                for (result.input_indices[0..term_index]) |previous| {
                    if (previous == input_index)
                        return error.DuplicateAdmRendererMatrixCoefficient;
                }
                const gain = try renderGain(Sample, coefficient.gain);
                result.input_indices[term_index] = @intCast(input_index);
                result.gains[term_index] = gain;
            }
            return result;
        }

        pub fn processSample(
            self: *const Self,
            inputs: []const Sample,
        ) Sample {
            if (!self.valid() or inputs.len != self.input_count)
                return 0.0;
            var output: Sample = 0.0;
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
            ) |input_index, gain| {
                const input = inputs[input_index];
                if (!std.math.isFinite(input)) return 0.0;
                output += input * gain;
                if (!std.math.isFinite(output)) return 0.0;
            }
            return output;
        }

        pub fn process(
            self: *const Self,
            inputs: []const []const Sample,
            output: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (inputs.len != self.input_count)
                return error.AdmRendererInputCountMismatch;
            for (inputs) |input| {
                if (input.len != output.len)
                    return error.AdmRendererBufferLengthMismatch;
                if (slicesOverlap(Sample, input, output))
                    return error.AdmRendererAliasedBuffers;
            }
            for (output, 0..) |*output_sample, sample_index| {
                var value: Sample = 0.0;
                for (
                    self.input_indices[0..self.term_count],
                    self.gains[0..self.term_count],
                ) |input_index, gain| {
                    const input = inputs[input_index][sample_index];
                    if (!std.math.isFinite(input)) {
                        value = 0.0;
                        break;
                    }
                    value += input * gain;
                    if (!std.math.isFinite(value)) {
                        value = 0.0;
                        break;
                    }
                }
                output_sample.* = value;
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_input_channels or
                self.input_count != self.declared_input_count or
                self.term_count == 0 or
                self.term_count > maximum_input_channels or
                self.term_count != self.declared_term_count)
            {
                return false;
            }
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
                0..,
            ) |input_index, gain, term_index| {
                if (input_index >= self.input_count or
                    !std.math.isFinite(gain))
                {
                    return false;
                }
                for (self.input_indices[0..term_index]) |previous| {
                    if (previous == input_index) return false;
                }
            }
            return true;
        }
    };
}

pub fn MatrixCoefficientMixer(
    comptime Sample: type,
    comptime maximum_delay_samples: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("MatrixCoefficientMixer supports f32 and f64 samples");
    if (maximum_delay_samples == std.math.maxInt(usize))
        @compileError("MatrixCoefficientMixer delay capacity is too large");

    return struct {
        const Self = @This();
        const history_length = maximum_delay_samples + 1;

        pub const delay_capacity = maximum_delay_samples;

        input_count: usize = 0,
        term_count: usize = 0,
        declared_input_count: usize = 0,
        declared_term_count: usize = 0,
        input_indices: [maximum_input_channels]u8 = @splat(0),
        gains: [maximum_input_channels]Sample = @splat(0.0),
        delays: [maximum_input_channels]usize = @splat(0),
        history: [maximum_input_channels][history_length]Sample =
            @splat(@splat(0.0)),
        cursor: usize = 0,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            input_channels: []const adm.Identifier,
            sample_rate: f64,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0002 or
                block.channel_identifier.typeLabel() != 0x0002)
            {
                return error.AdmRendererRequiresMatrixBlock;
            }
            if (input_channels.len == 0 or
                input_channels.len > maximum_input_channels)
            {
                return error.InvalidAdmRendererInputCount;
            }
            if (!std.math.isFinite(sample_rate) or sample_rate <= 0.0)
                return error.InvalidAdmRendererSampleRate;
            for (input_channels, 0..) |channel, index| {
                if (channel.kind != .channel_format)
                    return error.InvalidAdmRendererInputIdentifier;
                for (input_channels[0..index]) |previous| {
                    if (channel.eql(previous))
                        return error.DuplicateAdmRendererInputIdentifier;
                }
            }

            const coefficients = block.matrixCoefficientSlice();
            if (coefficients.len == 0)
                return error.MissingAdmRendererMatrixCoefficient;
            var result = Self{
                .input_count = input_channels.len,
                .term_count = coefficients.len,
                .declared_input_count = input_channels.len,
                .declared_term_count = coefficients.len,
            };
            for (coefficients, 0..) |coefficient, term_index| {
                if (coefficient.gain_variable != null or
                    coefficient.phase_variable != null or
                    coefficient.delay_variable != null)
                {
                    return error.UnsupportedVariableAdmMatrixCoefficient;
                }
                if (coefficient.phase_degrees != 0.0)
                    return error.UnsupportedAdmMatrixCoefficientPhase;
                const identifier = try coefficient.channelIdentifier();
                const input_index = findInputChannel(
                    input_channels,
                    identifier,
                ) orelse return error.MissingAdmRendererInputChannel;
                for (result.input_indices[0..term_index]) |previous| {
                    if (previous == input_index)
                        return error.DuplicateAdmRendererMatrixCoefficient;
                }
                result.input_indices[term_index] =
                    @intCast(input_index);
                result.gains[term_index] =
                    try renderGain(Sample, coefficient.gain);
                result.delays[term_index] = try matrixDelaySamples(
                    coefficient.delay_milliseconds,
                    sample_rate,
                    maximum_delay_samples,
                );
            }
            return result;
        }

        pub fn reset(self: *Self) void {
            if (self.input_count != self.declared_input_count or
                self.term_count != self.declared_term_count)
            {
                return;
            }
            self.cursor = 0;
            for (&self.history) |*term_history|
                @memset(term_history, 0.0);
        }

        pub fn processSample(
            self: *Self,
            inputs: []const Sample,
        ) Sample {
            if (!self.valid() or inputs.len != self.input_count)
                return 0.0;
            return self.processSampleUnchecked(inputs);
        }

        fn processSampleUnchecked(
            self: *Self,
            inputs: []const Sample,
        ) Sample {
            var output: Sample = 0.0;
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
                self.delays[0..self.term_count],
                0..,
            ) |input_index, gain, delay, term_index| {
                const raw_input = inputs[input_index];
                const input = if (std.math.isFinite(raw_input))
                    raw_input
                else
                    0.0;
                self.history[term_index][self.cursor] = input;
                const read_index =
                    (self.cursor + history_length - delay) %
                    history_length;
                const raw_delayed =
                    self.history[term_index][read_index];
                const delayed = if (std.math.isFinite(raw_delayed))
                    raw_delayed
                else
                    0.0;
                output += delayed * gain;
                if (!std.math.isFinite(output)) output = 0.0;
            }
            self.cursor = (self.cursor + 1) % history_length;
            return output;
        }

        pub fn process(
            self: *Self,
            inputs: []const []const Sample,
            output: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (inputs.len != self.input_count)
                return error.AdmRendererInputCountMismatch;
            for (inputs) |input| {
                if (input.len != output.len)
                    return error.AdmRendererBufferLengthMismatch;
                if (slicesOverlap(Sample, input, output))
                    return error.AdmRendererAliasedBuffers;
            }
            for (output, 0..) |*output_sample, sample_index| {
                var samples: [maximum_input_channels]Sample = undefined;
                for (inputs, 0..) |input, input_index|
                    samples[input_index] = input[sample_index];
                output_sample.* = self.processSampleUnchecked(
                    samples[0..self.input_count],
                );
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_input_channels or
                self.input_count != self.declared_input_count or
                self.term_count == 0 or
                self.term_count > maximum_input_channels or
                self.term_count != self.declared_term_count or
                self.cursor >= history_length)
            {
                return false;
            }
            for (
                self.input_indices[0..self.term_count],
                self.gains[0..self.term_count],
                self.delays[0..self.term_count],
                0..,
            ) |input_index, gain, delay, term_index| {
                if (input_index >= self.input_count or
                    !std.math.isFinite(gain) or
                    delay > maximum_delay_samples)
                {
                    return false;
                }
                for (self.input_indices[0..term_index]) |previous| {
                    if (previous == input_index) return false;
                }
            }
            return true;
        }
    };
}

/// Resolves variable Matrix metadata against caller-defined control lanes.
///
/// Processing remains sequential after reset or resetAt.
/// A nonempty antisymmetric quadrature FIR enables phase rotation and delays every
/// term by its integer group delay. Variable delay endpoints use the same
/// nearest-sample rule as fixed Matrix delay, then interpolate between endpoints.
pub fn VariableMatrixCoefficientMixer(
    comptime Sample: type,
    comptime maximum_delay_samples: usize,
    comptime maximum_variables: usize,
    comptime maximum_points: usize,
    comptime maximum_phase_taps: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "VariableMatrixCoefficientMixer supports f32 and f64 samples",
        );
    if (maximum_variables > std.math.maxInt(u16)) {
        @compileError(
            "VariableMatrixCoefficientMixer variable capacity is invalid",
        );
    }
    if (maximum_points > std.math.maxInt(u32))
        @compileError(
            "VariableMatrixCoefficientMixer point capacity is invalid",
        );
    if (maximum_delay_samples >
        std.math.maxInt(usize) - maximum_phase_taps - 1)
    {
        @compileError(
            "VariableMatrixCoefficientMixer history capacity is too large",
        );
    }

    return struct {
        const Self = @This();
        const history_length =
            maximum_delay_samples + maximum_phase_taps + 1;
        const Lane = struct {
            kind: MatrixVariableKind = .gain_linear,
            interpolation: MatrixVariableInterpolation = .linear,
            first_point: u32 = 0,
            point_count: u32 = 0,
        };
        const StoredPoint = struct {
            sample: u64 = 0,
            value: f64 = 0.0,
        };

        pub const delay_capacity = maximum_delay_samples;
        pub const variable_capacity = maximum_variables;
        pub const point_capacity = maximum_points;
        pub const phase_tap_capacity = maximum_phase_taps;

        input_count: usize = 0,
        term_count: usize = 0,
        declared_input_count: usize = 0,
        declared_term_count: usize = 0,
        lane_count: usize = 0,
        point_count: usize = 0,
        phase_tap_count: usize = 0,
        phase_latency: usize = 0,
        input_indices: [maximum_input_channels]u8 = @splat(0),
        fixed_gains: [maximum_input_channels]Sample = @splat(0.0),
        fixed_phases: [maximum_input_channels]f64 = @splat(0.0),
        fixed_delays: [maximum_input_channels]f64 = @splat(0.0),
        gain_lanes: [maximum_input_channels]?u16 = @splat(null),
        phase_lanes: [maximum_input_channels]?u16 = @splat(null),
        delay_lanes: [maximum_input_channels]?u16 = @splat(null),
        lanes: [maximum_variables]Lane = @splat(.{}),
        points: [maximum_points]StoredPoint = @splat(.{}),
        phase_taps: [maximum_phase_taps]Sample = @splat(0.0),
        history: [maximum_input_channels][history_length]Sample =
            @splat(@splat(0.0)),
        cursor: usize = 0,
        next_sample: u64 = 0,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            input_channels: []const adm.Identifier,
            sample_rate: f64,
            timelines: []const MatrixVariableTimeline,
            quadrature_fir: []const Sample,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0002 or
                block.channel_identifier.typeLabel() != 0x0002)
            {
                return error.AdmRendererRequiresMatrixBlock;
            }
            if (input_channels.len == 0 or
                input_channels.len > maximum_input_channels)
            {
                return error.InvalidAdmRendererInputCount;
            }
            if (!std.math.isFinite(sample_rate) or sample_rate <= 0.0)
                return error.InvalidAdmRendererSampleRate;
            if (timelines.len > maximum_variables)
                return error.AdmRendererMatrixVariableCapacityExceeded;
            for (input_channels, 0..) |channel, index| {
                if (channel.kind != .channel_format)
                    return error.InvalidAdmRendererInputIdentifier;
                for (input_channels[0..index]) |previous| {
                    if (channel.eql(previous))
                        return error.DuplicateAdmRendererInputIdentifier;
                }
            }

            const coefficients = block.matrixCoefficientSlice();
            if (coefficients.len == 0)
                return error.MissingAdmRendererMatrixCoefficient;
            var result = Self{
                .input_count = input_channels.len,
                .term_count = coefficients.len,
                .declared_input_count = input_channels.len,
                .declared_term_count = coefficients.len,
                .lane_count = timelines.len,
                .point_count = 0,
                .phase_tap_count = 0,
                .phase_latency = 0,
            };
            var timeline_used: [maximum_variables]bool = @splat(false);
            if (comptime maximum_variables != 0 and
                maximum_points != 0)
            {
                for (timelines, 0..) |timeline, lane_index| {
                    if (timeline.name.len == 0 or timeline.points.len == 0)
                        return error.InvalidAdmRendererMatrixVariable;
                    for (timelines[0..lane_index]) |previous| {
                        if (std.mem.eql(u8, timeline.name, previous.name))
                            return error.DuplicateAdmRendererMatrixVariable;
                    }
                    if (timeline.points[0].sample != 0)
                        return error.InvalidAdmRendererMatrixVariable;
                    const next_point_count = std.math.add(
                        usize,
                        result.point_count,
                        timeline.points.len,
                    ) catch
                        return error.AdmRendererMatrixPointCapacityExceeded;
                    if (next_point_count > maximum_points)
                        return error.AdmRendererMatrixPointCapacityExceeded;
                    const first_point = result.point_count;
                    for (timeline.points, 0..) |point, point_index| {
                        if (!std.math.isFinite(point.value) or
                            (point_index != 0 and
                                point.sample <=
                                    timeline.points[point_index - 1].sample))
                        {
                            return error.InvalidAdmRendererMatrixVariable;
                        }
                        if (point_index != 0 and
                            timeline.interpolation == .linear and
                            !std.math.isFinite(
                                point.value -
                                    timeline.points[point_index - 1].value,
                            ))
                        {
                            return error.InvalidAdmRendererMatrixVariable;
                        }
                        result.points[first_point + point_index] = .{
                            .sample = point.sample,
                            .value = try controlValue(
                                timeline.kind,
                                point.value,
                                sample_rate,
                            ),
                        };
                    }
                    result.lanes[lane_index] = .{
                        .kind = timeline.kind,
                        .interpolation = timeline.interpolation,
                        .first_point = @intCast(first_point),
                        .point_count = @intCast(timeline.points.len),
                    };
                    result.point_count = next_point_count;
                }
            } else if (timelines.len != 0) {
                if (maximum_variables == 0)
                    return error.AdmRendererMatrixVariableCapacityExceeded;
                return error.AdmRendererMatrixPointCapacityExceeded;
            }

            var phase_required = false;
            for (coefficients, 0..) |coefficient, term_index| {
                const identifier = try coefficient.channelIdentifier();
                const input_index = findInputChannel(
                    input_channels,
                    identifier,
                ) orelse return error.MissingAdmRendererInputChannel;
                for (result.input_indices[0..term_index]) |previous| {
                    if (previous == input_index)
                        return error.DuplicateAdmRendererMatrixCoefficient;
                }
                result.input_indices[term_index] = @intCast(input_index);

                if (coefficient.gain_variable) |variable| {
                    if (coefficient.gain.unit != .linear)
                        return error.InvalidAdmRendererMatrixVariable;
                    result.fixed_gains[term_index] = 0.0;
                    result.gain_lanes[term_index] = try bindTimeline(
                        timelines,
                        variable.value(),
                        .gain_linear,
                        &timeline_used,
                    );
                } else {
                    result.fixed_gains[term_index] =
                        try renderGain(Sample, coefficient.gain);
                }

                result.fixed_phases[term_index] =
                    coefficient.phase_degrees;
                if (!std.math.isFinite(result.fixed_phases[term_index]))
                    return error.InvalidAdmRendererMatrixPhase;
                if (coefficient.phase_variable) |variable| {
                    result.phase_lanes[term_index] = try bindTimeline(
                        timelines,
                        variable.value(),
                        .phase_degrees,
                        &timeline_used,
                    );
                    phase_required = true;
                } else if (coefficient.phase_degrees != 0.0) {
                    phase_required = true;
                }

                if (coefficient.delay_variable) |variable| {
                    result.fixed_delays[term_index] = 0.0;
                    result.delay_lanes[term_index] = try bindTimeline(
                        timelines,
                        variable.value(),
                        .delay_milliseconds,
                        &timeline_used,
                    );
                } else {
                    result.fixed_delays[term_index] = @floatFromInt(
                        try matrixDelaySamples(
                            coefficient.delay_milliseconds,
                            sample_rate,
                            maximum_delay_samples,
                        ),
                    );
                }
            }
            for (timeline_used[0..timelines.len]) |used| {
                if (!used) return error.UnusedAdmRendererMatrixVariable;
            }
            if (phase_required) {
                try result.setPhaseFilter(quadrature_fir);
            } else if (quadrature_fir.len != 0) {
                return error.UnusedAdmRendererMatrixPhaseFilter;
            }
            if (!result.valid())
                return error.InvalidAdmRendererState;
            return result;
        }

        pub fn reset(self: *Self) void {
            self.resetAt(0);
        }

        pub fn resetAt(self: *Self, first_sample: u64) void {
            if (self.input_count != self.declared_input_count or
                self.term_count != self.declared_term_count)
            {
                return;
            }
            self.cursor = 0;
            self.next_sample = first_sample;
            for (&self.history) |*term_history|
                @memset(term_history, 0.0);
        }

        pub fn latencySamples(self: *const Self) usize {
            return self.phase_latency;
        }

        pub fn process(
            self: *Self,
            first_sample: u64,
            inputs: []const []const Sample,
            output: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (first_sample != self.next_sample)
                return error.DiscontinuousAdmRendererSampleRange;
            if (inputs.len != self.input_count)
                return error.AdmRendererInputCountMismatch;
            for (inputs) |input| {
                if (input.len != output.len)
                    return error.AdmRendererBufferLengthMismatch;
                if (slicesOverlap(Sample, input, output))
                    return error.AdmRendererAliasedBuffers;
            }
            const sample_count = std.math.cast(
                u64,
                output.len,
            ) orelse return error.AdmRendererSampleRangeOverflow;
            const end_sample = std.math.add(
                u64,
                first_sample,
                sample_count,
            ) catch return error.AdmRendererSampleRangeOverflow;

            for (output, 0..) |*output_sample, sample_offset| {
                const absolute_sample =
                    first_sample + @as(u64, @intCast(sample_offset));
                var mixed: Sample = 0.0;
                for (0..self.term_count) |term_index| {
                    const raw_input =
                        inputs[self.input_indices[term_index]][sample_offset];
                    const input = if (std.math.isFinite(raw_input))
                        raw_input
                    else
                        0.0;
                    self.history[term_index][self.cursor] = input;

                    const gain = if (self.gain_lanes[term_index]) |lane|
                        self.laneSampleValue(lane, absolute_sample)
                    else
                        @as(f64, @floatCast(self.fixed_gains[term_index]));
                    const phase_degrees =
                        if (self.phase_lanes[term_index]) |lane|
                            self.laneSampleValue(lane, absolute_sample)
                        else
                            self.fixed_phases[term_index];
                    const delay = if (self.delay_lanes[term_index]) |lane|
                        self.laneSampleValue(lane, absolute_sample)
                    else
                        self.fixed_delays[term_index];

                    const real = self.delayedSample(
                        term_index,
                        delay + @as(f64, @floatFromInt(self.phase_latency)),
                    );
                    const rotated = if (self.phase_tap_count == 0)
                        real
                    else phase: {
                        var quadrature: Sample = 0.0;
                        for (
                            self.phase_taps[0..self.phase_tap_count],
                            0..,
                        ) |tap, tap_index| {
                            quadrature += tap * self.delayedSample(
                                term_index,
                                delay + @as(
                                    f64,
                                    @floatFromInt(tap_index),
                                ),
                            );
                        }
                        const radians =
                            @mod(phase_degrees, 360.0) *
                            std.math.pi / 180.0;
                        break :phase real *
                            @as(Sample, @floatCast(@cos(radians))) +
                            quadrature *
                                @as(Sample, @floatCast(@sin(radians)));
                    };
                    mixed += rotated * @as(Sample, @floatCast(gain));
                    if (!std.math.isFinite(mixed)) mixed = 0.0;
                }
                output_sample.* = mixed;
                self.cursor = (self.cursor + 1) % history_length;
            }
            self.next_sample = end_sample;
        }

        pub fn valid(self: *const Self) bool {
            if (self.input_count == 0 or
                self.input_count > maximum_input_channels or
                self.input_count != self.declared_input_count or
                self.term_count == 0 or
                self.term_count > maximum_input_channels or
                self.term_count != self.declared_term_count or
                self.lane_count > maximum_variables or
                self.point_count > maximum_points or
                self.phase_tap_count > maximum_phase_taps or
                self.cursor >= history_length or
                (self.phase_tap_count == 0 and self.phase_latency != 0) or
                (self.phase_tap_count != 0 and
                    (self.phase_tap_count < 3 or
                        self.phase_tap_count % 2 == 0 or
                        self.phase_latency != self.phase_tap_count / 2)))
            {
                return false;
            }
            var covered_points: usize = 0;
            for (self.lanes[0..self.lane_count]) |lane| {
                if (lane.point_count == 0 or
                    lane.first_point != covered_points)
                {
                    return false;
                }
                const lane_end = std.math.add(
                    usize,
                    lane.first_point,
                    lane.point_count,
                ) catch return false;
                if (lane_end > self.point_count) return false;
                const lane_points = self.points[lane.first_point..lane_end];
                if (lane_points[0].sample != 0) return false;
                for (lane_points, 0..) |point, point_index| {
                    if (!std.math.isFinite(point.value) or
                        (point_index != 0 and
                            point.sample <=
                                lane_points[point_index - 1].sample))
                    {
                        return false;
                    }
                    if (point_index != 0 and
                        lane.interpolation == .linear and
                        !std.math.isFinite(
                            point.value -
                                lane_points[point_index - 1].value,
                        ))
                    {
                        return false;
                    }
                    if (lane.kind == .delay_milliseconds and
                        (point.value < 0.0 or
                            point.value >
                                @as(
                                    f64,
                                    @floatFromInt(maximum_delay_samples),
                                )))
                    {
                        return false;
                    }
                }
                covered_points = lane_end;
            }
            if (covered_points != self.point_count) return false;
            var lane_used: [maximum_variables]bool = @splat(false);
            for (
                self.input_indices[0..self.term_count],
                self.fixed_gains[0..self.term_count],
                self.fixed_phases[0..self.term_count],
                self.fixed_delays[0..self.term_count],
                0..,
            ) |input_index, gain, phase_degrees, delay, term_index| {
                if (input_index >= self.input_count or
                    !std.math.isFinite(gain) or
                    !std.math.isFinite(phase_degrees) or
                    !std.math.isFinite(delay) or
                    delay < 0.0 or
                    delay >
                        @as(
                            f64,
                            @floatFromInt(maximum_delay_samples),
                        ))
                {
                    return false;
                }
                for (self.input_indices[0..term_index]) |previous| {
                    if (previous == input_index) return false;
                }
                if (!self.validLane(
                    self.gain_lanes[term_index],
                    .gain_linear,
                ) or
                    !self.validLane(
                        self.phase_lanes[term_index],
                        .phase_degrees,
                    ) or
                    !self.validLane(
                        self.delay_lanes[term_index],
                        .delay_milliseconds,
                    ))
                {
                    return false;
                }
                if (comptime maximum_variables != 0) {
                    if (self.gain_lanes[term_index]) |lane|
                        lane_used[lane] = true;
                    if (self.phase_lanes[term_index]) |lane|
                        lane_used[lane] = true;
                    if (self.delay_lanes[term_index]) |lane|
                        lane_used[lane] = true;
                }
                for (self.history[term_index]) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
            }
            for (lane_used[0..self.lane_count]) |used| {
                if (!used) return false;
            }
            if (comptime maximum_phase_taps == 0) {
                if (self.phase_tap_count != 0 or self.phase_latency != 0)
                    return false;
            } else if (self.phase_tap_count != 0) {
                const tolerance =
                    @as(Sample, std.math.floatEps(Sample) * 32.0);
                if (@abs(self.phase_taps[self.phase_latency]) > tolerance)
                    return false;
                for (0..self.phase_latency) |tap_index| {
                    const mirror =
                        self.phase_taps[self.phase_tap_count - 1 - tap_index];
                    if (@abs(self.phase_taps[tap_index] + mirror) >
                        tolerance)
                    {
                        return false;
                    }
                }
            }
            return true;
        }

        fn setPhaseFilter(
            self: *Self,
            quadrature_fir: []const Sample,
        ) !void {
            if (comptime maximum_phase_taps == 0)
                return error.InvalidAdmRendererMatrixPhaseFilter;
            if (quadrature_fir.len < 3 or
                quadrature_fir.len > maximum_phase_taps or
                quadrature_fir.len % 2 == 0)
            {
                return error.InvalidAdmRendererMatrixPhaseFilter;
            }
            const center = quadrature_fir.len / 2;
            const tolerance =
                @as(Sample, std.math.floatEps(Sample) * 32.0);
            if (!std.math.isFinite(quadrature_fir[center]) or
                @abs(quadrature_fir[center]) > tolerance)
            {
                return error.InvalidAdmRendererMatrixPhaseFilter;
            }
            for (quadrature_fir, 0..) |tap, tap_index| {
                if (!std.math.isFinite(tap))
                    return error.InvalidAdmRendererMatrixPhaseFilter;
                if (tap_index < center and
                    @abs(tap +
                        quadrature_fir[quadrature_fir.len - 1 - tap_index]) >
                        tolerance)
                {
                    return error.InvalidAdmRendererMatrixPhaseFilter;
                }
            }
            @memcpy(
                self.phase_taps[0..quadrature_fir.len],
                quadrature_fir,
            );
            self.phase_tap_count = quadrature_fir.len;
            self.phase_latency = center;
        }

        fn laneSampleValue(
            self: *const Self,
            lane_index: u16,
            sample: u64,
        ) f64 {
            if (comptime maximum_variables == 0) {
                return 0.0;
            }
            const lane = self.lanes[lane_index];
            const first: usize = lane.first_point;
            const count: usize = lane.point_count;
            const lane_points = self.points[first .. first + count];
            if (sample >= lane_points[count - 1].sample)
                return lane_points[count - 1].value;
            var upper_index: usize = 1;
            while (lane_points[upper_index].sample <= sample)
                upper_index += 1;
            const lower = lane_points[upper_index - 1];
            if (lane.interpolation == .hold) return lower.value;
            const upper = lane_points[upper_index];
            const numerator =
                @as(f64, @floatFromInt(sample - lower.sample));
            const denominator =
                @as(f64, @floatFromInt(upper.sample - lower.sample));
            return lower.value +
                (upper.value - lower.value) *
                    (numerator / denominator);
        }

        fn delayedSample(
            self: *const Self,
            term_index: usize,
            delay: f64,
        ) Sample {
            const lower_delay: usize = @intFromFloat(@floor(delay));
            const fraction: Sample =
                @floatCast(delay - @as(f64, @floatFromInt(lower_delay)));
            const lower_index =
                (self.cursor + history_length -
                    lower_delay % history_length) %
                history_length;
            const lower = self.history[term_index][lower_index];
            if (fraction == 0.0) return lower;
            const upper_index =
                (lower_index + history_length - 1) % history_length;
            const upper = self.history[term_index][upper_index];
            return lower + (upper - lower) * fraction;
        }

        fn validLane(
            self: *const Self,
            lane_index: ?u16,
            kind: MatrixVariableKind,
        ) bool {
            if (comptime maximum_variables == 0) {
                return lane_index == null;
            }
            const index = lane_index orelse return true;
            return index < self.lane_count and
                self.lanes[index].kind == kind;
        }

        fn controlValue(
            kind: MatrixVariableKind,
            value: f64,
            sample_rate: f64,
        ) !f64 {
            return switch (kind) {
                .gain_linear => gain: {
                    const sample_value: Sample = @floatCast(value);
                    if (!std.math.isFinite(sample_value))
                        return error.InvalidAdmRendererMatrixVariable;
                    break :gain value;
                },
                .phase_degrees => value,
                .delay_milliseconds => @floatFromInt(
                    try matrixDelaySamples(
                        value,
                        sample_rate,
                        maximum_delay_samples,
                    ),
                ),
            };
        }

        fn bindTimeline(
            timelines: []const MatrixVariableTimeline,
            name: []const u8,
            kind: MatrixVariableKind,
            used: *[maximum_variables]bool,
        ) !u16 {
            if (comptime maximum_variables == 0)
                return error.MissingAdmRendererMatrixVariable;
            for (timelines, 0..) |timeline, index| {
                if (!std.mem.eql(u8, timeline.name, name)) continue;
                if (timeline.kind != kind)
                    return error.AdmRendererMatrixVariableKindMismatch;
                used[index] = true;
                return @intCast(index);
            }
            return error.MissingAdmRendererMatrixVariable;
        }
    };
}

fn matrixDelaySamples(
    delay_milliseconds: f64,
    sample_rate: f64,
    maximum_delay_samples: usize,
) !usize {
    if (!std.math.isFinite(delay_milliseconds) or
        delay_milliseconds < 0.0)
    {
        return error.InvalidAdmRendererMatrixDelay;
    }
    const exact_samples =
        sample_rate * delay_milliseconds / 1000.0;
    if (!std.math.isFinite(exact_samples))
        return error.InvalidAdmRendererMatrixDelay;
    const rounded_samples = @ceil(exact_samples - 0.5);
    if (rounded_samples <= 0.0) return 0;
    if (rounded_samples > @as(f64, @floatFromInt(maximum_delay_samples)))
        return error.AdmRendererMatrixDelayCapacityExceeded;
    return @intFromFloat(rounded_samples);
}

fn findInputChannel(
    channels: []const adm.Identifier,
    target: adm.Identifier,
) ?usize {
    for (channels, 0..) |channel, index| {
        if (channel.eql(target)) return index;
    }
    return null;
}
