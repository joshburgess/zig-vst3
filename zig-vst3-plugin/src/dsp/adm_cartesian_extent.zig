const std = @import("std");

const grid_count: usize = 40;
const reduced_height_grid_count: usize = grid_count / 2;
const minimum_term: f64 = std.math.pow(f64, 10.0, -6.5);
const normalization_tolerance: f64 = 1.0e-16;

pub const Position = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

pub fn Panner(
    comptime Sample: type,
    comptime maximum_outputs: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("ADM Cartesian extent panner supports f32 and f64 samples");
    if (maximum_outputs == 0)
        @compileError("ADM Cartesian extent panner requires output capacity");

    return struct {
        const Self = @This();

        output_count: usize,
        panner_output_count: usize,
        positions: [maximum_outputs]Position = @splat(.{}),
        enabled: [maximum_outputs]bool = @splat(false),

        pub fn init(
            positions: []const Position,
            enabled: []const bool,
        ) !Self {
            if (positions.len == 0 or
                positions.len > maximum_outputs or
                positions.len != enabled.len)
            {
                return error.InvalidAdmCartesianExtentLayout;
            }

            var result = Self{
                .output_count = positions.len,
                .panner_output_count = 0,
            };
            for (positions, enabled, 0..) |position, is_enabled, index| {
                if (!validPosition(position))
                    return error.InvalidAdmCartesianExtentLayout;
                result.positions[index] = position;
                result.enabled[index] = is_enabled;
                if (is_enabled) result.panner_output_count += 1;
            }
            if (result.panner_output_count == 0)
                return error.InvalidAdmCartesianExtentLayout;
            return result;
        }

        pub fn calculateGains(
            self: *const Self,
            position: Position,
            size_x: f64,
            size_y: f64,
            size_z: f64,
            point_gains: []const Sample,
            gains: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidAdmCartesianExtentState;
            if (!validPosition(position) or
                position.x < -1.0 or position.x > 1.0 or
                position.y < -1.0 or position.y > 1.0 or
                position.z < -1.0 or position.z > 1.0)
            {
                return error.InvalidAdmCartesianExtentPosition;
            }
            if (!validSize(size_x) or
                !validSize(size_y) or
                !validSize(size_z))
            {
                return error.InvalidAdmCartesianExtent;
            }
            if (point_gains.len != self.output_count or
                gains.len != self.output_count)
            {
                return error.AdmCartesianExtentOutputCountMismatch;
            }
            if (slicesOverlap(Sample, point_gains, gains))
                return error.AdmCartesianExtentAliasedBuffers;

            const z_count = self.heightGridCount();
            var object_position = position;
            if (z_count == reduced_height_grid_count)
                object_position.z = @max(0.0, object_position.z);

            const sx = @max(
                scaleSize(size_x),
                2.0 / @as(f64, @floatFromInt(grid_count - 1)),
            );
            const sy = @max(
                scaleSize(size_y),
                2.0 / @as(f64, @floatFromInt(grid_count - 1)),
            );
            const sz = @max(scaleSize(size_z), 2.0 / @as(f64, @floatFromInt(z_count - 1)));
            const effective_size = self.effectiveSize(sx, sy, sz);
            const exponent = extentExponent(effective_size);
            const dimension_count = self.dimension();

            var x_weights: [grid_count]f64 = undefined;
            var y_weights: [grid_count]f64 = undefined;
            var z_weights: [grid_count]f64 = undefined;
            fillWeights(
                &x_weights,
                object_position.x,
                sx,
                -1.0,
                false,
            );
            fillWeights(
                &y_weights,
                object_position.y,
                sy,
                -1.0,
                false,
            );
            fillWeights(
                z_weights[0..z_count],
                object_position.z,
                sz,
                if (z_count == grid_count) -1.0 else 0.0,
                true,
            );

            var inside: [maximum_outputs]f64 = @splat(0.0);
            var boundary: [maximum_outputs]f64 = @splat(0.0);
            var size_gains: [maximum_outputs]f64 = @splat(0.0);
            var inside_power: f64 = 0.0;
            for (0..self.output_count) |output_index| {
                if (!self.enabled[output_index]) continue;
                const fx = self.axisContribution(
                    output_index,
                    .x,
                    &x_weights,
                    -1.0,
                    exponent,
                );
                const fy = self.axisContribution(
                    output_index,
                    .y,
                    &y_weights,
                    -1.0,
                    exponent,
                );
                const fz = self.axisContribution(
                    output_index,
                    .z,
                    z_weights[0..z_count],
                    if (z_count == grid_count) -1.0 else 0.0,
                    exponent,
                );
                const value = fx * fy * fz;
                if (!std.math.isFinite(value) or value < 0.0)
                    return error.InvalidAdmCartesianExtentGain;
                inside[output_index] = value;
                inside_power += value * value;

                const left = boundaryTerm(
                    self.axisGain(output_index, .x, -1.0),
                    x_weights[0],
                    exponent,
                );
                const right = boundaryTerm(
                    self.axisGain(output_index, .x, 1.0),
                    x_weights[grid_count - 1],
                    exponent,
                );
                const front = boundaryTerm(
                    self.axisGain(output_index, .y, -1.0),
                    y_weights[0],
                    exponent,
                );
                const back = boundaryTerm(
                    self.axisGain(output_index, .y, 1.0),
                    y_weights[grid_count - 1],
                    exponent,
                );
                const floor = boundaryTerm(
                    self.axisGain(
                        output_index,
                        .z,
                        if (z_count == grid_count) -1.0 else 0.0,
                    ),
                    z_weights[0],
                    exponent,
                );
                const ceiling = boundaryTerm(
                    self.axisGain(output_index, .z, 1.0),
                    z_weights[z_count - 1],
                    exponent,
                );
                boundary[output_index] =
                    (left + right) * fy * fz +
                    (front + back) * fx * fz +
                    (floor + ceiling) * fx * fy;
                if (!std.math.isFinite(boundary[output_index]) or
                    boundary[output_index] < 0.0)
                {
                    return error.InvalidAdmCartesianExtentGain;
                }
            }

            const inside_scale = if (inside_power > normalization_tolerance *
                normalization_tolerance)
                1.0 / @sqrt(inside_power)
            else
                0.0;
            const fade = insideFade(
                dimension_count,
                sx,
                sy,
                sz,
                object_position,
            );
            var size_power: f64 = 0.0;
            for (0..self.output_count) |output_index| {
                const base = boundary[output_index] +
                    fade * inside[output_index] * inside_scale;
                if (!std.math.isFinite(base) or base < 0.0)
                    return error.InvalidAdmCartesianExtentGain;
                const value = std.math.pow(f64, base, 1.0 / exponent);
                if (!std.math.isFinite(value) or value < 0.0)
                    return error.InvalidAdmCartesianExtentGain;
                size_gains[output_index] = value;
                size_power += value * value;
            }
            const size_scale = if (size_power > normalization_tolerance *
                normalization_tolerance)
                1.0 / @sqrt(size_power)
            else
                0.0;

            const fade_size: f64 = 0.2;
            const blend_angle = effective_size * std.math.pi /
                (fade_size * 2.0);
            const point_scale = if (effective_size < fade_size)
                @cos(blend_angle)
            else
                0.0;
            const extent_scale = if (effective_size < fade_size)
                @sin(blend_angle)
            else
                1.0;

            var total_power: f64 = 0.0;
            var total: [maximum_outputs]f64 = @splat(0.0);
            for (
                point_gains,
                size_gains[0..self.output_count],
                total[0..self.output_count],
                0..,
            ) |point_gain, size_gain, *value, output_index| {
                if (!self.enabled[output_index]) {
                    value.* = 0.0;
                    continue;
                }
                if (!std.math.isFinite(point_gain) or point_gain < 0.0)
                    return error.InvalidAdmCartesianExtentGain;
                value.* = point_scale * @as(f64, @floatCast(point_gain)) +
                    extent_scale * size_gain * size_scale;
                if (!std.math.isFinite(value.*) or value.* < 0.0)
                    return error.InvalidAdmCartesianExtentGain;
                total_power += value.* * value.*;
            }
            if (!std.math.isFinite(total_power) or
                total_power <= normalization_tolerance *
                    normalization_tolerance)
            {
                return error.InvalidAdmCartesianExtentGain;
            }
            const total_scale = 1.0 / @sqrt(total_power);
            for (gains, total[0..self.output_count]) |*gain, value| {
                gain.* = @floatCast(value * total_scale);
                if (!std.math.isFinite(gain.*))
                    return error.InvalidAdmCartesianExtentGain;
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.output_count == 0 or
                self.output_count > maximum_outputs or
                self.panner_output_count == 0 or
                self.panner_output_count > self.output_count)
            {
                return false;
            }
            var enabled_count: usize = 0;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!validPosition(position)) return false;
                if (is_enabled) enabled_count += 1;
            }
            return enabled_count == self.panner_output_count;
        }

        const Axis = enum { x, y, z };

        fn effectiveSize(
            self: *const Self,
            sx: f64,
            sy: f64,
            sz: f64,
        ) f64 {
            const first = self.firstEnabledPosition() orelse return 0.0;
            var same_y = true;
            var same_z = true;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled) continue;
                same_y = same_y and position.y == first.y;
                same_z = same_z and position.z == first.z;
            }
            if (same_y and same_z) return sx;
            if (same_z) {
                const larger = @max(sx, sy);
                const smaller = @min(sx, sy);
                return 0.75 * larger + 0.25 * smaller;
            }
            var sizes = [_]f64{ sx, sy, sz };
            std.mem.sort(f64, &sizes, {}, std.sort.asc(f64));
            return (6.0 * sizes[2] +
                2.0 * sizes[1] +
                sizes[0]) / 9.0;
        }

        fn dimension(self: *const Self) usize {
            const first = self.firstEnabledPosition() orelse return 0;
            var varies_x = false;
            var varies_y = false;
            var varies_z = false;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled) continue;
                varies_x = varies_x or position.x != first.x;
                varies_y = varies_y or position.y != first.y;
                varies_z = varies_z or position.z != first.z;
            }
            return @as(usize, @intFromBool(varies_x)) +
                @as(usize, @intFromBool(varies_y)) +
                @as(usize, @intFromBool(varies_z));
        }

        fn heightGridCount(self: *const Self) usize {
            var distinct: [maximum_outputs]f64 = undefined;
            var distinct_count: usize = 0;
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled) continue;
                var found = false;
                for (distinct[0..distinct_count]) |height| {
                    if (position.z == height) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    distinct[distinct_count] = position.z;
                    distinct_count += 1;
                }
            }
            return if (distinct_count >= 3)
                grid_count
            else
                reduced_height_grid_count;
        }

        fn firstEnabledPosition(self: *const Self) ?Position {
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (is_enabled) return position;
            }
            return null;
        }

        fn axisContribution(
            self: *const Self,
            output_index: usize,
            axis: Axis,
            weights: []const f64,
            start: f64,
            exponent: f64,
        ) f64 {
            var sum: f64 = 0.0;
            for (weights, 0..) |weight, index| {
                const coordinate = gridCoordinate(index, weights.len, start);
                const gain = self.axisGain(output_index, axis, coordinate);
                sum += std.math.pow(f64, gain * weight, exponent);
            }
            return if (sum < minimum_term) 0.0 else sum;
        }

        fn axisGain(
            self: *const Self,
            output_index: usize,
            axis: Axis,
            coordinate: f64,
        ) f64 {
            const output = self.positions[output_index];
            const bounds = switch (axis) {
                .z => self.zBounds(coordinate),
                .y => self.yBounds(coordinate, output.z),
                .x => self.xBounds(coordinate, output.y, output.z),
            };
            const output_coordinate = axisCoordinate(output, axis);
            const low = bounds.low orelse {
                const high = bounds.high orelse return 0.0;
                return if (output_coordinate == high) 1.0 else 0.0;
            };
            const high = bounds.high orelse
                return if (output_coordinate == low) 1.0 else 0.0;
            if (output_coordinate < low or output_coordinate > high)
                return 0.0;
            if (low == high) return 1.0;
            if (output_coordinate == low) {
                return @cos(
                    (coordinate - low) / (high - low) *
                        std.math.pi / 2.0,
                );
            }
            return @sin(
                (coordinate - low) / (high - low) *
                    std.math.pi / 2.0,
            );
        }

        fn zBounds(self: *const Self, coordinate: f64) PannerBounds {
            var result = PannerBounds{};
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled) continue;
                updateBounds(&result, position.z, coordinate);
            }
            return result;
        }

        fn yBounds(
            self: *const Self,
            coordinate: f64,
            plane_z: f64,
        ) PannerBounds {
            var result = PannerBounds{};
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled or position.z != plane_z) continue;
                updateBounds(&result, position.y, coordinate);
            }
            return result;
        }

        fn xBounds(
            self: *const Self,
            coordinate: f64,
            row_y: f64,
            plane_z: f64,
        ) PannerBounds {
            var result = PannerBounds{};
            for (
                self.positions[0..self.output_count],
                self.enabled[0..self.output_count],
            ) |position, is_enabled| {
                if (!is_enabled or
                    position.y != row_y or
                    position.z != plane_z)
                {
                    continue;
                }
                updateBounds(&result, position.x, coordinate);
            }
            return result;
        }
    };
}

fn scaleSize(value: f64) f64 {
    const inputs = [_]f64{ 0.0, 0.2, 0.5, 0.75, 1.0 };
    const outputs = [_]f64{ 0.0, 0.3, 1.0, 1.8, 2.8 };
    const clipped = @min(value, 1.0);
    for (1..inputs.len) |index| {
        if (clipped > inputs[index]) continue;
        const proportion = (clipped - inputs[index - 1]) /
            (inputs[index] - inputs[index - 1]);
        return outputs[index - 1] +
            proportion * (outputs[index] - outputs[index - 1]);
    }
    return outputs[outputs.len - 1];
}

fn extentExponent(effective_size: f64) f64 {
    if (effective_size <= 0.5) return 6.0;
    return 6.0 - 4.0 * ((effective_size - 0.5) / (2.8 - 0.5));
}

fn fillWeights(
    weights: []f64,
    object_coordinate: f64,
    size: f64,
    start: f64,
    height_axis: bool,
) void {
    for (weights, 0..) |*weight, index| {
        const coordinate = gridCoordinate(index, weights.len, start);
        const divisor = if (height_axis) size else 2.0 * size;
        const exponent = @min(
            std.math.pow(
                f64,
                1.5 * (coordinate - object_coordinate) / divisor,
                4.0,
            ),
            6.5,
        );
        weight.* = std.math.pow(f64, 10.0, -exponent);
        if (height_axis) {
            weight.* *= @cos(
                coordinate * std.math.pi * (3.0 / 7.0),
            );
        }
    }
}

fn gridCoordinate(index: usize, count: usize, start: f64) f64 {
    return start +
        (1.0 - start) * @as(f64, @floatFromInt(index)) /
            @as(f64, @floatFromInt(count - 1));
}

fn boundaryTerm(gain: f64, weight: f64, exponent: f64) f64 {
    return std.math.pow(f64, gain * weight, exponent);
}

fn insideFade(
    dimension: usize,
    sx: f64,
    sy: f64,
    sz: f64,
    position: Position,
) f64 {
    const boundary_distance = switch (dimension) {
        1 => @min(position.x + 1.0, 1.0 - position.x),
        2 => @min(
            @min(position.x + 1.0, 1.0 - position.x),
            @min(position.y + 1.0, 1.0 - position.y),
        ),
        else => @min(
            @min(position.x + 1.0, 1.0 - position.x),
            @min(
                @min(position.y + 1.0, 1.0 - position.y),
                @min(position.z + 1.0, 1.0 - position.z),
            ),
        ),
    };
    return switch (dimension) {
        1 => std.math.pow(
            f64,
            heightFade(sx, boundary_distance),
            3.0,
        ),
        2 => std.math.pow(
            f64,
            heightFade(sx, boundary_distance) *
                heightFade(sy, boundary_distance),
            1.5,
        ),
        else => heightFade(sx, boundary_distance) *
            heightFade(sy, boundary_distance) *
            heightFade(sz, boundary_distance),
    };
}

fn heightFade(size: f64, boundary_distance: f64) f64 {
    if (boundary_distance >= 2.0 * size and
        boundary_distance >= 0.4)
    {
        const value = @max(2.0 * size, 0.4);
        return std.math.pow(
            f64,
            value * value * value / (0.16 * 2.0 * size),
            1.0 / 3.0,
        );
    }
    const ratio = boundary_distance / 0.4;
    return std.math.pow(
        f64,
        boundary_distance / 2.0 * ratio * ratio,
        1.0 / 3.0,
    );
}

fn updateBounds(
    bounds: *PannerBounds,
    candidate: f64,
    coordinate: f64,
) void {
    if (candidate <= coordinate) {
        if (bounds.low) |low| {
            if (candidate > low) bounds.low = candidate;
        } else {
            bounds.low = candidate;
        }
    }
    if (candidate >= coordinate) {
        if (bounds.high) |high| {
            if (candidate < high) bounds.high = candidate;
        } else {
            bounds.high = candidate;
        }
    }
}

const PannerBounds = struct {
    low: ?f64 = null,
    high: ?f64 = null,
};

fn axisCoordinate(position: Position, axis: anytype) f64 {
    return switch (axis) {
        .x => position.x,
        .y => position.y,
        .z => position.z,
    };
}

fn validPosition(position: Position) bool {
    return std.math.isFinite(position.x) and
        std.math.isFinite(position.y) and
        std.math.isFinite(position.z);
}

fn validSize(size: f64) bool {
    return std.math.isFinite(size) and size >= 0.0 and size <= 1.0;
}

fn slicesOverlap(
    comptime Sample: type,
    left: []const Sample,
    right: []Sample,
) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_size = std.math.mul(
        usize,
        left.len,
        @sizeOf(Sample),
    ) catch return true;
    const right_size = std.math.mul(
        usize,
        right.len,
        @sizeOf(Sample),
    ) catch return true;
    const left_end = std.math.add(usize, left_start, left_size) catch
        return true;
    const right_end = std.math.add(usize, right_start, right_size) catch
        return true;
    return left_start < right_end and right_start < left_end;
}
