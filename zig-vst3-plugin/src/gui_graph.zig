const std = @import("std");
const gui_telemetry = @import("gui_telemetry.zig");

pub const Point = extern struct {
    x: f64,
    y: f64,

    pub fn finite(self: Point) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.y);
    }
};

pub const Range = struct {
    minimum: f64,
    maximum: f64,

    pub fn init(minimum: f64, maximum: f64) !Range {
        if (!std.math.isFinite(minimum) or !std.math.isFinite(maximum) or maximum <= minimum) {
            return error.InvalidRange;
        }
        return .{ .minimum = minimum, .maximum = maximum };
    }

    pub fn normalizeClamped(self: Range, value: f64) f64 {
        if (!std.math.isFinite(value)) return 0.0;
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
    id: PointId,
    position: Point,
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
        points: [capacity]EditablePoint = undefined,
        point_count: usize = 0,
        selected_id: ?PointId = null,
        next_id: PointId = 1,
        transaction_points: [capacity]EditablePoint = undefined,
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
            return self.points[0..self.point_count];
        }

        pub fn selected(self: *const Self) ?EditablePoint {
            const index = self.indexOf(self.selected_id orelse return null) orelse return null;
            return self.points[index];
        }

        pub fn begin(self: *Self) !void {
            if (self.transaction_active) return error.TransactionActive;
            @memcpy(self.transaction_points[0..self.point_count], self.points[0..self.point_count]);
            self.transaction_count = self.point_count;
            self.transaction_selection = self.selected_id;
            self.transaction_next_id = self.next_id;
            self.transaction_active = true;
        }

        pub fn finish(self: *Self) void {
            self.transaction_active = false;
        }

        pub fn cancel(self: *Self) void {
            if (!self.transaction_active) return;
            @memcpy(self.points[0..self.transaction_count], self.transaction_points[0..self.transaction_count]);
            self.point_count = self.transaction_count;
            self.selected_id = self.transaction_selection;
            self.next_id = self.transaction_next_id;
            self.transaction_active = false;
        }

        pub fn select(self: *Self, id: ?PointId) !void {
            if (id) |value| _ = self.indexOf(value) orelse return error.PointNotFound;
            self.selected_id = id;
        }

        pub fn selectAdjacent(self: *Self, direction: enum { previous, next }) ?EditablePoint {
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
            if (self.point_count == 0) {
                self.selected_id = null;
            } else {
                self.selected_id = self.points[@min(index, self.point_count - 1)].id;
            }
        }

        fn requireTransaction(self: *const Self) !void {
            if (!self.transaction_active) return error.NoActiveTransaction;
        }

        fn indexOf(self: *const Self, id: PointId) ?usize {
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
    };
}

pub fn FixedSeries(comptime capacity: usize) type {
    if (capacity == 0) @compileError("FixedSeries capacity must be positive");
    return struct {
        points: [capacity]Point = undefined,
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
            return self.points[0..self.count];
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
            if (!self.activity.active() or source.len > capacity) return self.drop();
            for (source) |point| if (!point.finite()) return self.drop();

            _ = self.generation.fetchAdd(1, .acq_rel);
            for (source, 0..) |point, index| {
                self.points[index].x.store(point.x);
                self.points[index].y.store(point.y);
            }
            self.point_count.store(source.len, .release);
            _ = self.generation.fetchAdd(1, .release);
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
                    point.* = .{
                        .x = self.points[index].x.load(),
                        .y = self.points[index].y.load(),
                    };
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

        fn drop(self: *@This()) bool {
            _ = self.dropped_count.fetchAdd(1, .monotonic);
            return false;
        }
    };
}

test "ranges reject invalid bounds and clamp finite values" {
    try std.testing.expectError(error.InvalidRange, Range.init(1.0, 1.0));
    try std.testing.expectError(error.InvalidRange, Range.init(std.math.nan(f64), 1.0));
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

test "editable envelope keeps stable IDs and ordered snapped points" {
    const Envelope = EditableEnvelope(4);
    const x_range = try Range.init(0.0, 1.0);
    const y_range = try Range.init(-1.0, 1.0);
    var envelope = try Envelope.init(x_range, y_range, .{ .x = 0.25, .y = 0.5 }, &.{
        .{ .id = 7, .position = .{ .x = 0.0, .y = 0.0 } },
        .{ .id = 9, .position = .{ .x = 1.0, .y = 0.0 } },
    });
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
    envelope.cancel();
    try std.testing.expectEqual(@as(usize, 2), envelope.slice().len);
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
