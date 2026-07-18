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
