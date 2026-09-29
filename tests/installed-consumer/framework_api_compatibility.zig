const std = @import("std");
const baseline = @import("rc1_api_baseline.zig");
const manifest = @import("framework_api_manifest.zig");

const Root = enum {
    plugin,
    core,
};

const Change = enum {
    removed,
    reclassified,
};

const Migration = struct {
    root: Root,
    name: []const u8,
    change: Change,
    deprecated_in: []const u8,
    effective_in: []const u8,
    last_supported_release: []const u8,
    replacement: []const u8,
    release_note: []const u8,
};

const ReleaseLine = struct {
    major: u32,
    minor: u32,
};

const approved_migrations = [_]Migration{};

fn currentClassification(name: []const u8, entries: []const manifest.Entry) ?manifest.Classification {
    for (entries) |entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry.classification;
    }
    return null;
}

fn listsMatch(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left) |left_name| {
        var found = false;
        for (right) |right_name| {
            if (std.mem.eql(u8, left_name, right_name)) found = true;
        }
        if (!found) return false;
    }
    return true;
}

fn classifiedNames(
    comptime classification: manifest.Classification,
    comptime entries: []const manifest.Entry,
) [countClassification(classification, entries)][]const u8 {
    var names: [countClassification(classification, entries)][]const u8 = undefined;
    var index: usize = 0;
    for (entries) |entry| {
        if (entry.classification == classification) {
            names[index] = entry.name;
            index += 1;
        }
    }
    return names;
}

fn countClassification(
    comptime classification: manifest.Classification,
    comptime entries: []const manifest.Entry,
) usize {
    var count: usize = 0;
    for (entries) |entry| {
        if (entry.classification == classification) count += 1;
    }
    return count;
}

fn releaseLine(version: []const u8) ?ReleaseLine {
    var parts = std.mem.splitScalar(u8, version, '.');
    const major_text = parts.next() orelse return null;
    const minor_text = parts.next() orelse return null;
    if (major_text.len == 0 or minor_text.len == 0) return null;
    const major = std.fmt.parseUnsigned(u32, major_text, 10) catch return null;
    const minor = std.fmt.parseUnsigned(u32, minor_text, 10) catch return null;
    return .{ .major = major, .minor = minor };
}

fn isLaterLine(candidate: ReleaseLine, earlier: ReleaseLine) bool {
    return candidate.major > earlier.major or
        (candidate.major == earlier.major and candidate.minor > earlier.minor);
}

fn migrationIsComplete(migration: Migration) bool {
    const deprecated_line = releaseLine(migration.deprecated_in) orelse return false;
    const effective_line = releaseLine(migration.effective_in) orelse return false;
    const last_supported_line = releaseLine(migration.last_supported_release) orelse return false;
    return migration.name.len != 0 and
        migration.deprecated_in.len != 0 and
        migration.effective_in.len != 0 and
        migration.last_supported_release.len != 0 and
        migration.replacement.len != 0 and
        migration.release_note.len != 0 and
        deprecated_line.major == last_supported_line.major and
        deprecated_line.minor == last_supported_line.minor and
        isLaterLine(effective_line, deprecated_line);
}

fn hasApprovedMigration(
    root: Root,
    name: []const u8,
    change: Change,
    migrations: []const Migration,
) bool {
    for (migrations) |migration| {
        if (migration.root == root and
            migration.change == change and
            std.mem.eql(u8, migration.name, name))
        {
            return migrationIsComplete(migration);
        }
    }
    return false;
}

fn baselineMatches(
    root: Root,
    names: []const []const u8,
    entries: []const manifest.Entry,
    migrations: []const Migration,
) bool {
    for (names) |name| {
        const classification = currentClassification(name, entries);
        if (classification == .compatibility_ready) continue;
        const change: Change = if (classification == null) .removed else .reclassified;
        if (!hasApprovedMigration(root, name, change, migrations)) return false;
    }
    return true;
}

test "RC1 compatibility-ready declarations remain compatibility-ready" {
    try std.testing.expectEqualStrings(
        "7650781a5625c041ec474a5377d859a427a344f3",
        baseline.candidate_commit,
    );
    try std.testing.expect(baselineMatches(
        .plugin,
        &baseline.plugin_compatibility_ready,
        &manifest.plugin_api,
        &approved_migrations,
    ));
    try std.testing.expect(baselineMatches(
        .core,
        &baseline.core_compatibility_ready,
        &manifest.core_api,
        &approved_migrations,
    ));
}

test "frozen RC1 baseline was captured from the candidate manifest" {
    const plugin_names = comptime classifiedNames(.compatibility_ready, &manifest.plugin_api);
    const core_names = comptime classifiedNames(.compatibility_ready, &manifest.core_api);
    try std.testing.expect(listsMatch(&baseline.plugin_compatibility_ready, &plugin_names));
    try std.testing.expect(listsMatch(&baseline.core_compatibility_ready, &core_names));
}

test "baseline rejects silent removal and reclassification" {
    const removed = [_]manifest.Entry{};
    const reclassified = [_]manifest.Entry{
        .{ .name = "version", .classification = .experimental },
    };
    try std.testing.expect(!baselineMatches(.plugin, &.{"version"}, &removed, &.{}));
    try std.testing.expect(!baselineMatches(.plugin, &.{"version"}, &reclassified, &.{}));
}

test "baseline requires a complete policy migration" {
    const removed = [_]manifest.Entry{};
    const incomplete = [_]Migration{.{
        .root = .plugin,
        .name = "version",
        .change = .removed,
        .deprecated_in = "0.3.1",
        .effective_in = "0.4.0",
        .last_supported_release = "0.3.9",
        .replacement = "",
        .release_note = "docs/releases/0.4.0.md",
    }};
    const complete = [_]Migration{.{
        .root = .plugin,
        .name = "version",
        .change = .removed,
        .deprecated_in = "0.3.1",
        .effective_in = "0.4.0",
        .last_supported_release = "0.3.9",
        .replacement = "zig-vst3-plugin.release_version",
        .release_note = "docs/releases/0.4.0.md",
    }};
    try std.testing.expect(!baselineMatches(.plugin, &.{"version"}, &removed, &incomplete));
    try std.testing.expect(baselineMatches(.plugin, &.{"version"}, &removed, &complete));
}

test "baseline rejects removal inside the promised minor line" {
    const removed = [_]manifest.Entry{};
    const same_line = [_]Migration{.{
        .root = .plugin,
        .name = "version",
        .change = .removed,
        .deprecated_in = "0.3.1",
        .effective_in = "0.3.2",
        .last_supported_release = "0.3.1",
        .replacement = "zig-vst3-plugin.release_version",
        .release_note = "docs/releases/0.3.2.md",
    }};
    try std.testing.expect(!baselineMatches(.plugin, &.{"version"}, &removed, &same_line));
}
