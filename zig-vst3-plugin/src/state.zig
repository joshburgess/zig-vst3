const std = @import("std");
const parameters = @import("parameters.zig");

const magic = "ZPLGSTAT";
pub const format_version: u16 = 1;
pub const encoded_header_size: usize = magic.len + @sizeOf(u16) + @sizeOf(u16);
pub const encoded_entry_size: usize = @sizeOf(u32) + @sizeOf(u64);

pub const ParameterStateHeader = struct {
    version: u16,
    entry_count: usize,

    pub fn entryCount(self: ParameterStateHeader) usize {
        return self.entry_count;
    }

    pub fn hasEntries(self: ParameterStateHeader) bool {
        return self.entry_count != 0;
    }

    pub fn hasNoEntries(self: ParameterStateHeader) bool {
        return self.entry_count == 0;
    }

    pub fn entriesEmpty(self: ParameterStateHeader) bool {
        return self.hasNoEntries();
    }

    pub fn isCurrentVersion(self: ParameterStateHeader) bool {
        return self.version == format_version;
    }

    pub fn matchesEntryCount(self: ParameterStateHeader, expected_count: usize) bool {
        return self.entry_count == expected_count;
    }

    pub fn hasFewerEntriesThan(self: ParameterStateHeader, expected_count: usize) bool {
        return self.entry_count < expected_count;
    }

    pub fn hasMoreEntriesThan(self: ParameterStateHeader, expected_count: usize) bool {
        return self.entry_count > expected_count;
    }

    pub fn missingEntryCount(self: ParameterStateHeader, expected_count: usize) usize {
        return expected_count -| self.entry_count;
    }

    pub fn extraEntryCount(self: ParameterStateHeader, expected_count: usize) usize {
        return self.entry_count -| expected_count;
    }

    pub fn encodedSize(self: ParameterStateHeader) usize {
        return encodedSizeForCount(self.entry_count);
    }

    pub fn encodedSizeChecked(self: ParameterStateHeader) !usize {
        return encodedSizeForCountChecked(self.entry_count);
    }
};

pub const ParameterIdMigration = struct {
    old_id: u32,
    new_id: u32,
};

pub const ReadParameterStateClassification = enum {
    empty,
    restored_all,
    ignored_all,
    restored_and_ignored,
    partial,
};

pub const ReadParameterStateReport = struct {
    entry_count: usize,
    restored_count: usize,
    ignored_count: usize,

    pub fn decodedCount(self: ReadParameterStateReport) usize {
        return self.entry_count;
    }

    pub fn restoredCount(self: ReadParameterStateReport) usize {
        return self.restored_count;
    }

    pub fn ignoredCount(self: ReadParameterStateReport) usize {
        return self.ignored_count;
    }

    pub fn accountedCount(self: ReadParameterStateReport) usize {
        return self.restored_count + self.ignored_count;
    }

    pub fn unaccountedCount(self: ReadParameterStateReport) usize {
        return self.entry_count -| self.accountedCount();
    }

    pub fn matchesDecodedCount(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.entry_count == expected_count;
    }

    pub fn hasFewerDecodedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.entry_count < expected_count;
    }

    pub fn hasMoreDecodedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.entry_count > expected_count;
    }

    pub fn missingDecodedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return expected_count -| self.entry_count;
    }

    pub fn extraDecodedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return self.entry_count -| expected_count;
    }

    pub fn matchesRestoredCount(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.restored_count == expected_count;
    }

    pub fn hasFewerRestoredEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.restored_count < expected_count;
    }

    pub fn hasMoreRestoredEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.restored_count > expected_count;
    }

    pub fn missingRestoredEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return expected_count -| self.restored_count;
    }

    pub fn extraRestoredEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return self.restored_count -| expected_count;
    }

    pub fn matchesIgnoredCount(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.ignored_count == expected_count;
    }

    pub fn hasFewerIgnoredEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.ignored_count < expected_count;
    }

    pub fn hasMoreIgnoredEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.ignored_count > expected_count;
    }

    pub fn missingIgnoredEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return expected_count -| self.ignored_count;
    }

    pub fn extraIgnoredEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return self.ignored_count -| expected_count;
    }

    pub fn matchesAccountedCount(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.accountedCount() == expected_count;
    }

    pub fn hasFewerAccountedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.accountedCount() < expected_count;
    }

    pub fn hasMoreAccountedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.accountedCount() > expected_count;
    }

    pub fn missingAccountedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return expected_count -| self.accountedCount();
    }

    pub fn extraAccountedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return self.accountedCount() -| expected_count;
    }

    pub fn matchesUnaccountedCount(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.unaccountedCount() == expected_count;
    }

    pub fn hasFewerUnaccountedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.unaccountedCount() < expected_count;
    }

    pub fn hasMoreUnaccountedEntriesThan(self: ReadParameterStateReport, expected_count: usize) bool {
        return self.unaccountedCount() > expected_count;
    }

    pub fn missingUnaccountedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return expected_count -| self.unaccountedCount();
    }

    pub fn extraUnaccountedEntryCount(self: ReadParameterStateReport, expected_count: usize) usize {
        return self.unaccountedCount() -| expected_count;
    }

    pub fn hasDecodedEntries(self: ReadParameterStateReport) bool {
        return self.entry_count != 0;
    }

    pub fn hasNoDecodedEntries(self: ReadParameterStateReport) bool {
        return self.entry_count == 0;
    }

    pub fn decodedEntriesEmpty(self: ReadParameterStateReport) bool {
        return self.hasNoDecodedEntries();
    }

    pub fn hasRestoredEntries(self: ReadParameterStateReport) bool {
        return self.restored_count != 0;
    }

    pub fn hasNoRestoredEntries(self: ReadParameterStateReport) bool {
        return self.restored_count == 0;
    }

    pub fn restoredEntriesEmpty(self: ReadParameterStateReport) bool {
        return self.hasNoRestoredEntries();
    }

    pub fn hasIgnoredEntries(self: ReadParameterStateReport) bool {
        return self.ignored_count != 0;
    }

    pub fn hasNoIgnoredEntries(self: ReadParameterStateReport) bool {
        return self.ignored_count == 0;
    }

    pub fn ignoredEntriesEmpty(self: ReadParameterStateReport) bool {
        return self.hasNoIgnoredEntries();
    }

    pub fn hasUnaccountedEntries(self: ReadParameterStateReport) bool {
        return self.unaccountedCount() != 0;
    }

    pub fn hasNoUnaccountedEntries(self: ReadParameterStateReport) bool {
        return self.unaccountedCount() == 0;
    }

    pub fn unaccountedEntriesEmpty(self: ReadParameterStateReport) bool {
        return self.hasNoUnaccountedEntries();
    }

    pub fn accountedAllEntries(self: ReadParameterStateReport) bool {
        return self.accountedCount() == self.entry_count;
    }

    pub fn accountedPartialEntries(self: ReadParameterStateReport) bool {
        const accounted = self.accountedCount();
        return accounted != 0 and accounted < self.entry_count;
    }

    pub fn restoredAllEntries(self: ReadParameterStateReport) bool {
        return self.restored_count == self.entry_count and self.ignored_count == 0;
    }

    pub fn restoredPartialEntries(self: ReadParameterStateReport) bool {
        return self.restored_count != 0 and self.restored_count < self.entry_count;
    }

    pub fn ignoredAllEntries(self: ReadParameterStateReport) bool {
        return self.entry_count != 0 and self.ignored_count == self.entry_count and self.restored_count == 0;
    }

    pub fn ignoredPartialEntries(self: ReadParameterStateReport) bool {
        return self.ignored_count != 0 and self.ignored_count < self.entry_count;
    }

    pub fn restoredAndIgnoredEntries(self: ReadParameterStateReport) bool {
        return self.restored_count != 0 and self.ignored_count != 0;
    }

    pub fn fullyHandled(self: ReadParameterStateReport) bool {
        return self.accountedAllEntries();
    }

    pub fn classification(self: ReadParameterStateReport) ReadParameterStateClassification {
        if (self.entry_count == 0) return .empty;
        if (!self.accountedAllEntries()) return .partial;
        if (self.restoredAllEntries()) return .restored_all;
        if (self.ignoredAllEntries()) return .ignored_all;
        return .restored_and_ignored;
    }

    pub fn isEmptyClassification(self: ReadParameterStateReport) bool {
        return self.classification() == .empty;
    }

    pub fn isRestoredAllClassification(self: ReadParameterStateReport) bool {
        return self.classification() == .restored_all;
    }

    pub fn isIgnoredAllClassification(self: ReadParameterStateReport) bool {
        return self.classification() == .ignored_all;
    }

    pub fn isRestoredAndIgnoredClassification(self: ReadParameterStateReport) bool {
        return self.classification() == .restored_and_ignored;
    }

    pub fn isPartialClassification(self: ReadParameterStateReport) bool {
        return self.classification() == .partial;
    }
};

pub fn encodedSize(comptime Params: type) usize {
    assertEncodableParameterCount(Params);
    return encodedSizeForCount(parameters.ParameterSet(Params).count);
}

pub fn encodedSizeForCount(count: usize) usize {
    return encodedSizeForCountChecked(count) catch std.math.maxInt(usize);
}

pub fn encodedSizeForCountChecked(count: usize) !usize {
    const entries_size = try std.math.mul(usize, count, encoded_entry_size);
    return std.math.add(usize, encoded_header_size, entries_size);
}

fn assertEncodableParameterCount(comptime Params: type) void {
    if (parameters.ParameterSet(Params).count > std.math.maxInt(u16)) {
        @compileError("parameter state format supports at most 65535 parameters");
    }
}

pub fn writeParameterState(
    comptime Params: type,
    set: *const parameters.ParameterSet(Params),
    values: *const parameters.ParameterValues(Params),
    writer: anytype,
) !void {
    comptime assertEncodableParameterCount(Params);
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
    try reader.readNoEof(&header);
    if (!std.mem.eql(u8, &header, magic)) return error.InvalidStateMagic;
    return .{
        .version = try reader.readInt(u16, .little),
        .entry_count = try reader.readInt(u16, .little),
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
        try std.json.stringify(set.name(index).?, .{}, writer);
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
    try validateParameterIdMigrations(migrations);
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
        const id = try reader.readInt(u32, .little);
        const normalized: f64 = @bitCast(try reader.readInt(u64, .little));
        if (!std.math.isFinite(normalized) or normalized < 0.0 or normalized > 1.0) return error.ParameterStateOutsideNormalizedRange;
        if (set.indexOfId(migratedParameterId(id, migrations))) |index| {
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

pub fn validateParameterIdMigrations(migrations: []const ParameterIdMigration) !void {
    for (migrations, 0..) |left, left_index| {
        if (left.old_id == left.new_id) return error.IdentityParameterMigration;
        for (migrations[left_index + 1 ..]) |right| {
            if (left.old_id == right.old_id) return error.DuplicateParameterMigration;
        }
    }
    for (migrations) |migration| {
        var current = migration.old_id;
        for (0..migrations.len + 1) |_| {
            var next: ?u32 = null;
            for (migrations) |candidate| {
                if (candidate.old_id == current) {
                    next = candidate.new_id;
                    break;
                }
            }
            current = next orelse break;
        } else {
            return error.CyclicParameterMigration;
        }
    }
    for (migrations, 0..) |left, left_index| {
        const left_target = migratedParameterId(left.old_id, migrations);
        for (migrations[left_index + 1 ..]) |right| {
            if (left_target == migratedParameterId(right.old_id, migrations)) {
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
        for (migrations, 0..) |right, right_index| {
            if (right_index > left_index and left.old_id == right.old_id) return right_index;
        }
    }
    return null;
}

pub fn ambiguousParameterMigrationIndex(migrations: []const ParameterIdMigration) ?usize {
    for (migrations, 0..) |left, left_index| {
        const left_target = migratedParameterId(left.old_id, migrations);
        for (migrations, 0..) |right, right_index| {
            if (right_index > left_index and left_target == migratedParameterId(right.old_id, migrations)) return right_index;
        }
    }
    return null;
}

pub fn migratedParameterId(id: u32, migrations: []const ParameterIdMigration) u32 {
    var current = id;
    for (0..migrations.len + 1) |_| {
        var next: ?u32 = null;
        for (migrations) |migration| {
            if (migration.old_id == current) {
                next = migration.new_id;
                break;
            }
        }
        current = next orelse return current;
    }
    return id;
}

test "parameter state round-trips normalized values" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var restored = Values.init(&set);
    var bytes: [encodedSize(Params)]u8 = undefined;

    try std.testing.expectEqual(@as(usize, 12), encoded_header_size);
    try std.testing.expectEqual(@as(usize, 12), encoded_entry_size);
    try std.testing.expectEqual(@as(usize, 36), encodedSizeForCount(2));
    try std.testing.expectEqual(@as(usize, 36), try encodedSizeForCountChecked(2));
    try std.testing.expectEqual(@as(usize, 36), encodedSize(Params));
    try std.testing.expectError(error.Overflow, encodedSizeForCountChecked(std.math.maxInt(usize)));
    try std.testing.expectEqual(std.math.maxInt(usize), encodedSizeForCount(std.math.maxInt(usize)));
    try std.testing.expect(values.storeField(&set, "gain", 0.25));
    try std.testing.expect(values.storeField(&set, "mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(Params, &set, &values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const header = try readParameterStateHeader(in_stream.reader());
    try std.testing.expectEqual(ParameterStateHeader{ .version = format_version, .entry_count = 2 }, header);
    try std.testing.expectEqual(@as(usize, 2), header.entryCount());
    try std.testing.expect(header.hasEntries());
    try std.testing.expect(!header.hasNoEntries());
    try std.testing.expect(!header.entriesEmpty());
    try std.testing.expect(header.isCurrentVersion());
    try std.testing.expect(header.matchesEntryCount(2));
    try std.testing.expect(!header.matchesEntryCount(3));
    try std.testing.expect(header.hasFewerEntriesThan(3));
    try std.testing.expect(!header.hasFewerEntriesThan(2));
    try std.testing.expect(header.hasMoreEntriesThan(1));
    try std.testing.expect(!header.hasMoreEntriesThan(2));
    try std.testing.expectEqual(@as(usize, 1), header.missingEntryCount(3));
    try std.testing.expectEqual(@as(usize, 0), header.missingEntryCount(1));
    try std.testing.expectEqual(@as(usize, 1), header.extraEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), header.extraEntryCount(3));
    try std.testing.expectEqual(@as(usize, 36), header.encodedSize());
    try std.testing.expectEqual(@as(usize, 36), try header.encodedSizeChecked());

    in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateReport(Params, &set, &restored, in_stream.reader());

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 2, .restored_count = 2, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(usize, 2), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 2), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 0), report.ignoredCount());
    try std.testing.expectEqual(@as(usize, 2), report.accountedCount());
    try std.testing.expectEqual(@as(usize, 0), report.unaccountedCount());
    try std.testing.expect(report.matchesDecodedCount(2));
    try std.testing.expect(!report.matchesDecodedCount(3));
    try std.testing.expect(report.hasFewerDecodedEntriesThan(3));
    try std.testing.expect(!report.hasFewerDecodedEntriesThan(2));
    try std.testing.expect(report.hasMoreDecodedEntriesThan(1));
    try std.testing.expect(!report.hasMoreDecodedEntriesThan(2));
    try std.testing.expectEqual(@as(usize, 1), report.missingDecodedEntryCount(3));
    try std.testing.expectEqual(@as(usize, 0), report.missingDecodedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 1), report.extraDecodedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), report.extraDecodedEntryCount(3));
    try std.testing.expect(report.matchesRestoredCount(2));
    try std.testing.expect(!report.matchesRestoredCount(3));
    try std.testing.expect(report.hasFewerRestoredEntriesThan(3));
    try std.testing.expect(!report.hasFewerRestoredEntriesThan(2));
    try std.testing.expect(report.hasMoreRestoredEntriesThan(1));
    try std.testing.expect(!report.hasMoreRestoredEntriesThan(2));
    try std.testing.expectEqual(@as(usize, 1), report.missingRestoredEntryCount(3));
    try std.testing.expectEqual(@as(usize, 0), report.missingRestoredEntryCount(1));
    try std.testing.expectEqual(@as(usize, 1), report.extraRestoredEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), report.extraRestoredEntryCount(3));
    try std.testing.expect(report.matchesIgnoredCount(0));
    try std.testing.expect(report.hasFewerIgnoredEntriesThan(1));
    try std.testing.expect(!report.hasMoreIgnoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), report.missingIgnoredEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), report.extraIgnoredEntryCount(1));
    try std.testing.expect(report.matchesAccountedCount(2));
    try std.testing.expect(report.hasFewerAccountedEntriesThan(3));
    try std.testing.expect(report.hasMoreAccountedEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 1), report.missingAccountedEntryCount(3));
    try std.testing.expectEqual(@as(usize, 1), report.extraAccountedEntryCount(1));
    try std.testing.expect(report.matchesUnaccountedCount(0));
    try std.testing.expect(report.hasFewerUnaccountedEntriesThan(1));
    try std.testing.expect(!report.hasMoreUnaccountedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), report.missingUnaccountedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), report.extraUnaccountedEntryCount(1));
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasIgnoredEntries());
    try std.testing.expect(!report.decodedEntriesEmpty());
    try std.testing.expect(!report.restoredEntriesEmpty());
    try std.testing.expect(report.ignoredEntriesEmpty());
    try std.testing.expect(!report.hasUnaccountedEntries());
    try std.testing.expect(report.hasNoUnaccountedEntries());
    try std.testing.expect(report.unaccountedEntriesEmpty());
    try std.testing.expect(report.fullyHandled());
    try std.testing.expectEqual(ReadParameterStateClassification.restored_all, report.classification());
    try std.testing.expect(!report.isEmptyClassification());
    try std.testing.expect(report.isRestoredAllClassification());
    try std.testing.expect(!report.isIgnoredAllClassification());
    try std.testing.expect(!report.isRestoredAndIgnoredClassification());
    try std.testing.expect(!report.isPartialClassification());
    try std.testing.expect(report.accountedAllEntries());
    try std.testing.expect(!report.accountedPartialEntries());
    try std.testing.expect(report.restoredAllEntries());
    try std.testing.expect(!report.restoredPartialEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expect(!report.ignoredPartialEntries());
    try std.testing.expect(!report.restoredAndIgnoredEntries());
    try std.testing.expectEqual(@as(f64, 0.25), restored.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.75), restored.loadField(&set, "mix"));
}

test "parameter state header helpers validate magic and count range" {
    var bytes: [encoded_header_size]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);

    try writeParameterStateHeaderForCount(0, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const header = try readParameterStateHeader(in_stream.reader());
    try std.testing.expectEqual(ParameterStateHeader{ .version = format_version, .entry_count = 0 }, header);
    try std.testing.expect(!header.hasEntries());
    try std.testing.expect(header.entriesEmpty());
    try std.testing.expect(header.isCurrentVersion());
    try std.testing.expectEqual(encoded_header_size, header.encodedSize());

    try std.testing.expectError(
        error.ParameterStateTooLarge,
        writeParameterStateHeaderForCount(@as(usize, std.math.maxInt(u16)) + 1, out_stream.writer()),
    );

    var bad_magic = bytes;
    bad_magic[0] = 'X';
    var bad_magic_stream = std.io.fixedBufferStream(&bad_magic);
    try std.testing.expectError(error.InvalidStateMagic, readParameterStateHeader(bad_magic_stream.reader()));
}

test "parameter state writes debug json" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [160]u8 = undefined;

    try std.testing.expect(values.storeField(&set, "gain", 0.25));
    try std.testing.expect(values.storeField(&set, "mix", 0.75));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterStateJson(Params, &set, &values, out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain\",\"normalized\":0.25},{\"id\":1,\"name\":\"Mix\",\"normalized\":0.75}]}",
        out_stream.getWritten(),
    );
}

test "parameter state debug json escapes names" {
    const Params = struct {
        quoted: parameters.FloatParam = parameters.FloatParam.init(0, "Gain \"A\\B\"", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [128]u8 = undefined;

    try std.testing.expect(values.storeField(&set, "quoted", 0.25));

    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterStateJson(Params, &set, &values, out_stream.writer());

    try std.testing.expectEqualStrings(
        "{\"version\":1,\"parameters\":[{\"id\":0,\"name\":\"Gain \\\"A\\\\B\\\"\",\"normalized\":0.25}]}",
        out_stream.getWritten(),
    );
}

test "parameter state ignores unknown parameter ids" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + 2 * (@sizeOf(u32) + @sizeOf(u64))]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 999, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.75)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateReport(Params, &set, &values, in_stream.reader());

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 2, .restored_count = 1, .ignored_count = 1 }, report);
    try std.testing.expectEqual(@as(usize, 2), report.decodedCount());
    try std.testing.expectEqual(@as(usize, 1), report.restoredCount());
    try std.testing.expectEqual(@as(usize, 1), report.ignoredCount());
    try std.testing.expectEqual(@as(usize, 2), report.accountedCount());
    try std.testing.expectEqual(@as(usize, 0), report.unaccountedCount());
    try std.testing.expect(report.hasDecodedEntries());
    try std.testing.expect(report.hasRestoredEntries());
    try std.testing.expect(!report.hasNoRestoredEntries());
    try std.testing.expect(report.hasIgnoredEntries());
    try std.testing.expect(!report.hasNoIgnoredEntries());
    try std.testing.expect(!report.hasUnaccountedEntries());
    try std.testing.expect(report.fullyHandled());
    try std.testing.expectEqual(ReadParameterStateClassification.restored_and_ignored, report.classification());
    try std.testing.expect(!report.isEmptyClassification());
    try std.testing.expect(!report.isRestoredAllClassification());
    try std.testing.expect(!report.isIgnoredAllClassification());
    try std.testing.expect(report.isRestoredAndIgnoredClassification());
    try std.testing.expect(!report.isPartialClassification());
    try std.testing.expect(report.accountedAllEntries());
    try std.testing.expect(!report.accountedPartialEntries());
    try std.testing.expect(!report.restoredAllEntries());
    try std.testing.expect(report.restoredPartialEntries());
    try std.testing.expect(!report.ignoredAllEntries());
    try std.testing.expect(report.ignoredPartialEntries());
    try std.testing.expect(report.restoredAndIgnoredEntries());
    try std.testing.expectEqual(@as(f64, 0.75), values.loadField(&set, "gain"));
}

test "parameter state report classifies empty and ignored loads" {
    const empty = ReadParameterStateReport{ .entry_count = 0, .restored_count = 0, .ignored_count = 0 };
    const ignored = ReadParameterStateReport{ .entry_count = 2, .restored_count = 0, .ignored_count = 2 };
    const incomplete = ReadParameterStateReport{ .entry_count = 3, .restored_count = 1, .ignored_count = 1 };

    try std.testing.expectEqual(@as(usize, 0), empty.accountedCount());
    try std.testing.expectEqual(@as(usize, 0), empty.unaccountedCount());
    try std.testing.expect(empty.matchesDecodedCount(0));
    try std.testing.expect(empty.hasFewerDecodedEntriesThan(1));
    try std.testing.expect(!empty.hasMoreDecodedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), empty.missingDecodedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), empty.extraDecodedEntryCount(1));
    try std.testing.expect(empty.matchesRestoredCount(0));
    try std.testing.expect(empty.hasFewerRestoredEntriesThan(1));
    try std.testing.expect(!empty.hasMoreRestoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), empty.missingRestoredEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), empty.extraRestoredEntryCount(1));
    try std.testing.expect(empty.matchesIgnoredCount(0));
    try std.testing.expect(empty.hasFewerIgnoredEntriesThan(1));
    try std.testing.expect(!empty.hasMoreIgnoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), empty.missingIgnoredEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), empty.extraIgnoredEntryCount(1));
    try std.testing.expect(empty.matchesAccountedCount(0));
    try std.testing.expect(empty.hasFewerAccountedEntriesThan(1));
    try std.testing.expect(!empty.hasMoreAccountedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), empty.missingAccountedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), empty.extraAccountedEntryCount(1));
    try std.testing.expect(empty.matchesUnaccountedCount(0));
    try std.testing.expect(empty.hasFewerUnaccountedEntriesThan(1));
    try std.testing.expect(!empty.hasMoreUnaccountedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), empty.missingUnaccountedEntryCount(1));
    try std.testing.expectEqual(@as(usize, 0), empty.extraUnaccountedEntryCount(1));
    try std.testing.expect(!empty.hasDecodedEntries());
    try std.testing.expect(empty.hasNoDecodedEntries());
    try std.testing.expect(empty.decodedEntriesEmpty());
    try std.testing.expect(!empty.hasRestoredEntries());
    try std.testing.expect(empty.hasNoRestoredEntries());
    try std.testing.expect(empty.restoredEntriesEmpty());
    try std.testing.expect(!empty.hasIgnoredEntries());
    try std.testing.expect(empty.hasNoIgnoredEntries());
    try std.testing.expect(empty.ignoredEntriesEmpty());
    try std.testing.expect(!empty.hasUnaccountedEntries());
    try std.testing.expect(empty.hasNoUnaccountedEntries());
    try std.testing.expect(empty.unaccountedEntriesEmpty());
    try std.testing.expect(empty.fullyHandled());
    try std.testing.expectEqual(ReadParameterStateClassification.empty, empty.classification());
    try std.testing.expect(empty.isEmptyClassification());
    try std.testing.expect(!empty.isRestoredAllClassification());
    try std.testing.expect(!empty.isIgnoredAllClassification());
    try std.testing.expect(!empty.isRestoredAndIgnoredClassification());
    try std.testing.expect(!empty.isPartialClassification());
    try std.testing.expect(empty.accountedAllEntries());
    try std.testing.expect(!empty.accountedPartialEntries());
    try std.testing.expect(empty.restoredAllEntries());
    try std.testing.expect(!empty.restoredPartialEntries());
    try std.testing.expect(!empty.ignoredAllEntries());
    try std.testing.expect(!empty.ignoredPartialEntries());
    try std.testing.expect(!empty.restoredAndIgnoredEntries());

    try std.testing.expect(ignored.hasDecodedEntries());
    try std.testing.expect(!ignored.hasNoDecodedEntries());
    try std.testing.expect(!ignored.decodedEntriesEmpty());
    try std.testing.expect(!ignored.hasRestoredEntries());
    try std.testing.expect(ignored.hasNoRestoredEntries());
    try std.testing.expect(ignored.restoredEntriesEmpty());
    try std.testing.expect(ignored.hasIgnoredEntries());
    try std.testing.expect(!ignored.hasNoIgnoredEntries());
    try std.testing.expect(!ignored.ignoredEntriesEmpty());
    try std.testing.expect(!ignored.hasUnaccountedEntries());
    try std.testing.expect(ignored.fullyHandled());
    try std.testing.expectEqual(ReadParameterStateClassification.ignored_all, ignored.classification());
    try std.testing.expect(!ignored.isEmptyClassification());
    try std.testing.expect(!ignored.isRestoredAllClassification());
    try std.testing.expect(ignored.isIgnoredAllClassification());
    try std.testing.expect(!ignored.isRestoredAndIgnoredClassification());
    try std.testing.expect(!ignored.isPartialClassification());
    try std.testing.expect(ignored.accountedAllEntries());
    try std.testing.expect(!ignored.accountedPartialEntries());
    try std.testing.expect(!ignored.restoredAllEntries());
    try std.testing.expect(!ignored.restoredPartialEntries());
    try std.testing.expect(ignored.ignoredAllEntries());
    try std.testing.expect(!ignored.ignoredPartialEntries());
    try std.testing.expect(!ignored.restoredAndIgnoredEntries());
    try std.testing.expect(!ignored.matchesRestoredCount(2));
    try std.testing.expect(ignored.hasFewerRestoredEntriesThan(2));
    try std.testing.expect(!ignored.hasMoreRestoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 2), ignored.missingRestoredEntryCount(2));
    try std.testing.expectEqual(@as(usize, 0), ignored.extraRestoredEntryCount(2));
    try std.testing.expect(ignored.matchesIgnoredCount(2));
    try std.testing.expect(!ignored.hasFewerIgnoredEntriesThan(2));
    try std.testing.expect(ignored.hasMoreIgnoredEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 0), ignored.missingIgnoredEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), ignored.extraIgnoredEntryCount(1));
    try std.testing.expect(ignored.matchesAccountedCount(2));
    try std.testing.expect(!ignored.hasFewerAccountedEntriesThan(2));
    try std.testing.expect(ignored.hasMoreAccountedEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 0), ignored.missingAccountedEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), ignored.extraAccountedEntryCount(1));
    try std.testing.expect(ignored.matchesUnaccountedCount(0));

    try std.testing.expectEqual(@as(usize, 2), incomplete.accountedCount());
    try std.testing.expectEqual(@as(usize, 1), incomplete.unaccountedCount());
    try std.testing.expect(incomplete.matchesDecodedCount(3));
    try std.testing.expect(!incomplete.hasFewerDecodedEntriesThan(3));
    try std.testing.expect(incomplete.hasMoreDecodedEntriesThan(2));
    try std.testing.expectEqual(@as(usize, 1), incomplete.missingDecodedEntryCount(4));
    try std.testing.expectEqual(@as(usize, 1), incomplete.extraDecodedEntryCount(2));
    try std.testing.expect(incomplete.matchesRestoredCount(1));
    try std.testing.expect(!incomplete.hasFewerRestoredEntriesThan(1));
    try std.testing.expect(incomplete.hasMoreRestoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), incomplete.missingRestoredEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), incomplete.extraRestoredEntryCount(0));
    try std.testing.expect(incomplete.matchesIgnoredCount(1));
    try std.testing.expect(!incomplete.hasFewerIgnoredEntriesThan(1));
    try std.testing.expect(incomplete.hasMoreIgnoredEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), incomplete.missingIgnoredEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), incomplete.extraIgnoredEntryCount(0));
    try std.testing.expect(incomplete.matchesAccountedCount(2));
    try std.testing.expect(incomplete.hasFewerAccountedEntriesThan(3));
    try std.testing.expect(incomplete.hasMoreAccountedEntriesThan(1));
    try std.testing.expectEqual(@as(usize, 1), incomplete.missingAccountedEntryCount(3));
    try std.testing.expectEqual(@as(usize, 1), incomplete.extraAccountedEntryCount(1));
    try std.testing.expect(incomplete.matchesUnaccountedCount(1));
    try std.testing.expect(!incomplete.hasFewerUnaccountedEntriesThan(1));
    try std.testing.expect(incomplete.hasMoreUnaccountedEntriesThan(0));
    try std.testing.expectEqual(@as(usize, 1), incomplete.missingUnaccountedEntryCount(2));
    try std.testing.expectEqual(@as(usize, 1), incomplete.extraUnaccountedEntryCount(0));
    try std.testing.expect(incomplete.hasUnaccountedEntries());
    try std.testing.expect(!incomplete.hasNoUnaccountedEntries());
    try std.testing.expect(!incomplete.unaccountedEntriesEmpty());
    try std.testing.expect(!incomplete.fullyHandled());
    try std.testing.expectEqual(ReadParameterStateClassification.partial, incomplete.classification());
    try std.testing.expect(!incomplete.isEmptyClassification());
    try std.testing.expect(!incomplete.isRestoredAllClassification());
    try std.testing.expect(!incomplete.isIgnoredAllClassification());
    try std.testing.expect(!incomplete.isRestoredAndIgnoredClassification());
    try std.testing.expect(incomplete.isPartialClassification());
    try std.testing.expect(!incomplete.accountedAllEntries());
    try std.testing.expect(incomplete.accountedPartialEntries());
    try std.testing.expect(incomplete.restoredPartialEntries());
    try std.testing.expect(incomplete.ignoredPartialEntries());
    try std.testing.expect(incomplete.restoredAndIgnoredEntries());
}

test "parameter state rejects duplicate restored parameter ids without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + 2 * (@sizeOf(u32) + @sizeOf(u64))]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.75)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.DuplicateParameterStateEntry, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "parameter state rejects malformed headers and unsupported versions" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);

    var bad_magic = [_]u8{0} ** (magic.len + @sizeOf(u16) + @sizeOf(u16));
    var bad_magic_stream = std.io.fixedBufferStream(&bad_magic);
    try std.testing.expectError(error.InvalidStateMagic, readParameterState(Params, &set, &values, bad_magic_stream.reader()));

    var bad_version: [magic.len + @sizeOf(u16) + @sizeOf(u16)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bad_version);
    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version + 1, .little);
    try out_stream.writer().writeInt(u16, 0, .little);
    var in_stream = std.io.fixedBufferStream(&bad_version);
    try std.testing.expectError(error.UnsupportedStateVersion, readParameterState(Params, &set, &values, in_stream.reader()));
}

test "parameter state rejects truncated entries without changing defaults" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + @sizeOf(u32)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);

    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version, .little);
    try out_stream.writer().writeInt(u16, 1, .little);
    try out_stream.writer().writeInt(u32, 0, .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.EndOfStream, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 1.0), values.loadField(&set, "gain"));
}

test "parameter state rejects later truncated entries without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + (@sizeOf(u32) + @sizeOf(u64)) + @sizeOf(u32)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 1, .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.EndOfStream, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "parameter state rejects normalized values outside range without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + 2 * (@sizeOf(u32) + @sizeOf(u64))]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 1, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 1.5)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
    try std.testing.expectEqual(@as(f64, 0.6), values.loadField(&set, "mix"));
}

test "parameter state rejects non-finite normalized values without partial updates" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", 0.0, 1.0, 1.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});
    var values = Values.init(&set);
    var bytes: [magic.len + @sizeOf(u16) + @sizeOf(u16) + @sizeOf(u32) + @sizeOf(u64)]u8 = undefined;
    var out_stream = std.io.fixedBufferStream(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(std.math.nan(f64)), .little);

    var in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    out_stream = std.io.fixedBufferStream(&bytes);
    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(std.math.inf(f64)), .little);

    in_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));
}

test "parameter state migrates renamed parameter ids" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(9, "Output", 0.0, 1.0, 1.0),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    const report = try readParameterStateWithMigrationsReport(NewParams, &new_set, &new_values, in_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
    });

    try std.testing.expectEqual(ReadParameterStateReport{ .entry_count = 1, .restored_count = 1, .ignored_count = 0 }, report);
    try std.testing.expectEqual(@as(f64, 0.25), new_values.loadField(&new_set, "output"));
}

test "parameter state migrates renamed parameter ids through chains" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(11, "Output", 0.0, 1.0, 1.0),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = std.io.fixedBufferStream(&bytes);
    try readParameterStateWithMigrations(NewParams, &new_set, &new_values, in_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 9, .new_id = 11 },
    });

    try std.testing.expectEqual(@as(f64, 0.25), new_values.loadField(&new_set, "output"));
}

test "parameter state exposes migration resolution" {
    const migrations = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 10 },
        .{ .old_id = 9, .new_id = 11 },
    };
    const cycle = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    };
    const identity = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 1 },
    };
    const longer_cycle = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 3 },
        .{ .old_id = 3, .new_id = 2 },
    };
    const converging = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    };
    const chained_converging = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 8 },
        .{ .old_id = 8, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    };

    try std.testing.expectEqual(@as(u32, 11), migratedParameterId(1, &migrations));
    try std.testing.expectEqual(@as(u32, 10), migratedParameterId(2, &migrations));
    try std.testing.expectEqual(@as(u32, 3), migratedParameterId(3, &migrations));
    try std.testing.expectEqual(@as(u32, 1), migratedParameterId(1, &cycle));
    try std.testing.expectEqual(@as(u32, 1), migratedParameterId(1, &longer_cycle));
    try std.testing.expectEqual(@as(?usize, null), identityParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(?usize, null), duplicateParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(?usize, null), ambiguousParameterMigrationIndex(&migrations));
    try std.testing.expectEqual(@as(?usize, 0), identityParameterMigrationIndex(&identity));
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&cycle));
    try std.testing.expectEqual(@as(?usize, 2), ambiguousParameterMigrationIndex(&longer_cycle));
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&converging));
    try std.testing.expectEqual(@as(?usize, 2), ambiguousParameterMigrationIndex(&chained_converging));
    try validateParameterIdMigrations(&migrations);
    try std.testing.expectError(error.IdentityParameterMigration, validateParameterIdMigrations(&identity));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&cycle));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&longer_cycle));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&converging));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&chained_converging));
}

test "parameter state rejects ambiguous migrations before partial updates" {
    const OldParams = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(1, "Gain", 0.0, 1.0, 1.0),
    };
    const NewParams = struct {
        output: parameters.FloatParam = parameters.FloatParam.init(9, "Output", 0.0, 1.0, 1.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(10, "Mix", 0.0, 1.0, 0.5),
    };
    const OldSet = parameters.ParameterSet(OldParams);
    const OldValues = parameters.ParameterValues(OldParams);
    const NewSet = parameters.ParameterSet(NewParams);
    const NewValues = parameters.ParameterValues(NewParams);
    const old_set = OldSet.init(.{});
    const new_set = NewSet.init(.{});
    var old_values = OldValues.init(&old_set);
    var new_values = NewValues.init(&new_set);
    var bytes: [encodedSize(OldParams)]u8 = undefined;

    try std.testing.expect(old_values.storeField(&old_set, "gain", 0.25));
    try std.testing.expect(new_values.storeField(&new_set, "output", 0.8));
    var out_stream = std.io.fixedBufferStream(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var duplicate_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectEqual(@as(?usize, 1), duplicateParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 1, .new_id = 10 },
    }));
    try std.testing.expectError(error.DuplicateParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, duplicate_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 1, .new_id = 10 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var ambiguous_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    }));
    try std.testing.expectError(error.AmbiguousParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, ambiguous_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var identity_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectEqual(@as(?usize, 0), identityParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 1 },
    }));
    try std.testing.expectError(error.IdentityParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, identity_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 1 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var cycle_stream = std.io.fixedBufferStream(&bytes);
    try std.testing.expectError(error.CyclicParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, cycle_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));
}
