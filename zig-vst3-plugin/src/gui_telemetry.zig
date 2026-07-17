const std = @import("std");

/// A lock-free scalar value for meters and other latest-value displays.
pub fn ScalarSnapshot(comptime Float: type) type {
    const Bits = switch (Float) {
        f32 => u32,
        f64 => u64,
        else => @compileError("ScalarSnapshot supports f32 and f64"),
    };

    return struct {
        bits: std.atomic.Value(Bits),

        pub fn init(value: Float) @This() {
            return .{ .bits = std.atomic.Value(Bits).init(@bitCast(value)) };
        }

        pub fn store(self: *@This(), value: Float) void {
            self.bits.store(@bitCast(value), .release);
        }

        pub fn load(self: *const @This()) Float {
            return @bitCast(self.bits.load(.acquire));
        }
    };
}

/// A bounded queue with one producer and one consumer. Full queues drop new data.
pub fn SpscQueue(comptime T: type, comptime capacity: usize) type {
    if (capacity == 0) @compileError("SpscQueue capacity must be positive");

    return struct {
        items: [capacity]T = undefined,
        write_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        read_index: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
        dropped_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

        pub fn push(self: *@This(), item: T) bool {
            const write = self.write_index.load(.monotonic);
            const read = self.read_index.load(.acquire);
            if (write -% read == capacity) {
                _ = self.dropped_count.fetchAdd(1, .monotonic);
                return false;
            }
            self.items[write % capacity] = item;
            self.write_index.store(write +% 1, .release);
            return true;
        }

        pub fn pop(self: *@This()) ?T {
            const read = self.read_index.load(.monotonic);
            const write = self.write_index.load(.acquire);
            if (read == write) return null;
            const item = self.items[read % capacity];
            self.read_index.store(read +% 1, .release);
            return item;
        }

        pub fn dropped(self: *const @This()) usize {
            return self.dropped_count.load(.acquire);
        }
    };
}

/// Coalesces many invalidations into one pending GUI-thread repaint.
pub const RepaintCoalescer = struct {
    pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn request(self: *RepaintCoalescer) bool {
        return self.pending.cmpxchgStrong(false, true, .acq_rel, .acquire) == null;
    }

    pub fn complete(self: *RepaintCoalescer) void {
        self.pending.store(false, .release);
    }
};

/// Lets the processor skip editor-only analysis while no editor is open.
pub const EditorActivity = struct {
    open_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    pub fn opened(self: *EditorActivity) void {
        _ = self.open_count.fetchAdd(1, .release);
    }

    pub fn closed(self: *EditorActivity) void {
        var current = self.open_count.load(.acquire);
        while (current != 0) {
            if (self.open_count.cmpxchgWeak(current, current - 1, .acq_rel, .acquire)) |observed| {
                current = observed;
            } else return;
        }
    }

    pub fn active(self: *const EditorActivity) bool {
        return self.open_count.load(.acquire) != 0;
    }
};

test "scalar snapshot preserves the latest value" {
    var snapshot = ScalarSnapshot(f64).init(0.25);
    try std.testing.expectEqual(@as(f64, 0.25), snapshot.load());
    snapshot.store(0.75);
    try std.testing.expectEqual(@as(f64, 0.75), snapshot.load());
}

test "bounded queue preserves order and drops overflow" {
    var queue = SpscQueue(u32, 2){};
    try std.testing.expect(queue.push(10));
    try std.testing.expect(queue.push(20));
    try std.testing.expect(!queue.push(30));
    try std.testing.expectEqual(@as(usize, 1), queue.dropped());
    try std.testing.expectEqual(@as(?u32, 10), queue.pop());
    try std.testing.expectEqual(@as(?u32, 20), queue.pop());
    try std.testing.expectEqual(@as(?u32, null), queue.pop());
}

test "repaint requests coalesce until completion" {
    var coalescer = RepaintCoalescer{};
    try std.testing.expect(coalescer.request());
    try std.testing.expect(!coalescer.request());
    coalescer.complete();
    try std.testing.expect(coalescer.request());
}

test "editor activity tracks multiple views without underflow" {
    var activity = EditorActivity{};
    activity.opened();
    activity.opened();
    try std.testing.expect(activity.active());
    activity.closed();
    try std.testing.expect(activity.active());
    activity.closed();
    activity.closed();
    try std.testing.expect(!activity.active());
}
