const std = @import("std");
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

pub fn writeParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    comptime format.assertEncodableParameterCount(Params);
    try writeParameterStateHeaderForCount(parameters.ParameterSet(Params).count, writer);
    inline for (0..parameters.ParameterSet(Params).count) |index| {
        try writer.writeInt(u32, set.id(index).?, .little);
        try writer.writeInt(u64, @bitCast(values.load(index).?), .little);
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
        try writer.writeAll("{\"id\":");
        try writer.print("{}", .{set.id(index).?});
        try writer.writeAll(",\"name\":");
        try writer.print("{f}", .{std.json.fmt(set.name(index).?, .{})});
        try writer.writeAll(",\"normalized\":");
        try writer.print("{d}", .{values.load(index).?});
        try writer.writeByte('}');
    }
    try writer.writeAll("]}");
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
        const id = try reader.takeInt(u32, .little);
        const normalized: f64 = @bitCast(try reader.takeInt(u64, .little));
        if (!std.math.isFinite(normalized) or normalized < 0.0 or normalized > 1.0) return error.ParameterStateOutsideNormalizedRange;
        if (set.indexOfId(migrations_mod.migratedParameterId(id, migrations))) |index| {
            if (comptime parameters.ParameterSet(Params).count > 0) {
                if (seen_restored[index]) return error.DuplicateParameterStateEntry;
                seen_restored[index] = true;
            }
            _ = restored.store(index, normalized);
            report.restored_count += 1;
        } else {
            report.ignored_count += 1;
        }
    }
    values.copyFrom(&restored);
    return report;
}
