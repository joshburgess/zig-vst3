const std = @import("std");
const adm_polar_extent = @import("../adm_polar_extent.zig");
const adm_polar_panner = @import("../adm_polar_panner.zig");
const adm_xml = @import("../adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;
pub const polar_extent_spreading_direction_count =
    adm_polar_extent.spreading_direction_count;

pub const PolarPosition = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
    distance: f64 = 1.0,
};

pub const CartesianPosition = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub const OutputSpeaker = struct {
    label: []const u8,
    is_lfe: bool = false,
    nominal_polar: PolarPosition,
    reproduction_polar: ?PolarPosition = null,
    allocentric: CartesianPosition,
};

pub const ScreenEdges = struct {
    left_azimuth_degrees: f64,
    right_azimuth_degrees: f64,
    bottom_elevation_degrees: f64,
    top_elevation_degrees: f64,
};

pub fn renderGain(
    comptime Sample: type,
    gain_value: adm_xml.Gain,
) !Sample {
    const linear_gain = switch (gain_value.unit) {
        .linear => gain_value.value,
        .decibels => if (std.math.isInf(gain_value.value) and
            gain_value.value < 0.0)
            0.0
        else
            std.math.pow(f64, 10.0, gain_value.value / 20.0),
    };
    const gain: Sample = @floatCast(linear_gain);
    if (!std.math.isFinite(gain))
        return error.InvalidAdmRendererGain;
    return gain;
}

pub fn slicesOverlap(
    comptime Sample: type,
    input: []const Sample,
    output: []Sample,
) bool {
    if (input.len == 0 or output.len == 0) return false;
    const input_start = @intFromPtr(input.ptr);
    const output_start = @intFromPtr(output.ptr);
    const input_bytes = std.math.mul(
        usize,
        input.len,
        @sizeOf(Sample),
    ) catch return true;
    const output_bytes = std.math.mul(
        usize,
        output.len,
        @sizeOf(Sample),
    ) catch return true;
    const input_end = std.math.add(
        usize,
        input_start,
        input_bytes,
    ) catch return true;
    const output_end = std.math.add(
        usize,
        output_start,
        output_bytes,
    ) catch return true;
    return input_start < output_end and output_start < input_end;
}

pub fn validateOutputLayout(outputs: []const OutputSpeaker) !void {
    if (outputs.len == 0 or outputs.len > maximum_output_channels)
        return error.InvalidAdmRendererOutputCount;
    for (outputs, 0..) |output, index| {
        const label = normalizeSpeakerLabel(output.label) orelse
            return error.InvalidAdmRendererSpeakerLabel;
        if (!validPolar(output.nominal_polar) or
            !validCartesian(output.allocentric))
        {
            return error.InvalidAdmRendererSpeakerPosition;
        }
        if (output.reproduction_polar) |position| {
            if (!validPolar(position))
                return error.InvalidAdmRendererSpeakerPosition;
        }
        const label_is_lfe = std.mem.eql(u8, label, "LFE1") or
            std.mem.eql(u8, label, "LFE2");
        if (label_is_lfe != output.is_lfe)
            return error.InvalidAdmRendererSpeakerType;
        for (outputs[0..index]) |previous| {
            const previous_label =
                normalizeSpeakerLabel(previous.label) orelse
                return error.InvalidAdmRendererSpeakerLabel;
            if (std.mem.eql(u8, label, previous_label))
                return error.DuplicateAdmRendererSpeakerLabel;
        }
    }
}

pub fn normalizeSpeakerLabel(label: []const u8) ?[]const u8 {
    var normalized = label;
    const urn_prefix = "urn:itu:bs:2051:";
    if (std.mem.startsWith(u8, normalized, urn_prefix)) {
        const remainder = normalized[urn_prefix.len..];
        const separator = std.mem.indexOfScalar(u8, remainder, ':') orelse
            return null;
        if (separator == 0) return null;
        for (remainder[0..separator]) |byte| {
            if (!std.ascii.isDigit(byte)) return null;
        }
        const speaker_prefix = "speaker:";
        const suffix = remainder[separator + 1 ..];
        if (!std.mem.startsWith(u8, suffix, speaker_prefix)) return null;
        normalized = suffix[speaker_prefix.len..];
    }
    if (std.mem.eql(u8, normalized, "LFE") or
        std.mem.eql(u8, normalized, "LFEL"))
    {
        normalized = "LFE1";
    } else if (std.mem.eql(u8, normalized, "LFER")) {
        normalized = "LFE2";
    }
    const standard_labels = [_][]const u8{
        "M+000", "M+030",  "M-030", "M+SC",  "M-SC",
        "M+060", "M-060",  "M+090", "M-090", "M+110",
        "M-110", "M+135",  "M-135", "M+180", "U+000",
        "U+030", "U-030",  "U+045", "U-045", "U+090",
        "U-090", "U+110",  "U-110", "U+135", "U-135",
        "U+180", "UH+180", "B+000", "B+045", "B-045",
        "T+000", "LFE1",   "LFE2",
    };
    for (standard_labels) |standard| {
        if (std.mem.eql(u8, normalized, standard)) return normalized;
    }
    return null;
}

pub fn validPolar(position: PolarPosition) bool {
    return std.math.isFinite(position.azimuth_degrees) and
        std.math.isFinite(position.elevation_degrees) and
        std.math.isFinite(position.distance) and
        position.azimuth_degrees >= -180.0 and
        position.azimuth_degrees <= 180.0 and
        position.elevation_degrees >= -90.0 and
        position.elevation_degrees <= 90.0 and
        position.distance >= 0.0;
}

pub fn pannerPolarPosition(
    position: PolarPosition,
) adm_polar_panner.PolarPosition {
    return .{
        .azimuth_degrees = position.azimuth_degrees,
        .elevation_degrees = position.elevation_degrees,
    };
}

pub fn validCartesian(position: CartesianPosition) bool {
    return std.math.isFinite(position.x) and
        std.math.isFinite(position.y) and
        std.math.isFinite(position.z);
}

pub fn validatePannerPosition(position: CartesianPosition) !void {
    if (!validCartesian(position) or !insideUnitCube(position, 0.0))
        return error.InvalidAdmRendererCartesianPosition;
}

pub fn insideUnitCube(position: CartesianPosition, tolerance: f64) bool {
    return @abs(position.x) <= 1.0 + tolerance and
        @abs(position.y) <= 1.0 + tolerance and
        @abs(position.z) <= 1.0 + tolerance;
}

pub fn onUnitCubeSurface(position: CartesianPosition, tolerance: f64) bool {
    return @abs(@abs(position.x) - 1.0) < tolerance or
        @abs(@abs(position.y) - 1.0) < tolerance or
        @abs(@abs(position.z) - 1.0) < tolerance;
}

pub fn samePosition(
    left: CartesianPosition,
    right: CartesianPosition,
    tolerance: f64,
) bool {
    return @abs(left.x - right.x) < tolerance and
        @abs(left.y - right.y) < tolerance and
        @abs(left.z - right.z) < tolerance;
}

pub fn subtractPosition(
    left: CartesianPosition,
    right: CartesianPosition,
) CartesianPosition {
    return .{
        .x = left.x - right.x,
        .y = left.y - right.y,
        .z = left.z - right.z,
    };
}

pub fn sameSign(left: f64, right: f64) bool {
    return (left > 0.0 and right > 0.0) or
        (left < 0.0 and right < 0.0) or
        (left == 0.0 and right == 0.0);
}

pub fn validateMixBuffers(
    comptime Sample: type,
    input: []const Sample,
    outputs: []const []Sample,
    expected_output_count: usize,
) !void {
    if (outputs.len != expected_output_count)
        return error.AdmRendererOutputCountMismatch;
    for (outputs, 0..) |output, output_index| {
        if (output.len != input.len)
            return error.AdmRendererBufferLengthMismatch;
        if (slicesOverlap(Sample, input, output))
            return error.AdmRendererAliasedBuffers;
        for (outputs[0..output_index]) |previous| {
            if (slicesOverlap(Sample, previous, output))
                return error.AdmRendererAliasedBuffers;
        }
    }
}

pub fn mixGainVector(
    comptime Sample: type,
    input: []const Sample,
    outputs: []const []Sample,
    gains: []const Sample,
) void {
    for (outputs, gains) |output, gain| {
        if (gain == 0.0) continue;
        for (input, output) |input_sample, *output_sample| {
            if (!std.math.isFinite(input_sample)) continue;
            if (!std.math.isFinite(output_sample.*)) {
                output_sample.* = 0.0;
                continue;
            }
            const mixed = output_sample.* + input_sample * gain;
            output_sample.* = if (std.math.isFinite(mixed))
                mixed
            else
                0.0;
        }
    }
}
