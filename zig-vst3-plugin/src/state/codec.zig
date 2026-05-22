const std = @import("std");
const common = @import("../common.zig");
const parameters = @import("../parameters.zig");
const format = @import("format.zig");
const migrations_mod = @import("migrations.zig");

pub const encodedSize = format.encodedSize;
pub const encodedSizeForCount = format.encodedSizeForCount;
pub const encodedSizeForCountChecked = format.encodedSizeForCountChecked;
pub const ParameterStateHeader = format.ParameterStateHeader;
pub const ParameterIdMigration = format.ParameterIdMigration;
pub const ReadParameterStateReport = format.ReadParameterStateReport;

const magic = format.magic;
const format_version = format.format_version;

const ParameterStateEntry = struct {
    id: u32,
    normalized: f64,
};

pub fn writeParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    comptime format.assertEncodableParameterCount(Params);
    try writeParameterStateHeaderForCount(parameters.ParameterSet(Params).count, writer);
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        const id = set.idAt(index);
        const normalized = values.loadAt(index);
        try writer.writeInt(u32, id, .little);
        try writer.writeInt(u64, @bitCast(normalized), .little);
    }
}

pub fn writeParameterStateHeaderForCount(count: usize, writer: anytype) !void {
    const encodable_count = std.math.cast(u16, count) orelse return error.ParameterStateTooLarge;
    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, encodable_count, .little);
}

pub fn readParameterStateHeader(reader: anytype) !ParameterStateHeader {
    var header: [magic.len]u8 = undefined;
    try reader.readSliceAll(&header);
    if (!std.mem.eql(u8, &header, magic)) return error.InvalidStateMagic;
    return .{
        .version = try reader.takeInt(u16, .little),
        .entry_count = try reader.takeInt(u16, .little),
    };
}

pub fn writeParameterStateJson(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    try writer.writeAll("{\"version\":");
    try writer.print("{}", .{format_version});
    try writer.writeAll(",\"parameters\":[");
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        if (index != 0) try writer.writeByte(',');
        const id = set.idAt(index);
        const name = set.nameAt(index);
        const normalized = values.loadAt(index);
        try writer.writeAll("{\"id\":");
        try writer.print("{}", .{id});
        try writer.writeAll(",\"name\":");
        try writer.print("{f}", .{std.json.fmt(name, .{})});
        try writer.writeAll(",\"normalized\":");
        try writer.print("{d}", .{normalized});
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
}

fn readParameterStateEntry(reader: anytype) !ParameterStateEntry {
    const id = try reader.takeInt(u32, .little);
    const normalized: f64 = @bitCast(try reader.takeInt(u64, .little));
    if (!common.isNormalized(normalized)) return error.ParameterStateOutsideNormalizedRange;
    return .{
        .id = id,
        .normalized = normalized,
    };
}

fn restoreParameterStateEntry(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    seen_restored: []bool,
    migrations: []const ParameterIdMigration,
    entry: ParameterStateEntry,
    report: *ReadParameterStateReport,
) !void {
    const restored_id = migrations_mod.migratedParameterId(entry.id, migrations);
    const index = set.indexOfId(restored_id) orelse {
        report.ignored_count += 1;
        return;
    };

    if (comptime parameters.ParameterSet(Params).count > 0) {
        if (seen_restored[index]) return error.DuplicateParameterStateEntry;
        seen_restored[index] = true;
    }

    const stored = values.store(index, entry.normalized);
    std.debug.assert(stored);
    report.restored_count += 1;
}

pub fn readParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
) !void {
    _ = try readParameterStateReport(Params, set, values, reader);
}

pub fn readParameterStateWithMigrations(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
    migrations: []const ParameterIdMigration,
) !void {
    _ = try readParameterStateWithMigrationsReport(Params, set, values, reader, migrations);
}

pub fn readParameterStateReport(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
) !ReadParameterStateReport {
    return readParameterStateWithMigrationsReport(Params, set, values, reader, &.{});
}

pub fn readParameterStateWithMigrationsReport(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *parameters.ParameterValues(Params),
    reader: anytype,
    migrations: []const ParameterIdMigration,
) !ReadParameterStateReport {
    try migrations_mod.validateParameterIdMigrations(migrations);
    const header = try readParameterStateHeader(reader);
    if (!header.isCurrentVersion()) return error.UnsupportedStateVersion;
    var restored = parameters.ParameterValues(Params).init(set);
    restored.copyFrom(values);
    var report = ReadParameterStateReport{
        .entry_count = header.entry_count,
        .restored_count = 0,
        .ignored_count = 0,
    };
    var seen_restored = [_]bool{false} ** parameters.ParameterSet(Params).count;
    for (0..header.entry_count) |_| {
        const entry = try readParameterStateEntry(reader);
        try restoreParameterStateEntry(Params, set, &restored, &seen_restored, migrations, entry, &report);
    }
    std.debug.assert(report.accountedCount() == report.entry_count);
    values.copyFrom(&restored);
    return report;
}
