const std = @import("std");
const process_context = @import("../process/context.zig");

pub const NoteDivision = enum {
    whole,
    dotted_half,
    half,
    dotted_quarter,
    quarter,
    quarter_triplet,
    dotted_eighth,
    eighth,
    eighth_triplet,
    dotted_sixteenth,
    sixteenth,
    sixteenth_triplet,
    thirty_second,

    pub fn beatsPerCycle(self: NoteDivision) f64 {
        return switch (self) {
            .whole => 4.0,
            .dotted_half => 3.0,
            .half => 2.0,
            .dotted_quarter => 1.5,
            .quarter => 1.0,
            .quarter_triplet => 2.0 / 3.0,
            .dotted_eighth => 0.75,
            .eighth => 0.5,
            .eighth_triplet => 1.0 / 3.0,
            .dotted_sixteenth => 0.375,
            .sixteenth => 0.25,
            .sixteenth_triplet => 1.0 / 6.0,
            .thirty_second => 0.125,
        };
    }
};

pub fn rateHz(bpm: f64, division: NoteDivision) !f64 {
    return rateHzForBeats(bpm, division.beatsPerCycle());
}

pub fn rateHzForBeats(bpm: f64, beats_per_cycle: f64) !f64 {
    if (!std.math.isFinite(bpm) or
        bpm <= 0.0 or
        bpm > 1_000.0 or
        !std.math.isFinite(beats_per_cycle) or
        beats_per_cycle <= 0.0 or
        beats_per_cycle > 1_024.0)
        return error.InvalidModulationTempo;

    const result = bpm / (60.0 * beats_per_cycle);
    if (!std.math.isFinite(result) or result > 20.0)
        return error.InvalidModulationTempo;
    return result;
}

pub fn tempoFromTransport(
    transport: ?process_context.Transport,
    fallback_bpm: f64,
) !f64 {
    if (!std.math.isFinite(fallback_bpm) or
        fallback_bpm <= 0.0 or
        fallback_bpm > 1_000.0)
        return error.InvalidModulationTempo;
    const value = transport orelse return fallback_bpm;
    if (!value.valid()) return error.InvalidModulationTransport;
    return value.tempoOr(fallback_bpm);
}

pub fn phaseFromTransport(
    transport: ?process_context.Transport,
    division: NoteDivision,
) ?f64 {
    const value = transport orelse return null;
    if (!value.valid()) return null;
    const position = value.project_quarter_notes orelse return null;
    const beats = division.beatsPerCycle();
    const cycles = position / beats;
    if (!std.math.isFinite(cycles)) return null;
    const phase = cycles - @floor(cycles);
    if (!std.math.isFinite(phase) or phase < 0.0 or phase >= 1.0)
        return null;
    return phase;
}

pub const RateSmoother = struct {
    sample_rate: f64,
    current_hz: f64,
    target_hz: f64,
    step_hz: f64 = 0.0,
    remaining_samples: usize = 0,

    pub fn init(sample_rate: f64, rate_hz: f64) !RateSmoother {
        try validateRate(sample_rate, rate_hz);
        return .{
            .sample_rate = sample_rate,
            .current_hz = rate_hz,
            .target_hz = rate_hz,
        };
    }

    pub fn setImmediate(
        self: *RateSmoother,
        sample_rate: f64,
        rate_hz: f64,
    ) !void {
        try validateRate(sample_rate, rate_hz);
        self.* = try init(sample_rate, rate_hz);
    }

    /// Preserve the current rate while replacing the target transactionally.
    pub fn setTarget(
        self: *RateSmoother,
        sample_rate: f64,
        rate_hz: f64,
        smoothing_seconds: f64,
    ) !void {
        try validateRate(sample_rate, rate_hz);
        if (!std.math.isFinite(smoothing_seconds) or
            smoothing_seconds < 0.0 or
            smoothing_seconds > 60.0)
            return error.InvalidModulationSmoothing;
        if (!self.valid())
            return error.InvalidModulationRateState;
        if (self.sample_rate == sample_rate and
            self.target_hz == rate_hz)
            return;

        const sample_count_float = @round(sample_rate * smoothing_seconds);
        if (!std.math.isFinite(sample_count_float) or
            sample_count_float >
                @as(f64, @floatFromInt(std.math.maxInt(usize))))
            return error.InvalidModulationSmoothing;
        const sample_count: usize = @intFromFloat(sample_count_float);
        if (sample_count == 0)
            return self.setImmediate(sample_rate, rate_hz);

        const step =
            (rate_hz - self.current_hz) /
            @as(f64, @floatFromInt(sample_count));
        if (!std.math.isFinite(step))
            return error.InvalidModulationSmoothing;

        self.sample_rate = sample_rate;
        self.target_hz = rate_hz;
        self.step_hz = step;
        self.remaining_samples = sample_count;
    }

    pub fn next(self: *RateSmoother) f64 {
        if (!self.valid()) return self.repair();
        const current = self.current_hz;
        if (self.remaining_samples > 0) {
            self.remaining_samples -= 1;
            if (self.remaining_samples == 0) {
                self.settle();
            } else {
                const next_rate = self.current_hz + self.step_hz;
                if (!rateValid(self.sample_rate, next_rate)) {
                    self.settle();
                } else {
                    self.current_hz = next_rate;
                }
            }
        }
        return current;
    }

    pub fn valid(self: *const RateSmoother) bool {
        validateRate(self.sample_rate, self.current_hz) catch return false;
        validateRate(self.sample_rate, self.target_hz) catch return false;
        return std.math.isFinite(self.step_hz) and
            self.remaining_samples <=
                @as(usize, @intFromFloat(self.sample_rate * 60.0));
    }

    fn settle(self: *RateSmoother) void {
        self.current_hz = self.target_hz;
        self.step_hz = 0.0;
        self.remaining_samples = 0;
    }

    fn repair(self: *RateSmoother) f64 {
        self.* = .{
            .sample_rate = 48_000.0,
            .current_hz = 0.0,
            .target_hz = 0.0,
        };
        return self.current_hz;
    }

    fn rateValid(sample_rate: f64, rate_hz: f64) bool {
        validateRate(sample_rate, rate_hz) catch return false;
        return true;
    }

    fn validateRate(sample_rate: f64, rate_hz: f64) !void {
        if (!std.math.isFinite(sample_rate) or
            sample_rate < 1_000.0 or
            sample_rate > 768_000.0 or
            !std.math.isFinite(rate_hz) or
            rate_hz < 0.0 or
            rate_hz > 20.0)
            return error.InvalidModulationRate;
    }
};

test "tempo divisions convert quarter-note BPM to LFO rates" {
    try std.testing.expectEqual(
        @as(f64, 2.0),
        try rateHz(120.0, .quarter),
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        try rateHz(120.0, .whole),
    );
    try std.testing.expectEqual(
        @as(f64, 6.0),
        try rateHz(120.0, .eighth_triplet),
    );
}

test "rate smoothing reaches its exact target across partitions" {
    var whole = try RateSmoother.init(1_000.0, 1.0);
    try whole.setTarget(1_000.0, 3.0, 0.004);
    var whole_values: [6]f64 = undefined;
    for (&whole_values) |*value| value.* = whole.next();

    var partitioned = try RateSmoother.init(1_000.0, 1.0);
    try partitioned.setTarget(1_000.0, 3.0, 0.004);
    var partitioned_values: [6]f64 = undefined;
    for (partitioned_values[0..2]) |*value| value.* = partitioned.next();
    for (partitioned_values[2..]) |*value| value.* = partitioned.next();
    try std.testing.expectEqualSlices(
        f64,
        &whole_values,
        &partitioned_values,
    );
    try std.testing.expectEqual(@as(f64, 3.0), whole_values[4]);
    try std.testing.expectEqual(@as(f64, 3.0), whole.current_hz);
}

test "tempo and smoothing failures preserve valid state" {
    try std.testing.expectError(
        error.InvalidModulationTempo,
        rateHz(0.0, .quarter),
    );
    try std.testing.expectError(
        error.InvalidModulationTempo,
        rateHzForBeats(120.0, 0.0),
    );

    var rate = try RateSmoother.init(48_000.0, 1.0);
    const before = rate;
    try std.testing.expectError(
        error.InvalidModulationSmoothing,
        rate.setTarget(48_000.0, 2.0, -1.0),
    );
    try std.testing.expectEqualDeep(before, rate);
}

test "rate smoothing contains hostile retained arithmetic" {
    var smoother = try RateSmoother.init(48_000.0, 20.0);
    smoother.target_hz = 10.0;
    smoother.step_hz = 20.0;
    smoother.remaining_samples = 2;
    try std.testing.expectEqual(@as(f64, 20.0), smoother.next());
    try std.testing.expectEqual(@as(f64, 10.0), smoother.current_hz);
    try std.testing.expectEqual(@as(usize, 0), smoother.remaining_samples);
    try std.testing.expect(smoother.valid());

    smoother.step_hz = std.math.nan(f64);
    try std.testing.expectEqual(@as(f64, 0.0), smoother.next());
    try std.testing.expect(smoother.valid());
}

test "host transport follows tempo and musical phase" {
    const transport = process_context.Transport{
        .project_time_samples = 48_000,
        .tempo_bpm = 135.0,
        .project_quarter_notes = 3.5,
    };
    try std.testing.expectEqual(
        @as(f64, 135.0),
        try tempoFromTransport(transport, 120.0),
    );
    try std.testing.expectEqual(
        @as(?f64, 0.75),
        phaseFromTransport(transport, .half),
    );
    try std.testing.expectEqual(
        @as(f64, 120.0),
        try tempoFromTransport(null, 120.0),
    );
}

test "host transport phase rejects finite positions that overflow scaling" {
    const positive = process_context.Transport{
        .project_time_samples = 0,
        .project_quarter_notes = std.math.floatMax(f64),
    };
    const negative = process_context.Transport{
        .project_time_samples = 0,
        .project_quarter_notes = -std.math.floatMax(f64),
    };
    try std.testing.expect(positive.valid());
    try std.testing.expect(negative.valid());
    try std.testing.expect(
        phaseFromTransport(positive, .thirty_second) == null,
    );
    try std.testing.expect(
        phaseFromTransport(negative, .thirty_second) == null,
    );
}

test "repeated host tempo target does not restart smoothing" {
    var rate = try RateSmoother.init(1_000.0, 1.0);
    try rate.setTarget(1_000.0, 3.0, 0.004);
    _ = rate.next();
    const remaining = rate.remaining_samples;
    try rate.setTarget(1_000.0, 3.0, 0.004);
    try std.testing.expectEqual(remaining, rate.remaining_samples);
}
