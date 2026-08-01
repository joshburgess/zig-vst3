const std = @import("std");
const fft = @import("fft.zig");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");

pub const unknown_granule = std.math.maxInt(u64);
pub const maximum_page_segments = 255;
pub const maximum_page_body_bytes = 255 * 255;
pub const maximum_page_bytes = 27 + maximum_page_segments +
    maximum_page_body_bytes;

pub const Page = struct {
    continued: bool,
    beginning: bool,
    end: bool,
    logical_stream_index: u32 = 0,
    byte_offset: u64 = 0,
    byte_length: u32 = 0,
    granule_position: u64,
    serial_number: u32,
    sequence_number: u32,
    lacing_values: []const u8,
    body: []const u8,
};

pub const PageIterator = struct {
    encoded: []const u8,
    offset: usize = 0,
    serial_number: ?u32 = null,
    expected_sequence: ?u32 = null,
    packet_continues: bool = false,
    ended: bool = false,
    allow_chaining: bool = false,
    logical_stream_index: u32 = 0,

    pub fn init(encoded: []const u8) PageIterator {
        return .{ .encoded = encoded };
    }

    pub fn initChained(encoded: []const u8) PageIterator {
        return .{ .encoded = encoded, .allow_chaining = true };
    }

    pub fn next(self: *PageIterator) !?Page {
        var trial = self.*;
        const page = try trial.nextInPlace();
        self.* = trial;
        return page;
    }

    /// Advances past at most `maximum_skip_bytes` to a continuous valid page.
    pub fn resynchronize(
        self: *PageIterator,
        maximum_skip_bytes: usize,
    ) !usize {
        if (self.offset > self.encoded.len)
            return error.InvalidOggReaderState;
        if (maximum_skip_bytes == 0)
            return error.InvalidOggResynchronizationLimit;
        if (self.offset >= self.encoded.len -| 27)
            return error.OggResynchronizationLimitReached;
        const first_candidate = std.math.add(
            usize,
            self.offset,
            1,
        ) catch return error.OggByteCountOverflow;
        const last_candidate = @min(
            self.encoded.len - 27,
            std.math.add(
                usize,
                self.offset,
                maximum_skip_bytes,
            ) catch self.encoded.len - 27,
        );
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            if (!std.mem.eql(
                u8,
                self.encoded[candidate..][0..4],
                "OggS",
            )) continue;
            var trial = self.*;
            trial.offset = candidate;
            _ = trial.nextInPlace() catch continue;
            const skipped = candidate - self.offset;
            self.offset = candidate;
            return skipped;
        }
        return error.OggResynchronizationLimitReached;
    }

    fn nextInPlace(self: *PageIterator) !?Page {
        if (self.offset > self.encoded.len)
            return error.InvalidOggReaderState;
        if (self.offset == self.encoded.len) {
            if (self.packet_continues) return error.TruncatedOggPacket;
            return null;
        }
        if (self.ended) {
            if (!self.allow_chaining)
                return error.OggDataAfterEndOfStream;
            if (self.logical_stream_index == std.math.maxInt(u32))
                return error.OggLogicalStreamCountOverflow;
            self.serial_number = null;
            self.expected_sequence = null;
            self.ended = false;
            self.logical_stream_index += 1;
        }
        if (self.encoded.len - self.offset < 27)
            return error.TruncatedOggPage;
        const start = self.offset;
        const header = self.encoded[start..][0..27];
        if (!std.mem.eql(u8, header[0..4], "OggS"))
            return error.InvalidOggCapturePattern;
        if (header[4] != 0) return error.UnsupportedOggVersion;
        if (header[5] & 0xf8 != 0) return error.InvalidOggHeaderFlags;
        const segment_count: usize = header[26];
        const header_bytes = 27 + segment_count;
        if (self.encoded.len - start < header_bytes)
            return error.TruncatedOggPage;
        const lacing = self.encoded[start + 27 .. start + header_bytes];
        var body_bytes: usize = 0;
        for (lacing) |value| body_bytes += value;
        const page_bytes = header_bytes + body_bytes;
        if (self.encoded.len - start < page_bytes)
            return error.TruncatedOggPage;
        const complete = self.encoded[start .. start + page_bytes];
        const stored_crc = std.mem.readInt(u32, header[22..26], .little);
        if (pageChecksum(complete) != stored_crc)
            return error.OggPageChecksumMismatch;

        const flags = header[5];
        const continued = flags & 0x01 != 0;
        const beginning = flags & 0x02 != 0;
        const end = flags & 0x04 != 0;
        if (continued != self.packet_continues)
            return error.InvalidOggContinuation;
        const serial = std.mem.readInt(u32, header[14..18], .little);
        const sequence = std.mem.readInt(u32, header[18..22], .little);
        if (self.serial_number) |expected| {
            if (serial != expected) return error.OggLogicalStreamChanged;
        } else {
            self.serial_number = serial;
            if (!beginning) return error.MissingOggBeginningOfStream;
        }
        if (self.expected_sequence) |expected| {
            if (sequence != expected) return error.InvalidOggPageSequence;
            if (beginning) return error.DuplicateOggBeginningOfStream;
        }
        self.expected_sequence = sequence +% 1;
        self.packet_continues =
            lacing.len != 0 and lacing[lacing.len - 1] == 255;
        if (end and self.packet_continues)
            return error.InvalidOggEndOfStream;
        self.ended = end;
        self.offset += page_bytes;
        return .{
            .continued = continued,
            .beginning = beginning,
            .end = end,
            .logical_stream_index = self.logical_stream_index,
            .byte_offset = start,
            .byte_length = @intCast(page_bytes),
            .granule_position = std.mem.readInt(u64, header[6..14], .little),
            .serial_number = serial,
            .sequence_number = sequence,
            .lacing_values = lacing,
            .body = complete[header_bytes..],
        };
    }
};

pub const Packet = struct {
    bytes: []const u8,
    granule_position: u64,
    beginning: bool,
    end: bool,
    logical_stream_index: u32 = 0,
};

pub const PacketIterator = struct {
    pages: PageIterator,
    storage: []u8,
    page: ?Page = null,
    segment_index: usize = 0,
    body_offset: usize = 0,
    packet_bytes: usize = 0,
    packet_index: u64 = 0,
    logical_stream_packet_index: u64 = 0,

    /// Returned packet bytes remain valid until the next call.
    pub fn init(encoded: []const u8, storage: []u8) PacketIterator {
        return .{
            .pages = PageIterator.init(encoded),
            .storage = storage,
        };
    }

    pub fn initChained(
        encoded: []const u8,
        storage: []u8,
    ) PacketIterator {
        return .{
            .pages = PageIterator.initChained(encoded),
            .storage = storage,
        };
    }

    pub fn next(self: *PacketIterator) !?Packet {
        var trial = self.*;
        const packet = try trial.nextInPlace();
        self.* = trial;
        return packet;
    }

    /// Recover only after a complete packet exhausts its page.
    pub fn resynchronize(
        self: *PacketIterator,
        maximum_skip_bytes: usize,
    ) !usize {
        try self.validateState();
        const at_page_boundary = if (self.page) |page|
            self.segment_index == page.lacing_values.len
        else
            true;
        if (self.packet_bytes != 0 or !at_page_boundary) {
            return error.OggPacketResynchronizationRequiresPageBoundary;
        }
        var pages = self.pages;
        const skipped = try pages.resynchronize(
            maximum_skip_bytes,
        );
        self.pages = pages;
        self.page = null;
        self.segment_index = 0;
        self.body_offset = 0;
        return skipped;
    }

    fn nextInPlace(self: *PacketIterator) !?Packet {
        try self.validateState();
        while (true) {
            if (self.page == null or
                self.segment_index == self.page.?.lacing_values.len)
            {
                self.page = try self.pages.next() orelse {
                    if (self.packet_bytes != 0)
                        return error.TruncatedOggPacket;
                    return null;
                };
                self.segment_index = 0;
                self.body_offset = 0;
                if (self.page.?.beginning)
                    self.logical_stream_packet_index = 0;
            }
            const page = self.page.?;
            if (page.lacing_values.len == 0) {
                self.page = null;
                continue;
            }
            const segment_bytes: usize =
                page.lacing_values[self.segment_index];
            if (segment_bytes > self.storage.len -| self.packet_bytes)
                return error.OggPacketBufferTooSmall;
            @memcpy(
                self.storage[self.packet_bytes..][0..segment_bytes],
                page.body[self.body_offset..][0..segment_bytes],
            );
            self.packet_bytes += segment_bytes;
            self.body_offset += segment_bytes;
            self.segment_index += 1;
            if (segment_bytes == 255) continue;

            var later_packet_ends = false;
            for (page.lacing_values[self.segment_index..]) |value| {
                if (value < 255) {
                    later_packet_ends = true;
                    break;
                }
            }
            const granule = if (later_packet_ends)
                unknown_granule
            else
                page.granule_position;
            const bytes = self.storage[0..self.packet_bytes];
            const packet = Packet{
                .bytes = bytes,
                .granule_position = granule,
                .beginning = self.logical_stream_packet_index == 0,
                .end = page.end and
                    self.segment_index == page.lacing_values.len,
                .logical_stream_index = page.logical_stream_index,
            };
            self.packet_bytes = 0;
            if (self.packet_index == std.math.maxInt(u64) or
                self.logical_stream_packet_index ==
                    std.math.maxInt(u64))
                return error.OggPacketCountOverflow;
            self.packet_index += 1;
            self.logical_stream_packet_index += 1;
            return packet;
        }
    }

    fn validateState(self: *const PacketIterator) !void {
        if (self.packet_bytes > self.storage.len)
            return error.InvalidOggPacketReaderState;
        const page = self.page orelse {
            if (self.segment_index != 0 or self.body_offset != 0)
                return error.InvalidOggPacketReaderState;
            return;
        };
        if (self.segment_index > page.lacing_values.len or
            self.body_offset > page.body.len)
            return error.InvalidOggPacketReaderState;
        var consumed: usize = 0;
        for (page.lacing_values[0..self.segment_index]) |value|
            consumed += value;
        var total = consumed;
        for (page.lacing_values[self.segment_index..]) |value|
            total += value;
        if (consumed != self.body_offset or total != page.body.len)
            return error.InvalidOggPacketReaderState;
    }
};

pub const VorbisPacketLocation = struct {
    byte_offset: u64,
    serial_number: u32,
    sequence_number: u32,
    logical_stream_index: u32,
    logical_packet_index: u64,
    completed_packets_before: u16,
    continued: bool,
};

pub const VorbisSeekPoint = struct {
    pcm_end: i64,
    decode: VorbisPacketLocation,
    packet: VorbisPacketLocation,
};

const VorbisSeekIndexer = struct {
    destination: ?[]VorbisSeekPoint,
    count: usize = 0,
    logical_stream_index: ?u32 = null,
    logical_packet_index: u64 = 0,
    current_packet: ?VorbisPacketLocation = null,
    first_audio_packet: ?VorbisPacketLocation = null,
    previous_audio_packet: ?VorbisPacketLocation = null,
    previous_pcm_end: ?i64 = null,

    fn consume(
        self: *VorbisSeekIndexer,
        page: Page,
    ) !void {
        if (page.beginning) {
            self.logical_stream_index = page.logical_stream_index;
            self.logical_packet_index = 0;
            self.current_packet = null;
            self.first_audio_packet = null;
            self.previous_audio_packet = null;
            self.previous_pcm_end = null;
        } else if (self.logical_stream_index != page.logical_stream_index) {
            return error.InvalidVorbisSeekLogicalStream;
        }

        var completed_on_page: u16 = 0;
        if (!page.continued) {
            self.current_packet = vorbisPacketLocation(
                page,
                self.logical_packet_index,
                completed_on_page,
            );
        } else if (self.current_packet == null) {
            return error.InvalidVorbisSeekContinuation;
        }

        var last_audio_packet: ?VorbisPacketLocation = null;
        var decode_packet: ?VorbisPacketLocation = null;
        for (page.lacing_values) |segment_bytes| {
            if (segment_bytes == 255) continue;
            const completed_packet = self.current_packet orelse
                return error.InvalidVorbisSeekContinuation;
            if (self.logical_packet_index >= 3) {
                if (self.first_audio_packet == null)
                    self.first_audio_packet = completed_packet;
                decode_packet =
                    self.previous_audio_packet orelse completed_packet;
                last_audio_packet = completed_packet;
                self.previous_audio_packet = completed_packet;
            }
            if (self.logical_packet_index == std.math.maxInt(u64))
                return error.OggPacketCountOverflow;
            self.logical_packet_index += 1;
            completed_on_page += 1;
            self.current_packet = vorbisPacketLocation(
                page,
                self.logical_packet_index,
                completed_on_page,
            );
        }

        if (page.lacing_values.len == 0 or
            page.lacing_values[page.lacing_values.len - 1] != 255)
            self.current_packet = null;
        if (page.granule_position == unknown_granule or
            last_audio_packet == null)
            return;
        const pcm_end: i64 = @bitCast(page.granule_position);
        if (self.previous_pcm_end) |previous| {
            if (pcm_end < previous)
                return error.InvalidVorbisSeekGranuleOrder;
        }
        const point = VorbisSeekPoint{
            .pcm_end = pcm_end,
            .decode = if (self.previous_pcm_end == null)
                self.first_audio_packet.?
            else
                decode_packet.?,
            .packet = last_audio_packet.?,
        };
        if (self.destination) |destination| {
            if (self.count >= destination.len)
                return error.VorbisSeekIndexTooSmall;
            destination[self.count] = point;
        }
        self.count += 1;
        self.previous_pcm_end = pcm_end;
    }
};

fn vorbisPacketLocation(
    page: Page,
    logical_packet_index: u64,
    completed_packets_before: u16,
) VorbisPacketLocation {
    return .{
        .byte_offset = page.byte_offset,
        .serial_number = page.serial_number,
        .sequence_number = page.sequence_number,
        .logical_stream_index = page.logical_stream_index,
        .logical_packet_index = logical_packet_index,
        .completed_packets_before = completed_packets_before,
        .continued = page.continued,
    };
}

pub fn requiredVorbisSeekPoints(encoded: []const u8) !usize {
    var pages = PageIterator.initChained(encoded);
    var indexer = VorbisSeekIndexer{ .destination = null };
    while (try pages.next()) |page| try indexer.consume(page);
    return indexer.count;
}

pub fn buildVorbisSeekIndex(
    encoded: []const u8,
    destination: []VorbisSeekPoint,
) ![]const VorbisSeekPoint {
    const required = try requiredVorbisSeekPoints(encoded);
    if (destination.len < required)
        return error.VorbisSeekIndexTooSmall;
    var pages = PageIterator.initChained(encoded);
    var indexer = VorbisSeekIndexer{ .destination = destination };
    while (try pages.next()) |page| try indexer.consume(page);
    if (indexer.count != required)
        return error.VorbisSeekIndexChanged;
    return destination[0..required];
}

pub fn findVorbisSeekPoint(
    points: []const VorbisSeekPoint,
    logical_stream_index: u32,
    target_pcm: i64,
) !VorbisSeekPoint {
    var first: ?VorbisSeekPoint = null;
    var selected: ?VorbisSeekPoint = null;
    var previous_pcm: ?i64 = null;
    var previous_stream: ?u32 = null;
    for (points) |point| {
        const stream = point.packet.logical_stream_index;
        if (point.decode.logical_stream_index != stream)
            return error.InvalidVorbisSeekIndex;
        if (previous_stream) |previous| {
            if (stream < previous or
                (stream == previous and
                    previous_pcm.? > point.pcm_end))
                return error.InvalidVorbisSeekIndex;
        }
        previous_stream = stream;
        previous_pcm = point.pcm_end;
        if (stream != logical_stream_index) continue;
        if (first == null) first = point;
        if (point.pcm_end <= target_pcm) selected = point;
    }
    return selected orelse first orelse
        error.VorbisSeekLogicalStreamNotFound;
}

pub const FilePageReader = struct {
    io: std.Io,
    file: std.Io.File,
    file_size: u64,
    offset: u64 = 0,
    serial_number: ?u32 = null,
    expected_sequence: ?u32 = null,
    packet_continues: bool = false,
    ended: bool = false,
    allow_chaining: bool = false,
    logical_stream_index: u32 = 0,

    pub fn init(io: std.Io, file: std.Io.File) !FilePageReader {
        return .{
            .io = io,
            .file = file,
            .file_size = (try file.stat(io)).size,
        };
    }

    pub fn initChained(
        io: std.Io,
        file: std.Io.File,
    ) !FilePageReader {
        var reader = try init(io, file);
        reader.allow_chaining = true;
        return reader;
    }

    /// Returned page slices borrow storage until the next read.
    pub fn next(
        self: *FilePageReader,
        storage: []u8,
    ) !?Page {
        if (self.offset > self.file_size)
            return error.InvalidOggFileReaderState;
        if (self.offset == self.file_size) {
            if (self.packet_continues) return error.TruncatedOggPacket;
            return null;
        }
        const remaining = self.file_size - self.offset;
        if (remaining < 27) return error.TruncatedOggPage;
        if (storage.len < 27) return error.OggPageBufferTooSmall;
        try readExactAt(self.io, self.file, self.offset, storage[0..27]);
        const segment_count: usize = storage[26];
        const header_bytes = 27 + segment_count;
        if (storage.len < header_bytes)
            return error.OggPageBufferTooSmall;
        try readExactAt(
            self.io,
            self.file,
            self.offset + 27,
            storage[27..header_bytes],
        );
        var body_bytes: usize = 0;
        for (storage[27..header_bytes]) |value| body_bytes += value;
        const page_bytes = header_bytes + body_bytes;
        if (storage.len < page_bytes)
            return error.OggPageBufferTooSmall;
        if (page_bytes > remaining)
            return error.TruncatedOggPage;
        try readExactAt(
            self.io,
            self.file,
            self.offset + header_bytes,
            storage[header_bytes..page_bytes],
        );
        var parser = PageIterator{
            .encoded = storage[0..page_bytes],
            .serial_number = self.serial_number,
            .expected_sequence = self.expected_sequence,
            .packet_continues = self.packet_continues,
            .ended = self.ended,
            .allow_chaining = self.allow_chaining,
            .logical_stream_index = self.logical_stream_index,
        };
        var page = (try parser.next()).?;
        page.byte_offset = self.offset;
        self.serial_number = parser.serial_number;
        self.expected_sequence = parser.expected_sequence;
        self.packet_continues = parser.packet_continues;
        self.ended = parser.ended;
        self.logical_stream_index = parser.logical_stream_index;
        self.offset += page_bytes;
        return page;
    }

    /// Advances past at most `maximum_skip_bytes` to a continuous valid page.
    pub fn resynchronize(
        self: *FilePageReader,
        storage: []u8,
        maximum_skip_bytes: u64,
    ) !u64 {
        if (self.offset > self.file_size)
            return error.InvalidOggFileReaderState;
        if (storage.len < maximum_page_bytes)
            return error.OggPageBufferTooSmall;
        if (maximum_skip_bytes == 0)
            return error.InvalidOggResynchronizationLimit;
        if (self.offset >= self.file_size -| 27)
            return error.OggResynchronizationLimitReached;
        const first_candidate = std.math.add(
            u64,
            self.offset,
            1,
        ) catch return error.OggByteCountOverflow;
        const last_candidate = @min(
            self.file_size - 27,
            std.math.add(
                u64,
                self.offset,
                maximum_skip_bytes,
            ) catch self.file_size - 27,
        );
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            try readExactAt(
                self.io,
                self.file,
                candidate,
                storage[0..27],
            );
            if (!std.mem.eql(u8, storage[0..4], "OggS"))
                continue;
            if (storage[4] != 0 or storage[5] & 0xf8 != 0)
                continue;
            const segment_count: usize = storage[26];
            const header_bytes = 27 + segment_count;
            if (@as(u64, @intCast(header_bytes)) >
                self.file_size - candidate)
                continue;
            try readExactAt(
                self.io,
                self.file,
                candidate + 27,
                storage[27..header_bytes],
            );
            var body_bytes: usize = 0;
            for (storage[27..header_bytes]) |value|
                body_bytes += value;
            const page_bytes = header_bytes + body_bytes;
            if (page_bytes > self.file_size - candidate)
                continue;
            try readExactAt(
                self.io,
                self.file,
                candidate + header_bytes,
                storage[header_bytes..page_bytes],
            );
            var parser = PageIterator{
                .encoded = storage[0..page_bytes],
                .serial_number = self.serial_number,
                .expected_sequence = self.expected_sequence,
                .packet_continues = self.packet_continues,
                .ended = self.ended,
                .allow_chaining = self.allow_chaining,
                .logical_stream_index = self.logical_stream_index,
            };
            _ = parser.next() catch continue;
            const skipped = candidate - self.offset;
            self.offset = candidate;
            return skipped;
        }
        return error.OggResynchronizationLimitReached;
    }
};

pub fn requiredVorbisFileSeekPoints(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
) !usize {
    var pages = try FilePageReader.initChained(io, file);
    var indexer = VorbisSeekIndexer{ .destination = null };
    while (try pages.next(page_storage)) |page| {
        try indexer.consume(page);
    }
    return indexer.count;
}

pub fn buildVorbisFileSeekIndex(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    destination: []VorbisSeekPoint,
) ![]const VorbisSeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(VorbisSeekPoint),
    ) catch return error.VorbisSeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(page_storage.ptr),
        page_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    )) return error.OverlappingVorbisSeekStorage;
    const required = try requiredVorbisFileSeekPoints(
        io,
        file,
        page_storage,
    );
    if (destination.len < required)
        return error.VorbisSeekIndexTooSmall;
    var pages = try FilePageReader.initChained(io, file);
    var indexer = VorbisSeekIndexer{ .destination = destination };
    while (try pages.next(page_storage)) |page| {
        try indexer.consume(page);
    }
    if (indexer.count != required)
        return error.VorbisSeekIndexChanged;
    return destination[0..required];
}

pub const FilePacketReader = struct {
    pages: FilePageReader,
    page: ?Page = null,
    segment_index: usize = 0,
    body_offset: usize = 0,
    reload_segment_index: usize = 0,
    reload_body_offset: usize = 0,
    preserve_logical_index_on_reload: bool = false,
    packet_bytes: usize = 0,
    packet_index: u64 = 0,
    logical_stream_packet_index: u64 = 0,
    packets_to_skip: u16 = 0,
    page_storage_pointer: ?[*]u8 = null,
    packet_storage_pointer: ?[*]u8 = null,
    page_storage_length: usize = 0,
    packet_storage_length: usize = 0,

    pub fn init(io: std.Io, file: std.Io.File) !FilePacketReader {
        return .{ .pages = try FilePageReader.init(io, file) };
    }

    pub fn initChained(
        io: std.Io,
        file: std.Io.File,
    ) !FilePacketReader {
        return .{ .pages = try FilePageReader.initChained(io, file) };
    }

    /// Reposition to the preceding audio packet retained by a seek point.
    pub fn seek(
        self: *FilePacketReader,
        point: VorbisSeekPoint,
    ) !void {
        const location = point.decode;
        if (location.byte_offset > self.pages.file_size -| 27 or
            location.logical_packet_index <
                location.completed_packets_before)
            return error.InvalidVorbisSeekPoint;
        var header: [27]u8 = undefined;
        try readExactAt(
            self.pages.io,
            self.pages.file,
            location.byte_offset,
            &header,
        );
        if (!std.mem.eql(u8, header[0..4], "OggS") or
            header[4] != 0 or header[5] & 0xf8 != 0 or
            std.mem.readInt(u32, header[14..18], .little) !=
                location.serial_number or
            std.mem.readInt(u32, header[18..22], .little) !=
                location.sequence_number or
            (header[5] & 0x01 != 0) != location.continued)
            return error.InvalidVorbisSeekPoint;

        self.pages.offset = location.byte_offset;
        self.pages.serial_number = location.serial_number;
        self.pages.expected_sequence = location.sequence_number;
        self.pages.packet_continues = location.continued;
        self.pages.ended = false;
        self.pages.logical_stream_index =
            location.logical_stream_index;
        self.page = null;
        self.segment_index = 0;
        self.body_offset = 0;
        self.reload_segment_index = 0;
        self.reload_body_offset = 0;
        self.preserve_logical_index_on_reload = false;
        self.packet_bytes = 0;
        self.packet_index = 0;
        self.logical_stream_packet_index =
            location.logical_packet_index -
            location.completed_packets_before;
        self.packets_to_skip = location.completed_packets_before;
    }

    /// Both storage buffers must retain their address until iteration ends.
    pub fn next(
        self: *FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) !?Packet {
        var trial = self.*;
        const packet = trial.nextInPlace(
            page_storage,
            packet_storage,
        ) catch |err| {
            if (err == error.OggPacketBufferTooSmall)
                self.* = trial;
            return err;
        };
        self.* = trial;
        return packet;
    }

    fn nextInPlace(
        self: *FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) !?Packet {
        try self.validateState(page_storage, packet_storage);
        const checkpoint: ?FilePacketCheckpoint =
            if (self.packet_bytes == 0)
                self.packetCheckpoint()
            else
                null;
        if (self.page_storage_pointer) |pointer| {
            if (pointer != page_storage.ptr or
                self.packet_storage_pointer.? != packet_storage.ptr or
                self.page_storage_length != page_storage.len or
                self.packet_storage_length != packet_storage.len)
                return error.OggReaderStorageChanged;
        } else {
            self.page_storage_pointer = page_storage.ptr;
            self.packet_storage_pointer = packet_storage.ptr;
            self.page_storage_length = page_storage.len;
            self.packet_storage_length = packet_storage.len;
        }
        while (true) {
            if (self.page == null or
                self.segment_index == self.page.?.lacing_values.len)
            {
                self.page = try self.pages.next(page_storage) orelse {
                    if (self.packet_bytes != 0)
                        return error.TruncatedOggPacket;
                    return null;
                };
                self.segment_index = self.reload_segment_index;
                self.body_offset = self.reload_body_offset;
                const preserve_logical_index =
                    self.preserve_logical_index_on_reload;
                self.reload_segment_index = 0;
                self.reload_body_offset = 0;
                self.preserve_logical_index_on_reload = false;
                try validatePacketPageCursor(
                    self.page.?,
                    self.segment_index,
                    self.body_offset,
                );
                if (self.page.?.beginning and
                    !preserve_logical_index)
                    self.logical_stream_packet_index = 0;
            }
            const page = self.page.?;
            if (page.lacing_values.len == 0) {
                self.page = null;
                continue;
            }
            const segment_bytes: usize =
                page.lacing_values[self.segment_index];
            if (segment_bytes > packet_storage.len -| self.packet_bytes) {
                if (checkpoint) |packet_checkpoint|
                    self.restorePacketCheckpoint(packet_checkpoint);
                return error.OggPacketBufferTooSmall;
            }
            @memcpy(
                packet_storage[self.packet_bytes..][0..segment_bytes],
                page.body[self.body_offset..][0..segment_bytes],
            );
            self.packet_bytes += segment_bytes;
            self.body_offset += segment_bytes;
            self.segment_index += 1;
            if (segment_bytes == 255) continue;
            var later_packet_ends = false;
            for (page.lacing_values[self.segment_index..]) |value| {
                if (value < 255) {
                    later_packet_ends = true;
                    break;
                }
            }
            const packet = Packet{
                .bytes = packet_storage[0..self.packet_bytes],
                .granule_position = if (later_packet_ends)
                    unknown_granule
                else
                    page.granule_position,
                .beginning = self.logical_stream_packet_index == 0,
                .end = page.end and
                    self.segment_index == page.lacing_values.len,
                .logical_stream_index = page.logical_stream_index,
            };
            self.packet_bytes = 0;
            self.packet_index += 1;
            self.logical_stream_packet_index += 1;
            if (self.packets_to_skip != 0) {
                self.packets_to_skip -= 1;
                continue;
            }
            return packet;
        }
    }

    /// Recover only after a complete packet exhausts its page.
    pub fn resynchronize(
        self: *FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
        maximum_skip_bytes: u64,
    ) !u64 {
        try self.validateState(page_storage, packet_storage);
        if (self.page_storage_pointer) |page_pointer| {
            if (page_pointer != page_storage.ptr or
                self.packet_storage_pointer.? !=
                    packet_storage.ptr or
                self.page_storage_length != page_storage.len or
                self.packet_storage_length != packet_storage.len)
            {
                return error.OggReaderStorageChanged;
            }
        }
        const at_page_boundary = if (self.page) |page|
            self.segment_index == page.lacing_values.len
        else
            true;
        if (self.packet_bytes != 0 or
            self.reload_segment_index != 0 or
            self.reload_body_offset != 0 or
            self.preserve_logical_index_on_reload or
            !at_page_boundary)
        {
            return error.OggPacketResynchronizationRequiresPageBoundary;
        }
        var pages = self.pages;
        const skipped = try pages.resynchronize(
            page_storage,
            maximum_skip_bytes,
        );
        self.pages = pages;
        self.page = null;
        self.segment_index = 0;
        self.body_offset = 0;
        return skipped;
    }

    fn packetCheckpoint(
        self: *const FilePacketReader,
    ) FilePacketCheckpoint {
        const page = self.page orelse return .{
            .pages = self.pages,
            .packet_index = self.packet_index,
            .logical_stream_packet_index = self.logical_stream_packet_index,
            .packets_to_skip = self.packets_to_skip,
        };
        if (self.segment_index == page.lacing_values.len) return .{
            .pages = self.pages,
            .packet_index = self.packet_index,
            .logical_stream_packet_index = self.logical_stream_packet_index,
            .packets_to_skip = self.packets_to_skip,
        };

        var pages = self.pages;
        pages.offset = page.byte_offset;
        pages.ended = false;
        pages.logical_stream_index = page.logical_stream_index;
        if (page.beginning) {
            pages.serial_number = null;
            pages.expected_sequence = null;
            pages.packet_continues = false;
            if (page.logical_stream_index != 0) {
                pages.ended = true;
                pages.logical_stream_index -= 1;
            }
        } else {
            pages.serial_number = page.serial_number;
            pages.expected_sequence = page.sequence_number;
            pages.packet_continues = page.continued;
        }
        return .{
            .pages = pages,
            .reload_segment_index = self.segment_index,
            .reload_body_offset = self.body_offset,
            .preserve_logical_index_on_reload = page.beginning and self.segment_index != 0,
            .packet_index = self.packet_index,
            .logical_stream_packet_index = self.logical_stream_packet_index,
            .packets_to_skip = self.packets_to_skip,
        };
    }

    fn restorePacketCheckpoint(
        self: *FilePacketReader,
        checkpoint: FilePacketCheckpoint,
    ) void {
        self.pages = checkpoint.pages;
        self.page = null;
        self.segment_index = 0;
        self.body_offset = 0;
        self.reload_segment_index = checkpoint.reload_segment_index;
        self.reload_body_offset = checkpoint.reload_body_offset;
        self.preserve_logical_index_on_reload =
            checkpoint.preserve_logical_index_on_reload;
        self.packet_bytes = 0;
        self.packet_index = checkpoint.packet_index;
        self.logical_stream_packet_index =
            checkpoint.logical_stream_packet_index;
        self.packets_to_skip = checkpoint.packets_to_skip;
        self.page_storage_pointer = null;
        self.packet_storage_pointer = null;
        self.page_storage_length = 0;
        self.packet_storage_length = 0;
    }

    fn validateState(
        self: *const FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) !void {
        if ((self.page_storage_pointer == null) !=
            (self.packet_storage_pointer == null) or
            self.packet_bytes > packet_storage.len or
            self.packet_index == std.math.maxInt(u64) or
            self.logical_stream_packet_index ==
                std.math.maxInt(u64))
            return error.InvalidOggFilePacketReaderState;
        if (self.page_storage_pointer == null and
            (self.page_storage_length != 0 or
                self.packet_storage_length != 0))
            return error.InvalidOggFilePacketReaderState;
        const page = self.page orelse {
            if (self.segment_index != 0 or self.body_offset != 0)
                return error.InvalidOggFilePacketReaderState;
            if (self.reload_segment_index >
                maximum_page_segments or
                self.reload_body_offset >
                    maximum_page_body_bytes or
                (self.reload_segment_index == 0 and
                    self.reload_body_offset != 0))
                return error.InvalidOggFilePacketReaderState;
            if (self.preserve_logical_index_on_reload and
                self.reload_segment_index == 0)
                return error.InvalidOggFilePacketReaderState;
            return;
        };
        if (self.reload_segment_index != 0 or
            self.reload_body_offset != 0 or
            self.preserve_logical_index_on_reload or
            page_storage.len < page.byte_length)
            return error.InvalidOggFilePacketReaderState;
        try validatePacketPageCursor(
            page,
            self.segment_index,
            self.body_offset,
        );
    }
};

const FilePacketCheckpoint = struct {
    pages: FilePageReader,
    reload_segment_index: usize = 0,
    reload_body_offset: usize = 0,
    preserve_logical_index_on_reload: bool = false,
    packet_index: u64,
    logical_stream_packet_index: u64,
    packets_to_skip: u16,
};

fn validatePacketPageCursor(
    page: Page,
    segment_index: usize,
    body_offset: usize,
) !void {
    if (segment_index > page.lacing_values.len or
        body_offset > page.body.len)
        return error.InvalidOggFilePacketReaderState;
    var consumed: usize = 0;
    for (page.lacing_values[0..segment_index]) |value|
        consumed += value;
    var total = consumed;
    for (page.lacing_values[segment_index..]) |value|
        total += value;
    if (consumed != body_offset or total != page.body.len)
        return error.InvalidOggFilePacketReaderState;
}

const PacketLayout = struct {
    segment_count: usize,
    page_count: usize,
    encoded_bytes: usize,
};

fn packetLayout(packet_bytes: usize) !PacketLayout {
    const segment_count = std.math.add(
        usize,
        packet_bytes / 255,
        1,
    ) catch return error.OggSizeOverflow;
    const page_count = std.math.add(
        usize,
        segment_count,
        254,
    ) catch return error.OggSizeOverflow;
    const rounded_page_count = page_count / 255;
    const framing_bytes = std.math.add(
        usize,
        std.math.mul(
            usize,
            27,
            rounded_page_count,
        ) catch return error.OggSizeOverflow,
        segment_count,
    ) catch return error.OggSizeOverflow;
    const encoded_bytes = std.math.add(
        usize,
        packet_bytes,
        framing_bytes,
    ) catch return error.OggSizeOverflow;
    return .{
        .segment_count = segment_count,
        .page_count = rounded_page_count,
        .encoded_bytes = encoded_bytes,
    };
}

pub const StreamWriter = struct {
    destination: []u8,
    serial_number: u32,
    sequence_number: u32 = 0,
    byte_count: usize = 0,
    began: bool = false,
    ended: bool = false,

    pub fn init(destination: []u8, serial_number: u32) StreamWriter {
        return .{
            .destination = destination,
            .serial_number = serial_number,
        };
    }

    pub fn appendPacket(
        self: *StreamWriter,
        packet: []const u8,
        granule_position: u64,
        beginning: bool,
        end: bool,
    ) !void {
        if (self.ended) return error.OggStreamAlreadyEnded;
        if (beginning != !self.began)
            return error.InvalidOggBeginningOfStream;
        const layout = try packetLayout(packet.len);
        if (layout.encoded_bytes >
            self.destination.len -| self.byte_count)
            return error.OggOutputTooSmall;

        var packet_offset: usize = 0;
        var segment_offset: usize = 0;
        for (0..layout.page_count) |page_index| {
            const page_segments: usize =
                @min(255, layout.segment_count - segment_offset);
            const page_start = self.byte_count;
            var lacing_values: [maximum_page_segments]u8 = undefined;
            var body_bytes: usize = 0;
            for (0..page_segments) |index| {
                const global_segment = segment_offset + index;
                const remaining = packet.len - packet_offset - body_bytes;
                const value: u8 =
                    if (global_segment + 1 == layout.segment_count)
                        @intCast(remaining)
                    else
                        255;
                lacing_values[index] = value;
                body_bytes += value;
            }
            const final_page = page_index + 1 == layout.page_count;
            const flags =
                (if (page_index != 0) @as(u8, 0x01) else 0) |
                (if (beginning and page_index == 0) @as(u8, 0x02) else 0) |
                (if (end and final_page) @as(u8, 0x04) else 0);
            const page_bytes = try encodePage(
                self.destination[page_start..],
                self.serial_number,
                self.sequence_number,
                flags,
                if (final_page) granule_position else unknown_granule,
                lacing_values[0..page_segments],
                packet[packet_offset..][0..body_bytes],
            );
            self.sequence_number +%= 1;
            self.byte_count += page_bytes;
            packet_offset += body_bytes;
            segment_offset += page_segments;
        }
        self.began = true;
        self.ended = end;
    }

    pub fn bytes(self: *const StreamWriter) []const u8 {
        return self.destination[0..self.byte_count];
    }
};

pub const FileWriter = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    page_storage: []u8,
    serial_number: u32,
    sequence_number: u32 = 0,
    byte_count: u64 = 0,
    began: bool = false,
    ended: bool = false,
    failed: bool = false,

    /// The caller owns the file and page storage for the writer lifetime.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        page_storage: []u8,
        serial_number: u32,
    ) !FileWriter {
        return initWithOperations(
            io,
            file,
            page_storage,
            serial_number,
            .{},
        );
    }

    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        page_storage: []u8,
        serial_number: u32,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        if (page_storage.len < maximum_page_bytes)
            return error.OggPageBufferTooSmall;
        try operations.setLength(io, file, 0);
        return .{
            .io = io,
            .file = file,
            .operations = operations,
            .page_storage = page_storage,
            .serial_number = serial_number,
        };
    }

    pub fn appendPacket(
        self: *FileWriter,
        packet: []const u8,
        granule_position: u64,
        beginning: bool,
        end: bool,
    ) !void {
        if (!self.valid()) return error.InvalidOggFileWriterState;
        if (self.ended) return error.OggStreamAlreadyEnded;
        if (beginning != !self.began)
            return error.InvalidOggBeginningOfStream;
        if (packet.len != 0 and byteRangesOverlap(
            @intFromPtr(self.page_storage.ptr),
            self.page_storage.len,
            @intFromPtr(packet.ptr),
            packet.len,
        )) return error.OverlappingOggWriterStorage;
        const layout = try packetLayout(packet.len);
        const next_byte_count = std.math.add(
            u64,
            self.byte_count,
            @intCast(layout.encoded_bytes),
        ) catch return error.OggSizeOverflow;
        const checkpoint =
            file_writer_io.Checkpoint.exact(self.byte_count);

        var packet_offset: usize = 0;
        var segment_offset: usize = 0;
        var written_bytes: u64 = 0;
        var next_sequence = self.sequence_number;
        for (0..layout.page_count) |page_index| {
            const page_segments: usize =
                @min(255, layout.segment_count - segment_offset);
            var lacing_values: [maximum_page_segments]u8 = undefined;
            var body_bytes: usize = 0;
            for (0..page_segments) |index| {
                const global_segment = segment_offset + index;
                const remaining =
                    packet.len - packet_offset - body_bytes;
                const value: u8 =
                    if (global_segment + 1 == layout.segment_count)
                        @intCast(remaining)
                    else
                        255;
                lacing_values[index] = value;
                body_bytes += value;
            }
            const final_page = page_index + 1 == layout.page_count;
            const flags =
                (if (page_index != 0) @as(u8, 0x01) else 0) |
                (if (beginning and page_index == 0) @as(u8, 0x02) else 0) |
                (if (end and final_page) @as(u8, 0x04) else 0);
            const page_bytes = try encodePage(
                self.page_storage,
                self.serial_number,
                next_sequence,
                flags,
                if (final_page) granule_position else unknown_granule,
                lacing_values[0..page_segments],
                packet[packet_offset..][0..body_bytes],
            );
            self.operations.writeAt(
                self.io,
                self.file,
                self.byte_count + written_bytes,
                self.page_storage[0..page_bytes],
            ) catch |err| {
                checkpoint.restore(
                    self.operations,
                    self.io,
                    self.file,
                ) catch {
                    self.failed = true;
                };
                return err;
            };
            written_bytes += page_bytes;
            next_sequence +%= 1;
            packet_offset += body_bytes;
            segment_offset += page_segments;
        }
        if (written_bytes != layout.encoded_bytes) {
            checkpoint.restore(
                self.operations,
                self.io,
                self.file,
            ) catch {
                self.failed = true;
            };
            return error.OggEncodedSizeMismatch;
        }
        self.sequence_number = next_sequence;
        self.byte_count = next_byte_count;
        self.began = true;
        self.ended = end;
    }

    pub fn finalize(self: *FileWriter) !void {
        if (!self.ended) return error.OggStreamNotEnded;
        try self.recover();
        try self.file.sync(self.io);
    }

    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable())
            return error.InvalidOggFileWriterState;
        file_writer_io.Checkpoint.exact(self.byte_count).restore(
            self.operations,
            self.io,
            self.file,
        ) catch |err| {
            self.failed = true;
            return err;
        };
        self.failed = false;
    }

    pub fn valid(self: *const FileWriter) bool {
        return !self.failed and self.recoverable();
    }

    pub fn recoverable(self: *const FileWriter) bool {
        if (self.page_storage.len < maximum_page_bytes)
            return false;
        if (self.ended and !self.began) return false;
        if (!self.began)
            return self.sequence_number == 0 and
                self.byte_count == 0;
        return self.byte_count >= 28;
    }
};

pub const VorbisIdentification = struct {
    channel_count: u8,
    sample_rate: u32,
    bitrate_maximum: i32,
    bitrate_nominal: i32,
    bitrate_minimum: i32,
    small_block_size: u16,
    large_block_size: u16,

    pub fn parse(packet: []const u8) !VorbisIdentification {
        if (packet.len != 30 or packet[0] != 1 or
            !std.mem.eql(u8, packet[1..7], "vorbis"))
            return error.InvalidVorbisIdentificationHeader;
        if (std.mem.readInt(u32, packet[7..11], .little) != 0)
            return error.UnsupportedVorbisVersion;
        const channels = packet[11];
        const sample_rate =
            std.mem.readInt(u32, packet[12..16], .little);
        const blocks = packet[28];
        const small_exponent = blocks & 0x0f;
        const large_exponent = blocks >> 4;
        if (channels == 0 or sample_rate == 0 or
            small_exponent < 6 or large_exponent > 13 or
            small_exponent > large_exponent or packet[29] != 1)
            return error.InvalidVorbisIdentificationHeader;
        return .{
            .channel_count = channels,
            .sample_rate = sample_rate,
            .bitrate_maximum = std.mem.readInt(i32, packet[16..20], .little),
            .bitrate_nominal = std.mem.readInt(i32, packet[20..24], .little),
            .bitrate_minimum = std.mem.readInt(i32, packet[24..28], .little),
            .small_block_size = @as(u16, 1) << @intCast(small_exponent),
            .large_block_size = @as(u16, 1) << @intCast(large_exponent),
        };
    }
};

pub fn encodeVorbisIdentificationPacket(
    destination: []u8,
    identification: VorbisIdentification,
) ![]const u8 {
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        !validVorbisBitrate(identification.bitrate_maximum) or
        !validVorbisBitrate(identification.bitrate_nominal) or
        !validVorbisBitrate(identification.bitrate_minimum) or
        !validVorbisBlockSize(identification.small_block_size) or
        !validVorbisBlockSize(identification.large_block_size) or
        identification.small_block_size >
            identification.large_block_size)
        return error.InvalidVorbisIdentification;
    if (identification.bitrate_minimum > 0 and
        identification.bitrate_maximum > 0 and
        identification.bitrate_minimum >
            identification.bitrate_maximum)
        return error.InvalidVorbisIdentification;
    if (destination.len < 30)
        return error.VorbisIdentificationOutputTooSmall;

    var packet: [30]u8 = @splat(0);
    packet[0] = 1;
    @memcpy(packet[1..7], "vorbis");
    packet[11] = identification.channel_count;
    std.mem.writeInt(
        u32,
        packet[12..16],
        identification.sample_rate,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[16..20],
        identification.bitrate_maximum,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[20..24],
        identification.bitrate_nominal,
        .little,
    );
    std.mem.writeInt(
        i32,
        packet[24..28],
        identification.bitrate_minimum,
        .little,
    );
    packet[28] =
        vorbisBlockExponent(identification.small_block_size) |
        (vorbisBlockExponent(identification.large_block_size) << 4);
    packet[29] = 1;
    @memcpy(destination[0..30], &packet);
    return destination[0..30];
}

pub const VorbisComment = struct {
    name: []const u8,
    value: []const u8,
};

pub fn requiredVorbisCommentPacketBytes(
    vendor: []const u8,
    comments: []const VorbisComment,
) !usize {
    try validateVorbisCommentText(vendor);
    if (vendor.len > std.math.maxInt(u32) or
        comments.len > std.math.maxInt(u32))
        return error.VorbisCommentSizeOverflow;
    var required: usize = 16;
    required = std.math.add(
        usize,
        required,
        vendor.len,
    ) catch return error.VorbisCommentSizeOverflow;
    for (comments) |comment| {
        try validateVorbisCommentName(comment.name);
        try validateVorbisCommentText(comment.value);
        const field_bytes = std.math.add(
            usize,
            comment.name.len,
            1,
        ) catch return error.VorbisCommentSizeOverflow;
        const complete_field_bytes = std.math.add(
            usize,
            field_bytes,
            comment.value.len,
        ) catch return error.VorbisCommentSizeOverflow;
        if (complete_field_bytes > std.math.maxInt(u32))
            return error.VorbisCommentSizeOverflow;
        required = std.math.add(
            usize,
            required,
            4,
        ) catch return error.VorbisCommentSizeOverflow;
        required = std.math.add(
            usize,
            required,
            complete_field_bytes,
        ) catch return error.VorbisCommentSizeOverflow;
    }
    return required;
}

pub fn encodeVorbisCommentPacket(
    destination: []u8,
    vendor: []const u8,
    comments: []const VorbisComment,
) ![]const u8 {
    const required = try requiredVorbisCommentPacketBytes(
        vendor,
        comments,
    );
    if (destination.len < required)
        return error.VorbisCommentOutputTooSmall;
    if (byteRangesOverlap(
        @intFromPtr(destination.ptr),
        required,
        @intFromPtr(vendor.ptr),
        vendor.len,
    )) return error.OverlappingVorbisCommentStorage;
    for (comments) |comment| {
        if (byteRangesOverlap(
            @intFromPtr(destination.ptr),
            required,
            @intFromPtr(comment.name.ptr),
            comment.name.len,
        ) or byteRangesOverlap(
            @intFromPtr(destination.ptr),
            required,
            @intFromPtr(comment.value.ptr),
            comment.value.len,
        )) return error.OverlappingVorbisCommentStorage;
    }

    destination[0] = 3;
    @memcpy(destination[1..7], "vorbis");
    std.mem.writeInt(
        u32,
        destination[7..11],
        @intCast(vendor.len),
        .little,
    );
    var offset: usize = 11;
    @memcpy(destination[offset..][0..vendor.len], vendor);
    offset += vendor.len;
    std.mem.writeInt(
        u32,
        destination[offset..][0..4],
        @intCast(comments.len),
        .little,
    );
    offset += 4;
    for (comments) |comment| {
        const field_bytes =
            comment.name.len + 1 + comment.value.len;
        std.mem.writeInt(
            u32,
            destination[offset..][0..4],
            @intCast(field_bytes),
            .little,
        );
        offset += 4;
        @memcpy(
            destination[offset..][0..comment.name.len],
            comment.name,
        );
        offset += comment.name.len;
        destination[offset] = '=';
        offset += 1;
        @memcpy(
            destination[offset..][0..comment.value.len],
            comment.value,
        );
        offset += comment.value.len;
    }
    destination[offset] = 1;
    offset += 1;
    std.debug.assert(offset == required);
    return destination[0..required];
}

pub const VorbisCommentIterator = struct {
    packet: []const u8,
    vendor: []const u8,
    offset: usize,
    remaining: u32,

    pub fn init(packet: []const u8) !VorbisCommentIterator {
        if (packet.len < 16 or packet[0] != 3 or
            !std.mem.eql(u8, packet[1..7], "vorbis"))
            return error.InvalidVorbisCommentHeader;
        const vendor_bytes =
            std.mem.readInt(u32, packet[7..11], .little);
        if (vendor_bytes > packet.len - 16)
            return error.InvalidVorbisCommentHeader;
        const vendor_end = 11 + @as(usize, vendor_bytes);
        const vendor = packet[11..vendor_end];
        try validateVorbisCommentText(vendor);
        const result = VorbisCommentIterator{
            .packet = packet,
            .vendor = vendor,
            .offset = vendor_end + 4,
            .remaining = std.mem.readInt(
                u32,
                packet[vendor_end..][0..4],
                .little,
            ),
        };
        var validation = result;
        while (try validation.next()) |_| {}
        return result;
    }

    pub fn next(self: *VorbisCommentIterator) !?VorbisComment {
        if (self.remaining == 0) {
            if (self.offset + 1 != self.packet.len or
                self.packet[self.offset] != 1)
                return error.InvalidVorbisCommentHeader;
            return null;
        }
        if (self.packet.len - self.offset < 5)
            return error.InvalidVorbisCommentHeader;
        const field_bytes =
            std.mem.readInt(u32, self.packet[self.offset..][0..4], .little);
        self.offset += 4;
        if (field_bytes > self.packet.len - self.offset -| 1)
            return error.InvalidVorbisCommentHeader;
        const field = self.packet[self.offset..][0..field_bytes];
        self.offset += field_bytes;
        self.remaining -= 1;
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse
            return error.InvalidVorbisCommentField;
        const name = field[0..separator];
        try validateVorbisCommentName(name);
        const value = field[separator + 1 ..];
        try validateVorbisCommentText(value);
        return .{ .name = name, .value = value };
    }
};

fn validVorbisBitrate(bitrate: i32) bool {
    return bitrate >= -1;
}

fn validVorbisBlockSize(block_size: u16) bool {
    return block_size >= 64 and
        block_size <= 8_192 and
        std.math.isPowerOfTwo(block_size);
}

fn vorbisBlockExponent(block_size: u16) u8 {
    std.debug.assert(validVorbisBlockSize(block_size));
    return @intCast(@ctz(block_size));
}

fn validateVorbisCommentName(name: []const u8) !void {
    if (name.len == 0)
        return error.InvalidVorbisCommentField;
    for (name) |byte| {
        if (byte < 0x20 or byte > 0x7d or byte == '=')
            return error.InvalidVorbisCommentField;
    }
}

fn validateVorbisCommentText(text: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(text))
        return error.InvalidVorbisCommentUtf8;
}

pub const VorbisHeaders = struct {
    identification: VorbisIdentification,
    comments: VorbisCommentIterator,
    setup: VorbisSetupSummary,

    pub fn parse(
        identification_packet: []const u8,
        comment_packet: []const u8,
        setup_packet: []const u8,
    ) !VorbisHeaders {
        const identification =
            try VorbisIdentification.parse(identification_packet);
        const comments = try VorbisCommentIterator.init(comment_packet);
        const setup = try validateVorbisSetup(
            setup_packet,
            identification.channel_count,
        );
        return .{
            .identification = identification,
            .comments = comments,
            .setup = setup,
        };
    }
};

pub const VorbisCodebook = struct {
    dimensions: u16,
    entries: u32,
    entry_offset: u64,
    active_entry_count: u32,
    tree_node_offset: u64 = 0,
    tree_node_count: u32 = 0,
    lookup_type: u2,
    minimum_value: f64 = 0,
    delta_value: f64 = 0,
    sequence: bool = false,
    multiplicand_offset: u64 = 0,
    multiplicand_count: u64 = 0,
};

pub const VorbisCodebookEntry = struct {
    codeword: u32,
    length: u8,
};

pub const VorbisHuffmanNode = struct {
    branches: [2]u32,
};

pub const VorbisFloorZero = struct {
    order: u8,
    rate: u16,
    bark_map_size: u16,
    amplitude_bits: u6,
    amplitude_offset: u8,
    book_count: u5,
    books: [16]u8,
};

pub const VorbisFloorOneClass = struct {
    dimensions: u4,
    subclass_bits: u2,
    masterbook: i16,
    subclass_books: [8]i16,
};

pub const VorbisFloorOne = struct {
    partition_count: u5,
    partition_classes: [31]u4,
    class_count: u5,
    classes: [16]VorbisFloorOneClass,
    multiplier: u3,
    range_bits: u4,
    point_count: u7,
    x_list: [65]u16,
};

pub const VorbisFloor = union(enum) {
    zero: VorbisFloorZero,
    one: VorbisFloorOne,
};

pub const VorbisResidueKind = enum(u2) {
    zero,
    one,
    two,
};

pub const VorbisResidue = struct {
    kind: VorbisResidueKind,
    begin: u24,
    end: u24,
    partition_size: u25,
    classification_count: u7,
    classbook: u8,
    cascades: [64]u8,
    books: [64][8]i16,
};

pub const VorbisCouplingStep = struct {
    magnitude: u8,
    angle: u8,
};

pub const VorbisSubmap = struct {
    floor: u8,
    residue: u8,
};

pub const VorbisMapping = struct {
    submap_count: u5,
    coupling_step_count: u9,
    coupling_steps: [256]VorbisCouplingStep,
    channel_mux: [255]u4,
    submaps: [16]VorbisSubmap,
};

pub const VorbisSetupSummary = struct {
    codebook_count: u16,
    codebook_entry_count: u64,
    huffman_node_count: u64 = 0,
    codebook_multiplicand_count: u64 = 0,
    time_count: u8,
    floor_count: u8,
    residue_count: u8,
    mapping_count: u8,
    mode_count: u8,
    maximum_codebook_dimensions: u16,
    maximum_codebook_entries: u32,
};

pub const VorbisSetup = struct {
    summary: VorbisSetupSummary,
    codebooks: []const VorbisCodebook,
    codebook_entries: []const VorbisCodebookEntry,
    huffman_nodes: []const VorbisHuffmanNode,
    codebook_multiplicands: []const u32,
    floors: []const VorbisFloor,
    residues: []const VorbisResidue,
    mappings: []const VorbisMapping,
    modes: []const VorbisMode,
};

pub const VorbisMode = struct {
    large_block: bool,
    mapping: u8,
};

pub const VorbisSetupStorage = struct {
    codebooks: []VorbisCodebook,
    codebook_entries: []VorbisCodebookEntry,
    huffman_nodes: []VorbisHuffmanNode,
    codebook_multiplicands: []u32,
    floors: []VorbisFloor,
    residues: []VorbisResidue,
    mappings: []VorbisMapping,
    modes: []VorbisMode,
};

/// Validate first to obtain exact entry, Huffman node, and multiplicand counts.
/// Returned slices borrow `storage`.
pub fn parseVorbisSetup(
    packet: []const u8,
    channel_count: u8,
    storage: VorbisSetupStorage,
) !VorbisSetup {
    const summary = try parseVorbisSetupInternal(packet, channel_count, null);
    if (storage.codebooks.len < summary.codebook_count or
        summary.codebook_entry_count > std.math.maxInt(usize) or
        storage.codebook_entries.len < summary.codebook_entry_count or
        summary.huffman_node_count > std.math.maxInt(usize) or
        storage.huffman_nodes.len < summary.huffman_node_count or
        summary.codebook_multiplicand_count > std.math.maxInt(usize) or
        storage.codebook_multiplicands.len <
            summary.codebook_multiplicand_count or
        storage.floors.len < summary.floor_count or
        storage.residues.len < summary.residue_count or
        storage.mappings.len < summary.mapping_count or
        storage.modes.len < summary.mode_count)
        return error.VorbisSetupStorageTooSmall;
    const destination = VorbisSetupDestination{
        .codebooks = storage.codebooks[0..summary.codebook_count],
        .codebook_entries = storage.codebook_entries[0..@intCast(summary.codebook_entry_count)],
        .huffman_nodes = storage.huffman_nodes[0..@intCast(summary.huffman_node_count)],
        .codebook_multiplicands = storage.codebook_multiplicands[0..@intCast(summary.codebook_multiplicand_count)],
        .floors = storage.floors[0..summary.floor_count],
        .residues = storage.residues[0..summary.residue_count],
        .mappings = storage.mappings[0..summary.mapping_count],
        .modes = storage.modes[0..summary.mode_count],
    };
    _ = try parseVorbisSetupInternal(
        packet,
        channel_count,
        destination,
    );
    return .{
        .summary = summary,
        .codebooks = destination.codebooks,
        .codebook_entries = destination.codebook_entries,
        .huffman_nodes = destination.huffman_nodes,
        .codebook_multiplicands = destination.codebook_multiplicands,
        .floors = destination.floors,
        .residues = destination.residues,
        .mappings = destination.mappings,
        .modes = destination.modes,
    };
}

pub fn validateVorbisSetup(
    packet: []const u8,
    channel_count: u8,
) !VorbisSetupSummary {
    return parseVorbisSetupInternal(packet, channel_count, null);
}

pub fn requiredVorbisSetupPacketBytes(
    setup: VorbisSetup,
    channel_count: u8,
) !usize {
    var encoder = VorbisSetupPacketEncoder{};
    try encoder.writeSetup(setup, channel_count);
    return try encoder.byteCount();
}

pub fn encodeVorbisSetupPacket(
    destination: []u8,
    setup: VorbisSetup,
    channel_count: u8,
) ![]const u8 {
    const required = try requiredVorbisSetupPacketBytes(
        setup,
        channel_count,
    );
    if (destination.len < required)
        return error.VorbisSetupOutputTooSmall;
    try rejectVorbisSetupOverlap(
        destination[0..required],
        setup,
    );
    @memset(destination[0..required], 0);
    var encoder = VorbisSetupPacketEncoder{
        .destination = destination[7..required],
    };
    try encoder.writeSetup(setup, channel_count);
    std.debug.assert(try encoder.byteCount() == required);
    @memcpy(destination[0..7], "\x05vorbis");
    return destination[0..required];
}

const VorbisSetupPacketEncoder = struct {
    destination: ?[]u8 = null,
    bit_offset: usize = 0,

    fn writeSetup(
        self: *VorbisSetupPacketEncoder,
        setup: VorbisSetup,
        channel_count: u8,
    ) !void {
        if (channel_count == 0)
            return error.InvalidVorbisChannelCount;
        if (setup.codebooks.len == 0 or setup.codebooks.len > 256)
            return error.InvalidVorbisSetupCodebookCount;
        if (setup.summary.time_count == 0 or
            setup.summary.time_count > 64)
            return error.InvalidVorbisTimeCount;
        try validateVorbisSetupSliceCounts(setup);

        try self.write(
            @as(u32, @intCast(setup.codebooks.len - 1)),
            8,
        );
        var entry_count: u64 = 0;
        var node_count: u64 = 0;
        var multiplicand_count: u64 = 0;
        var maximum_dimensions: u16 = 0;
        var maximum_entries: u32 = 0;
        for (setup.codebooks) |codebook| {
            const entries = try vorbisSetupSlice(
                VorbisCodebookEntry,
                setup.codebook_entries,
                codebook.entry_offset,
                codebook.entries,
            );
            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            try self.writeCodebook(
                codebook,
                entries,
                multiplicands,
            );
            entry_count = std.math.add(
                u64,
                entry_count,
                codebook.entries,
            ) catch return error.VorbisSetupSizeOverflow;
            node_count = std.math.add(
                u64,
                node_count,
                if (codebook.active_entry_count > 1)
                    codebook.active_entry_count - 1
                else
                    0,
            ) catch return error.VorbisSetupSizeOverflow;
            multiplicand_count = std.math.add(
                u64,
                multiplicand_count,
                codebook.multiplicand_count,
            ) catch return error.VorbisSetupSizeOverflow;
            maximum_dimensions = @max(
                maximum_dimensions,
                codebook.dimensions,
            );
            maximum_entries = @max(
                maximum_entries,
                codebook.entries,
            );
        }

        try self.write(
            setup.summary.time_count - 1,
            6,
        );
        for (0..setup.summary.time_count) |_|
            try self.write(0, 16);

        try self.write(
            @as(u32, @intCast(setup.floors.len - 1)),
            6,
        );
        for (setup.floors) |floor|
            try self.writeFloor(floor, setup.codebooks);

        try self.write(
            @as(u32, @intCast(setup.residues.len - 1)),
            6,
        );
        for (setup.residues) |residue|
            try self.writeResidue(residue, setup.codebooks);

        try self.write(
            @as(u32, @intCast(setup.mappings.len - 1)),
            6,
        );
        for (setup.mappings) |mapping| {
            try self.writeMapping(
                mapping,
                channel_count,
                setup.floors.len,
                setup.residues.len,
            );
        }

        try self.write(
            @as(u32, @intCast(setup.modes.len - 1)),
            6,
        );
        for (setup.modes) |mode| {
            try self.write(@intFromBool(mode.large_block), 1);
            try self.write(0, 16);
            try self.write(0, 16);
            if (mode.mapping >= setup.mappings.len)
                return error.InvalidVorbisModeMapping;
            try self.write(mode.mapping, 8);
        }
        try self.write(1, 1);

        const expected = VorbisSetupSummary{
            .codebook_count = @intCast(setup.codebooks.len),
            .codebook_entry_count = entry_count,
            .huffman_node_count = node_count,
            .codebook_multiplicand_count = multiplicand_count,
            .time_count = setup.summary.time_count,
            .floor_count = @intCast(setup.floors.len),
            .residue_count = @intCast(setup.residues.len),
            .mapping_count = @intCast(setup.mappings.len),
            .mode_count = @intCast(setup.modes.len),
            .maximum_codebook_dimensions = maximum_dimensions,
            .maximum_codebook_entries = maximum_entries,
        };
        if (!std.meta.eql(expected, setup.summary))
            return error.InconsistentVorbisSetupSummary;
    }

    fn writeCodebook(
        self: *VorbisSetupPacketEncoder,
        codebook: VorbisCodebook,
        entries: []const VorbisCodebookEntry,
        multiplicands: []const u32,
    ) !void {
        if (codebook.dimensions == 0 or codebook.entries == 0 or
            codebook.entries > 0xffffff)
            return error.InvalidVorbisCodebook;
        if (entries.len != codebook.entries)
            return error.InvalidVorbisCodebook;

        var length_counts = [_]u32{0} ** 32;
        var active_entries: u32 = 0;
        for (entries) |entry| {
            if (entry.length > 32)
                return error.InvalidVorbisCodebookLengths;
            if (entry.length != 0) {
                length_counts[entry.length - 1] += 1;
                active_entries += 1;
            }
        }
        try validateVorbisCodebookTree(
            &length_counts,
            active_entries,
        );
        if (active_entries != codebook.active_entry_count)
            return error.InconsistentVorbisCodebook;

        try self.write(0x564342, 24);
        try self.write(codebook.dimensions, 16);
        try self.write(codebook.entries, 24);
        try self.write(0, 1);
        const sparse = active_entries != codebook.entries;
        try self.write(@intFromBool(sparse), 1);
        for (entries) |entry| {
            if (sparse) try self.write(
                @intFromBool(entry.length != 0),
                1,
            );
            if (entry.length != 0)
                try self.write(entry.length - 1, 5);
        }

        if (codebook.lookup_type > 2)
            return error.UnsupportedVorbisCodebookLookup;
        try self.write(codebook.lookup_type, 4);
        if (codebook.lookup_type == 0) {
            if (codebook.multiplicand_count != 0 or
                multiplicands.len != 0)
                return error.InconsistentVorbisCodebook;
            return;
        }

        const expected_multiplicands: u64 =
            if (codebook.lookup_type == 1)
                vorbisLookupOneValues(
                    codebook.entries,
                    codebook.dimensions,
                )
            else
                @as(u64, codebook.entries) * codebook.dimensions;
        if (codebook.multiplicand_count != expected_multiplicands or
            multiplicands.len != expected_multiplicands)
            return error.InconsistentVorbisCodebook;
        try self.write(
            try vorbisFloat32PackExact(codebook.minimum_value),
            32,
        );
        try self.write(
            try vorbisFloat32PackExact(codebook.delta_value),
            32,
        );
        var maximum_multiplicand: u32 = 0;
        for (multiplicands) |value|
            maximum_multiplicand = @max(maximum_multiplicand, value);
        const value_bits: u6 = @max(
            1,
            vorbisILog(maximum_multiplicand),
        );
        if (value_bits > 16)
            return error.VorbisCodebookMultiplicandTooLarge;
        try self.write(value_bits - 1, 4);
        try self.write(@intFromBool(codebook.sequence), 1);
        for (multiplicands) |value|
            try self.write(value, value_bits);
    }

    fn writeFloor(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloor,
        codebooks: []const VorbisCodebook,
    ) !void {
        switch (floor) {
            .zero => |zero| try self.writeFloorZero(
                zero,
                codebooks,
            ),
            .one => |one| try self.writeFloorOne(
                one,
                codebooks,
            ),
        }
    }

    fn writeFloorZero(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloorZero,
        codebooks: []const VorbisCodebook,
    ) !void {
        if (floor.order == 0 or floor.rate == 0 or
            floor.bark_map_size == 0 or floor.book_count == 0 or
            floor.book_count > 16)
            return error.InvalidVorbisFloorConfiguration;
        try self.write(0, 16);
        try self.write(floor.order, 8);
        try self.write(floor.rate, 16);
        try self.write(floor.bark_map_size, 16);
        try self.write(floor.amplitude_bits, 6);
        try self.write(floor.amplitude_offset, 8);
        try self.write(floor.book_count - 1, 4);
        for (floor.books[0..floor.book_count]) |book| {
            if (book >= codebooks.len or
                codebooks[book].lookup_type == 0)
                return error.InvalidVorbisFloorCodebook;
            try self.write(book, 8);
        }
    }

    fn writeFloorOne(
        self: *VorbisSetupPacketEncoder,
        floor: VorbisFloorOne,
        codebooks: []const VorbisCodebook,
    ) !void {
        try self.write(1, 16);
        try self.write(floor.partition_count, 5);
        var maximum_class: ?u4 = null;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            maximum_class = @max(maximum_class orelse 0, class);
            try self.write(class, 4);
        }
        const class_count: u5 = if (maximum_class) |highest|
            @as(u5, highest) + 1
        else
            0;
        if (floor.class_count != class_count)
            return error.InvalidVorbisFloorConfiguration;
        for (floor.classes[0..class_count]) |class| {
            if (class.dimensions == 0 or class.dimensions > 8)
                return error.InvalidVorbisFloorConfiguration;
            try self.write(class.dimensions - 1, 3);
            try self.write(class.subclass_bits, 2);
            if (class.subclass_bits != 0) {
                if (class.masterbook < 0 or
                    class.masterbook >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                try self.write(
                    @as(u32, @intCast(class.masterbook)),
                    8,
                );
            } else if (class.masterbook != -1) {
                return error.InvalidVorbisFloorConfiguration;
            }
            const subclass_count =
                @as(usize, 1) << @intCast(class.subclass_bits);
            for (class.subclass_books[0..subclass_count]) |book| {
                if (book < -1 or book >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                try self.write(@as(u32, @intCast(book + 1)), 8);
            }
        }
        if (floor.multiplier == 0 or floor.multiplier > 4)
            return error.InvalidVorbisFloorConfiguration;
        try self.write(floor.multiplier - 1, 2);
        try self.write(floor.range_bits, 4);

        var expected_points: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            expected_points = std.math.add(
                usize,
                expected_points,
                floor.classes[class].dimensions,
            ) catch return error.TooManyVorbisFloorPoints;
        }
        if (expected_points > floor.x_list.len or
            floor.point_count != expected_points or
            floor.x_list[0] != 0 or
            floor.x_list[1] !=
                @as(u16, 1) << @intCast(floor.range_bits))
            return error.InvalidVorbisFloorConfiguration;
        var point_index: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class| {
            for (0..floor.classes[class].dimensions) |_| {
                const point = floor.x_list[point_index];
                for (floor.x_list[0..point_index]) |existing| {
                    if (point == existing)
                        return error.DuplicateVorbisFloorPoint;
                }
                if (point >=
                    @as(u32, 1) << @intCast(floor.range_bits))
                    return error.InvalidVorbisFloorConfiguration;
                try self.write(point, floor.range_bits);
                point_index += 1;
            }
        }
    }

    fn writeResidue(
        self: *VorbisSetupPacketEncoder,
        residue: VorbisResidue,
        codebooks: []const VorbisCodebook,
    ) !void {
        if (residue.partition_size == 0 or
            residue.partition_size > 0x1000000 or
            residue.classification_count == 0 or
            residue.classification_count > 64)
            return error.InvalidVorbisResidueConfiguration;
        if (residue.classbook >= codebooks.len)
            return error.InvalidVorbisResidueCodebook;
        const classbook = codebooks[residue.classbook];
        if (!powerAtMost(
            residue.classification_count,
            classbook.dimensions,
            classbook.entries,
        )) return error.InvalidVorbisResidueClassbook;

        try self.write(@intFromEnum(residue.kind), 16);
        try self.write(residue.begin, 24);
        try self.write(residue.end, 24);
        try self.write(residue.partition_size - 1, 24);
        try self.write(residue.classification_count - 1, 6);
        try self.write(residue.classbook, 8);
        for (residue.cascades[0..residue.classification_count]) |cascade| {
            try self.write(cascade & 7, 3);
            const has_high_bits = cascade > 7;
            try self.write(@intFromBool(has_high_bits), 1);
            if (has_high_bits) try self.write(cascade >> 3, 5);
        }
        for (
            residue.cascades[0..residue.classification_count],
            0..,
        ) |cascade, classification| {
            for (0..8) |pass| {
                const book = residue.books[classification][pass];
                if (cascade & (@as(u8, 1) << @intCast(pass)) == 0) {
                    if (book != -1)
                        return error.InvalidVorbisResidueConfiguration;
                    continue;
                }
                if (book < 0 or book >= codebooks.len or
                    codebooks[@intCast(book)].lookup_type == 0 or
                    residue.partition_size %
                        codebooks[@intCast(book)].dimensions != 0)
                    return error.InvalidVorbisResidueCodebook;
                try self.write(@as(u32, @intCast(book)), 8);
            }
        }
    }

    fn writeMapping(
        self: *VorbisSetupPacketEncoder,
        mapping: VorbisMapping,
        channel_count: u8,
        floor_count: usize,
        residue_count: usize,
    ) !void {
        if (mapping.submap_count == 0 or
            mapping.submap_count > 16)
            return error.InvalidVorbisMapping;
        if (channel_count == 1 and mapping.coupling_step_count != 0)
            return error.InvalidVorbisChannelCoupling;
        try self.write(0, 16);
        const multiple_submaps = mapping.submap_count > 1;
        try self.write(@intFromBool(multiple_submaps), 1);
        if (multiple_submaps)
            try self.write(mapping.submap_count - 1, 4);
        const coupled = mapping.coupling_step_count != 0;
        try self.write(@intFromBool(coupled), 1);
        if (coupled) {
            try self.write(mapping.coupling_step_count - 1, 8);
            const channel_bits = vorbisILog(channel_count - 1);
            for (
                mapping.coupling_steps[0..mapping.coupling_step_count],
            ) |step| {
                if (step.magnitude == step.angle or
                    step.magnitude >= channel_count or
                    step.angle >= channel_count)
                    return error.InvalidVorbisChannelCoupling;
                try self.write(step.magnitude, channel_bits);
                try self.write(step.angle, channel_bits);
            }
        }
        try self.write(0, 2);
        if (multiple_submaps) {
            for (mapping.channel_mux[0..channel_count]) |mux| {
                if (mux >= mapping.submap_count)
                    return error.InvalidVorbisChannelMux;
                try self.write(mux, 4);
            }
        }
        for (mapping.submaps[0..mapping.submap_count]) |submap| {
            if (submap.floor >= floor_count)
                return error.InvalidVorbisMappingFloor;
            if (submap.residue >= residue_count)
                return error.InvalidVorbisMappingResidue;
            try self.write(0, 8);
            try self.write(submap.floor, 8);
            try self.write(submap.residue, 8);
        }
    }

    fn write(
        self: *VorbisSetupPacketEncoder,
        value: anytype,
        bit_count: u6,
    ) !void {
        const next_offset = std.math.add(
            usize,
            self.bit_offset,
            bit_count,
        ) catch return error.VorbisSetupSizeOverflow;
        if (self.destination) |destination| {
            if (next_offset > destination.len * 8)
                return error.VorbisSetupOutputTooSmall;
            const encoded: u32 = @intCast(value);
            for (0..bit_count) |index| {
                const destination_bit = self.bit_offset + index;
                destination[destination_bit / 8] |=
                    @as(u8, @intCast(
                        (encoded >> @intCast(index)) & 1,
                    )) << @intCast(destination_bit % 8);
            }
        }
        self.bit_offset = next_offset;
    }

    fn byteCount(self: *const VorbisSetupPacketEncoder) !usize {
        const payload_bytes = std.math.add(
            usize,
            self.bit_offset,
            7,
        ) catch return error.VorbisSetupSizeOverflow;
        return std.math.add(
            usize,
            7,
            payload_bytes / 8,
        ) catch return error.VorbisSetupSizeOverflow;
    }
};

fn validateVorbisSetupSliceCounts(setup: VorbisSetup) !void {
    if (setup.floors.len == 0 or setup.floors.len > 64 or
        setup.residues.len == 0 or setup.residues.len > 64 or
        setup.mappings.len == 0 or setup.mappings.len > 64 or
        setup.modes.len == 0 or setup.modes.len > 64)
        return error.InvalidVorbisSetupCount;
    if (setup.summary.codebook_count != setup.codebooks.len or
        setup.summary.floor_count != setup.floors.len or
        setup.summary.residue_count != setup.residues.len or
        setup.summary.mapping_count != setup.mappings.len or
        setup.summary.mode_count != setup.modes.len)
        return error.InconsistentVorbisSetupSummary;
}

fn vorbisSetupSlice(
    comptime T: type,
    values: []const T,
    offset: u64,
    count: u64,
) ![]const T {
    if (offset > std.math.maxInt(usize) or
        count > std.math.maxInt(usize))
        return error.InvalidVorbisSetupStorage;
    const start: usize = @intCast(offset);
    const length: usize = @intCast(count);
    if (start > values.len or length > values.len - start)
        return error.InvalidVorbisSetupStorage;
    return values[start..][0..length];
}

fn rejectVorbisSetupOverlap(
    destination: []u8,
    setup: VorbisSetup,
) !void {
    const destination_address = @intFromPtr(destination.ptr);
    inline for (.{
        setup.codebooks,
        setup.codebook_entries,
        setup.codebook_multiplicands,
        setup.floors,
        setup.residues,
        setup.mappings,
        setup.modes,
    }) |values| {
        if (byteRangesOverlap(
            destination_address,
            destination.len,
            @intFromPtr(values.ptr),
            std.math.mul(
                usize,
                values.len,
                @sizeOf(@TypeOf(values[0])),
            ) catch return error.VorbisSetupSizeOverflow,
        )) return error.OverlappingVorbisSetupStorage;
    }
}

const VorbisBitReader = struct {
    bytes: []const u8,
    bit_offset: usize = 0,

    fn read(self: *VorbisBitReader, bit_count: u6) !u32 {
        if (@as(usize, bit_count) > self.remainingBits())
            return error.TruncatedVorbisSetup;
        var value: u32 = 0;
        for (0..bit_count) |index| {
            const source_bit = self.bit_offset + index;
            value |= @as(u32, (self.bytes[source_bit / 8] >>
                @intCast(source_bit % 8)) & 1) << @intCast(index);
        }
        self.bit_offset += bit_count;
        return value;
    }

    fn skip(self: *VorbisBitReader, bit_count: u64) !void {
        if (bit_count > self.remainingBits())
            return error.TruncatedVorbisSetup;
        self.bit_offset += @intCast(bit_count);
    }

    fn remainingBits(self: *const VorbisBitReader) usize {
        return self.bytes.len * 8 -| self.bit_offset;
    }
};

const VorbisSetupDestination = struct {
    codebooks: []VorbisCodebook,
    codebook_entries: []VorbisCodebookEntry,
    huffman_nodes: []VorbisHuffmanNode,
    codebook_multiplicands: []u32,
    floors: []VorbisFloor,
    residues: []VorbisResidue,
    mappings: []VorbisMapping,
    modes: []VorbisMode,
};

fn parseVorbisSetupInternal(
    packet: []const u8,
    channel_count: u8,
    destination: ?VorbisSetupDestination,
) !VorbisSetupSummary {
    if (packet.len < 8 or packet[0] != 5 or
        !std.mem.eql(u8, packet[1..7], "vorbis"))
        return error.InvalidVorbisSetupHeader;
    if (channel_count == 0) return error.InvalidVorbisChannelCount;

    var reader = VorbisBitReader{ .bytes = packet[7..] };
    const codebook_count: u16 = @intCast(try reader.read(8) + 1);
    var codebooks: [256]VorbisCodebook = undefined;
    var codebook_entry_count: u64 = 0;
    var huffman_node_count: u64 = 0;
    var codebook_multiplicand_count: u64 = 0;
    var maximum_dimensions: u16 = 0;
    var maximum_entries: u32 = 0;
    for (codebooks[0..codebook_count], 0..) |*codebook, index| {
        const entry_destination: ?[]VorbisCodebookEntry =
            if (destination) |output|
                output.codebook_entries[@intCast(codebook_entry_count)..]
            else
                null;
        const node_destination: ?[]VorbisHuffmanNode =
            if (destination) |output|
                output.huffman_nodes[@intCast(huffman_node_count)..]
            else
                null;
        const multiplicand_destination: ?[]u32 =
            if (destination) |output|
                output.codebook_multiplicands[@intCast(codebook_multiplicand_count)..]
            else
                null;
        codebook.* = try parseVorbisCodebook(
            &reader,
            codebook_entry_count,
            entry_destination,
            huffman_node_count,
            node_destination,
            codebook_multiplicand_count,
            multiplicand_destination,
        );
        codebook_entry_count = std.math.add(
            u64,
            codebook_entry_count,
            codebook.entries,
        ) catch return error.VorbisSetupSizeOverflow;
        huffman_node_count = std.math.add(
            u64,
            huffman_node_count,
            codebook.tree_node_count,
        ) catch return error.VorbisSetupSizeOverflow;
        codebook_multiplicand_count = std.math.add(
            u64,
            codebook_multiplicand_count,
            codebook.multiplicand_count,
        ) catch return error.VorbisSetupSizeOverflow;
        maximum_dimensions = @max(maximum_dimensions, codebook.dimensions);
        maximum_entries = @max(maximum_entries, codebook.entries);
        if (destination) |output| output.codebooks[index] = codebook.*;
    }

    const time_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..time_count) |_| {
        if (try reader.read(16) != 0)
            return error.UnsupportedVorbisTimeTransform;
    }

    const floor_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..floor_count) |index| {
        const floor: VorbisFloor = switch (try reader.read(16)) {
            0 => .{
                .zero = try parseVorbisFloorZero(
                    &reader,
                    codebooks[0..codebook_count],
                ),
            },
            1 => .{
                .one = try parseVorbisFloorOne(
                    &reader,
                    codebooks[0..codebook_count],
                ),
            },
            else => return error.UnsupportedVorbisFloorType,
        };
        if (destination) |output| output.floors[index] = floor;
    }

    const residue_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..residue_count) |index| {
        const residue = try parseVorbisResidue(
            &reader,
            codebooks[0..codebook_count],
        );
        if (destination) |output| output.residues[index] = residue;
    }

    const mapping_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..mapping_count) |index| {
        const mapping = try parseVorbisMapping(
            &reader,
            channel_count,
            floor_count,
            residue_count,
        );
        if (destination) |output| output.mappings[index] = mapping;
    }

    const mode_count: u8 = @intCast(try reader.read(6) + 1);
    for (0..mode_count) |index| {
        const large_block = try reader.read(1) != 0;
        if (try reader.read(16) != 0 or try reader.read(16) != 0)
            return error.UnsupportedVorbisMode;
        const mapping: u8 = @intCast(try reader.read(8));
        if (mapping >= mapping_count)
            return error.InvalidVorbisModeMapping;
        if (destination) |output| {
            output.modes[index] = .{
                .large_block = large_block,
                .mapping = mapping,
            };
        }
    }
    if (try reader.read(1) != 1) return error.InvalidVorbisSetupFraming;

    return .{
        .codebook_count = codebook_count,
        .codebook_entry_count = codebook_entry_count,
        .huffman_node_count = huffman_node_count,
        .codebook_multiplicand_count = codebook_multiplicand_count,
        .time_count = time_count,
        .floor_count = floor_count,
        .residue_count = residue_count,
        .mapping_count = mapping_count,
        .mode_count = mode_count,
        .maximum_codebook_dimensions = maximum_dimensions,
        .maximum_codebook_entries = maximum_entries,
    };
}

const VorbisVectorCursor = struct {
    codebook: VorbisCodebook,
    multiplicands: []const u32,
    entry: u32,
    index_divisor: u64 = 1,
    explicit_offset: u64,
    last: f64 = 0,

    fn next(self: *VorbisVectorCursor) f64 {
        const multiplicand_index: usize =
            if (self.codebook.lookup_type == 1)
                @intCast(
                    (self.entry / self.index_divisor) %
                        self.multiplicands.len,
                )
            else blk: {
                const index: usize = @intCast(self.explicit_offset);
                self.explicit_offset += 1;
                break :blk index;
            };
        const decoded =
            @as(f64, @floatFromInt(
                self.multiplicands[multiplicand_index],
            )) *
            self.codebook.delta_value +
            self.codebook.minimum_value +
            self.last;
        if (self.codebook.sequence) self.last = decoded;
        if (self.codebook.lookup_type == 1)
            self.index_divisor *= self.multiplicands.len;
        return decoded;
    }
};

pub const VorbisVectorQuantization = struct {
    entry: u32,
    squared_error: f64,
};

pub const VorbisVectorBatchQuantization = struct {
    entries: []u32,
    squared_error: f64,
};

pub fn quantizeVorbisVector(
    comptime Float: type,
    setup: VorbisSetup,
    codebook_number: u8,
    target: []const Float,
) !VorbisVectorQuantization {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis vector quantization requires f32 or f64");
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    try validateVorbisVectorCodebookState(codebook, setup);
    if (target.len != codebook.dimensions)
        return error.InvalidVorbisQuantizationShape;
    for (target) |value| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisQuantizationTarget;
    }
    if (!std.math.isFinite(codebook.minimum_value) or
        !std.math.isFinite(codebook.delta_value))
        return error.InvalidVorbisSetupState;

    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    const multiplicands = try vorbisSetupSlice(
        u32,
        setup.codebook_multiplicands,
        codebook.multiplicand_offset,
        codebook.multiplicand_count,
    );
    const expected_multiplicands: u64 =
        if (codebook.lookup_type == 1)
            vorbisLookupOneValues(
                codebook.entries,
                codebook.dimensions,
            )
        else
            @as(u64, codebook.entries) * codebook.dimensions;
    if (codebook.multiplicand_count != expected_multiplicands or
        multiplicands.len == 0)
        return error.InvalidVorbisSetupState;

    var best_entry: ?u32 = null;
    var best_error = std.math.inf(f128);
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var index_divisor: u64 = 1;
        var explicit_offset =
            @as(u64, @intCast(entry_number)) * codebook.dimensions;
        var last: f64 = 0;
        var error_sum: f128 = 0;
        for (target) |target_value| {
            const multiplicand_index: usize =
                if (codebook.lookup_type == 1)
                    @intCast(
                        (@as(u64, @intCast(entry_number)) /
                            index_divisor) %
                            multiplicands.len,
                    )
                else blk: {
                    const index: usize =
                        @intCast(explicit_offset);
                    explicit_offset += 1;
                    break :blk index;
                };
            const decoded =
                @as(f64, @floatFromInt(
                    multiplicands[multiplicand_index],
                )) *
                codebook.delta_value +
                codebook.minimum_value +
                last;
            if (!std.math.isFinite(decoded))
                return error.InvalidVorbisSetupState;
            if (codebook.sequence) last = decoded;
            if (codebook.lookup_type == 1)
                index_divisor *= multiplicands.len;
            const difference =
                @as(f128, @floatCast(target_value)) -
                @as(f128, @floatCast(decoded));
            error_sum += difference * difference;
        }
        if (error_sum < best_error) {
            best_error = error_sum;
            best_entry = @intCast(entry_number);
        }
    }
    return .{
        .entry = best_entry orelse
            return error.InvalidVorbisSetupState,
        .squared_error = @floatCast(best_error),
    };
}

pub fn quantizeVorbisVectors(
    comptime Float: type,
    setup: VorbisSetup,
    codebook_number: u8,
    targets: []const Float,
    destination: []u32,
) !VorbisVectorBatchQuantization {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis vector quantization requires f32 or f64");
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const dimensions: usize = setup.codebooks[codebook_number].dimensions;
    if (dimensions == 0)
        return error.InvalidVorbisSetupState;
    if (targets.len % dimensions != 0)
        return error.InvalidVorbisQuantizationShape;
    const vector_count = targets.len / dimensions;
    if (destination.len < vector_count)
        return error.VorbisQuantizationOutputTooSmall;

    const output = destination[0..vector_count];
    const output_bytes = std.mem.sliceAsBytes(output);
    if (vorbisSliceOverlapsBytes(Float, targets, output_bytes) or
        vorbisSliceOverlapsBytes(
            VorbisCodebook,
            setup.codebooks,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            VorbisCodebookEntry,
            setup.codebook_entries,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            VorbisHuffmanNode,
            setup.huffman_nodes,
            output_bytes,
        ) or
        vorbisSliceOverlapsBytes(
            u32,
            setup.codebook_multiplicands,
            output_bytes,
        ))
        return error.OverlappingVorbisQuantization;

    var total_error: f128 = 0;
    for (0..vector_count) |index| {
        const start = index * dimensions;
        const quantized = try quantizeVorbisVector(
            Float,
            setup,
            codebook_number,
            targets[start .. start + dimensions],
        );
        total_error += quantized.squared_error;
    }
    for (output, 0..) |*entry, index| {
        const start = index * dimensions;
        entry.* = (try quantizeVorbisVector(
            Float,
            setup,
            codebook_number,
            targets[start .. start + dimensions],
        )).entry;
    }
    return .{
        .entries = output,
        .squared_error = @floatCast(total_error),
    };
}

pub const VorbisFloorZeroEncoding = struct {
    amplitude: u64 = 0,
    book_number: u8 = 0,
    entries: []const u32 = &.{},
};

pub const VorbisFloorOneEncoding = struct {
    used: bool = false,
    y_values: []const u32 = &.{},
};

pub const VorbisFloorOneFit = struct {
    encoding: VorbisFloorOneEncoding,
    squared_control_point_error: f64,
};

pub const VorbisAudioFloorOneStorageRequirements = struct {
    encodings: usize,
    y_values: usize,
    curve_values: usize,
};

pub fn VorbisAudioFloorOneScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        y_values: []u32,
        curves: []Float,
    };
}

pub fn VorbisAudioFloorOneStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        encodings: []VorbisFloorPacketEncoding,
        y_values: []u32,
        curves: []Float,
    };
}

pub fn VorbisAudioFloorOnePlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    return struct {
        encodings: []const VorbisFloorPacketEncoding,
        y_values: []const u32,
        curves: []const Float,
        coefficient_count: usize,
        squared_control_point_error: f64,
    };
}

pub const VorbisAudioResiduePreparationStorageRequirements = struct {
    floor_encodings: usize,
    floor_y_values: usize,
    floor_curve_values: usize,
    residue_values: usize,
    threshold_values: usize,
    coupling_values: usize,
    do_not_encode: usize,
};

pub fn VorbisAudioResiduePreparationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_fit_y_values: []u32,
        floor_fit_curves: []Float,
        floor_encodings: []VorbisFloorPacketEncoding,
        floor_y_values: []u32,
        floor_curves: []Float,
        residue_values: []Float,
        noise_thresholds: []Float,
        coupling_values: []Float,
        coupling_thresholds: []Float,
        do_not_encode: []bool,
    };
}

pub fn VorbisAudioResiduePreparationStorage(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_encodings: []VorbisFloorPacketEncoding,
        floor_y_values: []u32,
        floor_curves: []Float,
        residue_values: []Float,
        noise_thresholds: []Float,
        do_not_encode: []bool,
    };
}

pub fn VorbisAudioResiduePreparationPlan(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    return struct {
        floor_encodings: []const VorbisFloorPacketEncoding,
        floor_y_values: []const u32,
        floor_curves: []const Float,
        residue_values: []const Float,
        noise_thresholds: []const Float,
        do_not_encode: []const bool,
        coefficient_count: usize,
        fixed_packet_bits: u32,
        squared_control_point_error: f64,
    };
}

pub const VorbisResidueEncoding = struct {
    do_not_encode: []const bool,
    classifications: []const u8,
    entries: []const u32,
};

pub fn VorbisResidueQuantizationScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
    };
}

pub const VorbisResidueQuantizationScratchRequirements = struct {
    partition_values: usize,
    vector_values: usize,
    classifications: usize,
};

pub const VorbisResidueQuantization = struct {
    encoding: VorbisResidueEncoding,
    squared_error: f64,
};

pub fn VorbisAdaptiveResidueScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("adaptive Vorbis quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
        best_classifications: []u8,
    };
}

pub const VorbisAdaptiveResidueConfig = struct {
    target_bits: u32,
    maximum_iterations: u8 = 32,
    initial_lambda: f64 = 0.000_001,
};

pub const VorbisAdaptiveResidueQuantization = struct {
    encoding: VorbisResidueEncoding,
    squared_error: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
    encoded_bits: u32,
    budget_met: bool,
    lambda: f64,
    iterations: u8,
};

pub const VorbisAudioResidueQuantizationConfig = struct {
    maximum_iterations: u8 = 32,
    initial_lambda: f64 = 0.000_001,
};

pub const VorbisAudioResidueSubmapResult = struct {
    target_bits: u32,
    encoded_bits: u32,
    budget_met: bool,
    squared_error: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
    lambda: f64,
    iterations: u8,
};

pub const VorbisAudioResidueQuantizationStorageRequirements = struct {
    encodings: usize,
    submap_results: usize,
    do_not_encode: usize,
    classifications: usize,
    entries: usize,
    partition_values: usize,
    vector_values: usize,
    classification_scratch: usize,
};

pub fn VorbisAudioResidueQuantizationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis audio residue quantization requires f32 or f64");
    return struct {
        partition: []Float,
        vector: []Float,
        classifications: []u8,
        best_classifications: []u8,
        output_classifications: []u8,
        entries: []u32,
        do_not_encode: []bool,
    };
}

pub const VorbisAudioResidueQuantizationStorage = struct {
    encodings: []VorbisResidueEncoding,
    submap_results: []VorbisAudioResidueSubmapResult,
    do_not_encode: []bool,
    classifications: []u8,
    entries: []u32,
};

pub const VorbisAudioResidueQuantizationPlan = struct {
    encodings: []const VorbisResidueEncoding,
    submap_results: []const VorbisAudioResidueSubmapResult,
    do_not_encode: []const bool,
    classifications: []const u8,
    entries: []const u32,
    allocation: VorbisResidueBitAllocation,
};

pub const VorbisPcmPacketEncodingStorageRequirements = struct {
    preparation: VorbisAudioResiduePreparationStorageRequirements,
    quantization: VorbisAudioResidueQuantizationStorageRequirements,
};

pub fn VorbisPcmPacketEncodingScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        preparation: VorbisAudioResiduePreparationScratch(Float),
        preparation_storage: VorbisAudioResiduePreparationStorage(Float),
        quantization: VorbisAudioResidueQuantizationScratch(Float),
        quantization_storage: VorbisAudioResidueQuantizationStorage,
    };
}

pub fn VorbisPcmPacketEncodingStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        preparation: VorbisAudioResiduePreparationStorage(Float),
        quantization: VorbisAudioResidueQuantizationStorage,
    };
}

pub fn VorbisPcmPacketEncodingTrial(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    return struct {
        packet: VorbisAudioPacketEncodingResult,
        commit: VorbisPcmPacketCommit,
        preparation: VorbisAudioResiduePreparationPlan(Float),
        quantization: VorbisAudioResidueQuantizationPlan,
    };
}

pub fn VorbisPcmPacketOrchestrationScratch(
    comptime Float: type,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet orchestration requires f32 or f64");
    return struct {
        analysis: VorbisPcmFrameAnalysisScratch(Float),
        analysis_storage: VorbisPcmFrameAnalysisStorage(Float),
        encoding: VorbisPcmPacketEncodingScratch(Float),
    };
}

pub const VorbisFloorPacketEncoding = union(enum) {
    zero: VorbisFloorZeroEncoding,
    one: VorbisFloorOneEncoding,
};

pub const VorbisAudioPacketEncoding = struct {
    mode_number: u8,
    previous_window_flag: ?bool = null,
    next_window_flag: ?bool = null,
    floors: []const VorbisFloorPacketEncoding,
    residues: []const VorbisResidueEncoding,
};

pub const VorbisAudioPacketPrefixEncoding = struct {
    mode_number: u8,
    previous_window_flag: ?bool = null,
    next_window_flag: ?bool = null,
    floors: []const VorbisFloorPacketEncoding,
};

pub const VorbisAudioPacketEncodingResult = struct {
    bytes: []const u8,
    bit_count: usize,
    header: VorbisAudioPacketHeader,
};

pub const VorbisAudioPacketFixedCost = struct {
    bit_count: u32,
    header: VorbisAudioPacketHeader,
    do_not_encode: []const bool,
};

pub const VorbisPacketWriter = struct {
    destination: []u8,
    bit_offset: usize = 0,
    count_only: bool = false,

    pub fn init(destination: []u8) VorbisPacketWriter {
        @memset(destination, 0);
        return .{ .destination = destination };
    }

    fn counting() VorbisPacketWriter {
        return .{
            .destination = &.{},
            .count_only = true,
        };
    }

    pub fn writeBits(
        self: *VorbisPacketWriter,
        value: u64,
        bit_count: u6,
    ) !void {
        if (bit_count < 64 and value >> bit_count != 0)
            return error.VorbisPacketValueDoesNotFit;
        try self.ensureCapacity(bit_count);
        self.writeBitsUnchecked(value, bit_count);
    }

    pub fn writeScalar(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) !void {
        const codeword = try writableVorbisCodeword(
            setup,
            codebook_number,
            entry_number,
        );
        const entry = codeword.entry;
        try self.ensureCapacity(entry.length);
        if (codeword.single_entry) {
            self.writeBitsUnchecked(0, 1);
            return;
        }
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            self.writeBitsUnchecked(
                (entry.codeword >> shift) & 1,
                1,
            );
        }
    }

    pub fn writeVectorEntry(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) !void {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        if (setup.codebooks[codebook_number].lookup_type == 0)
            return error.VorbisCodebookHasNoVectorLookup;
        try self.writeScalar(
            setup,
            codebook_number,
            entry_number,
        );
    }

    pub fn writeFloorZero(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        floor_number: u8,
        encoding: VorbisFloorZeroEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .zero => |value| value,
            .one => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorZeroState(floor, setup.codebooks);
        if (encoding.amplitude == 0) {
            if (encoding.entries.len != 0)
                return error.InvalidVorbisFloorEncoding;
            try self.ensureCapacity(floor.amplitude_bits);
            self.writeBitsUnchecked(0, floor.amplitude_bits);
            return;
        }
        if (floor.amplitude_bits == 0 or
            encoding.amplitude >>
                @intCast(floor.amplitude_bits) != 0 or
            encoding.book_number >= floor.book_count)
            return error.InvalidVorbisFloorEncoding;
        const codebook_number = floor.books[encoding.book_number];
        const dimensions = setup.codebooks[codebook_number].dimensions;
        const entry_count =
            (@as(usize, floor.order) + dimensions - 1) / dimensions;
        if (encoding.entries.len != entry_count)
            return error.InvalidVorbisFloorEncoding;

        var staged_entries: [255]u32 = undefined;
        @memcpy(
            staged_entries[0..entry_count],
            encoding.entries,
        );
        var required_bits: usize =
            @as(usize, floor.amplitude_bits) +
            vorbisILog(floor.book_count);
        for (staged_entries[0..entry_count]) |entry| {
            const codeword = try writableVorbisCodeword(
                setup,
                codebook_number,
                entry,
            );
            required_bits = try addVorbisPacketBits(
                required_bits,
                codeword.entry.length,
            );
        }
        try self.ensureCapacity(required_bits);
        self.writeBitsUnchecked(
            encoding.amplitude,
            floor.amplitude_bits,
        );
        self.writeBitsUnchecked(
            encoding.book_number,
            vorbisILog(floor.book_count),
        );
        for (staged_entries[0..entry_count]) |entry|
            self.writeScalarAssumeCapacity(
                setup,
                codebook_number,
                entry,
            );
    }

    pub fn writeFloorOne(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        floor_number: u8,
        encoding: VorbisFloorOneEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        if (!encoding.used) {
            if (encoding.y_values.len != 0)
                return error.InvalidVorbisFloorEncoding;
            try self.ensureCapacity(1);
            self.writeBitsUnchecked(0, 1);
            return;
        }
        if (encoding.y_values.len != floor.point_count)
            return error.InvalidVorbisFloorEncoding;
        var y_values: [65]u32 = undefined;
        @memcpy(
            y_values[0..floor.point_count],
            encoding.y_values,
        );
        const ranges = [_]u16{ 256, 128, 86, 64 };
        const value_bits = vorbisILog(ranges[floor.multiplier - 1] - 1);
        if (y_values[0] >= ranges[floor.multiplier - 1] or
            y_values[1] >= ranges[floor.multiplier - 1])
            return error.InvalidVorbisFloorEncoding;

        var classwords = [_]u32{0} ** 31;
        var required_bits: usize = 1 + 2 * @as(usize, value_bits);
        var value_offset: usize = 2;
        for (
            floor.partition_classes[0..floor.partition_count],
            0..,
        ) |class_index, partition| {
            const class = floor.classes[class_index];
            if (class.dimensions == 0 or class.dimensions > 8)
                return error.InvalidVorbisSetupState;
            const class_values =
                y_values[value_offset..][0..class.dimensions];
            if (class.subclass_bits != 0) {
                const masterbook: u8 = @intCast(class.masterbook);
                classwords[partition] =
                    try findVorbisFloorOneClassword(
                        setup,
                        class,
                        class_values,
                    );
                const masterword = try writableVorbisCodeword(
                    setup,
                    masterbook,
                    classwords[partition],
                );
                required_bits = try addVorbisPacketBits(
                    required_bits,
                    masterword.entry.length,
                );
            }
            var classword = classwords[partition];
            const mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (class_values) |value| {
                const book = class.subclass_books[classword & mask];
                classword >>= @intCast(class.subclass_bits);
                if (book < 0) {
                    if (value != 0)
                        return error.UnencodableVorbisFloorValue;
                    continue;
                }
                const codeword = try writableVorbisCodeword(
                    setup,
                    @intCast(book),
                    value,
                );
                required_bits = try addVorbisPacketBits(
                    required_bits,
                    codeword.entry.length,
                );
            }
            value_offset += class.dimensions;
        }
        if (value_offset != floor.point_count)
            return error.InvalidVorbisSetupState;
        try self.ensureCapacity(required_bits);

        self.writeBitsUnchecked(1, 1);
        self.writeBitsUnchecked(y_values[0], value_bits);
        self.writeBitsUnchecked(y_values[1], value_bits);
        value_offset = 2;
        for (
            floor.partition_classes[0..floor.partition_count],
            0..,
        ) |class_index, partition| {
            const class = floor.classes[class_index];
            var classword = classwords[partition];
            if (class.subclass_bits != 0) {
                self.writeScalarAssumeCapacity(
                    setup,
                    @intCast(class.masterbook),
                    classword,
                );
            }
            const mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (0..class.dimensions) |_| {
                const book = class.subclass_books[classword & mask];
                classword >>= @intCast(class.subclass_bits);
                if (book >= 0) {
                    self.writeScalarAssumeCapacity(
                        setup,
                        @intCast(book),
                        y_values[value_offset],
                    );
                }
                value_offset += 1;
            }
        }
    }

    pub fn writeResidue(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        residue_number: u8,
        vector_length: usize,
        encoding: VorbisResidueEncoding,
    ) !void {
        try rejectVorbisPacketSetupOverlap(
            self.destination,
            setup,
        );
        if (residue_number >= setup.residues.len)
            return error.InvalidVorbisResidueNumber;
        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        const shape = try vorbisResidueShape(
            residue,
            vector_length,
            encoding.do_not_encode.len,
        );
        var all_skipped = true;
        for (encoding.do_not_encode) |skip|
            all_skipped = all_skipped and skip;
        const type_two_skipped =
            residue.kind == .two and all_skipped;
        const expected_classifications =
            if (type_two_skipped)
                0
            else
                shape.required_classifications;
        if (encoding.classifications.len !=
            expected_classifications)
            return error.InvalidVorbisResidueEncoding;
        for (encoding.classifications) |classification| {
            if (classification >= residue.classification_count)
                return error.InvalidVorbisResidueEncoding;
        }
        if (type_two_skipped or shape.partition_count == 0) {
            if (encoding.entries.len != 0)
                return error.InvalidVorbisResidueEncoding;
            return;
        }
        if (vorbisSliceOverlapsBytes(
            bool,
            encoding.do_not_encode,
            self.destination,
        ) or vorbisSliceOverlapsBytes(
            u8,
            encoding.classifications,
            self.destination,
        ) or vorbisSliceOverlapsBytes(
            u32,
            encoding.entries,
            self.destination,
        )) return error.OverlappingVorbisPacketEncoding;

        var required_bits: usize = 0;
        var entry_offset: usize = 0;
        try walkVorbisResidueEncoding(
            setup,
            residue,
            shape,
            encoding,
            &required_bits,
            &entry_offset,
            null,
        );
        if (entry_offset != encoding.entries.len)
            return error.InvalidVorbisResidueEncoding;
        try self.ensureCapacity(required_bits);

        entry_offset = 0;
        var ignored_bits: usize = 0;
        walkVorbisResidueEncoding(
            setup,
            residue,
            shape,
            encoding,
            &ignored_bits,
            &entry_offset,
            self,
        ) catch unreachable;
        std.debug.assert(entry_offset == encoding.entries.len);
    }

    pub fn writeAudioHeader(
        self: *VorbisPacketWriter,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mode_number: u8,
        previous_window_flag: ?bool,
        next_window_flag: ?bool,
    ) !VorbisAudioPacketHeader {
        if (mode_number >= setup.modes.len)
            return error.InvalidVorbisModeNumber;
        const mode = setup.modes[mode_number];
        const block_size = if (mode.large_block)
            identification.large_block_size
        else
            identification.small_block_size;
        const header = VorbisAudioPacketHeader{
            .mode_number = mode_number,
            .large_block = mode.large_block,
            .previous_window_flag = if (mode.large_block)
                previous_window_flag orelse
                    return error.MissingVorbisWindowFlag
            else
                null,
            .next_window_flag = if (mode.large_block)
                next_window_flag orelse
                    return error.MissingVorbisWindowFlag
            else
                null,
            .block_size = block_size,
            .payload_bit_offset = 0,
        };
        _ = try validateVorbisAudioDecodeState(
            identification,
            setup,
            header,
        );
        const mode_bits = vorbisILog(setup.modes.len - 1);
        const header_bits: usize =
            1 + @as(usize, mode_bits) +
            if (mode.large_block) @as(usize, 2) else 0;
        try self.ensureCapacity(header_bits);
        self.writeBitsUnchecked(0, 1);
        self.writeBitsUnchecked(mode_number, mode_bits);
        if (mode.large_block) {
            self.writeBitsUnchecked(
                @intFromBool(previous_window_flag.?),
                1,
            );
            self.writeBitsUnchecked(
                @intFromBool(next_window_flag.?),
                1,
            );
        }
        var written = header;
        written.payload_bit_offset = self.bit_offset;
        return written;
    }

    pub fn bytes(self: *const VorbisPacketWriter) []const u8 {
        const byte_count =
            self.bit_offset / 8 +
            @intFromBool(self.bit_offset % 8 != 0);
        return self.destination[0..byte_count];
    }

    fn ensureCapacity(
        self: *const VorbisPacketWriter,
        bit_count: usize,
    ) !void {
        const next = std.math.add(
            usize,
            self.bit_offset,
            bit_count,
        ) catch return error.VorbisAudioPacketSizeOverflow;
        if (self.count_only) return;
        const capacity = std.math.mul(
            usize,
            self.destination.len,
            8,
        ) catch return error.VorbisAudioPacketSizeOverflow;
        if (next > capacity)
            return error.VorbisAudioPacketOutputTooSmall;
    }

    fn writeBitsUnchecked(
        self: *VorbisPacketWriter,
        value: anytype,
        bit_count: u6,
    ) void {
        const encoded: u64 = @intCast(value);
        if (!self.count_only) {
            for (0..bit_count) |index| {
                const destination_bit = self.bit_offset + index;
                const mask =
                    @as(u8, 1) << @intCast(destination_bit % 8);
                if ((encoded >> @intCast(index)) & 1 != 0)
                    self.destination[destination_bit / 8] |= mask
                else
                    self.destination[destination_bit / 8] &= ~mask;
            }
        }
        self.bit_offset += bit_count;
    }

    fn writeScalarAssumeCapacity(
        self: *VorbisPacketWriter,
        setup: VorbisSetup,
        codebook_number: u8,
        entry_number: u32,
    ) void {
        const codebook = setup.codebooks[codebook_number];
        const start: usize = @intCast(codebook.entry_offset);
        const entry = setup.codebook_entries[start + entry_number];
        if (codebook.active_entry_count == 1) {
            self.writeBitsUnchecked(0, 1);
            return;
        }
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            self.writeBitsUnchecked(
                (entry.codeword >> shift) & 1,
                1,
            );
        }
    }
};

pub fn requiredVorbisAudioPacketBytes(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !usize {
    var writer = VorbisPacketWriter.counting();
    _ = try writeVorbisAudioPacket(
        &writer,
        identification,
        setup,
        encoding,
    );
    return writer.bit_offset / 8 +
        @intFromBool(writer.bit_offset % 8 != 0);
}

pub fn encodeVorbisAudioPacket(
    destination: []u8,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !VorbisAudioPacketEncodingResult {
    var counter = VorbisPacketWriter.counting();
    _ = try writeVorbisAudioPacket(
        &counter,
        identification,
        setup,
        encoding,
    );
    const required =
        counter.bit_offset / 8 +
        @intFromBool(counter.bit_offset % 8 != 0);
    if (destination.len < required)
        return error.VorbisAudioPacketOutputTooSmall;
    try rejectVorbisAudioPacketEncodingOverlap(
        destination[0..required],
        setup,
        encoding,
    );

    var writer = VorbisPacketWriter.init(
        destination[0..required],
    );
    const header = writeVorbisAudioPacket(
        &writer,
        identification,
        setup,
        encoding,
    ) catch unreachable;
    std.debug.assert(writer.bit_offset == counter.bit_offset);
    return .{
        .bytes = writer.bytes(),
        .bit_count = writer.bit_offset,
        .header = header,
    };
}

pub fn measureVorbisAudioPacketFixedCost(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    do_not_encode_destination: []bool,
) !VorbisAudioPacketFixedCost {
    if (do_not_encode_destination.len <
        identification.channel_count)
        return error.VorbisAudioPacketSkipOutputTooSmall;
    const output = do_not_encode_destination[0..identification.channel_count];
    try rejectVorbisAudioPacketPrefixOutputOverlap(
        setup,
        encoding,
        output,
    );
    var staged = [_]bool{true} ** 255;
    var writer = VorbisPacketWriter.counting();
    const header = try writeVorbisAudioPacketPrefix(
        &writer,
        identification,
        setup,
        encoding,
        &staged,
    );
    const bit_count = std.math.cast(
        u32,
        writer.bit_offset,
    ) orelse return error.VorbisAudioPacketSizeOverflow;
    @memcpy(output, staged[0..identification.channel_count]);
    return .{
        .bit_count = bit_count,
        .header = header,
        .do_not_encode = output,
    };
}

fn writeVorbisAudioPacket(
    writer: *VorbisPacketWriter,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !VorbisAudioPacketHeader {
    var no_residue = [_]bool{true} ** 255;
    const header = try writeVorbisAudioPacketPrefix(
        writer,
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = encoding.floors,
        },
        &no_residue,
    );
    const mode = setup.modes[encoding.mode_number];
    const mapping = setup.mappings[mode.mapping];
    if (encoding.residues.len != mapping.submap_count)
        return error.InvalidVorbisAudioResidueEncoding;

    const coefficient_count = header.block_size / 2;
    for (0..mapping.submap_count) |submap_index| {
        var expected_skips = [_]bool{false} ** 255;
        var bundle_count: usize = 0;
        for (0..identification.channel_count) |channel| {
            if (mapping.channel_mux[channel] != submap_index)
                continue;
            expected_skips[bundle_count] = no_residue[channel];
            bundle_count += 1;
        }
        const residue_encoding = encoding.residues[submap_index];
        if (!std.mem.eql(
            bool,
            residue_encoding.do_not_encode,
            expected_skips[0..bundle_count],
        )) return error.InvalidVorbisAudioResidueEncoding;
        if (bundle_count == 0) {
            if (residue_encoding.classifications.len != 0 or
                residue_encoding.entries.len != 0)
                return error.InvalidVorbisAudioResidueEncoding;
            continue;
        }
        try writer.writeResidue(
            setup,
            mapping.submaps[submap_index].residue,
            coefficient_count,
            residue_encoding,
        );
    }
    return header;
}

fn writeVorbisAudioPacketPrefix(
    writer: *VorbisPacketWriter,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    no_residue: *[255]bool,
) !VorbisAudioPacketHeader {
    if (encoding.floors.len != identification.channel_count)
        return error.InvalidVorbisAudioFloorEncoding;
    const header = try writer.writeAudioHeader(
        identification,
        setup,
        encoding.mode_number,
        encoding.previous_window_flag,
        encoding.next_window_flag,
    );
    const mode = setup.modes[encoding.mode_number];
    const mapping = setup.mappings[mode.mapping];
    for (encoding.floors, 0..) |floor_encoding, channel| {
        const submap = mapping.submaps[mapping.channel_mux[channel]];
        switch (floor_encoding) {
            .zero => |value| {
                switch (setup.floors[submap.floor]) {
                    .zero => {},
                    .one => return error.InvalidVorbisAudioFloorEncoding,
                }
                try writer.writeFloorZero(
                    setup,
                    submap.floor,
                    value,
                );
                no_residue[channel] = value.amplitude == 0;
            },
            .one => |value| {
                switch (setup.floors[submap.floor]) {
                    .one => {},
                    .zero => return error.InvalidVorbisAudioFloorEncoding,
                }
                try writer.writeFloorOne(
                    setup,
                    submap.floor,
                    value,
                );
                no_residue[channel] = !value.used;
            },
        }
    }
    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (!no_residue[step.magnitude] or
            !no_residue[step.angle])
        {
            no_residue[step.magnitude] = false;
            no_residue[step.angle] = false;
        }
    }
    return header;
}

fn rejectVorbisAudioPacketPrefixOutputOverlap(
    setup: VorbisSetup,
    encoding: VorbisAudioPacketPrefixEncoding,
    output: []bool,
) !void {
    const bytes = std.mem.sliceAsBytes(output);
    rejectVorbisSetupOverlap(bytes, setup) catch |err| switch (err) {
        error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPacketEncoding,
        else => return err,
    };
    if (vorbisSliceOverlapsBytes(
        VorbisFloorPacketEncoding,
        encoding.floors,
        bytes,
    )) return error.OverlappingVorbisPacketEncoding;
    for (encoding.floors) |floor| {
        const overlap = switch (floor) {
            .zero => |value| vorbisSliceOverlapsBytes(
                u32,
                value.entries,
                bytes,
            ),
            .one => |value| vorbisSliceOverlapsBytes(
                u32,
                value.y_values,
                bytes,
            ),
        };
        if (overlap) return error.OverlappingVorbisPacketEncoding;
    }
}

fn rejectVorbisAudioPacketEncodingOverlap(
    destination: []u8,
    setup: VorbisSetup,
    encoding: VorbisAudioPacketEncoding,
) !void {
    try rejectVorbisPacketSetupOverlap(destination, setup);
    if (vorbisSliceOverlapsBytes(
        VorbisFloorPacketEncoding,
        encoding.floors,
        destination,
    ) or vorbisSliceOverlapsBytes(
        VorbisResidueEncoding,
        encoding.residues,
        destination,
    )) return error.OverlappingVorbisPacketEncoding;
    for (encoding.floors) |floor| {
        const overlap = switch (floor) {
            .zero => |value| vorbisSliceOverlapsBytes(
                u32,
                value.entries,
                destination,
            ),
            .one => |value| vorbisSliceOverlapsBytes(
                u32,
                value.y_values,
                destination,
            ),
        };
        if (overlap) return error.OverlappingVorbisPacketEncoding;
    }
    for (encoding.residues) |residue| {
        if (vorbisSliceOverlapsBytes(
            bool,
            residue.do_not_encode,
            destination,
        ) or vorbisSliceOverlapsBytes(
            u8,
            residue.classifications,
            destination,
        ) or vorbisSliceOverlapsBytes(
            u32,
            residue.entries,
            destination,
        )) return error.OverlappingVorbisPacketEncoding;
    }
}

fn rejectVorbisPacketSetupOverlap(
    destination: []u8,
    setup: VorbisSetup,
) !void {
    rejectVorbisSetupOverlap(destination, setup) catch |err| switch (err) {
        error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPacketEncoding,
        else => return err,
    };
}

fn walkVorbisResidueEncoding(
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    encoding: VorbisResidueEncoding,
    bit_count: *usize,
    entry_offset: *usize,
    writer: ?*VorbisPacketWriter,
) !void {
    const classbook = setup.codebooks[residue.classbook];
    const classwords: usize = classbook.dimensions;
    const effective_vectors: usize =
        if (residue.kind == .two)
            1
        else
            encoding.do_not_encode.len;
    for (0..8) |pass| {
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            if (pass == 0) {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        encoding.do_not_encode[vector])
                        continue;
                    const classifications = encoding.classifications[vector * shape.partition_count ..][partition..@min(
                        partition + classwords,
                        shape.partition_count,
                    )];
                    const classword =
                        findVorbisResidueClassword(
                            setup,
                            residue,
                            classifications,
                        ) orelse
                        return error.UnencodableVorbisResidueClassifications;
                    const codeword = try writableVorbisCodeword(
                        setup,
                        residue.classbook,
                        classword,
                    );
                    bit_count.* = try addVorbisPacketBits(
                        bit_count.*,
                        codeword.entry.length,
                    );
                    if (writer) |output| {
                        output.writeScalarAssumeCapacity(
                            setup,
                            residue.classbook,
                            classword,
                        );
                    }
                }
            }

            var classword_index: usize = 0;
            while (classword_index < classwords and
                partition < shape.partition_count) : (classword_index += 1)
            {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        encoding.do_not_encode[vector])
                        continue;
                    const classification = encoding.classifications[
                        vector * shape.partition_count + partition
                    ];
                    const book = residue.books[classification][pass];
                    if (book < 0) continue;
                    const codebook = setup.codebooks[@intCast(book)];
                    const vector_count =
                        @as(usize, residue.partition_size) /
                        codebook.dimensions;
                    if (vector_count >
                        encoding.entries.len -| entry_offset.*)
                        return error.InvalidVorbisResidueEncoding;
                    for (
                        encoding.entries[entry_offset.*..][0..vector_count],
                    ) |entry| {
                        const codeword = try writableVorbisCodeword(
                            setup,
                            @intCast(book),
                            entry,
                        );
                        bit_count.* = try addVorbisPacketBits(
                            bit_count.*,
                            codeword.entry.length,
                        );
                        if (writer) |output| {
                            output.writeScalarAssumeCapacity(
                                setup,
                                @intCast(book),
                                entry,
                            );
                        }
                    }
                    entry_offset.* += vector_count;
                }
                partition += 1;
            }
        }
    }
}

fn findVorbisResidueClassword(
    setup: VorbisSetup,
    residue: VorbisResidue,
    classifications: []const u8,
) ?u32 {
    const classbook = setup.codebooks[residue.classbook];
    const entries = vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    ) catch return null;
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var encoded: u32 = @intCast(entry_number);
        var omitted =
            @as(usize, classbook.dimensions) - classifications.len;
        while (omitted != 0) : (omitted -= 1)
            encoded /= residue.classification_count;
        var matches = true;
        var index = classifications.len;
        while (index != 0) {
            index -= 1;
            if (classifications[index] !=
                encoded % residue.classification_count)
            {
                matches = false;
                break;
            }
            encoded /= residue.classification_count;
        }
        if (matches) return @intCast(entry_number);
    }
    return null;
}

const WritableVorbisCodeword = struct {
    entry: VorbisCodebookEntry,
    single_entry: bool,
};

fn writableVorbisCodeword(
    setup: VorbisSetup,
    codebook_number: u8,
    entry_number: u32,
) !WritableVorbisCodeword {
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    if (entry_number >= entries.len or
        codebook.active_entry_count == 0 or
        codebook.active_entry_count > entries.len)
        return error.InvalidVorbisSetupState;
    const entry = entries[entry_number];
    if (entry.length == 0 or entry.length > 32)
        return error.InvalidVorbisCodebookEntry;
    const single_entry = codebook.active_entry_count == 1;
    if (single_entry) {
        if (entry.length != 1)
            return error.InvalidVorbisSetupState;
    } else {
        try validateVorbisCodewordForWrite(
            setup,
            codebook,
            entry_number,
            entry,
        );
    }
    return .{
        .entry = entry,
        .single_entry = single_entry,
    };
}

fn findVorbisFloorOneClassword(
    setup: VorbisSetup,
    class: VorbisFloorOneClass,
    values: []const u32,
) !u32 {
    const masterbook_number: u8 = @intCast(class.masterbook);
    const masterbook = setup.codebooks[masterbook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        masterbook.entry_offset,
        masterbook.entries,
    );
    const mask =
        (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        var classword: u32 = @intCast(entry_number);
        var compatible = true;
        for (values) |value| {
            const book = class.subclass_books[classword & mask];
            classword >>= @intCast(class.subclass_bits);
            if (book < 0) {
                compatible = compatible and value == 0;
            } else {
                _ = writableVorbisCodeword(
                    setup,
                    @intCast(book),
                    value,
                ) catch {
                    compatible = false;
                    continue;
                };
            }
        }
        if (compatible) return @intCast(entry_number);
    }
    return error.UnencodableVorbisFloorValue;
}

fn addVorbisPacketBits(total: usize, count: usize) !usize {
    return std.math.add(
        usize,
        total,
        count,
    ) catch error.VorbisAudioPacketSizeOverflow;
}

fn validateVorbisCodewordForWrite(
    setup: VorbisSetup,
    codebook: VorbisCodebook,
    entry_number: u32,
    entry: VorbisCodebookEntry,
) !void {
    if (codebook.tree_node_count !=
        codebook.active_entry_count - 1)
        return error.InvalidVorbisSetupState;
    const nodes = try vorbisSetupSlice(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        codebook.tree_node_offset,
        codebook.tree_node_count,
    );
    var node_index: u32 = 0;
    for (0..entry.length) |depth| {
        if (node_index >= nodes.len)
            return error.InvalidVorbisSetupState;
        const shift: u5 = @intCast(entry.length - 1 - depth);
        const bit: usize = @intCast(
            (entry.codeword >> shift) & 1,
        );
        const branch = nodes[node_index].branches[bit];
        if (depth + 1 == entry.length) {
            if (branch != huffman_leaf_flag | entry_number)
                return error.InvalidVorbisSetupState;
        } else {
            if (branch & huffman_leaf_flag != 0 or
                branch >= nodes.len)
                return error.InvalidVorbisSetupState;
            node_index = branch;
        }
    }
}

pub const VorbisPacketReader = struct {
    packet: []const u8,
    bit_offset: usize = 0,

    pub fn init(packet: []const u8, bit_offset: usize) !VorbisPacketReader {
        if (bit_offset > packet.len * 8)
            return error.InvalidVorbisPacketBitOffset;
        return .{ .packet = packet, .bit_offset = bit_offset };
    }

    /// Decode one scalar entry. Failures preserve the cursor.
    pub fn decodeScalar(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        codebook_number: u8,
    ) !u32 {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        const start = std.math.cast(usize, codebook.entry_offset) orelse
            return error.InvalidVorbisSetupState;
        if (codebook.entries == 0 or
            codebook.active_entry_count == 0 or
            codebook.active_entry_count > codebook.entries or
            start > setup.codebook_entries.len or
            codebook.entries > setup.codebook_entries.len - start)
            return error.InvalidVorbisSetupState;
        const entries =
            setup.codebook_entries[start..][0..codebook.entries];

        var trial = VorbisBitReader{
            .bytes = self.packet,
            .bit_offset = self.bit_offset,
        };
        if (codebook.active_entry_count == 1) {
            _ = readVorbisAudioBits(&trial, 1) catch |err| return err;
            for (entries, 0..) |entry, index| {
                if (entry.length != 0) {
                    self.bit_offset = trial.bit_offset;
                    return @intCast(index);
                }
            }
            return error.InvalidVorbisSetupState;
        }

        if (codebook.tree_node_count != codebook.active_entry_count - 1)
            return error.InvalidVorbisSetupState;
        const node_start =
            std.math.cast(usize, codebook.tree_node_offset) orelse
            return error.InvalidVorbisSetupState;
        if (codebook.tree_node_count >
            setup.huffman_nodes.len -| node_start)
            return error.InvalidVorbisSetupState;
        const nodes = setup.huffman_nodes[node_start..][0..codebook.tree_node_count];
        var node_index: u32 = 0;
        for (0..32) |_| {
            const bit =
                readVorbisAudioBits(&trial, 1) catch |err| return err;
            const branch = nodes[node_index].branches[bit];
            if (branch == invalid_huffman_branch)
                return error.InvalidVorbisCodeword;
            if (branch & huffman_leaf_flag != 0) {
                const entry_index = branch & ~huffman_leaf_flag;
                if (entry_index >= entries.len or
                    entries[entry_index].length == 0)
                    return error.InvalidVorbisSetupState;
                self.bit_offset = trial.bit_offset;
                return entry_index;
            }
            if (branch >= nodes.len)
                return error.InvalidVorbisSetupState;
            node_index = branch;
        }
        return error.InvalidVorbisCodeword;
    }

    /// Decode one VQ entry. Failures preserve the cursor and output.
    pub fn decodeVector(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        codebook_number: u8,
        output: []Float,
    ) !void {
        if (Float != f32 and Float != f64)
            @compileError("Vorbis vectors require f32 or f64 output");
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (output.len < codebook.dimensions)
            return error.VorbisVectorOutputTooSmall;
        try self.decodeVectorPrefix(
            Float,
            setup,
            codebook_number,
            output[0..codebook.dimensions],
        );
    }

    fn decodeVectorPrefix(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        codebook_number: u8,
        output: []Float,
    ) !void {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (output.len > codebook.dimensions)
            return error.InvalidVorbisSetupState;
        var cursor = try self.decodeVectorCursor(setup, codebook_number);
        for (output) |*value| value.* = @floatCast(cursor.next());
    }

    fn decodeVectorCursor(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        codebook_number: u8,
    ) !VorbisVectorCursor {
        if (codebook_number >= setup.codebooks.len)
            return error.InvalidVorbisCodebookNumber;
        const codebook = setup.codebooks[codebook_number];
        if (codebook.lookup_type == 0)
            return error.VorbisCodebookHasNoVectorLookup;
        if (codebook.lookup_type > 2 or
            codebook.dimensions == 0 or
            codebook.entries == 0)
            return error.InvalidVorbisSetupState;
        const start =
            std.math.cast(usize, codebook.multiplicand_offset) orelse
            return error.InvalidVorbisSetupState;
        if (start > setup.codebook_multiplicands.len or
            codebook.multiplicand_count >
                setup.codebook_multiplicands.len - start)
            return error.InvalidVorbisSetupState;
        const multiplicands = setup.codebook_multiplicands[start..][0..@intCast(codebook.multiplicand_count)];
        if (multiplicands.len == 0)
            return error.InvalidVorbisSetupState;
        const expected_multiplicands: u64 = if (codebook.lookup_type == 1)
            vorbisLookupOneValues(codebook.entries, codebook.dimensions)
        else
            @as(u64, codebook.entries) * codebook.dimensions;
        if (codebook.multiplicand_count != expected_multiplicands)
            return error.InvalidVorbisSetupState;

        const entry = try self.decodeScalar(setup, codebook_number);
        return .{
            .codebook = codebook,
            .multiplicands = multiplicands,
            .entry = entry,
            .explicit_offset = @as(u64, entry) * codebook.dimensions,
        };
    }

    /// Truncation consumes the packet remainder and returns an unused floor.
    pub fn decodeFloorZero(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        floor_number: u8,
        coefficients: []f64,
    ) !VorbisFloorZeroPacket {
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .zero => |value| value,
            .one => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorZeroState(floor, setup.codebooks);
        if (coefficients.len < floor.order)
            return error.VorbisFloorOutputTooSmall;

        var trial = self.*;
        const amplitude = trial.readBits64(floor.amplitude_bits) catch |err|
            return self.finishTruncatedFloorZero(err);
        if (amplitude == 0) {
            self.bit_offset = trial.bit_offset;
            return .{ .used = false };
        }
        const book_number = trial.readBits(
            vorbisILog(floor.book_count),
        ) catch |err| return self.finishTruncatedFloorZero(err);
        if (book_number >= floor.book_count)
            return error.InvalidVorbisFloorBookNumber;
        const codebook_number = floor.books[book_number];
        const dimensions = setup.codebooks[codebook_number].dimensions;

        var decoded: [255]f64 = undefined;
        var decoded_count: usize = 0;
        var last: f64 = 0;
        while (decoded_count < floor.order) {
            const count = @min(
                @as(usize, dimensions),
                @as(usize, floor.order) - decoded_count,
            );
            trial.decodeVectorPrefix(
                f64,
                setup,
                codebook_number,
                decoded[decoded_count..][0..count],
            ) catch |err| return self.finishTruncatedFloorZero(err);
            for (decoded[decoded_count..][0..count]) |*value| {
                value.* += last;
            }
            last = decoded[decoded_count + count - 1];
            decoded_count += count;
        }
        @memcpy(coefficients[0..floor.order], decoded[0..floor.order]);
        self.bit_offset = trial.bit_offset;
        return .{
            .used = true,
            .amplitude = amplitude,
            .coefficient_count = floor.order,
        };
    }

    /// Truncation consumes the packet remainder and returns an unused floor.
    pub fn decodeFloorOne(
        self: *VorbisPacketReader,
        setup: VorbisSetup,
        floor_number: u8,
        y_values: []u32,
    ) !VorbisFloorOnePacket {
        if (floor_number >= setup.floors.len)
            return error.InvalidVorbisFloorNumber;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.InvalidVorbisFloorType,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        if (y_values.len < floor.point_count)
            return error.VorbisFloorOutputTooSmall;

        var trial = self.*;
        const nonzero = trial.readBits(1) catch |err|
            return self.finishTruncatedFloorOne(err);
        if (nonzero == 0) {
            self.bit_offset = trial.bit_offset;
            return .{ .used = false };
        }

        const ranges = [_]u16{ 256, 128, 86, 64 };
        const range = ranges[floor.multiplier - 1];
        const value_bits = vorbisILog(range - 1);
        var decoded = [_]u32{0} ** 65;
        decoded[0] = trial.readBits(value_bits) catch |err|
            return self.finishTruncatedFloorOne(err);
        decoded[1] = trial.readBits(value_bits) catch |err|
            return self.finishTruncatedFloorOne(err);
        var offset: usize = 2;
        for (floor.partition_classes[0..floor.partition_count]) |class_index| {
            const class = floor.classes[class_index];
            var class_value: u32 = 0;
            if (class.subclass_bits != 0) {
                class_value = trial.decodeScalar(
                    setup,
                    @intCast(class.masterbook),
                ) catch |err| return self.finishTruncatedFloorOne(err);
            }
            const subclass_mask =
                (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
            for (0..class.dimensions) |_| {
                const book =
                    class.subclass_books[class_value & subclass_mask];
                class_value >>= @intCast(class.subclass_bits);
                decoded[offset] = if (book < 0)
                    0
                else
                    trial.decodeScalar(
                        setup,
                        @intCast(book),
                    ) catch |err|
                        return self.finishTruncatedFloorOne(err);
                offset += 1;
            }
        }
        if (offset != floor.point_count)
            return error.InvalidVorbisSetupState;
        @memcpy(y_values[0..floor.point_count], decoded[0..floor.point_count]);
        self.bit_offset = trial.bit_offset;
        return .{
            .used = true,
            .value_count = floor.point_count,
        };
    }

    /// End-of-packet returns decoded partial residue and consumes the remainder.
    pub fn decodeResidue(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue_number: u8,
        do_not_decode: []const bool,
        outputs: []const []Float,
        classification_scratch: []u8,
    ) !VorbisResiduePacket {
        if (Float != f32 and Float != f64)
            @compileError("Vorbis residue requires f32 or f64 output");
        if (residue_number >= setup.residues.len)
            return error.InvalidVorbisResidueNumber;
        if (outputs.len == 0 or outputs.len > 255 or
            do_not_decode.len != outputs.len)
            return error.InvalidVorbisResidueBundle;
        const vector_length = outputs[0].len;
        for (outputs, 0..) |output, index| {
            if (output.len != vector_length)
                return error.InvalidVorbisResidueBundle;
            for (outputs[0..index]) |earlier| {
                if (vorbisSlicesOverlap(Float, output, earlier))
                    return error.OverlappingVorbisResidueOutput;
            }
            if (vorbisSliceOverlapsBytes(
                Float,
                output,
                classification_scratch,
            )) return error.OverlappingVorbisResidueScratch;
        }

        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        const shape = try vorbisResidueShape(
            residue,
            vector_length,
            outputs.len,
        );
        if (classification_scratch.len < shape.required_classifications)
            return error.VorbisResidueScratchTooSmall;

        for (outputs) |output| @memset(output, 0);
        if (shape.partition_count == 0) return .{};
        if (residue.kind == .two) {
            var all_skipped = true;
            for (do_not_decode) |skip| all_skipped = all_skipped and skip;
            if (all_skipped) return .{};
        }

        var trial = self.*;
        trial.decodeResidueInternal(
            Float,
            setup,
            residue,
            shape,
            do_not_decode,
            outputs,
            classification_scratch,
        ) catch |err| {
            if (err == error.TruncatedVorbisAudioPacket) {
                self.bit_offset = self.packet.len * 8;
                return .{ .truncated = true };
            }
            for (outputs) |output| @memset(output, 0);
            return err;
        };
        self.bit_offset = trial.bit_offset;
        return .{};
    }

    fn decodeResidueInternal(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue: VorbisResidue,
        shape: VorbisResidueShape,
        do_not_decode: []const bool,
        outputs: []const []Float,
        classifications: []u8,
    ) !void {
        const classbook = setup.codebooks[residue.classbook];
        const classwords: usize = classbook.dimensions;
        const effective_vectors: usize =
            if (residue.kind == .two) 1 else outputs.len;
        for (0..8) |pass| {
            var partition: usize = 0;
            while (partition < shape.partition_count) {
                if (pass == 0) {
                    for (0..effective_vectors) |vector| {
                        if (residue.kind != .two and do_not_decode[vector])
                            continue;
                        var encoded = try self.decodeScalar(
                            setup,
                            residue.classbook,
                        );
                        var classword = classwords;
                        while (classword != 0) {
                            classword -= 1;
                            const target = partition + classword;
                            if (target < shape.partition_count) {
                                classifications[
                                    vector * shape.partition_count + target
                                ] = @intCast(
                                    encoded % residue.classification_count,
                                );
                            }
                            encoded /= residue.classification_count;
                        }
                    }
                }

                var classword: usize = 0;
                while (classword < classwords and
                    partition < shape.partition_count) : (classword += 1)
                {
                    for (0..effective_vectors) |vector| {
                        if (residue.kind != .two and do_not_decode[vector])
                            continue;
                        const classification = classifications[
                            vector * shape.partition_count + partition
                        ];
                        const book = residue.books[classification][pass];
                        if (book >= 0) {
                            try self.decodeResiduePartition(
                                Float,
                                setup,
                                residue,
                                @intCast(book),
                                vector,
                                shape.begin +
                                    partition *
                                        @as(usize, residue.partition_size),
                                outputs,
                            );
                        }
                    }
                    partition += 1;
                }
            }
        }
    }

    fn decodeResiduePartition(
        self: *VorbisPacketReader,
        comptime Float: type,
        setup: VorbisSetup,
        residue: VorbisResidue,
        codebook_number: u8,
        vector: usize,
        partition_offset: usize,
        outputs: []const []Float,
    ) !void {
        const dimensions: usize =
            setup.codebooks[codebook_number].dimensions;
        const partition_size: usize = residue.partition_size;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            var decoded =
                try self.decodeVectorCursor(setup, codebook_number);
            for (0..dimensions) |component| {
                const within_partition = switch (residue.kind) {
                    .zero => entry_index +
                        component * vector_count,
                    .one, .two => entry_index * dimensions + component,
                };
                const flat_index =
                    partition_offset + within_partition;
                if (residue.kind == .two) {
                    const channel = flat_index % outputs.len;
                    const sample = flat_index / outputs.len;
                    outputs[channel][sample] +=
                        @as(Float, @floatCast(decoded.next()));
                } else {
                    outputs[vector][flat_index] +=
                        @as(Float, @floatCast(decoded.next()));
                }
            }
        }
    }

    fn finishTruncatedFloorZero(
        self: *VorbisPacketReader,
        err: anyerror,
    ) anyerror!VorbisFloorZeroPacket {
        if (err != error.TruncatedVorbisAudioPacket) return err;
        self.bit_offset = self.packet.len * 8;
        return .{ .used = false, .truncated = true };
    }

    fn readBits(self: *VorbisPacketReader, bit_count: u6) !u32 {
        var reader = VorbisBitReader{
            .bytes = self.packet,
            .bit_offset = self.bit_offset,
        };
        const value = try readVorbisAudioBits(&reader, bit_count);
        self.bit_offset = reader.bit_offset;
        return value;
    }

    fn readBits64(self: *VorbisPacketReader, bit_count: u6) !u64 {
        if (@as(usize, bit_count) > self.packet.len * 8 -| self.bit_offset)
            return error.TruncatedVorbisAudioPacket;
        var value: u64 = 0;
        for (0..bit_count) |index| {
            const source_bit = self.bit_offset + index;
            value |= @as(u64, (self.packet[source_bit / 8] >>
                @intCast(source_bit % 8)) & 1) << @intCast(index);
        }
        self.bit_offset += bit_count;
        return value;
    }

    fn finishTruncatedFloorOne(
        self: *VorbisPacketReader,
        err: anyerror,
    ) anyerror!VorbisFloorOnePacket {
        if (err != error.TruncatedVorbisAudioPacket) return err;
        self.bit_offset = self.packet.len * 8;
        return .{ .used = false, .truncated = true };
    }
};

pub const VorbisFloorZeroPacket = struct {
    used: bool,
    truncated: bool = false,
    amplitude: u64 = 0,
    coefficient_count: u8 = 0,
};

pub const VorbisFloorOnePacket = struct {
    used: bool,
    truncated: bool = false,
    value_count: u7 = 0,
};

pub const VorbisResiduePacket = struct {
    truncated: bool = false,
};

const VorbisResidueShape = struct {
    begin: usize,
    partition_count: usize,
    required_classifications: usize,
};

/// Returns the caller-owned classification scratch required by `decodeResidue`.
pub fn requiredVorbisResidueClassifications(
    residue: VorbisResidue,
    vector_length: usize,
    vector_count: usize,
) !usize {
    return (try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    )).required_classifications;
}

pub fn requiredVorbisResidueQuantizationScratch(
    setup: VorbisSetup,
    residue_number: u8,
    vector_length: usize,
    vector_count: usize,
) !VorbisResidueQuantizationScratchRequirements {
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    );
    var maximum_dimensions: usize = 0;
    for (
        residue.books[0..residue.classification_count],
    ) |passes| {
        for (passes) |book_number| {
            if (book_number >= 0) {
                maximum_dimensions = @max(
                    maximum_dimensions,
                    setup.codebooks[@intCast(book_number)].dimensions,
                );
            }
        }
    }
    return .{
        .partition_values = residue.partition_size,
        .vector_values = maximum_dimensions,
        .classifications = shape.required_classifications,
    };
}

pub fn requiredVorbisResidueQuantizationEntries(
    setup: VorbisSetup,
    residue_number: u8,
    vector_length: usize,
    vector_count: usize,
) !usize {
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        vector_count,
    );
    if (shape.partition_count == 0) return 0;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    var classification_entries = [_]usize{0} ** 64;
    for (0..residue.classification_count) |classification| {
        for (0..8) |pass| {
            const book_number = residue.books[classification][pass];
            if (book_number < 0) continue;
            const dimensions: usize =
                setup.codebooks[@intCast(book_number)].dimensions;
            classification_entries[classification] = std.math.add(
                usize,
                classification_entries[classification],
                @as(usize, residue.partition_size) / dimensions,
            ) catch return error.VorbisResidueEntryCountOverflow;
        }
    }

    const classword_dimensions: usize = classbook.dimensions;
    var entries_per_vector: usize = 0;
    var partition: usize = 0;
    while (partition < shape.partition_count) {
        const group_count = @min(
            classword_dimensions,
            shape.partition_count - partition,
        );
        var maximum_group_entries: ?usize = null;
        for (classbook_entries, 0..) |entry, entry_number| {
            if (entry.length == 0) continue;
            var encoded: u32 = @intCast(entry_number);
            var omitted = classword_dimensions - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var group_entries: usize = 0;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                const classification: usize =
                    encoded % residue.classification_count;
                encoded /= residue.classification_count;
                group_entries = std.math.add(
                    usize,
                    group_entries,
                    classification_entries[classification],
                ) catch return error.VorbisResidueEntryCountOverflow;
            }
            maximum_group_entries = @max(
                maximum_group_entries orelse 0,
                group_entries,
            );
        }
        entries_per_vector = std.math.add(
            usize,
            entries_per_vector,
            maximum_group_entries orelse
                return error.InvalidVorbisSetupState,
        ) catch return error.VorbisResidueEntryCountOverflow;
        partition += group_count;
    }
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else vector_count;
    return std.math.mul(
        usize,
        entries_per_vector,
        effective_vectors,
    ) catch return error.VorbisResidueEntryCountOverflow;
}

pub fn quantizeVorbisResidue(
    comptime Float: type,
    setup: VorbisSetup,
    residue_number: u8,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    scratch: VorbisResidueQuantizationScratch(Float),
    classification_destination: []u8,
    entry_destination: []u32,
) !VorbisResidueQuantization {
    if (inputs.len == 0 or inputs.len > 255 or
        do_not_encode.len != inputs.len)
        return error.InvalidVorbisResidueBundle;
    const vector_length = inputs[0].len;
    for (inputs) |input| {
        if (input.len != vector_length)
            return error.InvalidVorbisResidueBundle;
        for (input) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisQuantizationTarget;
        }
    }
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        inputs.len,
    );
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            residue_number,
            vector_length,
            inputs.len,
        );
    var all_skipped = true;
    for (do_not_encode) |skip| all_skipped = all_skipped and skip;
    const type_two_skipped = residue.kind == .two and all_skipped;
    const classification_count =
        if (type_two_skipped) 0 else shape.required_classifications;
    if (classification_destination.len < classification_count)
        return error.VorbisResidueClassificationOutputTooSmall;
    if (classification_count == 0) {
        return .{
            .encoding = .{
                .do_not_encode = do_not_encode,
                .classifications = classification_destination[0..0],
                .entries = entry_destination[0..0],
            },
            .squared_error = 0,
        };
    }
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len < requirements.classifications)
        return error.VorbisResidueQuantizationScratchTooSmall;
    try rejectVorbisResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        scratch,
        classification_destination,
        entry_destination,
    );

    const planned_classifications =
        scratch.classifications[0..classification_count];
    try selectVorbisResidueClassifications(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        planned_classifications,
    );
    const entry_count = try countVorbisResidueQuantizedEntries(
        setup,
        residue,
        shape,
        do_not_encode,
        planned_classifications,
    );
    if (entry_destination.len < entry_count)
        return error.VorbisResidueEntryOutputTooSmall;

    const classifications =
        classification_destination[0..classification_count];
    const entries = entry_destination[0..entry_count];

    const total_error = try measureVorbisResidueQuantization(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        planned_classifications,
    );
    @memcpy(classifications, planned_classifications);
    var entry_offset: usize = 0;
    assembleVorbisResidueEntries(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        scratch.partition[0..requirements.partition_values],
        scratch.vector[0..requirements.vector_values],
        classifications,
        entries,
        &entry_offset,
    ) catch unreachable;
    std.debug.assert(entry_offset == entries.len);
    return .{
        .encoding = .{
            .do_not_encode = do_not_encode,
            .classifications = classifications,
            .entries = entries,
        },
        .squared_error = @floatCast(total_error),
    };
}

pub fn quantizeVorbisResidueAdaptive(
    comptime Float: type,
    setup: VorbisSetup,
    residue_number: u8,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    config: VorbisAdaptiveResidueConfig,
    scratch: VorbisAdaptiveResidueScratch(Float),
    classification_destination: []u8,
    entry_destination: []u32,
) !VorbisAdaptiveResidueQuantization {
    if (Float != f32 and Float != f64)
        @compileError("adaptive Vorbis quantization requires f32 or f64");
    if (config.maximum_iterations == 0 or
        config.maximum_iterations > 64 or
        !std.math.isFinite(config.initial_lambda) or
        config.initial_lambda <= 0)
        return error.InvalidVorbisAdaptiveResidueConfig;
    if (inputs.len == 0 or inputs.len > 255 or
        do_not_encode.len != inputs.len or
        noise_thresholds.len != inputs.len)
        return error.InvalidVorbisResidueBundle;
    const vector_length = inputs[0].len;
    for (inputs, noise_thresholds) |input, thresholds| {
        if (input.len != vector_length or
            thresholds.len != vector_length)
            return error.InvalidVorbisResidueBundle;
        for (input, thresholds) |value, threshold| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisQuantizationTarget;
            if (!std.math.isFinite(threshold) or threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
        }
    }
    if (residue_number >= setup.residues.len)
        return error.InvalidVorbisResidueNumber;
    const residue = setup.residues[residue_number];
    try validateVorbisResidueState(residue, setup);
    const shape = try vorbisResidueShape(
        residue,
        vector_length,
        inputs.len,
    );
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            residue_number,
            vector_length,
            inputs.len,
        );
    var all_skipped = true;
    for (do_not_encode) |skip| all_skipped = all_skipped and skip;
    const classification_count =
        if (residue.kind == .two and all_skipped)
            0
        else
            shape.required_classifications;
    if (classification_destination.len < classification_count)
        return error.VorbisResidueClassificationOutputTooSmall;
    if (classification_count == 0) {
        return .{
            .encoding = .{
                .do_not_encode = do_not_encode,
                .classifications = classification_destination[0..0],
                .entries = entry_destination[0..0],
            },
            .squared_error = 0,
            .weighted_squared_error = 0,
            .audible_excess_power = 0,
            .encoded_bits = 0,
            .budget_met = true,
            .lambda = 0,
            .iterations = 0,
        };
    }
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len < requirements.classifications or
        scratch.best_classifications.len < requirements.classifications)
        return error.VorbisResidueQuantizationScratchTooSmall;
    try rejectVorbisAdaptiveResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        noise_thresholds,
        scratch,
        classification_destination,
        entry_destination,
    );

    const partition_scratch =
        scratch.partition[0..requirements.partition_values];
    const vector_scratch =
        scratch.vector[0..requirements.vector_values];
    const trial_classifications =
        scratch.classifications[0..classification_count];
    const best_classifications =
        scratch.best_classifications[0..classification_count];

    var iterations: u8 = 1;
    var selected = try planVorbisAdaptiveResidueCandidate(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        trial_classifications,
        0,
    );
    @memcpy(best_classifications, trial_classifications);
    if (selected.encoded_bits > config.target_bits) {
        var lower_lambda: f64 = 0;
        var upper_lambda: ?f64 = null;
        var lambda = config.initial_lambda;
        while (iterations < config.maximum_iterations and
            upper_lambda == null)
        {
            const candidate = try planVorbisAdaptiveResidueCandidate(
                Float,
                setup,
                residue,
                shape,
                do_not_encode,
                inputs,
                noise_thresholds,
                partition_scratch,
                vector_scratch,
                trial_classifications,
                lambda,
            );
            iterations += 1;
            if (candidate.encoded_bits <= config.target_bits) {
                upper_lambda = lambda;
                selected = candidate;
                @memcpy(best_classifications, trial_classifications);
            } else {
                lower_lambda = lambda;
                if (candidate.encoded_bits < selected.encoded_bits or
                    (candidate.encoded_bits == selected.encoded_bits and
                        candidate.metrics.weighted_squared_error <
                            selected.metrics.weighted_squared_error))
                {
                    selected = candidate;
                    @memcpy(best_classifications, trial_classifications);
                }
                lambda *= 2;
                if (!std.math.isFinite(lambda)) break;
            }
        }
        if (upper_lambda) |initial_upper| {
            var upper = initial_upper;
            while (iterations < config.maximum_iterations) {
                const midpoint = lower_lambda +
                    (upper - lower_lambda) / 2;
                if (midpoint == lower_lambda or midpoint == upper)
                    break;
                const candidate =
                    try planVorbisAdaptiveResidueCandidate(
                        Float,
                        setup,
                        residue,
                        shape,
                        do_not_encode,
                        inputs,
                        noise_thresholds,
                        partition_scratch,
                        vector_scratch,
                        trial_classifications,
                        midpoint,
                    );
                iterations += 1;
                if (candidate.encoded_bits <= config.target_bits) {
                    upper = midpoint;
                    if (candidate.metrics.weighted_squared_error <
                        selected.metrics.weighted_squared_error or
                        (candidate.metrics.weighted_squared_error ==
                            selected.metrics.weighted_squared_error and
                            candidate.encoded_bits >
                                selected.encoded_bits))
                    {
                        selected = candidate;
                        @memcpy(
                            best_classifications,
                            trial_classifications,
                        );
                    }
                } else {
                    lower_lambda = midpoint;
                }
            }
        }
    }

    const entry_count = try countVorbisResidueQuantizedEntries(
        setup,
        residue,
        shape,
        do_not_encode,
        best_classifications,
    );
    if (entry_destination.len < entry_count)
        return error.VorbisResidueEntryOutputTooSmall;
    const classifications =
        classification_destination[0..classification_count];
    const entries = entry_destination[0..entry_count];
    @memcpy(classifications, best_classifications);
    var entry_offset: usize = 0;
    assembleVorbisResidueEntries(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        partition_scratch,
        vector_scratch,
        classifications,
        entries,
        &entry_offset,
    ) catch unreachable;
    std.debug.assert(entry_offset == entries.len);
    return .{
        .encoding = .{
            .do_not_encode = do_not_encode,
            .classifications = classifications,
            .entries = entries,
        },
        .squared_error = @floatCast(selected.metrics.squared_error),
        .weighted_squared_error = @floatCast(
            selected.metrics.weighted_squared_error,
        ),
        .audible_excess_power = @floatCast(
            selected.metrics.audible_excess_power,
        ),
        .encoded_bits = selected.encoded_bits,
        .budget_met = selected.encoded_bits <= config.target_bits,
        .lambda = selected.lambda,
        .iterations = iterations,
    };
}

pub fn requiredVorbisCouplingScratch(
    channel_count: usize,
    vector_length: usize,
) !usize {
    if (channel_count == 0 or channel_count > 255)
        return error.InvalidVorbisChannelBundle;
    return std.math.mul(usize, channel_count, vector_length) catch
        return error.InvalidVorbisChannelBundle;
}

/// Applies retained channel coupling through caller-owned transactional scratch.
pub fn forwardCoupleVorbisChannels(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []Float,
    scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis channel coupling requires f32 or f64 vectors");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    for (channels, 0..) |channel, channel_index| {
        if (channel.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (channels[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(Float, channel, earlier))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(Float, channel, scratch))
            return error.OverlappingVorbisCouplingScratch;
        for (channel) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
        }
        @memcpy(
            scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
    }

    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude = scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle = scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (magnitude, angle) |*magnitude_value, *angle_value| {
            const first = magnitude_value.*;
            const second = angle_value.*;
            const first_dominates =
                @abs(first) > @abs(second);
            const coupled = if (first_dominates)
                .{
                    first,
                    if (first > 0)
                        first - second
                    else
                        second - first,
                }
            else
                .{
                    second,
                    if (second > 0)
                        first - second
                    else
                        second - first,
                };
            if (!std.math.isFinite(coupled[0]) or
                !std.math.isFinite(coupled[1]))
                return error.InvalidVorbisChannelValue;
            magnitude_value.* = coupled[0];
            angle_value.* = coupled[1];
        }
    }
    for (channels, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

/// Keeps inverse coupling within its continuous branch and the original bounds.
pub fn forwardCoupleVorbisNoiseThresholds(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []const Float,
    thresholds: []const []Float,
    value_scratch: []Float,
    threshold_scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis noise thresholds require f32 or f64");
    if (channels.len == 0 or channels.len > 255 or
        thresholds.len != channels.len)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (value_scratch.len < required or
        threshold_scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    if (vorbisSlicesOverlap(
        Float,
        value_scratch,
        threshold_scratch,
    )) return error.OverlappingVorbisCouplingScratch;
    for (channels, thresholds, 0..) |
        channel,
        channel_thresholds,
        channel_index,
    | {
        if (channel.len != vector_length or
            channel_thresholds.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (thresholds[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                channel_thresholds,
                earlier,
            ))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(
            Float,
            channel_thresholds,
            value_scratch,
        ) or vorbisSlicesOverlap(
            Float,
            channel_thresholds,
            threshold_scratch,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            channel_thresholds,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            value_scratch,
        ) or vorbisConstSlicesOverlap(
            Float,
            channel,
            threshold_scratch,
        ))
            return error.OverlappingVorbisCouplingScratch;
        for (channel, channel_thresholds) |value, threshold| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
            if (!std.math.isFinite(threshold) or threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
        }
        @memcpy(
            value_scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
        @memcpy(
            threshold_scratch[channel_index * vector_length ..][0..vector_length],
            channel_thresholds,
        );
    }

    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude_values =
            value_scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle_values =
            value_scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        const magnitude_thresholds =
            threshold_scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle_thresholds =
            threshold_scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (
            magnitude_values,
            angle_values,
            magnitude_thresholds,
            angle_thresholds,
        ) |
            *magnitude_value,
            *angle_value,
            *magnitude_threshold,
            *angle_threshold,
        | {
            const first = magnitude_value.*;
            const second = angle_value.*;
            const first_dominates = @abs(first) > @abs(second);
            const coupled_magnitude = if (first_dominates)
                first
            else
                second;
            const coupled_angle = if (first_dominates)
                if (first > 0) first - second else second - first
            else if (second > 0)
                first - second
            else
                second - first;
            var coupled_threshold = @min(
                magnitude_threshold.*,
                angle_threshold.*,
            ) / 2;
            if (coupled_angle != 0) {
                coupled_threshold = @min(
                    coupled_threshold,
                    @abs(coupled_magnitude) / 2,
                );
            }
            if (!std.math.isFinite(coupled_magnitude) or
                !std.math.isFinite(coupled_angle))
                return error.InvalidVorbisChannelValue;
            if (!std.math.isFinite(coupled_threshold) or
                coupled_threshold <= 0)
                return error.InvalidVorbisNoiseThreshold;
            magnitude_value.* = coupled_magnitude;
            angle_value.* = coupled_angle;
            magnitude_threshold.* = coupled_threshold;
            angle_threshold.* = coupled_threshold;
        }
    }
    for (thresholds, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            threshold_scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

/// Inverts retained channel coupling through caller-owned transactional scratch.
pub fn inverseCoupleVorbisChannels(
    comptime Float: type,
    mapping: VorbisMapping,
    channels: []const []Float,
    scratch: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis channel coupling requires f32 or f64 vectors");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    const vector_length = channels[0].len;
    const required = try requiredVorbisCouplingScratch(
        channels.len,
        vector_length,
    );
    if (scratch.len < required)
        return error.VorbisCouplingScratchTooSmall;
    for (channels, 0..) |channel, channel_index| {
        if (channel.len != vector_length)
            return error.InvalidVorbisChannelBundle;
        for (channels[0..channel_index]) |earlier| {
            if (vorbisSlicesOverlap(Float, channel, earlier))
                return error.OverlappingVorbisChannelOutput;
        }
        if (vorbisSlicesOverlap(Float, channel, scratch))
            return error.OverlappingVorbisCouplingScratch;
        for (channel) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisChannelValue;
        }
        @memcpy(
            scratch[channel_index * vector_length ..][0..vector_length],
            channel,
        );
    }

    var remaining: usize = mapping.coupling_step_count;
    while (remaining != 0) {
        remaining -= 1;
        const step = mapping.coupling_steps[remaining];
        if (step.magnitude >= channels.len or
            step.angle >= channels.len or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
        const magnitude = scratch[@as(usize, step.magnitude) * vector_length ..][0..vector_length];
        const angle = scratch[@as(usize, step.angle) * vector_length ..][0..vector_length];
        for (magnitude, angle) |*magnitude_value, *angle_value| {
            const coupled_magnitude = magnitude_value.*;
            const coupled_angle = angle_value.*;
            const decoded = if (coupled_magnitude > 0)
                if (coupled_angle > 0)
                    .{
                        coupled_magnitude,
                        coupled_magnitude - coupled_angle,
                    }
                else
                    .{
                        coupled_magnitude + coupled_angle,
                        coupled_magnitude,
                    }
            else if (coupled_angle > 0)
                .{
                    coupled_magnitude,
                    coupled_magnitude + coupled_angle,
                }
            else
                .{
                    coupled_magnitude - coupled_angle,
                    coupled_magnitude,
                };
            if (!std.math.isFinite(decoded[0]) or
                !std.math.isFinite(decoded[1]))
                return error.InvalidVorbisChannelValue;
            magnitude_value.* = decoded[0];
            angle_value.* = decoded[1];
        }
    }
    for (channels, 0..) |channel, channel_index| {
        @memcpy(
            channel,
            scratch[channel_index * vector_length ..][0..vector_length],
        );
    }
}

pub const VorbisAudioPacketHeader = struct {
    mode_number: u8,
    large_block: bool,
    previous_window_flag: ?bool,
    next_window_flag: ?bool,
    block_size: u16,
    payload_bit_offset: usize,
};

pub fn inferVorbisMissingPacketLargeBlock(
    identification: VorbisIdentification,
    following: VorbisAudioPacketHeader,
) !bool {
    if (identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    if (following.large_block) {
        if (following.block_size != identification.large_block_size)
            return error.InvalidVorbisAudioPacketHeader;
        const previous_window_flag = following.previous_window_flag orelse
            return error.InvalidVorbisAudioPacketHeader;
        _ = following.next_window_flag orelse
            return error.InvalidVorbisAudioPacketHeader;
        return previous_window_flag;
    }
    if (following.block_size != identification.small_block_size or
        following.previous_window_flag != null or
        following.next_window_flag != null)
        return error.InvalidVorbisAudioPacketHeader;
    if (identification.small_block_size ==
        identification.large_block_size)
        return false;
    return error.VorbisFollowingPacketBlockSizeUnavailable;
}

pub const VorbisPcmBlockAnalysisConfig = struct {
    transient_energy_ratio: f64 = 4,
    minimum_rms: f64 = 0.000_01,
};

pub const VorbisPcmBlockAnalysis = struct {
    recommended_large_block: bool,
    peak: f64,
    rms: f64,
    maximum_energy_ratio: f64,
    transient_segment: ?u16,
};

pub const VorbisPcmBlockClassifierConfig = struct {
    analysis: VorbisPcmBlockAnalysisConfig = .{},
    cross_block_energy_ratio: f64 = 3,
    stable_energy_ratio: f64 = 1.5,
    energy_smoothing: f64 = 0.25,
    minimum_short_blocks: u8 = 2,
};

pub const VorbisPcmBlockClassification = struct {
    analysis: VorbisPcmBlockAnalysis,
    recommended_large_block: bool,
    cross_block_energy_ratio: f64,
    short_blocks_remaining: u8,
};

pub const VorbisPcmBlockClassifier = struct {
    initialized: bool = false,
    smoothed_mean_square: f64 = 0,
    large_block: bool = true,
    short_blocks_remaining: u8 = 0,

    pub fn reset(self: *VorbisPcmBlockClassifier) void {
        self.* = .{};
    }

    pub fn classify(
        self: *VorbisPcmBlockClassifier,
        comptime Float: type,
        channels: []const []const Float,
        small_block_size: u16,
        large_block_size: u16,
        config: VorbisPcmBlockClassifierConfig,
    ) !VorbisPcmBlockClassification {
        try validateVorbisPcmBlockClassifierConfig(config);
        const analysis = try analyzeVorbisPcmBlock(
            Float,
            channels,
            small_block_size,
            large_block_size,
            config.analysis,
        );
        if (self.initialized and
            (!std.math.isFinite(self.smoothed_mean_square) or
                self.smoothed_mean_square < 0))
            return error.InvalidVorbisPcmBlockClassifierState;

        const current_mean_square = analysis.rms * analysis.rms;
        const floor_power =
            config.analysis.minimum_rms *
            config.analysis.minimum_rms;
        const reference_power = if (self.initialized)
            @max(self.smoothed_mean_square, floor_power)
        else
            @max(current_mean_square, floor_power);
        const bounded_current = @max(current_mean_square, floor_power);
        const cross_ratio = if (bounded_current == 0 and
            reference_power == 0)
            1
        else if (bounded_current == 0 or reference_power == 0)
            std.math.floatMax(f64)
        else
            @max(
                bounded_current / reference_power,
                reference_power / bounded_current,
            );
        var next_large = if (self.initialized)
            self.large_block
        else
            analysis.recommended_large_block;
        var next_hold = if (self.initialized)
            self.short_blocks_remaining
        else
            0;
        const transient =
            !analysis.recommended_large_block or
            (self.initialized and
                cross_ratio >= config.cross_block_energy_ratio);
        if (transient) {
            next_large = false;
            next_hold = config.minimum_short_blocks;
        } else if (next_hold != 0) {
            next_large = false;
            next_hold -= 1;
        } else if (cross_ratio <= config.stable_energy_ratio) {
            next_large = true;
        }

        const next_smoothed = if (self.initialized)
            self.smoothed_mean_square +
                config.energy_smoothing *
                    (current_mean_square -
                        self.smoothed_mean_square)
        else
            current_mean_square;
        if (!std.math.isFinite(next_smoothed) or next_smoothed < 0)
            return error.InvalidVorbisPcmBlockClassifierState;
        self.* = .{
            .initialized = true,
            .smoothed_mean_square = next_smoothed,
            .large_block = next_large,
            .short_blocks_remaining = next_hold,
        };
        return .{
            .analysis = analysis,
            .recommended_large_block = next_large,
            .cross_block_energy_ratio = cross_ratio,
            .short_blocks_remaining = next_hold,
        };
    }
};

pub const VorbisPsychoacousticConfig = struct {
    band_count: u8 = 24,
    absolute_threshold: f64 = 0.000_001,
    tonal_masking_offset_db: f64 = 14.5,
    noise_masking_offset_db: f64 = 5.5,
    lower_spread_db_per_bark: f64 = 27,
    upper_spread_db_per_bark: f64 = 12,
    quality: f64 = 0.75,
    maximum_masking_relaxation_db: f64 = 18,
};

pub const VorbisPsychoacousticAnalysis = struct {
    silent: bool,
    active_band_count: u8,
    peak: f64,
    rms: f64,
    spectral_flatness: f64,
    tonality: f64,
    masking_relaxation_db: f64,
};

pub const VorbisAudioPsychoacousticStorageRequirements = struct {
    analyses: usize,
    floor_values: usize,
    threshold_values: usize,
};

pub fn VorbisAudioPsychoacousticScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisAudioPsychoacousticStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        analyses: []VorbisPsychoacousticAnalysis,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisAudioPsychoacousticPlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    return struct {
        analyses: []const VorbisPsychoacousticAnalysis,
        floor_targets: []const Float,
        noise_thresholds: []const Float,
        coefficient_count: usize,
    };
}

pub const VorbisRateDistortion = struct {
    within_mask: bool,
    maximum_noise_ratio: f64,
    weighted_squared_error: f64,
    audible_excess_power: f64,
};

pub fn analyzeVorbisPsychoacoustics(
    comptime Float: type,
    spectrum: []const Float,
    sample_rate: u32,
    config: VorbisPsychoacousticConfig,
    floor_target: []Float,
    noise_threshold: []Float,
) !VorbisPsychoacousticAnalysis {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    if (spectrum.len < 32 or spectrum.len > 4096 or
        !std.math.isPowerOfTwo(spectrum.len) or
        floor_target.len != spectrum.len or
        noise_threshold.len != spectrum.len)
        return error.InvalidVorbisSpectrumShape;
    if (sample_rate == 0)
        return error.InvalidVorbisSampleRate;
    if (config.band_count == 0 or config.band_count > 64 or
        !std.math.isFinite(config.absolute_threshold) or
        config.absolute_threshold < 0 or
        !std.math.isFinite(config.tonal_masking_offset_db) or
        !std.math.isFinite(config.noise_masking_offset_db) or
        config.noise_masking_offset_db < 0 or
        config.tonal_masking_offset_db <
            config.noise_masking_offset_db or
        !std.math.isFinite(config.lower_spread_db_per_bark) or
        config.lower_spread_db_per_bark <= 0 or
        !std.math.isFinite(config.upper_spread_db_per_bark) or
        config.upper_spread_db_per_bark <= 0 or
        !std.math.isFinite(config.quality) or
        config.quality < 0 or config.quality > 1 or
        !std.math.isFinite(
            config.maximum_masking_relaxation_db,
        ) or
        config.maximum_masking_relaxation_db < 0 or
        config.maximum_masking_relaxation_db > 120)
        return error.InvalidVorbisPsychoacousticConfig;
    if (vorbisSlicesOverlap(
        Float,
        floor_target,
        noise_threshold,
    )) return error.OverlappingVorbisPsychoacousticOutput;

    var band_energy = [_]f128{0} ** 64;
    var band_log_power = [_]f128{0} ** 64;
    var band_counts = [_]u32{0} ** 64;
    var total_energy: f128 = 0;
    var total_log_power: f128 = 0;
    var peak: f128 = 0;
    const absolute_power =
        @as(f128, config.absolute_threshold) *
        @as(f128, config.absolute_threshold);
    const logarithm_floor =
        @max(absolute_power, std.math.floatMin(f128));

    for (spectrum, 0..) |coefficient, index| {
        if (!std.math.isFinite(coefficient))
            return error.InvalidVorbisSpectrumValue;
        const widened: f128 = @floatCast(coefficient);
        const magnitude = @abs(widened);
        const power = widened * widened;
        if (!std.math.isFinite(power))
            return error.InvalidVorbisSpectrumValue;
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        band_energy[band] += power;
        band_log_power[band] += @log(@max(power, logarithm_floor));
        band_counts[band] += 1;
        total_energy += power;
        total_log_power += @log(@max(power, logarithm_floor));
        peak = @max(peak, magnitude);
    }

    if (total_energy == 0) {
        @memset(floor_target, 0);
        @memset(noise_threshold, 0);
        return .{
            .silent = true,
            .active_band_count = 0,
            .peak = 0,
            .rms = 0,
            .spectral_flatness = 1,
            .tonality = 0,
            .masking_relaxation_db = 0,
        };
    }

    var band_mean_power = [_]f128{0} ** 64;
    var band_masker_power = [_]f128{0} ** 64;
    var active_band_count: u8 = 0;
    for (0..config.band_count) |band| {
        const count = band_counts[band];
        if (count == 0) continue;
        const denominator: f128 = @floatFromInt(count);
        const mean_power = band_energy[band] / denominator;
        band_mean_power[band] = mean_power;
        if (mean_power == 0) continue;
        active_band_count += 1;
        const geometric_mean =
            @exp(band_log_power[band] / denominator);
        const flatness = std.math.clamp(
            geometric_mean / mean_power,
            0,
            1,
        );
        const tonality = 1 - flatness;
        const offset_db =
            @as(f128, config.noise_masking_offset_db) +
            tonality *
                @as(
                    f128,
                    config.tonal_masking_offset_db -
                        config.noise_masking_offset_db,
                );
        band_masker_power[band] =
            mean_power * @exp(
                -offset_db *
                    (@as(f128, std.math.ln10) / 10),
            );
    }

    const nyquist_bark =
        vorbisBark(@as(f64, @floatFromInt(sample_rate)) / 2);
    const bark_per_band =
        nyquist_bark / @as(f64, @floatFromInt(config.band_count));
    const relaxation_db =
        (1 - config.quality) *
        config.maximum_masking_relaxation_db;
    const relaxation_power = @exp(
        @as(f128, relaxation_db) *
            (@as(f128, std.math.ln10) / 10),
    );
    var band_threshold_power = [_]f128{0} ** 64;
    for (0..config.band_count) |target_band| {
        var threshold = absolute_power;
        const target_bark =
            (@as(f64, @floatFromInt(target_band)) + 0.5) *
            bark_per_band;
        for (0..config.band_count) |source_band| {
            if (band_masker_power[source_band] == 0) continue;
            const source_bark =
                (@as(f64, @floatFromInt(source_band)) + 0.5) *
                bark_per_band;
            const distance = @abs(target_bark - source_bark);
            const slope = if (target_bark < source_bark)
                config.lower_spread_db_per_bark
            else
                config.upper_spread_db_per_bark;
            const attenuation = @exp(
                -@as(f128, distance * slope) *
                    (@as(f128, std.math.ln10) / 10),
            );
            threshold +=
                band_masker_power[source_band] * attenuation;
        }
        band_threshold_power[target_band] =
            threshold * relaxation_power;
    }

    for (0..spectrum.len) |index| {
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        const threshold = @sqrt(band_threshold_power[band]);
        const envelope = @sqrt(band_mean_power[band]);
        const floor_value = @max(threshold, envelope);
        if (!std.math.isFinite(threshold) or
            !std.math.isFinite(floor_value) or
            threshold > std.math.floatMax(Float) or
            floor_value > std.math.floatMax(Float))
            return error.InvalidVorbisPsychoacousticResult;
    }
    for (
        floor_target,
        noise_threshold,
        0..,
    ) |*floor_value, *threshold_value, index| {
        const band = vorbisPsychoacousticBand(
            index,
            spectrum.len,
            sample_rate,
            config.band_count,
        );
        const threshold = @sqrt(band_threshold_power[band]);
        threshold_value.* = @floatCast(threshold);
        floor_value.* = @floatCast(@max(
            threshold,
            @sqrt(band_mean_power[band]),
        ));
    }

    const denominator: f128 = @floatFromInt(spectrum.len);
    const mean_power = total_energy / denominator;
    const geometric_mean = @exp(total_log_power / denominator);
    const flatness = std.math.clamp(
        geometric_mean / mean_power,
        0,
        1,
    );
    return .{
        .silent = false,
        .active_band_count = active_band_count,
        .peak = @floatCast(peak),
        .rms = @floatCast(@sqrt(mean_power)),
        .spectral_flatness = @floatCast(flatness),
        .tonality = @floatCast(1 - flatness),
        .masking_relaxation_db = relaxation_db,
    };
}

pub fn requiredVorbisAudioPsychoacousticStorage(
    channel_count: usize,
    coefficient_count: usize,
) !VorbisAudioPsychoacousticStorageRequirements {
    if (channel_count == 0 or channel_count > 255)
        return error.InvalidVorbisChannelCount;
    if (coefficient_count < 32 or coefficient_count > 4096 or
        !std.math.isPowerOfTwo(coefficient_count))
        return error.InvalidVorbisSpectrumShape;
    const value_count = std.math.mul(
        usize,
        channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioPsychoacousticSizeOverflow;
    return .{
        .analyses = channel_count,
        .floor_values = value_count,
        .threshold_values = value_count,
    };
}

pub fn analyzeVorbisAudioPsychoacoustics(
    comptime Float: type,
    spectra: []const []const Float,
    sample_rate: u32,
    config: VorbisPsychoacousticConfig,
    scratch: VorbisAudioPsychoacousticScratch(Float),
    storage: VorbisAudioPsychoacousticStorage(Float),
) !VorbisAudioPsychoacousticPlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis psychoacoustics require f32 or f64");
    if (spectra.len == 0 or spectra.len > 255)
        return error.InvalidVorbisChannelCount;
    const coefficient_count = spectra[0].len;
    const requirements = try requiredVorbisAudioPsychoacousticStorage(
        spectra.len,
        coefficient_count,
    );
    for (spectra) |spectrum| {
        if (spectrum.len != coefficient_count)
            return error.InvalidVorbisSpectrumBundle;
        for (spectrum) |coefficient| {
            if (!std.math.isFinite(coefficient))
                return error.InvalidVorbisSpectrumValue;
        }
    }
    if (scratch.floor_targets.len < requirements.floor_values or
        scratch.noise_thresholds.len <
            requirements.threshold_values)
        return error.VorbisAudioPsychoacousticScratchTooSmall;
    if (storage.analyses.len < requirements.analyses or
        storage.floor_targets.len < requirements.floor_values or
        storage.noise_thresholds.len <
            requirements.threshold_values)
        return error.VorbisAudioPsychoacousticStorageTooSmall;

    const trial_floor =
        scratch.floor_targets[0..requirements.floor_values];
    const trial_thresholds =
        scratch.noise_thresholds[0..requirements.threshold_values];
    const analyses = storage.analyses[0..requirements.analyses];
    const floor_targets =
        storage.floor_targets[0..requirements.floor_values];
    const noise_thresholds =
        storage.noise_thresholds[0..requirements.threshold_values];
    try rejectVorbisAudioPsychoacousticOverlap(
        Float,
        spectra,
        trial_floor,
        trial_thresholds,
        analyses,
        floor_targets,
        noise_thresholds,
    );

    var trial_analyses: [255]VorbisPsychoacousticAnalysis =
        undefined;
    for (spectra, 0..) |spectrum, channel| {
        const start = channel * coefficient_count;
        trial_analyses[channel] = try analyzeVorbisPsychoacoustics(
            Float,
            spectrum,
            sample_rate,
            config,
            trial_floor[start..][0..coefficient_count],
            trial_thresholds[start..][0..coefficient_count],
        );
    }

    @memcpy(floor_targets, trial_floor);
    @memcpy(noise_thresholds, trial_thresholds);
    @memcpy(analyses, trial_analyses[0..requirements.analyses]);
    return .{
        .analyses = analyses,
        .floor_targets = floor_targets,
        .noise_thresholds = noise_thresholds,
        .coefficient_count = coefficient_count,
    };
}

fn rejectVorbisAudioPsychoacousticOverlap(
    comptime Float: type,
    spectra: []const []const Float,
    trial_floor: []Float,
    trial_thresholds: []Float,
    analyses: []VorbisPsychoacousticAnalysis,
    floor_targets: []Float,
    noise_thresholds: []Float,
) !void {
    if (vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        trial_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        VorbisPsychoacousticAnalysis,
        analyses,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_floor,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        VorbisPsychoacousticAnalysis,
        analyses,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_thresholds,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        VorbisPsychoacousticAnalysis,
        analyses,
        Float,
        floor_targets,
    ) or vorbisTypedSlicesOverlap(
        VorbisPsychoacousticAnalysis,
        analyses,
        Float,
        noise_thresholds,
    ) or vorbisTypedSlicesOverlap(
        Float,
        floor_targets,
        Float,
        noise_thresholds,
    ))
        return error.OverlappingVorbisAudioPsychoacousticStorage;

    inline for (.{
        trial_floor,
        trial_thresholds,
        analyses,
        floor_targets,
        noise_thresholds,
    }) |destination| {
        const destination_bytes = std.mem.sliceAsBytes(destination);
        if (vorbisSliceOverlapsBytes(
            []const Float,
            spectra,
            destination_bytes,
        )) return error.OverlappingVorbisAudioPsychoacousticStorage;
        for (spectra) |spectrum| {
            if (vorbisSliceOverlapsBytes(
                Float,
                spectrum,
                destination_bytes,
            )) return error.OverlappingVorbisAudioPsychoacousticStorage;
        }
    }
}

fn vorbisPsychoacousticBand(
    index: usize,
    coefficient_count: usize,
    sample_rate: u32,
    band_count: u8,
) usize {
    const frequency =
        (@as(f64, @floatFromInt(index)) + 0.5) *
        @as(f64, @floatFromInt(sample_rate)) /
        (2 * @as(f64, @floatFromInt(coefficient_count)));
    const nyquist_bark =
        vorbisBark(@as(f64, @floatFromInt(sample_rate)) / 2);
    return @min(
        @as(usize, @intFromFloat(@floor(
            vorbisBark(frequency) / nyquist_bark *
                @as(f64, @floatFromInt(band_count)),
        ))),
        band_count - 1,
    );
}

pub fn evaluateVorbisRateDistortion(
    comptime Float: type,
    original: []const Float,
    reconstructed: []const Float,
    noise_threshold: []const Float,
) !VorbisRateDistortion {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis rate-distortion evaluation requires f32 or f64");
    if (original.len == 0 or
        reconstructed.len != original.len or
        noise_threshold.len != original.len)
        return error.InvalidVorbisSpectrumShape;
    var maximum_ratio: f128 = 0;
    var weighted_error: f128 = 0;
    var audible_excess_power: f128 = 0;
    for (
        original,
        reconstructed,
        noise_threshold,
    ) |source, decoded, threshold| {
        if (!std.math.isFinite(source) or
            !std.math.isFinite(decoded) or
            !std.math.isFinite(threshold) or
            threshold < 0)
            return error.InvalidVorbisSpectrumValue;
        const difference =
            @abs(@as(f128, @floatCast(source)) -
                @as(f128, @floatCast(decoded)));
        const widened_threshold: f128 = @floatCast(threshold);
        if (widened_threshold == 0) {
            if (difference != 0) {
                return .{
                    .within_mask = false,
                    .maximum_noise_ratio = std.math.inf(f64),
                    .weighted_squared_error = std.math.inf(f64),
                    .audible_excess_power = std.math.inf(f64),
                };
            }
            continue;
        }
        const ratio = difference / widened_threshold;
        const ratio_squared = ratio * ratio;
        maximum_ratio = @max(maximum_ratio, ratio);
        weighted_error += ratio_squared;
        audible_excess_power += @max(
            difference * difference -
                widened_threshold * widened_threshold,
            0,
        );
    }
    if (maximum_ratio > std.math.floatMax(f64) or
        weighted_error > std.math.floatMax(f64) or
        audible_excess_power > std.math.floatMax(f64))
        return error.InvalidVorbisRateDistortionResult;
    return .{
        .within_mask = maximum_ratio <= 1,
        .maximum_noise_ratio = @floatCast(maximum_ratio),
        .weighted_squared_error = @floatCast(weighted_error),
        .audible_excess_power = @floatCast(audible_excess_power),
    };
}

pub const VorbisRateControlConfig = struct {
    target_bitrate: u32,
    reservoir_capacity_bits: u32,
    minimum_packet_bits: u32 = 1,
    maximum_packet_bits: u32 = std.math.maxInt(u32),
    correction_window_packets: u8 = 4,
};

pub const VorbisAdaptiveRatePolicyConfig = struct {
    quiet_rms: f64 = 0.000_1,
    full_activity_rms: f64 = 0.25,
    full_transient_ratio: f64 = 8,
    full_crest_factor: f64 = 6,
    transient_weight: f64 = 0.4,
    crest_weight: f64 = 0.2,
    minimum_target_scale: f64 = 0.6,
    maximum_target_scale: f64 = 1.4,
};

pub const VorbisAdaptiveRateDecision = struct {
    budget: VorbisPacketBitBudget,
    activity: f64,
    transient: f64,
    crest: f64,
    complexity: f64,
    target_scale: f64,
};

pub const VorbisPacketBitBudget = struct {
    packet_index: u64,
    nominal_bits: u32,
    target_bits: u32,
    reservoir_balance_before: i64,
};

pub fn adaptVorbisPacketBitBudget(
    budget: VorbisPacketBitBudget,
    classification: VorbisPcmBlockClassification,
    rate_control: VorbisRateControlConfig,
    policy: VorbisAdaptiveRatePolicyConfig,
) !VorbisAdaptiveRateDecision {
    try validateVorbisRateControlConfig(rate_control);
    try validateVorbisAdaptiveRatePolicyConfig(policy);
    if (budget.nominal_bits == 0 or
        budget.target_bits < rate_control.minimum_packet_bits or
        budget.target_bits > rate_control.maximum_packet_bits or
        budget.reservoir_balance_before <
            -@as(i64, rate_control.reservoir_capacity_bits) or
        budget.reservoir_balance_before >
            @as(i64, rate_control.reservoir_capacity_bits))
        return error.InvalidVorbisPacketBitBudget;
    const analysis = classification.analysis;
    if (!std.math.isFinite(analysis.peak) or analysis.peak < 0 or
        !std.math.isFinite(analysis.rms) or analysis.rms < 0 or
        analysis.rms > analysis.peak or
        !std.math.isFinite(analysis.maximum_energy_ratio) or
        analysis.maximum_energy_ratio < 1 or
        !std.math.isFinite(classification.cross_block_energy_ratio) or
        classification.cross_block_energy_ratio < 1)
        return error.InvalidVorbisBlockAnalysis;

    const activity = std.math.clamp(
        (analysis.rms - policy.quiet_rms) /
            (policy.full_activity_rms - policy.quiet_rms),
        0,
        1,
    );
    const transient = std.math.clamp(
        @log2(@max(
            analysis.maximum_energy_ratio,
            classification.cross_block_energy_ratio,
        )) /
            @log2(policy.full_transient_ratio),
        0,
        1,
    );
    const crest_factor = if (analysis.rms == 0)
        @as(f64, 1)
    else
        analysis.peak / analysis.rms;
    const crest = std.math.clamp(
        (crest_factor - 1) / (policy.full_crest_factor - 1),
        0,
        1,
    );
    const activity_weight =
        1 - policy.transient_weight - policy.crest_weight;
    const complexity = std.math.clamp(
        activity * activity_weight +
            transient * policy.transient_weight +
            crest * policy.crest_weight,
        0,
        1,
    );
    const target_scale = if (complexity <= 0.5)
        policy.minimum_target_scale +
            complexity * 2 *
                (1 - policy.minimum_target_scale)
    else
        1 + (complexity - 0.5) * 2 *
            (policy.maximum_target_scale - 1);
    const exact_target =
        @as(f128, @floatFromInt(budget.target_bits)) *
        @as(f128, target_scale);
    if (!std.math.isFinite(exact_target) or exact_target < 0 or
        exact_target > std.math.maxInt(u64))
        return error.VorbisAdaptiveRateTargetOverflow;
    const rounded_target: u64 = @intFromFloat(@floor(
        exact_target + 0.5,
    ));

    const reservoir_center =
        @as(i128, budget.reservoir_balance_before) +
        @as(i128, budget.nominal_bits);
    const reservoir_capacity: i128 =
        rate_control.reservoir_capacity_bits;
    const safe_minimum_i128 = @max(
        reservoir_center - reservoir_capacity,
        1,
    );
    const safe_maximum_i128 =
        reservoir_center + reservoir_capacity;
    if (safe_maximum_i128 < 1)
        return error.InvalidVorbisPacketBitBudget;
    const safe_minimum: u64 = @intCast(@min(
        safe_minimum_i128,
        std.math.maxInt(u64),
    ));
    const safe_maximum: u64 = @intCast(@min(
        safe_maximum_i128,
        std.math.maxInt(u64),
    ));
    const minimum = @max(
        @as(u64, rate_control.minimum_packet_bits),
        safe_minimum,
    );
    const maximum = @min(
        @as(u64, rate_control.maximum_packet_bits),
        safe_maximum,
    );
    if (minimum > maximum)
        return error.VorbisAdaptiveRateRangeUnavailable;
    var adjusted = budget;
    adjusted.target_bits = @intCast(std.math.clamp(
        rounded_target,
        minimum,
        maximum,
    ));
    return .{
        .budget = adjusted,
        .activity = activity,
        .transient = transient,
        .crest = crest,
        .complexity = complexity,
        .target_scale = target_scale,
    };
}

pub const VorbisRateCommit = struct {
    packet_index: u64,
    actual_bits: u32,
    reservoir_balance_after: i64,
};

pub const VorbisResidueBitAllocation = struct {
    packet_target_bits: u32,
    fixed_packet_bits: u32,
    residue_bits: u32,
};

pub fn allocateVorbisResidueBitBudgets(
    budget: VorbisPacketBitBudget,
    fixed_packet_bits: u32,
    weights: []const f64,
    destination: []u32,
) !VorbisResidueBitAllocation {
    if (weights.len == 0 or weights.len > 255)
        return error.InvalidVorbisResidueBitWeights;
    if (destination.len < weights.len)
        return error.VorbisResidueBitBudgetOutputTooSmall;
    if (vorbisTypedSlicesOverlap(
        f64,
        weights,
        u32,
        destination[0..weights.len],
    )) return error.OverlappingVorbisResidueBitBudgets;
    if (fixed_packet_bits > budget.target_bits)
        return error.VorbisPacketBudgetBelowFixedCost;
    var total_weight: f128 = 0;
    for (weights) |weight| {
        if (!std.math.isFinite(weight) or weight < 0)
            return error.InvalidVorbisResidueBitWeights;
        total_weight += weight;
    }
    const residue_bits = budget.target_bits - fixed_packet_bits;
    const effective_total = if (total_weight == 0)
        @as(f128, @floatFromInt(weights.len))
    else
        total_weight;
    var allocated: u64 = 0;
    for (weights, destination[0..weights.len]) |weight, *output| {
        const effective_weight = if (total_weight == 0) 1 else weight;
        const exact =
            @as(f128, @floatFromInt(residue_bits)) *
            @as(f128, effective_weight) /
            effective_total;
        const base: u32 = @intFromFloat(@floor(exact));
        output.* = base;
        allocated += base;
    }
    var remaining: usize = @intCast(
        @as(u64, residue_bits) - allocated,
    );
    while (remaining != 0) : (remaining -= 1) {
        var selected: ?usize = null;
        var selected_remainder: f128 = -1;
        for (weights, 0..) |weight, index| {
            const effective_weight =
                if (total_weight == 0) 1 else weight;
            const exact =
                @as(f128, @floatFromInt(residue_bits)) *
                @as(f128, effective_weight) /
                effective_total;
            const base: u32 = @intFromFloat(@floor(exact));
            if (destination[index] != base) continue;
            const remainder = exact - @floor(exact);
            if (remainder > selected_remainder) {
                selected = index;
                selected_remainder = remainder;
            }
        }
        const index = selected orelse
            return error.InvalidVorbisResidueBitWeights;
        destination[index] += 1;
    }
    return .{
        .packet_target_bits = budget.target_bits,
        .fixed_packet_bits = fixed_packet_bits,
        .residue_bits = residue_bits,
    };
}

pub fn requiredVorbisAudioResidueQuantizationStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioResidueQuantizationStorageRequirements {
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    const coefficient_count: usize = header.block_size / 2;
    var classifications: usize = 0;
    var entries: usize = 0;
    var partition_values: usize = 0;
    var vector_values: usize = 0;
    var classification_scratch: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var vector_count: usize = 0;
        for (mapping.channel_mux[0..identification.channel_count]) |mux| {
            if (mux == submap_index) vector_count += 1;
        }
        if (vector_count == 0) continue;
        const residue_number =
            mapping.submaps[submap_index].residue;
        const scratch =
            try requiredVorbisResidueQuantizationScratch(
                setup,
                residue_number,
                coefficient_count,
                vector_count,
            );
        const maximum_entries =
            try requiredVorbisResidueQuantizationEntries(
                setup,
                residue_number,
                coefficient_count,
                vector_count,
            );
        classifications = std.math.add(
            usize,
            classifications,
            scratch.classifications,
        ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
        entries = std.math.add(
            usize,
            entries,
            maximum_entries,
        ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
        partition_values =
            @max(partition_values, scratch.partition_values);
        vector_values = @max(vector_values, scratch.vector_values);
        classification_scratch =
            @max(classification_scratch, scratch.classifications);
    }
    return .{
        .encodings = mapping.submap_count,
        .submap_results = mapping.submap_count,
        .do_not_encode = identification.channel_count,
        .classifications = classifications,
        .entries = entries,
        .partition_values = partition_values,
        .vector_values = vector_values,
        .classification_scratch = classification_scratch,
    };
}

pub fn quantizeVorbisAudioResiduesAdaptive(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    residue_values: []const Float,
    noise_thresholds: []const Float,
    do_not_encode: []const bool,
    budget: VorbisPacketBitBudget,
    fixed_packet_bits: u32,
    weights: []const f64,
    config: VorbisAudioResidueQuantizationConfig,
    scratch: VorbisAudioResidueQuantizationScratch(Float),
    storage: VorbisAudioResidueQuantizationStorage,
) !VorbisAudioResidueQuantizationPlan {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis audio residue quantization requires f32 or f64");
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    const requirements =
        try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            header,
        );
    const coefficient_count: usize = header.block_size / 2;
    const value_count = std.math.mul(
        usize,
        identification.channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioResidueQuantizationSizeOverflow;
    if (residue_values.len != value_count or
        noise_thresholds.len != value_count or
        do_not_encode.len != identification.channel_count)
        return error.InvalidVorbisResidueBundle;
    for (residue_values, noise_thresholds) |value, threshold| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisQuantizationTarget;
        if (!std.math.isFinite(threshold) or threshold <= 0)
            return error.InvalidVorbisNoiseThreshold;
    }
    if (weights.len != mapping.submap_count)
        return error.InvalidVorbisResidueBitWeights;
    if (config.maximum_iterations == 0 or
        config.maximum_iterations > 64 or
        !std.math.isFinite(config.initial_lambda) or
        config.initial_lambda <= 0)
        return error.InvalidVorbisAdaptiveResidueConfig;
    if (scratch.partition.len < requirements.partition_values or
        scratch.vector.len < requirements.vector_values or
        scratch.classifications.len <
            requirements.classification_scratch or
        scratch.best_classifications.len <
            requirements.classification_scratch or
        scratch.output_classifications.len <
            requirements.classifications or
        scratch.entries.len < requirements.entries or
        scratch.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResidueQuantizationScratchTooSmall;
    if (storage.encodings.len < requirements.encodings or
        storage.submap_results.len <
            requirements.submap_results or
        storage.do_not_encode.len <
            requirements.do_not_encode or
        storage.classifications.len <
            requirements.classifications or
        storage.entries.len < requirements.entries)
        return error.VorbisAudioResidueQuantizationStorageTooSmall;

    const partition =
        scratch.partition[0..requirements.partition_values];
    const vector = scratch.vector[0..requirements.vector_values];
    const classification_scratch =
        scratch.classifications[0..requirements.classification_scratch];
    const best_classifications =
        scratch.best_classifications[0..requirements.classification_scratch];
    const trial_classifications =
        scratch.output_classifications[0..requirements.classifications];
    const trial_entries = scratch.entries[0..requirements.entries];
    const trial_skips =
        scratch.do_not_encode[0..requirements.do_not_encode];
    const encodings = storage.encodings[0..requirements.encodings];
    const submap_results =
        storage.submap_results[0..requirements.submap_results];
    const retained_skips =
        storage.do_not_encode[0..requirements.do_not_encode];
    const retained_classifications =
        storage.classifications[0..requirements.classifications];
    const retained_entries =
        storage.entries[0..requirements.entries];
    try rejectVorbisAudioResidueQuantizationOverlap(
        Float,
        setup,
        residue_values,
        noise_thresholds,
        do_not_encode,
        weights,
        partition,
        vector,
        classification_scratch,
        best_classifications,
        trial_classifications,
        trial_entries,
        trial_skips,
        encodings,
        submap_results,
        retained_skips,
        retained_classifications,
        retained_entries,
    );

    var submap_budgets: [16]u32 = undefined;
    const allocation = try allocateVorbisResidueBitBudgets(
        budget,
        fixed_packet_bits,
        weights,
        submap_budgets[0..mapping.submap_count],
    );
    var trial_results: [16]VorbisAudioResidueSubmapResult =
        undefined;
    var skip_counts = [_]usize{0} ** 16;
    var classification_counts = [_]usize{0} ** 16;
    var entry_counts = [_]usize{0} ** 16;
    var skip_offset: usize = 0;
    var classification_offset: usize = 0;
    var entry_offset: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var bundle_inputs: [255][]const Float = undefined;
        var bundle_thresholds: [255][]const Float = undefined;
        var bundle_count: usize = 0;
        for (
            mapping.channel_mux[0..identification.channel_count],
            0..,
        ) |mux, channel| {
            if (mux != submap_index) continue;
            const start = channel * coefficient_count;
            bundle_inputs[bundle_count] =
                residue_values[start..][0..coefficient_count];
            bundle_thresholds[bundle_count] =
                noise_thresholds[start..][0..coefficient_count];
            trial_skips[skip_offset + bundle_count] =
                do_not_encode[channel];
            bundle_count += 1;
        }
        skip_counts[submap_index] = bundle_count;
        if (bundle_count == 0) {
            trial_results[submap_index] = .{
                .target_bits = submap_budgets[submap_index],
                .encoded_bits = 0,
                .budget_met = true,
                .squared_error = 0,
                .weighted_squared_error = 0,
                .audible_excess_power = 0,
                .lambda = 0,
                .iterations = 0,
            };
            continue;
        }
        const quantized = try quantizeVorbisResidueAdaptive(
            Float,
            setup,
            mapping.submaps[submap_index].residue,
            trial_skips[skip_offset..][0..bundle_count],
            bundle_inputs[0..bundle_count],
            bundle_thresholds[0..bundle_count],
            .{
                .target_bits = submap_budgets[submap_index],
                .maximum_iterations = config.maximum_iterations,
                .initial_lambda = config.initial_lambda,
            },
            .{
                .partition = partition,
                .vector = vector,
                .classifications = classification_scratch,
                .best_classifications = best_classifications,
            },
            trial_classifications[classification_offset..],
            trial_entries[entry_offset..],
        );
        const classification_count =
            quantized.encoding.classifications.len;
        const entry_count = quantized.encoding.entries.len;
        classification_counts[submap_index] = classification_count;
        entry_counts[submap_index] = entry_count;
        trial_results[submap_index] = .{
            .target_bits = submap_budgets[submap_index],
            .encoded_bits = quantized.encoded_bits,
            .budget_met = quantized.budget_met,
            .squared_error = quantized.squared_error,
            .weighted_squared_error = quantized.weighted_squared_error,
            .audible_excess_power = quantized.audible_excess_power,
            .lambda = quantized.lambda,
            .iterations = quantized.iterations,
        };
        skip_offset += bundle_count;
        classification_offset += classification_count;
        entry_offset += entry_count;
    }
    std.debug.assert(skip_offset == requirements.do_not_encode);

    @memcpy(retained_skips, trial_skips);
    @memcpy(
        retained_classifications[0..classification_offset],
        trial_classifications[0..classification_offset],
    );
    @memcpy(
        retained_entries[0..entry_offset],
        trial_entries[0..entry_offset],
    );
    @memcpy(submap_results, trial_results[0..mapping.submap_count]);
    skip_offset = 0;
    classification_offset = 0;
    entry_offset = 0;
    for (encodings, 0..) |*encoding, submap_index| {
        const skip_count = skip_counts[submap_index];
        const classification_count =
            classification_counts[submap_index];
        const entry_count = entry_counts[submap_index];
        encoding.* = .{
            .do_not_encode = retained_skips[skip_offset..][0..skip_count],
            .classifications = retained_classifications[classification_offset..][0..classification_count],
            .entries = retained_entries[entry_offset..][0..entry_count],
        };
        skip_offset += skip_count;
        classification_offset += classification_count;
        entry_offset += entry_count;
    }
    return .{
        .encodings = encodings,
        .submap_results = submap_results,
        .do_not_encode = retained_skips,
        .classifications = retained_classifications[0..classification_offset],
        .entries = retained_entries[0..entry_offset],
        .allocation = allocation,
    };
}

fn rejectVorbisAudioResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    residue_values: []const Float,
    noise_thresholds: []const Float,
    do_not_encode: []const bool,
    weights: []const f64,
    partition: []Float,
    vector: []Float,
    classification_scratch: []u8,
    best_classifications: []u8,
    trial_classifications: []u8,
    trial_entries: []u32,
    trial_skips: []bool,
    encodings: []VorbisResidueEncoding,
    submap_results: []VorbisAudioResidueSubmapResult,
    retained_skips: []bool,
    retained_classifications: []u8,
    retained_entries: []u32,
) !void {
    const destinations = [_][]u8{
        std.mem.sliceAsBytes(partition),
        std.mem.sliceAsBytes(vector),
        std.mem.sliceAsBytes(classification_scratch),
        std.mem.sliceAsBytes(best_classifications),
        std.mem.sliceAsBytes(trial_classifications),
        std.mem.sliceAsBytes(trial_entries),
        std.mem.sliceAsBytes(trial_skips),
        std.mem.sliceAsBytes(encodings),
        std.mem.sliceAsBytes(submap_results),
        std.mem.sliceAsBytes(retained_skips),
        std.mem.sliceAsBytes(retained_classifications),
        std.mem.sliceAsBytes(retained_entries),
    };
    inline for (.{
        std.mem.sliceAsBytes(residue_values),
        std.mem.sliceAsBytes(noise_thresholds),
        std.mem.sliceAsBytes(do_not_encode),
        std.mem.sliceAsBytes(weights),
    }) |source| {
        for (destinations) |destination| {
            if (vorbisConstSlicesOverlap(
                u8,
                source,
                destination,
            )) return error.OverlappingVorbisAudioResidueQuantizationStorage;
        }
    }
    for (destinations, 0..) |destination, index| {
        for (destinations[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(
                u8,
                destination,
                earlier,
            )) return error.OverlappingVorbisAudioResidueQuantizationStorage;
        }
        rejectVorbisSetupOverlap(
            destination,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioResidueQuantizationStorage,
            else => return err,
        };
    }
}

pub const VorbisBitReservoir = struct {
    config: VorbisRateControlConfig,
    packet_index: u64 = 0,
    balance_bits: i64 = 0,
    pending: ?VorbisPacketBitBudget = null,

    pub fn init(
        config: VorbisRateControlConfig,
    ) !VorbisBitReservoir {
        try validateVorbisRateControlConfig(config);
        return .{ .config = config };
    }

    pub fn reset(self: *VorbisBitReservoir) void {
        self.packet_index = 0;
        self.balance_bits = 0;
        self.pending = null;
    }

    pub fn plan(
        self: *VorbisBitReservoir,
        sample_rate: u32,
        pcm_advance: u16,
    ) !VorbisPacketBitBudget {
        try validateVorbisRateControlConfig(self.config);
        if (self.pending != null)
            return error.VorbisRateBudgetAlreadyPending;
        if (self.packet_index == std.math.maxInt(u64))
            return error.VorbisAudioPacketCountOverflow;
        if (sample_rate == 0 or pcm_advance == 0)
            return error.InvalidVorbisRateInterval;
        const capacity: i64 = self.config.reservoir_capacity_bits;
        if (self.balance_bits < -capacity or
            self.balance_bits > capacity)
            return error.InvalidVorbisBitReservoirState;
        const numerator =
            @as(u64, self.config.target_bitrate) * pcm_advance;
        const rounded =
            (numerator + sample_rate / 2) / sample_rate;
        const nominal: u32 = @intCast(@min(
            @max(rounded, 1),
            std.math.maxInt(u32),
        ));
        const correction = @divTrunc(
            self.balance_bits,
            self.config.correction_window_packets,
        );
        const desired = std.math.add(
            i64,
            nominal,
            correction,
        ) catch if (correction < 0)
            @as(i64, std.math.minInt(i64))
        else
            @as(i64, std.math.maxInt(i64));
        const target: u32 = @intCast(std.math.clamp(
            desired,
            self.config.minimum_packet_bits,
            self.config.maximum_packet_bits,
        ));
        const budget = VorbisPacketBitBudget{
            .packet_index = self.packet_index,
            .nominal_bits = nominal,
            .target_bits = target,
            .reservoir_balance_before = self.balance_bits,
        };
        self.pending = budget;
        return budget;
    }

    pub fn commit(
        self: *VorbisBitReservoir,
        actual_bits: u32,
    ) !VorbisRateCommit {
        try validateVorbisRateControlConfig(self.config);
        const budget = self.pending orelse
            return error.VorbisRateBudgetNotPending;
        if (self.packet_index == std.math.maxInt(u64) or
            budget.packet_index != self.packet_index or
            budget.reservoir_balance_before != self.balance_bits or
            budget.nominal_bits == 0 or
            budget.target_bits < self.config.minimum_packet_bits or
            budget.target_bits > self.config.maximum_packet_bits)
            return error.InvalidVorbisBitReservoirState;
        const capacity: i64 = self.config.reservoir_capacity_bits;
        if (self.balance_bits < -capacity or
            self.balance_bits > capacity)
            return error.InvalidVorbisBitReservoirState;
        const credited = std.math.add(
            i64,
            self.balance_bits,
            budget.nominal_bits,
        ) catch return error.VorbisBitReservoirExceeded;
        const next_balance = std.math.sub(
            i64,
            credited,
            actual_bits,
        ) catch return error.VorbisBitReservoirExceeded;
        if (next_balance < -capacity or next_balance > capacity)
            return error.VorbisBitReservoirExceeded;
        const result = VorbisRateCommit{
            .packet_index = budget.packet_index,
            .actual_bits = actual_bits,
            .reservoir_balance_after = next_balance,
        };
        self.balance_bits = next_balance;
        self.pending = null;
        self.packet_index += 1;
        return result;
    }

    pub fn cancel(self: *VorbisBitReservoir) !void {
        if (self.pending == null)
            return error.VorbisRateBudgetNotPending;
        self.pending = null;
    }
};

fn validateVorbisRateControlConfig(
    config: VorbisRateControlConfig,
) !void {
    if (config.target_bitrate == 0 or
        config.minimum_packet_bits > config.maximum_packet_bits or
        config.correction_window_packets == 0 or
        config.correction_window_packets > 64)
        return error.InvalidVorbisRateControlConfig;
}

fn validateVorbisAdaptiveRatePolicyConfig(
    config: VorbisAdaptiveRatePolicyConfig,
) !void {
    if (!std.math.isFinite(config.quiet_rms) or
        config.quiet_rms < 0 or
        !std.math.isFinite(config.full_activity_rms) or
        config.full_activity_rms <= config.quiet_rms or
        !std.math.isFinite(config.full_transient_ratio) or
        config.full_transient_ratio <= 1 or
        !std.math.isFinite(config.full_crest_factor) or
        config.full_crest_factor <= 1 or
        !std.math.isFinite(config.transient_weight) or
        config.transient_weight < 0 or
        !std.math.isFinite(config.crest_weight) or
        config.crest_weight < 0 or
        config.transient_weight + config.crest_weight > 1 or
        !std.math.isFinite(config.minimum_target_scale) or
        config.minimum_target_scale <= 0 or
        config.minimum_target_scale > 1 or
        !std.math.isFinite(config.maximum_target_scale) or
        config.maximum_target_scale < 1 or
        config.maximum_target_scale > 8)
        return error.InvalidVorbisAdaptiveRatePolicyConfig;
}

fn validateVorbisPcmBlockClassifierConfig(
    config: VorbisPcmBlockClassifierConfig,
) !void {
    if (!std.math.isFinite(config.cross_block_energy_ratio) or
        config.cross_block_energy_ratio <= 1 or
        !std.math.isFinite(config.stable_energy_ratio) or
        config.stable_energy_ratio < 1 or
        config.stable_energy_ratio >=
            config.cross_block_energy_ratio or
        !std.math.isFinite(config.energy_smoothing) or
        config.energy_smoothing <= 0 or
        config.energy_smoothing > 1)
        return error.InvalidVorbisPcmBlockClassifierConfig;
}

/// Recommends a block size from short-window energy changes.
pub fn analyzeVorbisPcmBlock(
    comptime Float: type,
    channels: []const []const Float,
    small_block_size: u16,
    large_block_size: u16,
    config: VorbisPcmBlockAnalysisConfig,
) !VorbisPcmBlockAnalysis {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM analysis requires f32 or f64 input");
    if (channels.len == 0 or channels.len > 255)
        return error.InvalidVorbisChannelBundle;
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        return error.InvalidVorbisBlockSizes;
    if (!std.math.isFinite(config.transient_energy_ratio) or
        config.transient_energy_ratio <= 1 or
        !std.math.isFinite(config.minimum_rms) or
        config.minimum_rms < 0)
        return error.InvalidVorbisBlockAnalysisConfig;
    for (channels) |channel| {
        if (channel.len != large_block_size)
            return error.InvalidVorbisPcmBlockShape;
        for (channel) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidVorbisPcmSample;
        }
    }

    const segment_length = @as(usize, small_block_size) / 2;
    const segment_count =
        @as(usize, large_block_size) / segment_length;
    const values_per_segment = segment_length * channels.len;
    const total_values = @as(usize, large_block_size) * channels.len;
    var total_energy: f128 = 0;
    var peak: f128 = 0;
    var previous_energy: f128 = 0;
    var maximum_ratio: f128 = 1;
    var transient_segment: ?u16 = null;
    const minimum_energy =
        @as(f128, config.minimum_rms) *
        @as(f128, config.minimum_rms);

    for (0..segment_count) |segment| {
        const start = segment * segment_length;
        var segment_energy: f128 = 0;
        for (channels) |channel| {
            for (channel[start..][0..segment_length]) |sample| {
                const widened: f128 = @floatCast(sample);
                const magnitude = @abs(widened);
                peak = @max(peak, magnitude);
                segment_energy += widened * widened;
            }
        }
        total_energy += segment_energy;
        const mean_energy =
            segment_energy /
            @as(f128, @floatFromInt(values_per_segment));
        if (segment != 0) {
            const high = @max(previous_energy, mean_energy);
            if (high > 0 and high >= minimum_energy) {
                const low = @max(
                    @min(previous_energy, mean_energy),
                    @max(minimum_energy, std.math.floatMin(f128)),
                );
                const ratio = high / low;
                if (ratio > maximum_ratio) {
                    maximum_ratio = ratio;
                    transient_segment = @intCast(segment);
                }
            }
        }
        previous_energy = mean_energy;
    }

    const mean_total_energy =
        total_energy / @as(f128, @floatFromInt(total_values));
    const transient =
        maximum_ratio >= @as(f128, config.transient_energy_ratio);
    return .{
        .recommended_large_block = small_block_size != large_block_size and !transient,
        .peak = @floatCast(peak),
        .rms = @floatCast(@sqrt(mean_total_energy)),
        .maximum_energy_ratio = @floatCast(@min(
            maximum_ratio,
            std.math.floatMax(f64),
        )),
        .transient_segment = if (transient)
            transient_segment
        else
            null,
    };
}

pub fn selectVorbisEncodingMode(
    setup: VorbisSetup,
    mapping_number: u8,
    large_block: bool,
) !u8 {
    if (setup.modes.len == 0 or
        setup.modes.len != setup.summary.mode_count or
        setup.mappings.len != setup.summary.mapping_count)
        return error.InvalidVorbisSetupState;
    if (mapping_number >= setup.mappings.len)
        return error.InvalidVorbisMappingNumber;
    for (setup.modes) |mode| {
        if (mode.mapping >= setup.mappings.len)
            return error.InvalidVorbisSetupState;
    }
    for (setup.modes, 0..) |mode, mode_number| {
        if (mode.mapping == mapping_number and
            mode.large_block == large_block)
            return @intCast(mode_number);
    }
    return error.VorbisEncodingModeUnavailable;
}

pub fn planVorbisEncodingBlock(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    mapping_number: u8,
    previous_large_block: bool,
    current_large_block: bool,
    next_large_block: bool,
) !VorbisAudioPacketHeader {
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size >
            identification.large_block_size or
        !std.math.isPowerOfTwo(
            identification.small_block_size,
        ) or
        !std.math.isPowerOfTwo(
            identification.large_block_size,
        ))
        return error.InvalidVorbisIdentificationState;
    const mode_number = try selectVorbisEncodingMode(
        setup,
        mapping_number,
        current_large_block,
    );
    var counter = VorbisPacketWriter.counting();
    return counter.writeAudioHeader(
        identification,
        setup,
        mode_number,
        if (current_large_block) previous_large_block else null,
        if (current_large_block) next_large_block else null,
    );
}

pub const VorbisPcmFramePlan = struct {
    packet_index: u64,
    header: VorbisAudioPacketHeader,
    source_start: i64,
    pcm_advance: u16,
    next_center: i64,
};

pub const VorbisPcmFramePlanner = struct {
    packet_index: u64 = 0,
    center: i64 = 0,
    previous_large_block: bool,

    pub fn init(previous_large_block: bool) VorbisPcmFramePlanner {
        return .{ .previous_large_block = previous_large_block };
    }

    pub fn reset(
        self: *VorbisPcmFramePlanner,
        previous_large_block: bool,
    ) void {
        self.* = .{ .previous_large_block = previous_large_block };
    }

    pub fn plan(
        self: *VorbisPcmFramePlanner,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
        current_large_block: bool,
        next_large_block: bool,
    ) !VorbisPcmFramePlan {
        if (self.packet_index == std.math.maxInt(u64))
            return error.VorbisAudioPacketCountOverflow;
        const header = try planVorbisEncodingBlock(
            identification,
            setup,
            mapping_number,
            self.previous_large_block,
            current_large_block,
            next_large_block,
        );
        const next_block_size: u16 = if (next_large_block)
            identification.large_block_size
        else
            identification.small_block_size;
        const half_block: i64 = header.block_size / 2;
        const source_start = std.math.sub(
            i64,
            self.center,
            half_block,
        ) catch return error.VorbisPcmFramePositionOverflow;
        const pcm_advance: u16 =
            header.block_size / 4 + next_block_size / 4;
        const next_center = std.math.add(
            i64,
            self.center,
            pcm_advance,
        ) catch return error.VorbisPcmFramePositionOverflow;
        const result = VorbisPcmFramePlan{
            .packet_index = self.packet_index,
            .header = header,
            .source_start = source_start,
            .pcm_advance = pcm_advance,
            .next_center = next_center,
        };
        self.packet_index += 1;
        self.center = next_center;
        self.previous_large_block = current_large_block;
        return result;
    }
};

pub const VorbisPcmBlockLookahead = struct {
    frames: VorbisPcmFramePlanner,
    pending_large_block: ?bool = null,

    pub fn init(
        previous_large_block: bool,
    ) VorbisPcmBlockLookahead {
        return .{
            .frames = .init(previous_large_block),
        };
    }

    pub fn reset(
        self: *VorbisPcmBlockLookahead,
        previous_large_block: bool,
    ) void {
        self.* = .init(previous_large_block);
    }

    pub fn prime(
        self: *VorbisPcmBlockLookahead,
        analysis: VorbisPcmBlockAnalysis,
    ) !void {
        if (self.pending_large_block != null)
            return error.VorbisBlockLookaheadAlreadyPrimed;
        self.pending_large_block =
            analysis.recommended_large_block;
    }

    pub fn push(
        self: *VorbisPcmBlockLookahead,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
        next_analysis: VorbisPcmBlockAnalysis,
    ) !VorbisPcmFramePlan {
        const current_large_block =
            self.pending_large_block orelse
            return error.VorbisBlockLookaheadNotPrimed;
        const result = try self.frames.plan(
            identification,
            setup,
            mapping_number,
            current_large_block,
            next_analysis.recommended_large_block,
        );
        self.pending_large_block =
            next_analysis.recommended_large_block;
        return result;
    }

    pub fn finish(
        self: *VorbisPcmBlockLookahead,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        mapping_number: u8,
    ) !VorbisPcmFramePlan {
        const current_large_block =
            self.pending_large_block orelse
            return error.VorbisBlockLookaheadNotPrimed;
        const result = try self.frames.plan(
            identification,
            setup,
            mapping_number,
            current_large_block,
            current_large_block,
        );
        self.pending_large_block = null;
        return result;
    }
};

pub const VorbisPcmPacketSequenceConfig = struct {
    mapping_number: u8 = 0,
    classifier: VorbisPcmBlockClassifierConfig = .{},
    rate_control: VorbisRateControlConfig,
    adaptive_rate: ?VorbisAdaptiveRatePolicyConfig = null,
};

pub const VorbisPcmPacketPlan = struct {
    base_revision: u64,
    frame: VorbisPcmFramePlan,
    classification: ?VorbisPcmBlockClassification,
    budget: VorbisPacketBitBudget,
    granule_position: u64,
    end: bool,
    classifier_after: VorbisPcmBlockClassifier,
    lookahead_after: VorbisPcmBlockLookahead,
    reservoir_pending: VorbisBitReservoir,
};

pub const VorbisPcmPacketCommit = struct {
    frame: VorbisPcmFramePlan,
    rate: VorbisRateCommit,
    granule_position: u64,
    end: bool,
};

pub const VorbisPcmPacketSequence = struct {
    config: VorbisPcmPacketSequenceConfig,
    classifier: VorbisPcmBlockClassifier = .{},
    lookahead: VorbisPcmBlockLookahead,
    reservoir: VorbisBitReservoir,
    revision: u64 = 0,
    granule_position: u64 = 0,
    ended: bool = false,

    pub fn init(
        config: VorbisPcmPacketSequenceConfig,
        previous_large_block: bool,
    ) !VorbisPcmPacketSequence {
        try validateVorbisPcmBlockClassifierConfig(
            config.classifier,
        );
        if (config.adaptive_rate) |adaptive_rate| {
            try validateVorbisAdaptiveRatePolicyConfig(adaptive_rate);
        }
        return .{
            .config = config,
            .lookahead = .init(previous_large_block),
            .reservoir = try .init(config.rate_control),
        };
    }

    pub fn prime(
        self: *VorbisPcmPacketSequence,
        comptime Float: type,
        channels: []const []const Float,
        identification: VorbisIdentification,
    ) !VorbisPcmBlockClassification {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        var classifier_after = self.classifier;
        const classification = try classifier_after.classify(
            Float,
            channels,
            identification.small_block_size,
            identification.large_block_size,
            self.config.classifier,
        );
        var lookahead_after = self.lookahead;
        try lookahead_after.prime(
            vorbisPcmBlockDecision(classification),
        );
        self.classifier = classifier_after;
        self.lookahead = lookahead_after;
        self.revision += 1;
        return classification;
    }

    pub fn planNext(
        self: *const VorbisPcmPacketSequence,
        comptime Float: type,
        channels: []const []const Float,
        identification: VorbisIdentification,
        setup: VorbisSetup,
    ) !VorbisPcmPacketPlan {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        var classifier_after = self.classifier;
        const classification = try classifier_after.classify(
            Float,
            channels,
            identification.small_block_size,
            identification.large_block_size,
            self.config.classifier,
        );
        var lookahead_after = self.lookahead;
        const frame = try lookahead_after.push(
            identification,
            setup,
            self.config.mapping_number,
            vorbisPcmBlockDecision(classification),
        );
        var reservoir_pending = self.reservoir;
        var budget = try reservoir_pending.plan(
            identification.sample_rate,
            frame.pcm_advance,
        );
        if (self.config.adaptive_rate) |adaptive_rate| {
            budget = (try adaptVorbisPacketBitBudget(
                budget,
                classification,
                self.config.rate_control,
                adaptive_rate,
            )).budget;
            reservoir_pending.pending = budget;
        }
        const granule_position =
            try vorbisPcmFrameGranule(frame);
        if (granule_position < self.granule_position)
            return error.InvalidVorbisEncoderGranulePosition;
        return .{
            .base_revision = self.revision,
            .frame = frame,
            .classification = classification,
            .budget = budget,
            .granule_position = granule_position,
            .end = false,
            .classifier_after = classifier_after,
            .lookahead_after = lookahead_after,
            .reservoir_pending = reservoir_pending,
        };
    }

    pub fn planFinish(
        self: *const VorbisPcmPacketSequence,
        identification: VorbisIdentification,
        setup: VorbisSetup,
        total_pcm_frames: u64,
    ) !VorbisPcmPacketPlan {
        try self.validateReady(identification);
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        if (total_pcm_frames > std.math.maxInt(i64))
            return error.InvalidVorbisEncoderGranulePosition;
        var lookahead_after = self.lookahead;
        const frame = try lookahead_after.finish(
            identification,
            setup,
            self.config.mapping_number,
        );
        const maximum_granule = try vorbisPcmFrameGranule(frame);
        if (total_pcm_frames < self.granule_position or
            total_pcm_frames > maximum_granule)
            return error.InvalidVorbisEncoderGranulePosition;
        var reservoir_pending = self.reservoir;
        const budget = try reservoir_pending.plan(
            identification.sample_rate,
            frame.pcm_advance,
        );
        return .{
            .base_revision = self.revision,
            .frame = frame,
            .classification = null,
            .budget = budget,
            .granule_position = total_pcm_frames,
            .end = true,
            .classifier_after = self.classifier,
            .lookahead_after = lookahead_after,
            .reservoir_pending = reservoir_pending,
        };
    }

    pub fn commit(
        self: *VorbisPcmPacketSequence,
        plan: VorbisPcmPacketPlan,
        actual_bits: u32,
    ) !VorbisPcmPacketCommit {
        if (actual_bits == 0)
            return error.InvalidVorbisAudioPacketBitCount;
        try self.validatePlan(plan);
        var reservoir_after = plan.reservoir_pending;
        const rate = try reservoir_after.commit(actual_bits);
        const result = VorbisPcmPacketCommit{
            .frame = plan.frame,
            .rate = rate,
            .granule_position = plan.granule_position,
            .end = plan.end,
        };
        self.classifier = plan.classifier_after;
        self.lookahead = plan.lookahead_after;
        self.reservoir = reservoir_after;
        self.revision += 1;
        self.granule_position = plan.granule_position;
        self.ended = plan.end;
        return result;
    }

    pub fn appendMemory(
        self: *VorbisPcmPacketSequence,
        writer: *StreamWriter,
        plan: VorbisPcmPacketPlan,
        packet: []const u8,
        packet_bit_count: usize,
    ) !VorbisPcmPacketCommit {
        const actual_bits = std.math.cast(
            u32,
            packet_bit_count,
        ) orelse return error.VorbisAudioPacketSizeOverflow;
        if (packet_bit_count > packet.len *| 8)
            return error.InvalidVorbisAudioPacketBitCount;
        var sequence_after = self.*;
        const result = try sequence_after.commit(plan, actual_bits);
        var writer_after = writer.*;
        try writer_after.appendPacket(
            packet,
            plan.granule_position,
            false,
            plan.end,
        );
        self.* = sequence_after;
        writer.* = writer_after;
        return result;
    }

    pub fn appendFile(
        self: *VorbisPcmPacketSequence,
        writer: *FileWriter,
        plan: VorbisPcmPacketPlan,
        packet: []const u8,
        packet_bit_count: usize,
    ) !VorbisPcmPacketCommit {
        const actual_bits = std.math.cast(
            u32,
            packet_bit_count,
        ) orelse return error.VorbisAudioPacketSizeOverflow;
        if (packet_bit_count > packet.len *| 8)
            return error.InvalidVorbisAudioPacketBitCount;
        var sequence_after = self.*;
        const result = try sequence_after.commit(plan, actual_bits);
        try writer.appendPacket(
            packet,
            plan.granule_position,
            false,
            plan.end,
        );
        self.* = sequence_after;
        return result;
    }

    fn validateReady(
        self: *const VorbisPcmPacketSequence,
        identification: VorbisIdentification,
    ) !void {
        if (self.ended)
            return error.VorbisPcmPacketSequenceAlreadyEnded;
        try validateVorbisPcmBlockClassifierConfig(
            self.config.classifier,
        );
        try validateVorbisRateControlConfig(
            self.config.rate_control,
        );
        if (self.config.adaptive_rate) |adaptive_rate| {
            try validateVorbisAdaptiveRatePolicyConfig(adaptive_rate);
        }
        if (!std.meta.eql(
            self.reservoir.config,
            self.config.rate_control,
        ) or self.reservoir.pending != null or
            self.lookahead.frames.packet_index !=
                self.reservoir.packet_index or
            identification.sample_rate == 0)
            return error.InvalidVorbisPcmPacketSequenceState;
    }

    fn validatePlan(
        self: *const VorbisPcmPacketSequence,
        plan: VorbisPcmPacketPlan,
    ) !void {
        if (self.ended)
            return error.VorbisPcmPacketSequenceAlreadyEnded;
        if (plan.base_revision != self.revision)
            return error.StaleVorbisPcmPacketPlan;
        if (self.revision == std.math.maxInt(u64))
            return error.VorbisPcmPacketSequenceRevisionOverflow;
        const next_packet_index = std.math.add(
            u64,
            self.lookahead.frames.packet_index,
            1,
        ) catch return error.InvalidVorbisPcmPacketPlan;
        if (plan.frame.packet_index !=
            self.lookahead.frames.packet_index or
            plan.budget.packet_index != self.reservoir.packet_index or
            plan.frame.packet_index != plan.budget.packet_index or
            plan.reservoir_pending.pending == null or
            plan.reservoir_pending.packet_index !=
                self.reservoir.packet_index or
            plan.reservoir_pending.balance_bits !=
                self.reservoir.balance_bits or
            plan.budget.reservoir_balance_before !=
                self.reservoir.balance_bits or
            !std.meta.eql(
                plan.reservoir_pending.pending.?,
                plan.budget,
            ) or !std.meta.eql(
            plan.reservoir_pending.config,
            self.config.rate_control,
        ) or plan.granule_position < self.granule_position or
            (!plan.end and
                plan.granule_position !=
                    vorbisPcmFrameGranule(plan.frame) catch
                        return error.InvalidVorbisPcmPacketPlan) or
            plan.lookahead_after.frames.packet_index !=
                next_packet_index or
            plan.lookahead_after.frames.center !=
                plan.frame.next_center or
            plan.lookahead_after.frames.previous_large_block !=
                plan.frame.header.large_block or
            plan.end != (plan.classification == null) or
            plan.end !=
                (plan.lookahead_after.pending_large_block == null))
            return error.InvalidVorbisPcmPacketPlan;
    }
};

fn vorbisPcmBlockDecision(
    classification: VorbisPcmBlockClassification,
) VorbisPcmBlockAnalysis {
    var decision = classification.analysis;
    decision.recommended_large_block =
        classification.recommended_large_block;
    return decision;
}

fn vorbisPcmPacketGranule(next_center: i64) !u64 {
    if (next_center < 0)
        return error.InvalidVorbisEncoderGranulePosition;
    return @intCast(next_center);
}

fn vorbisPcmFrameGranule(frame: VorbisPcmFramePlan) !u64 {
    const completed_center = std.math.sub(
        i64,
        frame.next_center,
        frame.pcm_advance,
    ) catch return error.InvalidVorbisEncoderGranulePosition;
    return vorbisPcmPacketGranule(completed_center);
}

/// Copies one planned block and zero-pads outside the source range.
pub fn extractVorbisPcmBlock(
    comptime Float: type,
    inputs: []const []const Float,
    source_start: i64,
    block_size: u16,
    outputs: []const []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM extraction requires f32 or f64");
    if (inputs.len == 0 or inputs.len > 255 or
        outputs.len != inputs.len)
        return error.InvalidVorbisChannelBundle;
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        return error.InvalidVorbisBlockSizes;
    const source_length = inputs[0].len;
    if (source_length > std.math.maxInt(i64))
        return error.InvalidVorbisPcmFrameRange;
    const block_end = std.math.add(
        i64,
        source_start,
        block_size,
    ) catch return error.InvalidVorbisPcmFrameRange;

    for (inputs, 0..) |input, channel| {
        if (input.len != source_length or
            outputs[channel].len != block_size)
            return error.InvalidVorbisPcmBlockShape;
        for (input) |sample| {
            if (!std.math.isFinite(sample))
                return error.InvalidVorbisPcmSample;
        }
        if (vorbisConstSlicesOverlap(
            Float,
            input,
            outputs[channel],
        )) return error.OverlappingVorbisPcmBlockOutput;
        for (outputs[0..channel]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                outputs[channel],
                earlier,
            )) return error.OverlappingVorbisPcmBlockOutput;
        }
    }

    const copy_start = @max(source_start, 0);
    const copy_end = @min(
        block_end,
        @as(i64, @intCast(source_length)),
    );
    const copy_count: usize = if (copy_end > copy_start)
        @intCast(copy_end - copy_start)
    else
        0;
    const source_offset: usize = if (copy_count != 0)
        @intCast(copy_start)
    else
        0;
    const destination_offset: usize = if (copy_count != 0)
        @intCast(copy_start - source_start)
    else
        0;
    for (inputs, outputs) |input, output| {
        @memset(output, 0);
        if (copy_count != 0) {
            @memcpy(
                output[destination_offset..][0..copy_count],
                input[source_offset..][0..copy_count],
            );
        }
    }
}

pub fn parseVorbisAudioPacketHeader(
    packet: []const u8,
    identification: VorbisIdentification,
    setup: VorbisSetup,
) !VorbisAudioPacketHeader {
    if (setup.modes.len == 0 or setup.modes.len != setup.summary.mode_count)
        return error.InvalidVorbisSetupState;
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    for (setup.modes) |mode| {
        if (mode.mapping >= setup.summary.mapping_count)
            return error.InvalidVorbisSetupState;
    }
    var reader = VorbisBitReader{ .bytes = packet };
    const packet_type =
        readVorbisAudioBits(&reader, 1) catch |err| return err;
    if (packet_type != 0)
        return error.InvalidVorbisAudioPacketType;
    const mode_bits = vorbisILog(setup.modes.len - 1);
    const mode_number =
        readVorbisAudioBits(&reader, mode_bits) catch |err| return err;
    if (mode_number >= setup.modes.len)
        return error.InvalidVorbisAudioPacketMode;
    const mode = setup.modes[mode_number];
    const previous_window_flag: ?bool = if (mode.large_block)
        (readVorbisAudioBits(&reader, 1) catch |err| return err) != 0
    else
        null;
    const next_window_flag: ?bool = if (mode.large_block)
        (readVorbisAudioBits(&reader, 1) catch |err| return err) != 0
    else
        null;
    return .{
        .mode_number = @intCast(mode_number),
        .large_block = mode.large_block,
        .previous_window_flag = previous_window_flag,
        .next_window_flag = next_window_flag,
        .block_size = if (mode.large_block)
            identification.large_block_size
        else
            identification.small_block_size,
        .payload_bit_offset = reader.bit_offset,
    };
}

pub fn synthesizeVorbisWindow(
    comptime Float: type,
    identification: VorbisIdentification,
    packet: VorbisAudioPacketHeader,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis windows require f32 or f64 output");
    if (identification.channel_count == 0 or
        identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size > identification.large_block_size or
        !std.math.isPowerOfTwo(identification.small_block_size) or
        !std.math.isPowerOfTwo(identification.large_block_size))
        return error.InvalidVorbisIdentificationState;
    const block_size: usize = packet.block_size;
    const expected_block_size: usize = if (packet.large_block)
        identification.large_block_size
    else
        identification.small_block_size;
    if (block_size != expected_block_size or output.len != block_size)
        return error.InvalidVorbisWindowShape;
    if (packet.large_block) {
        if (packet.previous_window_flag == null or
            packet.next_window_flag == null)
            return error.InvalidVorbisWindowState;
    } else if (packet.previous_window_flag != null or
        packet.next_window_flag != null)
        return error.InvalidVorbisWindowState;

    fillVorbisWindow(
        Float,
        identification.small_block_size,
        packet.previous_window_flag orelse true,
        packet.next_window_flag orelse true,
        output,
    );
}

pub fn VorbisWindowPlan(
    comptime Float: type,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis windows require f32 or f64");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    return struct {
        const Self = @This();

        small: [small_block_size]Float,
        large: [2][2][large_block_size]Float,

        pub fn init() Self {
            var self: Self = undefined;
            fillVorbisWindow(
                Float,
                small_block_size,
                true,
                true,
                &self.small,
            );
            for (0..2) |previous| {
                for (0..2) |next| {
                    fillVorbisWindow(
                        Float,
                        small_block_size,
                        previous != 0,
                        next != 0,
                        &self.large[previous][next],
                    );
                }
            }
            return self;
        }

        pub fn get(
            self: *const Self,
            packet: VorbisAudioPacketHeader,
        ) ![]const Float {
            if (packet.large_block) {
                if (packet.block_size != large_block_size or
                    packet.previous_window_flag == null or
                    packet.next_window_flag == null)
                    return error.InvalidVorbisWindowState;
                return &self.large[
                    @intFromBool(packet.previous_window_flag.?)
                ][@intFromBool(packet.next_window_flag.?)];
            }
            if (packet.block_size != small_block_size or
                packet.previous_window_flag != null or
                packet.next_window_flag != null)
                return error.InvalidVorbisWindowState;
            return &self.small;
        }
    };
}

fn fillVorbisWindow(
    comptime Float: type,
    small_block_size: usize,
    previous_large: bool,
    next_large: bool,
    output: []Float,
) void {
    const block_size = output.len;
    const left_start: usize =
        if (block_size != small_block_size and !previous_large)
            block_size / 4 - small_block_size / 4
        else
            0;
    const left_end: usize =
        if (block_size != small_block_size and !previous_large)
            block_size / 4 + small_block_size / 4
        else
            block_size / 2;
    const right_start: usize =
        if (block_size != small_block_size and !next_large)
            block_size * 3 / 4 - small_block_size / 4
        else
            block_size / 2;
    const right_end: usize =
        if (block_size != small_block_size and !next_large)
            block_size * 3 / 4 + small_block_size / 4
        else
            block_size;

    @memset(output, 0);
    fillVorbisWindowSlope(Float, output[left_start..left_end], false);
    @memset(output[left_end..right_start], 1);
    fillVorbisWindowSlope(Float, output[right_start..right_end], true);
}

fn fillVorbisWindowSlope(
    comptime Float: type,
    output: []Float,
    reverse: bool,
) void {
    const length: f64 = @floatFromInt(output.len);
    for (output, 0..) |*value, index| {
        const position: f64 = if (reverse)
            @floatFromInt(output.len - index)
        else
            @floatFromInt(index + 1);
        const inner = @sin(
            ((position - 0.5) / length) * (std.math.pi / 2.0),
        );
        value.* = @floatCast(@sin(
            (std.math.pi / 2.0) * inner * inner,
        ));
    }
}

pub fn VorbisInverseMdct(
    comptime Float: type,
    comptime block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis inverse MDCT requires f32 or f64");
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        @compileError("Vorbis block size must be a power of two from 64 to 8192");

    const Transform = fft.Transform(Float, block_size);
    const coefficient_count = block_size / 2;

    return struct {
        const Self = @This();

        transform: Transform,
        coefficient_rotations: [coefficient_count]Transform.Value,
        output_rotations: [block_size]Transform.Value,
        work: [block_size]Transform.Value,

        pub fn init() Self {
            var self: Self = undefined;
            self.transform = Transform.init();
            const coefficient_scale =
                std.math.pi /
                @as(Float, @floatFromInt(coefficient_count));
            const rotation_offset =
                @as(Float, @floatFromInt(coefficient_count)) / 2.0 + 0.5;
            for (&self.coefficient_rotations, 0..) |*rotation, index| {
                const angle = coefficient_scale * rotation_offset *
                    (@as(Float, @floatFromInt(index)) + 0.5);
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            const output_scale =
                std.math.pi / @as(Float, @floatFromInt(block_size));
            for (&self.output_rotations, 0..) |*rotation, index| {
                const angle =
                    output_scale * @as(Float, @floatFromInt(index));
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            return self;
        }

        /// Input and output may overlap. Failures preserve output.
        pub fn process(
            self: *Self,
            input: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, null, output);
        }

        pub fn processWindowed(
            self: *Self,
            input: []const Float,
            window: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, window, output);
        }

        fn processInternal(
            self: *Self,
            input: []const Float,
            window: ?[]const Float,
            output: []Float,
        ) !void {
            if (input.len != coefficient_count or output.len != block_size)
                return error.InvalidVorbisMdctShape;
            for (input) |coefficient| {
                if (!std.math.isFinite(coefficient))
                    return error.InvalidVorbisMdctInput;
            }
            if (window) |values| {
                if (values.len != block_size)
                    return error.InvalidVorbisMdctShape;
                for (values) |value| {
                    if (!std.math.isFinite(value))
                        return error.InvalidVorbisMdctInput;
                }
            }

            @memset(&self.work, .{});
            for (
                input,
                self.coefficient_rotations,
                self.work[0..coefficient_count],
            ) |
                coefficient,
                rotation,
                *value,
            | {
                value.* = .{
                    .real = coefficient * rotation.real,
                    .imaginary = coefficient * rotation.imaginary,
                };
            }
            try self.transform.inverse(&self.work);

            for (&self.work, self.output_rotations, 0..) |
                *value,
                rotation,
                index,
            | {
                var sample = @as(Float, @floatFromInt(block_size)) *
                    (value.real * rotation.real -
                        value.imaginary * rotation.imaginary);
                if (window) |values| sample *= values[index];
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisMdctOutput;
                value.real = sample;
            }
            for (output, self.work) |*sample, value| {
                sample.* = value.real;
            }
        }
    };
}

pub fn VorbisForwardMdct(
    comptime Float: type,
    comptime block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis forward MDCT requires f32 or f64");
    if (block_size < 64 or block_size > 8192 or
        !std.math.isPowerOfTwo(block_size))
        @compileError("Vorbis block size must be a power of two from 64 to 8192");

    const Transform = fft.Transform(Float, block_size);
    const coefficient_count = block_size / 2;

    return struct {
        const Self = @This();

        transform: Transform,
        input_rotations: [block_size]Transform.Value,
        coefficient_rotations: [coefficient_count]Transform.Value,
        work: [block_size]Transform.Value,

        pub fn init() Self {
            var self: Self = undefined;
            self.transform = Transform.init();
            const input_scale =
                std.math.pi / @as(Float, @floatFromInt(block_size));
            for (&self.input_rotations, 0..) |*rotation, index| {
                const angle =
                    input_scale * @as(Float, @floatFromInt(index));
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            const coefficient_scale =
                std.math.pi /
                @as(Float, @floatFromInt(coefficient_count));
            const rotation_offset =
                @as(Float, @floatFromInt(coefficient_count)) / 2.0 + 0.5;
            for (&self.coefficient_rotations, 0..) |*rotation, index| {
                const angle = coefficient_scale * rotation_offset *
                    (@as(Float, @floatFromInt(index)) + 0.5);
                rotation.* = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            return self;
        }

        /// Input and output may overlap. Failures preserve output.
        pub fn process(
            self: *Self,
            input: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, null, output);
        }

        pub fn processWindowed(
            self: *Self,
            input: []const Float,
            window: []const Float,
            output: []Float,
        ) !void {
            try self.processInternal(input, window, output);
        }

        fn processInternal(
            self: *Self,
            input: []const Float,
            window: ?[]const Float,
            output: []Float,
        ) !void {
            if (input.len != block_size or
                output.len != coefficient_count)
                return error.InvalidVorbisMdctShape;
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisMdctInput;
            }
            if (window) |values| {
                if (values.len != block_size)
                    return error.InvalidVorbisMdctShape;
                for (values) |value| {
                    if (!std.math.isFinite(value))
                        return error.InvalidVorbisMdctInput;
                }
            }

            for (
                input,
                self.input_rotations,
                &self.work,
                0..,
            ) |sample, rotation, *value, index| {
                const windowed = if (window) |values|
                    sample * values[index]
                else
                    sample;
                if (!std.math.isFinite(windowed))
                    return error.InvalidVorbisMdctInput;
                value.* = .{
                    .real = windowed * rotation.real,
                    .imaginary = windowed * rotation.imaginary,
                };
            }
            try self.transform.inverse(&self.work);

            const scale: Float = 4.0;
            for (
                self.work[0..coefficient_count],
                self.coefficient_rotations,
            ) |*value, rotation| {
                const coefficient = scale *
                    (value.real * rotation.real -
                        value.imaginary * rotation.imaginary);
                if (!std.math.isFinite(coefficient))
                    return error.InvalidVorbisMdctOutput;
                value.real = coefficient;
            }
            for (
                output,
                self.work[0..coefficient_count],
            ) |*coefficient, value| {
                coefficient.* = value.real;
            }
        }
    };
}

pub fn VorbisPcmBlockTransform(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM transforms require f32 or f64");
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis PCM transforms require 1 through 255 channels");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    const Windows =
        VorbisWindowPlan(Float, small_block_size, large_block_size);
    const SmallMdct = VorbisForwardMdct(Float, small_block_size);
    const LargeMdct = VorbisForwardMdct(Float, large_block_size);

    return struct {
        const Self = @This();

        windows: Windows,
        small_mdct: SmallMdct,
        large_mdct: LargeMdct,

        pub fn init() Self {
            return .{
                .windows = .init(),
                .small_mdct = .init(),
                .large_mdct = .init(),
            };
        }

        pub fn requiredScratch(
            header: VorbisAudioPacketHeader,
        ) !usize {
            const block_size = try checkedBlockSize(header);
            return channel_count * (block_size / 2);
        }

        /// All channel outputs commit after every transform succeeds.
        pub fn process(
            self: *Self,
            header: VorbisAudioPacketHeader,
            inputs: []const []const Float,
            outputs: []const []Float,
            scratch: []Float,
        ) !void {
            const block_size = try checkedBlockSize(header);
            const coefficient_count = block_size / 2;
            const required_scratch = channel_count * coefficient_count;
            if (inputs.len != channel_count or outputs.len != channel_count)
                return error.InvalidVorbisPcmBlockShape;
            if (scratch.len < required_scratch)
                return error.VorbisPcmBlockScratchTooSmall;
            const used_scratch = scratch[0..required_scratch];
            for (inputs, 0..) |input, channel| {
                if (input.len != block_size or
                    outputs[channel].len != coefficient_count)
                    return error.InvalidVorbisPcmBlockShape;
                for (input) |sample| {
                    if (!std.math.isFinite(sample))
                        return error.InvalidVorbisPcmSample;
                }
                if (vorbisConstSlicesOverlap(
                    Float,
                    input,
                    used_scratch,
                )) return error.OverlappingVorbisPcmBlockScratch;
                for (outputs[0..channel]) |earlier| {
                    if (vorbisSlicesOverlap(
                        Float,
                        outputs[channel],
                        earlier,
                    )) return error.OverlappingVorbisPcmBlockOutput;
                }
                if (vorbisSlicesOverlap(
                    Float,
                    outputs[channel],
                    used_scratch,
                )) return error.OverlappingVorbisPcmBlockScratch;
            }

            const window = try self.windows.get(header);
            for (inputs, 0..) |input, channel| {
                const staged =
                    used_scratch[channel * coefficient_count ..][0..coefficient_count];
                if (header.large_block) {
                    try self.large_mdct.processWindowed(
                        input,
                        window,
                        staged,
                    );
                } else {
                    try self.small_mdct.processWindowed(
                        input,
                        window,
                        staged,
                    );
                }
            }
            for (outputs, 0..) |output, channel| {
                @memcpy(
                    output,
                    used_scratch[channel * coefficient_count ..][0..coefficient_count],
                );
            }
        }

        fn checkedBlockSize(
            header: VorbisAudioPacketHeader,
        ) !usize {
            const expected: usize = if (header.large_block)
                large_block_size
            else
                small_block_size;
            if (header.block_size != expected)
                return error.InvalidVorbisPcmBlockShape;
            if (header.large_block) {
                if (header.previous_window_flag == null or
                    header.next_window_flag == null)
                    return error.InvalidVorbisWindowState;
            } else if (header.previous_window_flag != null or
                header.next_window_flag != null)
                return error.InvalidVorbisWindowState;
            return expected;
        }
    };
}

pub const VorbisPcmFrameAnalysisStorageRequirements = struct {
    pcm_values: usize,
    transform_values: usize,
    spectrum_values: usize,
    analyses: usize,
    floor_values: usize,
    threshold_values: usize,
};

pub fn VorbisPcmFrameAnalysisScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        pcm: []Float,
        transform: []Float,
        spectra: []Float,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisPcmFrameAnalysisStorage(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        spectra: []Float,
        analyses: []VorbisPsychoacousticAnalysis,
        floor_targets: []Float,
        noise_thresholds: []Float,
    };
}

pub fn VorbisPcmFrameAnalysisPlan(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM frame analysis requires f32 or f64");
    return struct {
        frame: VorbisPcmFramePlan,
        spectra: []const Float,
        analyses: []const VorbisPsychoacousticAnalysis,
        floor_targets: []const Float,
        noise_thresholds: []const Float,
        coefficient_count: usize,
    };
}

pub fn VorbisPcmFrameAnalyzer(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const Transform = VorbisPcmBlockTransform(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );

    return struct {
        const Self = @This();

        transform: Transform,

        pub fn init() Self {
            return .{ .transform = .init() };
        }

        pub fn requiredStorage(
            header: VorbisAudioPacketHeader,
        ) !VorbisPcmFrameAnalysisStorageRequirements {
            const transform_values =
                try Transform.requiredScratch(header);
            const block_size: usize = header.block_size;
            const pcm_values = std.math.mul(
                usize,
                channel_count,
                block_size,
            ) catch return error.VorbisPcmFrameAnalysisSizeOverflow;
            const psychoacoustic =
                try requiredVorbisAudioPsychoacousticStorage(
                    channel_count,
                    block_size / 2,
                );
            return .{
                .pcm_values = pcm_values,
                .transform_values = transform_values,
                .spectrum_values = psychoacoustic.floor_values,
                .analyses = psychoacoustic.analyses,
                .floor_values = psychoacoustic.floor_values,
                .threshold_values = psychoacoustic.threshold_values,
            };
        }

        pub fn analyze(
            self: *Self,
            inputs: []const []const Float,
            frame: VorbisPcmFramePlan,
            config: VorbisPsychoacousticConfig,
            sample_rate: u32,
            scratch: VorbisPcmFrameAnalysisScratch(Float),
            storage: VorbisPcmFrameAnalysisStorage(Float),
        ) !VorbisPcmFrameAnalysisPlan(Float) {
            const requirements =
                try requiredStorage(frame.header);
            if (inputs.len != channel_count)
                return error.InvalidVorbisChannelBundle;
            if (scratch.pcm.len < requirements.pcm_values or
                scratch.transform.len <
                    requirements.transform_values or
                scratch.spectra.len <
                    requirements.spectrum_values or
                scratch.floor_targets.len <
                    requirements.floor_values or
                scratch.noise_thresholds.len <
                    requirements.threshold_values)
                return error.VorbisPcmFrameAnalysisScratchTooSmall;
            if (storage.spectra.len <
                requirements.spectrum_values or
                storage.analyses.len < requirements.analyses or
                storage.floor_targets.len <
                    requirements.floor_values or
                storage.noise_thresholds.len <
                    requirements.threshold_values)
                return error.VorbisPcmFrameAnalysisStorageTooSmall;

            const pcm = scratch.pcm[0..requirements.pcm_values];
            const transform =
                scratch.transform[0..requirements.transform_values];
            const trial_spectra =
                scratch.spectra[0..requirements.spectrum_values];
            const trial_floor =
                scratch.floor_targets[0..requirements.floor_values];
            const trial_thresholds =
                scratch.noise_thresholds[0..requirements.threshold_values];
            const spectra =
                storage.spectra[0..requirements.spectrum_values];
            const analyses =
                storage.analyses[0..requirements.analyses];
            const floor_targets =
                storage.floor_targets[0..requirements.floor_values];
            const noise_thresholds =
                storage.noise_thresholds[0..requirements.threshold_values];
            try rejectVorbisPcmFrameAnalysisOverlap(
                Float,
                inputs,
                pcm,
                transform,
                trial_spectra,
                trial_floor,
                trial_thresholds,
                spectra,
                analyses,
                floor_targets,
                noise_thresholds,
            );

            const block_size: usize = frame.header.block_size;
            const coefficient_count = block_size / 2;
            var pcm_channels: [channel_count][]Float = undefined;
            var pcm_inputs: [channel_count][]const Float = undefined;
            var spectrum_channels: [channel_count][]Float = undefined;
            var spectrum_inputs: [channel_count][]const Float =
                undefined;
            for (0..channel_count) |channel| {
                pcm_channels[channel] =
                    pcm[channel * block_size ..][0..block_size];
                pcm_inputs[channel] = pcm_channels[channel];
                spectrum_channels[channel] =
                    trial_spectra[channel * coefficient_count ..][0..coefficient_count];
                spectrum_inputs[channel] =
                    spectrum_channels[channel];
            }
            try extractVorbisPcmBlock(
                Float,
                inputs,
                frame.source_start,
                frame.header.block_size,
                &pcm_channels,
            );
            try self.transform.process(
                frame.header,
                &pcm_inputs,
                &spectrum_channels,
                transform,
            );
            const psychoacoustic =
                try analyzeVorbisAudioPsychoacoustics(
                    Float,
                    &spectrum_inputs,
                    sample_rate,
                    config,
                    .{
                        .floor_targets = trial_floor,
                        .noise_thresholds = trial_thresholds,
                    },
                    .{
                        .analyses = analyses,
                        .floor_targets = floor_targets,
                        .noise_thresholds = noise_thresholds,
                    },
                );
            @memcpy(spectra, trial_spectra);
            return .{
                .frame = frame,
                .spectra = spectra,
                .analyses = psychoacoustic.analyses,
                .floor_targets = psychoacoustic.floor_targets,
                .noise_thresholds = psychoacoustic.noise_thresholds,
                .coefficient_count = coefficient_count,
            };
        }
    };
}

fn rejectVorbisPcmFrameAnalysisOverlap(
    comptime Float: type,
    inputs: []const []const Float,
    pcm: []Float,
    transform: []Float,
    trial_spectra: []Float,
    trial_floor: []Float,
    trial_thresholds: []Float,
    spectra: []Float,
    analyses: []VorbisPsychoacousticAnalysis,
    floor_targets: []Float,
    noise_thresholds: []Float,
) !void {
    const values = [_][]Float{
        pcm,
        transform,
        trial_spectra,
        trial_floor,
        trial_thresholds,
        spectra,
        floor_targets,
        noise_thresholds,
    };
    for (values, 0..) |current, index| {
        for (values[0..index]) |earlier| {
            if (vorbisSlicesOverlap(
                Float,
                current,
                earlier,
            )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        }
        if (vorbisTypedSlicesOverlap(
            Float,
            current,
            VorbisPsychoacousticAnalysis,
            analyses,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    }
    const analysis_bytes = std.mem.sliceAsBytes(analyses);
    if (vorbisSliceOverlapsBytes(
        []const Float,
        inputs,
        analysis_bytes,
    )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    for (inputs) |input| {
        if (vorbisSliceOverlapsBytes(
            Float,
            input,
            analysis_bytes,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
    }
    for (values) |destination| {
        const destination_bytes = std.mem.sliceAsBytes(destination);
        if (vorbisSliceOverlapsBytes(
            []const Float,
            inputs,
            destination_bytes,
        )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        for (inputs) |input| {
            if (vorbisSliceOverlapsBytes(
                Float,
                input,
                destination_bytes,
            )) return error.OverlappingVorbisPcmFrameAnalysisStorage;
        }
    }
}

pub fn VorbisOverlapAdd(
    comptime Float: type,
    comptime maximum_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis overlap-add requires f32 or f64");
    if (maximum_block_size < 64 or maximum_block_size > 8192 or
        !std.math.isPowerOfTwo(maximum_block_size))
        @compileError("maximum block size must be a power of two from 64 to 8192");

    return struct {
        const Self = @This();

        previous: [maximum_block_size]Float = undefined,
        pending: [maximum_block_size / 2]Float = undefined,
        previous_size: usize = 0,

        pub fn reset(self: *Self) void {
            self.previous_size = 0;
        }

        pub fn primed(self: *const Self) bool {
            return self.previous_size != 0;
        }

        pub fn previousBlockSize(self: *const Self) usize {
            return self.previous_size;
        }

        /// The first block primes state and returns no samples.
        pub fn push(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
        ) !usize {
            const output_count = try self.prepare(windowed_block, output);
            self.commitPrepared(windowed_block, output, output_count);
            return output_count;
        }

        fn prepare(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
        ) !usize {
            if (windowed_block.len < 64 or
                windowed_block.len > maximum_block_size or
                !std.math.isPowerOfTwo(windowed_block.len))
                return error.InvalidVorbisOverlapBlock;
            for (windowed_block) |sample| {
                if (!std.math.isFinite(sample))
                    return error.InvalidVorbisOverlapInput;
            }
            if (self.previous_size == 0) {
                return 0;
            }
            if (self.previous_size > maximum_block_size or
                self.previous_size < 64 or
                !std.math.isPowerOfTwo(self.previous_size))
                return error.InvalidVorbisOverlapState;

            const output_count =
                self.previous_size / 4 + windowed_block.len / 4;
            if (output.len < output_count)
                return error.VorbisOverlapOutputTooSmall;
            if (vorbisConstSlicesOverlap(Float, windowed_block, output) or
                vorbisConstSlicesOverlap(
                    Float,
                    windowed_block,
                    self.previous[0..self.previous_size],
                ) or
                vorbisConstSlicesOverlap(
                    Float,
                    output,
                    self.previous[0..self.previous_size],
                ) or
                vorbisConstSlicesOverlap(
                    Float,
                    output,
                    self.pending[0..output_count],
                ))
                return error.OverlappingVorbisOverlapBuffer;

            const previous_size: i64 = @intCast(self.previous_size);
            const current_size: i64 = @intCast(windowed_block.len);
            const current_start =
                @divExact(previous_size * 3, 4) -
                @divExact(current_size, 4);
            const output_start = @divExact(previous_size, 2);
            for (self.pending[0..output_count], 0..) |*sample, index| {
                const position =
                    output_start + @as(i64, @intCast(index));
                var sum: Float = 0;
                if (position >= 0 and position < previous_size) {
                    sum += self.previous[@intCast(position)];
                }
                const current_index = position - current_start;
                if (current_index >= 0 and current_index < current_size) {
                    sum += windowed_block[@intCast(current_index)];
                }
                if (!std.math.isFinite(sum))
                    return error.InvalidVorbisOverlapOutput;
                sample.* = sum;
            }

            return output_count;
        }

        fn commitPrepared(
            self: *Self,
            windowed_block: []const Float,
            output: []Float,
            output_count: usize,
        ) void {
            @memcpy(output[0..output_count], self.pending[0..output_count]);
            @memcpy(
                self.previous[0..windowed_block.len],
                windowed_block,
            );
            self.previous_size = windowed_block.len;
        }
    };
}

pub fn VorbisChannelOverlapAdd(
    comptime Float: type,
    comptime channel_count: usize,
    comptime maximum_block_size: usize,
) type {
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis channel count must be from 1 to 255");
    const ChannelState = VorbisOverlapAdd(Float, maximum_block_size);

    return struct {
        const Self = @This();

        channels: [channel_count]ChannelState =
            [_]ChannelState{.{}} ** channel_count,

        pub fn reset(self: *Self) void {
            for (&self.channels) |*channel| channel.reset();
        }

        pub fn primed(self: *const Self) bool {
            if (!self.channels[0].primed()) return false;
            for (self.channels[1..]) |channel| {
                if (!channel.primed()) return false;
            }
            return true;
        }

        /// Failures preserve outputs and logical overlap history.
        pub fn push(
            self: *Self,
            windowed_blocks: []const []const Float,
            outputs: []const []Float,
        ) !usize {
            if (windowed_blocks.len != channel_count or
                outputs.len != channel_count)
                return error.InvalidVorbisChannelOverlapBundle;
            const previous_size = self.channels[0].previous_size;
            for (self.channels[1..]) |channel| {
                if (channel.previous_size != previous_size)
                    return error.InvalidVorbisChannelOverlapState;
            }
            for (windowed_blocks, 0..) |input, channel| {
                for (outputs, 0..) |output, output_channel| {
                    if (vorbisConstSlicesOverlap(Float, input, output))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                    if (channel != output_channel and
                        vorbisConstSlicesOverlap(
                            Float,
                            outputs[channel],
                            output,
                        ))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                }
                for (&self.channels) |*state| {
                    if (vorbisConstSlicesOverlap(
                        Float,
                        input,
                        &state.previous,
                    ) or vorbisConstSlicesOverlap(
                        Float,
                        input,
                        &state.pending,
                    ))
                        return error.OverlappingVorbisChannelOverlapBuffer;
                    for (outputs) |output| {
                        if (vorbisConstSlicesOverlap(
                            Float,
                            output,
                            &state.previous,
                        ) or vorbisConstSlicesOverlap(
                            Float,
                            output,
                            &state.pending,
                        ))
                            return error.OverlappingVorbisChannelOverlapBuffer;
                    }
                }
            }

            var output_count: ?usize = null;
            for (&self.channels, windowed_blocks, outputs) |
                *state,
                input,
                output,
            | {
                const count = try state.prepare(input, output);
                if (output_count) |expected| {
                    if (count != expected)
                        return error.InvalidVorbisChannelOverlapState;
                } else {
                    output_count = count;
                }
            }
            for (&self.channels, windowed_blocks, outputs) |
                *state,
                input,
                output,
            | {
                state.commitPrepared(input, output, output_count.?);
            }
            return output_count.?;
        }
    };
}

pub const VorbisGranuleRange = struct {
    source_start: usize,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
};

pub const VorbisGranuleTracker = struct {
    decoded_samples: u64 = 0,
    position_offset: ?i64 = null,
    ended: bool = false,

    pub fn reset(self: *VorbisGranuleTracker) void {
        self.* = .{};
    }

    /// Return the portion of one finished overlap range that belongs to the stream.
    pub fn trim(
        self: *VorbisGranuleTracker,
        nominal_sample_count: usize,
        granule_position: u64,
        end: bool,
    ) !VorbisGranuleRange {
        if (self.ended) return error.VorbisGranuleStreamAlreadyEnded;
        if (nominal_sample_count == 0)
            return error.InvalidVorbisGranuleSampleCount;
        if (end and granule_position == unknown_granule)
            return error.MissingVorbisEndGranule;
        const decoded_before = self.decoded_samples;
        const decoded_after = std.math.add(
            u64,
            decoded_before,
            nominal_sample_count,
        ) catch return error.VorbisGranulePositionOverflow;
        if (decoded_after > std.math.maxInt(i64))
            return error.VorbisGranulePositionOverflow;

        var offset = self.position_offset;
        var source_start: usize = 0;
        var sample_count = nominal_sample_count;
        if (granule_position != unknown_granule) {
            const declared_end: i64 = @bitCast(granule_position);
            if (offset == null) {
                if (end and declared_end >= 0 and
                    declared_end <= @as(i64, @intCast(decoded_after)))
                {
                    if (declared_end <
                        @as(i64, @intCast(decoded_before)))
                        return error.InvalidVorbisEndGranule;
                    offset = 0;
                    sample_count =
                        @intCast(
                            declared_end -
                                @as(i64, @intCast(decoded_before)),
                        );
                } else {
                    offset = std.math.sub(
                        i64,
                        declared_end,
                        @intCast(decoded_after),
                    ) catch return error.VorbisGranulePositionOverflow;
                    if (offset.? < 0) {
                        if (decoded_before != 0)
                            return error.LateVorbisInitialGranule;
                        const discarded: u64 = @intCast(-offset.?);
                        if (discarded > nominal_sample_count)
                            return error.InvalidVorbisInitialGranule;
                        source_start = @intCast(discarded);
                        sample_count -= source_start;
                    }
                }
            } else {
                const expected_end = std.math.add(
                    i64,
                    offset.?,
                    @intCast(decoded_after),
                ) catch return error.VorbisGranulePositionOverflow;
                if (!end) {
                    if (declared_end != expected_end)
                        return error.InvalidVorbisGranulePosition;
                } else {
                    const earliest_end = std.math.add(
                        i64,
                        offset.?,
                        @intCast(decoded_before),
                    ) catch return error.VorbisGranulePositionOverflow;
                    if (declared_end < earliest_end or
                        declared_end > expected_end)
                        return error.InvalidVorbisEndGranule;
                    sample_count = @intCast(declared_end - earliest_end);
                }
            }
        }

        const pcm_start: ?i64 = if (offset) |known_offset|
            std.math.add(
                i64,
                known_offset,
                @as(i64, @intCast(decoded_before + source_start)),
            ) catch return error.VorbisGranulePositionOverflow
        else
            null;
        const pcm_end: ?i64 = if (pcm_start) |start|
            std.math.add(
                i64,
                start,
                @intCast(sample_count),
            ) catch return error.VorbisGranulePositionOverflow
        else
            null;

        self.decoded_samples = decoded_after;
        self.position_offset = offset;
        self.ended = end;
        return .{
            .source_start = source_start,
            .sample_count = sample_count,
            .pcm_start = pcm_start,
            .pcm_end = pcm_end,
        };
    }
};

pub fn VorbisPcmStreamScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis stream decoding requires f32 or f64");
    return struct {
        packet: VorbisAudioPacketScratch(Float),
        windowed: []Float,
    };
}

pub const VorbisPcmStreamResult = struct {
    packet: VorbisAudioPacketResult,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
};

pub const VorbisPcmConcealmentResult = struct {
    block_size: u16,
    sample_count: usize,
    pcm_start: ?i64,
    pcm_end: ?i64,
    concealed_packet_count: u64,
};

pub const VorbisChainedPcmStreamResult = struct {
    stream: VorbisPcmStreamResult,
    logical_stream_index: u64,
    global_pcm_start: u64,
    global_pcm_end: u64,
};

pub const VorbisChainedPcmConcealmentResult = struct {
    stream: VorbisPcmConcealmentResult,
    logical_stream_index: u64,
    global_pcm_start: u64,
    global_pcm_end: u64,
};

pub const VorbisPcmSeekCursor = struct {
    target_pcm: i64,
    reached: bool = false,

    pub fn init(target_pcm: i64) VorbisPcmSeekCursor {
        return .{ .target_pcm = target_pcm };
    }

    /// Select the suffix at or after the target from one decoded PCM range.
    pub fn select(
        self: *VorbisPcmSeekCursor,
        decoded: VorbisPcmStreamResult,
    ) !VorbisGranuleRange {
        if (decoded.sample_count == 0) {
            if (decoded.pcm_start != null or decoded.pcm_end != null)
                return error.InvalidVorbisPcmSeekRange;
            return .{
                .source_start = 0,
                .sample_count = 0,
                .pcm_start = null,
                .pcm_end = null,
            };
        }
        const pcm_start = decoded.pcm_start orelse
            return error.VorbisPcmSeekPositionUnavailable;
        const pcm_end = decoded.pcm_end orelse
            return error.VorbisPcmSeekPositionUnavailable;
        if (pcm_end < pcm_start or
            @as(u64, @intCast(pcm_end - pcm_start)) !=
                decoded.sample_count)
            return error.InvalidVorbisPcmSeekRange;

        if (self.reached or self.target_pcm <= pcm_start) {
            self.reached = true;
            return .{
                .source_start = 0,
                .sample_count = decoded.sample_count,
                .pcm_start = pcm_start,
                .pcm_end = pcm_end,
            };
        }
        if (self.target_pcm >= pcm_end) {
            self.reached = self.target_pcm == pcm_end;
            return .{
                .source_start = decoded.sample_count,
                .sample_count = 0,
                .pcm_start = pcm_end,
                .pcm_end = pcm_end,
            };
        }

        const source_start: usize =
            @intCast(self.target_pcm - pcm_start);
        self.reached = true;
        return .{
            .source_start = source_start,
            .sample_count = decoded.sample_count - source_start,
            .pcm_start = self.target_pcm,
            .pcm_end = pcm_end,
        };
    }
};

pub fn VorbisPcmStreamDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const PacketDecoder = VorbisAudioPacketDecoder(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );
    const ChannelOverlap = VorbisChannelOverlapAdd(
        Float,
        channel_count,
        large_block_size,
    );

    return struct {
        const Self = @This();

        packets: PacketDecoder,
        overlap: ChannelOverlap = .{},
        granules: VorbisGranuleTracker = .{},
        audio_packet_count: u64 = 0,
        concealed_packet_count: u64 = 0,
        ended: bool = false,

        pub fn init() Self {
            return .{ .packets = .init() };
        }

        pub fn reset(self: *Self) void {
            self.overlap.reset();
            self.granules.reset();
            self.audio_packet_count = 0;
            self.concealed_packet_count = 0;
            self.ended = false;
        }

        /// Returned samples occupy the prefix of every output channel.
        pub fn decode(
            self: *Self,
            packet: Packet,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisPcmStreamScratch(Float),
        ) !VorbisPcmStreamResult {
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            if (self.audio_packet_count == std.math.maxInt(u64))
                return error.VorbisAudioPacketCountOverflow;
            if (self.concealed_packet_count > self.audio_packet_count)
                return error.InvalidVorbisPcmStreamState;
            const header = try parseVorbisAudioPacketHeader(
                packet.bytes,
                identification,
                setup,
            );
            const previous_size =
                self.overlap.channels[0].previousBlockSize();
            for (self.overlap.channels[1..]) |channel| {
                if (channel.previousBlockSize() != previous_size)
                    return error.InvalidVorbisChannelOverlapState;
            }
            const nominal_sample_count = if (previous_size == 0)
                0
            else
                previous_size / 4 + header.block_size / 4;
            if (packet.end and nominal_sample_count == 0)
                return error.VorbisStreamEndedBeforePcm;
            if (outputs.len != channel_count)
                return error.InvalidVorbisAudioOutput;
            for (outputs) |output| {
                if (output.len < nominal_sample_count)
                    return error.VorbisOverlapOutputTooSmall;
            }
            const windowed_values = std.math.mul(
                usize,
                channel_count,
                header.block_size,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            if (scratch.windowed.len < windowed_values)
                return error.VorbisPcmStreamScratchTooSmall;

            var granule_trial = self.granules;
            const granule_range: VorbisGranuleRange =
                if (nominal_sample_count == 0)
                    .{
                        .source_start = 0,
                        .sample_count = 0,
                        .pcm_start = null,
                        .pcm_end = null,
                    }
                else
                    try granule_trial.trim(
                        nominal_sample_count,
                        packet.granule_position,
                        packet.end,
                    );

            var windowed_channels: [channel_count][]Float = undefined;
            for (&windowed_channels, 0..) |*channel, index| {
                channel.* =
                    scratch.windowed[index * header.block_size ..][0..header.block_size];
            }
            const packet_result = try self.packets.decode(
                packet.bytes,
                identification,
                setup,
                &windowed_channels,
                scratch.packet,
            );
            var const_windowed_channels: [channel_count][]const Float = undefined;
            for (&const_windowed_channels, windowed_channels) |
                *destination,
                source,
            | {
                destination.* = source;
            }
            _ = try self.overlap.push(
                &const_windowed_channels,
                outputs,
            );
            if (granule_range.source_start != 0) {
                for (outputs) |output| {
                    std.mem.copyForwards(
                        Float,
                        output[0..granule_range.sample_count],
                        output[granule_range.source_start..][0..granule_range.sample_count],
                    );
                }
            }

            self.granules = granule_trial;
            self.audio_packet_count += 1;
            self.ended = packet.end;
            return .{
                .packet = packet_result,
                .sample_count = granule_range.sample_count,
                .pcm_start = granule_range.pcm_start,
                .pcm_end = granule_range.pcm_end,
            };
        }

        /// Inserts one silent block while retaining overlap and granule timing.
        pub fn concealMissingPacket(
            self: *Self,
            large_block: bool,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            if (self.audio_packet_count == std.math.maxInt(u64) or
                self.concealed_packet_count == std.math.maxInt(u64))
                return error.VorbisAudioPacketCountOverflow;
            if (self.concealed_packet_count > self.audio_packet_count)
                return error.InvalidVorbisPcmStreamState;
            if (identification.channel_count != channel_count or
                identification.small_block_size != small_block_size or
                identification.large_block_size != large_block_size)
                return error.VorbisDecoderConfigurationMismatch;
            if (identification.sample_rate == 0)
                return error.InvalidVorbisSampleRate;
            const block_size: u16 = if (large_block)
                large_block_size
            else
                small_block_size;
            const previous_size =
                self.overlap.channels[0].previousBlockSize();
            for (self.overlap.channels[1..]) |channel| {
                if (channel.previousBlockSize() != previous_size)
                    return error.InvalidVorbisChannelOverlapState;
            }
            const nominal_sample_count = if (previous_size == 0)
                0
            else
                previous_size / 4 + block_size / 4;
            if (end and nominal_sample_count == 0)
                return error.VorbisStreamEndedBeforePcm;
            if (outputs.len != channel_count)
                return error.InvalidVorbisAudioOutput;
            for (outputs) |output| {
                if (output.len < nominal_sample_count)
                    return error.VorbisOverlapOutputTooSmall;
            }
            const windowed_values = std.math.mul(
                usize,
                channel_count,
                block_size,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            if (windowed_scratch.len < windowed_values)
                return error.VorbisPcmStreamScratchTooSmall;
            const used_windowed = windowed_scratch[0..windowed_values];
            for (outputs) |output| {
                if (vorbisConstSlicesOverlap(
                    Float,
                    output,
                    used_windowed,
                )) return error.OverlappingVorbisPcmStreamScratch;
            }
            for (&self.overlap.channels) |*channel| {
                if (vorbisConstSlicesOverlap(
                    Float,
                    &channel.previous,
                    used_windowed,
                ) or vorbisConstSlicesOverlap(
                    Float,
                    &channel.pending,
                    used_windowed,
                )) return error.OverlappingVorbisPcmStreamScratch;
            }

            var granule_trial = self.granules;
            const granule_range: VorbisGranuleRange =
                if (nominal_sample_count == 0)
                    .{
                        .source_start = 0,
                        .sample_count = 0,
                        .pcm_start = null,
                        .pcm_end = null,
                    }
                else
                    try granule_trial.trim(
                        nominal_sample_count,
                        granule_position,
                        end,
                    );
            @memset(used_windowed, 0);
            var windowed_channels: [channel_count][]const Float = undefined;
            for (&windowed_channels, 0..) |*channel, index| {
                channel.* = used_windowed[index * block_size ..][0..block_size];
            }
            _ = try self.overlap.push(
                &windowed_channels,
                outputs,
            );
            if (granule_range.source_start != 0) {
                for (outputs) |output| {
                    std.mem.copyForwards(
                        Float,
                        output[0..granule_range.sample_count],
                        output[granule_range.source_start..][0..granule_range.sample_count],
                    );
                }
            }

            self.granules = granule_trial;
            self.audio_packet_count += 1;
            self.concealed_packet_count += 1;
            self.ended = end;
            return .{
                .block_size = block_size,
                .sample_count = granule_range.sample_count,
                .pcm_start = granule_range.pcm_start,
                .pcm_end = granule_range.pcm_end,
                .concealed_packet_count = self.concealed_packet_count,
            };
        }

        /// Selects the missing block size from the retained preceding block.
        pub fn concealMissingPacketUsingPreviousBlockSize(
            self: *Self,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            const previous_size =
                self.overlap.channels[0].previousBlockSize();
            for (self.overlap.channels[1..]) |channel| {
                if (channel.previousBlockSize() != previous_size)
                    return error.InvalidVorbisChannelOverlapState;
            }
            if (previous_size == 0)
                return error.VorbisPreviousBlockSizeUnavailable;
            if (previous_size != small_block_size and
                previous_size != large_block_size)
                return error.InvalidVorbisChannelOverlapState;
            return self.concealMissingPacket(
                previous_size == large_block_size,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing size from a following packet header when exact.
        pub fn concealMissingPacketUsingFollowingHeader(
            self: *Self,
            following: VorbisAudioPacketHeader,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisPcmConcealmentResult {
            if (self.ended)
                return error.VorbisPcmStreamAlreadyEnded;
            const large_block = try inferVorbisMissingPacketLargeBlock(
                identification,
                following,
            );
            return self.concealMissingPacket(
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }
    };
}

pub fn VorbisChainedPcmStreamDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    const StreamDecoder = VorbisPcmStreamDecoder(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    );

    return struct {
        const Self = @This();
        const MissingPacketBlockSelection = union(enum) {
            explicit: bool,
            previous,
        };

        stream: StreamDecoder,
        sample_rate: ?u32 = null,
        logical_stream_index: u64 = 0,
        completed_pcm: u64 = 0,
        current_stream_pcm: u64 = 0,
        started: bool = false,

        pub fn init() Self {
            return .{ .stream = .init() };
        }

        pub fn reset(self: *Self) void {
            self.stream.reset();
            self.sample_rate = null;
            self.logical_stream_index = 0;
            self.completed_pcm = 0;
            self.current_stream_pcm = 0;
            self.started = false;
        }

        pub fn beginLogicalStream(
            self: *Self,
            identification: VorbisIdentification,
        ) !void {
            try validateIdentification(identification);
            if (self.started and !self.stream.ended)
                return error.VorbisPreviousLogicalStreamNotEnded;
            if (self.sample_rate) |sample_rate| {
                if (identification.sample_rate != sample_rate)
                    return error.VorbisChainedSampleRateChanged;
            }

            var next_completed = self.completed_pcm;
            var next_index = self.logical_stream_index;
            if (self.started) {
                next_completed = std.math.add(
                    u64,
                    next_completed,
                    self.current_stream_pcm,
                ) catch return error.VorbisChainedPcmPositionOverflow;
                next_index = std.math.add(
                    u64,
                    next_index,
                    1,
                ) catch return error.VorbisLogicalStreamIndexOverflow;
            }

            self.stream.reset();
            self.sample_rate = identification.sample_rate;
            self.logical_stream_index = next_index;
            self.completed_pcm = next_completed;
            self.current_stream_pcm = 0;
            self.started = true;
        }

        pub fn decode(
            self: *Self,
            packet: Packet,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisPcmStreamScratch(Float),
        ) !VorbisChainedPcmStreamResult {
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            try validateIdentification(identification);
            const sample_rate = self.sample_rate orelse
                return error.VorbisLogicalStreamNotStarted;
            if (identification.sample_rate != sample_rate)
                return error.VorbisChainedSampleRateChanged;

            const global_start = std.math.add(
                u64,
                self.completed_pcm,
                self.current_stream_pcm,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            _ = std.math.add(
                u64,
                global_start,
                large_block_size / 2,
            ) catch return error.VorbisChainedPcmPositionOverflow;

            const decoded = try self.stream.decode(
                packet,
                identification,
                setup,
                outputs,
                scratch,
            );
            const global_end = global_start +
                @as(u64, @intCast(decoded.sample_count));
            self.current_stream_pcm +=
                @as(u64, @intCast(decoded.sample_count));
            return .{
                .stream = decoded,
                .logical_stream_index = self.logical_stream_index,
                .global_pcm_start = global_start,
                .global_pcm_end = global_end,
            };
        }

        pub fn concealMissingPacket(
            self: *Self,
            large_block: bool,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .{ .explicit = large_block },
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing block size from the retained preceding block.
        pub fn concealMissingPacketUsingPreviousBlockSize(
            self: *Self,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            return self.concealMissingPacketSelected(
                .previous,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        /// Selects the missing size from a following packet header when exact.
        pub fn concealMissingPacketUsingFollowingHeader(
            self: *Self,
            following: VorbisAudioPacketHeader,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            const large_block = try inferVorbisMissingPacketLargeBlock(
                identification,
                following,
            );
            return self.concealMissingPacket(
                large_block,
                granule_position,
                end,
                identification,
                outputs,
                windowed_scratch,
            );
        }

        fn concealMissingPacketSelected(
            self: *Self,
            selection: MissingPacketBlockSelection,
            granule_position: u64,
            end: bool,
            identification: VorbisIdentification,
            outputs: []const []Float,
            windowed_scratch: []Float,
        ) !VorbisChainedPcmConcealmentResult {
            if (!self.started)
                return error.VorbisLogicalStreamNotStarted;
            try validateIdentification(identification);
            const sample_rate = self.sample_rate orelse
                return error.VorbisLogicalStreamNotStarted;
            if (identification.sample_rate != sample_rate)
                return error.VorbisChainedSampleRateChanged;

            const global_start = std.math.add(
                u64,
                self.completed_pcm,
                self.current_stream_pcm,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            _ = std.math.add(
                u64,
                global_start,
                large_block_size / 2,
            ) catch return error.VorbisChainedPcmPositionOverflow;
            const concealed = switch (selection) {
                .explicit => |large_block| try self.stream.concealMissingPacket(
                    large_block,
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
                .previous => try self.stream.concealMissingPacketUsingPreviousBlockSize(
                    granule_position,
                    end,
                    identification,
                    outputs,
                    windowed_scratch,
                ),
            };
            const global_end = global_start +
                @as(u64, @intCast(concealed.sample_count));
            self.current_stream_pcm +=
                @as(u64, @intCast(concealed.sample_count));
            return .{
                .stream = concealed,
                .logical_stream_index = self.logical_stream_index,
                .global_pcm_start = global_start,
                .global_pcm_end = global_end,
            };
        }

        fn validateIdentification(
            identification: VorbisIdentification,
        ) !void {
            if (@as(usize, identification.channel_count) != channel_count or
                @as(usize, identification.small_block_size) !=
                    small_block_size or
                @as(usize, identification.large_block_size) !=
                    large_block_size)
                return error.VorbisChainedStreamGeometryChanged;
            if (identification.sample_rate == 0)
                return error.InvalidVorbisSampleRate;
        }
    };
}

pub fn applyVorbisFloor(
    comptime Float: type,
    spectrum: []Float,
    floor: []const Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor application requires f32 or f64");
    if (spectrum.len != floor.len)
        return error.InvalidVorbisSpectrumShape;
    for (spectrum, floor) |spectrum_value, floor_value| {
        if (!std.math.isFinite(spectrum_value) or
            !std.math.isFinite(floor_value) or
            !std.math.isFinite(spectrum_value * floor_value))
            return error.InvalidVorbisSpectrumValue;
    }
    for (spectrum, floor) |*spectrum_value, floor_value| {
        spectrum_value.* *= floor_value;
    }
}

pub const VorbisAudioPacketScratchRequirements = struct {
    spectrum_values: usize,
    floor_values: usize,
    coupling_values: usize,
    time_values: usize,
    classification_bytes: usize,
};

pub fn VorbisAudioPacketScratch(comptime Float: type) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis packet decoding requires f32 or f64");
    return struct {
        spectra: []Float,
        floor_curves: []Float,
        coupling: []Float,
        time: []Float,
        classifications: []u8,
    };
}

pub const VorbisAudioPacketResult = struct {
    header: VorbisAudioPacketHeader,
    decoded_bit_count: usize,
    truncated: bool,
    floor_truncated: bool,
    residue_truncated: bool,
};

pub fn requiredVorbisAudioPacketScratch(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioPacketScratchRequirements {
    const mapping = try validateVorbisAudioDecodeState(
        identification,
        setup,
        header,
    );
    const channel_count: usize = identification.channel_count;
    const coefficient_count: usize = header.block_size / 2;
    const spectrum_values = std.math.mul(
        usize,
        channel_count,
        coefficient_count,
    ) catch return error.VorbisAudioPacketSizeOverflow;
    const time_values = std.math.mul(
        usize,
        channel_count,
        header.block_size,
    ) catch return error.VorbisAudioPacketSizeOverflow;

    var classification_bytes: usize = 0;
    for (0..mapping.submap_count) |submap_index| {
        var bundle_count: usize = 0;
        for (mapping.channel_mux[0..channel_count]) |mux| {
            if (mux == submap_index) bundle_count += 1;
        }
        if (bundle_count == 0) continue;
        const residue_number = mapping.submaps[submap_index].residue;
        const residue = setup.residues[residue_number];
        try validateVorbisResidueState(residue, setup);
        classification_bytes = @max(
            classification_bytes,
            try requiredVorbisResidueClassifications(
                residue,
                coefficient_count,
                bundle_count,
            ),
        );
    }
    return .{
        .spectrum_values = spectrum_values,
        .floor_values = spectrum_values,
        .coupling_values = spectrum_values,
        .time_values = time_values,
        .classification_bytes = classification_bytes,
    };
}

pub fn VorbisAudioPacketDecoder(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
) type {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis packet decoding requires f32 or f64");
    if (channel_count == 0 or channel_count > 255)
        @compileError("Vorbis channel count must be from 1 to 255");
    if (small_block_size < 64 or large_block_size > 8192 or
        small_block_size > large_block_size or
        !std.math.isPowerOfTwo(small_block_size) or
        !std.math.isPowerOfTwo(large_block_size))
        @compileError("Vorbis block sizes must be ordered powers of two from 64 to 8192");

    return struct {
        const Self = @This();

        windows: VorbisWindowPlan(
            Float,
            small_block_size,
            large_block_size,
        ),
        small_mdct: VorbisInverseMdct(Float, small_block_size),
        large_mdct: VorbisInverseMdct(Float, large_block_size),

        pub fn init() Self {
            return .{
                .windows = .init(),
                .small_mdct = .init(),
                .large_mdct = .init(),
            };
        }

        /// Failures preserve every output channel.
        pub fn decode(
            self: *Self,
            packet: []const u8,
            identification: VorbisIdentification,
            setup: VorbisSetup,
            outputs: []const []Float,
            scratch: VorbisAudioPacketScratch(Float),
        ) !VorbisAudioPacketResult {
            if (identification.channel_count != channel_count or
                identification.small_block_size != small_block_size or
                identification.large_block_size != large_block_size)
                return error.VorbisDecoderConfigurationMismatch;
            const header = try parseVorbisAudioPacketHeader(
                packet,
                identification,
                setup,
            );
            const requirements = try requiredVorbisAudioPacketScratch(
                identification,
                setup,
                header,
            );
            try validateVorbisAudioPacketBuffers(
                Float,
                outputs,
                header.block_size,
                scratch,
                requirements,
            );

            const coefficient_count: usize = header.block_size / 2;
            const spectra =
                scratch.spectra[0..requirements.spectrum_values];
            const floor_curves =
                scratch.floor_curves[0..requirements.floor_values];
            const coupling =
                scratch.coupling[0..requirements.coupling_values];
            const time = scratch.time[0..requirements.time_values];
            const classifications =
                scratch.classifications[0..requirements.classification_bytes];
            @memset(spectra, 0);

            const mode = setup.modes[header.mode_number];
            const mapping = setup.mappings[mode.mapping];
            var reader = try VorbisPacketReader.init(
                packet,
                header.payload_bit_offset,
            );
            var no_residue = [_]bool{true} ** channel_count;
            var floor_truncated = false;
            var residue_truncated = false;
            var floor_zero_coefficients: [255]f64 = undefined;
            var floor_one_values: [65]u32 = undefined;
            for (0..channel_count) |channel| {
                const submap = mapping.submaps[
                    mapping.channel_mux[channel]
                ];
                const floor_curve =
                    floor_curves[channel * coefficient_count ..][0..coefficient_count];
                switch (setup.floors[submap.floor]) {
                    .zero => |floor| {
                        const floor_packet = try reader.decodeFloorZero(
                            setup,
                            submap.floor,
                            &floor_zero_coefficients,
                        );
                        floor_truncated =
                            floor_truncated or floor_packet.truncated;
                        no_residue[channel] = !floor_packet.used;
                        try synthesizeVorbisFloorZero(
                            Float,
                            floor,
                            floor_packet,
                            &floor_zero_coefficients,
                            floor_curve,
                        );
                    },
                    .one => |floor| {
                        const floor_packet = try reader.decodeFloorOne(
                            setup,
                            submap.floor,
                            &floor_one_values,
                        );
                        floor_truncated =
                            floor_truncated or floor_packet.truncated;
                        no_residue[channel] = !floor_packet.used;
                        try synthesizeVorbisFloorOne(
                            Float,
                            floor,
                            floor_packet,
                            &floor_one_values,
                            floor_curve,
                        );
                    },
                }
            }

            var channel_spectra: [channel_count][]Float = undefined;
            for (&channel_spectra, 0..) |*channel, index| {
                channel.* =
                    spectra[index * coefficient_count ..][0..coefficient_count];
            }

            if (!floor_truncated) {
                for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
                    if (!no_residue[step.magnitude] or
                        !no_residue[step.angle])
                    {
                        no_residue[step.magnitude] = false;
                        no_residue[step.angle] = false;
                    }
                }

                var bundle_outputs: [channel_count][]Float = undefined;
                var bundle_skips: [channel_count]bool = undefined;
                for (0..mapping.submap_count) |submap_index| {
                    var bundle_count: usize = 0;
                    for (0..channel_count) |channel| {
                        if (mapping.channel_mux[channel] != submap_index)
                            continue;
                        bundle_outputs[bundle_count] =
                            spectra[channel * coefficient_count ..][0..coefficient_count];
                        bundle_skips[bundle_count] = no_residue[channel];
                        bundle_count += 1;
                    }
                    if (bundle_count == 0) continue;
                    const residue_packet = try reader.decodeResidue(
                        Float,
                        setup,
                        mapping.submaps[submap_index].residue,
                        bundle_skips[0..bundle_count],
                        bundle_outputs[0..bundle_count],
                        classifications,
                    );
                    residue_truncated =
                        residue_truncated or residue_packet.truncated;
                }

                try inverseCoupleVorbisChannels(
                    Float,
                    mapping,
                    &channel_spectra,
                    coupling,
                );
                for (channel_spectra, 0..) |spectrum, channel| {
                    try applyVorbisFloor(
                        Float,
                        spectrum,
                        floor_curves[channel * coefficient_count ..][0..coefficient_count],
                    );
                }
            }

            const window = try self.windows.get(header);
            for (channel_spectra, 0..) |spectrum, channel| {
                const time_block =
                    time[channel * header.block_size ..][0..header.block_size];
                if (header.large_block) {
                    try self.large_mdct.processWindowed(
                        spectrum,
                        window,
                        time_block,
                    );
                } else {
                    try self.small_mdct.processWindowed(
                        spectrum,
                        window,
                        time_block,
                    );
                }
            }
            for (outputs, 0..) |output, channel| {
                @memcpy(
                    output,
                    time[channel * header.block_size ..][0..header.block_size],
                );
            }
            return .{
                .header = header,
                .decoded_bit_count = reader.bit_offset,
                .truncated = floor_truncated or residue_truncated,
                .floor_truncated = floor_truncated,
                .residue_truncated = residue_truncated,
            };
        }
    };
}

fn validateVorbisAudioDecodeState(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisMapping {
    if (identification.channel_count == 0 or
        setup.modes.len != setup.summary.mode_count or
        setup.floors.len != setup.summary.floor_count or
        setup.residues.len != setup.summary.residue_count or
        setup.mappings.len != setup.summary.mapping_count or
        header.mode_number >= setup.modes.len)
        return error.InvalidVorbisSetupState;
    const mode = setup.modes[header.mode_number];
    if (mode.large_block != header.large_block or
        mode.mapping >= setup.mappings.len)
        return error.InvalidVorbisSetupState;
    const mapping = setup.mappings[mode.mapping];
    if (mapping.submap_count == 0 or
        mapping.submap_count > mapping.submaps.len or
        mapping.coupling_step_count > mapping.coupling_steps.len)
        return error.InvalidVorbisMappingState;
    for (mapping.channel_mux[0..identification.channel_count]) |mux| {
        if (mux >= mapping.submap_count)
            return error.InvalidVorbisMappingState;
    }
    for (mapping.coupling_steps[0..mapping.coupling_step_count]) |step| {
        if (step.magnitude >= identification.channel_count or
            step.angle >= identification.channel_count or
            step.magnitude == step.angle)
            return error.InvalidVorbisMappingState;
    }
    for (mapping.submaps[0..mapping.submap_count]) |submap| {
        if (submap.floor >= setup.floors.len or
            submap.residue >= setup.residues.len)
            return error.InvalidVorbisMappingState;
    }
    return mapping;
}

fn validateVorbisAudioPacketBuffers(
    comptime Float: type,
    outputs: []const []Float,
    block_size: usize,
    scratch: VorbisAudioPacketScratch(Float),
    requirements: VorbisAudioPacketScratchRequirements,
) !void {
    if (outputs.len == 0 or outputs.len > 255)
        return error.InvalidVorbisAudioOutput;
    if (scratch.spectra.len < requirements.spectrum_values or
        scratch.floor_curves.len < requirements.floor_values or
        scratch.coupling.len < requirements.coupling_values or
        scratch.time.len < requirements.time_values or
        scratch.classifications.len < requirements.classification_bytes)
        return error.VorbisAudioPacketScratchTooSmall;

    const spectra = scratch.spectra[0..requirements.spectrum_values];
    const floor_curves =
        scratch.floor_curves[0..requirements.floor_values];
    const coupling = scratch.coupling[0..requirements.coupling_values];
    const time = scratch.time[0..requirements.time_values];
    const classifications =
        scratch.classifications[0..requirements.classification_bytes];
    const float_scratch = [_][]Float{
        spectra,
        floor_curves,
        coupling,
        time,
    };
    for (float_scratch, 0..) |values, index| {
        for (float_scratch[0..index]) |earlier| {
            if (vorbisSlicesOverlap(Float, values, earlier))
                return error.OverlappingVorbisAudioPacketScratch;
        }
        if (vorbisSliceOverlapsBytes(Float, values, classifications))
            return error.OverlappingVorbisAudioPacketScratch;
    }
    for (outputs, 0..) |output, channel| {
        if (output.len != block_size)
            return error.InvalidVorbisAudioOutput;
        for (outputs[0..channel]) |earlier| {
            if (vorbisSlicesOverlap(Float, output, earlier))
                return error.OverlappingVorbisAudioOutput;
        }
        for (float_scratch) |values| {
            if (vorbisSlicesOverlap(Float, output, values))
                return error.OverlappingVorbisAudioPacketScratch;
        }
        if (vorbisSliceOverlapsBytes(Float, output, classifications))
            return error.OverlappingVorbisAudioPacketScratch;
    }
}

fn vorbisResidueShape(
    residue: VorbisResidue,
    vector_length: usize,
    vector_count: usize,
) !VorbisResidueShape {
    if (vector_count == 0 or vector_count > 255 or
        residue.partition_size == 0)
        return error.InvalidVorbisResidueBundle;
    const available = if (residue.kind == .two)
        std.math.mul(usize, vector_length, vector_count) catch
            return error.InvalidVorbisResidueBundle
    else
        vector_length;
    const begin = @min(@as(usize, residue.begin), available);
    const end = @min(@as(usize, residue.end), available);
    const sample_count = end -| begin;
    const partition_count =
        sample_count / @as(usize, residue.partition_size);
    const classification_vectors =
        if (residue.kind == .two) 1 else vector_count;
    const required_classifications = std.math.mul(
        usize,
        partition_count,
        classification_vectors,
    ) catch return error.InvalidVorbisResidueBundle;
    return .{
        .begin = begin,
        .partition_count = partition_count,
        .required_classifications = required_classifications,
    };
}

const VorbisResidueRateMetrics = struct {
    squared_error: f128 = 0,
    weighted_squared_error: f128 = 0,
    audible_excess_power: f128 = 0,
    encoded_bits: u64 = 0,

    fn add(
        self: *VorbisResidueRateMetrics,
        other: VorbisResidueRateMetrics,
    ) !void {
        self.squared_error += other.squared_error;
        self.weighted_squared_error += other.weighted_squared_error;
        self.audible_excess_power += other.audible_excess_power;
        self.encoded_bits = std.math.add(
            u64,
            self.encoded_bits,
            other.encoded_bits,
        ) catch return error.VorbisAudioPacketSizeOverflow;
    }
};

const VorbisAdaptiveResidueCandidate = struct {
    metrics: VorbisResidueRateMetrics,
    encoded_bits: u32,
    lambda: f64,
};

fn planVorbisAdaptiveResidueCandidate(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
    lambda: f64,
) !VorbisAdaptiveResidueCandidate {
    try selectVorbisResidueClassificationsRateDistortion(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        classifications,
        lambda,
    );
    const metrics = try measureVorbisResidueRateDistortion(
        Float,
        setup,
        residue,
        shape,
        do_not_encode,
        inputs,
        noise_thresholds,
        partition_scratch,
        vector_scratch,
        classifications,
    );
    return .{
        .metrics = metrics,
        .encoded_bits = std.math.cast(
            u32,
            metrics.encoded_bits,
        ) orelse return error.VorbisAudioPacketSizeOverflow,
        .lambda = lambda,
    };
}

fn selectVorbisResidueClassificationsRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
    lambda: f64,
) !void {
    @memset(classifications, 0);
    if (shape.partition_count == 0) return;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group_count = @min(
                @as(usize, classbook.dimensions),
                shape.partition_count - partition,
            );
            var best_entry: ?u32 = null;
            var best_score = std.math.inf(f128);
            var best_bits: u64 = std.math.maxInt(u64);
            for (classbook_entries, 0..) |entry, entry_number| {
                if (entry.length == 0) continue;
                var encoded: u32 = @intCast(entry_number);
                var omitted =
                    @as(usize, classbook.dimensions) - group_count;
                while (omitted != 0) : (omitted -= 1)
                    encoded /= residue.classification_count;
                var metrics = VorbisResidueRateMetrics{
                    .encoded_bits = entry.length,
                };
                var index = group_count;
                while (index != 0) {
                    index -= 1;
                    const classification: u8 = @intCast(
                        encoded % residue.classification_count,
                    );
                    encoded /= residue.classification_count;
                    try metrics.add(
                        try measureVorbisResiduePartitionRateDistortion(
                            Float,
                            setup,
                            residue,
                            shape,
                            inputs,
                            noise_thresholds,
                            vector,
                            partition + index,
                            classification,
                            partition_scratch,
                            vector_scratch,
                        ),
                    );
                }
                const score =
                    metrics.weighted_squared_error +
                    @as(f128, lambda) *
                        @as(f128, @floatFromInt(metrics.encoded_bits));
                if (score < best_score or
                    (score == best_score and
                        (metrics.encoded_bits < best_bits or
                            (metrics.encoded_bits == best_bits and
                                (best_entry == null or
                                    entry_number < best_entry.?)))))
                {
                    best_score = score;
                    best_bits = metrics.encoded_bits;
                    best_entry = @intCast(entry_number);
                }
            }
            const selected = best_entry orelse
                return error.InvalidVorbisSetupState;
            var encoded = selected;
            var omitted =
                @as(usize, classbook.dimensions) - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                classifications[
                    vector * shape.partition_count + partition + index
                ] = @intCast(encoded % residue.classification_count);
                encoded /= residue.classification_count;
            }
            partition += group_count;
        }
    }
}

fn measureVorbisResidueRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
) !VorbisResidueRateMetrics {
    var total = VorbisResidueRateMetrics{};
    const classbook = setup.codebooks[residue.classbook];
    const classwords: usize = classbook.dimensions;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group = classifications[vector * shape.partition_count + partition ..][0..@min(
                classwords,
                shape.partition_count - partition,
            )];
            const classword = findVorbisResidueClassword(
                setup,
                residue,
                group,
            ) orelse
                return error.UnencodableVorbisResidueClassifications;
            const codeword = try writableVorbisCodeword(
                setup,
                residue.classbook,
                classword,
            );
            total.encoded_bits = std.math.add(
                u64,
                total.encoded_bits,
                codeword.entry.length,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            partition += group.len;
        }
        for (0..shape.partition_count) |partition_index| {
            try total.add(
                try measureVorbisResiduePartitionRateDistortion(
                    Float,
                    setup,
                    residue,
                    shape,
                    inputs,
                    noise_thresholds,
                    vector,
                    partition_index,
                    classifications[
                        vector * shape.partition_count + partition_index
                    ],
                    partition_scratch,
                    vector_scratch,
                ),
            );
        }
    }
    return total;
}

fn measureVorbisResiduePartitionRateDistortion(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    vector: usize,
    partition: usize,
    classification: u8,
    partition_scratch: []Float,
    vector_scratch: []Float,
) !VorbisResidueRateMetrics {
    const partition_size: usize = residue.partition_size;
    const partition_values = partition_scratch[0..partition_size];
    const partition_offset =
        shape.begin + partition * partition_size;
    for (partition_values, 0..) |*destination, index| {
        destination.* = vorbisResidueInputValue(
            Float,
            residue.kind,
            inputs,
            vector,
            partition_offset + index,
        );
    }

    var metrics = VorbisResidueRateMetrics{};
    for (0..8) |pass| {
        const book_number = residue.books[classification][pass];
        if (book_number < 0) continue;
        const codebook_number: u8 = @intCast(book_number);
        const codebook = setup.codebooks[codebook_number];
        const dimensions: usize = codebook.dimensions;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            const target = vector_scratch[0..dimensions];
            for (target, 0..) |*value, component| {
                value.* = partition_values[
                    vorbisResiduePartitionIndex(
                        residue.kind,
                        dimensions,
                        vector_count,
                        entry_index,
                        component,
                    )
                ];
            }
            const quantized = try quantizeVorbisVector(
                Float,
                setup,
                codebook_number,
                target,
            );
            const codeword = try writableVorbisCodeword(
                setup,
                codebook_number,
                quantized.entry,
            );
            metrics.encoded_bits = std.math.add(
                u64,
                metrics.encoded_bits,
                codeword.entry.length,
            ) catch return error.VorbisAudioPacketSizeOverflow;
            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            var decoded = VorbisVectorCursor{
                .codebook = codebook,
                .multiplicands = multiplicands,
                .entry = quantized.entry,
                .explicit_offset = @as(u64, quantized.entry) * codebook.dimensions,
            };
            for (0..dimensions) |component| {
                const index = vorbisResiduePartitionIndex(
                    residue.kind,
                    dimensions,
                    vector_count,
                    entry_index,
                    component,
                );
                partition_values[index] -=
                    @as(Float, @floatCast(decoded.next()));
            }
        }
    }

    for (partition_values, 0..) |residual, index| {
        const wide_residual: f128 = @floatCast(residual);
        const threshold: f128 = @floatCast(vorbisResidueInputValue(
            Float,
            residue.kind,
            noise_thresholds,
            vector,
            partition_offset + index,
        ));
        const squared = wide_residual * wide_residual;
        const ratio = wide_residual / threshold;
        const excess = @max(@abs(wide_residual) - threshold, 0);
        metrics.squared_error += squared;
        metrics.weighted_squared_error += ratio * ratio;
        metrics.audible_excess_power += excess * excess;
    }
    return metrics;
}

fn selectVorbisResidueClassifications(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []u8,
) !void {
    @memset(classifications, 0);
    if (shape.partition_count == 0) return;
    const classbook = setup.codebooks[residue.classbook];
    const classbook_entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classbook.entry_offset,
        classbook.entries,
    );
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            const group_count = @min(
                @as(usize, classbook.dimensions),
                shape.partition_count - partition,
            );
            var best_entry: ?u32 = null;
            var best_error = std.math.inf(f128);
            for (classbook_entries, 0..) |entry, entry_number| {
                if (entry.length == 0) continue;
                var encoded: u32 = @intCast(entry_number);
                var omitted =
                    @as(usize, classbook.dimensions) - group_count;
                while (omitted != 0) : (omitted -= 1)
                    encoded /= residue.classification_count;
                var candidate_error: f128 = 0;
                var index = group_count;
                while (index != 0) {
                    index -= 1;
                    const classification: u8 = @intCast(
                        encoded % residue.classification_count,
                    );
                    encoded /= residue.classification_count;
                    candidate_error +=
                        try quantizeVorbisResiduePartition(
                            Float,
                            setup,
                            residue,
                            shape,
                            inputs,
                            vector,
                            partition + index,
                            classification,
                            partition_scratch,
                            vector_scratch,
                            null,
                            null,
                            null,
                        );
                }
                if (candidate_error < best_error) {
                    best_error = candidate_error;
                    best_entry = @intCast(entry_number);
                }
            }
            const selected = best_entry orelse
                return error.InvalidVorbisSetupState;
            var encoded = selected;
            var omitted =
                @as(usize, classbook.dimensions) - group_count;
            while (omitted != 0) : (omitted -= 1)
                encoded /= residue.classification_count;
            var index = group_count;
            while (index != 0) {
                index -= 1;
                classifications[
                    vector * shape.partition_count + partition + index
                ] = @intCast(encoded % residue.classification_count);
                encoded /= residue.classification_count;
            }
            partition += group_count;
        }
    }
}

fn countVorbisResidueQuantizedEntries(
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    classifications: []const u8,
) !usize {
    var count: usize = 0;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else do_not_encode.len;
    for (0..8) |pass| {
        for (0..shape.partition_count) |partition| {
            for (0..effective_vectors) |vector| {
                if (residue.kind != .two and do_not_encode[vector])
                    continue;
                const classification = classifications[
                    vector * shape.partition_count + partition
                ];
                const book_number = residue.books[classification][pass];
                if (book_number < 0) continue;
                const dimensions: usize =
                    setup.codebooks[@intCast(book_number)].dimensions;
                count = std.math.add(
                    usize,
                    count,
                    @as(usize, residue.partition_size) / dimensions,
                ) catch return error.VorbisResidueEntryCountOverflow;
            }
        }
    }
    return count;
}

fn measureVorbisResidueQuantization(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
) !f128 {
    var total_error: f128 = 0;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..effective_vectors) |vector| {
        if (residue.kind != .two and do_not_encode[vector])
            continue;
        for (0..shape.partition_count) |partition| {
            total_error += try quantizeVorbisResiduePartition(
                Float,
                setup,
                residue,
                shape,
                inputs,
                vector,
                partition,
                classifications[
                    vector * shape.partition_count + partition
                ],
                partition_scratch,
                vector_scratch,
                null,
                null,
                null,
            );
        }
    }
    return total_error;
}

fn assembleVorbisResidueEntries(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    partition_scratch: []Float,
    vector_scratch: []Float,
    classifications: []const u8,
    entries: []u32,
    entry_offset: *usize,
) !void {
    const classwords: usize =
        setup.codebooks[residue.classbook].dimensions;
    const effective_vectors =
        if (residue.kind == .two) @as(usize, 1) else inputs.len;
    for (0..8) |pass| {
        var partition: usize = 0;
        while (partition < shape.partition_count) {
            var classword_index: usize = 0;
            while (classword_index < classwords and
                partition < shape.partition_count) : (classword_index += 1)
            {
                for (0..effective_vectors) |vector| {
                    if (residue.kind != .two and
                        do_not_encode[vector])
                        continue;
                    const classification = classifications[
                        vector * shape.partition_count + partition
                    ];
                    if (residue.books[classification][pass] < 0)
                        continue;
                    _ = try quantizeVorbisResiduePartition(
                        Float,
                        setup,
                        residue,
                        shape,
                        inputs,
                        vector,
                        partition,
                        classification,
                        partition_scratch,
                        vector_scratch,
                        pass,
                        entries,
                        entry_offset,
                    );
                }
                partition += 1;
            }
        }
    }
}

fn quantizeVorbisResiduePartition(
    comptime Float: type,
    setup: VorbisSetup,
    residue: VorbisResidue,
    shape: VorbisResidueShape,
    inputs: []const []const Float,
    vector: usize,
    partition: usize,
    classification: u8,
    partition_scratch: []Float,
    vector_scratch: []Float,
    record_pass: ?usize,
    entries: ?[]u32,
    entry_offset: ?*usize,
) !f128 {
    const partition_size: usize = residue.partition_size;
    const partition_values = partition_scratch[0..partition_size];
    const partition_offset =
        shape.begin + partition * partition_size;
    for (partition_values, 0..) |*destination, index| {
        destination.* = vorbisResidueInputValue(
            Float,
            residue.kind,
            inputs,
            vector,
            partition_offset + index,
        );
    }

    for (0..8) |pass| {
        const book_number = residue.books[classification][pass];
        if (book_number < 0) continue;
        const codebook_number: u8 = @intCast(book_number);
        const codebook = setup.codebooks[codebook_number];
        const dimensions: usize = codebook.dimensions;
        const vector_count = partition_size / dimensions;
        for (0..vector_count) |entry_index| {
            const target = vector_scratch[0..dimensions];
            for (target, 0..) |*value, component| {
                value.* = partition_values[
                    vorbisResiduePartitionIndex(
                        residue.kind,
                        dimensions,
                        vector_count,
                        entry_index,
                        component,
                    )
                ];
            }
            const quantized = try quantizeVorbisVector(
                Float,
                setup,
                codebook_number,
                target,
            );
            if (record_pass != null and record_pass.? == pass) {
                const offset = entry_offset orelse
                    return error.InvalidVorbisResidueEncoding;
                const output_entries = entries orelse
                    return error.InvalidVorbisResidueEncoding;
                if (offset.* >= output_entries.len)
                    return error.VorbisResidueEntryOutputTooSmall;
                output_entries[offset.*] = quantized.entry;
                offset.* += 1;
            }

            const multiplicands = try vorbisSetupSlice(
                u32,
                setup.codebook_multiplicands,
                codebook.multiplicand_offset,
                codebook.multiplicand_count,
            );
            var decoded = VorbisVectorCursor{
                .codebook = codebook,
                .multiplicands = multiplicands,
                .entry = quantized.entry,
                .explicit_offset = @as(u64, quantized.entry) * codebook.dimensions,
            };
            for (0..dimensions) |component| {
                const index = vorbisResiduePartitionIndex(
                    residue.kind,
                    dimensions,
                    vector_count,
                    entry_index,
                    component,
                );
                partition_values[index] -=
                    @as(Float, @floatCast(decoded.next()));
            }
        }
    }

    var squared_error: f128 = 0;
    for (partition_values) |value| {
        const wide: f128 = @floatCast(value);
        squared_error += wide * wide;
    }
    return squared_error;
}

fn vorbisResiduePartitionIndex(
    kind: VorbisResidueKind,
    dimensions: usize,
    vector_count: usize,
    entry_index: usize,
    component: usize,
) usize {
    return switch (kind) {
        .zero => entry_index + component * vector_count,
        .one, .two => entry_index * dimensions + component,
    };
}

fn vorbisResidueInputValue(
    comptime Float: type,
    kind: VorbisResidueKind,
    inputs: []const []const Float,
    vector: usize,
    flat_index: usize,
) Float {
    if (kind != .two) return inputs[vector][flat_index];
    return inputs[flat_index % inputs.len][flat_index / inputs.len];
}

fn rejectVorbisResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    scratch: VorbisResidueQuantizationScratch(Float),
    classifications: []u8,
    entries: []u32,
) !void {
    if (vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.vector,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.partition,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        Float,
        scratch.vector,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        scratch.classifications,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        u32,
        entries,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        bool,
        do_not_encode,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u8,
        classifications,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u32,
        entries,
        u8,
        scratch.classifications,
    )) return error.OverlappingVorbisResidueQuantization;
    for (inputs) |input| {
        if (vorbisTypedSlicesOverlap(
            u8,
            classifications,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            u32,
            entries,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            Float,
            scratch.partition,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            Float,
            scratch.vector,
            Float,
            input,
        ) or vorbisTypedSlicesOverlap(
            u8,
            scratch.classifications,
            Float,
            input,
        )) return error.OverlappingVorbisResidueQuantization;
    }
    const classification_bytes = std.mem.sliceAsBytes(classifications);
    const entry_bytes = std.mem.sliceAsBytes(entries);
    const partition_bytes = std.mem.sliceAsBytes(scratch.partition);
    const vector_bytes = std.mem.sliceAsBytes(scratch.vector);
    const scratch_classification_bytes =
        std.mem.sliceAsBytes(scratch.classifications);
    if (vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        entry_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        partition_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        vector_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        scratch_classification_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        scratch_classification_bytes,
    )) return error.OverlappingVorbisResidueQuantization;
}

fn rejectVorbisAdaptiveResidueQuantizationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    do_not_encode: []const bool,
    inputs: []const []const Float,
    noise_thresholds: []const []const Float,
    scratch: VorbisAdaptiveResidueScratch(Float),
    classifications: []u8,
    entries: []u32,
) !void {
    try rejectVorbisResidueQuantizationOverlap(
        Float,
        setup,
        do_not_encode,
        inputs,
        .{
            .partition = scratch.partition,
            .vector = scratch.vector,
            .classifications = scratch.classifications,
        },
        classifications,
        entries,
    );
    const best = scratch.best_classifications;
    if (vorbisTypedSlicesOverlap(
        u8,
        best,
        Float,
        scratch.partition,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        Float,
        scratch.vector,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u8,
        scratch.classifications,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u8,
        classifications,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        u32,
        entries,
    ) or vorbisTypedSlicesOverlap(
        u8,
        best,
        bool,
        do_not_encode,
    )) return error.OverlappingVorbisResidueQuantization;
    for (inputs) |input| {
        if (vorbisTypedSlicesOverlap(u8, best, Float, input))
            return error.OverlappingVorbisResidueQuantization;
    }
    for (noise_thresholds) |thresholds| {
        if (vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            Float,
            scratch.partition,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            Float,
            scratch.vector,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            scratch.classifications,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            best,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u8,
            classifications,
        ) or vorbisTypedSlicesOverlap(
            Float,
            thresholds,
            u32,
            entries,
        )) return error.OverlappingVorbisResidueQuantization;
    }
    const best_bytes = std.mem.sliceAsBytes(best);
    if (vorbisSliceOverlapsBytes(
        VorbisCodebook,
        setup.codebooks,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisCodebookEntry,
        setup.codebook_entries,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        VorbisHuffmanNode,
        setup.huffman_nodes,
        best_bytes,
    ) or vorbisSliceOverlapsBytes(
        u32,
        setup.codebook_multiplicands,
        best_bytes,
    )) return error.OverlappingVorbisResidueQuantization;
}

fn validateVorbisResidueState(
    residue: VorbisResidue,
    setup: VorbisSetup,
) !void {
    if (residue.partition_size == 0 or
        residue.classification_count == 0 or
        residue.classification_count > residue.cascades.len or
        residue.classbook >= setup.codebooks.len)
        return error.InvalidVorbisSetupState;
    const classbook = setup.codebooks[residue.classbook];
    try validateVorbisScalarCodebookState(classbook, setup);
    if (classbook.dimensions == 0 or !powerAtMost(
        residue.classification_count,
        classbook.dimensions,
        classbook.entries,
    )) return error.InvalidVorbisSetupState;

    for (
        residue.cascades[0..residue.classification_count],
        0..,
    ) |cascade, classification| {
        for (0..8) |pass| {
            const selected =
                cascade & (@as(u8, 1) << @intCast(pass)) != 0;
            const book_number = residue.books[classification][pass];
            if (!selected) {
                if (book_number != -1)
                    return error.InvalidVorbisSetupState;
                continue;
            }
            if (book_number < 0 or book_number >= setup.codebooks.len)
                return error.InvalidVorbisSetupState;
            const codebook = setup.codebooks[@intCast(book_number)];
            try validateVorbisVectorCodebookState(codebook, setup);
            if (residue.partition_size % codebook.dimensions != 0)
                return error.InvalidVorbisSetupState;
        }
    }
}

fn validateVorbisScalarCodebookState(
    codebook: VorbisCodebook,
    setup: VorbisSetup,
) !void {
    if (codebook.entries == 0 or codebook.active_entry_count == 0 or
        codebook.active_entry_count > codebook.entries)
        return error.InvalidVorbisSetupState;
    const entry_start =
        std.math.cast(usize, codebook.entry_offset) orelse
        return error.InvalidVorbisSetupState;
    if (entry_start > setup.codebook_entries.len or
        codebook.entries > setup.codebook_entries.len - entry_start)
        return error.InvalidVorbisSetupState;
    if (codebook.active_entry_count > 1) {
        const node_start =
            std.math.cast(usize, codebook.tree_node_offset) orelse
            return error.InvalidVorbisSetupState;
        if (node_start > setup.huffman_nodes.len or
            codebook.tree_node_count >
                setup.huffman_nodes.len - node_start or
            codebook.tree_node_count == 0)
            return error.InvalidVorbisSetupState;
    }
}

fn validateVorbisVectorCodebookState(
    codebook: VorbisCodebook,
    setup: VorbisSetup,
) !void {
    try validateVorbisScalarCodebookState(codebook, setup);
    if (codebook.lookup_type == 0 or codebook.lookup_type > 2 or
        codebook.dimensions == 0)
        return error.InvalidVorbisSetupState;
    const multiplicand_start =
        std.math.cast(usize, codebook.multiplicand_offset) orelse
        return error.InvalidVorbisSetupState;
    if (multiplicand_start > setup.codebook_multiplicands.len or
        codebook.multiplicand_count >
            setup.codebook_multiplicands.len - multiplicand_start)
        return error.InvalidVorbisSetupState;
    const expected: u64 = if (codebook.lookup_type == 1)
        vorbisLookupOneValues(codebook.entries, codebook.dimensions)
    else
        @as(u64, codebook.entries) * codebook.dimensions;
    if (codebook.multiplicand_count == 0 or
        codebook.multiplicand_count != expected)
        return error.InvalidVorbisSetupState;
}

fn vorbisSlicesOverlap(
    comptime Element: type,
    first: []Element,
    second: []Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(Element)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Element)) catch return true,
    );
}

fn vorbisConstSlicesOverlap(
    comptime Element: type,
    first: []const Element,
    second: []const Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(Element)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Element)) catch return true,
    );
}

fn vorbisSliceOverlapsBytes(
    comptime Element: type,
    values: []const Element,
    bytes: []const u8,
) bool {
    if (values.len == 0 or bytes.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(values.ptr),
        std.math.mul(usize, values.len, @sizeOf(Element)) catch return true,
        @intFromPtr(bytes.ptr),
        bytes.len,
    );
}

fn vorbisTypedSlicesOverlap(
    comptime First: type,
    first: []const First,
    comptime Second: type,
    second: []const Second,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    return byteRangesOverlap(
        @intFromPtr(first.ptr),
        std.math.mul(usize, first.len, @sizeOf(First)) catch return true,
        @intFromPtr(second.ptr),
        std.math.mul(usize, second.len, @sizeOf(Second)) catch return true,
    );
}

fn byteRangesOverlap(
    first_start: usize,
    first_length: usize,
    second_start: usize,
    second_length: usize,
) bool {
    const first_end =
        std.math.add(usize, first_start, first_length) catch return true;
    const second_end =
        std.math.add(usize, second_start, second_length) catch return true;
    return first_start < second_end and second_start < first_end;
}

fn validateVorbisFloorZeroState(
    floor: VorbisFloorZero,
    codebooks: []const VorbisCodebook,
) !void {
    try validateVorbisFloorZeroSynthesisState(floor);
    for (floor.books[0..floor.book_count]) |book_number| {
        if (book_number >= codebooks.len)
            return error.InvalidVorbisSetupState;
        const codebook = codebooks[book_number];
        if (codebook.dimensions == 0 or codebook.lookup_type == 0 or
            codebook.lookup_type > 2)
            return error.InvalidVorbisSetupState;
    }
}

fn validateVorbisFloorZeroSynthesisState(
    floor: VorbisFloorZero,
) !void {
    if (floor.order == 0 or floor.rate == 0 or
        floor.bark_map_size == 0 or floor.book_count == 0 or
        floor.book_count > floor.books.len)
        return error.InvalidVorbisSetupState;
}

fn validateVorbisFloorOneState(
    floor: VorbisFloorOne,
    codebooks: ?[]const VorbisCodebook,
) !void {
    if (floor.partition_count > floor.partition_classes.len or
        floor.class_count > floor.classes.len or
        floor.multiplier == 0 or floor.multiplier > 4 or
        floor.point_count < 2 or floor.point_count > floor.x_list.len or
        floor.x_list[0] != 0 or
        floor.x_list[1] != @as(u16, 1) << @intCast(floor.range_bits))
        return error.InvalidVorbisSetupState;

    var expected_points: usize = 2;
    for (floor.partition_classes[0..floor.partition_count]) |class_index| {
        if (class_index >= floor.class_count)
            return error.InvalidVorbisSetupState;
        expected_points += floor.classes[class_index].dimensions;
        if (expected_points > floor.x_list.len)
            return error.InvalidVorbisSetupState;
    }
    if (expected_points != floor.point_count)
        return error.InvalidVorbisSetupState;
    for (floor.x_list[0..floor.point_count], 0..) |point, index| {
        if (index >= 2 and
            (point == 0 or point >= floor.x_list[1]))
            return error.InvalidVorbisSetupState;
        for (floor.x_list[0..index]) |earlier| {
            if (point == earlier) return error.InvalidVorbisSetupState;
        }
    }

    for (floor.classes[0..floor.class_count]) |class| {
        if (class.dimensions == 0 or class.subclass_bits > 3)
            return error.InvalidVorbisSetupState;
        if (class.subclass_bits == 0) {
            if (class.masterbook != -1)
                return error.InvalidVorbisSetupState;
        } else if (class.masterbook < 0) {
            return error.InvalidVorbisSetupState;
        }
        if (codebooks) |books| {
            if (class.masterbook >= books.len and class.masterbook >= 0)
                return error.InvalidVorbisSetupState;
        }
        const subclass_count =
            @as(usize, 1) << @intCast(class.subclass_bits);
        for (class.subclass_books[0..subclass_count]) |book| {
            if (book < -1)
                return error.InvalidVorbisSetupState;
            if (codebooks) |books| {
                if (book >= books.len)
                    return error.InvalidVorbisSetupState;
            }
        }
    }
}

pub fn synthesizeVorbisFloorZero(
    comptime Float: type,
    floor: VorbisFloorZero,
    packet: VorbisFloorZeroPacket,
    coefficients: []const f64,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor synthesis requires f32 or f64 output");
    try validateVorbisFloorZeroSynthesisState(floor);
    if (!packet.used) {
        @memset(output, 0);
        return;
    }
    if (floor.amplitude_bits == 0 or
        packet.coefficient_count != floor.order or
        coefficients.len < floor.order)
        return error.InvalidVorbisFloorPacketState;
    const maximum_amplitude =
        (@as(u64, 1) << floor.amplitude_bits) - 1;
    if (packet.amplitude == 0 or packet.amplitude > maximum_amplitude)
        return error.InvalidVorbisFloorPacketState;

    var cosines: [255]f64 = undefined;
    for (coefficients[0..floor.order], 0..) |coefficient, index| {
        if (!std.math.isFinite(coefficient))
            return error.InvalidVorbisFloorPacketState;
        cosines[index] = 2.0 * @cos(coefficient);
    }
    const amplitude =
        @as(f64, @floatFromInt(packet.amplitude)) /
        @as(f64, @floatFromInt(maximum_amplitude)) *
        @as(f64, floor.amplitude_offset);
    const bark_limit = vorbisBark(@as(f64, floor.rate) / 2.0);
    const map_scale = @as(f64, floor.bark_map_size) / bark_limit;
    for (output, 0..) |*value, index| {
        const frequency =
            (@as(f64, floor.rate) / 2.0) /
            @as(f64, @floatFromInt(output.len)) *
            @as(f64, @floatFromInt(index));
        const mapped: u16 = @intFromFloat(@min(
            @floor(vorbisBark(frequency) * map_scale),
            @as(f64, floor.bark_map_size - 1),
        ));
        const angular =
            std.math.pi * @as(f64, @floatFromInt(mapped)) /
            @as(f64, floor.bark_map_size);
        const frequency_cosine = 2.0 * @cos(angular);
        var log_p: f64 = @log(0.5);
        var log_q: f64 = @log(0.5);
        var coefficient_index: usize = 1;
        while (coefficient_index < floor.order) : (coefficient_index += 2) {
            log_q += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index - 1],
            );
            log_p += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index],
            );
        }
        if (coefficient_index == floor.order) {
            log_q += vorbisLogAbsolute(
                frequency_cosine - cosines[coefficient_index - 1],
            );
            log_p = 2.0 * log_p +
                vorbisLogAbsolute(
                    4.0 - frequency_cosine * frequency_cosine,
                );
            log_q *= 2.0;
        } else {
            log_p = 2.0 * log_p +
                vorbisLogAbsolute(2.0 - frequency_cosine);
            log_q = 2.0 * log_q +
                vorbisLogAbsolute(2.0 + frequency_cosine);
        }
        const inverse_denominator =
            @exp(-0.5 * vorbisLogAddExp(log_p, log_q));
        const linear = @exp(
            (amplitude * inverse_denominator -
                @as(f64, floor.amplitude_offset)) *
                0.11512925,
        );
        value.* = @floatCast(linear);
    }
}

fn vorbisLogAbsolute(value: f64) f64 {
    const magnitude = @abs(value);
    return if (magnitude == 0)
        -std.math.inf(f64)
    else
        @log(magnitude);
}

fn vorbisLogAddExp(left: f64, right: f64) f64 {
    const maximum = @max(left, right);
    if (maximum == -std.math.inf(f64)) return maximum;
    return maximum + @log(
        @exp(left - maximum) + @exp(right - maximum),
    );
}

fn vorbisBark(frequency: f64) f64 {
    return 13.1 * std.math.atan(0.00074 * frequency) +
        2.24 * std.math.atan(0.0000000185 * frequency * frequency) +
        0.0001 * frequency;
}

pub fn synthesizeVorbisFloorOne(
    comptime Float: type,
    floor: VorbisFloorOne,
    packet: VorbisFloorOnePacket,
    y_values: []const u32,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor synthesis requires f32 or f64 output");
    try validateVorbisFloorOneState(floor, null);
    if (!packet.used) {
        @memset(output, 0);
        return;
    }
    if (packet.value_count != floor.point_count or
        y_values.len < floor.point_count)
        return error.InvalidVorbisFloorPacketState;

    const ranges = [_]i32{ 256, 128, 86, 64 };
    const range = ranges[floor.multiplier - 1];
    var final_y = [_]i32{0} ** 65;
    var render = [_]bool{false} ** 65;
    final_y[0] = @intCast(@min(y_values[0], @as(u32, @intCast(range - 1))));
    final_y[1] = @intCast(@min(y_values[1], @as(u32, @intCast(range - 1))));
    render[0] = true;
    render[1] = true;

    for (2..floor.point_count) |index| {
        const low = vorbisFloorLowNeighbor(floor.x_list[0..floor.point_count], index);
        const high = vorbisFloorHighNeighbor(floor.x_list[0..floor.point_count], index);
        const predicted = vorbisFloorRenderPoint(
            floor.x_list[low],
            final_y[low],
            floor.x_list[high],
            final_y[high],
            floor.x_list[index],
        );
        if (y_values[index] != 0) {
            render[low] = true;
            render[high] = true;
            render[index] = true;
        }
        final_y[index] = decodeVorbisFloorOneValue(
            predicted,
            range,
            y_values[index],
        );
    }

    var order: [65]u7 = undefined;
    for (order[0..floor.point_count], 0..) |*destination, index| {
        destination.* = @intCast(index);
    }
    std.mem.sort(
        u7,
        order[0..floor.point_count],
        &floor.x_list,
        struct {
            fn lessThan(
                points: *const [65]u16,
                left: u7,
                right: u7,
            ) bool {
                return points[left] < points[right];
            }
        }.lessThan,
    );

    var low_x: u16 = 0;
    var low_y: i32 = final_y[0] * floor.multiplier;
    for (order[1..floor.point_count]) |index| {
        if (!render[index]) continue;
        const high_x = floor.x_list[index];
        const high_y = final_y[index] * floor.multiplier;
        renderVorbisFloorLine(
            Float,
            low_x,
            low_y,
            high_x,
            high_y,
            output,
        );
        low_x = high_x;
        low_y = high_y;
        if (low_x >= output.len) return;
    }
    if (low_x < output.len) {
        @memset(
            output[low_x..],
            vorbisFloorOneInverseDb(Float, @intCast(low_y)),
        );
    }
}

pub fn requiredVorbisAudioFloorOneStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioFloorOneStorageRequirements {
    const mapping = try validateVorbisAudioFloorOneState(
        identification,
        setup,
        header,
    );
    var y_values: usize = 0;
    for (mapping.channel_mux[0..identification.channel_count]) |mux| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => return error.UnsupportedVorbisFloorZeroAnalysis,
        };
        try validateVorbisFloorOneState(floor, setup.codebooks);
        y_values = std.math.add(
            usize,
            y_values,
            floor.point_count,
        ) catch return error.VorbisAudioPacketSizeOverflow;
    }
    const curve_values = std.math.mul(
        usize,
        identification.channel_count,
        header.block_size / 2,
    ) catch return error.VorbisAudioPacketSizeOverflow;
    return .{
        .encodings = identification.channel_count,
        .y_values = y_values,
        .curve_values = curve_values,
    };
}

pub fn fitVorbisAudioFloorOne(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    floor_targets: []const []const Float,
    scratch: VorbisAudioFloorOneScratch(Float),
    storage: VorbisAudioFloorOneStorage(Float),
) !VorbisAudioFloorOnePlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor analysis requires f32 or f64");
    const requirements = try requiredVorbisAudioFloorOneStorage(
        identification,
        setup,
        header,
    );
    if (floor_targets.len != requirements.encodings)
        return error.InvalidVorbisSpectrumBundle;
    const coefficient_count = header.block_size / 2;
    for (floor_targets) |target| {
        if (target.len != coefficient_count)
            return error.InvalidVorbisSpectrumShape;
        for (target) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisSpectrumValue;
        }
    }
    if (scratch.y_values.len < requirements.y_values or
        scratch.curves.len < requirements.curve_values)
        return error.VorbisAudioFloorScratchTooSmall;
    if (storage.encodings.len < requirements.encodings or
        storage.y_values.len < requirements.y_values or
        storage.curves.len < requirements.curve_values)
        return error.VorbisAudioFloorStorageTooSmall;

    const trial_y = scratch.y_values[0..requirements.y_values];
    const trial_curves =
        scratch.curves[0..requirements.curve_values];
    const encodings = storage.encodings[0..requirements.encodings];
    const y_values = storage.y_values[0..requirements.y_values];
    const curves = storage.curves[0..requirements.curve_values];
    try rejectVorbisAudioFloorOneOverlap(
        Float,
        setup,
        floor_targets,
        trial_y,
        trial_curves,
        encodings,
        y_values,
        curves,
    );

    const mapping = setup.mappings[
        setup.modes[header.mode_number].mapping
    ];
    var used = [_]bool{false} ** 255;
    var y_offset: usize = 0;
    var total_error: f128 = 0;
    @memset(trial_y, 0);
    for (
        mapping.channel_mux[0..identification.channel_count],
        floor_targets,
        0..,
    ) |mux, target, channel| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => unreachable,
        };
        const channel_y =
            trial_y[y_offset..][0..floor.point_count];
        const fit = try fitVorbisFloorOne(
            Float,
            setup,
            floor_number,
            target,
            channel_y,
        );
        const channel_curve =
            trial_curves[channel * coefficient_count ..][0..coefficient_count];
        try synthesizeVorbisFloorOne(
            Float,
            floor,
            .{
                .used = fit.encoding.used,
                .value_count = if (fit.encoding.used)
                    floor.point_count
                else
                    0,
            },
            channel_y,
            channel_curve,
        );
        used[channel] = fit.encoding.used;
        total_error += fit.squared_control_point_error;
        y_offset += floor.point_count;
    }
    std.debug.assert(y_offset == requirements.y_values);

    @memcpy(y_values, trial_y);
    @memcpy(curves, trial_curves);
    y_offset = 0;
    for (
        mapping.channel_mux[0..identification.channel_count],
        encodings,
        used[0..identification.channel_count],
    ) |mux, *encoding, channel_used| {
        const floor_number = mapping.submaps[mux].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => unreachable,
        };
        encoding.* = .{ .one = if (channel_used)
            .{
                .used = true,
                .y_values = y_values[y_offset..][0..floor.point_count],
            }
        else
            .{} };
        y_offset += floor.point_count;
    }
    return .{
        .encodings = encodings,
        .y_values = y_values,
        .curves = curves,
        .coefficient_count = coefficient_count,
        .squared_control_point_error = @floatCast(total_error),
    };
}

pub fn requiredVorbisAudioResiduePreparationStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisAudioResiduePreparationStorageRequirements {
    const floor = try requiredVorbisAudioFloorOneStorage(
        identification,
        setup,
        header,
    );
    const coupling = try requiredVorbisCouplingScratch(
        identification.channel_count,
        header.block_size / 2,
    );
    return .{
        .floor_encodings = floor.encodings,
        .floor_y_values = floor.y_values,
        .floor_curve_values = floor.curve_values,
        .residue_values = floor.curve_values,
        .threshold_values = floor.curve_values,
        .coupling_values = coupling,
        .do_not_encode = identification.channel_count,
    };
}

pub fn prepareVorbisAudioResidue(
    comptime Float: type,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    spectra: []const []const Float,
    floor_targets: []const []const Float,
    noise_thresholds: []const []const Float,
    scratch: VorbisAudioResiduePreparationScratch(Float),
    storage: VorbisAudioResiduePreparationStorage(Float),
) !VorbisAudioResiduePreparationPlan(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue preparation requires f32 or f64");
    const requirements =
        try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            header,
        );
    if (spectra.len != identification.channel_count or
        floor_targets.len != identification.channel_count or
        noise_thresholds.len != identification.channel_count)
        return error.InvalidVorbisSpectrumBundle;
    const coefficient_count: usize = header.block_size / 2;
    for (spectra, floor_targets, noise_thresholds) |
        spectrum,
        floor_target,
        thresholds,
    | {
        if (spectrum.len != coefficient_count or
            floor_target.len != coefficient_count or
            thresholds.len != coefficient_count)
            return error.InvalidVorbisSpectrumShape;
        for (spectrum) |value| {
            if (!std.math.isFinite(value))
                return error.InvalidVorbisSpectrumValue;
        }
        for (floor_target) |value| {
            if (!std.math.isFinite(value) or value < 0)
                return error.InvalidVorbisSpectrumValue;
        }
        for (thresholds) |value| {
            if (!std.math.isFinite(value) or value < 0)
                return error.InvalidVorbisNoiseThreshold;
        }
    }
    if (scratch.floor_fit_y_values.len <
        requirements.floor_y_values or
        scratch.floor_fit_curves.len <
            requirements.floor_curve_values or
        scratch.floor_encodings.len <
            requirements.floor_encodings or
        scratch.floor_y_values.len <
            requirements.floor_y_values or
        scratch.floor_curves.len <
            requirements.floor_curve_values or
        scratch.residue_values.len <
            requirements.residue_values or
        scratch.noise_thresholds.len <
            requirements.threshold_values or
        scratch.coupling_values.len <
            requirements.coupling_values or
        scratch.coupling_thresholds.len <
            requirements.coupling_values or
        scratch.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResiduePreparationScratchTooSmall;
    if (storage.floor_encodings.len <
        requirements.floor_encodings or
        storage.floor_y_values.len <
            requirements.floor_y_values or
        storage.floor_curves.len <
            requirements.floor_curve_values or
        storage.residue_values.len <
            requirements.residue_values or
        storage.noise_thresholds.len <
            requirements.threshold_values or
        storage.do_not_encode.len <
            requirements.do_not_encode)
        return error.VorbisAudioResiduePreparationStorageTooSmall;

    const fit_y =
        scratch.floor_fit_y_values[0..requirements.floor_y_values];
    const fit_curves =
        scratch.floor_fit_curves[0..requirements.floor_curve_values];
    const trial_encodings =
        scratch.floor_encodings[0..requirements.floor_encodings];
    const trial_y =
        scratch.floor_y_values[0..requirements.floor_y_values];
    const trial_curves =
        scratch.floor_curves[0..requirements.floor_curve_values];
    const trial_residue =
        scratch.residue_values[0..requirements.residue_values];
    const trial_thresholds =
        scratch.noise_thresholds[0..requirements.threshold_values];
    const coupling_values =
        scratch.coupling_values[0..requirements.coupling_values];
    const coupling_thresholds =
        scratch.coupling_thresholds[0..requirements.coupling_values];
    const trial_skips =
        scratch.do_not_encode[0..requirements.do_not_encode];
    const floor_encodings =
        storage.floor_encodings[0..requirements.floor_encodings];
    const floor_y_values =
        storage.floor_y_values[0..requirements.floor_y_values];
    const floor_curves =
        storage.floor_curves[0..requirements.floor_curve_values];
    const residue_values =
        storage.residue_values[0..requirements.residue_values];
    const retained_thresholds =
        storage.noise_thresholds[0..requirements.threshold_values];
    const do_not_encode =
        storage.do_not_encode[0..requirements.do_not_encode];
    try rejectVorbisAudioResiduePreparationOverlap(
        Float,
        setup,
        spectra,
        floor_targets,
        noise_thresholds,
        fit_y,
        fit_curves,
        trial_encodings,
        trial_y,
        trial_curves,
        trial_residue,
        trial_thresholds,
        coupling_values,
        coupling_thresholds,
        trial_skips,
        floor_encodings,
        floor_y_values,
        floor_curves,
        residue_values,
        retained_thresholds,
        do_not_encode,
    );

    const floor = try fitVorbisAudioFloorOne(
        Float,
        identification,
        setup,
        header,
        floor_targets,
        .{
            .y_values = fit_y,
            .curves = fit_curves,
        },
        .{
            .encodings = trial_encodings,
            .y_values = trial_y,
            .curves = trial_curves,
        },
    );
    var residue_channels: [255][]Float = undefined;
    var residue_inputs: [255][]const Float = undefined;
    var threshold_channels: [255][]Float = undefined;
    for (0..identification.channel_count) |channel| {
        const start = channel * coefficient_count;
        const channel_residue =
            trial_residue[start..][0..coefficient_count];
        const channel_thresholds =
            trial_thresholds[start..][0..coefficient_count];
        const floor_curve =
            floor.curves[start..][0..coefficient_count];
        if (floor.encodings[channel].one.used) {
            try normalizeVorbisResidue(
                Float,
                spectra[channel],
                floor_curve,
                channel_residue,
            );
            try normalizeVorbisNoiseThresholds(
                Float,
                noise_thresholds[channel],
                floor_curve,
                channel_thresholds,
            );
        } else {
            @memset(channel_residue, 0);
            @memset(
                channel_thresholds,
                std.math.floatMax(Float),
            );
        }
        residue_channels[channel] = channel_residue;
        residue_inputs[channel] = channel_residue;
        threshold_channels[channel] = channel_thresholds;
    }

    const mapping =
        setup.mappings[setup.modes[header.mode_number].mapping];
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        mapping,
        residue_inputs[0..identification.channel_count],
        threshold_channels[0..identification.channel_count],
        coupling_values,
        coupling_thresholds,
    );
    try forwardCoupleVorbisChannels(
        Float,
        mapping,
        residue_channels[0..identification.channel_count],
        coupling_values,
    );
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = header.mode_number,
            .previous_window_flag = header.previous_window_flag,
            .next_window_flag = header.next_window_flag,
            .floors = floor.encodings,
        },
        trial_skips,
    );
    if (!std.meta.eql(fixed.header, header))
        return error.InvalidVorbisPacketBitOffset;

    @memcpy(floor_y_values, trial_y);
    @memcpy(floor_curves, trial_curves);
    @memcpy(residue_values, trial_residue);
    @memcpy(retained_thresholds, trial_thresholds);
    @memcpy(do_not_encode, trial_skips);
    var y_offset: usize = 0;
    for (0..identification.channel_count) |channel| {
        const floor_number =
            mapping.submaps[mapping.channel_mux[channel]].floor;
        const floor_one = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => unreachable,
        };
        const used = floor.encodings[channel].one.used;
        floor_encodings[channel] = .{ .one = if (used)
            .{
                .used = true,
                .y_values = floor_y_values[y_offset..][0..floor_one.point_count],
            }
        else
            .{} };
        y_offset += floor_one.point_count;
    }
    std.debug.assert(y_offset == requirements.floor_y_values);
    return .{
        .floor_encodings = floor_encodings,
        .floor_y_values = floor_y_values,
        .floor_curves = floor_curves,
        .residue_values = residue_values,
        .noise_thresholds = retained_thresholds,
        .do_not_encode = do_not_encode,
        .coefficient_count = coefficient_count,
        .fixed_packet_bits = fixed.bit_count,
        .squared_control_point_error = floor.squared_control_point_error,
    };
}

pub fn requiredVorbisPcmPacketEncodingStorage(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    frame: VorbisPcmFramePlan,
) !VorbisPcmPacketEncodingStorageRequirements {
    return .{
        .preparation = try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            frame.header,
        ),
        .quantization = try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            frame.header,
        ),
    };
}

pub fn encodeVorbisPcmPacket(
    comptime Float: type,
    comptime channel_count: usize,
    comptime small_block_size: usize,
    comptime large_block_size: usize,
    analyzer: *VorbisPcmFrameAnalyzer(
        Float,
        channel_count,
        small_block_size,
        large_block_size,
    ),
    sequence: *const VorbisPcmPacketSequence,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    plan: VorbisPcmPacketPlan,
    inputs: []const []const Float,
    psychoacoustic_config: VorbisPsychoacousticConfig,
    residue_weights: []const f64,
    residue_config: VorbisAudioResidueQuantizationConfig,
    destination: []u8,
    scratch: VorbisPcmPacketOrchestrationScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !VorbisPcmPacketEncodingTrial(Float) {
    if (identification.channel_count != channel_count or
        identification.small_block_size != small_block_size or
        identification.large_block_size != large_block_size)
        return error.InvalidVorbisPcmEncoderConfiguration;
    const analysis = try analyzer.analyze(
        inputs,
        plan.frame,
        psychoacoustic_config,
        identification.sample_rate,
        scratch.analysis,
        scratch.analysis_storage,
    );
    return encodeVorbisPcmPacketTrial(
        Float,
        sequence,
        identification,
        setup,
        plan,
        analysis,
        residue_weights,
        residue_config,
        destination,
        scratch.encoding,
        storage,
    );
}

pub fn encodeVorbisPcmPacketTrial(
    comptime Float: type,
    sequence: *const VorbisPcmPacketSequence,
    identification: VorbisIdentification,
    setup: VorbisSetup,
    plan: VorbisPcmPacketPlan,
    analysis: VorbisPcmFrameAnalysisPlan(Float),
    weights: []const f64,
    config: VorbisAudioResidueQuantizationConfig,
    destination: []u8,
    scratch: VorbisPcmPacketEncodingScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !VorbisPcmPacketEncodingTrial(Float) {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis PCM packet encoding requires f32 or f64");
    try sequence.validatePlan(plan);
    if (!std.meta.eql(analysis.frame, plan.frame))
        return error.InvalidVorbisPcmFrameAnalysisPlan;
    const coefficient_count: usize = plan.frame.header.block_size / 2;
    const value_count = std.math.mul(
        usize,
        identification.channel_count,
        coefficient_count,
    ) catch return error.VorbisPcmPacketEncodingSizeOverflow;
    if (analysis.coefficient_count != coefficient_count or
        analysis.spectra.len != value_count or
        analysis.analyses.len != identification.channel_count or
        analysis.floor_targets.len != value_count or
        analysis.noise_thresholds.len != value_count)
        return error.InvalidVorbisPcmFrameAnalysisPlan;

    const requirements =
        try requiredVorbisPcmPacketEncodingStorage(
            identification,
            setup,
            plan.frame,
        );
    try validateVorbisPcmPacketEncodingStorage(
        Float,
        setup,
        analysis,
        weights,
        destination,
        requirements,
        scratch,
        storage,
    );

    var spectra: [255][]const Float = undefined;
    var floor_targets: [255][]const Float = undefined;
    var noise_thresholds: [255][]const Float = undefined;
    for (0..identification.channel_count) |channel| {
        const start = channel * coefficient_count;
        spectra[channel] =
            analysis.spectra[start..][0..coefficient_count];
        floor_targets[channel] =
            analysis.floor_targets[start..][0..coefficient_count];
        noise_thresholds[channel] =
            analysis.noise_thresholds[start..][0..coefficient_count];
    }
    const prepared = try prepareVorbisAudioResidue(
        Float,
        identification,
        setup,
        plan.frame.header,
        spectra[0..identification.channel_count],
        floor_targets[0..identification.channel_count],
        noise_thresholds[0..identification.channel_count],
        scratch.preparation,
        scratch.preparation_storage,
    );
    const quantized = try quantizeVorbisAudioResiduesAdaptive(
        Float,
        identification,
        setup,
        plan.frame.header,
        prepared.residue_values,
        prepared.noise_thresholds,
        prepared.do_not_encode,
        plan.budget,
        prepared.fixed_packet_bits,
        weights,
        config,
        scratch.quantization,
        scratch.quantization_storage,
    );
    const encoding = VorbisAudioPacketEncoding{
        .mode_number = plan.frame.header.mode_number,
        .previous_window_flag = plan.frame.header.previous_window_flag,
        .next_window_flag = plan.frame.header.next_window_flag,
        .floors = prepared.floor_encodings,
        .residues = quantized.encodings,
    };

    var counter = VorbisPacketWriter.counting();
    const counted_header = try writeVorbisAudioPacket(
        &counter,
        identification,
        setup,
        encoding,
    );
    if (!std.meta.eql(counted_header, plan.frame.header))
        return error.InvalidVorbisPcmFrameAnalysisPlan;
    const actual_bits = std.math.cast(
        u32,
        counter.bit_offset,
    ) orelse return error.VorbisAudioPacketSizeOverflow;
    var sequence_after = sequence.*;
    const commit = try sequence_after.commit(plan, actual_bits);
    const required_bytes =
        counter.bit_offset / 8 +
        @intFromBool(counter.bit_offset % 8 != 0);
    if (destination.len < required_bytes)
        return error.VorbisAudioPacketOutputTooSmall;

    const packet = try encodeVorbisAudioPacket(
        destination[0..required_bytes],
        identification,
        setup,
        encoding,
    );
    const retained_preparation =
        retainVorbisAudioResiduePreparation(
            identification,
            setup,
            plan.frame.header,
            prepared,
            storage.preparation,
        );
    const retained_quantization =
        retainVorbisAudioResidueQuantization(
            quantized,
            storage.quantization,
        );
    return .{
        .packet = packet,
        .commit = commit,
        .preparation = retained_preparation,
        .quantization = retained_quantization,
    };
}

fn validateVorbisPcmPacketEncodingStorage(
    comptime Float: type,
    setup: VorbisSetup,
    analysis: VorbisPcmFrameAnalysisPlan(Float),
    weights: []const f64,
    destination: []u8,
    requirements: VorbisPcmPacketEncodingStorageRequirements,
    scratch: VorbisPcmPacketEncodingScratch(Float),
    storage: VorbisPcmPacketEncodingStorage(Float),
) !void {
    const preparation = requirements.preparation;
    const quantization = requirements.quantization;
    if (scratch.preparation_storage.floor_encodings.len <
        preparation.floor_encodings or
        scratch.preparation_storage.floor_y_values.len <
            preparation.floor_y_values or
        scratch.preparation_storage.floor_curves.len <
            preparation.floor_curve_values or
        scratch.preparation_storage.residue_values.len <
            preparation.residue_values or
        scratch.preparation_storage.noise_thresholds.len <
            preparation.threshold_values or
        scratch.preparation_storage.do_not_encode.len <
            preparation.do_not_encode or
        scratch.quantization_storage.encodings.len <
            quantization.encodings or
        scratch.quantization_storage.submap_results.len <
            quantization.submap_results or
        scratch.quantization_storage.do_not_encode.len <
            quantization.do_not_encode or
        scratch.quantization_storage.classifications.len <
            quantization.classifications or
        scratch.quantization_storage.entries.len <
            quantization.entries)
        return error.VorbisPcmPacketEncodingScratchTooSmall;
    if (storage.preparation.floor_encodings.len <
        preparation.floor_encodings or
        storage.preparation.floor_y_values.len <
            preparation.floor_y_values or
        storage.preparation.floor_curves.len <
            preparation.floor_curve_values or
        storage.preparation.residue_values.len <
            preparation.residue_values or
        storage.preparation.noise_thresholds.len <
            preparation.threshold_values or
        storage.preparation.do_not_encode.len <
            preparation.do_not_encode or
        storage.quantization.encodings.len <
            quantization.encodings or
        storage.quantization.submap_results.len <
            quantization.submap_results or
        storage.quantization.do_not_encode.len <
            quantization.do_not_encode or
        storage.quantization.classifications.len <
            quantization.classifications or
        storage.quantization.entries.len <
            quantization.entries)
        return error.VorbisPcmPacketEncodingStorageTooSmall;

    const buffers = [_][]u8{
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_encodings[0..preparation.floor_encodings],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_y_values[0..preparation.floor_y_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.floor_curves[0..preparation.floor_curve_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.residue_values[0..preparation.residue_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.noise_thresholds[0..preparation.threshold_values],
        ),
        std.mem.sliceAsBytes(
            scratch.preparation_storage.do_not_encode[0..preparation.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.encodings[0..quantization.encodings],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.submap_results[0..quantization.submap_results],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.do_not_encode[0..quantization.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.classifications[0..quantization.classifications],
        ),
        std.mem.sliceAsBytes(
            scratch.quantization_storage.entries[0..quantization.entries],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_encodings[0..preparation.floor_encodings],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_y_values[0..preparation.floor_y_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.floor_curves[0..preparation.floor_curve_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.residue_values[0..preparation.residue_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.noise_thresholds[0..preparation.threshold_values],
        ),
        std.mem.sliceAsBytes(
            storage.preparation.do_not_encode[0..preparation.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.encodings[0..quantization.encodings],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.submap_results[0..quantization.submap_results],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.do_not_encode[0..quantization.do_not_encode],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.classifications[0..quantization.classifications],
        ),
        std.mem.sliceAsBytes(
            storage.quantization.entries[0..quantization.entries],
        ),
    };
    const sources = [_][]const u8{
        std.mem.sliceAsBytes(analysis.spectra),
        std.mem.sliceAsBytes(analysis.analyses),
        std.mem.sliceAsBytes(analysis.floor_targets),
        std.mem.sliceAsBytes(analysis.noise_thresholds),
        std.mem.sliceAsBytes(weights),
        destination,
    };
    for (buffers, 0..) |buffer, index| {
        for (buffers[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(u8, buffer, earlier))
                return error.OverlappingVorbisPcmPacketEncodingStorage;
        }
        for (sources) |source| {
            if (vorbisConstSlicesOverlap(u8, buffer, source))
                return error.OverlappingVorbisPcmPacketEncodingStorage;
        }
        rejectVorbisSetupOverlap(
            buffer,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisPcmPacketEncodingStorage,
            else => return err,
        };
    }
    for (sources[0 .. sources.len - 1]) |source| {
        if (vorbisConstSlicesOverlap(u8, destination, source))
            return error.OverlappingVorbisPcmPacketEncodingStorage;
    }
}

fn retainVorbisAudioResiduePreparation(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
    plan: anytype,
    storage: anytype,
) @TypeOf(plan) {
    @memcpy(
        storage.floor_y_values[0..plan.floor_y_values.len],
        plan.floor_y_values,
    );
    @memcpy(
        storage.floor_curves[0..plan.floor_curves.len],
        plan.floor_curves,
    );
    @memcpy(
        storage.residue_values[0..plan.residue_values.len],
        plan.residue_values,
    );
    @memcpy(
        storage.noise_thresholds[0..plan.noise_thresholds.len],
        plan.noise_thresholds,
    );
    @memcpy(
        storage.do_not_encode[0..plan.do_not_encode.len],
        plan.do_not_encode,
    );
    const mapping =
        setup.mappings[setup.modes[header.mode_number].mapping];
    var y_offset: usize = 0;
    for (0..identification.channel_count) |channel| {
        const floor_number =
            mapping.submaps[mapping.channel_mux[channel]].floor;
        const floor = switch (setup.floors[floor_number]) {
            .one => |value| value,
            .zero => unreachable,
        };
        const used = plan.floor_encodings[channel].one.used;
        storage.floor_encodings[channel] = .{
            .one = if (used)
                .{
                    .used = true,
                    .y_values = storage.floor_y_values[y_offset..][0..floor.point_count],
                }
            else
                .{},
        };
        y_offset += floor.point_count;
    }
    return .{
        .floor_encodings = storage.floor_encodings[0..plan.floor_encodings.len],
        .floor_y_values = storage.floor_y_values[0..plan.floor_y_values.len],
        .floor_curves = storage.floor_curves[0..plan.floor_curves.len],
        .residue_values = storage.residue_values[0..plan.residue_values.len],
        .noise_thresholds = storage.noise_thresholds[0..plan.noise_thresholds.len],
        .do_not_encode = storage.do_not_encode[0..plan.do_not_encode.len],
        .coefficient_count = plan.coefficient_count,
        .fixed_packet_bits = plan.fixed_packet_bits,
        .squared_control_point_error = plan.squared_control_point_error,
    };
}

fn retainVorbisAudioResidueQuantization(
    plan: VorbisAudioResidueQuantizationPlan,
    storage: VorbisAudioResidueQuantizationStorage,
) VorbisAudioResidueQuantizationPlan {
    @memcpy(
        storage.submap_results[0..plan.submap_results.len],
        plan.submap_results,
    );
    @memcpy(
        storage.do_not_encode[0..plan.do_not_encode.len],
        plan.do_not_encode,
    );
    @memcpy(
        storage.classifications[0..plan.classifications.len],
        plan.classifications,
    );
    @memcpy(
        storage.entries[0..plan.entries.len],
        plan.entries,
    );
    var skip_offset: usize = 0;
    var classification_offset: usize = 0;
    var entry_offset: usize = 0;
    for (plan.encodings, 0..) |source, index| {
        storage.encodings[index] = .{
            .do_not_encode = storage.do_not_encode[skip_offset..][0..source.do_not_encode.len],
            .classifications = storage.classifications[classification_offset..][0..source.classifications.len],
            .entries = storage.entries[entry_offset..][0..source.entries.len],
        };
        skip_offset += source.do_not_encode.len;
        classification_offset += source.classifications.len;
        entry_offset += source.entries.len;
    }
    return .{
        .encodings = storage.encodings[0..plan.encodings.len],
        .submap_results = storage.submap_results[0..plan.submap_results.len],
        .do_not_encode = storage.do_not_encode[0..plan.do_not_encode.len],
        .classifications = storage.classifications[0..plan.classifications.len],
        .entries = storage.entries[0..plan.entries.len],
        .allocation = plan.allocation,
    };
}

fn rejectVorbisAudioResiduePreparationOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    spectra: []const []const Float,
    floor_targets: []const []const Float,
    noise_thresholds: []const []const Float,
    fit_y: []u32,
    fit_curves: []Float,
    trial_encodings: []VorbisFloorPacketEncoding,
    trial_y: []u32,
    trial_curves: []Float,
    trial_residue: []Float,
    trial_thresholds: []Float,
    coupling_values: []Float,
    coupling_thresholds: []Float,
    trial_skips: []bool,
    floor_encodings: []VorbisFloorPacketEncoding,
    floor_y_values: []u32,
    floor_curves: []Float,
    residue_values: []Float,
    retained_thresholds: []Float,
    do_not_encode: []bool,
) !void {
    const destinations = [_][]u8{
        std.mem.sliceAsBytes(fit_y),
        std.mem.sliceAsBytes(fit_curves),
        std.mem.sliceAsBytes(trial_encodings),
        std.mem.sliceAsBytes(trial_y),
        std.mem.sliceAsBytes(trial_curves),
        std.mem.sliceAsBytes(trial_residue),
        std.mem.sliceAsBytes(trial_thresholds),
        std.mem.sliceAsBytes(coupling_values),
        std.mem.sliceAsBytes(coupling_thresholds),
        std.mem.sliceAsBytes(trial_skips),
        std.mem.sliceAsBytes(floor_encodings),
        std.mem.sliceAsBytes(floor_y_values),
        std.mem.sliceAsBytes(floor_curves),
        std.mem.sliceAsBytes(residue_values),
        std.mem.sliceAsBytes(retained_thresholds),
        std.mem.sliceAsBytes(do_not_encode),
    };
    const bundles = [_][]const []const Float{
        spectra,
        floor_targets,
        noise_thresholds,
    };
    for (destinations, 0..) |destination, index| {
        for (destinations[0..index]) |earlier| {
            if (vorbisConstSlicesOverlap(
                u8,
                destination,
                earlier,
            )) return error.OverlappingVorbisAudioResiduePreparationStorage;
        }
        rejectVorbisSetupOverlap(
            destination,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioResiduePreparationStorage,
            else => return err,
        };
        for (bundles) |bundle| {
            if (vorbisSliceOverlapsBytes(
                []const Float,
                bundle,
                destination,
            )) return error.OverlappingVorbisAudioResiduePreparationStorage;
            for (bundle) |values| {
                if (vorbisSliceOverlapsBytes(
                    Float,
                    values,
                    destination,
                )) return error.OverlappingVorbisAudioResiduePreparationStorage;
            }
        }
    }
}

fn validateVorbisAudioFloorOneState(
    identification: VorbisIdentification,
    setup: VorbisSetup,
    header: VorbisAudioPacketHeader,
) !VorbisMapping {
    if (identification.sample_rate == 0 or
        identification.small_block_size < 64 or
        identification.large_block_size > 8192 or
        identification.small_block_size >
            identification.large_block_size or
        !std.math.isPowerOfTwo(
            identification.small_block_size,
        ) or
        !std.math.isPowerOfTwo(
            identification.large_block_size,
        ))
        return error.InvalidVorbisIdentificationState;
    const mapping = try validateVorbisAudioDecodeState(
        identification,
        setup,
        header,
    );
    const expected_block_size: u16 = if (header.large_block)
        identification.large_block_size
    else
        identification.small_block_size;
    if (header.block_size != expected_block_size)
        return error.InvalidVorbisPcmBlockShape;
    if (header.large_block) {
        if (header.previous_window_flag == null or
            header.next_window_flag == null)
            return error.InvalidVorbisWindowState;
    } else if (header.previous_window_flag != null or
        header.next_window_flag != null)
        return error.InvalidVorbisWindowState;
    return mapping;
}

fn rejectVorbisAudioFloorOneOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    floor_targets: []const []const Float,
    trial_y: []u32,
    trial_curves: []Float,
    encodings: []VorbisFloorPacketEncoding,
    y_values: []u32,
    curves: []Float,
) !void {
    if (vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        Float,
        trial_curves,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        VorbisFloorPacketEncoding,
        encodings,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        u32,
        trial_y,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        VorbisFloorPacketEncoding,
        encodings,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        Float,
        trial_curves,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        VorbisFloorPacketEncoding,
        encodings,
        u32,
        y_values,
    ) or vorbisTypedSlicesOverlap(
        VorbisFloorPacketEncoding,
        encodings,
        Float,
        curves,
    ) or vorbisTypedSlicesOverlap(
        u32,
        y_values,
        Float,
        curves,
    ))
        return error.OverlappingVorbisAudioFloorStorage;

    inline for (.{
        trial_y,
        trial_curves,
        encodings,
        y_values,
        curves,
    }) |destination| {
        const destination_bytes =
            std.mem.sliceAsBytes(destination);
        rejectVorbisSetupOverlap(
            destination_bytes,
            setup,
        ) catch |err| switch (err) {
            error.OverlappingVorbisSetupStorage => return error.OverlappingVorbisAudioFloorStorage,
            else => return err,
        };
        if (vorbisSliceOverlapsBytes(
            []const Float,
            floor_targets,
            destination_bytes,
        )) return error.OverlappingVorbisAudioFloorStorage;
        for (floor_targets) |target| {
            if (vorbisSliceOverlapsBytes(
                Float,
                target,
                destination_bytes,
            )) return error.OverlappingVorbisAudioFloorStorage;
        }
    }
}

pub fn fitVorbisFloorOne(
    comptime Float: type,
    setup: VorbisSetup,
    floor_number: u8,
    target_spectrum: []const Float,
    y_destination: []u32,
) !VorbisFloorOneFit {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis floor fitting requires f32 or f64 input");
    if (floor_number >= setup.floors.len)
        return error.InvalidVorbisFloorNumber;
    const floor = switch (setup.floors[floor_number]) {
        .one => |value| value,
        .zero => return error.InvalidVorbisFloorType,
    };
    try validateVorbisFloorOneState(floor, setup.codebooks);
    if (target_spectrum.len != floor.x_list[1])
        return error.InvalidVorbisSpectrumShape;

    var silent = true;
    for (target_spectrum) |value| {
        if (!std.math.isFinite(value))
            return error.InvalidVorbisSpectrumValue;
        silent = silent and value == 0;
    }
    if (silent) {
        return .{
            .encoding = .{},
            .squared_control_point_error = 0,
        };
    }
    if (y_destination.len < floor.point_count)
        return error.VorbisFloorOutputTooSmall;
    const output = y_destination[0..floor.point_count];
    try rejectVorbisFloorFitOverlap(
        Float,
        setup,
        target_spectrum,
        output,
    );

    const ranges = [_]i32{ 256, 128, 86, 64 };
    const range = ranges[floor.multiplier - 1];
    var desired_y = [_]i32{0} ** 65;
    desired_y[0] = vorbisFloorOneTargetY(
        Float,
        target_spectrum[0],
        floor.multiplier,
        range,
    );
    desired_y[1] = vorbisFloorOneTargetY(
        Float,
        target_spectrum[target_spectrum.len - 1],
        floor.multiplier,
        range,
    );
    for (2..floor.point_count) |index| {
        desired_y[index] = vorbisFloorOneTargetY(
            Float,
            target_spectrum[floor.x_list[index]],
            floor.multiplier,
            range,
        );
    }

    var staged_y = [_]u32{0} ** 65;
    var final_y = [_]i32{0} ** 65;
    staged_y[0] = @intCast(desired_y[0]);
    staged_y[1] = @intCast(desired_y[1]);
    final_y[0] = desired_y[0];
    final_y[1] = desired_y[1];
    var total_error: f128 = 0;
    var point_offset: usize = 2;
    for (floor.partition_classes[0..floor.partition_count]) |class_index| {
        const class = floor.classes[class_index];
        total_error += try fitVorbisFloorOneClass(
            setup,
            floor,
            class,
            point_offset,
            desired_y,
            &staged_y,
            &final_y,
            range,
        );
        point_offset += class.dimensions;
    }
    if (point_offset != floor.point_count)
        return error.InvalidVorbisSetupState;

    var counter = VorbisPacketWriter.counting();
    try counter.writeFloorOne(
        setup,
        floor_number,
        .{
            .used = true,
            .y_values = staged_y[0..floor.point_count],
        },
    );
    @memcpy(output, staged_y[0..floor.point_count]);
    return .{
        .encoding = .{
            .used = true,
            .y_values = output,
        },
        .squared_control_point_error = @floatCast(total_error),
    };
}

pub fn normalizeVorbisResidue(
    comptime Float: type,
    spectrum: []const Float,
    floor_curve: []const Float,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis residue normalization requires f32 or f64");
    if (spectrum.len != floor_curve.len or output.len != spectrum.len)
        return error.InvalidVorbisSpectrumShape;
    const exact_in_place =
        spectrum.len == output.len and spectrum.ptr == output.ptr;
    if ((!exact_in_place and
        vorbisConstSlicesOverlap(Float, spectrum, output)) or
        vorbisConstSlicesOverlap(Float, floor_curve, output))
        return error.OverlappingVorbisResidueNormalization;

    for (spectrum, floor_curve) |spectrum_value, floor_value| {
        if (!std.math.isFinite(spectrum_value) or
            !std.math.isFinite(floor_value) or floor_value <= 0)
            return error.InvalidVorbisSpectrumValue;
        if (!std.math.isFinite(spectrum_value / floor_value))
            return error.InvalidVorbisSpectrumValue;
    }
    for (spectrum, floor_curve, output) |
        spectrum_value,
        floor_value,
        *destination,
    | {
        destination.* = spectrum_value / floor_value;
    }
}

pub fn normalizeVorbisNoiseThresholds(
    comptime Float: type,
    thresholds: []const Float,
    floor_curve: []const Float,
    output: []Float,
) !void {
    if (Float != f32 and Float != f64)
        @compileError("Vorbis noise thresholds require f32 or f64");
    if (thresholds.len == 0 or
        thresholds.len != floor_curve.len or
        output.len != thresholds.len)
        return error.InvalidVorbisSpectrumShape;
    const exact_in_place =
        thresholds.len == output.len and thresholds.ptr == output.ptr;
    if ((!exact_in_place and
        vorbisConstSlicesOverlap(Float, thresholds, output)) or
        vorbisConstSlicesOverlap(Float, floor_curve, output))
        return error.OverlappingVorbisNoiseThresholdNormalization;

    for (thresholds, floor_curve) |threshold, floor_value| {
        if (!std.math.isFinite(threshold) or threshold <= 0 or
            !std.math.isFinite(floor_value) or floor_value <= 0 or
            !std.math.isFinite(threshold / floor_value) or
            threshold / floor_value <= 0)
            return error.InvalidVorbisNoiseThreshold;
    }
    for (thresholds, floor_curve, output) |
        threshold,
        floor_value,
        *destination,
    | {
        destination.* = threshold / floor_value;
    }
}

fn fitVorbisFloorOneClass(
    setup: VorbisSetup,
    floor: VorbisFloorOne,
    class: VorbisFloorOneClass,
    point_offset: usize,
    desired_y: [65]i32,
    staged_y: *[65]u32,
    final_y: *[65]i32,
    range: i32,
) !f128 {
    var best_error = std.math.inf(f128);
    var best_raw = [_]u32{0} ** 8;
    var best_final = final_y.*;
    var found = false;

    if (class.subclass_bits == 0) {
        best_error = try fitVorbisFloorOneClassword(
            setup,
            floor,
            class,
            point_offset,
            desired_y,
            final_y.*,
            0,
            &best_raw,
            &best_final,
            range,
        );
        found = true;
    } else {
        const masterbook_number: u8 = @intCast(class.masterbook);
        const masterbook = setup.codebooks[masterbook_number];
        const entries = try vorbisSetupSlice(
            VorbisCodebookEntry,
            setup.codebook_entries,
            masterbook.entry_offset,
            masterbook.entries,
        );
        for (entries, 0..) |entry, entry_number| {
            if (entry.length == 0) continue;
            _ = try writableVorbisCodeword(
                setup,
                masterbook_number,
                @intCast(entry_number),
            );
            var candidate_raw = [_]u32{0} ** 8;
            var candidate_final = final_y.*;
            const candidate_error = try fitVorbisFloorOneClassword(
                setup,
                floor,
                class,
                point_offset,
                desired_y,
                final_y.*,
                @intCast(entry_number),
                &candidate_raw,
                &candidate_final,
                range,
            );
            if (!found or candidate_error < best_error) {
                found = true;
                best_error = candidate_error;
                best_raw = candidate_raw;
                best_final = candidate_final;
            }
        }
    }
    if (!found) return error.UnencodableVorbisFloorValue;
    @memcpy(
        staged_y[point_offset..][0..class.dimensions],
        best_raw[0..class.dimensions],
    );
    for (point_offset..point_offset + class.dimensions) |index| {
        final_y[index] = best_final[index];
    }
    return best_error;
}

fn fitVorbisFloorOneClassword(
    setup: VorbisSetup,
    floor: VorbisFloorOne,
    class: VorbisFloorOneClass,
    point_offset: usize,
    desired_y: [65]i32,
    base_final_y: [65]i32,
    encoded_classword: u32,
    raw_values: *[8]u32,
    fitted_final_y: *[65]i32,
    range: i32,
) !f128 {
    fitted_final_y.* = base_final_y;
    var classword = encoded_classword;
    const mask =
        (@as(u32, 1) << @intCast(class.subclass_bits)) - 1;
    var error_sum: f128 = 0;
    for (0..class.dimensions) |dimension| {
        const point_index = point_offset + dimension;
        const low = vorbisFloorLowNeighbor(
            floor.x_list[0..floor.point_count],
            point_index,
        );
        const high = vorbisFloorHighNeighbor(
            floor.x_list[0..floor.point_count],
            point_index,
        );
        const predicted = vorbisFloorRenderPoint(
            floor.x_list[low],
            fitted_final_y[low],
            floor.x_list[high],
            fitted_final_y[high],
            floor.x_list[point_index],
        );
        const book = class.subclass_books[classword & mask];
        classword >>= @intCast(class.subclass_bits);
        const fitted = if (book < 0)
            VorbisFloorOneValueFit{
                .raw = 0,
                .final_y = predicted,
            }
        else
            try fitVorbisFloorOneValue(
                setup,
                @intCast(book),
                predicted,
                desired_y[point_index],
                range,
            );
        raw_values[dimension] = fitted.raw;
        fitted_final_y[point_index] = fitted.final_y;
        const difference =
            @as(f128, @floatFromInt(
                fitted.final_y - desired_y[point_index],
            ));
        error_sum += difference * difference;
    }
    return error_sum;
}

const VorbisFloorOneValueFit = struct {
    raw: u32,
    final_y: i32,
};

fn fitVorbisFloorOneValue(
    setup: VorbisSetup,
    codebook_number: u8,
    predicted: i32,
    desired: i32,
    range: i32,
) !VorbisFloorOneValueFit {
    if (codebook_number >= setup.codebooks.len)
        return error.InvalidVorbisCodebookNumber;
    const codebook = setup.codebooks[codebook_number];
    const entries = try vorbisSetupSlice(
        VorbisCodebookEntry,
        setup.codebook_entries,
        codebook.entry_offset,
        codebook.entries,
    );
    var result: ?VorbisFloorOneValueFit = null;
    var best_error: i64 = std.math.maxInt(i64);
    for (entries, 0..) |entry, entry_number| {
        if (entry.length == 0) continue;
        const raw: u32 = @intCast(entry_number);
        _ = try writableVorbisCodeword(
            setup,
            codebook_number,
            raw,
        );
        const final_y = decodeVorbisFloorOneValue(
            predicted,
            range,
            raw,
        );
        const difference: i64 = final_y - desired;
        const squared = difference * difference;
        if (squared < best_error) {
            best_error = squared;
            result = .{
                .raw = raw,
                .final_y = final_y,
            };
        }
    }
    return result orelse error.UnencodableVorbisFloorValue;
}

fn decodeVorbisFloorOneValue(
    predicted: i32,
    range: i32,
    raw_value: u32,
) i32 {
    const value: i64 = raw_value;
    const high_room: i64 = range - predicted;
    const low_room: i64 = predicted;
    const room = 2 * @min(high_room, low_room);
    var decoded: i64 = predicted;
    if (value != 0) {
        if (value >= room) {
            decoded = if (high_room > low_room)
                value - low_room + predicted
            else
                predicted - value + high_room - 1;
        } else if (value & 1 != 0) {
            decoded = predicted - @divTrunc(value + 1, 2);
        } else {
            decoded = predicted + @divTrunc(value, 2);
        }
    }
    return @intCast(std.math.clamp(
        decoded,
        0,
        @as(i64, range - 1),
    ));
}

fn vorbisFloorOneTargetY(
    comptime Float: type,
    value: Float,
    multiplier: u3,
    range: i32,
) i32 {
    const magnitude: f64 = @abs(@as(f64, @floatCast(value)));
    if (magnitude <= vorbis_floor_one_inverse_db[0]) return 0;
    const step: f64 = 0.11512925 * 140.0 / 256.0;
    const table_index = std.math.clamp(
        @round(255.0 + @log(magnitude) / step),
        0.0,
        255.0,
    );
    return @intFromFloat(std.math.clamp(
        @round(table_index / @as(f64, @floatFromInt(multiplier))),
        0.0,
        @as(f64, @floatFromInt(range - 1)),
    ));
}

fn rejectVorbisFloorFitOverlap(
    comptime Float: type,
    setup: VorbisSetup,
    target_spectrum: []const Float,
    output: []u32,
) !void {
    const output_bytes = std.mem.sliceAsBytes(output);
    if (vorbisSliceOverlapsBytes(
        Float,
        target_spectrum,
        output_bytes,
    )) return error.OverlappingVorbisFloorFit;
    inline for (.{
        setup.codebooks,
        setup.codebook_entries,
        setup.huffman_nodes,
        setup.codebook_multiplicands,
        setup.floors,
        setup.residues,
        setup.mappings,
        setup.modes,
    }) |values| {
        if (vorbisSliceOverlapsBytes(
            @TypeOf(values[0]),
            values,
            output_bytes,
        )) return error.OverlappingVorbisFloorFit;
    }
}

fn vorbisFloorLowNeighbor(points: []const u16, index: usize) usize {
    var result: usize = 0;
    for (1..index) |candidate| {
        if (points[candidate] < points[index] and
            points[candidate] > points[result])
            result = candidate;
    }
    return result;
}

fn vorbisFloorHighNeighbor(points: []const u16, index: usize) usize {
    var result: usize = 1;
    for (2..index) |candidate| {
        if (points[candidate] > points[index] and
            points[candidate] < points[result])
            result = candidate;
    }
    return result;
}

fn vorbisFloorRenderPoint(
    x0: u16,
    y0: i32,
    x1: u16,
    y1: i32,
    x: u16,
) i32 {
    const difference = y1 - y0;
    const absolute_difference: i32 = @intCast(@abs(difference));
    const offset = @divTrunc(
        absolute_difference * @as(i32, x - x0),
        @as(i32, x1 - x0),
    );
    return if (difference < 0) y0 - offset else y0 + offset;
}

fn renderVorbisFloorLine(
    comptime Float: type,
    x0: u16,
    y0: i32,
    x1: u16,
    y1: i32,
    output: []Float,
) void {
    const delta_x: i32 = x1 - x0;
    const delta_y = y1 - y0;
    var remainder: i32 = @intCast(@abs(delta_y));
    const base = @divTrunc(delta_y, delta_x);
    const step = if (delta_y < 0) base - 1 else base + 1;
    remainder -= @as(i32, @intCast(@abs(base))) * delta_x;
    var error_accumulator: i32 = 0;
    var y = y0;
    const end = @min(@as(usize, x1), output.len);
    for (x0..end) |x| {
        output[x] = vorbisFloorOneInverseDb(Float, @intCast(y));
        error_accumulator += remainder;
        if (error_accumulator >= delta_x) {
            error_accumulator -= delta_x;
            y += step;
        } else {
            y += base;
        }
    }
}

fn vorbisFloorOneInverseDb(comptime Float: type, index: u8) Float {
    return @floatCast(vorbis_floor_one_inverse_db[index]);
}

const vorbis_floor_one_inverse_db = table: {
    var values: [256]f64 = undefined;
    const step: f64 = 0.11512925 * 140.0 / 256.0;
    for (&values, 0..) |*value, index| {
        value.* = @exp(
            (@as(f64, @floatFromInt(index)) - 255.0) * step,
        );
    }
    break :table values;
};

fn readVorbisAudioBits(reader: *VorbisBitReader, bit_count: u6) !u32 {
    return reader.read(bit_count) catch |err| switch (err) {
        error.TruncatedVorbisSetup => error.TruncatedVorbisAudioPacket,
    };
}

fn parseVorbisCodebook(
    reader: *VorbisBitReader,
    entry_offset: u64,
    entry_destination: ?[]VorbisCodebookEntry,
    tree_node_offset: u64,
    node_destination: ?[]VorbisHuffmanNode,
    multiplicand_offset: u64,
    multiplicand_destination: ?[]u32,
) !VorbisCodebook {
    if (try reader.read(24) != 0x564342)
        return error.InvalidVorbisCodebookSync;
    const dimensions: u16 = @intCast(try reader.read(16));
    const entries = try reader.read(24);
    if (dimensions == 0 or entries == 0)
        return error.InvalidVorbisCodebook;
    const output = if (entry_destination) |destination|
        destination[0..entries]
    else
        null;
    if (output) |entry_output| {
        @memset(entry_output, .{ .codeword = 0, .length = 0 });
    }

    var length_counts = [_]u32{0} ** 32;
    var active_entries: u32 = 0;
    if (try reader.read(1) == 0) {
        const sparse = try reader.read(1) != 0;
        for (0..entries) |index| {
            if (sparse and try reader.read(1) == 0) continue;
            const length = try reader.read(5) + 1;
            length_counts[length - 1] += 1;
            active_entries += 1;
            if (output) |entry_output| {
                entry_output[index].length = @intCast(length);
            }
        }
    } else {
        var current_entry: u32 = 0;
        var current_length = try reader.read(5) + 1;
        while (current_entry < entries) : (current_length += 1) {
            if (current_length > 32)
                return error.InvalidVorbisCodebookLengths;
            const number = try reader.read(vorbisILog(entries - current_entry));
            if (number > entries - current_entry)
                return error.InvalidVorbisCodebookLengths;
            length_counts[current_length - 1] += number;
            active_entries += number;
            if (output) |entry_output| {
                for (entry_output[current_entry..][0..number]) |*entry| {
                    entry.length = @intCast(current_length);
                }
            }
            current_entry += number;
        }
    }
    try validateVorbisCodebookTree(&length_counts, active_entries);
    const tree_node_count = if (active_entries > 1)
        active_entries - 1
    else
        0;
    if (output) |entry_output| {
        assignVorbisCodewords(entry_output);
        if (node_destination) |destination| {
            try buildVorbisHuffmanTree(
                entry_output,
                destination[0..tree_node_count],
            );
        }
    }

    const lookup_value = try reader.read(4);
    if (lookup_value > 2) return error.UnsupportedVorbisCodebookLookup;
    const lookup_type: u2 = @intCast(lookup_value);
    var minimum_value: f64 = 0;
    var delta_value: f64 = 0;
    var sequence = false;
    var multiplicand_count: u64 = 0;
    if (lookup_type != 0) {
        minimum_value = vorbisFloat32Unpack(try reader.read(32));
        delta_value = vorbisFloat32Unpack(try reader.read(32));
        const value_bits = try reader.read(4) + 1;
        sequence = try reader.read(1) != 0;
        multiplicand_count = if (lookup_type == 1)
            vorbisLookupOneValues(entries, dimensions)
        else
            @as(u64, entries) * dimensions;
        if (multiplicand_destination) |destination| {
            const output_values =
                destination[0..@intCast(multiplicand_count)];
            for (output_values) |*value| {
                value.* = try reader.read(@intCast(value_bits));
            }
        } else {
            try reader.skip(multiplicand_count * value_bits);
        }
    }
    return .{
        .dimensions = dimensions,
        .entries = entries,
        .entry_offset = entry_offset,
        .active_entry_count = active_entries,
        .tree_node_offset = tree_node_offset,
        .tree_node_count = tree_node_count,
        .lookup_type = lookup_type,
        .minimum_value = minimum_value,
        .delta_value = delta_value,
        .sequence = sequence,
        .multiplicand_offset = multiplicand_offset,
        .multiplicand_count = multiplicand_count,
    };
}

const invalid_huffman_branch = std.math.maxInt(u32);
const huffman_leaf_flag: u32 = 1 << 31;

fn buildVorbisHuffmanTree(
    entries: []const VorbisCodebookEntry,
    nodes: []VorbisHuffmanNode,
) !void {
    if (nodes.len == 0) return;
    @memset(nodes, .{
        .branches = .{ invalid_huffman_branch, invalid_huffman_branch },
    });
    var next_node: u32 = 1;
    for (entries, 0..) |entry, entry_index| {
        if (entry.length == 0) continue;
        var node_index: u32 = 0;
        for (0..entry.length) |depth| {
            const shift: u5 = @intCast(entry.length - 1 - depth);
            const branch_index: usize =
                @intCast((entry.codeword >> shift) & 1);
            const branch = &nodes[node_index].branches[branch_index];
            if (depth + 1 == entry.length) {
                if (branch.* != invalid_huffman_branch)
                    return error.InvalidVorbisCodebookTree;
                branch.* = huffman_leaf_flag | @as(u32, @intCast(entry_index));
            } else if (branch.* == invalid_huffman_branch) {
                if (next_node >= nodes.len)
                    return error.InvalidVorbisCodebookTree;
                branch.* = next_node;
                node_index = next_node;
                next_node += 1;
            } else {
                if (branch.* & huffman_leaf_flag != 0)
                    return error.InvalidVorbisCodebookTree;
                node_index = branch.*;
            }
        }
    }
    if (next_node != nodes.len)
        return error.InvalidVorbisCodebookTree;
}

fn vorbisFloat32Unpack(encoded: u32) f64 {
    const unsigned_mantissa = encoded & 0x1fffff;
    const mantissa: i32 = if (encoded & 0x80000000 != 0)
        -@as(i32, @intCast(unsigned_mantissa))
    else
        @intCast(unsigned_mantissa);
    const exponent: i32 = @intCast((encoded & 0x7fe00000) >> 21);
    return std.math.ldexp(@as(f64, @floatFromInt(mantissa)), exponent - 788);
}

fn vorbisFloat32PackExact(value: f64) !u32 {
    if (!std.math.isFinite(value))
        return error.InvalidVorbisCodebookFloat;
    if (value == 0) return 0;
    const magnitude = @abs(value);
    for (0..1024) |exponent| {
        const scaled = std.math.ldexp(
            magnitude,
            788 - @as(i32, @intCast(exponent)),
        );
        if (!std.math.isFinite(scaled) or scaled < 1 or
            scaled > 0x1fffff or @trunc(scaled) != scaled)
            continue;
        const mantissa: u32 = @intFromFloat(scaled);
        const encoded =
            (@as(u32, @intCast(exponent)) << 21) |
            mantissa |
            if (std.math.signbit(value))
                @as(u32, 0x80000000)
            else
                0;
        if (vorbisFloat32Unpack(encoded) == value)
            return encoded;
    }
    return error.UnrepresentableVorbisCodebookFloat;
}

fn assignVorbisCodewords(entries: []VorbisCodebookEntry) void {
    var markers = [_]u32{0} ** 33;
    for (entries) |*entry| {
        if (entry.length == 0) continue;
        const length: usize = entry.length;
        const assigned_codeword = markers[length];

        var level = length;
        while (level != 0) {
            if (markers[level] & 1 != 0) {
                if (level == 1)
                    markers[1] += 1
                else
                    markers[level] = markers[level - 1] << 1;
                break;
            }
            markers[level] += 1;
            level -= 1;
        }

        var branch = assigned_codeword;
        for (length + 1..markers.len) |deeper| {
            if (markers[deeper] >> 1 != branch) break;
            branch = markers[deeper];
            markers[deeper] = markers[deeper - 1] << 1;
        }

        entry.codeword = assigned_codeword;
    }
}

fn validateVorbisCodebookTree(
    length_counts: *const [32]u32,
    active_entries: u32,
) !void {
    if (active_entries == 1) {
        if (length_counts[0] != 1)
            return error.InvalidVorbisCodebookLengths;
        return;
    }
    var available: u64 = 1;
    for (length_counts) |count| {
        available *= 2;
        if (count > available)
            return error.InvalidVorbisCodebookLengths;
        available -= count;
    }
    if (active_entries == 0 or available != 0)
        return error.InvalidVorbisCodebookLengths;
}

fn parseVorbisFloorZero(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisFloorZero {
    const order: u8 = @intCast(try reader.read(8));
    const rate: u16 = @intCast(try reader.read(16));
    const bark_map_size: u16 = @intCast(try reader.read(16));
    const amplitude_bits: u6 = @intCast(try reader.read(6));
    const amplitude_offset: u8 = @intCast(try reader.read(8));
    const book_count: u5 = @intCast(try reader.read(4) + 1);
    if (order == 0 or rate == 0 or bark_map_size == 0)
        return error.InvalidVorbisFloorConfiguration;
    var books = [_]u8{0} ** 16;
    for (books[0..book_count]) |*destination| {
        const book = try reader.read(8);
        if (book >= codebooks.len)
            return error.InvalidVorbisFloorCodebook;
        if (codebooks[book].lookup_type == 0)
            return error.InvalidVorbisFloorCodebook;
        destination.* = @intCast(book);
    }
    return .{
        .order = order,
        .rate = rate,
        .bark_map_size = bark_map_size,
        .amplitude_bits = amplitude_bits,
        .amplitude_offset = amplitude_offset,
        .book_count = book_count,
        .books = books,
    };
}

fn parseVorbisFloorOne(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisFloorOne {
    const partition_count: u5 = @intCast(try reader.read(5));
    var partition_classes = [_]u4{0} ** 31;
    var maximum_class: ?u4 = null;
    for (partition_classes[0..partition_count]) |*class| {
        class.* = @intCast(try reader.read(4));
        maximum_class = @max(maximum_class orelse 0, class.*);
    }
    var classes = [_]VorbisFloorOneClass{.{
        .dimensions = 0,
        .subclass_bits = 0,
        .masterbook = -1,
        .subclass_books = [_]i16{-1} ** 8,
    }} ** 16;
    const class_count: u5 = if (maximum_class) |highest|
        @as(u5, highest) + 1
    else
        0;
    if (maximum_class) |highest| {
        for (classes[0 .. @as(usize, highest) + 1]) |*class| {
            class.dimensions = @intCast(try reader.read(3) + 1);
            class.subclass_bits = @intCast(try reader.read(2));
            if (class.subclass_bits != 0) {
                const masterbook = try reader.read(8);
                if (masterbook >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                class.masterbook = @intCast(masterbook);
            }
            const subclass_count =
                @as(usize, 1) << @intCast(class.subclass_bits);
            for (class.subclass_books[0..subclass_count]) |*destination| {
                const encoded_book = try reader.read(8);
                if (encoded_book != 0 and encoded_book - 1 >= codebooks.len)
                    return error.InvalidVorbisFloorCodebook;
                destination.* = @as(i16, @intCast(encoded_book)) - 1;
            }
        }
    }
    const multiplier: u3 = @intCast(try reader.read(2) + 1);
    const range_bits: u6 = @intCast(try reader.read(4));
    var points = [_]u16{0} ** 65;
    points[1] = @as(u16, 1) << @intCast(range_bits);
    var point_count: usize = 2;
    for (partition_classes[0..partition_count]) |class| {
        const dimensions = classes[class].dimensions;
        if (dimensions > 65 - point_count)
            return error.TooManyVorbisFloorPoints;
        for (0..dimensions) |_| {
            const point: u16 = @intCast(try reader.read(range_bits));
            for (points[0..point_count]) |existing| {
                if (point == existing)
                    return error.DuplicateVorbisFloorPoint;
            }
            points[point_count] = point;
            point_count += 1;
        }
    }
    return .{
        .partition_count = partition_count,
        .partition_classes = partition_classes,
        .class_count = class_count,
        .classes = classes,
        .multiplier = multiplier,
        .range_bits = @intCast(range_bits),
        .point_count = @intCast(point_count),
        .x_list = points,
    };
}

fn parseVorbisResidue(
    reader: *VorbisBitReader,
    codebooks: []const VorbisCodebook,
) !VorbisResidue {
    const residue_type = try reader.read(16);
    if (residue_type > 2) return error.UnsupportedVorbisResidueType;
    const begin: u24 = @intCast(try reader.read(24));
    const end: u24 = @intCast(try reader.read(24));
    const partition_size: u25 = @intCast(try reader.read(24) + 1);
    const classification_count: u7 = @intCast(try reader.read(6) + 1);
    const classbook_index = try reader.read(8);
    if (classbook_index >= codebooks.len)
        return error.InvalidVorbisResidueCodebook;
    const classbook = codebooks[classbook_index];
    if (!powerAtMost(
        classification_count,
        classbook.dimensions,
        classbook.entries,
    )) return error.InvalidVorbisResidueClassbook;

    var cascades = [_]u8{0} ** 64;
    for (cascades[0..classification_count]) |*cascade| {
        const low: u8 = @intCast(try reader.read(3));
        const high: u8 = if (try reader.read(1) != 0)
            @intCast(try reader.read(5))
        else
            0;
        cascade.* = high * 8 + low;
    }
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    for (cascades[0..classification_count], 0..) |cascade, classification| {
        for (0..8) |pass| {
            if (cascade & (@as(u8, 1) << @intCast(pass)) == 0) continue;
            const book_index = try reader.read(8);
            if (book_index >= codebooks.len or
                codebooks[book_index].lookup_type == 0 or
                partition_size % codebooks[book_index].dimensions != 0)
                return error.InvalidVorbisResidueCodebook;
            books[classification][pass] = @intCast(book_index);
        }
    }
    return .{
        .kind = @enumFromInt(residue_type),
        .begin = begin,
        .end = end,
        .partition_size = partition_size,
        .classification_count = classification_count,
        .classbook = @intCast(classbook_index),
        .cascades = cascades,
        .books = books,
    };
}

fn parseVorbisMapping(
    reader: *VorbisBitReader,
    channel_count: u8,
    floor_count: u8,
    residue_count: u8,
) !VorbisMapping {
    if (try reader.read(16) != 0)
        return error.UnsupportedVorbisMappingType;
    const submap_count: u8 = if (try reader.read(1) != 0)
        @intCast(try reader.read(4) + 1)
    else
        1;
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    var coupling_step_count: u9 = 0;
    if (try reader.read(1) != 0) {
        coupling_step_count = @intCast(try reader.read(8) + 1);
        const channel_bits = vorbisILog(channel_count - 1);
        for (coupling_steps[0..coupling_step_count]) |*step| {
            const magnitude = try reader.read(channel_bits);
            const angle = try reader.read(channel_bits);
            if (magnitude == angle or magnitude >= channel_count or
                angle >= channel_count)
                return error.InvalidVorbisChannelCoupling;
            step.* = .{
                .magnitude = @intCast(magnitude),
                .angle = @intCast(angle),
            };
        }
    }
    if (try reader.read(2) != 0)
        return error.InvalidVorbisMappingReservedBits;
    var channel_mux = [_]u4{0} ** 255;
    if (submap_count > 1) {
        for (channel_mux[0..channel_count]) |*mux| {
            const decoded = try reader.read(4);
            if (decoded >= submap_count)
                return error.InvalidVorbisChannelMux;
            mux.* = @intCast(decoded);
        }
    }
    var submaps = [_]VorbisSubmap{.{
        .floor = 0,
        .residue = 0,
    }} ** 16;
    for (submaps[0..submap_count]) |*submap| {
        _ = try reader.read(8);
        const floor = try reader.read(8);
        if (floor >= floor_count)
            return error.InvalidVorbisMappingFloor;
        const residue = try reader.read(8);
        if (residue >= residue_count)
            return error.InvalidVorbisMappingResidue;
        submap.* = .{
            .floor = @intCast(floor),
            .residue = @intCast(residue),
        };
    }
    return .{
        .submap_count = @intCast(submap_count),
        .coupling_step_count = coupling_step_count,
        .coupling_steps = coupling_steps,
        .channel_mux = channel_mux,
        .submaps = submaps,
    };
}

fn vorbisILog(value: anytype) u6 {
    var remaining: u64 = @intCast(value);
    var bits: u6 = 0;
    while (remaining != 0) : (remaining >>= 1) bits += 1;
    return bits;
}

fn vorbisLookupOneValues(entries: u32, dimensions: u16) u32 {
    if (dimensions == 1) return entries;
    var low: u32 = 1;
    var high: u32 = entries;
    while (low < high) {
        const midpoint = low + (high - low + 1) / 2;
        if (powerAtMost(midpoint, dimensions, entries))
            low = midpoint
        else
            high = midpoint - 1;
    }
    return low;
}

fn powerAtMost(base: anytype, exponent: anytype, limit: anytype) bool {
    var product: u64 = 1;
    for (0..exponent) |_| {
        if (base != 0 and product > @as(u64, limit) / base)
            return false;
        product *= base;
    }
    return product <= limit;
}

pub fn pageChecksum(page: []const u8) u32 {
    var crc: u32 = 0;
    for (page, 0..) |byte, index| {
        const value: u8 = if (index >= 22 and index < 26) 0 else byte;
        crc ^= @as(u32, value) << 24;
        for (0..8) |_| {
            crc = if (crc & 0x80000000 != 0)
                (crc << 1) ^ 0x04c11db7
            else
                crc << 1;
        }
    }
    return crc;
}

fn encodePage(
    destination: []u8,
    serial_number: u32,
    sequence_number: u32,
    flags: u8,
    granule_position: u64,
    lacing_values: []const u8,
    body: []const u8,
) !usize {
    if (flags & 0xf8 != 0 or
        lacing_values.len > maximum_page_segments)
        return error.InvalidOggPage;
    var expected_body_bytes: usize = 0;
    for (lacing_values) |value|
        expected_body_bytes += value;
    if (expected_body_bytes != body.len)
        return error.InvalidOggPage;
    const header_bytes = std.math.add(
        usize,
        27,
        lacing_values.len,
    ) catch return error.OggSizeOverflow;
    const page_bytes = std.math.add(
        usize,
        header_bytes,
        body.len,
    ) catch return error.OggSizeOverflow;
    if (destination.len < page_bytes)
        return error.OggPageBufferTooSmall;
    const page = destination[0..page_bytes];
    @memset(page[0..27], 0);
    @memcpy(page[0..4], "OggS");
    page[5] = flags;
    std.mem.writeInt(u64, page[6..14], granule_position, .little);
    std.mem.writeInt(u32, page[14..18], serial_number, .little);
    std.mem.writeInt(u32, page[18..22], sequence_number, .little);
    page[26] = @intCast(lacing_values.len);
    @memcpy(page[27..header_bytes], lacing_values);
    @memcpy(page[header_bytes..], body);
    std.mem.writeInt(u32, page[22..26], pageChecksum(page), .little);
    return page_bytes;
}

fn readExactAt(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    destination: []u8,
) !void {
    return file_reader_io.readExactAt(
        io,
        file,
        offset,
        destination,
        error.TruncatedOggPage,
    );
}

fn appendTestOggPage(
    destination: []u8,
    offset: usize,
    serial_number: u32,
    sequence_number: u32,
    flags: u8,
    granule_position: u64,
    lacing_values: []const u8,
    body: []const u8,
) !usize {
    var expected_body_bytes: usize = 0;
    for (lacing_values) |value| expected_body_bytes += value;
    if (lacing_values.len > 255 or expected_body_bytes != body.len)
        return error.InvalidTestOggPage;
    const page_bytes = 27 + lacing_values.len + body.len;
    if (page_bytes > destination.len -| offset)
        return error.TestOggOutputTooSmall;
    const page = destination[offset..][0..page_bytes];
    @memset(page[0..27], 0);
    @memcpy(page[0..4], "OggS");
    page[5] = flags;
    std.mem.writeInt(u64, page[6..14], granule_position, .little);
    std.mem.writeInt(u32, page[14..18], serial_number, .little);
    std.mem.writeInt(u32, page[18..22], sequence_number, .little);
    page[26] = @intCast(lacing_values.len);
    @memcpy(page[27..][0..lacing_values.len], lacing_values);
    @memcpy(page[27 + lacing_values.len ..], body);
    std.mem.writeInt(u32, page[22..26], pageChecksum(page), .little);
    return offset + page_bytes;
}

const TestVorbisCodebookEncoding = enum {
    unordered,
    unordered_deep,
    ordered,
    ordered_gap,
    sparse,
};

const OggFileFaults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    set_length_calls: usize = 0,
    maximum_write_bytes: usize = 0,
    fail_write_call: ?usize = null,
    fail_set_length_call: ?usize = null,
    partial_write_bytes: usize = 0,

    fn operations(self: *@This()) file_writer_io.Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn clearFailures(self: *@This()) void {
        self.fail_write_call = null;
        self.fail_set_length_call = null;
        self.partial_write_bytes = 0;
    }

    fn writeAt(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        offset: u64,
        bytes: []const u8,
    ) !usize {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingOggFaultContext,
        ));
        self.write_calls += 1;
        if (self.fail_write_call == self.write_calls) {
            const partial = @min(self.partial_write_bytes, bytes.len);
            if (partial != 0)
                try self.delegate.writeAt(
                    io,
                    file,
                    offset,
                    bytes[0..partial],
                );
            return error.InjectedOggWriteFailure;
        }
        const count = if (self.maximum_write_bytes == 0)
            bytes.len
        else
            @min(self.maximum_write_bytes, bytes.len);
        try self.delegate.writeAt(io, file, offset, bytes[0..count]);
        return count;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingOggFaultContext,
        ));
        self.set_length_calls += 1;
        if (self.fail_set_length_call == self.set_length_calls)
            return error.InjectedOggTruncateFailure;
        try self.delegate.setLength(io, file, length);
    }

    const vtable = file_writer_io.Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
    };
};

const TestVorbisSetupPacket = struct {
    bytes: []const u8,
    framing_bit: usize,
    mapping_reserved_bit: usize,
    floor_point_bit: ?usize,
};

const TestVorbisBitWriter = struct {
    bytes: []u8,
    bit_offset: usize = 0,

    fn init(bytes: []u8) TestVorbisBitWriter {
        @memset(bytes, 0);
        return .{ .bytes = bytes };
    }

    fn write(self: *TestVorbisBitWriter, value: u32, bit_count: u6) void {
        for (0..bit_count) |index| {
            const destination_bit = self.bit_offset + index;
            self.bytes[destination_bit / 8] |= @as(u8, @intCast(
                (value >> @intCast(index)) & 1,
            )) << @intCast(destination_bit % 8);
        }
        self.bit_offset += bit_count;
    }
};

fn makeTestVorbisSetup(
    destination: []u8,
    encoding: TestVorbisCodebookEncoding,
    rich: bool,
    floor_zero: bool,
) TestVorbisSetupPacket {
    @memcpy(destination[0..7], "\x05vorbis");
    var writer = TestVorbisBitWriter.init(destination[7..]);
    writer.write(0, 8);
    writer.write(0x564342, 24);
    writer.write(1, 16);
    const codebook_entries: u32 = switch (encoding) {
        .unordered_deep, .ordered_gap => 4,
        else => 2,
    };
    writer.write(codebook_entries, 24);
    switch (encoding) {
        .unordered => {
            writer.write(0, 1);
            writer.write(0, 1);
            writer.write(0, 5);
            writer.write(0, 5);
        },
        .unordered_deep => {
            writer.write(0, 1);
            writer.write(0, 1);
            for (0..4) |_| writer.write(1, 5);
        },
        .ordered => {
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(2, 2);
        },
        .ordered_gap => {
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(0, 3);
            writer.write(4, 3);
        },
        .sparse => {
            writer.write(0, 1);
            writer.write(1, 1);
            writer.write(1, 1);
            writer.write(0, 5);
            writer.write(0, 1);
        },
    }
    writer.write(1, 4);
    writer.write(0, 32);
    writer.write((@as(u32, 788) << 21) | 1, 32);
    writer.write(1, 4);
    writer.write(0, 1);
    for (0..codebook_entries) |index| {
        writer.write(@intCast(index), 2);
    }

    writer.write(0, 6);
    writer.write(0, 16);

    writer.write(0, 6);
    writer.write(if (floor_zero) 0 else 1, 16);
    var floor_point_bit: ?usize = null;
    if (floor_zero) {
        writer.write(1, 8);
        writer.write(48_000, 16);
        writer.write(64, 16);
        writer.write(8, 6);
        writer.write(60, 8);
        writer.write(0, 4);
        writer.write(0, 8);
    } else if (rich) {
        writer.write(1, 5);
        writer.write(0, 4);
        writer.write(0, 3);
        writer.write(1, 2);
        writer.write(0, 8);
        writer.write(1, 8);
        writer.write(1, 8);
        writer.write(0, 2);
        writer.write(2, 4);
        floor_point_bit = 7 * 8 + writer.bit_offset;
        writer.write(1, 2);
    } else {
        writer.write(0, 5);
        writer.write(0, 2);
        writer.write(0, 4);
    }

    writer.write(0, 6);
    writer.write(0, 16);
    writer.write(0, 24);
    writer.write(0, 24);
    writer.write(0, 24);
    writer.write(0, 6);
    writer.write(0, 8);
    writer.write(if (rich) 1 else 0, 3);
    writer.write(0, 1);
    if (rich) writer.write(0, 8);

    writer.write(0, 6);
    writer.write(0, 16);
    writer.write(if (rich) 1 else 0, 1);
    if (rich) writer.write(1, 4);
    writer.write(if (rich) 1 else 0, 1);
    if (rich) {
        writer.write(0, 8);
        writer.write(0, 1);
        writer.write(1, 1);
    }
    const mapping_reserved_bit = 7 * 8 + writer.bit_offset;
    writer.write(0, 2);
    if (rich) {
        writer.write(0, 4);
        writer.write(1, 4);
    }
    const submap_count: usize = if (rich) 2 else 1;
    for (0..submap_count) |_| {
        writer.write(0, 8);
        writer.write(0, 8);
        writer.write(0, 8);
    }

    writer.write(0, 6);
    writer.write(if (rich) 1 else 0, 1);
    writer.write(0, 16);
    writer.write(0, 16);
    writer.write(0, 8);
    const framing_bit = 7 * 8 + writer.bit_offset;
    writer.write(1, 1);
    return .{
        .bytes = destination[0 .. 7 + (writer.bit_offset + 7) / 8],
        .framing_bit = framing_bit,
        .mapping_reserved_bit = mapping_reserved_bit,
        .floor_point_bit = floor_point_bit,
    };
}

fn flipTestBit(bytes: []u8, bit_offset: usize) void {
    bytes[bit_offset / 8] ^= @as(u8, 1) << @intCast(bit_offset % 8);
}

test "Ogg writer and packet iterator preserve continued packets" {
    var encoded: [70_000]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x12345678);
    const first = [_]u8{0xaa} ** 65_100;
    try writer.appendPacket(&first, 100, true, false);
    try writer.appendPacket("tail", 104, false, true);
    var packet_storage: [65_100]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &packet_storage);
    const decoded_first = (try packets.next()).?;
    try std.testing.expect(decoded_first.beginning);
    try std.testing.expectEqual(@as(u64, 100), decoded_first.granule_position);
    try std.testing.expectEqualSlices(u8, &first, decoded_first.bytes);
    const tail = (try packets.next()).?;
    try std.testing.expect(tail.end);
    try std.testing.expectEqualStrings("tail", tail.bytes);
    try std.testing.expect((try packets.next()) == null);
}

test "Ogg packet iteration rolls back capacity and hostile state failures" {
    var encoded: [512]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 9);
    const source = [_]u8{0x5a} ** 300;
    try writer.appendPacket(&source, 300, true, true);

    var short_storage: [260]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &short_storage);
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        packets.next(),
    );
    try std.testing.expectEqual(@as(usize, 0), packets.pages.offset);
    try std.testing.expect(packets.page == null);
    try std.testing.expectEqual(@as(usize, 0), packets.packet_bytes);

    var complete_storage: [300]u8 = undefined;
    packets.storage = &complete_storage;
    const packet = (try packets.next()).?;
    try std.testing.expectEqualSlices(u8, &source, packet.bytes);
    try std.testing.expect(packet.beginning);
    try std.testing.expect(packet.end);

    var invalid = PacketIterator.init(writer.bytes(), &complete_storage);
    invalid.packet_bytes = complete_storage.len + 1;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        invalid.next(),
    );
    invalid.packet_bytes = 0;
    invalid.segment_index = 1;
    try std.testing.expectError(
        error.InvalidOggPacketReaderState,
        invalid.next(),
    );

    var overflow = PacketIterator.init(writer.bytes(), &complete_storage);
    overflow.packet_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.OggPacketCountOverflow,
        overflow.next(),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        overflow.packet_index,
    );
    try std.testing.expectEqual(@as(usize, 0), overflow.pages.offset);
}

test "file-backed Ogg writer streams continued packets" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "stream.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        &page_storage,
        0x12345678,
    );
    const first = [_]u8{0xaa} ** 65_100;
    try writer.appendPacket(&first, 100, true, false);
    try writer.appendPacket("tail", 104, false, true);
    try writer.finalize();
    try std.testing.expectEqual(
        writer.byte_count,
        try file.length(std.testing.io),
    );

    var reader = try FilePacketReader.init(std.testing.io, file);
    var reader_page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [65_100]u8 = undefined;
    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.next(
            &reader_page_storage,
            packet_storage[0..65_000],
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), reader.pages.offset);
    try std.testing.expect(reader.page == null);
    try std.testing.expect(reader.page_storage_pointer == null);
    try std.testing.expect(reader.packet_storage_pointer == null);
    const decoded_first = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(decoded_first.beginning);
    try std.testing.expectEqual(@as(u64, 100), decoded_first.granule_position);
    try std.testing.expectEqualSlices(u8, &first, decoded_first.bytes);
    const tail = (try reader.next(
        &reader_page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(tail.end);
    try std.testing.expectEqualStrings("tail", tail.bytes);
    try std.testing.expect(
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )) == null,
    );
}

test "file-backed Ogg packet capacity rollback reloads chained packed BOS pages" {
    var encoded: [1024]u8 = undefined;
    var body: [301]u8 = @splat(0x5a);
    body[0] = 0x11;
    var encoded_bytes = try appendTestOggPage(
        &encoded,
        0,
        16,
        0,
        0x06,
        1,
        &.{1},
        &.{0x01},
    );
    encoded_bytes = try appendTestOggPage(
        &encoded,
        encoded_bytes,
        17,
        0,
        0x06,
        300,
        &.{ 1, 255, 45 },
        &body,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packed-capacity.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        encoded[0..encoded_bytes],
        0,
    );
    try file.setLength(std.testing.io, encoded_bytes);

    var reader = try FilePacketReader.initChained(std.testing.io, file);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [300]u8 = undefined;
    const prelude = (try reader.next(
        &page_storage,
        packet_storage[0..260],
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x01}, prelude.bytes);
    try std.testing.expectEqual(
        @as(u32, 0),
        prelude.logical_stream_index,
    );
    const first = (try reader.next(
        &page_storage,
        packet_storage[0..260],
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x11}, first.bytes);
    try std.testing.expect(first.beginning);
    try std.testing.expectEqual(@as(u32, 1), first.logical_stream_index);

    try std.testing.expectError(
        error.OggPacketBufferTooSmall,
        reader.next(
            &page_storage,
            packet_storage[0..260],
        ),
    );
    try std.testing.expect(reader.page == null);
    try std.testing.expectEqual(@as(usize, 1), reader.reload_segment_index);
    try std.testing.expectEqual(@as(usize, 1), reader.reload_body_offset);
    try std.testing.expect(reader.preserve_logical_index_on_reload);
    try std.testing.expectEqual(@as(u64, 2), reader.packet_index);
    try std.testing.expectEqual(
        @as(u64, 1),
        reader.logical_stream_packet_index,
    );

    const second = (try reader.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0x5a} ** 300),
        second.bytes,
    );
    try std.testing.expect(!second.beginning);
    try std.testing.expect(second.end);
    try std.testing.expectEqual(@as(u64, 300), second.granule_position);
    try std.testing.expect(
        (try reader.next(
            &page_storage,
            &packet_storage,
        )) == null,
    );
}

test "Ogg page readers reject invalid cursors without trapping" {
    var encoded: [64]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 7);
    try writer.appendPacket("end", 3, true, true);

    var pages = PageIterator.initChained(writer.bytes());
    _ = try pages.next();
    pages.encoded = encoded[0 .. writer.bytes().len + 1];
    encoded[writer.bytes().len] = 0;
    const ended = pages.ended;
    const logical_stream_index = pages.logical_stream_index;
    try std.testing.expectError(
        error.TruncatedOggPage,
        pages.next(),
    );
    try std.testing.expectEqual(ended, pages.ended);
    try std.testing.expectEqual(
        logical_stream_index,
        pages.logical_stream_index,
    );

    pages.offset = pages.encoded.len + 1;
    try std.testing.expectError(
        error.InvalidOggReaderState,
        pages.next(),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "invalid-cursor.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var file_pages = try FilePageReader.init(std.testing.io, file);
    var storage: [27]u8 = undefined;
    file_pages.file_size = std.math.maxInt(u64);
    file_pages.offset = std.math.maxInt(u64) - 10;
    try std.testing.expectError(
        error.TruncatedOggPage,
        file_pages.next(&storage),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 10,
        file_pages.offset,
    );
    file_pages.file_size = 4;
    file_pages.offset = 5;
    try std.testing.expectError(
        error.InvalidOggFileReaderState,
        file_pages.next(&storage),
    );

    var file_packets = try FilePacketReader.init(std.testing.io, file);
    var packet_storage: [1]u8 = undefined;
    file_packets.page_storage_pointer = storage[0..].ptr;
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
    file_packets.page_storage_pointer = null;
    file_packets.packet_bytes = packet_storage.len + 1;
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
    file_packets.packet_bytes = 0;
    file_packets.packet_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
    file_packets.packet_index = 0;
    file_packets.reload_segment_index = std.math.maxInt(usize);
    try std.testing.expectError(
        error.InvalidOggFilePacketReaderState,
        file_packets.next(&storage, &packet_storage),
    );
}

test "file-backed Ogg writer recovers positional failures" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "recovery.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var faults = OggFileFaults{ .maximum_write_bytes = 3 };
    var writer = try FileWriter.initWithOperations(
        std.testing.io,
        file,
        &page_storage,
        77,
        faults.operations(),
    );
    try writer.appendPacket("one", 1, true, false);
    try std.testing.expect(faults.write_calls > 1);
    const committed_bytes = writer.byte_count;

    faults.maximum_write_bytes = 0;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 2;
    try std.testing.expectError(
        error.InjectedOggWriteFailure,
        writer.appendPacket("two", 2, false, true),
    );
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(committed_bytes, writer.byte_count);
    try std.testing.expectEqual(
        committed_bytes,
        try file.length(std.testing.io),
    );

    faults.fail_write_call = faults.write_calls + 1;
    faults.fail_set_length_call = faults.set_length_calls + 1;
    faults.partial_write_bytes = 2;
    try std.testing.expectError(
        error.InjectedOggWriteFailure,
        writer.appendPacket("two", 2, false, true),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    faults.clearFailures();
    try writer.recover();
    try std.testing.expect(writer.valid());
    try writer.appendPacket("two", 2, false, true);
    try writer.finalize();

    var reader = try FilePacketReader.init(std.testing.io, file);
    var reader_page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [3]u8 = undefined;
    try std.testing.expectEqualStrings(
        "one",
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "two",
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )).?.bytes,
    );
    try std.testing.expect(
        (try reader.next(
            &reader_page_storage,
            &packet_storage,
        )) == null,
    );
}

test "file-backed Ogg writer validates before file mutation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "validation.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, "keep", 0);
    var small_storage: [maximum_page_bytes - 1]u8 = undefined;
    try std.testing.expectError(
        error.OggPageBufferTooSmall,
        FileWriter.init(
            std.testing.io,
            file,
            &small_storage,
            1,
        ),
    );
    try std.testing.expectEqual(
        @as(u64, 4),
        try file.length(std.testing.io),
    );

    var page_storage: [maximum_page_bytes]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        &page_storage,
        1,
    );
    try std.testing.expectError(
        error.OggStreamNotEnded,
        writer.finalize(),
    );
    try std.testing.expectError(
        error.InvalidOggBeginningOfStream,
        writer.appendPacket("bad", 0, false, false),
    );
    try std.testing.expectEqual(@as(u64, 0), writer.byte_count);
    try std.testing.expectEqual(
        @as(u64, 0),
        try file.length(std.testing.io),
    );
    @memcpy(page_storage[100..103], "bad");
    try std.testing.expectError(
        error.OverlappingOggWriterStorage,
        writer.appendPacket(
            page_storage[100..103],
            0,
            true,
            false,
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), writer.byte_count);
    try std.testing.expectError(
        error.OggSizeOverflow,
        packetLayout(std.math.maxInt(usize)),
    );
    writer.began = true;
    writer.byte_count = 1;
    try std.testing.expect(!writer.valid());
    try std.testing.expectError(
        error.InvalidOggFileWriterState,
        writer.recover(),
    );
}

test "Ogg parser rejects corruption and sequence gaps" {
    var encoded: [256]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 7);
    try writer.appendPacket("one", 1, true, false);
    try writer.appendPacket("two", 2, false, true);
    const bytes = writer.bytes();
    var corrupt: [256]u8 = undefined;
    @memcpy(corrupt[0..bytes.len], bytes);
    corrupt[bytes.len - 1] ^= 1;
    var corrupt_pages = PageIterator.init(corrupt[0..bytes.len]);
    _ = try corrupt_pages.next();
    try std.testing.expectError(
        error.OggPageChecksumMismatch,
        corrupt_pages.next(),
    );

    @memcpy(corrupt[0..bytes.len], bytes);
    const second_page = 27 + 1 + 3;
    std.mem.writeInt(
        u32,
        corrupt[second_page + 18 ..][0..4],
        9,
        .little,
    );
    @memset(corrupt[second_page + 22 ..][0..4], 0);
    std.mem.writeInt(
        u32,
        corrupt[second_page + 22 ..][0..4],
        pageChecksum(corrupt[second_page..bytes.len]),
        .little,
    );
    var gap_pages = PageIterator.init(corrupt[0..bytes.len]);
    _ = try gap_pages.next();
    try std.testing.expectError(
        error.InvalidOggPageSequence,
        gap_pages.next(),
    );
}

test "Ogg readers reject single-bit page damage transactionally" {
    var clean: [128]u8 = undefined;
    const page_bytes = try appendTestOggPage(
        &clean,
        0,
        0x1020_3040,
        0,
        0x06,
        4,
        &.{4},
        "data",
    );

    for (0..page_bytes) |byte_index| {
        var damaged = clean;
        damaged[byte_index] ^= 1;
        const encoded = damaged[0..page_bytes];

        var pages = PageIterator.init(encoded);
        const pages_before = pages;
        const page_rejected = if (pages.next()) |_|
            false
        else |_|
            true;
        try std.testing.expect(page_rejected);
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = PacketIterator.init(
            encoded,
            &packet_storage,
        );
        const packets_before = packets;
        const packet_rejected = if (packets.next()) |_|
            false
        else |_|
            true;
        try std.testing.expect(packet_rejected);
        try std.testing.expectEqualDeep(packets_before, packets);
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }

    for (1..page_bytes) |truncated_bytes| {
        const encoded = clean[0..truncated_bytes];

        var pages = PageIterator.init(encoded);
        const pages_before = pages;
        try std.testing.expectError(
            error.TruncatedOggPage,
            pages.next(),
        );
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = PacketIterator.init(
            encoded,
            &packet_storage,
        );
        const packets_before = packets;
        try std.testing.expectError(
            error.TruncatedOggPage,
            packets.next(),
        );
        try std.testing.expectEqualDeep(packets_before, packets);
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }
}

test "file-backed Ogg readers reject single-bit page damage transactionally" {
    var clean: [128]u8 = undefined;
    const page_bytes = try appendTestOggPage(
        &clean,
        0,
        0x1020_3040,
        0,
        0x06,
        4,
        &.{4},
        "data",
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "damaged.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var page_storage: [maximum_page_bytes]u8 = undefined;

    for (0..page_bytes) |byte_index| {
        var damaged = clean;
        damaged[byte_index] ^= 1;
        try file.setLength(std.testing.io, page_bytes);
        try file.writePositionalAll(
            std.testing.io,
            damaged[0..page_bytes],
            0,
        );

        var pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        const pages_before = pages;
        const page_rejected =
            if (pages.next(&page_storage)) |_|
                false
            else |_|
                true;
        try std.testing.expect(page_rejected);
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = try FilePacketReader.init(
            std.testing.io,
            file,
        );
        const packets_before = packets;
        const packet_rejected =
            if (packets.next(
                &page_storage,
                &packet_storage,
            )) |_|
                false
            else |_|
                true;
        try std.testing.expect(packet_rejected);
        try std.testing.expectEqualDeep(
            packets_before,
            packets,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }

    for (1..page_bytes) |truncated_bytes| {
        try file.setLength(std.testing.io, page_bytes);
        try file.writePositionalAll(
            std.testing.io,
            clean[0..page_bytes],
            0,
        );
        try file.setLength(std.testing.io, truncated_bytes);

        var pages = try FilePageReader.init(
            std.testing.io,
            file,
        );
        const pages_before = pages;
        try std.testing.expectError(
            error.TruncatedOggPage,
            pages.next(&page_storage),
        );
        try std.testing.expectEqualDeep(pages_before, pages);

        var packet_storage: [4]u8 = @splat(0xa5);
        var packets = try FilePacketReader.init(
            std.testing.io,
            file,
        );
        const packets_before = packets;
        try std.testing.expectError(
            error.TruncatedOggPage,
            packets.next(
                &page_storage,
                &packet_storage,
            ),
        );
        try std.testing.expectEqualDeep(
            packets_before,
            packets,
        );
        try std.testing.expectEqualSlices(
            u8,
            &@as([4]u8, @splat(0xa5)),
            &packet_storage,
        );
    }
}

test "Ogg page readers resynchronize across bounded inserted junk" {
    var clean: [256]u8 = undefined;
    var clean_bytes = try appendTestOggPage(
        &clean,
        0,
        55,
        0,
        0x02,
        1,
        &.{3},
        "one",
    );
    const second_offset = clean_bytes;
    clean_bytes = try appendTestOggPage(
        &clean,
        clean_bytes,
        55,
        1,
        0,
        2,
        &.{3},
        "two",
    );
    const third_offset = clean_bytes;
    clean_bytes = try appendTestOggPage(
        &clean,
        clean_bytes,
        55,
        2,
        0x04,
        3,
        &.{5},
        "three",
    );
    const junk = [_]u8{ 'O', 'g', 'g', 'S', 0xff, 0x5a };
    var damaged: [clean.len + junk.len]u8 = undefined;
    @memcpy(damaged[0..second_offset], clean[0..second_offset]);
    @memcpy(
        damaged[second_offset..][0..junk.len],
        &junk,
    );
    @memcpy(
        damaged[second_offset + junk.len ..][0 .. clean_bytes - second_offset],
        clean[second_offset..clean_bytes],
    );
    const damaged_bytes =
        damaged[0 .. clean_bytes + junk.len];

    var pages = PageIterator.init(damaged_bytes);
    try std.testing.expectEqual(
        @as(u32, 0),
        (try pages.next()).?.sequence_number,
    );
    const retained_pages = pages;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        pages.next(),
    );
    try std.testing.expectEqual(retained_pages.offset, pages.offset);
    try std.testing.expectError(
        error.InvalidOggResynchronizationLimit,
        pages.resynchronize(0),
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        pages.resynchronize(junk.len - 1),
    );
    try std.testing.expectEqual(retained_pages.offset, pages.offset);
    try std.testing.expectEqual(
        junk.len,
        try pages.resynchronize(junk.len),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try pages.next()).?.sequence_number,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        (try pages.next()).?.sequence_number,
    );
    try std.testing.expect((try pages.next()) == null);

    var packet_storage: [5]u8 = undefined;
    var packets = PacketIterator.init(
        damaged_bytes,
        &packet_storage,
    );
    try std.testing.expectEqualStrings(
        "one",
        (try packets.next()).?.bytes,
    );
    const retained_packets = packets;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        packets.next(),
    );
    try std.testing.expectEqual(
        retained_packets.packet_index,
        packets.packet_index,
    );
    try std.testing.expectEqual(
        junk.len,
        try packets.resynchronize(junk.len),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try packets.next()).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "three",
        (try packets.next()).?.bytes,
    );
    try std.testing.expect((try packets.next()) == null);
    try std.testing.expectEqual(
        @as(u64, 3),
        packets.packet_index,
    );

    var packed_encoded: [64]u8 = undefined;
    const packed_bytes = try appendTestOggPage(
        &packed_encoded,
        0,
        56,
        0,
        0x06,
        2,
        &.{ 3, 3 },
        "onetwo",
    );
    var packed_storage: [3]u8 = undefined;
    var packed_packets = PacketIterator.init(
        packed_encoded[0..packed_bytes],
        &packed_storage,
    );
    _ = try packed_packets.next();
    try std.testing.expectError(
        error.OggPacketResynchronizationRequiresPageBoundary,
        packed_packets.resynchronize(1),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try packed_packets.next()).?.bytes,
    );

    var corrupt: [clean.len]u8 = undefined;
    @memcpy(corrupt[0..clean_bytes], clean[0..clean_bytes]);
    corrupt[third_offset - 1] ^= 1;
    var corrupt_pages = PageIterator.init(
        corrupt[0..clean_bytes],
    );
    _ = try corrupt_pages.next();
    try std.testing.expectError(
        error.OggPageChecksumMismatch,
        corrupt_pages.next(),
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        corrupt_pages.resynchronize(
            clean_bytes - second_offset,
        ),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "resynchronize.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        damaged_bytes,
        0,
    );
    var file_pages = try FilePageReader.init(
        std.testing.io,
        file,
    );
    var page_storage: [maximum_page_bytes]u8 = undefined;
    _ = try file_pages.next(&page_storage);
    const retained_file_pages = file_pages;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        file_pages.next(&page_storage),
    );
    try std.testing.expectEqual(
        retained_file_pages.offset,
        file_pages.offset,
    );
    try std.testing.expectError(
        error.OggResynchronizationLimitReached,
        file_pages.resynchronize(
            &page_storage,
            junk.len - 1,
        ),
    );
    try std.testing.expectEqual(
        retained_file_pages.offset,
        file_pages.offset,
    );
    try std.testing.expectError(
        error.InvalidOggResynchronizationLimit,
        file_pages.resynchronize(&page_storage, 0),
    );
    var short_page_storage: [maximum_page_bytes - 1]u8 = undefined;
    try std.testing.expectError(
        error.OggPageBufferTooSmall,
        file_pages.resynchronize(
            &short_page_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        junk.len,
        try file_pages.resynchronize(
            &page_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try file_pages.next(&page_storage)).?.sequence_number,
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        (try file_pages.next(&page_storage)).?.sequence_number,
    );
    try std.testing.expect(
        (try file_pages.next(&page_storage)) == null,
    );

    var file_packets = try FilePacketReader.init(
        std.testing.io,
        file,
    );
    var file_packet_storage: [5]u8 = undefined;
    try std.testing.expectEqualStrings(
        "one",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    const retained_file_packets = file_packets;
    try std.testing.expectError(
        error.UnsupportedOggVersion,
        file_packets.next(
            &page_storage,
            &file_packet_storage,
        ),
    );
    try std.testing.expectEqual(
        retained_file_packets.packet_index,
        file_packets.packet_index,
    );
    var other_page_storage: [maximum_page_bytes]u8 = undefined;
    try std.testing.expectError(
        error.OggReaderStorageChanged,
        file_packets.resynchronize(
            &other_page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    var reload_pending = file_packets;
    reload_pending.page = null;
    reload_pending.segment_index = 0;
    reload_pending.body_offset = 0;
    reload_pending.reload_segment_index = 1;
    reload_pending.reload_body_offset = 1;
    reload_pending.preserve_logical_index_on_reload = true;
    try std.testing.expectError(
        error.OggPacketResynchronizationRequiresPageBoundary,
        reload_pending.resynchronize(
            &page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqual(
        junk.len,
        try file_packets.resynchronize(
            &page_storage,
            &file_packet_storage,
            junk.len,
        ),
    );
    try std.testing.expectEqualStrings(
        "two",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    try std.testing.expectEqualStrings(
        "three",
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )).?.bytes,
    );
    try std.testing.expect(
        (try file_packets.next(
            &page_storage,
            &file_packet_storage,
        )) == null,
    );
    try std.testing.expectEqual(
        @as(u64, 3),
        file_packets.packet_index,
    );
}

test "Ogg writer preserves empty packets and fails transactionally" {
    var too_small: [27]u8 = undefined;
    var failed_writer = StreamWriter.init(&too_small, 1);
    try std.testing.expectError(
        error.OggOutputTooSmall,
        failed_writer.appendPacket("", 0, true, true),
    );
    try std.testing.expectEqual(@as(usize, 0), failed_writer.byte_count);
    try std.testing.expect(!failed_writer.began);

    var encoded: [128]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 2);
    try writer.appendPacket("", 0, true, false);
    try writer.appendPacket("data", 4, false, true);
    var storage: [4]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &storage);
    try std.testing.expectEqual(@as(usize, 0), (try packets.next()).?.bytes.len);
    try std.testing.expectEqualStrings("data", (try packets.next()).?.bytes);
}

test "Ogg chained readers restart logical stream sequencing" {
    var first_encoded: [128]u8 = undefined;
    var first_writer = StreamWriter.init(&first_encoded, 11);
    try first_writer.appendPacket("first", 5, true, true);
    var second_encoded: [128]u8 = undefined;
    var second_writer = StreamWriter.init(&second_encoded, 22);
    try second_writer.appendPacket("second", 6, true, true);
    var chained_encoded: [256]u8 = undefined;
    const first_bytes = first_writer.bytes();
    const second_bytes = second_writer.bytes();
    @memcpy(chained_encoded[0..first_bytes.len], first_bytes);
    @memcpy(
        chained_encoded[first_bytes.len..][0..second_bytes.len],
        second_bytes,
    );
    const chained =
        chained_encoded[0 .. first_bytes.len + second_bytes.len];

    var strict_storage: [6]u8 = undefined;
    var strict = PacketIterator.init(chained, &strict_storage);
    try std.testing.expectEqualStrings(
        "first",
        (try strict.next()).?.bytes,
    );
    try std.testing.expectError(
        error.OggDataAfterEndOfStream,
        strict.next(),
    );

    var storage: [6]u8 = undefined;
    var packets = PacketIterator.initChained(chained, &storage);
    const first = (try packets.next()).?;
    try std.testing.expect(first.beginning);
    try std.testing.expect(first.end);
    try std.testing.expectEqual(@as(u32, 0), first.logical_stream_index);
    try std.testing.expectEqualStrings("first", first.bytes);
    const second = (try packets.next()).?;
    try std.testing.expect(second.beginning);
    try std.testing.expect(second.end);
    try std.testing.expectEqual(@as(u32, 1), second.logical_stream_index);
    try std.testing.expectEqualStrings("second", second.bytes);
    try std.testing.expect((try packets.next()) == null);

    var malformed = chained_encoded;
    malformed[first_bytes.len + 5] &= ~@as(u8, 0x02);
    @memset(malformed[first_bytes.len + 22 ..][0..4], 0);
    std.mem.writeInt(
        u32,
        malformed[first_bytes.len + 22 ..][0..4],
        pageChecksum(
            malformed[first_bytes.len .. first_bytes.len + second_bytes.len],
        ),
        .little,
    );
    var malformed_pages = PageIterator.initChained(
        malformed[0 .. first_bytes.len + second_bytes.len],
    );
    _ = try malformed_pages.next();
    try std.testing.expectError(
        error.MissingOggBeginningOfStream,
        malformed_pages.next(),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "chained.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, chained, 0);
    try file.setLength(std.testing.io, chained.len);
    var file_reader = try FilePacketReader.initChained(
        std.testing.io,
        file,
    );
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var file_packet_storage: [6]u8 = undefined;
    const file_first = (try file_reader.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u32, 0), file_first.logical_stream_index);
    const file_second = (try file_reader.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u32, 1), file_second.logical_stream_index);
    try std.testing.expectEqualStrings("second", file_second.bytes);
    try std.testing.expect(
        (try file_reader.next(
            &page_storage,
            &file_packet_storage,
        )) == null,
    );
}

test "Vorbis identification validates declared stream properties" {
    var packet: [30]u8 = @splat(0);
    packet[0] = 1;
    @memcpy(packet[1..7], "vorbis");
    packet[11] = 2;
    std.mem.writeInt(u32, packet[12..16], 48_000, .little);
    packet[28] = 0xb8;
    packet[29] = 1;
    const info = try VorbisIdentification.parse(&packet);
    try std.testing.expectEqual(@as(u16, 256), info.small_block_size);
    try std.testing.expectEqual(@as(u16, 2048), info.large_block_size);
    packet[29] = 0;
    try std.testing.expectError(
        error.InvalidVorbisIdentificationHeader,
        VorbisIdentification.parse(&packet),
    );
}

test "Vorbis identification encoding round trips transactionally" {
    const expected = VorbisIdentification{
        .channel_count = 6,
        .sample_rate = 96_000,
        .bitrate_maximum = 640_000,
        .bitrate_nominal = 384_000,
        .bitrate_minimum = -1,
        .small_block_size = 256,
        .large_block_size = 4_096,
    };
    var destination: [30]u8 = @splat(0xaa);
    const encoded = try encodeVorbisIdentificationPacket(
        &destination,
        expected,
    );
    try std.testing.expectEqualDeep(
        expected,
        try VorbisIdentification.parse(encoded),
    );

    const before = destination;
    var invalid = expected;
    invalid.small_block_size = 192;
    try std.testing.expectError(
        error.InvalidVorbisIdentification,
        encodeVorbisIdentificationPacket(&destination, invalid),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    try std.testing.expectError(
        error.VorbisIdentificationOutputTooSmall,
        encodeVorbisIdentificationPacket(
            destination[0..29],
            expected,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
}

test "Ogg Vorbis logical stream decodes to granule-trimmed PCM" {
    var identification_packet = [_]u8{0} ** 30;
    identification_packet[0] = 1;
    @memcpy(identification_packet[1..7], "vorbis");
    identification_packet[11] = 1;
    std.mem.writeInt(
        u32,
        identification_packet[12..16],
        48_000,
        .little,
    );
    identification_packet[28] = 0x66;
    identification_packet[29] = 1;
    var comment_packet = [_]u8{0} ** 16;
    comment_packet[0] = 3;
    @memcpy(comment_packet[1..7], "vorbis");
    comment_packet[15] = 1;
    var setup_packet_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &setup_packet_storage,
        .unordered,
        false,
        false,
    );

    var encoded: [1024]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 0x564F_5242);
    try writer.appendPacket(&identification_packet, 0, true, false);
    try writer.appendPacket(&comment_packet, 0, false, false);
    try writer.appendPacket(setup_packet.bytes, 0, false, false);
    try writer.appendPacket(&.{0}, 0, false, false);
    try writer.appendPacket(&.{0}, 32, false, true);
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisSeekPoints(writer.bytes()),
    );
    var seek_points: [2]VorbisSeekPoint = undefined;
    const seek_index = try buildVorbisSeekIndex(
        writer.bytes(),
        &seek_points,
    );
    try std.testing.expectEqual(@as(i64, 0), seek_index[0].pcm_end);
    try std.testing.expectEqual(@as(u64, 3), seek_index[0].packet.logical_packet_index);
    try std.testing.expectEqual(@as(i64, 32), seek_index[1].pcm_end);
    try std.testing.expectEqual(
        seek_index[0].packet.byte_offset,
        seek_index[1].decode.byte_offset,
    );
    try std.testing.expectEqualDeep(
        seek_index[0],
        try findVorbisSeekPoint(seek_index, 0, 16),
    );
    try std.testing.expectEqualDeep(
        seek_index[1],
        try findVorbisSeekPoint(seek_index, 0, 32),
    );
    try std.testing.expectError(
        error.VorbisSeekLogicalStreamNotFound,
        findVorbisSeekPoint(seek_index, 1, 0),
    );
    var short_seek_index = [_]VorbisSeekPoint{.{
        .pcm_end = 99,
        .decode = seek_index[0].decode,
        .packet = seek_index[0].packet,
    }};
    try std.testing.expectError(
        error.VorbisSeekIndexTooSmall,
        buildVorbisSeekIndex(writer.bytes(), &short_seek_index),
    );
    try std.testing.expectEqual(@as(i64, 99), short_seek_index[0].pcm_end);

    var packet_storage: [128]u8 = undefined;
    var packets = PacketIterator.init(writer.bytes(), &packet_storage);
    const encoded_identification = (try packets.next()).?;
    const identification =
        try VorbisIdentification.parse(encoded_identification.bytes);
    const encoded_comments = (try packets.next()).?;
    var comments = try VorbisCommentIterator.init(encoded_comments.bytes);
    try std.testing.expectEqual(@as(usize, 0), comments.vendor.len);
    try std.testing.expect((try comments.next()) == null);
    const encoded_setup = (try packets.next()).?;
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(
        encoded_setup.bytes,
        identification.channel_count,
        .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        },
    );

    var decoder = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    var spectra: [32]f32 = undefined;
    var floor_curves: [32]f32 = undefined;
    var coupling: [32]f32 = undefined;
    var time: [64]f32 = undefined;
    var classifications: [1]u8 = undefined;
    var windowed: [64]f32 = undefined;
    const first_audio = (try packets.next()).?;
    var empty_output: [0]f32 = .{};
    const empty_outputs = [_][]f32{&empty_output};
    const first_result = try decoder.decode(
        first_audio,
        identification,
        setup,
        &empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), first_result.sample_count);

    const final_audio = (try packets.next()).?;
    var output = [_]f32{99} ** 32;
    const outputs = [_][]f32{&output};
    const final_result = try decoder.decode(
        final_audio,
        identification,
        setup,
        &outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), final_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), final_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), final_result.pcm_end);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 32), &output);
    var pcm_seek = VorbisPcmSeekCursor.init(16);
    const selected = try pcm_seek.select(final_result);
    try std.testing.expectEqual(@as(usize, 16), selected.source_start);
    try std.testing.expectEqual(@as(usize, 16), selected.sample_count);
    try std.testing.expectEqual(@as(?i64, 16), selected.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), selected.pcm_end);
    var unavailable_result = final_result;
    unavailable_result.pcm_start = null;
    var unavailable_seek = VorbisPcmSeekCursor.init(16);
    try std.testing.expectError(
        error.VorbisPcmSeekPositionUnavailable,
        unavailable_seek.select(unavailable_result),
    );
    try std.testing.expect(!unavailable_seek.reached);
    var inconsistent_result = final_result;
    inconsistent_result.pcm_end = 31;
    var inconsistent_seek = VorbisPcmSeekCursor.init(16);
    try std.testing.expectError(
        error.InvalidVorbisPcmSeekRange,
        inconsistent_seek.select(inconsistent_result),
    );
    try std.testing.expect(!inconsistent_seek.reached);
    var boundary_seek = VorbisPcmSeekCursor.init(32);
    const boundary = try boundary_seek.select(final_result);
    try std.testing.expectEqual(@as(usize, 32), boundary.source_start);
    try std.testing.expectEqual(@as(usize, 0), boundary.sample_count);
    try std.testing.expect(boundary_seek.reached);
    try std.testing.expect((try packets.next()) == null);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, writer.bytes(), 0);
    try file.setLength(std.testing.io, writer.bytes().len);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisFileSeekPoints(
            std.testing.io,
            file,
            &page_storage,
        ),
    );
    var file_seek_points: [2]VorbisSeekPoint = undefined;
    const file_index = try buildVorbisFileSeekIndex(
        std.testing.io,
        file,
        &page_storage,
        &file_seek_points,
    );
    try std.testing.expectEqualSlices(
        VorbisSeekPoint,
        seek_index,
        file_index,
    );

    var file_packets = try FilePacketReader.init(
        std.testing.io,
        file,
    );
    var invalid_point = file_index[1];
    invalid_point.decode.sequence_number += 1;
    try std.testing.expectError(
        error.InvalidVorbisSeekPoint,
        file_packets.seek(invalid_point),
    );
    try std.testing.expectEqual(@as(u64, 0), file_packets.pages.offset);
    try file_packets.seek(file_index[1]);
    var file_packet_storage: [128]u8 = undefined;
    const seek_prime = (try file_packets.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(
        @as(u64, 3),
        file_packets.logical_stream_packet_index - 1,
    );
    try std.testing.expectEqual(@as(u64, 0), seek_prime.granule_position);
    decoder.reset();
    const seek_prime_result = try decoder.decode(
        seek_prime,
        identification,
        setup,
        &empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        seek_prime_result.sample_count,
    );
    const seek_target = (try file_packets.next(
        &page_storage,
        &file_packet_storage,
    )).?;
    try std.testing.expectEqual(@as(u64, 32), seek_target.granule_position);
    try std.testing.expect(seek_target.end);
    output = [_]f32{99} ** 32;
    const seek_result = try decoder.decode(
        seek_target,
        identification,
        setup,
        &outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &windowed,
        },
    );
    var file_pcm_seek = VorbisPcmSeekCursor.init(16);
    const file_selected = try file_pcm_seek.select(seek_result);
    try std.testing.expectEqualDeep(selected, file_selected);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 16),
        output[file_selected.source_start..][0..file_selected.sample_count],
    );
}

test "Vorbis PCM concealment advances overlap and granules explicitly" {
    const identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var decoder = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    var windowed: [64]f32 = undefined;
    var empty: [0]f32 = .{};
    const empty_outputs = [_][]f32{&empty};
    const primed = try decoder.concealMissingPacket(
        false,
        unknown_granule,
        false,
        identification,
        &empty_outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(usize, 0), primed.sample_count);
    try std.testing.expectEqual(@as(u64, 1), primed.concealed_packet_count);
    try std.testing.expectEqual(@as(u64, 1), decoder.audio_packet_count);

    var output = [_]f32{99} ** 32;
    const outputs = [_][]f32{&output};
    const middle = try decoder.concealMissingPacket(
        false,
        32,
        false,
        identification,
        &outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(u16, 64), middle.block_size);
    try std.testing.expectEqual(@as(usize, 32), middle.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), middle.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), middle.pcm_end);
    try std.testing.expectEqual(@as(u64, 2), middle.concealed_packet_count);
    try std.testing.expectEqualSlices(f32, &([_]f32{0} ** 32), &output);

    output = [_]f32{99} ** 32;
    const ended = try decoder.concealMissingPacket(
        false,
        60,
        true,
        identification,
        &outputs,
        &windowed,
    );
    try std.testing.expectEqual(@as(usize, 28), ended.sample_count);
    try std.testing.expectEqual(@as(?i64, 32), ended.pcm_start);
    try std.testing.expectEqual(@as(?i64, 60), ended.pcm_end);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 28),
        output[0..28],
    );
    try std.testing.expect(decoder.ended);
    try std.testing.expectError(
        error.VorbisPcmStreamAlreadyEnded,
        decoder.concealMissingPacket(
            false,
            92,
            true,
            identification,
            &outputs,
            &windowed,
        ),
    );

    decoder.reset();
    const before_empty_end = decoder;
    try std.testing.expectError(
        error.VorbisStreamEndedBeforePcm,
        decoder.concealMissingPacket(
            false,
            0,
            true,
            identification,
            &empty_outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(before_empty_end, decoder);
    _ = try decoder.concealMissingPacket(
        false,
        unknown_granule,
        false,
        identification,
        &empty_outputs,
        &windowed,
    );
    var aliased = [_]f32{7} ** 64;
    const aliased_outputs = [_][]f32{aliased[0..32]};
    const before_alias = decoder;
    try std.testing.expectError(
        error.OverlappingVorbisPcmStreamScratch,
        decoder.concealMissingPacket(
            false,
            32,
            false,
            identification,
            &aliased_outputs,
            &aliased,
        ),
    );
    try std.testing.expectEqualDeep(before_alias, decoder);
    try std.testing.expectEqualSlices(f32, &([_]f32{7} ** 64), &aliased);

    var hostile = decoder;
    hostile.concealed_packet_count = hostile.audio_packet_count + 1;
    const hostile_before = hostile;
    try std.testing.expectError(
        error.InvalidVorbisPcmStreamState,
        hostile.concealMissingPacket(
            false,
            32,
            false,
            identification,
            &outputs,
            &windowed,
        ),
    );
    try std.testing.expectEqualDeep(hostile_before, hostile);

    var fading = VorbisPcmStreamDecoder(f32, 1, 64, 64).init();
    const retained = [_]f32{1} ** 64;
    _ = try fading.overlap.push(
        &[_][]const f32{&retained},
        &empty_outputs,
    );
    fading.audio_packet_count = 1;
    var faded_output: [32]f32 = undefined;
    const faded_outputs = [_][]f32{&faded_output};
    _ = try fading.concealMissingPacket(
        false,
        32,
        false,
        identification,
        &faded_outputs,
        &windowed,
    );
    var faded_energy: f64 = 0;
    for (faded_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        faded_energy += @as(f64, sample) * sample;
    }
    try std.testing.expect(faded_energy > 0);

    const mixed_identification = VorbisIdentification{
        .channel_count = 1,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 64_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };
    var mixed = VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    var mixed_windowed: [256]f32 = undefined;
    _ = try mixed.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    var mixed_output: [80]f32 = undefined;
    const mixed_outputs = [_][]f32{&mixed_output};
    const mixed_large = try mixed.concealMissingPacket(
        true,
        80,
        false,
        mixed_identification,
        &mixed_outputs,
        &mixed_windowed,
    );
    try std.testing.expectEqual(@as(u16, 256), mixed_large.block_size);
    try std.testing.expectEqual(@as(usize, 80), mixed_large.sample_count);
    const mixed_small = try mixed.concealMissingPacket(
        false,
        160,
        true,
        mixed_identification,
        &mixed_outputs,
        &mixed_windowed,
    );
    try std.testing.expectEqual(@as(u16, 64), mixed_small.block_size);
    try std.testing.expectEqual(@as(usize, 80), mixed_small.sample_count);

    var predicted = VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    const predicted_before = predicted;
    try std.testing.expectError(
        error.VorbisPreviousBlockSizeUnavailable,
        predicted.concealMissingPacketUsingPreviousBlockSize(
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(predicted_before, predicted);
    _ = try predicted.concealMissingPacket(
        true,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    var predicted_output: [128]f32 = undefined;
    const predicted_outputs = [_][]f32{&predicted_output};
    const predicted_loss =
        try predicted.concealMissingPacketUsingPreviousBlockSize(
            128,
            false,
            mixed_identification,
            &predicted_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 256), predicted_loss.block_size);
    try std.testing.expectEqual(@as(usize, 128), predicted_loss.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 128),
        &predicted_output,
    );

    predicted.reset();
    _ = try predicted.concealMissingPacket(
        false,
        unknown_granule,
        false,
        mixed_identification,
        &empty_outputs,
        &mixed_windowed,
    );
    predicted_output = [_]f32{99} ** 128;
    const predicted_small =
        try predicted.concealMissingPacketUsingPreviousBlockSize(
            32,
            false,
            mixed_identification,
            &predicted_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 64), predicted_small.block_size);
    try std.testing.expectEqual(@as(usize, 32), predicted_small.sample_count);
    try std.testing.expectEqualSlices(
        f32,
        &([_]f32{0} ** 32),
        predicted_output[0..32],
    );

    const following_large = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expect(
        !try inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_large,
        ),
    );
    var following_previous_large = following_large;
    following_previous_large.previous_window_flag = true;
    try std.testing.expect(
        try inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_previous_large,
        ),
    );
    const following_small = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 2,
    };
    try std.testing.expectError(
        error.VorbisFollowingPacketBlockSizeUnavailable,
        inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            following_small,
        ),
    );
    var malformed_following = following_large;
    malformed_following.previous_window_flag = null;
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketHeader,
        inferVorbisMissingPacketLargeBlock(
            mixed_identification,
            malformed_following,
        ),
    );

    var following_decoder =
        VorbisPcmStreamDecoder(f32, 1, 64, 256).init();
    const following_before = following_decoder;
    try std.testing.expectError(
        error.VorbisFollowingPacketBlockSizeUnavailable,
        following_decoder.concealMissingPacketUsingFollowingHeader(
            following_small,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(following_before, following_decoder);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketHeader,
        following_decoder.concealMissingPacketUsingFollowingHeader(
            malformed_following,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        ),
    );
    try std.testing.expectEqualDeep(following_before, following_decoder);
    const following_loss =
        try following_decoder.concealMissingPacketUsingFollowingHeader(
            following_large,
            unknown_granule,
            false,
            mixed_identification,
            &empty_outputs,
            &mixed_windowed,
        );
    try std.testing.expectEqual(@as(u16, 64), following_loss.block_size);
    try std.testing.expectEqual(@as(usize, 0), following_loss.sample_count);
}

test "Vorbis seeking handles packed packets and chained streams" {
    var packed_encoded: [512]u8 = undefined;
    var packed_writer = StreamWriter.init(&packed_encoded, 0x1020_3040);
    try packed_writer.appendPacket("header 1", 0, true, false);
    try packed_writer.appendPacket("header 2", 0, false, false);
    try packed_writer.appendPacket("header 3", 0, false, false);
    packed_writer.byte_count = try appendTestOggPage(
        &packed_encoded,
        packed_writer.byte_count,
        packed_writer.serial_number,
        packed_writer.sequence_number,
        0x04,
        32,
        &.{ 1, 1, 1 },
        &.{ 0x11, 0x22, 0x33 },
    );
    var packed_points: [1]VorbisSeekPoint = undefined;
    const packed_index = try buildVorbisSeekIndex(
        packed_writer.bytes(),
        &packed_points,
    );
    try std.testing.expectEqual(@as(usize, 1), packed_index.len);
    try std.testing.expectEqual(
        @as(u64, 3),
        packed_index[0].decode.logical_packet_index,
    );
    try std.testing.expectEqual(
        @as(u16, 0),
        packed_index[0].decode.completed_packets_before,
    );
    try std.testing.expectEqual(
        @as(u64, 5),
        packed_index[0].packet.logical_packet_index,
    );
    try std.testing.expectEqual(
        @as(u16, 2),
        packed_index[0].packet.completed_packets_before,
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packed-seek.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        packed_writer.bytes(),
        0,
    );
    try file.setLength(std.testing.io, packed_writer.bytes().len);
    var packets = try FilePacketReader.init(std.testing.io, file);
    try packets.seek(packed_index[0]);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [8]u8 = undefined;
    const prime = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x11}, prime.bytes);
    try std.testing.expectEqual(
        unknown_granule,
        prime.granule_position,
    );
    const middle = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x22}, middle.bytes);
    try std.testing.expectEqual(
        unknown_granule,
        middle.granule_position,
    );
    const target = (try packets.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expectEqualSlices(u8, &.{0x33}, target.bytes);
    try std.testing.expectEqual(@as(u64, 32), target.granule_position);
    try std.testing.expect(target.end);

    var chained_encoded: [1024]u8 = undefined;
    var first_writer = StreamWriter.init(&chained_encoded, 0x1111_1111);
    try first_writer.appendPacket("header 1", 0, true, false);
    try first_writer.appendPacket("header 2", 0, false, false);
    try first_writer.appendPacket("header 3", 0, false, false);
    try first_writer.appendPacket("audio", 8, false, true);
    var second_writer = StreamWriter.init(
        chained_encoded[first_writer.byte_count..],
        0x2222_2222,
    );
    try second_writer.appendPacket("header 1", 0, true, false);
    try second_writer.appendPacket("header 2", 0, false, false);
    try second_writer.appendPacket("header 3", 0, false, false);
    try second_writer.appendPacket("audio", 16, false, true);
    const chained_bytes = chained_encoded[0 .. first_writer.byte_count + second_writer.byte_count];
    var chained_points: [2]VorbisSeekPoint = undefined;
    const chained_index = try buildVorbisSeekIndex(
        chained_bytes,
        &chained_points,
    );
    try std.testing.expectEqual(@as(usize, 2), chained_index.len);
    try std.testing.expectEqual(
        @as(u32, 1),
        chained_index[1].packet.logical_stream_index,
    );
    try std.testing.expectEqualDeep(
        chained_index[1],
        try findVorbisSeekPoint(chained_index, 1, 4),
    );
}

test "Vorbis comments validate UTF-8 fields and framing" {
    var packet: [64]u8 = @splat(0);
    packet[0] = 3;
    @memcpy(packet[1..7], "vorbis");
    std.mem.writeInt(u32, packet[7..11], 6, .little);
    @memcpy(packet[11..17], "vendor");
    std.mem.writeInt(u32, packet[17..21], 1, .little);
    std.mem.writeInt(u32, packet[21..25], 10, .little);
    @memcpy(packet[25..35], "TITLE=Song");
    packet[35] = 1;
    var comments = try VorbisCommentIterator.init(packet[0..36]);
    try std.testing.expectEqualStrings("vendor", comments.vendor);
    const title = (try comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", title.name);
    try std.testing.expectEqualStrings("Song", title.value);
    try std.testing.expect((try comments.next()) == null);
    packet[35] = 0;
    try std.testing.expectError(
        error.InvalidVorbisCommentHeader,
        VorbisCommentIterator.init(packet[0..36]),
    );
}

test "Vorbis comment encoding preserves fields and caller storage" {
    const comments = [_]VorbisComment{
        .{ .name = "TITLE", .value = "Night Drive" },
        .{ .name = "ARTIST", .value = "Miyuki \xe7\xbe\x8e\xe9\x9b\xaa" },
        .{ .name = "DESCRIPTION", .value = "" },
    };
    const required = try requiredVorbisCommentPacketBytes(
        "zig-vst3",
        &comments,
    );
    var destination: [128]u8 = @splat(0xaa);
    const encoded = try encodeVorbisCommentPacket(
        &destination,
        "zig-vst3",
        &comments,
    );
    try std.testing.expectEqual(required, encoded.len);
    var iterator = try VorbisCommentIterator.init(encoded);
    try std.testing.expectEqualStrings("zig-vst3", iterator.vendor);
    for (comments) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expect((try iterator.next()) == null);

    const before = destination;
    try std.testing.expectError(
        error.VorbisCommentOutputTooSmall,
        encodeVorbisCommentPacket(
            destination[0 .. required - 1],
            "zig-vst3",
            &comments,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
    const invalid = [_]VorbisComment{
        .{ .name = "BAD=NAME", .value = "value" },
    };
    try std.testing.expectError(
        error.InvalidVorbisCommentField,
        encodeVorbisCommentPacket(
            &destination,
            "zig-vst3",
            &invalid,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
}

test "Vorbis comment encoding rejects overlapping borrowed fields" {
    var destination: [64]u8 = @splat(0xaa);
    @memcpy(destination[20..26], "vendor");
    const before = destination;
    try std.testing.expectError(
        error.OverlappingVorbisCommentStorage,
        encodeVorbisCommentPacket(
            &destination,
            destination[20..26],
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &destination);
}

test "encoded Vorbis headers traverse Ogg and parse together" {
    const expected_identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = -1,
        .bitrate_nominal = 192_000,
        .bitrate_minimum = -1,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var identification_storage: [30]u8 = undefined;
    const identification = try encodeVorbisIdentificationPacket(
        &identification_storage,
        expected_identification,
    );
    const expected_comments = [_]VorbisComment{
        .{ .name = "TITLE", .value = "Header integration" },
    };
    var comment_storage: [64]u8 = undefined;
    const comments = try encodeVorbisCommentPacket(
        &comment_storage,
        "zig-vst3",
        &expected_comments,
    );
    var setup_storage: [128]u8 = undefined;
    const setup = makeTestVorbisSetup(
        &setup_storage,
        .unordered,
        false,
        false,
    );

    var ogg_storage: [512]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x564f_5242);
    try writer.appendPacket(identification, 0, true, false);
    try writer.appendPacket(comments, 0, false, false);
    try writer.appendPacket(setup.bytes, 0, false, true);

    var packet_storage: [128]u8 = undefined;
    var packets = PacketIterator.init(
        writer.bytes(),
        &packet_storage,
    );
    const decoded_identification = (try packets.next()).?;
    var decoded_identification_storage: [30]u8 = undefined;
    @memcpy(
        &decoded_identification_storage,
        decoded_identification.bytes,
    );
    try std.testing.expectEqualDeep(
        expected_identification,
        try VorbisIdentification.parse(
            &decoded_identification_storage,
        ),
    );
    const decoded_comments = (try packets.next()).?;
    var decoded_comment_storage: [64]u8 = undefined;
    @memcpy(
        decoded_comment_storage[0..decoded_comments.bytes.len],
        decoded_comments.bytes,
    );
    const decoded_comment_bytes =
        decoded_comment_storage[0..decoded_comments.bytes.len];
    var decoded_comment_iterator =
        try VorbisCommentIterator.init(decoded_comment_bytes);
    try std.testing.expectEqualStrings(
        "zig-vst3",
        decoded_comment_iterator.vendor,
    );
    const decoded_title = (try decoded_comment_iterator.next()).?;
    try std.testing.expectEqualStrings(
        "Header integration",
        decoded_title.value,
    );
    const decoded_setup = (try packets.next()).?;
    var decoded_setup_storage: [128]u8 = undefined;
    @memcpy(
        decoded_setup_storage[0..decoded_setup.bytes.len],
        decoded_setup.bytes,
    );
    const decoded_setup_bytes =
        decoded_setup_storage[0..decoded_setup.bytes.len];
    const parsed = try VorbisHeaders.parse(
        &decoded_identification_storage,
        decoded_comment_bytes,
        decoded_setup_bytes,
    );
    try std.testing.expectEqualDeep(
        expected_identification,
        parsed.identification,
    );
    try std.testing.expect((try packets.next()) == null);
}

test "Vorbis setup validates codebook encodings and codec configuration" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebook_storage: [1]VorbisCodebook = undefined;
        var entry_storage: [4]VorbisCodebookEntry = undefined;
        var node_storage: [3]VorbisHuffmanNode = undefined;
        var multiplicand_storage: [4]u32 = undefined;
        var floor_storage: [1]VorbisFloor = undefined;
        var residue_storage: [1]VorbisResidue = undefined;
        var mapping_storage: [1]VorbisMapping = undefined;
        var mode_storage: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebook_storage,
            .codebook_entries = &entry_storage,
            .huffman_nodes = &node_storage,
            .codebook_multiplicands = &multiplicand_storage,
            .floors = &floor_storage,
            .residues = &residue_storage,
            .mappings = &mapping_storage,
            .modes = &mode_storage,
        });
        try std.testing.expectEqual(@as(u16, 1), setup.summary.codebook_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.floor_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.residue_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.mapping_count);
        try std.testing.expectEqual(@as(u8, 1), setup.summary.mode_count);
        try std.testing.expectEqual(@as(u16, 1), setup.codebooks[0].dimensions);
        try std.testing.expectEqual(@as(u2, 1), setup.codebooks[0].lookup_type);
        try std.testing.expect(setup.modes[0].large_block);
        try std.testing.expectEqual(
            VorbisResidueKind.zero,
            setup.residues[0].kind,
        );
        try std.testing.expectEqual(@as(u25, 1), setup.residues[0].partition_size);
        try std.testing.expectEqual(@as(u7, 1), setup.residues[0].classification_count);
        try std.testing.expectEqual(@as(u8, 1), setup.residues[0].cascades[0]);
        try std.testing.expectEqual(@as(i16, 0), setup.residues[0].books[0][0]);
        try std.testing.expectEqual(@as(u5, 2), setup.mappings[0].submap_count);
        try std.testing.expectEqual(@as(u9, 1), setup.mappings[0].coupling_step_count);
        try std.testing.expectEqual(
            VorbisCouplingStep{ .magnitude = 0, .angle = 1 },
            setup.mappings[0].coupling_steps[0],
        );
        try std.testing.expectEqual(@as(u4, 0), setup.mappings[0].channel_mux[0]);
        try std.testing.expectEqual(@as(u4, 1), setup.mappings[0].channel_mux[1]);
        try std.testing.expectEqual(
            VorbisSubmap{ .floor = 0, .residue = 0 },
            setup.mappings[0].submaps[1],
        );
        const deep = encoding == .unordered_deep or encoding == .ordered_gap;
        try std.testing.expectEqual(
            @as(u64, if (deep) 4 else 2),
            setup.summary.codebook_entry_count,
        );
        var scalar_reader = try VorbisPacketReader.init(
            if (encoding == .sparse)
                &.{1}
            else if (deep)
                &.{0b11011000}
            else
                &.{0b00000010},
            0,
        );
        const decoded_count: usize = if (encoding == .sparse)
            1
        else if (deep)
            4
        else
            2;
        try std.testing.expectEqual(
            @as(u64, if (encoding == .sparse) 0 else decoded_count - 1),
            setup.summary.huffman_node_count,
        );
        for (0..decoded_count) |expected| {
            try std.testing.expectEqual(
                @as(u32, @intCast(expected)),
                try scalar_reader.decodeScalar(setup, 0),
            );
        }
        var vector_reader = try VorbisPacketReader.init(
            if (encoding == .sparse)
                &.{1}
            else if (deep)
                &.{0b11011000}
            else
                &.{0b00000010},
            0,
        );
        for (0..decoded_count) |expected| {
            var vector: [1]f64 = undefined;
            try vector_reader.decodeVector(f64, setup, 0, &vector);
            try std.testing.expectEqual(
                @as(f64, @floatFromInt(expected)),
                vector[0],
            );
        }
        try std.testing.expectEqual(
            @as(u32, @intCast(decoded_count)),
            setup.codebooks[0].active_entry_count,
        );
        switch (setup.floors[0]) {
            .one => |floor| {
                try std.testing.expectEqual(
                    @as(u5, 1),
                    floor.partition_count,
                );
                try std.testing.expectEqual(
                    @as(u7, 3),
                    floor.point_count,
                );
            },
            .zero => return error.TestExpectedFloorOne,
        }
    }

    var floor_zero_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );
    switch (floor_zero_setup.floors[0]) {
        .zero => |floor| {
            try std.testing.expectEqual(@as(u8, 1), floor.order);
            try std.testing.expectEqual(@as(u16, 48_000), floor.rate);
            try std.testing.expectEqual(@as(u16, 64), floor.bark_map_size);
            try std.testing.expectEqual(@as(u6, 8), floor.amplitude_bits);
            try std.testing.expectEqual(@as(u8, 60), floor.amplitude_offset);
            try std.testing.expectEqual(@as(u5, 1), floor.book_count);
            try std.testing.expectEqual(@as(u8, 0), floor.books[0]);
        },
        .one => return error.TestExpectedFloorZero,
    }
}

test "Vorbis setup encoding canonicalizes and round trips retained setup" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebooks: [1]VorbisCodebook = undefined;
        var entries: [4]VorbisCodebookEntry = undefined;
        var nodes: [3]VorbisHuffmanNode = undefined;
        var multiplicands: [4]u32 = undefined;
        var floors: [1]VorbisFloor = undefined;
        var residues: [1]VorbisResidue = undefined;
        var mappings: [1]VorbisMapping = undefined;
        var modes: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        });
        if (encoding == .ordered) {
            codebooks[0].lookup_type = 2;
            codebooks[0].minimum_value = -1;
            codebooks[0].delta_value = 0.5;
            multiplicands[0] = 65535;
        }

        var encoded_storage: [256]u8 = undefined;
        @memset(&encoded_storage, 0xa5);
        const required = try requiredVorbisSetupPacketBytes(setup, 2);
        const encoded = try encodeVorbisSetupPacket(
            &encoded_storage,
            setup,
            2,
        );
        try std.testing.expectEqual(required, encoded.len);

        var decoded_codebooks: [1]VorbisCodebook = undefined;
        var decoded_entries: [4]VorbisCodebookEntry = undefined;
        var decoded_nodes: [3]VorbisHuffmanNode = undefined;
        var decoded_multiplicands: [4]u32 = undefined;
        var decoded_floors: [1]VorbisFloor = undefined;
        var decoded_residues: [1]VorbisResidue = undefined;
        var decoded_mappings: [1]VorbisMapping = undefined;
        var decoded_modes: [1]VorbisMode = undefined;
        const decoded = try parseVorbisSetup(encoded, 2, .{
            .codebooks = &decoded_codebooks,
            .codebook_entries = &decoded_entries,
            .huffman_nodes = &decoded_nodes,
            .codebook_multiplicands = &decoded_multiplicands,
            .floors = &decoded_floors,
            .residues = &decoded_residues,
            .mappings = &decoded_mappings,
            .modes = &decoded_modes,
        });
        try std.testing.expectEqualDeep(setup.summary, decoded.summary);
        try std.testing.expectEqualDeep(
            setup.codebooks,
            decoded.codebooks,
        );
        try std.testing.expectEqualDeep(
            setup.codebook_entries,
            decoded.codebook_entries,
        );
        try std.testing.expectEqualDeep(
            setup.codebook_multiplicands,
            decoded.codebook_multiplicands,
        );
        try std.testing.expectEqualDeep(setup.floors, decoded.floors);
        try std.testing.expectEqualDeep(setup.residues, decoded.residues);
        try std.testing.expectEqualDeep(setup.mappings, decoded.mappings);
        try std.testing.expectEqualDeep(setup.modes, decoded.modes);
    }

    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        false,
        true,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 1, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    var encoded_storage: [256]u8 = undefined;
    const encoded = try encodeVorbisSetupPacket(
        &encoded_storage,
        setup,
        1,
    );
    const summary = try validateVorbisSetup(encoded, 1);
    try std.testing.expectEqualDeep(setup.summary, summary);
}

test "Vorbis setup encoding validates before destination mutation" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    const required = try requiredVorbisSetupPacketBytes(setup, 2);

    var destination: [256]u8 = undefined;
    @memset(&destination, 0xa5);
    try std.testing.expectError(
        error.VorbisSetupOutputTooSmall,
        encodeVorbisSetupPacket(
            destination[0 .. required - 1],
            setup,
            2,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );

    var invalid = setup;
    invalid.summary.mode_count = 2;
    try std.testing.expectError(
        error.InconsistentVorbisSetupSummary,
        encodeVorbisSetupPacket(&destination, invalid, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );

    codebooks[0].minimum_value = 0.1;
    try std.testing.expectError(
        error.UnrepresentableVorbisCodebookFloat,
        encodeVorbisSetupPacket(&destination, setup, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );
    codebooks[0].minimum_value = 0;
    multiplicands[0] = 65536;
    try std.testing.expectError(
        error.VorbisCodebookMultiplicandTooLarge,
        encodeVorbisSetupPacket(&destination, setup, 2),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 256),
        &destination,
    );
    multiplicands[0] = 0;

    var overlapping: [256]u8 align(@alignOf(VorbisCodebook)) =
        [_]u8{0xa5} ** 256;
    const overlapping_codebooks = std.mem.bytesAsSlice(
        VorbisCodebook,
        overlapping[0..@sizeOf(VorbisCodebook)],
    );
    overlapping_codebooks[0] = setup.codebooks[0];
    var overlapping_setup = setup;
    overlapping_setup.codebooks = overlapping_codebooks;
    const before = overlapping;
    try std.testing.expectError(
        error.OverlappingVorbisSetupStorage,
        encodeVorbisSetupPacket(
            &overlapping,
            overlapping_setup,
            2,
        ),
    );
    try std.testing.expectEqualSlices(u8, &before, &overlapping);
}

test "Vorbis setup rejects malformed structure transactionally" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        false,
        false,
    );
    var codebook_sentinel = [_]VorbisCodebook{.{
        .dimensions = 99,
        .entries = 99,
        .entry_offset = 99,
        .active_entry_count = 99,
        .lookup_type = 2,
    }};
    var entry_sentinel = [_]VorbisCodebookEntry{.{
        .codeword = 99,
        .length = 99,
    }};
    var multiplicand_sentinel = [_]u32{99};
    var node_sentinel = [_]VorbisHuffmanNode{.{
        .branches = .{ 99, 99 },
    }};
    var floor_sentinel = [_]VorbisFloor{.{
        .zero = .{
            .order = 99,
            .rate = 99,
            .bark_map_size = 99,
            .amplitude_bits = 1,
            .amplitude_offset = 99,
            .book_count = 1,
            .books = [_]u8{99} ** 16,
        },
    }};
    var residue_sentinel = [_]VorbisResidue{.{
        .kind = .two,
        .begin = 99,
        .end = 99,
        .partition_size = 99,
        .classification_count = 1,
        .classbook = 99,
        .cascades = [_]u8{99} ** 64,
        .books = [_][8]i16{[_]i16{99} ** 8} ** 64,
    }};
    var mapping_sentinel: [1]VorbisMapping = undefined;
    var mode_sentinel = [_]VorbisMode{.{
        .large_block = true,
        .mapping = 99,
    }};
    try std.testing.expectError(
        error.VorbisSetupStorageTooSmall,
        parseVorbisSetup(packet.bytes, 1, .{
            .codebooks = codebook_sentinel[0..0],
            .codebook_entries = &entry_sentinel,
            .huffman_nodes = &node_sentinel,
            .codebook_multiplicands = &multiplicand_sentinel,
            .floors = &floor_sentinel,
            .residues = &residue_sentinel,
            .mappings = &mapping_sentinel,
            .modes = &mode_sentinel,
        }),
    );
    try std.testing.expectEqual(
        @as(u16, 99),
        codebook_sentinel[0].dimensions,
    );
    try std.testing.expectEqual(@as(u8, 99), mode_sentinel[0].mapping);
    try std.testing.expectEqual(@as(u8, 99), entry_sentinel[0].length);
    try std.testing.expectEqual(@as(u32, 99), multiplicand_sentinel[0]);
    try std.testing.expectEqual(@as(u32, 99), node_sentinel[0].branches[0]);
    switch (floor_sentinel[0]) {
        .zero => |floor| try std.testing.expectEqual(@as(u8, 99), floor.order),
        .one => return error.TestExpectedFloorZero,
    }

    var malformed = packet_storage;
    malformed[8] = 0;
    try std.testing.expectError(
        error.InvalidVorbisCodebookSync,
        validateVorbisSetup(malformed[0..packet.bytes.len], 1),
    );
    try std.testing.expectError(
        error.TruncatedVorbisSetup,
        validateVorbisSetup(packet.bytes[0 .. packet.bytes.len - 1], 1),
    );

    var bad_framing = packet_storage;
    flipTestBit(&bad_framing, packet.framing_bit);
    try std.testing.expectError(
        error.InvalidVorbisSetupFraming,
        validateVorbisSetup(bad_framing[0..packet.bytes.len], 1),
    );

    var bad_tree = packet_storage;
    flipTestBit(&bad_tree, 130);
    try std.testing.expectError(
        error.InvalidVorbisCodebookLengths,
        validateVorbisSetup(bad_tree[0..packet.bytes.len], 1),
    );

    var bad_mapping = packet_storage;
    flipTestBit(&bad_mapping, packet.mapping_reserved_bit);
    try std.testing.expectError(
        error.InvalidVorbisMappingReservedBits,
        validateVorbisSetup(bad_mapping[0..packet.bytes.len], 1),
    );

    var rich_storage: [128]u8 = undefined;
    const rich_packet = makeTestVorbisSetup(
        &rich_storage,
        .unordered,
        true,
        false,
    );
    flipTestBit(&rich_storage, rich_packet.floor_point_bit.?);
    try std.testing.expectError(
        error.DuplicateVorbisFloorPoint,
        validateVorbisSetup(
            rich_storage[0..rich_packet.bytes.len],
            2,
        ),
    );
}

test "Vorbis codewords follow entry order across mixed lengths" {
    var entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 0, .length = 2 },
    };

    assignVorbisCodewords(&entries);

    try std.testing.expectEqual(@as(u32, 0b00), entries[0].codeword);
    try std.testing.expectEqual(@as(u32, 0b1), entries[1].codeword);
    try std.testing.expectEqual(@as(u32, 0b01), entries[2].codeword);
}

test "Vorbis packet writer round trips headers and canonical codewords" {
    for (std.enums.values(TestVorbisCodebookEncoding)) |encoding| {
        var packet_storage: [128]u8 = undefined;
        const packet = makeTestVorbisSetup(
            &packet_storage,
            encoding,
            true,
            false,
        );
        var codebooks: [1]VorbisCodebook = undefined;
        var entries: [4]VorbisCodebookEntry = undefined;
        var nodes: [3]VorbisHuffmanNode = undefined;
        var multiplicands: [4]u32 = undefined;
        var floors: [1]VorbisFloor = undefined;
        var residues: [1]VorbisResidue = undefined;
        var mappings: [1]VorbisMapping = undefined;
        var modes: [1]VorbisMode = undefined;
        const setup = try parseVorbisSetup(packet.bytes, 2, .{
            .codebooks = &codebooks,
            .codebook_entries = &entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        });
        const identification = VorbisIdentification{
            .channel_count = 2,
            .sample_rate = 48_000,
            .bitrate_maximum = 0,
            .bitrate_nominal = 0,
            .bitrate_minimum = 0,
            .small_block_size = 64,
            .large_block_size = 128,
        };

        var output: [32]u8 = undefined;
        var writer = VorbisPacketWriter.init(&output);
        const header = try writer.writeAudioHeader(
            identification,
            setup,
            0,
            false,
            true,
        );
        const decoded_count: usize = if (encoding == .sparse)
            1
        else if (encoding == .unordered_deep or
            encoding == .ordered_gap)
            4
        else
            2;
        for (0..decoded_count) |entry|
            try writer.writeVectorEntry(setup, 0, @intCast(entry));

        const parsed_header = try parseVorbisAudioPacketHeader(
            writer.bytes(),
            identification,
            setup,
        );
        try std.testing.expectEqualDeep(header, parsed_header);
        var reader = try VorbisPacketReader.init(
            writer.bytes(),
            parsed_header.payload_bit_offset,
        );
        for (0..decoded_count) |entry| {
            try std.testing.expectEqual(
                @as(u32, @intCast(entry)),
                try reader.decodeScalar(setup, 0),
            );
        }
        try std.testing.expectEqual(writer.bit_offset, reader.bit_offset);

        const before = output;
        const before_offset = writer.bit_offset;
        try std.testing.expectError(
            error.VorbisPacketValueDoesNotFit,
            writer.writeBits(2, 1),
        );
        try std.testing.expectEqual(before_offset, writer.bit_offset);
        try std.testing.expectEqualSlices(
            u8,
            before[0..writer.bytes().len],
            writer.bytes(),
        );
        if (encoding == .sparse) {
            try std.testing.expectError(
                error.InvalidVorbisCodebookEntry,
                writer.writeScalar(setup, 0, 1),
            );
            try std.testing.expectEqual(before_offset, writer.bit_offset);
        }
    }

    var no_storage: [0]u8 = .{};
    var full = VorbisPacketWriter.init(&no_storage);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        full.writeBits(1, 1),
    );
    try std.testing.expectEqual(@as(usize, 0), full.bit_offset);
}

test "Vorbis packet writer round trips both floor packet formats" {
    var floor_one_storage: [128]u8 = undefined;
    const floor_one_packet = makeTestVorbisSetup(
        &floor_one_storage,
        .unordered,
        true,
        false,
    );
    var floor_one_codebooks: [1]VorbisCodebook = undefined;
    var floor_one_entries: [2]VorbisCodebookEntry = undefined;
    var floor_one_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_one_multiplicands: [2]u32 = undefined;
    var floor_one_floors: [1]VorbisFloor = undefined;
    var floor_one_residues: [1]VorbisResidue = undefined;
    var floor_one_mappings: [1]VorbisMapping = undefined;
    var floor_one_modes: [1]VorbisMode = undefined;
    const floor_one_setup = try parseVorbisSetup(
        floor_one_packet.bytes,
        2,
        .{
            .codebooks = &floor_one_codebooks,
            .codebook_entries = &floor_one_entries,
            .huffman_nodes = &floor_one_nodes,
            .codebook_multiplicands = &floor_one_multiplicands,
            .floors = &floor_one_floors,
            .residues = &floor_one_residues,
            .mappings = &floor_one_mappings,
            .modes = &floor_one_modes,
        },
    );
    var encoded_floor_one: [16]u8 = undefined;
    var floor_one_writer =
        VorbisPacketWriter.init(&encoded_floor_one);
    try floor_one_writer.writeFloorOne(
        floor_one_setup,
        0,
        .{
            .used = true,
            .y_values = &.{ 12, 34, 1 },
        },
    );
    var floor_one_reader = try VorbisPacketReader.init(
        floor_one_writer.bytes(),
        0,
    );
    var y_values: [65]u32 = undefined;
    const floor_one_decoded = try floor_one_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(floor_one_decoded.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 12, 34, 1 },
        y_values[0..floor_one_decoded.value_count],
    );
    try std.testing.expectEqual(
        floor_one_writer.bit_offset,
        floor_one_reader.bit_offset,
    );

    var unused_floor_one: [1]u8 = undefined;
    var unused_writer =
        VorbisPacketWriter.init(&unused_floor_one);
    try unused_writer.writeFloorOne(
        floor_one_setup,
        0,
        .{},
    );
    var unused_reader = try VorbisPacketReader.init(
        unused_writer.bytes(),
        0,
    );
    const unused = try unused_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(!unused.used);

    var too_small: [1]u8 = undefined;
    var small_writer = VorbisPacketWriter.init(&too_small);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        small_writer.writeFloorOne(
            floor_one_setup,
            0,
            .{
                .used = true,
                .y_values = &.{ 12, 34, 1 },
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), small_writer.bit_offset);
    try std.testing.expectEqual(@as(u8, 0), too_small[0]);

    var floor_zero_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );
    var encoded_floor_zero: [16]u8 = undefined;
    var floor_zero_writer =
        VorbisPacketWriter.init(&encoded_floor_zero);
    try floor_zero_writer.writeFloorZero(
        floor_zero_setup,
        0,
        .{
            .amplitude = 5,
            .entries = &.{1},
        },
    );
    var floor_zero_reader = try VorbisPacketReader.init(
        floor_zero_writer.bytes(),
        0,
    );
    var coefficients: [1]f64 = undefined;
    const floor_zero_decoded = try floor_zero_reader.decodeFloorZero(
        floor_zero_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(floor_zero_decoded.used);
    try std.testing.expectEqual(
        @as(u64, 5),
        floor_zero_decoded.amplitude,
    );
    try std.testing.expectEqual(@as(f64, 1), coefficients[0]);
    try std.testing.expectEqual(
        floor_zero_writer.bit_offset,
        floor_zero_reader.bit_offset,
    );
}

test "Vorbis Floor 1 fitting round trips packet values and residue" {
    try testVorbisFloorOneFitting(f32);
    try testVorbisFloorOneFitting(f64);
}

fn testVorbisFloorOneFitting(comptime Float: type) !void {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    const floor = switch (setup.floors[0]) {
        .one => |value| value,
        .zero => return error.TestExpectedFloorOne,
    };

    var target =
        [_]Float{vorbisFloorOneInverseDb(Float, 100)} ** 4;
    target[floor.x_list[2]] =
        vorbisFloorOneInverseDb(Float, 99);
    var fitted_y = [_]u32{ 91, 92, 93, 94 };
    const fitted = try fitVorbisFloorOne(
        Float,
        setup,
        0,
        &target,
        &fitted_y,
    );
    try std.testing.expect(fitted.encoding.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 100, 100, 1 },
        fitted.encoding.y_values,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        fitted.squared_control_point_error,
    );
    try std.testing.expectEqual(@as(u32, 94), fitted_y[3]);

    var encoded: [16]u8 = undefined;
    var writer = VorbisPacketWriter.init(&encoded);
    try writer.writeFloorOne(setup, 0, fitted.encoding);
    var reader = try VorbisPacketReader.init(writer.bytes(), 0);
    var decoded_y: [65]u32 = undefined;
    const decoded = try reader.decodeFloorOne(
        setup,
        0,
        &decoded_y,
    );
    try std.testing.expect(decoded.used);
    try std.testing.expectEqualSlices(
        u32,
        fitted.encoding.y_values,
        decoded_y[0..decoded.value_count],
    );

    var floor_curve: [4]Float = undefined;
    try synthesizeVorbisFloorOne(
        Float,
        floor,
        decoded,
        &decoded_y,
        &floor_curve,
    );
    const residue_values = [_]Float{ 1, -2, 3, -4 };
    var spectrum: [4]Float = undefined;
    for (&spectrum, floor_curve, residue_values) |
        *destination,
        floor_value,
        residue_value,
    | {
        destination.* = floor_value * residue_value;
    }
    var normalized = [_]Float{ 99, 99, 99, 99 };
    try normalizeVorbisResidue(
        Float,
        &spectrum,
        &floor_curve,
        &normalized,
    );
    for (normalized, residue_values) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            @as(Float, 16) * std.math.floatEps(Float),
        );
    }
    try applyVorbisFloor(Float, &normalized, &floor_curve);
    for (normalized, spectrum) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            @as(Float, 16) * std.math.floatEps(Float),
        );
    }

    var silent_destination = [_]u32{ 81, 82, 83 };
    const silent = try fitVorbisFloorOne(
        Float,
        setup,
        0,
        &([_]Float{0} ** 4),
        &silent_destination,
    );
    try std.testing.expect(!silent.encoding.used);
    try std.testing.expectEqual(@as(usize, 0), silent.encoding.y_values.len);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 81, 82, 83 },
        &silent_destination,
    );

    var preserved = [_]u32{ 71, 72, 73 };
    try std.testing.expectError(
        error.VorbisFloorOutputTooSmall,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            &target,
            preserved[0..2],
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );
    var invalid_target = target;
    invalid_target[1] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            &invalid_target,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        fitVorbisFloorOne(
            Float,
            setup,
            0,
            target[0..3],
            &preserved,
        ),
    );

    var unwritable_entries = entries;
    @memset(&unwritable_entries, .{
        .codeword = 0,
        .length = 0,
    });
    var unwritable_setup = setup;
    unwritable_setup.codebook_entries = &unwritable_entries;
    try std.testing.expectError(
        error.UnencodableVorbisFloorValue,
        fitVorbisFloorOne(
            Float,
            unwritable_setup,
            0,
            &target,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 71, 72, 73 },
        &preserved,
    );

    var wrong_floors = floors;
    wrong_floors[0] = .{ .zero = .{
        .order = 1,
        .rate = 48_000,
        .bark_map_size = 1,
        .amplitude_bits = 1,
        .amplitude_offset = 1,
        .book_count = 1,
        .books = [_]u8{0} ** 16,
    } };
    var wrong_setup = setup;
    wrong_setup.floors = &wrong_floors;
    try std.testing.expectError(
        error.InvalidVorbisFloorType,
        fitVorbisFloorOne(
            Float,
            wrong_setup,
            0,
            &target,
            &preserved,
        ),
    );
}

test "Vorbis multichannel Floor 1 analysis publishes atomically" {
    try testVorbisAudioFloorOne(f32);
    try testVorbisAudioFloorOne(f64);
}

fn testVorbisAudioFloorOne(comptime Float: type) !void {
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floor_one = VorbisFloorOne{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    };
    const floors = [_]VorbisFloor{.{ .one = floor_one }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioFloorOneStorageRequirements{
            .encodings = 2,
            .y_values = 4,
            .curve_values = 64,
        },
        try requiredVorbisAudioFloorOneStorage(
            identification,
            setup,
            header,
        ),
    );

    const active_target =
        [_]Float{vorbisFloorOneInverseDb(Float, 100)} ** 32;
    const silent_target = [_]Float{0} ** 32;
    var trial_y: [4]u32 = undefined;
    var trial_curves: [64]Float = undefined;
    var encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        .{ .one = .{} },
        .{ .one = .{
            .used = true,
            .y_values = &.{99},
        } },
    };
    var y_values = [_]u32{ 91, 92, 93, 94, 95 };
    var curves = [_]Float{9} ** 65;
    const plan = try fitVorbisAudioFloorOne(
        Float,
        identification,
        setup,
        header,
        &.{ &active_target, &silent_target },
        .{
            .y_values = &trial_y,
            .curves = &trial_curves,
        },
        .{
            .encodings = &encodings,
            .y_values = &y_values,
            .curves = &curves,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expectEqual(@as(f64, 0), plan.squared_control_point_error);
    try std.testing.expect(plan.encodings[0].one.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{ 100, 100 },
        plan.encodings[0].one.y_values,
    );
    try std.testing.expect(!plan.encodings[1].one.used);
    try std.testing.expectEqual(@as(usize, 0), plan.encodings[1].one.y_values.len);
    for (plan.curves[0..32]) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0);
    }
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.curves[32..64],
    );
    try std.testing.expectEqual(@as(u32, 95), y_values[4]);
    try std.testing.expectEqual(@as(Float, 9), curves[64]);
    try std.testing.expect(encodings[2].one.used);
    try std.testing.expectEqualSlices(
        u32,
        &.{99},
        encodings[2].one.y_values,
    );

    var skips = [_]bool{false} ** 2;
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = 0,
            .floors = plan.encodings,
        },
        &skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, true },
        fixed.do_not_encode,
    );

    const encodings_before = encodings;
    const y_before = y_values;
    const curves_before = curves;
    var invalid_target = silent_target;
    invalid_target[31] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &invalid_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectEqualDeep(encodings_before, encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &y_values);
    try std.testing.expectEqualSlices(Float, &curves_before, &curves);
    try std.testing.expectError(
        error.VorbisAudioFloorScratchTooSmall,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = trial_y[0..3],
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioFloorStorageTooSmall,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = encodings[0..1],
                .y_values = &y_values,
                .curves = &curves,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioFloorStorage,
        fitVorbisAudioFloorOne(
            Float,
            identification,
            setup,
            header,
            &.{ &active_target, &silent_target },
            .{
                .y_values = &trial_y,
                .curves = &trial_curves,
            },
            .{
                .encodings = &encodings,
                .y_values = &trial_y,
                .curves = &curves,
            },
        ),
    );

    const floor_zero = [_]VorbisFloor{.{ .zero = .{
        .order = 1,
        .rate = 48_000,
        .bark_map_size = 32,
        .amplitude_bits = 1,
        .amplitude_offset = 1,
        .book_count = 1,
        .books = [_]u8{0} ** 16,
    } }};
    var floor_zero_setup = setup;
    floor_zero_setup.floors = &floor_zero;
    try std.testing.expectError(
        error.UnsupportedVorbisFloorZeroAnalysis,
        requiredVorbisAudioFloorOneStorage(
            identification,
            floor_zero_setup,
            header,
        ),
    );
    var invalid_header = header;
    invalid_header.block_size = 128;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        requiredVorbisAudioFloorOneStorage(
            identification,
            setup,
            invalid_header,
        ),
    );
}

test "Vorbis residue preparation fits normalizes and couples atomically" {
    try testVorbisAudioResiduePreparation(f32);
    try testVorbisAudioResiduePreparation(f64);
}

fn testVorbisAudioResiduePreparation(comptime Float: type) !void {
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floor_one = VorbisFloorOne{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    };
    const floors = [_]VorbisFloor{.{ .one = floor_one }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioResiduePreparationStorageRequirements{
            .floor_encodings = 2,
            .floor_y_values = 4,
            .floor_curve_values = 64,
            .residue_values = 64,
            .threshold_values = 64,
            .coupling_values = 64,
            .do_not_encode = 2,
        },
        try requiredVorbisAudioResiduePreparationStorage(
            identification,
            setup,
            header,
        ),
    );

    const floor_value =
        vorbisFloorOneInverseDb(Float, 100);
    const active_spectrum = [_]Float{floor_value * 2} ** 32;
    const silent_spectrum = [_]Float{0} ** 32;
    const active_floor = [_]Float{floor_value} ** 32;
    const silent_floor = [_]Float{0} ** 32;
    const active_threshold =
        [_]Float{floor_value * 0.1} ** 32;
    const silent_threshold = [_]Float{0} ** 32;
    var fit_y: [4]u32 = undefined;
    var fit_curves: [64]Float = undefined;
    var trial_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var trial_y: [4]u32 = undefined;
    var trial_curves: [64]Float = undefined;
    var trial_residue: [64]Float = undefined;
    var trial_thresholds: [64]Float = undefined;
    var coupling_values: [64]Float = undefined;
    var coupling_thresholds: [64]Float = undefined;
    var trial_skips: [2]bool = undefined;
    const sentinel_encoding = VorbisFloorPacketEncoding{
        .one = .{
            .used = true,
            .y_values = &.{99},
        },
    };
    var retained_encodings =
        [_]VorbisFloorPacketEncoding{sentinel_encoding} ** 3;
    var retained_y = [_]u32{91} ** 5;
    var retained_curves = [_]Float{92} ** 65;
    var retained_residue = [_]Float{93} ** 65;
    var retained_thresholds = [_]Float{94} ** 65;
    var retained_skips = [_]bool{true} ** 3;
    const plan = try prepareVorbisAudioResidue(
        Float,
        identification,
        setup,
        header,
        &.{ &active_spectrum, &silent_spectrum },
        &.{ &active_floor, &silent_floor },
        &.{ &active_threshold, &silent_threshold },
        .{
            .floor_fit_y_values = &fit_y,
            .floor_fit_curves = &fit_curves,
            .floor_encodings = &trial_encodings,
            .floor_y_values = &trial_y,
            .floor_curves = &trial_curves,
            .residue_values = &trial_residue,
            .noise_thresholds = &trial_thresholds,
            .coupling_values = &coupling_values,
            .coupling_thresholds = &coupling_thresholds,
            .do_not_encode = &trial_skips,
        },
        .{
            .floor_encodings = &retained_encodings,
            .floor_y_values = &retained_y,
            .floor_curves = &retained_curves,
            .residue_values = &retained_residue,
            .noise_thresholds = &retained_thresholds,
            .do_not_encode = &retained_skips,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expect(plan.fixed_packet_bits > 0);
    try std.testing.expectEqual(
        @as(f64, 0),
        plan.squared_control_point_error,
    );
    try std.testing.expect(plan.floor_encodings[0].one.used);
    try std.testing.expect(!plan.floor_encodings[1].one.used);
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        plan.do_not_encode,
    );
    const tolerance =
        @as(Float, 64) * std.math.floatEps(Float);
    for (plan.residue_values, plan.noise_thresholds) |
        residue_value,
        threshold,
    | {
        try std.testing.expectApproxEqAbs(
            @as(Float, 2),
            residue_value,
            tolerance,
        );
        try std.testing.expectApproxEqAbs(
            @as(Float, 0.05),
            threshold,
            tolerance,
        );
    }
    var decoded_left: [32]Float = undefined;
    var decoded_right: [32]Float = undefined;
    @memcpy(&decoded_left, plan.residue_values[0..32]);
    @memcpy(&decoded_right, plan.residue_values[32..64]);
    var inverse_scratch: [64]Float = undefined;
    try inverseCoupleVorbisChannels(
        Float,
        mappings[0],
        &.{ &decoded_left, &decoded_right },
        &inverse_scratch,
    );
    try applyVorbisFloor(
        Float,
        &decoded_left,
        plan.floor_curves[0..32],
    );
    try applyVorbisFloor(
        Float,
        &decoded_right,
        plan.floor_curves[32..64],
    );
    try std.testing.expectEqualSlices(
        Float,
        &active_spectrum,
        &decoded_left,
    );
    try std.testing.expectEqualSlices(
        Float,
        &silent_spectrum,
        &decoded_right,
    );
    try std.testing.expectEqual(@as(u32, 91), retained_y[4]);
    try std.testing.expectEqual(@as(Float, 92), retained_curves[64]);
    try std.testing.expectEqual(@as(Float, 93), retained_residue[64]);
    try std.testing.expectEqual(
        @as(Float, 94),
        retained_thresholds[64],
    );
    try std.testing.expect(retained_skips[2]);
    try std.testing.expectEqual(
        sentinel_encoding,
        retained_encodings[2],
    );

    const encodings_before = retained_encodings;
    const y_before = retained_y;
    const curves_before = retained_curves;
    const residue_before = retained_residue;
    const thresholds_before = retained_thresholds;
    const skips_before = retained_skips;
    var invalid_threshold = active_threshold;
    invalid_threshold[31] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &invalid_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectEqualDeep(
        encodings_before,
        retained_encodings,
    );
    try std.testing.expectEqualSlices(u32, &y_before, &retained_y);
    try std.testing.expectEqualSlices(
        Float,
        &curves_before,
        &retained_curves,
    );
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
    try std.testing.expectEqualSlices(
        Float,
        &thresholds_before,
        &retained_thresholds,
    );
    try std.testing.expectEqualSlices(
        bool,
        &skips_before,
        &retained_skips,
    );

    try std.testing.expectError(
        error.VorbisAudioResiduePreparationScratchTooSmall,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = fit_y[0..3],
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioResiduePreparationStorageTooSmall,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = retained_encodings[0..1],
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioResiduePreparationStorage,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &trial_residue,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    var invalid_header = header;
    invalid_header.payload_bit_offset = 2;
    try std.testing.expectError(
        error.InvalidVorbisPacketBitOffset,
        prepareVorbisAudioResidue(
            Float,
            identification,
            setup,
            invalid_header,
            &.{ &active_spectrum, &silent_spectrum },
            &.{ &active_floor, &silent_floor },
            &.{ &active_threshold, &silent_threshold },
            .{
                .floor_fit_y_values = &fit_y,
                .floor_fit_curves = &fit_curves,
                .floor_encodings = &trial_encodings,
                .floor_y_values = &trial_y,
                .floor_curves = &trial_curves,
                .residue_values = &trial_residue,
                .noise_thresholds = &trial_thresholds,
                .coupling_values = &coupling_values,
                .coupling_thresholds = &coupling_thresholds,
                .do_not_encode = &trial_skips,
            },
            .{
                .floor_encodings = &retained_encodings,
                .floor_y_values = &retained_y,
                .floor_curves = &retained_curves,
                .residue_values = &retained_residue,
                .noise_thresholds = &retained_thresholds,
                .do_not_encode = &retained_skips,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
}

test "Vorbis Floor 1 fitting and normalization reject aliases" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });

    var aliased_storage align(@alignOf(u32)) =
        [_]u8{0} ** (4 * @sizeOf(u32));
    const aliased_target = std.mem.bytesAsSlice(
        f32,
        &aliased_storage,
    );
    @memset(aliased_target, 1);
    const aliased_output = std.mem.bytesAsSlice(
        u32,
        &aliased_storage,
    );
    try std.testing.expectError(
        error.OverlappingVorbisFloorFit,
        fitVorbisFloorOne(
            f32,
            setup,
            0,
            aliased_target,
            aliased_output,
        ),
    );

    const setup_output = std.mem.bytesAsSlice(
        u32,
        std.mem.sliceAsBytes(entries[0..]),
    );
    try std.testing.expectError(
        error.OverlappingVorbisFloorFit,
        fitVorbisFloorOne(
            f32,
            setup,
            0,
            &.{ 1, 1, 1, 1 },
            setup_output,
        ),
    );

    var in_place = [_]f64{ 2, -4, 6, -8 };
    try normalizeVorbisResidue(
        f64,
        &in_place,
        &.{ 2, 2, 2, 2 },
        &in_place,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, -2, 3, -4 },
        &in_place,
    );

    var overlapping = [_]f64{ 1, 2, 3, 4, 5 };
    try std.testing.expectError(
        error.OverlappingVorbisResidueNormalization,
        normalizeVorbisResidue(
            f64,
            overlapping[0..4],
            &.{ 1, 1, 1, 1 },
            overlapping[1..5],
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4, 5 },
        &overlapping,
    );

    var floor_alias = [_]f64{ 1, 2, 3, 4 };
    try std.testing.expectError(
        error.OverlappingVorbisResidueNormalization,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3, 4 },
            &floor_alias,
            &floor_alias,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4 },
        &floor_alias,
    );

    var preserved = [_]f64{ 9, 9, 9, 9 };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3, 4 },
            &.{ 1, 0, 1, 1 },
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 9, 9, 9, 9 },
        &preserved,
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        normalizeVorbisResidue(
            f64,
            &.{ 1, 2, 3 },
            &.{ 1, 1, 1 },
            &preserved,
        ),
    );
}

test "Vorbis packet writer round trips every residue layout" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var codebook_entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    });
    residues[0].end = 4;

    inline for (std.enums.values(VorbisResidueKind)) |kind| {
        residues[0].kind = kind;
        const classification_count: usize =
            if (kind == .two) 4 else 8;
        const classifications = [_]u8{0} ** 8;
        const entries = [_]u32{
            0, 1, 1, 0,
            1, 0, 0, 1,
        };
        var encoded: [32]u8 = undefined;
        var writer = VorbisPacketWriter.init(&encoded);
        try writer.writeResidue(
            setup,
            0,
            4,
            .{
                .do_not_encode = &.{ false, false },
                .classifications = classifications[0..classification_count],
                .entries = entries[0..classification_count],
            },
        );

        var first = [_]f64{99} ** 4;
        var second = [_]f64{99} ** 4;
        const outputs = [_][]f64{ &first, &second };
        var classification_scratch: [8]u8 = undefined;
        var reader = try VorbisPacketReader.init(
            writer.bytes(),
            0,
        );
        const decoded = try reader.decodeResidue(
            f64,
            setup,
            0,
            &.{ false, false },
            &outputs,
            &classification_scratch,
        );
        try std.testing.expect(!decoded.truncated);
        try std.testing.expectEqual(writer.bit_offset, reader.bit_offset);
        if (kind == .two) {
            try std.testing.expectEqualSlices(
                f64,
                &.{ 0, 1, 0, 0 },
                &first,
            );
            try std.testing.expectEqualSlices(
                f64,
                &.{ 1, 0, 0, 0 },
                &second,
            );
        } else {
            try std.testing.expectEqualSlices(
                f64,
                &.{ 0, 1, 1, 0 },
                &first,
            );
            try std.testing.expectEqualSlices(
                f64,
                &.{ 1, 0, 0, 1 },
                &second,
            );
        }
    }

    residues[0].kind = .two;
    var skipped_output: [1]u8 = undefined;
    var skipped_writer = VorbisPacketWriter.init(&skipped_output);
    try skipped_writer.writeResidue(
        setup,
        0,
        4,
        .{
            .do_not_encode = &.{ true, true },
            .classifications = &.{},
            .entries = &.{},
        },
    );
    try std.testing.expectEqual(@as(usize, 0), skipped_writer.bit_offset);

    var no_output: [0]u8 = .{};
    var small_writer = VorbisPacketWriter.init(&no_output);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        small_writer.writeResidue(
            setup,
            0,
            4,
            .{
                .do_not_encode = &.{ false, false },
                .classifications = &.{ 0, 0, 0, 0 },
                .entries = &.{ 0, 1, 1, 0 },
            },
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), small_writer.bit_offset);
}

test "Vorbis audio packet encoding composes floors residues and coupling" {
    var setup_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &setup_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var codebook_entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var modes: [1]VorbisMode = undefined;
    const setup = try parseVorbisSetup(
        setup_packet.bytes,
        2,
        .{
            .codebooks = &codebooks,
            .codebook_entries = &codebook_entries,
            .huffman_nodes = &nodes,
            .codebook_multiplicands = &multiplicands,
            .floors = &floors,
            .residues = &residues,
            .mappings = &mappings,
            .modes = &modes,
        },
    );
    residues[0].end = 4;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 128,
    };
    const floor_encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &.{ 12, 34, 1 },
        } },
        .{ .one = .{
            .used = true,
            .y_values = &.{ 20, 40, 0 },
        } },
    };
    const residue_encodings = [_]VorbisResidueEncoding{
        .{
            .do_not_encode = &.{false},
            .classifications = &.{ 0, 0, 0, 0 },
            .entries = &.{ 0, 1, 1, 0 },
        },
        .{
            .do_not_encode = &.{false},
            .classifications = &.{ 0, 0, 0, 0 },
            .entries = &.{ 1, 0, 0, 1 },
        },
    };
    const encoding = VorbisAudioPacketEncoding{
        .mode_number = 0,
        .previous_window_flag = false,
        .next_window_flag = true,
        .floors = &floor_encodings,
        .residues = &residue_encodings,
    };

    var packet: [128]u8 = undefined;
    @memset(&packet, 0xa5);
    const required = try requiredVorbisAudioPacketBytes(
        identification,
        setup,
        encoding,
    );
    const encoded = try encodeVorbisAudioPacket(
        &packet,
        identification,
        setup,
        encoding,
    );
    var measured_skips = [_]bool{ true, true, true };
    const fixed = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = encoding.floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        fixed.do_not_encode,
    );
    try std.testing.expect(measured_skips[2]);
    var residue_bit_count: usize = 0;
    for (residue_encodings, 0..) |residue_encoding, submap| {
        var residue_counter = VorbisPacketWriter.counting();
        try residue_counter.writeResidue(
            setup,
            mappings[0].submaps[submap].residue,
            encoded.header.block_size / 2,
            residue_encoding,
        );
        residue_bit_count += residue_counter.bit_offset;
    }
    try std.testing.expectEqual(
        encoded.bit_count,
        fixed.bit_count + residue_bit_count,
    );
    try std.testing.expectEqualDeep(encoded.header, fixed.header);
    try std.testing.expectEqual(required, encoded.bytes.len);
    try std.testing.expectEqualDeep(
        encoded.header,
        try parseVorbisAudioPacketHeader(
            encoded.bytes,
            identification,
            setup,
        ),
    );

    var first_output: [128]f64 = undefined;
    var second_output: [128]f64 = undefined;
    const outputs = [_][]f64{ &first_output, &second_output };
    var spectra: [128]f64 = undefined;
    var floor_curves: [128]f64 = undefined;
    var coupling: [128]f64 = undefined;
    var time: [256]f64 = undefined;
    var classifications: [8]u8 = undefined;
    var decoder = VorbisAudioPacketDecoder(
        f64,
        2,
        64,
        128,
    ).init();
    const decoded = try decoder.decode(
        encoded.bytes,
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(!decoded.truncated);
    try std.testing.expectEqual(encoded.bit_count, decoded.decoded_bit_count);
    var nonzero = false;
    for (first_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    for (second_output) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
        nonzero = nonzero or sample != 0;
    }
    try std.testing.expect(nonzero);

    const partly_silent_floors = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        floor_encodings[1],
    };
    const partly_silent = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = &partly_silent_floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ false, false },
        partly_silent.do_not_encode,
    );
    const silent_floors = [_]VorbisFloorPacketEncoding{
        .{ .one = .{} },
        .{ .one = .{} },
    };
    const silent = try measureVorbisAudioPacketFixedCost(
        identification,
        setup,
        .{
            .mode_number = encoding.mode_number,
            .previous_window_flag = encoding.previous_window_flag,
            .next_window_flag = encoding.next_window_flag,
            .floors = &silent_floors,
        },
        &measured_skips,
    );
    try std.testing.expectEqualSlices(
        bool,
        &.{ true, true },
        silent.do_not_encode,
    );
    const preserved_skips = measured_skips;
    try std.testing.expectError(
        error.VorbisAudioPacketSkipOutputTooSmall,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = encoding.floors,
            },
            measured_skips[0..1],
        ),
    );
    try std.testing.expectEqualSlices(
        bool,
        &preserved_skips,
        &measured_skips,
    );
    var invalid_floors = floor_encodings;
    invalid_floors[1] = .{ .zero = .{} };
    try std.testing.expectError(
        error.InvalidVorbisAudioFloorEncoding,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = &invalid_floors,
            },
            &measured_skips,
        ),
    );
    try std.testing.expectEqualSlices(
        bool,
        &preserved_skips,
        &measured_skips,
    );
    var aliased_y = [_]u32{ 12, 34, 1 };
    const aliased_floor = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &aliased_y,
        } },
        floor_encodings[1],
    };
    const aliased_skips = std.mem.bytesAsSlice(
        bool,
        std.mem.sliceAsBytes(&aliased_y),
    )[0..2];
    try std.testing.expectError(
        error.OverlappingVorbisPacketEncoding,
        measureVorbisAudioPacketFixedCost(
            identification,
            setup,
            .{
                .mode_number = encoding.mode_number,
                .previous_window_flag = encoding.previous_window_flag,
                .next_window_flag = encoding.next_window_flag,
                .floors = &aliased_floor,
            },
            aliased_skips,
        ),
    );

    @memset(&packet, 0xa5);
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        encodeVorbisAudioPacket(
            packet[0 .. required - 1],
            identification,
            setup,
            encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 128),
        &packet,
    );
    var invalid_residues = residue_encodings;
    invalid_residues[0].do_not_encode = &.{true};
    var invalid_encoding = encoding;
    invalid_encoding.residues = &invalid_residues;
    try std.testing.expectError(
        error.InvalidVorbisAudioResidueEncoding,
        encodeVorbisAudioPacket(
            &packet,
            identification,
            setup,
            invalid_encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** 128),
        &packet,
    );

    var overlapping: [128]u8 align(@alignOf(u32)) =
        [_]u8{0xa5} ** 128;
    const overlapping_entries = std.mem.bytesAsSlice(
        u32,
        overlapping[0 .. 4 * @sizeOf(u32)],
    );
    @memcpy(
        overlapping_entries,
        residue_encodings[0].entries,
    );
    var overlapping_residues = residue_encodings;
    overlapping_residues[0].entries = overlapping_entries;
    var overlapping_encoding = encoding;
    overlapping_encoding.residues = &overlapping_residues;
    const overlapping_before = overlapping;
    try std.testing.expectError(
        error.OverlappingVorbisPacketEncoding,
        encodeVorbisAudioPacket(
            &overlapping,
            identification,
            setup,
            overlapping_encoding,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &overlapping_before,
        &overlapping,
    );
}

test "Vorbis scalar codebook decoding preserves cursor on failure" {
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{.{
        .dimensions = 1,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 0,
    }};
    const nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            invalid_huffman_branch,
        },
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{},
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    var truncated = try VorbisPacketReader.init(&.{}, 0);
    try std.testing.expectError(
        error.TruncatedVorbisAudioPacket,
        truncated.decodeScalar(setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), truncated.bit_offset);

    const invalid_packet = [_]u8{0xff} ** 4;
    var invalid = try VorbisPacketReader.init(&invalid_packet, 0);
    try std.testing.expectError(
        error.InvalidVorbisCodeword,
        invalid.decodeScalar(setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid.bit_offset);
    try std.testing.expectError(
        error.InvalidVorbisCodebookNumber,
        invalid.decodeScalar(setup, 1),
    );

    var invalid_node_reference = nodes;
    invalid_node_reference[0].branches[0] = 1;
    var invalid_node_setup = setup;
    invalid_node_setup.huffman_nodes = &invalid_node_reference;
    var invalid_node_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_node_reader.decodeScalar(invalid_node_setup, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_node_reader.bit_offset,
    );

    var invalid_leaf = nodes;
    invalid_leaf[0].branches[0] = huffman_leaf_flag | 2;
    var invalid_leaf_setup = setup;
    invalid_leaf_setup.huffman_nodes = &invalid_leaf;
    var invalid_leaf_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_leaf_reader.decodeScalar(invalid_leaf_setup, 0),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_leaf_reader.bit_offset,
    );

    var empty_codebooks = codebooks;
    empty_codebooks[0].entries = 0;
    var empty_setup = setup;
    empty_setup.codebooks = &empty_codebooks;
    var empty_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        empty_reader.decodeScalar(empty_setup, 0),
    );
    try std.testing.expectEqual(@as(usize, 0), empty_reader.bit_offset);
}

test "Vorbis vector codebooks reconstruct both lookup forms" {
    const type_one_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
    };
    const type_one_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 4,
        .entry_offset = 0,
        .active_entry_count = 4,
        .tree_node_count = 3,
        .lookup_type = 1,
        .delta_value = 1,
        .multiplicand_count = 2,
    }};
    const type_one_nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
    };
    const type_one_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 4,
            .codebook_multiplicand_count = 2,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &type_one_books,
        .codebook_entries = &type_one_entries,
        .huffman_nodes = &type_one_nodes,
        .codebook_multiplicands = &.{ 1, 2 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    var type_one_reader = try VorbisPacketReader.init(&.{0b11}, 0);
    var type_one_output: [2]f32 = undefined;
    try type_one_reader.decodeVector(
        f32,
        type_one_setup,
        0,
        &type_one_output,
    );
    try std.testing.expectEqualSlices(f32, &.{ 2, 2 }, &type_one_output);

    const type_two_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const type_two_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 2,
        .minimum_value = 1,
        .delta_value = 0.5,
        .sequence = true,
        .multiplicand_count = 4,
    }};
    const type_two_nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        },
    }};
    const type_two_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &type_two_books,
        .codebook_entries = &type_two_entries,
        .huffman_nodes = &type_two_nodes,
        .codebook_multiplicands = &.{ 0, 2, 4, 6 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    var type_two_reader = try VorbisPacketReader.init(&.{1}, 0);
    var type_two_output: [2]f64 = undefined;
    try type_two_reader.decodeVector(
        f64,
        type_two_setup,
        0,
        &type_two_output,
    );
    try std.testing.expectEqualSlices(f64, &.{ 3, 7 }, &type_two_output);

    var bounded_reader = try VorbisPacketReader.init(&.{1}, 0);
    var short_output: [1]f64 = .{99};
    try std.testing.expectError(
        error.VorbisVectorOutputTooSmall,
        bounded_reader.decodeVector(
            f64,
            type_two_setup,
            0,
            &short_output,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), bounded_reader.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), short_output[0]);

    var invalid_lookup_books = type_two_books;
    invalid_lookup_books[0].lookup_type = 3;
    var invalid_lookup_setup = type_two_setup;
    invalid_lookup_setup.codebooks = &invalid_lookup_books;
    var invalid_lookup_reader = try VorbisPacketReader.init(&.{1}, 0);
    var preserved_output = [_]f64{ 99, 99 };
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_lookup_reader.decodeVector(
            f64,
            invalid_lookup_setup,
            0,
            &preserved_output,
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_lookup_reader.bit_offset,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99 },
        &preserved_output,
    );
}

test "Vorbis vector quantization selects nearest active entries" {
    const type_one_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
    };
    const type_one_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 4,
        .entry_offset = 0,
        .active_entry_count = 4,
        .tree_node_count = 3,
        .lookup_type = 1,
        .delta_value = 1,
        .multiplicand_count = 2,
    }};
    const quantizer_type_one_nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
    };
    const type_one_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 4,
            .codebook_multiplicand_count = 2,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 0,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &type_one_books,
        .codebook_entries = &type_one_entries,
        .huffman_nodes = &quantizer_type_one_nodes,
        .codebook_multiplicands = &.{ 1, 2 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{},
    };
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 3,
            .squared_error = 0,
        },
        try quantizeVorbisVector(
            f32,
            type_one_setup,
            0,
            &.{ 2, 2 },
        ),
    );
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 0,
            .squared_error = 0.5,
        },
        try quantizeVorbisVector(
            f64,
            type_one_setup,
            0,
            &.{ 1.5, 1.5 },
        ),
    );

    const type_two_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const type_two_books = [_]VorbisCodebook{.{
        .dimensions = 2,
        .entries = 2,
        .entry_offset = 0,
        .active_entry_count = 2,
        .tree_node_count = 1,
        .lookup_type = 2,
        .minimum_value = 1,
        .delta_value = 0.5,
        .sequence = true,
        .multiplicand_count = 4,
    }};
    const type_two_nodes = [_]VorbisHuffmanNode{.{
        .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        },
    }};
    const type_two_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 0,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &type_two_books,
        .codebook_entries = &type_two_entries,
        .huffman_nodes = &type_two_nodes,
        .codebook_multiplicands = &.{ 0, 2, 4, 6 },
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &.{},
    };
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 1,
            .squared_error = 0,
        },
        try quantizeVorbisVector(
            f64,
            type_two_setup,
            0,
            &.{ 3, 7 },
        ),
    );
    var batch_entries = [_]u32{ 99, 99, 99 };
    const batch = try quantizeVorbisVectors(
        f64,
        type_one_setup,
        0,
        &.{ 1.9, 2.1, 1.5, 1.5 },
        &batch_entries,
    );
    try std.testing.expectEqualSlices(u32, &.{ 3, 0 }, batch.entries);
    try std.testing.expectEqual(@as(u32, 99), batch_entries[2]);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.52),
        batch.squared_error,
        1e-12,
    );

    var preserved_batch = [_]u32{ 99, 99 };
    try std.testing.expectError(
        error.VorbisQuantizationOutputTooSmall,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, 1, 1 },
            preserved_batch[0..1],
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 99, 99 },
        &preserved_batch,
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationTarget,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, std.math.inf(f64), 1 },
            &preserved_batch,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 99, 99 },
        &preserved_batch,
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationShape,
        quantizeVorbisVectors(
            f64,
            type_one_setup,
            0,
            &.{ 2, 2, 1 },
            &preserved_batch,
        ),
    );

    var aliased_storage: [16]u8 align(@alignOf(u32)) = [_]u8{0} ** 16;
    const aliased_targets = std.mem.bytesAsSlice(
        f32,
        aliased_storage[0 .. 4 * @sizeOf(f32)],
    );
    const aliased_entries = std.mem.bytesAsSlice(
        u32,
        aliased_storage[0 .. 2 * @sizeOf(u32)],
    );
    try std.testing.expectError(
        error.OverlappingVorbisQuantization,
        quantizeVorbisVectors(
            f32,
            type_one_setup,
            0,
            aliased_targets,
            aliased_entries,
        ),
    );

    var sparse_entries = type_two_entries;
    sparse_entries[1].length = 0;
    var sparse_books = type_two_books;
    sparse_books[0].active_entry_count = 1;
    sparse_books[0].tree_node_count = 0;
    var sparse_setup = type_two_setup;
    sparse_setup.codebooks = &sparse_books;
    sparse_setup.codebook_entries = &sparse_entries;
    try std.testing.expectEqualDeep(
        VorbisVectorQuantization{
            .entry = 0,
            .squared_error = 20,
        },
        try quantizeVorbisVector(
            f64,
            sparse_setup,
            0,
            &.{ 3, 7 },
        ),
    );

    try std.testing.expectError(
        error.InvalidVorbisCodebookNumber,
        quantizeVorbisVector(f64, type_two_setup, 1, &.{ 3, 7 }),
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationShape,
        quantizeVorbisVector(f64, type_two_setup, 0, &.{3}),
    );
    try std.testing.expectError(
        error.InvalidVorbisQuantizationTarget,
        quantizeVorbisVector(
            f64,
            type_two_setup,
            0,
            &.{ std.math.nan(f64), 7 },
        ),
    );

    var invalid_books = type_two_books;
    invalid_books[0].minimum_value = std.math.inf(f64);
    var invalid_setup = type_two_setup;
    invalid_setup.codebooks = &invalid_books;
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        quantizeVorbisVector(f64, invalid_setup, 0, &.{ 3, 7 }),
    );
}

test "Vorbis residue quantization plans classifications and entries" {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 2,
            .entries = 4,
            .entry_offset = 0,
            .active_entry_count = 4,
            .tree_node_offset = 0,
            .tree_node_count = 3,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 4,
            .active_entry_count = 2,
            .tree_node_offset = 3,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 4,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 6,
            .active_entry_count = 2,
            .tree_node_offset = 4,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 4,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    books[1][0] = 2;
    const base_residue = VorbisResidue{
        .kind = .one,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    };
    var residues = [_]VorbisResidue{base_residue};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 3,
            .codebook_entry_count = codebook_entries.len,
            .huffman_node_count = nodes.len,
            .codebook_multiplicand_count = 8,
            .time_count = 0,
            .floor_count = 0,
            .residue_count = 1,
            .mapping_count = 0,
            .mode_count = 0,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{
            0, 0, 1, 1,
            0, 0, 2, 2,
        },
        .floors = &.{},
        .residues = &residues,
        .mappings = &.{},
        .modes = &.{},
    };
    const requirements =
        try requiredVorbisResidueQuantizationScratch(
            setup,
            0,
            8,
            1,
        );
    try std.testing.expectEqualDeep(
        VorbisResidueQuantizationScratchRequirements{
            .partition_values = 4,
            .vector_values = 2,
            .classifications = 2,
        },
        requirements,
    );
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVorbisResidueQuantizationEntries(
            setup,
            0,
            8,
            1,
        ),
    );

    const mono = [_]f64{ 1, 1, 1, 1, 2, 2, 2, 2 };
    var partition_scratch: [4]f64 = undefined;
    var vector_scratch: [2]f64 = undefined;
    var classification_scratch: [2]u8 = undefined;
    var classifications = [_]u8{ 99, 99, 99 };
    var entries = [_]u32{ 99, 99, 99, 99, 99 };
    const quantized = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&mono},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        &classifications,
        &entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 1 },
        quantized.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        quantized.encoding.entries,
    );
    try std.testing.expectEqual(@as(u8, 99), classifications[2]);
    try std.testing.expectEqual(@as(u32, 99), entries[4]);
    try std.testing.expectEqual(@as(f64, 0), quantized.squared_error);

    residues[0].cascades[0] = 0;
    residues[0].books[0][0] = -1;
    const adaptive_mono = [_]f64{2} ** mono.len;
    const thresholds = [_]f64{0.1} ** mono.len;
    var adaptive_trial: [2]u8 = undefined;
    var adaptive_best: [2]u8 = undefined;
    var adaptive_classifications = [_]u8{ 77, 77, 77 };
    var adaptive_entries = [_]u32{ 77, 77, 77, 77, 77 };
    const adaptive_quality = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 6 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(adaptive_quality.budget_met);
    try std.testing.expectEqual(@as(u32, 6), adaptive_quality.encoded_bits);
    try std.testing.expectEqual(@as(f64, 0), adaptive_quality.squared_error);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 1 },
        adaptive_quality.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        adaptive_quality.encoding.entries,
    );
    try std.testing.expectEqual(@as(u8, 77), adaptive_classifications[2]);
    try std.testing.expectEqual(@as(u32, 77), adaptive_entries[4]);

    const adaptive_rate = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 2 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(adaptive_rate.budget_met);
    try std.testing.expectEqual(@as(u32, 2), adaptive_rate.encoded_bits);
    try std.testing.expect(adaptive_rate.squared_error > 0);
    try std.testing.expect(adaptive_rate.weighted_squared_error > 0);
    try std.testing.expect(adaptive_rate.audible_excess_power > 0);
    try std.testing.expect(adaptive_rate.lambda > 0);
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0 },
        adaptive_rate.encoding.classifications,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        adaptive_rate.encoding.entries.len,
    );

    const impossible_budget = try quantizeVorbisResidueAdaptive(
        f64,
        setup,
        0,
        &.{false},
        &.{&adaptive_mono},
        &.{&thresholds},
        .{ .target_bits = 1 },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expect(!impossible_budget.budget_met);
    try std.testing.expectEqual(@as(u32, 2), impossible_budget.encoded_bits);

    const mono_f32 = [_]f32{2} ** mono.len;
    const thresholds_f32 = [_]f32{0.1} ** mono.len;
    var adaptive_partition_f32: [4]f32 = undefined;
    var adaptive_vector_f32: [2]f32 = undefined;
    const adaptive_f32 = try quantizeVorbisResidueAdaptive(
        f32,
        setup,
        0,
        &.{false},
        &.{&mono_f32},
        &.{&thresholds_f32},
        .{ .target_bits = 6 },
        .{
            .partition = &adaptive_partition_f32,
            .vector = &adaptive_vector_f32,
            .classifications = &adaptive_trial,
            .best_classifications = &adaptive_best,
        },
        &adaptive_classifications,
        &adaptive_entries,
    );
    try std.testing.expectEqual(@as(f64, 0), adaptive_f32.squared_error);

    const preserved_adaptive_classifications =
        adaptive_classifications;
    const preserved_adaptive_entries = adaptive_entries;
    var invalid_thresholds = thresholds;
    invalid_thresholds[3] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&invalid_thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_adaptive_classifications,
        &adaptive_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_adaptive_entries,
        &adaptive_entries,
    );
    try std.testing.expectError(
        error.VorbisResidueQuantizationScratchTooSmall,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = adaptive_best[0..1],
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueQuantization,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_trial,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    try std.testing.expectError(
        error.VorbisResidueEntryOutputTooSmall,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{ .target_bits = 6 },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            adaptive_entries[0..3],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_adaptive_classifications,
        &adaptive_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_adaptive_entries,
        &adaptive_entries,
    );
    try std.testing.expectError(
        error.InvalidVorbisAdaptiveResidueConfig,
        quantizeVorbisResidueAdaptive(
            f64,
            setup,
            0,
            &.{false},
            &.{&adaptive_mono},
            &.{&thresholds},
            .{
                .target_bits = 6,
                .maximum_iterations = 0,
            },
            .{
                .partition = &partition_scratch,
                .vector = &vector_scratch,
                .classifications = &adaptive_trial,
                .best_classifications = &adaptive_best,
            },
            &adaptive_classifications,
            &adaptive_entries,
        ),
    );
    residues[0].cascades[0] = 1;
    residues[0].books[0][0] = 1;

    var packet: [16]u8 = undefined;
    var writer = VorbisPacketWriter.init(&packet);
    try writer.writeResidue(
        setup,
        0,
        mono.len,
        quantized.encoding,
    );
    var decoded = [_]f64{0} ** mono.len;
    var decode_classifications: [2]u8 = undefined;
    var reader = try VorbisPacketReader.init(writer.bytes(), 0);
    _ = try reader.decodeResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&decoded},
        &decode_classifications,
    );
    try std.testing.expectEqualSlices(f64, &mono, &decoded);

    residues[0].kind = .zero;
    const type_zero = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{false},
        &.{&mono},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        classifications[0..2],
        entries[0..4],
    );
    try std.testing.expectEqual(@as(f64, 0), type_zero.squared_error);

    residues[0].kind = .one;
    var skipped_classification_scratch: [4]u8 = undefined;
    var skipped_classifications: [4]u8 = undefined;
    var skipped_entries: [4]u32 = undefined;
    const one_channel_skipped = try quantizeVorbisResidue(
        f64,
        setup,
        0,
        &.{ false, true },
        &.{ &mono, &mono },
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &skipped_classification_scratch,
        },
        &skipped_classifications,
        &skipped_entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 1, 0, 0 },
        one_channel_skipped.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1 },
        one_channel_skipped.encoding.entries,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        one_channel_skipped.squared_error,
    );

    residues[0].kind = .two;
    const stereo_left = [_]f32{ 1, 1, 2, 2 };
    const stereo_right = [_]f32{ 1, 1, 2, 2 };
    var stereo_partition_scratch: [4]f32 = undefined;
    var stereo_vector_scratch: [2]f32 = undefined;
    const type_two = try quantizeVorbisResidue(
        f32,
        setup,
        0,
        &.{ false, false },
        &.{ &stereo_left, &stereo_right },
        .{
            .partition = &stereo_partition_scratch,
            .vector = &stereo_vector_scratch,
            .classifications = &classification_scratch,
        },
        classifications[0..2],
        entries[0..4],
    );
    try std.testing.expectEqual(@as(f64, 0), type_two.squared_error);

    const preserved_classifications = classifications;
    const preserved_entries = entries;
    try std.testing.expectError(
        error.VorbisResidueClassificationOutputTooSmall,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            classifications[0..1],
            &entries,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_classifications,
        &classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_entries,
        &entries,
    );
    try std.testing.expectError(
        error.VorbisResidueEntryOutputTooSmall,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            &classifications,
            entries[0..3],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &preserved_classifications,
        &classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_entries,
        &entries,
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueQuantization,
        quantizeVorbisResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &.{ &stereo_left, &stereo_right },
            .{
                .partition = &stereo_partition_scratch,
                .vector = &stereo_vector_scratch,
                .classifications = &classification_scratch,
            },
            &classification_scratch,
            &entries,
        ),
    );

    residues[0].kind = .one;
    residues[0].classification_count = 1;
    residues[0].cascades[0] = 3;
    residues[0].books[0][0] = 1;
    residues[0].books[0][1] = 1;
    var wide_codebooks = codebooks;
    wide_codebooks[0].dimensions = 40;
    wide_codebooks[0].entries = 1;
    wide_codebooks[0].active_entry_count = 1;
    wide_codebooks[0].tree_node_count = 0;
    var wide_entries = codebook_entries;
    wide_entries[0].length = 1;
    var wide_setup = setup;
    wide_setup.codebooks = &wide_codebooks;
    wide_setup.codebook_entries = &wide_entries;
    const two_pass_input = [_]f64{2} ** 8;
    var two_pass_classifications: [2]u8 = undefined;
    var two_pass_entries: [8]u32 = undefined;
    const two_pass = try quantizeVorbisResidue(
        f64,
        wide_setup,
        0,
        &.{false},
        &.{&two_pass_input},
        .{
            .partition = &partition_scratch,
            .vector = &vector_scratch,
            .classifications = &classification_scratch,
        },
        &two_pass_classifications,
        &two_pass_entries,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 0, 0 },
        two_pass.encoding.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1, 1, 1, 1, 1 },
        two_pass.encoding.entries,
    );
    try std.testing.expectEqual(@as(f64, 0), two_pass.squared_error);
    var two_pass_packet: [16]u8 = undefined;
    var two_pass_writer = VorbisPacketWriter.init(&two_pass_packet);
    try two_pass_writer.writeResidue(
        wide_setup,
        0,
        two_pass_input.len,
        two_pass.encoding,
    );
    var two_pass_decoded = [_]f64{0} ** two_pass_input.len;
    var two_pass_decode_classifications: [2]u8 = undefined;
    var two_pass_reader =
        try VorbisPacketReader.init(two_pass_writer.bytes(), 0);
    _ = try two_pass_reader.decodeResidue(
        f64,
        wide_setup,
        0,
        &.{false},
        &.{&two_pass_decoded},
        &two_pass_decode_classifications,
    );
    try std.testing.expectEqualSlices(
        f64,
        &two_pass_input,
        &two_pass_decoded,
    );

    residues[0].kind = .two;
    const skipped = try quantizeVorbisResidue(
        f32,
        setup,
        0,
        &.{ true, true },
        &.{ &stereo_left, &stereo_right },
        .{
            .partition = &.{},
            .vector = &.{},
            .classifications = &.{},
        },
        &.{},
        &.{},
    );
    try std.testing.expectEqual(@as(usize, 0), skipped.encoding.entries.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        skipped.encoding.classifications.len,
    );
}

test "Vorbis audio residues group and quantize submaps atomically" {
    try testVorbisAudioResidueQuantization(f32);
    try testVorbisAudioResidueQuantization(f64);
}

fn testVorbisAudioResidueQuantization(comptime Float: type) !void {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 2 },
        .{ .codeword = 1, .length = 2 },
        .{ .codeword = 2, .length = 2 },
        .{ .codeword = 3, .length = 2 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 2,
            .entries = 4,
            .entry_offset = 0,
            .active_entry_count = 4,
            .tree_node_offset = 0,
            .tree_node_count = 3,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 4,
            .active_entry_count = 2,
            .tree_node_offset = 3,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 4,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 6,
            .active_entry_count = 2,
            .tree_node_offset = 4,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 4,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{ 1, 2 } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag | 2,
            huffman_leaf_flag | 3,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[1][0] = 2;
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{ .one = .{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    } }};
    var channel_mux = [_]u4{0} ** 255;
    channel_mux[1] = 1;
    const mappings = [_]VorbisMapping{.{
        .submap_count = 2,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = channel_mux,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = codebooks.len,
            .codebook_entry_count = codebook_entries.len,
            .huffman_node_count = nodes.len,
            .codebook_multiplicand_count = 8,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 4,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{
            0, 0, 1, 1,
            0, 0, 2, 2,
        },
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    try std.testing.expectEqual(
        VorbisAudioResidueQuantizationStorageRequirements{
            .encodings = 2,
            .submap_results = 2,
            .do_not_encode = 2,
            .classifications = 4,
            .entries = 8,
            .partition_values = 4,
            .vector_values = 2,
            .classification_scratch = 2,
        },
        try requiredVorbisAudioResidueQuantizationStorage(
            identification,
            setup,
            header,
        ),
    );

    var residue_values = [_]Float{0} ** 64;
    @memset(residue_values[0..8], 2);
    @memset(residue_values[32..40], 2);
    const thresholds = [_]Float{0.1} ** 64;
    var partition: [4]Float = undefined;
    var vector: [2]Float = undefined;
    var classification_scratch: [2]u8 = undefined;
    var best_classifications: [2]u8 = undefined;
    var trial_classifications: [4]u8 = undefined;
    var trial_entries: [8]u32 = undefined;
    var trial_skips: [2]bool = undefined;
    const sentinel_encoding = VorbisResidueEncoding{
        .do_not_encode = &.{true},
        .classifications = &.{99},
        .entries = &.{99},
    };
    const sentinel_result = VorbisAudioResidueSubmapResult{
        .target_bits = 91,
        .encoded_bits = 92,
        .budget_met = false,
        .squared_error = 93,
        .weighted_squared_error = 94,
        .audible_excess_power = 95,
        .lambda = 96,
        .iterations = 97,
    };
    var retained_encodings =
        [_]VorbisResidueEncoding{sentinel_encoding} ** 3;
    var retained_results =
        [_]VorbisAudioResidueSubmapResult{sentinel_result} ** 3;
    var retained_skips = [_]bool{true} ** 3;
    var retained_classifications = [_]u8{98} ** 5;
    var retained_entries = [_]u32{99} ** 9;
    const budget = VorbisPacketBitBudget{
        .packet_index = 0,
        .nominal_bits = 12,
        .target_bits = 12,
        .reservoir_balance_before = 0,
    };
    const plan = try quantizeVorbisAudioResiduesAdaptive(
        Float,
        identification,
        setup,
        header,
        &residue_values,
        &thresholds,
        &.{ false, false },
        budget,
        0,
        &.{ 1, 1 },
        .{},
        .{
            .partition = &partition,
            .vector = &vector,
            .classifications = &classification_scratch,
            .best_classifications = &best_classifications,
            .output_classifications = &trial_classifications,
            .entries = &trial_entries,
            .do_not_encode = &trial_skips,
        },
        .{
            .encodings = &retained_encodings,
            .submap_results = &retained_results,
            .do_not_encode = &retained_skips,
            .classifications = &retained_classifications,
            .entries = &retained_entries,
        },
    );
    try std.testing.expectEqual(
        VorbisResidueBitAllocation{
            .packet_target_bits = 12,
            .fixed_packet_bits = 0,
            .residue_bits = 12,
        },
        plan.allocation,
    );
    try std.testing.expectEqualSlices(
        u8,
        &.{ 1, 1, 1, 1 },
        plan.classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 1, 1, 1, 1, 1, 1, 1, 1 },
        plan.entries,
    );
    for (plan.submap_results) |result| {
        try std.testing.expectEqual(@as(u32, 6), result.target_bits);
        try std.testing.expectEqual(@as(u32, 6), result.encoded_bits);
        try std.testing.expect(result.budget_met);
        try std.testing.expectEqual(@as(f64, 0), result.squared_error);
    }
    for (plan.encodings) |encoding| {
        try std.testing.expectEqualSlices(
            bool,
            &.{false},
            encoding.do_not_encode,
        );
        try std.testing.expectEqualSlices(
            u8,
            &.{ 1, 1 },
            encoding.classifications,
        );
        try std.testing.expectEqualSlices(
            u32,
            &.{ 1, 1, 1, 1 },
            encoding.entries,
        );
    }
    try std.testing.expectEqual(
        sentinel_encoding,
        retained_encodings[2],
    );
    try std.testing.expectEqual(
        sentinel_result,
        retained_results[2],
    );
    try std.testing.expect(retained_skips[2]);
    try std.testing.expectEqual(@as(u8, 98), retained_classifications[4]);
    try std.testing.expectEqual(@as(u32, 99), retained_entries[8]);

    const floor_y = [_]u32{ 100, 100 };
    const floor_encodings = [_]VorbisFloorPacketEncoding{
        .{ .one = .{
            .used = true,
            .y_values = &floor_y,
        } },
        .{ .one = .{
            .used = true,
            .y_values = &floor_y,
        } },
    };
    try std.testing.expect(
        try requiredVorbisAudioPacketBytes(
            identification,
            setup,
            .{
                .mode_number = 0,
                .floors = &floor_encodings,
                .residues = plan.encodings,
            },
        ) > 0,
    );

    const encodings_before = retained_encodings;
    const results_before = retained_results;
    const skips_before = retained_skips;
    const classifications_before = retained_classifications;
    const entries_before = retained_entries;
    var invalid_thresholds = thresholds;
    invalid_thresholds[63] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &invalid_thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectEqualDeep(
        encodings_before,
        retained_encodings,
    );
    try std.testing.expectEqualSlices(
        VorbisAudioResidueSubmapResult,
        &results_before,
        &retained_results,
    );
    try std.testing.expectEqualSlices(
        bool,
        &skips_before,
        &retained_skips,
    );
    try std.testing.expectEqualSlices(
        u8,
        &classifications_before,
        &retained_classifications,
    );
    try std.testing.expectEqualSlices(
        u32,
        &entries_before,
        &retained_entries,
    );
    try std.testing.expectError(
        error.VorbisAudioResidueQuantizationScratchTooSmall,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = partition[0..3],
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioResidueQuantizationStorageTooSmall,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &best_classifications,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = retained_encodings[0..1],
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioResidueQuantizationStorage,
        quantizeVorbisAudioResiduesAdaptive(
            Float,
            identification,
            setup,
            header,
            &residue_values,
            &thresholds,
            &.{ false, false },
            budget,
            0,
            &.{ 1, 1 },
            .{},
            .{
                .partition = &partition,
                .vector = &vector,
                .classifications = &classification_scratch,
                .best_classifications = &classification_scratch,
                .output_classifications = &trial_classifications,
                .entries = &trial_entries,
                .do_not_encode = &trial_skips,
            },
            .{
                .encodings = &retained_encodings,
                .submap_results = &retained_results,
                .do_not_encode = &retained_skips,
                .classifications = &retained_classifications,
                .entries = &retained_entries,
            },
        ),
    );
}

test "Vorbis residues decode layouts transactionally with caller scratch" {
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 1, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 1,
            .entries = 2,
            .entry_offset = 0,
            .active_entry_count = 2,
            .tree_node_offset = 0,
            .tree_node_count = 1,
            .lookup_type = 0,
        },
        .{
            .dimensions = 2,
            .entries = 2,
            .entry_offset = 2,
            .active_entry_count = 2,
            .tree_node_offset = 1,
            .tree_node_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_count = 4,
        },
    };
    const nodes = [_]VorbisHuffmanNode{
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
        .{ .branches = .{
            huffman_leaf_flag,
            huffman_leaf_flag | 1,
        } },
    };
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    cascades[1] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    books[1][0] = 1;
    var residues = [_]VorbisResidue{.{
        .kind = .zero,
        .begin = 0,
        .end = 8,
        .partition_size = 4,
        .classification_count = 2,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var setup = VorbisSetup{
        .summary = .{
            .codebook_count = 2,
            .codebook_entry_count = 4,
            .huffman_node_count = 2,
            .codebook_multiplicand_count = 4,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 2,
            .maximum_codebook_entries = 2,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &.{ 1, 2, 3, 4 },
        .floors = &.{},
        .residues = &residues,
        .mappings = &.{},
        .modes = &.{.{ .large_block = false, .mapping = 0 }},
    };
    try std.testing.expectEqual(
        @as(usize, 4),
        try requiredVorbisResidueClassifications(residues[0], 8, 2),
    );

    var zero_left = [_]f32{99} ** 8;
    var zero_right = [_]f32{99} ** 8;
    const zero_outputs = [_][]f32{ &zero_left, &zero_right };
    var zero_scratch: [4]u8 = undefined;
    var zero_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    const zero_result = try zero_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &zero_outputs,
        &zero_scratch,
    );
    try std.testing.expect(!zero_result.truncated);
    try std.testing.expectEqual(@as(usize, 6), zero_reader.bit_offset);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 3, 2, 4, 3, 1, 4, 2 },
        &zero_left,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0, 0, 0, 0, 0 },
        &zero_right,
    );

    residues[0].kind = .one;
    var one_left = [_]f64{99} ** 8;
    var one_right = [_]f64{99} ** 8;
    const one_outputs = [_][]f64{ &one_left, &one_right };
    var one_scratch: [4]u8 = undefined;
    var one_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try one_reader.decodeResidue(
        f64,
        setup,
        0,
        &.{ false, true },
        &one_outputs,
        &one_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, 2, 3, 4, 3, 4, 1, 2 },
        &one_left,
    );

    residues[0].kind = .two;
    try std.testing.expectEqual(
        @as(usize, 2),
        try requiredVorbisResidueClassifications(residues[0], 4, 2),
    );
    var two_left = [_]f32{99} ** 4;
    var two_right = [_]f32{99} ** 4;
    const two_outputs = [_][]f32{ &two_left, &two_right };
    var two_scratch: [2]u8 = undefined;
    var two_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try two_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &two_outputs,
        &two_scratch,
    );
    try std.testing.expectEqualSlices(f32, &.{ 1, 3, 3, 1 }, &two_left);
    try std.testing.expectEqualSlices(f32, &.{ 2, 4, 4, 2 }, &two_right);

    @memset(&two_left, 99);
    @memset(&two_right, 99);
    var all_skipped_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    _ = try all_skipped_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ true, true },
        &two_outputs,
        &two_scratch,
    );
    try std.testing.expectEqual(@as(usize, 0), all_skipped_reader.bit_offset);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &two_left);
    try std.testing.expectEqualSlices(f32, &.{ 0, 0, 0, 0 }, &two_right);

    residues[0].kind = .one;
    residues[0].end = 12;
    var partial_left = [_]f32{99} ** 12;
    var partial_right = [_]f32{99} ** 12;
    const partial_outputs = [_][]f32{ &partial_left, &partial_right };
    var partial_scratch: [6]u8 = undefined;
    var partial_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    const partial = try partial_reader.decodeResidue(
        f32,
        setup,
        0,
        &.{ false, true },
        &partial_outputs,
        &partial_scratch,
    );
    try std.testing.expect(partial.truncated);
    try std.testing.expectEqual(@as(usize, 8), partial_reader.bit_offset);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1, 2, 3, 4, 3, 4, 1, 2, 1, 2, 0, 0 },
        &partial_left,
    );

    var preserved = [_]f32{99} ** 12;
    const overlapping_outputs = [_][]f32{ &preserved, &preserved };
    var overlap_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.OverlappingVorbisResidueOutput,
        overlap_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &overlapping_outputs,
            &partial_scratch,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), overlap_reader.bit_offset);
    try std.testing.expectEqual(@as(f32, 99), preserved[0]);

    var alias_output = [_]f32{99} ** 12;
    var other_output = [_]f32{99} ** 12;
    const alias_outputs = [_][]f32{ &alias_output, &other_output };
    var alias_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.OverlappingVorbisResidueScratch,
        alias_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, false },
            &alias_outputs,
            std.mem.sliceAsBytes(alias_output[0..]),
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), alias_output[0]);

    @memset(&partial_left, 99);
    @memset(&partial_right, 99);
    var short_scratch: [5]u8 = undefined;
    var short_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.VorbisResidueScratchTooSmall,
        short_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, true },
            &partial_outputs,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), partial_right[11]);

    var invalid_residues = residues;
    invalid_residues[0].books[0][0] = -1;
    setup.residues = &invalid_residues;
    var invalid_reader = try VorbisPacketReader.init(&.{0x1c}, 0);
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_reader.decodeResidue(
            f32,
            setup,
            0,
            &.{ false, true },
            &partial_outputs,
            &partial_scratch,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid_reader.bit_offset);
}

test "Vorbis channel coupling inverts through transactional scratch" {
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mapping = VorbisMapping{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    };
    try std.testing.expectEqual(
        @as(usize, 8),
        try requiredVorbisCouplingScratch(2, 4),
    );
    const original_first = [_]f64{
        4, 3, -4, -3, 1, -1, 2, -2,
    };
    const original_second = [_]f64{
        3, 4, -3, -4, -1, 1, -2, 2,
    };
    var forward_first = original_first;
    var forward_second = original_second;
    const forward_channels =
        [_][]f64{ &forward_first, &forward_second };
    var forward_scratch: [16]f64 = undefined;
    try forwardCoupleVorbisChannels(
        f64,
        mapping,
        &forward_channels,
        &forward_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 4, 4, -4, -4, -1, 1, -2, 2 },
        &forward_first,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1, -1, 1, -1, -2, -2, -4, -4 },
        &forward_second,
    );
    try inverseCoupleVorbisChannels(
        f64,
        mapping,
        &forward_channels,
        &forward_scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_first,
        &forward_first,
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_second,
        &forward_second,
    );
    var short_forward_scratch: [15]f64 = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        forwardCoupleVorbisChannels(
            f64,
            mapping,
            &forward_channels,
            &short_forward_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_first,
        &forward_first,
    );
    var invalid_forward_mapping = mapping;
    invalid_forward_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        forwardCoupleVorbisChannels(
            f64,
            invalid_forward_mapping,
            &forward_channels,
            &forward_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &original_second,
        &forward_second,
    );

    var magnitude = [_]f64{ 4, 4, -4, -4 };
    var angle = [_]f64{ 1, -1, 1, -1 };
    const channels = [_][]f64{ &magnitude, &angle };
    var scratch: [8]f64 = undefined;
    try inverseCoupleVorbisChannels(
        f64,
        mapping,
        &channels,
        &scratch,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 4, 3, -4, -3 },
        &magnitude,
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 3, 4, -3, -4 },
        &angle,
    );

    magnitude = [_]f64{ 4, 4, -4, -4 };
    angle = [_]f64{ 1, -1, 1, -1 };
    var short_scratch: [7]f64 = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &channels,
            &short_scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var alias_backing = [_]f64{ 4, 4, -4, -4, 0, 0, 0, 0 };
    const alias_channels = [_][]f64{ alias_backing[0..4], &angle };
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &alias_channels,
            &alias_backing,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), alias_backing[0]);

    var invalid_mapping = mapping;
    invalid_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        inverseCoupleVorbisChannels(
            f64,
            invalid_mapping,
            &channels,
            &scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var chained_mapping = mapping;
    chained_mapping.coupling_step_count = 2;
    chained_mapping.coupling_steps[1] = .{
        .magnitude = 1,
        .angle = 2,
    };
    const chained_original = [3][3]f32{
        .{ 4, -2, 1 },
        .{ 1, 3, -4 },
        .{ -2, 1, 2 },
    };
    var chained_values = chained_original;
    const chained_channels = [_][]f32{
        &chained_values[0],
        &chained_values[1],
        &chained_values[2],
    };
    var chained_scratch: [9]f32 = undefined;
    try forwardCoupleVorbisChannels(
        f32,
        chained_mapping,
        &chained_channels,
        &chained_scratch,
    );
    try inverseCoupleVorbisChannels(
        f32,
        chained_mapping,
        &chained_channels,
        &chained_scratch,
    );
    try std.testing.expectEqualDeep(
        chained_original,
        chained_values,
    );

    angle[0] = std.math.inf(f64);
    try std.testing.expectError(
        error.InvalidVorbisChannelValue,
        inverseCoupleVorbisChannels(
            f64,
            mapping,
            &channels,
            &scratch,
        ),
    );
    try std.testing.expectEqual(@as(f64, 4), magnitude[0]);

    var shared = [_]f32{ 1, 2 };
    const overlapping = [_][]f32{ &shared, &shared };
    var overlap_scratch: [4]f32 = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisChannelOutput,
        inverseCoupleVorbisChannels(
            f32,
            mapping,
            &overlapping,
            &overlap_scratch,
        ),
    );
}

test "Vorbis masking thresholds survive floor normalization and coupling" {
    try testVorbisNoiseThresholdCoupling(f32);
    try testVorbisNoiseThresholdCoupling(f64);
}

fn testVorbisNoiseThresholdCoupling(comptime Float: type) !void {
    const thresholds = [_]Float{ 0.1, 0.2, 0.4, 0.8 };
    const floor_curve = [_]Float{ 0.5, 2, 4, 0.25 };
    var normalized: [4]Float = undefined;
    try normalizeVorbisNoiseThresholds(
        Float,
        &thresholds,
        &floor_curve,
        &normalized,
    );
    const expected = [_]Float{ 0.2, 0.1, 0.1, 3.2 };
    for (normalized, expected) |actual, wanted| {
        try std.testing.expectApproxEqAbs(
            wanted,
            actual,
            16 * std.math.floatEps(Float),
        );
    }
    var in_place = thresholds;
    try normalizeVorbisNoiseThresholds(
        Float,
        &in_place,
        &floor_curve,
        &in_place,
    );
    try std.testing.expectEqualSlices(Float, &normalized, &in_place);

    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mapping = VorbisMapping{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    };
    var first_threshold = [_]Float{0.4};
    var second_threshold = [_]Float{0.4};
    const first_source_value = [_]Float{0.4};
    const second_source_value = [_]Float{0.2};
    const source_channels = [_][]const Float{
        &first_source_value,
        &second_source_value,
    };
    const threshold_channels = [_][]Float{
        &first_threshold,
        &second_threshold,
    };
    var value_scratch: [2]Float = undefined;
    var threshold_scratch: [2]Float = undefined;
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        mapping,
        &source_channels,
        &threshold_channels,
        &value_scratch,
        &threshold_scratch,
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        first_threshold[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        second_threshold[0],
        4 * std.math.floatEps(Float),
    );

    const source_values = [_]Float{ -0.2, 0, 0.2 };
    const perturbation_signs = [_]Float{ -1, 1 };
    for (source_values) |first_source| {
        for (source_values) |second_source| {
            var bounded_first_threshold = [_]Float{0.4};
            var bounded_second_threshold = [_]Float{0.4};
            const bounded_source_channels = [_][]const Float{
                &[_]Float{first_source},
                &[_]Float{second_source},
            };
            const bounded_threshold_channels = [_][]Float{
                &bounded_first_threshold,
                &bounded_second_threshold,
            };
            try forwardCoupleVorbisNoiseThresholds(
                Float,
                mapping,
                &bounded_source_channels,
                &bounded_threshold_channels,
                &value_scratch,
                &threshold_scratch,
            );
            for (perturbation_signs) |first_sign| {
                for (perturbation_signs) |second_sign| {
                    var first = [_]Float{first_source};
                    var second = [_]Float{second_source};
                    const channels = [_][]Float{ &first, &second };
                    var scratch: [2]Float = undefined;
                    try forwardCoupleVorbisChannels(
                        Float,
                        mapping,
                        &channels,
                        &scratch,
                    );
                    first[0] +=
                        first_sign * bounded_first_threshold[0];
                    second[0] +=
                        second_sign * bounded_second_threshold[0];
                    try inverseCoupleVorbisChannels(
                        Float,
                        mapping,
                        &channels,
                        &scratch,
                    );
                    const tolerance =
                        @as(Float, 0.4) +
                        32 * std.math.floatEps(Float);
                    try std.testing.expect(
                        @abs(first[0] - first_source) <= tolerance,
                    );
                    try std.testing.expect(
                        @abs(second[0] - second_source) <= tolerance,
                    );
                }
            }
        }
    }

    var chained_mapping = mapping;
    chained_mapping.coupling_step_count = 2;
    chained_mapping.coupling_steps[1] = .{
        .magnitude = 0,
        .angle = 2,
    };
    var chained_first = [_]Float{0.8};
    var chained_second = [_]Float{0.4};
    var chained_third = [_]Float{0.2};
    const chained_source_first = [_]Float{10};
    const chained_source_second = [_]Float{5};
    const chained_source_third = [_]Float{2};
    const chained_sources = [_][]const Float{
        &chained_source_first,
        &chained_source_second,
        &chained_source_third,
    };
    const chained_thresholds = [_][]Float{
        &chained_first,
        &chained_second,
        &chained_third,
    };
    var chained_value_scratch: [3]Float = undefined;
    var chained_scratch: [3]Float = undefined;
    try forwardCoupleVorbisNoiseThresholds(
        Float,
        chained_mapping,
        &chained_sources,
        &chained_thresholds,
        &chained_value_scratch,
        &chained_scratch,
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.1),
        chained_first[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.2),
        chained_second[0],
        4 * std.math.floatEps(Float),
    );
    try std.testing.expectApproxEqAbs(
        @as(Float, 0.1),
        chained_third[0],
        4 * std.math.floatEps(Float),
    );

    var preserved = [_]Float{9} ** 4;
    var invalid_thresholds = thresholds;
    invalid_thresholds[3] = 0;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        normalizeVorbisNoiseThresholds(
            Float,
            &invalid_thresholds,
            &floor_curve,
            &preserved,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{9} ** 4),
        &preserved,
    );
    var overlap = [_]Float{ 0.1, 0.2, 0.3, 0.4, 0.5 };
    try std.testing.expectError(
        error.OverlappingVorbisNoiseThresholdNormalization,
        normalizeVorbisNoiseThresholds(
            Float,
            overlap[0..4],
            &floor_curve,
            overlap[1..5],
        ),
    );

    first_threshold[0] = 0;
    second_threshold[0] = 0.4;
    const preserved_first = first_threshold;
    const preserved_second = second_threshold;
    try std.testing.expectError(
        error.InvalidVorbisNoiseThreshold,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_first,
        &first_threshold,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_second,
        &second_threshold,
    );
    first_threshold[0] = 0.4;
    var short_scratch: [1]Float = undefined;
    try std.testing.expectError(
        error.VorbisCouplingScratchTooSmall,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &short_scratch,
            &threshold_scratch,
        ),
    );
    const overlapping_channels = [_][]Float{
        &first_threshold,
        &first_threshold,
    };
    try std.testing.expectError(
        error.OverlappingVorbisChannelOutput,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &overlapping_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    var invalid_source_value = first_source_value;
    invalid_source_value[0] = std.math.nan(Float);
    const invalid_sources = [_][]const Float{
        &invalid_source_value,
        &second_source_value,
    };
    const before_invalid_first = first_threshold;
    const before_invalid_second = second_threshold;
    try std.testing.expectError(
        error.InvalidVorbisChannelValue,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &invalid_sources,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &before_invalid_first,
        &first_threshold,
    );
    try std.testing.expectEqualSlices(
        Float,
        &before_invalid_second,
        &second_threshold,
    );
    var invalid_mapping = mapping;
    invalid_mapping.coupling_steps[0].angle = 0;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            invalid_mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &threshold_scratch,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &threshold_channels,
            &value_scratch,
            &value_scratch,
        ),
    );
    var alias_backing = [_]Float{ 0.4, 0.4 };
    const alias_channels = [_][]Float{
        alias_backing[0..1],
        alias_backing[1..2],
    };
    try std.testing.expectError(
        error.OverlappingVorbisCouplingScratch,
        forwardCoupleVorbisNoiseThresholds(
            Float,
            mapping,
            &source_channels,
            &alias_channels,
            &alias_backing,
            &threshold_scratch,
        ),
    );
}

test "Vorbis floor packets decode retained type zero and type one setup" {
    var floor_zero_packet_storage: [128]u8 = undefined;
    const floor_zero_packet = makeTestVorbisSetup(
        &floor_zero_packet_storage,
        .unordered,
        false,
        true,
    );
    var floor_zero_codebooks: [1]VorbisCodebook = undefined;
    var floor_zero_entries: [2]VorbisCodebookEntry = undefined;
    var floor_zero_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_zero_multiplicands: [2]u32 = undefined;
    var floor_zero_floors: [1]VorbisFloor = undefined;
    var floor_zero_residues: [1]VorbisResidue = undefined;
    var floor_zero_mappings: [1]VorbisMapping = undefined;
    var floor_zero_modes: [1]VorbisMode = undefined;
    const floor_zero_setup = try parseVorbisSetup(
        floor_zero_packet.bytes,
        1,
        .{
            .codebooks = &floor_zero_codebooks,
            .codebook_entries = &floor_zero_entries,
            .huffman_nodes = &floor_zero_nodes,
            .codebook_multiplicands = &floor_zero_multiplicands,
            .floors = &floor_zero_floors,
            .residues = &floor_zero_residues,
            .mappings = &floor_zero_mappings,
            .modes = &floor_zero_modes,
        },
    );

    var floor_zero_audio_storage: [4]u8 = undefined;
    var floor_zero_writer =
        TestVorbisBitWriter.init(&floor_zero_audio_storage);
    floor_zero_writer.write(5, 8);
    floor_zero_writer.write(0, 1);
    floor_zero_writer.write(1, 1);
    var floor_zero_reader = try VorbisPacketReader.init(
        floor_zero_audio_storage[0..2],
        0,
    );
    var coefficients = [_]f64{99};
    const floor_zero_result = try floor_zero_reader.decodeFloorZero(
        floor_zero_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(floor_zero_result.used);
    try std.testing.expectEqual(@as(u64, 5), floor_zero_result.amplitude);
    try std.testing.expectEqual(@as(u8, 1), floor_zero_result.coefficient_count);
    try std.testing.expectEqual(@as(f64, 1), coefficients[0]);
    try std.testing.expectEqual(@as(usize, 10), floor_zero_reader.bit_offset);
    const retained_floor_zero = switch (floor_zero_setup.floors[0]) {
        .zero => |floor| floor,
        .one => return error.TestExpectedFloorZero,
    };
    var floor_zero_curve: [4]f64 = undefined;
    try synthesizeVorbisFloorZero(
        f64,
        retained_floor_zero,
        floor_zero_result,
        &coefficients,
        &floor_zero_curve,
    );
    const expected_floor_zero_curve = [_]f64{
        0.0013426457711833558,
        0.001098155656368672,
        0.0010932223306766293,
        0.0010921548064638331,
    };
    for (floor_zero_curve, expected_floor_zero_curve) |actual, expected| {
        try std.testing.expectApproxEqAbs(expected, actual, 1e-14);
    }

    var maximum_order_floor = retained_floor_zero;
    maximum_order_floor.order = 255;
    var maximum_order_coefficients: [255]f64 = undefined;
    for (&maximum_order_coefficients, 0..) |*coefficient, index| {
        coefficient.* =
            std.math.pi * @as(f64, @floatFromInt(index + 1)) / 256.0;
    }
    var maximum_order_curve: [16]f64 = undefined;
    try synthesizeVorbisFloorZero(
        f64,
        maximum_order_floor,
        .{
            .used = true,
            .amplitude = floor_zero_result.amplitude,
            .coefficient_count = 255,
        },
        &maximum_order_coefficients,
        &maximum_order_curve,
    );
    for (maximum_order_curve) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value > 0);
    }

    var invalid_coefficients = [_]f64{std.math.nan(f64)};
    var preserved_floor_zero_curve = [_]f64{99} ** 4;
    try std.testing.expectError(
        error.InvalidVorbisFloorPacketState,
        synthesizeVorbisFloorZero(
            f64,
            retained_floor_zero,
            floor_zero_result,
            &invalid_coefficients,
            &preserved_floor_zero_curve,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99, 99, 99 },
        &preserved_floor_zero_curve,
    );

    var truncated_zero = try VorbisPacketReader.init(&.{5}, 0);
    var preserved_coefficient = [_]f64{99};
    const truncated_zero_result = try truncated_zero.decodeFloorZero(
        floor_zero_setup,
        0,
        &preserved_coefficient,
    );
    try std.testing.expect(!truncated_zero_result.used);
    try std.testing.expectEqual(@as(usize, 8), truncated_zero.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), preserved_coefficient[0]);

    var wide_amplitude_floors = floor_zero_floors;
    wide_amplitude_floors[0].zero.amplitude_bits = 63;
    var wide_amplitude_setup = floor_zero_setup;
    wide_amplitude_setup.floors = &wide_amplitude_floors;
    var wide_amplitude_packet = [_]u8{0} ** 9;
    wide_amplitude_packet[0] = 1;
    wide_amplitude_packet[8] = 1;
    var wide_amplitude_reader = try VorbisPacketReader.init(
        &wide_amplitude_packet,
        0,
    );
    const wide_amplitude_result = try wide_amplitude_reader.decodeFloorZero(
        wide_amplitude_setup,
        0,
        &coefficients,
    );
    try std.testing.expect(wide_amplitude_result.used);
    try std.testing.expectEqual(@as(u64, 1), wide_amplitude_result.amplitude);
    try std.testing.expectEqual(@as(usize, 65), wide_amplitude_reader.bit_offset);

    var reserved_book_storage: [2]u8 = undefined;
    var reserved_book_writer =
        TestVorbisBitWriter.init(&reserved_book_storage);
    reserved_book_writer.write(5, 8);
    reserved_book_writer.write(1, 1);
    var reserved_book_reader = try VorbisPacketReader.init(
        &reserved_book_storage,
        0,
    );
    try std.testing.expectError(
        error.InvalidVorbisFloorBookNumber,
        reserved_book_reader.decodeFloorZero(
            floor_zero_setup,
            0,
            &preserved_coefficient,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), reserved_book_reader.bit_offset);
    try std.testing.expectEqual(@as(f64, 99), preserved_coefficient[0]);

    var floor_one_packet_storage: [128]u8 = undefined;
    const floor_one_packet = makeTestVorbisSetup(
        &floor_one_packet_storage,
        .unordered,
        true,
        false,
    );
    var floor_one_codebooks: [1]VorbisCodebook = undefined;
    var floor_one_entries: [2]VorbisCodebookEntry = undefined;
    var floor_one_nodes: [1]VorbisHuffmanNode = undefined;
    var floor_one_multiplicands: [2]u32 = undefined;
    var floor_one_floors: [1]VorbisFloor = undefined;
    var floor_one_residues: [1]VorbisResidue = undefined;
    var floor_one_mappings: [1]VorbisMapping = undefined;
    var floor_one_modes: [1]VorbisMode = undefined;
    const floor_one_setup = try parseVorbisSetup(
        floor_one_packet.bytes,
        2,
        .{
            .codebooks = &floor_one_codebooks,
            .codebook_entries = &floor_one_entries,
            .huffman_nodes = &floor_one_nodes,
            .codebook_multiplicands = &floor_one_multiplicands,
            .floors = &floor_one_floors,
            .residues = &floor_one_residues,
            .mappings = &floor_one_mappings,
            .modes = &floor_one_modes,
        },
    );

    var floor_one_audio_storage: [4]u8 = undefined;
    var floor_one_writer =
        TestVorbisBitWriter.init(&floor_one_audio_storage);
    floor_one_writer.write(1, 1);
    floor_one_writer.write(23, 8);
    floor_one_writer.write(47, 8);
    floor_one_writer.write(1, 1);
    floor_one_writer.write(1, 1);
    var floor_one_reader = try VorbisPacketReader.init(
        floor_one_audio_storage[0..3],
        0,
    );
    var y_values = [_]u32{ 99, 99, 99 };
    const floor_one_result = try floor_one_reader.decodeFloorOne(
        floor_one_setup,
        0,
        &y_values,
    );
    try std.testing.expect(floor_one_result.used);
    try std.testing.expectEqual(@as(u7, 3), floor_one_result.value_count);
    try std.testing.expectEqualSlices(u32, &.{ 23, 47, 1 }, &y_values);
    try std.testing.expectEqual(@as(usize, 19), floor_one_reader.bit_offset);
    const retained_floor_one = switch (floor_one_setup.floors[0]) {
        .one => |floor| floor,
        .zero => return error.TestExpectedFloorOne,
    };
    var floor_curve: [4]f64 = undefined;
    try synthesizeVorbisFloorOne(
        f64,
        retained_floor_one,
        floor_one_result,
        &y_values,
        &floor_curve,
    );
    const expected_curve = [_]f64{
        4.5315863e-7,
        6.2082472e-7,
        9.0579828e-7,
        1.3215816e-6,
    };
    for (floor_curve, expected_curve) |actual, expected| {
        try std.testing.expectApproxEqAbs(expected, actual, 1e-13);
    }

    var unused_one = try VorbisPacketReader.init(&.{0}, 0);
    var preserved_y = [_]u32{ 99, 99, 99 };
    const unused_one_result = try unused_one.decodeFloorOne(
        floor_one_setup,
        0,
        &preserved_y,
    );
    try std.testing.expect(!unused_one_result.used);
    try std.testing.expectEqual(@as(usize, 1), unused_one.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);
    var silent_curve = [_]f32{99} ** 4;
    try synthesizeVorbisFloorOne(
        f32,
        retained_floor_one,
        unused_one_result,
        &preserved_y,
        &silent_curve,
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0, 0, 0, 0 },
        &silent_curve,
    );

    var truncated_one = try VorbisPacketReader.init(&.{1}, 0);
    const truncated_one_result = try truncated_one.decodeFloorOne(
        floor_one_setup,
        0,
        &preserved_y,
    );
    try std.testing.expect(!truncated_one_result.used);
    try std.testing.expectEqual(@as(usize, 8), truncated_one.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);

    var preserved_curve = [_]f64{99} ** 4;
    try std.testing.expectError(
        error.InvalidVorbisFloorPacketState,
        synthesizeVorbisFloorOne(
            f64,
            retained_floor_one,
            .{ .used = true, .value_count = 2 },
            y_values[0..2],
            &preserved_curve,
        ),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 99, 99, 99, 99 },
        &preserved_curve,
    );

    var short_floor_output = [_]u32{99};
    var bounded_floor_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.VorbisFloorOutputTooSmall,
        bounded_floor_reader.decodeFloorOne(
            floor_one_setup,
            0,
            &short_floor_output,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), bounded_floor_reader.bit_offset);
    try std.testing.expectEqual(@as(u32, 99), short_floor_output[0]);

    var invalid_floors = floor_one_floors;
    invalid_floors[0].one.x_list[2] = 0;
    var invalid_floor_setup = floor_one_setup;
    invalid_floor_setup.floors = &invalid_floors;
    var invalid_floor_reader = try VorbisPacketReader.init(
        floor_one_audio_storage[0..3],
        0,
    );
    try std.testing.expectError(
        error.InvalidVorbisSetupState,
        invalid_floor_reader.decodeFloorOne(
            invalid_floor_setup,
            0,
            &preserved_y,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), invalid_floor_reader.bit_offset);
    try std.testing.expectEqualSlices(u32, &.{ 99, 99, 99 }, &preserved_y);

    var wrong_type_reader = try VorbisPacketReader.init(&.{0}, 0);
    try std.testing.expectError(
        error.InvalidVorbisFloorType,
        wrong_type_reader.decodeFloorOne(
            floor_zero_setup,
            0,
            &preserved_y,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), wrong_type_reader.bit_offset);
}

test "Vorbis psychoacoustics distinguish tonal and noise-like spectra" {
    try testVorbisPsychoacoustics(f32);
    try testVorbisPsychoacoustics(f64);
}

test "Vorbis multichannel psychoacoustics publish atomically" {
    try testVorbisAudioPsychoacoustics(f32);
    try testVorbisAudioPsychoacoustics(f64);
}

fn testVorbisAudioPsychoacoustics(comptime Float: type) !void {
    const requirements =
        try requiredVorbisAudioPsychoacousticStorage(2, 64);
    try std.testing.expectEqual(@as(usize, 2), requirements.analyses);
    try std.testing.expectEqual(
        @as(usize, 128),
        requirements.floor_values,
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        requirements.threshold_values,
    );
    try std.testing.expectError(
        error.InvalidVorbisChannelCount,
        requiredVorbisAudioPsychoacousticStorage(0, 64),
    );
    try std.testing.expectError(
        error.InvalidVorbisChannelCount,
        requiredVorbisAudioPsychoacousticStorage(256, 64),
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        requiredVorbisAudioPsychoacousticStorage(2, 63),
    );

    var tone = [_]Float{0} ** 64;
    tone[7] = 1;
    const silence = [_]Float{0} ** 64;
    const spectra = [_][]const Float{ &tone, &silence };
    var scratch_floor: [128]Float = undefined;
    var scratch_thresholds: [128]Float = undefined;
    const sentinel_analysis = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 71,
        .peak = 72,
        .rms = 73,
        .spectral_flatness = 74,
        .tonality = 75,
        .masking_relaxation_db = 76,
    };
    var retained_analyses =
        [_]VorbisPsychoacousticAnalysis{sentinel_analysis} ** 3;
    var retained_floor = [_]Float{91} ** 129;
    var retained_thresholds = [_]Float{92} ** 129;
    const plan = try analyzeVorbisAudioPsychoacoustics(
        Float,
        &spectra,
        48_000,
        .{ .absolute_threshold = 0.000_000_001 },
        .{
            .floor_targets = &scratch_floor,
            .noise_thresholds = &scratch_thresholds,
        },
        .{
            .analyses = &retained_analyses,
            .floor_targets = &retained_floor,
            .noise_thresholds = &retained_thresholds,
        },
    );
    try std.testing.expectEqual(@as(usize, 2), plan.analyses.len);
    try std.testing.expectEqual(
        @as(usize, 128),
        plan.floor_targets.len,
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        plan.noise_thresholds.len,
    );
    try std.testing.expectEqual(@as(usize, 64), plan.coefficient_count);
    try std.testing.expectEqual(
        @intFromPtr(retained_analyses[0..2].ptr),
        @intFromPtr(plan.analyses.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor[0..128].ptr),
        @intFromPtr(plan.floor_targets.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_thresholds[0..128].ptr),
        @intFromPtr(plan.noise_thresholds.ptr),
    );
    try std.testing.expect(!plan.analyses[0].silent);
    try std.testing.expect(plan.analyses[1].silent);
    for (
        plan.floor_targets[64..],
        plan.noise_thresholds[64..],
    ) |floor_value, threshold| {
        try std.testing.expectEqual(@as(Float, 0), floor_value);
        try std.testing.expectEqual(@as(Float, 0), threshold);
    }
    try std.testing.expectEqual(sentinel_analysis, retained_analyses[2]);
    try std.testing.expectEqual(@as(Float, 91), retained_floor[128]);
    try std.testing.expectEqual(
        @as(Float, 92),
        retained_thresholds[128],
    );

    const preserved_analyses = retained_analyses;
    const preserved_floor = retained_floor;
    const preserved_thresholds = retained_thresholds;
    var invalid = silence;
    invalid[63] = std.math.nan(Float);
    const invalid_spectra =
        [_][]const Float{ &tone, &invalid };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &invalid_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        VorbisPsychoacousticAnalysis,
        &preserved_analyses,
        &retained_analyses,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_floor,
        &retained_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_thresholds,
        &retained_thresholds,
    );

    const short_spectra =
        [_][]const Float{ &tone, silence[0..32] };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumBundle,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &short_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPsychoacousticScratchTooSmall,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = scratch_floor[0..127],
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPsychoacousticStorageTooSmall,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = retained_analyses[0..1],
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisAudioPsychoacousticStorage,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_floor,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );

    var aliased_floor = [_]Float{0} ** 128;
    aliased_floor[7] = 1;
    const aliased_spectra = [_][]const Float{
        aliased_floor[0..64],
        &silence,
    };
    try std.testing.expectError(
        error.OverlappingVorbisAudioPsychoacousticStorage,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &aliased_spectra,
            48_000,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &aliased_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSampleRate,
        analyzeVorbisAudioPsychoacoustics(
            Float,
            &spectra,
            0,
            .{},
            .{
                .floor_targets = &scratch_floor,
                .noise_thresholds = &scratch_thresholds,
            },
            .{
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
}

fn testVorbisPsychoacoustics(comptime Float: type) !void {
    var tone = [_]Float{0} ** 64;
    tone[7] = 1;
    var tone_floor: [64]Float = undefined;
    var tone_threshold: [64]Float = undefined;
    const tone_analysis = try analyzeVorbisPsychoacoustics(
        Float,
        &tone,
        48_000,
        .{ .absolute_threshold = 0.000_000_001 },
        &tone_floor,
        &tone_threshold,
    );
    try std.testing.expect(!tone_analysis.silent);
    try std.testing.expectEqual(@as(f64, 1), tone_analysis.peak);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.125),
        tone_analysis.rms,
        16 * std.math.floatEps(f64),
    );
    try std.testing.expect(tone_analysis.spectral_flatness < 0.001);
    try std.testing.expect(tone_analysis.tonality > 0.999);
    try std.testing.expect(tone_analysis.active_band_count > 0);
    for (tone_floor, tone_threshold) |floor_value, threshold| {
        try std.testing.expect(std.math.isFinite(floor_value));
        try std.testing.expect(std.math.isFinite(threshold));
        try std.testing.expect(floor_value >= threshold);
        try std.testing.expect(threshold > 0);
    }

    const noise_like = [_]Float{1} ** 64;
    var noise_floor: [64]Float = undefined;
    var high_quality_threshold: [64]Float = undefined;
    const noise_analysis = try analyzeVorbisPsychoacoustics(
        Float,
        &noise_like,
        48_000,
        .{
            .absolute_threshold = 0.000_000_001,
            .quality = 1,
        },
        &noise_floor,
        &high_quality_threshold,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1),
        noise_analysis.spectral_flatness,
        16 * std.math.floatEps(f64),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0),
        noise_analysis.tonality,
        16 * std.math.floatEps(f64),
    );
    var relaxed_floor: [64]Float = undefined;
    var relaxed_threshold: [64]Float = undefined;
    const relaxed = try analyzeVorbisPsychoacoustics(
        Float,
        &noise_like,
        48_000,
        .{
            .absolute_threshold = 0.000_000_001,
            .quality = 0,
        },
        &relaxed_floor,
        &relaxed_threshold,
    );
    try std.testing.expectEqual(
        @as(f64, 18),
        relaxed.masking_relaxation_db,
    );
    for (relaxed_threshold, high_quality_threshold) |
        relaxed_value,
        high_quality_value,
    | {
        try std.testing.expect(relaxed_value >= high_quality_value);
    }

    const within_mask = try evaluateVorbisRateDistortion(
        Float,
        &.{ 0, 0, 0, 0 },
        &.{ 0.5, -0.5, 0.5, -0.5 },
        &.{ 1, 1, 1, 1 },
    );
    try std.testing.expect(within_mask.within_mask);
    try std.testing.expectEqual(
        @as(f64, 0.5),
        within_mask.maximum_noise_ratio,
    );
    try std.testing.expectEqual(
        @as(f64, 1),
        within_mask.weighted_squared_error,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        within_mask.audible_excess_power,
    );
    const outside_mask = try evaluateVorbisRateDistortion(
        Float,
        &.{ 0, 0 },
        &.{ 2, 0 },
        &.{ 1, 1 },
    );
    try std.testing.expect(!outside_mask.within_mask);
    try std.testing.expectEqual(
        @as(f64, 2),
        outside_mask.maximum_noise_ratio,
    );
    try std.testing.expectEqual(
        @as(f64, 3),
        outside_mask.audible_excess_power,
    );
    const zero_threshold = try evaluateVorbisRateDistortion(
        Float,
        &.{0},
        &.{1},
        &.{0},
    );
    try std.testing.expect(!zero_threshold.within_mask);
    try std.testing.expect(std.math.isInf(
        zero_threshold.maximum_noise_ratio,
    ));
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        evaluateVorbisRateDistortion(
            Float,
            &.{0},
            &.{0},
            &.{-1},
        ),
    );

    var silent_floor = [_]Float{9} ** 64;
    var silent_threshold = [_]Float{8} ** 64;
    const silence = try analyzeVorbisPsychoacoustics(
        Float,
        &([_]Float{0} ** 64),
        48_000,
        .{},
        &silent_floor,
        &silent_threshold,
    );
    try std.testing.expect(silence.silent);
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 64),
        &silent_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 64),
        &silent_threshold,
    );

    var in_place = tone;
    var in_place_threshold: [64]Float = undefined;
    _ = try analyzeVorbisPsychoacoustics(
        Float,
        &in_place,
        48_000,
        .{},
        &in_place,
        &in_place_threshold,
    );
    try std.testing.expect(in_place[7] > 0);

    var preserved_floor = [_]Float{7} ** 64;
    var preserved_threshold = [_]Float{8} ** 64;
    var invalid = tone;
    invalid[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        analyzeVorbisPsychoacoustics(
            Float,
            &invalid,
            48_000,
            .{},
            &preserved_floor,
            &preserved_threshold,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{7} ** 64),
        &preserved_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{8} ** 64),
        &preserved_threshold,
    );
    try std.testing.expectError(
        error.OverlappingVorbisPsychoacousticOutput,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            48_000,
            .{},
            &preserved_floor,
            &preserved_floor,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPsychoacousticConfig,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            48_000,
            .{ .quality = 1.1 },
            &preserved_floor,
            &preserved_threshold,
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        analyzeVorbisPsychoacoustics(
            Float,
            tone[0..63],
            48_000,
            .{},
            preserved_floor[0..63],
            preserved_threshold[0..63],
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisSampleRate,
        analyzeVorbisPsychoacoustics(
            Float,
            &tone,
            0,
            .{},
            &preserved_floor,
            &preserved_threshold,
        ),
    );
}

test "Vorbis bit reservoir budgets and commits packet rates" {
    var reservoir = try VorbisBitReservoir.init(.{
        .target_bitrate = 48_000,
        .reservoir_capacity_bits = 256,
        .minimum_packet_bits = 32,
        .maximum_packet_bits = 256,
        .correction_window_packets = 4,
    });
    const first = try reservoir.plan(48_000, 128);
    try std.testing.expectEqual(
        VorbisPacketBitBudget{
            .packet_index = 0,
            .nominal_bits = 128,
            .target_bits = 128,
            .reservoir_balance_before = 0,
        },
        first,
    );
    var residue_budgets = [_]u32{ 99, 99, 99, 99 };
    try std.testing.expectEqual(
        VorbisResidueBitAllocation{
            .packet_target_bits = 128,
            .fixed_packet_bits = 28,
            .residue_bits = 100,
        },
        try allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, 2, 1 },
            &residue_budgets,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 25, 50, 25, 99 },
        &residue_budgets,
    );
    _ = try allocateVorbisResidueBitBudgets(
        .{
            .packet_index = 0,
            .nominal_bits = 5,
            .target_bits = 5,
            .reservoir_balance_before = 0,
        },
        0,
        &.{ 0, 0, 0 },
        &residue_budgets,
    );
    try std.testing.expectEqualSlices(
        u32,
        &.{ 2, 2, 1, 99 },
        &residue_budgets,
    );
    const preserved_residue_budgets = residue_budgets;
    try std.testing.expectError(
        error.InvalidVorbisResidueBitWeights,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, -1, 1 },
            &residue_budgets,
        ),
    );
    try std.testing.expectEqualSlices(
        u32,
        &preserved_residue_budgets,
        &residue_budgets,
    );
    try std.testing.expectError(
        error.VorbisResidueBitBudgetOutputTooSmall,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &.{ 1, 1, 1 },
            residue_budgets[0..2],
        ),
    );
    try std.testing.expectError(
        error.VorbisPacketBudgetBelowFixedCost,
        allocateVorbisResidueBitBudgets(
            first,
            129,
            &.{1},
            &residue_budgets,
        ),
    );
    var aliased_weights = [_]f64{ 1, 1, 1 };
    const aliased_destination = std.mem.bytesAsSlice(
        u32,
        std.mem.sliceAsBytes(&aliased_weights),
    );
    try std.testing.expectError(
        error.OverlappingVorbisResidueBitBudgets,
        allocateVorbisResidueBitBudgets(
            first,
            28,
            &aliased_weights,
            aliased_destination,
        ),
    );
    try std.testing.expectError(
        error.VorbisRateBudgetAlreadyPending,
        reservoir.plan(48_000, 128),
    );
    const first_commit = try reservoir.commit(64);
    try std.testing.expectEqual(
        VorbisRateCommit{
            .packet_index = 0,
            .actual_bits = 64,
            .reservoir_balance_after = 64,
        },
        first_commit,
    );

    const second = try reservoir.plan(48_000, 128);
    try std.testing.expectEqual(@as(u32, 144), second.target_bits);
    _ = try reservoir.commit(160);
    try std.testing.expectEqual(@as(i64, 32), reservoir.balance_bits);
    const third = try reservoir.plan(48_000, 128);
    try std.testing.expectEqual(@as(u32, 136), third.target_bits);
    const before_excess = reservoir;
    try std.testing.expectError(
        error.VorbisBitReservoirExceeded,
        reservoir.commit(1_000),
    );
    try std.testing.expectEqualDeep(before_excess, reservoir);
    try reservoir.cancel();
    try std.testing.expectEqual(@as(?VorbisPacketBitBudget, null), reservoir.pending);
    try std.testing.expectError(
        error.VorbisRateBudgetNotPending,
        reservoir.commit(128),
    );
    try std.testing.expectError(
        error.VorbisRateBudgetNotPending,
        reservoir.cancel(),
    );
    var corrupt = reservoir;
    corrupt.pending = .{
        .packet_index = corrupt.packet_index + 1,
        .nominal_bits = 128,
        .target_bits = 128,
        .reservoir_balance_before = corrupt.balance_bits,
    };
    const corrupt_before = corrupt;
    try std.testing.expectError(
        error.InvalidVorbisBitReservoirState,
        corrupt.commit(128),
    );
    try std.testing.expectEqualDeep(corrupt_before, corrupt);

    const clamped = try VorbisBitReservoir.init(.{
        .target_bitrate = 48_000,
        .reservoir_capacity_bits = 128,
        .minimum_packet_bits = 140,
        .maximum_packet_bits = 150,
    });
    var mutable_clamped = clamped;
    try std.testing.expectEqual(
        @as(u32, 140),
        (try mutable_clamped.plan(48_000, 128)).target_bits,
    );
    mutable_clamped.reset();
    try std.testing.expectEqual(@as(u64, 0), mutable_clamped.packet_index);
    try std.testing.expectEqual(@as(i64, 0), mutable_clamped.balance_bits);

    try std.testing.expectError(
        error.InvalidVorbisRateControlConfig,
        VorbisBitReservoir.init(.{
            .target_bitrate = 0,
            .reservoir_capacity_bits = 0,
        }),
    );
    try std.testing.expectError(
        error.InvalidVorbisRateInterval,
        reservoir.plan(0, 128),
    );
    reservoir.packet_index = std.math.maxInt(u64);
    try std.testing.expectError(
        error.VorbisAudioPacketCountOverflow,
        reservoir.plan(48_000, 128),
    );
}

test "Vorbis adaptive rate policy shifts bounded packet targets" {
    const rate_control = VorbisRateControlConfig{
        .target_bitrate = 96_000,
        .reservoir_capacity_bits = 500,
        .minimum_packet_bits = 100,
        .maximum_packet_bits = 2_000,
    };
    const budget = VorbisPacketBitBudget{
        .packet_index = 7,
        .nominal_bits = 1_000,
        .target_bits = 1_000,
        .reservoir_balance_before = 0,
    };
    const quiet = try adaptVorbisPacketBitBudget(
        budget,
        .{
            .analysis = .{
                .recommended_large_block = true,
                .peak = 0,
                .rms = 0,
                .maximum_energy_ratio = 1,
                .transient_segment = null,
            },
            .recommended_large_block = true,
            .cross_block_energy_ratio = 1,
            .short_blocks_remaining = 0,
        },
        rate_control,
        .{},
    );
    try std.testing.expectEqual(@as(u32, 600), quiet.budget.target_bits);
    try std.testing.expectEqual(@as(f64, 0), quiet.complexity);
    try std.testing.expectEqual(@as(f64, 0.6), quiet.target_scale);

    const complex = try adaptVorbisPacketBitBudget(
        budget,
        .{
            .analysis = .{
                .recommended_large_block = false,
                .peak = 1.5,
                .rms = 0.25,
                .maximum_energy_ratio = 8,
                .transient_segment = 1,
            },
            .recommended_large_block = false,
            .cross_block_energy_ratio = 8,
            .short_blocks_remaining = 2,
        },
        rate_control,
        .{},
    );
    try std.testing.expectEqual(@as(u32, 1_400), complex.budget.target_bits);
    try std.testing.expectEqual(@as(f64, 1), complex.activity);
    try std.testing.expectEqual(@as(f64, 1), complex.transient);
    try std.testing.expectEqual(@as(f64, 1), complex.crest);
    try std.testing.expectEqual(@as(f64, 1), complex.complexity);
    try std.testing.expectEqual(@as(f64, 1.4), complex.target_scale);

    const constrained = try adaptVorbisPacketBitBudget(
        .{
            .packet_index = 8,
            .nominal_bits = 100,
            .target_bits = 100,
            .reservoir_balance_before = -90,
        },
        complexAnalysisForVorbisRateTest(),
        .{
            .target_bitrate = 48_000,
            .reservoir_capacity_bits = 100,
            .maximum_packet_bits = 1_000,
        },
        .{},
    );
    try std.testing.expectEqual(@as(u32, 110), constrained.budget.target_bits);

    try std.testing.expectError(
        error.InvalidVorbisAdaptiveRatePolicyConfig,
        adaptVorbisPacketBitBudget(
            budget,
            complexAnalysisForVorbisRateTest(),
            rate_control,
            .{ .transient_weight = 0.8, .crest_weight = 0.3 },
        ),
    );
    var invalid_classification = complexAnalysisForVorbisRateTest();
    invalid_classification.analysis.rms = 2;
    try std.testing.expectError(
        error.InvalidVorbisBlockAnalysis,
        adaptVorbisPacketBitBudget(
            budget,
            invalid_classification,
            rate_control,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPacketBitBudget,
        adaptVorbisPacketBitBudget(
            .{
                .packet_index = 9,
                .nominal_bits = 1_000,
                .target_bits = 99,
                .reservoir_balance_before = 0,
            },
            complexAnalysisForVorbisRateTest(),
            rate_control,
            .{},
        ),
    );
    try std.testing.expectError(
        error.VorbisAdaptiveRateRangeUnavailable,
        adaptVorbisPacketBitBudget(
            .{
                .packet_index = 10,
                .nominal_bits = 100,
                .target_bits = 1_000,
                .reservoir_balance_before = -90,
            },
            complexAnalysisForVorbisRateTest(),
            .{
                .target_bitrate = 48_000,
                .reservoir_capacity_bits = 100,
                .minimum_packet_bits = 1_000,
                .maximum_packet_bits = 2_000,
            },
            .{},
        ),
    );
}

test "Vorbis adaptive rate targets are monotonic across activity and transients" {
    const rate_control = VorbisRateControlConfig{
        .target_bitrate = 128_000,
        .reservoir_capacity_bits = 2_000,
        .minimum_packet_bits = 100,
        .maximum_packet_bits = 4_000,
    };
    const budget = VorbisPacketBitBudget{
        .packet_index = 11,
        .nominal_bits = 2_000,
        .target_bits = 2_000,
        .reservoir_balance_before = 0,
    };
    var prior_activity_target: u32 = 0;
    for (0..17) |activity_index| {
        const activity =
            @as(f64, @floatFromInt(activity_index)) / 16;
        const rms = 0.000_1 + activity * (0.25 - 0.000_1);
        var prior_transient_target: u32 = 0;
        for (0..17) |transient_index| {
            const transient =
                @as(f64, @floatFromInt(transient_index)) / 16;
            const ratio = std.math.pow(f64, 8, transient);
            const decision = try adaptVorbisPacketBitBudget(
                budget,
                .{
                    .analysis = .{
                        .recommended_large_block = transient == 0,
                        .peak = rms,
                        .rms = rms,
                        .maximum_energy_ratio = ratio,
                        .transient_segment = if (transient == 0)
                            null
                        else
                            1,
                    },
                    .recommended_large_block = transient == 0,
                    .cross_block_energy_ratio = ratio,
                    .short_blocks_remaining = 0,
                },
                rate_control,
                .{},
            );
            try std.testing.expect(
                decision.budget.target_bits >= prior_transient_target,
            );
            try std.testing.expect(
                decision.budget.target_bits >=
                    rate_control.minimum_packet_bits,
            );
            try std.testing.expect(
                decision.budget.target_bits <=
                    rate_control.maximum_packet_bits,
            );
            prior_transient_target = decision.budget.target_bits;
            if (transient_index == 0) {
                try std.testing.expect(
                    decision.budget.target_bits >=
                        prior_activity_target,
                );
                prior_activity_target = decision.budget.target_bits;
            }
        }
    }
}

fn complexAnalysisForVorbisRateTest() VorbisPcmBlockClassification {
    return .{
        .analysis = .{
            .recommended_large_block = false,
            .peak = 1.5,
            .rms = 0.25,
            .maximum_energy_ratio = 8,
            .transient_segment = 1,
        },
        .recommended_large_block = false,
        .cross_block_energy_ratio = 8,
        .short_blocks_remaining = 2,
    };
}

test "Vorbis PCM block analysis selects steady and transient blocks" {
    try testVorbisPcmBlockAnalysis(f32);
    try testVorbisPcmBlockAnalysis(f64);
}

test "Vorbis PCM block classifier stabilizes cross-block decisions" {
    try testVorbisPcmBlockClassifier(f32);
    try testVorbisPcmBlockClassifier(f64);
}

fn testVorbisPcmBlockClassifier(comptime Float: type) !void {
    const quiet = [_]Float{0.1} ** 256;
    const loud = [_]Float{1} ** 256;
    const config = VorbisPcmBlockClassifierConfig{
        .cross_block_energy_ratio = 3,
        .stable_energy_ratio = 1.25,
        .energy_smoothing = 1,
        .minimum_short_blocks = 2,
    };
    var classifier = VorbisPcmBlockClassifier{};
    const first = try classifier.classify(
        Float,
        &.{&quiet},
        64,
        256,
        config,
    );
    try std.testing.expect(first.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 1), first.cross_block_energy_ratio);

    const change = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!change.recommended_large_block);
    try std.testing.expect(change.cross_block_energy_ratio > 99);
    try std.testing.expectEqual(
        @as(u8, 2),
        change.short_blocks_remaining,
    );
    const held_one = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!held_one.recommended_large_block);
    try std.testing.expectEqual(
        @as(u8, 1),
        held_one.short_blocks_remaining,
    );
    const held_two = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(!held_two.recommended_large_block);
    try std.testing.expectEqual(
        @as(u8, 0),
        held_two.short_blocks_remaining,
    );
    const released = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        config,
    );
    try std.testing.expect(released.recommended_large_block);

    var within_block = [_]Float{0} ** 256;
    @memset(within_block[128..], 1);
    const attacked = try classifier.classify(
        Float,
        &.{&within_block},
        64,
        256,
        config,
    );
    try std.testing.expect(!attacked.recommended_large_block);
    try std.testing.expectEqual(@as(u8, 2), attacked.short_blocks_remaining);

    const before_invalid = classifier;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierConfig,
        classifier.classify(
            Float,
            &.{&loud},
            64,
            256,
            .{ .stable_energy_ratio = 3 },
        ),
    );
    try std.testing.expectEqualDeep(before_invalid, classifier);
    var non_finite = loud;
    non_finite[255] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        classifier.classify(
            Float,
            &.{&non_finite},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(before_invalid, classifier);

    classifier.smoothed_mean_square = -1;
    const corrupt = classifier;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockClassifierState,
        classifier.classify(
            Float,
            &.{&loud},
            64,
            256,
            config,
        ),
    );
    try std.testing.expectEqualDeep(corrupt, classifier);
    classifier.reset();
    try std.testing.expectEqualDeep(
        VorbisPcmBlockClassifier{},
        classifier,
    );

    const silence = [_]Float{0} ** 256;
    _ = try classifier.classify(
        Float,
        &.{&silence},
        64,
        256,
        .{
            .analysis = .{ .minimum_rms = 0 },
            .energy_smoothing = 1,
        },
    );
    const from_silence = try classifier.classify(
        Float,
        &.{&loud},
        64,
        256,
        .{
            .analysis = .{ .minimum_rms = 0 },
            .energy_smoothing = 1,
        },
    );
    try std.testing.expectEqual(
        std.math.floatMax(f64),
        from_silence.cross_block_energy_ratio,
    );
    try std.testing.expect(!from_silence.recommended_large_block);
}

fn testVorbisPcmBlockAnalysis(comptime Float: type) !void {
    const steady = [_]Float{0.25} ** 256;
    const steady_analysis = try analyzeVorbisPcmBlock(
        Float,
        &.{&steady},
        64,
        256,
        .{},
    );
    try std.testing.expect(steady_analysis.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 0.25), steady_analysis.peak);
    try std.testing.expectEqual(@as(f64, 0.25), steady_analysis.rms);
    try std.testing.expectEqual(
        @as(f64, 1),
        steady_analysis.maximum_energy_ratio,
    );
    try std.testing.expectEqual(
        @as(?u16, null),
        steady_analysis.transient_segment,
    );

    var attack = [_]Float{0} ** 256;
    @memset(attack[128..], 1);
    const silent_channel = [_]Float{0} ** 256;
    const attack_analysis = try analyzeVorbisPcmBlock(
        Float,
        &.{ &attack, &silent_channel },
        64,
        256,
        .{},
    );
    try std.testing.expect(!attack_analysis.recommended_large_block);
    try std.testing.expectEqual(@as(f64, 1), attack_analysis.peak);
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 0.25)),
        attack_analysis.rms,
        8 * std.math.floatEps(f64),
    );
    try std.testing.expectEqual(
        @as(?u16, 4),
        attack_analysis.transient_segment,
    );
    try std.testing.expect(
        attack_analysis.maximum_energy_ratio >= 1_000_000,
    );

    const no_switch = try analyzeVorbisPcmBlock(
        Float,
        &.{steady[0..64]},
        64,
        64,
        .{},
    );
    try std.testing.expect(!no_switch.recommended_large_block);
    const zero_floor = try analyzeVorbisPcmBlock(
        Float,
        &.{&([_]Float{0} ** 256)},
        64,
        256,
        .{ .minimum_rms = 0 },
    );
    try std.testing.expect(zero_floor.recommended_large_block);
    try std.testing.expectEqual(
        @as(f64, 1),
        zero_floor.maximum_energy_ratio,
    );

    try std.testing.expectError(
        error.InvalidVorbisBlockAnalysisConfig,
        analyzeVorbisPcmBlock(
            Float,
            &.{&steady},
            64,
            256,
            .{ .transient_energy_ratio = 1 },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisBlockSizes,
        analyzeVorbisPcmBlock(
            Float,
            &.{&steady},
            63,
            256,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        analyzeVorbisPcmBlock(
            Float,
            &.{steady[0..255]},
            64,
            256,
            .{},
        ),
    );
    var non_finite = steady;
    non_finite[255] = std.math.inf(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        analyzeVorbisPcmBlock(
            Float,
            &.{&non_finite},
            64,
            256,
            .{},
        ),
    );
}

test "Vorbis encoding block plans select retained modes" {
    var packet_storage: [128]u8 = undefined;
    const packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var parsed_modes: [1]VorbisMode = undefined;
    var setup = try parseVorbisSetup(packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &parsed_modes,
    });
    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    setup.modes = &modes;
    setup.summary.mode_count = modes.len;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };

    try std.testing.expectEqual(
        @as(u8, 0),
        try selectVorbisEncodingMode(setup, 0, false),
    );
    try std.testing.expectEqual(
        @as(u8, 1),
        try selectVorbisEncodingMode(setup, 0, true),
    );
    const small = try planVorbisEncodingBlock(
        identification,
        setup,
        0,
        true,
        false,
        true,
    );
    try std.testing.expectEqual(@as(u8, 0), small.mode_number);
    try std.testing.expect(!small.large_block);
    try std.testing.expectEqual(@as(?bool, null), small.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, null), small.next_window_flag);
    try std.testing.expectEqual(@as(u16, 64), small.block_size);
    try std.testing.expectEqual(@as(usize, 2), small.payload_bit_offset);

    const large = try planVorbisEncodingBlock(
        identification,
        setup,
        0,
        false,
        true,
        true,
    );
    try std.testing.expectEqual(@as(u8, 1), large.mode_number);
    try std.testing.expect(large.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        large.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        large.next_window_flag,
    );
    try std.testing.expectEqual(@as(u16, 256), large.block_size);
    try std.testing.expectEqual(@as(usize, 4), large.payload_bit_offset);

    var small_only = setup;
    small_only.modes = modes[0..1];
    small_only.summary.mode_count = 1;
    try std.testing.expectError(
        error.VorbisEncodingModeUnavailable,
        selectVorbisEncodingMode(small_only, 0, true),
    );
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        selectVorbisEncodingMode(setup, 1, false),
    );
    var invalid_identification = identification;
    invalid_identification.small_block_size = 63;
    try std.testing.expectError(
        error.InvalidVorbisIdentificationState,
        planVorbisEncodingBlock(
            invalid_identification,
            setup,
            0,
            false,
            true,
            true,
        ),
    );

    var frames = VorbisPcmFramePlanner.init(true);
    const large_to_small = try frames.plan(
        identification,
        setup,
        0,
        true,
        false,
    );
    try std.testing.expectEqual(
        @as(u64, 0),
        large_to_small.packet_index,
    );
    try std.testing.expectEqual(
        @as(i64, -128),
        large_to_small.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 80),
        large_to_small.pcm_advance,
    );
    try std.testing.expectEqual(
        @as(i64, 80),
        large_to_small.next_center,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        large_to_small.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        large_to_small.header.next_window_flag,
    );
    const short = try frames.plan(
        identification,
        setup,
        0,
        false,
        false,
    );
    try std.testing.expectEqual(@as(i64, 48), short.source_start);
    try std.testing.expectEqual(@as(u16, 32), short.pcm_advance);
    try std.testing.expectEqual(@as(i64, 112), short.next_center);
    const small_to_large = try frames.plan(
        identification,
        setup,
        0,
        false,
        true,
    );
    try std.testing.expectEqual(
        @as(i64, 80),
        small_to_large.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 80),
        small_to_large.pcm_advance,
    );
    const sequenced_large = try frames.plan(
        identification,
        setup,
        0,
        true,
        true,
    );
    try std.testing.expectEqual(
        @as(i64, 64),
        sequenced_large.source_start,
    );
    try std.testing.expectEqual(
        @as(u16, 128),
        sequenced_large.pcm_advance,
    );
    try std.testing.expectEqual(
        @as(?bool, false),
        sequenced_large.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        sequenced_large.header.next_window_flag,
    );

    const preserved_frames = frames;
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        frames.plan(
            identification,
            setup,
            1,
            true,
            true,
        ),
    );
    try std.testing.expectEqualDeep(preserved_frames, frames);
    frames.center = std.math.maxInt(i64);
    const overflow_state = frames;
    try std.testing.expectError(
        error.VorbisPcmFramePositionOverflow,
        frames.plan(
            identification,
            setup,
            0,
            true,
            false,
        ),
    );
    try std.testing.expectEqualDeep(overflow_state, frames);
    frames.reset(false);
    try std.testing.expectEqual(
        VorbisPcmFramePlanner.init(false),
        frames,
    );
    frames.packet_index = std.math.maxInt(u64);
    const exhausted_state = frames;
    try std.testing.expectError(
        error.VorbisAudioPacketCountOverflow,
        frames.plan(
            identification,
            setup,
            0,
            false,
            false,
        ),
    );
    try std.testing.expectEqualDeep(exhausted_state, frames);

    const stationary = VorbisPcmBlockAnalysis{
        .recommended_large_block = true,
        .peak = 1,
        .rms = 0.5,
        .maximum_energy_ratio = 1,
        .transient_segment = null,
    };
    const transient = VorbisPcmBlockAnalysis{
        .recommended_large_block = false,
        .peak = 1,
        .rms = 0.5,
        .maximum_energy_ratio = 8,
        .transient_segment = 2,
    };
    var lookahead = VorbisPcmBlockLookahead.init(true);
    try std.testing.expectError(
        error.VorbisBlockLookaheadNotPrimed,
        lookahead.push(
            identification,
            setup,
            0,
            stationary,
        ),
    );
    try lookahead.prime(stationary);
    try std.testing.expectError(
        error.VorbisBlockLookaheadAlreadyPrimed,
        lookahead.prime(transient),
    );
    const lookahead_before_failure = lookahead;
    try std.testing.expectError(
        error.InvalidVorbisMappingNumber,
        lookahead.push(
            identification,
            setup,
            1,
            transient,
        ),
    );
    try std.testing.expectEqualDeep(
        lookahead_before_failure,
        lookahead,
    );
    const scheduled_large = try lookahead.push(
        identification,
        setup,
        0,
        transient,
    );
    try std.testing.expect(scheduled_large.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        scheduled_large.header.next_window_flag,
    );
    const scheduled_small = try lookahead.push(
        identification,
        setup,
        0,
        stationary,
    );
    try std.testing.expect(!scheduled_small.header.large_block);
    const terminal = try lookahead.finish(
        identification,
        setup,
        0,
    );
    try std.testing.expect(terminal.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        terminal.header.previous_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, true),
        terminal.header.next_window_flag,
    );
    try std.testing.expectEqual(
        @as(?bool, null),
        lookahead.pending_large_block,
    );
    try std.testing.expectError(
        error.VorbisBlockLookaheadNotPrimed,
        lookahead.finish(
            identification,
            setup,
            0,
        ),
    );
    lookahead.reset(false);
    try std.testing.expectEqual(
        VorbisPcmBlockLookahead.init(false),
        lookahead,
    );
}

test "Vorbis PCM packet sequence commits only after Ogg append" {
    try testVorbisPcmPacketSequence(f32);
    try testVorbisPcmPacketSequence(f64);
}

fn testVorbisPcmPacketSequence(comptime Float: type) !void {
    var packet_storage: [128]u8 = undefined;
    const setup_packet = makeTestVorbisSetup(
        &packet_storage,
        .unordered,
        true,
        false,
    );
    var codebooks: [1]VorbisCodebook = undefined;
    var entries: [2]VorbisCodebookEntry = undefined;
    var nodes: [1]VorbisHuffmanNode = undefined;
    var multiplicands: [2]u32 = undefined;
    var floors: [1]VorbisFloor = undefined;
    var residues: [1]VorbisResidue = undefined;
    var mappings: [1]VorbisMapping = undefined;
    var parsed_modes: [1]VorbisMode = undefined;
    var setup = try parseVorbisSetup(setup_packet.bytes, 2, .{
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &nodes,
        .codebook_multiplicands = &multiplicands,
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &parsed_modes,
    });
    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    setup.modes = &modes;
    setup.summary.mode_count = modes.len;
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 48_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 256,
    };
    const config = VorbisPcmPacketSequenceConfig{
        .classifier = .{
            .cross_block_energy_ratio = 3,
            .stable_energy_ratio = 1.25,
            .energy_smoothing = 1,
            .minimum_short_blocks = 1,
        },
        .rate_control = .{
            .target_bitrate = 48_000,
            .reservoir_capacity_bits = 2_048,
            .maximum_packet_bits = 2_048,
        },
        .adaptive_rate = .{},
    };
    var invalid_config = config;
    invalid_config.adaptive_rate.?.full_activity_rms =
        invalid_config.adaptive_rate.?.quiet_rms;
    try std.testing.expectError(
        error.InvalidVorbisAdaptiveRatePolicyConfig,
        VorbisPcmPacketSequence.init(invalid_config, true),
    );
    var sequence = try VorbisPcmPacketSequence.init(config, true);
    const steady = [_]Float{0.1} ** 256;
    const primed = try sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    try std.testing.expect(primed.recommended_large_block);
    try std.testing.expectEqual(@as(u64, 1), sequence.revision);

    const before_plan = sequence;
    const loud = [_]Float{1} ** 256;
    const plan = try sequence.planNext(
        Float,
        &.{ &loud, &loud },
        identification,
        setup,
    );
    try std.testing.expectEqualDeep(before_plan, sequence);
    try std.testing.expect(plan.frame.header.large_block);
    try std.testing.expectEqual(
        @as(?bool, false),
        plan.frame.header.next_window_flag,
    );
    try std.testing.expectEqual(@as(u64, 0), plan.granule_position);
    try std.testing.expect(!plan.end);
    try std.testing.expectEqual(@as(u64, 0), plan.budget.packet_index);
    try std.testing.expectEqual(@as(u32, 99), plan.budget.target_bits);
    try std.testing.expectEqualDeep(
        plan.budget,
        plan.reservoir_pending.pending.?,
    );
    try std.testing.expect(
        !plan.classification.?.recommended_large_block,
    );
    var hostile_plan = plan;
    hostile_plan.reservoir_pending.balance_bits = 1;
    hostile_plan.reservoir_pending.pending.?.reservoir_balance_before = 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmPacketPlan,
        sequence.commit(hostile_plan, 1),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketBitCount,
        sequence.commit(plan, 0),
    );
    try std.testing.expectEqualDeep(before_plan, sequence);

    var ogg_storage: [96]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x70636d);
    try writer.appendPacket(&.{1}, 0, true, false);
    const before_failed_append = sequence;
    const writer_before_failed_append = writer;
    const oversized_packet = [_]u8{0} ** 80;
    try std.testing.expectError(
        error.OggOutputTooSmall,
        sequence.appendMemory(
            &writer,
            plan,
            &oversized_packet,
            oversized_packet.len * 8,
        ),
    );
    try std.testing.expectEqualDeep(
        before_failed_append,
        sequence,
    );
    try std.testing.expectEqualDeep(
        writer_before_failed_append,
        writer,
    );

    const first_commit = try sequence.appendMemory(
        &writer,
        plan,
        &.{0},
        1,
    );
    try std.testing.expectEqual(@as(u64, 0), first_commit.rate.packet_index);
    try std.testing.expectEqual(@as(u32, 1), first_commit.rate.actual_bits);
    try std.testing.expectEqual(@as(u64, 2), sequence.revision);
    try std.testing.expectEqual(@as(u64, 1), sequence.reservoir.packet_index);
    try std.testing.expectEqual(@as(u64, 0), sequence.granule_position);

    const after_first_commit = sequence;
    try std.testing.expectError(
        error.StaleVorbisPcmPacketPlan,
        sequence.commit(plan, 1),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    try std.testing.expectError(
        error.InvalidVorbisEncoderGranulePosition,
        sequence.planFinish(
            identification,
            setup,
            81,
        ),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);
    const finish = try sequence.planFinish(
        identification,
        setup,
        80,
    );
    try std.testing.expect(finish.end);
    try std.testing.expectEqual(
        @as(?VorbisPcmBlockClassification, null),
        finish.classification,
    );
    try std.testing.expectEqual(@as(u64, 80), finish.granule_position);
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    try std.testing.expectError(
        error.InvalidVorbisAudioPacketBitCount,
        sequence.appendMemory(&writer, finish, &.{0}, 9),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);
    var invalid_file_writer: FileWriter = undefined;
    invalid_file_writer.failed = true;
    try std.testing.expectError(
        error.InvalidOggFileWriterState,
        sequence.appendFile(
            &invalid_file_writer,
            finish,
            &.{0},
            1,
        ),
    );
    try std.testing.expectEqualDeep(after_first_commit, sequence);

    const terminal_commit = try sequence.appendMemory(
        &writer,
        finish,
        &.{0},
        1,
    );
    try std.testing.expect(terminal_commit.end);
    try std.testing.expect(sequence.ended);
    try std.testing.expect(writer.ended);
    try std.testing.expectEqual(@as(u64, 80), sequence.granule_position);

    var pages = PageIterator.init(writer.bytes());
    var final_page: ?Page = null;
    while (try pages.next()) |page| final_page = page;
    try std.testing.expect(final_page.?.end);
    try std.testing.expectEqual(
        @as(u64, 80),
        final_page.?.granule_position,
    );
    try std.testing.expectError(
        error.VorbisPcmPacketSequenceAlreadyEnded,
        sequence.planFinish(
            identification,
            setup,
            80,
        ),
    );
}

test "Vorbis PCM packet trials encode without advancing sequence state" {
    try testVorbisPcmPacketEncodingTrial(f32);
    try testVorbisPcmPacketEncodingTrial(f64);
}

fn testVorbisPcmPacketEncodingTrial(comptime Float: type) !void {
    const codebook_entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{.{
        .dimensions = 1,
        .entries = 1,
        .entry_offset = 0,
        .active_entry_count = 1,
        .tree_node_offset = 0,
        .tree_node_count = 0,
        .lookup_type = 0,
    }};
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{ .one = .{
        .partition_count = 0,
        .partition_classes = [_]u4{0} ** 31,
        .class_count = 0,
        .classes = [_]VorbisFloorOneClass{.{
            .dimensions = 0,
            .subclass_bits = 0,
            .masterbook = -1,
            .subclass_books = [_]i16{-1} ** 8,
        }} ** 16,
        .multiplier = 1,
        .range_bits = 5,
        .point_count = 2,
        .x_list = x_list,
    } }};
    const residues = [_]VorbisResidue{.{
        .kind = .one,
        .begin = 0,
        .end = 32,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = [_]u8{0} ** 64,
        .books = [_][8]i16{[_]i16{-1} ** 8} ** 64,
    }};
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 0,
        .coupling_steps = [_]VorbisCouplingStep{.{
            .magnitude = 0,
            .angle = 0,
        }} ** 256,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 1,
            .codebook_entry_count = 1,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 1,
        },
        .codebooks = &codebooks,
        .codebook_entries = &codebook_entries,
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 192_000,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    var sequence = try VorbisPcmPacketSequence.init(
        .{
            .classifier = .{
                .cross_block_energy_ratio = 3,
                .stable_energy_ratio = 1.25,
                .energy_smoothing = 1,
                .minimum_short_blocks = 1,
            },
            .rate_control = .{
                .target_bitrate = 192_000,
                .reservoir_capacity_bits = 2_048,
                .maximum_packet_bits = 2_048,
            },
        },
        true,
    );
    const steady = [_]Float{0.1} ** 64;
    _ = try sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    const plan = try sequence.planNext(
        Float,
        &.{ &steady, &steady },
        identification,
        setup,
    );
    const sequence_before = sequence;
    const coefficient_count: usize =
        plan.frame.header.block_size / 2;
    try std.testing.expectEqual(@as(usize, 32), coefficient_count);

    const floor_value =
        vorbisFloorOneInverseDb(Float, 100);
    var spectra: [64]Float = undefined;
    var floor_targets: [64]Float = undefined;
    var thresholds: [64]Float = undefined;
    @memset(&spectra, floor_value * 2);
    @memset(&floor_targets, floor_value);
    @memset(&thresholds, floor_value * 0.1);
    const analysis_value = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 1,
        .peak = 1,
        .rms = 1,
        .spectral_flatness = 0,
        .tonality = 1,
        .masking_relaxation_db = 0,
    };
    const analyses =
        [_]VorbisPsychoacousticAnalysis{analysis_value} ** 2;
    const analysis = VorbisPcmFrameAnalysisPlan(Float){
        .frame = plan.frame,
        .spectra = &spectra,
        .analyses = &analyses,
        .floor_targets = &floor_targets,
        .noise_thresholds = &thresholds,
        .coefficient_count = coefficient_count,
    };
    const requirements =
        try requiredVorbisPcmPacketEncodingStorage(
            identification,
            setup,
            plan.frame,
        );
    try std.testing.expectEqual(
        @as(usize, identification.channel_count),
        requirements.preparation.floor_encodings,
    );
    try std.testing.expectEqual(
        @as(usize, identification.channel_count),
        requirements.quantization.do_not_encode,
    );
    try std.testing.expectEqual(
        @as(usize, mappings[0].submap_count),
        requirements.quantization.encodings,
    );

    var floor_fit_y: [130]u32 = undefined;
    var floor_fit_curves: [256]Float = undefined;
    var preparation_floor_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var preparation_y: [130]u32 = undefined;
    var preparation_curves: [256]Float = undefined;
    var preparation_residue: [256]Float = undefined;
    var preparation_thresholds: [256]Float = undefined;
    var coupling_values: [256]Float = undefined;
    var coupling_thresholds: [256]Float = undefined;
    var preparation_skips: [2]bool = undefined;

    var trial_floor_encodings: [2]VorbisFloorPacketEncoding = undefined;
    var trial_floor_y: [130]u32 = undefined;
    var trial_floor_curves: [256]Float = undefined;
    var trial_residue: [256]Float = undefined;
    var trial_thresholds: [256]Float = undefined;
    var trial_preparation_skips: [2]bool = undefined;

    var partition: [256]Float = undefined;
    var vector: [256]Float = undefined;
    var classifications: [512]u8 = undefined;
    var best_classifications: [512]u8 = undefined;
    var output_classifications: [512]u8 = undefined;
    var quantization_entries: [2_048]u32 = undefined;
    var quantization_skips: [2]bool = undefined;

    var trial_residue_encodings: [16]VorbisResidueEncoding = undefined;
    var trial_submap_results: [16]VorbisAudioResidueSubmapResult = undefined;
    var trial_quantization_skips: [2]bool = undefined;
    var trial_classifications: [512]u8 = undefined;
    var trial_entries: [2_048]u32 = undefined;

    const sentinel_floor = VorbisFloorPacketEncoding{
        .one = .{
            .used = true,
            .y_values = &.{99},
        },
    };
    var retained_floor_encodings =
        [_]VorbisFloorPacketEncoding{sentinel_floor} ** 2;
    var retained_floor_y = [_]u32{91} ** 130;
    var retained_floor_curves = [_]Float{92} ** 256;
    var retained_residue = [_]Float{93} ** 256;
    var retained_thresholds = [_]Float{94} ** 256;
    var retained_preparation_skips = [_]bool{true} ** 2;

    var retained_residue_encodings: [16]VorbisResidueEncoding = undefined;
    var retained_submap_results: [16]VorbisAudioResidueSubmapResult = undefined;
    var retained_quantization_skips = [_]bool{true} ** 2;
    var retained_classifications = [_]u8{95} ** 512;
    var retained_entries = [_]u32{96} ** 2_048;

    const scratch = VorbisPcmPacketEncodingScratch(Float){
        .preparation = .{
            .floor_fit_y_values = &floor_fit_y,
            .floor_fit_curves = &floor_fit_curves,
            .floor_encodings = &preparation_floor_encodings,
            .floor_y_values = &preparation_y,
            .floor_curves = &preparation_curves,
            .residue_values = &preparation_residue,
            .noise_thresholds = &preparation_thresholds,
            .coupling_values = &coupling_values,
            .coupling_thresholds = &coupling_thresholds,
            .do_not_encode = &preparation_skips,
        },
        .preparation_storage = .{
            .floor_encodings = &trial_floor_encodings,
            .floor_y_values = &trial_floor_y,
            .floor_curves = &trial_floor_curves,
            .residue_values = &trial_residue,
            .noise_thresholds = &trial_thresholds,
            .do_not_encode = &trial_preparation_skips,
        },
        .quantization = .{
            .partition = &partition,
            .vector = &vector,
            .classifications = &classifications,
            .best_classifications = &best_classifications,
            .output_classifications = &output_classifications,
            .entries = &quantization_entries,
            .do_not_encode = &quantization_skips,
        },
        .quantization_storage = .{
            .encodings = &trial_residue_encodings,
            .submap_results = &trial_submap_results,
            .do_not_encode = &trial_quantization_skips,
            .classifications = &trial_classifications,
            .entries = &trial_entries,
        },
    };
    const storage = VorbisPcmPacketEncodingStorage(Float){
        .preparation = .{
            .floor_encodings = &retained_floor_encodings,
            .floor_y_values = &retained_floor_y,
            .floor_curves = &retained_floor_curves,
            .residue_values = &retained_residue,
            .noise_thresholds = &retained_thresholds,
            .do_not_encode = &retained_preparation_skips,
        },
        .quantization = .{
            .encodings = &retained_residue_encodings,
            .submap_results = &retained_submap_results,
            .do_not_encode = &retained_quantization_skips,
            .classifications = &retained_classifications,
            .entries = &retained_entries,
        },
    };
    var packet = [_]u8{97} ** 256;
    const floor_before = retained_floor_encodings;
    const y_before = retained_floor_y;
    const residue_before = retained_residue;
    const classifications_before = retained_classifications;
    var invalid_analysis = analysis;
    invalid_analysis.coefficient_count -= 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmFrameAnalysisPlan,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            invalid_analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    var short_scratch = scratch;
    short_scratch.preparation_storage.floor_y_values =
        trial_floor_y[0 .. requirements.preparation.floor_y_values - 1];
    try std.testing.expectError(
        error.VorbisPcmPacketEncodingScratchTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            short_scratch,
            storage,
        ),
    );
    var short_storage = storage;
    short_storage.quantization.classifications =
        retained_classifications[0 .. requirements.quantization.classifications - 1];
    try std.testing.expectError(
        error.VorbisPcmPacketEncodingStorageTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            short_storage,
        ),
    );
    var aliased_storage = storage;
    aliased_storage.preparation.residue_values = &trial_residue;
    try std.testing.expectError(
        error.OverlappingVorbisPcmPacketEncodingStorage,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            aliased_storage,
        ),
    );
    try std.testing.expectError(
        error.VorbisAudioPacketOutputTooSmall,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            packet[0..0],
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(floor_before, retained_floor_encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &retained_floor_y);
    try std.testing.expectEqualSlices(
        Float,
        &residue_before,
        &retained_residue,
    );
    try std.testing.expectEqualSlices(
        u8,
        &classifications_before,
        &retained_classifications,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(@as(u8, 97), packet[0]);

    var constrained_sequence = try VorbisPcmPacketSequence.init(
        .{
            .classifier = .{
                .cross_block_energy_ratio = 3,
                .stable_energy_ratio = 1.25,
                .energy_smoothing = 1,
                .minimum_short_blocks = 1,
            },
            .rate_control = .{
                .target_bitrate = 54_000,
                .reservoir_capacity_bits = 32,
                .maximum_packet_bits = 2_048,
            },
        },
        true,
    );
    _ = try constrained_sequence.prime(
        Float,
        &.{ &steady, &steady },
        identification,
    );
    const constrained_plan = try constrained_sequence.planNext(
        Float,
        &.{ &steady, &steady },
        identification,
        setup,
    );
    var constrained_analysis = analysis;
    constrained_analysis.frame = constrained_plan.frame;
    const constrained_before = constrained_sequence;
    try std.testing.expectError(
        error.VorbisBitReservoirExceeded,
        encodeVorbisPcmPacketTrial(
            Float,
            &constrained_sequence,
            identification,
            setup,
            constrained_plan,
            constrained_analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(
        constrained_before,
        constrained_sequence,
    );
    try std.testing.expectEqual(@as(u8, 97), packet[0]);
    try std.testing.expectEqualDeep(floor_before, retained_floor_encodings);
    try std.testing.expectEqualSlices(u32, &y_before, &retained_floor_y);

    const Analyzer = VorbisPcmFrameAnalyzer(Float, 2, 64, 64);
    var analyzer = Analyzer.init();
    var analysis_pcm: [128]Float = undefined;
    var analysis_transform: [64]Float = undefined;
    var analysis_spectrum_scratch: [64]Float = undefined;
    var analysis_floor_scratch: [64]Float = undefined;
    var analysis_threshold_scratch: [64]Float = undefined;
    var analysis_spectra: [64]Float = undefined;
    var analysis_values: [2]VorbisPsychoacousticAnalysis = undefined;
    var analysis_floor: [64]Float = undefined;
    var analysis_thresholds: [64]Float = undefined;
    const orchestration_scratch =
        VorbisPcmPacketOrchestrationScratch(Float){
            .analysis = .{
                .pcm = &analysis_pcm,
                .transform = &analysis_transform,
                .spectra = &analysis_spectrum_scratch,
                .floor_targets = &analysis_floor_scratch,
                .noise_thresholds = &analysis_threshold_scratch,
            },
            .analysis_storage = .{
                .spectra = &analysis_spectra,
                .analyses = &analysis_values,
                .floor_targets = &analysis_floor,
                .noise_thresholds = &analysis_thresholds,
            },
            .encoding = scratch,
        };
    var invalid_identification = identification;
    invalid_identification.channel_count = 1;
    try std.testing.expectError(
        error.InvalidVorbisPcmEncoderConfiguration,
        encodeVorbisPcmPacket(
            Float,
            2,
            64,
            64,
            &analyzer,
            &sequence,
            invalid_identification,
            setup,
            plan,
            &.{ &steady, &steady },
            .{},
            &.{1},
            .{},
            &packet,
            orchestration_scratch,
            storage,
        ),
    );
    var short_orchestration_scratch = orchestration_scratch;
    short_orchestration_scratch.analysis_storage.analyses =
        analysis_values[0..1];
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisStorageTooSmall,
        encodeVorbisPcmPacket(
            Float,
            2,
            64,
            64,
            &analyzer,
            &sequence,
            identification,
            setup,
            plan,
            &.{ &steady, &steady },
            .{},
            &.{1},
            .{},
            &packet,
            short_orchestration_scratch,
            storage,
        ),
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(@as(u8, 97), packet[0]);
    const orchestrated = try encodeVorbisPcmPacket(
        Float,
        2,
        64,
        64,
        &analyzer,
        &sequence,
        identification,
        setup,
        plan,
        &.{ &steady, &steady },
        .{},
        &.{1},
        .{},
        &packet,
        orchestration_scratch,
        storage,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(
        orchestrated.packet.bit_count,
        orchestrated.commit.rate.actual_bits,
    );

    const trial = try encodeVorbisPcmPacketTrial(
        Float,
        &sequence,
        identification,
        setup,
        plan,
        analysis,
        &.{1},
        .{},
        &packet,
        scratch,
        storage,
    );
    try std.testing.expectEqualDeep(sequence_before, sequence);
    try std.testing.expectEqual(
        trial.packet.bit_count,
        trial.commit.rate.actual_bits,
    );
    var residue_bits: u32 = 0;
    for (trial.quantization.submap_results) |result|
        residue_bits += result.encoded_bits;
    try std.testing.expectEqual(
        trial.packet.bit_count,
        trial.preparation.fixed_packet_bits + residue_bits,
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor_encodings[0..].ptr),
        @intFromPtr(trial.preparation.floor_encodings.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_residue_encodings[0..].ptr),
        @intFromPtr(trial.quantization.encodings.ptr),
    );
    try std.testing.expectEqualSlices(
        u8,
        trial.packet.bytes,
        packet[0..trial.packet.bytes.len],
    );

    var ogg_storage: [2_048]u8 = undefined;
    var writer = StreamWriter.init(&ogg_storage, 0x74726961);
    try writer.appendPacket(&.{1}, 0, true, false);
    const committed = try sequence.appendMemory(
        &writer,
        plan,
        trial.packet.bytes,
        trial.packet.bit_count,
    );
    try std.testing.expectEqualDeep(trial.commit, committed);
    try std.testing.expectEqual(@as(u64, 2), sequence.revision);
    const packet_after = packet;
    const retained_after = retained_floor_y;
    try std.testing.expectError(
        error.StaleVorbisPcmPacketPlan,
        encodeVorbisPcmPacketTrial(
            Float,
            &sequence,
            identification,
            setup,
            plan,
            analysis,
            &.{1},
            .{},
            &packet,
            scratch,
            storage,
        ),
    );
    try std.testing.expectEqualSlices(u8, &packet_after, &packet);
    try std.testing.expectEqualSlices(
        u32,
        &retained_after,
        &retained_floor_y,
    );
}

test "Vorbis PCM frame extraction pads boundaries transactionally" {
    try testVorbisPcmFrameExtraction(f32);
    try testVorbisPcmFrameExtraction(f64);
}

fn testVorbisPcmFrameExtraction(comptime Float: type) !void {
    var left: [100]Float = undefined;
    var right: [100]Float = undefined;
    for (&left, &right, 0..) |*left_value, *right_value, index| {
        const value: Float = @floatFromInt(index + 1);
        left_value.* = value;
        right_value.* = -value;
    }
    var left_output: [64]Float = undefined;
    var right_output: [64]Float = undefined;
    try extractVorbisPcmBlock(
        Float,
        &.{ &left, &right },
        -2,
        64,
        &.{ &left_output, &right_output },
    );
    try std.testing.expectEqual(@as(Float, 0), left_output[0]);
    try std.testing.expectEqual(@as(Float, 0), left_output[1]);
    for (left_output[2..], right_output[2..], 0..) |
        left_value,
        right_value,
        index,
    | {
        const expected: Float = @floatFromInt(index + 1);
        try std.testing.expectEqual(expected, left_value);
        try std.testing.expectEqual(-expected, right_value);
    }

    try extractVorbisPcmBlock(
        Float,
        &.{ &left, &right },
        90,
        64,
        &.{ &left_output, &right_output },
    );
    for (left_output[0..10], right_output[0..10], 0..) |
        left_value,
        right_value,
        index,
    | {
        const expected: Float = @floatFromInt(index + 91);
        try std.testing.expectEqual(expected, left_value);
        try std.testing.expectEqual(-expected, right_value);
    }
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 54),
        left_output[10..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 54),
        right_output[10..],
    );

    @memset(&left_output, 7);
    @memset(&right_output, 8);
    var invalid_right = right;
    invalid_right[99] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, &invalid_right },
            0,
            64,
            &.{ &left_output, &right_output },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{7} ** 64),
        &left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{8} ** 64),
        &right_output,
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        extractVorbisPcmBlock(
            Float,
            &.{&left},
            0,
            64,
            &.{left[0..64]},
        ),
    );
    var shared_output: [64]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, &right },
            0,
            64,
            &.{ &shared_output, &shared_output },
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmFrameRange,
        extractVorbisPcmBlock(
            Float,
            &.{&left},
            std.math.maxInt(i64),
            64,
            &.{&shared_output},
        ),
    );
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        extractVorbisPcmBlock(
            Float,
            &.{ &left, right[0..99] },
            0,
            64,
            &.{ &left_output, &right_output },
        ),
    );
}

test "Vorbis PCM block transforms commit channels transactionally" {
    try testVorbisPcmBlockTransform(f32);
    try testVorbisPcmBlockTransform(f64);
}

fn testVorbisPcmBlockTransform(comptime Float: type) !void {
    const Transform = VorbisPcmBlockTransform(Float, 2, 64, 256);
    var transform = Transform.init();
    const small_header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 2,
    };
    try std.testing.expectEqual(
        @as(usize, 64),
        try Transform.requiredScratch(small_header),
    );
    var left: [64]Float = undefined;
    var right: [64]Float = undefined;
    for (&left, &right, 0..) |*left_value, *right_value, index| {
        const position: Float = @floatFromInt(index);
        left_value.* = @sin(position * 0.17);
        right_value.* = @cos(position * 0.11);
    }
    var left_output = [_]Float{99} ** 32;
    var right_output = [_]Float{99} ** 32;
    var scratch: [64]Float = undefined;
    try transform.process(
        small_header,
        &.{ &left, &right },
        &.{ &left_output, &right_output },
        &scratch,
    );

    const windows = VorbisWindowPlan(Float, 64, 256).init();
    const window = try windows.get(small_header);
    var reference = VorbisForwardMdct(Float, 64).init();
    var expected_left: [32]Float = undefined;
    var expected_right: [32]Float = undefined;
    try reference.processWindowed(&left, window, &expected_left);
    try reference.processWindowed(&right, window, &expected_right);
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        &left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_right,
        &right_output,
    );

    var preserved_left = [_]Float{ 7, 7, 7, 7 } ** 8;
    var preserved_right = [_]Float{ 8, 8, 8, 8 } ** 8;
    var invalid_right = right;
    invalid_right[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        transform.process(
            small_header,
            &.{ &left, &invalid_right },
            &.{ &preserved_left, &preserved_right },
            &scratch,
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{ 7, 7, 7, 7 } ** 8),
        &preserved_left,
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{ 8, 8, 8, 8 } ** 8),
        &preserved_right,
    );
    try std.testing.expectError(
        error.VorbisPcmBlockScratchTooSmall,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &preserved_left, &preserved_right },
            scratch[0..63],
        ),
    );

    var alias_storage: [64]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockScratch,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ alias_storage[0..32], &preserved_right },
            &alias_storage,
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockScratch,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &preserved_left, &preserved_right },
            left[0..],
        ),
    );
    var shared_output: [32]Float = undefined;
    try std.testing.expectError(
        error.OverlappingVorbisPcmBlockOutput,
        transform.process(
            small_header,
            &.{ &left, &right },
            &.{ &shared_output, &shared_output },
            &scratch,
        ),
    );

    const InPlaceTransform =
        VorbisPcmBlockTransform(Float, 1, 64, 256);
    var in_place_transform = InPlaceTransform.init();
    var in_place = left;
    var in_place_scratch: [32]Float = undefined;
    try in_place_transform.process(
        small_header,
        &.{&in_place},
        &.{in_place[0..32]},
        &in_place_scratch,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        in_place[0..32],
    );

    const large_header = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expectEqual(
        @as(usize, 256),
        try Transform.requiredScratch(large_header),
    );
    var large_left: [256]Float = undefined;
    var large_right: [256]Float = undefined;
    for (
        &large_left,
        &large_right,
        0..,
    ) |*left_value, *right_value, index| {
        const position: Float = @floatFromInt(index);
        left_value.* = @sin(position * 0.037);
        right_value.* = @cos(position * 0.061);
    }
    var large_left_output: [128]Float = undefined;
    var large_right_output: [128]Float = undefined;
    var large_scratch: [256]Float = undefined;
    try transform.process(
        large_header,
        &.{ &large_left, &large_right },
        &.{ &large_left_output, &large_right_output },
        &large_scratch,
    );
    const large_window = try windows.get(large_header);
    var large_reference = VorbisForwardMdct(Float, 256).init();
    var expected_large_left: [128]Float = undefined;
    var expected_large_right: [128]Float = undefined;
    try large_reference.processWindowed(
        &large_left,
        large_window,
        &expected_large_left,
    );
    try large_reference.processWindowed(
        &large_right,
        large_window,
        &expected_large_right,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_large_left,
        &large_left_output,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_large_right,
        &large_right_output,
    );
    var invalid_header = large_header;
    invalid_header.next_window_flag = null;
    try std.testing.expectError(
        error.InvalidVorbisWindowState,
        Transform.requiredScratch(invalid_header),
    );
}

test "Vorbis PCM frame analysis composes extraction transform and masking" {
    try testVorbisPcmFrameAnalysis(f32);
    try testVorbisPcmFrameAnalysis(f64);
}

fn testVorbisPcmFrameAnalysis(comptime Float: type) !void {
    const Analyzer = VorbisPcmFrameAnalyzer(Float, 2, 64, 256);
    var analyzer = Analyzer.init();
    const frame = VorbisPcmFramePlan{
        .packet_index = 7,
        .header = .{
            .mode_number = 0,
            .large_block = false,
            .previous_window_flag = null,
            .next_window_flag = null,
            .block_size = 64,
            .payload_bit_offset = 2,
        },
        .source_start = -16,
        .pcm_advance = 32,
        .next_center = 32,
    };
    try std.testing.expectEqual(
        VorbisPcmFrameAnalysisStorageRequirements{
            .pcm_values = 128,
            .transform_values = 64,
            .spectrum_values = 64,
            .analyses = 2,
            .floor_values = 64,
            .threshold_values = 64,
        },
        try Analyzer.requiredStorage(frame.header),
    );
    const large_header = VorbisAudioPacketHeader{
        .mode_number = 1,
        .large_block = true,
        .previous_window_flag = false,
        .next_window_flag = true,
        .block_size = 256,
        .payload_bit_offset = 4,
    };
    try std.testing.expectEqual(
        VorbisPcmFrameAnalysisStorageRequirements{
            .pcm_values = 512,
            .transform_values = 256,
            .spectrum_values = 256,
            .analyses = 2,
            .floor_values = 256,
            .threshold_values = 256,
        },
        try Analyzer.requiredStorage(large_header),
    );

    var left: [64]Float = undefined;
    for (&left, 0..) |*sample, index| {
        sample.* = @sin(@as(Float, @floatFromInt(index)) * 0.17);
    }
    const right = [_]Float{0} ** 64;
    const inputs = [_][]const Float{ &left, &right };
    var pcm_scratch: [128]Float = undefined;
    var transform_scratch: [64]Float = undefined;
    var spectrum_scratch: [64]Float = undefined;
    var floor_scratch: [64]Float = undefined;
    var threshold_scratch: [64]Float = undefined;
    const sentinel_analysis = VorbisPsychoacousticAnalysis{
        .silent = false,
        .active_band_count = 81,
        .peak = 82,
        .rms = 83,
        .spectral_flatness = 84,
        .tonality = 85,
        .masking_relaxation_db = 86,
    };
    var retained_spectra = [_]Float{91} ** 65;
    var retained_analyses =
        [_]VorbisPsychoacousticAnalysis{sentinel_analysis} ** 3;
    var retained_floor = [_]Float{92} ** 65;
    var retained_thresholds = [_]Float{93} ** 65;
    const plan = try analyzer.analyze(
        &inputs,
        frame,
        .{ .absolute_threshold = 0.000_000_001 },
        48_000,
        .{
            .pcm = &pcm_scratch,
            .transform = &transform_scratch,
            .spectra = &spectrum_scratch,
            .floor_targets = &floor_scratch,
            .noise_thresholds = &threshold_scratch,
        },
        .{
            .spectra = &retained_spectra,
            .analyses = &retained_analyses,
            .floor_targets = &retained_floor,
            .noise_thresholds = &retained_thresholds,
        },
    );
    try std.testing.expectEqual(frame, plan.frame);
    try std.testing.expectEqual(@as(usize, 32), plan.coefficient_count);
    try std.testing.expectEqual(@as(usize, 64), plan.spectra.len);
    try std.testing.expectEqual(@as(usize, 2), plan.analyses.len);
    try std.testing.expectEqual(
        @intFromPtr(retained_spectra[0..64].ptr),
        @intFromPtr(plan.spectra.ptr),
    );
    try std.testing.expectEqual(
        @intFromPtr(retained_floor[0..64].ptr),
        @intFromPtr(plan.floor_targets.ptr),
    );
    try std.testing.expect(!plan.analyses[0].silent);
    try std.testing.expect(plan.analyses[1].silent);
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.spectra[32..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.floor_targets[32..],
    );
    try std.testing.expectEqualSlices(
        Float,
        &([_]Float{0} ** 32),
        plan.noise_thresholds[32..],
    );
    var expected_pcm_left: [64]Float = undefined;
    var expected_pcm_right: [64]Float = undefined;
    try extractVorbisPcmBlock(
        Float,
        &inputs,
        frame.source_start,
        frame.header.block_size,
        &.{ &expected_pcm_left, &expected_pcm_right },
    );
    var reference_transform =
        VorbisPcmBlockTransform(Float, 2, 64, 256).init();
    var expected_left: [32]Float = undefined;
    var expected_right: [32]Float = undefined;
    var reference_scratch: [64]Float = undefined;
    try reference_transform.process(
        frame.header,
        &.{ &expected_pcm_left, &expected_pcm_right },
        &.{ &expected_left, &expected_right },
        &reference_scratch,
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_left,
        plan.spectra[0..32],
    );
    try std.testing.expectEqualSlices(
        Float,
        &expected_right,
        plan.spectra[32..64],
    );
    try std.testing.expectEqual(@as(Float, 91), retained_spectra[64]);
    try std.testing.expectEqual(sentinel_analysis, retained_analyses[2]);
    try std.testing.expectEqual(@as(Float, 92), retained_floor[64]);
    try std.testing.expectEqual(
        @as(Float, 93),
        retained_thresholds[64],
    );

    const preserved_spectra = retained_spectra;
    const preserved_analyses = retained_analyses;
    const preserved_floor = retained_floor;
    const preserved_thresholds = retained_thresholds;
    var invalid_right = right;
    invalid_right[63] = std.math.nan(Float);
    try std.testing.expectError(
        error.InvalidVorbisPcmSample,
        analyzer.analyze(
            &.{ &left, &invalid_right },
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_spectra,
        &retained_spectra,
    );
    try std.testing.expectEqualSlices(
        VorbisPsychoacousticAnalysis,
        &preserved_analyses,
        &retained_analyses,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_floor,
        &retained_floor,
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_thresholds,
        &retained_thresholds,
    );
    try std.testing.expectError(
        error.InvalidVorbisPsychoacousticConfig,
        analyzer.analyze(
            &inputs,
            frame,
            .{ .quality = 1.1 },
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        Float,
        &preserved_spectra,
        &retained_spectra,
    );
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisScratchTooSmall,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = pcm_scratch[0..127],
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.VorbisPcmFrameAnalysisStorageTooSmall,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = retained_spectra[0..63],
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    try std.testing.expectError(
        error.OverlappingVorbisPcmFrameAnalysisStorage,
        analyzer.analyze(
            &inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = pcm_scratch[0..64],
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &retained_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );

    var aliased_spectra = [_]Float{0} ** 65;
    aliased_spectra[17] = 1;
    const aliased_inputs = [_][]const Float{
        aliased_spectra[0..64],
        &right,
    };
    try std.testing.expectError(
        error.OverlappingVorbisPcmFrameAnalysisStorage,
        analyzer.analyze(
            &aliased_inputs,
            frame,
            .{},
            48_000,
            .{
                .pcm = &pcm_scratch,
                .transform = &transform_scratch,
                .spectra = &spectrum_scratch,
                .floor_targets = &floor_scratch,
                .noise_thresholds = &threshold_scratch,
            },
            .{
                .spectra = &aliased_spectra,
                .analyses = &retained_analyses,
                .floor_targets = &retained_floor,
                .noise_thresholds = &retained_thresholds,
            },
        ),
    );
    var invalid_header = frame.header;
    invalid_header.block_size = 256;
    var invalid_frame = frame;
    invalid_frame.header = invalid_header;
    try std.testing.expectError(
        error.InvalidVorbisPcmBlockShape,
        Analyzer.requiredStorage(invalid_frame.header),
    );
}

test "Vorbis audio packet headers select retained modes and windows" {
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 256,
        .large_block_size = 2048,
    };

    var large_packet_storage: [128]u8 = undefined;
    const large_setup_packet = makeTestVorbisSetup(
        &large_packet_storage,
        .unordered,
        true,
        false,
    );
    var large_codebooks: [1]VorbisCodebook = undefined;
    var large_entries: [2]VorbisCodebookEntry = undefined;
    var large_nodes: [1]VorbisHuffmanNode = undefined;
    var large_multiplicands: [2]u32 = undefined;
    var large_floors: [1]VorbisFloor = undefined;
    var large_residues: [1]VorbisResidue = undefined;
    var large_mappings: [1]VorbisMapping = undefined;
    var large_modes: [1]VorbisMode = undefined;
    const large_setup = try parseVorbisSetup(
        large_setup_packet.bytes,
        2,
        .{
            .codebooks = &large_codebooks,
            .codebook_entries = &large_entries,
            .huffman_nodes = &large_nodes,
            .codebook_multiplicands = &large_multiplicands,
            .floors = &large_floors,
            .residues = &large_residues,
            .mappings = &large_mappings,
            .modes = &large_modes,
        },
    );
    const large_header = try parseVorbisAudioPacketHeader(
        &.{0b00000110},
        identification,
        large_setup,
    );
    try std.testing.expect(large_header.large_block);
    try std.testing.expectEqual(@as(?bool, true), large_header.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, true), large_header.next_window_flag);
    try std.testing.expectEqual(@as(u16, 2048), large_header.block_size);
    try std.testing.expectEqual(@as(usize, 3), large_header.payload_bit_offset);

    var small_packet_storage: [128]u8 = undefined;
    const small_setup_packet = makeTestVorbisSetup(
        &small_packet_storage,
        .unordered,
        false,
        false,
    );
    var small_codebooks: [1]VorbisCodebook = undefined;
    var small_entries: [2]VorbisCodebookEntry = undefined;
    var small_nodes: [1]VorbisHuffmanNode = undefined;
    var small_multiplicands: [2]u32 = undefined;
    var small_floors: [1]VorbisFloor = undefined;
    var small_residues: [1]VorbisResidue = undefined;
    var small_mappings: [1]VorbisMapping = undefined;
    var small_modes: [1]VorbisMode = undefined;
    const small_setup = try parseVorbisSetup(
        small_setup_packet.bytes,
        1,
        .{
            .codebooks = &small_codebooks,
            .codebook_entries = &small_entries,
            .huffman_nodes = &small_nodes,
            .codebook_multiplicands = &small_multiplicands,
            .floors = &small_floors,
            .residues = &small_residues,
            .mappings = &small_mappings,
            .modes = &small_modes,
        },
    );
    const small_header = try parseVorbisAudioPacketHeader(
        &.{0},
        identification,
        small_setup,
    );
    try std.testing.expect(!small_header.large_block);
    try std.testing.expectEqual(@as(u16, 256), small_header.block_size);
    try std.testing.expectEqual(@as(usize, 1), small_header.payload_bit_offset);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        parseVorbisAudioPacketHeader(&.{1}, identification, small_setup),
    );
    try std.testing.expectError(
        error.TruncatedVorbisAudioPacket,
        parseVorbisAudioPacketHeader(&.{}, identification, small_setup),
    );

    const modes = [_]VorbisMode{
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = false, .mapping = 0 },
        .{ .large_block = true, .mapping = 0 },
    };
    const multi_mode_setup = VorbisSetup{
        .summary = .{
            .codebook_count = 0,
            .codebook_entry_count = 0,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 3,
            .maximum_codebook_dimensions = 0,
            .maximum_codebook_entries = 0,
        },
        .codebooks = &.{},
        .codebook_entries = &.{},
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{},
        .floors = &.{},
        .residues = &.{},
        .mappings = &.{},
        .modes = &modes,
    };
    const selected = try parseVorbisAudioPacketHeader(
        &.{0b00001100},
        identification,
        multi_mode_setup,
    );
    try std.testing.expectEqual(@as(u8, 2), selected.mode_number);
    try std.testing.expectEqual(@as(?bool, true), selected.previous_window_flag);
    try std.testing.expectEqual(@as(?bool, false), selected.next_window_flag);
    try std.testing.expectEqual(@as(usize, 5), selected.payload_bit_offset);

    var small_window: [256]f64 = undefined;
    try synthesizeVorbisWindow(
        f64,
        identification,
        small_header,
        &small_window,
    );
    for (0..small_window.len / 2) |index| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1),
            small_window[index] * small_window[index] +
                small_window[small_window.len / 2 + index] *
                    small_window[small_window.len / 2 + index],
            1e-14,
        );
    }
    try std.testing.expect(small_window[0] > 0);
    try std.testing.expect(small_window[0] < small_window[1]);

    var transition_window: [2048]f32 = undefined;
    try synthesizeVorbisWindow(
        f32,
        identification,
        selected,
        &transition_window,
    );
    try std.testing.expect(transition_window[0] > 0);
    try std.testing.expectEqual(@as(f32, 1), transition_window[1024]);
    try std.testing.expect(transition_window[1599] > 0);
    try std.testing.expectEqual(@as(f32, 0), transition_window[1600]);
    try std.testing.expectEqual(@as(f32, 0), transition_window[2047]);
    const window_plan = VorbisWindowPlan(f32, 256, 2048).init();
    try std.testing.expectEqualSlices(
        f32,
        &transition_window,
        try window_plan.get(selected),
    );
    var small_window_f32: [256]f32 = undefined;
    try synthesizeVorbisWindow(
        f32,
        identification,
        small_header,
        &small_window_f32,
    );
    try std.testing.expectEqualSlices(
        f32,
        &small_window_f32,
        try window_plan.get(small_header),
    );

    var preserved_window = [_]f32{99} ** 256;
    var invalid_window_header = small_header;
    invalid_window_header.previous_window_flag = false;
    try std.testing.expectError(
        error.InvalidVorbisWindowState,
        synthesizeVorbisWindow(
            f32,
            identification,
            invalid_window_header,
            &preserved_window,
        ),
    );
    try std.testing.expectEqual(@as(f32, 99), preserved_window[0]);
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketMode,
        parseVorbisAudioPacketHeader(
            &.{0b00000110},
            identification,
            multi_mode_setup,
        ),
    );
}

test "Vorbis audio packet decoder composes floor residue coupling and MDCT" {
    const identification = VorbisIdentification{
        .channel_count = 2,
        .sample_rate = 48_000,
        .bitrate_maximum = 0,
        .bitrate_nominal = 0,
        .bitrate_minimum = 0,
        .small_block_size = 64,
        .large_block_size = 64,
    };
    const entries = [_]VorbisCodebookEntry{
        .{ .codeword = 0, .length = 1 },
        .{ .codeword = 0, .length = 1 },
    };
    const codebooks = [_]VorbisCodebook{
        .{
            .dimensions = 1,
            .entries = 1,
            .entry_offset = 0,
            .active_entry_count = 1,
            .lookup_type = 0,
        },
        .{
            .dimensions = 1,
            .entries = 1,
            .entry_offset = 1,
            .active_entry_count = 1,
            .lookup_type = 2,
            .delta_value = 1,
            .multiplicand_offset = 0,
            .multiplicand_count = 1,
        },
    };
    var x_list = [_]u16{0} ** 65;
    x_list[1] = 32;
    const floors = [_]VorbisFloor{.{
        .one = .{
            .partition_count = 0,
            .partition_classes = [_]u4{0} ** 31,
            .class_count = 0,
            .classes = [_]VorbisFloorOneClass{.{
                .dimensions = 0,
                .subclass_bits = 0,
                .masterbook = -1,
                .subclass_books = [_]i16{-1} ** 8,
            }} ** 16,
            .multiplier = 1,
            .range_bits = 5,
            .point_count = 2,
            .x_list = x_list,
        },
    }};
    var cascades = [_]u8{0} ** 64;
    cascades[0] = 1;
    var books = [_][8]i16{[_]i16{-1} ** 8} ** 64;
    books[0][0] = 1;
    const residues = [_]VorbisResidue{.{
        .kind = .two,
        .begin = 0,
        .end = 64,
        .partition_size = 1,
        .classification_count = 1,
        .classbook = 0,
        .cascades = cascades,
        .books = books,
    }};
    var coupling_steps = [_]VorbisCouplingStep{.{
        .magnitude = 0,
        .angle = 0,
    }} ** 256;
    coupling_steps[0] = .{ .magnitude = 0, .angle = 1 };
    const mappings = [_]VorbisMapping{.{
        .submap_count = 1,
        .coupling_step_count = 1,
        .coupling_steps = coupling_steps,
        .channel_mux = [_]u4{0} ** 255,
        .submaps = [_]VorbisSubmap{.{
            .floor = 0,
            .residue = 0,
        }} ** 16,
    }};
    const modes = [_]VorbisMode{.{
        .large_block = false,
        .mapping = 0,
    }};
    const setup = VorbisSetup{
        .summary = .{
            .codebook_count = 2,
            .codebook_entry_count = 2,
            .huffman_node_count = 0,
            .codebook_multiplicand_count = 1,
            .time_count = 1,
            .floor_count = 1,
            .residue_count = 1,
            .mapping_count = 1,
            .mode_count = 1,
            .maximum_codebook_dimensions = 1,
            .maximum_codebook_entries = 1,
        },
        .codebooks = &codebooks,
        .codebook_entries = &entries,
        .huffman_nodes = &.{},
        .codebook_multiplicands = &.{1},
        .floors = &floors,
        .residues = &residues,
        .mappings = &mappings,
        .modes = &modes,
    };

    var packet_storage: [32]u8 = undefined;
    var packet_writer = TestVorbisBitWriter.init(&packet_storage);
    packet_writer.write(0, 1);
    packet_writer.write(1, 1);
    packet_writer.write(255, 8);
    packet_writer.write(255, 8);
    packet_writer.write(0, 1);
    for (0..64) |_| {
        packet_writer.write(0, 1);
        packet_writer.write(0, 1);
    }
    const packet =
        packet_storage[0 .. (packet_writer.bit_offset + 7) / 8];
    const header = try parseVorbisAudioPacketHeader(
        packet,
        identification,
        setup,
    );
    const requirements = try requiredVorbisAudioPacketScratch(
        identification,
        setup,
        header,
    );
    try std.testing.expectEqual(@as(usize, 64), requirements.spectrum_values);
    try std.testing.expectEqual(@as(usize, 128), requirements.time_values);
    try std.testing.expectEqual(@as(usize, 64), requirements.classification_bytes);

    var spectra: [64]f64 = undefined;
    var floor_curves: [64]f64 = undefined;
    var coupling: [64]f64 = undefined;
    var time: [128]f64 = undefined;
    var classifications: [64]u8 = undefined;
    var left = [_]f64{99} ** 64;
    var right = [_]f64{99} ** 64;
    const outputs = [_][]f64{ &left, &right };
    var decoder = VorbisAudioPacketDecoder(f64, 2, 64, 64).init();
    const result = try decoder.decode(
        packet,
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(!result.truncated);
    try std.testing.expect(!result.floor_truncated);
    try std.testing.expect(!result.residue_truncated);
    try std.testing.expectEqual(packet_writer.bit_offset, result.decoded_bit_count);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &right);

    var window: [64]f64 = undefined;
    try synthesizeVorbisWindow(f64, identification, header, &window);
    for (&left, window, 0..) |actual, window_value, sample_index| {
        var sum: f64 = 0;
        for (0..32) |coefficient_index| {
            const angle = std.math.pi / 32.0 *
                (@as(f64, @floatFromInt(sample_index)) + 16.5) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += @cos(angle);
        }
        const expected = window_value * sum;
        try std.testing.expectApproxEqAbs(expected, actual, 1e-12);
    }

    @memset(&left, 99);
    @memset(&right, 99);
    const truncated = try decoder.decode(
        packet[0..6],
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(truncated.truncated);
    try std.testing.expect(!truncated.floor_truncated);
    try std.testing.expect(truncated.residue_truncated);
    for (left) |sample| try std.testing.expect(std.math.isFinite(sample));
    for (right) |sample| try std.testing.expect(std.math.isFinite(sample));

    @memset(&left, 99);
    @memset(&right, 99);
    const truncated_floor = try decoder.decode(
        packet[0..2],
        identification,
        setup,
        &outputs,
        .{
            .spectra = &spectra,
            .floor_curves = &floor_curves,
            .coupling = &coupling,
            .time = &time,
            .classifications = &classifications,
        },
    );
    try std.testing.expect(truncated_floor.truncated);
    try std.testing.expect(truncated_floor.floor_truncated);
    try std.testing.expect(!truncated_floor.residue_truncated);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &left);
    try std.testing.expectEqualSlices(f64, &([_]f64{0} ** 64), &right);

    @memset(&left, 99);
    @memset(&right, 99);
    try std.testing.expectError(
        error.VorbisAudioPacketScratchTooSmall,
        decoder.decode(
            packet,
            identification,
            setup,
            &outputs,
            .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = time[0..127],
                .classifications = &classifications,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), left[0]);
    try std.testing.expectEqual(@as(f64, 99), right[0]);

    var invalid_mappings = mappings;
    invalid_mappings[0].coupling_steps[0].angle = 0;
    var invalid_setup = setup;
    invalid_setup.mappings = &invalid_mappings;
    try std.testing.expectError(
        error.InvalidVorbisMappingState,
        decoder.decode(
            packet,
            identification,
            invalid_setup,
            &outputs,
            .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), left[0]);

    var stream = VorbisPcmStreamDecoder(f64, 2, 64, 64).init();
    var stream_windowed: [128]f64 = undefined;
    var first_empty_left: [0]f64 = .{};
    var first_empty_right: [0]f64 = .{};
    const first_empty_outputs =
        [_][]f64{ &first_empty_left, &first_empty_right };
    const first_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 0), first_stream_result.sample_count);

    var stream_left = [_]f64{99} ** 32;
    var stream_right = [_]f64{99} ** 32;
    const stream_outputs = [_][]f64{ &stream_left, &stream_right };
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        stream.decode(
            .{
                .bytes = &.{1},
                .granule_position = 32,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(u64, 1), stream.audio_packet_count);
    try std.testing.expectEqual(@as(f64, 99), stream_left[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        stream.overlap.channels[0].previousBlockSize(),
    );
    const second_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 32), second_stream_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), second_stream_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 32), second_stream_result.pcm_end);
    for (stream_left) |sample| {
        try std.testing.expect(std.math.isFinite(sample));
    }
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{0} ** 32),
        &stream_right,
    );

    const final_stream_result = try stream.decode(
        .{
            .bytes = packet,
            .granule_position = 60,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(usize, 28), final_stream_result.sample_count);
    try std.testing.expectEqual(@as(?i64, 32), final_stream_result.pcm_start);
    try std.testing.expectEqual(@as(?i64, 60), final_stream_result.pcm_end);
    try std.testing.expectError(
        error.VorbisPcmStreamAlreadyEnded,
        stream.decode(
            .{
                .bytes = packet,
                .granule_position = 92,
                .beginning = false,
                .end = true,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    stream.reset();
    try std.testing.expectEqual(@as(u64, 0), stream.audio_packet_count);

    var chained =
        VorbisChainedPcmStreamDecoder(f64, 2, 64, 64).init();
    try std.testing.expectError(
        error.VorbisLogicalStreamNotStarted,
        chained.decode(
            .{
                .bytes = packet,
                .granule_position = unknown_granule,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &first_empty_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try chained.beginLogicalStream(identification);
    const chained_prime = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = true,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 0), chained_prime.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 0), chained_prime.global_pcm_end);
    try std.testing.expectError(
        error.VorbisPreviousLogicalStreamNotEnded,
        chained.beginLogicalStream(identification),
    );
    try std.testing.expectError(
        error.InvalidVorbisAudioPacketType,
        chained.decode(
            .{
                .bytes = &.{1},
                .granule_position = 32,
                .beginning = false,
                .end = false,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    var recovering = chained;
    const concealed =
        try recovering.concealMissingPacketUsingPreviousBlockSize(
            32,
            false,
            identification,
            &stream_outputs,
            &stream_windowed,
        );
    try std.testing.expectEqual(@as(u64, 0), concealed.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 32), concealed.global_pcm_end);
    try std.testing.expectEqual(@as(u64, 1), concealed.stream.concealed_packet_count);
    try std.testing.expectEqual(@as(u64, 32), recovering.current_stream_pcm);
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    var following_recovery = chained;
    const fixed_following_header = VorbisAudioPacketHeader{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = 64,
        .payload_bit_offset = 1,
    };
    const following_concealed =
        try following_recovery.concealMissingPacketUsingFollowingHeader(
            fixed_following_header,
            32,
            false,
            identification,
            &stream_outputs,
            &stream_windowed,
        );
    try std.testing.expectEqual(
        @as(u16, 64),
        following_concealed.stream.block_size,
    );
    try std.testing.expectEqual(
        @as(u64, 32),
        following_concealed.global_pcm_end,
    );
    try std.testing.expectEqual(@as(u64, 0), chained.current_stream_pcm);
    const chained_middle = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = false,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 0), chained_middle.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 32), chained_middle.global_pcm_end);
    const chained_end = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 60,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 32), chained_end.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 60), chained_end.global_pcm_end);

    var changed_rate = identification;
    changed_rate.sample_rate += 1;
    try std.testing.expectError(
        error.VorbisChainedSampleRateChanged,
        chained.beginLogicalStream(changed_rate),
    );
    try chained.beginLogicalStream(identification);
    try std.testing.expectEqual(@as(u64, 1), chained.logical_stream_index);
    try std.testing.expectEqual(@as(u64, 60), chained.completed_pcm);
    const second_chain_prime = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = unknown_granule,
            .beginning = true,
            .end = false,
        },
        identification,
        setup,
        &first_empty_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(
        @as(u64, 60),
        second_chain_prime.global_pcm_start,
    );
    const second_chain_end = try chained.decode(
        .{
            .bytes = packet,
            .granule_position = 32,
            .beginning = false,
            .end = true,
        },
        identification,
        setup,
        &stream_outputs,
        .{
            .packet = .{
                .spectra = &spectra,
                .floor_curves = &floor_curves,
                .coupling = &coupling,
                .time = &time,
                .classifications = &classifications,
            },
            .windowed = &stream_windowed,
        },
    );
    try std.testing.expectEqual(@as(u64, 60), second_chain_end.global_pcm_start);
    try std.testing.expectEqual(@as(u64, 92), second_chain_end.global_pcm_end);

    var changed_geometry = identification;
    changed_geometry.channel_count = 1;
    try std.testing.expectError(
        error.VorbisChainedStreamGeometryChanged,
        chained.beginLogicalStream(changed_geometry),
    );
    chained.current_stream_pcm = std.math.maxInt(u64) - 31;
    @memset(&stream_left, 99);
    try std.testing.expectError(
        error.VorbisChainedPcmPositionOverflow,
        chained.decode(
            .{
                .bytes = packet,
                .granule_position = 64,
                .beginning = false,
                .end = true,
            },
            identification,
            setup,
            &stream_outputs,
            .{
                .packet = .{
                    .spectra = &spectra,
                    .floor_curves = &floor_curves,
                    .coupling = &coupling,
                    .time = &time,
                    .classifications = &classifications,
                },
                .windowed = &stream_windowed,
            },
        ),
    );
    try std.testing.expectEqual(@as(f64, 99), stream_left[0]);
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 31,
        chained.current_stream_pcm,
    );
    chained.reset();
    try std.testing.expect(!chained.started);
    try std.testing.expectEqual(@as(?u32, null), chained.sample_rate);
}

test "Vorbis inverse MDCT matches its defining transform" {
    const block_size = 64;
    const coefficient_count = block_size / 2;
    var coefficients: [coefficient_count]f64 = undefined;
    for (&coefficients, 0..) |*coefficient, index| {
        coefficient.* =
            @sin(@as(f64, @floatFromInt(index + 1)) * 0.37) *
            (1.0 + @as(f64, @floatFromInt(index % 5)));
    }
    var expected: [block_size]f64 = undefined;
    for (&expected, 0..) |*sample, sample_index| {
        var sum: f64 = 0;
        for (coefficients, 0..) |coefficient, coefficient_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += coefficient * @cos(angle);
        }
        sample.* = sum;
    }

    var plan = VorbisInverseMdct(f64, block_size).init();
    var actual: [block_size]f64 = undefined;
    try plan.process(&coefficients, &actual);
    for (actual, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            3e-11,
        );
    }

    @memset(&coefficients, 0);
    coefficients[0] = 1;
    try plan.process(&coefficients, &actual);
    for (actual, 0..) |actual_sample, sample_index| {
        const expected_sample = @cos(std.math.pi /
            @as(f64, @floatFromInt(coefficient_count)) *
            (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
            0.5);
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            1e-12,
        );
    }

    var random_state = std.Random.DefaultPrng.init(0x564F_5242_4953_4D44);
    const random = random_state.random();
    for (0..16) |_| {
        for (&coefficients) |*coefficient| {
            coefficient.* = random.float(f64) * 200.0 - 100.0;
        }
        for (&expected, 0..) |*sample, sample_index| {
            var sum: f64 = 0;
            for (coefficients, 0..) |coefficient, coefficient_index| {
                const angle = std.math.pi /
                    @as(f64, @floatFromInt(coefficient_count)) *
                    (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                        @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                    (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
                sum += coefficient * @cos(angle);
            }
            sample.* = sum;
        }
        try plan.process(&coefficients, &actual);
        for (actual, expected) |actual_sample, expected_sample| {
            try std.testing.expectApproxEqAbs(
                expected_sample,
                actual_sample,
                2e-11,
            );
        }
    }

    var aliased: [block_size]f64 = undefined;
    @memcpy(aliased[0..coefficient_count], &coefficients);
    try plan.process(
        aliased[0..coefficient_count],
        &aliased,
    );
    for (aliased, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            expected_sample,
            actual_sample,
            3e-11,
        );
    }

    const window_plan = VorbisWindowPlan(f64, block_size, block_size).init();
    const window = try window_plan.get(.{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = block_size,
        .payload_bit_offset = 0,
    });
    try plan.processWindowed(&coefficients, window, &actual);
    for (actual, expected, window) |
        actual_sample,
        expected_sample,
        window_value,
    | {
        try std.testing.expectApproxEqAbs(
            expected_sample * window_value,
            actual_sample,
            3e-11,
        );
    }

    var invalid_coefficients = coefficients;
    invalid_coefficients[3] = std.math.nan(f64);
    var preserved = [_]f64{99} ** block_size;
    try std.testing.expectError(
        error.InvalidVorbisMdctInput,
        plan.process(&invalid_coefficients, &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);
    try std.testing.expectError(
        error.InvalidVorbisMdctShape,
        plan.process(coefficients[0 .. coefficient_count - 1], &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);

    var f32_plan = VorbisInverseMdct(f32, block_size).init();
    var f32_coefficients: [coefficient_count]f32 = undefined;
    for (&f32_coefficients, coefficients) |*target, source| {
        target.* = @floatCast(source);
    }
    var f32_output: [block_size]f32 = undefined;
    try f32_plan.process(&f32_coefficients, &f32_output);
    for (f32_output, expected) |actual_sample, expected_sample| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_sample)),
            actual_sample,
            2e-3,
        );
    }

    comptime {
        _ = VorbisInverseMdct(f32, 8192);
    }
}

test "Vorbis forward MDCT matches its defining transform" {
    const block_size = 64;
    const coefficient_count = block_size / 2;
    var input: [block_size]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* =
            @sin(@as(f64, @floatFromInt(index + 1)) * 0.23) *
            (1.0 + @as(f64, @floatFromInt(index % 7)));
    }
    var expected: [coefficient_count]f64 = undefined;
    for (&expected, 0..) |*coefficient, coefficient_index| {
        var sum: f64 = 0;
        for (input, 0..) |sample, sample_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += sample * @cos(angle);
        }
        coefficient.* = 4.0 /
            @as(f64, @floatFromInt(block_size)) * sum;
    }

    var plan = VorbisForwardMdct(f64, block_size).init();
    var actual: [coefficient_count]f64 = undefined;
    try plan.process(&input, &actual);
    for (actual, expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-12,
        );
    }

    var random_state = std.Random.DefaultPrng.init(0x464F_5257_4D44_4354);
    const random = random_state.random();
    for (0..16) |_| {
        for (&input) |*sample|
            sample.* = random.float(f64) * 200.0 - 100.0;
        for (&expected, 0..) |*coefficient, coefficient_index| {
            var sum: f64 = 0;
            for (input, 0..) |sample, sample_index| {
                const angle = std.math.pi /
                    @as(f64, @floatFromInt(coefficient_count)) *
                    (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                        @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                    (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
                sum += sample * @cos(angle);
            }
            coefficient.* = 4.0 /
                @as(f64, @floatFromInt(block_size)) * sum;
        }
        try plan.process(&input, &actual);
        for (actual, expected) |actual_value, expected_value| {
            try std.testing.expectApproxEqAbs(
                expected_value,
                actual_value,
                2e-10,
            );
        }
    }

    var source_coefficients: [coefficient_count]f64 = undefined;
    for (&source_coefficients) |*coefficient|
        coefficient.* = random.float(f64) * 20.0 - 10.0;
    var inverse = VorbisInverseMdct(f64, block_size).init();
    var synthesized: [block_size]f64 = undefined;
    try inverse.process(&source_coefficients, &synthesized);
    try plan.process(&synthesized, &actual);
    for (actual, source_coefficients) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            2.0 * expected_value,
            actual_value,
            2e-11,
        );
    }

    var aliased = input;
    try plan.process(&aliased, aliased[0..coefficient_count]);
    for (
        aliased[0..coefficient_count],
        expected,
    ) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-10,
        );
    }

    const window_plan = VorbisWindowPlan(
        f64,
        block_size,
        block_size,
    ).init();
    const window = try window_plan.get(.{
        .mode_number = 0,
        .large_block = false,
        .previous_window_flag = null,
        .next_window_flag = null,
        .block_size = block_size,
        .payload_bit_offset = 0,
    });
    var windowed_expected: [coefficient_count]f64 = undefined;
    for (
        &windowed_expected,
        0..,
    ) |*coefficient, coefficient_index| {
        var sum: f64 = 0;
        for (input, window, 0..) |sample, gain, sample_index| {
            const angle = std.math.pi /
                @as(f64, @floatFromInt(coefficient_count)) *
                (@as(f64, @floatFromInt(sample_index)) + 0.5 +
                    @as(f64, @floatFromInt(coefficient_count)) / 2.0) *
                (@as(f64, @floatFromInt(coefficient_index)) + 0.5);
            sum += sample * gain * @cos(angle);
        }
        coefficient.* = 4.0 /
            @as(f64, @floatFromInt(block_size)) * sum;
    }
    try plan.processWindowed(&input, window, &actual);
    for (actual, windowed_expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            expected_value,
            actual_value,
            2e-10,
        );
    }

    var preserved = [_]f64{99} ** coefficient_count;
    var invalid_input = input;
    invalid_input[7] = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidVorbisMdctInput,
        plan.process(&invalid_input, &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);
    try std.testing.expectError(
        error.InvalidVorbisMdctShape,
        plan.process(input[0 .. block_size - 1], &preserved),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved[0]);

    var f32_plan = VorbisForwardMdct(f32, block_size).init();
    var f32_input: [block_size]f32 = undefined;
    for (&f32_input, input) |*target, source|
        target.* = @floatCast(source);
    var f32_output: [coefficient_count]f32 = undefined;
    try f32_plan.process(&f32_input, &f32_output);
    for (f32_output, expected) |actual_value, expected_value| {
        try std.testing.expectApproxEqAbs(
            @as(f32, @floatCast(expected_value)),
            actual_value,
            2e-3,
        );
    }

    comptime {
        _ = VorbisForwardMdct(f32, 8192);
    }
}

test "Vorbis floor application is transactional" {
    var spectrum = [_]f32{ 1, -2, 3, -4 };
    try applyVorbisFloor(
        f32,
        &spectrum,
        &.{ 0.5, 2, 0.25, 0 },
    );
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, -4, 0.75, 0 },
        &spectrum,
    );

    var preserved = [_]f64{ 1, 2 };
    try std.testing.expectError(
        error.InvalidVorbisSpectrumValue,
        applyVorbisFloor(
            f64,
            &preserved,
            &.{ std.math.floatMax(f64), std.math.nan(f64) },
        ),
    );
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, &preserved);
    try std.testing.expectError(
        error.InvalidVorbisSpectrumShape,
        applyVorbisFloor(f64, &preserved, &.{1}),
    );
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, &preserved);
}

test "Vorbis overlap-add aligns every block-size transition" {
    var state = VorbisOverlapAdd(f64, 256){};
    var output = [_]f64{99} ** 80;
    const first = [_]f64{1} ** 64;
    try std.testing.expectEqual(
        @as(usize, 0),
        try state.push(&first, &output),
    );
    try std.testing.expect(state.primed());
    try std.testing.expectEqual(@as(usize, 64), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    const second = [_]f64{2} ** 64;
    try std.testing.expectEqual(
        @as(usize, 32),
        try state.push(&second, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{3} ** 32), output[0..32]);
    try std.testing.expectEqual(@as(f64, 99), output[32]);

    const large = [_]f64{4} ** 256;
    @memset(&output, 99);
    try std.testing.expectEqual(
        @as(usize, 80),
        try state.push(&large, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{6} ** 32), output[0..32]);
    try std.testing.expectEqualSlices(f64, &([_]f64{4} ** 48), output[32..80]);

    const final_short = [_]f64{8} ** 64;
    var short_output = [_]f64{99} ** 79;
    try std.testing.expectError(
        error.VorbisOverlapOutputTooSmall,
        state.push(&final_short, &short_output),
    );
    try std.testing.expectEqual(@as(usize, 256), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), short_output[0]);

    @memset(&output, 99);
    try std.testing.expectEqual(
        @as(usize, 80),
        try state.push(&final_short, &output),
    );
    try std.testing.expectEqualSlices(f64, &([_]f64{4} ** 48), output[0..48]);
    try std.testing.expectEqualSlices(f64, &([_]f64{12} ** 32), output[48..80]);

    var non_finite = final_short;
    non_finite[5] = std.math.inf(f64);
    @memset(&output, 99);
    try std.testing.expectError(
        error.InvalidVorbisOverlapInput,
        state.push(&non_finite, &output),
    );
    try std.testing.expectEqual(@as(usize, 64), state.previousBlockSize());
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    var overlapping_state = VorbisOverlapAdd(f32, 256){};
    const overlapping_first = [_]f32{1} ** 64;
    _ = try overlapping_state.push(&overlapping_first, &.{});
    var overlapping_current = [_]f32{2} ** 256;
    try std.testing.expectError(
        error.OverlappingVorbisOverlapBuffer,
        overlapping_state.push(
            &overlapping_current,
            overlapping_current[0..80],
        ),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        overlapping_state.previousBlockSize(),
    );

    var overflow_state = VorbisOverlapAdd(f32, 64){};
    const maximum = [_]f32{std.math.floatMax(f32)} ** 64;
    _ = try overflow_state.push(&maximum, &.{});
    var preserved = [_]f32{99} ** 32;
    try std.testing.expectError(
        error.InvalidVorbisOverlapOutput,
        overflow_state.push(&maximum, &preserved),
    );
    try std.testing.expectEqual(@as(f32, 99), preserved[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        overflow_state.previousBlockSize(),
    );

    var hostile_state = VorbisOverlapAdd(f64, 256){};
    hostile_state.previous_size = 3;
    @memset(&output, 99);
    try std.testing.expectError(
        error.InvalidVorbisOverlapState,
        hostile_state.push(&first, &output),
    );
    try std.testing.expectEqual(@as(f64, 99), output[0]);

    state.reset();
    try std.testing.expect(!state.primed());
}

test "Vorbis channel overlap-add commits every channel atomically" {
    var state = VorbisChannelOverlapAdd(f64, 2, 256){};
    const first_left = [_]f64{1} ** 64;
    const first_right = [_]f64{2} ** 64;
    const first = [_][]const f64{ &first_left, &first_right };
    var empty_left: [0]f64 = .{};
    var empty_right: [0]f64 = .{};
    const empty_outputs = [_][]f64{ &empty_left, &empty_right };
    try std.testing.expectEqual(
        @as(usize, 0),
        try state.push(&first, &empty_outputs),
    );
    try std.testing.expect(state.primed());

    const second_left = [_]f64{3} ** 64;
    const second_right = [_]f64{4} ** 64;
    const second = [_][]const f64{ &second_left, &second_right };
    var output_left = [_]f64{99} ** 32;
    var output_right = [_]f64{99} ** 32;
    const outputs = [_][]f64{ &output_left, &output_right };
    try std.testing.expectEqual(
        @as(usize, 32),
        try state.push(&second, &outputs),
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{4} ** 32),
        &output_left,
    );
    try std.testing.expectEqualSlices(
        f64,
        &([_]f64{6} ** 32),
        &output_right,
    );

    const third_left = [_]f64{5} ** 256;
    var invalid_right = [_]f64{6} ** 256;
    invalid_right[100] = std.math.nan(f64);
    const invalid = [_][]const f64{ &third_left, &invalid_right };
    var preserved_left = [_]f64{99} ** 80;
    var preserved_right = [_]f64{99} ** 80;
    const preserved_outputs =
        [_][]f64{ &preserved_left, &preserved_right };
    try std.testing.expectError(
        error.InvalidVorbisOverlapInput,
        state.push(&invalid, &preserved_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved_left[0]);
    try std.testing.expectEqual(@as(f64, 99), preserved_right[0]);
    try std.testing.expectEqual(
        @as(usize, 64),
        state.channels[0].previousBlockSize(),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        state.channels[1].previousBlockSize(),
    );

    var shared_output = [_]f64{99} ** 80;
    const overlapping_outputs =
        [_][]f64{ shared_output[0..32], shared_output[16..48] };
    const valid_third_right = [_]f64{6} ** 256;
    const valid_third =
        [_][]const f64{ &third_left, &valid_third_right };
    try std.testing.expectError(
        error.OverlappingVorbisChannelOverlapBuffer,
        state.push(&valid_third, &overlapping_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), shared_output[0]);

    state.channels[1].previous_size = 256;
    try std.testing.expectError(
        error.InvalidVorbisChannelOverlapState,
        state.push(&valid_third, &preserved_outputs),
    );
    try std.testing.expectEqual(@as(f64, 99), preserved_left[0]);

    state.reset();
    try std.testing.expect(!state.primed());
}

test "Vorbis granule tracking trims stream boundaries transactionally" {
    var normal = VorbisGranuleTracker{};
    const unknown = try normal.trim(32, unknown_granule, false);
    try std.testing.expectEqual(@as(usize, 0), unknown.source_start);
    try std.testing.expectEqual(@as(usize, 32), unknown.sample_count);
    try std.testing.expectEqual(@as(?i64, null), unknown.pcm_start);
    const positioned = try normal.trim(32, 64, false);
    try std.testing.expectEqual(@as(?i64, 32), positioned.pcm_start);
    try std.testing.expectEqual(@as(?i64, 64), positioned.pcm_end);
    try std.testing.expectEqual(@as(?i64, 0), normal.position_offset);
    const final = try normal.trim(32, 90, true);
    try std.testing.expectEqual(@as(usize, 26), final.sample_count);
    try std.testing.expectEqual(@as(?i64, 64), final.pcm_start);
    try std.testing.expectEqual(@as(?i64, 90), final.pcm_end);
    try std.testing.expect(normal.ended);
    try std.testing.expectError(
        error.VorbisGranuleStreamAlreadyEnded,
        normal.trim(32, 122, true),
    );

    var negative_start = VorbisGranuleTracker{};
    const clipped_start = try negative_start.trim(32, 22, false);
    try std.testing.expectEqual(@as(usize, 10), clipped_start.source_start);
    try std.testing.expectEqual(@as(usize, 22), clipped_start.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), clipped_start.pcm_start);
    try std.testing.expectEqual(@as(?i64, 22), clipped_start.pcm_end);
    try std.testing.expectEqual(
        @as(?i64, -10),
        negative_start.position_offset,
    );
    const clipped_end = try negative_start.trim(32, 50, true);
    try std.testing.expectEqual(@as(usize, 28), clipped_end.sample_count);
    try std.testing.expectEqual(@as(?i64, 22), clipped_end.pcm_start);
    try std.testing.expectEqual(@as(?i64, 50), clipped_end.pcm_end);

    var short_stream = VorbisGranuleTracker{};
    const short_end = try short_stream.trim(32, 28, true);
    try std.testing.expectEqual(@as(usize, 0), short_end.source_start);
    try std.testing.expectEqual(@as(usize, 28), short_end.sample_count);
    try std.testing.expectEqual(@as(?i64, 0), short_end.pcm_start);
    try std.testing.expectEqual(@as(?i64, 28), short_end.pcm_end);

    var positive_start = VorbisGranuleTracker{};
    const offset_start = try positive_start.trim(32, 37, false);
    try std.testing.expectEqual(@as(?i64, 5), offset_start.pcm_start);
    try std.testing.expectEqual(@as(?i64, 37), offset_start.pcm_end);

    var late = VorbisGranuleTracker{};
    _ = try late.trim(32, unknown_granule, false);
    const late_before = late;
    try std.testing.expectError(
        error.LateVorbisInitialGranule,
        late.trim(32, 54, false),
    );
    try std.testing.expectEqualDeep(late_before, late);

    var invalid = VorbisGranuleTracker{};
    _ = try invalid.trim(32, 32, false);
    const invalid_before = invalid;
    try std.testing.expectError(
        error.InvalidVorbisGranulePosition,
        invalid.trim(32, 63, false),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);
    try std.testing.expectError(
        error.MissingVorbisEndGranule,
        invalid.trim(32, unknown_granule, true),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);
    try std.testing.expectError(
        error.InvalidVorbisGranuleSampleCount,
        invalid.trim(0, 32, false),
    );
    try std.testing.expectEqualDeep(invalid_before, invalid);

    invalid.reset();
    try std.testing.expectEqualDeep(VorbisGranuleTracker{}, invalid);
}

test "file-backed Ogg packet reader streams continued packets" {
    var encoded: [70_000]u8 = undefined;
    var writer = StreamWriter.init(&encoded, 99);
    const packet = [_]u8{0x5a} ** 65_100;
    try writer.appendPacket(&packet, 65_100, true, true);
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "packets.ogg",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, writer.bytes(), 0);
    try file.setLength(std.testing.io, writer.bytes().len);
    var reader = try FilePacketReader.init(std.testing.io, file);
    var page_storage: [maximum_page_bytes]u8 = undefined;
    var packet_storage: [packet.len]u8 = undefined;
    const actual = (try reader.next(
        &page_storage,
        &packet_storage,
    )).?;
    try std.testing.expect(actual.beginning);
    try std.testing.expect(actual.end);
    try std.testing.expectEqualSlices(u8, &packet, actual.bytes);
    try std.testing.expect(
        (try reader.next(&page_storage, &packet_storage)) == null,
    );
}
