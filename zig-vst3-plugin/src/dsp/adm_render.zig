const std = @import("std");
const adm = @import("adm.zig");
const adm_cartesian_extent = @import("adm_cartesian_extent.zig");
const adm_polar_extent = @import("adm_polar_extent.zig");
const adm_polar_panner = @import("adm_polar_panner.zig");
const adm_xml = @import("adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;
pub const polar_extent_spreading_direction_count =
    adm_polar_extent.spreading_direction_count;
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

pub const ObjectRenderingContext = struct {
    reference_screen_edges: ?ScreenEdges = null,
    reproduction_screen_edges: ?ScreenEdges = null,
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

/// Precomputes direct and diffuse gains for one static Objects block.
pub fn ObjectPointGainPlan(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "ObjectPointGainPlan supports f32 and f64 samples",
        );

    return struct {
        const Self = @This();
        const PointPanners = struct {
            polar: ?*const PolarPointSourcePanner(Sample),
            cartesian: ?*const CartesianPointSourcePanner(Sample),
        };
        const SpatialPanner = union(enum) {
            point: PointPanners,
            polar_extent: *const PolarExtentPanner(Sample),
            cartesian_extent: *const CartesianExtentPanner(Sample),
        };

        output_count: usize,
        direct_gains: [maximum_output_channels]Sample = undefined,
        diffuse_gains: [maximum_output_channels]Sample = undefined,

        pub fn init(
            block: *const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            polar_panner: ?*const PolarPointSourcePanner(Sample),
            cartesian_panner: ?*const CartesianPointSourcePanner(Sample),
            context: ObjectRenderingContext,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0003 or
                block.channel_identifier.typeLabel() != 0x0003)
            {
                return error.AdmRendererRequiresObjectsBlock;
            }
            if (block.width != 0.0 or
                block.height != 0.0 or
                block.depth != 0.0)
            {
                return error.UnsupportedAdmObjectExtent;
            }
            return initWithPanner(
                block,
                outputs,
                .{ .point = .{
                    .polar = polar_panner,
                    .cartesian = cartesian_panner,
                } },
                context,
            );
        }

        pub fn initPolarExtent(
            block: *const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            panner: *const PolarExtentPanner(Sample),
            context: ObjectRenderingContext,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0003 or
                block.channel_identifier.typeLabel() != 0x0003)
            {
                return error.AdmRendererRequiresObjectsBlock;
            }
            if (block.cartesian)
                return error.AdmRendererPolarObjectsBlockRequired;
            if (!std.math.isFinite(block.width) or
                !std.math.isFinite(block.height) or
                !std.math.isFinite(block.depth) or
                block.width < 0.0 or
                block.width > 360.0 or
                block.height < 0.0 or
                block.height > 360.0 or
                block.depth < 0.0 or
                block.depth > 1.0)
            {
                return error.InvalidAdmObjectExtent;
            }
            return initWithPanner(
                block,
                outputs,
                .{ .polar_extent = panner },
                context,
            );
        }

        pub fn initCartesianExtent(
            block: *const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            panner: *const CartesianExtentPanner(Sample),
            context: ObjectRenderingContext,
        ) !Self {
            if (block.identifier.typeLabel() != 0x0003 or
                block.channel_identifier.typeLabel() != 0x0003)
            {
                return error.AdmRendererRequiresObjectsBlock;
            }
            if (!block.cartesian)
                return error.AdmRendererCartesianObjectsBlockRequired;
            if (!std.math.isFinite(block.width) or
                !std.math.isFinite(block.height) or
                !std.math.isFinite(block.depth) or
                block.width < 0.0 or
                block.width > 1.0 or
                block.height < 0.0 or
                block.height > 1.0 or
                block.depth < 0.0 or
                block.depth > 1.0)
            {
                return error.InvalidAdmObjectExtent;
            }
            return initWithPanner(
                block,
                outputs,
                .{ .cartesian_extent = panner },
                context,
            );
        }

        fn initWithPanner(
            block: *const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            spatial_panner: SpatialPanner,
            context: ObjectRenderingContext,
        ) !Self {
            if (!std.math.isFinite(block.diffuse) or
                block.diffuse < 0.0 or
                block.diffuse > 1.0)
            {
                return error.InvalidAdmRendererDiffuse;
            }
            try validateOutputLayout(outputs);
            switch (spatial_panner) {
                .point => |panners| {
                    if (block.cartesian) {
                        const panner = panners.cartesian orelse
                            return error.AdmRendererCartesianPointPannerRequired;
                        if (panner.output_count != outputs.len)
                            return error.AdmRendererOutputCountMismatch;
                        if (!panner.valid())
                            return error.InvalidAdmRendererState;
                    } else {
                        const panner = panners.polar orelse
                            return error.AdmRendererPolarPointPannerRequired;
                        if (panner.output_count != outputs.len)
                            return error.AdmRendererOutputCountMismatch;
                        if (!panner.valid())
                            return error.InvalidAdmRendererState;
                    }
                },
                .polar_extent => |panner| {
                    if (block.cartesian)
                        return error.AdmRendererPolarObjectsBlockRequired;
                    if (panner.output_count != outputs.len)
                        return error.AdmRendererOutputCountMismatch;
                    if (!panner.valid())
                        return error.InvalidAdmRendererState;
                },
                .cartesian_extent => |panner| {
                    if (!block.cartesian)
                        return error.AdmRendererCartesianObjectsBlockRequired;
                    if (panner.output_count != outputs.len)
                        return error.AdmRendererOutputCountMismatch;
                    if (!panner.valid())
                        return error.InvalidAdmRendererState;
                },
            }
            try validateObjectRenderingContext(context);

            var position = try objectPosition(block);
            position = try applyObjectScreenTransforms(
                block,
                outputs,
                context,
                position,
            );
            position = try applyObjectChannelLock(
                block,
                outputs,
                position,
            );

            const diverged = try objectDivergence(block, position);
            var combined: [maximum_output_channels]f64 = @splat(0.0);
            var branch_gains: [maximum_output_channels]Sample = undefined;
            for (
                diverged.positions[0..diverged.count],
                diverged.power_weights[0..diverged.count],
            ) |branch_position, power_weight| {
                if (power_weight == 0.0) continue;
                switch (spatial_panner) {
                    .point => |panners| {
                        if (block.cartesian) {
                            const panner = panners.cartesian orelse
                                return error.AdmRendererCartesianPointPannerRequired;
                            try panner.calculateGains(
                                branch_position,
                                branch_gains[0..outputs.len],
                            );
                        } else {
                            const panner = panners.polar orelse
                                return error.AdmRendererPolarPointPannerRequired;
                            try panner.calculateGains(
                                try cartesianToPolar(branch_position),
                                branch_gains[0..outputs.len],
                            );
                        }
                    },
                    .polar_extent => |panner| {
                        try panner.calculateGains(
                            try cartesianToPolar(branch_position),
                            block.width,
                            block.height,
                            block.depth,
                            branch_gains[0..outputs.len],
                        );
                    },
                    .cartesian_extent => |panner| {
                        try panner.calculateGains(
                            branch_position,
                            block.width,
                            block.height,
                            block.depth,
                            branch_gains[0..outputs.len],
                        );
                    },
                }
                for (
                    combined[0..outputs.len],
                    branch_gains[0..outputs.len],
                ) |*output_power, branch_gain| {
                    const gain: f64 = @floatCast(branch_gain);
                    output_power.* += power_weight * gain * gain;
                }
            }

            const block_gain: f64 = @floatCast(
                try renderGain(Sample, block.gain),
            );
            if (block_gain < 0.0)
                return error.InvalidAdmRendererGain;
            const direct_scale =
                block_gain * @sqrt(1.0 - block.diffuse);
            const diffuse_scale =
                block_gain * @sqrt(block.diffuse);
            if (!std.math.isFinite(direct_scale) or
                !std.math.isFinite(diffuse_scale))
            {
                return error.InvalidAdmRendererGain;
            }

            var result = Self{ .output_count = outputs.len };
            for (
                combined[0..outputs.len],
                result.direct_gains[0..outputs.len],
                result.diffuse_gains[0..outputs.len],
            ) |output_power, *direct_gain, *diffuse_gain| {
                if (!std.math.isFinite(output_power) or output_power < 0.0)
                    return error.InvalidAdmRendererPannerGain;
                const spatial_gain = @sqrt(output_power);
                direct_gain.* = @floatCast(spatial_gain * direct_scale);
                diffuse_gain.* = @floatCast(spatial_gain * diffuse_scale);
                if (!std.math.isFinite(direct_gain.*) or
                    !std.math.isFinite(diffuse_gain.*))
                {
                    return error.InvalidAdmRendererGain;
                }
            }
            return result;
        }

        pub fn directGainSlice(self: *const Self) []const Sample {
            return self.direct_gains[0..@min(self.output_count, maximum_output_channels)];
        }

        pub fn diffuseGainSlice(self: *const Self) []const Sample {
            return self.diffuse_gains[0..@min(self.output_count, maximum_output_channels)];
        }

        pub fn mix(
            self: *const Self,
            input: []const Sample,
            direct_outputs: []const []Sample,
            diffuse_outputs: []const []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmRendererState;
            try validateMixBuffers(
                Sample,
                input,
                direct_outputs,
                self.output_count,
            );
            try validateMixBuffers(
                Sample,
                input,
                diffuse_outputs,
                self.output_count,
            );
            for (direct_outputs) |direct_output| {
                for (diffuse_outputs) |diffuse_output| {
                    if (slicesOverlap(
                        Sample,
                        direct_output,
                        diffuse_output,
                    )) {
                        return error.AdmRendererAliasedBuffers;
                    }
                }
            }
            mixGainVector(
                Sample,
                input,
                direct_outputs,
                self.directGainSlice(),
            );
            mixGainVector(
                Sample,
                input,
                diffuse_outputs,
                self.diffuseGainSlice(),
            );
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels)
            {
                return false;
            }
            for (
                self.directGainSlice(),
                self.diffuseGainSlice(),
            ) |direct_gain, diffuse_gain| {
                if (!std.math.isFinite(direct_gain) or
                    !std.math.isFinite(diffuse_gain) or
                    direct_gain < 0.0 or
                    diffuse_gain < 0.0)
                {
                    return false;
                }
            }
            return true;
        }
    };
}

pub const ObjectPolarExtentGainPlan = ObjectPointGainPlan;
pub const ObjectCartesianExtentGainPlan = ObjectPointGainPlan;

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

const default_object_reference_screen = ScreenEdges{
    .left_azimuth_degrees = 29.0,
    .right_azimuth_degrees = -29.0,
    .bottom_elevation_degrees = -17.3,
    .top_elevation_degrees = 17.3,
};

const DivergedObjectPositions = struct {
    count: usize,
    power_weights: [3]f64,
    positions: [3]CartesianPosition,
};

fn objectPosition(
    block: *const adm_xml.BlockFormat,
) !CartesianPosition {
    for (block.positionSlice()) |position| {
        if (position.bound != .exact)
            return error.InvalidAdmRendererObjectPosition;
        const coordinate_matches = if (block.cartesian)
            position.coordinate == .x or
                position.coordinate == .y or
                position.coordinate == .z
        else
            position.coordinate == .azimuth or
                position.coordinate == .elevation or
                position.coordinate == .distance;
        if (!coordinate_matches)
            return error.InvalidAdmRendererObjectPosition;
    }

    if (block.cartesian) {
        const position = CartesianPosition{
            .x = try exactObjectCoordinate(block, .x, null),
            .y = try exactObjectCoordinate(block, .y, null),
            .z = try exactObjectCoordinate(block, .z, 0.0),
        };
        if (!validCartesian(position))
            return error.InvalidAdmRendererObjectPosition;
        return clipCartesian(position);
    }

    const polar = PolarPosition{
        .azimuth_degrees = try exactObjectCoordinate(block, .azimuth, null),
        .elevation_degrees = try exactObjectCoordinate(block, .elevation, null),
        .distance = try exactObjectCoordinate(block, .distance, 1.0),
    };
    if (!validPolar(polar))
        return error.InvalidAdmRendererObjectPosition;
    return polarToCartesian(polar);
}

fn exactObjectCoordinate(
    block: *const adm_xml.BlockFormat,
    coordinate: adm_xml.Coordinate,
    default_value: ?f64,
) !f64 {
    var found: ?f64 = null;
    for (block.positionSlice()) |position| {
        if (position.coordinate != coordinate) continue;
        if (found != null)
            return error.InvalidAdmRendererObjectPosition;
        found = position.value;
    }
    const value = found orelse default_value orelse
        return error.MissingAdmRendererObjectPosition;
    if (!std.math.isFinite(value))
        return error.InvalidAdmRendererObjectPosition;
    return value;
}

fn validateObjectRenderingContext(
    context: ObjectRenderingContext,
) !void {
    if (context.reference_screen_edges) |edges|
        try validateObjectScreenEdges(edges);
    if (context.reproduction_screen_edges) |edges|
        try validateObjectScreenEdges(edges);
}

fn validateObjectScreenEdges(edges: ScreenEdges) !void {
    try validateScreenEdges(edges);
    if (edges.right_azimuth_degrees <= -180.0 or
        edges.left_azimuth_degrees >= 180.0 or
        edges.bottom_elevation_degrees <= -90.0 or
        edges.top_elevation_degrees >= 90.0 or
        edges.right_azimuth_degrees >= edges.left_azimuth_degrees or
        edges.bottom_elevation_degrees >= edges.top_elevation_degrees)
    {
        return error.InvalidAdmRendererScreenGeometry;
    }
}

fn applyObjectScreenTransforms(
    block: *const adm_xml.BlockFormat,
    outputs: []const OutputSpeaker,
    context: ObjectRenderingContext,
    initial_position: CartesianPosition,
) !CartesianPosition {
    const reproduction =
        context.reproduction_screen_edges orelse return initial_position;
    var position = initial_position;
    if (block.screen_ref) {
        const reference =
            context.reference_screen_edges orelse
            default_object_reference_screen;
        position = try scaleObjectPosition(
            position,
            block.cartesian,
            outputs,
            reference,
            reproduction,
        );
    }
    if (hasScreenEdgeLock(block)) {
        position = try lockObjectPositionToScreen(
            block,
            outputs,
            reproduction,
            position,
        );
    }
    return position;
}

fn scaleObjectPosition(
    position: CartesianPosition,
    cartesian: bool,
    outputs: []const OutputSpeaker,
    reference: ScreenEdges,
    reproduction: ScreenEdges,
) !CartesianPosition {
    var polar = if (cartesian)
        try admCartesianToPolar(position)
    else
        try cartesianToPolar(position);
    polar.azimuth_degrees = piecewiseLinear(
        polar.azimuth_degrees,
        &.{
            -180.0,
            reference.right_azimuth_degrees,
            reference.left_azimuth_degrees,
            180.0,
        },
        &.{
            -180.0,
            reproduction.right_azimuth_degrees,
            reproduction.left_azimuth_degrees,
            180.0,
        },
    );
    polar.elevation_degrees = piecewiseLinear(
        polar.elevation_degrees,
        &.{
            -90.0,
            reference.bottom_elevation_degrees,
            reference.top_elevation_degrees,
            90.0,
        },
        &.{
            -90.0,
            reproduction.bottom_elevation_degrees,
            reproduction.top_elevation_degrees,
            90.0,
        },
    );
    if (cartesian) compensateCartesianScreenPosition(outputs, &polar);
    return if (cartesian)
        admPolarToCartesian(polar)
    else
        polarToCartesian(polar);
}

fn lockObjectPositionToScreen(
    block: *const adm_xml.BlockFormat,
    outputs: []const OutputSpeaker,
    reproduction: ScreenEdges,
    position: CartesianPosition,
) !CartesianPosition {
    var polar = if (block.cartesian)
        try admCartesianToPolar(position)
    else
        try cartesianToPolar(position);
    applyPolarScreenEdgeLock(block, reproduction, &polar);
    if (block.cartesian)
        compensateCartesianScreenPosition(outputs, &polar);
    return if (block.cartesian)
        admPolarToCartesian(polar)
    else
        polarToCartesian(polar);
}

fn applyObjectChannelLock(
    block: *const adm_xml.BlockFormat,
    outputs: []const OutputSpeaker,
    position: CartesianPosition,
) !CartesianPosition {
    if (!block.channel_lock.enabled) {
        if (block.channel_lock.max_distance != null)
            return error.InvalidAdmRendererChannelLock;
        return position;
    }
    if (block.channel_lock.max_distance) |maximum_distance| {
        if (!std.math.isFinite(maximum_distance) or
            maximum_distance < 0.0 or
            maximum_distance > 2.0 * @sqrt(3.0))
        {
            return error.InvalidAdmRendererChannelLock;
        }
    }

    var best_index: ?usize = null;
    var best_distance = std.math.inf(f64);
    for (outputs, 0..) |output, output_index| {
        if (output.is_lfe) continue;
        const candidate = objectSpeakerPosition(output, block.cartesian);
        const ordinary_distance = cartesianDistance(position, candidate);
        if (block.channel_lock.max_distance) |maximum_distance| {
            if (ordinary_distance >
                maximum_distance + position_tolerance)
            {
                continue;
            }
        }
        const selection_distance = if (block.cartesian)
            weightedCartesianDistance(position, candidate)
        else
            ordinary_distance;
        if (!std.math.isFinite(selection_distance))
            return error.InvalidAdmRendererSpeakerPosition;
        const current_best = best_index orelse {
            best_index = output_index;
            best_distance = selection_distance;
            continue;
        };
        if (selection_distance < best_distance - position_tolerance or
            (@abs(selection_distance - best_distance) <=
                position_tolerance and
                higherObjectSpeakerPriority(output, outputs[current_best])))
        {
            best_index = output_index;
            best_distance = selection_distance;
        }
    }
    const index = best_index orelse return position;
    return objectSpeakerPosition(outputs[index], block.cartesian);
}

fn objectSpeakerPosition(
    output: OutputSpeaker,
    cartesian: bool,
) CartesianPosition {
    if (cartesian) return output.allocentric;
    var polar = output.reproduction_polar orelse output.nominal_polar;
    polar.distance = 1.0;
    return polarToCartesian(polar);
}

fn weightedCartesianDistance(
    left: CartesianPosition,
    right: CartesianPosition,
) f64 {
    const x = left.x - right.x;
    const y = left.y - right.y;
    const z = left.z - right.z;
    return @sqrt(
        x * x / 16.0 +
            4.0 * y * y +
            32.0 * z * z,
    );
}

fn higherObjectSpeakerPriority(
    candidate: OutputSpeaker,
    current: OutputSpeaker,
) bool {
    const candidate_position =
        candidate.reproduction_polar orelse candidate.nominal_polar;
    const current_position =
        current.reproduction_polar orelse current.nominal_polar;
    const candidate_values = [_]f64{
        @abs(candidate_position.elevation_degrees),
        candidate_position.elevation_degrees,
        @abs(candidate_position.azimuth_degrees),
        candidate_position.azimuth_degrees,
    };
    const current_values = [_]f64{
        @abs(current_position.elevation_degrees),
        current_position.elevation_degrees,
        @abs(current_position.azimuth_degrees),
        current_position.azimuth_degrees,
    };
    for (candidate_values, current_values) |candidate_value, current_value| {
        if (candidate_value < current_value - position_tolerance)
            return true;
        if (candidate_value > current_value + position_tolerance)
            return false;
    }
    return false;
}

fn objectDivergence(
    block: *const adm_xml.BlockFormat,
    position: CartesianPosition,
) !DivergedObjectPositions {
    const value = block.object_divergence.value;
    if (!std.math.isFinite(value) or value < 0.0 or value > 1.0)
        return error.InvalidAdmRendererObjectDivergence;
    const side_weight = value / (value + 1.0);
    const center_weight = (1.0 - value) / (value + 1.0);

    if (block.cartesian) {
        if (block.object_divergence.azimuth_range != null)
            return error.InvalidAdmRendererObjectDivergence;
        const range = block.object_divergence.position_range orelse 0.0;
        if (!std.math.isFinite(range) or range < 0.0 or range > 1.0)
            return error.InvalidAdmRendererObjectDivergence;
        return .{
            .count = 3,
            .power_weights = .{
                side_weight,
                side_weight,
                center_weight,
            },
            .positions = .{
                clipCartesian(.{
                    .x = position.x - range,
                    .y = position.y,
                    .z = position.z,
                }),
                clipCartesian(.{
                    .x = position.x + range,
                    .y = position.y,
                    .z = position.z,
                }),
                clipCartesian(position),
            },
        };
    }

    if (block.object_divergence.position_range != null)
        return error.InvalidAdmRendererObjectDivergence;
    const range = block.object_divergence.azimuth_range orelse 0.0;
    if (!std.math.isFinite(range) or range < 0.0 or range > 180.0)
        return error.InvalidAdmRendererObjectDivergence;
    const polar = try cartesianToPolar(position);
    const local_left = polarToCartesian(.{
        .azimuth_degrees = range,
        .elevation_degrees = 0.0,
        .distance = polar.distance,
    });
    const local_right = polarToCartesian(.{
        .azimuth_degrees = -range,
        .elevation_degrees = 0.0,
        .distance = polar.distance,
    });
    return .{
        .count = 3,
        .power_weights = .{
            side_weight,
            side_weight,
            center_weight,
        },
        .positions = .{
            rotateLocalObjectPosition(polar, local_left),
            rotateLocalObjectPosition(polar, local_right),
            position,
        },
    };
}

fn rotateLocalObjectPosition(
    centre: PolarPosition,
    local: CartesianPosition,
) CartesianPosition {
    const basis_x = polarToCartesian(.{
        .azimuth_degrees = centre.azimuth_degrees - 90.0,
        .elevation_degrees = 0.0,
    });
    const basis_y = polarToCartesian(.{
        .azimuth_degrees = centre.azimuth_degrees,
        .elevation_degrees = centre.elevation_degrees,
    });
    const basis_z = polarToCartesian(.{
        .azimuth_degrees = centre.azimuth_degrees,
        .elevation_degrees = centre.elevation_degrees + 90.0,
    });
    return .{
        .x = basis_x.x * local.x +
            basis_y.x * local.y +
            basis_z.x * local.z,
        .y = basis_x.y * local.x +
            basis_y.y * local.y +
            basis_z.y * local.z,
        .z = basis_x.z * local.x +
            basis_y.z * local.y +
            basis_z.z * local.z,
    };
}

fn cartesianToPolar(
    position: CartesianPosition,
) !PolarPosition {
    if (!validCartesian(position))
        return error.InvalidAdmRendererPolarPosition;
    const planar_distance =
        @sqrt(position.x * position.x + position.y * position.y);
    const distance =
        @sqrt(planar_distance * planar_distance + position.z * position.z);
    const result = PolarPosition{
        .azimuth_degrees = if (planar_distance == 0.0)
            0.0
        else
            -radiansToDegrees(std.math.atan2(position.x, position.y)),
        .elevation_degrees = if (distance == 0.0)
            0.0
        else
            radiansToDegrees(std.math.atan2(position.z, planar_distance)),
        .distance = distance,
    };
    if (!validPolar(result))
        return error.InvalidAdmRendererPolarPosition;
    return result;
}

fn clipCartesian(position: CartesianPosition) CartesianPosition {
    return .{
        .x = std.math.clamp(position.x, -1.0, 1.0),
        .y = std.math.clamp(position.y, -1.0, 1.0),
        .z = std.math.clamp(position.z, -1.0, 1.0),
    };
}

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

fn mixGainVector(
    comptime Sample: type,
    input: []const Sample,
    outputs: []const []Sample,
    gains: []const Sample,
) void {
    for (outputs, gains) |output, gain| {
        if (gain == 0.0) continue;
        for (input, output) |input_sample, *output_sample| {
            if (!std.math.isFinite(input_sample)) continue;
            if (!std.math.isFinite(output_sample.*)) {
                output_sample.* = 0.0;
                continue;
            }
            const mixed = output_sample.* + input_sample * gain;
            output_sample.* = if (std.math.isFinite(mixed))
                mixed
            else
                0.0;
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

fn gainVectorPower(comptime Sample: type, gains: []const Sample) Sample {
    var power: Sample = 0.0;
    for (gains) |gain| power += gain * gain;
    return power;
}

test "ADM point Objects plan applies block gain and diffuse split" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <gain>0.5</gain>
        \\      <diffuse>0.25</diffuse>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = testPolarFiveLayout();
    const polar_panner = try PolarPointSourcePanner(f64).init(&outputs);
    const plan = try ObjectPointGainPlan(f64).init(
        &block,
        &outputs,
        &polar_panner,
        null,
        .{},
    );
    try std.testing.expect(plan.valid());
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5 * @sqrt(0.75)),
        plan.directGainSlice()[2],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        plan.diffuseGainSlice()[2],
        0.000_000_001,
    );
    for (0..outputs.len) |index| {
        if (index == 2) continue;
        try std.testing.expectEqual(
            @as(f64, 0.0),
            plan.directGainSlice()[index],
        );
        try std.testing.expectEqual(
            @as(f64, 0.0),
            plan.diffuseGainSlice()[index],
        );
    }

    const input = [_]f64{ 2.0, std.math.nan(f64), -2.0 };
    var direct_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var direct_outputs: [outputs.len][]f64 = undefined;
    var diffuse_outputs: [outputs.len][]f64 = undefined;
    for (
        &direct_storage,
        &direct_outputs,
        &diffuse_storage,
        &diffuse_outputs,
    ) |*direct, *direct_output, *diffuse, *diffuse_output| {
        direct_output.* = direct;
        diffuse_output.* = diffuse;
    }
    try plan.mix(&input, &direct_outputs, &diffuse_outputs);
    try std.testing.expectApproxEqAbs(
        @as(f64, @sqrt(0.75)),
        direct_storage[2][0],
        0.000_000_001,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        direct_storage[2][1],
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -@sqrt(0.75)),
        direct_storage[2][2],
        0.000_000_001,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 0.5, 0.0, -0.5 },
        diffuse_storage[2],
    );
}

test "ADM polar extent panner matches independent gain vectors" {
    const outputs = testPolarFiveLayout();
    const point_panner = try PolarPointSourcePanner(f64).init(&outputs);
    var gain_storage: [polar_extent_spreading_direction_count * outputs.len]f64 = undefined;
    const panner = try PolarExtentPanner(f64).init(
        &point_panner,
        &gain_storage,
    );
    try std.testing.expect(panner.valid());
    try std.testing.expectEqual(
        gain_storage.len,
        try PolarExtentPanner(f64).requiredGainStorage(outputs.len),
    );

    const Case = struct {
        position: PolarPosition,
        width: f64,
        height: f64,
        depth: f64,
        expected: [5]f64,
    };
    const cases = [_]Case{
        .{
            .position = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .width = 20,
            .height = 10,
            .depth = 0,
            .expected = .{
                0.163798417816650,
                0.163798417816651,
                0.972800162747480,
                0,
                0,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 10,
            },
            .width = 90,
            .height = 30,
            .depth = 0,
            .expected = .{
                0.8333116602488577,
                0.09645742508038607,
                0.4670328989816584,
                0.2795852523094557,
                0,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .width = 300,
            .height = 30,
            .depth = 0,
            .expected = .{
                0.354291484404771,
                0.354291484404771,
                0.191103406307312,
                0.596839415694988,
                0.596839415694988,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .width = 30,
            .height = 90,
            .depth = 0,
            .expected = .{
                0.291887589699198,
                0.291887589699198,
                0.909698274830566,
                0.032033722305387,
                0.032033722305387,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
                .distance = 0.5,
            },
            .width = 30,
            .height = 20,
            .depth = 0.8,
            .expected = .{
                0.331321656180713,
                0.331321656180713,
                0.677883093218296,
                0.400578601662729,
                0.400578601662729,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .width = 360,
            .height = 360,
            .depth = 0,
            .expected = .{
                0.326134605335874,
                0.326134605335875,
                0.215784270576593,
                0.608567821601074,
                0.608567821601074,
            },
        },
        .{
            .position = .{
                .azimuth_degrees = 10,
                .elevation_degrees = 20,
            },
            .width = 0,
            .height = 0,
            .depth = 0,
            .expected = .{
                0.452707246028212,
                0,
                0.891659211466776,
                0,
                0,
            },
        },
    };
    var gains: [outputs.len]f64 = undefined;
    for (cases) |case| {
        try panner.calculateGains(
            case.position,
            case.width,
            case.height,
            case.depth,
            &gains,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            gainVectorPower(f64, &gains),
            0.000_000_001,
        );
        for (gains, case.expected) |actual, expected| {
            try std.testing.expectApproxEqAbs(
                expected,
                actual,
                0.000_000_001,
            );
        }
    }

    var short_storage: [1]f64 = undefined;
    try std.testing.expectError(
        error.AdmPolarExtentGainStorageSizeMismatch,
        PolarExtentPanner(f64).init(
            &point_panner,
            &short_storage,
        ),
    );
    gains = @splat(7.0);
    try std.testing.expectError(
        error.InvalidAdmPolarExtent,
        panner.calculateGains(
            .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            std.math.nan(f64),
            0,
            0,
            &gains,
        ),
    );
    try std.testing.expectEqual(
        @as([outputs.len]f64, @splat(7.0)),
        gains,
    );
    try std.testing.expectError(
        error.AdmPolarExtentAliasedBuffers,
        panner.calculateGains(
            .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            20,
            10,
            0,
            gain_storage[0..outputs.len],
        ),
    );
    gain_storage[0] = std.math.nan(f64);
    try std.testing.expect(!panner.valid());
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        panner.calculateGains(
            .{ .azimuth_degrees = 0, .elevation_degrees = 0 },
            20,
            10,
            0,
            &gains,
        ),
    );
    try std.testing.expectEqual(
        @as([outputs.len]f64, @splat(7.0)),
        gains,
    );
}

test "ADM Cartesian extent panner matches independent gain vectors" {
    const outputs = testCartesianCubeLayout();
    const point_panner = try CartesianPointSourcePanner(f64).init(&outputs);
    var panner = try CartesianExtentPanner(f64).init(&point_panner);
    try std.testing.expect(panner.valid());

    const Case = struct {
        position: CartesianPosition,
        size_x: f64,
        size_y: f64,
        size_z: f64,
        expected: [8]f64,
    };
    const cases = [_]Case{
        .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .size_x = 0.25,
            .size_y = 0.25,
            .size_z = 0.25,
            .expected = .{
                0.34075868105644258,
                0.34075868105644258,
                0.34075868105644258,
                0.34075868105644258,
                0.36590097196464733,
                0.36590097196464733,
                0.36590097196464733,
                0.36590097196464733,
            },
        },
        .{
            .position = .{ .x = 0.6, .y = -0.3, .z = 0.2 },
            .size_x = 0.4,
            .size_y = 0.2,
            .size_z = 0.7,
            .expected = .{
                0.16216529426220688,
                0.32387243774913788,
                0.25478406622697408,
                0.50884831433256217,
                0.16272582626349621,
                0.36144228853327637,
                0.25566473938943218,
                0.56787573690083426,
            },
        },
        .{
            .position = .{ .x = -1.0, .y = -1.0, .z = -1.0 },
            .size_x = 1.0,
            .size_y = 1.0,
            .size_z = 1.0,
            .expected = .{
                0.30770529128711621,
                0.2828445680662614,
                0.33439371880198532,
                0.30770529128711621,
                0.39172407933447062,
                0.35474619952625336,
                0.43136333157770024,
                0.39172407933447062,
            },
        },
        .{
            .position = .{ .x = 0.8, .y = 0.5, .z = -0.6 },
            .size_x = 0.05,
            .size_y = 0.8,
            .size_z = 0.3,
            .expected = .{
                0.084244206869162355,
                0.51107495761065436,
                0.076503382913228959,
                0.46411456208702628,
                0.086437701558761848,
                0.52438198781686562,
                0.077661107148142408,
                0.47113799890568081,
            },
        },
    };
    var gains: [outputs.len]f64 = undefined;
    for (cases) |case| {
        try panner.calculateGains(
            case.position,
            case.size_x,
            case.size_y,
            case.size_z,
            &gains,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            gainVectorPower(f64, &gains),
            0.000_000_001,
        );
        for (gains, case.expected) |actual, expected| {
            try std.testing.expectApproxEqAbs(
                expected,
                actual,
                0.000_000_001,
            );
        }
    }

    try panner.calculateGains(
        .{ .x = 0.6, .y = -0.3, .z = 0.2 },
        0.0,
        0.0,
        0.0,
        &gains,
    );
    var point_gains: [outputs.len]f64 = undefined;
    try point_panner.calculateGains(
        .{ .x = 0.6, .y = -0.3, .z = 0.2 },
        &point_gains,
    );
    try std.testing.expectEqualDeep(point_gains, gains);

    var outputs_with_lfe: [outputs.len + 1]OutputSpeaker = undefined;
    @memcpy(outputs_with_lfe[0..outputs.len], &outputs);
    outputs_with_lfe[outputs.len] = .{
        .label = "LFE1",
        .is_lfe = true,
        .nominal_polar = .{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        },
        .allocentric = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    };
    const lfe_point =
        try CartesianPointSourcePanner(f64).init(&outputs_with_lfe);
    const lfe_extent =
        try CartesianExtentPanner(f64).init(&lfe_point);
    var lfe_gains: [outputs_with_lfe.len]f64 = undefined;
    try lfe_extent.calculateGains(
        cases[1].position,
        cases[1].size_x,
        cases[1].size_y,
        cases[1].size_z,
        &lfe_gains,
    );
    for (lfe_gains[0..outputs.len], cases[1].expected) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_001,
        );
    }
    try std.testing.expectEqual(@as(f64, 0.0), lfe_gains[outputs.len]);

    const stereo_outputs = [_]OutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = -1.0, .y = 1.0, .z = 0.0 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = 1.0, .y = 1.0, .z = 0.0 },
        },
    };
    const stereo_point =
        try CartesianPointSourcePanner(f32).init(&stereo_outputs);
    const stereo_extent =
        try CartesianExtentPanner(f32).init(&stereo_point);
    var stereo_gains: [stereo_outputs.len]f32 = undefined;
    try stereo_extent.calculateGains(
        .{ .x = 0.5, .y = 0.0, .z = 0.0 },
        0.5,
        0.0,
        0.0,
        &stereo_gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.550152941340817),
        stereo_gains[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.835063914400597),
        stereo_gains[1],
        0.000_001,
    );
    var irrelevant_extent_gains: [stereo_outputs.len]f32 = undefined;
    try stereo_extent.calculateGains(
        .{ .x = 0.5, .y = 0.0, .z = 0.0 },
        0.5,
        1.0,
        1.0,
        &irrelevant_extent_gains,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.53202693),
        irrelevant_extent_gains[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.84672743),
        irrelevant_extent_gains[1],
        0.000_001,
    );

    gains = @splat(7.0);
    try std.testing.expectError(
        error.InvalidAdmCartesianExtent,
        panner.calculateGains(
            .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            std.math.nan(f64),
            0.0,
            0.0,
            &gains,
        ),
    );
    try std.testing.expectEqual(
        @as([outputs.len]f64, @splat(7.0)),
        gains,
    );
    panner.core.output_count = 0;
    try std.testing.expect(!panner.valid());
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        panner.calculateGains(
            .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            0.2,
            0.2,
            0.2,
            &gains,
        ),
    );
    try std.testing.expectEqual(
        @as([outputs.len]f64, @splat(7.0)),
        gains,
    );
}

test "ADM Cartesian extent panner uses the full grid for three height planes" {
    const Core = adm_cartesian_extent.Panner(f64, 12);
    const positions = [_]adm_cartesian_extent.Position{
        .{ .x = -1.0, .y = 1.0, .z = -1.0 },
        .{ .x = 1.0, .y = 1.0, .z = -1.0 },
        .{ .x = -1.0, .y = -1.0, .z = -1.0 },
        .{ .x = 1.0, .y = -1.0, .z = -1.0 },
        .{ .x = -1.0, .y = 1.0, .z = 0.0 },
        .{ .x = 1.0, .y = 1.0, .z = 0.0 },
        .{ .x = -1.0, .y = -1.0, .z = 0.0 },
        .{ .x = 1.0, .y = -1.0, .z = 0.0 },
        .{ .x = -1.0, .y = 1.0, .z = 1.0 },
        .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .{ .x = -1.0, .y = -1.0, .z = 1.0 },
        .{ .x = 1.0, .y = -1.0, .z = 1.0 },
    };
    const enabled = [_]bool{true} ** positions.len;
    const point_gains = [_]f64{
        0.0,
        0.0,
        0.0,
        0.0,
        0.34012925309777514,
        0.39824018841171216,
        0.46814775458714158,
        0.54813059533491437,
        0.1733045105708482,
        0.20291351100722366,
        0.23853319508582088,
        0.27928648796967115,
    };
    const expected = [_]f64{
        0.01816511816486498,
        0.020626421203745013,
        0.025913009820218116,
        0.029424122120061194,
        0.33317542085399693,
        0.37831939780946811,
        0.47528333557135988,
        0.53968238365619559,
        0.18052107677948265,
        0.20498098234280759,
        0.25751797444351238,
        0.292410660926957,
    };
    const panner = try Core.init(&positions, &enabled);
    var gains: [positions.len]f64 = undefined;
    try panner.calculateGains(
        .{ .x = 0.1, .y = -0.2, .z = 0.3 },
        0.3,
        0.6,
        0.4,
        &point_gains,
        &gains,
    );
    for (gains, expected) |actual, expected_gain| {
        try std.testing.expectApproxEqAbs(
            expected_gain,
            actual,
            0.000_000_001,
        );
    }
}

test "ADM Cartesian extent Objects plan applies extent and diffuse gain" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0.6</position>
        \\      <position coordinate="Y">-0.3</position>
        \\      <position coordinate="Z">0.2</position>
        \\      <width>0.4</width>
        \\      <height>0.2</height>
        \\      <depth>0.7</depth>
        \\      <gain>0.5</gain>
        \\      <diffuse>0.36</diffuse>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = testCartesianCubeLayout();
    const point_panner = try CartesianPointSourcePanner(f32).init(&outputs);
    const extent_panner = try CartesianExtentPanner(f32).init(&point_panner);
    const plan =
        try ObjectCartesianExtentGainPlan(f32).initCartesianExtent(
            &block,
            &outputs,
            &extent_panner,
            .{},
        );
    try std.testing.expect(plan.valid());

    const expected = [_]f32{
        0.16216529426220688,
        0.32387243774913788,
        0.25478406622697408,
        0.50884831433256217,
        0.16272582626349621,
        0.36144228853327637,
        0.25566473938943218,
        0.56787573690083426,
    };
    for (
        plan.directGainSlice(),
        plan.diffuseGainSlice(),
        expected,
    ) |direct, diffuse, spatial| {
        try std.testing.expectApproxEqAbs(
            spatial * 0.4,
            direct,
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            spatial * 0.3,
            diffuse,
            0.000_001,
        );
    }

    var polar_block = block;
    polar_block.cartesian = false;
    try std.testing.expectError(
        error.AdmRendererCartesianObjectsBlockRequired,
        ObjectCartesianExtentGainPlan(f32).initCartesianExtent(
            &polar_block,
            &outputs,
            &extent_panner,
            .{},
        ),
    );
    var invalid_block = block;
    invalid_block.width = 1.1;
    try std.testing.expectError(
        error.InvalidAdmObjectExtent,
        ObjectCartesianExtentGainPlan(f32).initCartesianExtent(
            &invalid_block,
            &outputs,
            &extent_panner,
            .{},
        ),
    );
}

test "ADM polar extent Objects plan composes divergence and diffuse gain" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <position coordinate="distance">0.5</position>
        \\      <width>30</width>
        \\      <height>20</height>
        \\      <depth>0.8</depth>
        \\      <objectDivergence azimuthRange="30">0.5</objectDivergence>
        \\      <gain>0.5</gain>
        \\      <diffuse>0.25</diffuse>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = testPolarFiveWithLfeLayout();
    const point_panner = try PolarPointSourcePanner(f32).init(&outputs);
    var gain_storage: [polar_extent_spreading_direction_count * outputs.len]f32 = undefined;
    const extent_panner = try PolarExtentPanner(f32).init(
        &point_panner,
        &gain_storage,
    );
    const plan = try ObjectPolarExtentGainPlan(f32).initPolarExtent(
        &block,
        &outputs,
        &extent_panner,
        .{},
    );
    try std.testing.expect(plan.valid());
    try std.testing.expectEqual(
        @as(f32, 0.0),
        plan.directGainSlice()[outputs.len - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        plan.diffuseGainSlice()[outputs.len - 1],
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25 * 0.25),
        gainVectorPower(f32, plan.diffuseGainSlice()),
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25 * 0.75),
        gainVectorPower(f32, plan.directGainSlice()),
        0.000_001,
    );

    var invalid_block = block;
    invalid_block.cartesian = true;
    try std.testing.expectError(
        error.AdmRendererPolarObjectsBlockRequired,
        ObjectPolarExtentGainPlan(f32).initPolarExtent(
            &invalid_block,
            &outputs,
            &extent_panner,
            .{},
        ),
    );
    invalid_block = block;
    invalid_block.width = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidAdmObjectExtent,
        ObjectPolarExtentGainPlan(f32).initPolarExtent(
            &invalid_block,
            &outputs,
            &extent_panner,
            .{},
        ),
    );
}

test "ADM point Objects plan combines polar and Cartesian divergence power" {
    const polar_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <objectDivergence azimuthRange="30">0.5</objectDivergence>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var polar_blocks = polar_document.blocks();
    const polar_block = (try polar_blocks.next()).?;
    const polar_outputs = testPolarFiveLayout();
    const polar_panner =
        try PolarPointSourcePanner(f32).init(&polar_outputs);
    const polar_plan = try ObjectPointGainPlan(f32).init(
        &polar_block,
        &polar_outputs,
        &polar_panner,
        null,
        .{},
    );
    const equal_gain: f32 = @floatCast(@sqrt(1.0 / 3.0));
    try std.testing.expectApproxEqAbs(
        equal_gain,
        polar_plan.directGainSlice()[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        equal_gain,
        polar_plan.directGainSlice()[1],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        equal_gain,
        polar_plan.directGainSlice()[2],
        0.000_001,
    );

    const cartesian_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031002">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031002_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0</position>
        \\      <position coordinate="Y">0</position>
        \\      <position coordinate="Z">0</position>
        \\      <objectDivergence positionRange="1">1</objectDivergence>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var cartesian_blocks = cartesian_document.blocks();
    const cartesian_block = (try cartesian_blocks.next()).?;
    const cartesian_outputs = testCartesianCubeLayout();
    const cube_cartesian_panner =
        try CartesianPointSourcePanner(f64).init(&cartesian_outputs);
    const cartesian_plan = try ObjectPointGainPlan(f64).init(
        &cartesian_block,
        &cartesian_outputs,
        null,
        &cube_cartesian_panner,
        .{},
    );
    var power: f64 = 0.0;
    for (cartesian_plan.directGainSlice()) |gain|
        power += gain * gain;
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        power,
        0.000_000_001,
    );
    for (0..4) |index| {
        try std.testing.expectApproxEqAbs(
            cartesian_plan.directGainSlice()[index],
            cartesian_plan.directGainSlice()[index + 4],
            0.000_000_001,
        );
    }
}

test "ADM point Objects transforms screens and locks channels" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">29</position>
        \\      <position coordinate="elevation">17.3</position>
        \\      <screenRef>1</screenRef>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    var block = (try blocks.next()).?;
    const outputs = testPolarFiveLayout();
    const reproduction = ScreenEdges{
        .left_azimuth_degrees = 45.0,
        .right_azimuth_degrees = -45.0,
        .bottom_elevation_degrees = -25.0,
        .top_elevation_degrees = 25.0,
    };
    const scaled = try applyObjectScreenTransforms(
        &block,
        &outputs,
        .{ .reproduction_screen_edges = reproduction },
        try objectPosition(&block),
    );
    try expectPolarApprox(
        .{
            .azimuth_degrees = 45.0,
            .elevation_degrees = 25.0,
        },
        try cartesianToPolar(scaled),
    );

    const cartesian_input = try admPolarToCartesian(.{
        .azimuth_degrees = 29.0,
        .elevation_degrees = 17.3,
    });
    block.cartesian = true;
    block.positions[0] = .{
        .coordinate = .x,
        .bound = .exact,
        .value = cartesian_input.x,
    };
    block.positions[1] = .{
        .coordinate = .y,
        .bound = .exact,
        .value = cartesian_input.y,
    };
    block.positions[2] = .{
        .coordinate = .z,
        .bound = .exact,
        .value = cartesian_input.z,
    };
    block.position_count = 3;
    const scaled_cartesian = try applyObjectScreenTransforms(
        &block,
        &outputs,
        .{ .reproduction_screen_edges = reproduction },
        try objectPosition(&block),
    );
    try expectPolarApprox(
        .{
            .azimuth_degrees = 45.0,
            .elevation_degrees = 25.0,
        },
        try admCartesianToPolar(scaled_cartesian),
    );

    block.cartesian = false;
    block.positions[0] = .{
        .coordinate = .azimuth,
        .bound = .exact,
        .value = 29.0,
        .screen_edge_lock = .right,
    };
    block.positions[1] = .{
        .coordinate = .elevation,
        .bound = .exact,
        .value = 17.3,
        .screen_edge_lock = .bottom,
    };
    block.position_count = 2;
    block.positions[0].screen_edge_lock = .right;
    block.positions[1].screen_edge_lock = .bottom;
    block.screen_ref = false;
    const locked = try applyObjectScreenTransforms(
        &block,
        &outputs,
        .{ .reproduction_screen_edges = reproduction },
        try objectPosition(&block),
    );
    try expectPolarApprox(
        .{
            .azimuth_degrees = -45.0,
            .elevation_degrees = -25.0,
        },
        try cartesianToPolar(locked),
    );

    const stereo_outputs = [_]OutputSpeaker{
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
    block.positions[0].value = 0.0;
    block.positions[0].screen_edge_lock = null;
    block.positions[1].value = 0.0;
    block.positions[1].screen_edge_lock = null;
    block.channel_lock = .{ .enabled = true };
    const channel_locked = try applyObjectChannelLock(
        &block,
        &stereo_outputs,
        try objectPosition(&block),
    );
    try expectCartesianApprox(
        polarToCartesian(.{
            .azimuth_degrees = -30.0,
            .elevation_degrees = 0.0,
        }),
        channel_locked,
    );
    block.channel_lock.max_distance = 0.1;
    const outside_lock_range = try applyObjectChannelLock(
        &block,
        &stereo_outputs,
        try objectPosition(&block),
    );
    try expectCartesianApprox(
        .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        outside_lock_range,
    );

    const allocentric_outputs = [_]OutputSpeaker{
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = -1.0, .y = 0.9 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = 0.0, .y = 0.0 },
        },
    };
    block.cartesian = true;
    block.channel_lock.max_distance = null;
    const weighted_lock = try applyObjectChannelLock(
        &block,
        &allocentric_outputs,
        .{ .x = -1.0, .y = 0.0, .z = 0.0 },
    );
    try expectCartesianApprox(
        allocentric_outputs[1].allocentric,
        weighted_lock,
    );
}

test "ADM point Objects plan rejects unsupported and aliased work" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    var block = (try blocks.next()).?;
    const outputs = testPolarFiveWithLfeLayout();
    const polar_panner = try PolarPointSourcePanner(f32).init(&outputs);

    block.width = 1.0;
    try std.testing.expectError(
        error.UnsupportedAdmObjectExtent,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.width = 0.0;
    try std.testing.expectError(
        error.InvalidAdmRendererScreenGeometry,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{
                .reproduction_screen_edges = .{
                    .left_azimuth_degrees = -30.0,
                    .right_azimuth_degrees = 30.0,
                    .bottom_elevation_degrees = -15.0,
                    .top_elevation_degrees = 15.0,
                },
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmRendererScreenGeometry,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{
                .reproduction_screen_edges = .{
                    .left_azimuth_degrees = 0.0,
                    .right_azimuth_degrees = 0.0,
                    .bottom_elevation_degrees = 0.0,
                    .top_elevation_degrees = 0.0,
                },
            },
        ),
    );
    try std.testing.expectError(
        error.AdmRendererPolarPointPannerRequired,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            null,
            null,
            .{},
        ),
    );
    block.diffuse = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidAdmRendererDiffuse,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.diffuse = 0.0;
    block.object_divergence.position_range = 0.5;
    try std.testing.expectError(
        error.InvalidAdmRendererObjectDivergence,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.object_divergence.position_range = null;

    const plan = try ObjectPointGainPlan(f32).init(
        &block,
        &outputs,
        &polar_panner,
        null,
        .{},
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        plan.directGainSlice()[outputs.len - 1],
    );
    try std.testing.expectEqual(
        @as(f32, 0.0),
        plan.diffuseGainSlice()[outputs.len - 1],
    );

    const input = [_]f32{ 1.0, 2.0 };
    var storage: [outputs.len][input.len]f32 = @splat(@splat(7.0));
    var direct_outputs: [outputs.len][]f32 = undefined;
    var diffuse_outputs: [outputs.len][]f32 = undefined;
    for (&storage, &direct_outputs, &diffuse_outputs) |
        *channel,
        *direct_output,
        *diffuse_output,
    | {
        direct_output.* = channel;
        diffuse_output.* = channel;
    }
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        plan.mix(&input, &direct_outputs, &diffuse_outputs),
    );
    for (storage) |channel|
        try std.testing.expectEqualDeep(
            [_]f32{ 7.0, 7.0 },
            channel,
        );

    var invalid_plan = plan;
    invalid_plan.output_count = maximum_output_channels + 1;
    try std.testing.expect(!invalid_plan.valid());
    try std.testing.expectEqual(
        maximum_output_channels,
        invalid_plan.directGainSlice().len,
    );
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        invalid_plan.mix(&input, &direct_outputs, &diffuse_outputs),
    );
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

fn testPolarFiveWithLfeLayout() [6]OutputSpeaker {
    const base = testPolarFiveLayout();
    return .{
        base[0],
        base[1],
        base[2],
        base[3],
        base[4],
        .{
            .label = "LFE1",
            .is_lfe = true,
            .nominal_polar = .{
                .azimuth_degrees = 0.0,
                .elevation_degrees = 0.0,
            },
            .allocentric = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
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
