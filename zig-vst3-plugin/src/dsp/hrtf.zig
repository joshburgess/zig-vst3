const std = @import("std");
const convolution = @import("../gui_ir_convolution.zig");

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

pub const MotionPoint = struct {
    sample_position: u64 = 0,
    source_position: Position = .{},
    head_pose: HeadPose = .{},
};

/// Maps an ordered tracker clock onto absolute audio sample positions.
pub const MotionClock = struct {
    sample_rate: u32,
    tracker_ticks_per_second: u64,
    tracker_anchor: u64,
    sample_anchor: u64,
    last_tracker_timestamp: u64 = 0,
    last_sample_position: u64 = 0,
    has_mapped_timestamp: bool = false,

    pub fn init(
        sample_rate: u32,
        tracker_ticks_per_second: u64,
        tracker_anchor: u64,
        sample_anchor: u64,
    ) !MotionClock {
        if (sample_rate < 8_000 or sample_rate > 384_000)
            return error.InvalidHrtfSampleRate;
        if (tracker_ticks_per_second == 0)
            return error.InvalidHrtfTrackerClockRate;
        return .{
            .sample_rate = sample_rate,
            .tracker_ticks_per_second = tracker_ticks_per_second,
            .tracker_anchor = tracker_anchor,
            .sample_anchor = sample_anchor,
        };
    }

    pub fn initCalibrated(
        sample_rate: u32,
        first_tracker_timestamp: u64,
        first_sample_position: u64,
        second_tracker_timestamp: u64,
        second_sample_position: u64,
    ) !MotionClock {
        const tracker_ticks_per_second = try observedTrackerRate(
            sample_rate,
            first_tracker_timestamp,
            first_sample_position,
            second_tracker_timestamp,
            second_sample_position,
        );
        return init(
            sample_rate,
            tracker_ticks_per_second,
            second_tracker_timestamp,
            second_sample_position,
        );
    }

    pub fn valid(self: *const MotionClock) bool {
        self.validate() catch return false;
        return true;
    }

    pub fn map(
        self: *MotionClock,
        tracker_timestamp: u64,
    ) !u64 {
        try self.validate();
        if (tracker_timestamp < self.tracker_anchor or
            (self.has_mapped_timestamp and
                tracker_timestamp <= self.last_tracker_timestamp))
        {
            return error.InvalidHrtfTrackerTimestamp;
        }

        const tracker_delta = tracker_timestamp - self.tracker_anchor;
        const sample_delta_wide =
            (@as(u128, tracker_delta) * self.sample_rate) /
            self.tracker_ticks_per_second;
        if (sample_delta_wide > std.math.maxInt(u64))
            return error.HrtfMotionSamplePositionOverflow;
        const sample_delta: u64 = @intCast(sample_delta_wide);
        const sample_position = std.math.add(
            u64,
            self.sample_anchor,
            sample_delta,
        ) catch return error.HrtfMotionSamplePositionOverflow;
        if (self.has_mapped_timestamp and
            sample_position <= self.last_sample_position)
        {
            return error.HrtfTrackerTimestampTooDense;
        }

        self.last_tracker_timestamp = tracker_timestamp;
        self.last_sample_position = sample_position;
        self.has_mapped_timestamp = true;
        return sample_position;
    }

    pub fn reanchor(
        self: *MotionClock,
        tracker_anchor: u64,
        sample_anchor: u64,
    ) !void {
        try self.validate();
        if (self.has_mapped_timestamp and
            (tracker_anchor <= self.last_tracker_timestamp or
                sample_anchor <= self.last_sample_position))
        {
            return error.InvalidHrtfTrackerClockAnchor;
        }
        self.tracker_anchor = tracker_anchor;
        self.sample_anchor = sample_anchor;
    }

    fn validate(self: *const MotionClock) !void {
        if (self.sample_rate < 8_000 or self.sample_rate > 384_000 or
            self.tracker_ticks_per_second == 0)
        {
            return error.InvalidHrtfMotionClockState;
        }
        if (!self.has_mapped_timestamp) {
            if (self.last_tracker_timestamp != 0 or
                self.last_sample_position != 0)
            {
                return error.InvalidHrtfMotionClockState;
            }
            return;
        }
        if (self.last_tracker_timestamp < self.tracker_anchor) {
            if (self.last_sample_position >= self.sample_anchor)
                return error.InvalidHrtfMotionClockState;
            return;
        }
        const tracker_delta =
            self.last_tracker_timestamp - self.tracker_anchor;
        const sample_delta_wide =
            (@as(u128, tracker_delta) * self.sample_rate) /
            self.tracker_ticks_per_second;
        if (sample_delta_wide > std.math.maxInt(u64))
            return error.InvalidHrtfMotionClockState;
        const expected = std.math.add(
            u64,
            self.sample_anchor,
            @intCast(sample_delta_wide),
        ) catch return error.InvalidHrtfMotionClockState;
        if (self.last_sample_position != expected)
            return error.InvalidHrtfMotionClockState;
    }
};

pub const MotionClockObservation = struct {
    tracker_timestamp: u64,
    sample_position: u64,
};

/// Robust fixed-window calibration for synchronized clock observations.
pub fn MotionClockCalibrator(
    comptime maximum_observations: usize,
) type {
    if (maximum_observations < 3)
        @compileError("HRTF clock calibration requires three observations");
    if (maximum_observations > 64)
        @compileError("HRTF clock calibration supports at most 64 observations");

    return struct {
        const Self = @This();
        const maximum_pair_count =
            maximum_observations * (maximum_observations - 1) / 2;

        observations: [maximum_observations]MotionClockObservation =
            undefined,
        observation_count: usize = 0,

        pub fn observe(
            self: *Self,
            observation: MotionClockObservation,
        ) !void {
            try self.validate();
            if (self.observation_count != 0) {
                const previous =
                    self.observations[self.observation_count - 1];
                if (observation.tracker_timestamp <=
                    previous.tracker_timestamp or
                    observation.sample_position <= previous.sample_position)
                {
                    return error.InvalidHrtfTrackerClockObservation;
                }
            }
            if (self.observation_count == maximum_observations) {
                std.mem.copyForwards(
                    MotionClockObservation,
                    self.observations[0 .. maximum_observations - 1],
                    self.observations[1..maximum_observations],
                );
                self.observation_count -= 1;
            }
            self.observations[self.observation_count] = observation;
            self.observation_count += 1;
        }

        pub fn valid(self: *const Self) bool {
            self.validate() catch return false;
            return true;
        }

        pub fn count(self: *const Self) !usize {
            try self.validate();
            return self.observation_count;
        }

        pub fn calibrate(
            self: *const Self,
            sample_rate: u32,
            maximum_deviation_ppm: u32,
        ) !MotionClock {
            try self.validate();
            try validateCalibrationPolicy(
                sample_rate,
                maximum_deviation_ppm,
            );
            if (self.observation_count < 3)
                return error.InsufficientHrtfTrackerClockObservations;

            var rates: [maximum_pair_count]u64 = undefined;
            var rate_count: usize = 0;
            for (0..self.observation_count - 1) |first_index| {
                const first = self.observations[first_index];
                for (first_index + 1..self.observation_count) |
                    second_index,
                | {
                    const second = self.observations[second_index];
                    const rate = observedTrackerRate(
                        sample_rate,
                        first.tracker_timestamp,
                        first.sample_position,
                        second.tracker_timestamp,
                        second.sample_position,
                    ) catch continue;
                    rates[rate_count] = rate;
                    rate_count += 1;
                }
            }
            if (rate_count < self.observation_count - 1)
                return error.UnstableHrtfTrackerClockObservations;
            std.mem.sort(
                u64,
                rates[0..rate_count],
                {},
                std.sort.asc(u64),
            );
            const median_rate = rates[rate_count / 2];

            var inlier_interval_count: usize = 0;
            for (1..self.observation_count) |index| {
                const first = self.observations[index - 1];
                const second = self.observations[index];
                const interval_rate = observedTrackerRate(
                    sample_rate,
                    first.tracker_timestamp,
                    first.sample_position,
                    second.tracker_timestamp,
                    second.sample_position,
                ) catch continue;
                if (rateWithinTolerance(
                    interval_rate,
                    median_rate,
                    maximum_deviation_ppm,
                )) inlier_interval_count += 1;
            }
            const interval_count = self.observation_count - 1;
            const required_inliers = (interval_count + 1) / 2;
            const penultimate =
                self.observations[self.observation_count - 2];
            const newest =
                self.observations[self.observation_count - 1];
            const newest_rate = observedTrackerRate(
                sample_rate,
                penultimate.tracker_timestamp,
                penultimate.sample_position,
                newest.tracker_timestamp,
                newest.sample_position,
            ) catch return error.UnstableHrtfTrackerClockObservations;
            if (inlier_interval_count < required_inliers or
                !rateWithinTolerance(
                    newest_rate,
                    median_rate,
                    maximum_deviation_ppm,
                ))
            {
                return error.UnstableHrtfTrackerClockObservations;
            }
            return MotionClock.init(
                sample_rate,
                median_rate,
                newest.tracker_timestamp,
                newest.sample_position,
            );
        }

        pub fn observeAndCalibrate(
            self: *Self,
            observation: MotionClockObservation,
            sample_rate: u32,
            maximum_deviation_ppm: u32,
        ) !?MotionClock {
            try validateCalibrationPolicy(
                sample_rate,
                maximum_deviation_ppm,
            );
            var staged = self.*;
            try staged.observe(observation);
            if (staged.observation_count < 3) {
                self.* = staged;
                return null;
            }
            const clock = try staged.calibrate(
                sample_rate,
                maximum_deviation_ppm,
            );
            self.* = staged;
            return clock;
        }

        pub fn reset(self: *Self) void {
            self.observation_count = 0;
        }

        fn validate(self: *const Self) !void {
            if (self.observation_count > maximum_observations)
                return error.InvalidHrtfMotionClockCalibratorState;
            if (self.observation_count < 2) return;
            for (1..self.observation_count) |index| {
                const previous = self.observations[index - 1];
                const current = self.observations[index];
                if (current.tracker_timestamp <=
                    previous.tracker_timestamp or
                    current.sample_position <= previous.sample_position)
                {
                    return error.InvalidHrtfMotionClockCalibratorState;
                }
            }
        }
    };
}

fn validateCalibrationPolicy(
    sample_rate: u32,
    maximum_deviation_ppm: u32,
) !void {
    if (sample_rate < 8_000 or sample_rate > 384_000)
        return error.InvalidHrtfSampleRate;
    if (maximum_deviation_ppm == 0 or
        maximum_deviation_ppm > 1_000_000)
    {
        return error.InvalidHrtfTrackerClockTolerance;
    }
}

fn observedTrackerRate(
    sample_rate: u32,
    first_tracker_timestamp: u64,
    first_sample_position: u64,
    second_tracker_timestamp: u64,
    second_sample_position: u64,
) !u64 {
    if (second_tracker_timestamp <= first_tracker_timestamp or
        second_sample_position <= first_sample_position)
    {
        return error.InvalidHrtfTrackerClockObservation;
    }
    const tracker_delta =
        second_tracker_timestamp - first_tracker_timestamp;
    const sample_delta =
        second_sample_position - first_sample_position;
    const numerator =
        @as(u128, tracker_delta) * sample_rate + sample_delta / 2;
    const ticks_wide = numerator / sample_delta;
    if (ticks_wide == 0 or ticks_wide > std.math.maxInt(u64))
        return error.InvalidHrtfTrackerClockRate;
    return @intCast(ticks_wide);
}

fn rateWithinTolerance(
    candidate: u64,
    reference: u64,
    maximum_deviation_ppm: u32,
) bool {
    const difference = if (candidate > reference)
        candidate - reference
    else
        reference - candidate;
    return @as(u128, difference) * 1_000_000 <=
        @as(u128, reference) * maximum_deviation_ppm;
}

/// Bounded single-producer, single-consumer transport for tracker updates.
pub fn MotionPointQueue(comptime capacity: usize) type {
    if (capacity == 0)
        @compileError("HRTF motion point queue requires capacity");

    return struct {
        const Self = @This();

        points: [capacity]MotionPoint = @splat(.{}),
        write_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        read_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        dropped_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        last_submitted_sample: u64 = 0,
        has_submitted_sample: bool = false,

        pub fn submit(self: *Self, point: MotionPoint) !bool {
            _ = try self.validateState();
            _ = try directionFromPositions(
                point.source_position,
                point.head_pose,
            );
            if (self.has_submitted_sample and
                point.sample_position <= self.last_submitted_sample)
            {
                return error.InvalidHrtfMotionSchedule;
            }

            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > capacity)
                return error.InvalidHrtfMotionQueueState;
            if (pending_count == capacity) {
                self.recordDrop();
                return false;
            }

            self.points[write % capacity] = point;
            self.last_submitted_sample = point.sample_position;
            self.has_submitted_sample = true;
            self.write_index.store(write +% 1, .release);
            return true;
        }

        pub fn submitTracked(
            self: *Self,
            clock: *MotionClock,
            tracker_timestamp: u64,
            source_position: Position,
            head_pose: HeadPose,
        ) !bool {
            _ = try self.validateState();
            if (!clock.valid())
                return error.InvalidHrtfMotionClockState;
            var staged_clock = clock.*;
            const sample_position =
                try staged_clock.map(tracker_timestamp);
            const accepted = try self.submit(.{
                .sample_position = sample_position,
                .source_position = source_position,
                .head_pose = head_pose,
            });
            if (!accepted) return false;
            clock.* = staged_clock;
            return true;
        }

        pub fn receive(self: *Self) !?MotionPoint {
            const pending_count = try self.validateCursors();
            const read = self.read_index.load(.monotonic);
            if (pending_count == 0) return null;
            const point = self.points[read % capacity];
            _ = directionFromPositions(
                point.source_position,
                point.head_pose,
            ) catch return error.InvalidHrtfMotionQueueState;
            if (pending_count > 1) {
                const next = self.points[(read +% 1) % capacity];
                if (point.sample_position >= next.sample_position)
                    return error.InvalidHrtfMotionQueueState;
            }
            self.read_index.store(read +% 1, .release);
            return point;
        }

        pub fn pending(self: *const Self) !usize {
            return self.validateCursors();
        }

        /// Query complete state only while producer and consumer are stopped.
        pub fn valid(self: *const Self) bool {
            _ = self.validateState() catch return false;
            return true;
        }

        pub fn dropped(self: *const Self) usize {
            return self.dropped_count.load(.acquire);
        }

        /// Reset is only valid while both participating threads are stopped.
        pub fn reset(self: *Self) void {
            @memset(&self.points, .{});
            self.write_index.store(0, .release);
            self.read_index.store(0, .release);
            self.dropped_count.store(0, .release);
            self.last_submitted_sample = 0;
            self.has_submitted_sample = false;
        }

        fn recordDrop(self: *Self) void {
            var current = self.dropped_count.load(.monotonic);
            while (current != std.math.maxInt(usize)) {
                if (self.dropped_count.cmpxchgWeak(
                    current,
                    current + 1,
                    .monotonic,
                    .monotonic,
                )) |observed| {
                    current = observed;
                } else return;
            }
        }

        fn validateState(self: *const Self) !usize {
            const read = self.read_index.load(.acquire);
            const write = self.write_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > capacity)
                return error.InvalidHrtfMotionQueueState;
            if (!self.has_submitted_sample) {
                if (self.last_submitted_sample != 0 or
                    pending_count != 0)
                {
                    return error.InvalidHrtfMotionQueueState;
                }
                return pending_count;
            }
            var previous_sample: ?u64 = null;
            for (0..pending_count) |offset| {
                const point = self.points[(read +% offset) % capacity];
                _ = directionFromPositions(
                    point.source_position,
                    point.head_pose,
                ) catch return error.InvalidHrtfMotionQueueState;
                if (previous_sample) |previous| {
                    if (point.sample_position <= previous)
                        return error.InvalidHrtfMotionQueueState;
                }
                previous_sample = point.sample_position;
            }
            if (previous_sample) |latest| {
                if (latest != self.last_submitted_sample)
                    return error.InvalidHrtfMotionQueueState;
            }
            return pending_count;
        }

        fn validateCursors(self: *const Self) !usize {
            const read = self.read_index.load(.acquire);
            const write = self.write_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > capacity)
                return error.InvalidHrtfMotionQueueState;
            return pending_count;
        }
    };
}

pub const Interpolation = enum {
    nearest,
    inverse_distance,
    delay_aligned,
    spectral,
};

pub const RoomPath = struct {
    direction: Direction,
    distance_metres: f64 = 1.0,
    gain: f64 = 1.0,
    additional_delay_samples: f64 = 0.0,
};

pub const maximum_first_order_room_paths: usize = 7;
pub const maximum_second_order_room_paths: usize = 25;
pub const maximum_supported_room_reflection_order: usize = 8;

pub fn roomPathCapacityForOrder(comptime reflection_order: usize) usize {
    if (reflection_order > maximum_supported_room_reflection_order) {
        @compileError("HRTF room reflection order exceeds the supported limit");
    }
    var path_capacity: usize = 1;
    for (1..reflection_order + 1) |order| {
        path_capacity += 4 * order * order + 2;
    }
    return path_capacity;
}

pub const RoomSurfaceAbsorption = struct {
    minimum_x: f64 = 1.0,
    maximum_x: f64 = 1.0,
    minimum_y: f64 = 1.0,
    maximum_y: f64 = 1.0,
    minimum_z: f64 = 1.0,
    maximum_z: f64 = 1.0,

    fn values(self: RoomSurfaceAbsorption) [6]f64 {
        return .{
            self.minimum_x,
            self.maximum_x,
            self.minimum_y,
            self.maximum_y,
            self.minimum_z,
            self.maximum_z,
        };
    }
};

pub const ShoeboxRoom = struct {
    minimum: Position,
    maximum: Position,
    absorption: RoomSurfaceAbsorption = .{},
};

pub const FirstOrderRoomPathPlan = struct {
    path_storage: [maximum_first_order_room_paths]RoomPath = @splat(.{
        .direction = .{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        },
    }),
    path_count: usize = 0,
    declared_path_count: usize = 0,

    pub fn init(
        room: ShoeboxRoom,
        sample_rate: u32,
        speed_of_sound_meters_per_second: f64,
        source_position: Position,
        head_pose: HeadPose,
    ) !FirstOrderRoomPathPlan {
        const origin = try roomPlanOrigin(
            room,
            sample_rate,
            speed_of_sound_meters_per_second,
            source_position,
            head_pose,
        );
        var result = FirstOrderRoomPathPlan{};
        result.path_storage[0] = origin.direct_path;
        result.path_count = 1;

        const images = [6]Position{
            .{
                .x = 2.0 * room.minimum.x - source_position.x,
                .y = source_position.y,
                .z = source_position.z,
            },
            .{
                .x = 2.0 * room.maximum.x - source_position.x,
                .y = source_position.y,
                .z = source_position.z,
            },
            .{
                .x = source_position.x,
                .y = 2.0 * room.minimum.y - source_position.y,
                .z = source_position.z,
            },
            .{
                .x = source_position.x,
                .y = 2.0 * room.maximum.y - source_position.y,
                .z = source_position.z,
            },
            .{
                .x = source_position.x,
                .y = source_position.y,
                .z = 2.0 * room.minimum.z - source_position.z,
            },
            .{
                .x = source_position.x,
                .y = source_position.y,
                .z = 2.0 * room.maximum.z - source_position.z,
            },
        };
        const absorptions = room.absorption.values();
        for (images, absorptions) |image, absorption| {
            const reflection = @sqrt(1.0 - absorption);
            if (reflection == 0.0) continue;
            result.path_storage[result.path_count] = try roomPathFromImage(
                image,
                head_pose,
                origin.direct_distance,
                reflection,
                sample_rate,
                speed_of_sound_meters_per_second,
            );
            result.path_count += 1;
        }
        result.declared_path_count = result.path_count;
        if (!result.valid()) return error.InvalidHrtfRoomPathPlanState;
        return result;
    }

    pub fn items(self: *const FirstOrderRoomPathPlan) ![]const RoomPath {
        if (!self.valid()) return error.InvalidHrtfRoomPathPlanState;
        return self.path_storage[0..self.path_count];
    }

    pub fn valid(self: *const FirstOrderRoomPathPlan) bool {
        if (self.path_count != self.declared_path_count) return false;
        return roomPathPlanValid(
            &self.path_storage,
            self.path_count,
            maximum_first_order_room_paths,
        );
    }
};

pub const SecondOrderRoomPathPlan = struct {
    path_storage: [maximum_second_order_room_paths]RoomPath = @splat(.{
        .direction = .{
            .azimuth_degrees = 0.0,
            .elevation_degrees = 0.0,
        },
    }),
    path_count: usize = 0,
    declared_path_count: usize = 0,

    pub fn init(
        room: ShoeboxRoom,
        sample_rate: u32,
        speed_of_sound_meters_per_second: f64,
        source_position: Position,
        head_pose: HeadPose,
    ) !SecondOrderRoomPathPlan {
        const first_order = try FirstOrderRoomPathPlan.init(
            room,
            sample_rate,
            speed_of_sound_meters_per_second,
            source_position,
            head_pose,
        );
        const first_order_paths = try first_order.items();
        const direct_distance = try distanceBetweenPositions(
            source_position,
            head_pose.position,
        );
        var result = SecondOrderRoomPathPlan{};
        @memcpy(
            result.path_storage[0..first_order_paths.len],
            first_order_paths,
        );
        result.path_count = first_order_paths.len;

        for (second_order_image_indices) |indices| {
            const reflection = imageReflection(room, indices);
            if (reflection == 0.0) continue;
            const image = imagePosition(room, source_position, indices);
            const path = try roomPathFromImage(
                image,
                head_pose,
                direct_distance,
                reflection,
                sample_rate,
                speed_of_sound_meters_per_second,
            );
            result.path_storage[result.path_count] = path;
            result.path_count += 1;
        }
        result.declared_path_count = result.path_count;
        if (!result.valid()) return error.InvalidHrtfRoomPathPlanState;
        return result;
    }

    pub fn items(self: *const SecondOrderRoomPathPlan) ![]const RoomPath {
        if (!self.valid()) return error.InvalidHrtfRoomPathPlanState;
        return self.path_storage[0..self.path_count];
    }

    pub fn valid(self: *const SecondOrderRoomPathPlan) bool {
        if (self.path_count != self.declared_path_count) return false;
        return roomPathPlanValid(
            &self.path_storage,
            self.path_count,
            maximum_second_order_room_paths,
        );
    }
};

pub fn ImageSourceRoomPathPlan(comptime reflection_order: usize) type {
    const path_capacity = roomPathCapacityForOrder(reflection_order);
    return struct {
        const Self = @This();

        pub const maximum_reflection_order = reflection_order;
        pub const maximum_path_count = path_capacity;

        path_storage: [path_capacity]RoomPath = @splat(.{
            .direction = .{
                .azimuth_degrees = 0.0,
                .elevation_degrees = 0.0,
            },
        }),
        image_index_storage: [path_capacity][3]i16 =
            @splat(.{ 0, 0, 0 }),
        path_count: usize = 0,
        declared_path_count: usize = 0,

        pub fn init(
            room: ShoeboxRoom,
            sample_rate: u32,
            speed_of_sound_meters_per_second: f64,
            source_position: Position,
            head_pose: HeadPose,
        ) !Self {
            const origin = try roomPlanOrigin(
                room,
                sample_rate,
                speed_of_sound_meters_per_second,
                source_position,
                head_pose,
            );
            var result = Self{};
            result.path_storage[0] = origin.direct_path;
            result.path_count = 1;
            if (reflection_order == 0) {
                result.declared_path_count = result.path_count;
                if (!result.valid())
                    return error.InvalidHrtfRoomPathPlanState;
                return result;
            }

            const coordinate_count = 2 * reflection_order + 1;
            const signed_order: i16 = @intCast(reflection_order);
            for (0..coordinate_count) |x_offset| {
                const x = @as(i16, @intCast(x_offset)) - signed_order;
                for (0..coordinate_count) |y_offset| {
                    const y = @as(i16, @intCast(y_offset)) - signed_order;
                    for (0..coordinate_count) |z_offset| {
                        const z = @as(i16, @intCast(z_offset)) - signed_order;
                        const order = imageIndexMagnitude(x) +
                            imageIndexMagnitude(y) +
                            imageIndexMagnitude(z);
                        if (order == 0 or order > reflection_order) continue;
                        const indices = [3]i16{ x, y, z };
                        const reflection = imageReflection(room, indices);
                        if (reflection == 0.0) continue;
                        const image = imagePosition(
                            room,
                            source_position,
                            indices,
                        );
                        result.path_storage[result.path_count] =
                            try roomPathFromImage(
                                image,
                                head_pose,
                                origin.direct_distance,
                                reflection,
                                sample_rate,
                                speed_of_sound_meters_per_second,
                            );
                        result.image_index_storage[result.path_count] =
                            indices;
                        result.path_count += 1;
                    }
                }
            }
            result.declared_path_count = result.path_count;
            if (!result.valid()) return error.InvalidHrtfRoomPathPlanState;
            return result;
        }

        pub fn items(self: *const Self) ![]const RoomPath {
            if (!self.valid()) return error.InvalidHrtfRoomPathPlanState;
            return self.path_storage[0..self.path_count];
        }

        pub fn imageIndices(self: *const Self) ![]const [3]i16 {
            if (!self.valid()) return error.InvalidHrtfRoomPathPlanState;
            return self.image_index_storage[0..self.path_count];
        }

        pub fn valid(self: *const Self) bool {
            if (self.path_count != self.declared_path_count) return false;
            if (!roomPathPlanValid(
                &self.path_storage,
                self.path_count,
                path_capacity,
            )) return false;
            if (!std.meta.eql(
                self.image_index_storage[0],
                [3]i16{ 0, 0, 0 },
            ))
                return false;
            for (self.image_index_storage[1..self.path_count]) |indices| {
                const order = imageIndexMagnitude(indices[0]) +
                    imageIndexMagnitude(indices[1]) +
                    imageIndexMagnitude(indices[2]);
                if (order == 0 or order > reflection_order) return false;
            }
            return true;
        }
    };
}

pub const RoomSurfaceImpulseResponseInput = struct {
    minimum_x: []const f32,
    maximum_x: []const f32,
    minimum_y: []const f32,
    maximum_y: []const f32,
    minimum_z: []const f32,
    maximum_z: []const f32,
};

pub fn RoomSurfaceImpulseResponses(comptime maximum_frames: usize) type {
    if (maximum_frames == 0)
        @compileError("HRTF room surface responses require frame capacity");

    return struct {
        const Self = @This();

        response_storage: [6][maximum_frames]f32 =
            @splat(@splat(0.0)),
        frame_counts: [6]usize = @splat(0),
        sample_rate: u32 = 0,
        declared_frame_counts: [6]usize = @splat(0),
        declared_sample_rate: u32 = 0,

        pub fn init(
            sample_rate: u32,
            input: RoomSurfaceImpulseResponseInput,
        ) !Self {
            if (sample_rate < 8_000 or sample_rate > 384_000)
                return error.InvalidHrtfSampleRate;
            const responses = [6][]const f32{
                input.minimum_x,
                input.maximum_x,
                input.minimum_y,
                input.maximum_y,
                input.minimum_z,
                input.maximum_z,
            };
            var result = Self{};
            result.sample_rate = sample_rate;
            result.declared_sample_rate = sample_rate;
            for (responses, 0..) |surface_response, surface| {
                if (surface_response.len == 0 or
                    surface_response.len > maximum_frames)
                    return error.InvalidHrtfRoomSurfaceResponse;
                for (surface_response) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.InvalidHrtfRoomSurfaceResponse;
                }
                @memcpy(
                    result.response_storage[surface][0..surface_response.len],
                    surface_response,
                );
                result.frame_counts[surface] = surface_response.len;
                result.declared_frame_counts[surface] =
                    surface_response.len;
            }
            if (!result.valid())
                return error.InvalidHrtfRoomSurfaceResponseState;
            return result;
        }

        pub fn valid(self: *const Self) bool {
            if (self.sample_rate < 8_000 or
                self.sample_rate > 384_000 or
                self.sample_rate != self.declared_sample_rate)
                return false;
            for (self.frame_counts, 0..) |frame_count, surface| {
                if (frame_count == 0 or
                    frame_count > maximum_frames or
                    frame_count != self.declared_frame_counts[surface])
                    return false;
                for (self.response_storage[surface][0..frame_count]) |sample| {
                    if (!std.math.isFinite(sample)) return false;
                }
            }
            return true;
        }

        fn response(self: *const Self, surface: usize) []const f32 {
            return self.response_storage[surface][0..self.frame_counts[surface]];
        }
    };
}

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
        declared_measurement_count: usize,
        declared_frame_count: usize,
        declared_response_frame_count: usize,
        directions: [maximum_measurements]Direction =
            @splat(.{
                .azimuth_degrees = 0.0,
                .elevation_degrees = 0.0,
            }),
        distances_metres: [maximum_measurements]f64 = @splat(1.0),
        delays_samples: [maximum_measurements][channel_count]f64 =
            @splat(@splat(0.0)),
        responses: [maximum_measurements][maximum_frames][channel_count]f32 =
            @splat(@splat(@splat(0.0))),

        pub fn init(
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
        ) !Self {
            var result: Self = undefined;
            try initInto(
                &result,
                sample_rate,
                directions,
                interleaved_responses,
            );
            return result;
        }

        pub fn initInto(
            destination: *Self,
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
        ) !void {
            return initWithDelaysInto(
                destination,
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
            var result: Self = undefined;
            try initWithDelaysInto(
                &result,
                sample_rate,
                directions,
                interleaved_responses,
                delays_samples,
            );
            return result;
        }

        pub fn initWithDelaysInto(
            destination: *Self,
            sample_rate: u32,
            directions: []const Direction,
            interleaved_responses: []const f32,
            delays_samples: []const f64,
        ) !void {
            return initWithDistancesAndDelaysInto(
                destination,
                sample_rate,
                directions,
                &.{},
                interleaved_responses,
                delays_samples,
            );
        }

        pub fn initWithDistances(
            sample_rate: u32,
            directions: []const Direction,
            distances_metres: []const f64,
            interleaved_responses: []const f32,
        ) !Self {
            var result: Self = undefined;
            try initWithDistancesInto(
                &result,
                sample_rate,
                directions,
                distances_metres,
                interleaved_responses,
            );
            return result;
        }

        pub fn initWithDistancesInto(
            destination: *Self,
            sample_rate: u32,
            directions: []const Direction,
            distances_metres: []const f64,
            interleaved_responses: []const f32,
        ) !void {
            return initWithDistancesAndDelaysInto(
                destination,
                sample_rate,
                directions,
                distances_metres,
                interleaved_responses,
                &.{},
            );
        }

        pub fn initWithDistancesAndDelays(
            sample_rate: u32,
            directions: []const Direction,
            distances_metres: []const f64,
            interleaved_responses: []const f32,
            delays_samples: []const f64,
        ) !Self {
            var result: Self = undefined;
            try initWithDistancesAndDelaysInto(
                &result,
                sample_rate,
                directions,
                distances_metres,
                interleaved_responses,
                delays_samples,
            );
            return result;
        }

        pub fn initWithDistancesAndDelaysInto(
            destination: *Self,
            sample_rate: u32,
            directions: []const Direction,
            distances_metres: []const f64,
            interleaved_responses: []const f32,
            delays_samples: []const f64,
        ) !void {
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
            if (distances_metres.len != 0 and
                distances_metres.len != directions.len)
                return error.InvalidHrtfDistanceShape;
            const destination_bytes = std.mem.asBytes(destination);
            if (memorySlicesOverlap(
                Direction,
                directions,
                u8,
                destination_bytes,
            ) or memorySlicesOverlap(
                f32,
                interleaved_responses,
                u8,
                destination_bytes,
            ) or memorySlicesOverlap(
                f64,
                distances_metres,
                u8,
                destination_bytes,
            ) or memorySlicesOverlap(
                f64,
                delays_samples,
                u8,
                destination_bytes,
            )) return error.OverlappingHrtfDatabaseStorage;

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

            for (directions, 0..) |direction, measurement_index| {
                try validateDirection(direction);
                const position = MeasurementPosition{
                    .direction = direction,
                    .distance_metres = distanceValue(
                        distances_metres,
                        measurement_index,
                    ),
                };
                try validateMeasurementPosition(position);
                for (0..measurement_index) |previous_index| {
                    const previous = MeasurementPosition{
                        .direction = directions[previous_index],
                        .distance_metres = distanceValue(
                            distances_metres,
                            previous_index,
                        ),
                    };
                    if (sameMeasurementPosition(position, previous))
                        return error.DuplicateHrtfDirection;
                }
                var has_energy = false;
                for (0..response_frame_count) |frame_index| {
                    for (0..channel_count) |channel_index| {
                        const source_index =
                            (measurement_index *
                                response_frame_count +
                                frame_index) *
                            channel_count +
                            channel_index;
                        const sample = interleaved_responses[source_index];
                        if (!std.math.isFinite(sample))
                            return error.NonFiniteHrtfSample;
                        if (sample != 0.0) has_energy = true;
                    }
                }
                if (!has_energy) return error.EmptyHrtfResponse;
            }

            destination.* = Self{
                .sample_rate = sample_rate,
                .measurement_count = directions.len,
                .frame_count = frame_count,
                .response_frame_count = response_frame_count,
                .declared_measurement_count = directions.len,
                .declared_frame_count = frame_count,
                .declared_response_frame_count = response_frame_count,
            };
            for (directions, 0..) |direction, measurement_index| {
                destination.directions[measurement_index] = direction;
                destination.distances_metres[measurement_index] =
                    distanceValue(distances_metres, measurement_index);
                for (0..channel_count) |channel_index| {
                    destination.delays_samples[measurement_index][channel_index] =
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
                        destination.responses[measurement_index][frame_index][channel_index] = sample;
                    }
                }
            }
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
            return self.interpolateSelected(
                selected,
                method,
                destination,
            );
        }

        pub fn interpolateAt(
            self: *const Self,
            position: MeasurementPosition,
            method: Interpolation,
            destination: []f32,
        ) !void {
            if (!self.valid()) return error.InvalidHrtfDatabase;
            try validateMeasurementPosition(position);
            if (destination.len != self.frame_count * channel_count)
                return error.InvalidHrtfDestinationShape;
            return self.interpolateSelected(
                self.spatialNeighbors(position),
                method,
                destination,
            );
        }

        fn interpolateSelected(
            self: *const Self,
            selected: Neighbors,
            method: Interpolation,
            destination: []f32,
        ) !void {
            if (memorySlicesOverlap(
                f32,
                destination,
                u8,
                std.mem.asBytes(&self.responses),
            )) return error.OverlappingHrtfInterpolationStorage;

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
                self.measurement_count != self.declared_measurement_count or
                self.frame_count == 0 or
                self.frame_count > maximum_frames or
                self.frame_count != self.declared_frame_count or
                self.response_frame_count == 0 or
                self.response_frame_count > self.frame_count or
                self.response_frame_count !=
                    self.declared_response_frame_count)
            {
                return false;
            }
            var maximum_delay: f64 = 0.0;
            for (
                self.directions[0..self.measurement_count],
                0..,
            ) |direction, measurement_index| {
                const position = MeasurementPosition{
                    .direction = direction,
                    .distance_metres = self.distances_metres[measurement_index],
                };
                validateMeasurementPosition(position) catch return false;
                for (0..measurement_index) |previous_index| {
                    const previous = MeasurementPosition{
                        .direction = self.directions[previous_index],
                        .distance_metres = self.distances_metres[previous_index],
                    };
                    if (sameMeasurementPosition(position, previous))
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

        fn spatialNeighbors(
            self: *const Self,
            position: MeasurementPosition,
        ) Neighbors {
            const distance = if (self.hasVariableDistances())
                position.distance_metres
            else
                self.distances_metres[0];
            const target = measurementVector(.{
                .direction = position.direction,
                .distance_metres = distance,
            });
            var result = Neighbors{
                .count = @min(self.measurement_count, 3),
                .indices = @splat(0),
                .distances = @splat(std.math.inf(f64)),
            };
            for (0..self.measurement_count) |candidate_index| {
                const candidate = measurementVector(.{
                    .direction = self.directions[candidate_index],
                    .distance_metres = self.distances_metres[candidate_index],
                });
                const distance_squared = vectorDistanceSquared(
                    target,
                    candidate,
                );
                var insertion_index: usize = 0;
                while (insertion_index < result.count and
                    distance_squared >= result.distances[insertion_index])
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
                result.distances[insertion_index] = distance_squared;
            }
            return result;
        }

        fn hasVariableDistances(self: *const Self) bool {
            const first = self.distances_metres[0];
            for (self.distances_metres[1..self.measurement_count]) |value| {
                if (value != first) return true;
            }
            return false;
        }

        fn sampleResponse(
            self: *const Self,
            measurement_index: usize,
            channel_index: usize,
            sample_position: f64,
        ) f64 {
            if (sample_position <= -1.0 or
                sample_position >=
                    @as(f64, @floatFromInt(self.response_frame_count)))
            {
                return 0.0;
            }
            if (sample_position < 0.0) {
                return @as(
                    f64,
                    self.responses[measurement_index][0][channel_index],
                ) *
                    (sample_position + 1.0);
            }
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
                    const value: f64 = if (sample_position <= -1.0 or
                        sample_position >=
                            @as(f64, @floatFromInt(count)))
                        0.0
                    else if (sample_position < 0.0)
                        local_response[0] * (sample_position + 1.0)
                    else value: {
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
                        break :value first_value +
                            (second_value - first_value) * fraction;
                    };
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

pub fn RoomResponseComposer(
    comptime maximum_frames: usize,
    comptime maximum_paths: usize,
) type {
    if (maximum_frames == 0)
        @compileError("HRTF room response requires frame capacity");
    if (maximum_paths == 0)
        @compileError("HRTF room response requires path capacity");

    return struct {
        const Self = @This();

        path_response: [maximum_frames * 2]f32 = @splat(0.0),
        accumulation: [maximum_frames * 2]f64 = @splat(0.0),

        pub fn compose(
            self: *Self,
            database: anytype,
            paths: []const RoomPath,
            interpolation: Interpolation,
            destination: []f32,
        ) !usize {
            if (!database.*.valid()) return error.InvalidHrtfDatabase;
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            if (paths.len == 0 or paths.len > maximum_paths)
                return error.InvalidHrtfRoomPathCount;

            var maximum_delay: f64 = 0.0;
            var staged_paths: [maximum_paths]RoomPath = undefined;
            for (paths, 0..) |path, index| {
                try validateMeasurementPosition(.{
                    .direction = path.direction,
                    .distance_metres = path.distance_metres,
                });
                if (!std.math.isFinite(path.gain))
                    return error.InvalidHrtfRoomPathGain;
                if (!std.math.isFinite(path.additional_delay_samples) or
                    path.additional_delay_samples < 0.0 or
                    path.additional_delay_samples >
                        @as(f64, @floatFromInt(maximum_frames)))
                {
                    return error.InvalidHrtfRoomPathDelay;
                }
                maximum_delay = @max(
                    maximum_delay,
                    path.additional_delay_samples,
                );
                staged_paths[index] = path;
            }
            const delay_frames: usize =
                @intFromFloat(@ceil(maximum_delay));
            const frame_count = std.math.add(
                usize,
                database.frame_count,
                delay_frames,
            ) catch return error.HrtfFrameCapacityExceeded;
            if (frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            const sample_count = std.math.mul(
                usize,
                frame_count,
                2,
            ) catch return error.HrtfFrameCapacityExceeded;
            if (destination.len < sample_count)
                return error.InvalidHrtfDestinationShape;
            const used_destination = destination[0..sample_count];
            if (memorySlicesOverlap(
                f32,
                used_destination,
                f32,
                &self.path_response,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                f64,
                &self.accumulation,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                u8,
                std.mem.asBytes(&database.responses),
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                RoomPath,
                paths,
            )) return error.OverlappingHrtfRoomResponseStorage;

            @memset(self.accumulation[0..sample_count], 0.0);
            const database_samples = database.frame_count * 2;
            for (staged_paths[0..paths.len]) |path| {
                try database.interpolateAt(
                    .{
                        .direction = path.direction,
                        .distance_metres = path.distance_metres,
                    },
                    interpolation,
                    self.path_response[0..database_samples],
                );
                for (0..frame_count) |frame_index| {
                    const source_position =
                        @as(f64, @floatFromInt(frame_index)) -
                        path.additional_delay_samples;
                    for (0..2) |channel_index| {
                        const sample = sampleInterleavedResponse(
                            self.path_response[0..database_samples],
                            database.frame_count,
                            channel_index,
                            source_position,
                        );
                        const index = frame_index * 2 + channel_index;
                        const value = self.accumulation[index] +
                            path.gain * sample;
                        if (!std.math.isFinite(value))
                            return error.InvalidHrtfRoomResponse;
                        self.accumulation[index] = value;
                    }
                }
            }

            for (self.accumulation[0..sample_count], 0..) |value, index| {
                if (value < -std.math.floatMax(f32) or
                    value > std.math.floatMax(f32))
                {
                    return error.InvalidHrtfRoomResponse;
                }
                self.path_response[index] = @floatCast(value);
            }
            @memcpy(destination[0..sample_count], self.path_response[0..sample_count]);
            return frame_count;
        }
    };
}

pub fn FrequencyDependentRoomResponseComposer(
    comptime maximum_frames: usize,
    comptime reflection_order: usize,
    comptime maximum_surface_frames: usize,
) type {
    if (maximum_frames == 0)
        @compileError("HRTF room response requires frame capacity");
    if (maximum_surface_frames == 0)
        @compileError("HRTF room surface responses require frame capacity");
    const path_capacity = roomPathCapacityForOrder(reflection_order);
    const maximum_filter_frames =
        1 + reflection_order * (maximum_surface_frames - 1);
    const Plan = ImageSourceRoomPathPlan(reflection_order);
    const Materials = RoomSurfaceImpulseResponses(maximum_surface_frames);

    return struct {
        const Self = @This();

        pub const maximum_path_count = path_capacity;
        pub const maximum_material_response_frames = maximum_filter_frames;

        path_response: [maximum_frames * 2]f32 = @splat(0.0),
        accumulation: [maximum_frames * 2]f64 = @splat(0.0),
        filter_first: [maximum_filter_frames]f64 = @splat(0.0),
        filter_second: [maximum_filter_frames]f64 = @splat(0.0),

        pub fn compose(
            self: *Self,
            database: anytype,
            plan: *const Plan,
            materials: *const Materials,
            interpolation: Interpolation,
            destination: []f32,
        ) !usize {
            if (!database.*.valid()) return error.InvalidHrtfDatabase;
            if (!materials.valid())
                return error.InvalidHrtfRoomSurfaceResponseState;
            if (materials.sample_rate != database.sample_rate)
                return error.HrtfRoomSurfaceSampleRateMismatch;
            const paths = try plan.items();
            const image_indices = try plan.imageIndices();
            if (paths.len != image_indices.len or paths.len > path_capacity)
                return error.InvalidHrtfRoomPathPlanState;
            const material_samples = @as(
                [*]const f32,
                @ptrCast(&materials.response_storage),
            )[0 .. 6 * maximum_surface_frames];
            if (memorySlicesOverlap(
                f32,
                material_samples,
                f32,
                &self.path_response,
            ) or memorySlicesOverlap(
                f32,
                material_samples,
                f64,
                &self.accumulation,
            ) or memorySlicesOverlap(
                f32,
                material_samples,
                f64,
                &self.filter_first,
            ) or memorySlicesOverlap(
                f32,
                material_samples,
                f64,
                &self.filter_second,
            )) return error.OverlappingHrtfRoomResponseStorage;

            var frame_count: usize = 0;
            for (paths, image_indices) |path, indices| {
                const filter_frames = try materialResponseFrameCount(
                    reflection_order,
                    materials,
                    indices,
                );
                const delay_frames: usize =
                    @intFromFloat(@ceil(path.additional_delay_samples));
                const path_frames = std.math.add(
                    usize,
                    database.frame_count,
                    filter_frames - 1,
                ) catch return error.HrtfFrameCapacityExceeded;
                const delayed_frames = std.math.add(
                    usize,
                    path_frames,
                    delay_frames,
                ) catch return error.HrtfFrameCapacityExceeded;
                frame_count = @max(frame_count, delayed_frames);
            }
            if (frame_count == 0 or frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            const sample_count = std.math.mul(
                usize,
                frame_count,
                2,
            ) catch return error.HrtfFrameCapacityExceeded;
            if (destination.len < sample_count)
                return error.InvalidHrtfDestinationShape;
            const used_destination = destination[0..sample_count];
            if (memorySlicesOverlap(
                f32,
                used_destination,
                f32,
                &self.path_response,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                f64,
                &self.accumulation,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                f64,
                &self.filter_first,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                f64,
                &self.filter_second,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                f32,
                material_samples,
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                u8,
                std.mem.asBytes(plan),
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                u8,
                std.mem.asBytes(materials),
            ) or memorySlicesOverlap(
                f32,
                used_destination,
                u8,
                std.mem.asBytes(&database.responses),
            )) return error.OverlappingHrtfRoomResponseStorage;

            @memset(self.accumulation[0..sample_count], 0.0);
            const database_samples = database.frame_count * 2;
            for (paths, image_indices) |path, indices| {
                try database.interpolateAt(
                    .{
                        .direction = path.direction,
                        .distance_metres = path.distance_metres,
                    },
                    interpolation,
                    self.path_response[0..database_samples],
                );
                const filter = try self.buildMaterialResponse(
                    materials,
                    indices,
                );
                for (0..frame_count) |frame_index| {
                    for (0..2) |channel_index| {
                        var filtered: f64 = 0.0;
                        for (filter, 0..) |coefficient, tap| {
                            const source_position =
                                @as(f64, @floatFromInt(frame_index)) -
                                path.additional_delay_samples -
                                @as(f64, @floatFromInt(tap));
                            filtered += coefficient *
                                sampleInterleavedResponse(
                                    self.path_response[0..database_samples],
                                    database.frame_count,
                                    channel_index,
                                    source_position,
                                );
                        }
                        const index = frame_index * 2 + channel_index;
                        const value = self.accumulation[index] +
                            path.gain * filtered;
                        if (!std.math.isFinite(value))
                            return error.InvalidHrtfRoomResponse;
                        self.accumulation[index] = value;
                    }
                }
            }

            for (self.accumulation[0..sample_count], 0..) |value, index| {
                if (value < -std.math.floatMax(f32) or
                    value > std.math.floatMax(f32))
                {
                    return error.InvalidHrtfRoomResponse;
                }
                self.path_response[index] = @floatCast(value);
            }
            @memcpy(used_destination, self.path_response[0..sample_count]);
            return frame_count;
        }

        fn buildMaterialResponse(
            self: *Self,
            materials: *const Materials,
            indices: [3]i16,
        ) ![]const f64 {
            @memset(&self.filter_first, 0.0);
            self.filter_first[0] = 1.0;
            var frame_count: usize = 1;
            var first_is_current = true;
            for (0..3) |axis| {
                const reflection_count = imageIndexMagnitude(indices[axis]);
                for (0..reflection_count) |reflection_index| {
                    const surface = imageSurfaceIndex(
                        axis,
                        indices[axis],
                        reflection_index,
                    );
                    const response = materials.response(surface);
                    const next_count = frame_count + response.len - 1;
                    const source = if (first_is_current)
                        self.filter_first[0..frame_count]
                    else
                        self.filter_second[0..frame_count];
                    const destination_filter = if (first_is_current)
                        self.filter_second[0..next_count]
                    else
                        self.filter_first[0..next_count];
                    @memset(destination_filter, 0.0);
                    for (source, 0..) |source_sample, source_index| {
                        for (response, 0..) |coefficient, response_index| {
                            const index = source_index + response_index;
                            const value = destination_filter[index] +
                                source_sample * coefficient;
                            if (!std.math.isFinite(value))
                                return error.InvalidHrtfRoomSurfaceResponse;
                            destination_filter[index] = value;
                        }
                    }
                    frame_count = next_count;
                    first_is_current = !first_is_current;
                }
            }
            return if (first_is_current)
                self.filter_first[0..frame_count]
            else
                self.filter_second[0..frame_count];
        }
    };
}

fn materialResponseFrameCount(
    comptime reflection_order: usize,
    materials: anytype,
    indices: [3]i16,
) !usize {
    const order = imageIndexMagnitude(indices[0]) +
        imageIndexMagnitude(indices[1]) +
        imageIndexMagnitude(indices[2]);
    if (order > reflection_order)
        return error.InvalidHrtfRoomPathPlanState;
    var frame_count: usize = 1;
    for (0..3) |axis| {
        const reflection_count = imageIndexMagnitude(indices[axis]);
        for (0..reflection_count) |reflection_index| {
            const surface = imageSurfaceIndex(
                axis,
                indices[axis],
                reflection_index,
            );
            frame_count += materials.frame_counts[surface] - 1;
        }
    }
    return frame_count;
}

fn sampleInterleavedResponse(
    samples: []const f32,
    frame_count: usize,
    channel_index: usize,
    sample_position: f64,
) f64 {
    if (sample_position <= -1.0 or
        sample_position >= @as(f64, @floatFromInt(frame_count)))
    {
        return 0.0;
    }
    if (sample_position < 0.0) {
        return @as(f64, samples[channel_index]) *
            (sample_position + 1.0);
    }
    const first: usize = @intFromFloat(@floor(sample_position));
    const fraction = sample_position - @as(f64, @floatFromInt(first));
    const first_value: f64 = samples[first * 2 + channel_index];
    if (fraction == 0.0) return first_value;
    const second_value: f64 = if (first + 1 < frame_count)
        samples[(first + 1) * 2 + channel_index]
    else
        0.0;
    return first_value + (second_value - first_value) * fraction;
}

fn memorySlicesOverlap(
    comptime First: type,
    first: []const First,
    comptime Second: type,
    second: []const Second,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_bytes = std.math.mul(usize, first.len, @sizeOf(First)) catch
        return true;
    const second_bytes = std.math.mul(usize, second.len, @sizeOf(Second)) catch
        return true;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_end = std.math.add(usize, first_start, first_bytes) catch
        return true;
    const second_end = std.math.add(usize, second_start, second_bytes) catch
        return true;
    return first_start < second_end and second_start < first_end;
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

fn distanceValue(
    distances_metres: []const f64,
    measurement_index: usize,
) f64 {
    if (distances_metres.len == 0) return 1.0;
    return distances_metres[measurement_index];
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

            try self.prepareInterleavedResponse(
                database.sample_rate,
                samples,
                generation,
            );
        }

        pub fn prepareAt(
            self: *Self,
            database: anytype,
            position: MeasurementPosition,
            interpolation: Interpolation,
            generation: u64,
        ) !void {
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            const samples = self.prepared_response[0 .. database.frame_count * 2];
            try database.interpolateAt(
                position,
                interpolation,
                samples,
            );
            try self.prepareInterleavedResponse(
                database.sample_rate,
                samples,
                generation,
            );
        }

        pub fn prepareInterleavedResponse(
            self: *Self,
            sample_rate: u32,
            response: []const f32,
            generation: u64,
        ) !void {
            if (sample_rate < 8_000 or sample_rate > 384_000)
                return error.InvalidHrtfSampleRate;
            if (response.len == 0 or response.len % 2 != 0)
                return error.InvalidHrtfResponseShape;
            const frame_count = response.len / 2;
            if (frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;

            var began = false;
            errdefer {
                if (began) _ = self.convolver.cancel(generation);
            }
            try self.convolver.begin(.{
                .generation = generation,
                .sample_rate = sample_rate,
                .channels = 2,
                .frames = frame_count,
            });
            began = true;
            try self.convolver.write(generation, 0, response);
            try self.convolver.commit(generation);
        }

        pub fn adoptPending(self: *Self) bool {
            return self.convolver.adoptPending();
        }

        /// Requires preparation and audio processing to be stopped.
        pub fn valid(self: *const Self) bool {
            return self.convolver.valid();
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
        declared_sample_rate: u32 = 0,
        declared_frame_count: usize = 0,
        declared_point_count: usize = 0,
        declared_crossfade_samples: usize = 0,
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

        pub fn valid(self: *const Self) bool {
            if (!self.prepared) {
                if (self.sample_rate != 0 or
                    self.frame_count != 0 or
                    self.point_count != 0 or
                    self.crossfade_samples != 0 or
                    self.declared_sample_rate != 0 or
                    self.declared_frame_count != 0 or
                    self.declared_point_count != 0 or
                    self.declared_crossfade_samples != 0 or
                    self.history_write != 0 or
                    self.current_point != 0 or
                    self.sample_position != 0)
                    return false;
                for (self.history) |sample| {
                    if (sample != 0.0) return false;
                }
                return true;
            }
            if (!self.processingStateValid()) return false;
            for (self.history) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            for (self.points[0..self.point_count], 0..) |point, index| {
                const direction = directionFromPositions(
                    point.source_position,
                    point.head_pose,
                ) catch return false;
                validateDirection(self.directions[index]) catch return false;
                if (!sameDirection(
                    directionVector(direction),
                    directionVector(self.directions[index]),
                )) return false;
                if (index == 0) {
                    if (point.sample_position != 0) return false;
                } else {
                    const previous = self.points[index - 1].sample_position;
                    if (point.sample_position <= previous or
                        point.sample_position - previous <
                            self.crossfade_samples)
                        return false;
                }
                for (self.filters[index][0..self.frame_count]) |frame| {
                    if (!std.math.isFinite(frame[0]) or
                        !std.math.isFinite(frame[1]))
                        return false;
                }
            }
            return true;
        }

        pub fn prepare(
            self: *Self,
            database: anytype,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            try validatePreparation(
                database,
                points,
                crossfade_samples,
            );

            var staged_directions: [maximum_points]Direction =
                @splat(.{
                    .azimuth_degrees = 0.0,
                    .elevation_degrees = 0.0,
                });
            var staged_filters: [maximum_points][maximum_frames][2]f32 =
                @splat(@splat(@splat(0.0)));
            for (points, 0..) |point, point_index| {
                const position = try measurementFromPositions(
                    point.source_position,
                    point.head_pose,
                );
                staged_directions[point_index] = position.direction;
                const destination = @as(
                    [*]f32,
                    @ptrCast(&staged_filters[point_index]),
                )[0 .. database.frame_count * 2];
                try database.interpolateAt(
                    position,
                    interpolation,
                    destination,
                );
            }

            self.commitPreparation(
                database.sample_rate,
                database.frame_count,
                points,
                crossfade_samples,
                &staged_directions,
                &staged_filters,
            );
        }

        pub fn prepareRoom(
            self: *Self,
            database: anytype,
            room: ShoeboxRoom,
            speed_of_sound_meters_per_second: f64,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            return self.preparePlannedRoom(
                FirstOrderRoomPathPlan,
                maximum_first_order_room_paths,
                database,
                room,
                speed_of_sound_meters_per_second,
                points,
                interpolation,
                crossfade_samples,
            );
        }

        pub fn prepareSecondOrderRoom(
            self: *Self,
            database: anytype,
            room: ShoeboxRoom,
            speed_of_sound_meters_per_second: f64,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            return self.preparePlannedRoom(
                SecondOrderRoomPathPlan,
                maximum_second_order_room_paths,
                database,
                room,
                speed_of_sound_meters_per_second,
                points,
                interpolation,
                crossfade_samples,
            );
        }

        pub fn prepareImageSourceRoom(
            self: *Self,
            comptime reflection_order: usize,
            database: anytype,
            room: ShoeboxRoom,
            speed_of_sound_meters_per_second: f64,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            return self.preparePlannedRoom(
                ImageSourceRoomPathPlan(reflection_order),
                roomPathCapacityForOrder(reflection_order),
                database,
                room,
                speed_of_sound_meters_per_second,
                points,
                interpolation,
                crossfade_samples,
            );
        }

        pub fn prepareFrequencyDependentImageSourceRoom(
            self: *Self,
            comptime reflection_order: usize,
            comptime maximum_surface_frames: usize,
            database: anytype,
            room: ShoeboxRoom,
            materials: *const RoomSurfaceImpulseResponses(
                maximum_surface_frames,
            ),
            speed_of_sound_meters_per_second: f64,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            try validatePreparation(database, points, crossfade_samples);

            const Plan = ImageSourceRoomPathPlan(reflection_order);
            const Composer = FrequencyDependentRoomResponseComposer(
                maximum_frames,
                reflection_order,
                maximum_surface_frames,
            );
            var composer = Composer{};
            var staged_directions: [maximum_points]Direction =
                @splat(.{
                    .azimuth_degrees = 0.0,
                    .elevation_degrees = 0.0,
                });
            var staged_filters: [maximum_points][maximum_frames][2]f32 =
                @splat(@splat(@splat(0.0)));
            var frame_count: usize = 0;
            for (points, 0..) |point, point_index| {
                const plan = try Plan.init(
                    room,
                    database.sample_rate,
                    speed_of_sound_meters_per_second,
                    point.source_position,
                    point.head_pose,
                );
                const paths = try plan.items();
                staged_directions[point_index] = paths[0].direction;
                const destination = @as(
                    [*]f32,
                    @ptrCast(&staged_filters[point_index]),
                )[0 .. maximum_frames * 2];
                const composed_frames = try composer.compose(
                    database,
                    &plan,
                    materials,
                    interpolation,
                    destination,
                );
                frame_count = @max(frame_count, composed_frames);
            }

            self.commitPreparation(
                database.sample_rate,
                frame_count,
                points,
                crossfade_samples,
                &staged_directions,
                &staged_filters,
            );
        }

        fn preparePlannedRoom(
            self: *Self,
            comptime Plan: type,
            comptime maximum_paths: usize,
            database: anytype,
            room: ShoeboxRoom,
            speed_of_sound_meters_per_second: f64,
            points: []const MotionPoint,
            interpolation: Interpolation,
            crossfade_samples: usize,
        ) !void {
            try validatePreparation(
                database,
                points,
                crossfade_samples,
            );

            const Composer = RoomResponseComposer(
                maximum_frames,
                maximum_paths,
            );
            var composer = Composer{};
            var staged_directions: [maximum_points]Direction =
                @splat(.{
                    .azimuth_degrees = 0.0,
                    .elevation_degrees = 0.0,
                });
            var staged_filters: [maximum_points][maximum_frames][2]f32 =
                @splat(@splat(@splat(0.0)));
            var frame_count: usize = 0;
            for (points, 0..) |point, point_index| {
                const plan = try Plan.init(
                    room,
                    database.sample_rate,
                    speed_of_sound_meters_per_second,
                    point.source_position,
                    point.head_pose,
                );
                const paths = try plan.items();
                staged_directions[point_index] = paths[0].direction;
                const destination = @as(
                    [*]f32,
                    @ptrCast(&staged_filters[point_index]),
                )[0 .. maximum_frames * 2];
                const composed_frames = composer.compose(
                    database,
                    paths,
                    interpolation,
                    destination,
                ) catch |err| switch (err) {
                    error.InvalidHrtfRoomPathDelay => return error.HrtfFrameCapacityExceeded,
                    else => return err,
                };
                frame_count = @max(frame_count, composed_frames);
            }

            self.commitPreparation(
                database.sample_rate,
                frame_count,
                points,
                crossfade_samples,
                &staged_directions,
                &staged_filters,
            );
        }

        pub fn processSample(self: *Self, input: f32) [2]f32 {
            if (!self.processingStateValid())
                return @splat(0.0);
            const contained_input =
                if (std.math.isFinite(input)) input else 0.0;
            const current = self.filtered(
                self.current_point,
                contained_input,
            ) orelse return @splat(0.0);
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
                const next = self.filtered(
                    next_point,
                    contained_input,
                ) orelse return @splat(0.0);
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
            self.history[self.history_write] = contained_input;
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
            if (!self.processingStateValid()) return null;
            return self.directions[self.current_point];
        }

        fn filtered(
            self: *const Self,
            point_index: usize,
            current_input: f32,
        ) ?[2]f32 {
            var output: [2]f64 = @splat(0.0);
            for (0..self.frame_count) |frame_index| {
                const history_index =
                    (self.history_write +
                        self.frame_count -
                        frame_index) %
                    self.frame_count;
                const sample = if (frame_index == 0)
                    current_input
                else
                    self.history[history_index];
                if (!std.math.isFinite(sample)) return null;
                for (0..2) |channel_index| {
                    const coefficient =
                        self.filters[point_index][frame_index][channel_index];
                    if (!std.math.isFinite(coefficient)) return null;
                    output[channel_index] +=
                        sample *
                        coefficient;
                }
            }
            const converted = [2]f32{
                @floatCast(output[0]),
                @floatCast(output[1]),
            };
            if (!std.math.isFinite(converted[0]) or
                !std.math.isFinite(converted[1]))
                return null;
            return converted;
        }

        fn processingStateValid(self: *const Self) bool {
            if (!self.prepared or
                self.sample_rate < 8_000 or
                self.sample_rate > 384_000 or
                self.sample_rate != self.declared_sample_rate or
                self.frame_count == 0 or
                self.frame_count > maximum_frames or
                self.frame_count != self.declared_frame_count or
                self.point_count == 0 or
                self.point_count > maximum_points or
                self.point_count != self.declared_point_count or
                self.crossfade_samples == 0 or
                self.crossfade_samples > maximum_crossfade_samples or
                self.crossfade_samples != self.declared_crossfade_samples or
                self.history_write >= self.frame_count or
                self.current_point >= self.point_count)
                return false;
            if (self.sample_position <
                self.points[self.current_point].sample_position)
                return false;
            const next_point = self.current_point + 1;
            if (next_point == self.point_count) return true;
            const crossfade_tail = std.math.cast(
                u64,
                self.crossfade_samples - 1,
            ) orelse return false;
            const transition_end = std.math.add(
                u64,
                self.points[next_point].sample_position,
                crossfade_tail,
            ) catch return false;
            return self.sample_position <= transition_end;
        }

        fn validatePreparation(
            database: anytype,
            prepared_points: []const MotionPoint,
            prepared_crossfade_samples: usize,
        ) !void {
            if (!database.*.valid()) return error.InvalidHrtfDatabase;
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            if (prepared_points.len == 0 or
                prepared_points.len > maximum_points)
            {
                return error.InvalidHrtfMotionPointCount;
            }
            if (prepared_crossfade_samples == 0 or
                prepared_crossfade_samples > maximum_crossfade_samples)
            {
                return error.InvalidHrtfCrossfade;
            }
            if (prepared_points[0].sample_position != 0)
                return error.InvalidHrtfMotionSchedule;
            const crossfade_tail = std.math.cast(
                u64,
                prepared_crossfade_samples - 1,
            ) orelse return error.InvalidHrtfMotionSchedule;
            for (prepared_points[1..], 1..) |point, point_index| {
                const previous =
                    prepared_points[point_index - 1].sample_position;
                if (point.sample_position <= previous or
                    point.sample_position - previous <
                        prepared_crossfade_samples)
                {
                    return error.InvalidHrtfMotionSchedule;
                }
                _ = std.math.add(
                    u64,
                    point.sample_position,
                    crossfade_tail,
                ) catch return error.InvalidHrtfMotionSchedule;
            }
        }

        fn commitPreparation(
            self: *Self,
            prepared_sample_rate: u32,
            prepared_frame_count: usize,
            prepared_points: []const MotionPoint,
            prepared_crossfade_samples: usize,
            prepared_directions: *const [maximum_points]Direction,
            prepared_filters: *const [maximum_points][maximum_frames][2]f32,
        ) void {
            self.sample_rate = prepared_sample_rate;
            self.frame_count = prepared_frame_count;
            self.point_count = prepared_points.len;
            self.crossfade_samples = prepared_crossfade_samples;
            self.declared_sample_rate = prepared_sample_rate;
            self.declared_frame_count = prepared_frame_count;
            self.declared_point_count = prepared_points.len;
            self.declared_crossfade_samples = prepared_crossfade_samples;
            @memcpy(self.points[0..prepared_points.len], prepared_points);
            @memcpy(
                self.directions[0..prepared_points.len],
                prepared_directions[0..prepared_points.len],
            );
            @memcpy(
                self.filters[0..prepared_points.len],
                prepared_filters[0..prepared_points.len],
            );
            self.reset();
            self.prepared = true;
        }
    };
}

const direction_tolerance_squared = 1.0e-24;

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

fn validatePosition(position: Position) !void {
    if (!std.math.isFinite(position.x) or
        !std.math.isFinite(position.y) or
        !std.math.isFinite(position.z))
        return error.InvalidHrtfPosition;
}

fn validateShoeboxRoom(room: ShoeboxRoom) !void {
    try validatePosition(room.minimum);
    try validatePosition(room.maximum);
    if (room.minimum.x >= room.maximum.x or
        room.minimum.y >= room.maximum.y or
        room.minimum.z >= room.maximum.z or
        !std.math.isFinite(room.maximum.x - room.minimum.x) or
        !std.math.isFinite(room.maximum.y - room.minimum.y) or
        !std.math.isFinite(room.maximum.z - room.minimum.z))
    {
        return error.InvalidHrtfRoomGeometry;
    }
    for (room.absorption.values()) |absorption| {
        if (!std.math.isFinite(absorption) or
            absorption < 0.0 or absorption > 1.0)
        {
            return error.InvalidHrtfRoomAbsorption;
        }
    }
}

const RoomPlanOrigin = struct {
    direct_path: RoomPath,
    direct_distance: f64,
};

fn roomPlanOrigin(
    room: ShoeboxRoom,
    sample_rate: u32,
    speed_of_sound_meters_per_second: f64,
    source_position: Position,
    head_pose: HeadPose,
) !RoomPlanOrigin {
    try validateShoeboxRoom(room);
    if (sample_rate < 8_000 or sample_rate > 384_000)
        return error.InvalidHrtfSampleRate;
    if (!std.math.isFinite(speed_of_sound_meters_per_second) or
        speed_of_sound_meters_per_second <= 0.0)
    {
        return error.InvalidHrtfSpeedOfSound;
    }
    try validatePosition(source_position);
    try validatePosition(head_pose.position);
    if (!positionInsideRoom(room, source_position) or
        !positionInsideRoom(room, head_pose.position))
    {
        return error.HrtfRoomPositionOutsideBounds;
    }
    const direct_distance = try distanceBetweenPositions(
        source_position,
        head_pose.position,
    );
    const direct_direction = try directionFromPositions(
        source_position,
        head_pose,
    );
    return .{
        .direct_path = .{
            .direction = direct_direction,
            .distance_metres = direct_distance,
        },
        .direct_distance = direct_distance,
    };
}

const second_order_image_indices = [_][3]i16{
    .{ -2, 0, 0 },
    .{ 2, 0, 0 },
    .{ 0, -2, 0 },
    .{ 0, 2, 0 },
    .{ 0, 0, -2 },
    .{ 0, 0, 2 },
    .{ -1, -1, 0 },
    .{ -1, 1, 0 },
    .{ 1, -1, 0 },
    .{ 1, 1, 0 },
    .{ -1, 0, -1 },
    .{ -1, 0, 1 },
    .{ 1, 0, -1 },
    .{ 1, 0, 1 },
    .{ 0, -1, -1 },
    .{ 0, -1, 1 },
    .{ 0, 1, -1 },
    .{ 0, 1, 1 },
};

fn imagePosition(
    room: ShoeboxRoom,
    source: Position,
    indices: [3]i16,
) Position {
    return .{
        .x = imageCoordinate(
            room.minimum.x,
            room.maximum.x,
            source.x,
            indices[0],
        ),
        .y = imageCoordinate(
            room.minimum.y,
            room.maximum.y,
            source.y,
            indices[1],
        ),
        .z = imageCoordinate(
            room.minimum.z,
            room.maximum.z,
            source.z,
            indices[2],
        ),
    };
}

fn imageCoordinate(
    minimum: f64,
    maximum: f64,
    source: f64,
    index: i16,
) f64 {
    const length = maximum - minimum;
    const index_value: f64 = @floatFromInt(index);
    if (@mod(index, 2) == 0) return source + index_value * length;
    return 2.0 * minimum + (index_value + 1.0) * length - source;
}

fn imageReflection(room: ShoeboxRoom, indices: [3]i16) f64 {
    const absorption = room.absorption;
    return axisImageReflection(
        absorption.minimum_x,
        absorption.maximum_x,
        indices[0],
    ) * axisImageReflection(
        absorption.minimum_y,
        absorption.maximum_y,
        indices[1],
    ) * axisImageReflection(
        absorption.minimum_z,
        absorption.maximum_z,
        indices[2],
    );
}

fn axisImageReflection(
    minimum_absorption: f64,
    maximum_absorption: f64,
    index: i16,
) f64 {
    const minimum = @sqrt(1.0 - minimum_absorption);
    const maximum = @sqrt(1.0 - maximum_absorption);
    const reflection_count = imageIndexMagnitude(index);
    var result: f64 = 1.0;
    for (0..reflection_count) |reflection_index| {
        const minimum_surface = imageSurfaceIndex(
            0,
            index,
            reflection_index,
        ) == 0;
        result *= if (minimum_surface) minimum else maximum;
    }
    return result;
}

fn imageSurfaceIndex(
    axis: usize,
    index: i16,
    reflection_index: usize,
) usize {
    const minimum_surface = if (index < 0)
        reflection_index % 2 == 0
    else
        reflection_index % 2 == 1;
    return axis * 2 + @intFromBool(!minimum_surface);
}

fn imageIndexMagnitude(index: i16) usize {
    return @intCast(if (index < 0) -index else index);
}

fn roomPathFromImage(
    image: Position,
    head_pose: HeadPose,
    direct_distance: f64,
    reflection: f64,
    sample_rate: u32,
    speed_of_sound_meters_per_second: f64,
) !RoomPath {
    const reflected_distance = try distanceBetweenPositions(
        image,
        head_pose.position,
    );
    const gain = reflection * direct_distance / reflected_distance;
    const delay =
        (reflected_distance - direct_distance) *
        @as(f64, @floatFromInt(sample_rate)) /
        speed_of_sound_meters_per_second;
    if (!std.math.isFinite(gain) or gain <= 0.0 or gain > 1.0 or
        !std.math.isFinite(delay) or delay <= 0.0)
    {
        return error.InvalidHrtfRoomGeometry;
    }
    return .{
        .direction = try directionFromPositions(image, head_pose),
        .distance_metres = reflected_distance,
        .gain = gain,
        .additional_delay_samples = delay,
    };
}

fn roomPathPlanValid(
    path_storage: []const RoomPath,
    path_count: usize,
    maximum_path_count: usize,
) bool {
    if (path_count == 0 or
        path_count > maximum_path_count or
        path_count > path_storage.len)
    {
        return false;
    }
    for (path_storage[0..path_count], 0..) |path, index| {
        validateMeasurementPosition(.{
            .direction = path.direction,
            .distance_metres = path.distance_metres,
        }) catch return false;
        if (!std.math.isFinite(path.gain) or
            path.gain < 0.0 or path.gain > 1.0 or
            !std.math.isFinite(path.additional_delay_samples) or
            path.additional_delay_samples < 0.0)
        {
            return false;
        }
        if (index == 0 and
            (path.gain != 1.0 or path.additional_delay_samples != 0.0))
        {
            return false;
        }
        if (index != 0 and
            (path.gain <= 0.0 or path.additional_delay_samples <= 0.0))
        {
            return false;
        }
    }
    return true;
}

fn positionInsideRoom(room: ShoeboxRoom, position: Position) bool {
    return position.x > room.minimum.x and
        position.x < room.maximum.x and
        position.y > room.minimum.y and
        position.y < room.maximum.y and
        position.z > room.minimum.z and
        position.z < room.maximum.z;
}

fn distanceBetweenPositions(first: Position, second: Position) !f64 {
    const x = first.x - second.x;
    const y = first.y - second.y;
    const z = first.z - second.z;
    const squared = x * x + y * y + z * z;
    if (!std.math.isFinite(squared) or
        squared <= direction_tolerance_squared)
    {
        return error.InvalidHrtfRoomGeometry;
    }
    const distance = @sqrt(squared);
    if (!std.math.isFinite(distance))
        return error.InvalidHrtfRoomGeometry;
    return distance;
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

fn validateMeasurementPosition(position: MeasurementPosition) !void {
    try validateDirection(position.direction);
    if (!std.math.isFinite(position.distance_metres) or
        position.distance_metres <= 0.0)
    {
        return error.InvalidHrtfDistance;
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

fn measurementVector(position: MeasurementPosition) [3]f64 {
    const unit = directionVector(position.direction);
    return .{
        unit[0] * position.distance_metres,
        unit[1] * position.distance_metres,
        unit[2] * position.distance_metres,
    };
}

fn vectorDistanceSquared(first: [3]f64, second: [3]f64) f64 {
    return chordDistanceSquared(first, second);
}

fn sameMeasurementPosition(
    first: MeasurementPosition,
    second: MeasurementPosition,
) bool {
    return vectorDistanceSquared(
        measurementVector(first),
        measurementVector(second),
    ) <= direction_tolerance_squared;
}

fn sameDirection(first: [3]f64, second: [3]f64) bool {
    return chordDistanceSquared(first, second) <=
        direction_tolerance_squared;
}

test "HRTF motion clock maps ordered tracker timestamps exactly" {
    var clock = try MotionClock.init(
        48_000,
        1_000_000_000,
        10_000_000_000,
        100,
    );
    try std.testing.expect(clock.valid());
    try std.testing.expectEqual(
        @as(u64, 100),
        try clock.map(10_000_000_000),
    );
    try std.testing.expectEqual(
        @as(u64, 101),
        try clock.map(10_000_020_834),
    );
    try std.testing.expectEqual(
        @as(u64, 48_100),
        try clock.map(11_000_000_000),
    );
    try std.testing.expect(clock.valid());

    try clock.reanchor(12_000_000_000, 96_101);
    try std.testing.expect(clock.valid());
    try std.testing.expectEqual(
        @as(u64, 96_101),
        try clock.map(12_000_000_000),
    );
    try std.testing.expectEqual(
        @as(u64, 120_101),
        try clock.map(12_500_000_000),
    );
    try std.testing.expect(clock.valid());
}

test "HRTF motion clock calibrates an observed tracker rate" {
    var clock = try MotionClock.initCalibrated(
        48_000,
        2_000_000_000,
        96_000,
        3_000_050_000,
        144_000,
    );
    try std.testing.expectEqual(
        @as(u64, 1_000_050_000),
        clock.tracker_ticks_per_second,
    );
    try std.testing.expectEqual(
        @as(u64, 144_000),
        try clock.map(3_000_050_000),
    );
    try std.testing.expectEqual(
        @as(u64, 192_000),
        try clock.map(4_000_100_000),
    );

    try std.testing.expectError(
        error.InvalidHrtfTrackerClockObservation,
        MotionClock.initCalibrated(48_000, 4, 0, 4, 1),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockObservation,
        MotionClock.initCalibrated(48_000, 4, 1, 5, 1),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockRate,
        MotionClock.initCalibrated(
            8_000,
            0,
            0,
            1,
            std.math.maxInt(u64),
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockRate,
        MotionClock.initCalibrated(
            384_000,
            0,
            0,
            std.math.maxInt(u64),
            1,
        ),
    );
}

test "HRTF motion clock calibrator filters an interior outlier" {
    const Calibrator = MotionClockCalibrator(5);
    var calibrator = Calibrator{};
    try std.testing.expect(calibrator.valid());
    for ([_]MotionClockObservation{
        .{ .tracker_timestamp = 0, .sample_position = 0 },
        .{ .tracker_timestamp = 100_000_000, .sample_position = 4_800 },
        .{ .tracker_timestamp = 200_000_000, .sample_position = 9_648 },
        .{ .tracker_timestamp = 300_000_000, .sample_position = 14_400 },
        .{ .tracker_timestamp = 400_000_000, .sample_position = 19_200 },
    }) |observation| try calibrator.observe(observation);
    try std.testing.expect(calibrator.valid());

    var clock = try calibrator.calibrate(48_000, 1_000);
    try std.testing.expectEqual(
        @as(u64, 1_000_000_000),
        clock.tracker_ticks_per_second,
    );
    try std.testing.expectEqual(
        @as(u64, 24_000),
        try clock.map(500_000_000),
    );
}

test "HRTF motion clock calibrator rejects a newest outlier" {
    const Calibrator = MotionClockCalibrator(5);
    var calibrator = Calibrator{};
    for ([_]MotionClockObservation{
        .{ .tracker_timestamp = 0, .sample_position = 0 },
        .{ .tracker_timestamp = 100_000_000, .sample_position = 4_800 },
        .{ .tracker_timestamp = 200_000_000, .sample_position = 9_600 },
        .{ .tracker_timestamp = 300_000_000, .sample_position = 14_400 },
        .{ .tracker_timestamp = 400_000_000, .sample_position = 19_248 },
    }) |observation| try calibrator.observe(observation);

    try std.testing.expectError(
        error.UnstableHrtfTrackerClockObservations,
        calibrator.calibrate(48_000, 1_000),
    );
}

test "HRTF motion clock calibrator admits observations transactionally" {
    const Calibrator = MotionClockCalibrator(4);
    var calibrator = Calibrator{};
    try std.testing.expectEqual(
        @as(?MotionClock, null),
        try calibrator.observeAndCalibrate(
            .{ .tracker_timestamp = 0, .sample_position = 0 },
            48_000,
            1_000,
        ),
    );
    try std.testing.expectEqual(
        @as(?MotionClock, null),
        try calibrator.observeAndCalibrate(
            .{ .tracker_timestamp = 100_000_000, .sample_position = 4_800 },
            48_000,
            1_000,
        ),
    );
    const clock = (try calibrator.observeAndCalibrate(
        .{ .tracker_timestamp = 200_000_000, .sample_position = 9_600 },
        48_000,
        1_000,
    )).?;
    try std.testing.expectEqual(
        @as(u64, 1_000_000_000),
        clock.tracker_ticks_per_second,
    );

    const retained = calibrator;
    try std.testing.expectError(
        error.UnstableHrtfTrackerClockObservations,
        calibrator.observeAndCalibrate(
            .{ .tracker_timestamp = 300_000_000, .sample_position = 14_448 },
            48_000,
            1_000,
        ),
    );
    try std.testing.expectEqualDeep(retained, calibrator);

    const next = (try calibrator.observeAndCalibrate(
        .{ .tracker_timestamp = 300_000_000, .sample_position = 14_400 },
        48_000,
        1_000,
    )).?;
    try std.testing.expectEqual(
        @as(u64, 300_000_000),
        next.tracker_anchor,
    );
}

test "HRTF motion clock calibrator rolls its bounded window" {
    const Calibrator = MotionClockCalibrator(4);
    var calibrator = Calibrator{};
    for (0..5) |index| {
        try calibrator.observe(.{
            .tracker_timestamp = index * 100_000_000,
            .sample_position = index * 4_800,
        });
    }
    try std.testing.expectEqual(@as(usize, 4), try calibrator.count());
    const clock = try calibrator.calibrate(48_000, 100);
    try std.testing.expectEqual(
        @as(u64, 400_000_000),
        clock.tracker_anchor,
    );
    try std.testing.expectEqual(@as(u64, 19_200), clock.sample_anchor);

    calibrator.reset();
    try std.testing.expect(calibrator.valid());
    try std.testing.expectEqual(@as(usize, 0), try calibrator.count());
    try std.testing.expectError(
        error.InsufficientHrtfTrackerClockObservations,
        calibrator.calibrate(48_000, 100),
    );
}

test "HRTF motion clock calibrator contains invalid state" {
    const Calibrator = MotionClockCalibrator(3);
    var calibrator = Calibrator{};
    try calibrator.observe(.{
        .tracker_timestamp = 10,
        .sample_position = 20,
    });
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockObservation,
        calibrator.observe(.{
            .tracker_timestamp = 10,
            .sample_position = 21,
        }),
    );
    try std.testing.expectEqual(@as(usize, 1), try calibrator.count());
    try calibrator.observe(.{
        .tracker_timestamp = 20,
        .sample_position = 40,
    });
    try calibrator.observe(.{
        .tracker_timestamp = 30,
        .sample_position = 60,
    });
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockTolerance,
        calibrator.calibrate(48_000, 0),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockTolerance,
        calibrator.calibrate(48_000, 1_000_001),
    );
    try std.testing.expectError(
        error.InvalidHrtfSampleRate,
        calibrator.calibrate(7_999, 100),
    );

    var corrupt_count = calibrator;
    corrupt_count.observation_count = 4;
    try std.testing.expect(!corrupt_count.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionClockCalibratorState,
        corrupt_count.count(),
    );

    var corrupt_order = Calibrator{};
    corrupt_order.observations[0] = .{
        .tracker_timestamp = 2,
        .sample_position = 1,
    };
    corrupt_order.observations[1] = .{
        .tracker_timestamp = 1,
        .sample_position = 2,
    };
    corrupt_order.observation_count = 2;
    try std.testing.expect(!corrupt_order.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionClockCalibratorState,
        corrupt_order.observe(.{
            .tracker_timestamp = 3,
            .sample_position = 3,
        }),
    );
}

test "HRTF motion clock rejects invalid and unresolved time transactionally" {
    try std.testing.expectError(
        error.InvalidHrtfSampleRate,
        MotionClock.init(7_999, 1, 0, 0),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockRate,
        MotionClock.init(48_000, 0, 0, 0),
    );

    var clock = try MotionClock.init(48_000, 1_000_000_000, 1_000, 7);
    try std.testing.expectEqual(@as(u64, 7), try clock.map(1_000));
    try std.testing.expectError(
        error.InvalidHrtfTrackerTimestamp,
        clock.map(999),
    );
    try std.testing.expectError(
        error.HrtfTrackerTimestampTooDense,
        clock.map(1_001),
    );
    try std.testing.expectEqual(
        @as(u64, 8),
        try clock.map(21_834),
    );

    try std.testing.expectError(
        error.InvalidHrtfTrackerClockAnchor,
        clock.reanchor(21_834, 9),
    );
    try std.testing.expectError(
        error.InvalidHrtfTrackerClockAnchor,
        clock.reanchor(30_000, 8),
    );
    try std.testing.expectEqual(
        @as(u64, 9),
        try clock.map(42_667),
    );

    var overflowing = try MotionClock.init(
        384_000,
        1,
        0,
        std.math.maxInt(u64),
    );
    try std.testing.expectError(
        error.HrtfMotionSamplePositionOverflow,
        overflowing.map(1),
    );
    try std.testing.expectEqual(
        @as(u64, std.math.maxInt(u64)),
        try overflowing.map(0),
    );

    var corrupt = clock;
    corrupt.tracker_ticks_per_second = 0;
    try std.testing.expect(!corrupt.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionClockState,
        corrupt.map(50_000),
    );
    corrupt = clock;
    corrupt.sample_rate = 1;
    try std.testing.expect(!corrupt.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionClockState,
        corrupt.reanchor(50_000, 10),
    );

    corrupt = clock;
    corrupt.has_mapped_timestamp = false;
    try std.testing.expect(!corrupt.valid());
    const corrupt_before = corrupt;
    try std.testing.expectError(
        error.InvalidHrtfMotionClockState,
        corrupt.map(50_000),
    );
    try std.testing.expectEqual(corrupt_before, corrupt);
}

test "HRTF motion point queue validates and preserves tracker updates" {
    const Queue = MotionPointQueue(2);
    var queue = Queue{};
    try std.testing.expect(queue.valid());
    for (queue.points) |point|
        try std.testing.expectEqualDeep(MotionPoint{}, point);
    const first = MotionPoint{
        .sample_position = 10,
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    };
    const second = MotionPoint{
        .sample_position = 20,
        .source_position = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .yaw_degrees = 15.0,
        },
    };
    const third = MotionPoint{
        .sample_position = 30,
        .source_position = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    };

    try std.testing.expect(try queue.submit(first));
    try std.testing.expect(queue.valid());
    const read_before_corruption = queue.read_index.load(.acquire);
    queue.points[0].head_pose.yaw_degrees = std.math.nan(f64);
    try std.testing.expect(!queue.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.receive(),
    );
    try std.testing.expectEqual(
        read_before_corruption,
        queue.read_index.load(.acquire),
    );
    try std.testing.expectEqual(@as(usize, 1), try queue.pending());
    queue.points[0] = first;
    try std.testing.expect(queue.valid());
    try std.testing.expect(try queue.submit(second));
    try std.testing.expect(!(try queue.submit(third)));
    try std.testing.expectEqual(@as(usize, 2), try queue.pending());
    try std.testing.expectEqual(@as(usize, 1), queue.dropped());
    queue.points[0].sample_position = second.sample_position;
    try std.testing.expect(!queue.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.receive(),
    );
    try std.testing.expectEqual(
        read_before_corruption,
        queue.read_index.load(.acquire),
    );
    try std.testing.expectEqual(@as(usize, 2), try queue.pending());
    queue.points[0] = first;
    try std.testing.expect(queue.valid());
    try std.testing.expectEqualDeep(first, (try queue.receive()).?);
    try std.testing.expect(try queue.submit(third));
    try std.testing.expectEqualDeep(second, (try queue.receive()).?);
    try std.testing.expectEqualDeep(third, (try queue.receive()).?);
    try std.testing.expect((try queue.receive()) == null);
    try std.testing.expect(queue.valid());

    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        queue.submit(third),
    );
    var invalid = third;
    invalid.sample_position = 40;
    invalid.source_position = invalid.head_pose.position;
    try std.testing.expectError(
        error.InvalidHrtfSourcePosition,
        queue.submit(invalid),
    );
    try std.testing.expectEqual(@as(usize, 0), try queue.pending());

    queue.reset();
    try std.testing.expect(queue.valid());
    try std.testing.expectEqual(@as(usize, 0), queue.dropped());
    for (queue.points) |point|
        try std.testing.expectEqualDeep(MotionPoint{}, point);
    try std.testing.expect(try queue.submit(.{
        .sample_position = 0,
        .source_position = first.source_position,
        .head_pose = first.head_pose,
    }));
}

test "HRTF tracked submission preserves the clock until queue publication" {
    const Queue = MotionPointQueue(1);
    var queue = Queue{};
    var clock = try MotionClock.init(48_000, 1_000_000_000, 1_000, 10);
    const source = Position{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const head = HeadPose{
        .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
    };

    try std.testing.expect(try queue.submitTracked(
        &clock,
        1_000,
        source,
        head,
    ));
    const retained_timestamp = clock.last_tracker_timestamp;
    const retained_sample = clock.last_sample_position;
    try std.testing.expect(!(try queue.submitTracked(
        &clock,
        21_834,
        source,
        head,
    )));
    try std.testing.expectEqual(
        retained_timestamp,
        clock.last_tracker_timestamp,
    );
    try std.testing.expectEqual(
        retained_sample,
        clock.last_sample_position,
    );

    _ = try queue.receive();
    try std.testing.expect(try queue.submitTracked(
        &clock,
        21_834,
        source,
        head,
    ));
    const second = (try queue.receive()).?;
    try std.testing.expectEqual(@as(u64, 11), second.sample_position);

    var invalid_head = head;
    invalid_head.position = source;
    try std.testing.expectError(
        error.InvalidHrtfSourcePosition,
        queue.submitTracked(
            &clock,
            42_667,
            source,
            invalid_head,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 21_834),
        clock.last_tracker_timestamp,
    );
}

test "HRTF motion point queue contains cursor overflow" {
    const Queue = MotionPointQueue(2);
    var queue = Queue{};
    const point = MotionPoint{
        .sample_position = 0,
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    };
    const near_wrap = std.math.maxInt(usize);
    queue.write_index.store(near_wrap, .release);
    queue.read_index.store(near_wrap, .release);
    try std.testing.expect(try queue.submit(point));
    try std.testing.expectEqualDeep(point, (try queue.receive()).?);
    var next = point;
    next.sample_position = 1;
    try std.testing.expect(try queue.submit(next));
    try std.testing.expectEqualDeep(next, (try queue.receive()).?);

    queue.write_index.store(3, .release);
    queue.read_index.store(0, .release);
    try std.testing.expect(!queue.valid());
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.pending(),
    );
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.receive(),
    );
    next.sample_position = 2;
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.submit(next),
    );

    queue.reset();
    try std.testing.expect(queue.valid());
    try std.testing.expect(try queue.submit(point));
    next.sample_position = 1;
    try std.testing.expect(try queue.submit(next));
    queue.last_submitted_sample = 0;
    try std.testing.expect(!queue.valid());
    const write_before_rejection = queue.write_index.load(.acquire);
    var rejected = next;
    rejected.sample_position = 2;
    try std.testing.expectError(
        error.InvalidHrtfMotionQueueState,
        queue.submit(rejected),
    );
    try std.testing.expectEqual(
        write_before_rejection,
        queue.write_index.load(.acquire),
    );
    queue.last_submitted_sample = 1;
    try std.testing.expect(queue.valid());
    queue.dropped_count.store(std.math.maxInt(usize), .release);
    var overflow = next;
    overflow.sample_position = 2;
    try std.testing.expect(!(try queue.submit(overflow)));
    try std.testing.expectEqual(
        std.math.maxInt(usize),
        queue.dropped(),
    );
}

test "HRTF motion point queue transfers concurrent tracker updates" {
    const Queue = MotionPointQueue(32);
    const point_count = 4_096;
    const Producer = struct {
        fn run(
            queue: *Queue,
            failed: *std.atomic.Value(bool),
        ) void {
            var index: usize = 0;
            while (index < point_count) {
                const accepted = queue.submit(.{
                    .sample_position = @intCast(index),
                    .source_position = .{
                        .x = 1.0,
                        .y = 0.0,
                        .z = 0.0,
                    },
                    .head_pose = .{
                        .position = .{
                            .x = 0.0,
                            .y = 0.0,
                            .z = 0.0,
                        },
                    },
                }) catch {
                    failed.store(true, .release);
                    return;
                };
                if (!accepted) {
                    std.Thread.yield() catch {};
                    continue;
                }
                index += 1;
            }
        }
    };

    var queue = Queue{};
    var failed = std.atomic.Value(bool).init(false);
    const producer = try std.Thread.spawn(
        .{},
        Producer.run,
        .{ &queue, &failed },
    );
    var expected: usize = 0;
    while (expected < point_count) {
        const point = try queue.receive() orelse {
            if (failed.load(.acquire)) break;
            std.Thread.yield() catch {};
            continue;
        };
        if (point.sample_position != expected) {
            failed.store(true, .release);
        }
        expected += 1;
    }
    producer.join();
    try std.testing.expect(!failed.load(.acquire));
    try std.testing.expectEqual(point_count, expected);
    try std.testing.expectEqual(@as(usize, 0), try queue.pending());
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

test "HRTF database interpolates repeated directions across distance" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(2, 1);
    const database = try Db.initWithDistances(
        48_000,
        &.{ direction, direction },
        &.{ 0.5, 1.5 },
        &.{ 1.0, 2.0, 3.0, 4.0 },
    );
    try std.testing.expect(database.valid());
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.5, 1.5 },
        database.distances_metres[0..2],
    );

    var output: [2]f32 = undefined;
    try database.interpolateAt(
        .{ .direction = direction, .distance_metres = 0.5 },
        .inverse_distance,
        &output,
    );
    try std.testing.expectEqualDeep([_]f32{ 1.0, 2.0 }, output);
    try database.interpolateAt(
        .{ .direction = direction, .distance_metres = 1.0 },
        .inverse_distance,
        &output,
    );
    try std.testing.expectEqualDeep([_]f32{ 2.0, 3.0 }, output);
    try database.interpolateAt(
        .{ .direction = direction, .distance_metres = 1.5 },
        .nearest,
        &output,
    );
    try std.testing.expectEqualDeep([_]f32{ 3.0, 4.0 }, output);

    try database.interpolate(direction, .nearest, &output);
    try std.testing.expectEqualDeep([_]f32{ 1.0, 2.0 }, output);
}

test "HRTF single-radius data preserves directional interpolation" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = -45.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 45.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(2, 1);
    const database = try Db.initWithDistances(
        48_000,
        &directions,
        &.{ 2.0, 2.0 },
        &.{ 1.0, 2.0, 3.0, 4.0 },
    );
    var directional: [2]f32 = undefined;
    var spatial: [2]f32 = undefined;
    const center = Direction{};
    try database.interpolate(center, .inverse_distance, &directional);
    try database.interpolateAt(
        .{ .direction = center, .distance_metres = 100.0 },
        .inverse_distance,
        &spatial,
    );
    try std.testing.expectEqualDeep(directional, spatial);
}

test "HRTF distance construction and interpolation reject transactionally" {
    const direction = Direction{};
    const Db = Database(2, 1);
    var destination: Db = undefined;
    @memset(std.mem.asBytes(&destination), 0xA5);
    const before = destination;
    try std.testing.expectError(
        error.InvalidHrtfDistanceShape,
        Db.initWithDistancesInto(
            &destination,
            48_000,
            &.{ direction, direction },
            &.{0.5},
            &.{ 1.0, 1.0, 2.0, 2.0 },
        ),
    );
    try std.testing.expectEqualDeep(before, destination);
    try std.testing.expectError(
        error.InvalidHrtfDistance,
        Db.initWithDistancesInto(
            &destination,
            48_000,
            &.{ direction, direction },
            &.{ 0.5, std.math.nan(f64) },
            &.{ 1.0, 1.0, 2.0, 2.0 },
        ),
    );
    try std.testing.expectEqualDeep(before, destination);

    var database = try Db.initWithDistances(
        48_000,
        &.{ direction, direction },
        &.{ 0.5, 1.5 },
        &.{ 1.0, 1.0, 2.0, 2.0 },
    );
    var output = [_]f32{ 9.0, 9.0 };
    try std.testing.expectError(
        error.InvalidHrtfDistance,
        database.interpolateAt(
            .{ .direction = direction, .distance_metres = 0.0 },
            .nearest,
            &output,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 9.0, 9.0 }, output);

    const database_before = database;
    try std.testing.expectError(
        error.OverlappingHrtfInterpolationStorage,
        database.interpolate(
            direction,
            .nearest,
            database.responses[0][0][0..],
        ),
    );
    try std.testing.expectError(
        error.OverlappingHrtfInterpolationStorage,
        database.interpolateAt(
            .{ .direction = direction, .distance_metres = 0.5 },
            .nearest,
            database.responses[1][0][0..],
        ),
    );
    try std.testing.expectEqualDeep(database_before, database);

    var corrupted = database;
    corrupted.measurement_count = 1;
    try std.testing.expect(!corrupted.valid());
    try std.testing.expectError(
        error.InvalidHrtfDatabase,
        corrupted.interpolateAt(
            .{ .direction = direction, .distance_metres = 0.5 },
            .nearest,
            &output,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 9.0, 9.0 }, output);

    corrupted = database;
    corrupted.distances_metres[0] = std.math.nan(f64);
    try std.testing.expect(!corrupted.valid());
    try std.testing.expectError(
        error.InvalidHrtfDatabase,
        corrupted.interpolateAt(.{}, .nearest, &output),
    );
    try std.testing.expectEqualDeep([_]f32{ 9.0, 9.0 }, output);
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
            0.5,   0.25,
            0.625, 0.3125,
            0.125, 0.0625,
        },
        delayed,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.25),
        delayed[0] + delayed[2] + delayed[4],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.625),
        delayed[1] + delayed[3] + delayed[5],
        0.000_001,
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

test "HRTF room response composes bounded directional paths" {
    const directions = [_]Direction{
        .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        .{ .azimuth_degrees = 90.0, .elevation_degrees = 0.0 },
    };
    const Db = Database(2, 1);
    var database = try Db.init(
        48_000,
        &directions,
        &.{ 1.0, 0.5, 0.25, 1.0 },
    );
    const Composer = RoomResponseComposer(4, 2);
    var composer = Composer{};
    var paths = [_]RoomPath{
        .{ .direction = directions[0] },
        .{
            .direction = directions[1],
            .gain = 0.5,
            .additional_delay_samples = 1.5,
        },
    };
    var response = [_]f32{99.0} ** 8;
    const frame_count = try composer.compose(
        &database,
        &paths,
        .nearest,
        &response,
    );
    try std.testing.expectEqual(@as(usize, 3), frame_count);
    try std.testing.expectEqualDeep(
        [_]f32{
            1.0,    0.5,
            0.0625, 0.25,
            0.0625, 0.25,
        },
        response[0..6].*,
    );
    try std.testing.expectEqualDeep([_]f32{ 99.0, 99.0 }, response[6..8].*);

    const database_before_alias = database;
    const aliased_response = @as(
        [*]f32,
        @ptrCast(&database.responses),
    )[0..2];
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            paths[0..1],
            .nearest,
            aliased_response,
        ),
    );
    try std.testing.expectEqualDeep(database_before_alias, database);

    const paths_before_alias = paths;
    const path_backed_response = @as(
        [*]f32,
        @ptrCast(&paths),
    )[0..2];
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            paths[0..1],
            .nearest,
            path_backed_response,
        ),
    );
    try std.testing.expectEqualDeep(paths_before_alias, paths);

    const cancellation_frames = try composer.compose(
        &database,
        &.{
            .{ .direction = directions[0] },
            .{ .direction = directions[0], .gain = -1.0 },
        },
        .nearest,
        &response,
    );
    try std.testing.expectEqual(@as(usize, 1), cancellation_frames);
    try std.testing.expectEqualDeep([_]f32{ 0.0, 0.0 }, response[0..2].*);

    var renderer = try Renderer(8, 8).init(48_000, .zero);
    _ = try composer.compose(
        &database,
        &paths,
        .nearest,
        &response,
    );
    try renderer.prepareInterleavedResponse(
        48_000,
        response[0 .. frame_count * 2],
        1,
    );
    try std.testing.expect(renderer.adoptPending());
    const rendered = [_][2]f32{
        renderer.processSample(1.0),
        renderer.processSample(0.0),
        renderer.processSample(0.0),
    };
    for (rendered, 0..) |frame, index| {
        try std.testing.expectApproxEqAbs(
            response[index * 2],
            frame[0],
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            response[index * 2 + 1],
            frame[1],
            0.000_001,
        );
    }
}

test "HRTF room response composes frequency-dependent surfaces" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(1, 8);
    var database = try Db.init(8_000, &.{direction}, &.{ 1.0, 1.0 });
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 10.0, .y = 2.0, .z = 2.0 },
        .absorption = .{ .maximum_x = 0.0 },
    };
    const Plan = ImageSourceRoomPathPlan(1);
    var plan = try Plan.init(
        room,
        8_000,
        8_000.0,
        .{ .x = 7.0, .y = 1.0, .z = 1.0 },
        .{ .position = .{ .x = 5.0, .y = 1.0, .z = 1.0 } },
    );
    try std.testing.expectEqual(@as(usize, 2), (try plan.items()).len);
    try std.testing.expectEqualSlices(
        [3]i16,
        &.{ .{ 0, 0, 0 }, .{ 1, 0, 0 } },
        try plan.imageIndices(),
    );

    const Materials = RoomSurfaceImpulseResponses(2);
    const delta = [_]f32{1.0};
    const materials = try Materials.init(8_000, .{
        .minimum_x = &delta,
        .maximum_x = &.{ 0.5, 0.5 },
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    const Composer = FrequencyDependentRoomResponseComposer(8, 1, 2);
    var composer = Composer{};
    var response = [_]f32{99.0} ** 18;
    const frame_count = try composer.compose(
        &database,
        &plan,
        &materials,
        .nearest,
        &response,
    );
    try std.testing.expectEqual(@as(usize, 8), frame_count);
    try std.testing.expectEqualDeep(
        [_]f32{
            1.0,   1.0,
            0.0,   0.0,
            0.0,   0.0,
            0.0,   0.0,
            0.0,   0.0,
            0.0,   0.0,
            0.125, 0.125,
            0.125, 0.125,
        },
        response[0..16].*,
    );
    try std.testing.expectEqualDeep([_]f32{ 99.0, 99.0 }, response[16..18].*);

    const database_before_alias = database;
    const aliased_response = @as(
        [*]f32,
        @ptrCast(&database.responses),
    )[0..16];
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            aliased_response,
        ),
    );
    try std.testing.expectEqualDeep(database_before_alias, database);

    const plan_before_alias = plan;
    const plan_backed_response = @as(
        [*]f32,
        @ptrCast(&plan),
    )[0..16];
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            plan_backed_response,
        ),
    );
    try std.testing.expectEqualDeep(plan_before_alias, plan);

    const response_before_failure = response;
    const mismatched_materials = try Materials.init(16_000, .{
        .minimum_x = &delta,
        .maximum_x = &.{ 0.5, 0.5 },
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    try std.testing.expectError(
        error.HrtfRoomSurfaceSampleRateMismatch,
        composer.compose(
            &database,
            &plan,
            &mismatched_materials,
            .nearest,
            &response,
        ),
    );
    try std.testing.expectEqual(response_before_failure, response);
    try std.testing.expectError(
        error.InvalidHrtfDestinationShape,
        composer.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            response[0..15],
        ),
    );
    try std.testing.expectEqual(response_before_failure, response);
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            composer.path_response[0..16],
        ),
    );
    var too_small = FrequencyDependentRoomResponseComposer(7, 1, 2){};
    try std.testing.expectError(
        error.HrtfFrameCapacityExceeded,
        too_small.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            response[0..14],
        ),
    );
    try std.testing.expectEqual(response_before_failure, response);
}

test "HRTF room materials follow repeated image surfaces transactionally" {
    const Materials = RoomSurfaceImpulseResponses(2);
    const delta = [_]f32{1.0};
    var materials = try Materials.init(8_000, .{
        .minimum_x = &.{ 1.0, 0.5 },
        .maximum_x = &.{ 1.0, -0.25 },
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    try std.testing.expectError(
        error.InvalidHrtfSampleRate,
        Materials.init(7_999, .{
            .minimum_x = &delta,
            .maximum_x = &delta,
            .minimum_y = &delta,
            .maximum_y = &delta,
            .minimum_z = &delta,
            .maximum_z = &delta,
        }),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomSurfaceResponse,
        Materials.init(8_000, .{
            .minimum_x = &.{},
            .maximum_x = &delta,
            .minimum_y = &delta,
            .maximum_y = &delta,
            .minimum_z = &delta,
            .maximum_z = &delta,
        }),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomSurfaceResponse,
        Materials.init(8_000, .{
            .minimum_x = &.{std.math.nan(f32)},
            .maximum_x = &delta,
            .minimum_y = &delta,
            .maximum_y = &delta,
            .minimum_z = &delta,
            .maximum_z = &delta,
        }),
    );
    const Composer = FrequencyDependentRoomResponseComposer(16, 3, 2);
    var composer = Composer{};
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1.0, 0.0, -0.1875, 0.03125 },
        try composer.buildMaterialResponse(&materials, .{ 3, 0, 0 }),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1.0, 0.75, 0.0, -0.0625 },
        try composer.buildMaterialResponse(&materials, .{ -3, 0, 0 }),
    );
    const axis_materials = try Materials.init(8_000, .{
        .minimum_x = &.{0.2},
        .maximum_x = &.{0.3},
        .minimum_y = &.{0.4},
        .maximum_y = &.{0.5},
        .minimum_z = &.{0.6},
        .maximum_z = &.{0.7},
    });
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.084),
        (try composer.buildMaterialResponse(
            &axis_materials,
            .{ 1, -1, 1 },
        ))[0],
        1.0e-8,
    );

    materials.frame_counts[0] = 0;
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(1, 1);
    const database = try Db.init(8_000, &.{direction}, &.{ 1.0, 1.0 });
    const plan = try ImageSourceRoomPathPlan(3).init(
        .{
            .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .maximum = .{ .x = 10.0, .y = 2.0, .z = 2.0 },
        },
        8_000,
        8_000.0,
        .{ .x = 7.0, .y = 1.0, .z = 1.0 },
        .{ .position = .{ .x = 5.0, .y = 1.0, .z = 1.0 } },
    );
    var response = [_]f32{99.0} ** 32;
    try std.testing.expectError(
        error.InvalidHrtfRoomSurfaceResponseState,
        composer.compose(
            &database,
            &plan,
            &materials,
            .nearest,
            &response,
        ),
    );
    try std.testing.expectEqual([_]f32{99.0} ** 32, response);
}

test "HRTF first-order room plan derives reflection gain and delay" {
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 10.0, .y = 8.0, .z = 3.0 },
        .absorption = .{ .maximum_x = 0.75 },
    };
    const plan = try FirstOrderRoomPathPlan.init(
        room,
        48_000,
        300.0,
        .{ .x = 7.0, .y = 4.0, .z = 1.5 },
        .{
            .position = .{ .x = 5.0, .y = 4.0, .z = 1.5 },
        },
    );
    const paths = try plan.items();
    try std.testing.expectEqual(@as(usize, 2), paths.len);
    try std.testing.expectEqualDeep(
        Direction{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        paths[0].direction,
    );
    try std.testing.expectEqual(@as(f64, 1.0), paths[0].gain);
    try std.testing.expectEqual(
        @as(f64, 0.0),
        paths[0].additional_delay_samples,
    );
    try std.testing.expectEqualDeep(paths[0].direction, paths[1].direction);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        paths[1].gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 960.0),
        paths[1].additional_delay_samples,
        1.0e-9,
    );

    const Db = Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{paths[0].direction},
        &.{ 1.0, 1.0 },
    );
    const Composer = RoomResponseComposer(1024, 7);
    var composer = Composer{};
    var response: [2048]f32 = @splat(99.0);
    const frame_count = try composer.compose(
        &database,
        paths,
        .nearest,
        &response,
    );
    try std.testing.expectEqual(@as(usize, 961), frame_count);
    try std.testing.expectEqualDeep([_]f32{ 1.0, 1.0 }, response[0..2].*);
    try std.testing.expectEqualDeep(
        [_]f32{ 0.125, 0.125 },
        response[1920..1922].*,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 99.0, 99.0 },
        response[1922..1924].*,
    );
}

test "HRTF first-order room plan covers surfaces and head rotation" {
    const plan = try FirstOrderRoomPathPlan.init(
        .{
            .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .maximum = .{ .x = 10.0, .y = 8.0, .z = 3.0 },
            .absorption = .{
                .minimum_x = 0.0,
                .maximum_x = 0.0,
                .minimum_y = 0.0,
                .maximum_y = 0.0,
                .minimum_z = 0.0,
                .maximum_z = 0.0,
            },
        },
        48_000,
        343.0,
        .{ .x = 7.0, .y = 4.5, .z = 1.75 },
        .{
            .position = .{ .x = 5.0, .y = 4.0, .z = 1.5 },
            .yaw_degrees = 90.0,
        },
    );
    const paths = try plan.items();
    try std.testing.expectEqual(
        maximum_first_order_room_paths,
        paths.len,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -75.963_756_532_073_53),
        paths[0].direction.azimuth_degrees,
        1.0e-12,
    );
    const direct_distance = @sqrt(@as(f64, 4.3125));
    const reflected_distances = [_]f64{
        @sqrt(@as(f64, 144.3125)),
        @sqrt(@as(f64, 64.3125)),
        @sqrt(@as(f64, 76.3125)),
        @sqrt(@as(f64, 60.3125)),
        @sqrt(@as(f64, 14.8125)),
        @sqrt(@as(f64, 11.8125)),
    };
    for (paths[1..], reflected_distances) |path, distance| {
        try std.testing.expectApproxEqAbs(
            direct_distance / distance,
            path.gain,
            1.0e-12,
        );
        try std.testing.expectApproxEqAbs(
            (distance - direct_distance) * 48_000.0 / 343.0,
            path.additional_delay_samples,
            1.0e-9,
        );
    }
}

test "HRTF first-order room plan rejects invalid state and geometry" {
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 10.0, .y = 8.0, .z = 3.0 },
    };
    const source = Position{ .x = 7.0, .y = 4.0, .z = 1.5 };
    const head = HeadPose{
        .position = .{ .x = 5.0, .y = 4.0, .z = 1.5 },
    };
    try std.testing.expectError(
        error.InvalidHrtfRoomGeometry,
        FirstOrderRoomPathPlan.init(
            .{
                .minimum = room.minimum,
                .maximum = .{ .x = 0.0, .y = 8.0, .z = 3.0 },
            },
            48_000,
            343.0,
            source,
            head,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomAbsorption,
        FirstOrderRoomPathPlan.init(
            .{
                .minimum = room.minimum,
                .maximum = room.maximum,
                .absorption = .{ .minimum_x = 1.01 },
            },
            48_000,
            343.0,
            source,
            head,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfSpeedOfSound,
        FirstOrderRoomPathPlan.init(
            room,
            48_000,
            0.0,
            source,
            head,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfSampleRate,
        FirstOrderRoomPathPlan.init(
            room,
            7_999,
            343.0,
            source,
            head,
        ),
    );
    try std.testing.expectError(
        error.HrtfRoomPositionOutsideBounds,
        FirstOrderRoomPathPlan.init(
            room,
            48_000,
            343.0,
            .{ .x = 10.0, .y = 4.0, .z = 1.5 },
            head,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomGeometry,
        FirstOrderRoomPathPlan.init(
            room,
            48_000,
            343.0,
            head.position,
            head,
        ),
    );

    var malformed = try FirstOrderRoomPathPlan.init(
        room,
        48_000,
        343.0,
        source,
        head,
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        (try malformed.items()).len,
    );
    malformed.path_count = maximum_first_order_room_paths + 1;
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        malformed.items(),
    );
    malformed.path_count = 1;
    malformed.path_storage[0].gain = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        malformed.items(),
    );
}

test "HRTF second-order room plan covers the image lattice" {
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 4.0, .y = 4.0, .z = 4.0 },
        .absorption = .{
            .minimum_x = 0.0,
            .maximum_x = 0.0,
            .minimum_y = 0.0,
            .maximum_y = 0.0,
            .minimum_z = 0.0,
            .maximum_z = 0.0,
        },
    };
    const source = Position{ .x = 1.0, .y = 2.0, .z = 2.0 };
    const head = HeadPose{
        .position = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
    };
    const plan = try SecondOrderRoomPathPlan.init(
        room,
        48_000,
        300.0,
        source,
        head,
    );
    const paths = try plan.items();
    try std.testing.expectEqual(
        maximum_second_order_room_paths,
        paths.len,
    );
    try std.testing.expectEqualDeep(
        Direction{ .azimuth_degrees = 180.0, .elevation_degrees = 0.0 },
        paths[7].direction,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / 9.0),
        paths[7].gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1_280.0),
        paths[7].additional_delay_samples,
        1.0e-9,
    );
    try std.testing.expectEqualDeep(
        Direction{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        paths[8].direction,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / 7.0),
        paths[8].gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 960.0),
        paths[8].additional_delay_samples,
        1.0e-9,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -126.869_897_645_844_02),
        paths[13].direction.azimuth_degrees,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.2),
        paths[13].gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 640.0),
        paths[13].additional_delay_samples,
        1.0e-9,
    );
}

test "HRTF second-order room plan multiplies surface reflections" {
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 4.0, .y = 4.0, .z = 4.0 },
        .absorption = .{
            .minimum_x = 0.75,
            .maximum_x = 0.36,
        },
    };
    var plan = try SecondOrderRoomPathPlan.init(
        room,
        48_000,
        300.0,
        .{ .x = 1.0, .y = 2.0, .z = 2.0 },
        .{
            .position = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
        },
    );
    const paths = try plan.items();
    try std.testing.expectEqual(@as(usize, 5), paths.len);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.4 / 9.0),
        paths[3].gain,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.4 / 7.0),
        paths[4].gain,
        1.0e-12,
    );

    plan.path_count = maximum_second_order_room_paths + 1;
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        plan.items(),
    );
    plan.path_count = 5;
    plan.path_storage[4].additional_delay_samples = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        plan.items(),
    );
}

test "HRTF bounded image-source plan covers higher reflection orders" {
    try std.testing.expectEqual(
        @as(usize, 1),
        roomPathCapacityForOrder(0),
    );
    try std.testing.expectEqual(
        maximum_first_order_room_paths,
        roomPathCapacityForOrder(1),
    );
    try std.testing.expectEqual(
        maximum_second_order_room_paths,
        roomPathCapacityForOrder(2),
    );
    try std.testing.expectEqual(
        @as(usize, 63),
        roomPathCapacityForOrder(3),
    );
    try std.testing.expectEqual(
        @as(usize, 833),
        roomPathCapacityForOrder(maximum_supported_room_reflection_order),
    );

    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 4.0, .y = 4.0, .z = 4.0 },
        .absorption = .{
            .minimum_x = 0.0,
            .maximum_x = 0.0,
            .minimum_y = 0.0,
            .maximum_y = 0.0,
            .minimum_z = 0.0,
            .maximum_z = 0.0,
        },
    };
    const source = Position{ .x = 1.0, .y = 2.0, .z = 2.0 };
    const head = HeadPose{
        .position = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
    };
    const ThirdOrder = ImageSourceRoomPathPlan(3);
    const plan = try ThirdOrder.init(
        room,
        48_000,
        300.0,
        source,
        head,
    );
    const paths = try plan.items();
    try std.testing.expectEqual(@as(usize, 63), paths.len);

    var found_axial = false;
    var found_two_axis = false;
    var found_three_axis = false;
    const two_axis_distance = @sqrt(@as(f64, 65.0));
    const three_axis_distance = @sqrt(@as(f64, 57.0));
    for (paths) |path| {
        if (@abs(path.additional_delay_samples - 1_920.0) <= 1.0e-9 and
            @abs(path.direction.azimuth_degrees) <= 1.0e-12 and
            @abs(path.direction.elevation_degrees) <= 1.0e-12)
        {
            try std.testing.expectApproxEqAbs(
                @as(f64, 1.0 / 13.0),
                path.gain,
                1.0e-12,
            );
            found_axial = true;
        }
        if (@abs(
            path.additional_delay_samples -
                (two_axis_distance - 1.0) * 160.0,
        ) <= 1.0e-9 and
            @abs(
                path.direction.azimuth_degrees -
                    29.744_881_296_942_22,
            ) <= 1.0e-12 and
            @abs(path.direction.elevation_degrees) <= 1.0e-12)
        {
            try std.testing.expectApproxEqAbs(
                1.0 / two_axis_distance,
                path.gain,
                1.0e-12,
            );
            found_two_axis = true;
        }
        if (@abs(
            path.additional_delay_samples -
                (three_axis_distance - 1.0) * 160.0,
        ) <= 1.0e-9 and
            @abs(
                path.direction.azimuth_degrees -
                    38.659_808_254_090_095,
            ) <= 1.0e-12)
        {
            try std.testing.expectApproxEqAbs(
                1.0 / three_axis_distance,
                path.gain,
                1.0e-12,
            );
            found_three_axis = true;
        }
    }
    try std.testing.expect(found_axial);
    try std.testing.expect(found_two_axis);
    try std.testing.expect(found_three_axis);

    const EighthOrder = ImageSourceRoomPathPlan(8);
    const full_eighth_order = try EighthOrder.init(
        room,
        48_000,
        300.0,
        source,
        head,
    );
    try std.testing.expectEqual(
        @as(usize, 833),
        (try full_eighth_order.items()).len,
    );

    const DirectOnly = ImageSourceRoomPathPlan(0);
    const direct_only = try DirectOnly.init(
        .{
            .minimum = .{ .x = -1.0e154, .y = -1.0, .z = -1.0 },
            .maximum = .{ .x = 1.0e154, .y = 1.0, .z = 1.0 },
            .absorption = .{ .minimum_x = 0.0 },
        },
        48_000,
        300.0,
        .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .{
            .position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        },
    );
    try std.testing.expectEqual(@as(usize, 1), (try direct_only.items()).len);
    try std.testing.expectError(
        error.InvalidHrtfRoomGeometry,
        ImageSourceRoomPathPlan(1).init(
            .{
                .minimum = .{ .x = -1.0e154, .y = -1.0, .z = -1.0 },
                .maximum = .{ .x = 1.0e154, .y = 1.0, .z = 1.0 },
                .absorption = .{ .minimum_x = 0.0 },
            },
            48_000,
            300.0,
            .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .{
                .position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            },
        ),
    );
    var absorbed = try EighthOrder.init(
        .{
            .minimum = room.minimum,
            .maximum = room.maximum,
        },
        48_000,
        300.0,
        source,
        head,
    );
    try std.testing.expectEqual(@as(usize, 1), (try absorbed.items()).len);
    absorbed.path_count = EighthOrder.maximum_path_count + 1;
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        absorbed.items(),
    );
    absorbed.path_count = 1;
    absorbed.image_index_storage[0] = .{ 1, 0, 0 };
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        absorbed.imageIndices(),
    );
}

test "HRTF higher-order room plan multiplies repeated surfaces" {
    const ThirdOrder = ImageSourceRoomPathPlan(3);
    const plan = try ThirdOrder.init(
        .{
            .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            .maximum = .{ .x = 4.0, .y = 4.0, .z = 4.0 },
            .absorption = .{
                .minimum_x = 0.75,
                .maximum_x = 0.36,
            },
        },
        48_000,
        300.0,
        .{ .x = 1.0, .y = 2.0, .z = 2.0 },
        .{
            .position = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
        },
    );
    const paths = try plan.items();
    try std.testing.expectEqual(@as(usize, 7), paths.len);

    var found_minimum = false;
    var found_maximum = false;
    for (paths) |path| {
        if (@abs(path.additional_delay_samples - 1_600.0) <= 1.0e-9) {
            try std.testing.expectApproxEqAbs(
                @as(f64, 0.2 / 11.0),
                path.gain,
                1.0e-12,
            );
            found_minimum = true;
        }
        if (@abs(path.additional_delay_samples - 1_920.0) <= 1.0e-9) {
            try std.testing.expectApproxEqAbs(
                @as(f64, 0.32 / 13.0),
                path.gain,
                1.0e-12,
            );
            found_maximum = true;
        }
    }
    try std.testing.expect(found_minimum);
    try std.testing.expect(found_maximum);
}

test "HRTF room assets bind constructed path and response shapes" {
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 4.0, .y = 4.0, .z = 4.0 },
        .absorption = .{
            .minimum_x = 0.0,
            .maximum_x = 0.0,
            .minimum_y = 0.0,
            .maximum_y = 0.0,
            .minimum_z = 0.0,
            .maximum_z = 0.0,
        },
    };
    const source = Position{ .x = 1.0, .y = 2.0, .z = 2.0 };
    const head = HeadPose{
        .position = .{ .x = 2.0, .y = 2.0, .z = 2.0 },
    };

    var first = try FirstOrderRoomPathPlan.init(
        room,
        48_000,
        343.0,
        source,
        head,
    );
    first.path_count -= 1;
    try std.testing.expect(!first.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        first.items(),
    );
    first.path_count = first.declared_path_count;
    try std.testing.expect(first.valid());

    var second = try SecondOrderRoomPathPlan.init(
        room,
        48_000,
        343.0,
        source,
        head,
    );
    second.path_count -= 1;
    try std.testing.expect(!second.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        second.items(),
    );
    second.path_count = second.declared_path_count;
    try std.testing.expect(second.valid());

    var image_source = try ImageSourceRoomPathPlan(2).init(
        room,
        48_000,
        343.0,
        source,
        head,
    );
    image_source.path_count -= 1;
    try std.testing.expect(!image_source.valid());
    try std.testing.expectError(
        error.InvalidHrtfRoomPathPlanState,
        image_source.imageIndices(),
    );
    image_source.path_count = image_source.declared_path_count;
    try std.testing.expect(image_source.valid());

    const Materials = RoomSurfaceImpulseResponses(2);
    const delta = [_]f32{1.0};
    var materials = try Materials.init(8_000, .{
        .minimum_x = &.{ 1.0, 0.5 },
        .maximum_x = &delta,
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    materials.frame_counts[0] = 1;
    try std.testing.expect(!materials.valid());
    materials.frame_counts = materials.declared_frame_counts;
    materials.sample_rate = 16_000;
    try std.testing.expect(!materials.valid());
    materials.sample_rate = materials.declared_sample_rate;
    try std.testing.expect(materials.valid());
}

test "HRTF room response rejects invalid policy transactionally" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(1, 1);
    const database = try Db.init(48_000, &.{direction}, &.{ 1.0, 1.0 });
    const Composer = RoomResponseComposer(3, 2);
    var composer = Composer{};
    var destination = [_]f32{17.0} ** 6;

    try std.testing.expectError(
        error.InvalidHrtfRoomPathCount,
        composer.compose(&database, &.{}, .nearest, &destination),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomPathCount,
        composer.compose(
            &database,
            &.{ .{ .direction = direction }, .{ .direction = direction }, .{ .direction = direction } },
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomPathGain,
        composer.compose(
            &database,
            &.{.{ .direction = direction, .gain = std.math.inf(f64) }},
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomPathDelay,
        composer.compose(
            &database,
            &.{.{
                .direction = direction,
                .additional_delay_samples = -0.5,
            }},
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfDirection,
        composer.compose(
            &database,
            &.{.{
                .direction = .{
                    .azimuth_degrees = std.math.nan(f64),
                    .elevation_degrees = 0.0,
                },
            }},
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectError(
        error.HrtfFrameCapacityExceeded,
        composer.compose(
            &database,
            &.{.{
                .direction = direction,
                .additional_delay_samples = 3.0,
            }},
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfDestinationShape,
        composer.compose(
            &database,
            &.{.{ .direction = direction }},
            .nearest,
            destination[0..1],
        ),
    );
    try std.testing.expectError(
        error.InvalidHrtfRoomResponse,
        composer.compose(
            &database,
            &.{.{
                .direction = direction,
                .gain = std.math.floatMax(f64),
            }},
            .nearest,
            &destination,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{17.0} ** 6, destination);

    const frame_count = try composer.compose(
        &database,
        &.{.{ .direction = direction }},
        .nearest,
        &destination,
    );
    try std.testing.expectEqual(@as(usize, 1), frame_count);
    try std.testing.expectEqualDeep([_]f32{ 1.0, 1.0 }, destination[0..2].*);

    const internal_before = composer.path_response;
    try std.testing.expectError(
        error.OverlappingHrtfRoomResponseStorage,
        composer.compose(
            &database,
            &.{.{ .direction = direction }},
            .nearest,
            composer.path_response[1..],
        ),
    );
    try std.testing.expectEqualDeep(internal_before, composer.path_response);

    var renderer = try Renderer(8, 8).init(48_000, .zero);
    try std.testing.expectError(
        error.InvalidHrtfResponseShape,
        renderer.prepareInterleavedResponse(48_000, &.{1.0}, 1),
    );
    try std.testing.expectError(
        error.NonFiniteSample,
        renderer.prepareInterleavedResponse(
            48_000,
            &.{ std.math.nan(f32), 0.0 },
            1,
        ),
    );
    try std.testing.expect(renderer.activeGeneration() == null);
    try renderer.prepareInterleavedResponse(48_000, &.{ 1.0, 1.0 }, 1);
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expectEqual(@as(?u64, 1), renderer.activeGeneration());
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
    try std.testing.expect(renderer.valid());
    try renderer.prepare(
        &database,
        directions[0],
        .nearest,
        1,
    );
    try std.testing.expect(renderer.valid());
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expect(renderer.valid());
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
    try std.testing.expect(renderer.valid());
    renderer.convolver.output_index = HrtfRenderer.latency_capacity;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        renderer.processSample(1.0),
    );
    renderer.reset();
    try std.testing.expect(renderer.valid());
    try std.testing.expect(
        try renderer.reprepareForSampleRate(96_000),
    );
    try std.testing.expect(renderer.adoptPending());
    try std.testing.expect(renderer.valid());
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
    try std.testing.expect(renderer.valid());
    try renderer.prepare(
        &database,
        &points,
        .nearest,
        4,
    );
    try std.testing.expect(renderer.valid());
    try std.testing.expectEqual(
        directions[0],
        renderer.currentDirection().?,
    );
    var truncated_plan = renderer;
    truncated_plan.point_count = 1;
    try std.testing.expect(!truncated_plan.valid());
    const truncated_history = truncated_plan.history;
    const truncated_sample = truncated_plan.sample_position;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        truncated_plan.processSample(1.0),
    );
    try std.testing.expectEqualDeep(truncated_history, truncated_plan.history);
    try std.testing.expectEqual(truncated_sample, truncated_plan.sample_position);

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
    try std.testing.expect(renderer.valid());

    var hostile_cursor = renderer;
    hostile_cursor.current_point = hostile_cursor.point_count;
    try std.testing.expect(!hostile_cursor.valid());
    const cursor_history = hostile_cursor.history;
    const cursor_sample = hostile_cursor.sample_position;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        hostile_cursor.processSample(1.0),
    );
    try std.testing.expectEqual(cursor_sample, hostile_cursor.sample_position);
    try std.testing.expectEqualDeep(cursor_history, hostile_cursor.history);

    var early_cursor = renderer;
    early_cursor.sample_position =
        early_cursor.points[early_cursor.current_point].sample_position - 1;
    try std.testing.expect(!early_cursor.valid());
    const early_history = early_cursor.history;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        early_cursor.processSample(1.0),
    );
    try std.testing.expectEqualDeep(early_history, early_cursor.history);

    var overdue_cursor = renderer;
    overdue_cursor.current_point = 0;
    overdue_cursor.sample_position =
        overdue_cursor.points[1].sample_position +
        overdue_cursor.crossfade_samples;
    try std.testing.expect(!overdue_cursor.valid());
    const overdue_history = overdue_cursor.history;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        overdue_cursor.processSample(1.0),
    );
    try std.testing.expectEqualDeep(overdue_history, overdue_cursor.history);

    var hostile_filter = renderer;
    hostile_filter.filters[hostile_filter.current_point][0][0] =
        std.math.nan(f32);
    try std.testing.expect(!hostile_filter.valid());
    const filter_history = hostile_filter.history;
    const filter_sample = hostile_filter.sample_position;
    try std.testing.expectEqualDeep(
        [_]f32{ 0.0, 0.0 },
        hostile_filter.processSample(1.0),
    );
    try std.testing.expectEqual(filter_sample, hostile_filter.sample_position);
    try std.testing.expectEqualDeep(filter_history, hostile_filter.history);

    const original_direction = renderer.currentDirection();
    var invalid = points;
    invalid[1].sample_position = 2;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, &invalid, .nearest, 4),
    );
    invalid[1].sample_position = std.math.maxInt(u64) - 1;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, &invalid, .nearest, 4),
    );
    try std.testing.expectEqual(
        original_direction,
        renderer.currentDirection(),
    );
    renderer.reset();
    try std.testing.expect(renderer.valid());
}

test "HRTF static motion and room rendering select measured distance" {
    const direction = Direction{};
    const Db = Database(2, 1);
    const database = try Db.initWithDistances(
        48_000,
        &.{ direction, direction },
        &.{ 0.5, 1.5 },
        &.{ 0.25, 0.5, 0.75, 1.0 },
    );
    const measured = try measurementFromPositions(
        .{ .x = 1.5, .y = 0.0, .z = 0.0 },
        .{},
    );
    try std.testing.expectEqual(direction, measured.direction);
    try std.testing.expectEqual(@as(f64, 1.5), measured.distance_metres);

    const Static = Renderer(1, 8);
    var static = try Static.init(48_000, .zero);
    try static.prepareAt(&database, measured, .nearest, 1);
    try std.testing.expect(static.adoptPending());
    try std.testing.expectEqualDeep(
        [_]f32{ 0.75, 1.0 },
        static.processSample(1.0),
    );

    const Moving = MotionRenderer(1, 1, 2);
    var moving = Moving{};
    try moving.prepare(
        &database,
        &.{.{
            .source_position = .{ .x = 1.5, .y = 0.0, .z = 0.0 },
        }},
        .nearest,
        2,
    );
    try std.testing.expectEqualDeep(
        [_]f32{ 0.75, 1.0 },
        moving.processSample(1.0),
    );

    const Composer = RoomResponseComposer(1, 1);
    var composer = Composer{};
    var response: [2]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 1),
        try composer.compose(
            &database,
            &.{.{
                .direction = direction,
                .distance_metres = 0.5,
            }},
            .nearest,
            &response,
        ),
    );
    try std.testing.expectEqualDeep([_]f32{ 0.25, 0.5 }, response);
}

test "HRTF motion schedule crossfades first-order room responses" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{direction},
        &.{ 1.0, 1.0 },
    );
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 0.02, .y = 0.02, .z = 0.02 },
        .absorption = .{
            .minimum_x = 0.75,
            .maximum_x = 0.75,
        },
    };
    const points = [_]MotionPoint{
        .{
            .sample_position = 0,
            .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.008, .y = 0.01, .z = 0.01 },
            },
        },
        .{
            .sample_position = 8,
            .source_position = .{ .x = 0.004, .y = 0.01, .z = 0.01 },
            .head_pose = .{
                .position = .{ .x = 0.008, .y = 0.01, .z = 0.01 },
            },
        },
    };
    const Moving = MotionRenderer(8, 2, 2);
    var renderer = Moving{};
    try renderer.prepareRoom(
        &database,
        room,
        343.0,
        &points,
        .nearest,
        2,
    );
    try std.testing.expectEqual(
        Direction{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
        renderer.currentDirection().?,
    );

    var left_sum: f32 = 0.0;
    var right_sum: f32 = 0.0;
    for (0..5) |sample_index| {
        const output = renderer.processSample(
            if (sample_index == 0) 1.0 else 0.0,
        );
        left_sum += output[0];
        right_sum += output[1];
    }
    const expected_sum: f32 = @floatCast(
        1.0 + 0.5 * 0.006 / 0.022 + 0.5 * 0.006 / 0.018,
    );
    try std.testing.expectApproxEqAbs(expected_sum, left_sum, 0.000_001);
    try std.testing.expectApproxEqAbs(expected_sum, right_sum, 0.000_001);

    const expected_second_sum: f32 = @floatCast(
        1.0 + 0.5 * 0.004 / 0.012 + 0.5 * 0.004 / 0.028,
    );
    renderer.reset();
    var transition_output: [10][2]f32 = undefined;
    for (&transition_output) |*output| {
        output.* = renderer.processSample(1.0);
    }
    try std.testing.expectApproxEqAbs(
        expected_sum,
        transition_output[7][0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        (expected_sum + expected_second_sum) * 0.5,
        transition_output[8][0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        expected_second_sum,
        transition_output[9][0],
        0.000_001,
    );
    for (7..10) |sample_index| {
        try std.testing.expectApproxEqAbs(
            transition_output[sample_index][0],
            transition_output[sample_index][1],
            0.000_001,
        );
    }
    try std.testing.expectEqual(
        Direction{ .azimuth_degrees = 180.0, .elevation_degrees = 0.0 },
        renderer.currentDirection().?,
    );

    var invalid = points;
    invalid[1].source_position.x = room.maximum.x;
    const original_direction = renderer.currentDirection();
    try std.testing.expectError(
        error.HrtfRoomPositionOutsideBounds,
        renderer.prepareRoom(
            &database,
            room,
            343.0,
            &invalid,
            .nearest,
            2,
        ),
    );
    try std.testing.expectEqual(
        original_direction,
        renderer.currentDirection(),
    );

    var too_small = MotionRenderer(2, 2, 2){};
    try std.testing.expectError(
        error.HrtfFrameCapacityExceeded,
        too_small.prepareRoom(
            &database,
            room,
            343.0,
            &points,
            .nearest,
            2,
        ),
    );
    try std.testing.expect(too_small.currentDirection() == null);
}

test "HRTF motion renderer prepares second-order room responses" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const Db = Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{direction},
        &.{ 1.0, 1.0 },
    );
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 0.02, .y = 0.02, .z = 0.02 },
        .absorption = .{
            .minimum_x = 0.75,
            .maximum_x = 0.75,
        },
    };
    const point = MotionPoint{
        .sample_position = 0,
        .source_position = .{ .x = 0.014, .y = 0.01, .z = 0.01 },
        .head_pose = .{
            .position = .{ .x = 0.008, .y = 0.01, .z = 0.01 },
        },
    };
    var renderer = MotionRenderer(8, 1, 2){};
    try renderer.prepareSecondOrderRoom(
        &database,
        room,
        343.0,
        &.{point},
        .nearest,
        2,
    );

    var sum: [2]f32 = @splat(0.0);
    for (0..7) |sample_index| {
        const output = renderer.processSample(
            if (sample_index == 0) 1.0 else 0.0,
        );
        sum[0] += output[0];
        sum[1] += output[1];
    }
    const expected: f32 = @floatCast(
        1.0 +
            0.5 * 0.006 / 0.022 +
            0.5 * 0.006 / 0.018 +
            0.25 * 0.006 / 0.034 +
            0.25 * 0.006 / 0.046,
    );
    try std.testing.expectApproxEqAbs(expected, sum[0], 0.000_001);
    try std.testing.expectApproxEqAbs(expected, sum[1], 0.000_001);
    try std.testing.expectEqual(direction, renderer.currentDirection().?);

    var higher_order = MotionRenderer(16, 1, 2){};
    try higher_order.prepareImageSourceRoom(
        3,
        &database,
        room,
        343.0,
        &.{point},
        .nearest,
        2,
    );
    var higher_order_sum: [2]f32 = @splat(0.0);
    for (0..9) |sample_index| {
        const output = higher_order.processSample(
            if (sample_index == 0) 1.0 else 0.0,
        );
        higher_order_sum[0] += output[0];
        higher_order_sum[1] += output[1];
    }
    const higher_order_expected: f32 = @floatCast(
        @as(f64, expected) +
            0.125 * 0.006 / 0.062 +
            0.125 * 0.006 / 0.058,
    );
    try std.testing.expectApproxEqAbs(
        higher_order_expected,
        higher_order_sum[0],
        0.000_001,
    );
    try std.testing.expectApproxEqAbs(
        higher_order_expected,
        higher_order_sum[1],
        0.000_001,
    );
}

test "HRTF motion renderer prepares frequency-dependent room responses" {
    const direction = Direction{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
    };
    const database = try Database(1, 1).init(
        8_000,
        &.{direction},
        &.{ 1.0, 1.0 },
    );
    const room = ShoeboxRoom{
        .minimum = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .maximum = .{ .x = 10.0, .y = 2.0, .z = 2.0 },
        .absorption = .{ .maximum_x = 0.0 },
    };
    const delta = [_]f32{1.0};
    var materials = try RoomSurfaceImpulseResponses(2).init(8_000, .{
        .minimum_x = &delta,
        .maximum_x = &.{ 0.5, 0.5 },
        .minimum_y = &delta,
        .maximum_y = &delta,
        .minimum_z = &delta,
        .maximum_z = &delta,
    });
    var renderer = MotionRenderer(8, 1, 2){};
    try renderer.prepareFrequencyDependentImageSourceRoom(
        1,
        2,
        &database,
        room,
        &materials,
        8_000.0,
        &.{.{
            .sample_position = 0,
            .source_position = .{ .x = 7.0, .y = 1.0, .z = 1.0 },
            .head_pose = .{
                .position = .{ .x = 5.0, .y = 1.0, .z = 1.0 },
            },
        }},
        .nearest,
        2,
    );

    var rendered: [8][2]f32 = undefined;
    for (&rendered, 0..) |*output, sample_index| {
        output.* = renderer.processSample(
            if (sample_index == 0) 1.0 else 0.0,
        );
    }
    try std.testing.expectEqualDeep(
        [_][2]f32{
            .{ 1.0, 1.0 },
            .{ 0.0, 0.0 },
            .{ 0.0, 0.0 },
            .{ 0.0, 0.0 },
            .{ 0.0, 0.0 },
            .{ 0.0, 0.0 },
            .{ 0.125, 0.125 },
            .{ 0.125, 0.125 },
        },
        rendered,
    );

    const retained_direction = renderer.currentDirection();
    materials.frame_counts[1] = 0;
    try std.testing.expectError(
        error.InvalidHrtfRoomSurfaceResponseState,
        renderer.prepareFrequencyDependentImageSourceRoom(
            1,
            2,
            &database,
            room,
            &materials,
            8_000.0,
            &.{.{
                .sample_position = 0,
                .source_position = .{ .x = 7.0, .y = 1.0, .z = 1.0 },
                .head_pose = .{
                    .position = .{ .x = 5.0, .y = 1.0, .z = 1.0 },
                },
            }},
            .nearest,
            2,
        ),
    );
    try std.testing.expectEqual(retained_direction, renderer.currentDirection());
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

    var retained = try Db.init(48_000, &one, &.{ 1.0, 1.0 });
    const retained_before = retained;
    try std.testing.expectError(
        error.EmptyHrtfResponse,
        Db.initInto(&retained, 48_000, &one, &.{ 0.0, 0.0 }),
    );
    try std.testing.expectEqualDeep(retained_before, retained);
    try std.testing.expectError(
        error.OverlappingHrtfDatabaseStorage,
        Db.initInto(
            &retained,
            48_000,
            retained.directions[0..1],
            &.{ 0.5, 0.25 },
        ),
    );
    try std.testing.expectEqualDeep(retained_before, retained);
    try Db.initWithDelaysInto(
        &retained,
        48_000,
        &one,
        &.{ 0.5, 0.25 },
        &.{ 0.0, 0.0 },
    );
    try std.testing.expectEqual(@as(f32, 0.5), retained.responses[0][0][0]);

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
