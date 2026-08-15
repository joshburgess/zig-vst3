const std = @import("std");
const adm_polar_extent = @import("../adm_polar_extent.zig");
const adm_polar_panner = @import("../adm_polar_panner.zig");
const adm_xml = @import("../adm_xml.zig");

pub const maximum_input_channels = adm_xml.max_adm_matrix_coefficients;
pub const maximum_output_channels: usize = 64;
pub const polar_extent_spreading_direction_count =
    adm_polar_extent.spreading_direction_count;
const position_tolerance: f64 = 1.0e-5;

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

pub const CoordinateBounds = struct {
    nominal: f64,
    minimum: f64,
    maximum: f64,
};

pub const PolarBounds = struct {
    azimuth: CoordinateBounds,
    elevation: CoordinateBounds,
    distance: CoordinateBounds,
};

pub const CartesianBounds = struct {
    x: CoordinateBounds,
    y: CoordinateBounds,
    z: CoordinateBounds,
};

pub fn polarBounds(block: *const adm_xml.BlockFormat) !PolarBounds {
    return .{
        .azimuth = try coordinateBounds(block, .azimuth, 0.0),
        .elevation = try coordinateBounds(block, .elevation, 0.0),
        .distance = try coordinateBounds(block, .distance, 1.0),
    };
}

pub fn cartesianBounds(block: *const adm_xml.BlockFormat) !CartesianBounds {
    return .{
        .x = try coordinateBounds(block, .x, 0.0),
        .y = try coordinateBounds(block, .y, 0.0),
        .z = try coordinateBounds(block, .z, 0.0),
    };
}

pub fn coordinateBounds(
    block: *const adm_xml.BlockFormat,
    coordinate: adm_xml.Coordinate,
    default_nominal: f64,
) !CoordinateBounds {
    var nominal: ?f64 = null;
    var minimum: ?f64 = null;
    var maximum: ?f64 = null;
    for (block.positionSlice()) |position| {
        if (position.coordinate != coordinate) continue;
        switch (position.bound) {
            .exact => nominal = position.value,
            .minimum => minimum = position.value,
            .maximum => maximum = position.value,
        }
    }
    const value = nominal orelse default_nominal;
    const result = CoordinateBounds{
        .nominal = value,
        .minimum = minimum orelse value,
        .maximum = maximum orelse value,
    };
    if (!std.math.isFinite(result.nominal) or
        !std.math.isFinite(result.minimum) or
        !std.math.isFinite(result.maximum))
    {
        return error.InvalidAdmRendererPositionBounds;
    }
    if (coordinate == .azimuth) {
        if (!insideAngleRange(
            result.nominal,
            result.minimum,
            result.maximum,
            0.0,
        )) {
            return error.InvalidAdmRendererPositionBounds;
        }
    } else if (result.minimum > result.maximum or
        result.nominal < result.minimum or
        result.nominal > result.maximum)
    {
        return error.InvalidAdmRendererPositionBounds;
    }
    return result;
}

pub fn closestPolarOutput(
    outputs: []const OutputSpeaker,
    bounds: PolarBounds,
    nominal: PolarPosition,
    input_is_lfe: bool,
) !?usize {
    const target = polarToCartesian(nominal);
    var closest: ?usize = null;
    var closest_distance: f64 = std.math.inf(f64);
    var tied = false;
    for (outputs, 0..) |output, output_index| {
        if (output.is_lfe != input_is_lfe or
            !polarWithinBounds(output.nominal_polar, bounds))
        {
            continue;
        }
        const distance = cartesianDistance(
            polarToCartesian(output.nominal_polar),
            target,
        );
        if (!std.math.isFinite(distance))
            return error.InvalidAdmRendererSpeakerPosition;
        if (distance < closest_distance - position_tolerance) {
            closest = output_index;
            closest_distance = distance;
            tied = false;
        } else if (@abs(distance - closest_distance) < position_tolerance) {
            tied = true;
        }
    }
    return if (tied) null else closest;
}

pub fn closestCartesianOutput(
    outputs: []const OutputSpeaker,
    bounds: CartesianBounds,
    nominal: CartesianPosition,
    input_is_lfe: bool,
) !?usize {
    var closest: ?usize = null;
    var closest_distance: f64 = std.math.inf(f64);
    var tied = false;
    for (outputs, 0..) |output, output_index| {
        if (output.is_lfe != input_is_lfe or
            !cartesianWithinBounds(output.allocentric, bounds))
        {
            continue;
        }
        const distance = cartesianDistance(output.allocentric, nominal);
        if (!std.math.isFinite(distance))
            return error.InvalidAdmRendererSpeakerPosition;
        if (distance < closest_distance - position_tolerance) {
            closest = output_index;
            closest_distance = distance;
            tied = false;
        } else if (@abs(distance - closest_distance) < position_tolerance) {
            tied = true;
        }
    }
    return if (tied) null else closest;
}

pub fn polarWithinBounds(
    speaker: PolarPosition,
    bounds: PolarBounds,
) bool {
    return (insideAngleRange(
        speaker.azimuth_degrees,
        bounds.azimuth.minimum,
        bounds.azimuth.maximum,
        position_tolerance,
    ) or
        @abs(speaker.elevation_degrees) >= 90.0 - position_tolerance) and
        speaker.elevation_degrees >=
            bounds.elevation.minimum - position_tolerance and
        speaker.elevation_degrees <=
            bounds.elevation.maximum + position_tolerance and
        speaker.distance >= bounds.distance.minimum - position_tolerance and
        speaker.distance <= bounds.distance.maximum + position_tolerance;
}

pub fn cartesianWithinBounds(
    speaker: CartesianPosition,
    bounds: CartesianBounds,
) bool {
    return withinLinearBounds(speaker.x, bounds.x) and
        withinLinearBounds(speaker.y, bounds.y) and
        withinLinearBounds(speaker.z, bounds.z);
}

pub fn withinLinearBounds(value: f64, bounds: CoordinateBounds) bool {
    return value >= bounds.minimum - position_tolerance and
        value <= bounds.maximum + position_tolerance;
}

pub fn insideAngleRange(
    angle: f64,
    start: f64,
    end: f64,
    tolerance: f64,
) bool {
    if (start == -180.0 and end == 180.0) return true;
    const arc = positiveAngle(end - start);
    const offset = positiveAngle(angle - start);
    return offset <= arc + tolerance or
        offset >= 360.0 - tolerance;
}

pub fn positiveAngle(angle: f64) f64 {
    var normalized = @mod(angle, 360.0);
    if (normalized < 0.0) normalized += 360.0;
    return normalized;
}

pub fn polarToCartesian(position: PolarPosition) CartesianPosition {
    const azimuth =
        -position.azimuth_degrees * std.math.pi / 180.0;
    const elevation =
        position.elevation_degrees * std.math.pi / 180.0;
    const elevation_cosine = @cos(elevation);
    return .{
        .x = @sin(azimuth) * elevation_cosine * position.distance,
        .y = @cos(azimuth) * elevation_cosine * position.distance,
        .z = @sin(elevation) * position.distance,
    };
}

pub const ConversionSector = struct {
    left_azimuth: f64,
    right_azimuth: f64,
    left_x: f64,
    left_y: f64,
    right_x: f64,
    right_y: f64,
};

pub fn admPolarToCartesian(position: PolarPosition) !CartesianPosition {
    if (!validPolar(position))
        return error.InvalidAdmRendererCartesianPosition;

    const absolute_elevation = @abs(position.elevation_degrees);
    var planar_radius: f64 = undefined;
    var z: f64 = undefined;
    if (absolute_elevation > 30.0) {
        const adjusted_elevation =
            45.0 + (90.0 - 45.0) *
                (absolute_elevation - 30.0) / (90.0 - 30.0);
        z = position.distance * signValue(position.elevation_degrees);
        planar_radius = position.distance * @tan(
            degreesToRadians(90.0 - adjusted_elevation),
        );
    } else {
        const adjusted_elevation =
            45.0 * position.elevation_degrees / 30.0;
        z = position.distance * @tan(
            degreesToRadians(adjusted_elevation),
        );
        planar_radius = position.distance;
    }

    const sector = findConversionSector(
        position.azimuth_degrees,
        false,
    );
    const azimuth = relativeAngle(
        sector.right_azimuth,
        position.azimuth_degrees,
    );
    const left_azimuth = relativeAngle(
        sector.right_azimuth,
        sector.left_azimuth,
    );
    const proportion = mapAzimuthToLinear(
        left_azimuth,
        sector.right_azimuth,
        azimuth,
    );
    const result = CartesianPosition{
        .x = planar_radius *
            (sector.left_x +
                proportion * (sector.right_x - sector.left_x)),
        .y = planar_radius *
            (sector.left_y +
                proportion * (sector.right_y - sector.left_y)),
        .z = z,
    };
    if (!validCartesian(result))
        return error.InvalidAdmRendererCartesianPosition;
    return result;
}

pub fn admCartesianToPolar(position: CartesianPosition) !PolarPosition {
    try validatePannerPosition(position);
    const conversion_epsilon = 1.0e-10;
    if (@abs(position.x) < conversion_epsilon and
        @abs(position.y) < conversion_epsilon)
    {
        if (@abs(position.z) < conversion_epsilon) {
            return .{
                .azimuth_degrees = 0,
                .elevation_degrees = 0,
                .distance = 0,
            };
        }
        return .{
            .azimuth_degrees = 0,
            .elevation_degrees = 90.0 * signValue(position.z),
            .distance = @abs(position.z),
        };
    }

    const geometric_azimuth =
        -radiansToDegrees(std.math.atan2(position.x, position.y));
    const sector = findConversionSector(geometric_azimuth, true);
    const determinant =
        sector.left_x * sector.right_y -
        sector.left_y * sector.right_x;
    if (@abs(determinant) < conversion_epsilon)
        return error.InvalidAdmRendererCartesianPosition;
    const left_gain =
        (position.x * sector.right_y -
            position.y * sector.right_x) / determinant;
    const right_gain =
        (position.y * sector.left_x -
            position.x * sector.left_y) / determinant;
    const planar_radius = left_gain + right_gain;
    if (!std.math.isFinite(planar_radius) or
        planar_radius <= conversion_epsilon)
    {
        return error.InvalidAdmRendererCartesianPosition;
    }

    const left_azimuth = relativeAngle(
        sector.right_azimuth,
        sector.left_azimuth,
    );
    const mapped_azimuth = mapLinearToAzimuth(
        left_azimuth,
        sector.right_azimuth,
        right_gain / planar_radius,
    );
    const azimuth = relativeAngle(-180.0, mapped_azimuth);
    const adjusted_elevation = radiansToDegrees(
        std.math.atan(position.z / planar_radius),
    );
    var elevation: f64 = undefined;
    var distance: f64 = undefined;
    if (@abs(adjusted_elevation) > 45.0) {
        const absolute_elevation =
            30.0 + (90.0 - 30.0) *
                (@abs(adjusted_elevation) - 45.0) / (90.0 - 45.0);
        elevation = absolute_elevation *
            signValue(adjusted_elevation);
        distance = @abs(position.z);
    } else {
        elevation = adjusted_elevation * 30.0 / 45.0;
        distance = planar_radius;
    }
    const result = PolarPosition{
        .azimuth_degrees = if (azimuth > 180.0)
            azimuth - 360.0
        else
            azimuth,
        .elevation_degrees = elevation,
        .distance = distance,
    };
    if (!validPolar(result))
        return error.InvalidAdmRendererCartesianPosition;
    return result;
}

pub fn findConversionSector(
    azimuth: f64,
    cartesian_input: bool,
) ConversionSector {
    const front_limit: f64 = if (cartesian_input) 45.0 else 30.0;
    const side_limit: f64 = if (cartesian_input) 135.0 else 110.0;
    if (insideAngleRange(azimuth, 0.0, front_limit, 0.0)) {
        return .{
            .left_azimuth = 30,
            .right_azimuth = 0,
            .left_x = -1,
            .left_y = 1,
            .right_x = 0,
            .right_y = 1,
        };
    }
    if (insideAngleRange(azimuth, -front_limit, 0.0, 0.0)) {
        return .{
            .left_azimuth = 0,
            .right_azimuth = -30,
            .left_x = 0,
            .left_y = 1,
            .right_x = 1,
            .right_y = 1,
        };
    }
    if (insideAngleRange(
        azimuth,
        -side_limit,
        -front_limit,
        0.0,
    )) {
        return .{
            .left_azimuth = -30,
            .right_azimuth = -110,
            .left_x = 1,
            .left_y = 1,
            .right_x = 1,
            .right_y = -1,
        };
    }
    if (insideAngleRange(
        azimuth,
        side_limit,
        -side_limit,
        0.0,
    )) {
        return .{
            .left_azimuth = -110,
            .right_azimuth = 110,
            .left_x = 1,
            .left_y = -1,
            .right_x = -1,
            .right_y = -1,
        };
    }
    return .{
        .left_azimuth = 110,
        .right_azimuth = 30,
        .left_x = -1,
        .left_y = -1,
        .right_x = -1,
        .right_y = 1,
    };
}

pub fn mapAzimuthToLinear(
    left_azimuth: f64,
    right_azimuth: f64,
    azimuth: f64,
) f64 {
    const midpoint = (left_azimuth + right_azimuth) * 0.5;
    const range = right_azimuth - midpoint;
    const relative = azimuth - midpoint;
    const right_gain = 0.5 +
        @tan(degreesToRadians(relative)) /
            (2.0 * @tan(degreesToRadians(range)));
    return 2.0 / std.math.pi *
        std.math.atan2(right_gain, 1.0 - right_gain);
}

pub fn mapLinearToAzimuth(
    left_azimuth: f64,
    right_azimuth: f64,
    linear: f64,
) f64 {
    const midpoint = (left_azimuth + right_azimuth) * 0.5;
    const range = right_azimuth - midpoint;
    const left_gain = @cos(linear * std.math.pi / 2.0);
    const right_gain = @sin(linear * std.math.pi / 2.0);
    const normalized_right = right_gain / (left_gain + right_gain);
    const relative = radiansToDegrees(std.math.atan(
        2.0 * (normalized_right - 0.5) *
            @tan(degreesToRadians(range)),
    ));
    return midpoint + relative;
}

pub fn relativeAngle(minimum: f64, angle: f64) f64 {
    if (angle >= minimum) return angle;
    return angle +
        360.0 * @ceil((minimum - angle) / 360.0);
}

pub fn degreesToRadians(degrees: f64) f64 {
    return degrees * std.math.pi / 180.0;
}

pub fn radiansToDegrees(radians: f64) f64 {
    return radians * 180.0 / std.math.pi;
}

pub fn signValue(value: f64) f64 {
    if (value > 0.0) return 1.0;
    if (value < 0.0) return -1.0;
    return 0.0;
}

pub fn cartesianDistance(
    left: CartesianPosition,
    right: CartesianPosition,
) f64 {
    const x = left.x - right.x;
    const y = left.y - right.y;
    const z = left.z - right.z;
    return @sqrt(x * x + y * y + z * z);
}

pub fn hasScreenEdgeLock(block: *const adm_xml.BlockFormat) bool {
    for (block.positionSlice()) |position| {
        if (position.screen_edge_lock != null) return true;
    }
    return false;
}

pub fn validateScreenEdges(edges: ScreenEdges) !void {
    if (!std.math.isFinite(edges.left_azimuth_degrees) or
        !std.math.isFinite(edges.right_azimuth_degrees) or
        !std.math.isFinite(edges.bottom_elevation_degrees) or
        !std.math.isFinite(edges.top_elevation_degrees) or
        edges.left_azimuth_degrees < -180.0 or
        edges.left_azimuth_degrees > 180.0 or
        edges.right_azimuth_degrees < -180.0 or
        edges.right_azimuth_degrees > 180.0 or
        edges.bottom_elevation_degrees < -90.0 or
        edges.bottom_elevation_degrees > 90.0 or
        edges.top_elevation_degrees < -90.0 or
        edges.top_elevation_degrees > 90.0 or
        edges.bottom_elevation_degrees > edges.top_elevation_degrees)
    {
        return error.InvalidAdmRendererScreenGeometry;
    }
}

pub fn applyPolarScreenEdgeLock(
    block: *const adm_xml.BlockFormat,
    edges: ScreenEdges,
    nominal: *PolarPosition,
) void {
    for (block.positionSlice()) |position| {
        if (position.bound != .exact) continue;
        const edge = position.screen_edge_lock orelse continue;
        switch (edge) {
            .left => nominal.azimuth_degrees =
                edges.left_azimuth_degrees,
            .right => nominal.azimuth_degrees =
                edges.right_azimuth_degrees,
            .bottom => nominal.elevation_degrees =
                edges.bottom_elevation_degrees,
            .top => nominal.elevation_degrees =
                edges.top_elevation_degrees,
        }
    }
}

pub fn compensateCartesianScreenPosition(
    outputs: []const OutputSpeaker,
    position: *PolarPosition,
) void {
    var has_upper_front_45 = false;
    for (outputs) |output| {
        const label = normalizeSpeakerLabel(output.label) orelse continue;
        if (std.mem.eql(u8, label, "U+045")) {
            has_upper_front_45 = true;
            break;
        }
    }
    if (!has_upper_front_45) return;

    const azimuth_radius = piecewiseLinear(
        position.elevation_degrees,
        &.{ -90.0, 0.0, 30.0, 90.0 },
        &.{ 30.0, 30.0, 20.0, 30.0 },
    );
    position.azimuth_degrees = piecewiseLinear(
        position.azimuth_degrees,
        &.{ -180.0, -30.0, 30.0, 180.0 },
        &.{ -180.0, -azimuth_radius, azimuth_radius, 180.0 },
    );
}

pub fn piecewiseLinear(
    value: f64,
    inputs: *const [4]f64,
    outputs: *const [4]f64,
) f64 {
    if (value <= inputs[0]) return outputs[0];
    for (1..inputs.len) |index| {
        if (value > inputs[index]) continue;
        const proportion =
            (value - inputs[index - 1]) /
            (inputs[index] - inputs[index - 1]);
        return outputs[index - 1] +
            proportion * (outputs[index] - outputs[index - 1]);
    }
    return outputs[outputs.len - 1];
}
