const std = @import("std");
const analysis_common = @import("ara_analysis_common.zig");
const analysis_model = @import("ara_analysis_model.zig");
const controller_api = @import("ara_document_controller.zig");
const harmony_analysis = @import("ara_harmony_analysis.zig");
const note_analysis = @import("ara_note_analysis.zig");
const tempo_analysis = @import("ara_tempo_analysis.zig");
const tuning_detector = @import("ara_tuning_detector.zig");

pub const raw = analysis_model.raw;
const maximum_supported_sample_rate =
    analysis_model.maximum_supported_sample_rate;
pub const Error = analysis_model.Error;
pub const DetectionConfig = analysis_model.DetectionConfig;
pub const Detection = analysis_model.Detection;
pub const TempoDetectionConfig = analysis_model.TempoDetectionConfig;
pub const TempoDetection = analysis_model.TempoDetection;
pub const maximum_detected_tempo_entries =
    analysis_model.maximum_detected_tempo_entries;
pub const maximum_detected_bar_signatures =
    analysis_model.maximum_detected_bar_signatures;
pub const maximum_detected_key_signatures =
    analysis_model.maximum_detected_key_signatures;
pub const maximum_detected_chords =
    analysis_model.maximum_detected_chords;
pub const maximum_meter_pulses = analysis_model.maximum_meter_pulses;
pub const maximum_detected_notes =
    analysis_model.maximum_detected_notes;
pub const maximum_note_window_samples =
    analysis_model.maximum_note_window_samples;
pub const MeterDetectionConfig = analysis_model.MeterDetectionConfig;
pub const KeySignatureDetectionConfig =
    analysis_model.KeySignatureDetectionConfig;
pub const ChordDetectionConfig = analysis_model.ChordDetectionConfig;
pub const NoteDetectionConfig = analysis_model.NoteDetectionConfig;
pub const Limits = analysis_model.Limits;
pub const detectChords = harmony_analysis.detectChords;
pub const detectKeySignatures = harmony_analysis.detectKeySignatures;
pub const detectTempoEnvelope = tempo_analysis.detectTempoEnvelope;
pub const detectTempoMapEnvelope = tempo_analysis.detectTempoMapEnvelope;
pub const detectBarSignaturesEnvelope =
    tempo_analysis.detectBarSignaturesEnvelope;
pub const detectPolyphonicNotes = note_analysis.detectPolyphonicNotes;
pub const detectEqualTemperament =
    tuning_detector.detectEqualTemperament;
const boundedSearchIndex = analysis_common.boundedSearchIndex;
const chord_templates = harmony_analysis.chord_templates;
const keySignatureEvent = harmony_analysis.keySignatureEvent;
const major_intervals = harmony_analysis.major_intervals;
const MeterCandidate = tempo_analysis.MeterCandidate;
const meter_candidates = tempo_analysis.meter_candidates;
const meterTemplate = tempo_analysis.meterTemplate;
const mergeDetectedNote = note_analysis.mergeDetectedNote;
const minor_intervals = harmony_analysis.minor_intervals;
const noteIntersectsRange = note_analysis.noteIntersectsRange;
const noteLessThan = note_analysis.noteLessThan;
const pitchFrequency = note_analysis.pitchFrequency;
const sameNotes = harmony_analysis.sameNotes;
const sameTempoMap = harmony_analysis.sameTempoMap;
const validateTempoMap = analysis_common.validateTempoMap;

fn validArchivedNote(note: raw.ARAContentNote) bool {
    const pitch_valid =
        note.pitchNumber >= 0 and note.pitchNumber <= 127;
    const pitch_invalid =
        note.pitchNumber == std.math.minInt(i32);
    const frequency_valid =
        std.math.isFinite(note.frequency) and
        note.frequency > 0.0 and
        note.frequency <= maximum_supported_sample_rate * 0.5;
    const frequency_invalid = note.frequency == 0.0;
    return ((pitch_valid and frequency_valid) or
        (pitch_invalid and frequency_invalid)) and
        std.math.isFinite(note.volume) and
        note.volume >= 0.0 and
        note.volume <= 1.0 and
        std.math.isFinite(note.startPosition) and
        note.startPosition >= 0.0 and
        std.math.isFinite(note.attackDuration) and
        note.attackDuration >= 0.0 and
        std.math.isFinite(note.noteDuration) and
        note.noteDuration >= note.attackDuration and
        std.math.isFinite(note.signalDuration) and
        note.signalDuration >= note.noteDuration and
        note.signalDuration > 0.0;
}

fn validArchivedBarSignature(
    signature: raw.ARAContentBarSignature,
    previous: ?raw.ARAContentBarSignature,
) bool {
    if (signature.numerator <= 0 or
        signature.numerator > 64 or
        signature.denominator <= 0 or
        signature.denominator > 64 or
        !std.math.isPowerOfTwo(
            @as(u32, @intCast(signature.denominator)),
        ) or
        !std.math.isFinite(signature.position))
        return false;
    const prior = previous orelse return true;
    if (signature.position <= prior.position)
        return false;
    const prior_bar_length =
        @as(f64, @floatFromInt(prior.numerator)) * 4.0 /
        @as(f64, @floatFromInt(prior.denominator));
    const bar_count =
        (signature.position - prior.position) / prior_bar_length;
    return std.math.isFinite(bar_count) and
        bar_count >= 1.0 and
        @abs(bar_count - @round(bar_count)) <= 1.0e-7;
}

fn validArchivedKeySignature(
    signature: raw.ARAContentKeySignature,
    previous: ?raw.ARAContentKeySignature,
) bool {
    if (signature.root < -32 or
        signature.root > 32 or
        !std.math.isFinite(signature.position) or
        signature.name != null)
        return false;
    var used_count: usize = 0;
    for (signature.intervals) |usage| {
        if (usage != 0 and usage != 0xff)
            return false;
        if (usage == 0xff)
            used_count += 1;
    }
    if (used_count == 0)
        return false;
    if (previous) |prior| {
        if (signature.position <= prior.position)
            return false;
    }
    return true;
}

fn validArchivedChord(
    chord: raw.ARAContentChord,
    previous: ?raw.ARAContentChord,
) bool {
    if (chord.root < -32 or
        chord.root > 32 or
        chord.bass < -32 or
        chord.bass > 32 or
        !std.math.isFinite(chord.position) or
        chord.name != null)
        return false;
    for (chord.intervals) |usage| {
        switch (usage) {
            0, 1, 2, 3, 4, 5, 6, 7, 9, 11, 13, 0xff => {},
            else => return false,
        }
    }
    if (previous) |prior| {
        if (chord.position <= prior.position)
            return false;
    }
    return true;
}

pub fn Analyzer(
    comptime ControllerType: type,
    comptime limits: Limits,
) type {
    if (limits.sources == 0 or
        limits.sources > std.math.maxInt(u16) or
        limits.channels == 0 or
        limits.frames < 8 or
        limits.name_bytes == 0 or
        limits.name_bytes > std.math.maxInt(u16) or
        limits.tempo_bins < 8 or
        limits.tempo_entries < 2 or
        limits.tempo_entries >
            maximum_detected_tempo_entries or
        limits.bar_signatures == 0 or
        limits.bar_signatures >
            maximum_detected_bar_signatures or
        limits.key_signatures == 0 or
        limits.key_signatures >
            maximum_detected_key_signatures or
        limits.chords == 0 or
        limits.chords > maximum_detected_chords or
        limits.note_entries == 0 or
        limits.note_entries > maximum_detected_notes)
        @compileError(
            "ARA tuning analysis limits must fit archive and detection capacities",
        );

    const SourceId = @FieldType(
        ControllerType.ContentObject,
        "audio_source",
    );

    return struct {
        const Self = @This();
        pub const processing_algorithm_count = 2;
        pub const general_algorithm_index = 0;
        pub const low_register_algorithm_index = 1;

        const Status = enum {
            empty,
            pending,
            unavailable,
            detected,
            approved,
        };

        const Slot = struct {
            source_id: ?SourceId = null,
            status: Status = .empty,
            tuning: raw.ARAContentTuning =
                std.mem.zeroes(raw.ARAContentTuning),
            name: [limits.name_bytes + 1]u8 = @splat(0),
            processing_algorithm: u8 = general_algorithm_index,
            tempo_status: Status = .empty,
            tempo_entries: [limits.tempo_entries]raw.ARAContentTempoEntry =
                @splat(.{
                    .timePosition = 0.0,
                    .quarterPosition = 0.0,
                }),
            tempo_entry_count: u8 = 0,
            meter_status: Status = .empty,
            bar_signatures: [limits.bar_signatures]raw.ARAContentBarSignature =
                @splat(.{
                    .numerator = 0,
                    .denominator = 0,
                    .position = 0.0,
                }),
            bar_signature_count: u8 = 0,
            key_status: Status = .empty,
            key_signatures: [limits.key_signatures]raw.ARAContentKeySignature =
                @splat(.{
                    .root = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                }),
            key_signature_count: u8 = 0,
            chord_status: Status = .empty,
            chords: [limits.chords]raw.ARAContentChord =
                @splat(.{
                    .root = 0,
                    .bass = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                }),
            chord_count: u16 = 0,
            note_status: Status = .empty,
            notes: [limits.note_entries]raw.ARAContentNote =
                @splat(std.mem.zeroes(raw.ARAContentNote)),
            note_count: u16 = 0,
        };

        const TempoMapResult = struct {
            detection: TempoDetection,
            entry_count: usize,
            envelope_count: usize,
            envelope_rate: f64,
        };

        const processing_algorithms =
            [processing_algorithm_count]raw.ARAProcessingAlgorithmProperties{
                .{
                    .structSize = @sizeOf(
                        raw.ARAProcessingAlgorithmProperties,
                    ),
                    .persistentID = "dev.zig-vst3.analysis.general",
                    .name = "General music analysis",
                },
                .{
                    .structSize = @sizeOf(
                        raw.ARAProcessingAlgorithmProperties,
                    ),
                    .persistentID = "dev.zig-vst3.analysis.low-register",
                    .name = "Low-register music analysis",
                },
            };

        controller: *ControllerType,
        slots: [limits.sources]Slot = @splat(.{}),
        channel_samples: [limits.channels][limits.frames]f64 =
            @splat(@splat(0)),
        mono_samples: [limits.frames]f64 = @splat(0),
        tempo_energy: [limits.channels][limits.tempo_bins]f64 =
            @splat(@splat(0)),
        tempo_onsets: [limits.tempo_bins]f64 = @splat(0),
        detection_config: DetectionConfig = .{},
        tempo_detection_config: TempoDetectionConfig = .{},
        meter_detection_config: MeterDetectionConfig = .{},
        key_signature_detection_config: KeySignatureDetectionConfig = .{},
        chord_detection_config: ChordDetectionConfig = .{},
        note_detection_config: NoteDetectionConfig = .{},
        last_error: ?Error = null,

        pub fn init(controller: *ControllerType) Self {
            return .{ .controller = controller };
        }

        pub fn attach(self: *Self) Error!void {
            try self.controller.setContentProvider(.{
                .context = @ptrCast(self),
                .vtable = &vtable,
            });
        }

        pub fn detach(self: *Self) Error!void {
            try self.controller.setContentProvider(null);
        }

        pub fn takeLastError(self: *Self) ?Error {
            const failure = self.last_error;
            self.last_error = null;
            return failure;
        }

        pub fn analyze(
            self: *Self,
            source_id: SourceId,
        ) Error!Detection {
            const slot = try self.slotFor(source_id);
            slot.status = .pending;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            const result = self.detectSource(source_id) catch |failure| {
                slot.status = .unavailable;
                self.finishAnalysis(source_id);
                return failure;
            };
            setTuning(slot, result.concert_pitch, .detected, "Detected equal temperament");
            self.finishAnalysis(source_id);
            return result;
        }

        pub fn analyzeTempo(
            self: *Self,
            source_id: SourceId,
        ) Error!TempoDetection {
            const slot = try self.slotFor(source_id);
            slot.tempo_status = .pending;
            slot.meter_status = .empty;
            slot.bar_signature_count = 0;
            slot.key_status = .empty;
            slot.key_signature_count = 0;
            slot.chord_status = .empty;
            slot.chord_count = 0;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            const result = self.detectSourceTempo(
                source_id,
                &slot.tempo_entries,
            ) catch |failure| {
                slot.tempo_status = .unavailable;
                slot.tempo_entry_count = 0;
                self.finishTempoAnalysis(source_id);
                return failure;
            };
            slot.tempo_entry_count =
                @intCast(result.entry_count);
            slot.tempo_status = .detected;
            self.finishTempoAnalysis(source_id);
            return result.detection;
        }

        pub fn analyzeMeter(
            self: *Self,
            source_id: SourceId,
        ) Error!usize {
            const slot = try self.slotFor(source_id);
            slot.meter_status = .pending;
            slot.key_status = .empty;
            slot.key_signature_count = 0;
            slot.chord_status = .empty;
            slot.chord_count = 0;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            var staged_tempo: [limits.tempo_entries]raw.ARAContentTempoEntry =
                undefined;
            const tempo_result = self.detectSourceTempo(
                source_id,
                &staged_tempo,
            ) catch |failure| {
                slot.meter_status = .unavailable;
                slot.bar_signature_count = 0;
                self.finishMeterAnalysis(source_id);
                return failure;
            };
            var staged_signatures: [limits.bar_signatures]raw.ARAContentBarSignature =
                undefined;
            const signature_count =
                detectBarSignaturesEnvelope(
                    self.tempo_onsets[0..tempo_result.envelope_count],
                    tempo_result.envelope_rate,
                    staged_tempo[0..tempo_result.entry_count],
                    self.meter_detection_config,
                    &staged_signatures,
                ) catch |failure| {
                    slot.meter_status = .unavailable;
                    slot.bar_signature_count = 0;
                    self.finishMeterAnalysis(source_id);
                    return failure;
                };
            @memcpy(
                slot.tempo_entries[0..tempo_result.entry_count],
                staged_tempo[0..tempo_result.entry_count],
            );
            slot.tempo_entry_count =
                @intCast(tempo_result.entry_count);
            slot.tempo_status = .detected;
            @memcpy(
                slot.bar_signatures[0..signature_count],
                staged_signatures[0..signature_count],
            );
            slot.bar_signature_count = @intCast(signature_count);
            slot.meter_status = .detected;
            self.finishMeterAnalysis(source_id);
            return signature_count;
        }

        pub fn analyzeNotes(
            self: *Self,
            source_id: SourceId,
        ) Error!usize {
            const slot = try self.slotFor(source_id);
            slot.note_status = .pending;
            slot.key_status = .empty;
            slot.key_signature_count = 0;
            slot.chord_status = .empty;
            slot.chord_count = 0;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            const note_count = self.detectSourceNotes(
                source_id,
                &slot.notes,
            ) catch |failure| {
                slot.note_status = .unavailable;
                slot.note_count = 0;
                self.finishNoteAnalysis(source_id);
                return failure;
            };
            slot.note_count = @intCast(note_count);
            slot.note_status = .detected;
            self.finishNoteAnalysis(source_id);
            return note_count;
        }

        pub fn analyzeKeySignatures(
            self: *Self,
            source_id: SourceId,
        ) Error!usize {
            const slot = try self.slotFor(source_id);
            slot.key_status = .pending;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            var staged_notes: [limits.note_entries]raw.ARAContentNote =
                undefined;
            const note_count = self.detectSourceNotes(
                source_id,
                &staged_notes,
            ) catch |failure| {
                slot.key_status = .unavailable;
                slot.key_signature_count = 0;
                self.finishKeySignatureAnalysis(source_id);
                return failure;
            };
            var staged_tempo: [limits.tempo_entries]raw.ARAContentTempoEntry =
                undefined;
            const tempo_result = self.detectSourceTempo(
                source_id,
                &staged_tempo,
            ) catch |failure| {
                slot.key_status = .unavailable;
                slot.key_signature_count = 0;
                self.finishKeySignatureAnalysis(source_id);
                return failure;
            };
            var staged_keys: [limits.key_signatures]raw.ARAContentKeySignature =
                undefined;
            const key_count = detectKeySignatures(
                staged_notes[0..note_count],
                staged_tempo[0..tempo_result.entry_count],
                self.key_signature_detection_config,
                &staged_keys,
            ) catch |failure| {
                slot.key_status = .unavailable;
                slot.key_signature_count = 0;
                self.finishKeySignatureAnalysis(source_id);
                return failure;
            };
            if (!sameNotes(
                slot.notes[0..slot.note_count],
                staged_notes[0..note_count],
            )) {
                slot.chord_status = .empty;
                slot.chord_count = 0;
            }
            @memcpy(
                slot.notes[0..note_count],
                staged_notes[0..note_count],
            );
            slot.note_count = @intCast(note_count);
            slot.note_status = .detected;
            if (!sameTempoMap(
                slot.tempo_entries[0..slot.tempo_entry_count],
                staged_tempo[0..tempo_result.entry_count],
            )) {
                slot.meter_status = .empty;
                slot.bar_signature_count = 0;
                slot.chord_status = .empty;
                slot.chord_count = 0;
            }
            @memcpy(
                slot.tempo_entries[0..tempo_result.entry_count],
                staged_tempo[0..tempo_result.entry_count],
            );
            slot.tempo_entry_count = @intCast(tempo_result.entry_count);
            slot.tempo_status = .detected;
            @memcpy(
                slot.key_signatures[0..key_count],
                staged_keys[0..key_count],
            );
            slot.key_signature_count = @intCast(key_count);
            slot.key_status = .detected;
            self.finishKeySignatureAnalysis(source_id);
            return key_count;
        }

        pub fn analyzeChords(
            self: *Self,
            source_id: SourceId,
        ) Error!usize {
            const slot = try self.slotFor(source_id);
            slot.chord_status = .pending;
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressStarted,
                0.0,
            ) catch {};
            var staged_notes: [limits.note_entries]raw.ARAContentNote =
                undefined;
            const note_count = self.detectSourceNotes(
                source_id,
                &staged_notes,
            ) catch |failure| {
                slot.chord_status = .unavailable;
                slot.chord_count = 0;
                self.finishChordAnalysis(source_id);
                return failure;
            };
            var staged_tempo: [limits.tempo_entries]raw.ARAContentTempoEntry =
                undefined;
            const tempo_result = self.detectSourceTempo(
                source_id,
                &staged_tempo,
            ) catch |failure| {
                slot.chord_status = .unavailable;
                slot.chord_count = 0;
                self.finishChordAnalysis(source_id);
                return failure;
            };
            var staged_chords: [limits.chords]raw.ARAContentChord =
                undefined;
            const chord_count = detectChords(
                staged_notes[0..note_count],
                staged_tempo[0..tempo_result.entry_count],
                self.chord_detection_config,
                &staged_chords,
            ) catch |failure| {
                slot.chord_status = .unavailable;
                slot.chord_count = 0;
                self.finishChordAnalysis(source_id);
                return failure;
            };
            if (!sameNotes(
                slot.notes[0..slot.note_count],
                staged_notes[0..note_count],
            )) {
                slot.key_status = .empty;
                slot.key_signature_count = 0;
            }
            @memcpy(
                slot.notes[0..note_count],
                staged_notes[0..note_count],
            );
            slot.note_count = @intCast(note_count);
            slot.note_status = .detected;
            if (!sameTempoMap(
                slot.tempo_entries[0..slot.tempo_entry_count],
                staged_tempo[0..tempo_result.entry_count],
            )) {
                slot.meter_status = .empty;
                slot.bar_signature_count = 0;
                slot.key_status = .empty;
                slot.key_signature_count = 0;
            }
            @memcpy(
                slot.tempo_entries[0..tempo_result.entry_count],
                staged_tempo[0..tempo_result.entry_count],
            );
            slot.tempo_entry_count = @intCast(tempo_result.entry_count);
            slot.tempo_status = .detected;
            @memcpy(
                slot.chords[0..chord_count],
                staged_chords[0..chord_count],
            );
            slot.chord_count = @intCast(chord_count);
            slot.chord_status = .detected;
            self.finishChordAnalysis(source_id);
            return chord_count;
        }

        pub fn approveEqualTemperament(
            self: *Self,
            source_id: SourceId,
            concert_pitch: f64,
            name: []const u8,
        ) Error!void {
            if (!std.math.isFinite(concert_pitch) or
                concert_pitch < 300.0 or
                concert_pitch > 500.0)
                return error.InvalidConcertPitch;
            const slot = try self.slotFor(source_id);
            if (name.len > limits.name_bytes)
                return error.NameTooLong;
            setTuning(slot, concert_pitch, .approved, name);
            try self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_tuning,
            );
        }

        pub fn invalidate(
            self: *Self,
            source_id: SourceId,
        ) void {
            const slot = self.findSlot(source_id) orelse return;
            slot.status = .empty;
            slot.source_id = null;
            slot.tuning = std.mem.zeroes(raw.ARAContentTuning);
            slot.tempo_status = .empty;
            slot.tempo_entry_count = 0;
            slot.tempo_entries = @splat(.{
                .timePosition = 0.0,
                .quarterPosition = 0.0,
            });
            slot.meter_status = .empty;
            slot.bar_signature_count = 0;
            slot.bar_signatures = @splat(.{
                .numerator = 0,
                .denominator = 0,
                .position = 0.0,
            });
            slot.key_status = .empty;
            slot.key_signature_count = 0;
            slot.key_signatures = @splat(.{
                .root = 0,
                .intervals = @splat(0),
                .name = null,
                .position = 0.0,
            });
            slot.chord_status = .empty;
            slot.chord_count = 0;
            slot.chords = @splat(.{
                .root = 0,
                .bass = 0,
                .intervals = @splat(0),
                .name = null,
                .position = 0.0,
            });
            slot.note_status = .empty;
            slot.note_count = 0;
            slot.notes = @splat(std.mem.zeroes(raw.ARAContentNote));
            @memset(&slot.name, 0);
        }

        fn detectSource(
            self: *Self,
            source_id: SourceId,
        ) Error!Detection {
            const slot = self.findSlot(source_id) orelse
                return error.InvalidHandle;
            const source =
                self.controller.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if (!std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0.0 or
                source.sample_rate > maximum_supported_sample_rate)
                return error.InvalidSampleRate;
            if (source.channel_count <= 0 or
                source.channel_count > limits.channels)
                return error.InvalidChannelCount;
            if (source.sample_count < 8)
                return error.InvalidSampleCount;
            const frame_count: usize = @min(
                limits.frames,
                @as(usize, @intCast(source.sample_count)),
            );
            const channel_count: usize =
                @intCast(source.channel_count);
            var buffers: [limits.channels][]f64 = undefined;
            for (0..channel_count) |channel| {
                buffers[channel] =
                    self.channel_samples[channel][0..frame_count];
            }
            var reader =
                try self.controller.openAudioReader(source_id, true);
            defer reader.close();
            try reader.readF64(0, buffers[0..channel_count]);

            var selected_channel: usize = 0;
            var selected_energy: f64 = -1.0;
            for (0..channel_count) |channel| {
                var mean: f64 = 0.0;
                for (self.channel_samples[channel][0..frame_count]) |
                    sample,
                | {
                    if (!std.math.isFinite(sample))
                        return error.PitchNotFound;
                    mean += sample;
                }
                mean /= @floatFromInt(frame_count);
                var energy: f64 = 0.0;
                for (self.channel_samples[channel][0..frame_count]) |
                    sample,
                | {
                    const centered = sample - mean;
                    energy += centered * centered;
                }
                if (energy > selected_energy) {
                    selected_energy = energy;
                    selected_channel = channel;
                }
            }
            @memcpy(
                self.mono_samples[0..frame_count],
                self.channel_samples[selected_channel][0..frame_count],
            );
            return detectEqualTemperament(
                self.mono_samples[0..frame_count],
                source.sample_rate,
                self.configForAlgorithm(slot.processing_algorithm),
            );
        }

        fn configForAlgorithm(
            self: *const Self,
            algorithm: u8,
        ) DetectionConfig {
            return switch (algorithm) {
                low_register_algorithm_index => .{
                    .minimum_frequency = 25.0,
                    .maximum_frequency = 500.0,
                    .minimum_rms = self.detection_config.minimum_rms,
                    .minimum_correlation = @max(
                        self.detection_config.minimum_correlation,
                        0.85,
                    ),
                },
                else => self.detection_config,
            };
        }

        fn detectSourceTempo(
            self: *Self,
            source_id: SourceId,
            output: []raw.ARAContentTempoEntry,
        ) Error!TempoMapResult {
            const source =
                self.controller.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if (!std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0.0 or
                source.sample_rate > maximum_supported_sample_rate)
                return error.InvalidSampleRate;
            if (source.channel_count <= 0 or
                source.channel_count > limits.channels)
                return error.InvalidChannelCount;
            if (source.sample_count <= 0)
                return error.InvalidSampleCount;

            const target_envelope_rate = 200.0;
            const frames_per_bin: usize = @max(
                @as(usize, 1),
                @as(usize, @intFromFloat(@round(
                    source.sample_rate / target_envelope_rate,
                ))),
            );
            const maximum_frames =
                std.math.mul(
                    usize,
                    limits.tempo_bins,
                    frames_per_bin,
                ) catch return error.InvalidSampleCount;
            const source_frames: usize = @min(
                maximum_frames,
                std.math.cast(
                    usize,
                    source.sample_count,
                ) orelse return error.InvalidSampleCount,
            );
            const bin_count = @min(
                limits.tempo_bins,
                (source_frames + frames_per_bin - 1) /
                    frames_per_bin,
            );
            if (bin_count < 4)
                return error.InvalidSampleCount;
            const channel_count: usize =
                @intCast(source.channel_count);
            for (0..channel_count) |channel|
                @memset(
                    self.tempo_energy[channel][0..bin_count],
                    0.0,
                );

            var reader =
                try self.controller.openAudioReader(source_id, true);
            defer reader.close();
            var offset: usize = 0;
            while (offset < source_frames) {
                const frame_count =
                    @min(limits.frames, source_frames - offset);
                var buffers: [limits.channels][]f64 = undefined;
                for (0..channel_count) |channel|
                    buffers[channel] =
                        self.channel_samples[channel][0..frame_count];
                try reader.readF64(
                    @intCast(offset),
                    buffers[0..channel_count],
                );
                for (0..frame_count) |local_frame| {
                    const bin =
                        (offset + local_frame) / frames_per_bin;
                    for (0..channel_count) |channel| {
                        const sample =
                            self.channel_samples[channel][local_frame];
                        if (!std.math.isFinite(sample))
                            return error.TempoNotFound;
                        self.tempo_energy[channel][bin] +=
                            sample * sample;
                    }
                }
                offset += frame_count;
            }

            var selected_channel: usize = 0;
            var selected_energy: f64 = -1.0;
            for (0..channel_count) |channel| {
                var total: f64 = 0.0;
                for (self.tempo_energy[channel][0..bin_count]) |
                    energy,
                | total += energy;
                if (total > selected_energy) {
                    selected_energy = total;
                    selected_channel = channel;
                }
            }
            for (0..bin_count) |bin| {
                const first_frame = bin * frames_per_bin;
                const frames_in_bin = @min(
                    frames_per_bin,
                    source_frames - first_frame,
                );
                self.tempo_energy[selected_channel][bin] =
                    @sqrt(
                        self.tempo_energy[selected_channel][bin] /
                            @as(f64, @floatFromInt(frames_in_bin)),
                    );
            }
            self.tempo_onsets[0] =
                self.tempo_energy[selected_channel][0];
            for (1..bin_count) |bin| {
                self.tempo_onsets[bin] = @max(
                    0.0,
                    self.tempo_energy[selected_channel][bin] -
                        self.tempo_energy[selected_channel][bin - 1],
                );
            }
            const envelope = self.tempo_onsets[0..bin_count];
            const envelope_rate =
                source.sample_rate /
                @as(f64, @floatFromInt(frames_per_bin));
            const detection = try detectTempoEnvelope(
                envelope,
                envelope_rate,
                self.tempo_detection_config,
            );
            const entry_count = try detectTempoMapEnvelope(
                envelope,
                envelope_rate,
                self.tempo_detection_config,
                output,
            );
            return .{
                .detection = detection,
                .entry_count = entry_count,
                .envelope_count = bin_count,
                .envelope_rate = envelope_rate,
            };
        }

        fn detectSourceNotes(
            self: *Self,
            source_id: SourceId,
            output: []raw.ARAContentNote,
        ) Error!usize {
            const source =
                self.controller.document.audioSource(source_id) orelse
                return error.InvalidHandle;
            if (!std.math.isFinite(source.sample_rate) or
                source.sample_rate <= 0.0 or
                source.sample_rate > maximum_supported_sample_rate)
                return error.InvalidSampleRate;
            if (source.channel_count <= 0 or
                source.channel_count > limits.channels)
                return error.InvalidChannelCount;
            if (source.sample_count <= 0 or
                source.sample_count > limits.frames)
                return error.CapacityExceeded;
            const frame_count: usize =
                @intCast(source.sample_count);
            const channel_count: usize =
                @intCast(source.channel_count);
            var buffers: [limits.channels][]f64 = undefined;
            for (0..channel_count) |channel| {
                buffers[channel] =
                    self.channel_samples[channel][0..frame_count];
            }
            var reader =
                try self.controller.openAudioReader(source_id, true);
            defer reader.close();
            try reader.readF64(0, buffers[0..channel_count]);

            var staged: [maximum_detected_notes]raw.ARAContentNote =
                undefined;
            var staged_count: usize = 0;
            var channel_notes: [maximum_detected_notes]raw.ARAContentNote = undefined;
            for (0..channel_count) |channel| {
                const channel_count_detected =
                    try detectPolyphonicNotes(
                        self.channel_samples[channel][0..frame_count],
                        source.sample_rate,
                        self.note_detection_config,
                        &channel_notes,
                    );
                for (channel_notes[0..channel_count_detected]) |
                    candidate,
                | {
                    try mergeDetectedNote(
                        &staged,
                        &staged_count,
                        candidate,
                    );
                }
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

        fn finishAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_tuning,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn finishTempoAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_timing_and_harmonic,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn finishMeterAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_timing_and_harmonic,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn finishNoteAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_notes_and_harmonic,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn finishKeySignatureAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_notes_timing_and_harmonic,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn finishChordAnalysis(
            self: *Self,
            source_id: SourceId,
        ) void {
            self.controller.notifyAudioSourceAnalysisProgress(
                source_id,
                raw.kARAAnalysisProgressCompleted,
                1.0,
            ) catch {};
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_notes_timing_and_harmonic,
            ) catch |failure| {
                self.last_error = failure;
            };
        }

        fn slotFor(self: *Self, source_id: SourceId) Error!*Slot {
            if (self.controller.document.audioSource(source_id) == null)
                return error.InvalidHandle;
            if (self.findSlot(source_id)) |slot| return slot;
            for (&self.slots) |*slot| {
                if (slot.source_id != null) continue;
                slot.* = .{ .source_id = source_id };
                return slot;
            }
            return error.CapacityExceeded;
        }

        fn findSlot(
            self: *Self,
            source_id: SourceId,
        ) ?*Slot {
            for (&self.slots) |*slot| {
                const candidate = slot.source_id orelse continue;
                if (sameSource(candidate, source_id)) return slot;
            }
            return null;
        }

        fn setTuning(
            slot: *Slot,
            concert_pitch: f64,
            status: Status,
            name: []const u8,
        ) void {
            slot.status = status;
            slot.tuning = std.mem.zeroes(raw.ARAContentTuning);
            slot.tuning.concertPitchFrequency =
                @floatCast(concert_pitch);
            slot.tuning.root = 0;
            @memset(&slot.name, 0);
            @memcpy(slot.name[0..name.len], name);
        }

        fn sameSource(left: SourceId, right: SourceId) bool {
            return left.index == right.index and
                left.generation == right.generation;
        }

        fn nameLength(slot: *const Slot) usize {
            return std.mem.indexOfScalar(
                u8,
                &slot.name,
                0,
            ) orelse limits.name_bytes;
        }

        fn fromContext(context: ?*anyopaque) ?*Self {
            const pointer = context orelse return null;
            return @ptrCast(@alignCast(pointer));
        }

        fn archiveSize(
            context: ?*anyopaque,
            source_ids: []const SourceId,
        ) usize {
            if (source_ids.len == 0) return 0;
            const self = fromContext(context) orelse return 0;
            var size: usize = archive_header_size;
            for (source_ids) |source_id| {
                const slot = self.findSlot(source_id) orelse continue;
                if (!slotNeedsArchive(slot))
                    continue;
                const record_size = archive_record_fixed_size +|
                    nameLength(slot) +|
                    @as(usize, slot.tempo_entry_count) *| 16 +|
                    @as(usize, slot.bar_signature_count) *|
                        archive_bar_signature_size +|
                    @as(usize, slot.note_count) *|
                        archive_note_size +|
                    @as(usize, slot.key_signature_count) *|
                        archive_key_signature_size +|
                    @as(usize, slot.chord_count) *|
                        archive_chord_size;
                size +|= record_size;
            }
            return size;
        }

        fn storeArchive(
            context: ?*anyopaque,
            source_ids: []const SourceId,
            destination: []u8,
        ) bool {
            const self = fromContext(context) orelse return false;
            return self.storeArchiveChecked(
                source_ids,
                destination,
            ) catch |failure| {
                self.last_error = failure;
                return false;
            };
        }

        fn storeArchiveChecked(
            self: *Self,
            source_ids: []const SourceId,
            destination: []u8,
        ) Error!bool {
            if (destination.len != archiveSize(
                @ptrCast(self),
                source_ids,
            ))
                return error.InvalidArchive;
            var writer = ByteWriter.init(destination);
            try writer.bytes(&analysis_archive_magic);
            try writer.byte(analysis_archive_version);
            var record_count: usize = 0;
            for (source_ids) |source_id| {
                const slot = self.findSlot(source_id) orelse continue;
                if (slotNeedsArchive(slot))
                    record_count += 1;
            }
            if (record_count > std.math.maxInt(u16))
                return error.ArchiveTooLarge;
            try writer.integer16(@intCast(record_count));
            for (source_ids, 0..) |source_id, source_index| {
                const slot = self.findSlot(source_id) orelse continue;
                if (!slotNeedsArchive(slot))
                    continue;
                if (source_index > std.math.maxInt(u16))
                    return error.ArchiveTooLarge;
                try writer.integer16(@intCast(source_index));
                try writer.byte(switch (slot.status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.byte(slot.processing_algorithm);
                try writer.integer32(@bitCast(
                    slot.tuning.concertPitchFrequency,
                ));
                const name_length = nameLength(slot);
                try writer.integer16(@intCast(name_length));
                try writer.bytes(slot.name[0..name_length]);
                try writer.byte(switch (slot.tempo_status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.integer16(slot.tempo_entry_count);
                for (slot.tempo_entries[0..slot.tempo_entry_count]) |
                    entry,
                | {
                    try writer.integer64(@bitCast(
                        entry.timePosition,
                    ));
                    try writer.integer64(@bitCast(
                        entry.quarterPosition,
                    ));
                }
                try writer.byte(switch (slot.meter_status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.integer16(slot.bar_signature_count);
                for (
                    slot.bar_signatures[0..slot.bar_signature_count],
                ) |signature| {
                    try writer.integer32(@bitCast(
                        signature.numerator,
                    ));
                    try writer.integer32(@bitCast(
                        signature.denominator,
                    ));
                    try writer.integer64(@bitCast(
                        signature.position,
                    ));
                }
                try writer.byte(switch (slot.note_status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.integer16(slot.note_count);
                for (slot.notes[0..slot.note_count]) |note| {
                    try writer.integer32(@bitCast(note.frequency));
                    try writer.integer32(@bitCast(note.pitchNumber));
                    try writer.integer32(@bitCast(note.volume));
                    try writer.integer64(@bitCast(
                        note.startPosition,
                    ));
                    try writer.integer64(@bitCast(
                        note.attackDuration,
                    ));
                    try writer.integer64(@bitCast(
                        note.noteDuration,
                    ));
                    try writer.integer64(@bitCast(
                        note.signalDuration,
                    ));
                }
                try writer.byte(switch (slot.key_status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.integer16(slot.key_signature_count);
                for (
                    slot.key_signatures[0..slot.key_signature_count],
                ) |signature| {
                    try writer.integer32(@bitCast(signature.root));
                    try writer.bytes(&signature.intervals);
                    try writer.integer64(@bitCast(signature.position));
                }
                try writer.byte(switch (slot.chord_status) {
                    .detected => 1,
                    .approved => 2,
                    else => 0,
                });
                try writer.integer16(slot.chord_count);
                for (slot.chords[0..slot.chord_count]) |chord| {
                    try writer.integer32(@bitCast(chord.root));
                    try writer.integer32(@bitCast(chord.bass));
                    try writer.bytes(&chord.intervals);
                    try writer.integer64(@bitCast(chord.position));
                }
            }
            if (!writer.finished()) return error.InvalidArchive;
            return true;
        }

        fn restoreArchive(
            context: ?*anyopaque,
            mappings: []const ControllerType.ArchiveSourceMapping,
            bytes: []const u8,
        ) bool {
            const self = fromContext(context) orelse return false;
            self.restoreArchiveChecked(mappings, bytes) catch |failure| {
                self.last_error = failure;
                return false;
            };
            return true;
        }

        fn restoreArchiveChecked(
            self: *Self,
            mappings: []const ControllerType.ArchiveSourceMapping,
            bytes: []const u8,
        ) Error!void {
            var reader = ByteReader.init(bytes);
            const magic =
                try reader.bytes(analysis_archive_magic.len);
            if (!std.mem.eql(u8, magic, &analysis_archive_magic))
                return error.InvalidArchive;
            const archive_version = try reader.byte();
            if (archive_version < 1 or
                archive_version > analysis_archive_version)
                return error.InvalidArchive;
            const record_count = try reader.integer16();
            if (record_count > mappings.len or
                record_count > limits.sources)
                return error.InvalidArchive;
            var staged = self.slots;
            for (mappings) |mapping| {
                const current_id = mapping.current_id orelse continue;
                for (&staged) |*slot| {
                    const candidate = slot.source_id orelse continue;
                    if (sameSource(candidate, current_id))
                        slot.* = .{};
                }
            }
            var seen_source_indexes: [limits.sources]u16 = @splat(
                std.math.maxInt(u16),
            );
            for (0..record_count) |record_index| {
                const source_index = try reader.integer16();
                if (source_index >= mappings.len)
                    return error.InvalidArchive;
                for (seen_source_indexes[0..record_index]) |seen| {
                    if (seen == source_index)
                        return error.InvalidArchive;
                }
                seen_source_indexes[record_index] = source_index;
                const status_byte = try reader.byte();
                const status: Status = switch (status_byte) {
                    0 => if (archive_version < 2)
                        return error.InvalidArchive
                    else
                        .empty,
                    1 => .detected,
                    2 => .approved,
                    else => return error.InvalidArchive,
                };
                const processing_algorithm =
                    if (archive_version < 2)
                        general_algorithm_index
                    else
                        try reader.byte();
                if (processing_algorithm >=
                    processing_algorithms.len)
                    return error.InvalidArchive;
                const concert_pitch: f32 =
                    @bitCast(try reader.integer32());
                if (status != .empty and
                    (!std.math.isFinite(concert_pitch) or
                        concert_pitch < 300.0 or
                        concert_pitch > 500.0))
                    return error.InvalidArchive;
                const name_length = try reader.integer16();
                if (name_length > limits.name_bytes)
                    return error.InvalidArchive;
                const name = try reader.bytes(name_length);
                if (!std.unicode.utf8ValidateSlice(name) or
                    (status == .empty and name.len != 0))
                    return error.InvalidArchive;
                const tempo_status: Status =
                    if (archive_version < 3)
                        .empty
                    else switch (try reader.byte()) {
                        0 => .empty,
                        1 => .detected,
                        2 => .approved,
                        else => return error.InvalidArchive,
                    };
                var tempo_entries: [limits.tempo_entries]raw.ARAContentTempoEntry =
                    undefined;
                var tempo_entry_count: usize = 0;
                if (archive_version == 3) {
                    const first_beat_time: f64 =
                        @bitCast(try reader.integer64());
                    const beat_period: f64 =
                        @bitCast(try reader.integer64());
                    if (tempo_status != .empty) {
                        const minimum_period =
                            60.0 /
                            self.tempo_detection_config.maximum_bpm;
                        const maximum_period =
                            60.0 /
                            self.tempo_detection_config.minimum_bpm;
                        if (!std.math.isFinite(first_beat_time) or
                            first_beat_time < 0.0 or
                            !std.math.isFinite(beat_period) or
                            beat_period < minimum_period or
                            beat_period > maximum_period or
                            !std.math.isFinite(
                                first_beat_time + beat_period,
                            ))
                            return error.InvalidArchive;
                        tempo_entries[0] = .{
                            .timePosition = first_beat_time,
                            .quarterPosition = 0.0,
                        };
                        tempo_entries[1] = .{
                            .timePosition = first_beat_time + beat_period,
                            .quarterPosition = 1.0,
                        };
                        tempo_entry_count = 2;
                    }
                } else if (archive_version >= 4) {
                    tempo_entry_count = try reader.integer16();
                    if (tempo_entry_count > limits.tempo_entries or
                        (tempo_status == .empty) !=
                            (tempo_entry_count == 0) or
                        (tempo_status != .empty and
                            tempo_entry_count < 2))
                        return error.InvalidArchive;
                    for (0..tempo_entry_count) |tempo_index| {
                        const entry = raw.ARAContentTempoEntry{
                            .timePosition = @bitCast(try reader.integer64()),
                            .quarterPosition = @bitCast(try reader.integer64()),
                        };
                        if (!std.math.isFinite(entry.timePosition) or
                            !std.math.isFinite(entry.quarterPosition) or
                            entry.timePosition < 0.0 or
                            (tempo_index == 0 and
                                entry.quarterPosition != 0.0))
                            return error.InvalidArchive;
                        if (tempo_index > 0) {
                            const previous =
                                tempo_entries[tempo_index - 1];
                            if (entry.timePosition <=
                                previous.timePosition or
                                entry.quarterPosition <=
                                    previous.quarterPosition)
                                return error.InvalidArchive;
                            const bpm =
                                (entry.quarterPosition -
                                    previous.quarterPosition) /
                                (entry.timePosition -
                                    previous.timePosition) *
                                60.0;
                            if (!std.math.isFinite(bpm) or
                                bpm <
                                    self.tempo_detection_config.minimum_bpm or
                                bpm >
                                    self.tempo_detection_config.maximum_bpm)
                                return error.InvalidArchive;
                        }
                        tempo_entries[tempo_index] = entry;
                    }
                }
                const meter_status: Status =
                    if (archive_version < 6)
                        .empty
                    else switch (try reader.byte()) {
                        0 => .empty,
                        1 => .detected,
                        2 => .approved,
                        else => return error.InvalidArchive,
                    };
                var bar_signatures: [limits.bar_signatures]raw.ARAContentBarSignature =
                    undefined;
                var bar_signature_count: usize = 0;
                if (archive_version >= 6) {
                    bar_signature_count = try reader.integer16();
                    if (bar_signature_count >
                        limits.bar_signatures or
                        (meter_status == .empty) !=
                            (bar_signature_count == 0) or
                        (meter_status != .empty and
                            tempo_status == .empty))
                        return error.InvalidArchive;
                    for (0..bar_signature_count) |meter_index| {
                        const signature =
                            raw.ARAContentBarSignature{
                                .numerator = @bitCast(
                                    try reader.integer32(),
                                ),
                                .denominator = @bitCast(
                                    try reader.integer32(),
                                ),
                                .position = @bitCast(
                                    try reader.integer64(),
                                ),
                            };
                        const previous =
                            if (meter_index == 0)
                                null
                            else
                                bar_signatures[meter_index - 1];
                        if (!validArchivedBarSignature(
                            signature,
                            previous,
                        ))
                            return error.InvalidArchive;
                        bar_signatures[meter_index] = signature;
                    }
                }
                const note_status: Status =
                    if (archive_version < 5)
                        .empty
                    else switch (try reader.byte()) {
                        0 => .empty,
                        1 => .detected,
                        2 => .approved,
                        else => return error.InvalidArchive,
                    };
                var notes: [limits.note_entries]raw.ARAContentNote =
                    undefined;
                var note_count: usize = 0;
                if (archive_version >= 5) {
                    note_count = try reader.integer16();
                    if (note_count > limits.note_entries or
                        (note_status == .empty and note_count != 0))
                        return error.InvalidArchive;
                    for (0..note_count) |note_index| {
                        const note = raw.ARAContentNote{
                            .frequency = @bitCast(
                                try reader.integer32(),
                            ),
                            .pitchNumber = @bitCast(
                                try reader.integer32(),
                            ),
                            .volume = @bitCast(
                                try reader.integer32(),
                            ),
                            .startPosition = @bitCast(
                                try reader.integer64(),
                            ),
                            .attackDuration = @bitCast(
                                try reader.integer64(),
                            ),
                            .noteDuration = @bitCast(
                                try reader.integer64(),
                            ),
                            .signalDuration = @bitCast(
                                try reader.integer64(),
                            ),
                        };
                        if (!validArchivedNote(note) or
                            (note_index > 0 and
                                note.startPosition <
                                    notes[note_index - 1]
                                        .startPosition))
                            return error.InvalidArchive;
                        notes[note_index] = note;
                    }
                }
                const key_status: Status =
                    if (archive_version < 7)
                        .empty
                    else switch (try reader.byte()) {
                        0 => .empty,
                        1 => .detected,
                        2 => .approved,
                        else => return error.InvalidArchive,
                    };
                var key_signatures: [limits.key_signatures]raw.ARAContentKeySignature =
                    undefined;
                var key_signature_count: usize = 0;
                if (archive_version >= 7) {
                    key_signature_count = try reader.integer16();
                    if (key_signature_count > limits.key_signatures or
                        (key_status == .empty) !=
                            (key_signature_count == 0) or
                        (key_status != .empty and
                            tempo_status == .empty))
                        return error.InvalidArchive;
                    for (0..key_signature_count) |key_index| {
                        var signature = raw.ARAContentKeySignature{
                            .root = @bitCast(try reader.integer32()),
                            .intervals = undefined,
                            .name = null,
                            .position = 0.0,
                        };
                        const intervals = try reader.bytes(12);
                        @memcpy(&signature.intervals, intervals);
                        signature.position =
                            @bitCast(try reader.integer64());
                        const previous =
                            if (key_index == 0)
                                null
                            else
                                key_signatures[key_index - 1];
                        if (!validArchivedKeySignature(
                            signature,
                            previous,
                        ))
                            return error.InvalidArchive;
                        key_signatures[key_index] = signature;
                    }
                }
                const chord_status: Status =
                    if (archive_version < 8)
                        .empty
                    else switch (try reader.byte()) {
                        0 => .empty,
                        1 => .detected,
                        2 => .approved,
                        else => return error.InvalidArchive,
                    };
                var chords: [limits.chords]raw.ARAContentChord =
                    undefined;
                var chord_count: usize = 0;
                if (archive_version >= 8) {
                    chord_count = try reader.integer16();
                    if (chord_count > limits.chords or
                        (chord_status == .empty) !=
                            (chord_count == 0) or
                        (chord_status != .empty and
                            tempo_status == .empty))
                        return error.InvalidArchive;
                    for (0..chord_count) |chord_index| {
                        var chord = raw.ARAContentChord{
                            .root = @bitCast(try reader.integer32()),
                            .bass = @bitCast(try reader.integer32()),
                            .intervals = undefined,
                            .name = null,
                            .position = 0.0,
                        };
                        const intervals = try reader.bytes(12);
                        @memcpy(&chord.intervals, intervals);
                        chord.position =
                            @bitCast(try reader.integer64());
                        const previous =
                            if (chord_index == 0)
                                null
                            else
                                chords[chord_index - 1];
                        if (!validArchivedChord(chord, previous))
                            return error.InvalidArchive;
                        chords[chord_index] = chord;
                    }
                }
                const current_id =
                    mappings[source_index].current_id orelse continue;
                var destination: ?*Slot = null;
                for (&staged) |*slot| {
                    if (slot.source_id == null) {
                        destination = slot;
                        break;
                    }
                }
                const slot = destination orelse
                    return error.CapacityExceeded;
                slot.* = .{
                    .source_id = current_id,
                    .processing_algorithm = @intCast(processing_algorithm),
                };
                if (status != .empty)
                    setTuning(slot, concert_pitch, status, name);
                if (tempo_status != .empty) {
                    slot.tempo_status = tempo_status;
                    slot.tempo_entry_count =
                        @intCast(tempo_entry_count);
                    @memcpy(
                        slot.tempo_entries[0..tempo_entry_count],
                        tempo_entries[0..tempo_entry_count],
                    );
                }
                if (meter_status != .empty) {
                    slot.meter_status = meter_status;
                    slot.bar_signature_count =
                        @intCast(bar_signature_count);
                    @memcpy(
                        slot.bar_signatures[0..bar_signature_count],
                        bar_signatures[0..bar_signature_count],
                    );
                }
                if (note_status != .empty) {
                    slot.note_status = note_status;
                    slot.note_count = @intCast(note_count);
                    @memcpy(
                        slot.notes[0..note_count],
                        notes[0..note_count],
                    );
                }
                if (key_status != .empty) {
                    slot.key_status = key_status;
                    slot.key_signature_count =
                        @intCast(key_signature_count);
                    @memcpy(
                        slot.key_signatures[0..key_signature_count],
                        key_signatures[0..key_signature_count],
                    );
                }
                if (chord_status != .empty) {
                    slot.chord_status = chord_status;
                    slot.chord_count = @intCast(chord_count);
                    @memcpy(
                        slot.chords[0..chord_count],
                        chords[0..chord_count],
                    );
                }
            }
            if (!reader.finished()) return error.InvalidArchive;
            self.slots = staged;
        }

        fn analysisIncomplete(
            context: ?*anyopaque,
            source_id: SourceId,
            content_type: raw.ARAContentType,
        ) bool {
            const self = fromContext(context) orelse return false;
            const slot = self.findSlot(source_id) orelse return true;
            const status = switch (content_type) {
                raw.kARAContentTypeNotes => slot.note_status,
                raw.kARAContentTypeStaticTuning => slot.status,
                raw.kARAContentTypeTempoEntries => slot.tempo_status,
                raw.kARAContentTypeBarSignatures => slot.meter_status,
                raw.kARAContentTypeKeySignatures => slot.key_status,
                raw.kARAContentTypeSheetChords => slot.chord_status,
                else => return false,
            };
            return status == .empty or status == .pending;
        }

        fn slotNeedsArchive(slot: *const Slot) bool {
            return slot.status == .detected or
                slot.status == .approved or
                slot.tempo_status == .detected or
                slot.tempo_status == .approved or
                slot.meter_status == .detected or
                slot.meter_status == .approved or
                slot.key_status == .detected or
                slot.key_status == .approved or
                slot.chord_status == .detected or
                slot.chord_status == .approved or
                slot.note_status == .detected or
                slot.note_status == .approved or
                slot.processing_algorithm != general_algorithm_index;
        }

        fn requestAnalysis(
            context: ?*anyopaque,
            source_id: SourceId,
            content_types: []const raw.ARAContentType,
        ) bool {
            const self = fromContext(context) orelse return false;
            if (content_types.len == 0) return false;
            for (content_types) |content_type| {
                if (content_type != raw.kARAContentTypeNotes and
                    content_type !=
                        raw.kARAContentTypeStaticTuning and
                    content_type !=
                        raw.kARAContentTypeTempoEntries and
                    content_type !=
                        raw.kARAContentTypeBarSignatures and
                    content_type !=
                        raw.kARAContentTypeKeySignatures and
                    content_type !=
                        raw.kARAContentTypeSheetChords)
                    return false;
            }
            const notes_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeNotes,
            ) != null;
            const tuning_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeStaticTuning,
            ) != null;
            const tempo_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeTempoEntries,
            ) != null;
            const meter_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeBarSignatures,
            ) != null;
            const key_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeKeySignatures,
            ) != null;
            const chords_requested = std.mem.indexOfScalar(
                raw.ARAContentType,
                content_types,
                raw.kARAContentTypeSheetChords,
            ) != null;
            if (notes_requested and
                !key_requested and
                !chords_requested)
            {
                _ = self.analyzeNotes(source_id) catch |failure| {
                    self.last_error = failure;
                };
            }
            if (tuning_requested) {
                _ = self.analyze(source_id) catch |failure| {
                    self.last_error = failure;
                };
            }
            if (meter_requested) {
                _ = self.analyzeMeter(source_id) catch |failure| {
                    self.last_error = failure;
                };
            } else if (tempo_requested and
                !key_requested and
                !chords_requested)
            {
                _ = self.analyzeTempo(source_id) catch |failure| {
                    self.last_error = failure;
                };
            }
            if (chords_requested) {
                _ = self.analyzeChords(source_id) catch |failure| {
                    self.last_error = failure;
                };
            }
            if (key_requested) {
                _ = self.analyzeKeySignatures(source_id) catch |failure| {
                    self.last_error = failure;
                };
            }
            return true;
        }

        fn sourceContentChanged(
            context: ?*anyopaque,
            source_id: SourceId,
            range: ?raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) void {
            _ = range;
            const self = fromContext(context) orelse return;
            const slot = self.findSlot(source_id) orelse return;
            if (flags &
                raw.kARAContentUpdateNoteScopeRemainsUnchanged == 0)
            {
                slot.note_status = .empty;
                slot.note_count = 0;
                slot.notes =
                    @splat(std.mem.zeroes(raw.ARAContentNote));
            }
            if (flags &
                raw.kARAContentUpdateTuningScopeRemainsUnchanged == 0)
            {
                slot.status = .empty;
                slot.tuning = std.mem.zeroes(raw.ARAContentTuning);
                @memset(&slot.name, 0);
            }
            if (flags &
                raw.kARAContentUpdateTimingScopeRemainsUnchanged == 0)
            {
                slot.tempo_status = .empty;
                slot.tempo_entry_count = 0;
                slot.tempo_entries = @splat(.{
                    .timePosition = 0.0,
                    .quarterPosition = 0.0,
                });
                slot.meter_status = .empty;
                slot.bar_signature_count = 0;
                slot.bar_signatures = @splat(.{
                    .numerator = 0,
                    .denominator = 0,
                    .position = 0.0,
                });
                slot.key_status = .empty;
                slot.key_signature_count = 0;
                slot.key_signatures = @splat(.{
                    .root = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                });
                slot.chord_status = .empty;
                slot.chord_count = 0;
                slot.chords = @splat(.{
                    .root = 0,
                    .bass = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                });
            }
            if (flags &
                raw.kARAContentUpdateHarmonicScopeRemainsUnchanged == 0)
            {
                slot.key_status = .empty;
                slot.key_signature_count = 0;
                slot.key_signatures = @splat(.{
                    .root = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                });
                slot.chord_status = .empty;
                slot.chord_count = 0;
                slot.chords = @splat(.{
                    .root = 0,
                    .bass = 0,
                    .intervals = @splat(0),
                    .name = null,
                    .position = 0.0,
                });
            }
        }

        fn processingAlgorithmsCount(
            context: ?*anyopaque,
        ) usize {
            return if (fromContext(context) == null)
                0
            else
                processing_algorithm_count;
        }

        fn processingAlgorithmProperties(
            context: ?*anyopaque,
            index: usize,
        ) ?*const raw.ARAProcessingAlgorithmProperties {
            if (fromContext(context) == null or
                index >= processing_algorithms.len)
                return null;
            return &processing_algorithms[index];
        }

        fn processingAlgorithmForSource(
            context: ?*anyopaque,
            source_id: SourceId,
        ) ?usize {
            const self = fromContext(context) orelse return null;
            if (self.controller.document.audioSource(source_id) == null)
                return null;
            const slot = self.findSlot(source_id) orelse
                return general_algorithm_index;
            return slot.processing_algorithm;
        }

        fn requestProcessingAlgorithm(
            context: ?*anyopaque,
            source_id: SourceId,
            index: usize,
        ) bool {
            const self = fromContext(context) orelse return false;
            if (index >= processing_algorithms.len)
                return false;
            const slot = self.slotFor(source_id) catch |failure| {
                self.last_error = failure;
                return false;
            };
            if (@as(usize, slot.processing_algorithm) == index)
                return true;
            slot.processing_algorithm = @intCast(index);
            slot.status = .empty;
            slot.tempo_status = .empty;
            slot.tempo_entry_count = 0;
            slot.meter_status = .empty;
            slot.bar_signature_count = 0;
            slot.key_status = .empty;
            slot.key_signature_count = 0;
            slot.chord_status = .empty;
            slot.chord_count = 0;
            slot.note_status = .empty;
            slot.note_count = 0;
            slot.tuning = std.mem.zeroes(raw.ARAContentTuning);
            slot.tempo_entries = @splat(.{
                .timePosition = 0.0,
                .quarterPosition = 0.0,
            });
            slot.bar_signatures = @splat(.{
                .numerator = 0,
                .denominator = 0,
                .position = 0.0,
            });
            slot.key_signatures = @splat(.{
                .root = 0,
                .intervals = @splat(0),
                .name = null,
                .position = 0.0,
            });
            slot.chords = @splat(.{
                .root = 0,
                .bass = 0,
                .intervals = @splat(0),
                .name = null,
                .position = 0.0,
            });
            slot.notes = @splat(std.mem.zeroes(raw.ARAContentNote));
            @memset(&slot.name, 0);
            self.controller.notifyAudioSourceContentChanged(
                source_id,
                null,
                unchanged_except_signal,
            ) catch |failure| {
                self.last_error = failure;
                return false;
            };
            return true;
        }

        fn isAvailable(
            context: ?*anyopaque,
            object: *const ControllerType.ContentObject,
            content_type: raw.ARAContentType,
        ) bool {
            const self = fromContext(context) orelse return false;
            const source_id = switch (object.*) {
                .audio_source => |id| id,
                else => return false,
            };
            const slot = self.findSlot(source_id) orelse return false;
            return switch (content_type) {
                raw.kARAContentTypeNotes => slot.note_status == .detected or
                    slot.note_status == .approved,
                raw.kARAContentTypeStaticTuning => slot.status == .detected or
                    slot.status == .approved,
                raw.kARAContentTypeTempoEntries => slot.tempo_status == .detected or
                    slot.tempo_status == .approved,
                raw.kARAContentTypeBarSignatures => slot.meter_status == .detected or
                    slot.meter_status == .approved,
                raw.kARAContentTypeKeySignatures => slot.key_status == .detected or
                    slot.key_status == .approved,
                raw.kARAContentTypeSheetChords => slot.chord_status == .detected or
                    slot.chord_status == .approved,
                else => false,
            };
        }

        fn grade(
            context: ?*anyopaque,
            object: *const ControllerType.ContentObject,
            content_type: raw.ARAContentType,
        ) raw.ARAContentGrade {
            if (!isAvailable(context, object, content_type))
                return raw.kARAContentGradeInitial;
            const self = fromContext(context) orelse
                return raw.kARAContentGradeInitial;
            const source_id = switch (object.*) {
                .audio_source => |id| id,
                else => return raw.kARAContentGradeInitial,
            };
            const slot = self.findSlot(source_id) orelse
                return raw.kARAContentGradeInitial;
            const status = switch (content_type) {
                raw.kARAContentTypeNotes => slot.note_status,
                raw.kARAContentTypeStaticTuning => slot.status,
                raw.kARAContentTypeTempoEntries => slot.tempo_status,
                raw.kARAContentTypeBarSignatures => slot.meter_status,
                raw.kARAContentTypeKeySignatures => slot.key_status,
                raw.kARAContentTypeSheetChords => slot.chord_status,
                else => return raw.kARAContentGradeInitial,
            };
            return if (status == .approved)
                raw.kARAContentGradeApproved
            else
                raw.kARAContentGradeDetected;
        }

        fn eventCount(
            context: ?*anyopaque,
            query: *const ControllerType.ContentProvider.Query,
        ) ?usize {
            if (!isAvailable(
                context,
                &query.object,
                query.content_type,
            ))
                return null;
            const object = &query.object;
            const content_type = query.content_type;
            if (content_type == raw.kARAContentTypeNotes) {
                const self = fromContext(context) orelse return null;
                const source_id = switch (object.*) {
                    .audio_source => |id| id,
                    else => return null,
                };
                const slot = self.findSlot(source_id) orelse return null;
                var count: usize = 0;
                for (slot.notes[0..slot.note_count]) |note| {
                    if (noteIntersectsRange(note, query.range))
                        count += 1;
                }
                return count;
            }
            if (content_type == raw.kARAContentTypeBarSignatures) {
                const self = fromContext(context) orelse return null;
                const source_id = switch (object.*) {
                    .audio_source => |id| id,
                    else => return null,
                };
                const slot = self.findSlot(source_id) orelse return null;
                return slot.bar_signature_count;
            }
            if (content_type == raw.kARAContentTypeKeySignatures) {
                const self = fromContext(context) orelse return null;
                const source_id = switch (object.*) {
                    .audio_source => |id| id,
                    else => return null,
                };
                const slot = self.findSlot(source_id) orelse return null;
                return slot.key_signature_count;
            }
            if (content_type == raw.kARAContentTypeSheetChords) {
                const self = fromContext(context) orelse return null;
                const source_id = switch (object.*) {
                    .audio_source => |id| id,
                    else => return null,
                };
                const slot = self.findSlot(source_id) orelse return null;
                return slot.chord_count;
            }
            if (content_type != raw.kARAContentTypeTempoEntries)
                return 1;
            const self = fromContext(context) orelse return null;
            const source_id = switch (object.*) {
                .audio_source => |id| id,
                else => return null,
            };
            const slot = self.findSlot(source_id) orelse return null;
            return slot.tempo_entry_count;
        }

        fn eventData(
            context: ?*anyopaque,
            query: *const ControllerType.ContentProvider.Query,
            event_index: usize,
        ) ?*const anyopaque {
            const self = fromContext(context) orelse return null;
            const source_id = switch (query.object) {
                .audio_source => |id| id,
                else => return null,
            };
            const slot = self.findSlot(source_id) orelse return null;
            return switch (query.content_type) {
                raw.kARAContentTypeNotes => notes: {
                    if (slot.note_status != .detected and
                        slot.note_status != .approved)
                        break :notes null;
                    var matching_index: usize = 0;
                    for (slot.notes[0..slot.note_count]) |*note| {
                        if (!noteIntersectsRange(
                            note.*,
                            query.range,
                        ))
                            continue;
                        if (matching_index == event_index)
                            break :notes note;
                        matching_index += 1;
                    }
                    break :notes null;
                },
                raw.kARAContentTypeStaticTuning => tuning: {
                    if (event_index != 0 or
                        (slot.status != .detected and
                            slot.status != .approved))
                        break :tuning null;
                    slot.tuning.name = &slot.name;
                    break :tuning &slot.tuning;
                },
                raw.kARAContentTypeTempoEntries => tempo: {
                    if (event_index >= slot.tempo_entry_count or
                        (slot.tempo_status != .detected and
                            slot.tempo_status != .approved))
                        break :tempo null;
                    break :tempo &slot.tempo_entries[event_index];
                },
                raw.kARAContentTypeBarSignatures => meter: {
                    if (event_index >= slot.bar_signature_count or
                        (slot.meter_status != .detected and
                            slot.meter_status != .approved))
                        break :meter null;
                    break :meter &slot.bar_signatures[event_index];
                },
                raw.kARAContentTypeKeySignatures => key: {
                    if (event_index >= slot.key_signature_count or
                        (slot.key_status != .detected and
                            slot.key_status != .approved))
                        break :key null;
                    break :key &slot.key_signatures[event_index];
                },
                raw.kARAContentTypeSheetChords => chord: {
                    if (event_index >= slot.chord_count or
                        (slot.chord_status != .detected and
                            slot.chord_status != .approved))
                        break :chord null;
                    break :chord &slot.chords[event_index];
                },
                else => null,
            };
        }

        const vtable = ControllerType.ContentProvider.VTable{
            .archive_size = archiveSize,
            .store_archive = storeArchive,
            .restore_archive = restoreArchive,
            .analysis_incomplete = analysisIncomplete,
            .request_analysis = requestAnalysis,
            .source_content_changed = sourceContentChanged,
            .processing_algorithms_count = processingAlgorithmsCount,
            .processing_algorithm_properties = processingAlgorithmProperties,
            .processing_algorithm_for_source = processingAlgorithmForSource,
            .request_processing_algorithm = requestProcessingAlgorithm,
            .is_available = isAvailable,
            .grade = grade,
            .event_count = eventCount,
            .event_data = eventData,
        };
    };
}

const unchanged_except_tuning =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged |
    raw.kARAContentUpdateNoteScopeRemainsUnchanged |
    raw.kARAContentUpdateTimingScopeRemainsUnchanged |
    raw.kARAContentUpdateHarmonicScopeRemainsUnchanged;

const unchanged_except_signal =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged;

const unchanged_except_timing_and_harmonic =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged |
    raw.kARAContentUpdateNoteScopeRemainsUnchanged |
    raw.kARAContentUpdateTuningScopeRemainsUnchanged;

const unchanged_except_notes_and_harmonic =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged |
    raw.kARAContentUpdateTimingScopeRemainsUnchanged |
    raw.kARAContentUpdateTuningScopeRemainsUnchanged;

const unchanged_except_notes_timing_and_harmonic =
    raw.kARAContentUpdateSignalScopeRemainsUnchanged |
    raw.kARAContentUpdateTuningScopeRemainsUnchanged;

const analysis_archive_magic = [_]u8{ 'Z', 'T', 'U', 'N' };
const analysis_archive_version: u8 = 8;
const archive_header_size = analysis_archive_magic.len + 1 + 2;
const archive_record_fixed_size =
    2 + 1 + 1 + 4 + 2 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2 + 1 + 2;
const archive_bar_signature_size = 4 + 4 + 8;
const archive_note_size = 4 + 4 + 4 + 8 + 8 + 8 + 8;
const archive_key_signature_size = 4 + 12 + 8;
const archive_chord_size = 4 + 4 + 12 + 8;

const ByteWriter = struct {
    bytes_storage: []u8,
    position: usize = 0,

    fn init(storage: []u8) ByteWriter {
        return .{ .bytes_storage = storage };
    }

    fn byte(self: *ByteWriter, value: u8) Error!void {
        if (self.position >= self.bytes_storage.len)
            return error.ArchiveTooLarge;
        self.bytes_storage[self.position] = value;
        self.position += 1;
    }

    fn bytes(
        self: *ByteWriter,
        values: []const u8,
    ) Error!void {
        if (values.len >
            self.bytes_storage.len - self.position)
            return error.ArchiveTooLarge;
        @memcpy(
            self.bytes_storage[self.position..][0..values.len],
            values,
        );
        self.position += values.len;
    }

    fn integer16(self: *ByteWriter, value: u16) Error!void {
        try self.byte(@truncate(value));
        try self.byte(@truncate(value >> 8));
    }

    fn integer32(self: *ByteWriter, value: u32) Error!void {
        try self.integer16(@truncate(value));
        try self.integer16(@truncate(value >> 16));
    }

    fn integer64(self: *ByteWriter, value: u64) Error!void {
        try self.integer32(@truncate(value));
        try self.integer32(@truncate(value >> 32));
    }

    fn finished(self: *const ByteWriter) bool {
        return self.position == self.bytes_storage.len;
    }
};

const ByteReader = struct {
    bytes_storage: []const u8,
    position: usize = 0,

    fn init(storage: []const u8) ByteReader {
        return .{ .bytes_storage = storage };
    }

    fn byte(self: *ByteReader) Error!u8 {
        if (self.position >= self.bytes_storage.len)
            return error.InvalidArchive;
        const value = self.bytes_storage[self.position];
        self.position += 1;
        return value;
    }

    fn bytes(
        self: *ByteReader,
        count: usize,
    ) Error![]const u8 {
        if (count > self.bytes_storage.len - self.position)
            return error.InvalidArchive;
        const result =
            self.bytes_storage[self.position..][0..count];
        self.position += count;
        return result;
    }

    fn integer16(self: *ByteReader) Error!u16 {
        const low = try self.byte();
        const high = try self.byte();
        return @as(u16, low) | (@as(u16, high) << 8);
    }

    fn integer32(self: *ByteReader) Error!u32 {
        const low = try self.integer16();
        const high = try self.integer16();
        return @as(u32, low) | (@as(u32, high) << 16);
    }

    fn integer64(self: *ByteReader) Error!u64 {
        const low = try self.integer32();
        const high = try self.integer32();
        return @as(u64, low) | (@as(u64, high) << 32);
    }

    fn finished(self: *const ByteReader) bool {
        return self.position == self.bytes_storage.len;
    }
};

test "ARA analysis facade preserves detector model identities" {
    try std.testing.expect(
        DetectionConfig == analysis_model.DetectionConfig,
    );
    try std.testing.expect(
        TempoDetectionConfig == analysis_model.TempoDetectionConfig,
    );
    try std.testing.expect(
        MeterDetectionConfig == analysis_model.MeterDetectionConfig,
    );
    try std.testing.expect(
        KeySignatureDetectionConfig ==
            analysis_model.KeySignatureDetectionConfig,
    );
    try std.testing.expect(
        ChordDetectionConfig == analysis_model.ChordDetectionConfig,
    );
    try std.testing.expect(
        NoteDetectionConfig == analysis_model.NoteDetectionConfig,
    );
    try std.testing.expect(Limits == analysis_model.Limits);
}

test "ARA tuning detection estimates detuned equal temperament" {
    const sample_rate = 48_000.0;
    const concert_pitch = 442.0;
    const pitch_number = 57;
    const frequency = concert_pitch *
        std.math.pow(
            f64,
            2.0,
            (@as(f64, pitch_number) - 69.0) / 12.0,
        );
    var samples: [8_192]f64 = undefined;
    for (&samples, 0..) |*sample, frame| {
        const phase = 2.0 * std.math.pi * frequency *
            @as(f64, @floatFromInt(frame)) / sample_rate;
        sample.* = 0.5 * @sin(phase) + 0.02;
    }
    const result = try detectEqualTemperament(
        &samples,
        sample_rate,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        concert_pitch,
        result.concert_pitch,
        0.15,
    );
    try std.testing.expectEqual(
        @as(i32, pitch_number),
        result.pitch_number,
    );
    try std.testing.expect(result.correlation > 0.99);
}

test "ARA tuning detection rejects silence and invalid configuration" {
    const silence: [64]f64 = @splat(0);
    try std.testing.expectError(
        error.SignalTooQuiet,
        detectEqualTemperament(&silence, 48_000, .{}),
    );
    try std.testing.expectError(
        error.InvalidFrequencyRange,
        detectEqualTemperament(
            &silence,
            48_000,
            .{ .maximum_frequency = 30_000 },
        ),
    );
    try std.testing.expectError(
        error.InvalidSampleCount,
        detectEqualTemperament(
            &silence,
            48_000,
            .{
                .minimum_frequency = 1.0e-300,
                .maximum_frequency = 2.0e-300,
            },
        ),
    );
}

test "ARA tempo detection estimates periodic onset timing" {
    const envelope_rate = 200.0;
    var envelope: [1_200]f64 = @splat(0.0);
    var index: usize = 20;
    while (index < envelope.len) : (index += 100)
        envelope[index] = 1.0;
    const result = try detectTempoEnvelope(
        &envelope,
        envelope_rate,
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 120.0),
        result.bpm,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.1),
        result.first_beat_time,
        0.001,
    );
    try std.testing.expect(result.correlation > 0.9);

    const silence: [1_200]f64 = @splat(0.0);
    try std.testing.expectError(
        error.SignalTooQuiet,
        detectTempoEnvelope(&silence, envelope_rate, .{}),
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        detectTempoEnvelope(
            &envelope,
            envelope_rate,
            .{ .minimum_bpm = 240.0, .maximum_bpm = 40.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidSampleCount,
        detectTempoEnvelope(
            &envelope,
            envelope_rate,
            .{
                .minimum_bpm = 1.0e-300,
                .maximum_bpm = 2.0e-300,
            },
        ),
    );
}

test "ARA tempo map collapses constant tempo to two endpoints" {
    const envelope_rate = 200.0;
    var envelope: [4_000]f64 = @splat(0.0);
    var onset_index: usize = 20;
    while (onset_index < envelope.len) : (onset_index += 100)
        envelope[onset_index] = 1.0;
    var entries: [8]raw.ARAContentTempoEntry = undefined;
    const count = try detectTempoMapEnvelope(
        &envelope,
        envelope_rate,
        .{
            .window_seconds = 6.0,
            .hop_seconds = 3.0,
        },
        &entries,
    );
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 120.0),
        (entries[1].quarterPosition -
            entries[0].quarterPosition) /
            (entries[1].timePosition -
                entries[0].timePosition) *
            60.0,
        0.001,
    );
}

test "ARA tempo map detects a bounded tempo step" {
    const envelope_rate = 200.0;
    const transition_index = 3_000;
    var envelope: [6_000]f64 = @splat(0.0);
    var onset_index: usize = 0;
    while (onset_index < transition_index) : (onset_index += 100)
        envelope[onset_index] = 1.0;
    onset_index = transition_index;
    while (onset_index < envelope.len) : (onset_index += 150)
        envelope[onset_index] = 1.0;
    var entries: [16]raw.ARAContentTempoEntry = undefined;
    const config = TempoDetectionConfig{
        .window_seconds = 6.0,
        .hop_seconds = 3.0,
        .tempo_change_ratio = 0.1,
    };
    const count = try detectTempoMapEnvelope(
        &envelope,
        envelope_rate,
        config,
        &entries,
    );
    try std.testing.expect(count >= 3);
    for (entries[1..count], entries[0 .. count - 1]) |
        current,
        previous,
    | {
        try std.testing.expect(
            current.timePosition > previous.timePosition,
        );
        try std.testing.expect(
            current.quarterPosition > previous.quarterPosition,
        );
    }
    const first_bpm =
        (entries[1].quarterPosition -
            entries[0].quarterPosition) /
        (entries[1].timePosition -
            entries[0].timePosition) *
        60.0;
    const last_bpm =
        (entries[count - 1].quarterPosition -
            entries[count - 2].quarterPosition) /
        (entries[count - 1].timePosition -
            entries[count - 2].timePosition) *
        60.0;
    try std.testing.expectApproxEqAbs(
        @as(f64, 120.0),
        first_bpm,
        0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 80.0),
        last_bpm,
        0.001,
    );

    var insufficient = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 41.0, .quarterPosition = 42.0 },
        .{ .timePosition = 43.0, .quarterPosition = 44.0 },
    };
    const before = insufficient;
    try std.testing.expectError(
        error.CapacityExceeded,
        detectTempoMapEnvelope(
            &envelope,
            envelope_rate,
            config,
            &insufficient,
        ),
    );
    try std.testing.expectEqualDeep(before, insufficient);
}

fn keyTestNote(
    pitch: i32,
    start_quarter: f64,
    duration_quarters: f64,
    volume: f32,
) raw.ARAContentNote {
    return .{
        .frequency = 440.0 * @as(f32, @floatCast(std.math.pow(
            f64,
            2.0,
            (@as(f64, @floatFromInt(pitch)) - 69.0) / 12.0,
        ))),
        .pitchNumber = pitch,
        .volume = volume,
        .startPosition = start_quarter * 0.5,
        .attackDuration = 0.0,
        .noteDuration = duration_quarters * 0.5,
        .signalDuration = duration_quarters * 0.5,
    };
}

const key_test_tempo = [_]raw.ARAContentTempoEntry{
    .{ .timePosition = 0.0, .quarterPosition = 0.0 },
    .{ .timePosition = 32.0, .quarterPosition = 64.0 },
};

test "ARA key signature detection distinguishes major and minor" {
    const c_major_notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 2, 1.0),
        keyTestNote(64, 2, 1, 0.8),
        keyTestNote(67, 3, 2, 0.9),
        keyTestNote(65, 5, 1, 0.65),
        keyTestNote(71, 6, 1, 0.55),
        keyTestNote(60, 7, 1, 1.0),
    };
    var output: [4]raw.ARAContentKeySignature = undefined;
    const major_count = try detectKeySignatures(
        &c_major_notes,
        &key_test_tempo,
        .{
            .window_quarters = 8,
            .hop_quarters = 8,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 1), major_count);
    try std.testing.expectEqual(@as(i32, 0), output[0].root);
    try std.testing.expectEqualSlices(
        u8,
        &major_intervals,
        &output[0].intervals,
    );
    try std.testing.expectEqual(@as(?[*:0]const u8, null), output[0].name);

    const a_minor_notes = [_]raw.ARAContentNote{
        keyTestNote(57, 0, 2, 1.0),
        keyTestNote(60, 2, 1, 0.85),
        keyTestNote(64, 3, 2, 0.9),
        keyTestNote(62, 5, 1, 0.6),
        keyTestNote(65, 6, 1, 0.65),
        keyTestNote(57, 7, 1, 1.0),
    };
    const minor_count = try detectKeySignatures(
        &a_minor_notes,
        &key_test_tempo,
        .{
            .window_quarters = 8,
            .hop_quarters = 8,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 1), minor_count);
    try std.testing.expectEqual(@as(i32, 3), output[0].root);
    try std.testing.expectEqualSlices(
        u8,
        &minor_intervals,
        &output[0].intervals,
    );
}

test "ARA key signature detection publishes sustained changes" {
    const notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 2, 1.0),
        keyTestNote(64, 2, 2, 0.8),
        keyTestNote(67, 4, 2, 0.9),
        keyTestNote(60, 6, 2, 1.0),
        keyTestNote(67, 8, 2, 1.0),
        keyTestNote(71, 10, 2, 0.85),
        keyTestNote(74, 12, 2, 0.9),
        keyTestNote(67, 14, 2, 1.0),
    };
    var output: [4]raw.ARAContentKeySignature = undefined;
    const count = try detectKeySignatures(
        &notes,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_note_weight = 0.5,
            .minimum_score = 0.3,
            .minimum_score_margin = 0.005,
            .change_confirmation_windows = 2,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(i32, 0), output[0].root);
    try std.testing.expectEqual(@as(i32, 1), output[1].root);
    try std.testing.expectApproxEqAbs(
        @as(f64, 8.0),
        output[1].position,
        1.0e-9,
    );
}

test "ARA key signature detection is transactional and rejects bad input" {
    const notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 2, 1.0),
        keyTestNote(64, 2, 2, 0.8),
        keyTestNote(67, 4, 2, 0.9),
        keyTestNote(60, 6, 2, 1.0),
    };
    var sentinel = [_]raw.ARAContentKeySignature{keySignatureEvent(
        .{
            .root_pitch_class = 11,
            .minor = true,
            .score = 1,
            .margin = 1,
        },
        99,
    )};
    try std.testing.expectError(
        error.CapacityExceeded,
        detectKeySignatures(
            &notes,
            &key_test_tempo,
            .{
                .window_quarters = 4,
                .hop_quarters = 4,
                .minimum_score = 0.3,
                .minimum_score_margin = 0.005,
                .change_confirmation_windows = 1,
            },
            sentinel[0..0],
        ),
    );
    try std.testing.expectEqual(@as(i32, 5), sentinel[0].root);
    try std.testing.expectApproxEqAbs(
        @as(f64, 99),
        sentinel[0].position,
        1.0e-9,
    );

    var invalid_notes = notes;
    invalid_notes[2].startPosition = std.math.nan(f64);
    try std.testing.expectError(
        error.KeySignatureNotFound,
        detectKeySignatures(
            &invalid_notes,
            &key_test_tempo,
            .{},
            &sentinel,
        ),
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        detectKeySignatures(
            &notes,
            &key_test_tempo,
            .{ .change_confirmation_windows = 0 },
            &sentinel,
        ),
    );
}

test "ARA chord detection identifies quality and inversion" {
    const c_major_first_inversion = [_]raw.ARAContentNote{
        keyTestNote(64, 0, 4, 0.9),
        keyTestNote(67, 0, 4, 0.8),
        keyTestNote(72, 0, 4, 1.0),
    };
    var output: [4]raw.ARAContentChord = undefined;
    const major_count = try detectChords(
        &c_major_first_inversion,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 1), major_count);
    try std.testing.expectEqual(@as(i32, 0), output[0].root);
    try std.testing.expectEqual(@as(i32, 4), output[0].bass);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[0].intervals,
        &output[0].intervals,
    );

    const a_minor = [_]raw.ARAContentNote{
        keyTestNote(57, 0, 4, 1.0),
        keyTestNote(60, 0, 4, 0.9),
        keyTestNote(64, 0, 4, 0.8),
    };
    const minor_count = try detectChords(
        &a_minor,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 1), minor_count);
    try std.testing.expectEqual(@as(i32, 3), output[0].root);
    try std.testing.expectEqual(@as(i32, 3), output[0].bass);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[1].intervals,
        &output[0].intervals,
    );

    const c_six = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 4, 1.0),
        keyTestNote(64, 0, 4, 0.9),
        keyTestNote(67, 0, 4, 0.8),
        keyTestNote(69, 0, 4, 0.7),
    };
    _ = try detectChords(
        &c_six,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[12].intervals,
        &output[0].intervals,
    );

    const c_add_nine = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 4, 1.0),
        keyTestNote(62, 0, 4, 0.7),
        keyTestNote(64, 0, 4, 0.9),
        keyTestNote(67, 0, 4, 0.8),
    };
    _ = try detectChords(
        &c_add_nine,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[14].intervals,
        &output[0].intervals,
    );

    const d_power = [_]raw.ARAContentNote{
        keyTestNote(50, 0, 4, 1.0),
        keyTestNote(57, 0, 4, 0.9),
    };
    _ = try detectChords(
        &d_power,
        &key_test_tempo,
        .{
            .window_quarters = 4,
            .hop_quarters = 4,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(i32, 2), output[0].root);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[22].intervals,
        &output[0].intervals,
    );
}

test "ARA chord detection publishes changing seventh chords" {
    const notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 4, 1.0),
        keyTestNote(64, 0, 4, 0.8),
        keyTestNote(67, 0, 4, 0.9),
        keyTestNote(67, 4, 4, 1.0),
        keyTestNote(71, 4, 4, 0.8),
        keyTestNote(74, 4, 4, 0.9),
        keyTestNote(77, 4, 4, 0.7),
    };
    var output: [4]raw.ARAContentChord = undefined;
    const count = try detectChords(
        &notes,
        &key_test_tempo,
        .{
            .window_quarters = 2,
            .hop_quarters = 2,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(i32, 0), output[0].root);
    try std.testing.expectEqual(@as(i32, 1), output[1].root);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[6].intervals,
        &output[1].intervals,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        output[1].position,
        1.0e-9,
    );
    const before = output;
    try std.testing.expectError(
        error.CapacityExceeded,
        detectChords(
            &notes,
            &key_test_tempo,
            .{
                .window_quarters = 2,
                .hop_quarters = 2,
                .minimum_score_margin = 0.01,
            },
            output[0..1],
        ),
    );
    try std.testing.expectEqualDeep(before, output);
}

test "ARA chord detection publishes undefined gaps" {
    const notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 2, 1.0),
        keyTestNote(64, 0, 2, 0.9),
        keyTestNote(67, 0, 2, 0.8),
        keyTestNote(67, 4, 2, 1.0),
        keyTestNote(71, 4, 2, 0.9),
        keyTestNote(74, 4, 2, 0.8),
    };
    var output: [4]raw.ARAContentChord = undefined;
    const count = try detectChords(
        &notes,
        &key_test_tempo,
        .{
            .window_quarters = 1,
            .hop_quarters = 1,
            .minimum_score_margin = 0.01,
        },
        &output,
    );
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        output[1].position,
        1.0e-9,
    );
    try std.testing.expectEqual(
        @as([12]u8, @splat(0)),
        output[1].intervals,
    );
    try std.testing.expectEqual(@as(i32, 1), output[2].root);
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        output[2].position,
        1.0e-9,
    );
}

test "ARA chord detection rejects ambiguity transactionally" {
    const notes = [_]raw.ARAContentNote{
        keyTestNote(60, 0, 4, 1.0),
        keyTestNote(64, 0, 4, 0.8),
    };
    var sentinel = [_]raw.ARAContentChord{.{
        .root = 5,
        .bass = 5,
        .intervals = chord_templates[1].intervals,
        .name = null,
        .position = 99,
    }};
    const before = sentinel;
    try std.testing.expectError(
        error.ChordNotFound,
        detectChords(
            &notes,
            &key_test_tempo,
            .{},
            &sentinel,
        ),
    );
    try std.testing.expectEqualDeep(before, sentinel);
    try std.testing.expectError(
        error.InvalidConfiguration,
        detectChords(
            &notes,
            &key_test_tempo,
            .{ .minimum_pitch_classes = 1 },
            &sentinel,
        ),
    );
    var invalid_notes = notes;
    invalid_notes[1].noteDuration = std.math.nan(f64);
    try std.testing.expectError(
        error.ChordNotFound,
        detectChords(
            &invalid_notes,
            &key_test_tempo,
            .{},
            &sentinel,
        ),
    );
}

test "ARA tempo map follows a gradual slowdown" {
    const envelope_rate = 200.0;
    const duration_seconds = 40.0;
    var envelope: [8_000]f64 = @splat(0.0);
    var beat_time: f64 = 0.1;
    while (beat_time < duration_seconds) {
        const onset_index: usize = @intFromFloat(@round(
            beat_time * envelope_rate,
        ));
        if (onset_index < envelope.len)
            envelope[onset_index] = 1.0;
        const progress = beat_time / duration_seconds;
        const bpm = 120.0 - 40.0 * progress;
        beat_time += 60.0 / bpm;
    }
    var entries: [16]raw.ARAContentTempoEntry = undefined;
    const count = try detectTempoMapEnvelope(
        &envelope,
        envelope_rate,
        .{
            .window_seconds = 8.0,
            .hop_seconds = 4.0,
            .tempo_change_ratio = 0.04,
        },
        &entries,
    );
    try std.testing.expect(count >= 3);
    try std.testing.expect(count <= 10);
    for (entries[1..count], entries[0 .. count - 1]) |
        current,
        previous,
    | {
        try std.testing.expect(
            current.timePosition > previous.timePosition,
        );
        try std.testing.expect(
            current.quarterPosition > previous.quarterPosition,
        );
    }
    const first_bpm =
        (entries[1].quarterPosition -
            entries[0].quarterPosition) /
        (entries[1].timePosition -
            entries[0].timePosition) *
        60.0;
    const last_bpm =
        (entries[count - 1].quarterPosition -
            entries[count - 2].quarterPosition) /
        (entries[count - 1].timePosition -
            entries[count - 2].timePosition) *
        60.0;
    try std.testing.expect(first_bpm >= 110.0);
    try std.testing.expect(first_bpm <= 125.0);
    try std.testing.expect(last_bpm >= 75.0);
    try std.testing.expect(last_bpm <= 90.0);
    try std.testing.expect(last_bpm < first_bpm);
}

test "ARA meter detection distinguishes simple and compound meter" {
    const envelope_rate = 100.0;
    const tempo_entries = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 16.0, .quarterPosition = 32.0 },
    };
    const CandidateFixture = struct {
        candidate: MeterCandidate,
        expected_numerator: i32,
        expected_denominator: i32,
    };
    const fixtures = [_]CandidateFixture{
        .{
            .candidate = meter_candidates[2],
            .expected_numerator = 4,
            .expected_denominator = 4,
        },
        .{
            .candidate = meter_candidates[4],
            .expected_numerator = 6,
            .expected_denominator = 8,
        },
    };
    for (fixtures) |fixture| {
        var envelope: [1_600]f64 = @splat(0.0);
        for (0..64) |pulse| {
            const sample_index = pulse * 25;
            envelope[sample_index] = meterTemplate(
                fixture.candidate,
                pulse % fixture.candidate.pulses,
            );
        }
        var signatures: [2]raw.ARAContentBarSignature =
            undefined;
        const count = try detectBarSignaturesEnvelope(
            &envelope,
            envelope_rate,
            &tempo_entries,
            .{},
            &signatures,
        );
        try std.testing.expectEqual(@as(usize, 1), count);
        try std.testing.expectEqual(
            fixture.expected_numerator,
            signatures[0].numerator,
        );
        try std.testing.expectEqual(
            fixture.expected_denominator,
            signatures[0].denominator,
        );
        try std.testing.expectEqual(
            @as(f64, 0.0),
            signatures[0].position,
        );
    }
}

test "ARA meter detection finds the first downbeat phase" {
    const envelope_rate = 100.0;
    const tempo_entries = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 16.0, .quarterPosition = 32.0 },
    };
    const candidate = meter_candidates[1];
    const phase: usize = 2;
    var envelope: [1_600]f64 = @splat(0.0);
    for (phase..64) |pulse| {
        envelope[pulse * 25] = meterTemplate(
            candidate,
            (pulse - phase) % candidate.pulses,
        );
    }
    var signatures: [1]raw.ARAContentBarSignature = undefined;
    const count = try detectBarSignaturesEnvelope(
        &envelope,
        envelope_rate,
        &tempo_entries,
        .{},
        &signatures,
    );
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(i32, 3), signatures[0].numerator);
    try std.testing.expectEqual(@as(i32, 4), signatures[0].denominator);
    try std.testing.expectEqual(@as(f64, 1.0), signatures[0].position);
}

test "ARA meter detection publishes whole-bar changes" {
    const envelope_rate = 100.0;
    const tempo_entries = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 26.0, .quarterPosition = 52.0 },
    };
    const first = meter_candidates[2];
    const second = meter_candidates[1];
    const transition_pulse: usize = 32;
    var envelope: [2_600]f64 = @splat(0.0);
    for (0..104) |pulse| {
        const candidate =
            if (pulse < transition_pulse) first else second;
        const pattern_pulse =
            if (pulse < transition_pulse)
                pulse % first.pulses
            else
                (pulse - transition_pulse) % second.pulses;
        envelope[pulse * 25] = meterTemplate(
            candidate,
            pattern_pulse,
        );
    }
    var signatures: [4]raw.ARAContentBarSignature = undefined;
    const count = try detectBarSignaturesEnvelope(
        &envelope,
        envelope_rate,
        &tempo_entries,
        .{},
        &signatures,
    );
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqual(@as(i32, 4), signatures[0].numerator);
    try std.testing.expectEqual(@as(i32, 4), signatures[0].denominator);
    try std.testing.expectEqual(@as(f64, 0.0), signatures[0].position);
    try std.testing.expectEqual(@as(i32, 3), signatures[1].numerator);
    try std.testing.expectEqual(@as(i32, 4), signatures[1].denominator);
    try std.testing.expectEqual(@as(f64, 16.0), signatures[1].position);

    var insufficient = [_]raw.ARAContentBarSignature{.{
        .numerator = 7,
        .denominator = 8,
        .position = 9.0,
    }};
    const before = insufficient;
    try std.testing.expectError(
        error.CapacityExceeded,
        detectBarSignaturesEnvelope(
            &envelope,
            envelope_rate,
            &tempo_entries,
            .{},
            &insufficient,
        ),
    );
    try std.testing.expectEqualDeep(before, insufficient);
}

test "ARA meter detection rejects malformed input transactionally" {
    const tempo_entries = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 8.0, .quarterPosition = 16.0 },
    };
    var envelope: [800]f64 = @splat(0.0);
    var signatures = [_]raw.ARAContentBarSignature{.{
        .numerator = 7,
        .denominator = 8,
        .position = 3.5,
    }};
    const before = signatures;
    try std.testing.expectError(
        error.CapacityExceeded,
        detectBarSignaturesEnvelope(
            &envelope,
            100.0,
            &tempo_entries,
            .{},
            signatures[0..0],
        ),
    );
    try std.testing.expectEqualDeep(before, signatures);
    try std.testing.expectError(
        error.SignalTooQuiet,
        detectBarSignaturesEnvelope(
            &envelope,
            100.0,
            &tempo_entries,
            .{},
            &signatures,
        ),
    );
    envelope[envelope.len - 1] = std.math.nan(f64);
    try std.testing.expectError(
        error.MeterNotFound,
        detectBarSignaturesEnvelope(
            &envelope,
            100.0,
            &tempo_entries,
            .{},
            &signatures,
        ),
    );
    const unordered_tempo = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 8.0, .quarterPosition = -1.0 },
    };
    envelope[envelope.len - 1] = 0.0;
    envelope[0] = 1.0;
    try std.testing.expectError(
        error.MeterNotFound,
        detectBarSignaturesEnvelope(
            &envelope,
            100.0,
            &unordered_tempo,
            .{},
            &signatures,
        ),
    );
}

test "ARA note detection publishes a sorted bounded chord" {
    const sample_rate = 8_000.0;
    var samples: [8_000]f64 = undefined;
    const pitches = [_]u8{ 60, 64, 67 };
    for (&samples, 0..) |*sample, sample_index| {
        const time =
            @as(f64, @floatFromInt(sample_index)) / sample_rate;
        sample.* = 0.0;
        for (pitches) |pitch| {
            sample.* += 0.25 * @sin(
                2.0 * std.math.pi *
                    pitchFrequency(pitch) * time,
            );
        }
    }
    const config = NoteDetectionConfig{
        .minimum_pitch = 48,
        .maximum_pitch = 76,
        .maximum_polyphony = 3,
        .minimum_amplitude = 0.05,
    };
    var notes: [8]raw.ARAContentNote = undefined;
    const count = try detectPolyphonicNotes(
        &samples,
        sample_rate,
        config,
        &notes,
    );
    try std.testing.expectEqual(@as(usize, pitches.len), count);
    for (pitches, notes[0..count]) |pitch, note| {
        try std.testing.expectEqual(
            @as(i32, pitch),
            note.pitchNumber,
        );
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(pitchFrequency(pitch))),
            note.frequency,
            1.0,
        );
        try std.testing.expectEqual(@as(f64, 0.0), note.startPosition);
        try std.testing.expect(note.attackDuration > 0.0);
        try std.testing.expect(
            note.attackDuration <= note.noteDuration,
        );
        try std.testing.expectEqual(
            note.noteDuration,
            note.signalDuration,
        );
        try std.testing.expect(note.noteDuration > 0.95);
        try std.testing.expect(note.volume > 0.0);
        try std.testing.expect(note.volume <= 1.0);
    }

    var insufficient = [_]raw.ARAContentNote{.{
        .frequency = 123.0,
        .pitchNumber = 12,
        .volume = 0.5,
        .startPosition = 1.0,
        .attackDuration = 2.0,
        .noteDuration = 3.0,
        .signalDuration = 4.0,
    }};
    const before = insufficient;
    try std.testing.expectError(
        error.CapacityExceeded,
        detectPolyphonicNotes(
            &samples,
            sample_rate,
            config,
            &insufficient,
        ),
    );
    try std.testing.expectEqualDeep(before, insufficient);
}

test "ARA note detection rejects weaker harmonics of one note" {
    const sample_rate = 8_000.0;
    const fundamental_pitch: u8 = 57;
    const fundamental_frequency = pitchFrequency(fundamental_pitch);
    var samples: [8_000]f64 = undefined;
    for (&samples, 0..) |*sample, sample_index| {
        const time =
            @as(f64, @floatFromInt(sample_index)) / sample_rate;
        sample.* = 0.0;
        for (1..7) |harmonic| {
            const harmonic_float: f64 = @floatFromInt(harmonic);
            sample.* += 0.4 / harmonic_float * @sin(
                2.0 * std.math.pi * fundamental_frequency *
                    harmonic_float * time,
            );
        }
    }
    var notes: [8]raw.ARAContentNote = undefined;
    const count = try detectPolyphonicNotes(
        &samples,
        sample_rate,
        .{
            .minimum_pitch = 48,
            .maximum_pitch = 84,
            .minimum_amplitude = 0.03,
        },
        &notes,
    );
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(
        @as(i32, fundamental_pitch),
        notes[0].pitchNumber,
    );
}

test "ARA note detection accepts silence and rejects malformed input" {
    const silence: [512]f64 = @splat(0.0);
    var notes: [2]raw.ARAContentNote = undefined;
    try std.testing.expectEqual(
        @as(usize, 0),
        try detectPolyphonicNotes(
            &silence,
            8_000.0,
            .{},
            &notes,
        ),
    );
    var malformed = silence;
    malformed[malformed.len - 1] = std.math.nan(f64);
    try std.testing.expectError(
        error.NoteNotFound,
        detectPolyphonicNotes(
            &malformed,
            8_000.0,
            .{},
            &notes,
        ),
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        detectPolyphonicNotes(
            &silence,
            8_000.0,
            .{ .maximum_polyphony = 0 },
            &notes,
        ),
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        detectPolyphonicNotes(
            &silence,
            4_000.0,
            .{},
            &notes,
        ),
    );
    try std.testing.expectError(
        error.InvalidSampleCount,
        detectPolyphonicNotes(
            &silence,
            8_000.0,
            .{
                .window_seconds = 1.0e200,
                .hop_seconds = 1.0e200,
            },
            &notes,
        ),
    );
}

const fuzz_empty_analysis_archive =
    "ZTUN\x08\x01\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x00\x00\x00\x00\x00";

const fuzz_tempo_analysis_archive =
    "ZTUN\x04\x01\x00" ++
    "\x00\x00\x02\x00\x00\x00\xdc\x43\x01\x00A" ++
    "\x02\x02\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x00\x00\x00\x00\x00\x00\x00\x00" ++
    "\x00\x00\x00\x00\x00\x00\xe0\x3f" ++
    "\x00\x00\x00\x00\x00\x00\xf0\x3f";

test "fuzz failure-atomic bounded ARA analysis archive restore" {
    try std.testing.fuzz({}, fuzzAnalysisArchiveRestore, .{
        .corpus = &.{
            "ZTUN\x08\x00\x00",
            "ZTUN\x08\x01\x00\x00",
            fuzz_empty_analysis_archive,
            fuzz_tempo_analysis_archive,
        },
    });
}

fn fuzzAnalysisArchiveRestore(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    const TestController = controller_api.Controller(.{
        .audio_sources = 1,
        .name_bytes = 16,
        .persistent_id_bytes = 16,
        .archive_extension_bytes = 16 * 1024,
    });
    const TestAnalyzer = Analyzer(TestController, .{
        .sources = 1,
        .channels = 1,
        .frames = 8,
        .name_bytes = 16,
        .tempo_bins = 8,
        .tempo_entries = 4,
        .bar_signatures = 2,
        .key_signatures = 2,
        .chords = 2,
        .note_entries = 2,
    });
    var factory = std.mem.zeroes(raw.ARAFactory);
    var controller = TestController{
        .host = std.mem.zeroes(raw.ARADocumentControllerHostInstance),
        .factory = &factory,
    };
    try controller.document.beginEditing();
    const source_id = try controller.document.createAudioSource(
        null,
        .{
            .name = "Source",
            .persistent_id = "source-1",
            .sample_count = 8,
            .sample_rate = 48_000.0,
            .channel_count = 1,
        },
    );
    _ = try controller.document.endEditing();

    var analyzer = TestAnalyzer.init(&controller);
    analyzer.slots[0].source_id = source_id;
    analyzer.slots[0].status = .approved;
    analyzer.slots[0].tuning.concertPitchFrequency = 442.0;
    const baseline = analyzer.slots;
    const mappings = [_]TestController.ArchiveSourceMapping{.{
        .archive_id = "source-1",
        .current_id = source_id,
    }};
    var storage: [16 * 1024]u8 = undefined;
    const length = smith.slice(&storage);
    const input = storage[0..length];

    if (analyzer.restoreArchiveChecked(&mappings, input)) |_| {
        var replay = TestAnalyzer.init(&controller);
        replay.slots = baseline;
        try replay.restoreArchiveChecked(&mappings, input);
        if (!std.meta.eql(analyzer.slots, replay.slots))
            return error.InvalidArchive;
    } else |_| {
        if (std.mem.eql(u8, input, fuzz_empty_analysis_archive) or
            std.mem.eql(u8, input, fuzz_tempo_analysis_archive))
            return error.InvalidArchive;
        if (!std.meta.eql(baseline, analyzer.slots))
            return error.InvalidArchive;
    }
}

test "ARA tuning analyzer fulfills requests, publishes content, and invalidates" {
    const TestController = controller_api.Controller(.{
        .audio_sources = 1,
        .audio_readers = 1,
        .content_readers = 1,
        .name_bytes = 32,
        .persistent_id_bytes = 32,
        .archive_extension_bytes = 512,
    });
    const TestAnalyzer = Analyzer(TestController, .{
        .sources = 1,
        .channels = 2,
        .frames = 32_000,
        .tempo_bins = 2_000,
        .note_entries = 256,
    });
    const AudioState = struct {
        samples: [2][32_000]f64,
        open_count: usize = 0,
        destroy_count: usize = 0,
        progress_count: usize = 0,
        content_change_count: usize = 0,
        archive: [1_024]u8 = @splat(0),
        archive_length: usize = 0,
    };
    const Host = struct {
        fn state(pointer: ?*anyopaque) *AudioState {
            return @ptrCast(@alignCast(pointer.?));
        }

        fn createReader(
            host_ref: raw.ARAAudioAccessControllerHostRef,
            source_ref: raw.ARAAudioSourceHostRef,
            use_64_bit_samples: raw.ARABool,
        ) callconv(.c) raw.ARAAudioReaderHostRef {
            _ = source_ref;
            if (use_64_bit_samples != raw.kARATrue) return null;
            const audio = state(host_ref);
            audio.open_count += 1;
            return @ptrFromInt(0x1000);
        }

        fn readSamples(
            host_ref: raw.ARAAudioAccessControllerHostRef,
            reader_ref: raw.ARAAudioReaderHostRef,
            sample_position: raw.ARASamplePosition,
            sample_count: raw.ARASampleCount,
            buffers: [*c]const ?*anyopaque,
        ) callconv(.c) raw.ARABool {
            _ = reader_ref;
            if (sample_position < 0 or
                sample_count < 0 or
                buffers == null)
                return raw.kARAFalse;
            const audio = state(host_ref);
            const start: usize = @intCast(sample_position);
            const count: usize = @intCast(sample_count);
            if (start > audio.samples[0].len or
                count > audio.samples[0].len - start)
                return raw.kARAFalse;
            for (0..audio.samples.len) |channel| {
                const pointer = buffers[channel] orelse
                    return raw.kARAFalse;
                const destination: [*]f64 =
                    @ptrCast(@alignCast(pointer));
                @memcpy(
                    destination[0..count],
                    audio.samples[channel][start..][0..count],
                );
            }
            return raw.kARATrue;
        }

        fn destroyReader(
            host_ref: raw.ARAAudioAccessControllerHostRef,
            reader_ref: raw.ARAAudioReaderHostRef,
        ) callconv(.c) void {
            _ = reader_ref;
            const audio = state(host_ref);
            if (audio.open_count > 0) audio.open_count -= 1;
            audio.destroy_count += 1;
        }

        fn progress(
            host_ref: raw.ARAModelUpdateControllerHostRef,
            source_ref: raw.ARAAudioSourceHostRef,
            progress_state: raw.ARAAnalysisProgressState,
            value: f32,
        ) callconv(.c) void {
            _ = source_ref;
            _ = progress_state;
            _ = value;
            state(host_ref).progress_count += 1;
        }

        fn changed(
            host_ref: raw.ARAModelUpdateControllerHostRef,
            source_ref: raw.ARAAudioSourceHostRef,
            range: [*c]const raw.ARAContentTimeRange,
            flags: raw.ARAContentUpdateFlags,
        ) callconv(.c) void {
            _ = source_ref;
            _ = range;
            _ = flags;
            state(host_ref).content_change_count += 1;
        }

        fn archiveSize(
            host_ref: raw.ARAArchivingControllerHostRef,
            reader_ref: raw.ARAArchiveReaderHostRef,
        ) callconv(.c) raw.ARASize {
            _ = reader_ref;
            return state(host_ref).archive_length;
        }

        fn readArchive(
            host_ref: raw.ARAArchivingControllerHostRef,
            reader_ref: raw.ARAArchiveReaderHostRef,
            position: raw.ARASize,
            length: raw.ARASize,
            buffer: [*c]raw.ARAByte,
        ) callconv(.c) raw.ARABool {
            _ = reader_ref;
            const audio = state(host_ref);
            if (buffer == null or
                position > audio.archive_length or
                length > audio.archive_length - position)
                return raw.kARAFalse;
            @memcpy(
                buffer[0..length],
                audio.archive[position..][0..length],
            );
            return raw.kARATrue;
        }

        fn writeArchive(
            host_ref: raw.ARAArchivingControllerHostRef,
            writer_ref: raw.ARAArchiveWriterHostRef,
            position: raw.ARASize,
            length: raw.ARASize,
            buffer: [*c]const raw.ARAByte,
        ) callconv(.c) raw.ARABool {
            _ = writer_ref;
            const audio = state(host_ref);
            if (buffer == null or
                position > audio.archive.len or
                length > audio.archive.len - position)
                return raw.kARAFalse;
            @memcpy(
                audio.archive[position..][0..length],
                buffer[0..length],
            );
            audio.archive_length =
                @max(audio.archive_length, position + length);
            return raw.kARATrue;
        }

        const audio_interface =
            raw.ARAAudioAccessControllerInterface{
                .structSize = @sizeOf(raw.ARAAudioAccessControllerInterface),
                .createAudioReaderForSource = createReader,
                .readAudioSamples = readSamples,
                .destroyAudioReader = destroyReader,
            };
        const archive_interface =
            raw.ARAArchivingControllerInterface{
                .structSize = @sizeOf(raw.ARAArchivingControllerInterface),
                .getArchiveSize = archiveSize,
                .readBytesFromArchive = readArchive,
                .writeBytesToArchive = writeArchive,
            };
        const content_interface =
            raw.ARAContentAccessControllerInterface{
                .structSize = @sizeOf(raw.ARAContentAccessControllerInterface),
            };
        const model_update_interface =
            raw.ARAModelUpdateControllerInterface{
                .structSize = @sizeOf(raw.ARAModelUpdateControllerInterface),
                .notifyAudioSourceAnalysisProgress = progress,
                .notifyAudioSourceContentChanged = changed,
            };
        const playback_interface =
            raw.ARAPlaybackControllerInterface{
                .structSize = @sizeOf(raw.ARAPlaybackControllerInterface),
            };
    };

    const sample_rate = 4_000.0;
    const concert_pitch = 441.5;
    var audio = AudioState{ .samples = undefined };
    for (&audio.samples[0], 0..) |*sample, frame| {
        const phase = 2.0 * std.math.pi * concert_pitch *
            @as(f64, @floatFromInt(frame)) / sample_rate;
        sample.* = 0.4 * @sin(phase);
        audio.samples[1][frame] = -sample.*;
    }
    var host = raw.ARADocumentControllerHostInstance{
        .structSize = @sizeOf(raw.ARADocumentControllerHostInstance),
        .audioAccessControllerHostRef = @ptrCast(&audio),
        .audioAccessControllerInterface = &Host.audio_interface,
        .archivingControllerHostRef = @ptrCast(&audio),
        .archivingControllerInterface = &Host.archive_interface,
        .contentAccessControllerHostRef = null,
        .contentAccessControllerInterface = &Host.content_interface,
        .modelUpdateControllerHostRef = @ptrCast(&audio),
        .modelUpdateControllerInterface = &Host.model_update_interface,
        .playbackControllerHostRef = null,
        .playbackControllerInterface = &Host.playback_interface,
    };
    const analyzeable = [_]raw.ARAContentType{
        raw.kARAContentTypeNotes,
        raw.kARAContentTypeStaticTuning,
        raw.kARAContentTypeTempoEntries,
        raw.kARAContentTypeBarSignatures,
        raw.kARAContentTypeKeySignatures,
        raw.kARAContentTypeSheetChords,
    };
    var factory = std.mem.zeroes(raw.ARAFactory);
    factory.analyzeableContentTypesCount = analyzeable.len;
    factory.analyzeableContentTypes = &analyzeable;
    var properties = raw.ARADocumentProperties{
        .structSize = @sizeOf(raw.ARADocumentProperties),
        .name = "Tuning analysis",
    };
    var controller: TestController = undefined;
    try controller.init(&factory, &host, &properties);
    var source_host_token: u8 = 0;
    try controller.document.beginEditing();
    const source_id = try controller.document.createAudioSource(
        @ptrCast(&source_host_token),
        .{
            .name = "A4",
            .persistent_id = "source-a4",
            .sample_count = audio.samples[0].len,
            .sample_rate = sample_rate,
            .channel_count = 2,
        },
    );
    _ = try controller.document.endEditing();
    try controller.setAudioSourceSamplesAccess(source_id, true);
    var analyzer = TestAnalyzer.init(&controller);
    analyzer.detection_config.maximum_frequency = 1_900.0;
    analyzer.note_detection_config.maximum_pitch = 95;
    analyzer.key_signature_detection_config = .{
        .window_quarters = 8,
        .hop_quarters = 8,
        .minimum_note_weight = 0.01,
        .minimum_score = -1.0,
        .minimum_score_margin = 0.0,
        .change_confirmation_windows = 1,
    };
    analyzer.chord_detection_config = .{
        .window_quarters = 4,
        .hop_quarters = 4,
        .minimum_note_weight = 0.01,
        .minimum_score = 0.5,
        .minimum_score_margin = 0.0,
        .change_confirmation_windows = 1,
    };
    try analyzer.attach();
    defer analyzer.detach() catch {};

    const source_ref: raw.ARAAudioSourceRef =
        @ptrFromInt(
            (@as(usize, source_id.generation) << 16) |
                (@as(usize, source_id.index) + 1),
        );
    const instance = controller.documentControllerInstance();
    const api: *const raw.ARADocumentControllerInterface =
        @ptrCast(instance.documentControllerInterface);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.processing_algorithm_count),
        api.getProcessingAlgorithmsCount.?(
            instance.documentControllerRef,
        ),
    );
    const general_properties =
        api.getProcessingAlgorithmProperties.?(
            instance.documentControllerRef,
            TestAnalyzer.general_algorithm_index,
        );
    try std.testing.expect(general_properties != null);
    try std.testing.expectEqualStrings(
        "dev.zig-vst3.analysis.general",
        std.mem.sliceTo(general_properties[0].persistentID, 0),
    );
    try std.testing.expectEqualStrings(
        "General music analysis",
        std.mem.sliceTo(general_properties[0].name, 0),
    );
    try std.testing.expect(
        api.getProcessingAlgorithmProperties.?(
            instance.documentControllerRef,
            -1,
        ) == null,
    );
    try std.testing.expectEqual(
        error.InvalidProcessingAlgorithm,
        controller.takeLastError().?,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.general_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    api.requestProcessingAlgorithmForAudioSource.?(
        instance.documentControllerRef,
        source_ref,
        TestAnalyzer.low_register_algorithm_index,
    );
    try std.testing.expectEqual(
        error.NotEditing,
        controller.takeLastError().?,
    );
    api.beginEditing.?(instance.documentControllerRef);
    api.requestProcessingAlgorithmForAudioSource.?(
        instance.documentControllerRef,
        source_ref,
        TestAnalyzer.low_register_algorithm_index,
    );
    api.endEditing.?(instance.documentControllerRef);
    try std.testing.expect(controller.takeLastError() == null);
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.low_register_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        audio.content_change_count,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAnalysisIncomplete.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    const tuning_request = [_]raw.ARAContentType{
        raw.kARAContentTypeStaticTuning,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        tuning_request.len,
        &tuning_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(@as(usize, 2), audio.progress_count);
    try std.testing.expectEqual(
        @as(usize, 2),
        audio.content_change_count,
    );
    try std.testing.expectEqual(@as(usize, 1), audio.destroy_count);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeDetected,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    var reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    try std.testing.expect(reader != null);
    const event_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const tuning: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(event_pointer));
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(concert_pitch)),
        tuning.concertPitchFrequency,
        0.2,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    const note_request = [_]raw.ARAContentType{
        raw.kARAContentTypeNotes,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        note_request.len,
        &note_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(@as(usize, 4), audio.progress_count);
    try std.testing.expectEqual(
        @as(usize, 3),
        audio.content_change_count,
    );
    try std.testing.expectEqual(@as(usize, 2), audio.destroy_count);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeDetected,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeNotes,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const note_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const detected_note: *const raw.ARAContentNote =
        @ptrCast(@alignCast(note_pointer));
    try std.testing.expectEqual(@as(i32, 69), detected_note.pitchNumber);
    try std.testing.expectApproxEqAbs(
        @as(f32, @floatCast(concert_pitch)),
        detected_note.frequency,
        1.0,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    for (&audio.samples[0], 0..) |*sample, frame| {
        const phase = frame % 2_000;
        const beat = frame / 2_000;
        const time =
            @as(f64, @floatFromInt(frame)) / sample_rate;
        const accent: f64 = switch (beat % 4) {
            0 => 1.0,
            2 => 0.85,
            else => 0.7,
        };
        const transient = if (phase < 20)
            accent *
                (1.0 -
                    @as(f64, @floatFromInt(phase)) / 20.0)
        else
            0.0;
        const envelope =
            @min(1.0, @as(f64, @floatFromInt(phase)) / 80.0);
        sample.* = transient;
        for ([_]u8{ 60, 64, 67 }) |pitch| {
            sample.* += 0.04 * envelope * @sin(
                2.0 * std.math.pi *
                    pitchFrequency(pitch) * time,
            );
        }
        audio.samples[1][frame] = sample.*;
    }
    api.updateAudioSourceContent.?(
        instance.documentControllerRef,
        source_ref,
        null,
        raw.kARAContentUpdateTuningScopeRemainsUnchanged,
    );
    const tempo_request = [_]raw.ARAContentType{
        raw.kARAContentTypeTempoEntries,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        tempo_request.len,
        &tempo_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeDetected,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeTempoEntries,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 2),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const first_tempo_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const second_tempo_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const first_tempo: *const raw.ARAContentTempoEntry =
        @ptrCast(@alignCast(first_tempo_pointer));
    const second_tempo: *const raw.ARAContentTempoEntry =
        @ptrCast(@alignCast(second_tempo_pointer));
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        first_tempo.timePosition,
        0.01,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 120.0),
        (second_tempo.quarterPosition -
            first_tempo.quarterPosition) /
            (second_tempo.timePosition -
                first_tempo.timePosition) *
            60.0,
        0.1,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        first_tempo.quarterPosition,
    );
    try std.testing.expectEqual(
        @as(f64, 16.0),
        second_tempo.quarterPosition,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(@as(usize, 6), audio.progress_count);
    try std.testing.expectEqual(
        @as(usize, 4),
        audio.content_change_count,
    );
    try std.testing.expectEqual(@as(usize, 3), audio.destroy_count);

    const meter_request = [_]raw.ARAContentType{
        raw.kARAContentTypeBarSignatures,
        raw.kARAContentTypeTempoEntries,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        meter_request.len,
        &meter_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(@as(usize, 8), audio.progress_count);
    try std.testing.expectEqual(
        @as(usize, 5),
        audio.content_change_count,
    );
    try std.testing.expectEqual(@as(usize, 4), audio.destroy_count);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeBarSignatures,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeBarSignatures,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const meter_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const meter: *const raw.ARAContentBarSignature =
        @ptrCast(@alignCast(meter_pointer));
    try std.testing.expectEqual(@as(i32, 4), meter.numerator);
    try std.testing.expectEqual(@as(i32, 4), meter.denominator);
    try std.testing.expectEqual(@as(f64, 0.0), meter.position);
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    const key_request = [_]raw.ARAContentType{
        raw.kARAContentTypeKeySignatures,
        raw.kARAContentTypeSheetChords,
        raw.kARAContentTypeNotes,
        raw.kARAContentTypeTempoEntries,
    };
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        key_request.len,
        &key_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(@as(usize, 12), audio.progress_count);
    try std.testing.expectEqual(
        @as(usize, 7),
        audio.content_change_count,
    );
    try std.testing.expectEqual(@as(usize, 8), audio.destroy_count);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeKeySignatures,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeKeySignatures,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const key_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const key: *const raw.ARAContentKeySignature =
        @ptrCast(@alignCast(key_pointer));
    try std.testing.expectEqual(@as(i32, 0), key.root);
    try std.testing.expectEqualSlices(
        u8,
        &major_intervals,
        &key.intervals,
    );
    try std.testing.expectEqual(@as(f64, 0.0), key.position);
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeSheetChords,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeSheetChords,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const chord_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const chord: *const raw.ARAContentChord =
        @ptrCast(@alignCast(chord_pointer));
    try std.testing.expectEqual(@as(i32, 0), chord.root);
    try std.testing.expectEqual(@as(i32, 0), chord.bass);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[0].intervals,
        &chord.intervals,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    api.updateAudioSourceContent.?(
        instance.documentControllerRef,
        source_ref,
        null,
        raw.kARAContentUpdateTimingScopeRemainsUnchanged |
            raw.kARAContentUpdateHarmonicScopeRemainsUnchanged,
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    try analyzer.approveEqualTemperament(
        source_id,
        443.0,
        "Approved session tuning",
    );
    try std.testing.expectEqual(
        raw.kARAContentGradeApproved,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const approved_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const approved: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(approved_pointer));
    try std.testing.expectEqual(
        @as(f32, 443.0),
        approved.concertPitchFrequency,
    );
    try std.testing.expectEqualStrings(
        "Approved session tuning",
        std.mem.sliceTo(approved.name, 0),
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    const archive_ref: *AudioState = &audio;
    try std.testing.expectEqual(
        raw.kARATrue,
        api.storeObjectsToArchive.?(
            instance.documentControllerRef,
            @ptrCast(archive_ref),
            null,
        ),
    );
    try std.testing.expect(audio.archive_length > 0);
    analyzer.invalidate(source_id);
    api.beginEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.restoreObjectsFromArchive.?(
            instance.documentControllerRef,
            @ptrCast(archive_ref),
            null,
        ),
    );
    api.endEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        raw.kARAContentGradeApproved,
        api.getAudioSourceContentGrade.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const restored_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const restored: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(restored_pointer));
    try std.testing.expectEqual(
        @as(f32, 443.0),
        restored.concertPitchFrequency,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.low_register_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeTempoEntries,
        null,
    );
    const restored_tempo_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const restored_tempo: *const raw.ARAContentTempoEntry =
        @ptrCast(@alignCast(restored_tempo_pointer));
    try std.testing.expectApproxEqAbs(
        @as(f64, 120.0),
        restored_tempo.quarterPosition /
            restored_tempo.timePosition *
            60.0,
        0.1,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeBarSignatures,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeBarSignatures,
        null,
    );
    const restored_meter_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const restored_meter: *const raw.ARAContentBarSignature =
        @ptrCast(@alignCast(restored_meter_pointer));
    try std.testing.expectEqual(
        @as(i32, 4),
        restored_meter.numerator,
    );
    try std.testing.expectEqual(
        @as(i32, 4),
        restored_meter.denominator,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeKeySignatures,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeKeySignatures,
        null,
    );
    const restored_key_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const restored_key: *const raw.ARAContentKeySignature =
        @ptrCast(@alignCast(restored_key_pointer));
    try std.testing.expectEqual(@as(i32, 0), restored_key.root);
    try std.testing.expectEqualSlices(
        u8,
        &major_intervals,
        &restored_key.intervals,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeSheetChords,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeSheetChords,
        null,
    );
    const restored_chord_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const restored_chord: *const raw.ARAContentChord =
        @ptrCast(@alignCast(restored_chord_pointer));
    try std.testing.expectEqual(@as(i32, 0), restored_chord.root);
    try std.testing.expectEqualSlices(
        u8,
        &chord_templates[0].intervals,
        &restored_chord.intervals,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    api.requestAudioSourceContentAnalysis.?(
        instance.documentControllerRef,
        source_ref,
        tempo_request.len,
        &tempo_request,
    );
    try std.testing.expect(analyzer.takeLastError() == null);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeBarSignatures,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeKeySignatures,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeSheetChords,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );

    try analyzer.approveEqualTemperament(
        source_id,
        444.0,
        "Temporary tuning",
    );
    const archive_source_ids =
        [_]raw.ARAPersistentID{"source-a4"};
    var restore_filter = raw.ARARestoreObjectsFilter{
        .structSize = @sizeOf(raw.ARARestoreObjectsFilter),
        .documentData = raw.kARAFalse,
        .audioSourceIDsCount = archive_source_ids.len,
        .audioSourceArchiveIDs = &archive_source_ids,
        .audioSourceCurrentIDs = null,
        .audioModificationIDsCount = 0,
        .audioModificationArchiveIDs = null,
        .audioModificationCurrentIDs = null,
    };
    api.beginEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        raw.kARATrue,
        api.restoreObjectsFromArchive.?(
            instance.documentControllerRef,
            @ptrCast(archive_ref),
            &restore_filter,
        ),
    );
    api.endEditing.?(instance.documentControllerRef);
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const filtered_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const filtered: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(filtered_pointer));
    try std.testing.expectEqual(
        @as(f32, 443.0),
        filtered.concertPitchFrequency,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );

    try analyzer.approveEqualTemperament(
        source_id,
        444.0,
        "Current tuning",
    );
    const extension_offset = std.mem.indexOf(
        u8,
        audio.archive[0..audio.archive_length],
        &analysis_archive_magic,
    ) orelse return error.TestUnexpectedResult;
    const processing_algorithm_offset =
        extension_offset +
        analysis_archive_magic.len +
        1 +
        2 +
        2 +
        1;
    audio.archive[processing_algorithm_offset] = 0xff;
    api.beginEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.restoreObjectsFromArchive.?(
            instance.documentControllerRef,
            @ptrCast(archive_ref),
            null,
        ),
    );
    api.endEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const retained_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const retained: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(retained_pointer));
    try std.testing.expectEqual(
        @as(f32, 444.0),
        retained.concertPitchFrequency,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    audio.archive[processing_algorithm_offset] =
        TestAnalyzer.low_register_algorithm_index;
    const name_length_offset =
        processing_algorithm_offset + 1 + 4;
    const stored_name_length =
        @as(usize, audio.archive[name_length_offset]) |
        (@as(usize, audio.archive[name_length_offset + 1]) << 8);
    const stored_second_time_offset =
        name_length_offset +
        2 +
        stored_name_length +
        1 +
        2 +
        16;
    @memset(
        audio.archive[stored_second_time_offset..][0..8],
        0,
    );
    api.beginEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.restoreObjectsFromArchive.?(
            instance.documentControllerRef,
            @ptrCast(archive_ref),
            null,
        ),
    );
    api.endEditing.?(instance.documentControllerRef);
    try std.testing.expectEqual(
        error.InvalidArchive,
        controller.takeLastError().?,
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );

    const legacy_name = "Legacy";
    var legacy_payload: [archive_header_size + 2 + 1 + 4 + 2 + legacy_name.len]u8 =
        undefined;
    var legacy_writer = ByteWriter.init(&legacy_payload);
    try legacy_writer.bytes(&analysis_archive_magic);
    try legacy_writer.byte(1);
    try legacy_writer.integer16(1);
    try legacy_writer.integer16(0);
    try legacy_writer.byte(2);
    try legacy_writer.integer32(@bitCast(@as(f32, 445.0)));
    try legacy_writer.integer16(legacy_name.len);
    try legacy_writer.bytes(legacy_name);
    try std.testing.expect(legacy_writer.finished());
    const legacy_mappings =
        [_]TestController.ArchiveSourceMapping{.{
            .archive_id = "source-a4",
            .current_id = source_id,
        }};
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &legacy_payload,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.general_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const legacy_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const legacy: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(legacy_pointer));
    try std.testing.expectEqual(
        @as(f32, 445.0),
        legacy.concertPitchFrequency,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeTempoEntries,
        ),
    );

    const version_two_name = "Version two";
    var version_two_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 + version_two_name.len
    ]u8 =
        undefined;
    var version_two_writer = ByteWriter.init(&version_two_payload);
    try version_two_writer.bytes(&analysis_archive_magic);
    try version_two_writer.byte(2);
    try version_two_writer.integer16(1);
    try version_two_writer.integer16(0);
    try version_two_writer.byte(2);
    try version_two_writer.byte(
        TestAnalyzer.low_register_algorithm_index,
    );
    try version_two_writer.integer32(@bitCast(@as(f32, 446.0)));
    try version_two_writer.integer16(version_two_name.len);
    try version_two_writer.bytes(version_two_name);
    try std.testing.expect(version_two_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_two_payload,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.low_register_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeStaticTuning,
        null,
    );
    const version_two_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const version_two: *const raw.ARAContentTuning =
        @ptrCast(@alignCast(version_two_pointer));
    try std.testing.expectEqual(
        @as(f32, 446.0),
        version_two.concertPitchFrequency,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    const version_three_name = "Version three";
    var version_three_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 + version_three_name.len +
            1 + 8 + 8
    ]u8 = undefined;
    var version_three_writer = ByteWriter.init(
        &version_three_payload,
    );
    try version_three_writer.bytes(&analysis_archive_magic);
    try version_three_writer.byte(3);
    try version_three_writer.integer16(1);
    try version_three_writer.integer16(0);
    try version_three_writer.byte(2);
    try version_three_writer.byte(
        TestAnalyzer.low_register_algorithm_index,
    );
    try version_three_writer.integer32(
        @bitCast(@as(f32, 447.0)),
    );
    try version_three_writer.integer16(version_three_name.len);
    try version_three_writer.bytes(version_three_name);
    try version_three_writer.byte(1);
    try version_three_writer.integer64(
        @bitCast(@as(f64, 0.25)),
    );
    try version_three_writer.integer64(
        @bitCast(@as(f64, 0.5)),
    );
    try std.testing.expect(version_three_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_three_payload,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.low_register_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeTempoEntries,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 2),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const version_three_first_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const version_three_second_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const version_three_first: *const raw.ARAContentTempoEntry =
        @ptrCast(@alignCast(version_three_first_pointer));
    const version_three_second: *const raw.ARAContentTempoEntry =
        @ptrCast(@alignCast(version_three_second_pointer));
    try std.testing.expectEqual(
        @as(f64, 0.25),
        version_three_first.timePosition,
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        version_three_first.quarterPosition,
    );
    try std.testing.expectEqual(
        @as(f64, 0.75),
        version_three_second.timePosition,
    );
    try std.testing.expectEqual(
        @as(f64, 1.0),
        version_three_second.quarterPosition,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var version_four_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 +
            1 + 2 + 3 * 16
    ]u8 = undefined;
    var version_four_writer = ByteWriter.init(
        &version_four_payload,
    );
    try version_four_writer.bytes(&analysis_archive_magic);
    try version_four_writer.byte(4);
    try version_four_writer.integer16(1);
    try version_four_writer.integer16(0);
    try version_four_writer.byte(0);
    try version_four_writer.byte(
        TestAnalyzer.general_algorithm_index,
    );
    try version_four_writer.integer32(0);
    try version_four_writer.integer16(0);
    try version_four_writer.byte(1);
    try version_four_writer.integer16(3);
    const version_four_entries = [_]raw.ARAContentTempoEntry{
        .{ .timePosition = 0.0, .quarterPosition = 0.0 },
        .{ .timePosition = 10.0, .quarterPosition = 20.0 },
        .{ .timePosition = 20.0, .quarterPosition = 100.0 / 3.0 },
    };
    for (version_four_entries) |entry| {
        try version_four_writer.integer64(
            @bitCast(entry.timePosition),
        );
        try version_four_writer.integer64(
            @bitCast(entry.quarterPosition),
        );
    }
    try std.testing.expect(version_four_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_four_payload,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, TestAnalyzer.general_algorithm_index),
        api.getProcessingAlgorithmForAudioSource.?(
            instance.documentControllerRef,
            source_ref,
        ),
    );
    try std.testing.expectEqual(
        raw.kARAFalse,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeStaticTuning,
        ),
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeTempoEntries,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, version_four_entries.len),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    for (version_four_entries, 0..) |expected, event_index| {
        const version_four_event_pointer =
            api.getContentReaderDataForEvent.?(
                instance.documentControllerRef,
                reader,
                @intCast(event_index),
            ) orelse return error.TestUnexpectedResult;
        const actual: *const raw.ARAContentTempoEntry =
            @ptrCast(@alignCast(version_four_event_pointer));
        try std.testing.expectEqual(
            expected.timePosition,
            actual.timePosition,
        );
        try std.testing.expectEqual(
            expected.quarterPosition,
            actual.quarterPosition,
        );
    }
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var version_five_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 +
            1 + 2 + 1 + 2 + 2 * archive_note_size
    ]u8 = undefined;
    var version_five_writer = ByteWriter.init(
        &version_five_payload,
    );
    try version_five_writer.bytes(&analysis_archive_magic);
    try version_five_writer.byte(5);
    try version_five_writer.integer16(1);
    try version_five_writer.integer16(0);
    try version_five_writer.byte(0);
    try version_five_writer.byte(
        TestAnalyzer.general_algorithm_index,
    );
    try version_five_writer.integer32(0);
    try version_five_writer.integer16(0);
    try version_five_writer.byte(0);
    try version_five_writer.integer16(0);
    try version_five_writer.byte(1);
    try version_five_writer.integer16(2);
    const version_five_notes = [_]raw.ARAContentNote{
        .{
            .frequency = 440.0,
            .pitchNumber = 69,
            .volume = 0.75,
            .startPosition = 0.0,
            .attackDuration = 0.02,
            .noteDuration = 0.4,
            .signalDuration = 0.5,
        },
        .{
            .frequency = 523.251,
            .pitchNumber = 72,
            .volume = 0.5,
            .startPosition = 0.75,
            .attackDuration = 0.03,
            .noteDuration = 0.45,
            .signalDuration = 0.6,
        },
    };
    for (version_five_notes) |note| {
        try version_five_writer.integer32(
            @bitCast(note.frequency),
        );
        try version_five_writer.integer32(
            @bitCast(note.pitchNumber),
        );
        try version_five_writer.integer32(
            @bitCast(note.volume),
        );
        try version_five_writer.integer64(
            @bitCast(note.startPosition),
        );
        try version_five_writer.integer64(
            @bitCast(note.attackDuration),
        );
        try version_five_writer.integer64(
            @bitCast(note.noteDuration),
        );
        try version_five_writer.integer64(
            @bitCast(note.signalDuration),
        );
    }
    try std.testing.expect(version_five_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_five_payload,
    );
    var note_range = raw.ARAContentTimeRange{
        .start = 0.7,
        .duration = 0.7,
    };
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeNotes,
        &note_range,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, 1),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const version_five_note_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            0,
        ) orelse return error.TestUnexpectedResult;
    const version_five_note: *const raw.ARAContentNote =
        @ptrCast(@alignCast(version_five_note_pointer));
    try std.testing.expectEqual(
        version_five_notes[1].pitchNumber,
        version_five_note.pitchNumber,
    );
    try std.testing.expectEqual(
        version_five_notes[1].startPosition,
        version_five_note.startPosition,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var corrupt_version_five = version_five_payload;
    const first_note_volume_offset =
        archive_header_size +
        2 + 1 + 1 + 4 + 2 +
        1 + 2 + 1 + 2 + 4 + 4;
    var corrupt_volume_writer = ByteWriter.init(
        corrupt_version_five[first_note_volume_offset .. first_note_volume_offset + 4],
    );
    try corrupt_volume_writer.integer32(
        @bitCast(@as(f32, 2.0)),
    );
    try std.testing.expectError(
        error.InvalidArchive,
        analyzer.restoreArchiveChecked(
            &legacy_mappings,
            &corrupt_version_five,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeNotes,
        ),
    );

    var version_six_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 +
            1 + 2 + 2 * 16 +
            1 + 2 + 2 * archive_bar_signature_size +
            1 + 2
    ]u8 = undefined;
    var version_six_writer = ByteWriter.init(
        &version_six_payload,
    );
    try version_six_writer.bytes(&analysis_archive_magic);
    try version_six_writer.byte(6);
    try version_six_writer.integer16(1);
    try version_six_writer.integer16(0);
    try version_six_writer.byte(0);
    try version_six_writer.byte(
        TestAnalyzer.general_algorithm_index,
    );
    try version_six_writer.integer32(0);
    try version_six_writer.integer16(0);
    try version_six_writer.byte(1);
    try version_six_writer.integer16(2);
    try version_six_writer.integer64(@bitCast(@as(f64, 0.0)));
    try version_six_writer.integer64(@bitCast(@as(f64, 0.0)));
    try version_six_writer.integer64(@bitCast(@as(f64, 8.0)));
    try version_six_writer.integer64(@bitCast(@as(f64, 16.0)));
    try version_six_writer.byte(1);
    try version_six_writer.integer16(2);
    const version_six_signatures =
        [_]raw.ARAContentBarSignature{
            .{
                .numerator = 4,
                .denominator = 4,
                .position = 0.0,
            },
            .{
                .numerator = 3,
                .denominator = 4,
                .position = 8.0,
            },
        };
    for (version_six_signatures) |signature| {
        try version_six_writer.integer32(@bitCast(
            signature.numerator,
        ));
        try version_six_writer.integer32(@bitCast(
            signature.denominator,
        ));
        try version_six_writer.integer64(@bitCast(
            signature.position,
        ));
    }
    try version_six_writer.byte(0);
    try version_six_writer.integer16(0);
    try std.testing.expect(version_six_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_six_payload,
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeBarSignatures,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, version_six_signatures.len),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const second_meter_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const second_meter: *const raw.ARAContentBarSignature =
        @ptrCast(@alignCast(second_meter_pointer));
    try std.testing.expectEqual(
        version_six_signatures[1].numerator,
        second_meter.numerator,
    );
    try std.testing.expectEqual(
        version_six_signatures[1].position,
        second_meter.position,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var corrupt_version_six = version_six_payload;
    const second_meter_position_offset =
        archive_header_size +
        2 + 1 + 1 + 4 + 2 +
        1 + 2 + 2 * 16 +
        1 + 2 + archive_bar_signature_size + 4 + 4;
    var corrupt_meter_writer = ByteWriter.init(
        corrupt_version_six[second_meter_position_offset .. second_meter_position_offset + 8],
    );
    try corrupt_meter_writer.integer64(
        @bitCast(@as(f64, 9.0)),
    );
    try std.testing.expectError(
        error.InvalidArchive,
        analyzer.restoreArchiveChecked(
            &legacy_mappings,
            &corrupt_version_six,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeBarSignatures,
        ),
    );

    var version_seven_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 +
            1 + 2 + 2 * 16 +
            1 + 2 +
            1 + 2 +
            1 + 2 + 2 * archive_key_signature_size
    ]u8 = undefined;
    var version_seven_writer = ByteWriter.init(
        &version_seven_payload,
    );
    try version_seven_writer.bytes(&analysis_archive_magic);
    try version_seven_writer.byte(7);
    try version_seven_writer.integer16(1);
    try version_seven_writer.integer16(0);
    try version_seven_writer.byte(0);
    try version_seven_writer.byte(
        TestAnalyzer.general_algorithm_index,
    );
    try version_seven_writer.integer32(0);
    try version_seven_writer.integer16(0);
    try version_seven_writer.byte(1);
    try version_seven_writer.integer16(2);
    try version_seven_writer.integer64(
        @bitCast(@as(f64, 0.0)),
    );
    try version_seven_writer.integer64(
        @bitCast(@as(f64, 0.0)),
    );
    try version_seven_writer.integer64(
        @bitCast(@as(f64, 8.0)),
    );
    try version_seven_writer.integer64(
        @bitCast(@as(f64, 16.0)),
    );
    try version_seven_writer.byte(0);
    try version_seven_writer.integer16(0);
    try version_seven_writer.byte(0);
    try version_seven_writer.integer16(0);
    try version_seven_writer.byte(1);
    try version_seven_writer.integer16(2);
    const version_seven_keys =
        [_]raw.ARAContentKeySignature{
            .{
                .root = 0,
                .intervals = major_intervals,
                .name = null,
                .position = 0.0,
            },
            .{
                .root = 1,
                .intervals = major_intervals,
                .name = null,
                .position = 8.0,
            },
        };
    for (version_seven_keys) |signature| {
        try version_seven_writer.integer32(
            @bitCast(signature.root),
        );
        try version_seven_writer.bytes(&signature.intervals);
        try version_seven_writer.integer64(
            @bitCast(signature.position),
        );
    }
    try std.testing.expect(version_seven_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_seven_payload,
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeKeySignatures,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, version_seven_keys.len),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const second_key_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const second_key: *const raw.ARAContentKeySignature =
        @ptrCast(@alignCast(second_key_pointer));
    try std.testing.expectEqual(
        version_seven_keys[1].root,
        second_key.root,
    );
    try std.testing.expectEqual(
        version_seven_keys[1].position,
        second_key.position,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var corrupt_version_seven = version_seven_payload;
    const second_key_position_offset =
        archive_header_size +
        2 + 1 + 1 + 4 + 2 +
        1 + 2 + 2 * 16 +
        1 + 2 +
        1 + 2 +
        1 + 2 +
        archive_key_signature_size + 4 + 12;
    var corrupt_key_writer = ByteWriter.init(
        corrupt_version_seven[second_key_position_offset .. second_key_position_offset + 8],
    );
    try corrupt_key_writer.integer64(
        @bitCast(@as(f64, 0.0)),
    );
    try std.testing.expectError(
        error.InvalidArchive,
        analyzer.restoreArchiveChecked(
            &legacy_mappings,
            &corrupt_version_seven,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeKeySignatures,
        ),
    );

    var version_eight_payload: [
        archive_header_size +
            2 + 1 + 1 + 4 + 2 +
            1 + 2 + 2 * 16 +
            1 + 2 +
            1 + 2 +
            1 + 2 +
            1 + 2 + 2 * archive_chord_size
    ]u8 = undefined;
    var version_eight_writer = ByteWriter.init(
        &version_eight_payload,
    );
    try version_eight_writer.bytes(&analysis_archive_magic);
    try version_eight_writer.byte(8);
    try version_eight_writer.integer16(1);
    try version_eight_writer.integer16(0);
    try version_eight_writer.byte(0);
    try version_eight_writer.byte(
        TestAnalyzer.general_algorithm_index,
    );
    try version_eight_writer.integer32(0);
    try version_eight_writer.integer16(0);
    try version_eight_writer.byte(1);
    try version_eight_writer.integer16(2);
    try version_eight_writer.integer64(
        @bitCast(@as(f64, 0.0)),
    );
    try version_eight_writer.integer64(
        @bitCast(@as(f64, 0.0)),
    );
    try version_eight_writer.integer64(
        @bitCast(@as(f64, 8.0)),
    );
    try version_eight_writer.integer64(
        @bitCast(@as(f64, 16.0)),
    );
    try version_eight_writer.byte(0);
    try version_eight_writer.integer16(0);
    try version_eight_writer.byte(0);
    try version_eight_writer.integer16(0);
    try version_eight_writer.byte(0);
    try version_eight_writer.integer16(0);
    try version_eight_writer.byte(1);
    try version_eight_writer.integer16(2);
    const version_eight_chords =
        [_]raw.ARAContentChord{
            .{
                .root = 0,
                .bass = 4,
                .intervals = chord_templates[0].intervals,
                .name = null,
                .position = 0.0,
            },
            .{
                .root = 1,
                .bass = 1,
                .intervals = chord_templates[6].intervals,
                .name = null,
                .position = 4.0,
            },
        };
    for (version_eight_chords) |archived_chord| {
        try version_eight_writer.integer32(
            @bitCast(archived_chord.root),
        );
        try version_eight_writer.integer32(
            @bitCast(archived_chord.bass),
        );
        try version_eight_writer.bytes(&archived_chord.intervals);
        try version_eight_writer.integer64(
            @bitCast(archived_chord.position),
        );
    }
    try std.testing.expect(version_eight_writer.finished());
    try analyzer.restoreArchiveChecked(
        &legacy_mappings,
        &version_eight_payload,
    );
    reader = api.createAudioSourceContentReader.?(
        instance.documentControllerRef,
        source_ref,
        raw.kARAContentTypeSheetChords,
        null,
    );
    try std.testing.expectEqual(
        @as(raw.ARAInt32, version_eight_chords.len),
        api.getContentReaderEventCount.?(
            instance.documentControllerRef,
            reader,
        ),
    );
    const second_archived_chord_pointer =
        api.getContentReaderDataForEvent.?(
            instance.documentControllerRef,
            reader,
            1,
        ) orelse return error.TestUnexpectedResult;
    const second_archived_chord: *const raw.ARAContentChord =
        @ptrCast(@alignCast(second_archived_chord_pointer));
    try std.testing.expectEqual(
        version_eight_chords[1].root,
        second_archived_chord.root,
    );
    try std.testing.expectEqual(
        version_eight_chords[1].position,
        second_archived_chord.position,
    );
    api.destroyContentReader.?(
        instance.documentControllerRef,
        reader,
    );

    var corrupt_version_eight = version_eight_payload;
    const second_chord_interval_offset =
        archive_header_size +
        2 + 1 + 1 + 4 + 2 +
        1 + 2 + 2 * 16 +
        1 + 2 +
        1 + 2 +
        1 + 2 +
        1 + 2 +
        archive_chord_size + 4 + 4;
    corrupt_version_eight[second_chord_interval_offset] = 8;
    try std.testing.expectError(
        error.InvalidArchive,
        analyzer.restoreArchiveChecked(
            &legacy_mappings,
            &corrupt_version_eight,
        ),
    );
    try std.testing.expectEqual(
        raw.kARATrue,
        api.isAudioSourceContentAvailable.?(
            instance.documentControllerRef,
            source_ref,
            raw.kARAContentTypeSheetChords,
        ),
    );
}
