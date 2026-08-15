const std = @import("std");
const core = @import("adm_render/core.zig");

pub const maximum_input_channels = core.maximum_input_channels;
pub const maximum_output_channels = core.maximum_output_channels;
pub const polar_extent_spreading_direction_count =
    core.polar_extent_spreading_direction_count;

pub const PolarPosition = core.PolarPosition;
pub const CartesianPosition = core.CartesianPosition;
pub const OutputSpeaker = core.OutputSpeaker;
pub const ScreenEdges = core.ScreenEdges;
pub const DirectSpeakerRoutingContext = core.DirectSpeakerRoutingContext;
pub const DirectSpeakerCommonPackMapping =
    core.DirectSpeakerCommonPackMapping;
pub const MatrixVariableKind = core.MatrixVariableKind;
pub const MatrixVariableInterpolation = core.MatrixVariableInterpolation;
pub const MatrixVariablePoint = core.MatrixVariablePoint;
pub const MatrixVariableTimeline = core.MatrixVariableTimeline;
pub const ObjectRenderingContext = core.ObjectRenderingContext;
pub const DirectSpeakerRoute = core.DirectSpeakerRoute;

pub const PolarPointSourcePanner = core.PolarPointSourcePanner;
pub const PolarExtentPanner = core.PolarExtentPanner;
pub const CartesianPointSourcePanner = core.CartesianPointSourcePanner;
pub const CartesianExtentPanner = core.CartesianExtentPanner;
pub const ObjectPointGainPlan = core.ObjectPointGainPlan;
pub const ObjectPolarExtentGainPlan = core.ObjectPolarExtentGainPlan;
pub const ObjectCartesianExtentGainPlan = core.ObjectCartesianExtentGainPlan;
pub const ObjectGainTimeline = core.ObjectGainTimeline;
pub const StaticMatrixMixer = core.StaticMatrixMixer;
pub const MatrixCoefficientMixer = core.MatrixCoefficientMixer;
pub const VariableMatrixCoefficientMixer =
    core.VariableMatrixCoefficientMixer;
pub const DirectSpeakerRouter = core.DirectSpeakerRouter;
pub const DirectSpeakerPositionRouter = core.DirectSpeakerPositionRouter;
pub const resolveDirectSpeakerRoute = core.resolveDirectSpeakerRoute;
pub const canonicalSpeakerLabel = core.canonicalSpeakerLabel;

test "ADM renderer facade preserves exact public identities" {
    try std.testing.expect(PolarPosition == core.PolarPosition);
    try std.testing.expect(OutputSpeaker == core.OutputSpeaker);
    try std.testing.expect(
        PolarPointSourcePanner(f32) == core.PolarPointSourcePanner(f32),
    );
    try std.testing.expect(
        ObjectPointGainPlan(f64) == core.ObjectPointGainPlan(f64),
    );
    try std.testing.expect(
        MatrixCoefficientMixer(f32, 8) ==
            core.MatrixCoefficientMixer(f32, 8),
    );
    try std.testing.expect(
        DirectSpeakerRouter(f64) == core.DirectSpeakerRouter(f64),
    );
}
