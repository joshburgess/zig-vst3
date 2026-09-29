const std = @import("std");
const common = @import("ara_analysis_common.zig");
const model = @import("ara_analysis_model.zig");

const Error = model.Error;
const DetectionConfig = model.DetectionConfig;
const Detection = model.Detection;
const maximum_supported_sample_rate =
    model.maximum_supported_sample_rate;
const boundedSearchIndex = common.boundedSearchIndex;

pub fn detectEqualTemperament(
    samples: []const f64,
    sample_rate: f64,
    config: DetectionConfig,
) Error!Detection {
    if (!std.math.isFinite(sample_rate) or
        sample_rate <= 0.0 or
        sample_rate > maximum_supported_sample_rate)
        return error.InvalidSampleRate;
    if (samples.len < 8) return error.InvalidSampleCount;
    if (!std.math.isFinite(config.minimum_frequency) or
        !std.math.isFinite(config.maximum_frequency) or
        config.minimum_frequency <= 0.0 or
        config.maximum_frequency <= config.minimum_frequency or
        config.maximum_frequency >= sample_rate * 0.5 or
        !std.math.isFinite(config.minimum_rms) or
        config.minimum_rms < 0.0 or
        !std.math.isFinite(config.minimum_correlation) or
        config.minimum_correlation < 0.0 or
        config.minimum_correlation > 1.0)
        return error.InvalidFrequencyRange;

    const lag_limit = samples.len / 2;
    const minimum_lag = @max(
        @as(usize, 2),
        boundedSearchIndex(@floor(
            sample_rate / config.maximum_frequency,
        ), lag_limit) orelse return error.InvalidFrequencyRange,
    );
    const maximum_lag = boundedSearchIndex(
        @ceil(
            sample_rate / config.minimum_frequency,
        ),
        lag_limit,
    ) orelse return error.InvalidFrequencyRange;
    if (minimum_lag >= maximum_lag)
        return error.InvalidSampleCount;

    var mean: f64 = 0.0;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.PitchNotFound;
        mean += sample;
    }
    mean /= @floatFromInt(samples.len);
    var energy: f64 = 0.0;
    for (samples) |sample| {
        const centered = sample - mean;
        energy += centered * centered;
    }
    const rms = @sqrt(energy / @as(f64, @floatFromInt(samples.len)));
    if (rms < config.minimum_rms) return error.SignalTooQuiet;

    var best_lag = minimum_lag;
    var best_score: f64 = -1.0;
    var previous_score = correlationAt(samples, mean, minimum_lag);
    var lag = minimum_lag + 1;
    while (lag < maximum_lag) : (lag += 1) {
        const score = correlationAt(samples, mean, lag);
        const next_score = correlationAt(samples, mean, lag + 1);
        if (score > best_score) {
            best_score = score;
            best_lag = lag;
        }
        if (score >= config.minimum_correlation and
            score >= previous_score and
            score > next_score)
        {
            best_lag = lag;
            best_score = score;
            break;
        }
        previous_score = score;
    }
    if (best_score < config.minimum_correlation)
        return error.PitchNotFound;

    const left = correlationAt(samples, mean, best_lag - 1);
    const center = correlationAt(samples, mean, best_lag);
    const right = correlationAt(samples, mean, best_lag + 1);
    const curvature = left - 2.0 * center + right;
    const offset = if (@abs(curvature) > 1.0e-12)
        std.math.clamp(
            0.5 * (left - right) / curvature,
            -0.5,
            0.5,
        )
    else
        0.0;
    const period = @as(f64, @floatFromInt(best_lag)) + offset;
    const frequency = sample_rate / period;
    const pitch_value =
        69.0 + 12.0 * @log2(frequency / 440.0);
    const pitch_number: i32 = @intFromFloat(@round(pitch_value));
    const concert_pitch = frequency /
        std.math.pow(
            f64,
            2.0,
            (@as(f64, @floatFromInt(pitch_number)) - 69.0) / 12.0,
        );
    if (!std.math.isFinite(concert_pitch) or concert_pitch <= 0.0)
        return error.PitchNotFound;
    return .{
        .frequency = frequency,
        .concert_pitch = concert_pitch,
        .pitch_number = pitch_number,
        .correlation = center,
        .rms = rms,
    };
}

fn correlationAt(
    samples: []const f64,
    mean: f64,
    lag: usize,
) f64 {
    var cross: f64 = 0.0;
    var first_energy: f64 = 0.0;
    var second_energy: f64 = 0.0;
    for (samples[0 .. samples.len - lag], samples[lag..]) |
        first,
        second,
    | {
        const left = first - mean;
        const right = second - mean;
        cross += left * right;
        first_energy += left * left;
        second_energy += right * right;
    }
    const denominator = @sqrt(first_energy * second_energy);
    return if (denominator > 0.0) cross / denominator else -1.0;
}
