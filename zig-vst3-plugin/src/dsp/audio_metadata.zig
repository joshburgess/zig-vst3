const std = @import("std");
const adm = @import("adm.zig");
const adm_xml = @import("adm_xml.zig");
const broadcast_metadata = @import("broadcast_metadata.zig");

pub const Limits = struct {
    max_encoded_bytes: usize = 256 * 1024 * 1024,

    pub fn validate(self: Limits) !void {
        if (self.max_encoded_bytes == 0)
            return error.InvalidAudioMetadataLimits;
    }
};

pub const default_limits = Limits{};

pub const title = [4]u8{ 'I', 'N', 'A', 'M' };
pub const artist = [4]u8{ 'I', 'A', 'R', 'T' };
pub const comment = [4]u8{ 'I', 'C', 'M', 'T' };
pub const copyright = [4]u8{ 'I', 'C', 'O', 'P' };
pub const creation_date = [4]u8{ 'I', 'C', 'R', 'D' };
pub const genre = [4]u8{ 'I', 'G', 'N', 'R' };
pub const product = [4]u8{ 'I', 'P', 'R', 'D' };
pub const software = [4]u8{ 'I', 'S', 'F', 'T' };
pub const track_number = [4]u8{ 'I', 'T', 'R', 'K' };

pub const aiff_name = [4]u8{ 'N', 'A', 'M', 'E' };
pub const aiff_author = [4]u8{ 'A', 'U', 'T', 'H' };
pub const aiff_copyright = [4]u8{ '(', 'c', ')', ' ' };
pub const aiff_annotation = [4]u8{ 'A', 'N', 'N', 'O' };

pub const Entry = struct {
    id: [4]u8,
    value: []const u8,

    pub fn validate(self: Entry) !void {
        for (self.id) |byte| {
            if (byte < 0x20 or byte > 0x7e)
                return error.InvalidMetadataId;
        }
        if (self.value.len > std.math.maxInt(u32) - 1)
            return error.MetadataSizeOverflow;
    }
};

pub const RiffXmlKind = enum {
    ixml,
    axml,

    pub fn id(self: RiffXmlKind) [4]u8 {
        return switch (self) {
            .ixml => .{ 'i', 'X', 'M', 'L' },
            .axml => .{ 'a', 'x', 'm', 'l' },
        };
    }
};

pub const RiffXmlView = struct {
    kind: RiffXmlKind,
    document: []const u8,
    limits: Limits = default_limits,

    pub fn init(bytes: []const u8) !RiffXmlView {
        return initWithLimits(bytes, default_limits);
    }

    pub fn initWithLimits(bytes: []const u8, limits: Limits) !RiffXmlView {
        try limits.validate();
        if (bytes.len > limits.max_encoded_bytes)
            return error.AudioMetadataLimitExceeded;
        if (bytes.len < 8) return error.InvalidRiffXmlChunk;
        const kind: RiffXmlKind =
            if (std.mem.eql(u8, bytes[0..4], "iXML"))
                .ixml
            else if (std.mem.eql(u8, bytes[0..4], "axml"))
                .axml
            else
                return error.InvalidRiffXmlChunk;
        const document_bytes: usize = std.mem.readInt(
            u32,
            bytes[4..8],
            .little,
        );
        const padded_document = std.math.add(
            usize,
            document_bytes,
            document_bytes & 1,
        ) catch return error.InvalidRiffXmlChunk;
        const total_bytes = std.math.add(
            usize,
            8,
            padded_document,
        ) catch return error.InvalidRiffXmlChunk;
        if (total_bytes != bytes.len)
            return error.InvalidRiffXmlChunk;
        if (document_bytes & 1 != 0 and bytes[bytes.len - 1] != 0)
            return error.InvalidRiffXmlPadding;
        const document = bytes[8..][0..document_bytes];
        try validateXmlDocument(document);
        return .{ .kind = kind, .document = document, .limits = limits };
    }
};

pub const RiffMetadata = struct {
    broadcast: ?broadcast_metadata.Extension = null,
    ixml: ?[]const u8 = null,
    axml: ?[]const u8 = null,
    channel_allocation: ?adm.ChannelAllocation = null,
    info: []const Entry = &.{},

    pub fn validateAdm(self: RiffMetadata) !adm_xml.Document {
        const document = try adm_xml.Document.init(
            self.axml orelse return error.MissingAdmXml,
        );
        try document.validateChannelAllocation(
            self.channel_allocation orelse
                return error.MissingAdmChannelAllocation,
        );
        return document;
    }

    pub fn validateEmissionProfileAdm(
        self: RiffMetadata,
        essence: adm_xml.EmissionPcmEssence,
    ) !adm_xml.Document {
        const document = try self.validateAdm();
        const allocation = self.channel_allocation orelse
            return error.MissingAdmChannelAllocation;
        if (allocation.num_tracks != essence.channel_count or
            allocation.entries.len != allocation.num_tracks)
        {
            return error.AdmEmissionProfileTrackCountMismatch;
        }
        try document.validateEmissionProfilePcmEssence(essence);
        return document;
    }
};

pub fn requiredRiffXmlBytes(
    kind: RiffXmlKind,
    document: []const u8,
) !usize {
    _ = kind;
    try validateXmlDocument(document);
    if (document.len > std.math.maxInt(u32))
        return error.MetadataSizeOverflow;
    const padded_document = std.math.add(
        usize,
        document.len,
        document.len & 1,
    ) catch return error.MetadataSizeOverflow;
    return std.math.add(
        usize,
        8,
        padded_document,
    ) catch return error.MetadataSizeOverflow;
}

pub fn encodeRiffXml(
    destination: []u8,
    kind: RiffXmlKind,
    document: []const u8,
) ![]const u8 {
    const required = try requiredRiffXmlBytes(kind, document);
    if (destination.len < required)
        return error.MetadataOutputTooSmall;
    const output = destination[0..required];
    if (byteSlicesOverlap(output, document))
        return error.MetadataSourceAliasesOutput;
    @memcpy(destination[0..4], &kind.id());
    std.mem.writeInt(
        u32,
        destination[4..8],
        @intCast(document.len),
        .little,
    );
    @memcpy(destination[8..][0..document.len], document);
    if (document.len & 1 != 0)
        destination[8 + document.len] = 0;
    return destination[0..required];
}

pub fn writeRiffXmlFile(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    kind: RiffXmlKind,
    document: []const u8,
) !usize {
    const required = try requiredRiffXmlBytes(kind, document);
    var header: [8]u8 = undefined;
    @memcpy(header[0..4], &kind.id());
    std.mem.writeInt(
        u32,
        header[4..8],
        @intCast(document.len),
        .little,
    );
    try writeAt(io, file, offset, &header);
    try writeAt(io, file, offset + header.len, document);
    if (document.len & 1 != 0)
        try writeAt(io, file, offset + header.len + document.len, &.{0});
    return required;
}

pub fn requiredRiffMetadataBytes(metadata: RiffMetadata) !usize {
    var required: usize = 0;
    if (metadata.broadcast) |broadcast| {
        required = try addMetadataBytes(
            required,
            try broadcast_metadata.requiredBytes(broadcast),
        );
    }
    if (metadata.ixml) |document| {
        required = try addMetadataBytes(
            required,
            try requiredRiffXmlBytes(.ixml, document),
        );
    }
    if (metadata.axml) |document| {
        required = try addMetadataBytes(
            required,
            try requiredRiffXmlBytes(.axml, document),
        );
    }
    if (metadata.channel_allocation) |allocation| {
        required = try addMetadataBytes(
            required,
            try adm.requiredBytes(allocation),
        );
    }
    if (metadata.info.len != 0) {
        required = try addMetadataBytes(
            required,
            try requiredRiffInfoBytes(metadata.info),
        );
    }
    return required;
}

pub fn validateRiffMetadataChannelCount(
    metadata: RiffMetadata,
    channel_count: u16,
) !void {
    if (metadata.channel_allocation) |allocation| {
        if (allocation.num_tracks != channel_count)
            return error.AdmTrackCountMismatch;
    }
}

pub fn writeRiffMetadataFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    metadata: RiffMetadata,
) !usize {
    const required = try requiredRiffMetadataBytes(metadata);
    var offset = initial_offset;
    if (metadata.broadcast) |broadcast| {
        offset += try broadcast_metadata.writeFile(
            io,
            file,
            offset,
            broadcast,
        );
    }
    if (metadata.ixml) |document| {
        offset += try writeRiffXmlFile(
            io,
            file,
            offset,
            .ixml,
            document,
        );
    }
    if (metadata.axml) |document| {
        offset += try writeRiffXmlFile(
            io,
            file,
            offset,
            .axml,
            document,
        );
    }
    if (metadata.channel_allocation) |allocation| {
        offset += try adm.writeFile(
            io,
            file,
            offset,
            allocation,
        );
    }
    if (metadata.info.len != 0) {
        offset += try writeRiffInfoFile(
            io,
            file,
            offset,
            metadata.info,
        );
    }
    return required;
}

pub fn requiredRiffInfoBytes(entries: []const Entry) !usize {
    var payload_bytes: usize = 4;
    for (entries) |entry| {
        try entry.validate();
        if (std.mem.indexOfScalar(u8, entry.value, 0) != null)
            return error.MetadataContainsNul;
        const value_bytes = std.math.add(
            usize,
            entry.value.len,
            1,
        ) catch return error.MetadataSizeOverflow;
        const padded_value = std.math.add(
            usize,
            value_bytes,
            value_bytes & 1,
        ) catch return error.MetadataSizeOverflow;
        payload_bytes = std.math.add(
            usize,
            payload_bytes,
            8 + padded_value,
        ) catch return error.MetadataSizeOverflow;
    }
    if (payload_bytes > std.math.maxInt(u32))
        return error.MetadataSizeOverflow;
    return std.math.add(
        usize,
        payload_bytes,
        8,
    ) catch return error.MetadataSizeOverflow;
}

pub fn encodeRiffInfo(
    destination: []u8,
    entries: []const Entry,
) ![]const u8 {
    const required = try requiredRiffInfoBytes(entries);
    if (destination.len < required)
        return error.MetadataOutputTooSmall;
    const output = destination[0..required];
    try validateEntryStorageDisjoint(output, entries);

    @memcpy(destination[0..4], "LIST");
    std.mem.writeInt(
        u32,
        destination[4..8],
        @intCast(required - 8),
        .little,
    );
    @memcpy(destination[8..12], "INFO");
    var offset: usize = 12;
    for (entries) |entry| {
        const value_bytes = entry.value.len + 1;
        @memcpy(destination[offset..][0..4], &entry.id);
        std.mem.writeInt(
            u32,
            destination[offset + 4 ..][0..4],
            @intCast(value_bytes),
            .little,
        );
        offset += 8;
        @memcpy(destination[offset..][0..entry.value.len], entry.value);
        destination[offset + entry.value.len] = 0;
        offset += value_bytes;
        if (value_bytes & 1 != 0) {
            destination[offset] = 0;
            offset += 1;
        }
    }
    return destination[0..required];
}

pub fn writeRiffInfoFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    entries: []const Entry,
) !usize {
    const required = try requiredRiffInfoBytes(entries);
    var header: [12]u8 = undefined;
    @memcpy(header[0..4], "LIST");
    std.mem.writeInt(
        u32,
        header[4..8],
        @intCast(required - 8),
        .little,
    );
    @memcpy(header[8..12], "INFO");
    try writeAt(io, file, initial_offset, &header);
    _ = try writeRiffInfoPayloadFile(
        io,
        file,
        initial_offset + 8,
        entries,
    );
    return required;
}

pub fn writeRiffInfoPayloadFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    entries: []const Entry,
) !usize {
    const required = try requiredRiffInfoBytes(entries);
    try writeAt(io, file, initial_offset, "INFO");
    var offset = initial_offset + 4;
    for (entries) |entry| {
        var entry_header: [8]u8 = undefined;
        @memcpy(entry_header[0..4], &entry.id);
        std.mem.writeInt(
            u32,
            entry_header[4..8],
            @intCast(entry.value.len + 1),
            .little,
        );
        try writeAt(io, file, offset, &entry_header);
        offset += entry_header.len;
        try writeAt(io, file, offset, entry.value);
        offset += entry.value.len;
        const terminator_and_padding: [2]u8 = @splat(0);
        const trailer_length: usize =
            if ((entry.value.len + 1) & 1 != 0) 2 else 1;
        try writeAt(
            io,
            file,
            offset,
            terminator_and_padding[0..trailer_length],
        );
        offset += trailer_length;
    }
    return required - 8;
}

pub const RiffInfoView = struct {
    bytes: []const u8,
    limits: Limits = default_limits,

    pub fn init(bytes: []const u8) !RiffInfoView {
        return initWithLimits(bytes, default_limits);
    }

    pub fn initWithLimits(bytes: []const u8, limits: Limits) !RiffInfoView {
        try limits.validate();
        if (bytes.len > limits.max_encoded_bytes)
            return error.AudioMetadataLimitExceeded;
        if (bytes.len < 12 or
            !std.mem.eql(u8, bytes[0..4], "LIST") or
            !std.mem.eql(u8, bytes[8..12], "INFO"))
            return error.InvalidRiffInfo;
        const payload_bytes = std.mem.readInt(
            u32,
            bytes[4..8],
            .little,
        );
        const total_bytes = std.math.add(
            usize,
            payload_bytes,
            8,
        ) catch return error.InvalidRiffInfo;
        if (total_bytes != bytes.len)
            return error.InvalidRiffInfo;
        var validator = RiffInfoIterator{
            .bytes = bytes,
            .offset = 12,
        };
        while (try validator.nextInPlace()) |_| {}
        return .{ .bytes = bytes, .limits = limits };
    }

    pub fn iterator(self: RiffInfoView) RiffInfoIterator {
        return .{
            .bytes = self.bytes,
            .offset = 12,
            .validated_bytes = self.bytes,
            .validated_offset = 12,
            .limits = self.limits,
        };
    }
};

pub const RiffInfoIterator = struct {
    bytes: []const u8,
    offset: usize,
    validated_bytes: ?[]const u8 = null,
    validated_offset: usize = 0,
    limits: Limits = default_limits,

    pub fn valid(self: RiffInfoIterator) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn next(self: *RiffInfoIterator) !?Entry {
        try self.validateState();
        var trial = self.*;
        const entry = try trial.nextInPlace();
        trial.validated_bytes = trial.bytes;
        trial.validated_offset = trial.offset;
        self.* = trial;
        return entry;
    }

    fn validateState(self: RiffInfoIterator) !void {
        self.limits.validate() catch
            return error.InvalidRiffInfoIteratorState;
        if (self.bytes.len > self.limits.max_encoded_bytes)
            return error.InvalidRiffInfoIteratorState;
        if (self.validated_bytes) |bytes| {
            if (sameByteRange(self.bytes, bytes) and
                self.offset == self.validated_offset)
            {
                return;
            }
        }
        if (self.offset < 12 or self.offset > self.bytes.len)
            return error.InvalidRiffInfoIteratorState;
        const view = try RiffInfoView.initWithLimits(self.bytes, self.limits);
        var canonical = view.iterator();
        var state_seen = self.offset == canonical.offset;
        while (try canonical.nextInPlace()) |_| {
            if (self.offset == canonical.offset) state_seen = true;
        }
        if (!state_seen) return error.InvalidRiffInfoIteratorState;
    }

    fn nextInPlace(self: *RiffInfoIterator) !?Entry {
        if (self.offset == self.bytes.len) return null;
        if (self.bytes.len - self.offset < 8)
            return error.TruncatedRiffInfo;
        const entry_id = self.bytes[self.offset..][0..4].*;
        const value_bytes: usize = std.mem.readInt(
            u32,
            self.bytes[self.offset + 4 ..][0..4],
            .little,
        );
        if (value_bytes == 0) return error.InvalidRiffInfoValue;
        const padded_value = std.math.add(
            usize,
            value_bytes,
            value_bytes & 1,
        ) catch return error.TruncatedRiffInfo;
        const next_offset = std.math.add(
            usize,
            self.offset,
            8 + padded_value,
        ) catch return error.TruncatedRiffInfo;
        if (next_offset > self.bytes.len)
            return error.TruncatedRiffInfo;
        const value_start = self.offset + 8;
        const encoded_value =
            self.bytes[value_start..][0..value_bytes];
        if (encoded_value[value_bytes - 1] != 0)
            return error.InvalidRiffInfoValue;
        if (std.mem.indexOfScalar(
            u8,
            encoded_value[0 .. value_bytes - 1],
            0,
        ) != null)
            return error.InvalidRiffInfoValue;
        if (value_bytes & 1 != 0 and
            self.bytes[next_offset - 1] != 0)
            return error.InvalidRiffInfoPadding;
        self.offset = next_offset;
        return .{
            .id = entry_id,
            .value = encoded_value[0 .. value_bytes - 1],
        };
    }
};

pub fn requiredAiffTextBytes(entries: []const Entry) !usize {
    var required: usize = 0;
    for (entries) |entry| {
        try entry.validate();
        if (entry.value.len > std.math.maxInt(u32))
            return error.MetadataSizeOverflow;
        const padded_value = std.math.add(
            usize,
            entry.value.len,
            entry.value.len & 1,
        ) catch return error.MetadataSizeOverflow;
        required = std.math.add(
            usize,
            required,
            8 + padded_value,
        ) catch return error.MetadataSizeOverflow;
    }
    return required;
}

pub fn encodeAiffText(
    destination: []u8,
    entries: []const Entry,
) ![]const u8 {
    const required = try requiredAiffTextBytes(entries);
    if (destination.len < required)
        return error.MetadataOutputTooSmall;
    const output = destination[0..required];
    try validateEntryStorageDisjoint(output, entries);
    var offset: usize = 0;
    for (entries) |entry| {
        @memcpy(destination[offset..][0..4], &entry.id);
        std.mem.writeInt(
            u32,
            destination[offset + 4 ..][0..4],
            @intCast(entry.value.len),
            .big,
        );
        offset += 8;
        @memcpy(destination[offset..][0..entry.value.len], entry.value);
        offset += entry.value.len;
        if (entry.value.len & 1 != 0) {
            destination[offset] = 0;
            offset += 1;
        }
    }
    return destination[0..required];
}

pub fn writeAiffTextFile(
    io: std.Io,
    file: std.Io.File,
    initial_offset: u64,
    entries: []const Entry,
) !usize {
    const required = try requiredAiffTextBytes(entries);
    var offset = initial_offset;
    for (entries) |entry| {
        var entry_header: [8]u8 = undefined;
        @memcpy(entry_header[0..4], &entry.id);
        std.mem.writeInt(
            u32,
            entry_header[4..8],
            @intCast(entry.value.len),
            .big,
        );
        try writeAt(io, file, offset, &entry_header);
        offset += entry_header.len;
        try writeAt(io, file, offset, entry.value);
        offset += entry.value.len;
        if (entry.value.len & 1 != 0) {
            try writeAt(io, file, offset, &.{0});
            offset += 1;
        }
    }
    return required;
}

pub const AiffTextIterator = struct {
    bytes: []const u8,
    offset: usize = 0,
    validated_bytes: ?[]const u8 = null,
    validated_offset: usize = 0,
    limits: Limits = default_limits,

    pub fn init(bytes: []const u8) !AiffTextIterator {
        return initWithLimits(bytes, default_limits);
    }

    pub fn initWithLimits(
        bytes: []const u8,
        limits: Limits,
    ) !AiffTextIterator {
        try limits.validate();
        if (bytes.len > limits.max_encoded_bytes)
            return error.AudioMetadataLimitExceeded;
        var iterator = AiffTextIterator{ .bytes = bytes, .limits = limits };
        while (try iterator.nextInPlace()) |_| {}
        return .{
            .bytes = bytes,
            .validated_bytes = bytes,
            .limits = limits,
        };
    }

    pub fn valid(self: AiffTextIterator) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn next(self: *AiffTextIterator) !?Entry {
        try self.validateState();
        var trial = self.*;
        const entry = try trial.nextInPlace();
        trial.validated_bytes = trial.bytes;
        trial.validated_offset = trial.offset;
        self.* = trial;
        return entry;
    }

    fn validateState(self: AiffTextIterator) !void {
        self.limits.validate() catch
            return error.InvalidAiffTextIteratorState;
        if (self.bytes.len > self.limits.max_encoded_bytes)
            return error.InvalidAiffTextIteratorState;
        if (self.validated_bytes) |bytes| {
            if (sameByteRange(self.bytes, bytes) and
                self.offset == self.validated_offset)
            {
                return;
            }
        }
        if (self.offset > self.bytes.len)
            return error.InvalidAiffTextIteratorState;
        var canonical = try AiffTextIterator.initWithLimits(
            self.bytes,
            self.limits,
        );
        var state_seen = self.offset == canonical.offset;
        while (try canonical.nextInPlace()) |_| {
            if (self.offset == canonical.offset) state_seen = true;
        }
        if (!state_seen) return error.InvalidAiffTextIteratorState;
    }

    fn nextInPlace(self: *AiffTextIterator) !?Entry {
        if (self.offset == self.bytes.len) return null;
        if (self.bytes.len - self.offset < 8)
            return error.TruncatedAiffMetadata;
        const entry_id = self.bytes[self.offset..][0..4].*;
        const value_bytes: usize = std.mem.readInt(
            u32,
            self.bytes[self.offset + 4 ..][0..4],
            .big,
        );
        const padded_value = std.math.add(
            usize,
            value_bytes,
            value_bytes & 1,
        ) catch return error.TruncatedAiffMetadata;
        const next_offset = std.math.add(
            usize,
            self.offset,
            8 + padded_value,
        ) catch return error.TruncatedAiffMetadata;
        if (next_offset > self.bytes.len)
            return error.TruncatedAiffMetadata;
        const value_start = self.offset + 8;
        if (value_bytes & 1 != 0 and
            self.bytes[next_offset - 1] != 0)
            return error.InvalidAiffMetadataPadding;
        self.offset = next_offset;
        return .{
            .id = entry_id,
            .value = self.bytes[value_start..][0..value_bytes],
        };
    }
};

fn sameByteRange(first: []const u8, second: []const u8) bool {
    return first.len == second.len and first.ptr == second.ptr;
}

fn validateXmlDocument(document: []const u8) !void {
    if (document.len == 0) return error.EmptyXmlDocument;
    if (!std.unicode.utf8ValidateSlice(document))
        return error.InvalidXmlEncoding;
    if (std.mem.indexOfScalar(u8, document, 0) != null)
        return error.XmlDocumentContainsNul;
    var content = document;
    if (std.mem.startsWith(u8, content, "\xef\xbb\xbf"))
        content = content[3..];
    content = std.mem.trim(u8, content, " \t\r\n");
    if (content.len < 3 or content[0] != '<' or
        content[content.len - 1] != '>')
        return error.InvalidXmlEnvelope;
}

fn addMetadataBytes(left: usize, right: usize) !usize {
    return std.math.add(usize, left, right) catch
        return error.MetadataSizeOverflow;
}

fn validateEntryStorageDisjoint(
    output: []const u8,
    entries: []const Entry,
) !void {
    if (byteSlicesOverlap(output, entries))
        return error.MetadataSourceAliasesOutput;
    for (entries) |entry| {
        if (byteSlicesOverlap(output, entry.value))
            return error.MetadataSourceAliasesOutput;
    }
}

fn byteSlicesOverlap(first: anytype, second: anytype) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_bytes = std.mem.sliceAsBytes(first);
    const second_bytes = std.mem.sliceAsBytes(second);
    const first_start = @intFromPtr(first_bytes.ptr);
    const second_start = @intFromPtr(second_bytes.ptr);
    const first_end = std.math.add(
        usize,
        first_start,
        first_bytes.len,
    ) catch return true;
    const second_end = std.math.add(
        usize,
        second_start,
        second_bytes.len,
    ) catch return true;
    return first_start < second_end and second_start < first_end;
}

fn writeAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    bytes: []const u8,
) !void {
    var writer = file.writer(io, &.{});
    try writer.seekTo(offset);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

test "fuzz bounded audio metadata parsing" {
    try std.testing.fuzz({}, fuzzAudioMetadata, .{
        .corpus = &.{
            "ID3\x04\x00\x00\x00\x00\x00\x0c" ++
                "TIT2\x00\x00\x00\x02\x00\x00\x03x",
            "ID3\x03\x00\x00\x00\x00\x00\x0c" ++
                "TIT2\x00\x00\x00\x02\x00\x00\x00x",
            "LIST\x0e\x00\x00\x00INFOINAM\x02\x00\x00\x00x\x00",
            "NAME\x00\x00\x00\x01x\x00",
            "iXML\x09\x00\x00\x00<BWFXML/>\x00",
        },
    });
}

fn fuzzAudioMetadata(_: void, smith: *std.testing.Smith) !void {
    @disableInstrumentation();
    const id3 = @import("id3.zig");
    var encoded: [64 * 1024]u8 = undefined;
    const length = smith.slice(&encoded);
    const source = encoded[0..length];
    const limits = Limits{ .max_encoded_bytes = encoded.len };

    if (RiffInfoView.initWithLimits(source, limits)) |view| {
        var iterator = view.iterator();
        while (true) {
            const previous = iterator.offset;
            const entry = try iterator.next();
            if (entry == null) break;
            if (iterator.offset <= previous)
                return error.AudioMetadataFuzzDidNotProgress;
        }
    } else |_| {}
    if (AiffTextIterator.initWithLimits(source, limits)) |accepted| {
        var iterator = accepted;
        while (true) {
            const previous = iterator.offset;
            const entry = try iterator.next();
            if (entry == null) break;
            if (iterator.offset <= previous)
                return error.AudioMetadataFuzzDidNotProgress;
        }
    } else |_| {}
    if (RiffXmlView.initWithLimits(source, limits)) |_| {} else |_| {}

    const id3_limits = id3.Limits{ .max_encoded_bytes = encoded.len };
    if (id3.View.initWithLimits(source, id3_limits)) |view| {
        var iterator = view.iterator();
        while (true) {
            const previous = iterator.offset;
            const frame = try iterator.next();
            if (frame == null) break;
            if (iterator.offset <= previous)
                return error.AudioMetadataFuzzDidNotProgress;
        }
    } else |_| {}
    var decoded_storage: [encoded.len]u8 = undefined;
    if (id3.V23View.initWithLimits(
        source,
        &decoded_storage,
        id3_limits,
    )) |view| {
        var iterator = view.iterator();
        while (true) {
            const previous = iterator.offset;
            const frame = try iterator.next();
            if (frame == null) break;
            if (iterator.offset <= previous)
                return error.AudioMetadataFuzzDidNotProgress;
        }
    } else |_| {}
}

test "audio metadata parsers enforce retained encoded byte limits" {
    const entries = [_]Entry{.{ .id = title, .value = "value" }};
    var storage: [128]u8 = undefined;
    const riff = try encodeRiffInfo(&storage, &entries);
    try std.testing.expectError(
        error.InvalidAudioMetadataLimits,
        RiffInfoView.initWithLimits(riff, .{ .max_encoded_bytes = 0 }),
    );
    try std.testing.expectError(
        error.AudioMetadataLimitExceeded,
        RiffInfoView.initWithLimits(
            riff,
            .{ .max_encoded_bytes = riff.len - 1 },
        ),
    );
    const riff_view = try RiffInfoView.initWithLimits(
        riff,
        .{ .max_encoded_bytes = riff.len },
    );
    var riff_iterator = riff_view.iterator();
    riff_iterator.limits.max_encoded_bytes = riff.len - 1;
    try std.testing.expect(!riff_iterator.valid());

    const aiff = try encodeAiffText(&storage, &entries);
    try std.testing.expectError(
        error.AudioMetadataLimitExceeded,
        AiffTextIterator.initWithLimits(
            aiff,
            .{ .max_encoded_bytes = aiff.len - 1 },
        ),
    );
    _ = try AiffTextIterator.initWithLimits(
        aiff,
        .{ .max_encoded_bytes = aiff.len },
    );

    const riff_xml = try encodeRiffXml(
        &storage,
        .ixml,
        "<BWFXML/>",
    );
    try std.testing.expectError(
        error.AudioMetadataLimitExceeded,
        RiffXmlView.initWithLimits(
            riff_xml,
            .{ .max_encoded_bytes = riff_xml.len - 1 },
        ),
    );
    _ = try RiffXmlView.initWithLimits(
        riff_xml,
        .{ .max_encoded_bytes = riff_xml.len },
    );
}

test "RIFF INFO metadata round trips known and unknown entries" {
    const entries = [_]Entry{
        .{ .id = title, .value = "Session" },
        .{ .id = artist, .value = "Artist" },
        .{ .id = .{ 'X', 'T', 'A', 'G' }, .value = "custom" },
    };
    var storage: [72]u8 = undefined;
    const encoded = try encodeRiffInfo(&storage, &entries);
    const view = try RiffInfoView.init(encoded);
    var iterator = view.iterator();
    iterator.validated_bytes = null;
    for (entries) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.id, actual.id);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expect((try iterator.next()) == null);

    var invalid_iterator = view.iterator();
    invalid_iterator.offset = 13;
    try std.testing.expect(!invalid_iterator.valid());
    try std.testing.expectError(
        error.InvalidRiffInfoIteratorState,
        invalid_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 13), invalid_iterator.offset);
}

test "RIFF INFO metadata writes directly to a file" {
    const entries = [_]Entry{
        .{ .id = title, .value = "File title" },
        .{ .id = comment, .value = "odd" },
    };
    const required = try requiredRiffInfoBytes(&entries);
    var expected_storage: [64]u8 = undefined;
    const expected = try encodeRiffInfo(&expected_storage, &entries);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "metadata.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.setLength(std.testing.io, required + 7);
    try std.testing.expectEqual(
        required,
        try writeRiffInfoFile(std.testing.io, file, 7, &entries),
    );
    var actual: [64]u8 = undefined;
    try std.testing.expectEqual(
        required,
        try file.readPositionalAll(
            std.testing.io,
            actual[0..required],
            7,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        expected,
        actual[0..required],
    );
}

test "RIFF INFO validation is transactional and rejects malformed input" {
    var storage: [32]u8 = @splat(0xaa);
    const before = storage;
    try std.testing.expectError(
        error.MetadataContainsNul,
        encodeRiffInfo(
            &storage,
            &.{.{ .id = title, .value = "bad\x00value" }},
        ),
    );
    try std.testing.expectEqual(before, storage);

    var malformed = [_]u8{
        'L', 'I', 'S', 'T', 14, 0, 0, 0, 'I', 'N', 'F', 'O',
        'I', 'N', 'A', 'M', 1,  0, 0, 0, 'x', 0,
    };
    try std.testing.expectError(
        error.InvalidRiffInfoValue,
        RiffInfoView.init(&malformed),
    );
    malformed[20] = 0;
    malformed[21] = 1;
    try std.testing.expectError(
        error.InvalidRiffInfoPadding,
        RiffInfoView.init(&malformed),
    );

    var invalid_iterator = RiffInfoIterator{
        .bytes = &.{},
        .offset = 1,
    };
    try std.testing.expect(!invalid_iterator.valid());
    try std.testing.expectError(
        error.InvalidRiffInfoIteratorState,
        invalid_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), invalid_iterator.offset);
}

test "AIFF text metadata round trips padded chunks" {
    const entries = [_]Entry{
        .{ .id = aiff_name, .value = "Title" },
        .{ .id = aiff_author, .value = "Composer" },
    };
    var storage: [40]u8 = undefined;
    const encoded = try encodeAiffText(&storage, &entries);
    var iterator = try AiffTextIterator.init(encoded);
    iterator.validated_bytes = null;
    for (entries) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqual(expected.id, actual.id);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expect((try iterator.next()) == null);

    var middle_iterator = try AiffTextIterator.init(encoded);
    middle_iterator.offset = 1;
    try std.testing.expect(!middle_iterator.valid());
    try std.testing.expectError(
        error.InvalidAiffTextIteratorState,
        middle_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), middle_iterator.offset);

    var invalid_iterator = AiffTextIterator{
        .bytes = &.{},
        .offset = 1,
    };
    try std.testing.expect(!invalid_iterator.valid());
    try std.testing.expectError(
        error.InvalidAiffTextIteratorState,
        invalid_iterator.next(),
    );
    try std.testing.expectEqual(@as(usize, 1), invalid_iterator.offset);
}

test "RIFF XML metadata round trips iXML and aXML chunks" {
    const documents = [_]struct {
        kind: RiffXmlKind,
        document: []const u8,
    }{
        .{
            .kind = .ixml,
            .document = "<?xml version=\"1.0\"?><BWFXML><PROJECT>Film</PROJECT></BWFXML>",
        },
        .{
            .kind = .axml,
            .document = "\xef\xbb\xbf<audioFormatExtended/>",
        },
    };
    for (documents) |expected| {
        var storage: [80]u8 = undefined;
        const encoded = try encodeRiffXml(
            &storage,
            expected.kind,
            expected.document,
        );
        const view = try RiffXmlView.init(encoded);
        try std.testing.expectEqual(expected.kind, view.kind);
        try std.testing.expectEqualStrings(
            expected.document,
            view.document,
        );
    }
}

test "RIFF XML metadata validation is transactional" {
    var storage: [32]u8 = @splat(0xa5);
    const before = storage;
    try std.testing.expectError(
        error.InvalidXmlEncoding,
        encodeRiffXml(&storage, .ixml, "<x>\xff</x>"),
    );
    try std.testing.expectEqual(before, storage);
    try std.testing.expectError(
        error.XmlDocumentContainsNul,
        encodeRiffXml(&storage, .ixml, "<x/>\x00"),
    );
    try std.testing.expectError(
        error.InvalidXmlEnvelope,
        encodeRiffXml(&storage, .axml, "not XML"),
    );
}

test "memory metadata encoders reject overlapping borrowed input" {
    var xml_storage: [32]u8 = @splat(0xa5);
    @memcpy(xml_storage[0..4], "<x/>");
    const xml_before = xml_storage;
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        encodeRiffXml(
            &xml_storage,
            .ixml,
            xml_storage[0..4],
        ),
    );
    try std.testing.expectEqual(xml_before, xml_storage);

    var info_storage: [32]u8 = @splat(0x5a);
    @memcpy(info_storage[0..5], "Title");
    const info_before = info_storage;
    const info_entries = [_]Entry{.{
        .id = title,
        .value = info_storage[0..5],
    }};
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        encodeRiffInfo(&info_storage, &info_entries),
    );
    try std.testing.expectEqual(info_before, info_storage);

    var text_storage: [64]u8 align(@alignOf(Entry)) = @splat(0x3c);
    const text_entries = std.mem.bytesAsSlice(
        Entry,
        text_storage[0..@sizeOf(Entry)],
    );
    text_entries[0] = .{
        .id = aiff_name,
        .value = "Title",
    };
    const text_before = text_storage;
    try std.testing.expectError(
        error.MetadataSourceAliasesOutput,
        encodeAiffText(&text_storage, text_entries),
    );
    try std.testing.expectEqual(text_before, text_storage);
}

test "composed RIFF metadata validates every chunk before file output" {
    const channel_entries = [_]adm.Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    const metadata = RiffMetadata{
        .broadcast = .{
            .description = "Composite",
            .version = .version_2,
        },
        .ixml = "<BWFXML/>",
        .axml = "<audioFormatExtended/>",
        .channel_allocation = .{
            .num_tracks = 1,
            .entries = &channel_entries,
        },
        .info = &.{.{ .id = title, .value = "Title" }},
    };
    const adm_document = try metadata.validateAdm();
    try std.testing.expectEqual(@as(usize, 0), adm_document.declaration_count);
    try std.testing.expectError(
        error.MissingAdmEmissionProfileDocumentVersion,
        metadata.validateEmissionProfileAdm(.{
            .sample_rate = 48_000,
            .bit_depth = 24,
            .channel_count = 1,
            .frame_count = 48_000,
        }),
    );
    const required = try requiredRiffMetadataBytes(metadata);
    try std.testing.expect(required > 650);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "composite.bin",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.setLength(std.testing.io, required + 5);
    try std.testing.expectEqual(
        required,
        try writeRiffMetadataFile(
            std.testing.io,
            file,
            5,
            metadata,
        ),
    );
    var ids: [5][4]u8 = undefined;
    var offset: u64 = 5;
    for (&ids) |*id| {
        var header: [8]u8 = undefined;
        _ = try file.readPositionalAll(
            std.testing.io,
            &header,
            offset,
        );
        id.* = header[0..4].*;
        const payload_bytes =
            std.mem.readInt(u32, header[4..8], .little);
        offset += 8 + payload_bytes + (payload_bytes & 1);
    }
    try std.testing.expectEqualStrings("bext", &ids[0]);
    try std.testing.expectEqualStrings("iXML", &ids[1]);
    try std.testing.expectEqualStrings("axml", &ids[2]);
    try std.testing.expectEqualStrings("chna", &ids[3]);
    try std.testing.expectEqualStrings("LIST", &ids[4]);

    try std.testing.expectError(
        error.InvalidXmlEnvelope,
        requiredRiffMetadataBytes(.{
            .broadcast = .{ .description = "valid" },
            .ixml = "invalid",
        }),
    );
}
