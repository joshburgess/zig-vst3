const hrtf = @import("hrtf.zig");
const std = @import("std");

/// Prepares tracked HRTF filters on one thread and renders on another.
pub fn Renderer(
    comptime maximum_frames: usize,
    comptime queue_capacity: usize,
    comptime maximum_crossfade_samples: usize,
) type {
    if (maximum_frames == 0)
        @compileError("streaming HRTF rendering requires frame capacity");
    if (queue_capacity < 2)
        @compileError("streaming HRTF rendering requires two queue slots");
    if (maximum_crossfade_samples == 0)
        @compileError("streaming HRTF rendering requires crossfade capacity");

    return struct {
        const Self = @This();
        const Slot = struct {
            point: hrtf.MotionPoint = .{},
            direction: hrtf.Direction = .{},
            sample_rate: u32 = 0,
            frame_count: usize = 0,
            declared_frame_count: usize = 0,
            filters: [maximum_frames][2]f32 =
                @splat(@splat(0.0)),
        };

        slots: [queue_capacity]Slot = @splat(.{}),
        write_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        read_index: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        dropped_count: std.atomic.Value(usize) =
            std.atomic.Value(usize).init(0),
        start_sample_position: u64,
        crossfade_samples: usize,
        declared_start_sample_position: u64,
        declared_crossfade_samples: usize,
        producer_sample_rate: u32 = 0,
        last_submitted_sample: u64 = 0,
        has_submitted_sample: bool = false,
        history: [maximum_frames]f32 = @splat(0.0),
        history_write: usize = 0,
        sample_position: u64,
        has_active_filter: bool = false,
        startup_fade_active: bool = false,
        transition_active: bool = false,
        transition_start: u64 = 0,

        pub fn init(
            start_sample_position: u64,
            crossfade_samples: usize,
        ) !Self {
            if (crossfade_samples == 0 or
                crossfade_samples > maximum_crossfade_samples)
            {
                return error.InvalidHrtfCrossfade;
            }
            return .{
                .start_sample_position = start_sample_position,
                .crossfade_samples = crossfade_samples,
                .declared_start_sample_position = start_sample_position,
                .declared_crossfade_samples = crossfade_samples,
                .sample_position = start_sample_position,
            };
        }

        /// Query complete state only while producer and audio threads are stopped.
        pub fn valid(self: *const Self) bool {
            self.validateQuiescent() catch return false;
            return true;
        }

        pub fn prepare(
            self: *Self,
            database: anytype,
            point: hrtf.MotionPoint,
            interpolation: hrtf.Interpolation,
        ) !bool {
            try self.validateProducer();
            if (!database.valid()) return error.InvalidHrtfDatabase;
            if (database.frame_count > maximum_frames)
                return error.HrtfFrameCapacityExceeded;
            if (point.sample_position < self.start_sample_position)
                return error.InvalidHrtfMotionSchedule;
            _ = self.transitionResumePosition(
                point.sample_position,
            ) catch return error.InvalidHrtfMotionSchedule;
            const position = try hrtf.measurementFromPositions(
                point.source_position,
                point.head_pose,
            );
            const direction = position.direction;
            if (self.has_submitted_sample and
                (point.sample_position <= self.last_submitted_sample or
                    point.sample_position - self.last_submitted_sample <
                        self.crossfade_samples))
            {
                return error.InvalidHrtfMotionSchedule;
            }
            if (self.producer_sample_rate != 0 and
                database.sample_rate != self.producer_sample_rate)
            {
                return error.HrtfMotionSampleRateChanged;
            }

            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > queue_capacity)
                return error.InvalidHrtfStreamingRendererState;
            if (pending_count == queue_capacity) {
                self.recordDrop();
                return false;
            }

            const slot = &self.slots[write % queue_capacity];
            const destination = @as(
                [*]f32,
                @ptrCast(&slot.filters),
            )[0 .. database.frame_count * 2];
            try database.interpolateAt(
                position,
                interpolation,
                destination,
            );
            if (database.frame_count < maximum_frames) {
                @memset(
                    slot.filters[database.frame_count..maximum_frames],
                    @splat(0.0),
                );
            }
            slot.point = point;
            slot.direction = direction;
            slot.sample_rate = database.sample_rate;
            slot.frame_count = database.frame_count;
            slot.declared_frame_count = database.frame_count;
            if (self.producer_sample_rate == 0)
                self.producer_sample_rate = database.sample_rate;
            self.last_submitted_sample = point.sample_position;
            self.has_submitted_sample = true;
            self.write_index.store(write +% 1, .release);
            return true;
        }

        pub fn processSample(self: *Self, input: f32) ![2]f32 {
            const pending_count = try self.validateConsumer();
            if (self.sample_position == std.math.maxInt(u64))
                return error.HrtfMotionSamplePositionOverflow;

            self.history[self.history_write] =
                if (std.math.isFinite(input)) input else 0.0;
            const read = self.read_index.load(.monotonic);
            if (!self.has_active_filter and pending_count != 0) {
                const first = &self.slots[read % queue_capacity];
                if (self.sample_position >= first.point.sample_position) {
                    self.has_active_filter = true;
                    self.startup_fade_active = true;
                    self.transition_start = self.sample_position;
                }
            }

            var output: [2]f32 = @splat(0.0);
            if (self.has_active_filter) {
                const current = &self.slots[read % queue_capacity];
                const current_output = self.filtered(current);
                if (self.startup_fade_active) {
                    const progress = self.crossfadeProgress();
                    output = scale(current_output, progress);
                    if (progress >= 1.0)
                        self.startup_fade_active = false;
                } else {
                    if (!self.transition_active and pending_count >= 2) {
                        const next = &self.slots[
                            (read +% 1) % queue_capacity
                        ];
                        if (self.sample_position >=
                            next.point.sample_position)
                        {
                            self.transition_active = true;
                            self.transition_start = self.sample_position;
                        }
                    }
                    if (self.transition_active) {
                        const next = &self.slots[
                            (read +% 1) % queue_capacity
                        ];
                        const progress = self.crossfadeProgress();
                        output = blend(
                            current_output,
                            self.filtered(next),
                            progress,
                        );
                        if (progress >= 1.0) {
                            self.slots[read % queue_capacity] = .{};
                            self.read_index.store(read +% 1, .release);
                            self.transition_active = false;
                        }
                    } else {
                        output = current_output;
                    }
                }
            }

            self.history_write =
                (self.history_write + 1) % maximum_frames;
            self.sample_position += 1;
            return output;
        }

        pub fn preparedCount(self: *const Self) !usize {
            const read = self.read_index.load(.acquire);
            const write = self.write_index.load(.acquire);
            const count = write -% read;
            if (count > queue_capacity)
                return error.InvalidHrtfStreamingRendererState;
            return count;
        }

        pub fn dropped(self: *const Self) usize {
            return self.dropped_count.load(.acquire);
        }

        pub fn currentDirection(self: *const Self) !?hrtf.Direction {
            const pending_count = try self.preparedCount();
            if (!self.has_active_filter) return null;
            if (pending_count == 0)
                return error.InvalidHrtfStreamingRendererState;
            const read = self.read_index.load(.acquire);
            return self.slots[read % queue_capacity].direction;
        }

        /// Reset is only valid while producer and audio threads are stopped.
        pub fn reset(self: *Self, sample_position: u64) void {
            @memset(&self.slots, .{});
            self.write_index.store(0, .release);
            self.read_index.store(0, .release);
            self.dropped_count.store(0, .release);
            self.start_sample_position = sample_position;
            self.declared_start_sample_position = sample_position;
            self.producer_sample_rate = 0;
            self.last_submitted_sample = 0;
            self.has_submitted_sample = false;
            @memset(&self.history, 0.0);
            self.history_write = 0;
            self.sample_position = sample_position;
            self.has_active_filter = false;
            self.startup_fade_active = false;
            self.transition_active = false;
            self.transition_start = 0;
        }

        fn validateProducer(self: *const Self) !void {
            if (self.crossfade_samples == 0 or
                self.crossfade_samples > maximum_crossfade_samples or
                self.crossfade_samples != self.declared_crossfade_samples or
                self.start_sample_position !=
                    self.declared_start_sample_position or
                (self.producer_sample_rate != 0 and
                    (self.producer_sample_rate < 8_000 or
                        self.producer_sample_rate > 384_000)) or
                (self.has_submitted_sample and
                    self.last_submitted_sample < self.start_sample_position) or
                (self.has_submitted_sample and
                    self.producer_sample_rate == 0) or
                (!self.has_submitted_sample and
                    self.producer_sample_rate != 0))
            {
                return error.InvalidHrtfStreamingRendererState;
            }
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > queue_capacity)
                return error.InvalidHrtfStreamingRendererState;
            if (!self.has_submitted_sample) {
                if (self.last_submitted_sample != 0 or pending_count != 0)
                    return error.InvalidHrtfStreamingRendererState;
                return;
            }
            _ = self.transitionResumePosition(
                self.last_submitted_sample,
            ) catch return error.InvalidHrtfStreamingRendererState;
            if (pending_count == 0)
                return error.InvalidHrtfStreamingRendererState;
            const latest = &self.slots[(write -% 1) % queue_capacity];
            try validateSlot(latest, self.producer_sample_rate);
            if (latest.point.sample_position != self.last_submitted_sample or
                latest.point.sample_position < self.start_sample_position)
            {
                return error.InvalidHrtfStreamingRendererState;
            }
        }

        fn validateConsumer(self: *const Self) !usize {
            if (self.crossfade_samples == 0 or
                self.crossfade_samples > maximum_crossfade_samples or
                self.crossfade_samples != self.declared_crossfade_samples or
                self.start_sample_position !=
                    self.declared_start_sample_position or
                self.history_write >= maximum_frames or
                self.sample_position < self.start_sample_position or
                ((self.startup_fade_active or self.transition_active) and
                    !self.has_active_filter) or
                (self.startup_fade_active and self.transition_active))
            {
                return error.InvalidHrtfStreamingRendererState;
            }
            for (self.history) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidHrtfStreamingRendererState;
            }
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            const pending_count = write -% read;
            if (pending_count > queue_capacity or
                (self.has_active_filter and pending_count == 0) or
                (self.transition_active and pending_count < 2))
            {
                return error.InvalidHrtfStreamingRendererState;
            }
            if (self.startup_fade_active or self.transition_active) {
                const transition_resume = self.transitionResumePosition(
                    self.transition_start,
                ) catch return error.InvalidHrtfStreamingRendererState;
                if (self.transition_start >= self.sample_position or
                    self.sample_position >= transition_resume)
                {
                    return error.InvalidHrtfStreamingRendererState;
                }
            }
            try self.validatePendingSlots(read, pending_count);
            if (pending_count != 0 and self.has_active_filter) {
                const current = &self.slots[read % queue_capacity];
                if (self.sample_position < current.point.sample_position)
                    return error.InvalidHrtfStreamingRendererState;
                if (self.startup_fade_active and
                    self.transition_start < current.point.sample_position)
                {
                    return error.InvalidHrtfStreamingRendererState;
                }
            }
            if (self.transition_active) {
                const next = &self.slots[(read +% 1) % queue_capacity];
                if (self.sample_position < next.point.sample_position or
                    self.transition_start < next.point.sample_position)
                {
                    return error.InvalidHrtfStreamingRendererState;
                }
            }
            if (!self.has_active_filter and pending_count != 0) {
                const first = &self.slots[read % queue_capacity];
                if (self.sample_position >= first.point.sample_position) {
                    _ = self.transitionResumePosition(
                        self.sample_position,
                    ) catch return error.InvalidHrtfStreamingRendererState;
                }
            } else if (self.has_active_filter and
                !self.startup_fade_active and
                !self.transition_active and
                pending_count >= 2)
            {
                const next = &self.slots[(read +% 1) % queue_capacity];
                if (self.sample_position >= next.point.sample_position) {
                    _ = self.transitionResumePosition(
                        self.sample_position,
                    ) catch return error.InvalidHrtfStreamingRendererState;
                }
            }
            return pending_count;
        }

        fn validatePendingSlots(
            self: *const Self,
            read: usize,
            pending_count: usize,
        ) !void {
            var previous_sample: ?u64 = null;
            for (0..pending_count) |offset| {
                const slot = &self.slots[(read +% offset) % queue_capacity];
                try validateSlot(slot, self.producer_sample_rate);
                _ = self.transitionResumePosition(
                    slot.point.sample_position,
                ) catch return error.InvalidHrtfStreamingRendererState;
                if (slot.point.sample_position < self.start_sample_position)
                    return error.InvalidHrtfStreamingRendererState;
                if (previous_sample) |previous| {
                    const earliest_next = self.transitionResumePosition(
                        previous,
                    ) catch return error.InvalidHrtfStreamingRendererState;
                    if (slot.point.sample_position < earliest_next)
                        return error.InvalidHrtfStreamingRendererState;
                }
                previous_sample = slot.point.sample_position;
            }
        }

        fn validateQuiescent(self: *const Self) !void {
            try self.validateProducer();
            _ = try self.validateConsumer();
        }

        fn validateSlot(slot: *const Slot, sample_rate: u32) !void {
            if (slot.sample_rate != sample_rate or
                slot.frame_count == 0 or
                slot.frame_count > maximum_frames or
                slot.frame_count != slot.declared_frame_count or
                !std.math.isFinite(slot.direction.azimuth_degrees) or
                !std.math.isFinite(slot.direction.elevation_degrees) or
                slot.direction.azimuth_degrees < -180.0 or
                slot.direction.azimuth_degrees > 180.0 or
                slot.direction.elevation_degrees < -90.0 or
                slot.direction.elevation_degrees > 90.0)
            {
                return error.InvalidHrtfStreamingRendererState;
            }
            const derived_direction = hrtf.directionFromPositions(
                slot.point.source_position,
                slot.point.head_pose,
            ) catch return error.InvalidHrtfStreamingRendererState;
            if (!std.meta.eql(derived_direction, slot.direction))
                return error.InvalidHrtfStreamingRendererState;
            for (slot.filters[0..slot.frame_count]) |frame| {
                if (!std.math.isFinite(frame[0]) or
                    !std.math.isFinite(frame[1]))
                {
                    return error.InvalidHrtfStreamingRendererState;
                }
            }
        }

        fn crossfadeProgress(self: *const Self) f32 {
            const completed =
                self.sample_position - self.transition_start + 1;
            const linear = @min(
                @as(f64, @floatFromInt(completed)) /
                    @as(f64, @floatFromInt(self.crossfade_samples)),
                1.0,
            );
            return @floatCast(
                linear * linear * (3.0 - 2.0 * linear),
            );
        }

        fn transitionResumePosition(
            self: *const Self,
            start: u64,
        ) !u64 {
            const crossfade_samples = std.math.cast(
                u64,
                self.crossfade_samples,
            ) orelse return error.HrtfMotionSamplePositionOverflow;
            return std.math.add(
                u64,
                start,
                crossfade_samples,
            ) catch return error.HrtfMotionSamplePositionOverflow;
        }

        fn filtered(self: *const Self, slot: *const Slot) [2]f32 {
            var output: [2]f64 = @splat(0.0);
            for (0..slot.frame_count) |frame_index| {
                const history_index =
                    (self.history_write + maximum_frames - frame_index) %
                    maximum_frames;
                const sample = self.history[history_index];
                for (0..2) |channel_index| {
                    output[channel_index] +=
                        sample * slot.filters[frame_index][channel_index];
                }
            }
            const converted = [2]f32{
                @floatCast(output[0]),
                @floatCast(output[1]),
            };
            if (!std.math.isFinite(converted[0]) or
                !std.math.isFinite(converted[1]))
            {
                return @splat(0.0);
            }
            return converted;
        }

        fn recordDrop(self: *Self) void {
            var current = self.dropped_count.load(.monotonic);
            while (current != std.math.maxInt(usize)) {
                if (self.dropped_count.cmpxchgWeak(
                    current,
                    current + 1,
                    .release,
                    .monotonic,
                )) |observed| {
                    current = observed;
                } else break;
            }
        }
    };
}

fn scale(value: [2]f32, amount: f32) [2]f32 {
    return .{ value[0] * amount, value[1] * amount };
}

fn blend(first: [2]f32, second: [2]f32, amount: f32) [2]f32 {
    return .{
        first[0] + (second[0] - first[0]) * amount,
        first[1] + (second[1] - first[1]) * amount,
    };
}

test "streaming HRTF renderer adopts prepared filters smoothly" {
    const Db = hrtf.Database(2, 1);
    const database = try Db.init(
        48_000,
        &.{
            .{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 },
            .{ .azimuth_degrees = -90.0, .elevation_degrees = 0.0 },
        },
        &.{ 1.0, 0.5, 0.25, 1.0 },
    );
    const Streaming = Renderer(1, 2, 4);
    var renderer = try Streaming.init(0, 2);
    for (renderer.slots) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);
    const first = hrtf.MotionPoint{
        .sample_position = 0,
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    };
    const second = hrtf.MotionPoint{
        .sample_position = 4,
        .source_position = first.source_position,
        .head_pose = .{
            .position = first.head_pose.position,
            .yaw_degrees = 90.0,
        },
    };
    try std.testing.expect(try renderer.prepare(
        &database,
        first,
        .nearest,
    ));
    try std.testing.expect(try renderer.prepare(
        &database,
        second,
        .nearest,
    ));

    try std.testing.expectEqualDeep(
        [2]f32{ 0.5, 0.25 },
        try renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        [2]f32{ 1.0, 0.5 },
        try renderer.processSample(1.0),
    );
    _ = try renderer.processSample(1.0);
    _ = try renderer.processSample(1.0);
    try std.testing.expectEqualDeep(
        [2]f32{ 0.625, 0.75 },
        try renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        [2]f32{ 0.25, 1.0 },
        try renderer.processSample(1.0),
    );
    try std.testing.expectEqual(@as(usize, 1), try renderer.preparedCount());
    try std.testing.expectEqualDeep(
        @TypeOf(renderer.slots[0]){},
        renderer.slots[0],
    );
    try std.testing.expectEqual(
        hrtf.Direction{ .azimuth_degrees = -90.0, .elevation_degrees = 0.0 },
        (try renderer.currentDirection()).?,
    );
}

test "streaming HRTF renderer selects measured source distance" {
    const direction = hrtf.Direction{};
    const Db = hrtf.Database(2, 1);
    const database = try Db.initWithDistances(
        48_000,
        &.{ direction, direction },
        &.{ 0.5, 1.5 },
        &.{ 0.25, 0.5, 0.75, 1.0 },
    );
    const Streaming = Renderer(1, 2, 2);
    var renderer = try Streaming.init(0, 1);
    try std.testing.expect(try renderer.prepare(
        &database,
        .{
            .source_position = .{ .x = 1.5, .y = 0.0, .z = 0.0 },
        },
        .nearest,
    ));
    try std.testing.expectEqualDeep(
        [_]f32{ 0.75, 1.0 },
        try renderer.processSample(1.0),
    );
}

test "streaming HRTF renderer preserves full queues and invalid schedules" {
    const Db = hrtf.Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
        &.{ 1.0, 0.5 },
    );
    const Streaming = Renderer(1, 2, 2);
    var renderer = try Streaming.init(10, 2);
    const base = hrtf.MotionPoint{
        .sample_position = 10,
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
        .head_pose = .{
            .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
        },
    };
    try std.testing.expect(try renderer.prepare(&database, base, .nearest));
    var second = base;
    second.sample_position = 12;
    try std.testing.expect(try renderer.prepare(&database, second, .nearest));
    var third = base;
    third.sample_position = 14;
    try std.testing.expect(!try renderer.prepare(&database, third, .nearest));
    try std.testing.expectEqual(@as(usize, 1), renderer.dropped());
    var too_dense = base;
    too_dense.sample_position = 13;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, too_dense, .nearest),
    );
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, base, .nearest),
    );
    const changed_rate = try Db.init(
        96_000,
        &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
        &.{ 1.0, 0.5 },
    );
    try std.testing.expectError(
        error.HrtfMotionSampleRateChanged,
        renderer.prepare(&changed_rate, third, .nearest),
    );
    try std.testing.expectEqual(@as(usize, 2), try renderer.preparedCount());
    renderer.dropped_count.store(std.math.maxInt(usize), .release);
    try std.testing.expect(!try renderer.prepare(&database, third, .nearest));
    try std.testing.expectEqual(
        @as(usize, std.math.maxInt(usize)),
        renderer.dropped(),
    );

    for (0..4) |_| _ = try renderer.processSample(1.0);
    try std.testing.expect(try renderer.prepare(&database, third, .nearest));
    try std.testing.expectEqual(@as(usize, 2), try renderer.preparedCount());

    renderer.reset(100);
    try std.testing.expectEqual(@as(usize, 0), try renderer.preparedCount());
    try std.testing.expectEqual(@as(usize, 0), renderer.dropped());
    for (renderer.slots) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);
    renderer.write_index.store(std.math.maxInt(usize) - 1, .release);
    renderer.read_index.store(std.math.maxInt(usize) - 1, .release);
    var wrapped_first = base;
    wrapped_first.sample_position = 100;
    var wrapped_second = base;
    wrapped_second.sample_position = 102;
    try std.testing.expect(try renderer.prepare(
        &database,
        wrapped_first,
        .nearest,
    ));
    try std.testing.expect(try renderer.prepare(
        &database,
        wrapped_second,
        .nearest,
    ));
    for (0..4) |_| _ = try renderer.processSample(1.0);
    try std.testing.expectEqual(@as(usize, 1), try renderer.preparedCount());
}

test "streaming HRTF renderer contains malformed state" {
    const Streaming = Renderer(1, 2, 2);
    var renderer = try Streaming.init(0, 1);
    try std.testing.expect(renderer.valid());
    renderer.write_index.store(3, .release);
    try std.testing.expect(!renderer.valid());
    const invalid_cursor_sample = renderer.sample_position;
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqual(
        invalid_cursor_sample,
        renderer.sample_position,
    );
    try std.testing.expectEqual(
        @as(usize, 3),
        renderer.write_index.load(.acquire),
    );
    renderer.write_index.store(0, .release);
    renderer.history_write = 1;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqual(@as(usize, 1), renderer.history_write);
    renderer.history_write = 0;
    renderer.history[0] = std.math.nan(f32);
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expect(std.math.isNan(renderer.history[0]));
    renderer.history[0] = 0.0;
    renderer.sample_position = std.math.maxInt(u64);
    try std.testing.expectError(
        error.HrtfMotionSamplePositionOverflow,
        renderer.processSample(1.0),
    );

    const Db = hrtf.Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
        &.{ 1.0, 0.5 },
    );
    renderer.reset(0);
    try std.testing.expect(renderer.valid());
    try std.testing.expect(try renderer.prepare(
        &database,
        .{
            .sample_position = 0,
            .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
            .head_pose = .{
                .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
            },
        },
        .nearest,
    ));
    try std.testing.expect(renderer.valid());
    renderer.last_submitted_sample = 1;
    try std.testing.expect(!renderer.valid());
    const write_before_phase_rejection =
        renderer.write_index.load(.acquire);
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.prepare(
            &database,
            .{
                .sample_position = 2,
                .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
                .head_pose = .{
                    .position = .{ .x = 0.0, .y = 0.0, .z = 0.0 },
                },
            },
            .nearest,
        ),
    );
    try std.testing.expectEqual(
        write_before_phase_rejection,
        renderer.write_index.load(.acquire),
    );
    renderer.last_submitted_sample = 0;
    try std.testing.expect(renderer.valid());
    renderer.slots[0].direction.azimuth_degrees = 10.0;
    try std.testing.expect(!renderer.valid());
    const direction_mismatch_sample = renderer.sample_position;
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqual(
        direction_mismatch_sample,
        renderer.sample_position,
    );
    renderer.slots[0].direction.azimuth_degrees = 0.0;
    try std.testing.expect(renderer.valid());
    renderer.slots[0].frame_count = 2;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    renderer.slots[0].frame_count = 1;
    renderer.has_active_filter = true;
    renderer.startup_fade_active = true;
    renderer.transition_start = 1;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
}

test "streaming HRTF renderer binds configuration and published filter shape" {
    const Db = hrtf.Database(1, 2);
    const database = try Db.init(
        48_000,
        &.{.{}},
        &.{ 1.0, 0.5, 0.25, 0.125 },
    );
    const Streaming = Renderer(2, 2, 2);
    var renderer = try Streaming.init(10, 1);
    var point = hrtf.MotionPoint{};
    point.sample_position = 10;
    point.source_position.x = 1.0;
    try std.testing.expect(try renderer.prepare(
        &database,
        point,
        .nearest,
    ));

    renderer.slots[0].frame_count = 1;
    try std.testing.expect(!renderer.valid());
    const slot_history = renderer.history;
    const slot_sample = renderer.sample_position;
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(slot_history, renderer.history);
    try std.testing.expectEqual(slot_sample, renderer.sample_position);
    var later_point = point;
    later_point.sample_position = 12;
    const malformed_write = renderer.write_index.load(.monotonic);
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.prepare(&database, later_point, .nearest),
    );
    try std.testing.expectEqual(
        malformed_write,
        renderer.write_index.load(.monotonic),
    );
    try std.testing.expectEqual(@as(usize, 1), renderer.slots[0].frame_count);
    renderer.slots[0].frame_count =
        renderer.slots[0].declared_frame_count;
    try std.testing.expect(renderer.valid());

    renderer.crossfade_samples = 2;
    try std.testing.expect(!renderer.valid());
    renderer.crossfade_samples = renderer.declared_crossfade_samples;
    renderer.start_sample_position = 9;
    try std.testing.expect(!renderer.valid());
    renderer.start_sample_position =
        renderer.declared_start_sample_position;
    try std.testing.expect(renderer.valid());
    renderer.producer_sample_rate = 96_000;
    try std.testing.expect(!renderer.valid());
    renderer.producer_sample_rate = renderer.slots[0].sample_rate;
    try std.testing.expect(renderer.valid());
}

test "streaming HRTF renderer contains the sample timeline" {
    const Db = hrtf.Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
        &.{ 1.0, 0.5 },
    );
    const Streaming = Renderer(1, 2, 2);
    var renderer = try Streaming.init(0, 2);
    const point = hrtf.MotionPoint{
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
    };
    var unfinishable = point;
    unfinishable.sample_position = std.math.maxInt(u64) - 1;
    try std.testing.expectError(
        error.InvalidHrtfMotionSchedule,
        renderer.prepare(&database, unfinishable, .nearest),
    );
    try std.testing.expect(renderer.valid());
    try std.testing.expectEqual(@as(usize, 0), try renderer.preparedCount());
    for (renderer.slots) |slot|
        try std.testing.expectEqualDeep(@TypeOf(slot){}, slot);

    try std.testing.expect(try renderer.prepare(
        &database,
        point,
        .nearest,
    ));
    renderer.sample_position = std.math.maxInt(u64) - 1;
    const late_history = renderer.history;
    const late_history_write = renderer.history_write;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(late_history, renderer.history);
    try std.testing.expectEqual(late_history_write, renderer.history_write);
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 1,
        renderer.sample_position,
    );

    renderer.reset(0);
    try std.testing.expect(try renderer.prepare(
        &database,
        point,
        .nearest,
    ));
    _ = try renderer.processSample(1.0);
    try std.testing.expect(renderer.startup_fade_active);
    renderer.sample_position = 2;
    const overdue_history = renderer.history;
    const overdue_history_write = renderer.history_write;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(overdue_history, renderer.history);
    try std.testing.expectEqual(
        overdue_history_write,
        renderer.history_write,
    );
    try std.testing.expectEqual(@as(u64, 2), renderer.sample_position);
}

test "streaming HRTF renderer rejects unreachable queue phases" {
    const Db = hrtf.Database(1, 1);
    const database = try Db.init(
        48_000,
        &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
        &.{ 1.0, 0.5 },
    );
    const Streaming = Renderer(1, 2, 4);
    var renderer = try Streaming.init(0, 4);
    const first = hrtf.MotionPoint{
        .source_position = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
    };
    var second = first;
    second.sample_position = 4;
    try std.testing.expect(try renderer.prepare(
        &database,
        first,
        .nearest,
    ));
    try std.testing.expect(try renderer.prepare(
        &database,
        second,
        .nearest,
    ));
    renderer.slots[1].point.sample_position = 3;
    renderer.last_submitted_sample = 3;
    const dense_history = renderer.history;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(dense_history, renderer.history);
    try std.testing.expectEqual(@as(u64, 0), renderer.sample_position);

    renderer.reset(0);
    try std.testing.expect(try renderer.prepare(
        &database,
        second,
        .nearest,
    ));
    renderer.has_active_filter = true;
    renderer.startup_fade_active = true;
    renderer.transition_start = 3;
    renderer.sample_position = 4;
    const early_startup_history = renderer.history;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        early_startup_history,
        renderer.history,
    );
    try std.testing.expectEqual(@as(u64, 4), renderer.sample_position);

    renderer.reset(0);
    try std.testing.expect(try renderer.prepare(
        &database,
        first,
        .nearest,
    ));
    try std.testing.expect(try renderer.prepare(
        &database,
        second,
        .nearest,
    ));
    for (0..5) |_| _ = try renderer.processSample(1.0);
    try std.testing.expect(renderer.transition_active);
    renderer.transition_start = 3;
    const early_transition_history = renderer.history;
    try std.testing.expect(!renderer.valid());
    try std.testing.expectError(
        error.InvalidHrtfStreamingRendererState,
        renderer.processSample(1.0),
    );
    try std.testing.expectEqualDeep(
        early_transition_history,
        renderer.history,
    );
    try std.testing.expectEqual(@as(u64, 5), renderer.sample_position);
}

test "streaming HRTF renderer transfers prepared filters concurrently" {
    const Db = hrtf.Database(1, 1);
    const Streaming = Renderer(1, 4, 2);
    const Shared = struct {
        renderer: Streaming,
        database: Db,
        producer_done: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        failed: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),

        fn produce(shared: *@This()) void {
            var index: u64 = 0;
            while (index < 128) {
                const accepted = shared.renderer.prepare(
                    &shared.database,
                    .{
                        .sample_position = index * 2,
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
                    },
                    .nearest,
                ) catch {
                    shared.failed.store(true, .release);
                    return;
                };
                if (!accepted) {
                    std.Thread.yield() catch {};
                    continue;
                }
                index += 1;
            }
            shared.producer_done.store(true, .release);
        }
    };

    var shared = Shared{
        .renderer = try Streaming.init(0, 2),
        .database = try Db.init(
            48_000,
            &.{.{ .azimuth_degrees = 0.0, .elevation_degrees = 0.0 }},
            &.{ 1.0, 0.5 },
        ),
    };
    const producer = try std.Thread.spawn(.{}, Shared.produce, .{&shared});
    var iterations: usize = 0;
    while (iterations < 1_000_000) : (iterations += 1) {
        const output = try shared.renderer.processSample(1.0);
        try std.testing.expect(std.math.isFinite(output[0]));
        try std.testing.expect(std.math.isFinite(output[1]));
        if (shared.producer_done.load(.acquire) and
            try shared.renderer.preparedCount() == 1)
        {
            break;
        }
        std.Thread.yield() catch {};
    }
    producer.join();
    try std.testing.expect(!shared.failed.load(.acquire));
    try std.testing.expect(iterations < 1_000_000);
    try std.testing.expectEqual(
        @as(usize, 1),
        try shared.renderer.preparedCount(),
    );
}
