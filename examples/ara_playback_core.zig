const std = @import("std");

pub const BlockClock = struct {
    pub fn seconds(
        project_time_samples: i64,
        sample_rate: f64,
    ) !f64 {
        if (!std.math.isFinite(sample_rate) or sample_rate <= 0)
            return error.InvalidSampleRate;
        return @as(f64, @floatFromInt(project_time_samples)) /
            sample_rate;
    }
};

test "ARA playback block clock preserves signed host positions" {
    try std.testing.expectEqual(
        @as(f64, 1.0),
        try BlockClock.seconds(48_000, 48_000),
    );
    try std.testing.expectEqual(
        @as(f64, -0.5),
        try BlockClock.seconds(-24_000, 48_000),
    );
    try std.testing.expectError(
        error.InvalidSampleRate,
        BlockClock.seconds(0, std.math.nan(f64)),
    );
}
