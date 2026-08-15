const format = @import("format.zig");
const std = @import("std");

pub const ParameterIdMigration = format.ParameterIdMigration;
pub const maximum_parameter_id_migrations: usize = 256;

const MigrationResolution = union(enum) {
    resolved: u32,
    cyclic,
};

pub fn validateParameterIdMigrations(migrations: []const ParameterIdMigration) !void {
    _ = try MigrationIndex.init(migrations);
}

pub const MigrationIndex = struct {
    entries: [maximum_parameter_id_migrations]ParameterIdMigration = undefined,
    len: usize = 0,

    pub fn init(migrations: []const ParameterIdMigration) !MigrationIndex {
        if (migrations.len > maximum_parameter_id_migrations)
            return error.TooManyParameterIdMigrations;
        if (identityParameterMigrationIndex(migrations) != null)
            return error.IdentityParameterMigration;
        if (duplicateParameterMigrationIndex(migrations) != null)
            return error.DuplicateParameterMigration;
        const result = initSorted(migrations);
        if (result.cyclicMigrationIndex(migrations) != null)
            return error.CyclicParameterMigration;
        if (duplicateNewMigrationIndex(migrations) != null)
            return error.AmbiguousParameterMigration;
        return result;
    }

    fn initSorted(migrations: []const ParameterIdMigration) MigrationIndex {
        var result = MigrationIndex{};
        result.len = migrations.len;
        @memcpy(result.entries[0..migrations.len], migrations);
        var index: usize = 1;
        while (index < result.len) : (index += 1) {
            const value = result.entries[index];
            var insertion = index;
            while (insertion != 0 and
                result.entries[insertion - 1].old_id > value.old_id)
            {
                result.entries[insertion] = result.entries[insertion - 1];
                insertion -= 1;
            }
            result.entries[insertion] = value;
        }
        return result;
    }

    pub fn migratedParameterId(
        self: *const MigrationIndex,
        id: u32,
    ) u32 {
        return switch (self.resolution(id)) {
            .resolved => |resolved| resolved,
            .cyclic => id,
        };
    }

    fn cyclicMigrationIndex(
        self: *const MigrationIndex,
        migrations: []const ParameterIdMigration,
    ) ?usize {
        for (migrations, 0..) |migration, index| {
            if (self.resolution(migration.old_id) == .cyclic)
                return index;
        }
        return null;
    }

    fn resolution(
        self: *const MigrationIndex,
        id: u32,
    ) MigrationResolution {
        var current = id;
        for (0..self.len + 1) |_| {
            current = self.nextId(current) orelse
                return .{ .resolved = current };
        }
        return .cyclic;
    }

    fn nextId(self: *const MigrationIndex, id: u32) ?u32 {
        var start: usize = 0;
        var end = self.len;
        while (start < end) {
            const middle = start + (end - start) / 2;
            const migration = self.entries[middle];
            if (id < migration.old_id) {
                end = middle;
            } else if (id > migration.old_id) {
                start = middle + 1;
            } else {
                return migration.new_id;
            }
        }
        return null;
    }
};

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
    if (cyclicParameterMigrationIndex(migrations) != null) return null;
    return duplicateNewMigrationIndex(migrations);
}

fn duplicateNewMigrationIndex(
    migrations: []const ParameterIdMigration,
) ?usize {
    // With unique old IDs and no cycles, independent chains converge exactly
    // when two edges have the same destination.
    return firstMigrationPairIndex(migrations, duplicateNewIds);
}

fn duplicateNewIds(
    left: ParameterIdMigration,
    right: ParameterIdMigration,
    _: []const ParameterIdMigration,
) bool {
    return left.new_id == right.new_id;
}

fn migrationPathIsCyclic(start_id: u32, migrations: []const ParameterIdMigration) bool {
    return migrationResolution(start_id, migrations) == .cyclic;
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

test "parameter migration validation bounds and indexes migration work" {
    var too_many: [maximum_parameter_id_migrations + 1]ParameterIdMigration =
        undefined;
    try std.testing.expectError(
        error.TooManyParameterIdMigrations,
        validateParameterIdMigrations(&too_many),
    );

    const migrations = [_]ParameterIdMigration{
        .{ .old_id = 9, .new_id = 11 },
        .{ .old_id = 1, .new_id = 7 },
        .{ .old_id = 7, .new_id = 9 },
    };
    const index = try MigrationIndex.init(&migrations);
    try std.testing.expectEqual(@as(u32, 11), index.migratedParameterId(1));
    try std.testing.expectEqual(@as(u32, 11), index.migratedParameterId(7));
    try std.testing.expectEqual(@as(u32, 11), index.migratedParameterId(9));
    try std.testing.expectEqual(@as(u32, 12), index.migratedParameterId(12));
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
