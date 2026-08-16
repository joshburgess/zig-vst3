const std = @import("std");

pub const direction_tolerance_squared = 1.0e-24;

pub const Direction = struct {
    azimuth_degrees: f64 = 0,
    elevation_degrees: f64 = 0,
};

pub const MeasurementPosition = struct {
    direction: Direction = .{},
    distance_metres: f64 = 1.0,
};

pub const Position = struct {
    x: f64 = 0,
    y: f64 = 0,
    z: f64 = 0,
};

pub const HeadPose = struct {
    position: Position = .{},
    yaw_degrees: f64 = 0.0,
    pitch_degrees: f64 = 0.0,
    roll_degrees: f64 = 0.0,
};

pub fn directionFromPositions(
    source_position: Position,
    head_pose: HeadPose,
) !Direction {
    return (try measurementFromPositions(
        source_position,
        head_pose,
    )).direction;
}

pub fn measurementFromPositions(
    source_position: Position,
    head_pose: HeadPose,
) !MeasurementPosition {
    try validatePosition(source_position);
    try validatePosition(head_pose.position);
    if (!std.math.isFinite(head_pose.yaw_degrees) or
        !std.math.isFinite(head_pose.pitch_degrees) or
        !std.math.isFinite(head_pose.roll_degrees))
        return error.InvalidHrtfHeadPose;

    const world = [3]f64{
        source_position.x - head_pose.position.x,
        source_position.y - head_pose.position.y,
        source_position.z - head_pose.position.z,
    };
    const distance_squared =
        world[0] * world[0] +
        world[1] * world[1] +
        world[2] * world[2];
    if (!std.math.isFinite(distance_squared) or
        distance_squared <= direction_tolerance_squared)
        return error.InvalidHrtfSourcePosition;

    const yaw = head_pose.yaw_degrees * std.math.pi / 180.0;
    const pitch = head_pose.pitch_degrees * std.math.pi / 180.0;
    const roll = head_pose.roll_degrees * std.math.pi / 180.0;
    const cy = @cos(yaw);
    const sy = @sin(yaw);
    const cp = @cos(pitch);
    const sp = @sin(pitch);
    const cr = @cos(roll);
    const sr = @sin(roll);
    const rotation = [3][3]f64{
        .{ cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr },
        .{ sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr },
        .{ -sp, cp * sr, cp * cr },
    };
    var local: [3]f64 = @splat(0.0);
    for (0..3) |row| {
        for (0..3) |column|
            local[row] += rotation[column][row] * world[column];
    }
    const horizontal = @sqrt(
        local[0] * local[0] + local[1] * local[1],
    );
    const direction = Direction{
        .azimuth_degrees = std.math.atan2(local[1], local[0]) * 180.0 /
            std.math.pi,
        .elevation_degrees = std.math.atan2(local[2], horizontal) * 180.0 /
            std.math.pi,
    };
    const result = MeasurementPosition{
        .direction = direction,
        .distance_metres = @sqrt(distance_squared),
    };
    try validateMeasurementPosition(result);
    return result;
}

pub fn validatePosition(position: Position) !void {
    if (!std.math.isFinite(position.x) or
        !std.math.isFinite(position.y) or
        !std.math.isFinite(position.z))
        return error.InvalidHrtfPosition;
}

pub fn validateDirection(direction: Direction) !void {
    if (!std.math.isFinite(direction.azimuth_degrees) or
        direction.azimuth_degrees < -180.0 or
        direction.azimuth_degrees > 180.0 or
        !std.math.isFinite(direction.elevation_degrees) or
        direction.elevation_degrees < -90.0 or
        direction.elevation_degrees > 90.0)
    {
        return error.InvalidHrtfDirection;
    }
}

pub fn validateMeasurementPosition(position: MeasurementPosition) !void {
    try validateDirection(position.direction);
    if (!std.math.isFinite(position.distance_metres) or
        position.distance_metres <= 0.0)
    {
        return error.InvalidHrtfDistance;
    }
}

pub fn directionVector(direction: Direction) [3]f64 {
    const azimuth = direction.azimuth_degrees * std.math.pi / 180.0;
    const elevation = direction.elevation_degrees * std.math.pi / 180.0;
    const horizontal = @cos(elevation);
    return .{
        horizontal * @cos(azimuth),
        horizontal * @sin(azimuth),
        @sin(elevation),
    };
}

pub fn chordDistanceSquared(first: [3]f64, second: [3]f64) f64 {
    const x = first[0] - second[0];
    const y = first[1] - second[1];
    const z = first[2] - second[2];
    return x * x + y * y + z * z;
}

pub fn measurementVector(position: MeasurementPosition) [3]f64 {
    const unit = directionVector(position.direction);
    return .{
        unit[0] * position.distance_metres,
        unit[1] * position.distance_metres,
        unit[2] * position.distance_metres,
    };
}

pub fn vectorDistanceSquared(first: [3]f64, second: [3]f64) f64 {
    return chordDistanceSquared(first, second);
}

pub fn sameMeasurementPosition(
    first: MeasurementPosition,
    second: MeasurementPosition,
) bool {
    return vectorDistanceSquared(
        measurementVector(first),
        measurementVector(second),
    ) <= direction_tolerance_squared;
}

pub fn sameDirection(first: [3]f64, second: [3]f64) bool {
    return chordDistanceSquared(first, second) <=
        direction_tolerance_squared;
}
