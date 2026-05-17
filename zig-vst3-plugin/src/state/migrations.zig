const format = @import("format.zig");

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
    for (migrations, 0..) |left, left_index| {
        for (migrations[left_index + 1 ..], left_index + 1..) |right, right_index| {
            if (left.old_id == right.old_id) return right_index;
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
    for (migrations, 0..) |left, left_index| {
        const left_target = migratedParameterId(left.old_id, migrations);
        for (migrations[left_index + 1 ..], left_index + 1..) |right, right_index| {
            if (migrationTargetsAreAmbiguous(
                left.old_id,
                left_target,
                right.old_id,
                migrations,
            )) return right_index;
        }
    }
    return null;
}

fn migrationTargetsAreAmbiguous(
    left_id: u32,
    left_target: u32,
    right_id: u32,
    migrations: []const ParameterIdMigration,
) bool {
    return left_target == migratedParameterId(right_id, migrations) and !migrationIdsShareChain(left_id, right_id, migrations);
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
