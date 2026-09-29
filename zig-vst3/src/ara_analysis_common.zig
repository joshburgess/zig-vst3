const std = @import("std");
const model = @import("ara_analysis_model.zig");

const raw = model.raw;
const Error = model.Error;

pub fn validateTempoMap(
    tempo_entries: []const raw.ARAContentTempoEntry,
) Error!void {
    if (tempo_entries.len < 2)
        return error.InvalidSampleCount;
    var includes_quarter_zero = false;
    for (tempo_entries, 0..) |entry, index| {
        if (!std.math.isFinite(entry.timePosition) or
            !std.math.isFinite(entry.quarterPosition))
            return error.MeterNotFound;
        if (@abs(entry.quarterPosition) <= 1.0e-9)
            includes_quarter_zero = true;
        if (index == 0)
            continue;
        const previous = tempo_entries[index - 1];
        if (entry.timePosition <= previous.timePosition or
            entry.quarterPosition <= previous.quarterPosition)
            return error.MeterNotFound;
    }
    if (!includes_quarter_zero)
        return error.MeterNotFound;
}

pub fn boundedSearchIndex(value: f64, maximum: usize) ?usize {
    if (std.math.isNan(value)) return null;
    if (value <= 0.0) return 0;
    if (!std.math.isFinite(value) or
        value >= @as(f64, @floatFromInt(maximum)))
        return maximum;
    return @intFromFloat(value);
}

pub fn envelopeCorrelation(
    envelope: []const f64,
    mean: f64,
    lag: usize,
) f64 {
    var cross: f64 = 0.0;
    var left_energy: f64 = 0.0;
    var right_energy: f64 = 0.0;
    for (envelope[0 .. envelope.len - lag], envelope[lag..]) |
        left_value,
        right_value,
    | {
        const left = left_value - mean;
        const right = right_value - mean;
        cross += left * right;
        left_energy += left * left;
        right_energy += right * right;
    }
    const denominator = @sqrt(left_energy * right_energy);
    return if (denominator > 0.0)
        cross / denominator
    else
        -1.0;
}
