const std = @import("std");

pub const Gate = struct {
    const closed_bit: u32 = 1 << 31;
    const count_mask: u32 = closed_bit - 1;

    state: std.atomic.Value(u32) =
        std.atomic.Value(u32).init(closed_bit),

    pub const Admission = struct {
        gate: ?*Gate,

        pub fn release(self: *Admission) void {
            const gate = self.gate orelse return;
            self.gate = null;
            gate.release();
        }
    };

    pub fn open(self: *Gate) !void {
        if (self.state.cmpxchgStrong(
            closed_bit,
            0,
            .release,
            .acquire,
        ) != null) return error.CallbackGateNotDrained;
    }

    pub fn admit(self: *Gate) ?Admission {
        var current = self.state.load(.acquire);
        while (current & closed_bit == 0) {
            const count = current & count_mask;
            if (count == count_mask) return null;
            if (self.state.cmpxchgWeak(
                current,
                current + 1,
                .acquire,
                .monotonic,
            )) |observed| {
                current = observed;
            } else return .{ .gate = self };
        }
        return null;
    }

    pub fn closeAdmission(self: *Gate) void {
        _ = self.state.fetchOr(closed_bit, .acq_rel);
    }

    pub fn drain(self: *Gate) void {
        while (self.activeCount() != 0)
            std.Thread.yield() catch {};
    }

    pub fn activeCount(self: *const Gate) u32 {
        return self.state.load(.acquire) & count_mask;
    }

    pub fn isOpen(self: *const Gate) bool {
        return self.state.load(.acquire) & closed_bit == 0;
    }

    fn release(self: *Gate) void {
        var current = self.state.load(.monotonic);
        while (current & count_mask != 0) {
            if (self.state.cmpxchgWeak(
                current,
                current - 1,
                .release,
                .monotonic,
            )) |observed| {
                current = observed;
            } else return;
        }
    }
};

test "callback gate closes admission and drains active callbacks" {
    var gate = Gate{};
    try std.testing.expect(!gate.isOpen());
    try std.testing.expect(gate.admit() == null);

    try gate.open();
    var admission = gate.admit() orelse
        return error.ExpectedCallbackAdmission;
    try std.testing.expectEqual(@as(u32, 1), gate.activeCount());

    gate.closeAdmission();
    try std.testing.expect(!gate.isOpen());
    try std.testing.expect(gate.admit() == null);
    try std.testing.expectError(
        error.CallbackGateNotDrained,
        gate.open(),
    );
    admission.release();
    gate.drain();
    try std.testing.expectEqual(@as(u32, 0), gate.activeCount());
    try gate.open();
}

test "callback gate drain waits for an admitted callback" {
    const Context = struct {
        gate: *Gate,
        admitted: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),
        release: std.atomic.Value(bool) =
            std.atomic.Value(bool).init(false),

        fn run(self: *@This()) void {
            var admission = self.gate.admit() orelse return;
            defer admission.release();
            self.admitted.store(true, .release);
            while (!self.release.load(.acquire))
                std.Thread.yield() catch {};
        }
    };

    var gate = Gate{};
    try gate.open();
    var context = Context{ .gate = &gate };
    const worker = try std.Thread.spawn(.{}, Context.run, .{&context});
    while (!context.admitted.load(.acquire))
        std.Thread.yield() catch {};
    gate.closeAdmission();
    try std.testing.expect(gate.admit() == null);
    context.release.store(true, .release);
    gate.drain();
    worker.join();
}
