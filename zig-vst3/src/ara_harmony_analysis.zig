const std = @import("std");
const common = @import("ara_analysis_common.zig");
const model = @import("ara_analysis_model.zig");

const raw = model.raw;
const Error = model.Error;
const ChordDetectionConfig = model.ChordDetectionConfig;
const KeySignatureDetectionConfig = model.KeySignatureDetectionConfig;
const maximum_detected_chords = model.maximum_detected_chords;
const maximum_detected_key_signatures =
    model.maximum_detected_key_signatures;
const boundedSearchIndex = common.boundedSearchIndex;
const validateTempoMap = common.validateTempoMap;

const major_key_profile = [12]f64{
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09,
    2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
};

const minor_key_profile = [12]f64{
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53,
    2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
};

pub const major_intervals = [12]u8{
    0xff, 0,    0xff, 0,    0xff, 0xff,
    0,    0xff, 0,    0xff, 0,    0xff,
};

pub const minor_intervals = [12]u8{
    0xff, 0,    0xff, 0xff, 0,    0xff,
    0,    0xff, 0xff, 0,    0xff, 0,
};

const circle_of_fifths_by_pitch_class = [12]i32{
    0, -5, 2, -3, 4, -1, 6, 1, -4, 3, -2, 5,
};

const KeyCandidate = struct {
    root_pitch_class: u8,
    minor: bool,
    score: f64,
    margin: f64,
};

const ChordTemplate = struct {
    intervals: [12]u8,
    pitch_class_count: u8,
};

pub const chord_templates = [_]ChordTemplate{
    .{
        .intervals = .{ 1, 0, 0, 0, 3, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 5, 0, 0, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 3, 0, 0, 0, 5, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 2, 0, 0, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 0, 4, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 3,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 3, 0, 0, 5, 0, 0, 7, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 3, 0, 0, 5, 0, 0, 0, 7 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 0, 5, 0, 0, 7, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 5, 0, 0, 0, 7, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 5, 0, 0, 7, 0, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 0, 5, 0, 0, 0, 7 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 3, 0, 0, 5, 0, 6, 0, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 0, 3, 0, 0, 0, 5, 0, 6, 0, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 9, 3, 0, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 4,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 0, 0, 5, 0, 0, 7, 0 },
        .pitch_class_count = 5,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 0, 0, 5, 0, 0, 0, 7 },
        .pitch_class_count = 5,
    },
    .{
        .intervals = .{ 1, 0, 9, 3, 0, 0, 0, 5, 0, 0, 7, 0 },
        .pitch_class_count = 5,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 11, 0, 5, 0, 0, 7, 0 },
        .pitch_class_count = 6,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 0, 0, 5, 0, 13, 7, 0 },
        .pitch_class_count = 6,
    },
    .{
        .intervals = .{ 1, 0, 9, 0, 3, 0, 0, 5, 0, 13, 0, 7 },
        .pitch_class_count = 6,
    },
    .{
        .intervals = .{ 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0 },
        .pitch_class_count = 2,
    },
};

const ChordCandidate = struct {
    root_pitch_class: u8,
    bass_pitch_class: u8,
    template_index: u8,
    score: f64,
    margin: f64,
};

pub fn detectChords(
    notes: []const raw.ARAContentNote,
    tempo_entries: []const raw.ARAContentTempoEntry,
    config: ChordDetectionConfig,
    output: []raw.ARAContentChord,
) Error!usize {
    try validateChordDetectionConfig(config);
    try validateTempoMapForChords(tempo_entries);
    if (notes.len == 0)
        return error.ChordNotFound;

    var first_quarter = std.math.inf(f64);
    var last_quarter = -std.math.inf(f64);
    for (notes) |note| {
        if (!validKeyDetectionNote(note))
            return error.ChordNotFound;
        const start = quarterAtTime(
            tempo_entries,
            note.startPosition,
        ) catch return error.ChordNotFound;
        const end = quarterAtTime(
            tempo_entries,
            note.startPosition + note.noteDuration,
        ) catch return error.ChordNotFound;
        first_quarter = @min(first_quarter, start);
        last_quarter = @max(last_quarter, end);
    }
    if (!std.math.isFinite(first_quarter) or
        !std.math.isFinite(last_quarter) or
        last_quarter <= first_quarter)
        return error.ChordNotFound;

    var staged: [maximum_detected_chords]raw.ARAContentChord =
        undefined;
    var staged_count: usize = 0;
    var current: ?ChordCandidate = null;
    var pending: ?ChordCandidate = null;
    var pending_count: u8 = 0;
    var gap_count: u8 = 0;
    const start_quarter =
        @floor(first_quarter / config.hop_quarters) *
        config.hop_quarters;
    var window_start = start_quarter;
    while (window_start < last_quarter) : (window_start += config.hop_quarters) {
        const candidate = scoreChordWindow(
            notes,
            tempo_entries,
            window_start,
            window_start + config.window_quarters,
            config,
        ) catch |failure| switch (failure) {
            error.ChordNotFound => {
                pending = null;
                pending_count = 0;
                if (current != null) {
                    gap_count += 1;
                    if (gap_count >=
                        config.change_confirmation_windows)
                    {
                        if (staged_count >= staged.len)
                            return error.CapacityExceeded;
                        const gap_position = window_start -
                            config.hop_quarters *
                                @as(
                                    f64,
                                    @floatFromInt(
                                        config.change_confirmation_windows -
                                            1,
                                    ),
                                );
                        staged[staged_count] =
                            undefinedChordEvent(gap_position);
                        staged_count += 1;
                        current = null;
                    }
                }
                continue;
            },
            else => return failure,
        };
        gap_count = 0;
        if (current == null) {
            if (staged_count >= staged.len)
                return error.CapacityExceeded;
            staged[staged_count] = chordEvent(
                candidate,
                window_start,
            );
            staged_count += 1;
            current = candidate;
            continue;
        }
        const current_chord = current orelse
            return error.InvalidChordAnalysisState;
        if (sameChord(current_chord, candidate)) {
            pending = null;
            pending_count = 0;
            continue;
        }
        if (pending) |pending_chord| {
            if (sameChord(pending_chord, candidate)) {
                pending_count += 1;
            } else {
                pending = candidate;
                pending_count = 1;
            }
        } else {
            pending = candidate;
            pending_count = 1;
        }
        if (pending_count < config.change_confirmation_windows)
            continue;
        if (staged_count >= staged.len)
            return error.CapacityExceeded;
        const change_position = window_start -
            config.hop_quarters *
                @as(
                    f64,
                    @floatFromInt(
                        config.change_confirmation_windows - 1,
                    ),
                );
        staged[staged_count] = chordEvent(
            pending orelse return error.InvalidChordAnalysisState,
            change_position,
        );
        staged_count += 1;
        current = pending;
        pending = null;
        pending_count = 0;
    }
    if (staged_count == 0)
        return error.ChordNotFound;
    if (staged_count > output.len)
        return error.CapacityExceeded;
    @memcpy(output[0..staged_count], staged[0..staged_count]);
    return staged_count;
}

fn validateChordDetectionConfig(
    config: ChordDetectionConfig,
) Error!void {
    if (!std.math.isFinite(config.window_quarters) or
        config.window_quarters <= 0.0 or
        !std.math.isFinite(config.hop_quarters) or
        config.hop_quarters <= 0.0 or
        config.hop_quarters > config.window_quarters or
        !std.math.isFinite(config.minimum_note_weight) or
        config.minimum_note_weight <= 0.0 or
        !std.math.isFinite(config.minimum_note_quarters) or
        config.minimum_note_quarters <= 0.0 or
        !std.math.isFinite(config.minimum_score) or
        config.minimum_score < 0.0 or
        config.minimum_score > 1.0 or
        !std.math.isFinite(config.minimum_score_margin) or
        config.minimum_score_margin < 0.0 or
        config.minimum_score_margin > 1.0 or
        config.minimum_pitch_classes < 2 or
        config.minimum_pitch_classes > 12 or
        config.change_confirmation_windows == 0)
        return error.InvalidConfiguration;
}

fn validateTempoMapForChords(
    tempo_entries: []const raw.ARAContentTempoEntry,
) Error!void {
    validateTempoMap(tempo_entries) catch |failure| switch (failure) {
        error.InvalidSampleCount => return error.InvalidSampleCount,
        else => return error.ChordNotFound,
    };
}

fn scoreChordWindow(
    notes: []const raw.ARAContentNote,
    tempo_entries: []const raw.ARAContentTempoEntry,
    window_start: f64,
    window_end: f64,
    config: ChordDetectionConfig,
) Error!ChordCandidate {
    var histogram: [12]f64 = @splat(0.0);
    var total_weight: f64 = 0.0;
    var bass_pitch: i32 = std.math.maxInt(i32);
    for (notes) |note| {
        const note_start = quarterAtTime(
            tempo_entries,
            note.startPosition,
        ) catch return error.ChordNotFound;
        const note_end = quarterAtTime(
            tempo_entries,
            note.startPosition + note.noteDuration,
        ) catch return error.ChordNotFound;
        if (note_end - note_start <
            config.minimum_note_quarters)
            continue;
        const overlap = @max(
            0.0,
            @min(note_end, window_end) -
                @max(note_start, window_start),
        );
        if (overlap <= 0.0)
            continue;
        const pitch_class: usize =
            @intCast(@mod(note.pitchNumber, 12));
        const weight = overlap * @max(
            @as(f64, note.volume),
            0.05,
        );
        histogram[pitch_class] += weight;
        total_weight += weight;
        bass_pitch = @min(bass_pitch, note.pitchNumber);
    }
    if (total_weight < config.minimum_note_weight or
        bass_pitch == std.math.maxInt(i32))
        return error.ChordNotFound;
    var distinct_pitch_classes: u8 = 0;
    for (histogram) |weight| {
        if (weight > 1.0e-9)
            distinct_pitch_classes += 1;
    }
    if (distinct_pitch_classes < config.minimum_pitch_classes)
        return error.ChordNotFound;

    var best = ChordCandidate{
        .root_pitch_class = 0,
        .bass_pitch_class = @intCast(@mod(bass_pitch, 12)),
        .template_index = 0,
        .score = -1.0,
        .margin = 0.0,
    };
    var second_score: f64 = -1.0;
    for (0..12) |root| {
        for (chord_templates, 0..) |template, template_index| {
            var matched_weight: f64 = 0.0;
            var present_count: u8 = 0;
            for (0..12) |interval| {
                if (template.intervals[interval] == 0)
                    continue;
                const weight = histogram[@mod(root + interval, 12)];
                matched_weight += weight;
                if (weight > 1.0e-9)
                    present_count += 1;
            }
            const score =
                if (present_count == template.pitch_class_count)
                    0.72 * matched_weight / total_weight +
                        0.25 +
                        (if (root ==
                            @as(usize, best.bass_pitch_class))
                            @as(f64, 0.03)
                        else
                            0.0)
                else
                    -1.0;
            if (score > best.score + 1.0e-9) {
                second_score = best.score;
                best.root_pitch_class = @intCast(root);
                best.template_index = @intCast(template_index);
                best.score = score;
            } else if (score > second_score) {
                second_score = score;
            }
        }
    }
    best.margin = best.score - second_score;
    if (best.score < config.minimum_score or
        best.margin < config.minimum_score_margin)
        return error.ChordNotFound;
    return best;
}

fn sameChord(left: ChordCandidate, right: ChordCandidate) bool {
    return left.root_pitch_class == right.root_pitch_class and
        left.bass_pitch_class == right.bass_pitch_class and
        left.template_index == right.template_index;
}

fn chordEvent(
    candidate: ChordCandidate,
    position: f64,
) raw.ARAContentChord {
    return .{
        .root = circle_of_fifths_by_pitch_class[
            candidate.root_pitch_class
        ],
        .bass = circle_of_fifths_by_pitch_class[
            candidate.bass_pitch_class
        ],
        .intervals = chord_templates[
            candidate.template_index
        ].intervals,
        .name = null,
        .position = position,
    };
}

fn undefinedChordEvent(position: f64) raw.ARAContentChord {
    return .{
        .root = 0,
        .bass = 0,
        .intervals = @splat(0),
        .name = null,
        .position = position,
    };
}

pub fn detectKeySignatures(
    notes: []const raw.ARAContentNote,
    tempo_entries: []const raw.ARAContentTempoEntry,
    config: KeySignatureDetectionConfig,
    output: []raw.ARAContentKeySignature,
) Error!usize {
    try validateKeySignatureDetectionConfig(config);
    try validateTempoMapForKeySignatures(tempo_entries);
    if (notes.len == 0)
        return error.KeySignatureNotFound;

    var first_quarter = std.math.inf(f64);
    var last_quarter = -std.math.inf(f64);
    for (notes) |note| {
        if (!validKeyDetectionNote(note))
            return error.KeySignatureNotFound;
        const start = try quarterAtTime(
            tempo_entries,
            note.startPosition,
        );
        const end = try quarterAtTime(
            tempo_entries,
            note.startPosition + note.noteDuration,
        );
        first_quarter = @min(first_quarter, start);
        last_quarter = @max(last_quarter, end);
    }
    if (!std.math.isFinite(first_quarter) or
        !std.math.isFinite(last_quarter) or
        last_quarter <= first_quarter)
        return error.KeySignatureNotFound;

    var staged: [maximum_detected_key_signatures]raw.ARAContentKeySignature =
        undefined;
    var staged_count: usize = 0;
    var current: ?KeyCandidate = null;
    var pending: ?KeyCandidate = null;
    var pending_count: u8 = 0;
    const start_quarter =
        @floor(first_quarter / config.hop_quarters) *
        config.hop_quarters;
    var window_start = start_quarter;
    while (window_start < last_quarter) : (window_start += config.hop_quarters) {
        const candidate = scoreKeyWindow(
            notes,
            tempo_entries,
            window_start,
            window_start + config.window_quarters,
            config,
        ) catch |failure| switch (failure) {
            error.KeySignatureNotFound => continue,
            else => return failure,
        };
        if (current == null) {
            if (staged_count >= staged.len)
                return error.CapacityExceeded;
            staged[staged_count] = keySignatureEvent(
                candidate,
                window_start,
            );
            staged_count += 1;
            current = candidate;
            continue;
        }
        const current_key = current orelse
            return error.InvalidKeyAnalysisState;
        if (sameKey(current_key, candidate)) {
            pending = null;
            pending_count = 0;
            continue;
        }
        if (pending) |pending_key| {
            if (sameKey(pending_key, candidate)) {
                pending_count += 1;
            } else {
                pending = candidate;
                pending_count = 1;
            }
        } else {
            pending = candidate;
            pending_count = 1;
        }
        if (pending_count < config.change_confirmation_windows)
            continue;
        if (staged_count >= staged.len)
            return error.CapacityExceeded;
        const change_position = window_start -
            config.hop_quarters *
                @as(
                    f64,
                    @floatFromInt(
                        config.change_confirmation_windows - 1,
                    ),
                );
        staged[staged_count] = keySignatureEvent(
            pending orelse return error.InvalidKeyAnalysisState,
            change_position,
        );
        staged_count += 1;
        current = pending;
        pending = null;
        pending_count = 0;
    }
    if (staged_count == 0)
        return error.KeySignatureNotFound;
    if (staged_count > output.len)
        return error.CapacityExceeded;
    @memcpy(output[0..staged_count], staged[0..staged_count]);
    return staged_count;
}

fn validateKeySignatureDetectionConfig(
    config: KeySignatureDetectionConfig,
) Error!void {
    if (!std.math.isFinite(config.window_quarters) or
        config.window_quarters <= 0.0 or
        !std.math.isFinite(config.hop_quarters) or
        config.hop_quarters <= 0.0 or
        config.hop_quarters > config.window_quarters or
        !std.math.isFinite(config.minimum_note_weight) or
        config.minimum_note_weight <= 0.0 or
        !std.math.isFinite(config.minimum_score) or
        config.minimum_score < -1.0 or
        config.minimum_score > 1.0 or
        !std.math.isFinite(config.minimum_score_margin) or
        config.minimum_score_margin < 0.0 or
        config.minimum_score_margin > 2.0 or
        config.change_confirmation_windows == 0)
        return error.InvalidConfiguration;
}

fn validateTempoMapForKeySignatures(
    tempo_entries: []const raw.ARAContentTempoEntry,
) Error!void {
    validateTempoMap(tempo_entries) catch |failure| switch (failure) {
        error.InvalidSampleCount => return error.InvalidSampleCount,
        else => return error.KeySignatureNotFound,
    };
}

fn validKeyDetectionNote(note: raw.ARAContentNote) bool {
    return std.math.isFinite(note.volume) and
        std.math.isFinite(note.startPosition) and
        std.math.isFinite(note.noteDuration) and
        note.pitchNumber >= 0 and
        note.pitchNumber <= 127 and
        note.volume >= 0.0 and
        note.noteDuration > 0.0;
}

fn scoreKeyWindow(
    notes: []const raw.ARAContentNote,
    tempo_entries: []const raw.ARAContentTempoEntry,
    window_start: f64,
    window_end: f64,
    config: KeySignatureDetectionConfig,
) Error!KeyCandidate {
    var histogram: [12]f64 = @splat(0.0);
    var total_weight: f64 = 0.0;
    for (notes) |note| {
        const note_start = try quarterAtTime(
            tempo_entries,
            note.startPosition,
        );
        const note_end = try quarterAtTime(
            tempo_entries,
            note.startPosition + note.noteDuration,
        );
        const overlap = @max(
            0.0,
            @min(note_end, window_end) -
                @max(note_start, window_start),
        );
        if (overlap <= 0.0)
            continue;
        const pitch_class: usize =
            @intCast(@mod(note.pitchNumber, 12));
        const weight = overlap * @max(
            @as(f64, note.volume),
            0.05,
        );
        histogram[pitch_class] += weight;
        total_weight += weight;
    }
    if (total_weight < config.minimum_note_weight)
        return error.KeySignatureNotFound;

    var best = KeyCandidate{
        .root_pitch_class = 0,
        .minor = false,
        .score = -2.0,
        .margin = 0.0,
    };
    var second_score: f64 = -2.0;
    for (0..12) |root| {
        const major_score = keyProfileCorrelation(
            histogram,
            major_key_profile,
            root,
        );
        selectKeyCandidate(
            &best,
            &second_score,
            @intCast(root),
            false,
            major_score,
        );
        const minor_score = keyProfileCorrelation(
            histogram,
            minor_key_profile,
            root,
        );
        selectKeyCandidate(
            &best,
            &second_score,
            @intCast(root),
            true,
            minor_score,
        );
    }
    best.margin = best.score - second_score;
    if (best.score < config.minimum_score or
        best.margin < config.minimum_score_margin)
        return error.KeySignatureNotFound;
    return best;
}

fn selectKeyCandidate(
    best: *KeyCandidate,
    second_score: *f64,
    root: u8,
    minor: bool,
    score: f64,
) void {
    if (score > best.score + 1.0e-9) {
        second_score.* = best.score;
        best.* = .{
            .root_pitch_class = root,
            .minor = minor,
            .score = score,
            .margin = 0.0,
        };
    } else if (score > second_score.*) {
        second_score.* = score;
    }
}

fn keyProfileCorrelation(
    histogram: [12]f64,
    profile: [12]f64,
    root: usize,
) f64 {
    var histogram_mean: f64 = 0.0;
    var profile_mean: f64 = 0.0;
    for (0..12) |index| {
        histogram_mean += histogram[index];
        profile_mean += profile[index];
    }
    histogram_mean /= 12.0;
    profile_mean /= 12.0;
    var cross: f64 = 0.0;
    var histogram_energy: f64 = 0.0;
    var profile_energy: f64 = 0.0;
    for (0..12) |index| {
        const histogram_value = histogram[index] - histogram_mean;
        const profile_value =
            profile[@mod(index + 12 - root, 12)] - profile_mean;
        cross += histogram_value * profile_value;
        histogram_energy += histogram_value * histogram_value;
        profile_energy += profile_value * profile_value;
    }
    const denominator = @sqrt(histogram_energy * profile_energy);
    return if (denominator > 0.0)
        cross / denominator
    else
        -1.0;
}

fn sameKey(left: KeyCandidate, right: KeyCandidate) bool {
    return left.root_pitch_class == right.root_pitch_class and
        left.minor == right.minor;
}

pub fn keySignatureEvent(
    candidate: KeyCandidate,
    position: f64,
) raw.ARAContentKeySignature {
    return .{
        .root = circle_of_fifths_by_pitch_class[
            candidate.root_pitch_class
        ],
        .intervals = if (candidate.minor)
            minor_intervals
        else
            major_intervals,
        .name = null,
        .position = position,
    };
}

fn quarterAtTime(
    tempo_entries: []const raw.ARAContentTempoEntry,
    time: f64,
) Error!f64 {
    if (!std.math.isFinite(time))
        return error.KeySignatureNotFound;
    var upper: usize = 1;
    while (upper < tempo_entries.len and
        tempo_entries[upper].timePosition < time)
        upper += 1;
    if (upper >= tempo_entries.len) {
        upper = tempo_entries.len - 1;
    } else if (time < tempo_entries[0].timePosition) {
        upper = 1;
    }
    const lower = tempo_entries[upper - 1];
    const higher = tempo_entries[upper];
    const time_span = higher.timePosition - lower.timePosition;
    if (time_span <= 0.0)
        return error.KeySignatureNotFound;
    const fraction = (time - lower.timePosition) / time_span;
    const quarter = lower.quarterPosition +
        fraction *
            (higher.quarterPosition - lower.quarterPosition);
    if (!std.math.isFinite(quarter))
        return error.KeySignatureNotFound;
    return quarter;
}

pub fn sameTempoMap(
    left: []const raw.ARAContentTempoEntry,
    right: []const raw.ARAContentTempoEntry,
) bool {
    if (left.len != right.len)
        return false;
    for (left, right) |left_entry, right_entry| {
        if (left_entry.timePosition != right_entry.timePosition or
            left_entry.quarterPosition != right_entry.quarterPosition)
            return false;
    }
    return true;
}

pub fn sameNotes(
    left: []const raw.ARAContentNote,
    right: []const raw.ARAContentNote,
) bool {
    if (left.len != right.len)
        return false;
    for (left, right) |left_note, right_note| {
        if (left_note.frequency != right_note.frequency or
            left_note.pitchNumber != right_note.pitchNumber or
            left_note.volume != right_note.volume or
            left_note.startPosition != right_note.startPosition or
            left_note.attackDuration != right_note.attackDuration or
            left_note.noteDuration != right_note.noteDuration or
            left_note.signalDuration != right_note.signalDuration)
            return false;
    }
    return true;
}
