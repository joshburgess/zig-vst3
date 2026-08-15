const std = @import("std");
const common = @import("ara_analysis_common.zig");
const model = @import("ara_analysis_model.zig");

const raw = model.raw;
const Error = model.Error;
const NoteDetectionConfig = model.NoteDetectionConfig;
const maximum_detected_notes = model.maximum_detected_notes;
const maximum_note_window_samples =
    model.maximum_note_window_samples;
const maximum_supported_sample_rate =
    model.maximum_supported_sample_rate;
const boundedSearchIndex = common.boundedSearchIndex;

pub fn detectPolyphonicNotes(
    samples: []const f64,
    sample_rate: f64,
    config: NoteDetectionConfig,
    output: []raw.ARAContentNote,
) Error!usize {
    if (!std.math.isFinite(sample_rate) or
        sample_rate <= 0.0 or
        sample_rate > maximum_supported_sample_rate)
        return error.InvalidSampleRate;
    if (config.minimum_pitch > config.maximum_pitch or
        config.maximum_pitch > 127 or
        config.maximum_polyphony == 0 or
        config.maximum_polyphony > 16 or
        !std.math.isFinite(config.window_seconds) or
        config.window_seconds <= 0.0 or
        !std.math.isFinite(config.hop_seconds) or
        config.hop_seconds <= 0.0 or
        config.hop_seconds > config.window_seconds or
        !std.math.isFinite(config.minimum_amplitude) or
        config.minimum_amplitude <= 0.0 or
        config.minimum_amplitude > 1.0 or
        !std.math.isFinite(config.minimum_note_seconds) or
        config.minimum_note_seconds <= 0.0 or
        !std.math.isFinite(config.harmonic_rejection_ratio) or
        config.harmonic_rejection_ratio <= 0.0 or
        config.harmonic_rejection_ratio > 1.0 or
        pitchFrequency(config.maximum_pitch) >=
            sample_rate * 0.5)
        return error.InvalidConfiguration;
    for (samples) |sample| {
        if (!std.math.isFinite(sample))
            return error.NoteNotFound;
    }
    const window_product = sample_rate * config.window_seconds;
    const hop_product = sample_rate * config.hop_seconds;
    if (!std.math.isFinite(window_product) or
        !std.math.isFinite(hop_product))
        return error.InvalidConfiguration;
    if (window_product > maximum_note_window_samples or
        hop_product > maximum_note_window_samples)
        return error.InvalidSampleCount;
    const window_samples: usize = @intFromFloat(@round(
        window_product,
    ));
    if (window_samples < 32 or
        window_samples > maximum_note_window_samples or
        samples.len < window_samples)
        return error.InvalidSampleCount;
    const hop_samples: usize = @max(
        @as(usize, 1),
        @as(usize, @intFromFloat(@round(hop_product))),
    );

    const Candidate = struct {
        pitch: u8,
        amplitude: f64,
        frequency: f64,
    };
    const Active = struct {
        active: bool = false,
        start_sample: usize = 0,
        last_end_sample: usize = 0,
        missing_hops: u8 = 0,
        maximum_amplitude: f64 = 0.0,
        weighted_frequency: f64 = 0.0,
        weight: f64 = 0.0,
    };

    var staged: [maximum_detected_notes]raw.ARAContentNote =
        undefined;
    var staged_count: usize = 0;
    var active: [128]Active = @splat(.{});
    var windowed: [maximum_note_window_samples]f64 = undefined;
    var amplitudes: [128]f64 = @splat(0.0);
    var present: [128]bool = @splat(false);
    var candidates: [16]Candidate = undefined;
    var selected_candidates: [16]Candidate = undefined;

    var frame_start: usize = 0;
    while (frame_start + window_samples <= samples.len) : (frame_start += hop_samples) {
        var mean: f64 = 0.0;
        for (samples[frame_start..][0..window_samples]) |sample| {
            if (!std.math.isFinite(sample))
                return error.NoteNotFound;
            mean += sample;
        }
        mean /= @floatFromInt(window_samples);
        var window_sum: f64 = 0.0;
        for (
            samples[frame_start..][0..window_samples],
            windowed[0..window_samples],
            0..,
        ) |sample, *destination, sample_index| {
            const window = 0.5 -
                0.5 * @cos(
                    2.0 * std.math.pi *
                        @as(f64, @floatFromInt(sample_index)) /
                        @as(f64, @floatFromInt(window_samples - 1)),
                );
            destination.* = (sample - mean) * window;
            window_sum += window;
        }

        @memset(&amplitudes, 0.0);
        var pitch_index: usize = config.minimum_pitch;
        while (pitch_index <= config.maximum_pitch) : (pitch_index += 1) {
            amplitudes[pitch_index] = noteSpectralAmplitude(
                windowed[0..window_samples],
                sample_rate,
                pitchFrequency(@intCast(pitch_index)),
                window_sum,
            );
        }

        @memset(&present, false);
        var candidate_count: usize = 0;
        pitch_index = config.minimum_pitch;
        while (pitch_index <= config.maximum_pitch) : (pitch_index += 1) {
            const amplitude = amplitudes[pitch_index];
            if (amplitude < config.minimum_amplitude)
                continue;
            const left = if (pitch_index > config.minimum_pitch)
                amplitudes[pitch_index - 1]
            else
                0.0;
            const right = if (pitch_index < config.maximum_pitch)
                amplitudes[pitch_index + 1]
            else
                0.0;
            if (amplitude < left or amplitude <= right)
                continue;
            const pitch: u8 = @intCast(pitch_index);
            const base_frequency = pitchFrequency(pitch);
            const lower = noteSpectralAmplitude(
                windowed[0..window_samples],
                sample_rate,
                base_frequency *
                    std.math.pow(f64, 2.0, -1.0 / 48.0),
                window_sum,
            );
            const upper = noteSpectralAmplitude(
                windowed[0..window_samples],
                sample_rate,
                base_frequency *
                    std.math.pow(f64, 2.0, 1.0 / 48.0),
                window_sum,
            );
            const curvature =
                lower - 2.0 * amplitude + upper;
            const quarter_tone_offset =
                if (@abs(curvature) > 1.0e-12)
                    std.math.clamp(
                        0.5 * (lower - upper) / curvature,
                        -1.0,
                        1.0,
                    )
                else
                    0.0;
            const candidate = Candidate{
                .pitch = pitch,
                .amplitude = amplitude,
                .frequency = base_frequency *
                    std.math.pow(
                        f64,
                        2.0,
                        quarter_tone_offset / 48.0,
                    ),
            };
            var insertion = candidate_count;
            while (insertion > 0 and
                candidates[insertion - 1].amplitude <
                    candidate.amplitude) : (insertion -= 1)
            {
                if (insertion < candidates.len)
                    candidates[insertion] =
                        candidates[insertion - 1];
            }
            if (insertion < candidates.len) {
                candidates[insertion] = candidate;
                candidate_count = @min(
                    candidate_count + 1,
                    candidates.len,
                );
            }
        }

        var selected_count: usize = 0;
        for (candidates[0..candidate_count]) |candidate| {
            var rejected_harmonic = false;
            for (selected_candidates[0..selected_count]) |selected| {
                const frequency_ratio =
                    candidate.frequency / selected.frequency;
                const nearest_harmonic = @round(frequency_ratio);
                if (nearest_harmonic >= 2.0 and
                    nearest_harmonic <= 6.0 and
                    @abs(frequency_ratio - nearest_harmonic) <=
                        0.02 and
                    candidate.amplitude <=
                        selected.amplitude *
                            config.harmonic_rejection_ratio)
                {
                    rejected_harmonic = true;
                    break;
                }
            }
            if (rejected_harmonic)
                continue;
            selected_candidates[selected_count] = candidate;
            selected_count += 1;
            if (selected_count >= config.maximum_polyphony)
                break;
        }
        for (selected_candidates[0..selected_count]) |candidate| {
            present[candidate.pitch] = true;
            const note = &active[candidate.pitch];
            if (!note.active) {
                note.* = .{
                    .active = true,
                    .start_sample = frame_start,
                    .last_end_sample = frame_start + window_samples,
                };
            }
            note.last_end_sample = frame_start + window_samples;
            note.missing_hops = 0;
            note.maximum_amplitude = @max(
                note.maximum_amplitude,
                candidate.amplitude,
            );
            note.weighted_frequency +=
                candidate.frequency * candidate.amplitude;
            note.weight += candidate.amplitude;
        }

        pitch_index = config.minimum_pitch;
        while (pitch_index <= config.maximum_pitch) : (pitch_index += 1) {
            const note = &active[pitch_index];
            if (!note.active or present[pitch_index])
                continue;
            note.missing_hops +|= 1;
            if (note.missing_hops <= config.release_hops)
                continue;
            try finishDetectedNote(
                note,
                @intCast(pitch_index),
                sample_rate,
                config,
                &staged,
                &staged_count,
            );
        }
    }

    for (&active, 0..) |*note, pitch_index| {
        if (!note.active)
            continue;
        try finishDetectedNote(
            note,
            @intCast(pitch_index),
            sample_rate,
            config,
            &staged,
            &staged_count,
        );
    }
    std.mem.sort(
        raw.ARAContentNote,
        staged[0..staged_count],
        {},
        noteLessThan,
    );
    if (staged_count > output.len)
        return error.CapacityExceeded;
    @memcpy(output[0..staged_count], staged[0..staged_count]);
    return staged_count;
}

fn finishDetectedNote(
    note: anytype,
    pitch: u8,
    sample_rate: f64,
    config: NoteDetectionConfig,
    staged: *[maximum_detected_notes]raw.ARAContentNote,
    staged_count: *usize,
) Error!void {
    const duration_samples =
        note.last_end_sample - note.start_sample;
    const duration =
        @as(f64, @floatFromInt(duration_samples)) /
        sample_rate;
    if (duration >= config.minimum_note_seconds) {
        if (staged_count.* >= staged.len)
            return error.CapacityExceeded;
        const frequency = if (note.weight > 0.0)
            note.weighted_frequency / note.weight
        else
            pitchFrequency(pitch);
        staged[staged_count.*] = .{
            .frequency = @floatCast(frequency),
            .pitchNumber = pitch,
            .volume = @floatCast(@sqrt(std.math.clamp(
                note.maximum_amplitude,
                0.0,
                1.0,
            ))),
            .startPosition = @as(f64, @floatFromInt(note.start_sample)) /
                sample_rate,
            .attackDuration = @min(
                duration,
                config.window_seconds * 0.5,
            ),
            .noteDuration = duration,
            .signalDuration = duration,
        };
        staged_count.* += 1;
    }
    note.* = .{};
}

pub fn pitchFrequency(pitch: u8) f64 {
    return 440.0 * std.math.pow(
        f64,
        2.0,
        (@as(f64, @floatFromInt(pitch)) - 69.0) / 12.0,
    );
}

fn noteSpectralAmplitude(
    samples: []const f64,
    sample_rate: f64,
    frequency: f64,
    window_sum: f64,
) f64 {
    const omega = 2.0 * std.math.pi * frequency / sample_rate;
    const coefficient = 2.0 * @cos(omega);
    var previous: f64 = 0.0;
    var previous_two: f64 = 0.0;
    for (samples) |sample| {
        const current =
            sample + coefficient * previous - previous_two;
        previous_two = previous;
        previous = current;
    }
    const real = previous - previous_two * @cos(omega);
    const imaginary = previous_two * @sin(omega);
    return 2.0 * @sqrt(
        real * real + imaginary * imaginary,
    ) / window_sum;
}

pub fn noteLessThan(
    _: void,
    left: raw.ARAContentNote,
    right: raw.ARAContentNote,
) bool {
    return left.startPosition < right.startPosition or
        (left.startPosition == right.startPosition and
            left.pitchNumber < right.pitchNumber);
}

pub fn mergeDetectedNote(
    staged: *[maximum_detected_notes]raw.ARAContentNote,
    staged_count: *usize,
    candidate: raw.ARAContentNote,
) Error!void {
    const candidate_note_end =
        candidate.startPosition + candidate.noteDuration;
    const candidate_signal_end =
        candidate.startPosition + candidate.signalDuration;
    for (staged[0..staged_count.*]) |*existing| {
        if (existing.pitchNumber != candidate.pitchNumber)
            continue;
        const existing_signal_end =
            existing.startPosition + existing.signalDuration;
        if (candidate.startPosition > existing_signal_end or
            existing.startPosition > candidate_signal_end)
            continue;
        const existing_attack =
            existing.startPosition + existing.attackDuration;
        const candidate_attack =
            candidate.startPosition + candidate.attackDuration;
        const existing_note_end =
            existing.startPosition + existing.noteDuration;
        const existing_weight = @max(
            @as(f64, existing.volume),
            1.0e-6,
        );
        const candidate_weight = @max(
            @as(f64, candidate.volume),
            1.0e-6,
        );
        existing.frequency = @floatCast(
            (@as(f64, existing.frequency) * existing_weight +
                @as(f64, candidate.frequency) * candidate_weight) /
                (existing_weight + candidate_weight),
        );
        existing.volume = @max(
            existing.volume,
            candidate.volume,
        );
        existing.startPosition = @min(
            existing.startPosition,
            candidate.startPosition,
        );
        existing.attackDuration =
            @min(existing_attack, candidate_attack) -
            existing.startPosition;
        existing.noteDuration =
            @max(existing_note_end, candidate_note_end) -
            existing.startPosition;
        existing.signalDuration =
            @max(existing_signal_end, candidate_signal_end) -
            existing.startPosition;
        return;
    }
    if (staged_count.* >= staged.len)
        return error.CapacityExceeded;
    staged[staged_count.*] = candidate;
    staged_count.* += 1;
}

pub fn noteIntersectsRange(
    note: raw.ARAContentNote,
    range: ?raw.ARAContentTimeRange,
) bool {
    const selected = range orelse return true;
    const note_end = note.startPosition + note.signalDuration;
    const range_end = selected.start + selected.duration;
    return note_end >= selected.start and
        note.startPosition <= range_end;
}
