const format = @import("format.zig");

pub const ParameterIdMigration = format.ParameterIdMigration;

pub fn validateParameterIdMigrations(migrations: []const ParameterIdMigration) !void {
    for (migrations, 0..) |left, left_index| {
        if (left.old_id == left.new_id) return error.IdentityParameterMigration;
        for (migrations[left_index + 1 ..]) |right| {
            if (left.old_id == right.old_id) return error.DuplicateParameterMigration;
        }
    }
    for (migrations) |migration| {
        if (migrationPathIsCyclic(migration.old_id, migrations)) return error.CyclicParameterMigration;
    }
    for (migrations, 0..) |left, left_index| {
        const left_target = migratedParameterId(left.old_id, migrations);
        for (migrations[left_index + 1 ..]) |right| {
            if (migrationTargetsAreAmbiguous(left.old_id, left_target, right.old_id, migrations)) {
                return error.AmbiguousParameterMigration;
            }
        }
    }
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
    var current = start_id;
    for (0..migrations.len + 1) |_| {
        current = nextParameterMigrationId(current, migrations) orelse return false;
    }
    return true;
}

fn migrationPathContains(start_id: u32, target_id: u32, migrations: []const ParameterIdMigration) bool {
    if (start_id == target_id) return true;

    var current = start_id;
    for (0..migrations.len + 1) |_| {
        current = nextParameterMigrationId(current, migrations) orelse return false;
        if (current == target_id) return true;
    }
    return false;
}

pub fn migratedParameterId(id: u32, migrations: []const ParameterIdMigration) u32 {
    var current = id;
    for (0..migrations.len + 1) |_| {
        current = nextParameterMigrationId(current, migrations) orelse return current;
    }
    return id;
}

fn nextParameterMigrationId(id: u32, migrations: []const ParameterIdMigration) ?u32 {
    for (migrations) |migration| {
        if (migration.old_id == id) return migration.new_id;
    }
    return null;
}
