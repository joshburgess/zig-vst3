const std = @import("std");
const adm = @import("../adm.zig");
const common = @import("common.zig");
const direct_speaker = @import("direct_speaker.zig");
const matrix = @import("matrix.zig");
const panning = @import("panner.zig");
const adm_cartesian_extent = @import("../adm_cartesian_extent.zig");
const adm_direct_speaker_mapping =
    @import("../adm_direct_speaker_mapping.zig");
const adm_polar_extent = @import("../adm_polar_extent.zig");
const adm_polar_panner = @import("../adm_polar_panner.zig");
const adm_sample_time = @import("../adm_sample_time.zig");
const adm_time = @import("../adm_time.zig");
const adm_xml = @import("../adm_xml.zig");

pub const maximum_input_channels = common.maximum_input_channels;
pub const maximum_output_channels = common.maximum_output_channels;
pub const polar_extent_spreading_direction_count =
    common.polar_extent_spreading_direction_count;
const position_tolerance: f64 = 1.0e-5;
const insideUnitCube = common.insideUnitCube;
const mixGainVector = common.mixGainVector;
const normalizeSpeakerLabel = common.normalizeSpeakerLabel;
const onUnitCubeSurface = common.onUnitCubeSurface;
const pannerPolarPosition = common.pannerPolarPosition;
const renderGain = common.renderGain;
const samePosition = common.samePosition;
const sameSign = common.sameSign;
const slicesOverlap = common.slicesOverlap;
const subtractPosition = common.subtractPosition;
const validCartesian = common.validCartesian;
const validateMixBuffers = common.validateMixBuffers;
const validateOutputLayout = common.validateOutputLayout;
const validatePannerPosition = common.validatePannerPosition;
const validPolar = common.validPolar;
const CoordinateBounds = common.CoordinateBounds;
const PolarBounds = common.PolarBounds;
const CartesianBounds = common.CartesianBounds;
const polarBounds = common.polarBounds;
const cartesianBounds = common.cartesianBounds;
const coordinateBounds = common.coordinateBounds;
const closestPolarOutput = common.closestPolarOutput;
const closestCartesianOutput = common.closestCartesianOutput;
const polarWithinBounds = common.polarWithinBounds;
const cartesianWithinBounds = common.cartesianWithinBounds;
const withinLinearBounds = common.withinLinearBounds;
const insideAngleRange = common.insideAngleRange;
const positiveAngle = common.positiveAngle;
const polarToCartesian = common.polarToCartesian;
const ConversionSector = common.ConversionSector;
const admPolarToCartesian = common.admPolarToCartesian;
const admCartesianToPolar = common.admCartesianToPolar;
const findConversionSector = common.findConversionSector;
const mapAzimuthToLinear = common.mapAzimuthToLinear;
const mapLinearToAzimuth = common.mapLinearToAzimuth;
const relativeAngle = common.relativeAngle;
const degreesToRadians = common.degreesToRadians;
const radiansToDegrees = common.radiansToDegrees;
const signValue = common.signValue;
const cartesianDistance = common.cartesianDistance;
const hasScreenEdgeLock = common.hasScreenEdgeLock;
const validateScreenEdges = common.validateScreenEdges;
const applyPolarScreenEdgeLock = common.applyPolarScreenEdgeLock;
const compensateCartesianScreenPosition = common.compensateCartesianScreenPosition;
const piecewiseLinear = common.piecewiseLinear;

pub const PolarPosition = common.PolarPosition;
pub const CartesianPosition = common.CartesianPosition;
pub const OutputSpeaker = common.OutputSpeaker;
pub const ScreenEdges = common.ScreenEdges;

pub const DirectSpeakerRoutingContext =
    direct_speaker.DirectSpeakerRoutingContext;
pub const DirectSpeakerCommonPackMapping =
    direct_speaker.DirectSpeakerCommonPackMapping;

pub const MatrixVariableKind = matrix.MatrixVariableKind;
pub const MatrixVariableInterpolation = matrix.MatrixVariableInterpolation;
pub const MatrixVariablePoint = matrix.MatrixVariablePoint;
pub const MatrixVariableTimeline = matrix.MatrixVariableTimeline;

pub const ObjectRenderingContext = struct {
    reference_screen_edges: ?ScreenEdges = null,
    reproduction_screen_edges: ?ScreenEdges = null,
};

pub const DirectSpeakerRoute = direct_speaker.DirectSpeakerRoute;

pub const PolarPointSourcePanner = panning.PolarPointSourcePanner;
pub const PolarExtentPanner = panning.PolarExtentPanner;
pub const CartesianPointSourcePanner = panning.CartesianPointSourcePanner;
pub const CartesianExtentPanner = panning.CartesianExtentPanner;

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

        output_count: usize = 0,
        declared_output_count: usize = 0,
        direct_gains: [maximum_output_channels]Sample = @splat(0.0),
        diffuse_gains: [maximum_output_channels]Sample = @splat(0.0),

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

            const exclusion = try objectExclusion(block, outputs);
            var reduced_outputs: [maximum_output_channels]OutputSpeaker =
                undefined;
            var reduced_to_full: [maximum_output_channels]u8 = undefined;
            var reduced_count: usize = 0;
            if (block.cartesian and exclusion.effective()) {
                for (outputs, 0..) |output, output_index| {
                    if (output.is_lfe or exclusion.excluded[output_index])
                        continue;
                    reduced_outputs[reduced_count] = output;
                    reduced_to_full[reduced_count] = @intCast(output_index);
                    reduced_count += 1;
                }
            }
            var reduced_point: CartesianPointSourcePanner(Sample) = undefined;
            var reduced_extent: CartesianExtentPanner(Sample) = undefined;
            if (reduced_count != 0) {
                reduced_point = try CartesianPointSourcePanner(Sample).init(
                    reduced_outputs[0..reduced_count],
                );
                switch (spatial_panner) {
                    .cartesian_extent => {
                        reduced_extent =
                            try CartesianExtentPanner(Sample).init(
                                &reduced_point,
                            );
                    },
                    else => {},
                }
            }

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
                if (block.cartesian and exclusion.effective())
                    exclusion.excluded[0..outputs.len]
                else
                    null,
            );

            const diverged = try objectDivergence(block, position);
            var combined: [maximum_output_channels]f64 = @splat(0.0);
            var branch_gains: [maximum_output_channels]Sample = undefined;
            var reduced_gains: [maximum_output_channels]Sample = undefined;
            for (
                diverged.positions[0..diverged.count],
                diverged.power_weights[0..diverged.count],
            ) |branch_position, power_weight| {
                if (power_weight == 0.0) continue;
                if (block.cartesian and exclusion.effective()) {
                    @memset(branch_gains[0..outputs.len], 0.0);
                    switch (spatial_panner) {
                        .point => {
                            try reduced_point.calculateGains(
                                branch_position,
                                reduced_gains[0..reduced_count],
                            );
                        },
                        .cartesian_extent => {
                            try reduced_extent.calculateGains(
                                branch_position,
                                block.width,
                                block.height,
                                block.depth,
                                reduced_gains[0..reduced_count],
                            );
                        },
                        .polar_extent => {
                            return error.AdmRendererCartesianObjectsBlockRequired;
                        },
                    }
                    for (
                        reduced_to_full[0..reduced_count],
                        reduced_gains[0..reduced_count],
                    ) |full_index, gain| {
                        branch_gains[full_index] = gain;
                    }
                } else {
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
                }
                for (
                    combined[0..outputs.len],
                    branch_gains[0..outputs.len],
                ) |*output_power, branch_gain| {
                    const gain: f64 = @floatCast(branch_gain);
                    output_power.* += power_weight * gain * gain;
                }
            }
            if (!block.cartesian)
                try applyPolarExclusionDownmix(
                    outputs,
                    exclusion,
                    &combined,
                );

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

            var result = Self{
                .output_count = outputs.len,
                .declared_output_count = outputs.len,
            };
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
            if (!self.retainedGainsValid()) return &.{};
            return self.direct_gains[0..self.output_count];
        }

        pub fn diffuseGainSlice(self: *const Self) []const Sample {
            if (!self.retainedGainsValid()) return &.{};
            return self.diffuse_gains[0..self.output_count];
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
            return self.retainedGainsValid();
        }

        fn retainedGainsValid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels or
                self.output_count != self.declared_output_count)
            {
                return false;
            }
            for (
                self.direct_gains[0..self.output_count],
                self.diffuse_gains[0..self.output_count],
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

/// Owns a bounded sequence of precomputed Objects gain targets.
pub fn ObjectGainTimeline(
    comptime Sample: type,
    comptime maximum_blocks: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ObjectGainTimeline supports f32 and f64 samples");
    if (maximum_blocks == 0)
        @compileError("ObjectGainTimeline requires at least one block");

    return struct {
        const Self = @This();
        const GainPlan = ObjectPointGainPlan(Sample);
        const PointPanners = struct {
            polar: ?*const PolarPointSourcePanner(Sample),
            cartesian: ?*const CartesianPointSourcePanner(Sample),
        };
        const SpatialPanner = union(enum) {
            point: PointPanners,
            polar_extent: *const PolarExtentPanner(Sample),
            cartesian_extent: *const CartesianExtentPanner(Sample),
        };
        const Segment = struct {
            first_sample: u64 = 0,
            interpolation_end_sample: u64 = 0,
            end_sample: u64 = 0,
            start_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            interpolation_end_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            end_position: ExactSamplePosition = .{
                .numerator = 0,
                .denominator = 1,
            },
            interpolate_from_previous: bool = false,
            target: GainPlan = .{},
        };

        output_count: usize = 0,
        segment_count: usize = 0,
        declared_output_count: usize = 0,
        declared_segment_count: usize = 0,
        segments: [maximum_blocks]Segment = @splat(.{}),

        pub fn init(
            blocks: []const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            polar_panner: ?*const PolarPointSourcePanner(Sample),
            cartesian_panner: ?*const CartesianPointSourcePanner(Sample),
            context: ObjectRenderingContext,
            sample_rate: u32,
        ) !Self {
            return initWithPanner(
                blocks,
                outputs,
                .{ .point = .{
                    .polar = polar_panner,
                    .cartesian = cartesian_panner,
                } },
                context,
                sample_rate,
            );
        }

        pub fn initPolarExtent(
            blocks: []const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            panner: *const PolarExtentPanner(Sample),
            context: ObjectRenderingContext,
            sample_rate: u32,
        ) !Self {
            return initWithPanner(
                blocks,
                outputs,
                .{ .polar_extent = panner },
                context,
                sample_rate,
            );
        }

        pub fn initCartesianExtent(
            blocks: []const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            panner: *const CartesianExtentPanner(Sample),
            context: ObjectRenderingContext,
            sample_rate: u32,
        ) !Self {
            return initWithPanner(
                blocks,
                outputs,
                .{ .cartesian_extent = panner },
                context,
                sample_rate,
            );
        }

        fn initWithPanner(
            blocks: []const adm_xml.BlockFormat,
            outputs: []const OutputSpeaker,
            spatial_panner: SpatialPanner,
            context: ObjectRenderingContext,
            sample_rate: u32,
        ) !Self {
            if (sample_rate == 0)
                return error.InvalidAdmRendererSampleRate;
            if (blocks.len == 0)
                return error.MissingAdmRendererObjectBlock;
            if (blocks.len > maximum_blocks)
                return error.AdmRendererObjectBlockCapacityExceeded;

            const channel = blocks[0].channel_identifier;
            var result = Self{
                .output_count = outputs.len,
                .segment_count = blocks.len,
                .declared_output_count = outputs.len,
                .declared_segment_count = blocks.len,
            };
            for (blocks, 0..) |*block, block_index| {
                if (!block.channel_identifier.eql(channel))
                    return error.AdmRendererObjectChannelMismatch;
                const duration = block.duration orelse
                    return error.MissingAdmRendererObjectBlockDuration;
                if (!block.rtime_explicit)
                    return error.MissingAdmRendererObjectBlockTime;
                if (block_index != 0) {
                    const previous_identifier =
                        blocks[block_index - 1].identifier.secondary orelse
                        return error.InvalidAdmRendererObjectBlockSequence;
                    const identifier = block.identifier.secondary orelse
                        return error.InvalidAdmRendererObjectBlockSequence;
                    const expected_identifier = std.math.add(
                        u32,
                        previous_identifier,
                        1,
                    ) catch
                        return error.InvalidAdmRendererObjectBlockSequence;
                    if (identifier != expected_identifier)
                        return error.InvalidAdmRendererObjectBlockSequence;
                }

                const first_sample =
                    try ceilAdmSamples(block.rtime, null, sample_rate);
                const end_sample =
                    try ceilAdmSamples(block.rtime, duration, sample_rate);
                const start_position =
                    try exactSamplePosition(
                        block.rtime,
                        null,
                        sample_rate,
                    );
                const end_position =
                    try exactSamplePosition(
                        block.rtime,
                        duration,
                        sample_rate,
                    );
                if (end_position.compare(start_position) == .lt)
                    return error.InvalidAdmRendererObjectBlockDuration;

                var adjacent = false;
                if (block_index != 0) {
                    const previous = &blocks[block_index - 1];
                    const previous_duration = previous.duration orelse
                        return error.MissingAdmRendererObjectBlockDuration;
                    const order = try compareAdmTimeSum(
                        previous.rtime,
                        previous_duration,
                        block.rtime,
                    );
                    if (order == .gt)
                        return error.OverlappingAdmRendererObjectBlocks;
                    adjacent = order == .eq;
                }

                const interpolation_length = if (!adjacent or block_index == 0)
                    null
                else if (block.jump_position.enabled)
                    block.jump_position.interpolation_length orelse
                        zeroAdmTime()
                else
                    duration;
                if (interpolation_length) |length| {
                    if (length.compare(duration) == .gt)
                        return error.InvalidAdmRendererInterpolationLength;
                }
                const interpolation_end_sample = if (interpolation_length) |length|
                    try ceilAdmSamples(block.rtime, length, sample_rate)
                else
                    first_sample;
                const interpolation_end_position =
                    if (interpolation_length) |length|
                        try exactSamplePosition(
                            block.rtime,
                            length,
                            sample_rate,
                        )
                    else
                        start_position;

                const target = switch (spatial_panner) {
                    .point => |panners| try GainPlan.init(
                        block,
                        outputs,
                        panners.polar,
                        panners.cartesian,
                        context,
                    ),
                    .polar_extent => |panner| try GainPlan.initPolarExtent(
                        block,
                        outputs,
                        panner,
                        context,
                    ),
                    .cartesian_extent => |panner| try GainPlan.initCartesianExtent(
                        block,
                        outputs,
                        panner,
                        context,
                    ),
                };
                result.segments[block_index] = .{
                    .first_sample = first_sample,
                    .interpolation_end_sample = interpolation_end_sample,
                    .end_sample = end_sample,
                    .start_position = start_position,
                    .interpolation_end_position = interpolation_end_position,
                    .end_position = end_position,
                    .interpolate_from_previous = adjacent and
                        interpolation_end_position.compare(start_position) ==
                            .gt,
                    .target = target,
                };
            }
            if (!result.valid())
                return error.InvalidAdmRendererState;
            return result;
        }

        pub fn mix(
            self: *const Self,
            first_sample: u64,
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
            const input_length: u64 = std.math.cast(
                u64,
                input.len,
            ) orelse return error.AdmRendererSampleRangeOverflow;
            const end_sample = std.math.add(
                u64,
                first_sample,
                input_length,
            ) catch return error.AdmRendererSampleRangeOverflow;

            for (self.segmentSlice(), 0..) |*segment, segment_index| {
                const overlap_start =
                    @max(first_sample, segment.first_sample);
                const overlap_end = @min(end_sample, segment.end_sample);
                if (overlap_start >= overlap_end) continue;
                const source = if (segment.interpolate_from_previous)
                    &self.segments[segment_index - 1].target
                else
                    &segment.target;
                var sample = overlap_start;
                while (sample < overlap_end) : (sample += 1) {
                    const input_index: usize = @intCast(
                        sample - first_sample,
                    );
                    const input_sample = input[input_index];
                    if (!std.math.isFinite(input_sample)) continue;
                    const phase = if (segment.interpolate_from_previous and
                        sample < segment.interpolation_end_sample)
                        interpolationPhase(segment, sample)
                    else
                        1.0;
                    for (
                        direct_outputs,
                        source.directGainSlice(),
                        segment.target.directGainSlice(),
                    ) |output, source_gain, target_gain| {
                        mixInterpolatedSample(
                            output,
                            input_index,
                            input_sample,
                            source_gain,
                            target_gain,
                            phase,
                        );
                    }
                    for (
                        diffuse_outputs,
                        source.diffuseGainSlice(),
                        segment.target.diffuseGainSlice(),
                    ) |output, source_gain, target_gain| {
                        mixInterpolatedSample(
                            output,
                            input_index,
                            input_sample,
                            source_gain,
                            target_gain,
                            phase,
                        );
                    }
                }
            }
        }

        pub fn blockCount(self: *const Self) usize {
            return if (self.valid()) self.segment_count else 0;
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels or
                self.output_count != self.declared_output_count or
                self.segment_count == 0 or
                self.segment_count > maximum_blocks or
                self.segment_count != self.declared_segment_count)
            {
                return false;
            }
            for (self.segmentSlice(), 0..) |segment, index| {
                if (segment.target.output_count != self.output_count or
                    !segment.target.valid() or
                    segment.first_sample > segment.interpolation_end_sample or
                    segment.interpolation_end_sample > segment.end_sample or
                    segment.interpolation_end_position.compare(
                        segment.start_position,
                    ) == .lt or
                    segment.end_position.compare(
                        segment.interpolation_end_position,
                    ) == .lt or
                    (segment.start_position.ceil() catch null) !=
                        segment.first_sample or
                    (segment.interpolation_end_position.ceil() catch null) !=
                        segment.interpolation_end_sample or
                    (segment.end_position.ceil() catch null) !=
                        segment.end_sample)
                {
                    return false;
                }
                if (segment.interpolate_from_previous) {
                    if (index == 0 or
                        segment.interpolation_end_position.compare(
                            segment.start_position,
                        ) != .gt or
                        self.segments[index - 1].end_position.compare(
                            segment.start_position,
                        ) != .eq)
                    {
                        return false;
                    }
                } else if (segment.interpolation_end_position.compare(
                    segment.start_position,
                ) != .eq) {
                    return false;
                }
                if (index != 0 and
                    self.segments[index - 1].end_position.compare(
                        segment.start_position,
                    ) == .gt)
                {
                    return false;
                }
            }
            return true;
        }

        fn segmentSlice(self: *const Self) []const Segment {
            return self.segments[0..@min(
                self.segment_count,
                maximum_blocks,
            )];
        }

        fn interpolationPhase(
            segment: *const Segment,
            sample: u64,
        ) Sample {
            return adm_sample_time.interpolationPhase(
                Sample,
                segment.start_position,
                segment.interpolation_end_position,
                sample,
            );
        }

        fn mixInterpolatedSample(
            output: []Sample,
            sample_index: usize,
            input_sample: Sample,
            source_gain: Sample,
            target_gain: Sample,
            phase: Sample,
        ) void {
            if (!std.math.isFinite(output[sample_index])) {
                output[sample_index] = 0.0;
                return;
            }
            const gain =
                source_gain + (target_gain - source_gain) * phase;
            const mixed =
                output[sample_index] + input_sample * gain;
            output[sample_index] = if (std.math.isFinite(mixed))
                mixed
            else
                0.0;
        }
    };
}

pub const StaticMatrixMixer = matrix.StaticMatrixMixer;
pub const MatrixCoefficientMixer = matrix.MatrixCoefficientMixer;
pub const VariableMatrixCoefficientMixer =
    matrix.VariableMatrixCoefficientMixer;

pub const DirectSpeakerRouter = direct_speaker.DirectSpeakerRouter;
pub const DirectSpeakerPositionRouter =
    direct_speaker.DirectSpeakerPositionRouter;
pub const resolveDirectSpeakerRoute =
    direct_speaker.resolveDirectSpeakerRoute;

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

const ObjectExclusion = struct {
    excluded: [maximum_output_channels]bool = @splat(false),
    active_count: usize = 0,
    excluded_count: usize = 0,

    fn effective(self: ObjectExclusion) bool {
        return self.excluded_count != 0 and
            self.excluded_count != self.active_count;
    }
};

fn objectExclusion(
    block: *const adm_xml.BlockFormat,
    outputs: []const OutputSpeaker,
) !ObjectExclusion {
    if (block.exclusion_zone_count > adm_xml.max_adm_exclusion_zones)
        return error.InvalidAdmRendererExclusionZones;

    var result = ObjectExclusion{};
    for (outputs) |output| {
        if (!output.is_lfe) result.active_count += 1;
    }
    for (block.exclusionZoneSlice()) |zone| {
        try validateRendererExclusionZone(zone);
        for (outputs, 0..) |output, output_index| {
            if (output.is_lfe or result.excluded[output_index]) continue;
            if (speakerInsideExclusionZone(output, zone))
                result.excluded[output_index] = true;
        }
    }
    if (block.cartesian) {
        for (outputs, 0..) |output, output_index| {
            if (!result.excluded[output_index]) continue;
            const position = output.allocentric;
            if (@abs(@abs(position.x) - 1.0) > 1.0e-6 or
                @abs(@abs(position.y) - 1.0) <= 1.0e-6)
            {
                continue;
            }
            for (outputs, 0..) |candidate, candidate_index| {
                if (candidate.is_lfe) continue;
                if (@abs(candidate.allocentric.y - position.y) < 1.0e-6 and
                    @abs(candidate.allocentric.z - position.z) < 1.0e-6)
                {
                    result.excluded[candidate_index] = true;
                }
            }
        }
    }
    for (outputs, result.excluded[0..outputs.len]) |output, excluded| {
        if (!output.is_lfe and excluded) result.excluded_count += 1;
    }
    if (block.cartesian and
        result.excluded_count == result.active_count)
    {
        @memset(result.excluded[0..outputs.len], false);
        result.excluded_count = 0;
    }
    return result;
}

fn validateRendererExclusionZone(zone: adm_xml.ExclusionZone) !void {
    switch (zone) {
        .cartesian => |value| {
            const coordinates = [_]f64{
                value.min_x,
                value.min_y,
                value.min_z,
                value.max_x,
                value.max_y,
                value.max_z,
            };
            for (coordinates) |coordinate| {
                if (!std.math.isFinite(coordinate) or
                    coordinate < -1.0 or
                    coordinate > 1.0)
                {
                    return error.InvalidAdmRendererExclusionZones;
                }
            }
            if (value.min_x > value.max_x or
                value.min_y > value.max_y or
                value.min_z > value.max_z)
            {
                return error.InvalidAdmRendererExclusionZones;
            }
        },
        .polar => |value| {
            if (!std.math.isFinite(value.min_azimuth) or
                !std.math.isFinite(value.max_azimuth) or
                !std.math.isFinite(value.min_elevation) or
                !std.math.isFinite(value.max_elevation) or
                value.min_azimuth < -180.0 or
                value.min_azimuth > 180.0 or
                value.max_azimuth < -180.0 or
                value.max_azimuth > 180.0 or
                value.min_elevation < -90.0 or
                value.min_elevation > 90.0 or
                value.max_elevation < -90.0 or
                value.max_elevation > 90.0 or
                value.min_elevation > value.max_elevation)
            {
                return error.InvalidAdmRendererExclusionZones;
            }
        },
    }
}

fn speakerInsideExclusionZone(
    output: OutputSpeaker,
    zone: adm_xml.ExclusionZone,
) bool {
    const epsilon = 1.0e-6;
    return switch (zone) {
        .cartesian => |value| inside: {
            var nominal = output.nominal_polar;
            nominal.distance = 1.0;
            const position = polarToCartesian(nominal);
            break :inside position.x - epsilon < value.max_x and
                position.x + epsilon > value.min_x and
                position.y - epsilon < value.max_y and
                position.y + epsilon > value.min_y and
                position.z - epsilon < value.max_z and
                position.z + epsilon > value.min_z;
        },
        .polar => |value| output.nominal_polar.elevation_degrees - epsilon <
            value.max_elevation and
            output.nominal_polar.elevation_degrees + epsilon >
                value.min_elevation and
            (@abs(output.nominal_polar.elevation_degrees) >
                90.0 - epsilon or
                insideAngleRange(
                    output.nominal_polar.azimuth_degrees,
                    value.min_azimuth,
                    value.max_azimuth,
                    epsilon,
                )),
    };
}

const ExclusionPriority = struct {
    layer: u8,
    front_back_change: f64,
    distance: f64,
    front_back_distance: f64,
};

fn applyPolarExclusionDownmix(
    outputs: []const OutputSpeaker,
    exclusion: ObjectExclusion,
    powers: *[maximum_output_channels]f64,
) !void {
    if (!exclusion.effective()) return;
    var redistributed: [maximum_output_channels]f64 = @splat(0.0);
    for (outputs, 0..) |source, source_index| {
        if (source.is_lfe) continue;
        var representatives: [maximum_output_channels]ExclusionPriority = undefined;
        var target_groups: [maximum_output_channels]u8 = undefined;
        var group_count: usize = 0;
        for (outputs, 0..) |target, target_index| {
            if (target.is_lfe) continue;
            const priority = exclusionPriority(source, target);
            var group_index: ?usize = null;
            for (representatives[0..group_count], 0..) |
                representative,
                index,
            | {
                if (sameExclusionPriority(priority, representative)) {
                    group_index = index;
                    break;
                }
            }
            const index = group_index orelse add: {
                representatives[group_count] = priority;
                group_count += 1;
                break :add group_count - 1;
            };
            target_groups[target_index] = @intCast(index);
        }
        var selected_group: ?usize = null;
        for (representatives[0..group_count], 0..) |
            representative,
            group_index,
        | {
            var has_destination = false;
            for (outputs, 0..) |target, target_index| {
                if (!target.is_lfe and
                    !exclusion.excluded[target_index] and
                    target_groups[target_index] == group_index)
                {
                    has_destination = true;
                    break;
                }
            }
            if (!has_destination) continue;
            if (selected_group) |current| {
                if (priorityLess(
                    representative,
                    representatives[current],
                )) {
                    selected_group = group_index;
                }
            } else {
                selected_group = group_index;
            }
        }
        const selected = selected_group orelse
            return error.InvalidAdmRendererExclusionZones;
        var destination_count: usize = 0;
        for (outputs, 0..) |target, target_index| {
            if (target.is_lfe or exclusion.excluded[target_index]) continue;
            if (target_groups[target_index] == selected)
                destination_count += 1;
        }
        if (destination_count == 0)
            return error.InvalidAdmRendererExclusionZones;
        const contribution =
            powers[source_index] /
            @as(f64, @floatFromInt(destination_count));
        if (!std.math.isFinite(contribution) or contribution < 0.0)
            return error.InvalidAdmRendererPannerGain;
        for (outputs, 0..) |target, target_index| {
            if (target.is_lfe or exclusion.excluded[target_index]) continue;
            if (target_groups[target_index] == selected)
                redistributed[target_index] += contribution;
        }
    }
    @memcpy(
        powers[0..outputs.len],
        redistributed[0..outputs.len],
    );
}

fn exclusionPriority(
    source: OutputSpeaker,
    target: OutputSpeaker,
) ExclusionPriority {
    const source_position = nominalUnitPosition(source);
    const target_position = nominalUnitPosition(target);
    const layer_priority = [4][4]u8{
        .{ 0, 1, 2, 3 },
        .{ 3, 0, 1, 2 },
        .{ 3, 2, 0, 1 },
        .{ 3, 2, 1, 0 },
    };
    return .{
        .layer = layer_priority[
            exclusionLayer(source.nominal_polar.elevation_degrees)
        ][exclusionLayer(target.nominal_polar.elevation_degrees)],
        .front_back_change = @abs(
            exclusionSign(source_position.y) -
                exclusionSign(target_position.y),
        ),
        .distance = cartesianDistance(
            source_position,
            target_position,
        ),
        .front_back_distance = @abs(source_position.y - target_position.y),
    };
}

fn exclusionLayer(elevation_degrees: f64) u2 {
    if (elevation_degrees < -10.0) return 0;
    if (elevation_degrees < 10.0) return 1;
    if (elevation_degrees < 75.0) return 2;
    return 3;
}

fn exclusionSign(value: f64) f64 {
    if (value > 1.0e-6) return 1.0;
    if (value < -1.0e-6) return -1.0;
    return 0.0;
}

fn nominalUnitPosition(output: OutputSpeaker) CartesianPosition {
    var nominal = output.nominal_polar;
    nominal.distance = 1.0;
    return polarToCartesian(nominal);
}

fn priorityLess(
    left: ExclusionPriority,
    right: ExclusionPriority,
) bool {
    if (left.layer != right.layer) return left.layer < right.layer;
    if (left.front_back_change != right.front_back_change)
        return left.front_back_change < right.front_back_change;
    if (left.distance != right.distance)
        return left.distance < right.distance;
    return left.front_back_distance < right.front_back_distance;
}

fn sameExclusionPriority(
    left: ExclusionPriority,
    right: ExclusionPriority,
) bool {
    return left.layer == right.layer and
        @abs(left.front_back_change - right.front_back_change) < 1.0e-6 and
        @abs(left.distance - right.distance) < 1.0e-6 and
        @abs(left.front_back_distance - right.front_back_distance) < 1.0e-6;
}

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
    excluded: ?[]const bool,
) !CartesianPosition {
    if (excluded) |mask| {
        if (mask.len != outputs.len)
            return error.InvalidAdmRendererExclusionZones;
    }
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
        if (excluded) |mask| {
            if (mask[output_index]) continue;
        }
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

pub fn canonicalSpeakerLabel(label: []const u8) ?[]const u8 {
    return normalizeSpeakerLabel(label);
}

const ExactSamplePosition = adm_sample_time.Position;

fn zeroAdmTime() adm_time.Value {
    return adm_sample_time.zero();
}

fn compareAdmTimeSum(
    first: adm_time.Value,
    second: adm_time.Value,
    expected: adm_time.Value,
) !std.math.Order {
    return adm_sample_time.compareSum(
        first,
        second,
        expected,
    ) catch |err| return mapSampleTimeError(err);
}

fn ceilAdmSamples(
    first: adm_time.Value,
    second: ?adm_time.Value,
    sample_rate: u32,
) !u64 {
    return (try exactSamplePosition(
        first,
        second,
        sample_rate,
    )).ceil() catch |err| return mapSampleTimeError(err);
}

fn exactSamplePosition(
    first: adm_time.Value,
    second: ?adm_time.Value,
    sample_rate: u32,
) !ExactSamplePosition {
    return adm_sample_time.position(
        first,
        second,
        sample_rate,
    ) catch |err| return mapSampleTimeError(err);
}

fn mapSampleTimeError(
    err: error{
        InvalidAdmSampleTime,
        AdmSampleTimeOverflow,
    },
) error{
    InvalidAdmRendererTime,
    AdmRendererTimeOverflow,
} {
    return switch (err) {
        error.InvalidAdmSampleTime => error.InvalidAdmRendererTime,
        error.AdmSampleTimeOverflow => error.AdmRendererTimeOverflow,
    };
}

fn gainVectorPower(comptime Sample: type, gains: []const Sample) Sample {
    var power: Sample = 0.0;
    for (gains) |gain| power += gain * gain;
    return power;
}

test "ADM object renderer common public names remain exact aliases" {
    try std.testing.expect(PolarPosition == common.PolarPosition);
    try std.testing.expect(CartesianPosition == common.CartesianPosition);
    try std.testing.expect(OutputSpeaker == common.OutputSpeaker);
    try std.testing.expect(ScreenEdges == common.ScreenEdges);
    try std.testing.expectEqual(
        common.maximum_input_channels,
        maximum_input_channels,
    );
    try std.testing.expectEqual(
        common.maximum_output_channels,
        maximum_output_channels,
    );
    try std.testing.expectEqual(
        common.polar_extent_spreading_direction_count,
        polar_extent_spreading_direction_count,
    );
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
    for (plan.direct_gains[outputs.len..]) |gain|
        try std.testing.expectEqual(@as(f64, 0.0), gain);
    for (plan.diffuse_gains[outputs.len..]) |gain|
        try std.testing.expectEqual(@as(f64, 0.0), gain);
    var malformed_plan = plan;
    malformed_plan.output_count += 1;
    try std.testing.expect(!malformed_plan.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed_plan.directGainSlice().len);
    try std.testing.expectEqual(@as(usize, 0), malformed_plan.diffuseGainSlice().len);

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
    for (point_panner.positions[outputs.len..]) |position|
        try std.testing.expectEqualDeep(CartesianPosition{}, position);
    for (point_panner.enabled[outputs.len..]) |enabled|
        try std.testing.expect(!enabled);
    var panner = try CartesianExtentPanner(f64).init(&point_panner);
    for (panner.core.positions[outputs.len..]) |position|
        try std.testing.expectEqualDeep(adm_cartesian_extent.Position{}, position);
    for (panner.core.enabled[outputs.len..]) |enabled|
        try std.testing.expect(!enabled);
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
        null,
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
        null,
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
        null,
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
    block.exclusion_zone_count = adm_xml.max_adm_exclusion_zones + 1;
    try std.testing.expectError(
        error.InvalidAdmRendererExclusionZones,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.exclusion_zone_count = 1;
    block.exclusion_zones[0] = .{
        .polar = .{
            .min_azimuth = std.math.nan(f64),
            .max_azimuth = 0.0,
            .min_elevation = 0.0,
            .max_elevation = 0.0,
        },
    };
    try std.testing.expectError(
        error.InvalidAdmRendererExclusionZones,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.exclusion_zones[0] = .{
        .cartesian = .{
            .min_x = 0.5,
            .min_y = -1.0,
            .min_z = -1.0,
            .max_x = -0.5,
            .max_y = 1.0,
            .max_z = 1.0,
        },
    };
    try std.testing.expectError(
        error.InvalidAdmRendererExclusionZones,
        ObjectPointGainPlan(f32).init(
            &block,
            &outputs,
            &polar_panner,
            null,
            .{},
        ),
    );
    block.exclusion_zone_count = 0;

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
        @as(usize, 0),
        invalid_plan.directGainSlice().len,
    );
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        invalid_plan.mix(&input, &direct_outputs, &diffuse_outputs),
    );

    invalid_plan = plan;
    invalid_plan.diffuse_gains[0] = std.math.nan(f32);
    try std.testing.expect(!invalid_plan.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_plan.directGainSlice().len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_plan.diffuseGainSlice().len,
    );
}

test "ADM polar Objects exclusion redistributes power by priority" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="0" maxAzimuth="0" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const outputs = testPolarFiveWithLfeLayout();
    const panner = try PolarPointSourcePanner(f64).init(&outputs);
    const plan = try ObjectPointGainPlan(f64).init(
        &block,
        &outputs,
        &panner,
        null,
        .{},
    );
    const expected = [_]f64{
        @sqrt(0.5),
        @sqrt(0.5),
        0.0,
        0.0,
        0.0,
        0.0,
    };
    for (plan.directGainSlice(), expected) |actual, wanted| {
        try std.testing.expectApproxEqAbs(wanted, actual, 1.0e-12);
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gainVectorPower(f64, plan.directGainSlice()),
        1.0e-12,
    );

    var cartesian_zone_block = block;
    cartesian_zone_block.exclusion_zones[0] = .{
        .cartesian = .{
            .min_x = 0.0,
            .min_y = 1.0,
            .min_z = 0.0,
            .max_x = 0.0,
            .max_y = 1.0,
            .max_z = 0.0,
        },
    };
    const cartesian_zone_plan = try ObjectPointGainPlan(f64).init(
        &cartesian_zone_block,
        &outputs,
        &panner,
        null,
        .{},
    );
    for (cartesian_zone_plan.directGainSlice(), expected) |actual, wanted| {
        try std.testing.expectApproxEqAbs(wanted, actual, 1.0e-12);
    }

    var all_excluded_block = block;
    all_excluded_block.exclusion_zones[0] = .{
        .polar = .{
            .min_azimuth = -180.0,
            .max_azimuth = 180.0,
            .min_elevation = 0.0,
            .max_elevation = 0.0,
        },
    };
    const all_excluded_plan = try ObjectPointGainPlan(f64).init(
        &all_excluded_block,
        &outputs,
        &panner,
        null,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        all_excluded_plan.directGainSlice()[2],
        1.0e-12,
    );
    for (all_excluded_plan.directGainSlice(), 0..) |gain, index| {
        if (index != 2)
            try std.testing.expectApproxEqAbs(@as(f64, 0.0), gain, 1.0e-12);
    }

    const immersive_outputs = testFourPlusFiveLayout();
    const immersive_panner =
        try PolarPointSourcePanner(f64).init(&immersive_outputs);
    const mid_layer_plan = try ObjectPointGainPlan(f64).init(
        &all_excluded_block,
        &immersive_outputs,
        &immersive_panner,
        null,
        .{},
    );
    const upper_left = immersive_outputs.len - 4;
    const upper_right = immersive_outputs.len - 3;
    for (mid_layer_plan.directGainSlice(), 0..) |gain, index| {
        const wanted: f64 =
            if (index == upper_left or index == upper_right)
                @sqrt(0.5)
            else
                0.0;
        try std.testing.expectApproxEqAbs(wanted, gain, 1.0e-12);
    }
}

test "ADM polar extent exclusion follows the post-panner downmix" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <width>40</width>
        \\      <height>20</height>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="0" maxAzimuth="0" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const outputs = testPolarFiveWithLfeLayout();
    const point_panner = try PolarPointSourcePanner(f32).init(&outputs);
    var storage: [polar_extent_spreading_direction_count * outputs.len]f32 = undefined;
    const extent_panner = try PolarExtentPanner(f32).init(
        &point_panner,
        &storage,
    );
    const plan = try ObjectPolarExtentGainPlan(f32).initPolarExtent(
        &block,
        &outputs,
        &extent_panner,
        .{},
    );
    try std.testing.expectEqual(@as(f32, 0.0), plan.directGainSlice()[2]);
    try std.testing.expectEqual(@as(f32, 0.0), plan.directGainSlice()[5]);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        gainVectorPower(f32, plan.directGainSlice()),
        0.000_002,
    );
}

test "ADM exclusion matches independent composite gain vectors" {
    const outputs = testFourPlusFiveLayout();
    const polar_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <position coordinate="azimuth">15</position>
        \\      <position coordinate="elevation">5</position>
        \\      <position coordinate="distance">0.8</position>
        \\      <width>35</width>
        \\      <height>20</height>
        \\      <depth>0.4</depth>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="-5" maxAzimuth="5" minElevation="-5" maxElevation="5"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var polar_blocks = polar_document.blocks();
    const polar_block = (try polar_blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const polar_point = try PolarPointSourcePanner(f64).init(&outputs);
    var polar_storage: [polar_extent_spreading_direction_count * outputs.len]f64 = undefined;
    const polar_extent = try PolarExtentPanner(f64).init(
        &polar_point,
        &polar_storage,
    );
    const polar_plan =
        try ObjectPolarExtentGainPlan(f64).initPolarExtent(
            &polar_block,
            &outputs,
            &polar_extent,
            .{},
        );
    const expected_polar = [_]f64{
        0.76335073411451304,
        0.49146398352030901,
        0.0,
        0.061258168878796475,
        0.000017752940041608044,
        0.38262461709567069,
        0.15785851313935170,
        0.026060650294635349,
        0.0024861189992837216,
    };
    for (polar_plan.directGainSlice(), expected_polar) |actual, wanted| {
        try std.testing.expectApproxEqAbs(wanted, actual, 1.0e-9);
    }

    const cartesian_document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0.3</position>
        \\      <position coordinate="Y">0.7</position>
        \\      <position coordinate="Z">0.2</position>
        \\      <width>0.25</width>
        \\      <height>0.4</height>
        \\      <depth>0.3</depth>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="0" maxAzimuth="0" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var cartesian_blocks = cartesian_document.blocks();
    const cartesian_block = (try cartesian_blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const cartesian_point =
        try CartesianPointSourcePanner(f64).init(&outputs);
    const cartesian_extent =
        try CartesianExtentPanner(f64).init(&cartesian_point);
    const cartesian_plan =
        try ObjectCartesianExtentGainPlan(f64).initCartesianExtent(
            &cartesian_block,
            &outputs,
            &cartesian_extent,
            .{},
        );
    const expected_cartesian = [_]f64{
        0.48055502233032266,
        0.7277271788840611,
        0.0,
        0.20024680207909254,
        0.3032431950266978,
        0.17738622563448112,
        0.2686243438428574,
        0.03396828562441432,
        0.05143978008828547,
    };
    for (
        cartesian_plan.directGainSlice(),
        expected_cartesian,
    ) |actual, wanted| {
        try std.testing.expectApproxEqAbs(wanted, actual, 1.0e-9);
    }
}

test "ADM Cartesian exclusion reduces point extent and lock layouts" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">0.1</position>
        \\      <position coordinate="Y">1</position>
        \\      <position coordinate="Z">0</position>
        \\      <channelLock>1</channelLock>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="0" maxAzimuth="0" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const outputs = testPolarFiveLayout();
    const point_panner =
        try CartesianPointSourcePanner(f64).init(&outputs);
    const point_plan = try ObjectPointGainPlan(f64).init(
        &block,
        &outputs,
        null,
        &point_panner,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        point_plan.directGainSlice()[1],
        1.0e-12,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        point_plan.directGainSlice()[2],
    );

    var extent_block = block;
    extent_block.channel_lock = .{};
    extent_block.width = 0.4;
    extent_block.height = 0.2;
    extent_block.depth = 0.3;
    const extent_panner =
        try CartesianExtentPanner(f64).init(&point_panner);
    const extent_plan =
        try ObjectCartesianExtentGainPlan(f64).initCartesianExtent(
            &extent_block,
            &outputs,
            &extent_panner,
            .{},
        );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        extent_plan.directGainSlice()[2],
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gainVectorPower(f64, extent_plan.directGainSlice()),
        1.0e-9,
    );
}

test "ADM Cartesian exclusion repairs side rows and preserves all-excluded layouts" {
    const cube = testCartesianCubeLayout();
    var outputs: [cube.len + 2]OutputSpeaker = undefined;
    @memcpy(outputs[0..cube.len], &cube);
    outputs[cube.len] = .{
        .label = "M+090",
        .nominal_polar = .{
            .azimuth_degrees = 90.0,
            .elevation_degrees = 0.0,
        },
        .allocentric = .{ .x = -1.0, .y = 0.0, .z = 0.0 },
    };
    outputs[cube.len + 1] = .{
        .label = "M-090",
        .nominal_polar = .{
            .azimuth_degrees = -90.0,
            .elevation_degrees = 0.0,
        },
        .allocentric = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
    };
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00031001">
        \\    <audioBlockFormatObjects audioBlockFormatID="AB_00031001_00000001">
        \\      <cartesian>1</cartesian>
        \\      <position coordinate="X">-1</position>
        \\      <position coordinate="Y">0</position>
        \\      <position coordinate="Z">0</position>
        \\      <zoneExclusion>
        \\        <zone minAzimuth="90" maxAzimuth="90" minElevation="0" maxElevation="0"/>
        \\      </zoneExclusion>
        \\    </audioBlockFormatObjects>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()) orelse
        return error.TestExpectedAdmBlock;
    const panner = try CartesianPointSourcePanner(f64).init(&outputs);
    const plan = try ObjectPointGainPlan(f64).init(
        &block,
        &outputs,
        null,
        &panner,
        .{},
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        plan.directGainSlice()[cube.len],
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        plan.directGainSlice()[cube.len + 1],
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        gainVectorPower(f64, plan.directGainSlice()),
        1.0e-12,
    );

    var all_excluded = block;
    all_excluded.exclusion_zones[0] = .{
        .cartesian = .{
            .min_x = -1.0,
            .min_y = -1.0,
            .min_z = -1.0,
            .max_x = 1.0,
            .max_y = 1.0,
            .max_z = 1.0,
        },
    };
    const identity_plan = try ObjectPointGainPlan(f64).init(
        &all_excluded,
        &outputs,
        null,
        &panner,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        identity_plan.directGainSlice()[cube.len],
        1.0e-12,
    );
}

test "ADM Objects gain timeline renders regular jump and shortened ramps" {
    const outputs = testPolarFiveLayout();
    const panner = try PolarPointSourcePanner(f64).init(&outputs);
    var blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.00000", "1.00000", 0.25),
        try testTimedObjectBlock(2, "1.00000", "1.00000", 1.0),
        try testTimedObjectBlock(3, "2.00000", "1.00000", 0.5),
        try testTimedObjectBlock(4, "3.00000", "1.00000", 1.0),
        try testTimedObjectBlock(5, "5.00000", "1.00000", 0.25),
    };
    blocks[2].jump_position.enabled = true;
    blocks[3].jump_position = .{
        .enabled = true,
        .interpolation_length = try adm_time.Value.parse("0.50000"),
    };
    const timeline = try ObjectGainTimeline(f64, 5).init(
        &blocks,
        &outputs,
        &panner,
        null,
        .{},
        4,
    );
    try std.testing.expect(timeline.valid());
    try std.testing.expectEqual(@as(usize, 5), timeline.blockCount());

    const input: [24]f64 = @splat(1.0);
    var direct_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var direct: [outputs.len][]f64 = undefined;
    var diffuse: [outputs.len][]f64 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try timeline.mix(0, &input, &direct, &diffuse);

    try std.testing.expectEqualDeep(
        [_]f64{
            0.25, 0.25,   0.25,  0.25,
            0.25, 0.4375, 0.625, 0.8125,
            0.5,  0.5,    0.5,   0.5,
            0.5,  0.75,   1.0,   1.0,
            0.0,  0.0,    0.0,   0.0,
            0.25, 0.25,   0.25,  0.25,
        },
        direct_storage[2],
    );
    for (diffuse_storage) |channel| {
        try std.testing.expectEqualDeep(
            @as([input.len]f64, @splat(0.0)),
            channel,
        );
    }
}

test "ADM Objects gain timeline honors zero and fractional block boundaries" {
    const outputs = testPolarFiveLayout();
    const panner = try PolarPointSourcePanner(f32).init(&outputs);
    const zero_blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.00000", "0.00000", 0.2),
        try testTimedObjectBlock(2, "0.00000", "1.00000", 1.0),
    };
    const zero_timeline = try ObjectGainTimeline(f32, 2).init(
        &zero_blocks,
        &outputs,
        &panner,
        null,
        .{},
        4,
    );
    const input: [4]f32 = @splat(1.0);
    var direct_storage: [outputs.len][input.len]f32 =
        @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][input.len]f32 =
        @splat(@splat(0.0));
    var direct: [outputs.len][]f32 = undefined;
    var diffuse: [outputs.len][]f32 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try zero_timeline.mix(0, &input, &direct, &diffuse);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.2, 0.4, 0.6, 0.8 },
        direct_storage[2],
    );

    const fractional_blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.12500", "0.50000", 0.75),
    };
    const fractional_timeline = try ObjectGainTimeline(f32, 1).init(
        &fractional_blocks,
        &outputs,
        &panner,
        null,
        .{},
        4,
    );
    direct_storage = @splat(@splat(0.0));
    diffuse_storage = @splat(@splat(0.0));
    try fractional_timeline.mix(0, &input, &direct, &diffuse);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.75, 0.75, 0.0 },
        direct_storage[2],
    );

    const spare_timeline = try ObjectGainTimeline(f32, 2).init(
        &fractional_blocks,
        &outputs,
        &panner,
        null,
        .{},
        4,
    );
    const spare = spare_timeline.segments[1];
    try std.testing.expectEqual(@as(u64, 0), spare.first_sample);
    try std.testing.expectEqual(@as(u128, 1), spare.start_position.denominator);
    try std.testing.expectEqual(@as(usize, 0), spare.target.output_count);
    try std.testing.expectEqual(
        @as([maximum_output_channels]f32, @splat(0.0)),
        spare.target.direct_gains,
    );
    try std.testing.expectEqual(
        @as([maximum_output_channels]f32, @splat(0.0)),
        spare.target.diffuse_gains,
    );
}

test "ADM Objects gain timeline preserves phase beyond f64 integer precision" {
    const outputs = testPolarFiveLayout();
    const panner = try PolarPointSourcePanner(f64).init(&outputs);
    const blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(
            1,
            "9007199254740992S1",
            "1S1",
            0.25,
        ),
        try testTimedObjectBlock(
            2,
            "9007199254740993S1",
            "4S1",
            1.0,
        ),
    };
    const timeline = try ObjectGainTimeline(f64, 2).init(
        &blocks,
        &outputs,
        &panner,
        null,
        .{},
        1,
    );
    const input = [_]f64{1.0};
    var direct_storage: [outputs.len][1]f64 = @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][1]f64 = @splat(@splat(0.0));
    var direct: [outputs.len][]f64 = undefined;
    var diffuse: [outputs.len][]f64 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try timeline.mix(
        9_007_199_254_740_994,
        &input,
        &direct,
        &diffuse,
    );
    try std.testing.expectEqual(
        @as(f64, 0.4375),
        direct_storage[2][0],
    );
}

test "ADM Objects gain timeline composes extent diffuse and exclusion targets" {
    const outputs = testPolarFiveLayout();
    const point_panner = try PolarPointSourcePanner(f64).init(&outputs);
    var gain_storage: [
        polar_extent_spreading_direction_count *
            outputs.len
    ]f64 = undefined;
    const extent_panner = try PolarExtentPanner(f64).init(
        &point_panner,
        &gain_storage,
    );
    var blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.00000", "1.00000", 0.8),
        try testTimedObjectBlock(2, "1.00000", "1.00000", 0.6),
    };
    blocks[0].width = 20.0;
    blocks[0].height = 10.0;
    blocks[0].diffuse = 0.25;
    blocks[1].width = 100.0;
    blocks[1].height = 50.0;
    blocks[1].depth = 0.4;
    blocks[1].diffuse = 0.75;
    blocks[1].exclusion_zones[0] = .{
        .polar = .{
            .min_azimuth = -1.0,
            .max_azimuth = 1.0,
            .min_elevation = -1.0,
            .max_elevation = 1.0,
        },
    };
    blocks[1].exclusion_zone_count = 1;

    const source = try ObjectPointGainPlan(f64).initPolarExtent(
        &blocks[0],
        &outputs,
        &extent_panner,
        .{},
    );
    const target = try ObjectPointGainPlan(f64).initPolarExtent(
        &blocks[1],
        &outputs,
        &extent_panner,
        .{},
    );
    const timeline = try ObjectGainTimeline(f64, 2).initPolarExtent(
        &blocks,
        &outputs,
        &extent_panner,
        .{},
        4,
    );

    const input = [_]f64{ 1.0, 1.0 };
    var direct_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][input.len]f64 =
        @splat(@splat(0.0));
    var direct: [outputs.len][]f64 = undefined;
    var diffuse: [outputs.len][]f64 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try timeline.mix(4, &input, &direct, &diffuse);
    for (0..outputs.len) |output_index| {
        try std.testing.expectApproxEqAbs(
            source.directGainSlice()[output_index],
            direct_storage[output_index][0],
            1.0e-12,
        );
        try std.testing.expectApproxEqAbs(
            source.directGainSlice()[output_index] * 0.75 +
                target.directGainSlice()[output_index] * 0.25,
            direct_storage[output_index][1],
            1.0e-12,
        );
        try std.testing.expectApproxEqAbs(
            source.diffuseGainSlice()[output_index],
            diffuse_storage[output_index][0],
            1.0e-12,
        );
        try std.testing.expectApproxEqAbs(
            source.diffuseGainSlice()[output_index] * 0.75 +
                target.diffuseGainSlice()[output_index] * 0.25,
            diffuse_storage[output_index][1],
            1.0e-12,
        );
    }
}

test "ADM Objects gain timeline accepts Cartesian extent sequences" {
    const outputs = testCartesianCubeLayout();
    const point_panner = try CartesianPointSourcePanner(f32).init(&outputs);
    const extent_panner =
        try CartesianExtentPanner(f32).init(&point_panner);
    var blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.00000", "1.00000", 1.0),
        try testTimedObjectBlock(2, "1.00000", "1.00000", 0.5),
    };
    for (&blocks) |*block| {
        block.cartesian = true;
        block.positions[0].coordinate = .x;
        block.positions[1].coordinate = .y;
        block.positions[2].coordinate = .z;
        block.width = 0.2;
        block.height = 0.3;
        block.depth = 0.4;
    }
    blocks[1].positions[0].value = 0.5;
    blocks[1].positions[1].value = -0.25;
    blocks[1].jump_position.enabled = true;
    blocks[1].exclusion_zones[0] = .{
        .cartesian = .{
            .min_x = -1.0,
            .min_y = -1.0,
            .min_z = -1.0,
            .max_x = -0.9,
            .max_y = 1.0,
            .max_z = 1.0,
        },
    };
    blocks[1].exclusion_zone_count = 1;
    const target = try ObjectPointGainPlan(f32).initCartesianExtent(
        &blocks[1],
        &outputs,
        &extent_panner,
        .{},
    );
    const timeline =
        try ObjectGainTimeline(f32, 2).initCartesianExtent(
            &blocks,
            &outputs,
            &extent_panner,
            .{},
            48_000,
        );

    const input = [_]f32{1.0};
    var direct_storage: [outputs.len][1]f32 = @splat(@splat(0.0));
    var diffuse_storage: [outputs.len][1]f32 = @splat(@splat(0.0));
    var direct: [outputs.len][]f32 = undefined;
    var diffuse: [outputs.len][]f32 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    try timeline.mix(48_000, &input, &direct, &diffuse);
    for (direct_storage, target.directGainSlice()) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual[0],
            0.000_001,
        );
    }
}

test "ADM Objects gain timeline rejects malformed sequences transactionally" {
    const outputs = testPolarFiveLayout();
    const panner = try PolarPointSourcePanner(f32).init(&outputs);
    var blocks = [_]adm_xml.BlockFormat{
        try testTimedObjectBlock(1, "0.00000", "1.00000", 0.5),
        try testTimedObjectBlock(2, "0.50000", "1.00000", 1.0),
    };
    try std.testing.expectError(
        error.AdmRendererObjectBlockCapacityExceeded,
        ObjectGainTimeline(f32, 1).init(
            &blocks,
            &outputs,
            &panner,
            null,
            .{},
            48_000,
        ),
    );
    try std.testing.expectError(
        error.OverlappingAdmRendererObjectBlocks,
        ObjectGainTimeline(f32, 2).init(
            &blocks,
            &outputs,
            &panner,
            null,
            .{},
            48_000,
        ),
    );

    blocks[1].rtime = try adm_time.Value.parse("1.00000");
    blocks[1].jump_position = .{
        .enabled = true,
        .interpolation_length = try adm_time.Value.parse("2.00000"),
    };
    try std.testing.expectError(
        error.InvalidAdmRendererInterpolationLength,
        ObjectGainTimeline(f32, 2).init(
            &blocks,
            &outputs,
            &panner,
            null,
            .{},
            48_000,
        ),
    );
    blocks[1].jump_position = .{};
    blocks[1].rtime_explicit = false;
    try std.testing.expectError(
        error.MissingAdmRendererObjectBlockTime,
        ObjectGainTimeline(f32, 2).init(
            &blocks,
            &outputs,
            &panner,
            null,
            .{},
            48_000,
        ),
    );

    blocks[1].rtime_explicit = true;
    var timeline = try ObjectGainTimeline(f32, 2).init(
        &blocks,
        &outputs,
        &panner,
        null,
        .{},
        48_000,
    );
    const input = [_]f32{1.0};
    var direct_storage: [outputs.len][1]f32 = @splat(@splat(7.0));
    var diffuse_storage: [outputs.len][1]f32 = @splat(@splat(7.0));
    var direct: [outputs.len][]f32 = undefined;
    var diffuse: [outputs.len][]f32 = undefined;
    for (
        &direct_storage,
        &direct,
        &diffuse_storage,
        &diffuse,
    ) |*direct_samples, *direct_output, *diffuse_samples, *diffuse_output| {
        direct_output.* = direct_samples;
        diffuse_output.* = diffuse_samples;
    }
    timeline.segment_count = 1;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectEqual(@as(usize, 0), timeline.blockCount());
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        timeline.mix(0, &input, &direct, &diffuse),
    );
    try std.testing.expectEqual(
        @as([outputs.len][1]f32, @splat(@splat(7.0))),
        direct_storage,
    );

    timeline.segment_count = 3;
    try std.testing.expect(!timeline.valid());
    try std.testing.expectEqual(@as(usize, 0), timeline.blockCount());
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        timeline.mix(0, &input, &direct, &diffuse),
    );
    try std.testing.expectEqual(
        @as([outputs.len][1]f32, @splat(@splat(7.0))),
        direct_storage,
    );

    timeline = try ObjectGainTimeline(f32, 2).init(
        &blocks,
        &outputs,
        &panner,
        null,
        .{},
        48_000,
    );
    try std.testing.expectError(
        error.AdmRendererSampleRangeOverflow,
        timeline.mix(
            std.math.maxInt(u64),
            &input,
            &direct,
            &diffuse,
        ),
    );
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        timeline.mix(0, &input, &direct, &direct),
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
    for (mixer.input_indices[mixer.term_count..]) |input_index|
        try std.testing.expectEqual(@as(u8, 0), input_index);
    for (mixer.gains[mixer.term_count..]) |gain|
        try std.testing.expectEqual(@as(f64, 0.0), gain);
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

test "ADM Matrix mixers bind public counts to the resolved plan" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gain="0.5">AC_00010002</coefficient>
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
    };
    const first = [_]f64{1.0};
    const second = [_]f64{2.0};
    const unused = [_]f64{3.0};
    const inputs = [_][]const f64{ &first, &second };
    const expanded_inputs = [_][]const f64{ &first, &second, &unused };

    var static_mixer = try StaticMatrixMixer(f64).init(&block, &channels);
    static_mixer.input_count = expanded_inputs.len;
    var output = [_]f64{7.0};
    try std.testing.expect(!static_mixer.valid());
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        static_mixer.process(&expanded_inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
    static_mixer.input_count = static_mixer.declared_input_count;
    static_mixer.term_count += 1;
    try std.testing.expect(!static_mixer.valid());
    try std.testing.expectEqual(@as(f64, 0.0), static_mixer.processSample(&.{ 1.0, 2.0 }));

    var delayed_mixer = try MatrixCoefficientMixer(f64, 1).init(
        &block,
        &channels,
        1000.0,
    );
    delayed_mixer.cursor = 1;
    delayed_mixer.history[0][0] = 0.25;
    delayed_mixer.input_count = expanded_inputs.len;
    delayed_mixer.reset();
    try std.testing.expectEqual(@as(usize, 1), delayed_mixer.cursor);
    try std.testing.expectEqual(@as(f64, 0.25), delayed_mixer.history[0][0]);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        delayed_mixer.process(&expanded_inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);

    const VariableMixer =
        VariableMatrixCoefficientMixer(f64, 1, 0, 0, 0);
    var variable_mixer = try VariableMixer.init(
        &block,
        &channels,
        1000.0,
        &.{},
        &.{},
    );
    variable_mixer.cursor = 1;
    variable_mixer.next_sample = 4;
    variable_mixer.history[0][0] = 0.5;
    variable_mixer.term_count += 1;
    variable_mixer.resetAt(0);
    try std.testing.expectEqual(@as(usize, 1), variable_mixer.cursor);
    try std.testing.expectEqual(@as(u64, 4), variable_mixer.next_sample);
    try std.testing.expectEqual(@as(f64, 0.5), variable_mixer.history[0][0]);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        variable_mixer.process(4, &inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
}

test "ADM Matrix coefficient mixer applies rounded delays across partitions" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient>AC_00010001</coefficient>
        \\        <coefficient gain="0.5" delay="1.5">AC_00010002</coefficient>
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
    };
    const Mixer = MatrixCoefficientMixer(f32, 2);
    var complete = try Mixer.init(&block, &channels, 1000.0);
    try std.testing.expectEqual(@as(usize, 0), complete.delays[0]);
    try std.testing.expectEqual(@as(usize, 1), complete.delays[1]);
    for (complete.input_indices[complete.term_count..]) |input_index|
        try std.testing.expectEqual(@as(u8, 0), input_index);
    for (complete.gains[complete.term_count..]) |gain|
        try std.testing.expectEqual(@as(f32, 0.0), gain);
    for (complete.delays[complete.term_count..]) |delay|
        try std.testing.expectEqual(@as(usize, 0), delay);
    const first = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    const second = [_]f32{ 10.0, 20.0, std.math.nan(f32), 40.0 };
    const inputs = [_][]const f32{ &first, &second };
    var complete_output: [first.len]f32 = undefined;
    try complete.process(&inputs, &complete_output);
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 7.0, 13.0, 4.0 },
        complete_output,
    );
    try std.testing.expectEqual(
        @as(f32, 20.0),
        complete.processSample(&.{ 0.0, 0.0 }),
    );

    var partitioned = try Mixer.init(&block, &channels, 1000.0);
    var partitioned_output: [first.len]f32 = undefined;
    const first_inputs = [_][]const f32{
        first[0..2],
        second[0..2],
    };
    try partitioned.process(
        &first_inputs,
        partitioned_output[0..2],
    );
    const second_inputs = [_][]const f32{
        first[2..],
        second[2..],
    };
    try partitioned.process(
        &second_inputs,
        partitioned_output[2..],
    );
    try std.testing.expectEqualDeep(
        complete_output,
        partitioned_output,
    );
    partitioned.reset();
    var reset_output: [first.len]f32 = undefined;
    try partitioned.process(&inputs, &reset_output);
    try std.testing.expectEqualDeep(
        complete_output,
        reset_output,
    );
}

test "ADM Matrix coefficient mixer validates policy and state transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient delay="2.5">AC_00010001</coefficient>
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
    var mixer = try MatrixCoefficientMixer(f64, 2).init(
        &block,
        &channels,
        1000.0,
    );
    try std.testing.expectEqual(@as(usize, 2), mixer.delays[0]);
    try std.testing.expectError(
        error.AdmRendererMatrixDelayCapacityExceeded,
        MatrixCoefficientMixer(f64, 1).init(
            &block,
            &channels,
            1000.0,
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmRendererSampleRate,
        MatrixCoefficientMixer(f64, 2).init(
            &block,
            &channels,
            0.0,
        ),
    );

    var invalid_block = block;
    invalid_block.matrix_coefficients[0].delay_milliseconds = -0.1;
    try std.testing.expectError(
        error.InvalidAdmRendererMatrixDelay,
        MatrixCoefficientMixer(f64, 2).init(
            &invalid_block,
            &channels,
            1000.0,
        ),
    );
    invalid_block = block;
    invalid_block.matrix_coefficients[0].phase_degrees = 90.0;
    try std.testing.expectError(
        error.UnsupportedAdmMatrixCoefficientPhase,
        MatrixCoefficientMixer(f64, 2).init(
            &invalid_block,
            &channels,
            1000.0,
        ),
    );
    invalid_block = block;
    invalid_block.matrix_coefficients[0].delay_variable =
        .{ .len = 1, .bytes = undefined };
    invalid_block.matrix_coefficients[0]
        .delay_variable.?.bytes[0] = 'd';
    try std.testing.expectError(
        error.UnsupportedVariableAdmMatrixCoefficient,
        MatrixCoefficientMixer(f64, 2).init(
            &invalid_block,
            &channels,
            1000.0,
        ),
    );

    var aliased = [_]f64{ 1.0, 2.0, 3.0 };
    const aliased_inputs = [_][]const f64{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        mixer.process(&aliased_inputs, &aliased),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 2.0, 3.0 },
        aliased,
    );
    try std.testing.expectEqual(@as(usize, 0), mixer.cursor);

    mixer.cursor = 3;
    var output = [_]f64{7.0};
    const input = [_]f64{1.0};
    const inputs = [_][]const f64{&input};
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        mixer.process(&inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
    mixer.reset();
    try std.testing.expect(mixer.valid());
}

test "ADM variable Matrix mixer interpolates gain and delay across partitions" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="gain" delayVar="delay">AC_00010001</coefficient>
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
    const gain_points = [_]MatrixVariablePoint{
        .{ .sample = 0, .value = 0.0 },
        .{ .sample = 4, .value = 1.0 },
    };
    const delay_points = [_]MatrixVariablePoint{
        .{ .sample = 0, .value = 0.0 },
        .{ .sample = 4, .value = 2.0 },
    };
    const timelines = [_]MatrixVariableTimeline{
        .{
            .name = "gain",
            .kind = .gain_linear,
            .points = &gain_points,
        },
        .{
            .name = "delay",
            .kind = .delay_milliseconds,
            .points = &delay_points,
        },
    };
    const Mixer =
        VariableMatrixCoefficientMixer(f64, 2, 2, 4, 0);
    var complete = try Mixer.init(
        &block,
        &channels,
        1000.0,
        &timelines,
        &.{},
    );
    for (complete.input_indices[complete.term_count..]) |input_index|
        try std.testing.expectEqual(@as(u8, 0), input_index);
    for (complete.fixed_gains[complete.term_count..]) |gain|
        try std.testing.expectEqual(@as(f64, 0.0), gain);
    for (complete.fixed_phases[complete.term_count..]) |phase|
        try std.testing.expectEqual(@as(f64, 0.0), phase);
    for (complete.fixed_delays[complete.term_count..]) |delay|
        try std.testing.expectEqual(@as(f64, 0.0), delay);
    for (complete.lanes[complete.lane_count..]) |lane| {
        try std.testing.expectEqual(MatrixVariableKind.gain_linear, lane.kind);
        try std.testing.expectEqual(
            MatrixVariableInterpolation.linear,
            lane.interpolation,
        );
        try std.testing.expectEqual(@as(u32, 0), lane.first_point);
        try std.testing.expectEqual(@as(u32, 0), lane.point_count);
    }
    const input = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 };
    const inputs = [_][]const f64{&input};
    var complete_output: [input.len]f64 = undefined;
    try complete.process(0, &inputs, &complete_output);
    try std.testing.expectEqualDeep(
        [_]f64{ 0.0, 0.375, 1.0, 1.875, 3.0, 4.0 },
        complete_output,
    );

    var partitioned = try Mixer.init(
        &block,
        &channels,
        1000.0,
        &timelines,
        &.{},
    );
    var partitioned_output: [input.len]f64 = undefined;
    const first_inputs = [_][]const f64{input[0..2]};
    try partitioned.process(
        0,
        &first_inputs,
        partitioned_output[0..2],
    );
    const second_inputs = [_][]const f64{input[2..5]};
    try partitioned.process(
        2,
        &second_inputs,
        partitioned_output[2..5],
    );
    const final_inputs = [_][]const f64{input[5..]};
    try partitioned.process(
        5,
        &final_inputs,
        partitioned_output[5..],
    );
    try std.testing.expectEqualDeep(
        complete_output,
        partitioned_output,
    );
    partitioned.reset();
    try partitioned.process(0, &inputs, &partitioned_output);
    try std.testing.expectEqualDeep(
        complete_output,
        partitioned_output,
    );
}

test "ADM variable Matrix mixer rotates phase with explicit FIR latency" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient phaseVar="phase">AC_00010001</coefficient>
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
    const phase_points = [_]MatrixVariablePoint{
        .{ .sample = 0, .value = 0.0 },
        .{ .sample = 4, .value = 180.0 },
    };
    const timelines = [_]MatrixVariableTimeline{.{
        .name = "phase",
        .kind = .phase_degrees,
        .points = &phase_points,
    }};
    const quadrature_fir = [_]f32{ 0.5, 0.0, -0.5 };
    const Mixer =
        VariableMatrixCoefficientMixer(f32, 0, 1, 2, 3);
    var mixer = try Mixer.init(
        &block,
        &channels,
        48_000.0,
        &timelines,
        &quadrature_fir,
    );
    try std.testing.expectEqual(@as(usize, 1), mixer.latencySamples());
    for (mixer.points[mixer.point_count..]) |point| {
        try std.testing.expectEqual(@as(u64, 0), point.sample);
        try std.testing.expectEqual(@as(f64, 0.0), point.value);
    }
    for (mixer.phase_taps[mixer.phase_tap_count..]) |tap|
        try std.testing.expectEqual(@as(f32, 0.0), tap);
    const input = [_]f32{ 1.0, 0.0, -1.0, 0.0, 1.0, 0.0 };
    const inputs = [_][]const f32{&input};
    var output: [input.len]f32 = undefined;
    try mixer.process(0, &inputs, &output);
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(0.5)),
        output[1],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0),
        output[2],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, @sqrt(0.5)),
        output[3],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.0),
        output[4],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0),
        output[5],
        0.000_001,
    );

    var fixed_block = block;
    fixed_block.matrix_coefficients[0].phase_variable = null;
    fixed_block.matrix_coefficients[0].phase_degrees = 90.0;
    const FixedMixer =
        VariableMatrixCoefficientMixer(f32, 0, 0, 0, 3);
    var fixed = try FixedMixer.init(
        &fixed_block,
        &channels,
        48_000.0,
        &.{},
        &quadrature_fir,
    );
    try fixed.process(0, &inputs, &output);
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0),
        output[2],
        0.000_001,
    );
}

test "ADM variable Matrix mixer preserves control phase beyond f64 precision" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="gain">AC_00010001</coefficient>
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
    const large_sample = @as(u64, 1) << 54;
    const points = [_]MatrixVariablePoint{
        .{ .sample = 0, .value = 0.0 },
        .{ .sample = large_sample, .value = 0.0 },
        .{ .sample = large_sample + 4, .value = 1.0 },
    };
    const timelines = [_]MatrixVariableTimeline{.{
        .name = "gain",
        .kind = .gain_linear,
        .points = &points,
    }};
    const Mixer =
        VariableMatrixCoefficientMixer(f64, 0, 1, 3, 0);
    var mixer = try Mixer.init(
        &block,
        &channels,
        48_000.0,
        &timelines,
        &.{},
    );
    mixer.resetAt(large_sample + 2);
    const input = [_]f64{ 2.0, 2.0 };
    const inputs = [_][]const f64{&input};
    var output: [input.len]f64 = undefined;
    try mixer.process(large_sample + 2, &inputs, &output);
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 1.5 },
        output,
    );
}

test "ADM variable Matrix mixer validates policy and state transactionally" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00021001">
        \\    <audioBlockFormatMatrix audioBlockFormatID="AB_00021001_00000001">
        \\      <matrix>
        \\        <coefficient gainVar="gain" phase="90">AC_00010001</coefficient>
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
    const points = [_]MatrixVariablePoint{
        .{ .sample = 0, .value = 1.0 },
    };
    const timelines = [_]MatrixVariableTimeline{.{
        .name = "gain",
        .kind = .gain_linear,
        .points = &points,
    }};
    const Mixer =
        VariableMatrixCoefficientMixer(f64, 2, 1, 1, 3);
    const quadrature_fir = [_]f64{ 0.5, 0.0, -0.5 };
    var mixer = try Mixer.init(
        &block,
        &channels,
        1000.0,
        &timelines,
        &quadrature_fir,
    );
    try std.testing.expect(mixer.valid());

    const input = [_]f64{1.0};
    const inputs = [_][]const f64{&input};
    var output = [_]f64{7.0};
    try std.testing.expectError(
        error.DiscontinuousAdmRendererSampleRange,
        mixer.process(1, &inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
    var aliased = [_]f64{1.0};
    const aliased_inputs = [_][]const f64{&aliased};
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        mixer.process(0, &aliased_inputs, &aliased),
    );
    try std.testing.expectEqual(@as(u64, 0), mixer.next_sample);

    mixer.resetAt(std.math.maxInt(u64));
    try std.testing.expectError(
        error.AdmRendererSampleRangeOverflow,
        mixer.process(std.math.maxInt(u64), &inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        mixer.next_sample,
    );
    mixer.reset();

    const wrong_kind = [_]MatrixVariableTimeline{.{
        .name = "gain",
        .kind = .phase_degrees,
        .points = &points,
    }};
    try std.testing.expectError(
        error.AdmRendererMatrixVariableKindMismatch,
        Mixer.init(
            &block,
            &channels,
            1000.0,
            &wrong_kind,
            &quadrature_fir,
        ),
    );
    try std.testing.expectError(
        error.InvalidAdmRendererMatrixPhaseFilter,
        Mixer.init(
            &block,
            &channels,
            1000.0,
            &timelines,
            &.{ 0.5, 0.0, 0.5 },
        ),
    );

    mixer.history[0][0] = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        mixer.process(0, &inputs, &output),
    );
    try std.testing.expectEqual(@as(f64, 7.0), output[0]);
    mixer.reset();
    try std.testing.expect(mixer.valid());
    mixer.gain_lanes[0] = null;
    try std.testing.expect(!mixer.valid());
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
    var router = try DirectSpeakerRouter(f32).init(&block, &labels);
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
    router.output_count += 1;
    try std.testing.expect(!router.valid());
    try std.testing.expectEqual(@as(f32, 0.0), router.processSample(2.0));
    var unused = [_]f32{ 1.0, 1.0, 1.0 };
    const expanded_outputs = [_][]f32{ &left, &center, &right, &unused };
    try std.testing.expectError(
        error.InvalidAdmRendererState,
        router.mix(&input, &expanded_outputs),
    );
    try std.testing.expectEqualDeep([_]f32{ 1.0, 1.0, 1.0 }, unused);
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

test "ADM position router applies common layout speaker mappings" {
    const document = try adm_xml.Document.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00011001">
        \\    <audioBlockFormatDirectSpeakers audioBlockFormatID="AB_00011001_00000001">
        \\      <speakerLabel>urn:itu:bs:2051:2:speaker:M+000</speakerLabel>
        \\      <position coordinate="azimuth">0</position>
        \\      <position coordinate="elevation">0</position>
        \\      <gain>0.5</gain>
        \\    </audioBlockFormatDirectSpeakers>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var blocks = document.blocks();
    const block = (try blocks.next()).?;
    const outputs = [_]OutputSpeaker{
        .{
            .label = "urn:itu:bs:2051:3:speaker:M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = 1 },
        },
        .{
            .label = "M-030",
            .nominal_polar = .{
                .azimuth_degrees = -30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 1, .y = 1 },
        },
    };
    const context = DirectSpeakerRoutingContext{
        .common_pack_mapping = .{
            .input_pack = try adm.Identifier.parse("AP_00010005"),
            .output_layout_name = "0+2+0",
        },
    };
    const router = try DirectSpeakerPositionRouter(f32).init(
        &block,
        &outputs,
        context,
    );
    const mapping = switch (router.route) {
        .mapped => |value| value,
        else => return error.TestUnexpectedResult,
    };
    const root_half: f64 = @sqrt(0.5);
    try std.testing.expectApproxEqAbs(
        root_half,
        mapping.gains[0],
        1.0e-15,
    );
    try std.testing.expectApproxEqAbs(
        root_half,
        mapping.gains[1],
        1.0e-15,
    );
    try std.testing.expectError(
        error.AdmRendererMultipleOutputsRequired,
        router.processSample(1.0),
    );

    const input = [_]f32{ 2.0, std.math.nan(f32), -4.0 };
    var left = [_]f32{ 1.0, 1.0, 1.0 };
    var right = [_]f32{ -1.0, -1.0, -1.0 };
    const output_buffers = [_][]f32{ &left, &right };
    try router.mix(&input, &output_buffers);
    const scaled: f32 = @floatCast(root_half);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0) + scaled,
        left[0],
        0.000_001,
    );
    try std.testing.expectEqual(@as(f32, 1.0), left[1]);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0) - 2.0 * scaled,
        left[2],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0) + scaled,
        right[0],
        0.000_001,
    );
    try std.testing.expectEqual(@as(f32, -1.0), right[1]);
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0) - 2.0 * scaled,
        right[2],
        0.000_001,
    );
}

test "ADM common layout mapping preserves fallback and transactional errors" {
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
    const outputs = [_]OutputSpeaker{
        .{
            .label = "M+000",
            .nominal_polar = .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = 0, .y = 1 },
        },
        .{
            .label = "M+030",
            .nominal_polar = .{
                .azimuth_degrees = 30,
                .elevation_degrees = 0,
            },
            .allocentric = .{ .x = -1, .y = 1 },
        },
    };
    const common_pack = try adm.Identifier.parse("AP_00010005");
    const skipped = try resolveDirectSpeakerRoute(
        &block,
        &outputs,
        .{ .common_pack_mapping = .{
            .input_pack = common_pack,
            .output_layout_name = "0+2+0",
        } },
    );
    try std.testing.expectEqual(@as(u8, 0), skipped.output);

    try std.testing.expectError(
        error.InvalidAdmRendererOutputLayoutName,
        resolveDirectSpeakerRoute(
            &block,
            &outputs,
            .{ .common_pack_mapping = .{
                .input_pack = common_pack,
                .output_layout_name = "",
            } },
        ),
    );

    var single_label_block = block;
    single_label_block.speaker_label_count = 1;
    const router = try DirectSpeakerPositionRouter(f64).init(
        &single_label_block,
        &outputs,
        .{ .common_pack_mapping = .{
            .input_pack = common_pack,
            .output_layout_name = "0+2+0",
        } },
    );
    var aliased = [_]f64{ 1.0, 2.0 };
    var untouched = [_]f64{ 3.0, 4.0 };
    const aliased_outputs = [_][]f64{ &aliased, &untouched };
    try std.testing.expectError(
        error.AdmRendererAliasedBuffers,
        router.mix(&aliased, &aliased_outputs),
    );
    try std.testing.expectEqualDeep([_]f64{ 1.0, 2.0 }, aliased);
    try std.testing.expectEqualDeep([_]f64{ 3.0, 4.0 }, untouched);

    const local_pack = try adm.Identifier.parse("AP_00011001");
    const ordinary = try resolveDirectSpeakerRoute(
        &single_label_block,
        &outputs,
        .{ .common_pack_mapping = .{
            .input_pack = local_pack,
            .output_layout_name = "0+2+0",
        } },
    );
    try std.testing.expectEqual(@as(u8, 0), ordinary.output);
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

fn testTimedObjectBlock(
    sequence: u32,
    start: []const u8,
    duration: []const u8,
    gain: f64,
) !adm_xml.BlockFormat {
    var identifier_text: [32]u8 = undefined;
    const identifier = try std.fmt.bufPrint(
        &identifier_text,
        "AB_00031001_{d:0>8}",
        .{sequence},
    );
    var block = adm_xml.BlockFormat{
        .identifier = try adm.Identifier.parse(identifier),
        .channel_identifier = try adm.Identifier.parse("AC_00031001"),
        .channel_name = null,
        .rtime = try adm_time.Value.parse(start),
        .rtime_explicit = true,
        .duration = try adm_time.Value.parse(duration),
        .gain = .{ .value = gain },
    };
    block.positions[0] = .{
        .coordinate = .azimuth,
        .bound = .exact,
        .value = 0.0,
    };
    block.positions[1] = .{
        .coordinate = .elevation,
        .bound = .exact,
        .value = 0.0,
    };
    block.positions[2] = .{
        .coordinate = .distance,
        .bound = .exact,
        .value = 1.0,
    };
    block.position_count = 3;
    return block;
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

fn testFourPlusFiveLayout() [9]OutputSpeaker {
    const middle = testPolarFiveLayout();
    return .{
        middle[0],
        middle[1],
        middle[2],
        middle[3],
        middle[4],
        .{
            .label = "U+030",
            .nominal_polar = .{
                .azimuth_degrees = 30.0,
                .elevation_degrees = 30.0,
            },
            .allocentric = .{ .x = -1.0, .y = 1.0, .z = 1.0 },
        },
        .{
            .label = "U-030",
            .nominal_polar = .{
                .azimuth_degrees = -30.0,
                .elevation_degrees = 30.0,
            },
            .allocentric = .{ .x = 1.0, .y = 1.0, .z = 1.0 },
        },
        .{
            .label = "U+110",
            .nominal_polar = .{
                .azimuth_degrees = 110.0,
                .elevation_degrees = 30.0,
            },
            .allocentric = .{ .x = -1.0, .y = -1.0, .z = 1.0 },
        },
        .{
            .label = "U-110",
            .nominal_polar = .{
                .azimuth_degrees = -110.0,
                .elevation_degrees = 30.0,
            },
            .allocentric = .{ .x = 1.0, .y = -1.0, .z = 1.0 },
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
