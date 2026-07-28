const std = @import("std");
const modulated_delay = @import("modulated_delay.zig");

/// Coordinates two matching modulation processors with a fixed phase offset.
pub fn StereoProcessor(
    comptime Sample: type,
    comptime Processor: type,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("stereo modulation supports f32 and f64 samples");

    return struct {
        const Self = @This();

        left: Processor,
        right: Processor,
        phase_offset: f64,

        pub fn init(
            left: Processor,
            right: Processor,
            phase_offset: f64,
        ) !Self {
            if (!validPhaseOffset(phase_offset))
                return error.InvalidStereoModulationPhaseOffset;

            var result = Self{
                .left = left,
                .right = right,
                .phase_offset = phase_offset,
            };
            try result.reset(0.0);
            return result;
        }

        pub fn reset(self: *Self, phase: f64) !void {
            if (!std.math.isFinite(phase))
                return error.InvalidStereoModulationPhase;
            const right_phase = phase + self.phase_offset;
            if (!std.math.isFinite(right_phase))
                return error.InvalidStereoModulationPhase;

            self.left.reset(phase) catch
                return error.InvalidStereoModulationPhase;
            self.right.reset(right_phase) catch
                return error.InvalidStereoModulationPhase;
        }

        /// Validates all channel lengths before advancing either processor.
        pub fn process(
            self: *Self,
            left_input: []const Sample,
            right_input: []const Sample,
            left_output: []Sample,
            right_output: []Sample,
        ) !void {
            const sample_count = left_input.len;
            if (right_input.len != sample_count or
                left_output.len != sample_count or
                right_output.len != sample_count)
                return error.StereoModulationBufferLengthMismatch;

            self.left.process(left_input, left_output) catch
                return error.StereoModulationProcessingFailed;
            self.right.process(right_input, right_output) catch
                return error.StereoModulationProcessingFailed;
        }

        pub fn valid(self: *const Self) bool {
            return validPhaseOffset(self.phase_offset) and
                self.left.valid() and
                self.right.valid();
        }

        fn validPhaseOffset(phase_offset: f64) bool {
            return std.math.isFinite(phase_offset) and
                phase_offset >= 0.0 and
                phase_offset < 1.0;
        }
    };
}

test "stereo modulation preserves its channel phase relationship" {
    const Effect = modulated_delay.Processor(f32, 512);
    const Stereo = StereoProcessor(f32, Effect);
    const config = modulated_delay.Config{
        .sample_rate = 48_000.0,
        .rate_hz = 1.0,
        .center_delay_ms = 3.0,
        .depth_ms = 1.0,
        .feedback = 0.0,
        .mix = 1.0,
        .mixing_rule = .linear,
    };
    var stereo = try Stereo.init(
        try Effect.init(config),
        try Effect.init(config),
        0.25,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        stereo.right.phase - stereo.left.phase,
        0.000_000_1,
    );

    var input: [256]f32 = @splat(0.0);
    input[0] = 1.0;
    var left_output: [256]f32 = undefined;
    var right_output: [256]f32 = undefined;
    try stereo.process(
        &input,
        &input,
        &left_output,
        &right_output,
    );
    try std.testing.expect(!std.mem.eql(
        f32,
        &left_output,
        &right_output,
    ));
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.25),
        stereo.right.phase - stereo.left.phase,
        0.000_000_1,
    );
}

test "stereo modulation is independent of block partitioning" {
    const Effect = modulated_delay.Processor(f64, 512);
    const Stereo = StereoProcessor(f64, Effect);
    const config = modulated_delay.Config{
        .sample_rate = 48_000.0,
        .rate_hz = 0.75,
        .center_delay_ms = 3.0,
        .depth_ms = 1.0,
        .feedback = 0.25,
        .mix = 0.5,
        .mixing_rule = .linear,
    };
    var left_input: [96]f64 = undefined;
    var right_input: [96]f64 = undefined;
    for (&left_input, &right_input, 0..) |*left, *right, index| {
        const time = @as(f64, @floatFromInt(index)) / 48_000.0;
        left.* = @sin(std.math.tau * 220.0 * time);
        right.* = @sin(std.math.tau * 330.0 * time);
    }

    var whole = try Stereo.init(
        try Effect.init(config),
        try Effect.init(config),
        0.5,
    );
    var whole_left: [96]f64 = undefined;
    var whole_right: [96]f64 = undefined;
    try whole.process(
        &left_input,
        &right_input,
        &whole_left,
        &whole_right,
    );

    var partitioned = try Stereo.init(
        try Effect.init(config),
        try Effect.init(config),
        0.5,
    );
    var partitioned_left: [96]f64 = undefined;
    var partitioned_right: [96]f64 = undefined;
    try partitioned.process(
        left_input[0..31],
        right_input[0..31],
        partitioned_left[0..31],
        partitioned_right[0..31],
    );
    try partitioned.process(
        left_input[31..],
        right_input[31..],
        partitioned_left[31..],
        partitioned_right[31..],
    );
    try std.testing.expectEqualSlices(
        f64,
        &whole_left,
        &partitioned_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &whole_right,
        &partitioned_right,
    );
}

test "stereo modulation rejects invalid input transactionally" {
    const Effect = modulated_delay.Processor(f32, 256);
    const Stereo = StereoProcessor(f32, Effect);
    const config = modulated_delay.Config{
        .sample_rate = 48_000.0,
        .rate_hz = 1.0,
        .center_delay_ms = 3.0,
        .depth_ms = 1.0,
        .feedback = 0.0,
        .mix = 0.5,
        .mixing_rule = .linear,
    };
    try std.testing.expectError(
        error.InvalidStereoModulationPhaseOffset,
        Stereo.init(
            try Effect.init(config),
            try Effect.init(config),
            1.0,
        ),
    );

    var stereo = try Stereo.init(
        try Effect.init(config),
        try Effect.init(config),
        0.25,
    );
    const left_phase = stereo.left.phase;
    const right_phase = stereo.right.phase;
    var output: [2]f32 = undefined;
    try std.testing.expectError(
        error.StereoModulationBufferLengthMismatch,
        stereo.process(&.{0.0}, &.{ 0.0, 0.0 }, &output, &output),
    );
    try std.testing.expectEqual(left_phase, stereo.left.phase);
    try std.testing.expectEqual(right_phase, stereo.right.phase);
}
