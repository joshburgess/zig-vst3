const std = @import("std");

pub const title = [4]u8{ 'T', 'I', 'T', '2' };
pub const artist = [4]u8{ 'T', 'P', 'E', '1' };
pub const album = [4]u8{ 'T', 'A', 'L', 'B' };
pub const track = [4]u8{ 'T', 'R', 'C', 'K' };
pub const genre = [4]u8{ 'T', 'C', 'O', 'N' };
pub const recording_time = [4]u8{ 'T', 'D', 'R', 'C' };
pub const comment = [4]u8{ 'C', 'O', 'M', 'M' };
pub const attached_picture = [4]u8{ 'A', 'P', 'I', 'C' };

pub const TextEncoding = enum(u8) {
    latin1 = 0,
    utf16 = 1,
    utf16_be = 2,
    utf8 = 3,
};

pub const Frame = struct {
    id: [4]u8,
    payload: []const u8,
    tag_alter_preservation: bool = false,
    file_alter_preservation: bool = false,
    read_only: bool = false,
    grouping_identity: ?u8 = null,
    compressed: bool = false,
    encryption_method: ?u8 = null,
    unsynchronise: bool = false,
    data_length_indicator: ?u32 = null,
};

pub const EncodeOptions = struct {
    experimental: bool = false,
    footer: bool = false,
    padding_bytes: u28 = 0,
};

pub const ExtendedHeader = struct {
    update: bool = false,
    crc: ?u35 = null,
    restrictions: ?u8 = null,
};

pub const Header = struct {
    unsynchronised: bool,
    experimental: bool,
    footer: bool,
    body_bytes: u28,
    extended: ?ExtendedHeader,
    padding_bytes: usize,
};

pub const EncodedFrame = struct {
    id: [4]u8,
    body: []const u8,
    tag_alter_preservation: bool,
    file_alter_preservation: bool,
    read_only: bool,
    grouped: bool,
    compressed: bool,
    encrypted: bool,
    unsynchronised: bool,
    has_data_length_indicator: bool,

    pub fn requiredDecodedBytes(self: EncodedFrame) !usize {
        if (!self.unsynchronised) return self.body.len;
        return decodedUnsynchronisedBytes(self.body);
    }

    pub fn decode(
        self: EncodedFrame,
        destination: []u8,
    ) !DecodedFrame {
        const required = try self.requiredDecodedBytes();
        if (destination.len < required) return error.Id3OutputTooSmall;
        const decoded = destination[0..required];
        if (slicesOverlap(decoded, self.body))
            return error.Id3SourceAliasesOutput;
        if (self.unsynchronised) {
            _ = try decodeUnsynchronised(decoded, self.body);
        } else {
            @memcpy(decoded, self.body);
        }

        var offset: usize = 0;
        const grouping_identity: ?u8 =
            if (self.grouped) takeByte(decoded, &offset) else null;
        const encryption_method: ?u8 =
            if (self.encrypted) takeByte(decoded, &offset) else null;
        const data_length_indicator: ?u32 =
            if (self.has_data_length_indicator)
                try takeSyncsafe32(decoded, &offset)
            else
                null;
        if (offset >= decoded.len) return error.InvalidId3Frame;
        return .{
            .id = self.id,
            .payload = decoded[offset..],
            .tag_alter_preservation = self.tag_alter_preservation,
            .file_alter_preservation = self.file_alter_preservation,
            .read_only = self.read_only,
            .grouping_identity = grouping_identity,
            .compressed = self.compressed,
            .encryption_method = encryption_method,
            .data_length_indicator = data_length_indicator,
        };
    }
};

pub const DecodedFrame = struct {
    id: [4]u8,
    payload: []const u8,
    tag_alter_preservation: bool,
    file_alter_preservation: bool,
    read_only: bool,
    grouping_identity: ?u8,
    compressed: bool,
    encryption_method: ?u8,
    data_length_indicator: ?u32,

    pub fn text(self: DecodedFrame) !Text {
        if (self.id[0] != 'T' or std.mem.eql(u8, &self.id, "TXXX"))
            return error.NotId3TextFrame;
        if (self.compressed or self.encryption_method != null)
            return error.EncodedId3TextFrame;
        if (self.payload.len < 2) return error.InvalidId3TextFrame;
        const encoding: TextEncoding = switch (self.payload[0]) {
            0 => .latin1,
            1 => .utf16,
            2 => .utf16_be,
            3 => .utf8,
            else => return error.UnsupportedId3TextEncoding,
        };
        const value = self.payload[1..];
        try validateText(encoding, value);
        return .{ .encoding = encoding, .value = value };
    }
};

pub const Text = struct {
    encoding: TextEncoding,
    value: []const u8,
};

pub const V23Frame = struct {
    id: [4]u8,
    payload: []const u8,
    tag_alter_preservation: bool = false,
    file_alter_preservation: bool = false,
    read_only: bool = false,
    decompressed_size: ?u32 = null,
    encryption_method: ?u8 = null,
    grouping_identity: ?u8 = null,
};

pub const V23EncodeOptions = struct {
    unsynchronise: bool = false,
    experimental: bool = false,
    extended_header: bool = false,
    padding_bytes: u28 = 0,
    crc: ?u32 = null,
};

pub const V23ExtendedHeader = struct {
    padding_bytes: u32,
    crc: ?u32,
};

pub const V23Header = struct {
    unsynchronised: bool,
    experimental: bool,
    body_bytes: u28,
    extended: ?V23ExtendedHeader,
    padding_bytes: usize,
};

pub const V23EncodedFrame = struct {
    id: [4]u8,
    payload: []const u8,
    tag_alter_preservation: bool,
    file_alter_preservation: bool,
    read_only: bool,
    decompressed_size: ?u32,
    encryption_method: ?u8,
    grouping_identity: ?u8,

    pub fn text(self: V23EncodedFrame) !Text {
        if (self.id[0] != 'T' or std.mem.eql(u8, &self.id, "TXXX"))
            return error.NotId3TextFrame;
        if (self.decompressed_size != null or
            self.encryption_method != null)
            return error.EncodedId3TextFrame;
        if (self.payload.len < 2) return error.InvalidId3TextFrame;
        const encoding: TextEncoding = switch (self.payload[0]) {
            0 => .latin1,
            1 => .utf16,
            else => return error.UnsupportedId3v23TextEncoding,
        };
        const value = self.payload[1..];
        try validateText(encoding, value);
        return .{ .encoding = encoding, .value = value };
    }
};

pub const V23View = struct {
    bytes: []const u8,
    body: []const u8,
    header: V23Header,
    frames_start: usize,
    frames_end: usize,

    pub fn requiredDecodedBytes(bytes: []const u8) !usize {
        const parsed = try parseV23Header(bytes);
        if (!parsed.unsynchronised) return 0;
        return decodedUnsynchronisedBytes(bytes[10..]);
    }

    pub fn init(
        bytes: []const u8,
        decoded_storage: []u8,
    ) !V23View {
        const parsed = try parseV23Header(bytes);
        const body = if (parsed.unsynchronised) blk: {
            const required = try decodedUnsynchronisedBytes(bytes[10..]);
            if (decoded_storage.len < required)
                return error.Id3OutputTooSmall;
            const output = decoded_storage[0..required];
            if (slicesOverlap(output, bytes[10..]))
                return error.Id3SourceAliasesOutput;
            _ = try decodeUnsynchronised(output, bytes[10..]);
            break :blk output;
        } else bytes[10..];

        var frames_start: usize = 0;
        const extended =
            if (parsed.has_extended_header)
                try parseV23ExtendedHeader(body, &frames_start)
            else
                null;
        const frames_end = if (extended) |value| blk: {
            if (value.padding_bytes > body.len - frames_start)
                return error.InvalidId3v23ExtendedHeader;
            break :blk body.len - value.padding_bytes;
        } else try findV23FramesEnd(body, frames_start, body.len);
        for (body[frames_end..]) |byte| {
            if (byte != 0) return error.InvalidId3Padding;
        }
        if (frames_end == frames_start) return error.EmptyId3Tag;

        const view = V23View{
            .bytes = bytes,
            .body = body,
            .header = .{
                .unsynchronised = parsed.unsynchronised,
                .experimental = parsed.experimental,
                .body_bytes = parsed.body_bytes,
                .extended = extended,
                .padding_bytes = body.len - frames_end,
            },
            .frames_start = frames_start,
            .frames_end = frames_end,
        };
        var validator = view.iterator();
        while (try validator.next()) |_| {}
        return view;
    }

    pub fn iterator(self: V23View) V23Iterator {
        return .{ .bytes = self.body[self.frames_start..self.frames_end] };
    }
};

pub const V23Iterator = struct {
    bytes: []const u8,
    offset: usize = 0,

    pub fn next(self: *V23Iterator) !?V23EncodedFrame {
        if (self.offset == self.bytes.len) return null;
        if (self.bytes.len - self.offset < 10)
            return error.TruncatedId3Frame;
        const header = self.bytes[self.offset..][0..10];
        const id = header[0..4].*;
        try validateFrameId(id);
        const body_bytes: usize = std.mem.readInt(
            u32,
            header[4..8],
            .big,
        );
        if (body_bytes == 0) return error.InvalidId3Frame;
        const status = header[8];
        const format = header[9];
        if (status & 0x1f != 0 or format & 0x1f != 0)
            return error.InvalidId3FrameFlags;
        const next_offset = std.math.add(
            usize,
            self.offset + 10,
            body_bytes,
        ) catch return error.TruncatedId3Frame;
        if (next_offset > self.bytes.len)
            return error.TruncatedId3Frame;

        const body = self.bytes[self.offset + 10 .. next_offset];
        var prefix_offset: usize = 0;
        const decompressed_size: ?u32 =
            if (format & 0x80 != 0)
                try takeV23U32(body, &prefix_offset)
            else
                null;
        const encryption_method: ?u8 =
            if (format & 0x40 != 0)
                try takeV23Byte(body, &prefix_offset)
            else
                null;
        const grouping_identity: ?u8 =
            if (format & 0x20 != 0)
                try takeV23Byte(body, &prefix_offset)
            else
                null;
        if (prefix_offset >= body.len) return error.InvalidId3Frame;

        self.offset = next_offset;
        return .{
            .id = id,
            .payload = body[prefix_offset..],
            .tag_alter_preservation = status & 0x80 != 0,
            .file_alter_preservation = status & 0x40 != 0,
            .read_only = status & 0x20 != 0,
            .decompressed_size = decompressed_size,
            .encryption_method = encryption_method,
            .grouping_identity = grouping_identity,
        };
    }
};

pub fn requiredV23Bytes(
    frames: []const V23Frame,
    options: V23EncodeOptions,
) !usize {
    const body_bytes = try countV23Body(frames, options);
    if (body_bytes > std.math.maxInt(u28))
        return error.Id3SizeOverflow;
    return std.math.add(usize, 10, body_bytes) catch
        return error.Id3SizeOverflow;
}

pub fn encodeV23(
    destination: []u8,
    frames: []const V23Frame,
    options: V23EncodeOptions,
) ![]const u8 {
    const required = try requiredV23Bytes(frames, options);
    if (destination.len < required) return error.Id3OutputTooSmall;
    const output = destination[0..required];
    for (frames) |frame| {
        if (slicesOverlap(output, frame.payload))
            return error.Id3SourceAliasesOutput;
    }
    const unsynchronise = try usesV23Unsynchronisation(frames, options);

    @memcpy(output[0..3], "ID3");
    output[3] = 3;
    output[4] = 0;
    output[5] =
        @as(u8, @intFromBool(unsynchronise)) << 7 |
        @as(u8, @intFromBool(hasV23ExtendedHeader(options))) << 6 |
        @as(u8, @intFromBool(options.experimental)) << 5;
    writeSyncsafe28(output[6..10], @intCast(required - 10));

    var writer = UnsynchronisedWriter{
        .destination = output[10..],
        .enabled = unsynchronise,
    };
    if (hasV23ExtendedHeader(options))
        try writeV23ExtendedHeader(&writer, options);
    for (frames) |frame| try writeV23Frame(&writer, frame);
    for (0..options.padding_bytes) |_| try writer.writeByte(0);
    if (unsynchronise) try writer.finish();
    if (writer.offset != required - 10)
        return error.InvalidId3EncoderState;
    return output;
}

pub fn requiredV23TextPayloadBytes(
    encoding: TextEncoding,
    value: []const u8,
) !usize {
    if (encoding != .latin1 and encoding != .utf16)
        return error.UnsupportedId3v23TextEncoding;
    try validateText(encoding, value);
    return std.math.add(usize, value.len, 1) catch
        return error.Id3SizeOverflow;
}

pub fn encodeV23TextPayload(
    destination: []u8,
    encoding: TextEncoding,
    value: []const u8,
) ![]const u8 {
    const required = try requiredV23TextPayloadBytes(encoding, value);
    if (destination.len < required) return error.Id3OutputTooSmall;
    destination[0] = @intFromEnum(encoding);
    @memcpy(destination[1..required], value);
    return destination[0..required];
}

fn countV23Body(
    frames: []const V23Frame,
    options: V23EncodeOptions,
) !usize {
    if (frames.len == 0) return error.EmptyId3Tag;
    var counter = UnsynchronisationCounter{};
    if (hasV23ExtendedHeader(options)) {
        var extended: [14]u8 = undefined;
        const length = encodeV23ExtendedHeader(
            &extended,
            options.padding_bytes,
            options.crc,
        );
        counter.write(extended[0..length]);
    }
    for (frames) |frame| {
        try validateV23Frame(frame);
        var header: [10]u8 = undefined;
        try encodeV23FrameHeader(&header, frame);
        counter.write(&header);
        writeV23FrameBodyToCounter(&counter, frame);
    }
    for (0..options.padding_bytes) |_| counter.writeByte(0);
    if (options.unsynchronise) {
        counter.finish();
        return counter.bytes;
    }
    return rawV23BodyBytes(frames, options);
}

fn usesV23Unsynchronisation(
    frames: []const V23Frame,
    options: V23EncodeOptions,
) !bool {
    if (!options.unsynchronise) return false;
    return try countV23Body(frames, options) >
        try rawV23BodyBytes(frames, options);
}

fn rawV23BodyBytes(
    frames: []const V23Frame,
    options: V23EncodeOptions,
) !usize {
    var bytes: usize = options.padding_bytes;
    if (hasV23ExtendedHeader(options))
        bytes = std.math.add(
            usize,
            bytes,
            if (options.crc == null) 10 else 14,
        ) catch return error.Id3SizeOverflow;
    for (frames) |frame| {
        const body_bytes = try v23FrameBodyBytes(frame);
        const frame_bytes = std.math.add(
            usize,
            10,
            body_bytes,
        ) catch return error.Id3SizeOverflow;
        bytes = std.math.add(
            usize,
            bytes,
            frame_bytes,
        ) catch return error.Id3SizeOverflow;
    }
    return bytes;
}

fn validateV23Frame(frame: V23Frame) !void {
    try validateFrameId(frame.id);
    if (frame.payload.len == 0) return error.EmptyId3Frame;
    if (try v23FrameBodyBytes(frame) > std.math.maxInt(u32))
        return error.Id3SizeOverflow;
}

fn v23FrameBodyBytes(frame: V23Frame) !usize {
    const extra_bytes =
        4 * @as(usize, @intFromBool(frame.decompressed_size != null)) +
        @as(usize, @intFromBool(frame.encryption_method != null)) +
        @as(usize, @intFromBool(frame.grouping_identity != null));
    return std.math.add(usize, frame.payload.len, extra_bytes) catch
        return error.Id3SizeOverflow;
}

fn encodeV23FrameHeader(
    header: *[10]u8,
    frame: V23Frame,
) !void {
    @memcpy(header[0..4], &frame.id);
    std.mem.writeInt(
        u32,
        header[4..8],
        @intCast(try v23FrameBodyBytes(frame)),
        .big,
    );
    header[8] =
        @as(u8, @intFromBool(frame.tag_alter_preservation)) << 7 |
        @as(u8, @intFromBool(frame.file_alter_preservation)) << 6 |
        @as(u8, @intFromBool(frame.read_only)) << 5;
    header[9] =
        @as(u8, @intFromBool(frame.decompressed_size != null)) << 7 |
        @as(u8, @intFromBool(frame.encryption_method != null)) << 6 |
        @as(u8, @intFromBool(frame.grouping_identity != null)) << 5;
}

fn writeV23Frame(
    writer: *UnsynchronisedWriter,
    frame: V23Frame,
) !void {
    var header: [10]u8 = undefined;
    try encodeV23FrameHeader(&header, frame);
    try writer.write(&header);
    if (frame.decompressed_size) |size| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, size, .big);
        try writer.write(&bytes);
    }
    if (frame.encryption_method) |method| try writer.writeByte(method);
    if (frame.grouping_identity) |identity| try writer.writeByte(identity);
    try writer.write(frame.payload);
}

fn writeV23FrameBodyToCounter(
    counter: *UnsynchronisationCounter,
    frame: V23Frame,
) void {
    if (frame.decompressed_size) |size| {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, size, .big);
        counter.write(&bytes);
    }
    if (frame.encryption_method) |method| counter.writeByte(method);
    if (frame.grouping_identity) |identity| counter.writeByte(identity);
    counter.write(frame.payload);
}

fn writeV23ExtendedHeader(
    writer: *UnsynchronisedWriter,
    options: V23EncodeOptions,
) !void {
    var bytes: [14]u8 = undefined;
    const length = encodeV23ExtendedHeader(
        &bytes,
        options.padding_bytes,
        options.crc,
    );
    try writer.write(bytes[0..length]);
}

fn encodeV23ExtendedHeader(
    bytes: *[14]u8,
    padding_bytes: u28,
    crc: ?u32,
) usize {
    const size: u32 = if (crc == null) 6 else 10;
    std.mem.writeInt(u32, bytes[0..4], size, .big);
    std.mem.writeInt(
        u16,
        bytes[4..6],
        if (crc == null) 0 else 0x8000,
        .big,
    );
    std.mem.writeInt(u32, bytes[6..10], padding_bytes, .big);
    if (crc) |value|
        std.mem.writeInt(u32, bytes[10..14], value, .big);
    return size + 4;
}

fn hasV23ExtendedHeader(options: V23EncodeOptions) bool {
    return options.extended_header or options.crc != null;
}

const ParsedV23Header = struct {
    unsynchronised: bool,
    has_extended_header: bool,
    experimental: bool,
    body_bytes: u28,
};

fn parseV23Header(bytes: []const u8) !ParsedV23Header {
    if (bytes.len < 10 or !std.mem.eql(u8, bytes[0..3], "ID3"))
        return error.InvalidId3Header;
    if (bytes[3] != 3 or bytes[4] != 0)
        return error.UnsupportedId3Version;
    if (bytes[5] & 0x1f != 0) return error.InvalidId3HeaderFlags;
    const body_bytes = try readSyncsafe28(bytes[6..10]);
    if (10 + @as(usize, body_bytes) != bytes.len)
        return error.InvalidId3Size;
    return .{
        .unsynchronised = bytes[5] & 0x80 != 0,
        .has_extended_header = bytes[5] & 0x40 != 0,
        .experimental = bytes[5] & 0x20 != 0,
        .body_bytes = body_bytes,
    };
}

fn parseV23ExtendedHeader(
    body: []const u8,
    frames_start: *usize,
) !V23ExtendedHeader {
    if (body.len < 10) return error.TruncatedId3ExtendedHeader;
    const size: usize = std.mem.readInt(u32, body[0..4], .big);
    if (size != 6 and size != 10)
        return error.InvalidId3v23ExtendedHeader;
    const total_size = size + 4;
    if (total_size > body.len)
        return error.TruncatedId3ExtendedHeader;
    const flags = std.mem.readInt(u16, body[4..6], .big);
    if (flags & 0x7fff != 0 or
        (flags & 0x8000 == 0) != (size == 6))
        return error.InvalidId3v23ExtendedHeader;
    const padding_bytes = std.mem.readInt(u32, body[6..10], .big);
    const crc: ?u32 =
        if (size == 10)
            std.mem.readInt(u32, body[10..14], .big)
        else
            null;
    frames_start.* = total_size;
    return .{ .padding_bytes = padding_bytes, .crc = crc };
}

fn findV23FramesEnd(
    body: []const u8,
    frames_start: usize,
    frames_limit: usize,
) !usize {
    var iterator = V23Iterator{ .bytes = body[frames_start..frames_limit] };
    while (iterator.offset < iterator.bytes.len) {
        if (iterator.bytes[iterator.offset] == 0)
            return frames_start + iterator.offset;
        _ = try iterator.next();
    }
    return frames_limit;
}

fn takeV23Byte(bytes: []const u8, offset: *usize) !u8 {
    if (offset.* >= bytes.len) return error.InvalidId3Frame;
    const byte = bytes[offset.*];
    offset.* += 1;
    return byte;
}

fn takeV23U32(bytes: []const u8, offset: *usize) !u32 {
    if (bytes.len - offset.* < 4) return error.InvalidId3Frame;
    const value = std.mem.readInt(u32, bytes[offset.*..][0..4], .big);
    offset.* += 4;
    return value;
}

pub const V1Tag = struct {
    title: []const u8 = "",
    artist: []const u8 = "",
    album: []const u8 = "",
    year: []const u8 = "",
    comment: []const u8 = "",
    track_number: ?u8 = null,
    genre: u8 = 255,
};

pub const V1View = struct {
    bytes: *const [128]u8,
    title: []const u8,
    artist: []const u8,
    album: []const u8,
    year: []const u8,
    comment: []const u8,
    track_number: ?u8,
    genre: u8,

    pub fn init(bytes: []const u8) !V1View {
        if (bytes.len != 128 or !std.mem.eql(u8, bytes[0..3], "TAG"))
            return error.InvalidId3v1Tag;
        const fixed: *const [128]u8 = bytes[0..128];
        const track_number: ?u8 =
            if (fixed[125] == 0 and fixed[126] != 0)
                fixed[126]
            else
                null;
        return .{
            .bytes = fixed,
            .title = v1Field(fixed[3..33]),
            .artist = v1Field(fixed[33..63]),
            .album = v1Field(fixed[63..93]),
            .year = v1Field(fixed[93..97]),
            .comment = v1Field(
                if (track_number == null)
                    fixed[97..127]
                else
                    fixed[97..125],
            ),
            .track_number = track_number,
            .genre = fixed[127],
        };
    }
};

pub fn encodeV1(
    destination: *[128]u8,
    tag: V1Tag,
) !*const [128]u8 {
    const comment_capacity: usize =
        if (tag.track_number == null) 30 else 28;
    try validateV1Field(tag.title, 30);
    try validateV1Field(tag.artist, 30);
    try validateV1Field(tag.album, 30);
    try validateV1Field(tag.year, 4);
    try validateV1Field(tag.comment, comment_capacity);
    if (tag.track_number == 0) return error.InvalidId3v1TrackNumber;
    if (tag.year.len != 0) {
        if (tag.year.len != 4) return error.InvalidId3v1Year;
        for (tag.year) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidId3v1Year;
        }
    }

    var encoded: [128]u8 = @splat(0);
    @memcpy(encoded[0..3], "TAG");
    writeV1Field(encoded[3..33], tag.title);
    writeV1Field(encoded[33..63], tag.artist);
    writeV1Field(encoded[63..93], tag.album);
    writeV1Field(encoded[93..97], tag.year);
    writeV1Field(encoded[97 .. 97 + comment_capacity], tag.comment);
    if (tag.track_number) |track_number| {
        encoded[125] = 0;
        encoded[126] = track_number;
    }
    encoded[127] = tag.genre;
    destination.* = encoded;
    return destination;
}

fn validateV1Field(value: []const u8, capacity: usize) !void {
    if (value.len > capacity) return error.Id3v1FieldTooLong;
    for (value) |byte| {
        if (byte == 0) return error.InvalidId3v1Text;
    }
}

fn writeV1Field(destination: []u8, value: []const u8) void {
    @memcpy(destination[0..value.len], value);
}

fn v1Field(bytes: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
    return bytes[0..end];
}

pub const View = struct {
    bytes: []const u8,
    header: Header,
    frames_start: usize,
    frames_end: usize,

    pub fn init(bytes: []const u8) !View {
        if (bytes.len < 10 or !std.mem.eql(u8, bytes[0..3], "ID3"))
            return error.InvalidId3Header;
        if (bytes[3] != 4 or bytes[4] != 0)
            return error.UnsupportedId3Version;
        const flags = bytes[5];
        if (flags & 0x0f != 0) return error.InvalidId3HeaderFlags;
        const body_bytes = try readSyncsafe28(bytes[6..10]);
        const footer = flags & 0x10 != 0;
        const total_bytes = std.math.add(
            usize,
            10 + @as(usize, if (footer) 10 else 0),
            body_bytes,
        ) catch return error.InvalidId3Size;
        if (total_bytes != bytes.len) return error.InvalidId3Size;

        var frames_start: usize = 10;
        const extended =
            if (flags & 0x40 != 0)
                try parseExtendedHeader(bytes, &frames_start, 10 + body_bytes)
            else
                null;
        const frames_limit = 10 + body_bytes;
        const frames_end = try findFramesEnd(
            bytes,
            frames_start,
            frames_limit,
            flags & 0x80 != 0,
        );
        for (bytes[frames_end..frames_limit]) |byte| {
            if (byte != 0) return error.InvalidId3Padding;
        }
        if (frames_end == frames_start) return error.EmptyId3Tag;
        if (footer)
            try validateFooter(bytes, flags, body_bytes, frames_limit);

        const view = View{
            .bytes = bytes,
            .header = .{
                .unsynchronised = flags & 0x80 != 0,
                .experimental = flags & 0x20 != 0,
                .footer = footer,
                .body_bytes = body_bytes,
                .extended = extended,
                .padding_bytes = frames_limit - frames_end,
            },
            .frames_start = frames_start,
            .frames_end = frames_end,
        };
        var validator = view.iterator();
        while (try validator.next()) |_| {}
        return view;
    }

    pub fn iterator(self: View) Iterator {
        return .{
            .bytes = self.bytes[self.frames_start..self.frames_end],
            .tag_unsynchronised = self.header.unsynchronised,
        };
    }
};

pub const Iterator = struct {
    bytes: []const u8,
    offset: usize = 0,
    tag_unsynchronised: bool,

    pub fn next(self: *Iterator) !?EncodedFrame {
        if (self.offset == self.bytes.len) return null;
        if (self.bytes.len - self.offset < 10)
            return error.TruncatedId3Frame;
        const header = self.bytes[self.offset..][0..10];
        const id = header[0..4].*;
        try validateFrameId(id);
        const body_bytes: usize = try readSyncsafe28(header[4..8]);
        if (body_bytes == 0) return error.InvalidId3Frame;
        const status = header[8];
        const format = header[9];
        if (status & 0x8f != 0 or format & 0xb0 != 0)
            return error.InvalidId3FrameFlags;
        const compressed = format & 0x08 != 0;
        const has_dli = format & 0x01 != 0;
        if (compressed and !has_dli)
            return error.InvalidId3FrameFlags;
        const next_offset = std.math.add(
            usize,
            self.offset + 10,
            body_bytes,
        ) catch return error.TruncatedId3Frame;
        if (next_offset > self.bytes.len)
            return error.TruncatedId3Frame;
        const unsynchronised = format & 0x02 != 0;
        if (self.tag_unsynchronised and !unsynchronised)
            return error.InconsistentId3Unsynchronisation;
        const body = self.bytes[self.offset + 10 .. next_offset];
        const decoded_bytes =
            if (unsynchronised)
                try decodedUnsynchronisedBytes(body)
            else
                body.len;
        const extra_bytes: usize =
            @as(usize, @intFromBool(format & 0x40 != 0)) +
            @as(usize, @intFromBool(format & 0x04 != 0)) +
            4 * @as(usize, @intFromBool(has_dli));
        if (decoded_bytes <= extra_bytes)
            return error.InvalidId3Frame;
        if (has_dli) {
            var prefix: [6]u8 = undefined;
            const prefix_length = @min(decoded_bytes, prefix.len);
            _ = try decodePrefix(
                prefix[0..prefix_length],
                body,
                unsynchronised,
            );
            var dli_offset =
                @as(usize, @intFromBool(format & 0x40 != 0)) +
                @as(usize, @intFromBool(format & 0x04 != 0));
            _ = try takeSyncsafe32(prefix[0..prefix_length], &dli_offset);
        }
        self.offset = next_offset;
        return .{
            .id = id,
            .body = body,
            .tag_alter_preservation = status & 0x40 != 0,
            .file_alter_preservation = status & 0x20 != 0,
            .read_only = status & 0x10 != 0,
            .grouped = format & 0x40 != 0,
            .compressed = compressed,
            .encrypted = format & 0x04 != 0,
            .unsynchronised = unsynchronised,
            .has_data_length_indicator = has_dli,
        };
    }
};

pub fn requiredBytes(
    frames: []const Frame,
    options: EncodeOptions,
) !usize {
    if (frames.len == 0) return error.EmptyId3Tag;
    var body_bytes: usize = options.padding_bytes;
    for (frames) |frame| {
        const frame_bytes = try requiredFrameBytes(frame);
        body_bytes = std.math.add(
            usize,
            body_bytes,
            frame_bytes,
        ) catch return error.Id3SizeOverflow;
    }
    if (body_bytes > std.math.maxInt(u28))
        return error.Id3SizeOverflow;
    return std.math.add(
        usize,
        10 + body_bytes,
        if (options.footer) 10 else 0,
    ) catch return error.Id3SizeOverflow;
}

pub fn encode(
    destination: []u8,
    frames: []const Frame,
    options: EncodeOptions,
) ![]const u8 {
    const required = try requiredBytes(frames, options);
    if (destination.len < required) return error.Id3OutputTooSmall;
    const output = destination[0..required];
    for (frames) |frame| {
        if (slicesOverlap(output, frame.payload))
            return error.Id3SourceAliasesOutput;
    }
    const all_unsynchronised = allUnsynchronised(frames);
    var flags: u8 = 0;
    if (all_unsynchronised) flags |= 0x80;
    if (options.experimental) flags |= 0x20;
    if (options.footer) flags |= 0x10;
    @memcpy(destination[0..3], "ID3");
    destination[3] = 4;
    destination[4] = 0;
    destination[5] = flags;
    const footer_bytes: usize = if (options.footer) 10 else 0;
    const body_bytes: u28 = @intCast(required - 10 - footer_bytes);
    writeSyncsafe28(destination[6..10], body_bytes);

    var offset: usize = 10;
    for (frames) |frame| {
        offset += try encodeFrame(destination[offset..], frame);
    }
    @memset(destination[offset..][0..options.padding_bytes], 0);
    offset += options.padding_bytes;
    if (options.footer) {
        @memcpy(destination[offset..][0..3], "3DI");
        @memcpy(destination[offset + 3 ..][0..7], destination[3..10]);
        offset += 10;
    }
    if (offset != required) return error.InvalidId3EncoderState;
    return destination[0..required];
}

pub fn requiredUtf8TextPayloadBytes(value: []const u8) !usize {
    try validateText(.utf8, value);
    return std.math.add(usize, value.len, 1) catch
        return error.Id3SizeOverflow;
}

pub fn encodeUtf8TextPayload(
    destination: []u8,
    value: []const u8,
) ![]const u8 {
    const required = try requiredUtf8TextPayloadBytes(value);
    if (destination.len < required) return error.Id3OutputTooSmall;
    destination[0] = @intFromEnum(TextEncoding.utf8);
    @memcpy(destination[1..required], value);
    return destination[0..required];
}

fn requiredFrameBytes(frame: Frame) !usize {
    try validateFrame(frame);
    const extra_bytes: usize =
        @as(usize, @intFromBool(frame.grouping_identity != null)) +
        @as(usize, @intFromBool(frame.encryption_method != null)) +
        4 * @as(usize, @intFromBool(frame.data_length_indicator != null));
    const decoded_bytes = std.math.add(
        usize,
        extra_bytes,
        frame.payload.len,
    ) catch return error.Id3SizeOverflow;
    const encoded_bytes =
        if (frame.unsynchronise)
            try requiredUnsynchronisedBytes(frame)
        else
            decoded_bytes;
    if (encoded_bytes > std.math.maxInt(u28))
        return error.Id3SizeOverflow;
    return std.math.add(usize, 10, encoded_bytes) catch
        return error.Id3SizeOverflow;
}

fn validateFrame(frame: Frame) !void {
    try validateFrameId(frame.id);
    if (frame.payload.len == 0) return error.EmptyId3Frame;
    if (frame.compressed and frame.data_length_indicator == null)
        return error.Id3CompressionRequiresDataLength;
    if (frame.data_length_indicator) |length| {
        if (length > std.math.maxInt(u28))
            return error.Id3DataLengthOverflow;
    }
}

fn validateFrameId(id: [4]u8) !void {
    for (id) |byte| {
        if (!std.ascii.isUpper(byte) and !std.ascii.isDigit(byte))
            return error.InvalidId3FrameId;
    }
}

fn encodeFrame(destination: []u8, frame: Frame) !usize {
    const required = try requiredFrameBytes(frame);
    const body_bytes = required - 10;
    @memcpy(destination[0..4], &frame.id);
    writeSyncsafe28(destination[4..8], @intCast(body_bytes));
    destination[8] =
        @as(u8, @intFromBool(frame.tag_alter_preservation)) << 6 |
        @as(u8, @intFromBool(frame.file_alter_preservation)) << 5 |
        @as(u8, @intFromBool(frame.read_only)) << 4;
    destination[9] =
        @as(u8, @intFromBool(frame.grouping_identity != null)) << 6 |
        @as(u8, @intFromBool(frame.compressed)) << 3 |
        @as(u8, @intFromBool(frame.encryption_method != null)) << 2 |
        @as(u8, @intFromBool(frame.unsynchronise)) << 1 |
        @as(u8, @intFromBool(frame.data_length_indicator != null));

    var writer = UnsynchronisedWriter{
        .destination = destination[10..required],
        .enabled = frame.unsynchronise,
    };
    if (frame.grouping_identity) |identity| try writer.writeByte(identity);
    if (frame.encryption_method) |method| try writer.writeByte(method);
    if (frame.data_length_indicator) |length| {
        var encoded: [4]u8 = undefined;
        writeSyncsafe28(&encoded, @intCast(length));
        try writer.write(&encoded);
    }
    try writer.write(frame.payload);
    if (frame.unsynchronise) try writer.finish();
    if (writer.offset != body_bytes)
        return error.InvalidId3EncoderState;
    return required;
}

const UnsynchronisedWriter = struct {
    destination: []u8,
    offset: usize = 0,
    previous_ff: bool = false,
    enabled: bool,

    fn write(self: *UnsynchronisedWriter, bytes: []const u8) !void {
        for (bytes) |byte| try self.writeByte(byte);
    }

    fn writeByte(self: *UnsynchronisedWriter, byte: u8) !void {
        if (self.enabled and self.previous_ff and
            (byte == 0 or byte >= 0xe0))
        {
            try self.put(0);
        }
        try self.put(byte);
        self.previous_ff = byte == 0xff;
    }

    fn finish(self: *UnsynchronisedWriter) !void {
        if (self.previous_ff) try self.put(0);
    }

    fn put(self: *UnsynchronisedWriter, byte: u8) !void {
        if (self.offset >= self.destination.len)
            return error.InvalidId3EncoderState;
        self.destination[self.offset] = byte;
        self.offset += 1;
    }
};

fn requiredUnsynchronisedBytes(frame: Frame) !usize {
    var counter = UnsynchronisationCounter{};
    if (frame.grouping_identity) |identity| counter.writeByte(identity);
    if (frame.encryption_method) |method| counter.writeByte(method);
    if (frame.data_length_indicator) |length| {
        var encoded: [4]u8 = undefined;
        writeSyncsafe28(&encoded, @intCast(length));
        counter.write(&encoded);
    }
    counter.write(frame.payload);
    counter.finish();
    return counter.bytes;
}

const UnsynchronisationCounter = struct {
    bytes: usize = 0,
    previous_ff: bool = false,

    fn write(self: *UnsynchronisationCounter, source: []const u8) void {
        for (source) |byte| self.writeByte(byte);
    }

    fn writeByte(self: *UnsynchronisationCounter, byte: u8) void {
        if (self.previous_ff and (byte == 0 or byte >= 0xe0))
            self.bytes += 1;
        self.bytes += 1;
        self.previous_ff = byte == 0xff;
    }

    fn finish(self: *UnsynchronisationCounter) void {
        if (self.previous_ff) self.bytes += 1;
    }
};

fn decodedUnsynchronisedBytes(source: []const u8) !usize {
    var decoded: usize = 0;
    var offset: usize = 0;
    while (offset < source.len) {
        const byte = source[offset];
        decoded += 1;
        offset += 1;
        if (byte != 0xff or offset >= source.len) continue;
        if (source[offset] != 0) {
            if (source[offset] >= 0xe0)
                return error.InvalidId3Unsynchronisation;
            continue;
        }
        offset += 1;
        if (offset < source.len and source[offset] != 0 and
            source[offset] < 0xe0)
            return error.InvalidId3Unsynchronisation;
    }
    return decoded;
}

fn decodeUnsynchronised(
    destination: []u8,
    source: []const u8,
) !usize {
    var source_offset: usize = 0;
    var destination_offset: usize = 0;
    while (source_offset < source.len) {
        const byte = source[source_offset];
        destination[destination_offset] = byte;
        destination_offset += 1;
        source_offset += 1;
        if (byte != 0xff or source_offset >= source.len) continue;
        if (source[source_offset] != 0) {
            if (source[source_offset] >= 0xe0)
                return error.InvalidId3Unsynchronisation;
            continue;
        }
        source_offset += 1;
        if (source_offset < source.len and source[source_offset] != 0 and
            source[source_offset] < 0xe0)
            return error.InvalidId3Unsynchronisation;
    }
    if (destination_offset != destination.len)
        return error.InvalidId3Unsynchronisation;
    return destination_offset;
}

fn decodePrefix(
    destination: []u8,
    source: []const u8,
    unsynchronised: bool,
) !usize {
    if (!unsynchronised) {
        if (source.len < destination.len) return error.InvalidId3Frame;
        @memcpy(destination, source[0..destination.len]);
        return destination.len;
    }
    var source_offset: usize = 0;
    var destination_offset: usize = 0;
    while (destination_offset < destination.len) {
        if (source_offset >= source.len) return error.InvalidId3Frame;
        const byte = source[source_offset];
        destination[destination_offset] = byte;
        destination_offset += 1;
        source_offset += 1;
        if (byte == 0xff and source_offset < source.len and
            source[source_offset] == 0)
            source_offset += 1;
    }
    return destination_offset;
}

fn parseExtendedHeader(
    bytes: []const u8,
    frames_start: *usize,
    body_end: usize,
) !ExtendedHeader {
    if (body_end - frames_start.* < 6)
        return error.TruncatedId3ExtendedHeader;
    const size: usize = try readSyncsafe28(
        bytes[frames_start.*..][0..4],
    );
    if (size < 6 or size > body_end - frames_start.*)
        return error.InvalidId3ExtendedHeader;
    const extended = bytes[frames_start.*..][0..size];
    if (extended[4] != 1 or extended[5] & 0x8f != 0)
        return error.InvalidId3ExtendedHeader;
    var result = ExtendedHeader{};
    var offset: usize = 6;
    if (extended[5] & 0x40 != 0) {
        if (offset >= extended.len or extended[offset] != 0)
            return error.InvalidId3ExtendedHeader;
        result.update = true;
        offset += 1;
    }
    if (extended[5] & 0x20 != 0) {
        if (extended.len - offset < 6 or extended[offset] != 5)
            return error.InvalidId3ExtendedHeader;
        result.crc = try readSyncsafe35(extended[offset + 1 ..][0..5]);
        offset += 6;
    }
    if (extended[5] & 0x10 != 0) {
        if (extended.len - offset < 2 or extended[offset] != 1)
            return error.InvalidId3ExtendedHeader;
        result.restrictions = extended[offset + 1];
        offset += 2;
    }
    if (offset != extended.len)
        return error.InvalidId3ExtendedHeader;
    frames_start.* += size;
    return result;
}

fn findFramesEnd(
    bytes: []const u8,
    frames_start: usize,
    frames_limit: usize,
    tag_unsynchronised: bool,
) !usize {
    var iterator = Iterator{
        .bytes = bytes[frames_start..frames_limit],
        .tag_unsynchronised = tag_unsynchronised,
    };
    while (iterator.offset < iterator.bytes.len) {
        if (iterator.bytes[iterator.offset] == 0)
            return frames_start + iterator.offset;
        _ = try iterator.next();
    }
    return frames_limit;
}

fn validateFooter(
    bytes: []const u8,
    header_flags: u8,
    body_bytes: u28,
    footer_offset: usize,
) !void {
    const footer = bytes[footer_offset..][0..10];
    if (!std.mem.eql(u8, footer[0..3], "3DI") or
        footer[3] != 4 or footer[4] != 0 or
        footer[5] != header_flags or
        try readSyncsafe28(footer[6..10]) != body_bytes)
        return error.InvalidId3Footer;
}

fn validateText(encoding: TextEncoding, value: []const u8) !void {
    if (value.len == 0) return error.EmptyId3Text;
    switch (encoding) {
        .latin1 => {},
        .utf8 => {
            if (!std.unicode.utf8ValidateSlice(value))
                return error.InvalidId3TextEncoding;
        },
        .utf16 => {
            if (value.len < 2 or value.len & 1 != 0)
                return error.InvalidId3TextEncoding;
            const bom = value[0..2];
            if (!std.mem.eql(u8, bom, "\xff\xfe") and
                !std.mem.eql(u8, bom, "\xfe\xff"))
                return error.InvalidId3TextEncoding;
            try validateUtf16(
                value[2..],
                if (bom[0] == 0xff) .little else .big,
            );
        },
        .utf16_be => {
            if (value.len & 1 != 0)
                return error.InvalidId3TextEncoding;
            try validateUtf16(value, .big);
        },
    }
}

fn validateUtf16(
    bytes: []const u8,
    endian: std.builtin.Endian,
) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const first = std.mem.readInt(u16, bytes[offset..][0..2], endian);
        offset += 2;
        if (first >= 0xd800 and first <= 0xdbff) {
            if (bytes.len - offset < 2)
                return error.InvalidId3TextEncoding;
            const second =
                std.mem.readInt(u16, bytes[offset..][0..2], endian);
            if (second < 0xdc00 or second > 0xdfff)
                return error.InvalidId3TextEncoding;
            offset += 2;
        } else if (first >= 0xdc00 and first <= 0xdfff) {
            return error.InvalidId3TextEncoding;
        }
    }
}

fn allUnsynchronised(frames: []const Frame) bool {
    for (frames) |frame| {
        if (!frame.unsynchronise) return false;
    }
    return frames.len != 0;
}

fn slicesOverlap(left: []const u8, right: []const u8) bool {
    if (left.len == 0 or right.len == 0) return false;
    const left_start = @intFromPtr(left.ptr);
    const right_start = @intFromPtr(right.ptr);
    const left_end = std.math.add(usize, left_start, left.len) catch
        return true;
    const right_end = std.math.add(usize, right_start, right.len) catch
        return true;
    return left_start < right_end and right_start < left_end;
}

fn takeByte(bytes: []const u8, offset: *usize) u8 {
    const byte = bytes[offset.*];
    offset.* += 1;
    return byte;
}

fn takeSyncsafe32(bytes: []const u8, offset: *usize) !u32 {
    if (bytes.len - offset.* < 4) return error.InvalidId3Frame;
    const value = try readSyncsafe28(bytes[offset.*..][0..4]);
    offset.* += 4;
    return value;
}

fn readSyncsafe28(bytes: *const [4]u8) !u28 {
    for (bytes) |byte| {
        if (byte & 0x80 != 0) return error.InvalidId3SyncsafeInteger;
    }
    return @as(u28, bytes[0]) << 21 |
        @as(u28, bytes[1]) << 14 |
        @as(u28, bytes[2]) << 7 |
        bytes[3];
}

fn writeSyncsafe28(bytes: *[4]u8, value: u28) void {
    bytes.* = .{
        @intCast(value >> 21),
        @intCast((value >> 14) & 0x7f),
        @intCast((value >> 7) & 0x7f),
        @intCast(value & 0x7f),
    };
}

fn readSyncsafe35(bytes: *const [5]u8) !u35 {
    var value: u35 = 0;
    for (bytes) |byte| {
        if (byte & 0x80 != 0) return error.InvalidId3SyncsafeInteger;
        value = value << 7 | byte;
    }
    return value;
}

test "ID3v2.3 tag-wide unsynchronisation preserves frame prefixes" {
    const title_payload = [_]u8{ 1, 0xff, 0xfe, 'A', 0 };
    const binary_payload = [_]u8{
        0xff, 0xe1, 0xff, 0, 0xff, 0x20,
    };
    const frames = [_]V23Frame{
        .{ .id = title, .payload = &title_payload },
        .{
            .id = .{ 'X', 'B', 'I', 'N' },
            .payload = &binary_payload,
            .tag_alter_preservation = true,
            .read_only = true,
            .decompressed_size = 1234,
            .encryption_method = 0xff,
            .grouping_identity = 0xe2,
        },
    };
    const options = V23EncodeOptions{
        .unsynchronise = true,
        .experimental = true,
        .padding_bytes = 3,
        .crc = 0x1234_5678,
    };
    var encoded_storage: [160]u8 = undefined;
    const encoded = try encodeV23(&encoded_storage, &frames, options);
    try std.testing.expectEqual(
        encoded.len,
        try requiredV23Bytes(&frames, options),
    );
    try std.testing.expectEqual(@as(u8, 3), encoded[3]);
    try std.testing.expectEqual(@as(u8, 0xe0), encoded[5]);
    try std.testing.expect(
        std.mem.indexOf(u8, encoded, "\xff\x00\xe1") != null,
    );

    var decoded_storage: [160]u8 = undefined;
    try std.testing.expect(
        try V23View.requiredDecodedBytes(encoded) > 0,
    );
    const view = try V23View.init(encoded, &decoded_storage);
    try std.testing.expect(view.header.unsynchronised);
    try std.testing.expect(view.header.experimental);
    try std.testing.expectEqual(@as(usize, 3), view.header.padding_bytes);
    try std.testing.expectEqual(
        @as(?u32, 0x1234_5678),
        view.header.extended.?.crc,
    );
    try std.testing.expectEqual(
        @as(u32, title_payload.len),
        std.mem.readInt(
            u32,
            view.body[view.frames_start + 4 ..][0..4],
            .big,
        ),
    );

    var iterator = view.iterator();
    const title_frame = (try iterator.next()).?;
    try std.testing.expectEqualStrings(
        title_payload[1..],
        (try title_frame.text()).value,
    );
    const binary_frame = (try iterator.next()).?;
    try std.testing.expect(binary_frame.tag_alter_preservation);
    try std.testing.expect(binary_frame.read_only);
    try std.testing.expectEqual(
        @as(?u32, 1234),
        binary_frame.decompressed_size,
    );
    try std.testing.expectEqual(
        @as(?u8, 0xff),
        binary_frame.encryption_method,
    );
    try std.testing.expectEqual(
        @as(?u8, 0xe2),
        binary_frame.grouping_identity,
    );
    try std.testing.expectEqualSlices(
        u8,
        &binary_payload,
        binary_frame.payload,
    );
    try std.testing.expect((try iterator.next()) == null);
}

test "ID3v2.3 extended header without CRC declares padding" {
    var text_storage: [8]u8 = undefined;
    const text_payload = try encodeV23TextPayload(
        &text_storage,
        .latin1,
        "x",
    );
    const frames = [_]V23Frame{
        .{ .id = title, .payload = text_payload },
    };
    const options = V23EncodeOptions{
        .unsynchronise = true,
        .extended_header = true,
        .padding_bytes = 5,
    };
    var storage: [64]u8 = undefined;
    const encoded = try encodeV23(&storage, &frames, options);
    try std.testing.expectEqual(@as(u8, 0x40), encoded[5]);
    try std.testing.expectEqual(
        @as(u32, 6),
        std.mem.readInt(u32, encoded[10..14], .big),
    );
    const view = try V23View.init(encoded, &.{});
    try std.testing.expect(!view.header.unsynchronised);
    try std.testing.expectEqual(
        @as(?u32, null),
        view.header.extended.?.crc,
    );
    try std.testing.expectEqual(@as(usize, 5), view.header.padding_bytes);
}

test "ID3v2.3 validation is transactional and version-specific" {
    var destination: [64]u8 = @splat(0xa5);
    const before = destination;
    try std.testing.expectError(
        error.InvalidId3FrameId,
        encodeV23(
            &destination,
            &.{.{ .id = .{ 'b', 'a', 'd', '!' }, .payload = "x" }},
            .{},
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);

    var encoded_storage: [64]u8 = undefined;
    const encoded = try encodeV23(
        &encoded_storage,
        &.{.{ .id = title, .payload = &.{ 3, 'x' } }},
        .{},
    );
    const view = try V23View.init(encoded, &.{});
    var iterator = view.iterator();
    try std.testing.expectError(
        error.UnsupportedId3v23TextEncoding,
        (try iterator.next()).?.text(),
    );
    encoded_storage[19] = 1;
    try std.testing.expectError(
        error.InvalidId3FrameFlags,
        V23View.init(encoded, &.{}),
    );

    const malformed_unsynchronisation = [_]u8{
        'I', 'D', '3', 3, 0, 0x80, 0, 0, 0, 2, 0xff, 0xe0,
    };
    try std.testing.expectError(
        error.InvalidId3Unsynchronisation,
        V23View.requiredDecodedBytes(&malformed_unsynchronisation),
    );
}

test "ID3v2.3 uses ordinary frame sizes and rejects storage aliasing" {
    const payload: [128]u8 = @splat(0x20);
    const frames = [_]V23Frame{
        .{ .id = .{ 'X', 'B', 'I', 'N' }, .payload = &payload },
    };
    var storage: [192]u8 = undefined;
    const encoded = try encodeV23(&storage, &frames, .{});
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0, 0, 0x80 },
        encoded[14..18],
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        try V23View.requiredDecodedBytes(encoded),
    );

    var alias_storage: [96]u8 = @splat(0xa5);
    alias_storage[20] = 0xff;
    alias_storage[21] = 0xe1;
    const before = alias_storage;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        encodeV23(
            &alias_storage,
            &.{.{
                .id = .{ 'X', 'B', 'I', 'N' },
                .payload = alias_storage[20..22],
            }},
            .{ .unsynchronise = true },
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &alias_storage);

    var unsynchronised_storage: [64]u8 = undefined;
    const unsynchronised = try encodeV23(
        &unsynchronised_storage,
        &.{.{
            .id = .{ 'X', 'B', 'I', 'N' },
            .payload = &.{ 0xff, 0xe1 },
        }},
        .{ .unsynchronise = true },
    );
    const decoded_bytes = try V23View.requiredDecodedBytes(unsynchronised);
    try std.testing.expectError(
        error.Id3OutputTooSmall,
        V23View.init(
            unsynchronised,
            unsynchronised_storage[0 .. decoded_bytes - 1],
        ),
    );
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        V23View.init(
            unsynchronised,
            unsynchronised_storage[10 .. 10 + decoded_bytes],
        ),
    );
}

test "ID3v2.3 rejects malformed extended headers and declared padding" {
    const frames = [_]V23Frame{
        .{ .id = title, .payload = &.{ 0, 'x' } },
    };
    var storage: [64]u8 = undefined;
    const encoded = try encodeV23(&storage, &frames, .{
        .extended_header = true,
        .padding_bytes = 2,
    });
    storage[15] = 1;
    try std.testing.expectError(
        error.InvalidId3v23ExtendedHeader,
        V23View.init(encoded, &.{}),
    );

    _ = try encodeV23(&storage, &frames, .{
        .extended_header = true,
        .padding_bytes = 2,
    });
    std.mem.writeInt(u32, storage[16..20], 1_000, .big);
    try std.testing.expectError(
        error.InvalidId3v23ExtendedHeader,
        V23View.init(encoded, &.{}),
    );
}

test "ID3v1 and ID3v1.1 fixed tags round trip" {
    var storage: [128]u8 = undefined;
    const encoded = try encodeV1(&storage, .{
        .title = "Title",
        .artist = "Artist",
        .album = "Album",
        .year = "1998",
        .comment = "Thirty-byte comment fits here.",
        .genre = 17,
    });
    const view = try V1View.init(encoded);
    try std.testing.expectEqualStrings("Title", view.title);
    try std.testing.expectEqualStrings("Artist", view.artist);
    try std.testing.expectEqualStrings("Album", view.album);
    try std.testing.expectEqualStrings("1998", view.year);
    try std.testing.expectEqualStrings(
        "Thirty-byte comment fits here.",
        view.comment,
    );
    try std.testing.expectEqual(@as(?u8, null), view.track_number);
    try std.testing.expectEqual(@as(u8, 17), view.genre);

    _ = try encodeV1(&storage, .{
        .title = "Track",
        .comment = "Short",
        .track_number = 7,
    });
    const v11 = try V1View.init(&storage);
    try std.testing.expectEqual(@as(?u8, 7), v11.track_number);
    try std.testing.expectEqualStrings("Short", v11.comment);
    try std.testing.expectEqual(@as(u8, 0), storage[125]);
    try std.testing.expectEqual(@as(u8, 7), storage[126]);
}

test "ID3v1 validation completes before output mutation" {
    var storage: [128]u8 = @splat(0xa5);
    const before = storage;
    try std.testing.expectError(
        error.InvalidId3v1TrackNumber,
        encodeV1(&storage, .{ .track_number = 0 }),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);
    try std.testing.expectError(
        error.InvalidId3v1Year,
        encodeV1(&storage, .{ .year = "98" }),
    );
    try std.testing.expectError(
        error.Id3v1FieldTooLong,
        encodeV1(&storage, .{ .title = "1234567890123456789012345678901" }),
    );
    try std.testing.expectError(
        error.InvalidId3v1Text,
        encodeV1(&storage, .{ .artist = "a\x00b" }),
    );
    try std.testing.expectError(
        error.InvalidId3v1Tag,
        V1View.init(storage[0..127]),
    );
}

test "ID3v2.4 UTF-8 text frames round trip with footer and padding" {
    var title_payload_storage: [64]u8 = undefined;
    const title_payload = try encodeUtf8TextPayload(
        &title_payload_storage,
        "A Unicode title \xe2\x99\xab",
    );
    var artist_payload_storage: [32]u8 = undefined;
    const artist_payload = try encodeUtf8TextPayload(
        &artist_payload_storage,
        "Artist",
    );
    const frames = [_]Frame{
        .{ .id = title, .payload = title_payload },
        .{
            .id = artist,
            .payload = artist_payload,
            .read_only = true,
        },
    };
    var storage: [160]u8 = undefined;
    const encoded = try encode(&storage, &frames, .{
        .experimental = true,
        .footer = true,
        .padding_bytes = 7,
    });
    const view = try View.init(encoded);
    try std.testing.expect(view.header.experimental);
    try std.testing.expect(view.header.footer);
    try std.testing.expectEqual(@as(usize, 7), view.header.padding_bytes);
    try std.testing.expect(!view.header.unsynchronised);

    var decoded_storage: [64]u8 = undefined;
    var iterator = view.iterator();
    const decoded_title =
        try (try iterator.next()).?.decode(&decoded_storage);
    const title_text = try decoded_title.text();
    try std.testing.expectEqual(TextEncoding.utf8, title_text.encoding);
    try std.testing.expectEqualStrings(
        "A Unicode title \xe2\x99\xab",
        title_text.value,
    );
    const decoded_artist =
        try (try iterator.next()).?.decode(&decoded_storage);
    try std.testing.expect(decoded_artist.read_only);
    try std.testing.expectEqualStrings(
        "Artist",
        (try decoded_artist.text()).value,
    );
    try std.testing.expect((try iterator.next()) == null);
}

test "ID3v2.4 unsynchronisation crosses format fields and payload" {
    const payload = [_]u8{
        0xe1, 0xff, 0x00, 0x20, 0xff, 0x20, 0xff,
    };
    const frames = [_]Frame{.{
        .id = .{ 'X', 'B', 'I', 'N' },
        .payload = &payload,
        .grouping_identity = 0xff,
        .encryption_method = 0xe2,
        .unsynchronise = true,
        .data_length_indicator = payload.len,
    }};
    var storage: [96]u8 = undefined;
    const encoded = try encode(&storage, &frames, .{});
    const view = try View.init(encoded);
    try std.testing.expect(view.header.unsynchronised);
    var iterator = view.iterator();
    const encoded_frame = (try iterator.next()).?;
    try std.testing.expect(encoded_frame.unsynchronised);
    try std.testing.expect(
        std.mem.indexOf(u8, encoded_frame.body, "\xff\x00\xe2") != null,
    );
    try std.testing.expect(
        std.mem.endsWith(u8, encoded_frame.body, "\xff\x00"),
    );
    var decoded_storage: [32]u8 = undefined;
    const decoded = try encoded_frame.decode(&decoded_storage);
    try std.testing.expectEqual(@as(?u8, 0xff), decoded.grouping_identity);
    try std.testing.expectEqual(@as(?u8, 0xe2), decoded.encryption_method);
    try std.testing.expectEqual(
        @as(?u32, payload.len),
        decoded.data_length_indicator,
    );
    try std.testing.expectEqualSlices(u8, &payload, decoded.payload);
}

test "ID3v2.4 parser exposes extended header fields" {
    var bytes = [_]u8{
        'I', 'D', '3', 4,  0,    0x40, 0,   0,   0,   28,
        0,   0,   0,   15, 1,    0x70, 0,   5,   0,   0,
        0,   0,   1,   1,  0xa5, 'T',  'I', 'T', '2', 0,
        0,   0,   3,   0,  0,    3,    'x', 'y',
    };
    const view = try View.init(&bytes);
    const extended = view.header.extended.?;
    try std.testing.expect(extended.update);
    try std.testing.expectEqual(@as(?u35, 1), extended.crc);
    try std.testing.expectEqual(@as(?u8, 0xa5), extended.restrictions);
}

test "ID3v2.4 validation rejects malformed input before encoding" {
    var destination: [48]u8 = @splat(0xa5);
    const before = destination;
    try std.testing.expectError(
        error.InvalidId3FrameId,
        encode(
            &destination,
            &.{.{ .id = .{ 'B', 'a', 'D', '!' }, .payload = "x" }},
            .{},
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    try std.testing.expectError(
        error.Id3CompressionRequiresDataLength,
        requiredBytes(
            &.{.{ .id = title, .payload = "x", .compressed = true }},
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidId3SyncsafeInteger,
        View.init(&.{
            'I', 'D', '3', 4, 0, 0, 0x80, 0, 0, 0,
        }),
    );
}

test "ID3v2.4 rejects source and output aliasing before mutation" {
    var storage: [64]u8 = @splat(0xa5);
    storage[20] = 3;
    storage[21] = 'x';
    const before = storage;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        encode(
            &storage,
            &.{.{ .id = title, .payload = storage[20..22] }},
            .{},
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &storage);

    var encoded_storage: [64]u8 = undefined;
    const encoded = try encode(
        &encoded_storage,
        &.{.{ .id = title, .payload = &.{ 3, 'x' } }},
        .{},
    );
    const view = try View.init(encoded);
    var iterator = view.iterator();
    const encoded_frame = (try iterator.next()).?;
    try std.testing.expectError(
        error.Id3SourceAliasesOutput,
        encoded_frame.decode(encoded_storage[20..]),
    );
}

test "ID3v2.4 parser rejects invalid padding and unsynchronisation" {
    var storage: [64]u8 = undefined;
    const encoded = try encode(
        &storage,
        &.{.{ .id = title, .payload = &.{ 3, 'x' } }},
        .{ .padding_bytes = 2 },
    );
    storage[encoded.len - 1] = 1;
    try std.testing.expectError(error.InvalidId3Padding, View.init(encoded));

    const malformed = [_]u8{
        'I',  'D', '3',  4,   0, 0x80, 0, 0, 0, 13,
        'X',  'B', 'I',  'N', 0, 0,    0, 3, 0, 2,
        0xff, 0,   0x20,
    };
    try std.testing.expectError(
        error.InvalidId3Unsynchronisation,
        View.init(&malformed),
    );
}

test "ID3 text validation covers UTF-16 and UTF-8 failures" {
    const valid_utf16 = DecodedFrame{
        .id = title,
        .payload = &.{ 1, 0xff, 0xfe, 0x34, 0xd8, 0x1e, 0xdd },
        .tag_alter_preservation = false,
        .file_alter_preservation = false,
        .read_only = false,
        .grouping_identity = null,
        .compressed = false,
        .encryption_method = null,
        .data_length_indicator = null,
    };
    try std.testing.expectEqual(
        TextEncoding.utf16,
        (try valid_utf16.text()).encoding,
    );
    var invalid_utf8 = valid_utf16;
    invalid_utf8.payload = &.{ 3, 0xff };
    try std.testing.expectError(
        error.InvalidId3TextEncoding,
        invalid_utf8.text(),
    );
}
