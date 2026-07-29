const std = @import("std");
const adm = @import("adm.zig");
const adm_polar_panner = @import("adm_polar_panner.zig");
const adm_xml = @import("adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;
const position_tolerance: f64 = 1.0e-5;

pub const PolarPosition = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
    distance: f64 = 1.0,
};

pub const CartesianPosition = struct {
    x: f64,
    y: f64,
    z: f64 = 0.0,
};

pub const OutputSpeaker = struct {
    label: []const u8,
    is_lfe: bool = false,
    nominal_polar: PolarPosition,
    reproduction_polar: ?PolarPosition = null,
    allocentric: CartesianPosition,
};

pub const ScreenEdges = struct {
    left_azimuth_degrees: f64,
    right_azimuth_degrees: f64,
    bottom_elevation_degrees: f64,
    top_elevation_degrees: f64,
};

pub const DirectSpeakerRoutingContext = struct {
    screen_edges: ?ScreenEdges = null,
    /// Overrides the internal Cartesian screen-lock transform when supplied.
    cartesian_screen_locked_nominal: ?CartesianPosition = null,
};

pub const DirectSpeakerRoute = union(enum) {
    output: u8,
    discard,
    polar_panner: PolarPosition,
    cartesian_panner: CartesianPosition,
};

/// Computes directional gains from nominal and measured polar positions.
/// LFE outputs remain addressable by index but receive no panner gain.
pub fn PolarPointSourcePanner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "PolarPointSourcePanner supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();

        output_count: usize,
        core: adm_polar_panner.Panner(Sample),

        pub fn init(outputs: []const OutputSpeaker) !Self {
            try validateOutputLayout(outputs);
            var speakers: [maximum_output_channels]adm_polar_panner.Speaker =
                undefined;
            var speaker_count: usize = 0;
            for (outputs, 0..) |output, output_index| {
                if (output.is_lfe) continue;
                const label = normalizeSpeakerLabel(output.label) orelse
                    return error.InvalidAdmRendererSpeakerLabel;
                const reproduction =
                    output.reproduction_polar orelse output.nominal_polar;
                speakers[speaker_count] = .{
                    .output_index = @intCast(output_index),
                    .label = label,
                    .nominal = pannerPolarPosition(output.nominal_polar),
                    .actual = pannerPolarPosition(reproduction),
                };
                speaker_count += 1;
            }
            if (speaker_count < 2)
                return error.MissingAdmRendererPannerOutput;
            return .{
                .output_count = outputs.len,
                .core = try adm_polar_panner.Panner(Sample).init(
                    outputs.len,
                    speakers[0..speaker_count],
                ),
            };
        }

        pub fn calculateGains(
            self: *const Self,
            position: PolarPosition,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (!validPolar(position))
                return error.InvalidAdmRendererPolarPosition;
            try self.core.calculateGains(
                pannerPolarPosition(position),
                gains,
            );
        }

        pub fn mix(
            self: *const Self,
            position: PolarPosition,
            input_gain: Sample,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (!validPolar(position))
                return error.InvalidAdmRendererPolarPosition;
            try self.core.mix(
                pannerPolarPosition(position),
                input_gain,
                input,
                outputs,
            );
        }

        pub fn valid(self: *const Self) bool {
            return self.output_count > 0 and
                self.output_count <= maximum_output_channels and
                self.core.output_count == self.output_count and
                self.core.valid();
        }
    };
}

/// Computes bounded, energy-preserving gains for allocentric room positions.
/// The output layout is caller-owned; LFE speakers are retained but excluded.
pub fn CartesianPointSourcePanner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "CartesianPointSourcePanner supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();
        const layout_tolerance: f64 = 0.001;

        output_count: usize,
        panner_output_count: usize,
        positions: [maximum_output_channels]CartesianPosition = undefined,
        enabled: [maximum_output_channels]bool = undefined,

        pub fn init(outputs: []const OutputSpeaker) !Self {
            try validateOutputLayout(outputs);
            var result = Self{
                .output_count = outputs.len,
                .panner_output_count = 0,
            };
            for (outputs, 0..) |output, output_index| {
                result.positions[output_index] = output.allocentric;
                result.enabled[output_index] = !output.is_lfe;
                if (!output.is_lfe) result.panner_output_count += 1;
            }
            if (result.panner_output_count == 0)
                return error.MissingAdmRendererPannerOutput;
            try result.validateLayout();
            return result;
        }

        pub fn calculateGains(
            self: *const Self,
            position: CartesianPosition,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (gains.len != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            try validatePannerPosition(position);

            var raw_gains: [maximum_output_channels]f64 =
                @splat(0.0);
            var power: f64 = 0.0;
            for (0..self.output_count) |output_index| {
                if (!self.enabled[output_index]) continue;
                const value = self.outputGain(position, output_index);
                if (!std.math.isFinite(value) or value < 0.0)
                    return error.InvalidAdmRendererPannerGain;
                raw_gains[output_index] = value;
                power += value * value;
            }
            if (!std.math.isFinite(power) or power <= 0.0)
                return error.InvalidAdmRendererPannerGain;
            const normalization = 1.0 / @sqrt(power);
            for (gains, raw_gains[0..self.output_count]) |*gain, raw| {
                const normalized: Sample =
                    @floatCast(raw * normalization);
                if (!std.math.isFinite(normalized))
                    return error.InvalidAdmRendererPannerGain;
                gain.* = normalized;
            }
        }

        pub fn mix(
            self: *const Self,
            position: CartesianPosition,
            input_gain: Sample,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (!std.math.isFinite(input_gain))
                return error.InvalidAdmRendererGain;
            try validateMixBuffers(Sample, input, outputs, self.output_count);

            var gains: [maximum_output_channels]Sample = undefined;
            try self.calculateGains(position, gains[0..self.output_count]);
            for (outputs, gains[0..self.output_count]) |output, gain| {
                if (gain == 0.0) continue;
                const combined_gain = input_gain * gain;
                if (!std.math.isFinite(combined_gain))
                    return error.InvalidAdmRendererGain;
                for (input, output) |input_sample, *output_sample| {
                    if (!std.math.isFinite(input_sample)) continue;
                    if (!std.math.isFinite(output_sample.*)) {
                        output_sample.* = 0.0;
                        continue;
                    }
                    const mixed =
                        output_sample.* + input_sample * combined_gain;
                    output_sample.* = if (std.math.isFinite(mixed))
                        mixed
                    else
                        0.0;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels or
                self.panner_output_count == 0 or
                self.panner_output_count > self.output_count)
            {
                return false;
            }
            var enabled_count: usize = 0;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, enabled| {
                if (!validCartesian(position)) return false;
                if (!enabled) continue;
                enabled_count += 1;
            }
            if (enabled_count != self.panner_output_count) return false;
            self.validateLayout() catch return false;
            return true;
        }

        fn validateLayout(self: *const Self) !void {
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
                0..,
            ) |position, enabled, index| {
                if (!enabled) continue;
                if (!insideUnitCube(position, layout_tolerance) or
                    !onUnitCubeSurface(position, layout_tolerance))
                {
                    return error.InvalidAdmRendererCartesianLayout;
                }
                for (0..index) |previous| {
                    if (self.enabled[previous] and
                        samePosition(
                            position,
                            self.positions[previous],
                            layout_tolerance,
                        ))
                    {
                        return error.DuplicateAdmRendererSpeakerPosition;
                    }
                }
            }

            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, enabled| {
                if (!enabled or
                    @abs(position.y) >= 1.0 - layout_tolerance)
                {
                    continue;
                }
                var has_left = false;
                var has_right = false;
                for (
                    self.positions[0..self.output_count],
                    self.enabled[0..self.output_count],
                ) |candidate, candidate_enabled| {
                    if (!candidate_enabled or
                        @abs(candidate.z - position.z) >= layout_tolerance or
                        @abs(candidate.y - position.y) >= layout_tolerance)
                    {
                        continue;
                    }
                    has_left = has_left or
                        @abs(candidate.x + 1.0) < layout_tolerance;
                    has_right = has_right or
                        @abs(candidate.x - 1.0) < layout_tolerance;
                }
                if (!has_left or !has_right)
                    return error.InvalidAdmRendererCartesianLayout;
            }
        }

        fn outputGain(
            self: *const Self,
            object: CartesianPosition,
            output_index: usize,
        ) f64 {
            const relative = subtractPosition(
                self.positions[output_index],
                object,
            );
            const z_gain = self.axisGain(
                relative.z,
                .z,
                relative,
                object,
            );
            const y_gain = self.axisGain(
                relative.y,
                .y,
                relative,
                object,
            );
            const x_gain = self.axisGain(
                relative.x,
                .x,
                relative,
                object,
            );
            return x_gain * y_gain * z_gain;
        }

        const Axis = enum { x, y, z };

        fn axisGain(
            self: *const Self,
            coordinate: f64,
            axis: Axis,
            reference: CartesianPosition,
            object: CartesianPosition,
        ) f64 {
            var other: ?f64 = null;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, enabled| {
                if (!enabled) continue;
                const relative = subtractPosition(position, object);
                if (!axisCandidate(relative, reference, axis, layout_tolerance))
                    continue;
                const candidate = axisCoordinate(relative, axis);
                if (coordinate >= 0.0) {
                    if (candidate >= coordinate) continue;
                    if (other) |current| {
                        if (candidate > current) other = candidate;
                    } else {
                        other = candidate;
                    }
                } else {
                    if (candidate <= coordinate) continue;
                    if (other) |current| {
                        if (candidate < current) other = candidate;
                    } else {
                        other = candidate;
                    }
                }
            }
            const opposite = other orelse return 1.0;
            if (sameSign(opposite, coordinate)) return 0.0;
            return @cos(
                coordinate / (opposite - coordinate) *
                    std.math.pi / 2.0,
            );
        }

        fn axisCandidate(
            candidate: CartesianPosition,
            reference: CartesianPosition,
            axis: Axis,
            tolerance: f64,
        ) bool {
            return switch (axis) {
                .z => true,
                .y => @abs(candidate.z - reference.z) < tolerance,
                .x => @abs(candidate.z - reference.z) < tolerance and
                    @abs(candidate.y - reference.y) < tolerance,
            };
        }

        fn axisCoordinate(position: CartesianPosition, axis: Axis) f64 {
            return switch (axis) {
                .x => position.x,
                .y => position.y,
                .z => position.z,
            };
        }
    };
}

pub fn StaticMatrixMixer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("StaticMatrixMixer supports f32 and f64 samples");

    return struct {
        const Self = @This();

        input_count: usize,
        term_count: usize,
        input_indices: [maximum_input_channels]u8 = undefined,
        gains: [maximum_input_channels]Sample = undefined,

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
                self.term_count == 0 or
                self.term_count > maximum_input_channels)
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

pub fn DirectSpeakerRouter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DirectSpeakerRouter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        output_count: usize,
        output_index: u8,
        gain: Sample,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            output_labels: []const []const u8,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0001 or
                block.channel_identifier.typeLabel() != 0x0001)
            {
                return error.AdmRendererRequiresDirectSpeakersBlock;
            }
            if (output_labels.len == 0 or
                output_labels.len > maximum_output_channels)
            {
                return error.InvalidAdmRendererOutputCount;
            }
            for (output_labels, 0..) |label, index| {
                if (label.len == 0 or
                    label.len > adm_xml.max_adm_speaker_label_bytes or
                    !std.unicode.utf8ValidateSlice(label))
                {
                    return error.InvalidAdmRendererSpeakerLabel;
                }
                for (output_labels[0..index]) |previous| {
                    if (std.mem.eql(u8, label, previous))
                        return error.DuplicateAdmRendererSpeakerLabel;
                }
            }

            var matched_output: ?usize = null;
            for (block.speakerLabelSlice()) |speaker_label| {
                for (output_labels, 0..) |output_label, output_index| {
                    if (!std.mem.eql(
                        u8,
                        speaker_label.value(),
                        output_label,
                    )) {
                        continue;
                    }
                    if (matched_output) |previous| {
                        if (previous != output_index)
                            return error.AmbiguousAdmRendererSpeakerRoute;
                    } else {
                        matched_output = output_index;
                    }
                }
            }
            const output_index = matched_output orelse
                return error.MissingAdmRendererSpeakerRoute;
            return .{
                .output_count = output_labels.len,
                .output_index = @intCast(output_index),
                .gain = try renderGain(Sample, block.gain),
            };
        }

        pub fn processSample(
            self: *const Self,
            input: Sample,
        ) Sample {
            if (!self.valid() or !std.math.isFinite(input)) return 0.0;
            const output = input * self.gain;
            return if (std.math.isFinite(output)) output else 0.0;
        }

        pub fn mix(
            self: *const Self,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (outputs.len != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            for (outputs, 0..) |output, output_index| {
                if (output.len != input.len)
                    return error.AdmRendererBufferLengthMismatch;
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, previous, output))
                        return error.AdmRendererAliasedBuffers;
                }
            }
            const target = outputs[self.output_index];
            if (slicesOverlap(Sample, input, target))
                return error.AdmRendererAliasedBuffers;

            for (input, target) |input_sample, *output_sample| {
                if (!std.math.isFinite(input_sample)) continue;
                if (!std.math.isFinite(output_sample.*)) {
                    output_sample.* = 0.0;
                    continue;
                }
                const mixed = output_sample.* + input_sample * self.gain;
                output_sample.* = if (std.math.isFinite(mixed))
                    mixed
                else
                    0.0;
            }
        }

        pub fn valid(self: *const Self) bool {
            return self.output_count > 0 and
                self.output_count <= maximum_output_channels and
                self.output_index < self.output_count and
                std.math.isFinite(self.gain);
        }
    };
}

pub fn DirectSpeakerPositionRouter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "DirectSpeakerPositionRouter supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();

        output_count: usize,
        route: DirectSpeakerRoute,
        gain: Sample,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            context: DirectSpeakerRoutingContext,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0001 or
                block.channel_identifier.typeLabel() != 0x0001)
            {
                return error.AdmRendererRequiresDirectSpeakersBlock;
            }
            const route = try resolveDirectSpeakerRoute(
                block,
                outputs,
                context,
            );
            return .{
                .output_count = outputs.len,
                .route = route,
                .gain = try renderGain(Sample, block.gain),
            };
        }

        pub fn processSample(
            self: *const Self,
            input: Sample,
        ) !Sample {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (!std.math.isFinite(input)) return 0.0;
            return switch (self.route) {
                .output => blk: {
                    const output = input * self.gain;
                    break :blk if (std.math.isFinite(output))
                        output
                    else
                        0.0;
                },
                .discard => 0.0,
                .polar_panner, .cartesian_panner => {
                    return error.AdmRendererPointPannerRequired;
                },
            };
        }

        pub fn mix(
            self: *const Self,
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (outputs.len != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            for (outputs, 0..) |output, output_index| {
                if (output.len != input.len)
                    return error.AdmRendererBufferLengthMismatch;
                for (outputs[0..output_index]) |previous| {
                    if (slicesOverlap(Sample, previous, output))
                        return error.AdmRendererAliasedBuffers;
                }
            }

            const output_index = switch (self.route) {
                .output => |index| index,
                .discard => return,
                .polar_panner, .cartesian_panner => {
                    return error.AdmRendererPointPannerRequired;
                },
            };
            const target = outputs[output_index];
            if (slicesOverlap(Sample, input, target))
                return error.AdmRendererAliasedBuffers;
            for (input, target) |input_sample, *output_sample| {
                if (!std.math.isFinite(input_sample)) continue;
                if (!std.math.isFinite(output_sample.*)) {
                    output_sample.* = 0.0;
                    continue;
                }
                const mixed = output_sample.* + input_sample * self.gain;
                output_sample.* = if (std.math.isFinite(mixed))
                    mixed
                else
                    0.0;
            }
        }

        pub fn mixWithCartesianFallback(
            self: *const Self,
            panner: *const CartesianPointSourcePanner(Sample),
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (panner.output_count != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            switch (self.route) {
                .cartesian_panner => |position| try panner.mix(
                    position,
                    self.gain,
                    input,
                    outputs,
                ),
                .polar_panner => {
                    return error.AdmRendererPolarPointPannerRequired;
                },
                .output, .discard => try self.mix(input, outputs),
            }
        }

        pub fn mixWithPolarFallback(
            self: *const Self,
            panner: *const PolarPointSourcePanner(Sample),
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (panner.output_count != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            switch (self.route) {
                .polar_panner => |position| try panner.mix(
                    position,
                    self.gain,
                    input,
                    outputs,
                ),
                .cartesian_panner => {
                    return error.AdmRendererCartesianPointPannerRequired;
                },
                .output, .discard => try self.mix(input, outputs),
            }
        }

        pub fn mixWithPointSourceFallback(
            self: *const Self,
            polar_panner: *const PolarPointSourcePanner(Sample),
            cartesian_panner: *const CartesianPointSourcePanner(Sample),
            input: []const Sample,
            outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (polar_panner.output_count != self.output_count or
                cartesian_panner.output_count != self.output_count)
            {
                return error.AdmRendererOutputCountMismatch;
            }
            switch (self.route) {
                .polar_panner => |position| try polar_panner.mix(
                    position,
                    self.gain,
                    input,
                    outputs,
                ),
                .cartesian_panner => |position| try cartesian_panner.mix(
                    position,
                    self.gain,
                    input,
                    outputs,
                ),
                .output, .discard => try self.mix(input, outputs),
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels or
                !std.math.isFinite(self.gain))
            {
                return false;
            }
            return switch (self.route) {
                .output => |index| index < self.output_count,
                .discard => true,
                .polar_panner => |position| validPolar(position),
                .cartesian_panner => |position| validCartesian(position),
            };
        }
    };
}

pub fn resolveDirectSpeakerRoute(
    block: *const adm_xml.BlockFormat,
    outputs: []const OutputSpeaker,
    context: DirectSpeakerRoutingContext,
) !DirectSpeakerRoute {
    if (block.identifier.typeLabel() != 0x0001 or
        block.channel_identifier.typeLabel() != 0x0001)
    {
        return error.AdmRendererRequiresDirectSpeakersBlock;
    }
    try validateOutputLayout(outputs);
    const input_is_lfe = directSpeakerIsLfe(block);

    for (block.speakerLabelSlice()) |speaker_label| {
        const normalized = normalizeSpeakerLabel(
            speaker_label.value(),
        ) orelse continue;
        for (outputs, 0..) |output, output_index| {
            if (output.is_lfe != input_is_lfe) continue;
            const output_label = normalizeSpeakerLabel(output.label) orelse
                return error.InvalidAdmRendererSpeakerLabel;
            if (std.mem.eql(u8, normalized, output_label)) {
                return .{ .output = @intCast(output_index) };
            }
        }
    }

    if (block.cartesian) {
        const bounds = try cartesianBounds(block);
        var nominal = CartesianPosition{
            .x = bounds.x.nominal,
            .y = bounds.y.nominal,
            .z = bounds.z.nominal,
        };
        if (hasScreenEdgeLock(block)) {
            if (context.cartesian_screen_locked_nominal) |transformed| {
                nominal = transformed;
                if (!validCartesian(nominal))
                    return error.InvalidAdmRendererScreenGeometry;
            } else if (context.screen_edges) |screen_edges| {
                try validateScreenEdges(screen_edges);
                var polar_nominal =
                    try admCartesianToPolar(nominal);
                applyPolarScreenEdgeLock(
                    block,
                    screen_edges,
                    &polar_nominal,
                );
                compensateCartesianScreenPosition(
                    outputs,
                    &polar_nominal,
                );
                nominal = try admPolarToCartesian(polar_nominal);
            }
        }
        if (try closestCartesianOutput(
            outputs,
            bounds,
            nominal,
            input_is_lfe,
        )) |output_index| {
            return .{ .output = @intCast(output_index) };
        }
        if (!input_is_lfe)
            return .{ .cartesian_panner = nominal };
    } else {
        const bounds = try polarBounds(block);
        var nominal = PolarPosition{
            .azimuth_degrees = bounds.azimuth.nominal,
            .elevation_degrees = bounds.elevation.nominal,
            .distance = bounds.distance.nominal,
        };
        if (context.screen_edges) |screen_edges| {
            try validateScreenEdges(screen_edges);
            applyPolarScreenEdgeLock(block, screen_edges, &nominal);
        }
        if (try closestPolarOutput(
            outputs,
            bounds,
            nominal,
            input_is_lfe,
        )) |output_index| {
            return .{ .output = @intCast(output_index) };
        }
        if (!input_is_lfe)
            return .{ .polar_panner = nominal };
    }

    for (outputs, 0..) |output, output_index| {
        const label = normalizeSpeakerLabel(output.label) orelse
            return error.InvalidAdmRendererSpeakerLabel;
        if (output.is_lfe and std.mem.eql(u8, label, "LFE1"))
            return .{ .output = @intCast(output_index) };
    }
    return .discard;
}

const CoordinateBounds = struct {
    nominal: f64,
    minimum: f64,
    maximum: f64,
};

const PolarBounds = struct {
    azimuth: CoordinateBounds,
    elevation: CoordinateBounds,
    distance: CoordinateBounds,
};

const CartesianBounds = struct {
    x: CoordinateBounds,
    y: CoordinateBounds,
    z: CoordinateBounds,
};

fn validateOutputLayout(outputs: []const OutputSpeaker) !void {
    if (outputs.len == 0 or outputs.len > maximum_output_channels)
        return error.InvalidAdmRendererOutputCount;
    for (outputs, 0..) |output, index| {
        const label = normalizeSpeakerLabel(output.label) orelse
            return error.InvalidAdmRendererSpeakerLabel;
        if (!validPolar(output.nominal_polar) or
            !validCartesian(output.allocentric))
        {
            return error.InvalidAdmRendererSpeakerPosition;
        }
        if (output.reproduction_polar) |position| {
            if (!validPolar(position))
                return error.InvalidAdmRendererSpeakerPosition;
        }
        const label_is_lfe = std.mem.eql(u8, label, "LFE1") or
            std.mem.eql(u8, label, "LFE2");
        if (label_is_lfe != output.is_lfe)
            return error.InvalidAdmRendererSpeakerType;
        for (outputs[0..index]) |previous| {
            const previous_label =
                normalizeSpeakerLabel(previous.label) orelse
                return error.InvalidAdmRendererSpeakerLabel;
            if (std.mem.eql(u8, label, previous_label))
                return error.DuplicateAdmRendererSpeakerLabel;
        }
    }
}

fn directSpeakerIsLfe(block: *const adm_xml.BlockFormat) bool {
    if (block.channel_frequency.isLfe()) return true;
    for (block.speakerLabelSlice()) |speaker_label| {
        const label = normalizeSpeakerLabel(
            speaker_label.value(),
        ) orelse continue;
        if (std.mem.eql(u8, label, "LFE1") or
            std.mem.eql(u8, label, "LFE2"))
        {
            return true;
        }
    }
    return false;
}

fn normalizeSpeakerLabel(label: []const u8) ?[]const u8 {
    var normalized = label;
    const urn_prefix = "urn:itu:bs:2051:";
    if (std.mem.startsWith(u8, normalized, urn_prefix)) {
        const remainder = normalized[urn_prefix.len..];
        const separator = std.mem.indexOfScalar(u8, remainder, ':') orelse
            return null;
        if (separator == 0) return null;
        for (remainder[0..separator]) |byte| {
            if (!std.ascii.isDigit(byte)) return null;
        }
        const speaker_prefix = "speaker:";
        const suffix = remainder[separator + 1 ..];
        if (!std.mem.startsWith(u8, suffix, speaker_prefix)) return null;
        normalized = suffix[speaker_prefix.len..];
    }
    if (std.mem.eql(u8, normalized, "LFE") or
        std.mem.eql(u8, normalized, "LFEL"))
    {
        normalized = "LFE1";
    } else if (std.mem.eql(u8, normalized, "LFER")) {
        normalized = "LFE2";
    }
    const standard_labels = [_][]const u8{
        "M+000", "M+030",  "M-030", "M+SC",  "M-SC",
        "M+060", "M-060",  "M+090", "M-090", "M+110",
        "M-110", "M+135",  "M-135", "M+180", "U+000",
        "U+030", "U-030",  "U+045", "U-045", "U+090",
        "U-090", "U+110",  "U-110", "U+135", "U-135",
        "U+180", "UH+180", "B+000", "B+045", "B-045",
        "T+000", "LFE1",   "LFE2",
    };
    for (standard_labels) |standard| {
        if (std.mem.eql(u8, normalized, standard)) return normalized;
    }
    return null;
}

fn polarBounds(block: *const adm_xml.BlockFormat) !PolarBounds {
    return .{
        .azimuth = try coordinateBounds(block, .azimuth, 0.0),
        .elevation = try coordinateBounds(block, .elevation, 0.0),
        .distance = try coordinateBounds(block, .distance, 1.0),
    };
}

fn cartesianBounds(block: *const adm_xml.BlockFormat) !CartesianBounds {
    return .{
        .x = try coordinateBounds(block, .x, 0.0),
        .y = try coordinateBounds(block, .y, 0.0),
        .z = try coordinateBounds(block, .z, 0.0),
    };
}

fn coordinateBounds(
    block: *const adm_xml.BlockFormat,
    coordinate: adm_xml.Coordinate,
    default_nominal: f64,
) !CoordinateBounds {
    var nominal: ?f64 = null;
    var minimum: ?f64 = null;
    var maximum: ?f64 = null;
    for (block.positionSlice()) |position| {
        if (position.coordinate != coordinate) continue;
        switch (position.bound) {
            .exact => nominal = position.value,
            .minimum => minimum = position.value,
            .maximum => maximum = position.value,
        }
    }
    const value = nominal orelse default_nominal;
    const result = CoordinateBounds{
        .nominal = value,
        .minimum = minimum orelse value,
        .maximum = maximum orelse value,
    };
    if (!std.math.isFinite(result.nominal) or
        !std.math.isFinite(result.minimum) or
        !std.math.isFinite(result.maximum))
    {
        return error.InvalidAdmRendererPositionBounds;
    }
    if (coordinate == .azimuth) {
        if (!insideAngleRange(
            result.nominal,
            result.minimum,
            result.maximum,
            0.0,
        )) {
            return error.InvalidAdmRendererPositionBounds;
        }
    } else if (result.minimum > result.maximum or
        result.nominal < result.minimum or
        result.nominal > result.maximum)
    {
        return error.InvalidAdmRendererPositionBounds;
    }
    return result;
}

fn closestPolarOutput(
    outputs: []const OutputSpeaker,
    bounds: PolarBounds,
    nominal: PolarPosition,
    input_is_lfe: bool,
) !?usize {
    const target = polarToCartesian(nominal);
    var closest: ?usize = null;
    var closest_distance: f64 = std.math.inf(f64);
    var tied = false;
    for (outputs, 0..) |output, output_index| {
        if (output.is_lfe != input_is_lfe or
            !polarWithinBounds(output.nominal_polar, bounds))
        {
            continue;
        }
        const distance = cartesianDistance(
            polarToCartesian(output.nominal_polar),
            target,
        );
        if (!std.math.isFinite(distance))
            return error.InvalidAdmRendererSpeakerPosition;
        if (distance < closest_distance - position_tolerance) {
            closest = output_index;
            closest_distance = distance;
            tied = false;
        } else if (@abs(distance - closest_distance) < position_tolerance) {
            tied = true;
        }
    }
    return if (tied) null else closest;
}

fn closestCartesianOutput(
    outputs: []const OutputSpeaker,
    bounds: CartesianBounds,
    nominal: CartesianPosition,
    input_is_lfe: bool,
) !?usize {
    var closest: ?usize = null;
    var closest_distance: f64 = std.math.inf(f64);
    var tied = false;
    for (outputs, 0..) |output, output_index| {
        if (output.is_lfe != input_is_lfe or
            !cartesianWithinBounds(output.allocentric, bounds))
        {
            continue;
        }
        const distance = cartesianDistance(output.allocentric, nominal);
        if (!std.math.isFinite(distance))
            return error.InvalidAdmRendererSpeakerPosition;
        if (distance < closest_distance - position_tolerance) {
            closest = output_index;
            closest_distance = distance;
            tied = false;
        } else if (@abs(distance - closest_distance) < position_tolerance) {
            tied = true;
        }
    }
    return if (tied) null else closest;
}

fn polarWithinBounds(
    speaker: PolarPosition,
    bounds: PolarBounds,
) bool {
    return (insideAngleRange(
        speaker.azimuth_degrees,
        bounds.azimuth.minimum,
        bounds.azimuth.maximum,
        position_tolerance,
    ) or
        @abs(speaker.elevation_degrees) >= 90.0 - position_tolerance) and
        speaker.elevation_degrees >=
            bounds.elevation.minimum - position_tolerance and
        speaker.elevation_degrees <=
            bounds.elevation.maximum + position_tolerance and
        speaker.distance >= bounds.distance.minimum - position_tolerance and
        speaker.distance <= bounds.distance.maximum + position_tolerance;
}

fn cartesianWithinBounds(
    speaker: CartesianPosition,
    bounds: CartesianBounds,
) bool {
    return withinLinearBounds(speaker.x, bounds.x) and
        withinLinearBounds(speaker.y, bounds.y) and
        withinLinearBounds(speaker.z, bounds.z);
}

fn withinLinearBounds(value: f64, bounds: CoordinateBounds) bool {
    return value >= bounds.minimum - position_tolerance and
        value <= bounds.maximum + position_tolerance;
}

fn insideAngleRange(
    angle: f64,
    start: f64,
    end: f64,
    tolerance: f64,
) bool {
    if (start == -180.0 and end == 180.0) return true;
    const arc = positiveAngle(end - start);
    const offset = positiveAngle(angle - start);
    return offset <= arc + tolerance or
        offset >= 360.0 - tolerance;
}

fn positiveAngle(angle: f64) f64 {
    var normalized = @mod(angle, 360.0);
    if (normalized < 0.0) normalized += 360.0;
    return normalized;
}

fn polarToCartesian(position: PolarPosition) CartesianPosition {
    const azimuth =
        -position.azimuth_degrees * std.math.pi / 180.0;
    const elevation =
        position.elevation_degrees * std.math.pi / 180.0;
    const elevation_cosine = @cos(elevation);
    return .{
        .x = @sin(azimuth) * elevation_cosine * position.distance,
        .y = @cos(azimuth) * elevation_cosine * position.distance,
        .z = @sin(elevation) * position.distance,
    };
}

const ConversionSector = struct {
    left_azimuth: f64,
    right_azimuth: f64,
    left_x: f64,
    left_y: f64,
    right_x: f64,
    right_y: f64,
};

fn admPolarToCartesian(position: PolarPosition) !CartesianPosition {
    if (!validPolar(position))
        return error.InvalidAdmRendererCartesianPosition;

    const absolute_elevation = @abs(position.elevation_degrees);
    var planar_radius: f64 = undefined;
    var z: f64 = undefined;
    if (absolute_elevation > 30.0) {
        const adjusted_elevation =
            45.0 + (90.0 - 45.0) *
                (absolute_elevation - 30.0) / (90.0 - 30.0);
        z = position.distance * signValue(position.elevation_degrees);
        planar_radius = position.distance * @tan(
            degreesToRadians(90.0 - adjusted_elevation),
        );
    } else {
        const adjusted_elevation =
            45.0 * position.elevation_degrees / 30.0;
        z = position.distance * @tan(
            degreesToRadians(adjusted_elevation),
        );
        planar_radius = position.distance;
    }

    const sector = findConversionSector(
        position.azimuth_degrees,
        false,
    );
    const azimuth = relativeAngle(
        sector.right_azimuth,
        position.azimuth_degrees,
    );
    const left_azimuth = relativeAngle(
        sector.right_azimuth,
        sector.left_azimuth,
    );
    const proportion = mapAzimuthToLinear(
        left_azimuth,
        sector.right_azimuth,
        azimuth,
    );
    const result = CartesianPosition{
        .x = planar_radius *
            (sector.left_x +
                proportion * (sector.right_x - sector.left_x)),
        .y = planar_radius *
            (sector.left_y +
                proportion * (sector.right_y - sector.left_y)),
        .z = z,
    };
    if (!validCartesian(result))
        return error.InvalidAdmRendererCartesianPosition;
    return result;
}

fn admCartesianToPolar(position: CartesianPosition) !PolarPosition {
    try validatePannerPosition(position);
    const conversion_epsilon = 1.0e-10;
    if (@abs(position.x) < conversion_epsilon and
        @abs(position.y) < conversion_epsilon)
    {
        if (@abs(position.z) < conversion_epsilon) {
            return .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
                .distance = 0,
            };
        }
        return .{
            .azimuth_degrees = 0,
            .elevation_degrees = 90.0 * signValue(position.z),
            .distance = @abs(position.z),
        };
    }

    const geometric_azimuth =
        -radiansToDegrees(std.math.atan2(position.x, position.y));
    const sector = findConversionSector(geometric_azimuth, true);
    const determinant =
        sector.left_x * sector.right_y -
        sector.left_y * sector.right_x;
    if (@abs(determinant) < conversion_epsilon)
        return error.InvalidAdmRendererCartesianPosition;
    const left_gain =
        (position.x * sector.right_y -
            position.y * sector.right_x) / determinant;
    const right_gain =
        (position.y * sector.left_x -
            position.x * sector.left_y) / determinant;
    const planar_radius = left_gain + right_gain;
    if (!std.math.isFinite(planar_radius) or
        planar_radius <= conversion_epsilon)
    {
        return error.InvalidAdmRendererCartesianPosition;
    }

    const left_azimuth = relativeAngle(
        sector.right_azimuth,
        sector.left_azimuth,
    );
    const mapped_azimuth = mapLinearToAzimuth(
        left_azimuth,
        sector.right_azimuth,
        right_gain / planar_radius,
    );
    const azimuth = relativeAngle(-180.0, mapped_azimuth);
    const adjusted_elevation = radiansToDegrees(
        std.math.atan(position.z / planar_radius),
    );
    var elevation: f64 = undefined;
    var distance: f64 = undefined;
    if (@abs(adjusted_elevation) > 45.0) {
        const absolute_elevation =
            30.0 + (90.0 - 30.0) *
                (@abs(adjusted_elevation) - 45.0) / (90.0 - 45.0);
        elevation = absolute_elevation *
            signValue(adjusted_elevation);
        distance = @abs(position.z);
    } else {
        elevation = adjusted_elevation * 30.0 / 45.0;
        distance = planar_radius;
    }
    const result = PolarPosition{
        .azimuth_degrees = if (azimuth > 180.0)
            azimuth - 360.0
        else
            azimuth,
        .elevation_degrees = elevation,
        .distance = distance,
    };
    if (!validPolar(result))
        return error.InvalidAdmRendererCartesianPosition;
    return result;
}

fn findConversionSector(
    azimuth: f64,
    cartesian_input: bool,
) ConversionSector {
    const front_limit: f64 = if (cartesian_input) 45.0 else 30.0;
    const side_limit: f64 = if (cartesian_input) 135.0 else 110.0;
    if (insideAngleRange(azimuth, 0.0, front_limit, 0.0)) {
        return .{
            .left_azimuth = 30,
            .right_azimuth = 0,
            .left_x = -1,
            .left_y = 1,
            .right_x = 0,
            .right_y = 1,
        };
    }
    if (insideAngleRange(azimuth, -front_limit, 0.0, 0.0)) {
        return .{
            .left_azimuth = 0,
            .right_azimuth = -30,
            .left_x = 0,
            .left_y = 1,
            .right_x = 1,
            .right_y = 1,
        };
    }
    if (insideAngleRange(
        azimuth,
        -side_limit,
        -front_limit,
        0.0,
    )) {
        return .{
            .left_azimuth = -30,
            .right_azimuth = -110,
            .left_x = 1,
            .left_y = 1,
            .right_x = 1,
            .right_y = -1,
        };
    }
    if (insideAngleRange(
        azimuth,
        side_limit,
        -side_limit,
        0.0,
    )) {
        return .{
            .left_azimuth = -110,
            .right_azimuth = 110,
            .left_x = 1,
            .left_y = -1,
            .right_x = -1,
            .right_y = -1,
        };
    }
    return .{
        .left_azimuth = 110,
        .right_azimuth = 30,
        .left_x = -1,
        .left_y = -1,
        .right_x = -1,
        .right_y = 1,
    };
}

fn mapAzimuthToLinear(
    left_azimuth: f64,
    right_azimuth: f64,
    azimuth: f64,
) f64 {
    const midpoint = (left_azimuth + right_azimuth) * 0.5;
    const range = right_azimuth - midpoint;
    const relative = azimuth - midpoint;
    const right_gain = 0.5 +
        @tan(degreesToRadians(relative)) /
            (2.0 * @tan(degreesToRadians(range)));
    return 2.0 / std.math.pi *
        std.math.atan2(right_gain, 1.0 - right_gain);
}

fn mapLinearToAzimuth(
    left_azimuth: f64,
    right_azimuth: f64,
    linear: f64,
) f64 {
    const midpoint = (left_azimuth + right_azimuth) * 0.5;
    const range = right_azimuth - midpoint;
    const left_gain = @cos(linear * std.math.pi / 2.0);
    const right_gain = @sin(linear * std.math.pi / 2.0);
    const normalized_right = right_gain / (left_gain + right_gain);
    const relative = radiansToDegrees(std.math.atan(
        2.0 * (normalized_right - 0.5) *
            @tan(degreesToRadians(range)),
    ));
    return midpoint + relative;
}

fn relativeAngle(minimum: f64, angle: f64) f64 {
    if (angle >= minimum) return angle;
    return angle +
        360.0 * @ceil((minimum - angle) / 360.0);
}

fn degreesToRadians(degrees: f64) f64 {
    return degrees * std.math.pi / 180.0;
}

fn radiansToDegrees(radians: f64) f64 {
    return radians * 180.0 / std.math.pi;
}

fn signValue(value: f64) f64 {
    if (value > 0.0) return 1.0;
    if (value < 0.0) return -1.0;
    return 0.0;
}

fn cartesianDistance(
    left: CartesianPosition,
    right: CartesianPosition,
) f64 {
    const x = left.x - right.x;
    const y = left.y - right.y;
    const z = left.z - right.z;
    return @sqrt(x * x + y * y + z * z);
}

fn validPolar(position: PolarPosition) bool {
    return std.math.isFinite(position.azimuth_degrees) and
        std.math.isFinite(position.elevation_degrees) and
        std.math.isFinite(position.distance) and
        position.azimuth_degrees >= -180.0 and
        position.azimuth_degrees <= 180.0 and
        position.elevation_degrees >= -90.0 and
        position.elevation_degrees <= 90.0 and
        position.distance >= 0.0;
}

fn pannerPolarPosition(
    position: PolarPosition,
) adm_polar_panner.PolarPosition {
    return .{
        .azimuth_degrees = position.azimuth_degrees,
        .elevation_degrees = position.elevation_degrees,
    };
}

fn validCartesian(position: CartesianPosition) bool {
    return std.math.isFinite(position.x) and
        std.math.isFinite(position.y) and
        std.math.isFinite(position.z);
}

fn validatePannerPosition(position: CartesianPosition) !void {
    if (!validCartesian(position) or !insideUnitCube(position, 0.0))
        return error.InvalidAdmRendererCartesianPosition;
}

fn insideUnitCube(position: CartesianPosition, tolerance: f64) bool {
    return @abs(position.x) <= 1.0 + tolerance and
        @abs(position.y) <= 1.0 + tolerance and
        @abs(position.z) <= 1.0 + tolerance;
}

fn onUnitCubeSurface(position: CartesianPosition, tolerance: f64) bool {
    return @abs(@abs(position.x) - 1.0) < tolerance or
        @abs(@abs(position.y) - 1.0) < tolerance or
        @abs(@abs(position.z) - 1.0) < tolerance;
}

fn samePosition(
    left: CartesianPosition,
    right: CartesianPosition,
    tolerance: f64,
) bool {
    return @abs(left.x - right.x) < tolerance and
        @abs(left.y - right.y) < tolerance and
        @abs(left.z - right.z) < tolerance;
}

fn subtractPosition(
    left: CartesianPosition,
    right: CartesianPosition,
) CartesianPosition {
    return .{
        .x = left.x - right.x,
        .y = left.y - right.y,
        .z = left.z - right.z,
    };
}

fn sameSign(left: f64, right: f64) bool {
    return (left > 0.0 and right > 0.0) or
        (left < 0.0 and right < 0.0) or
        (left == 0.0 and right == 0.0);
}

fn hasScreenEdgeLock(block: *const adm_xml.BlockFormat) bool {
    for (block.positionSlice()) |position| {
        if (position.screen_edge_lock != null) return true;
    }
    return false;
}

fn validateScreenEdges(edges: ScreenEdges) !void {
    if (!std.math.isFinite(edges.left_azimuth_degrees) or
        !std.math.isFinite(edges.right_azimuth_degrees) or
        !std.math.isFinite(edges.bottom_elevation_degrees) or
        !std.math.isFinite(edges.top_elevation_degrees) or
        edges.left_azimuth_degrees < -180.0 or
        edges.left_azimuth_degrees > 180.0 or
        edges.right_azimuth_degrees < -180.0 or
        edges.right_azimuth_degrees > 180.0 or
        edges.bottom_elevation_degrees < -90.0 or
        edges.bottom_elevation_degrees > 90.0 or
        edges.top_elevation_degrees < -90.0 or
        edges.top_elevation_degrees > 90.0 or
        edges.bottom_elevation_degrees > edges.top_elevation_degrees)
    {
        return error.InvalidAdmRendererScreenGeometry;
    }
}

fn applyPolarScreenEdgeLock(
    block: *const adm_xml.BlockFormat,
    edges: ScreenEdges,
    nominal: *PolarPosition,
) void {
    for (block.positionSlice()) |position| {
        if (position.bound != .exact) continue;
        const edge = position.screen_edge_lock orelse continue;
        switch (edge) {
            .left => nominal.azimuth_degrees =
                edges.left_azimuth_degrees,
            .right => nominal.azimuth_degrees =
                edges.right_azimuth_degrees,
            .bottom => nominal.elevation_degrees =
                edges.bottom_elevation_degrees,
            .top => nominal.elevation_degrees =
                edges.top_elevation_degrees,
        }
    }
}

fn compensateCartesianScreenPosition(
    outputs: []const OutputSpeaker,
    position: *PolarPosition,
) void {
    var has_upper_front_45 = false;
    for (outputs) |output| {
        const label = normalizeSpeakerLabel(output.label) orelse continue;
        if (std.mem.eql(u8, label, "U+045")) {
            has_upper_front_45 = true;
            break;
        }
    }
    if (!has_upper_front_45) return;

    const azimuth_radius = piecewiseLinear(
        position.elevation_degrees,
        &.{ -90.0, 0.0, 30.0, 90.0 },
        &.{ 30.0, 30.0, 20.0, 30.0 },
    );
    position.azimuth_degrees = piecewiseLinear(
        position.azimuth_degrees,
        &.{ -180.0, -30.0, 30.0, 180.0 },
        &.{ -180.0, -azimuth_radius, azimuth_radius, 180.0 },
    );
}

fn piecewiseLinear(
    value: f64,
    inputs: *const [4]f64,
    outputs: *const [4]f64,
) f64 {
    if (value <= inputs[0]) return outputs[0];
    for (1..inputs.len) |index| {
        if (value > inputs[index]) continue;
        const proportion =
            (value - inputs[index - 1]) /
            (inputs[index] - inputs[index - 1]);
        return outputs[index - 1] +
            proportion * (outputs[index] - outputs[index - 1]);
    }
    return outputs[outputs.len - 1];
}

fn renderGain(
    comptime Sample: type,
    gain_value: adm_xml.Gain,
) !Sample {
    const linear_gain = switch (gain_value.unit) {
        .linear => gain_value.value,
        .decibels => if (std.math.isInf(gain_value.value) and
            gain_value.value < 0.0)
            0.0
        else
            std.math.pow(f64, 10.0, gain_value.value / 20.0),
    };
    const gain: Sample = @floatCast(linear_gain);
    if (!std.math.isFinite(gain))
        return error.InvalidAdmRendererGain;
    return gain;
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

fn validateMixBuffers(
    comptime Sample: type,
    input: []const Sample,
    outputs: []const []Sample,
    expected_output_count: usize,
) !void {
    if (outputs.len != expected_output_count)
        return error.AdmRendererOutputCountMismatch;
    for (outputs, 0..) |output, output_index| {
        if (output.len != input.len)
            return error.AdmRendererBufferLengthMismatch;
        if (slicesOverlap(Sample, input, output))
            return error.AdmRendererAliasedBuffers;
        for (outputs[0..output_index]) |previous| {
            if (slicesOverlap(Sample, previous, output))
                return error.AdmRendererAliasedBuffers;
        }
    }
}

fn slicesOverlap(
    comptime Sample: type,
    input: []const Sample,
    output: []Sample,
) bool {
    if (input.len == 0 or output.len == 0) return false;
    const input_start = @intFromPtr(input.ptr);
    const output_start = @intFromPtr(output.ptr);
    const input_bytes = std.math.mul(
        usize,
        input.len,
        @sizeOf(Sample),
    ) catch return true;
    const output_bytes = std.math.mul(
        usize,
        output.len,
        @sizeOf(Sample),
    ) catch return true;
    const input_end = std.math.add(
        usize,
        input_start,
        input_bytes,
    ) catch return true;
    const output_end = std.math.add(
        usize,
        output_start,
        output_bytes,
    ) catch return true;
    return input_start < output_end and output_start < input_end;
}

test "ADM static matrix mixer binds identifiers and applies gains" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gain="0.5">AC_00010001</coefficient>
        \\        <coefficient gain="-6.020599913279624" gainUnit="dB">AC_00010002</coefficient>
        \\        <coefficient gain="-inf" gainUnit="dB">AC_00010003</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const channels = [_]adm.Identifier{
        try adm.Identifier.parse("AC_00010001"),
        try adm.Identifier.parse("AC_00010002"),
        try adm.Identifier.parse("AC_00010003"),
    };
    const mixer = try StaticMatrixMixer(f64).init(&block, &channels);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        mixer.processSample(&.{ 1.0, 3.0, 1000.0 }),
        0.000_000_001,
    );

    const first = [_]f64{ 2.0, -2.0, std.math.nan(f64) };
    const second = [_]f64{ 4.0, 2.0, 1.0 };
    const muted = [_]f64{ 1000.0, 1000.0, 1000.0 };
    const inputs = [_][]const f64{ &first, &second, &muted };
    var output: [3]f64 = undefined;
    try mixer.process(&inputs, &output);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        output[0],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        output[1],
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), output[2]);
}

test "ADM static matrix mixer rejects unsupported plans transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="automation">AC_00010001</coefficient>
        \\      </matrix>
        \\    </audioBlockFormatMatrix>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const channels = [_]adm.Identifier{
        try adm.Identifier.parse("AC_00010001"),
    };
    try std.testing.expectError(
        error.UnsupportedDynamicAdmMatrixCoefficient,
        StaticMatrixMixer(f32).init(&block, &channels),
    );

    var static_block = block;
    static_block.matrix_coefficients[0].gain_variable = null;
    const mixer = try StaticMatrixMixer(f32).init(
        &static_block,
        &channels,
    );
    const input = [_]f32{ 1.0, 2.0 };
    const inputs = [_][]const f32{&input};
    var output = [_]f32{7.0};
    try std.testing.expectError(
        error.AdmRendererBufferLengthMismatch,
        mixer.process(&inputs, &output),
    );
    try std.testing.expectEqual(@as(f32, 7.0), output[0]);

    var aliased = [_]f32{ 1.0, 2.0 };
    const aliased_inputs = [_][]const f32{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        mixer.process(&aliased_inputs, &aliased),
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 2.0 },
        aliased,
    );
}

test "ADM direct speaker router mixes an exact label match" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const labels = [_][]const u8{ "M+030", "M+000", "M-030" };
    const router = try DirectSpeakerRouter(f32).init(&block, &labels);
    try std.testing.expectEqual(@as(u8, 1), router.output_index);
    try std.testing.expectEqual(
        @as(f32, 1.0),
        router.processSample(2.0),
    );

    const input = [_]f32{ 2.0, std.math.nan(f32), -4.0 };
    var left = [_]f32{ 1.0, 1.0, 1.0 };
    var center = [_]f32{ 1.0, 1.0, 1.0 };
    var right = [_]f32{ 1.0, 1.0, 1.0 };
    const outputs = [_][]f32{ &left, &center, &right };
    try router.mix(&input, &outputs);
    try std.testing.expectEqualDeep(
        [_]f32{ 2.0, 1.0, -1.0 },
        center,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 1.0, 1.0 },
        left,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 1.0, 1.0 },
        right,
    );
}

test "ADM direct speaker router rejects ambiguous and aliased routes" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>M+000</speakerLabel>
        \\      <speakerLabel>M+030</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    try std.testing.expectError(
        error.AmbiguousAdmRendererSpeakerRoute,
        DirectSpeakerRouter(f64).init(
            &block,
            &[_][]const u8{ "M+000", "M+030" },
        ),
    );
    try std.testing.expectError(
        error.MissingAdmRendererSpeakerRoute,
        DirectSpeakerRouter(f64).init(
            &block,
            &[_][]const u8{"M-030"},
        ),
    );

    const router = try DirectSpeakerRouter(f64).init(
        &block,
        &[_][]const u8{"M+000"},
    );
    var aliased = [_]f64{ 1.0, 2.0 };
    const outputs = [_][]f64{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        router.mix(&aliased, &outputs),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 2.0 },
        aliased,
    );
}

test "ADM position router selects the nearest bounded polar speaker" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth" bound="min">20</position>
        \\      <position coordinate="azimuth">25</position>
        \\      <position coordinate="azimuth" bound="max">40</position>
        \\      <position coordinate="elevation">0</position>
        \\      <position coordinate="distance">1</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -0.5, .y = 1.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.5, .y = 1.0 },
        },
    };
    const router = try DirectSpeakerPositionRouter(f32).init(
        &block,
        &outputs,
        .{},
    );
    switch (router.route) {
        .output => |index| try std.testing.expectEqual(
            @as(u8, 0),
            index,
        ),
        else => return error.TestUnexpectedResult,
    }

    const input = [_]f32{ 2.0, -4.0 };
    var left = [_]f32{ 1.0, 1.0 };
    var right = [_]f32{ 1.0, 1.0 };
    const output_buffers = [_][]f32{ &left, &right };
    try router.mix(&input, &output_buffers);
    try std.testing.expectEqualDeep([_]f32{ 2.0, -1.0 }, left);
    try std.testing.expectEqualDeep([_]f32{ 1.0, 1.0 }, right);
}

test "ADM position router handles circular bounds poles and ties" {
    try std.testing.expect(insideAngleRange(
        180.0,
        90.0,
        -90.0,
        position_tolerance,
    ));
    try std.testing.expect(!insideAngleRange(
        0.0,
        90.0,
        -90.0,
        position_tolerance,
    ));
    try std.testing.expect(insideAngleRange(
        -170.0,
        -180.0,
        180.0,
        position_tolerance,
    ));

    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth" bound="min">-30</position>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="azimuth" bound="max">30</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -0.5, .y = 1.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.5, .y = 1.0 },
        },
        .{
            .label = "T+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 90,
            },
            .allocentric = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
        },
        .{
            .label = "M+135",
            .nominal_polar = .{
                .azimuth_degrees = 135,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1.0, .y = -1.0 },
        },
    };
    const route = try resolveDirectSpeakerRoute(&block, &outputs, .{});
    switch (route) {
        .polar_panner => |position| {
            try std.testing.expectEqual(@as(f64, 0.0), position.azimuth_degrees);
            try std.testing.expectEqual(
                @as(f64, 0.0),
                position.elevation_degrees,
            );
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(polarWithinBounds(
        outputs[2].nominal_polar,
        .{
            .azimuth = .{
                .nominal = 120,
                .minimum = 110,
                .maximum = 130,
            },
            .elevation = .{
                .nominal = 90,
                .minimum = 90,
                .maximum = 90,
            },
            .distance = .{
                .nominal = 1,
                .minimum = 1,
                .maximum = 1,
            },
        },
    ));

    var wrapped_block = block;
    wrapped_block.positions[0].value = 90;
    wrapped_block.positions[1].value = 180;
    wrapped_block.positions[2].value = -90;
    const wrapped_route = try resolveDirectSpeakerRoute(
        &wrapped_block,
        &outputs,
        .{},
    );
    try std.testing.expectEqual(@as(u8, 3), wrapped_route.output);
}

test "ADM position router applies polar screen edges to nominal only" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth" bound="min">-40</position>
        \\      <position coordinate="azimuth" screenEdgeLock="right">0</position>
        \\      <position coordinate="azimuth" bound="max">40</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{
        .{
            .label = "M+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.0, .y = 1.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.5, .y = 1.0 },
        },
    };
    const route = try resolveDirectSpeakerRoute(
        &block,
        &outputs,
        .{
            .screen_edges = .{
                .left_azimuth_degrees = 30,
                .right_azimuth_degrees = -30,
                .bottom_elevation_degrees = -15,
                .top_elevation_degrees = 15,
            },
        },
    );
    switch (route) {
        .output => |index| try std.testing.expectEqual(
            @as(u8, 1),
            index,
        ),
        else => return error.TestUnexpectedResult,
    }
}

test "ADM Cartesian screen conversion matches reference layout positions" {
    const vectors = [_]struct {
        polar: PolarPosition,
        cartesian: CartesianPosition,
    }{
        .{
            .polar = .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            .cartesian = .{ .x = 0, .y = 1, .z = 0 },
        },
        .{
            .polar = .{ .azimuth_degrees = 30, .elevation_degrees = 0 },
            .cartesian = .{ .x = -1, .y = 1, .z = 0 },
        },
        .{
            .polar = .{ .azimuth_degrees = -30, .elevation_degrees = 0 },
            .cartesian = .{ .x = 1, .y = 1, .z = 0 },
        },
        .{
            .polar = .{ .azimuth_degrees = 110, .elevation_degrees = 0 },
            .cartesian = .{ .x = -1, .y = -1, .z = 0 },
        },
        .{
            .polar = .{ .azimuth_degrees = -110, .elevation_degrees = 0 },
            .cartesian = .{ .x = 1, .y = -1, .z = 0 },
        },
        .{
            .polar = .{ .azimuth_degrees = 0, .elevation_degrees = 30 },
            .cartesian = .{ .x = 0, .y = 1, .z = 1 },
        },
        .{
            .polar = .{ .azimuth_degrees = 0, .elevation_degrees = 90 },
            .cartesian = .{ .x = 0, .y = 0, .z = 1 },
        },
    };
    for (vectors) |vector| {
        const cartesian = try admPolarToCartesian(vector.polar);
        try expectCartesianApprox(vector.cartesian, cartesian);
        const polar = try admCartesianToPolar(vector.cartesian);
        try expectPolarApprox(vector.polar, polar);
    }

    for ([_]PolarPosition{
        .{
            .azimuth_degrees = -70,
            .elevation_degrees = 20,
            .distance = 0.7,
        },
        .{
            .azimuth_degrees = 150,
            .elevation_degrees = 60,
            .distance = 0.5,
        },
    }) |original| {
        const round_trip = try admCartesianToPolar(
            try admPolarToCartesian(original),
        );
        try expectPolarApprox(original, round_trip);
    }
}

test "ADM position router applies Cartesian screen edges internally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X" screenEdgeLock="right">0</position>
        \\      <position coordinate="Y">1</position>
        \\      <position coordinate="Z">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{.{
        .label = "M+030",
        .nominal_polar = .{
            .azimuth_degrees = 30,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = -1, .y = 1, .z = 0 },
    }};
    const route = try resolveDirectSpeakerRoute(
        &block,
        &outputs,
        .{
            .screen_edges = .{
                .left_azimuth_degrees = 30,
                .right_azimuth_degrees = -30,
                .bottom_elevation_degrees = -15,
                .top_elevation_degrees = 15,
            },
        },
    );
    switch (route) {
        .cartesian_panner => |position| try expectCartesianApprox(
            .{ .x = 1, .y = 1, .z = 0 },
            position,
        ),
        else => return error.TestUnexpectedResult,
    }

    var compensated = PolarPosition{
        .azimuth_degrees = -30,
        .elevation_degrees = 30,
    };
    const compensated_outputs = [_]OutputSpeaker{.{
        .label = "U+045",
        .nominal_polar = .{
            .azimuth_degrees = 45,
            .elevation_degrees = 30,
        },
        .allocentric = .{ .x = -1, .y = 1, .z = 1 },
    }};
    compensateCartesianScreenPosition(
        &compensated_outputs,
        &compensated,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -20),
        compensated.azimuth_degrees,
        0.000_000_001,
    );
}

test "ADM position router normalizes labels and classifies LFE metadata" {
    const label_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>urn:itu:bs:2051:2:speaker:M+030</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var label_blocks = label_document.blocks();
    const label_block = (try label_blocks.next()).?;
    const ordinary_output = [_]OutputSpeaker{.{
        .label = "M+030",
        .nominal_polar = .{
            .azimuth_degrees = 30,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = -0.5, .y = 1.0 },
    }};
    const label_route = try resolveDirectSpeakerRoute(
        &label_block,
        &ordinary_output,
        .{},
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        label_route.output,
    );

    const lfe_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <frequency typeDefinition="lowPass">120</frequency>
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>LFER</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var lfe_blocks = lfe_document.blocks();
    const lfe_block = (try lfe_blocks.next()).?;
    const lfe_outputs = [_]OutputSpeaker{
        .{
            .label = "M+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.0, .y = 1.0 },
        },
        .{
            .label = "LFE1",
            .is_lfe = true,
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1.0, .y = 1.0 },
        },
        .{
            .label = "LFE2",
            .is_lfe = true,
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1.0, .y = 1.0 },
        },
    };
    const exact_lfe_route = try resolveDirectSpeakerRoute(
        &lfe_block,
        &lfe_outputs,
        .{},
    );
    try std.testing.expectEqual(
        @as(u8, 2),
        exact_lfe_route.output,
    );

    var fallback_block = lfe_block;
    fallback_block.speaker_label_count = 0;
    fallback_block.positions[0].value = 180;
    const fallback_lfe_route = try resolveDirectSpeakerRoute(
        &fallback_block,
        &lfe_outputs,
        .{},
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        fallback_lfe_route.output,
    );
}

test "ADM position router selects Cartesian speakers and preserves fallbacks" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X" bound="min">0</position>
        \\      <position coordinate="X">0.2</position>
        \\      <position coordinate="X" bound="max">0.5</position>
        \\      <position coordinate="Y" bound="min">0.4</position>
        \\      <position coordinate="Y">0.5</position>
        \\      <position coordinate="Y" bound="max">0.6</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0.25, .y = 0.5 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -0.25, .y = 0.5 },
        },
    };
    const route = try resolveDirectSpeakerRoute(&block, &outputs, .{});
    try std.testing.expectEqual(@as(u8, 0), route.output);

    var fallback_block = block;
    fallback_block.positions[0].value = -0.5;
    fallback_block.positions[1].value = -0.4;
    fallback_block.positions[2].value = -0.3;
    const fallback_router =
        try DirectSpeakerPositionRouter(f64).init(
            &fallback_block,
            &outputs,
            .{},
        );
    switch (fallback_router.route) {
        .cartesian_panner => |position| try std.testing.expectEqual(
            @as(f64, -0.4),
            position.x,
        ),
        else => return error.TestUnexpectedResult,
    }
    const input = [_]f64{ 1.0, 2.0 };
    var left = [_]f64{ 3.0, 4.0 };
    var right = [_]f64{ 5.0, 6.0 };
    const output_buffers = [_][]f64{ &left, &right };
    try std.testing.expectError(
        error.AdmRendererPointPannerRequired,
        fallback_router.mix(&input, &output_buffers),
    );
    try std.testing.expectError(
        error.AdmRendererPointPannerRequired,
        fallback_router.processSample(1.0),
    );
    try std.testing.expectEqualDeep([_]f64{ 3.0, 4.0 }, left);
    try std.testing.expectEqualDeep([_]f64{ 5.0, 6.0 }, right);
}

test "ADM polar point panner uses reproduction positions and excludes LFE" {
    const base = testPolarFiveLayout();
    var layout: [base.len + 1]OutputSpeaker = undefined;
    @memcpy(layout[0..base.len], &base);
    layout[0].reproduction_polar = .{
        .azimuth_degrees = 24,
        .elevation_degrees = 0,
    };
    layout[base.len] = .{
        .label = "LFE1",
        .is_lfe = true,
        .nominal_polar = .{
            .azimuth_degrees = 0,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = 0, .y = 0, .z = 0 },
    };
    const panner = try PolarPointSourcePanner(f64).init(&layout);
    var gains: [layout.len]f64 = undefined;
    try panner.calculateGains(
        .{ .azimuth_degrees = 24, .elevation_degrees = 0 },
        &gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gains[0],
        0.000_000_001,
    );
    for (gains[1..]) |gain| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            gain,
            0.000_000_001,
        );
    }

    try panner.calculateGains(
        .{ .azimuth_degrees = -145, .elevation_degrees = -40 },
        &gains,
    );
    var power: f64 = 0.0;
    for (gains[0..base.len]) |gain| power += gain * gain;
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        power,
        0.000_000_001,
    );
    try std.testing.expectEqual(@as(f64, 0.0), gains[base.len]);
}

test "ADM polar point panner implements stereo rear attenuation" {
    const layout = [_]OutputSpeaker{
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = 1, .z = 0 },
        },
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = 1, .z = 0 },
        },
    };
    const panner = try PolarPointSourcePanner(f32).init(&layout);
    var gains: [layout.len]f32 = undefined;
    try panner.calculateGains(
        .{ .azimuth_degrees = 180, .elevation_degrees = 0 },
        &gains,
    );
    for (gains) |gain| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 0.5),
            gain,
            0.000_001,
        );
    }
}

test "ADM polar point panner mixes DirectSpeakers fallback routes" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth">65</position>
        \\      <position coordinate="elevation">25</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const layout = testPolarFiveLayout();
    const router = try DirectSpeakerPositionRouter(f32).init(
        &block,
        &layout,
        .{},
    );
    try std.testing.expect(router.route == .polar_panner);
    const panner = try PolarPointSourcePanner(f32).init(&layout);
    var expected: [layout.len]f32 = undefined;
    try panner.calculateGains(
        .{ .azimuth_degrees = 65, .elevation_degrees = 25 },
        &expected,
    );

    const input = [_]f32{ 2.0, std.math.nan(f32) };
    var storage: [layout.len][2]f32 = @splat(@splat(0.0));
    var outputs: [layout.len][]f32 = undefined;
    for (&storage, &outputs) |*channel, *output| output.* = channel;
    try router.mixWithPolarFallback(&panner, &input, &outputs);
    for (storage, expected) |channel, gain| {
        try std.testing.expectApproxEqAbs(gain, channel[0], 0.000_001);
        try std.testing.expectEqual(@as(f32, 0.0), channel[1]);
    }
}

test "ADM Cartesian point panner preserves power across a cube layout" {
    const outputs = testCartesianCubeLayout();
    const panner = try CartesianPointSourcePanner(f64).init(&outputs);
    var gains: [outputs.len]f64 = undefined;
    try panner.calculateGains(.{ .x = 0.0, .y = 0.0 }, &gains);

    var power: f64 = 0.0;
    for (gains) |gain| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0 / @sqrt(8.0)),
            gain,
            0.000_000_001,
        );
        power += gain * gain;
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        power,
        0.000_000_001,
    );

    try panner.calculateGains(.{ .x = 0.5, .y = 0.0 }, &gains);
    try std.testing.expectApproxEqAbs(
        @as(f64, @cos(3.0 * std.math.pi / 8.0) * 0.5),
        gains[0],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, @cos(std.math.pi / 8.0) * 0.5),
        gains[1],
        0.000_000_001,
    );

    try panner.calculateGains(
        .{ .x = -1.0, .y = 1.0, .z = -1.0 },
        &gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gains[0],
        0.000_000_001,
    );
    for (gains[1..]) |gain| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            gain,
            0.000_000_001,
        );
    }

    var layout_with_lfe: [outputs.len + 1]OutputSpeaker = undefined;
    @memcpy(layout_with_lfe[0..outputs.len], &outputs);
    layout_with_lfe[outputs.len] = .{
        .label = "LFE1",
        .is_lfe = true,
        .nominal_polar = .{
            .azimuth_degrees = 0,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = 0, .y = 0, .z = 0 },
    };
    const panner_with_lfe =
        try CartesianPointSourcePanner(f64).init(&layout_with_lfe);
    var lfe_gains: [layout_with_lfe.len]f64 = undefined;
    try panner_with_lfe.calculateGains(
        .{ .x = 0, .y = 0, .z = 0 },
        &lfe_gains,
    );
    try std.testing.expectEqual(@as(f64, 0.0), lfe_gains[outputs.len]);
}

test "ADM Cartesian point panner mixes DirectSpeakers fallback routes" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0</position>
        \\      <position coordinate="Y">0</position>
        \\      <position coordinate="Z">0</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const layout = testCartesianCubeLayout();
    const router = try DirectSpeakerPositionRouter(f32).init(
        &block,
        &layout,
        .{},
    );
    try std.testing.expect(router.route == .cartesian_panner);
    const panner = try CartesianPointSourcePanner(f32).init(&layout);

    const input = [_]f32{ 2.0, std.math.nan(f32) };
    var storage: [layout.len][2]f32 = @splat(@splat(0.0));
    var outputs: [layout.len][]f32 = undefined;
    for (&storage, &outputs) |*channel, *output| output.* = channel;
    try router.mixWithCartesianFallback(&panner, &input, &outputs);
    for (storage) |channel| {
        try std.testing.expectApproxEqAbs(
            @as(f32, 1.0 / @sqrt(8.0)),
            channel[0],
            0.000_001,
        );
        try std.testing.expectEqual(@as(f32, 0.0), channel[1]);
    }

    var invalid_position_gains: [layout.len]f32 = undefined;
    try std.testing.expectError(
        error.InvalidAdmRendererCartesianPosition,
        panner.calculateGains(
            .{ .x = 1.01, .y = 0.0 },
            &invalid_position_gains,
        ),
    );
}

test "ADM Cartesian point panner rejects malformed layouts and aliases" {
    var duplicate = testCartesianCubeLayout();
    duplicate[1].allocentric = duplicate[0].allocentric;
    try std.testing.expectError(
        error.DuplicateAdmRendererSpeakerPosition,
        CartesianPointSourcePanner(f32).init(&duplicate),
    );

    const incomplete_row = [_]OutputSpeaker{.{
        .label = "M+090",
        .nominal_polar = .{
            .azimuth_degrees = 90,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = -1, .y = 0, .z = 0 },
    }};
    try std.testing.expectError(
        error.InvalidAdmRendererCartesianLayout,
        CartesianPointSourcePanner(f64).init(&incomplete_row),
    );
    const lfe_only = [_]OutputSpeaker{.{
        .label = "LFE1",
        .is_lfe = true,
        .nominal_polar = .{
            .azimuth_degrees = 0,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = 0, .y = 0, .z = 0 },
    }};
    try std.testing.expectError(
        error.MissingAdmRendererPannerOutput,
        CartesianPointSourcePanner(f64).init(&lfe_only),
    );

    const layout = testCartesianCubeLayout();
    const panner = try CartesianPointSourcePanner(f32).init(&layout);
    var invalid_state = panner;
    invalid_state.positions[0] = .{ .x = 0, .y = 0, .z = 0 };
    try std.testing.expect(!invalid_state.valid());
    var retained_gains: [layout.len]f32 = @splat(0.25);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        invalid_state.calculateGains(
            .{ .x = 0, .y = 0 },
            &retained_gains,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f32{0.25} ** layout.len,
        retained_gains,
    );

    var aliased = [_]f32{ 1.0, 2.0 };
    var storage: [layout.len - 1][2]f32 = @splat(@splat(0.0));
    var outputs: [layout.len][]f32 = undefined;
    outputs[0] = &aliased;
    for (&storage, outputs[1..]) |*channel, *output| output.* = channel;
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        panner.mix(
            .{ .x = 0, .y = 0 },
            1.0,
            &aliased,
            &outputs,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 1.0, 2.0 }, aliased);
    for (storage) |channel| {
        try std.testing.expectEqualDeep([_]f32{ 0.0, 0.0 }, channel);
    }
}

test "ADM position router discards unmatched LFE without mutating output" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <frequency typeDefinition="lowPass">100</frequency>
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <position coordinate="azimuth">180</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{.{
        .label = "M+000",
        .nominal_polar = .{
            .azimuth_degrees = 0,
            .elevation_degrees = 0,
        },
        .allocentric = .{ .x = 0.0, .y = 1.0 },
    }};
    const router = try DirectSpeakerPositionRouter(f32).init(
        &block,
        &outputs,
        .{},
    );
    try std.testing.expect(router.route == .discard);
    try std.testing.expectEqual(@as(f32, 0.0), try router.processSample(1.0));
    const input = [_]f32{ 1.0, 2.0 };
    var output = [_]f32{ 3.0, 4.0 };
    const output_buffers = [_][]f32{&output};
    try router.mix(&input, &output_buffers);
    try std.testing.expectEqualDeep([_]f32{ 3.0, 4.0 }, output);

    var invalid_outputs = outputs;
    invalid_outputs[0].is_lfe = true;
    try std.testing.expectError(
        error.InvalidAdmRendererSpeakerType,
        DirectSpeakerPositionRouter(f32).init(
            &block,
            &invalid_outputs,
            .{},
        ),
    );
}

fn testPolarFiveLayout() [5]OutputSpeaker {
    return .{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = 1, .z = 0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = 1, .z = 0 },
        },
        .{
            .label = "M+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0, .y = 1, .z = 0 },
        },
        .{
            .label = "M+110",
            .nominal_polar = .{
                .azimuth_degrees = 110,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = -1, .z = 0 },
        },
        .{
            .label = "M-110",
            .nominal_polar = .{
                .azimuth_degrees = -110,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = -1, .z = 0 },
        },
    };
}

fn testCartesianCubeLayout() [8]OutputSpeaker {
    return .{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = -30,
            },
            .allocentric = .{ .x = -1, .y = 1, .z = -1 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = -30,
            },
            .allocentric = .{ .x = 1, .y = 1, .z = -1 },
        },
        .{
            .label = "M+110",
            .nominal_polar = .{
                .azimuth_degrees = 110,
                .elevation_degrees = -30,
            },
            .allocentric = .{ .x = -1, .y = -1, .z = -1 },
        },
        .{
            .label = "M-110",
            .nominal_polar = .{
                .azimuth_degrees = -110,
                .elevation_degrees = -30,
            },
            .allocentric = .{ .x = 1, .y = -1, .z = -1 },
        },
        .{
            .label = "U+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 30,
            },
            .allocentric = .{ .x = -1, .y = 1, .z = 1 },
        },
        .{
            .label = "U-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 30,
            },
            .allocentric = .{ .x = 1, .y = 1, .z = 1 },
        },
        .{
            .label = "U+110",
            .nominal_polar = .{
                .azimuth_degrees = 110,
                .elevation_degrees = 30,
            },
            .allocentric = .{ .x = -1, .y = -1, .z = 1 },
        },
        .{
            .label = "U-110",
            .nominal_polar = .{
                .azimuth_degrees = -110,
                .elevation_degrees = 30,
            },
            .allocentric = .{ .x = 1, .y = -1, .z = 1 },
        },
    };
}

fn expectCartesianApprox(
    expected: CartesianPosition,
    actual: CartesianPosition,
) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, 0.000_000_001);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, 0.000_000_001);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, 0.000_000_001);
}

fn expectPolarApprox(
    expected: PolarPosition,
    actual: PolarPosition,
) !void {
    try std.testing.expectApproxEqAbs(
        expected.azimuth_degrees,
        actual.azimuth_degrees,
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        expected.elevation_degrees,
        actual.elevation_degrees,
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        expected.distance,
        actual.distance,
        0.000_000_001,
    );
}
