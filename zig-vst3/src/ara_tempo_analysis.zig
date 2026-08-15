const std = @import("std");
const common = @import("ara_analysis_common.zig");
const model = @import("ara_analysis_model.zig");

const raw = model.raw;
const Error = model.Error;
const TempoDetectionConfig = model.TempoDetectionConfig;
const TempoDetection = model.TempoDetection;
const MeterDetectionConfig = model.MeterDetectionConfig;
const maximum_detected_tempo_entries =
    model.maximum_detected_tempo_entries;
const maximum_detected_bar_signatures =
    model.maximum_detected_bar_signatures;
const maximum_meter_pulses = model.maximum_meter_pulses;
const maximum_supported_sample_rate =
    model.maximum_supported_sample_rate;
const boundedSearchIndex = common.boundedSearchIndex;
const envelopeCorrelation = common.envelopeCorrelation;
const validateTempoMap = common.validateTempoMap;

pub fn detectTempoEnvelope(
    onset_envelope: []const f64,
    envelope_rate: f64,
    config: TempoDetectionConfig,
) Error!TempoDetection {
    try validateTempoDetectionConfig(envelope_rate, config);
    if (onset_envelope.len < 4)
        return error.InvalidSampleCount;

    const lag_limit = onset_envelope.len / 2;
    const minimum_lag = @max(
        @as(usize, 1),
        boundedSearchIndex(@floor(
            envelope_rate * 60.0 / config.maximum_bpm,
        ), lag_limit) orelse return error.InvalidConfiguration,
    );
    const maximum_lag = boundedSearchIndex(
        @ceil(
            envelope_rate * 60.0 / config.minimum_bpm,
        ),
        lag_limit,
    ) orelse return error.InvalidConfiguration;
    if (minimum_lag >= maximum_lag)
        return error.InvalidSampleCount;

    var peak: f64 = 0.0;
    var mean: f64 = 0.0;
    for (onset_envelope) |value| {
        if (!std.math.isFinite(value) or value < 0.0)
            return error.TempoNotFound;
        peak = @max(peak, value);
        mean += value;
    }
    if (peak < config.minimum_onset)
        return error.SignalTooQuiet;
    mean /= @floatFromInt(onset_envelope.len);

    var best_lag = minimum_lag;
    var best_score: f64 = -1.0;
    var lag = minimum_lag;
    while (lag <= maximum_lag) : (lag += 1) {
        const score = envelopeCorrelation(
            onset_envelope,
            mean,
            lag,
        );
        if (score > best_score + 1.0e-9) {
            best_score = score;
            best_lag = lag;
        }
    }
    const harmonic_lag = best_lag;
    const harmonic_score = best_score;
    var selected_lag = best_lag;
    var selected_score = best_score;
    var harmonic_divisor: usize = 2;
    while (harmonic_divisor <= 4) : (harmonic_divisor += 1) {
        if (harmonic_lag % harmonic_divisor != 0)
            continue;
        const candidate_lag = harmonic_lag / harmonic_divisor;
        if (candidate_lag < minimum_lag)
            continue;
        const candidate_score = envelopeCorrelation(
            onset_envelope,
            mean,
            candidate_lag,
        );
        if (candidate_score >= config.minimum_correlation and
            candidate_score + 0.05 >= harmonic_score and
            candidate_lag < selected_lag)
        {
            selected_lag = candidate_lag;
            selected_score = candidate_score;
        }
    }
    best_lag = selected_lag;
    best_score = selected_score;
    if (best_score < config.minimum_correlation)
        return error.TempoNotFound;

    var phase_index: usize = 0;
    var phase_strength: f64 = -1.0;
    for (0..@min(best_lag, onset_envelope.len)) |phase| {
        var strength: f64 = 0.0;
        var index = phase;
        while (index < onset_envelope.len) : (index += best_lag)
            strength += onset_envelope[index];
        if (strength > phase_strength) {
            phase_strength = strength;
            phase_index = phase;
        }
    }
    const period =
        @as(f64, @floatFromInt(best_lag)) / envelope_rate;
    return .{
        .bpm = 60.0 / period,
        .beat_period = period,
        .first_beat_time = @as(f64, @floatFromInt(phase_index)) /
            envelope_rate,
        .correlation = best_score,
    };
}

fn validateTempoDetectionConfig(
    envelope_rate: f64,
    config: TempoDetectionConfig,
) Error!void {
    if (!std.math.isFinite(envelope_rate) or
        envelope_rate <= 0.0 or
        envelope_rate > maximum_supported_sample_rate or
        !std.math.isFinite(config.minimum_bpm) or
        !std.math.isFinite(config.maximum_bpm) or
        config.minimum_bpm <= 0.0 or
        config.maximum_bpm <= config.minimum_bpm or
        !std.math.isFinite(config.minimum_correlation) or
        config.minimum_correlation < 0.0 or
        config.minimum_correlation > 1.0 or
        !std.math.isFinite(config.minimum_onset) or
        config.minimum_onset < 0.0 or
        !std.math.isFinite(config.window_seconds) or
        config.window_seconds <= 0.0 or
        !std.math.isFinite(config.hop_seconds) or
        config.hop_seconds <= 0.0 or
        config.hop_seconds > config.window_seconds or
        !std.math.isFinite(config.tempo_change_ratio) or
        config.tempo_change_ratio <= 0.0 or
        config.tempo_change_ratio >= 1.0)
        return error.InvalidConfiguration;
}

pub fn detectTempoMapEnvelope(
    onset_envelope: []const f64,
    envelope_rate: f64,
    config: TempoDetectionConfig,
    output: []raw.ARAContentTempoEntry,
) Error!usize {
    if (output.len < 2)
        return error.CapacityExceeded;
    try validateTempoDetectionConfig(envelope_rate, config);
    if (onset_envelope.len < 4)
        return error.InvalidSampleCount;
    const window_product =
        envelope_rate * config.window_seconds;
    const hop_product =
        envelope_rate * config.hop_seconds;
    if (!std.math.isFinite(window_product) or
        !std.math.isFinite(hop_product))
        return error.InvalidConfiguration;
    const window_bins = @min(
        onset_envelope.len,
        @max(
            @as(usize, 4),
            @as(usize, @intFromFloat(@ceil(@min(
                window_product,
                @as(f64, @floatFromInt(onset_envelope.len)),
            )))),
        ),
    );
    const hop_bins = @max(
        @as(usize, 1),
        @as(usize, @intFromFloat(@round(@min(
            hop_product,
            @as(f64, @floatFromInt(window_bins)),
        )))),
    );

    var staged: [maximum_detected_tempo_entries]raw.ARAContentTempoEntry =
        undefined;
    var count: usize = 0;
    var previous_bpm: f64 = 0.0;
    var previous_time: f64 = 0.0;
    var quarter_position: f64 = 0.0;
    var have_local_tempo = false;
    var window_start: usize = 0;
    const minimum_window_bins = @max(
        @as(usize, 4),
        (window_bins + 1) / 2,
    );
    while (window_start < onset_envelope.len) : (window_start += hop_bins) {
        const window_end = @min(
            onset_envelope.len,
            window_start + window_bins,
        );
        if (window_end - window_start < minimum_window_bins)
            break;
        const local = detectTempoEnvelope(
            onset_envelope[window_start..window_end],
            envelope_rate,
            config,
        ) catch continue;
        if (!have_local_tempo) {
            const first_beat_time =
                @as(f64, @floatFromInt(window_start)) /
                envelope_rate +
                local.first_beat_time;
            staged[0] = .{
                .timePosition = first_beat_time,
                .quarterPosition = 0.0,
            };
            count = 1;
            previous_time = first_beat_time;
            previous_bpm = local.bpm;
            have_local_tempo = true;
            continue;
        }
        const local_bpm = stabilizeTempoOctave(
            local.bpm,
            previous_bpm,
            config,
        );
        const boundary_time =
            (@as(f64, @floatFromInt(window_start)) +
                0.5 * @as(f64, @floatFromInt(
                    window_end - window_start,
                ))) /
            envelope_rate;
        if (boundary_time <= previous_time)
            continue;
        const change_ratio =
            @abs(local_bpm - previous_bpm) / previous_bpm;
        if (change_ratio < config.tempo_change_ratio)
            continue;
        if (count >= staged.len - 1)
            return error.CapacityExceeded;
        quarter_position +=
            (boundary_time - previous_time) *
            previous_bpm / 60.0;
        if (!std.math.isFinite(quarter_position) or
            quarter_position <= staged[count - 1].quarterPosition)
            return error.TempoNotFound;
        staged[count] = .{
            .timePosition = boundary_time,
            .quarterPosition = quarter_position,
        };
        count += 1;
        previous_time = boundary_time;
        previous_bpm = local_bpm;
    }
    if (!have_local_tempo) {
        const global = try detectTempoEnvelope(
            onset_envelope,
            envelope_rate,
            config,
        );
        staged[0] = .{
            .timePosition = global.first_beat_time,
            .quarterPosition = 0.0,
        };
        count = 1;
        previous_time = global.first_beat_time;
        previous_bpm = global.bpm;
    }

    const analyzed_duration =
        @as(f64, @floatFromInt(onset_envelope.len)) /
        envelope_rate;
    const final_time = @max(
        analyzed_duration,
        previous_time + 60.0 / previous_bpm,
    );
    quarter_position +=
        (final_time - previous_time) * previous_bpm / 60.0;
    if (!std.math.isFinite(final_time) or
        !std.math.isFinite(quarter_position) or
        final_time <= staged[count - 1].timePosition or
        quarter_position <= staged[count - 1].quarterPosition)
        return error.TempoNotFound;
    staged[count] = .{
        .timePosition = final_time,
        .quarterPosition = quarter_position,
    };
    count += 1;
    if (count > output.len)
        return error.CapacityExceeded;
    @memcpy(output[0..count], staged[0..count]);
    return count;
}

pub const MeterCandidate = struct {
    numerator: i32,
    denominator: i32,
    pulses: usize,
};

pub const meter_candidates = [_]MeterCandidate{
    .{ .numerator = 2, .denominator = 4, .pulses = 4 },
    .{ .numerator = 3, .denominator = 4, .pulses = 6 },
    .{ .numerator = 4, .denominator = 4, .pulses = 8 },
    .{ .numerator = 5, .denominator = 4, .pulses = 10 },
    .{ .numerator = 6, .denominator = 8, .pulses = 6 },
    .{ .numerator = 7, .denominator = 8, .pulses = 7 },
    .{ .numerator = 9, .denominator = 8, .pulses = 9 },
    .{ .numerator = 12, .denominator = 8, .pulses = 12 },
};

pub fn detectBarSignaturesEnvelope(
    onset_envelope: []const f64,
    envelope_rate: f64,
    tempo_entries: []const raw.ARAContentTempoEntry,
    config: MeterDetectionConfig,
    output: []raw.ARAContentBarSignature,
) Error!usize {
    if (output.len == 0)
        return error.CapacityExceeded;
    if (!std.math.isFinite(envelope_rate) or
        envelope_rate <= 0.0 or
        envelope_rate > maximum_supported_sample_rate or
        config.minimum_bars < 2 or
        config.minimum_bars > 32 or
        !std.math.isFinite(config.minimum_score) or
        config.minimum_score <= 0.0 or
        config.minimum_score >= 1.0 or
        !std.math.isFinite(config.change_score_margin) or
        config.change_score_margin <= 0.0 or
        config.change_score_margin >= 1.0 or
        !std.math.isFinite(config.onset_window_ratio) or
        config.onset_window_ratio <= 0.0 or
        config.onset_window_ratio >= 0.5)
        return error.InvalidConfiguration;
    if (onset_envelope.len < 4)
        return error.InvalidSampleCount;
    var peak: f64 = 0.0;
    for (onset_envelope) |onset| {
        if (!std.math.isFinite(onset) or onset < 0.0)
            return error.MeterNotFound;
        peak = @max(peak, onset);
    }
    if (peak <= 0.0)
        return error.SignalTooQuiet;
    try validateTempoMap(tempo_entries);

    const last_quarter = tempo_entries[
        tempo_entries.len - 1
    ].quarterPosition;
    if (last_quarter <= 0.0)
        return error.InvalidSampleCount;
    const pulse_count_float = @floor(last_quarter * 2.0) + 1.0;
    if (!std.math.isFinite(pulse_count_float) or
        pulse_count_float < 2.0 or
        pulse_count_float >
            @as(f64, @floatFromInt(maximum_meter_pulses)))
        return error.CapacityExceeded;
    const pulse_count: usize = @intFromFloat(pulse_count_float);
    var pulse_strengths: [maximum_meter_pulses]f64 =
        @splat(0.0);
    const envelope_duration =
        @as(f64, @floatFromInt(onset_envelope.len)) /
        envelope_rate;
    for (pulse_strengths[0..pulse_count], 0..) |
        *strength,
        pulse_index,
    | {
        const quarter =
            @as(f64, @floatFromInt(pulse_index)) * 0.5;
        const time = try timeAtQuarter(tempo_entries, quarter);
        if (time < 0.0 or time >= envelope_duration)
            continue;
        const adjacent_quarter =
            if (pulse_index + 1 < pulse_count)
                quarter + 0.5
            else
                quarter - 0.5;
        const adjacent_time =
            try timeAtQuarter(tempo_entries, adjacent_quarter);
        const pulse_duration = @abs(adjacent_time - time);
        const radius_float = @ceil(
            pulse_duration * config.onset_window_ratio *
                envelope_rate,
        );
        const radius: usize = @max(
            @as(usize, 1),
            boundedSearchIndex(
                radius_float,
                onset_envelope.len,
            ) orelse return error.MeterNotFound,
        );
        const center = boundedSearchIndex(
            @round(time * envelope_rate),
            onset_envelope.len,
        ) orelse return error.MeterNotFound;
        const first = center -| radius;
        const end = @min(
            onset_envelope.len,
            center +| radius +| 1,
        );
        for (onset_envelope[first..end]) |onset|
            strength.* = @max(strength.*, onset / peak);
    }

    var best_candidate: ?MeterCandidate = null;
    var best_phase: usize = 0;
    var best_score: f64 = -1.0;
    for (meter_candidates) |candidate| {
        const required_pulses =
            candidate.pulses * config.minimum_bars;
        if (required_pulses > pulse_count)
            continue;
        for (0..candidate.pulses) |phase| {
            if (phase + required_pulses > pulse_count)
                continue;
            const score = meterCorrelation(
                pulse_strengths[phase .. phase + required_pulses],
                candidate,
            );
            if (score > best_score + 1.0e-9) {
                best_candidate = candidate;
                best_phase = phase;
                best_score = score;
            }
        }
    }
    const candidate = best_candidate orelse
        return error.InvalidSampleCount;
    if (best_score < config.minimum_score)
        return error.MeterNotFound;

    var staged: [maximum_detected_bar_signatures]raw.ARAContentBarSignature =
        undefined;
    staged[0] = .{
        .numerator = candidate.numerator,
        .denominator = candidate.denominator,
        .position = @as(f64, @floatFromInt(best_phase)) * 0.5,
    };
    var staged_count: usize = 1;
    var current = candidate;
    var boundary = best_phase + current.pulses;
    while (boundary < pulse_count) {
        const current_window =
            current.pulses * config.minimum_bars;
        if (boundary + current_window > pulse_count)
            break;
        const current_score = meterCorrelation(
            pulse_strengths[boundary .. boundary + current_window],
            current,
        );
        var replacement = current;
        var replacement_score = current_score;
        for (meter_candidates) |alternative| {
            if (alternative.numerator == current.numerator and
                alternative.denominator == current.denominator)
                continue;
            const alternative_window =
                alternative.pulses * config.minimum_bars;
            if (boundary + alternative_window > pulse_count)
                continue;
            const score = meterCorrelation(
                pulse_strengths[boundary .. boundary + alternative_window],
                alternative,
            );
            if (score > replacement_score + 1.0e-9) {
                replacement = alternative;
                replacement_score = score;
            }
        }
        if ((replacement.numerator != current.numerator or
            replacement.denominator != current.denominator) and
            replacement_score >= config.minimum_score and
            replacement_score >=
                current_score + config.change_score_margin)
        {
            if (staged_count >= staged.len)
                return error.CapacityExceeded;
            staged[staged_count] = .{
                .numerator = replacement.numerator,
                .denominator = replacement.denominator,
                .position = @as(f64, @floatFromInt(boundary)) * 0.5,
            };
            staged_count += 1;
            current = replacement;
        }
        boundary += current.pulses;
    }
    if (staged_count > output.len)
        return error.CapacityExceeded;
    @memcpy(output[0..staged_count], staged[0..staged_count]);
    return staged_count;
}

fn timeAtQuarter(
    tempo_entries: []const raw.ARAContentTempoEntry,
    quarter: f64,
) Error!f64 {
    if (!std.math.isFinite(quarter))
        return error.MeterNotFound;
    var upper: usize = 1;
    while (upper < tempo_entries.len and
        tempo_entries[upper].quarterPosition < quarter)
        upper += 1;
    if (upper >= tempo_entries.len) {
        upper = tempo_entries.len - 1;
    } else if (quarter <
        tempo_entries[0].quarterPosition)
    {
        upper = 1;
    }
    const lower = tempo_entries[upper - 1];
    const higher = tempo_entries[upper];
    const quarter_span =
        higher.quarterPosition - lower.quarterPosition;
    if (quarter_span <= 0.0)
        return error.MeterNotFound;
    const fraction =
        (quarter - lower.quarterPosition) / quarter_span;
    const time = lower.timePosition +
        fraction * (higher.timePosition - lower.timePosition);
    if (!std.math.isFinite(time))
        return error.MeterNotFound;
    return time;
}

fn meterCorrelation(
    strengths: []const f64,
    candidate: MeterCandidate,
) f64 {
    var strength_mean: f64 = 0.0;
    var template_mean: f64 = 0.0;
    for (strengths, 0..) |strength, index| {
        strength_mean += strength;
        template_mean += meterTemplate(
            candidate,
            index % candidate.pulses,
        );
    }
    strength_mean /= @floatFromInt(strengths.len);
    template_mean /= @floatFromInt(strengths.len);
    var cross: f64 = 0.0;
    var strength_energy: f64 = 0.0;
    var template_energy: f64 = 0.0;
    for (strengths, 0..) |strength, index| {
        const centered_strength = strength - strength_mean;
        const centered_template =
            meterTemplate(
                candidate,
                index % candidate.pulses,
            ) - template_mean;
        cross += centered_strength * centered_template;
        strength_energy += centered_strength * centered_strength;
        template_energy += centered_template * centered_template;
    }
    const denominator =
        @sqrt(strength_energy * template_energy);
    return if (denominator > 0.0)
        cross / denominator
    else
        -1.0;
}

pub fn meterTemplate(
    candidate: MeterCandidate,
    pulse: usize,
) f64 {
    if (pulse == 0)
        return 1.0;
    if (candidate.denominator == 4) {
        if (pulse % 2 != 0)
            return 0.05;
        return switch (candidate.numerator) {
            4 => if (pulse == 4) 0.8 else 0.6,
            5 => if (pulse == 6) 0.65 else 0.35,
            else => 0.45,
        };
    }
    return switch (candidate.numerator) {
        6 => if (pulse == 3) 0.65 else 0.08,
        7 => if (pulse == 4)
            0.65
        else if (pulse == 2)
            0.4
        else
            0.08,
        9 => if (pulse % 3 == 0) 0.5 else 0.08,
        12 => if (pulse == 6)
            0.65
        else if (pulse % 3 == 0)
            0.45
        else
            0.08,
        else => 0.08,
    };
}

fn stabilizeTempoOctave(
    bpm: f64,
    previous_bpm: f64,
    config: TempoDetectionConfig,
) f64 {
    if (bpm > previous_bpm * 1.8 and
        bpm * 0.5 >= config.minimum_bpm)
        return bpm * 0.5;
    if (bpm < previous_bpm * 0.56 and
        bpm * 2.0 <= config.maximum_bpm)
        return bpm * 2.0;
    return bpm;
}
