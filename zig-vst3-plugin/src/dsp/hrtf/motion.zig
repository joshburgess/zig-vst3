const std = @import("std");
const spatial = @import("spatial.zig");

const Position = spatial.Position;
const HeadPose = spatial.HeadPose;
const directionFromPositions = spatial.directionFromPositions;

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
