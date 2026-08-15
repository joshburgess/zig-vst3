const std = @import("std");
const adm_cartesian_extent = @import("../adm_cartesian_extent.zig");
const adm_polar_extent = @import("../adm_polar_extent.zig");
const adm_polar_panner = @import("../adm_polar_panner.zig");
const common = @import("common.zig");

const maximum_output_channels = common.maximum_output_channels;
const PolarPosition = common.PolarPosition;
const CartesianPosition = common.CartesianPosition;
const OutputSpeaker = common.OutputSpeaker;
const insideUnitCube = common.insideUnitCube;
const normalizeSpeakerLabel = common.normalizeSpeakerLabel;
const onUnitCubeSurface = common.onUnitCubeSurface;
const pannerPolarPosition = common.pannerPolarPosition;
const samePosition = common.samePosition;
const sameSign = common.sameSign;
const subtractPosition = common.subtractPosition;
const validCartesian = common.validCartesian;
const validateMixBuffers = common.validateMixBuffers;
const validateOutputLayout = common.validateOutputLayout;
const validatePannerPosition = common.validatePannerPosition;
const validPolar = common.validPolar;

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

/// Precomputes the fixed polar spreading grid into caller-owned gain storage.
pub fn PolarExtentPanner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "PolarExtentPanner supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();

        output_count: usize,
        core: adm_polar_extent.Panner(Sample),

        pub fn requiredGainStorage(output_count: usize) !usize {
            return adm_polar_extent.requiredGainStorage(output_count);
        }

        pub fn init(
            point_panner: *const PolarPointSourcePanner(Sample),
            gain_storage: []Sample,
        ) !Self {
            if (!point_panner.valid())
                return error.InvalidAdmRendererState;
            return .{
                .output_count = point_panner.output_count,
                .core = try adm_polar_extent.Panner(Sample).init(
                    &point_panner.core,
                    gain_storage,
                ),
            };
        }

        pub fn calculateGains(
            self: *const Self,
            position: PolarPosition,
            width_degrees: f64,
            height_degrees: f64,
            depth: f64,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (!validPolar(position))
                return error.InvalidAdmRendererPolarPosition;
            try self.core.calculateGains(
                pannerPolarPosition(position),
                position.distance,
                width_degrees,
                height_degrees,
                depth,
                gains,
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
        positions: [maximum_output_channels]CartesianPosition = @splat(.{}),
        enabled: [maximum_output_channels]bool = @splat(false),

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

/// Computes extent gains for allocentric room positions without allocation.
pub fn CartesianExtentPanner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "CartesianExtentPanner supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();
        const Core = adm_cartesian_extent.Panner(
            Sample,
            maximum_output_channels,
        );

        output_count: usize,
        point_panner: CartesianPointSourcePanner(Sample),
        core: Core,

        pub fn init(
            point_panner: *const CartesianPointSourcePanner(Sample),
        ) !Self {
            if (!point_panner.valid())
                return error.InvalidAdmRendererState;
            var positions: [maximum_output_channels]adm_cartesian_extent.Position =
                undefined;
            for (
                point_panner.positions[0..point_panner.output_count],
                positions[0..point_panner.output_count],
            ) |source, *target| {
                target.* = .{
                    .x = source.x,
                    .y = source.y,
                    .z = source.z,
                };
            }
            return .{
                .output_count = point_panner.output_count,
                .point_panner = point_panner.*,
                .core = try Core.init(
                    positions[0..point_panner.output_count],
                    point_panner.enabled[0..point_panner.output_count],
                ),
            };
        }

        pub fn calculateGains(
            self: *const Self,
            position: CartesianPosition,
            size_x: f64,
            size_y: f64,
            size_z: f64,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            if (gains.len != self.output_count)
                return error.AdmRendererOutputCountMismatch;
            var point_gains: [maximum_output_channels]Sample = undefined;
            try self.point_panner.calculateGains(
                position,
                point_gains[0..self.output_count],
            );
            if (size_x == 0.0 and size_y == 0.0 and size_z == 0.0) {
                @memcpy(gains, point_gains[0..self.output_count]);
                return;
            }
            try self.core.calculateGains(
                .{ .x = position.x, .y = position.y, .z = position.z },
                size_x,
                size_y,
                size_z,
                point_gains[0..self.output_count],
                gains,
            );
        }

        pub fn valid(self: *const Self) bool {
            if (!(self.output_count > 0 and
                self.output_count <= maximum_output_channels and
                self.point_panner.output_count == self.output_count and
                self.core.output_count == self.output_count and
                self.point_panner.valid() and
                self.core.valid() and
                self.point_panner.panner_output_count ==
                    self.core.panner_output_count))
            {
                return false;
            }
            for (
                self.point_panner.positions[0..self.output_count],
                self.point_panner.enabled[0..self.output_count],
                self.core.positions[0..self.output_count],
                self.core.enabled[0..self.output_count],
            ) |point_position, point_enabled, core_position, core_enabled| {
                if (point_enabled != core_enabled or
                    point_position.x != core_position.x or
                    point_position.y != core_position.y or
                    point_position.z != core_position.z)
                {
                    return false;
                }
            }
            return true;
        }
    };
}
