const std = @import("std");

pub const Mode = enum {
    determinate,
    indeterminate,
};

pub const State = enum {
    idle,
    running,
    complete,
    failed,
};

pub const Snapshot = struct {
    mode: Mode = .determinate,
    state: State = .idle,
    value: f64 = 0.0,
    generation: u64 = 0,

    pub fn validate(self: Snapshot) !void {
        if (self.state != .idle and self.generation == 0)
            return error.InvalidProgressGeneration;
        if (!std.math.isFinite(self.value) or self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
        if (self.state == .idle and self.value != 0.0)
            return error.InvalidIdleProgress;
        if (self.state == .complete and self.value != 1.0) return error.InvalidCompleteProgress;
        if (self.mode == .indeterminate and self.state != .running) {
            return error.InvalidIndeterminateState;
        }
        if (self.mode == .indeterminate and self.value != 0.0)
            return error.InvalidIndeterminateProgress;
    }

    pub fn valid(self: Snapshot) bool {
        self.validate() catch return false;
        return true;
    }
};

test "progress snapshots reject ambiguous states" {
    try (Snapshot{ .state = .running, .value = 0.42, .generation = 1 }).validate();
    try (Snapshot{ .mode = .indeterminate, .state = .running, .generation = 1 }).validate();
    try (Snapshot{ .state = .complete, .value = 1.0, .generation = 1 }).validate();
    try std.testing.expectError(error.InvalidProgressValue, (Snapshot{ .value = 1.1 }).validate());
    try std.testing.expectError(error.InvalidProgressGeneration, (Snapshot{ .state = .complete, .value = 0.9 }).validate());
    try std.testing.expectError(error.InvalidCompleteProgress, (Snapshot{ .state = .complete, .value = 0.9, .generation = 1 }).validate());
    try std.testing.expectError(error.InvalidIndeterminateState, (Snapshot{ .mode = .indeterminate }).validate());
    try std.testing.expectError(error.InvalidIdleProgress, (Snapshot{ .value = 0.5 }).validate());
    try std.testing.expectError(error.InvalidProgressGeneration, (Snapshot{ .state = .failed }).validate());
    try std.testing.expectError(error.InvalidIndeterminateProgress, (Snapshot{
        .mode = .indeterminate,
        .state = .running,
        .value = 0.5,
        .generation = 1,
    }).validate());
    try std.testing.expect((Snapshot{}).valid());
    try std.testing.expect(!(Snapshot{ .state = .running }).valid());
}

test "progress snapshot validation covers the bounded state matrix" {
    const modes = [_]Mode{ .determinate, .indeterminate };
    const states = [_]State{ .idle, .running, .complete, .failed };
    const values = [_]f64{
        -0.1,
        0.0,
        0.5,
        1.0,
        1.1,
        std.math.nan(f64),
        std.math.inf(f64),
    };
    const generations = [_]u64{ 0, 1 };

    for (modes) |mode| {
        for (states) |state| {
            for (values) |value| {
                for (generations) |generation| {
                    const snapshot = Snapshot{
                        .mode = mode,
                        .state = state,
                        .value = value,
                        .generation = generation,
                    };
                    const expected =
                        (state == .idle or generation != 0) and
                        std.math.isFinite(value) and
                        value >= 0.0 and value <= 1.0 and
                        (state != .idle or value == 0.0) and
                        (state != .complete or value == 1.0) and
                        (mode != .indeterminate or
                            (state == .running and value == 0.0));
                    var validates = true;
                    snapshot.validate() catch {
                        validates = false;
                    };
                    try std.testing.expectEqual(expected, validates);
                    try std.testing.expectEqual(expected, snapshot.valid());
                }
            }
        }
    }
}
