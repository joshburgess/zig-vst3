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
        if (!std.math.isFinite(self.value) or self.value < 0.0 or self.value > 1.0) {
            return error.InvalidProgressValue;
        }
        if (self.state == .complete and self.value != 1.0) return error.InvalidCompleteProgress;
        if (self.mode == .indeterminate and self.state != .running) {
            return error.InvalidIndeterminateState;
        }
    }
};

test "progress snapshots reject ambiguous states" {
    try (Snapshot{ .state = .running, .value = 0.42 }).validate();
    try (Snapshot{ .mode = .indeterminate, .state = .running }).validate();
    try (Snapshot{ .state = .complete, .value = 1.0 }).validate();
    try std.testing.expectError(error.InvalidProgressValue, (Snapshot{ .value = 1.1 }).validate());
    try std.testing.expectError(error.InvalidCompleteProgress, (Snapshot{ .state = .complete, .value = 0.9 }).validate());
    try std.testing.expectError(error.InvalidIndeterminateState, (Snapshot{ .mode = .indeterminate }).validate());
}
