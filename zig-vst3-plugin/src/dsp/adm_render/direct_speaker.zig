const std = @import("std");
const adm = @import("../adm.zig");
const adm_direct_speaker_mapping =
    @import("../adm_direct_speaker_mapping.zig");
const adm_xml = @import("../adm_xml.zig");
const common = @import("common.zig");
const panning = @import("panner.zig");

const maximum_output_channels = common.maximum_output_channels;
const PolarPosition = common.PolarPosition;
const CartesianPosition = common.CartesianPosition;
const OutputSpeaker = common.OutputSpeaker;
const ScreenEdges = common.ScreenEdges;
const PolarPointSourcePanner = panning.PolarPointSourcePanner;
const CartesianPointSourcePanner = panning.CartesianPointSourcePanner;
const mixGainVector = common.mixGainVector;
const normalizeSpeakerLabel = common.normalizeSpeakerLabel;
const renderGain = common.renderGain;
const slicesOverlap = common.slicesOverlap;
const validCartesian = common.validCartesian;
const validateOutputLayout = common.validateOutputLayout;
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

pub const DirectSpeakerRoutingContext = struct {
    screen_edges: ?ScreenEdges = null,
    /// Overrides the internal Cartesian screen-lock transform when supplied.
    cartesian_screen_locked_nominal: ?CartesianPosition = null,
    common_pack_mapping: ?DirectSpeakerCommonPackMapping = null,
};

pub const DirectSpeakerCommonPackMapping = struct {
    input_pack: adm.Identifier,
    output_layout_name: []const u8,
};

pub const DirectSpeakerRoute = union(enum) {
    mapped: adm_direct_speaker_mapping.GainVector,
    output: u8,
    discard,
    polar_panner: PolarPosition,
    cartesian_panner: CartesianPosition,
};

pub fn DirectSpeakerRouter(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DirectSpeakerRouter supports f32 and f64 samples");

    return struct {
        const Self = @This();

        output_count: usize,
        declared_output_count: usize,
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
                .declared_output_count = output_labels.len,
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
                self.output_count == self.declared_output_count and
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
        declared_output_count: usize,
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
                .declared_output_count = outputs.len,
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
                .mapped => {
                    return error.AdmRendererMultipleOutputsRequired;
                },
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
                .mapped => |mapping| {
                    for (
                        outputs,
                        mapping.slice(),
                    ) |output, mapping_gain| {
                        if (mapping_gain != 0.0 and
                            slicesOverlap(Sample, input, output))
                        {
                            return error.AdmRendererAliasedBuffers;
                        }
                    }
                    var gains: [maximum_output_channels]Sample =
                        @splat(0.0);
                    for (
                        gains[0..self.output_count],
                        mapping.slice(),
                    ) |*gain, mapping_gain| {
                        const combined =
                            @as(f64, self.gain) * mapping_gain;
                        gain.* = if (std.math.isFinite(combined))
                            @floatCast(combined)
                        else
                            0.0;
                    }
                    mixGainVector(
                        Sample,
                        input,
                        outputs,
                        gains[0..self.output_count],
                    );
                    return;
                },
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
                .mapped, .output, .discard => try self.mix(input, outputs),
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
                .mapped, .output, .discard => try self.mix(input, outputs),
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
                .mapped, .output, .discard => try self.mix(input, outputs),
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_output_channels or
                self.output_count != self.declared_output_count or
                !std.math.isFinite(self.gain))
            {
                return false;
            }
            return switch (self.route) {
                .mapped => |mapping| mapping.output_count ==
                    self.output_count and mapping.valid(),
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
    if (context.common_pack_mapping) |mapping_context| {
        if (mapping_context.output_layout_name.len == 0 or
            mapping_context.output_layout_name.len > 64 or
            !std.unicode.utf8ValidateSlice(
                mapping_context.output_layout_name,
            ) or
            std.mem.indexOfScalar(
                u8,
                mapping_context.output_layout_name,
                0,
            ) != null)
        {
            return error.InvalidAdmRendererOutputLayoutName;
        }
        const speaker_labels = block.speakerLabelSlice();
        if (speaker_labels.len == 1) {
            const input_label = normalizeSpeakerLabel(
                speaker_labels[0].value(),
            );
            if (input_label) |label| {
                var output_labels: [maximum_output_channels][]const u8 = undefined;
                for (outputs, 0..) |output, output_index| {
                    output_labels[output_index] =
                        normalizeSpeakerLabel(output.label) orelse
                        return error.InvalidAdmRendererSpeakerLabel;
                }
                if (adm_direct_speaker_mapping.resolve(
                    mapping_context.input_pack,
                    mapping_context.output_layout_name,
                    label,
                    output_labels[0..outputs.len],
                )) |mapping| {
                    return .{ .mapped = mapping };
                }
            }
        }
    }
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
