const std = @import("std");
const file_writer_io = @import("file_writer_io.zig");

pub const audio_id_bytes: usize = 40;

pub const IdentifierKind = enum {
    programme,
    content,
    object,
    pack_format,
    channel_format,
    stream_format,
    track_format,
    track_uid,
    alternative_value_set,
    block_format,
};

pub const Identifier = struct {
    kind: IdentifierKind,
    raw: []const u8,
    primary: u32,
    secondary: ?u32,

    pub fn parse(raw: []const u8) !Identifier {
        const shape = identifierShape(raw) orelse
            return error.InvalidAdmIdentifier;
        const primary = try parseHex(raw[shape.primary_start..shape.primary_end]);
        if (primary == 0) return error.UndefinedAdmIdentifier;
        const secondary = if (shape.secondary_start) |start|
            try parseHex(raw[start..])
        else
            null;
        if (secondary) |value| {
            if (value == 0) return error.UndefinedAdmIdentifier;
        }
        return .{
            .kind = shape.kind,
            .raw = raw,
            .primary = primary,
            .secondary = secondary,
        };
    }

    pub fn eql(self: Identifier, other: Identifier) bool {
        return self.kind == other.kind and
            asciiEqlIgnoreCase(self.raw, other.raw);
    }

    pub fn typeLabel(self: Identifier) ?u16 {
        return switch (self.kind) {
            .pack_format,
            .channel_format,
            .stream_format,
            .track_format,
            .block_format,
            => @intCast(self.primary >> 16),
            else => null,
        };
    }

    pub fn definitionIndex(self: Identifier) ?u16 {
        return switch (self.kind) {
            .pack_format,
            .channel_format,
            .stream_format,
            .track_format,
            .block_format,
            => @truncate(self.primary),
            else => null,
        };
    }

    pub fn isCommonDefinition(self: Identifier) bool {
        const index = self.definitionIndex() orelse return false;
        return index >= 1 and index <= 0x0fff;
    }

    pub fn requiresLocalDefinition(self: Identifier) bool {
        const index = self.definitionIndex() orelse return true;
        return index >= 0x1000;
    }
};

const IdentifierShape = struct {
    kind: IdentifierKind,
    primary_start: usize,
    primary_end: usize,
    secondary_start: ?usize = null,
};

pub const Entry = struct {
    track_index: u16,
    uid: []const u8,
    track_ref: []const u8,
    pack_ref: ?[]const u8 = null,
};

pub const ChannelAllocation = struct {
    num_tracks: u16,
    entries: []const Entry,
    entry_capacity: ?u16 = null,

    pub fn capacity(self: ChannelAllocation) usize {
        return if (self.entry_capacity) |capacity_value|
            capacity_value
        else
            self.entries.len;
    }

    pub fn validate(self: ChannelAllocation) !void {
        const capacity_value = self.capacity();
        if (self.entries.len > std.math.maxInt(u16) or
            capacity_value > std.math.maxInt(u16))
        {
            return error.TooManyAdmTrackUids;
        }
        if (capacity_value < self.entries.len)
            return error.AdmChannelAllocationCapacityTooSmall;
        if (self.num_tracks == 0 and self.entries.len != 0)
            return error.InvalidAdmTrackCount;

        for (self.entries, 0..) |entry, index| {
            try validateEntry(entry, self.num_tracks);
            for (self.entries[0..index]) |previous| {
                if (asciiEqlIgnoreCase(previous.uid, entry.uid))
                    return error.DuplicateAdmTrackUid;
            }
        }

        var track_index: usize = 1;
        while (track_index <= self.num_tracks) : (track_index += 1) {
            var found = false;
            for (self.entries) |entry| {
                if (entry.track_index == @as(u16, @intCast(track_index))) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.MissingAdmTrackAllocation;
        }
    }
};

pub const View = struct {
    bytes: []const u8,
    num_tracks: u16,
    num_uids: u16,
    entry_capacity: u16,

    pub fn init(bytes: []const u8) !View {
        if (bytes.len < 12 or !std.mem.eql(u8, bytes[0..4], "chna"))
            return error.InvalidAdmChannelAllocation;
        const payload_bytes: usize = std.mem.readInt(
            u32,
            bytes[4..8],
            .little,
        );
        if (payload_bytes < 4 or
            payload_bytes > std.math.maxInt(usize) - 8 or
            payload_bytes + 8 != bytes.len or
            (payload_bytes - 4) % audio_id_bytes != 0)
        {
            return error.InvalidAdmChannelAllocation;
        }
        const capacity_value = (payload_bytes - 4) / audio_id_bytes;
        if (capacity_value > std.math.maxInt(u16))
            return error.TooManyAdmTrackUids;

        const view = View{
            .bytes = bytes,
            .num_tracks = std.mem.readInt(u16, bytes[8..10], .little),
            .num_uids = std.mem.readInt(u16, bytes[10..12], .little),
            .entry_capacity = @intCast(capacity_value),
        };
        if (view.num_uids > view.entry_capacity)
            return error.InvalidAdmChannelAllocation;
        try view.validate();
        return view;
    }

    pub fn entry(self: View, index: usize) !Entry {
        if (index >= self.num_uids) return error.AdmTrackUidIndexOutOfRange;
        return decodeEntry(self.entryBytes(index), self.num_tracks);
    }

    pub fn iterator(self: View) Iterator {
        return .{ .view = self };
    }

    fn validate(self: View) !void {
        if (self.num_tracks == 0 and self.num_uids != 0)
            return error.InvalidAdmTrackCount;

        var index: usize = 0;
        while (index < self.num_uids) : (index += 1) {
            const current = try self.entry(index);
            var previous_index: usize = 0;
            while (previous_index < index) : (previous_index += 1) {
                const previous = try self.entry(previous_index);
                if (asciiEqlIgnoreCase(previous.uid, current.uid))
                    return error.DuplicateAdmTrackUid;
            }
        }

        while (index < self.entry_capacity) : (index += 1) {
            for (self.entryBytes(index)) |byte| {
                if (byte != 0) return error.InvalidAdmUnusedTrackUid;
            }
        }

        var track_index: usize = 1;
        while (track_index <= self.num_tracks) : (track_index += 1) {
            var found = false;
            var entry_index: usize = 0;
            while (entry_index < self.num_uids) : (entry_index += 1) {
                if ((try self.entry(entry_index)).track_index ==
                    @as(u16, @intCast(track_index)))
                {
                    found = true;
                    break;
                }
            }
            if (!found) return error.MissingAdmTrackAllocation;
        }
    }

    fn entryBytes(self: View, index: usize) []const u8 {
        const offset = 12 + index * audio_id_bytes;
        return self.bytes[offset..][0..audio_id_bytes];
    }
};

pub const Iterator = struct {
    view: View,
    index: usize = 0,

    pub fn next(self: *Iterator) !?Entry {
        if (self.index == self.view.num_uids) return null;
        const result = try self.view.entry(self.index);
        self.index += 1;
        return result;
    }
};

pub fn requiredBytes(allocation: ChannelAllocation) !usize {
    try allocation.validate();
    return std.math.add(
        usize,
        12,
        std.math.mul(
            usize,
            allocation.capacity(),
            audio_id_bytes,
        ) catch return error.AdmChannelAllocationSizeOverflow,
    ) catch return error.AdmChannelAllocationSizeOverflow;
}

pub fn encode(
    destination: []u8,
    allocation: ChannelAllocation,
) ![]const u8 {
    const required = try requiredBytes(allocation);
    if (destination.len < required)
        return error.AdmChannelAllocationOutputTooSmall;

    @memcpy(destination[0..4], "chna");
    std.mem.writeInt(u32, destination[4..8], @intCast(required - 8), .little);
    std.mem.writeInt(u16, destination[8..10], allocation.num_tracks, .little);
    std.mem.writeInt(
        u16,
        destination[10..12],
        @intCast(allocation.entries.len),
        .little,
    );
    var offset: usize = 12;
    for (allocation.entries) |entry| {
        writeEntry(destination[offset..][0..audio_id_bytes], entry);
        offset += audio_id_bytes;
    }
    @memset(destination[offset..required], 0);
    return destination[0..required];
}

pub fn writeFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    allocation: ChannelAllocation,
) !usize {
    const required = try requiredBytes(allocation);
    _ = std.math.add(
        u64,
        initial_offset,
        @as(u64, @intCast(required)),
    ) catch return error.FileOffsetOverflow;
    var header: [12]u8 = undefined;
    @memcpy(header[0..4], "chna");
    std.mem.writeInt(u32, header[4..8], @intCast(required - 8), .little);
    std.mem.writeInt(u16, header[8..10], allocation.num_tracks, .little);
    std.mem.writeInt(
        u16,
        header[10..12],
        @intCast(allocation.entries.len),
        .little,
    );

    const operations = file_writer_io.Operations{};
    try operations.writeAt(io, file, initial_offset, &header);
    var offset = std.math.add(
        u64,
        initial_offset,
        header.len,
    ) catch return error.FileOffsetOverflow;
    for (allocation.entries) |entry| {
        var encoded: [audio_id_bytes]u8 = undefined;
        writeEntry(&encoded, entry);
        try operations.writeAt(io, file, offset, &encoded);
        offset = std.math.add(
            u64,
            offset,
            audio_id_bytes,
        ) catch return error.FileOffsetOverflow;
    }
    var zero_entry: [audio_id_bytes]u8 = @splat(0);
    var unused = allocation.capacity() - allocation.entries.len;
    while (unused != 0) : (unused -= 1) {
        try operations.writeAt(io, file, offset, &zero_entry);
        offset = std.math.add(
            u64,
            offset,
            audio_id_bytes,
        ) catch return error.FileOffsetOverflow;
    }
    return required;
}

fn validateEntry(entry: Entry, num_tracks: u16) !void {
    if (entry.track_index == 0 or entry.track_index > num_tracks)
        return error.InvalidAdmTrackIndex;
    const uid = try Identifier.parse(entry.uid);
    if (uid.kind != .track_uid) return error.InvalidAdmTrackUid;
    if (entry.track_ref.len != 14)
        return error.InvalidAdmTrackReference;
    if (asciiEqlIgnoreCase(entry.track_ref[0..3], "AT_")) {
        const track_format = try Identifier.parse(entry.track_ref);
        if (track_format.kind != .track_format)
            return error.InvalidAdmTrackReference;
    } else if (asciiEqlIgnoreCase(entry.track_ref[0..3], "AC_")) {
        const channel_format = try Identifier.parse(entry.track_ref[0..11]);
        if (channel_format.kind != .channel_format)
            return error.InvalidAdmChannelFormatReference;
        if (entry.track_ref[11] != '_' or
            !std.mem.eql(u8, entry.track_ref[12..14], "00"))
        {
            return error.InvalidAdmChannelFormatReference;
        }
    } else {
        return error.InvalidAdmTrackReference;
    }
    if (entry.pack_ref) |pack_ref| {
        const pack_format = try Identifier.parse(pack_ref);
        if (pack_format.kind != .pack_format)
            return error.InvalidAdmPackFormatReference;
    }
}

fn identifierShape(raw: []const u8) ?IdentifierShape {
    const candidates = [_]struct {
        prefix: []const u8,
        primary_digits: usize,
        secondary_digits: ?usize,
        kind: IdentifierKind,
    }{
        .{ .prefix = "APR_", .primary_digits = 4, .secondary_digits = null, .kind = .programme },
        .{ .prefix = "ACO_", .primary_digits = 4, .secondary_digits = null, .kind = .content },
        .{ .prefix = "ATU_", .primary_digits = 8, .secondary_digits = null, .kind = .track_uid },
        .{ .prefix = "AVS_", .primary_digits = 4, .secondary_digits = 4, .kind = .alternative_value_set },
        .{ .prefix = "AO_", .primary_digits = 4, .secondary_digits = null, .kind = .object },
        .{ .prefix = "AP_", .primary_digits = 8, .secondary_digits = null, .kind = .pack_format },
        .{ .prefix = "AC_", .primary_digits = 8, .secondary_digits = null, .kind = .channel_format },
        .{ .prefix = "AS_", .primary_digits = 8, .secondary_digits = null, .kind = .stream_format },
        .{ .prefix = "AT_", .primary_digits = 8, .secondary_digits = 2, .kind = .track_format },
        .{ .prefix = "AB_", .primary_digits = 8, .secondary_digits = 8, .kind = .block_format },
    };
    for (candidates) |candidate| {
        const secondary_bytes: usize = candidate.secondary_digits orelse 0;
        const separator_bytes: usize =
            if (candidate.secondary_digits != null) 1 else 0;
        const expected = candidate.prefix.len + candidate.primary_digits +
            separator_bytes + secondary_bytes;
        if (raw.len != expected or
            !asciiEqlIgnoreCase(raw[0..candidate.prefix.len], candidate.prefix))
        {
            continue;
        }
        const primary_end = candidate.prefix.len + candidate.primary_digits;
        if (candidate.secondary_digits != null and raw[primary_end] != '_')
            continue;
        return .{
            .kind = candidate.kind,
            .primary_start = candidate.prefix.len,
            .primary_end = primary_end,
            .secondary_start = if (candidate.secondary_digits != null)
                primary_end + 1
            else
                null,
        };
    }
    return null;
}

fn parseHex(bytes: []const u8) !u32 {
    for (bytes) |byte| {
        if (!std.ascii.isHex(byte)) return error.InvalidAdmIdentifier;
    }
    return std.fmt.parseInt(u32, bytes, 16) catch
        return error.InvalidAdmIdentifier;
}

fn decodeEntry(bytes: []const u8, num_tracks: u16) !Entry {
    if (bytes[39] != 0) return error.InvalidAdmChannelAllocationPadding;
    const entry = Entry{
        .track_index = std.mem.readInt(u16, bytes[0..2], .little),
        .uid = bytes[2..14],
        .track_ref = bytes[14..28],
        .pack_ref = if (allZeroBytes(bytes[28..39])) null else bytes[28..39],
    };
    try validateEntry(entry, num_tracks);
    return entry;
}

fn writeEntry(destination: []u8, entry: Entry) void {
    @memset(destination, 0);
    std.mem.writeInt(u16, destination[0..2], entry.track_index, .little);
    @memcpy(destination[2..14], entry.uid);
    @memcpy(destination[14..28], entry.track_ref);
    if (entry.pack_ref) |pack_ref| @memcpy(destination[28..39], pack_ref);
}

fn allZeroBytes(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn asciiEqlIgnoreCase(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_byte, right_byte| {
        if (std.ascii.toLower(left_byte) != std.ascii.toLower(right_byte))
            return false;
    }
    return true;
}

test "ADM identifiers cover every standardized core family" {
    const cases = [_]struct {
        raw: []const u8,
        kind: IdentifierKind,
    }{
        .{ .raw = "APR_1001", .kind = .programme },
        .{ .raw = "ACO_1001", .kind = .content },
        .{ .raw = "AO_1001", .kind = .object },
        .{ .raw = "AP_00011001", .kind = .pack_format },
        .{ .raw = "AC_00011001", .kind = .channel_format },
        .{ .raw = "AS_00011001", .kind = .stream_format },
        .{ .raw = "AT_00011001_01", .kind = .track_format },
        .{ .raw = "ATU_00000001", .kind = .track_uid },
        .{ .raw = "AVS_1001_0001", .kind = .alternative_value_set },
        .{ .raw = "AB_00031001_00000001", .kind = .block_format },
    };
    for (cases) |case| {
        const identifier = try Identifier.parse(case.raw);
        try std.testing.expectEqual(case.kind, identifier.kind);
    }
    const lowercase = try Identifier.parse("at_00011001_01");
    try std.testing.expect(lowercase.eql(
        try Identifier.parse("AT_00011001_01"),
    ));
}

test "ADM identifiers distinguish common and local format definitions" {
    const common = try Identifier.parse("AP_00010fff");
    try std.testing.expect(common.isCommonDefinition());
    try std.testing.expect(!common.requiresLocalDefinition());
    try std.testing.expectEqual(@as(?u16, 1), common.typeLabel());
    try std.testing.expectEqual(@as(?u16, 0x0fff), common.definitionIndex());

    const local = try Identifier.parse("AC_00011000");
    try std.testing.expect(!local.isCommonDefinition());
    try std.testing.expect(local.requiresLocalDefinition());
    try std.testing.expectError(
        error.UndefinedAdmIdentifier,
        Identifier.parse("ATU_00000000"),
    );
    try std.testing.expectError(
        error.InvalidAdmIdentifier,
        Identifier.parse("AT_00011001_0g"),
    );
}

test "ADM channel allocation encodes the normative stereo layout" {
    const entries = [_]Entry{
        .{
            .track_index = 1,
            .uid = "ATU_00000001",
            .track_ref = "AT_00010001_01",
            .pack_ref = "AP_00010002",
        },
        .{
            .track_index = 2,
            .uid = "ATU_00000002",
            .track_ref = "AT_00010002_01",
            .pack_ref = "AP_00010002",
        },
    };
    var storage: [92]u8 = undefined;
    const encoded = try encode(&storage, .{
        .num_tracks = 2,
        .entries = &entries,
    });
    try std.testing.expectEqual(@as(usize, 92), encoded.len);
    try std.testing.expectEqualStrings("chna", encoded[0..4]);
    try std.testing.expectEqual(@as(u32, 84), std.mem.readInt(
        u32,
        encoded[4..8],
        .little,
    ));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(
        u16,
        encoded[8..10],
        .little,
    ));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(
        u16,
        encoded[10..12],
        .little,
    ));
    try std.testing.expectEqualSlices(u8, "ATU_00000001", encoded[14..26]);
    try std.testing.expectEqualSlices(u8, "AT_00010001_01", encoded[26..40]);
    try std.testing.expectEqualSlices(u8, "AP_00010002", encoded[40..51]);
    try std.testing.expectEqual(@as(u8, 0), encoded[51]);

    const view = try View.init(encoded);
    try std.testing.expectEqual(@as(u16, 2), view.num_tracks);
    try std.testing.expectEqual(@as(u16, 2), view.num_uids);
    const second = try view.entry(1);
    try std.testing.expectEqual(@as(u16, 2), second.track_index);
    try std.testing.expectEqualStrings("ATU_00000002", second.uid);
    try std.testing.expectEqualStrings("AT_00010002_01", second.track_ref);
    try std.testing.expectEqualStrings("AP_00010002", second.pack_ref.?);
}

test "ADM channel allocation retains reserved zero entries" {
    const entries = [_]Entry{
        .{
            .track_index = 1,
            .uid = "atu_00000001",
            .track_ref = "ac_00010001_00",
        },
        .{
            .track_index = 1,
            .uid = "ATU_00000002",
            .track_ref = "AT_00031003_01",
            .pack_ref = "AP_00031002",
        },
    };
    var storage: [132]u8 = undefined;
    const encoded = try encode(&storage, .{
        .num_tracks = 1,
        .entries = &entries,
        .entry_capacity = 3,
    });
    const view = try View.init(encoded);
    try std.testing.expectEqual(@as(u16, 2), view.num_uids);
    try std.testing.expectEqual(@as(u16, 3), view.entry_capacity);
    try std.testing.expect((try view.entry(0)).pack_ref == null);
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0} ** audio_id_bytes),
        encoded[92..132],
    );
}

test "ADM channel allocation rejects malformed mappings transactionally" {
    const duplicate_entries = [_]Entry{
        .{
            .track_index = 1,
            .uid = "ATU_00000001",
            .track_ref = "AT_00010001_01",
        },
        .{
            .track_index = 2,
            .uid = "atu_00000001",
            .track_ref = "AT_00010002_01",
        },
    };
    var storage: [92]u8 = @splat(0xa5);
    const before = storage;
    try std.testing.expectError(
        error.DuplicateAdmTrackUid,
        encode(&storage, .{
            .num_tracks = 2,
            .entries = &duplicate_entries,
        }),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);

    const incomplete = [_]Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
    }};
    try std.testing.expectError(
        error.MissingAdmTrackAllocation,
        requiredBytes(.{
            .num_tracks = 2,
            .entries = &incomplete,
        }),
    );
    try std.testing.expectError(
        error.InvalidAdmChannelFormatReference,
        requiredBytes(.{
            .num_tracks = 1,
            .entries = &.{.{
                .track_index = 1,
                .uid = "ATU_00000001",
                .track_ref = "AC_00010001_01",
            }},
        }),
    );
}

test "ADM channel allocation parser rejects nonzero reserved bytes" {
    const entries = [_]Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
    }};
    var storage: [92]u8 = undefined;
    _ = try encode(&storage, .{
        .num_tracks = 1,
        .entries = &entries,
        .entry_capacity = 2,
    });

    storage[91] = 1;
    try std.testing.expectError(
        error.InvalidAdmUnusedTrackUid,
        View.init(&storage),
    );
    storage[91] = 0;
    storage[51] = 1;
    try std.testing.expectError(
        error.InvalidAdmChannelAllocationPadding,
        View.init(&storage),
    );
}

test "ADM channel allocation writes directly to a file" {
    const entries = [_]Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "chna.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.setLength(std.testing.io, 60);
    try std.testing.expectEqual(
        @as(usize, 52),
        try writeFile(std.testing.io, file, 8, .{
            .num_tracks = 1,
            .entries = &entries,
        }),
    );
    var bytes: [52]u8 = undefined;
    try std.testing.expectEqual(
        bytes.len,
        try file.readPositionalAll(std.testing.io, &bytes, 8),
    );
    _ = try View.init(&bytes);
    try std.testing.expectError(
        error.FileOffsetOverflow,
        writeFile(
            std.testing.io,
            file,
            std.math.maxInt(u64),
            .{ .num_tracks = 1, .entries = &entries },
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 60),
        try file.length(std.testing.io),
    );
}
