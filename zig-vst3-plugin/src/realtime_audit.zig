const builtin = @import("builtin");
const std = @import("std");

pub const enabled = builtin.is_test or builtin.mode == .Debug;

pub const Operation = enum {
    allocation,
    lock,
    file_access,
    logging,
    host_call,
    gui_call,
    telemetry_publication,
    decoded_audio_adoption,
    resource_adoption,
};

pub const Report = struct {
    counts: [operation_count]u32,
    first_violation: ?Operation,

    pub fn clean(self: Report) bool {
        return self.first_violation == null;
    }

    pub fn count(self: Report, operation: Operation) u32 {
        return self.counts[@intFromEnum(operation)];
    }
};

pub const Scope = struct {
    outermost: bool,

    pub fn enter() Scope {
        if (comptime !enabled) return .{ .outermost = false };
        const outermost = depth == 0;
        if (outermost) {
            counts = @splat(0);
            first_violation = null;
        }
        depth += 1;
        return .{ .outermost = outermost };
    }

    pub fn leave(self: Scope) Report {
        if (comptime !enabled) return .{ .counts = @splat(0), .first_violation = null };
        std.debug.assert(depth != 0);
        depth -= 1;
        if (!self.outermost) return .{ .counts = @splat(0), .first_violation = null };
        std.debug.assert(depth == 0);
        return .{ .counts = counts, .first_violation = first_violation };
    }
};

const operation_count = @typeInfo(Operation).@"enum".fields.len;
threadlocal var depth: usize = 0;
threadlocal var counts: [operation_count]u32 = @splat(0);
threadlocal var first_violation: ?Operation = null;

pub fn active() bool {
    if (comptime !enabled) return false;
    return depth != 0;
}

pub fn observe(operation: Operation) bool {
    if (comptime !enabled) return true;
    if (!active()) return true;
    counts[@intFromEnum(operation)] +|= 1;
    if (!allowed(operation)) {
        if (first_violation == null) first_violation = operation;
        return false;
    }
    return true;
}

fn allowed(operation: Operation) bool {
    return switch (operation) {
        .telemetry_publication, .decoded_audio_adoption, .resource_adoption => true,
        .allocation, .lock, .file_access, .logging, .host_call, .gui_call => false,
    };
}

test "realtime audit records allowed and forbidden operations per thread" {
    const scope = Scope.enter();
    try std.testing.expect(observe(.telemetry_publication));
    try std.testing.expect(observe(.decoded_audio_adoption));
    try std.testing.expect(observe(.resource_adoption));
    try std.testing.expect(!observe(.allocation));
    try std.testing.expect(!observe(.lock));
    try std.testing.expect(!observe(.file_access));
    try std.testing.expect(!observe(.logging));
    try std.testing.expect(!observe(.host_call));
    try std.testing.expect(!observe(.gui_call));
    const report = scope.leave();
    try std.testing.expectEqual(Operation.allocation, report.first_violation.?);
    inline for (@typeInfo(Operation).@"enum".fields) |field| {
        try std.testing.expectEqual(@as(u32, 1), report.count(@enumFromInt(field.value)));
    }
}

test "realtime audit ignores non-realtime work" {
    try std.testing.expect(observe(.allocation));
    try std.testing.expect(observe(.file_access));
}
