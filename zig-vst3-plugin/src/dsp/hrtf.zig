const std = @import("std");
const convolution = @import("../gui_ir_convolution.zig");

pub const Direction = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
};

pub const Interpolation = enum {
    nearest,
    inverse_distance,
};

pub fn Database(
    comptime maximum_measurements: usize,
    comptime maximum_frames: usize,
) type {
    if (maximum_measurements == 0)
        @compileError("HRTF database requires measurement capacity");
    if (maximum_frames == 0)
        @compileError("HRTF database requires frame capacity");

    return struct {
        const Self = @This();

        pub const measurement_capacity = maximum_measurements;
        pub const frame_capacity = maximum_frames;
        pub const channel_count: usize = 2;

        sample_rate: u32,
        measurement_count: usize,
        frame_count: usize,
        directions: [maximum_measurements]Direction =
            @splat(.{
                .azimuth_degrees = 0.0,
                .elevation_degrees = 0.0,
            }),
        responses: [maximum_measurements][maximum_frames][channel_count]f32 =
            @splat(@splat(@splat(0.0))),

        pub fn init(
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
        ) !Self {
            if (sample_rate < 8_000 or sample_rate > 384_000)
                return error.InvalidHrtfSampleRate;
            if (directions.len == 0 or
                directions.len > maximum_measurements)
            {
                return error.InvalidHrtfMeasurementCount;
            }
            const samples_per_frame =
                directions.len * channel_count;
            if (interleaved_responses.len == 0 or
                interleaved_responses.len % samples_per_frame != 0)
            {
                return error.InvalidHrtfResponseShape;
            }
            const frame_count =
                interleaved_responses.len / samples_per_frame;
            if (frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;

            var result = Self{
                .sample_rate = sample_rate,
                .measurement_count = directions.len,
                .frame_count = frame_count,
            };
            for (directions, 0..) |direction, measurement_index| {
                try validateDirection(direction);
                result.directions[measurement_index] = direction;
                const vector = directionVector(direction);
                for (directions[0..measurement_index]) |previous| {
                    if (sameDirection(vector, directionVector(previous)))
                        return error.DuplicateHrtfDirection;
                }

                var has_energy = false;
                for (0..frame_count) |frame_index| {
                    for (0..channel_count) |channel_index| {
                        const source_index =
                            (measurement_index * frame_count +
                                frame_index) *
                            channel_count +
                            channel_index;
                        const sample =
                            interleaved_responses[source_index];
                        if (!std.math.isFinite(sample))
                            return error.NonFiniteHrtfSample;
                        if (sample != 0.0) has_energy = true;
                        result.responses[measurement_index][frame_index][channel_index] = sample;
                    }
                }
                if (!has_energy)
                    return error.EmptyHrtfResponse;
            }
            if (!result.valid())
                return error.InvalidHrtfDatabase;
            return result;
        }

        pub fn interpolate(
            self: *const Self,
            direction: Direction,
            method: Interpolation,
            destination: []f32,
        ) !void {
            if (!self.valid()) return error.InvalidHrtfDatabase;
            try validateDirection(direction);
            if (destination.len != self.frame_count * channel_count)
                return error.InvalidHrtfDestinationShape;

            const selected = self.neighbors(direction);
            var weights: [3]f64 = @splat(0.0);
            switch (method) {
                .nearest => weights[0] = 1.0,
                .inverse_distance => {
                    if (selected.distances[0] <=
                        direction_tolerance_squared)
                    {
                        weights[0] = 1.0;
                    } else {
                        var total: f64 = 0.0;
                        for (0..selected.count) |neighbor_index| {
                            const weight =
                                1.0 /
                                selected.distances[neighbor_index];
                            weights[neighbor_index] = weight;
                            total += weight;
                        }
                        if (!std.math.isFinite(total) or total <= 0.0)
                            return error.InvalidHrtfInterpolation;
                        for (weights[0..selected.count]) |*weight|
                            weight.* /= total;
                    }
                },
            }

            for (0..self.frame_count) |frame_index| {
                for (0..channel_count) |channel_index| {
                    var value: f64 = 0.0;
                    for (0..selected.count) |neighbor_index| {
                        value +=
                            weights[neighbor_index] *
                            self.responses[
                                selected.indices[neighbor_index]
                            ][frame_index][channel_index];
                    }
                    const converted: f32 = @floatCast(value);
                    if (!std.math.isFinite(converted))
                        return error.InvalidHrtfInterpolation;
                    destination[
                        frame_index * channel_count + channel_index
                    ] = converted;
                }
            }
        }

        pub fn valid(self: *const Self) bool {
            if (self.sample_rate < 8_000 or self.sample_rate > 384_000 or
                self.measurement_count == 0 or
                self.measurement_count > maximum_measurements or
                self.frame_count == 0 or
                self.frame_count > maximum_frames)
            {
                return false;
            }
            for (
                self.directions[0..self.measurement_count],
                0..,
            ) |direction, measurement_index| {
                validateDirection(direction) catch return false;
                const vector = directionVector(direction);
                for (self.directions[0..measurement_index]) |previous| {
                    if (sameDirection(vector, directionVector(previous)))
                        return false;
                }
                var has_energy = false;
                for (
                    self.responses[measurement_index][0..self.frame_count],
                ) |frame| {
                    for (frame) |sample| {
                        if (!std.math.isFinite(sample)) return false;
                        if (sample != 0.0) has_energy = true;
                    }
                }
                if (!has_energy) return false;
            }
            return true;
        }

        const Neighbors = struct {
            count: usize,
            indices: [3]usize,
            distances: [3]f64,
        };

        fn neighbors(
            self: *const Self,
            direction: Direction,
        ) Neighbors {
            const target = directionVector(direction);
            var result = Neighbors{
                .count = @min(self.measurement_count, 3),
                .indices = @splat(0),
                .distances = @splat(std.math.inf(f64)),
            };
            for (
                self.directions[0..self.measurement_count],
                0..,
            ) |candidate, candidate_index| {
                const distance = chordDistanceSquared(
                    target,
                    directionVector(candidate),
                );
                var insertion_index: usize = 0;
                while (insertion_index < result.count and
                    distance >= result.distances[insertion_index])
                {
                    insertion_index += 1;
                }
                if (insertion_index == result.count) continue;
                var shift = result.count - 1;
                while (shift > insertion_index) : (shift -= 1) {
                    result.indices[shift] = result.indices[shift - 1];
                    result.distances[shift] =
                        result.distances[shift - 1];
                }
                result.indices[insertion_index] = candidate_index;
                result.distances[insertion_index] = distance;
            }
            return result;
        }
    };
}

pub fn Renderer(
    comptime maximum_frames: usize,
    comptime partition_size: usize,
) type {
    const Convolver =
        convolution.PartitionedConvolver(maximum_frames, partition_size);

    return struct {
        const Self = @This();

        pub const frame_capacity = maximum_frames;
        pub const latency_capacity = partition_size;

        convolver: Convolver,
        prepared_response: [maximum_frames * 2]f32 = @splat(0.0),

        pub fn init(
            sample_rate: u32,
            latency: convolution.LatencyMode,
        ) !Self {
            if (sample_rate < 8_000 or sample_rate > 384_000)
                return error.InvalidHrtfSampleRate;
            return .{
                .convolver = Convolver.initWithOptions(
                    sample_rate,
                    .{
                        .latency = latency,
                        .routing = .independent,
                    },
                ),
            };
        }

        pub fn prepare(
            self: *Self,
            database: anytype,
            direction: Direction,
            interpolation: Interpolation,
            generation: u64,
        ) !void {
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            const samples = self.prepared_response[0 .. database.frame_count * 2];
            try database.interpolate(
                direction,
                interpolation,
                samples,
            );

            var began = false;
            errdefer {
                if (began) _ = self.convolver.cancel(generation);
            }
            try self.convolver.begin(.{
                .generation = generation,
                .sample_rate = database.sample_rate,
                .channels = 2,
                .frames = database.frame_count,
            });
            began = true;
            try self.convolver.write(generation, 0, samples);
            try self.convolver.commit(generation);
        }

        pub fn adoptPending(self: *Self) bool {
            return self.convolver.adoptPending();
        }

        pub fn processSample(
            self: *Self,
            input: f32,
        ) [2]f32 {
            return self.convolver.processFrame(input, input);
        }

        pub fn latencySamples(self: *const Self) usize {
            return self.convolver.latencySamples();
        }

        pub fn activeGeneration(self: *const Self) ?u64 {
            const metadata =
                self.convolver.activeMetadata() orelse return null;
            return metadata.generation;
        }

        pub fn reset(self: *Self) void {
            self.convolver.resetProcessing();
        }

        pub fn reprepareForSampleRate(
            self: *Self,
            sample_rate: u32,
        ) !bool {
            return self.convolver.reprepareForSampleRate(sample_rate);
        }
    };
}

const direction_tolerance_squared = 1.0e-24;

fn validateDirection(direction: Direction) !void {
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

fn directionVector(direction: Direction) [3]f64 {
    const azimuth =
        direction.azimuth_degrees * std.math.pi / 180.0;
    const elevation =
        direction.elevation_degrees * std.math.pi / 180.0;
    const horizontal = @cos(elevation);
    return .{
        horizontal * @cos(azimuth),
        horizontal * @sin(azimuth),
        @sin(elevation),
    };
}

fn chordDistanceSquared(first: [3]f64, second: [3]f64) f64 {
    const x = first[0] - second[0];
    const y = first[1] - second[1];
    const z = first[2] - second[2];
    return x * x + y * y + z * z;
}

fn sameDirection(first: [3]f64, second: [3]f64) bool {
    return chordDistanceSquared(first, second) <=
        direction_tolerance_squared;
}

test "HRTF database interpolates nearest and inverse-distance responses" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = -90.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 90.0, .elevation_degrees = 0.0 },
    };
    const responses = [_]f32{
        1.0, 0.0, 0.5,  0.0,
        0.5, 0.5, 0.25, 0.25,
        0.0, 1.0, 0.0,  0.5,
    };
    const Db = Database(3, 2);
    const database = try Db.init(48_000, &directions, &responses);
    var output: [4]f32 = undefined;
    try database.interpolate(
        directions[1],
        .inverse_distance,
        &output,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 0.5, 0.5, 0.25, 0.25 },
        output,
    );
    try database.interpolate(
        .{ .azimuth_degrees = -80.0, .elevation_degrees = 0.0 },
        .nearest,
        &output,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 0.0, 0.5, 0.0 },
        output,
    );

    try database.interpolate(
        .{ .azimuth_degrees = 45.0, .elevation_degrees = 0.0 },
        .inverse_distance,
        &output,
    );
    for (output) |sample|
        try std.testing.expect(std.math.isFinite(sample));
    try std.testing.expect(output[0] < output[1]);
}

test "HRTF renderer publishes and convolves a measured response" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
    };
    const responses = [_]f32{
        1.0, 0.5,
        0.0, 0.0,
        0.0, 0.0,
        0.0, 0.0,
        0.0, 0.0,
        0.0, 0.0,
        0.0, 0.0,
        0.0, 0.0,
    };
    const Db = Database(1, 8);
    const database = try Db.init(48_000, &directions, &responses);
    const HrtfRenderer = Renderer(16, 8);
    var renderer = try HrtfRenderer.init(48_000, .zero);
    try renderer.prepare(
        &database,
        directions[0],
        .nearest,
        1,
    );
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expectEqual(@as(?u64, 1), renderer.activeGeneration());
    try std.testing.expectEqual(@as(usize, 0), renderer.latencySamples());
    const impulse = renderer.processSample(1.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        impulse[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        impulse[1],
        0.000_001,
    );
    const contained = renderer.processSample(std.math.nan(f32));
    try std.testing.expectEqualDeep([_]f32{ 0.0, 0.0 }, contained);
    renderer.reset();
    try std.testing.expect(
        try renderer.reprepareForSampleRate(96_000),
    );
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expectEqual(@as(?u64, 1), renderer.activeGeneration());
}

test "HRTF database rejects malformed measurements transactionally" {
    const Db = Database(2, 2);
    const one = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 90.0 },
    };
    try std.testing.expectError(
        error.InvalidHrtfResponseShape,
        Db.init(48_000, &one, &.{}),
    );
    try std.testing.expectError(
        error.EmptyHrtfResponse,
        Db.init(48_000, &one, &.{ 0.0, 0.0 }),
    );
    const duplicate = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 90.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = 90.0 },
    };
    try std.testing.expectError(
        error.DuplicateHrtfDirection,
        Db.init(48_000, &duplicate, &.{
            1.0, 1.0,
            1.0, 1.0,
        }),
    );
    const wrapped_duplicate = [_]Direction{
        .{ .azimuth_degrees = -180.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 180.0, .elevation_degrees = 0.0 },
    };
    try std.testing.expectError(
        error.DuplicateHrtfDirection,
        Db.init(48_000, &wrapped_duplicate, &.{
            1.0, 1.0,
            1.0, 1.0,
        }),
    );
    try std.testing.expectError(
        error.NonFiniteHrtfSample,
        Db.init(
            48_000,
            &one,
            &.{ std.math.nan(f32), 1.0 },
        ),
    );

    var database = try Db.init(48_000, &one, &.{ 1.0, 1.0 });
    database.responses[0][0][0] = std.math.nan(f32);
    try std.testing.expect(!database.valid());
    var output: [2]f32 = undefined;
    try std.testing.expectError(
        error.InvalidHrtfDatabase,
        database.interpolate(one[0], .nearest, &output),
    );
}

test "HRTF renderer rejects stale generations without losing active data" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(1, 8);
    const database = try Db.init(
        48_000,
        &directions,
        &.{
            1.0, 0.25,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
            0.0, 0.0,
        },
    );
    const HrtfRenderer = Renderer(8, 8);
    var renderer = try HrtfRenderer.init(48_000, .partitioned);
    try renderer.prepare(&database, directions[0], .nearest, 7);
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expectEqual(@as(usize, 8), renderer.latencySamples());
    try std.testing.expectError(
        error.InvalidGeneration,
        renderer.prepare(&database, directions[0], .nearest, 7),
    );
    try std.testing.expectEqual(@as(?u64, 7), renderer.activeGeneration());

    for (0..8) |index| {
        const output =
            renderer.processSample(if (index == 0) 1.0 else 0.0);
        try std.testing.expectEqualDeep([_]f32{ 0.0, 0.0 }, output);
    }
    const delayed = renderer.processSample(0.0);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        delayed[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.25),
        delayed[1],
        0.000_001,
    );
}
