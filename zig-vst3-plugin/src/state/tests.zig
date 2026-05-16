const std = @import("std");
const parameters = @import("../parameters.zig");
const state = @import("../state.zig");
const format = @import("format.zig");

const magic = format.magic;
const format_version = state.format_version;
const encoded_header_size = state.encoded_header_size;
const encoded_entry_size = state.encoded_entry_size;
const ParameterStateHeader = state.ParameterStateHeader;
const ParameterIdMigration = state.ParameterIdMigration;
const ReadParameterStateClassification = state.ReadParameterStateClassification;
const ReadParameterStateReport = state.ReadParameterStateReport;
const encodedSize = state.encodedSize;
const encodedSizeForCount = state.encodedSizeForCount;
const encodedSizeForCountChecked = state.encodedSizeForCountChecked;
const writeParameterState = state.writeParameterState;
const writeParameterStateHeaderForCount = state.writeParameterStateHeaderForCount;
const readParameterStateHeader = state.readParameterStateHeader;
const writeParameterStateJson = state.writeParameterStateJson;
const readParameterState = state.readParameterState;
const readParameterStateWithMigrations = state.readParameterStateWithMigrations;
const readParameterStateReport = state.readParameterStateReport;
const readParameterStateWithMigrationsReport = state.readParameterStateWithMigrationsReport;
const validateParameterIdMigrations = state.validateParameterIdMigrations;
const identityParameterMigrationIndex = state.identityParameterMigrationIndex;
const duplicateParameterMigrationIndex = state.duplicateParameterMigrationIndex;
const ambiguousParameterMigrationIndex = state.ambiguousParameterMigrationIndex;
const migratedParameterId = state.migratedParameterId;

const FixedBufferStream = struct {
    buffer: []u8,
    reader_interface: std.Io.Reader,
    writer_interface: std.Io.Writer,

    fn init(buffer: []u8) FixedBufferStream {
        return .{
            .buffer = buffer,
            .reader_interface = std.Io.Reader.fixed(buffer),
            .writer_interface = std.Io.Writer.fixed(buffer),
        };
    }

    fn reader(self: *FixedBufferStream) *std.Io.Reader {
        self.reader_interface = std.Io.Reader.fixed(self.buffer);
        return &self.reader_interface;
    }

    fn writer(self: *FixedBufferStream) *std.Io.Writer {
        self.writer_interface = std.Io.Writer.fixed(self.buffer);
        return &self.writer_interface;
    }

    fn getWritten(self: *const FixedBufferStream) []const u8 {
        return self.writer_interface.buffered();
    }
};

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

    var out_stream = FixedBufferStream.init(&bytes);
    try writeParameterState(Params, &set, &values, out_stream.writer());

    var in_stream = FixedBufferStream.init(&bytes);
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

    in_stream = FixedBufferStream.init(&bytes);
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
    try std.testing.expect(report.hasAccountedEntries());
    try std.testing.expect(!report.hasNoAccountedEntries());
    try std.testing.expect(!report.accountedEntriesEmpty());
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
    var out_stream = FixedBufferStream.init(&bytes);

    try writeParameterStateHeaderForCount(0, out_stream.writer());

    var in_stream = FixedBufferStream.init(&bytes);
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
    var bad_magic_stream = FixedBufferStream.init(&bad_magic);
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

    var out_stream = FixedBufferStream.init(&bytes);
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

    var out_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
    const writer = out_stream.writer();

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 999, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.75)), .little);

    var in_stream = FixedBufferStream.init(&bytes);
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
    try std.testing.expect(!empty.hasAccountedEntries());
    try std.testing.expect(empty.hasNoAccountedEntries());
    try std.testing.expect(empty.accountedEntriesEmpty());
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
    try std.testing.expect(incomplete.hasAccountedEntries());
    try std.testing.expect(!incomplete.hasNoAccountedEntries());
    try std.testing.expect(!incomplete.accountedEntriesEmpty());
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

test "parameter state round-trips generated normalized values" {
    const Params = struct {
        gain: parameters.FloatParam = parameters.FloatParam.init(0, "Gain", -24.0, 24.0, 0.0),
        mix: parameters.FloatParam = parameters.FloatParam.init(1, "Mix", 0.0, 1.0, 0.5),
        tone: parameters.FloatParam = parameters.FloatParam.init(2, "Tone", 20.0, 20_000.0, 1_000.0),
        width: parameters.FloatParam = parameters.FloatParam.init(3, "Width", -1.0, 1.0, 0.0),
    };
    const Set = parameters.ParameterSet(Params);
    const Values = parameters.ParameterValues(Params);
    const set = Set.init(.{});

    var prng = std.Random.DefaultPrng.init(0x7a67_7673_7433_0001);
    const random = prng.random();
    var bytes: [encodedSize(Params)]u8 = undefined;

    for (0..256) |_| {
        var values = Values.init(&set);
        var restored = Values.init(&set);
        var expected: [Set.count]f64 = undefined;

        for (&expected, 0..) |*normalized, index| {
            normalized.* = random.float(f64);
            try std.testing.expect(values.store(index, normalized.*));
        }

        var out_stream = FixedBufferStream.init(&bytes);
        try writeParameterState(Params, &set, &values, out_stream.writer());

        var in_stream = FixedBufferStream.init(&bytes);
        const report = try readParameterStateReport(Params, &set, &restored, in_stream.reader());
        try std.testing.expectEqual(ReadParameterStateReport{
            .entry_count = Set.count,
            .restored_count = Set.count,
            .ignored_count = 0,
        }, report);

        for (expected, 0..) |normalized, index| {
            try std.testing.expectEqual(normalized, restored.load(index).?);
        }
    }
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
    var out_stream = FixedBufferStream.init(&bytes);
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

    var in_stream = FixedBufferStream.init(&bytes);
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
    var bad_magic_stream = FixedBufferStream.init(&bad_magic);
    try std.testing.expectError(error.InvalidStateMagic, readParameterState(Params, &set, &values, bad_magic_stream.reader()));

    var bad_version: [magic.len + @sizeOf(u16) + @sizeOf(u16)]u8 = undefined;
    var out_stream = FixedBufferStream.init(&bad_version);
    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version + 1, .little);
    try out_stream.writer().writeInt(u16, 0, .little);
    var in_stream = FixedBufferStream.init(&bad_version);
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
    var out_stream = FixedBufferStream.init(&bytes);

    try out_stream.writer().writeAll(magic);
    try out_stream.writer().writeInt(u16, format_version, .little);
    try out_stream.writer().writeInt(u16, 1, .little);
    try out_stream.writer().writeInt(u32, 0, .little);

    var in_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    try std.testing.expect(values.storeField(&set, "mix", 0.6));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 2, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(@as(f64, 0.25)), .little);
    try writer.writeInt(u32, 1, .little);

    var in_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
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

    var in_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
    const writer = out_stream.writer();

    try std.testing.expect(values.storeField(&set, "gain", 0.8));

    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(std.math.nan(f64)), .little);

    var in_stream = FixedBufferStream.init(&bytes);
    try std.testing.expectError(error.ParameterStateOutsideNormalizedRange, readParameterState(Params, &set, &values, in_stream.reader()));
    try std.testing.expectEqual(@as(f64, 0.8), values.loadField(&set, "gain"));

    try std.testing.expect(values.storeField(&set, "gain", 0.8));
    out_stream = FixedBufferStream.init(&bytes);
    try writer.writeAll(magic);
    try writer.writeInt(u16, format_version, .little);
    try writer.writeInt(u16, 1, .little);
    try writer.writeInt(u32, 0, .little);
    try writer.writeInt(u64, @bitCast(std.math.inf(f64)), .little);

    in_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = FixedBufferStream.init(&bytes);
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
    var out_stream = FixedBufferStream.init(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var in_stream = FixedBufferStream.init(&bytes);
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
    const branching_converging = [_]ParameterIdMigration{
        .{ .old_id = 1, .new_id = 8 },
        .{ .old_id = 2, .new_id = 8 },
        .{ .old_id = 8, .new_id = 9 },
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
    try std.testing.expectEqual(@as(?usize, null), ambiguousParameterMigrationIndex(&cycle));
    try std.testing.expectEqual(@as(?usize, null), ambiguousParameterMigrationIndex(&longer_cycle));
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&converging));
    try std.testing.expectEqual(@as(?usize, 2), ambiguousParameterMigrationIndex(&chained_converging));
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&branching_converging));
    try validateParameterIdMigrations(&migrations);
    try std.testing.expectError(error.IdentityParameterMigration, validateParameterIdMigrations(&identity));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&cycle));
    try std.testing.expectError(error.CyclicParameterMigration, validateParameterIdMigrations(&longer_cycle));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&converging));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&chained_converging));
    try std.testing.expectError(error.AmbiguousParameterMigration, validateParameterIdMigrations(&branching_converging));
}

test "parameter state generated migration chains match reference resolution" {
    const Reference = struct {
        fn next(id: u32, migrations: []const ParameterIdMigration) ?u32 {
            for (migrations) |migration| {
                if (migration.old_id == id) return migration.new_id;
            }
            return null;
        }

        fn resolve(id: u32, migrations: []const ParameterIdMigration) u32 {
            var current = id;
            for (0..migrations.len + 1) |_| {
                current = next(current, migrations) orelse return current;
            }
            return id;
        }
    };

    for (0..24) |seed| {
        const base: u32 = @intCast(10 + seed * 10);
        var migrations = [_]ParameterIdMigration{
            .{ .old_id = base + 2, .new_id = base + 3 },
            .{ .old_id = base + 0, .new_id = base + 1 },
            .{ .old_id = base + 3, .new_id = base + 4 },
            .{ .old_id = base + 1, .new_id = base + 2 },
        };
        if (seed % 2 == 1) {
            std.mem.swap(ParameterIdMigration, &migrations[0], &migrations[3]);
        }
        if (seed % 3 == 1) {
            std.mem.swap(ParameterIdMigration, &migrations[1], &migrations[2]);
        }

        try validateParameterIdMigrations(&migrations);
        for (0..6) |offset| {
            const id: u32 = @intCast(base + offset);
            try std.testing.expectEqual(Reference.resolve(id, &migrations), migratedParameterId(id, &migrations));
        }
    }
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
    var out_stream = FixedBufferStream.init(&bytes);
    try writeParameterState(OldParams, &old_set, &old_values, out_stream.writer());

    var duplicate_stream = FixedBufferStream.init(&bytes);
    try std.testing.expectEqual(@as(?usize, 1), duplicateParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 1, .new_id = 10 },
    }));
    try std.testing.expectError(error.DuplicateParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, duplicate_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 1, .new_id = 10 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var ambiguous_stream = FixedBufferStream.init(&bytes);
    try std.testing.expectEqual(@as(?usize, 1), ambiguousParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    }));
    try std.testing.expectError(error.AmbiguousParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, ambiguous_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 9 },
        .{ .old_id = 2, .new_id = 9 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var identity_stream = FixedBufferStream.init(&bytes);
    try std.testing.expectEqual(@as(?usize, 0), identityParameterMigrationIndex(&.{
        .{ .old_id = 1, .new_id = 1 },
    }));
    try std.testing.expectError(error.IdentityParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, identity_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 1 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));

    var cycle_stream = FixedBufferStream.init(&bytes);
    try std.testing.expectError(error.CyclicParameterMigration, readParameterStateWithMigrations(NewParams, &new_set, &new_values, cycle_stream.reader(), &.{
        .{ .old_id = 1, .new_id = 2 },
        .{ .old_id = 2, .new_id = 1 },
    }));
    try std.testing.expectEqual(@as(f64, 0.8), new_values.loadField(&new_set, "output"));
}
