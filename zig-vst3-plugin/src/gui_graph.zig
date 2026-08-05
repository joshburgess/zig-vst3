const std = @import("std");
const dsp_fft = @import("dsp/fft.zig");
const realtime_audit = @import("realtime_audit.zig");
const gui_telemetry = @import("gui_telemetry.zig");

pub const Point = extern struct {
    x: f64 = 0.0,
    y: f64 = 0.0,

    pub fn finite(self: Point) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.y);
    }
};

pub const Range = struct {
    minimum: f64,
    maximum: f64,

    pub fn init(minimum: f64, maximum: f64) !Range {
        const result = Range{ .minimum = minimum, .maximum = maximum };
        if (!result.valid()) return error.InvalidRange;
        return result;
    }

    pub fn valid(self: Range) bool {
        return std.math.isFinite(self.minimum) and std.math.isFinite(self.maximum) and self.maximum > self.minimum;
    }

    pub fn normalizeClamped(self: Range, value: f64) f64 {
        if (!self.valid() or !std.math.isFinite(value)) return 0.0;
        return std.math.clamp((value - self.minimum) / (self.maximum - self.minimum), 0.0, 1.0);
    }
};

pub const Scale = enum {
    linear,
    logarithmic,
    decibels,
};

pub const Axis = struct {
    range: Range,
    scale: Scale = .linear,
    label: []const u8 = "",
};

pub const StyleRole = enum {
    primary,
    secondary,
    modulation,
    warning,
};

pub const SeriesKind = enum {
    transfer_function,
    envelope,
    waveform,
    spectrum,
};

pub const Description = struct {
    x_axis: Axis,
    y_axis: Axis,
    kind: SeriesKind,
    style: StyleRole = .primary,
};

pub const PointId = u32;

pub const EditablePoint = struct {
    id: PointId = 0,
    position: Point = .{},
};

pub const Snap = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,

    pub fn valid(self: Snap) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.y) and self.x >= 0.0 and self.y >= 0.0;
    }
};

pub fn EditableEnvelope(comptime capacity: usize) type {
    if (capacity == 0) @compileError("EditableEnvelope capacity must be positive");
    return struct {
        const Self = @This();

        x_range: Range,
        y_range: Range,
        snap: Snap,
        points: [capacity]EditablePoint = @splat(.{}),
        point_count: usize = 0,
        selected_id: ?PointId = null,
        next_id: PointId = 1,
        transaction_points: [capacity]EditablePoint = @splat(.{}),
        transaction_count: usize = 0,
        transaction_selection: ?PointId = null,
        transaction_next_id: PointId = 1,
        transaction_active: bool = false,

        pub fn init(
            x_range: Range,
            y_range: Range,
            snap: Snap,
            source: []const EditablePoint,
        ) !Self {
            if (!x_range.valid() or !y_range.valid()) return error.InvalidRange;
            if (!snap.valid()) return error.InvalidSnap;
            if (source.len > capacity) return error.TooManyPoints;
            var result = Self{ .x_range = x_range, .y_range = y_range, .snap = snap };
            var maximum_id: PointId = 0;
            for (source, 0..) |point, index| {
                if (point.id == 0 or !point.position.finite()) return error.InvalidPoint;
                if (point.position.x < x_range.minimum or point.position.x > x_range.maximum or
                    point.position.y < y_range.minimum or point.position.y > y_range.maximum)
                {
                    return error.InvalidPoint;
                }
                if (index > 0 and source[index - 1].position.x > point.position.x) return error.UnorderedPoints;
                for (source[0..index]) |previous| {
                    if (previous.id == point.id) return error.DuplicatePointId;
                }
                result.points[index] = point;
                maximum_id = @max(maximum_id, point.id);
            }
            result.point_count = source.len;
            result.next_id = if (maximum_id == std.math.maxInt(PointId)) 1 else maximum_id + 1;
            return result;
        }

        pub fn slice(self: *const Self) []const EditablePoint {
            if (!self.valid()) return &.{};
            return self.points[0..self.point_count];
        }

        pub fn selected(self: *const Self) ?EditablePoint {
            if (!self.valid()) return null;
            const index = self.indexOf(self.selected_id orelse return null) orelse return null;
            return self.points[index];
        }

        pub fn begin(self: *Self) !void {
            if (self.transaction_active) return error.TransactionActive;
            if (!self.valid()) return error.InvalidEnvelopeState;
            self.transaction_points = @splat(.{});
            @memcpy(self.transaction_points[0..self.point_count], self.points[0..self.point_count]);
            self.transaction_count = self.point_count;
            self.transaction_selection = self.selected_id;
            self.transaction_next_id = self.next_id;
            self.transaction_active = true;
        }

        pub fn finish(self: *Self) void {
            self.clearTransaction();
        }

        pub fn cancel(self: *Self) void {
            if (!self.transaction_active) return;
            const retained_points =
                self.transaction_points[0..@min(self.transaction_count, capacity)];
            const selection_valid = if (self.transaction_selection) |id|
                containsId(retained_points, id)
            else
                true;
            if (self.transaction_count > capacity or !self.x_range.valid() or !self.y_range.valid() or
                !validPointStorage(retained_points, self.x_range, self.y_range) or
                !selection_valid)
            {
                self.clearTransaction();
                return;
            }
            self.points = @splat(.{});
            @memcpy(self.points[0..self.transaction_count], self.transaction_points[0..self.transaction_count]);
            self.point_count = self.transaction_count;
            self.selected_id = self.transaction_selection;
            self.next_id = self.transaction_next_id;
            self.clearTransaction();
        }

        pub fn select(self: *Self, id: ?PointId) !void {
            if (!self.valid()) return error.InvalidEnvelopeState;
            if (id) |value| _ = self.indexOf(value) orelse return error.PointNotFound;
            self.selected_id = id;
        }

        pub fn selectAdjacent(self: *Self, direction: enum { previous, next }) ?EditablePoint {
            if (!self.valid()) return null;
            if (self.point_count == 0) {
                self.selected_id = null;
                return null;
            }
            const index = if (self.selected_id) |id| blk: {
                const current = self.indexOf(id) orelse 0;
                break :blk switch (direction) {
                    .previous => if (current == 0) self.point_count - 1 else current - 1,
                    .next => (current + 1) % self.point_count,
                };
            } else switch (direction) {
                .previous => self.point_count - 1,
                .next => 0,
            };
            self.selected_id = self.points[index].id;
            return self.points[index];
        }

        pub fn add(self: *Self, position: Point) !PointId {
            try self.requireTransaction();
            if (self.point_count == capacity) return error.TooManyPoints;
            const snapped_position = try self.snapPoint(position);
            const id = try self.allocateId();
            var insertion = self.point_count;
            for (self.points[0..self.point_count], 0..) |point, index| {
                if (point.position.x > snapped_position.x) {
                    insertion = index;
                    break;
                }
            }
            var index = self.point_count;
            while (index > insertion) : (index -= 1) self.points[index] = self.points[index - 1];
            self.points[insertion] = .{ .id = id, .position = snapped_position };
            self.point_count += 1;
            self.selected_id = id;
            return id;
        }

        pub fn move(self: *Self, id: PointId, position: Point) !void {
            try self.requireTransaction();
            const index = self.indexOf(id) orelse return error.PointNotFound;
            var snapped_position = try self.snapPoint(position);
            if (index > 0) snapped_position.x = @max(snapped_position.x, self.points[index - 1].position.x);
            if (index + 1 < self.point_count) snapped_position.x = @min(snapped_position.x, self.points[index + 1].position.x);
            self.points[index].position = snapped_position;
            self.selected_id = id;
        }

        pub fn delete(self: *Self, id: PointId, minimum_count: usize) !void {
            try self.requireTransaction();
            if (minimum_count > capacity or self.point_count <= minimum_count) return error.MinimumPointCount;
            const index = self.indexOf(id) orelse return error.PointNotFound;
            for (index + 1..self.point_count) |source| self.points[source - 1] = self.points[source];
            self.point_count -= 1;
            self.points[self.point_count] = .{};
            if (self.point_count == 0) {
                self.selected_id = null;
            } else {
                self.selected_id = self.points[@min(index, self.point_count - 1)].id;
            }
        }

        fn requireTransaction(self: *const Self) !void {
            if (!self.transaction_active) return error.NoActiveTransaction;
            if (!self.valid()) return error.InvalidEnvelopeState;
        }

        fn clearTransaction(self: *Self) void {
            self.transaction_points = @splat(.{});
            self.transaction_count = 0;
            self.transaction_selection = null;
            self.transaction_next_id = 1;
            self.transaction_active = false;
        }

        fn indexOf(self: *const Self, id: PointId) ?usize {
            if (self.point_count > capacity) return null;
            for (self.points[0..self.point_count], 0..) |point, index| {
                if (point.id == id) return index;
            }
            return null;
        }

        fn allocateId(self: *Self) !PointId {
            var candidate = self.next_id;
            var attempts: usize = 0;
            while (attempts <= capacity) : (attempts += 1) {
                if (candidate != 0 and self.indexOf(candidate) == null) {
                    self.next_id = if (candidate == std.math.maxInt(PointId)) 1 else candidate + 1;
                    return candidate;
                }
                candidate = if (candidate == std.math.maxInt(PointId)) 1 else candidate + 1;
            }
            return error.NoPointIdAvailable;
        }

        pub fn valid(self: *const Self) bool {
            if (!self.x_range.valid() or !self.y_range.valid() or !self.snap.valid() or
                self.point_count > capacity or self.transaction_count > capacity or self.next_id == 0)
            {
                return false;
            }
            if (!validPointStorage(self.points[0..self.point_count], self.x_range, self.y_range)) return false;
            if (self.selected_id) |id| {
                if (self.indexOf(id) == null) return false;
            }
            if (self.transaction_active) {
                if (self.transaction_next_id == 0 or
                    !validPointStorage(self.transaction_points[0..self.transaction_count], self.x_range, self.y_range))
                {
                    return false;
                }
                if (self.transaction_selection) |id| {
                    if (!containsId(self.transaction_points[0..self.transaction_count], id)) return false;
                }
            }
            return true;
        }

        fn snapPoint(self: *const Self, position: Point) !Point {
            if (!position.finite()) return error.InvalidPoint;
            return .{
                .x = snapValue(position.x, self.x_range, self.snap.x),
                .y = snapValue(position.y, self.y_range, self.snap.y),
            };
        }

        fn snapValue(value: f64, range: Range, step: f64) f64 {
            const clamped = std.math.clamp(value, range.minimum, range.maximum);
            if (step == 0.0) return clamped;
            const snapped_value = range.minimum + @round((clamped - range.minimum) / step) * step;
            return std.math.clamp(snapped_value, range.minimum, range.maximum);
        }

        fn validPointStorage(source: []const EditablePoint, x_range: Range, y_range: Range) bool {
            for (source, 0..) |point, index| {
                if (point.id == 0 or !point.position.finite() or
                    point.position.x < x_range.minimum or point.position.x > x_range.maximum or
                    point.position.y < y_range.minimum or point.position.y > y_range.maximum)
                {
                    return false;
                }
                if (index > 0 and source[index - 1].position.x > point.position.x) return false;
                for (source[0..index]) |previous| {
                    if (previous.id == point.id) return false;
                }
            }
            return true;
        }

        fn containsId(source: []const EditablePoint, id: PointId) bool {
            for (source) |point| {
                if (point.id == id) return true;
            }
            return false;
        }
    };
}

pub fn FixedSeries(comptime capacity: usize) type {
    if (capacity == 0) @compileError("FixedSeries capacity must be positive");
    return struct {
        points: [capacity]Point = @splat(.{}),
        count: usize = 0,

        pub fn init(source: []const Point) !@This() {
            if (source.len > capacity) return error.TooManyPoints;
            var result = @This(){};
            for (source, 0..) |point, index| {
                if (!point.finite()) return error.InvalidPoint;
                result.points[index] = point;
            }
            result.count = source.len;
            return result;
        }

        pub fn slice(self: *const @This()) []const Point {
            if (!self.valid()) return &.{};
            return self.points[0..self.count];
        }

        pub fn valid(self: *const @This()) bool {
            if (self.count > capacity) return false;
            for (self.points[0..self.count]) |point| {
                if (!point.finite()) return false;
            }
            return true;
        }
    };
}

pub fn SnapshotSeries(comptime capacity: usize) type {
    if (capacity == 0) @compileError("SnapshotSeries capacity must be positive");
    const AtomicPoint = struct {
        x: gui_telemetry.ScalarSnapshot(f64),
        y: gui_telemetry.ScalarSnapshot(f64),
    };

    return struct {
        points: [capacity]AtomicPoint,
        point_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        generation: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        dropped_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        activity: gui_telemetry.EditorActivity = .{},

        pub fn init() @This() {
            @setEvalBranchQuota(@max(1_000, capacity * 32));
            var result: @This() = undefined;
            for (&result.points) |*point| {
                point.* = .{
                    .x = gui_telemetry.ScalarSnapshot(f64).init(0.0),
                    .y = gui_telemetry.ScalarSnapshot(f64).init(0.0),
                };
            }
            result.point_count = std.atomic.Value(usize).init(0);
            result.generation = std.atomic.Value(usize).init(0);
            result.dropped_count = std.atomic.Value(usize).init(0);
            result.activity = .{};
            return result;
        }

        pub fn editorOpened(self: *@This()) void {
            self.activity.opened();
        }

        pub fn editorClosed(self: *@This()) void {
            self.activity.closed();
        }

        pub fn publish(self: *@This(), source: []const Point) bool {
            _ = realtime_audit.observe(.telemetry_publication);
            if (!self.activity.active() or source.len > capacity) return self.drop();
            for (source) |point| if (!point.finite()) return self.drop();

            const current_generation = self.generation.load(.monotonic);
            const writing_generation = if (current_generation >= std.math.maxInt(usize) - 2)
                1
            else
                (current_generation + 1) | 1;
            self.generation.store(writing_generation, .release);
            for (source, 0..) |point, index| {
                self.points[index].x.store(point.x);
                self.points[index].y.store(point.y);
            }
            self.point_count.store(source.len, .release);
            self.generation.store(writing_generation + 1, .release);
            return true;
        }

        pub fn read(self: *const @This(), output: []Point) ?usize {
            var attempt: usize = 0;
            while (attempt < 3) : (attempt += 1) {
                const before = self.generation.load(.acquire);
                if (before & 1 != 0) continue;
                const count = self.point_count.load(.acquire);
                if (count > capacity or count > output.len) return null;
                for (output[0..count], 0..) |*point, index| {
                    if (!self.points[index].x.valid() or
                        !self.points[index].y.valid())
                        return null;
                    point.* = .{
                        .x = self.points[index].x.load(),
                        .y = self.points[index].y.load(),
                    };
                    if (!point.finite()) return null;
                }
                const after = self.generation.load(.acquire);
                if (before == after and after & 1 == 0) return count;
            }
            return null;
        }

        pub fn dropped(self: *const @This()) usize {
            return self.dropped_count.load(.acquire);
        }

        pub fn producing(self: *const @This()) bool {
            return self.activity.active();
        }

        /// Requires publication and reading to be stopped.
        pub fn valid(self: *const @This()) bool {
            if (self.generation.load(.acquire) & 1 != 0) return false;
            const count = self.point_count.load(.acquire);
            if (count > capacity) return false;
            for (0..count) |index| {
                const point = &self.points[index];
                if (!point.x.valid() or !point.y.valid()) return false;
            }
            return true;
        }

        fn drop(self: *@This()) bool {
            var current = self.dropped_count.load(.monotonic);
            while (current != std.math.maxInt(usize)) {
                if (self.dropped_count.cmpxchgWeak(current, current + 1, .monotonic, .monotonic)) |observed| {
                    current = observed;
                } else break;
            }
            return false;
        }
    };
}

pub fn WaveformCapture(comptime capacity: usize) type {
    if (capacity == 0 or capacity > 256) @compileError("WaveformCapture capacity must be between 1 and 256 points");
    const Series = SnapshotSeries(capacity);

    return struct {
        series: Series,

        pub fn init() @This() {
            return .{ .series = Series.init() };
        }

        pub fn editorOpened(self: *@This()) void {
            self.series.editorOpened();
        }

        pub fn editorClosed(self: *@This()) void {
            self.series.editorClosed();
        }

        pub fn capture(self: *@This(), samples: anytype) bool {
            if (!self.series.producing()) return false;
            const source = samples;
            const count = @min(source.len, capacity);
            var points: [capacity]Point = undefined;
            for (points[0..count], 0..) |*point, index| {
                const source_index = if (count <= 1) 0 else index * (source.len - 1) / (count - 1);
                point.* = .{
                    .x = if (count <= 1) 0.0 else @as(f64, @floatFromInt(index)) / @as(f64, @floatFromInt(count - 1)),
                    .y = @floatCast(source[source_index]),
                };
            }
            return self.series.publish(points[0..count]);
        }

        pub fn read(self: *const @This(), output: []Point) ?usize {
            return self.series.read(output);
        }

        pub fn producing(self: *const @This()) bool {
            return self.series.producing();
        }

        pub fn dropped(self: *const @This()) usize {
            return self.series.dropped();
        }

        /// Requires capture and reading to be stopped.
        pub fn valid(self: *const @This()) bool {
            return self.series.valid();
        }
    };
}

pub fn SpectrumAnalyzer(comptime fft_size: usize) type {
    if (fft_size < 8 or fft_size > 512 or !std.math.isPowerOfTwo(fft_size)) {
        @compileError("SpectrumAnalyzer FFT size must be a power of two from 8 through 512");
    }
    const bin_count = fft_size / 2;
    const Series = SnapshotSeries(bin_count);
    const Fft = dsp_fft.Transform(f64, fft_size);

    return struct {
        series: Series,
        window: [fft_size]f64,
        samples: [fft_size]f64 = @splat(0.0),
        fft: Fft,
        spectrum: [fft_size]Fft.Value = undefined,
        write_index: usize = 0,
        buffered_count: usize = 0,
        samples_since_frame: usize = 0,

        pub fn init() @This() {
            @setEvalBranchQuota(@max(1_000, fft_size * 32));
            var result: @This() = undefined;
            result.series = Series.init();
            for (&result.window, 0..) |*value, index| {
                value.* = 0.5 - 0.5 * std.math.cos(std.math.tau * @as(f64, @floatFromInt(index)) /
                    @as(f64, @floatFromInt(fft_size - 1)));
            }
            result.samples = @splat(0.0);
            result.fft = Fft.init();
            result.spectrum = undefined;
            result.write_index = 0;
            result.buffered_count = 0;
            result.samples_since_frame = 0;
            return result;
        }

        pub fn editorOpened(self: *@This()) void {
            self.series.editorOpened();
        }

        pub fn editorClosed(self: *@This()) void {
            self.series.editorClosed();
        }

        pub fn push(self: *@This(), source: anytype, sample_rate: f64) bool {
            if (!self.series.producing() or source.len == 0 or
                !std.math.isFinite(sample_rate) or sample_rate <= 0.0) return false;
            if (self.write_index >= fft_size or self.buffered_count > fft_size) {
                self.write_index = 0;
                self.buffered_count = 0;
                self.samples_since_frame = 0;
            }
            for (source) |sample| {
                const value: f64 = @floatCast(sample);
                self.samples[self.write_index] = if (std.math.isFinite(value)) value else 0.0;
                self.write_index = (self.write_index + 1) % fft_size;
                self.buffered_count = @min(self.buffered_count + 1, fft_size);
                self.samples_since_frame +|= 1;
            }
            if (self.buffered_count < fft_size or self.samples_since_frame < fft_size / 2) return false;
            self.samples_since_frame %= fft_size / 2;
            return self.analyze(sample_rate);
        }

        pub fn read(self: *const @This(), output: []Point) ?usize {
            return self.series.read(output);
        }

        pub fn producing(self: *const @This()) bool {
            return self.series.producing();
        }

        pub fn dropped(self: *const @This()) usize {
            return self.series.dropped();
        }

        /// Requires analysis, publication, and reading to be stopped.
        pub fn valid(self: *const @This()) bool {
            if (!self.series.valid() or
                self.write_index >= fft_size or
                self.buffered_count > fft_size)
            {
                return false;
            }
            if (self.buffered_count < fft_size) {
                if (self.write_index != self.buffered_count or
                    self.samples_since_frame != self.buffered_count)
                {
                    return false;
                }
            } else if (self.samples_since_frame >= fft_size / 2) {
                return false;
            }
            for (self.window) |coefficient| {
                if (!std.math.isFinite(coefficient) or coefficient < 0.0)
                    return false;
            }
            for (self.samples) |sample| {
                if (!std.math.isFinite(sample)) return false;
            }
            return true;
        }

        fn analyze(self: *@This(), sample_rate: f64) bool {
            var window_sum: f64 = 0.0;
            for (0..fft_size) |index| {
                const source_index = (self.write_index + index) % fft_size;
                self.spectrum[index] = .{
                    .real = self.samples[source_index] * self.window[index],
                };
                window_sum += self.window[index];
            }
            self.fft.forward(&self.spectrum) catch return false;
            var points: [bin_count]Point = undefined;
            for (&points, 1..) |*point, bin| {
                const magnitude =
                    2.0 * self.spectrum[bin].magnitude() / window_sum;
                point.* = .{
                    .x = @as(f64, @floatFromInt(bin)) * sample_rate / @as(f64, @floatFromInt(fft_size)),
                    .y = std.math.clamp(20.0 * std.math.log10(@max(magnitude, 0.000001)), -120.0, 0.0),
                };
            }
            return self.series.publish(&points);
        }
    };
}

test "ranges reject invalid bounds and clamp finite values" {
    try std.testing.expectError(error.InvalidRange, Range.init(1.0, 1.0));
    try std.testing.expectError(error.InvalidRange, Range.init(std.math.nan(f64), 1.0));
    try std.testing.expectEqual(@as(f64, 0.0), (Range{ .minimum = 1.0, .maximum = 0.0 }).normalizeClamped(0.5));
    try std.testing.expectEqual(@as(f64, 0.0), (Range{ .minimum = 0.0, .maximum = std.math.inf(f64) }).normalizeClamped(0.5));
    const range = try Range.init(-1.0, 1.0);
    try std.testing.expectEqual(@as(f64, 0.0), range.normalizeClamped(-2.0));
    try std.testing.expectEqual(@as(f64, 0.5), range.normalizeClamped(0.0));
    try std.testing.expectEqual(@as(f64, 1.0), range.normalizeClamped(2.0));
}

test "fixed series rejects overflow and invalid points" {
    const Series = FixedSeries(2);
    try std.testing.expectError(error.TooManyPoints, Series.init(&.{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 } }));
    try std.testing.expectError(error.InvalidPoint, Series.init(&.{.{ .x = 0, .y = std.math.inf(f64) }}));
    const series = try Series.init(&.{ .{ .x = 0, .y = 1 }, .{ .x = 1, .y = 0 } });
    try std.testing.expectEqual(@as(usize, 2), series.slice().len);
    var malformed = series;
    malformed.count = 3;
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.slice().len);
    malformed = series;
    malformed.points[0].x = std.math.nan(f64);
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.slice().len);

    const spare = try FixedSeries(3).init(&.{.{ .x = 0.25, .y = 0.75 }});
    try std.testing.expectEqualDeep(Point{}, spare.points[1]);
    try std.testing.expectEqualDeep(Point{}, spare.points[2]);
}

test "editable envelopes reject directly constructed invalid ranges" {
    const Envelope = EditableEnvelope(2);
    const valid = try Range.init(0.0, 1.0);
    try std.testing.expectError(
        error.InvalidRange,
        Envelope.init(.{ .minimum = 1.0, .maximum = 0.0 }, valid, .{}, &.{}),
    );
    try std.testing.expectError(
        error.InvalidRange,
        Envelope.init(valid, .{ .minimum = 0.0, .maximum = std.math.nan(f64) }, .{}, &.{}),
    );
}

test "editable envelope rejects malformed direct collection state" {
    const Envelope = EditableEnvelope(2);
    const range = try Range.init(0.0, 1.0);
    var envelope = try Envelope.init(range, range, .{}, &.{
        .{ .id = 1, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 2, .position = .{ .x = 1.0, .y = 1.0 } },
    });
    envelope.point_count = 3;
    try std.testing.expect(!envelope.valid());
    try std.testing.expectEqual(@as(usize, 0), envelope.slice().len);
    try std.testing.expectEqual(@as(?EditablePoint, null), envelope.selected());
    try std.testing.expectError(error.InvalidEnvelopeState, envelope.begin());
    try std.testing.expectEqual(@as(?EditablePoint, null), envelope.selectAdjacent(.next));

    envelope.point_count = 2;
    envelope.points[1].id = 1;
    try std.testing.expect(!envelope.valid());
    try std.testing.expectEqual(@as(usize, 0), envelope.slice().len);
    try std.testing.expectError(error.InvalidEnvelopeState, envelope.select(1));

    envelope.points[1] = .{ .id = 2, .position = .{ .x = 1.0, .y = 1.0 } };
    try std.testing.expect(envelope.valid());
    try envelope.begin();
    envelope.transaction_count = 3;
    envelope.cancel();
    try std.testing.expect(!envelope.transaction_active);
    try std.testing.expect(envelope.valid());
}

test "snapshot series is activity gated and bounded" {
    var series = SnapshotSeries(2).init();
    var output: [2]Point = undefined;
    try std.testing.expect(!series.publish(&.{.{ .x = 0, .y = 0 }}));
    series.editorOpened();
    try std.testing.expect(series.publish(&.{ .{ .x = -1, .y = 0.25 }, .{ .x = 1, .y = 0.75 } }));
    try std.testing.expectEqual(@as(?usize, 2), series.read(&output));
    try std.testing.expectEqual(@as(f64, 0.75), output[1].y);
    try std.testing.expect(!series.publish(&.{ .{ .x = 0, .y = 0 }, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 2 } }));
    try std.testing.expectEqual(@as(usize, 2), series.dropped());
    series.editorClosed();
}

test "snapshot series drop count saturates instead of wrapping" {
    var series = SnapshotSeries(1).init();
    series.dropped_count.store(std.math.maxInt(usize), .release);
    try std.testing.expect(!series.publish(&.{.{ .x = 0.0, .y = 0.0 }}));
    try std.testing.expectEqual(std.math.maxInt(usize), series.dropped());
    series.editorOpened();
    try std.testing.expect(series.publish(&.{.{ .x = 0.0, .y = 0.5 }}));
    var output: [1]Point = undefined;
    try std.testing.expectEqual(@as(?usize, 1), series.read(&output));
    try std.testing.expectEqual(@as(f64, 0.5), output[0].y);
}

test "snapshot series recovers a generation at the integer boundary" {
    var series = SnapshotSeries(1).init();
    series.editorOpened();
    series.generation.store(std.math.maxInt(usize), .release);
    try std.testing.expect(series.publish(&.{.{ .x = 0.25, .y = 0.75 }}));
    try std.testing.expectEqual(@as(usize, 2), series.generation.load(.acquire));
    var output: [1]Point = undefined;
    try std.testing.expectEqual(@as(?usize, 1), series.read(&output));
    try std.testing.expectEqual(@as(f64, 0.25), output[0].x);
    try std.testing.expectEqual(@as(f64, 0.75), output[0].y);
}

test "snapshot series rejects malformed retained points and counts" {
    var series = SnapshotSeries(2).init();
    try std.testing.expect(series.valid());
    series.editorOpened();
    try std.testing.expect(series.publish(&.{.{ .x = 0.25, .y = 0.75 }}));

    var output: [2]Point = undefined;
    series.points[0].x.bits.store(
        @bitCast(std.math.nan(f64)),
        .release,
    );
    try std.testing.expect(!series.valid());
    try std.testing.expect(series.read(&output) == null);
    series.points[0].x.store(0.25);
    series.points[0].y.bits.store(
        @bitCast(std.math.inf(f64)),
        .release,
    );
    try std.testing.expect(!series.valid());
    try std.testing.expect(series.read(&output) == null);

    series.points[0].y.store(0.75);
    series.point_count.store(3, .release);
    try std.testing.expect(!series.valid());
    try std.testing.expect(series.read(&output) == null);
    series.point_count.store(1, .release);
    try std.testing.expect(series.valid());
    try std.testing.expectEqual(@as(?usize, 1), series.read(&output));
    try std.testing.expectEqual(@as(f64, 0.25), output[0].x);
    try std.testing.expectEqual(@as(f64, 0.75), output[0].y);
}

test "waveform capture downsamples without work while inactive" {
    var capture = WaveformCapture(4).init();
    try std.testing.expect(capture.valid());
    const samples = [_]f32{ -1.0, -0.75, -0.5, -0.25, 0.0, 0.25, 0.5, 1.0 };
    try std.testing.expect(!capture.capture(&samples));
    capture.editorOpened();
    try std.testing.expect(capture.capture(&samples));
    try std.testing.expect(capture.valid());
    var points: [4]Point = undefined;
    try std.testing.expectEqual(@as(?usize, 4), capture.read(&points));
    try std.testing.expectEqual(@as(f64, 0.0), points[0].x);
    try std.testing.expectEqual(@as(f64, 1.0), points[3].x);
    try std.testing.expectEqual(@as(f64, -1.0), points[0].y);
    try std.testing.expectEqual(@as(f64, 1.0), points[3].y);
    capture.editorClosed();
    try std.testing.expect(!capture.capture(&samples));
}

test "spectrum analyzer publishes a deterministic bounded FFT" {
    const fft_size = 64;
    var analyzer = SpectrumAnalyzer(fft_size).init();
    try std.testing.expect(analyzer.valid());
    var samples: [fft_size]f64 = undefined;
    const expected_bin = 8;
    for (&samples, 0..) |*sample, index| {
        sample.* = std.math.sin(std.math.tau * @as(f64, @floatFromInt(expected_bin * index)) /
            @as(f64, @floatFromInt(fft_size)));
    }
    try std.testing.expect(!analyzer.push(&samples, 48_000.0));
    analyzer.editorOpened();
    try std.testing.expect(analyzer.push(&samples, 48_000.0));
    try std.testing.expect(analyzer.valid());
    var points: [fft_size / 2]Point = undefined;
    const count = analyzer.read(&points) orelse return error.MissingSpectrum;
    try std.testing.expectEqual(@as(usize, fft_size / 2), count);
    var strongest: usize = 0;
    for (points[1..count], 1..) |point, index| {
        if (point.y > points[strongest].y) strongest = index;
    }
    try std.testing.expectEqual(@as(usize, expected_bin - 1), strongest);
    try std.testing.expectApproxEqAbs(@as(f64, 6_000.0), points[strongest].x, 0.001);
    try std.testing.expect(points[strongest].y > -1.0);
    try std.testing.expect(!analyzer.push(&samples, 0.0));
    analyzer.editorClosed();
    try std.testing.expect(!analyzer.push(&samples, 48_000.0));
}

test "spectrum analyzer recovers malformed retained cursors" {
    const fft_size = 8;
    var analyzer = SpectrumAnalyzer(fft_size).init();
    analyzer.editorOpened();
    analyzer.write_index = fft_size;
    analyzer.buffered_count = std.math.maxInt(usize);
    analyzer.samples_since_frame = std.math.maxInt(usize);
    try std.testing.expect(!analyzer.valid());
    const samples = [_]f64{ 0.0, 1.0, 0.0, -1.0, 0.0, 1.0, 0.0, -1.0 };
    try std.testing.expect(analyzer.push(&samples, 48_000.0));
    try std.testing.expect(analyzer.valid());
    try std.testing.expectEqual(@as(usize, 0), analyzer.write_index);
    try std.testing.expectEqual(@as(usize, fft_size), analyzer.buffered_count);
    try std.testing.expectEqual(@as(usize, 0), analyzer.samples_since_frame);
    var points: [fft_size / 2]Point = undefined;
    try std.testing.expectEqual(@as(?usize, fft_size / 2), analyzer.read(&points));
    for (points) |point| try std.testing.expect(point.finite());

    analyzer.window[0] = std.math.nan(f64);
    try std.testing.expect(!analyzer.valid());
    analyzer.window[0] = 0.0;
    analyzer.samples[0] = std.math.inf(f64);
    try std.testing.expect(!analyzer.valid());
}

test "editable envelope keeps stable IDs and ordered snapped points" {
    const Envelope = EditableEnvelope(4);
    const x_range = try Range.init(0.0, 1.0);
    const y_range = try Range.init(-1.0, 1.0);
    var envelope = try Envelope.init(x_range, y_range, .{ .x = 0.25, .y = 0.5 }, &.{
        .{ .id = 7, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 9, .position = .{ .x = 1.0, .y = 0.0 } },
    });
    try std.testing.expectEqualDeep(EditablePoint{}, envelope.points[2]);
    try std.testing.expectEqualDeep(EditablePoint{}, envelope.points[3]);
    for (envelope.transaction_points) |point|
        try std.testing.expectEqualDeep(EditablePoint{}, point);
    try envelope.begin();
    const added = try envelope.add(.{ .x = 0.61, .y = 0.62 });
    try std.testing.expectEqual(@as(PointId, 10), added);
    try std.testing.expectEqual(@as(f64, 0.5), envelope.slice()[1].position.x);
    try std.testing.expectEqual(@as(f64, 0.5), envelope.slice()[1].position.y);
    try envelope.move(added, .{ .x = 2.0, .y = -2.0 });
    try std.testing.expectEqual(@as(f64, 1.0), envelope.selected().?.position.x);
    try std.testing.expectEqual(@as(f64, -1.0), envelope.selected().?.position.y);
    envelope.finish();
    try std.testing.expectEqual(@as(usize, 3), envelope.slice().len);
    for (envelope.transaction_points) |point|
        try std.testing.expectEqualDeep(EditablePoint{}, point);
}

test "editable envelope cancellation restores points selection and ID allocation" {
    const Envelope = EditableEnvelope(3);
    var envelope = try Envelope.init(
        try Range.init(0.0, 1.0),
        try Range.init(0.0, 1.0),
        .{},
        &.{ .{ .id = 3, .position = .{ .x = 0.0, .y = 0.0 } }, .{ .id = 4, .position = .{ .x = 1.0, .y = 1.0 } } },
    );
    try envelope.select(3);
    try envelope.begin();
    const transient = try envelope.add(.{ .x = 0.5, .y = 0.5 });
    try std.testing.expectEqual(@as(PointId, 5), transient);
    try envelope.delete(3, 1);
    try std.testing.expectEqualDeep(EditablePoint{}, envelope.points[2]);
    envelope.cancel();
    try std.testing.expectEqual(@as(usize, 2), envelope.slice().len);
    try std.testing.expectEqualDeep(EditablePoint{}, envelope.points[2]);
    for (envelope.transaction_points) |point|
        try std.testing.expectEqualDeep(EditablePoint{}, point);
    try std.testing.expectEqual(@as(PointId, 3), envelope.selected().?.id);
    try envelope.begin();
    try std.testing.expectEqual(@as(PointId, 5), try envelope.add(.{ .x = 0.5, .y = 0.5 }));
    envelope.finish();
}

test "editable envelope enforces bounds capacity and transaction rules" {
    const Envelope = EditableEnvelope(2);
    const range = try Range.init(0.0, 1.0);
    try std.testing.expectError(error.InvalidSnap, Envelope.init(range, range, .{ .x = -1.0 }, &.{}));
    try std.testing.expectError(error.DuplicatePointId, Envelope.init(range, range, .{}, &.{
        .{ .id = 1, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 1, .position = .{ .x = 1.0, .y = 1.0 } },
    }));
    var envelope = try Envelope.init(range, range, .{}, &.{
        .{ .id = 1, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 2, .position = .{ .x = 1.0, .y = 1.0 } },
    });
    try std.testing.expectError(error.NoActiveTransaction, envelope.move(1, .{ .x = 0.5, .y = 0.5 }));
    try envelope.begin();
    try std.testing.expectError(error.TooManyPoints, envelope.add(.{ .x = 0.5, .y = 0.5 }));
    try std.testing.expectError(error.MinimumPointCount, envelope.delete(1, 2));
    envelope.cancel();
    try std.testing.expectEqual(@as(PointId, 1), envelope.selectAdjacent(.next).?.id);
    try std.testing.expectEqual(@as(PointId, 2), envelope.selectAdjacent(.next).?.id);
    try std.testing.expectEqual(@as(PointId, 1), envelope.selectAdjacent(.next).?.id);
}
