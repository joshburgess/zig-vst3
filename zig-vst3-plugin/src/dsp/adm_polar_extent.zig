const std = @import("std");
const adm_polar_panner = @import("adm_polar_panner.zig");

pub const spreading_direction_count: usize = 1652;
const spreading_row_count: usize = 37;
const spreading_step_degrees: f64 = 5.0;
const minimum_spread_degrees: f64 = 5.0;
const fade_width_degrees: f64 = 10.0;
const direction_tolerance: f64 = 1.0e-9;

const Vector = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub fn requiredGainStorage(output_count: usize) !usize {
    if (output_count == 0 or output_count > adm_polar_panner.maximum_outputs)
        return error.InvalidAdmPolarExtentOutputCount;
    return std.math.mul(
        usize,
        spreading_direction_count,
        output_count,
    ) catch error.AdmPolarExtentStorageSizeOverflow;
}

pub fn Panner(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ADM polar extent panner supports f32 and f64 samples");

    return struct {
        const Self = @This();

        output_count: usize,
        point_panner: adm_polar_panner.Panner(Sample),
        directions: [spreading_direction_count]Vector,
        precomputed_gains: []const Sample,

        pub fn init(
            point_panner: *const adm_polar_panner.Panner(Sample),
            gain_storage: []Sample,
        ) !Self {
            if (!point_panner.valid())
                return error.InvalidAdmPolarExtentPointPanner;
            const required = try requiredGainStorage(
                point_panner.output_count,
            );
            if (gain_storage.len != required)
                return error.AdmPolarExtentGainStorageSizeMismatch;
            if (objectSliceOverlap(
                adm_polar_panner.Panner(Sample),
                Sample,
                point_panner,
                gain_storage,
            )) {
                return error.AdmPolarExtentAliasedBuffers;
            }

            var result = Self{
                .output_count = point_panner.output_count,
                .point_panner = point_panner.*,
                .directions = undefined,
                .precomputed_gains = gain_storage,
            };
            var direction_index: usize = 0;
            for (0..spreading_row_count) |row| {
                const elevation =
                    -90.0 + spreading_step_degrees * @as(f64, @floatFromInt(row));
                const count = directionsInRow(elevation);
                for (0..count) |column| {
                    const azimuth =
                        360.0 * @as(f64, @floatFromInt(column)) /
                        @as(f64, @floatFromInt(count));
                    const direction = polarVector(azimuth, elevation);
                    result.directions[direction_index] = direction;
                    direction_index += 1;
                }
            }
            if (direction_index != spreading_direction_count)
                return error.InvalidAdmPolarExtentDirectionGrid;

            var scratch: [adm_polar_panner.maximum_outputs]Sample = undefined;
            for (result.directions) |direction| {
                try result.point_panner.calculateGains(
                    vectorPolarPosition(direction),
                    scratch[0..result.output_count],
                );
            }
            for (result.directions, 0..) |direction, index| {
                const start = index * result.output_count;
                try result.point_panner.calculateGains(
                    vectorPolarPosition(direction),
                    gain_storage[start..][0..result.output_count],
                );
            }
            if (!result.valid())
                return error.InvalidAdmPolarExtentState;
            return result;
        }

        pub fn calculateGains(
            self: *const Self,
            position: adm_polar_panner.PolarPosition,
            distance: f64,
            width_degrees: f64,
            height_degrees: f64,
            depth: f64,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmPolarExtentState;
            if (!validPosition(position, distance))
                return error.InvalidAdmPolarExtentPosition;
            if (!validExtent(width_degrees, height_degrees, depth))
                return error.InvalidAdmPolarExtent;
            if (gains.len != self.output_count)
                return error.AdmPolarExtentOutputCountMismatch;
            if (slicesOverlap(Sample, self.precomputed_gains, gains))
                return error.AdmPolarExtentAliasedBuffers;

            const distance_count: usize = if (depth == 0.0) 1 else 2;
            const distances = [_]f64{
                distance + depth / 2.0,
                @max(distance - depth / 2.0, 0.0),
            };
            var combined_power: [adm_polar_panner.maximum_outputs]f64 = @splat(0.0);
            var distance_gains: [adm_polar_panner.maximum_outputs]f64 = undefined;
            for (distances[0..distance_count]) |extent_distance| {
                try self.calculateSpreadPointBlend(
                    position,
                    extentModification(width_degrees, extent_distance),
                    extentModification(height_degrees, extent_distance),
                    distance_gains[0..self.output_count],
                );
                for (
                    combined_power[0..self.output_count],
                    distance_gains[0..self.output_count],
                ) |*power, gain| {
                    power.* += gain * gain /
                        @as(f64, @floatFromInt(distance_count));
                }
            }

            for (
                gains,
                combined_power[0..self.output_count],
            ) |*gain, power| {
                if (!std.math.isFinite(power) or power < 0.0)
                    return error.InvalidAdmPolarExtentGain;
                gain.* = @floatCast(@sqrt(power));
                if (!std.math.isFinite(gain.*))
                    return error.InvalidAdmPolarExtentGain;
            }
        }

        pub fn valid(self: *const Self) bool {
            if (!self.point_panner.valid() or
                self.output_count != self.point_panner.output_count)
            {
                return false;
            }
            const required = requiredGainStorage(self.output_count) catch
                return false;
            if (self.precomputed_gains.len != required) return false;
            for (self.directions) |direction| {
                const magnitude_squared = dot(direction, direction);
                if (!finiteVector(direction) or
                    @abs(magnitude_squared - 1.0) > direction_tolerance)
                {
                    return false;
                }
            }
            for (0..spreading_direction_count) |direction_index| {
                const start = direction_index * self.output_count;
                var power: f64 = 0.0;
                for (
                    self.precomputed_gains[start..][0..self.output_count],
                ) |gain| {
                    if (!std.math.isFinite(gain) or gain < 0.0)
                        return false;
                    const value: f64 = @floatCast(gain);
                    power += value * value;
                }
                if (!std.math.isFinite(power) or
                    @abs(power - 1.0) >
                        if (Sample == f32) 0.000_01 else 0.000_000_001)
                {
                    return false;
                }
            }
            return true;
        }

        fn calculateSpreadPointBlend(
            self: *const Self,
            position: adm_polar_panner.PolarPosition,
            width_degrees: f64,
            height_degrees: f64,
            gains: []f64,
        ) !void {
            const spread_proportion =
                spreadProportion(width_degrees, height_degrees);
            const point_proportion = 1.0 - spread_proportion;
            var point_gains: [adm_polar_panner.maximum_outputs]Sample = undefined;
            var spread_gains: [adm_polar_panner.maximum_outputs]f64 = undefined;
            if (point_proportion > 0.0) {
                try self.point_panner.calculateGains(
                    position,
                    point_gains[0..self.output_count],
                );
            }
            if (spread_proportion > 0.0) {
                try self.calculateSpreadGains(
                    position,
                    @max(width_degrees, minimum_spread_degrees),
                    @max(height_degrees, minimum_spread_degrees),
                    spread_gains[0..self.output_count],
                );
            }

            for (gains, 0..) |*gain, output_index| {
                const point_gain: f64 = if (point_proportion > 0.0)
                    @floatCast(point_gains[output_index])
                else
                    0.0;
                const spread_gain = if (spread_proportion > 0.0)
                    spread_gains[output_index]
                else
                    0.0;
                const power =
                    point_proportion * point_gain * point_gain +
                    spread_proportion * spread_gain * spread_gain;
                if (!std.math.isFinite(power) or power < 0.0)
                    return error.InvalidAdmPolarExtentGain;
                gain.* = @sqrt(power);
            }
        }

        fn calculateSpreadGains(
            self: *const Self,
            position: adm_polar_panner.PolarPosition,
            width_degrees: f64,
            height_degrees: f64,
            gains: []f64,
        ) !void {
            const shape = ExtentShape.init(
                position,
                width_degrees,
                height_degrees,
            );
            @memset(gains, 0.0);
            for (self.directions, 0..) |direction, direction_index| {
                const weight = shape.weight(direction);
                if (weight == 0.0) continue;
                const start = direction_index * self.output_count;
                for (
                    gains,
                    self.precomputed_gains[start..][0..self.output_count],
                ) |*gain, virtual_gain| {
                    gain.* += weight * @as(f64, @floatCast(virtual_gain));
                }
            }
            if (!normalizeNonnegative(gains))
                return error.InvalidAdmPolarExtentGain;
        }
    };
}

pub fn extentModification(extent_degrees: f64, distance: f64) f64 {
    const size =
        0.2 + 0.8 * std.math.clamp(extent_degrees / 360.0, 0.0, 1.0);
    const extent_at_one =
        4.0 * radiansToDegrees(std.math.atan2(size, 1.0));
    const extent_at_distance =
        4.0 * radiansToDegrees(std.math.atan2(size, @max(distance, 0.0)));
    if (extent_at_distance < extent_at_one) {
        return extent_degrees * extent_at_distance / extent_at_one;
    }
    return extent_degrees +
        (360.0 - extent_degrees) *
            (extent_at_distance - extent_at_one) /
            (360.0 - extent_at_one);
}

const ExtentShape = struct {
    basis: [3]Vector,
    circle_radius: f64,
    circle_position: f64,
    circle_centres: [2]Vector,

    fn init(
        position: adm_polar_panner.PolarPosition,
        width_degrees: f64,
        height_degrees: f64,
    ) ExtentShape {
        var width = degreesToRadians(width_degrees) / 2.0;
        var height = degreesToRadians(height_degrees) / 2.0;
        const circle_radius = @min(width, height);
        var basis = localBasis(position);
        if (height > width) {
            const previous_x = basis[0];
            basis[0] = basis[2];
            basis[2] = previous_x;
            const previous_width = width;
            width = height;
            height = previous_width;
        }

        const original_width = width;
        const width_full = std.math.pi + height;
        const width_modified = piecewiseLinearClamped(
            width,
            &.{ 0.0, std.math.pi / 2.0, std.math.pi },
            &.{ 0.0, std.math.pi / 2.0, width_full },
        );
        width = piecewiseLinearClamped(
            height,
            &.{
                0.0,
                std.math.pi / 4.0,
                std.math.pi / 2.0,
                std.math.pi,
            },
            &.{
                width_modified,
                width_modified,
                original_width,
                original_width,
            },
        );
        const circle_position = width - circle_radius;
        return .{
            .basis = basis,
            .circle_radius = circle_radius,
            .circle_position = circle_position,
            .circle_centres = .{
                vectorOnBasis(basis, -circle_position, 0.0),
                vectorOnBasis(basis, circle_position, 0.0),
            },
        };
    }

    fn weight(self: ExtentShape, direction: Vector) f64 {
        const local_x = dot(direction, self.basis[0]);
        const local_y = dot(direction, self.basis[1]);
        const local_z = std.math.clamp(
            dot(direction, self.basis[2]),
            -1.0,
            1.0,
        );
        const azimuth = std.math.atan2(local_x, local_y);
        const elevation = std.math.asin(local_z);
        const distance = if (@abs(azimuth) <= self.circle_position)
            @abs(elevation) - self.circle_radius
        else
            @min(
                std.math.acos(std.math.clamp(
                    dot(direction, self.circle_centres[0]),
                    -1.0,
                    1.0,
                )),
                std.math.acos(std.math.clamp(
                    dot(direction, self.circle_centres[1]),
                    -1.0,
                    1.0,
                )),
            ) - self.circle_radius;
        return std.math.clamp(
            1.0 - distance / degreesToRadians(fade_width_degrees),
            0.0,
            1.0,
        );
    }
};

fn directionsInRow(elevation_degrees: f64) usize {
    const estimate =
        360.0 / spreading_step_degrees *
        @cos(degreesToRadians(elevation_degrees));
    return @max(
        @as(usize, @intFromFloat(@round(estimate))),
        1,
    );
}

fn localBasis(
    position: adm_polar_panner.PolarPosition,
) [3]Vector {
    const azimuth = if (@abs(position.elevation_degrees) >
        90.0 - 0.000_01)
        0.0
    else
        position.azimuth_degrees;
    return .{
        polarVector(azimuth - 90.0, 0.0),
        polarVector(azimuth, position.elevation_degrees),
        polarVector(azimuth, position.elevation_degrees + 90.0),
    };
}

fn vectorOnBasis(
    basis: [3]Vector,
    azimuth: f64,
    elevation: f64,
) Vector {
    const local = Vector{
        .x = @sin(azimuth) * @cos(elevation),
        .y = @cos(azimuth) * @cos(elevation),
        .z = @sin(elevation),
    };
    return .{
        .x = local.x * basis[0].x +
            local.y * basis[1].x +
            local.z * basis[2].x,
        .y = local.x * basis[0].y +
            local.y * basis[1].y +
            local.z * basis[2].y,
        .z = local.x * basis[0].z +
            local.y * basis[1].z +
            local.z * basis[2].z,
    };
}

fn polarVector(azimuth_degrees: f64, elevation_degrees: f64) Vector {
    const azimuth = -degreesToRadians(azimuth_degrees);
    const elevation = degreesToRadians(elevation_degrees);
    const elevation_cosine = @cos(elevation);
    return .{
        .x = @sin(azimuth) * elevation_cosine,
        .y = @cos(azimuth) * elevation_cosine,
        .z = @sin(elevation),
    };
}

fn vectorPolarPosition(
    direction: Vector,
) adm_polar_panner.PolarPosition {
    const planar_distance =
        @sqrt(direction.x * direction.x + direction.y * direction.y);
    return .{
        .azimuth_degrees = if (planar_distance == 0.0)
            0.0
        else
            -radiansToDegrees(std.math.atan2(direction.x, direction.y)),
        .elevation_degrees = radiansToDegrees(std.math.atan2(direction.z, planar_distance)),
    };
}

fn validPosition(
    position: adm_polar_panner.PolarPosition,
    distance: f64,
) bool {
    return std.math.isFinite(position.azimuth_degrees) and
        std.math.isFinite(position.elevation_degrees) and
        std.math.isFinite(distance) and
        position.azimuth_degrees >= -180.0 and
        position.azimuth_degrees <= 180.0 and
        position.elevation_degrees >= -90.0 and
        position.elevation_degrees <= 90.0 and
        distance >= 0.0;
}

fn validExtent(width: f64, height: f64, depth: f64) bool {
    return std.math.isFinite(width) and
        std.math.isFinite(height) and
        std.math.isFinite(depth) and
        width >= 0.0 and
        width <= 360.0 and
        height >= 0.0 and
        height <= 360.0 and
        depth >= 0.0 and
        depth <= 1.0;
}

fn spreadProportion(width: f64, height: f64) f64 {
    return std.math.clamp(
        @max(width, height) / minimum_spread_degrees,
        0.0,
        1.0,
    );
}

fn piecewiseLinearClamped(
    value: f64,
    inputs: []const f64,
    outputs: []const f64,
) f64 {
    if (value <= inputs[0]) return outputs[0];
    if (value >= inputs[inputs.len - 1])
        return outputs[outputs.len - 1];
    for (0..inputs.len - 1) |index| {
        if (value > inputs[index + 1]) continue;
        const proportion =
            (value - inputs[index]) /
            (inputs[index + 1] - inputs[index]);
        return outputs[index] +
            proportion * (outputs[index + 1] - outputs[index]);
    }
    return outputs[outputs.len - 1];
}

fn normalizeNonnegative(values: []f64) bool {
    var power: f64 = 0.0;
    for (values) |value| {
        if (!std.math.isFinite(value) or value < 0.0) return false;
        power += value * value;
    }
    if (!std.math.isFinite(power) or power <= 0.0) return false;
    const scale = 1.0 / @sqrt(power);
    for (values) |*value| value.* *= scale;
    return true;
}

fn finiteVector(vector: Vector) bool {
    return std.math.isFinite(vector.x) and
        std.math.isFinite(vector.y) and
        std.math.isFinite(vector.z);
}

fn dot(left: Vector, right: Vector) f64 {
    return left.x * right.x + left.y * right.y + left.z * right.z;
}

fn degreesToRadians(degrees: f64) f64 {
    return degrees * std.math.pi / 180.0;
}

fn radiansToDegrees(radians: f64) f64 {
    return radians * 180.0 / std.math.pi;
}

fn slicesOverlap(
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

fn objectSliceOverlap(
    comptime Object: type,
    comptime Element: type,
    object: *const Object,
    slice: []Element,
) bool {
    if (slice.len == 0) return false;
    const object_start = @intFromPtr(object);
    const slice_start = @intFromPtr(slice.ptr);
    const object_end = std.math.add(
        usize,
        object_start,
        @sizeOf(Object),
    ) catch return true;
    const slice_bytes = std.math.mul(
        usize,
        slice.len,
        @sizeOf(Element),
    ) catch return true;
    const slice_end = std.math.add(
        usize,
        slice_start,
        slice_bytes,
    ) catch return true;
    return object_start < slice_end and slice_start < object_end;
}

test "polar extent direction grid contains the specified 1652 points" {
    var count: usize = 0;
    for (0..spreading_row_count) |row| {
        const elevation =
            -90.0 + spreading_step_degrees * @as(f64, @floatFromInt(row));
        count += directionsInRow(elevation);
    }
    try std.testing.expectEqual(spreading_direction_count, count);
}

test "polar extent modification preserves and expands declared angles" {
    try std.testing.expectApproxEqAbs(
        @as(f64, 30.0),
        extentModification(30.0, 1.0),
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 360.0),
        extentModification(30.0, 0.0),
        0.000_000_001,
    );
    try std.testing.expect(extentModification(30.0, 2.0) < 30.0);
    try std.testing.expect(extentModification(30.0, 0.5) > 30.0);
}

test "polar extent transitions fully to spread at five degrees" {
    try std.testing.expectEqual(
        @as(f64, 0.0),
        spreadProportion(0.0, 0.0),
    );
    try std.testing.expectEqual(
        @as(f64, 0.5),
        spreadProportion(2.5, 0.0),
    );
    try std.testing.expectEqual(
        @as(f64, 1.0),
        spreadProportion(0.0, 5.0),
    );
    try std.testing.expectEqual(
        @as(f64, 1.0),
        spreadProportion(360.0, 360.0),
    );
}

test "polar extent weighting covers wide, tall, and full-sphere shapes" {
    const centre = adm_polar_panner.PolarPosition{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const wide = ExtentShape.init(centre, 90.0, 30.0);
    try std.testing.expectEqual(
        @as(f64, 1.0),
        wide.weight(polarVector(40.0, 0.0)),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        wide.weight(polarVector(0.0, 30.0)),
    );

    const tall = ExtentShape.init(centre, 30.0, 90.0);
    try std.testing.expectEqual(
        @as(f64, 1.0),
        tall.weight(polarVector(0.0, 40.0)),
    );
    try std.testing.expectEqual(
        @as(f64, 0.0),
        tall.weight(polarVector(30.0, 0.0)),
    );

    const full = ExtentShape.init(centre, 360.0, 360.0);
    try std.testing.expectEqual(
        @as(f64, 1.0),
        full.weight(polarVector(180.0, -90.0)),
    );
}
