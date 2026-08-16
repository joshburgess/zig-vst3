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
    invalid_scope: bool = false,

    pub fn clean(self: Report) bool {
        return self.first_violation == null and !self.invalid_scope;
    }

    pub fn count(self: Report, operation: Operation) u32 {
        return self.counts[@intFromEnum(operation)];
    }
};

pub const Scope = struct {
    outermost: bool,
    id: u64,
    parent_id: u64,

    pub fn enter() Scope {
        if (comptime !enabled) return .{
            .outermost = false,
            .id = 0,
            .parent_id = 0,
        };
        const outermost = depth == 0;
        if (outermost) {
            counts = @splat(0);
            first_violation = null;
        }
        const parent_id = active_scope_id;
        if (depth == std.math.maxInt(usize)) return .{
            .outermost = false,
            .id = 0,
            .parent_id = parent_id,
        };
        var id = next_scope_id;
        if (id == 0 or id == parent_id) id +%= 1;
        if (id == 0 or id == parent_id) id +%= 1;
        next_scope_id = id +% 1;
        if (next_scope_id == 0) next_scope_id = 1;
        active_scope_id = id;
        depth += 1;
        return .{
            .outermost = outermost,
            .id = id,
            .parent_id = parent_id,
        };
    }

    pub fn leave(self: Scope) Report {
        if (comptime !enabled) return .{ .counts = @splat(0), .first_violation = null };
        const valid_depth = if (self.outermost)
            depth == 1 and self.parent_id == 0
        else
            depth > 1 and self.parent_id != 0;
        if (!valid_depth or active_scope_id != self.id) {
            return .{
                .counts = counts,
                .first_violation = first_violation,
                .invalid_scope = true,
            };
        }
        depth -= 1;
        active_scope_id = self.parent_id;
        if (!self.outermost) return .{ .counts = @splat(0), .first_violation = null };
        return .{ .counts = counts, .first_violation = first_violation };
    }
};

const operation_count = @typeInfo(Operation).@"enum".fields.len;
threadlocal var depth: usize = 0;
threadlocal var counts: [operation_count]u32 = @splat(0);
threadlocal var first_violation: ?Operation = null;
threadlocal var active_scope_id: u64 = 0;
threadlocal var next_scope_id: u64 = 1;

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

test "realtime audit contains duplicate and out-of-order scope release" {
    const outer = Scope.enter();
    const duplicate_outer = outer;
    const inner = Scope.enter();

    const out_of_order = outer.leave();
    try std.testing.expect(out_of_order.invalid_scope);
    try std.testing.expect(active());

    const inner_report = inner.leave();
    try std.testing.expect(inner_report.clean());
    try std.testing.expect(active());

    const outer_report = outer.leave();
    try std.testing.expect(outer_report.clean());
    try std.testing.expect(!active());

    const duplicate_report = duplicate_outer.leave();
    try std.testing.expect(duplicate_report.invalid_scope);
    try std.testing.expect(!active());

    const next = Scope.enter();
    const stale_report = duplicate_outer.leave();
    try std.testing.expect(stale_report.invalid_scope);
    try std.testing.expect(active());
    try std.testing.expect(next.leave().clean());
}

test "realtime audit rejects malformed scope tokens without state loss" {
    for (0..4_096) |_| {
        const outer = Scope.enter();
        const inner = Scope.enter();

        var wrong_id = inner;
        wrong_id.id +%= 1;
        try std.testing.expect(wrong_id.leave().invalid_scope);

        var wrong_parent = inner;
        wrong_parent.parent_id = 0;
        try std.testing.expect(wrong_parent.leave().invalid_scope);

        var wrong_kind = inner;
        wrong_kind.outermost = true;
        try std.testing.expect(wrong_kind.leave().invalid_scope);

        try std.testing.expect(inner.leave().clean());
        try std.testing.expect(outer.leave().clean());
        try std.testing.expect(!active());
    }
}

test "realtime audit contains saturated nesting state" {
    const saved_depth = depth;
    const saved_active_scope_id = active_scope_id;
    const saved_next_scope_id = next_scope_id;
    defer {
        depth = saved_depth;
        active_scope_id = saved_active_scope_id;
        next_scope_id = saved_next_scope_id;
    }

    depth = std.math.maxInt(usize);
    active_scope_id = 7;
    next_scope_id = 7;
    const rejected = Scope.enter();
    try std.testing.expectEqual(@as(u64, 0), rejected.id);
    try std.testing.expectEqual(std.math.maxInt(usize), depth);
    try std.testing.expect(rejected.leave().invalid_scope);
    try std.testing.expectEqual(@as(u64, 7), active_scope_id);
}
