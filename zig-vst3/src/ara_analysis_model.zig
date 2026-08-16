const controller_api = @import("ara_document_controller.zig");

pub const raw = controller_api.raw;
pub const maximum_supported_sample_rate = 2_000_000.0;

pub const Error = controller_api.Error || error{
    InvalidConfiguration,
    InvalidSampleRate,
    InvalidSampleCount,
    InvalidFrequencyRange,
    InvalidConcertPitch,
    SignalTooQuiet,
    PitchNotFound,
    TempoNotFound,
    MeterNotFound,
    KeySignatureNotFound,
    ChordNotFound,
    NoteNotFound,
    InvalidChordAnalysisState,
    InvalidKeyAnalysisState,
};

pub const DetectionConfig = struct {
    minimum_frequency: f64 = 40.0,
    maximum_frequency: f64 = 2_000.0,
    minimum_rms: f64 = 1.0e-5,
    minimum_correlation: f64 = 0.8,
};

pub const Detection = struct {
    frequency: f64,
    concert_pitch: f64,
    pitch_number: i32,
    correlation: f64,
    rms: f64,
};

pub const TempoDetectionConfig = struct {
    minimum_bpm: f64 = 40.0,
    maximum_bpm: f64 = 240.0,
    minimum_correlation: f64 = 0.2,
    minimum_onset: f64 = 1.0e-6,
    window_seconds: f64 = 8.0,
    hop_seconds: f64 = 4.0,
    tempo_change_ratio: f64 = 0.05,
};

pub const TempoDetection = struct {
    bpm: f64,
    beat_period: f64,
    first_beat_time: f64,
    correlation: f64,
};

pub const maximum_detected_tempo_entries = 64;
pub const maximum_detected_bar_signatures = 64;
pub const maximum_detected_key_signatures = 64;
pub const maximum_detected_chords = 256;
pub const maximum_meter_pulses = 2_048;
pub const maximum_detected_notes = 256;
pub const maximum_note_window_samples = 8_192;

pub const MeterDetectionConfig = struct {
    minimum_bars: u8 = 4,
    minimum_score: f64 = 0.25,
    change_score_margin: f64 = 0.12,
    onset_window_ratio: f64 = 0.3,
};

pub const KeySignatureDetectionConfig = struct {
    window_quarters: f64 = 8.0,
    hop_quarters: f64 = 4.0,
    minimum_note_weight: f64 = 1.0,
    minimum_score: f64 = 0.45,
    minimum_score_margin: f64 = 0.04,
    change_confirmation_windows: u8 = 2,
};

pub const ChordDetectionConfig = struct {
    window_quarters: f64 = 1.0,
    hop_quarters: f64 = 1.0,
    minimum_note_weight: f64 = 0.2,
    minimum_note_quarters: f64 = 0.25,
    minimum_score: f64 = 0.65,
    minimum_score_margin: f64 = 0.02,
    minimum_pitch_classes: u8 = 2,
    change_confirmation_windows: u8 = 1,
};

pub const NoteDetectionConfig = struct {
    minimum_pitch: u8 = 24,
    maximum_pitch: u8 = 96,
    maximum_polyphony: u8 = 8,
    window_seconds: f64 = 0.04,
    hop_seconds: f64 = 0.01,
    minimum_amplitude: f64 = 0.025,
    minimum_note_seconds: f64 = 0.04,
    release_hops: u8 = 1,
    harmonic_rejection_ratio: f64 = 0.75,
};

pub const Limits = struct {
    sources: usize,
    channels: usize,
    frames: usize,
    name_bytes: usize = 63,
    tempo_bins: usize = 6_000,
    tempo_entries: usize = 32,
    bar_signatures: usize = 16,
    key_signatures: usize = 16,
    chords: usize = 64,
    note_entries: usize = 64,
};
