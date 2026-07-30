const std = @import("std");
const convolution = @import("../gui_ir_convolution.zig");

pub const Direction = struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
};

pub const Position = struct {
    x: f64,
    y: f64,
    z: f64,
};

pub const HeadPose = struct {
    position: Position,
    yaw_degrees: f64 = 0.0,
    pitch_degrees: f64 = 0.0,
    roll_degrees: f64 = 0.0,
};

pub const MotionPoint = struct {
    sample_position: u64,
    source_position: Position,
    head_pose: HeadPose,
};

pub const Interpolation = enum {
    nearest,
    inverse_distance,
    delay_aligned,
    spectral,
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
        response_frame_count: usize,
        directions: [maximum_measurements]Direction =
            @splat(.{
                .azimuth_degrees = 0.0,
                .elevation_degrees = 0.0,
            }),
        delays_samples: [maximum_measurements][channel_count]f64 =
            @splat(@splat(0.0)),
        responses: [maximum_measurements][maximum_frames][channel_count]f32 =
            @splat(@splat(@splat(0.0))),

        pub fn init(
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
        ) !Self {
            return initWithDelays(
                sample_rate,
                directions,
                interleaved_responses,
                &.{},
            );
        }

        pub fn initWithDelays(
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
            delays_samples: []const f64,
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
            const response_frame_count =
                interleaved_responses.len / samples_per_frame;
            if (response_frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            if (delays_samples.len != 0 and
                delays_samples.len != channel_count and
                delays_samples.len !=
                    directions.len * channel_count)
                return error.InvalidHrtfDelayShape;

            var maximum_delay: f64 = 0.0;
            for (0..directions.len) |measurement_index| {
                for (0..channel_count) |channel_index| {
                    const delay = delayValue(
                        delays_samples,
                        measurement_index,
                        channel_index,
                    );
                    if (!std.math.isFinite(delay) or delay < 0.0)
                        return error.InvalidHrtfDelay;
                    maximum_delay = @max(maximum_delay, delay);
                }
            }
            if (maximum_delay >
                @as(f64, @floatFromInt(maximum_frames)))
                return error.HrtfFrameCapacityExceeded;
            const delay_frames: usize =
                @intFromFloat(@ceil(maximum_delay));
            const frame_count = std.math.add(
                usize,
                response_frame_count,
                delay_frames,
            ) catch return error.HrtfFrameCapacityExceeded;
            if (frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;

            var result = Self{
                .sample_rate = sample_rate,
                .measurement_count = directions.len,
                .frame_count = frame_count,
                .response_frame_count = response_frame_count,
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
                for (0..channel_count) |channel_index| {
                    result.delays_samples[measurement_index][channel_index] =
                        delayValue(
                            delays_samples,
                            measurement_index,
                            channel_index,
                        );
                }
                for (0..response_frame_count) |frame_index| {
                    for (0..channel_count) |channel_index| {
                        const source_index =
                            (measurement_index *
                                response_frame_count +
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
                .inverse_distance,
                .delay_aligned,
                .spectral,
                => {
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

            var staged: [maximum_frames * channel_count]f32 =
                @splat(0.0);
            if (method == .spectral) {
                try self.interpolateSpectral(
                    selected,
                    weights,
                    &staged,
                );
                @memcpy(destination, staged[0..destination.len]);
                return;
            }
            for (0..self.frame_count) |frame_index| {
                for (0..channel_count) |channel_index| {
                    var aligned_delay: f64 = 0.0;
                    if (method == .delay_aligned) {
                        for (0..selected.count) |neighbor_index| {
                            aligned_delay +=
                                weights[neighbor_index] *
                                self.delays_samples[
                                    selected.indices[neighbor_index]
                                ][channel_index];
                        }
                    }
                    var value: f64 = 0.0;
                    for (0..selected.count) |neighbor_index| {
                        const measurement_index =
                            selected.indices[neighbor_index];
                        const delay = if (method == .delay_aligned)
                            aligned_delay
                        else
                            self.delays_samples[
                                measurement_index
                            ][channel_index];
                        value +=
                            weights[neighbor_index] *
                            self.sampleResponse(
                                measurement_index,
                                channel_index,
                                @as(
                                    f64,
                                    @floatFromInt(frame_index),
                                ) - delay,
                            );
                    }
                    const converted: f32 = @floatCast(value);
                    if (!std.math.isFinite(converted))
                        return error.InvalidHrtfInterpolation;
                    staged[
                        frame_index * channel_count + channel_index
                    ] = converted;
                }
            }
            @memcpy(destination, staged[0..destination.len]);
        }

        pub fn valid(self: *const Self) bool {
            if (self.sample_rate < 8_000 or self.sample_rate > 384_000 or
                self.measurement_count == 0 or
                self.measurement_count > maximum_measurements or
                self.frame_count == 0 or
                self.frame_count > maximum_frames or
                self.response_frame_count == 0 or
                self.response_frame_count > self.frame_count)
            {
                return false;
            }
            var maximum_delay: f64 = 0.0;
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
                for (self.delays_samples[measurement_index]) |delay| {
                    if (!std.math.isFinite(delay) or delay < 0.0)
                        return false;
                    maximum_delay = @max(maximum_delay, delay);
                }
                for (
                    self.responses[measurement_index][0..self.response_frame_count],
                ) |frame| {
                    for (frame) |sample| {
                        if (!std.math.isFinite(sample)) return false;
                        if (sample != 0.0) has_energy = true;
                    }
                }
                if (!has_energy) return false;
            }
            if (maximum_delay >
                @as(f64, @floatFromInt(maximum_frames)))
                return false;
            const delay_frames: usize =
                @intFromFloat(@ceil(maximum_delay));
            if (self.response_frame_count + delay_frames !=
                self.frame_count)
                return false;
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

        fn sampleResponse(
            self: *const Self,
            measurement_index: usize,
            channel_index: usize,
            sample_position: f64,
        ) f64 {
            if (sample_position < 0.0 or
                sample_position >=
                    @as(
                        f64,
                        @floatFromInt(self.response_frame_count),
                    ))
                return 0.0;
            const first: usize = @intFromFloat(@floor(sample_position));
            const fraction =
                sample_position -
                @as(f64, @floatFromInt(first));
            const first_value =
                self.responses[measurement_index][first][channel_index];
            if (fraction == 0.0) return first_value;
            const second_value = if (first + 1 < self.response_frame_count)
                self.responses[measurement_index][first + 1][channel_index]
            else
                0.0;
            return first_value +
                (second_value - first_value) * fraction;
        }

        fn interpolateSpectral(
            self: *const Self,
            selected: Neighbors,
            weights: [3]f64,
            destination: *[maximum_frames * channel_count]f32,
        ) !void {
            const count = self.response_frame_count;
            var spectrum_real: [maximum_frames]f64 = @splat(0.0);
            var spectrum_imaginary: [maximum_frames]f64 = @splat(0.0);
            var local_response: [maximum_frames]f64 = @splat(0.0);
            for (0..channel_count) |channel_index| {
                for (0..count) |bin| {
                    var log_magnitude: f64 = 0.0;
                    var magnitude_sum: f64 = 0.0;
                    var phase_x: f64 = 0.0;
                    var phase_y: f64 = 0.0;
                    var linear_real: f64 = 0.0;
                    var linear_imaginary: f64 = 0.0;
                    for (0..selected.count) |neighbor_index| {
                        const measurement_index =
                            selected.indices[neighbor_index];
                        var real: f64 = 0.0;
                        var imaginary: f64 = 0.0;
                        for (0..count) |sample_index| {
                            const angle =
                                -2.0 *
                                std.math.pi *
                                @as(f64, @floatFromInt(bin)) *
                                @as(
                                    f64,
                                    @floatFromInt(sample_index),
                                ) /
                                @as(f64, @floatFromInt(count));
                            const sample =
                                self.responses[
                                    measurement_index
                                ][sample_index][channel_index];
                            real += sample * @cos(angle);
                            imaginary += sample * @sin(angle);
                        }
                        const magnitude = @sqrt(
                            real * real +
                                imaginary * imaginary,
                        );
                        const weight = weights[neighbor_index];
                        magnitude_sum += weight * magnitude;
                        log_magnitude +=
                            weight * @log(@max(magnitude, 1.0e-30));
                        if (magnitude > 1.0e-30) {
                            phase_x += weight * real / magnitude;
                            phase_y += weight * imaginary / magnitude;
                        }
                        linear_real += weight * real;
                        linear_imaginary += weight * imaginary;
                    }
                    if (magnitude_sum <= 1.0e-30) {
                        spectrum_real[bin] = 0.0;
                        spectrum_imaginary[bin] = 0.0;
                        continue;
                    }
                    const phase_length =
                        @sqrt(phase_x * phase_x + phase_y * phase_y);
                    if (phase_length <= 1.0e-15) {
                        spectrum_real[bin] = linear_real;
                        spectrum_imaginary[bin] =
                            linear_imaginary;
                    } else {
                        const magnitude = @exp(log_magnitude);
                        spectrum_real[bin] =
                            magnitude * phase_x / phase_length;
                        spectrum_imaginary[bin] =
                            magnitude * phase_y / phase_length;
                    }
                    if (!std.math.isFinite(spectrum_real[bin]) or
                        !std.math.isFinite(
                            spectrum_imaginary[bin],
                        ))
                        return error.InvalidHrtfInterpolation;
                }

                for (0..count) |sample_index| {
                    var value: f64 = 0.0;
                    for (0..count) |bin| {
                        const angle =
                            2.0 *
                            std.math.pi *
                            @as(f64, @floatFromInt(bin)) *
                            @as(
                                f64,
                                @floatFromInt(sample_index),
                            ) /
                            @as(f64, @floatFromInt(count));
                        value +=
                            spectrum_real[bin] * @cos(angle) -
                            spectrum_imaginary[bin] * @sin(angle);
                    }
                    local_response[sample_index] =
                        value / @as(f64, @floatFromInt(count));
                    if (!std.math.isFinite(
                        local_response[sample_index],
                    ))
                        return error.InvalidHrtfInterpolation;
                }

                var aligned_delay: f64 = 0.0;
                for (0..selected.count) |neighbor_index| {
                    aligned_delay +=
                        weights[neighbor_index] *
                        self.delays_samples[
                            selected.indices[neighbor_index]
                        ][channel_index];
                }
                for (0..self.frame_count) |frame_index| {
                    const sample_position =
                        @as(f64, @floatFromInt(frame_index)) -
                        aligned_delay;
                    var value: f64 = 0.0;
                    if (sample_position >= 0.0 and
                        sample_position <
                            @as(f64, @floatFromInt(count)))
                    {
                        const first: usize =
                            @intFromFloat(@floor(sample_position));
                        const fraction =
                            sample_position -
                            @as(f64, @floatFromInt(first));
                        const first_value = local_response[first];
                        const second_value =
                            if (first + 1 < count)
                                local_response[first + 1]
                            else
                                0.0;
                        value = first_value +
                            (second_value - first_value) * fraction;
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
    };
}

fn delayValue(
    delays: []const f64,
    measurement_index: usize,
    channel_index: usize,
) f64 {
    if (delays.len == 0) return 0.0;
    if (delays.len == 2) return delays[channel_index];
    return delays[measurement_index * 2 + channel_index];
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

pub fn MotionRenderer(
    comptime maximum_frames: usize,
    comptime maximum_points: usize,
    comptime maximum_crossfade_samples: usize,
) type {
    if (maximum_frames == 0)
        @compileError("HRTF motion renderer requires frame capacity");
    if (maximum_points == 0)
        @compileError("HRTF motion renderer requires point capacity");
    if (maximum_crossfade_samples == 0)
        @compileError("HRTF motion renderer requires crossfade capacity");

    return struct {
        const Self = @This();

        pub const frame_capacity = maximum_frames;
        pub const point_capacity = maximum_points;
        pub const crossfade_capacity = maximum_crossfade_samples;

        sample_rate: u32 = 0,
        frame_count: usize = 0,
        point_count: usize = 0,
        crossfade_samples: usize = 0,
        points: [maximum_points]MotionPoint = @splat(.{
            .sample_position = 0,
            .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .head_pose = .{
                .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            },
        }),
        directions: [maximum_points]Direction = @splat(.{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        }),
        filters: [maximum_points][maximum_frames][2]f32 =
            @splat(@splat(@splat(0.0))),
        history: [maximum_frames]f32 = @splat(0.0),
        history_write: usize = 0,
        current_point: usize = 0,
        sample_position: u64 = 0,
        prepared: bool = false,

        pub fn prepare(
            self: *Self,
            database: anytype,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            if (!database.valid()) return error.InvalidHrtfDatabase;
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            if (points.len == 0 or points.len > maximum_points)
                return error.InvalidHrtfMotionPointCount;
            if (crossfade_samples == 0 or
                crossfade_samples > maximum_crossfade_samples)
                return error.InvalidHrtfCrossfade;
            if (points[0].sample_position != 0)
                return error.InvalidHrtfMotionSchedule;

            var staged_directions: [maximum_points]Direction =
                @splat(.{
                    .azimuth_degrees = 0.0,
                    .elevation_degrees = 0.0,
                });
            var staged_filters: [maximum_points][maximum_frames][2]f32 =
                @splat(@splat(@splat(0.0)));
            for (points, 0..) |point, point_index| {
                if (point_index != 0) {
                    const previous =
                        points[point_index - 1].sample_position;
                    if (point.sample_position <= previous or
                        point.sample_position - previous <
                            crossfade_samples)
                        return error.InvalidHrtfMotionSchedule;
                }
                const direction = try directionFromPositions(
                    point.source_position,
                    point.head_pose,
                );
                staged_directions[point_index] = direction;
                const destination = @as(
                    [*]f32,
                    @ptrCast(&staged_filters[point_index]),
                )[0 .. database.frame_count * 2];
                try database.interpolate(
                    direction,
                    interpolation,
                    destination,
                );
            }

            self.sample_rate = database.sample_rate;
            self.frame_count = database.frame_count;
            self.point_count = points.len;
            self.crossfade_samples = crossfade_samples;
            @memcpy(self.points[0..points.len], points);
            @memcpy(
                self.directions[0..points.len],
                staged_directions[0..points.len],
            );
            @memcpy(
                self.filters[0..points.len],
                staged_filters[0..points.len],
            );
            self.reset();
            self.prepared = true;
        }

        pub fn processSample(self: *Self, input: f32) [2]f32 {
            if (!self.prepared or self.frame_count == 0)
                return @splat(0.0);
            self.history[self.history_write] =
                if (std.math.isFinite(input)) input else 0.0;
            const current = self.filtered(self.current_point);
            var output = current;
            const next_point = self.current_point + 1;
            if (next_point < self.point_count and
                self.sample_position >=
                    self.points[next_point].sample_position)
            {
                const transition_position =
                    self.sample_position -
                    self.points[next_point].sample_position;
                const completed_samples =
                    transition_position +| 1;
                const progress = @min(
                    @as(f64, @floatFromInt(completed_samples)) /
                        @as(
                            f64,
                            @floatFromInt(self.crossfade_samples),
                        ),
                    1.0,
                );
                const blend =
                    progress * progress * (3.0 - 2.0 * progress);
                const next = self.filtered(next_point);
                for (0..2) |channel_index| {
                    output[channel_index] = @floatCast(
                        @as(f64, current[channel_index]) *
                            (1.0 - blend) +
                            @as(f64, next[channel_index]) * blend,
                    );
                }
                if (completed_samples >= self.crossfade_samples)
                    self.current_point = next_point;
            }
            self.history_write =
                (self.history_write + 1) % self.frame_count;
            self.sample_position +|= 1;
            return output;
        }

        pub fn reset(self: *Self) void {
            @memset(&self.history, 0.0);
            self.history_write = 0;
            self.current_point = 0;
            self.sample_position = 0;
        }

        pub fn currentDirection(self: *const Self) ?Direction {
            if (!self.prepared) return null;
            return self.directions[self.current_point];
        }

        fn filtered(
            self: *const Self,
            point_index: usize,
        ) [2]f32 {
            var output: [2]f64 = @splat(0.0);
            for (0..self.frame_count) |frame_index| {
                const history_index =
                    (self.history_write +
                        self.frame_count -
                        frame_index) %
                    self.frame_count;
                const sample = self.history[history_index];
                for (0..2) |channel_index| {
                    output[channel_index] +=
                        sample *
                        self.filters[point_index][frame_index][channel_index];
                }
            }
            const converted = [2]f32{
                @floatCast(output[0]),
                @floatCast(output[1]),
            };
            if (!std.math.isFinite(converted[0]) or
                !std.math.isFinite(converted[1]))
                return @splat(0.0);
            return converted;
        }
    };
}

const direction_tolerance_squared = 1.0e-24;

pub fn directionFromPositions(
    source_position: Position,
    head_pose: HeadPose,
) !Direction {
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

    const yaw =
        head_pose.yaw_degrees * std.math.pi / 180.0;
    const pitch =
        head_pose.pitch_degrees * std.math.pi / 180.0;
    const roll =
        head_pose.roll_degrees * std.math.pi / 180.0;
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
    const result = Direction{
        .azimuth_degrees = std.math.atan2(local[1], local[0]) * 180.0 /
            std.math.pi,
        .elevation_degrees = std.math.atan2(local[2], horizontal) * 180.0 /
            std.math.pi,
    };
    try validateDirection(result);
    return result;
}

fn validatePosition(position: Position) !void {
    if (!std.math.isFinite(position.x) or
        !std.math.isFinite(position.y) or
        !std.math.isFinite(position.z))
        return error.InvalidHrtfPosition;
}

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

test "HRTF database applies measured delays and reconstructs exact spectra" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(1, 4);
    const database = try Db.initWithDelays(
        48_000,
        &directions,
        &.{
            1.0,  0.5,
            0.25, 0.125,
        },
        &.{ 0.5, 0.5 },
    );
    try std.testing.expectEqual(@as(usize, 3), database.frame_count);

    var delayed: [6]f32 = undefined;
    try database.interpolate(directions[0], .nearest, &delayed);
    try std.testing.expectEqualDeep(
        [_]f32{
            0.0,   0.0,
            0.625, 0.3125,
            0.125, 0.0625,
        },
        delayed,
    );

    var spectral: [6]f32 = undefined;
    try database.interpolate(directions[0], .spectral, &spectral);
    for (spectral, delayed) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_001,
        );
    }
}

test "HRTF delay-aligned interpolation avoids arrival-time smearing" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = -45.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 45.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(2, 4);
    const database = try Db.initWithDelays(
        48_000,
        &directions,
        &.{
            1.0, 1.0,
            1.0, 1.0,
        },
        &.{ 0.0, 0.0, 2.0, 2.0 },
    );
    var ordinary: [6]f32 = undefined;
    var aligned: [6]f32 = undefined;
    const center = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    try database.interpolate(center, .inverse_distance, &ordinary);
    try database.interpolate(center, .delay_aligned, &aligned);

    try std.testing.expect(ordinary[0] > 0.49);
    try std.testing.expect(ordinary[4] > 0.49);
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        aligned[2],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.0),
        aligned[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.0),
        aligned[4],
        0.000_001,
    );
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

test "HRTF motion schedule follows head pose with smooth filter changes" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = -90.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(2, 1);
    const database = try Db.init(
        48_000,
        &directions,
        &.{
            1.0, 0.0,
            0.0, 1.0,
        },
    );
    const points = [_]MotionPoint{
        .{
            .sample_position = 0,
            .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .head_pose = .{
                .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            },
        },
        .{
            .sample_position = 4,
            .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .head_pose = .{
                .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                .yaw_degrees = 90.0,
            },
        },
    };
    const Moving = MotionRenderer(1, 2, 4);
    var renderer = Moving{};
    try renderer.prepare(
        &database,
        &points,
        .nearest,
        4,
    );
    try std.testing.expectEqual(
        directions[0],
        renderer.currentDirection().?,
    );

    var previous: [2]f32 = @splat(0.0);
    for (0..8) |sample_index| {
        const output = renderer.processSample(1.0);
        try std.testing.expectApproxEqAbs(
            @as(f32, 1.0),
            output[0] + output[1],
            0.000_001,
        );
        if (sample_index != 0) {
            try std.testing.expect(
                @abs(output[0] - previous[0]) <= 0.35,
            );
            try std.testing.expect(
                @abs(output[1] - previous[1]) <= 0.35,
            );
        }
        previous = output;
    }
    try std.testing.expectEqual(
        directions[1],
        renderer.currentDirection().?,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 1.0 },
        renderer.processSample(1.0),
    );

    const original_direction = renderer.currentDirection();
    var invalid = points;
    invalid[1].sample_position = 2;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, &invalid, .nearest, 4),
    );
    try std.testing.expectEqual(
        original_direction,
        renderer.currentDirection(),
    );
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
    try std.testing.expectError(
        error.InvalidHrtfDelayShape,
        Db.initWithDelays(
            48_000,
            &one,
            &.{ 1.0, 1.0 },
            &.{0.0},
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfDelay,
        Db.initWithDelays(
            48_000,
            &one,
            &.{ 1.0, 1.0 },
            &.{ -1.0, 0.0 },
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
