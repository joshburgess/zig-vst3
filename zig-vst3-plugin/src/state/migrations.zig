const format = @import("format.zig");
const std = @import("std");

pub const ParameterIdMigration = format.ParameterIdMigration;

const MigrationResolution = union(enum) {
    resolved: u32,
    cyclic,
};

pub fn validateParameterIdMigrations(migrations: []const ParameterIdMigration) !void {
    if (identityParameterMigrationIndex(migrations) != null) return error.IdentityParameterMigration;
    if (duplicateParameterMigrationIndex(migrations) != null) return error.DuplicateParameterMigration;
    if (cyclicParameterMigrationIndex(migrations) != null) return error.CyclicParameterMigration;
    if (ambiguousParameterMigrationIndex(migrations) != null) return error.AmbiguousParameterMigration;
}

pub fn identityParameterMigrationIndex(migrations: []const ParameterIdMigration) ?usize {
    for (migrations, 0..) |migration, index| {
        if (migration.old_id == migration.new_id) return index;
    }
    return null;
}

pub fn duplicateParameterMigrationIndex(migrations: []const ParameterIdMigration) ?usize {
    return firstMigrationPairIndex(migrations, duplicateOldIds);
}

fn duplicateOldIds(left: ParameterIdMigration, right: ParameterIdMigration, _: []const ParameterIdMigration) bool {
    return left.old_id == right.old_id;
}

fn firstMigrationPairIndex(
    migrations: []const ParameterIdMigration,
    comptime matches: fn (ParameterIdMigration, ParameterIdMigration, []const ParameterIdMigration) bool,
) ?usize {
    for (migrations, 0..) |left, left_index| {
        for (migrations[left_index + 1 ..], left_index + 1..) |right, right_index| {
            if (matches(left, right, migrations)) return right_index;
        }
    }
    return null;
}

pub fn cyclicParameterMigrationIndex(migrations: []const ParameterIdMigration) ?usize {
    for (migrations, 0..) |migration, index| {
        if (migrationPathIsCyclic(migration.old_id, migrations)) return index;
    }
    return null;
}

pub fn ambiguousParameterMigrationIndex(migrations: []const ParameterIdMigration) ?usize {
    return firstMigrationPairIndex(migrations, migrationTargetsAreAmbiguous);
}

fn migrationTargetsAreAmbiguous(
    left: ParameterIdMigration,
    right: ParameterIdMigration,
    migrations: []const ParameterIdMigration,
) bool {
    const same_resolved_target = migratedParameterId(left.old_id, migrations) == migratedParameterId(right.old_id, migrations);
    if (!same_resolved_target) return false;

    const same_chain = migrationIdsShareChain(left.old_id, right.old_id, migrations);
    return !same_chain;
}

fn migrationIdsShareChain(left_id: u32, right_id: u32, migrations: []const ParameterIdMigration) bool {
    return migrationPathContains(left_id, right_id, migrations) or migrationPathContains(right_id, left_id, migrations);
}

fn migrationPathIsCyclic(start_id: u32, migrations: []const ParameterIdMigration) bool {
    return migrationResolution(start_id, migrations) == .cyclic;
}

fn migrationPathContains(start_id: u32, target_id: u32, migrations: []const ParameterIdMigration) bool {
    if (start_id == target_id) return true;

    var current = start_id;
    for (0..migrationStepLimit(migrations)) |_| {
        current = nextParameterMigrationId(current, migrations) orelse return false;
        if (current == target_id) return true;
    }
    return false;
}

pub fn migratedParameterId(id: u32, migrations: []const ParameterIdMigration) u32 {
    return switch (migrationResolution(id, migrations)) {
        .resolved => |resolved| resolved,
        .cyclic => id,
    };
}

fn migrationResolution(id: u32, migrations: []const ParameterIdMigration) MigrationResolution {
    var current = id;
    for (0..migrationStepLimit(migrations)) |_| {
        current = nextParameterMigrationId(current, migrations) orelse return .{ .resolved = current };
    }
    return .cyclic;
}

fn migrationStepLimit(migrations: []const ParameterIdMigration) usize {
    return migrations.len + 1;
}

fn nextParameterMigrationId(id: u32, migrations: []const ParameterIdMigration) ?u32 {
    for (migrations) |migration| {
        if (migration.old_id == id) return migration.new_id;
    }
    return null;
}

test "parameter migration validation accepts empty and chained migrations" {
    try validateParameterIdMigrations(&.{});

    const migrations = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 3 },
    };
    try validateParameterIdMigrations(&migrations);
    try std.testing.expectEqual(@as(u32, 3), migratedParameterId(1, &migrations));
    try std.testing.expectEqual(@as(u32, 3), migratedParameterId(2, &migrations));
    try std.testing.expectEqual(@as(u32, 4), migratedParameterId(4, &migrations));
}

test "parameter migration validation reports invalid migration tables" {
    const identity = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 1 },
    };
    try std.testing.expectEqual(@as(?usize, 0), identityParameterMigrationIndex(&identity));
    try std.testing.expectError(error.IdentityParameterMigration, validateParameterIdMigrations(&identity));

    const duplicate = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 1, .new_id = 3 },
    };
    try std.testing.expectEqual(@as(?usize, 1), duplicateParameterMigrationIndex(&duplicate));
    try std.testing.expectError(error.DuplicateParameterMigration, validateParameterIdMigrations(&duplicate));

    const cycle = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    };
    try std.testing.expectEqual(@as(?usize, 0), cyclicParameterMigrationIndex(&cycle));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&cycle));

    const ambiguous = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 3 },
        .{ .old_id = 2, .new_id = 3 },
    };
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&ambiguous));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&ambiguous));
}

test "parameter migration validation covers generated chains" {
    for (1..8) |chain_len| {
        var migrations: [7]ParameterIdMigration = undefined;
        for (0..chain_len) |index| {
            const old_id: u32 = @intCast(index + 1);
            migrations[index] = .{
                .old_id = old_id,
                .new_id = old_id + 1,
            };
        }

        const chain = migrations[0..chain_len];
        try validateParameterIdMigrations(chain);
        const terminal: u32 = @intCast(chain_len + 1);
        for (1..chain_len + 1) |id| {
            try std.testing.expectEqual(terminal, migratedParameterId(@intCast(id), chain));
        }
        try std.testing.expectEqual(@as(u32, 99), migratedParameterId(99, chain));
    }
}

test "parameter migration validation covers generated fan-in ambiguity" {
    for (3..10) |terminal| {
        const terminal_id: u32 = @intCast(terminal);
        const migrations = [_]ParameterIdMigration{
            .{ .old_id = 1, .new_id = terminal_id },
            .{ .old_id = 2, .new_id = terminal_id },
        };

        try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&migrations));
        try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&migrations));
    }
}

test "parameter migration validation covers generated cycles" {
    for (2..8) |cycle_len| {
        var migrations: [7]ParameterIdMigration = undefined;
        for (0..cycle_len) |index| {
            const old_id: u32 = @intCast(index + 1);
            const next_id: u32 = if (index + 1 == cycle_len) 1 else old_id + 1;
            migrations[index] = .{
                .old_id = old_id,
                .new_id = next_id,
            };
        }

        const cycle = migrations[0..cycle_len];
        try std.testing.expectEqual(@as(?usize, 0), cyclicParameterMigrationIndex(cycle));
        try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(cycle));
    }
}
