const std = @import("std");
const adm = @import("../adm.zig");
const adm_time = @import("../adm_time.zig");
const xml = @import("../xml.zig");

const max_identifier_bytes: usize = 20;
const max_profile_text_bytes: usize = 128;

pub const max_adm_positions: usize = 9;
pub const max_adm_speaker_labels: usize = 16;
pub const max_adm_speaker_label_bytes: usize = 64;
pub const max_adm_matrix_coefficients: usize = 32;
pub const max_adm_exclusion_zones: usize = 32;

pub const Tag = struct {
    group_index: usize,
    value: []const u8,
    class: ?[]const u8,
};

pub const TagTarget = struct {
    group_index: usize,
    identifier: adm.Identifier,
};

pub const TagItem = union(enum) {
    tag: Tag,
    target: TagTarget,
};

pub const GainUnit = enum {
    linear,
    decibels,
};

pub const Gain = struct {
    value: f64 = 1.0,
    unit: GainUnit = .linear,
};

pub const Frequency = struct {
    low_pass_hz: ?f64 = null,
    high_pass_hz: ?f64 = null,

    pub fn isLfe(self: Frequency) bool {
        if (self.high_pass_hz != null) return false;
        const low_pass_hz = self.low_pass_hz orelse return false;
        return low_pass_hz <= 120.0;
    }
};

pub const JumpPosition = struct {
    enabled: bool = false,
    interpolation_length: ?adm_time.Value = null,
};

pub const HeadphoneVirtualise = struct {
    bypass: bool = false,
    direct_to_reverberant_ratio_db: f64 = 130.0,
};

pub const Coordinate = enum {
    azimuth,
    elevation,
    distance,
    x,
    y,
    z,
};

pub const PositionBound = enum {
    exact,
    minimum,
    maximum,
};

pub const ScreenEdge = enum {
    left,
    right,
    top,
    bottom,
};

pub const Position = struct {
    coordinate: Coordinate = .azimuth,
    bound: PositionBound = .exact,
    value: f64 = 0.0,
    screen_edge_lock: ?ScreenEdge = null,
};

pub const SpeakerLabel = struct {
    bytes: [max_adm_speaker_label_bytes]u8 = @splat(0),
    len: u8 = 0,

    pub fn value(self: *const SpeakerLabel) []const u8 {
        if (self.len > self.bytes.len) return &.{};
        return self.bytes[0..self.len];
    }

    pub fn valid(self: *const SpeakerLabel) bool {
        return self.len <= self.bytes.len;
    }
};

pub const ObjectDivergence = struct {
    value: f64 = 0.0,
    azimuth_range: ?f64 = null,
    position_range: ?f64 = null,
};

pub const ChannelLock = struct {
    enabled: bool = false,
    max_distance: ?f64 = null,
};

pub const CartesianExclusionZone = struct {
    min_x: f64 = 0.0,
    min_y: f64 = 0.0,
    min_z: f64 = 0.0,
    max_x: f64 = 0.0,
    max_y: f64 = 0.0,
    max_z: f64 = 0.0,
};

pub const PolarExclusionZone = struct {
    min_azimuth: f64 = 0.0,
    max_azimuth: f64 = 0.0,
    min_elevation: f64 = 0.0,
    max_elevation: f64 = 0.0,
};

pub const ExclusionZone = union(enum) {
    cartesian: CartesianExclusionZone,
    polar: PolarExclusionZone,
};

pub const HoaNormalization = enum {
    n3d,
    sn3d,
    fuma,
};

pub const AdmText = struct {
    bytes: [max_profile_text_bytes]u8 = @splat(0),
    len: u8 = 0,

    pub fn value(self: *const AdmText) []const u8 {
        if (self.len > self.bytes.len) return &.{};
        return self.bytes[0..self.len];
    }

    pub fn valid(self: *const AdmText) bool {
        return self.len <= self.bytes.len;
    }
};

pub const MatrixCoefficient = struct {
    channel_identifier_bytes: [max_identifier_bytes]u8 = @splat(0),
    channel_identifier_len: u8 = 0,
    gain: Gain = .{},
    gain_variable: ?AdmText = null,
    phase_degrees: f64 = 0.0,
    phase_variable: ?AdmText = null,
    delay_milliseconds: f64 = 0.0,
    delay_variable: ?AdmText = null,

    pub fn channelIdentifier(
        self: *const MatrixCoefficient,
    ) !adm.Identifier {
        if (self.channel_identifier_len > self.channel_identifier_bytes.len)
            return error.InvalidAdmMatrixCoefficientState;
        return adm.Identifier.parse(
            self.channel_identifier_bytes[0..self.channel_identifier_len],
        );
    }
};

pub const BlockFormat = struct {
    identifier: adm.Identifier,
    channel_identifier: adm.Identifier,
    channel_name: ?AdmText,
    channel_frequency: Frequency = .{},
    rtime: adm_time.Value,
    rtime_explicit: bool,
    duration: ?adm_time.Value,
    lstart: ?adm_time.Value = null,
    lduration: ?adm_time.Value = null,
    initialize_block: ?bool = null,
    gain: Gain = .{},
    importance: u8 = 10,
    jump_position: JumpPosition = .{},
    head_locked: bool = false,
    headphone_virtualise: HeadphoneVirtualise = .{},
    cartesian: bool = false,
    positions: [max_adm_positions]Position = @splat(.{}),
    position_count: usize = 0,
    speaker_labels: [max_adm_speaker_labels]SpeakerLabel = @splat(.{}),
    speaker_label_count: usize = 0,
    width: f64 = 0.0,
    height: f64 = 0.0,
    depth: f64 = 0.0,
    diffuse: f64 = 0.0,
    object_divergence: ObjectDivergence = .{},
    channel_lock: ChannelLock = .{},
    exclusion_zones: [max_adm_exclusion_zones]ExclusionZone =
        @splat(.{ .cartesian = .{} }),
    exclusion_zone_count: usize = 0,
    screen_ref: bool = false,
    hoa_equation: ?AdmText = null,
    hoa_order: ?u32 = null,
    hoa_degree: ?i32 = null,
    hoa_normalization: HoaNormalization = .sn3d,
    hoa_nfc_reference_distance: f64 = 0.0,
    matrix_coefficients: [max_adm_matrix_coefficients]MatrixCoefficient =
        @splat(.{}),
    matrix_coefficient_count: usize = 0,

    pub fn retainedCountsValid(self: *const BlockFormat) bool {
        return self.position_count <= self.positions.len and
            self.speaker_label_count <= self.speaker_labels.len and
            self.exclusion_zone_count <= self.exclusion_zones.len and
            self.matrix_coefficient_count <= self.matrix_coefficients.len;
    }

    pub fn positionSlice(self: *const BlockFormat) []const Position {
        if (self.position_count > self.positions.len) return &.{};
        return self.positions[0..self.position_count];
    }

    pub fn speakerLabelSlice(
        self: *const BlockFormat,
    ) []const SpeakerLabel {
        if (self.speaker_label_count > self.speaker_labels.len) return &.{};
        return self.speaker_labels[0..self.speaker_label_count];
    }

    pub fn exclusionZoneSlice(
        self: *const BlockFormat,
    ) []const ExclusionZone {
        if (self.exclusion_zone_count > self.exclusion_zones.len) return &.{};
        return self.exclusion_zones[0..self.exclusion_zone_count];
    }

    pub fn matrixCoefficientSlice(
        self: *const BlockFormat,
    ) []const MatrixCoefficient {
        if (self.matrix_coefficient_count > self.matrix_coefficients.len)
            return &.{};
        return self.matrix_coefficients[0..self.matrix_coefficient_count];
    }
};
