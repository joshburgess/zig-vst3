const std = @import("std");
const parameters = @import("../parameters.zig");

pub const magic = "ZPLGSTAT";
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

pub fn assertEncodableParameterCount(comptime Params: type) void {
    if (parameters.ParameterSet(Params).count > std.math.maxInt(u16)) {
        @compileError("parameter state format supports at most 65535 parameters");
    }
}

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

    pub fn hasAccountedEntries(self: ReadParameterStateReport) bool {
        return self.accountedCount() != 0;
    }

    pub fn hasNoAccountedEntries(self: ReadParameterStateReport) bool {
        return self.accountedCount() == 0;
    }

    pub fn accountedEntriesEmpty(self: ReadParameterStateReport) bool {
        return self.hasNoAccountedEntries();
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
