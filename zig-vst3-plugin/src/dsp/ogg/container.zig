const std = @import("std");
const file_reader_io = @import("../file_reader_io.zig");
const file_writer_io = @import("../file_writer_io.zig");

pub const unknown_granule = std.math.maxInt(u64);
pub const maximum_page_segments = 255;
pub const maximum_page_body_bytes = 255 * 255;
pub const maximum_page_bytes = 27 + maximum_page_segments +
    maximum_page_body_bytes;
pub const Limits = struct {
    max_stream_bytes: u64 = std.math.maxInt(u32),
    max_pages: u64 = 10_000_000,
    max_packets: u64 = 10_000_000,
    max_logical_streams: u32 = 65_536,

    pub fn validate(self: Limits) !void {
        if (self.max_stream_bytes < 27 or
            self.max_pages == 0 or
            self.max_packets == 0 or
            self.max_logical_streams == 0)
        {
            return error.InvalidOggLimits;
        }
    }
};

pub const default_limits = Limits{};

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
    pages_read: u64 = 0,
    limits: Limits = default_limits,

    pub fn init(encoded: []const u8) PageIterator {
        return .{ .encoded = encoded, .limits = default_limits };
    }

    pub fn initWithLimits(
        encoded: []const u8,
        limits: Limits,
    ) !PageIterator {
        try validateEncodedLimits(encoded, limits);
        return .{ .encoded = encoded, .limits = limits };
    }

    pub fn initChained(encoded: []const u8) PageIterator {
        return .{
            .encoded = encoded,
            .allow_chaining = true,
            .limits = default_limits,
        };
    }

    pub fn initChainedWithLimits(
        encoded: []const u8,
        limits: Limits,
    ) !PageIterator {
        try validateEncodedLimits(encoded, limits);
        return .{
            .encoded = encoded,
            .allow_chaining = true,
            .limits = limits,
        };
    }

    pub fn valid(self: *const PageIterator) bool {
        self.validateState() catch return false;
        return true;
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
        try self.validateState();
        if (self.pages_read == self.limits.max_pages)
            return error.OggPageLimitExceeded;
        if (self.ended and self.allow_chaining and
            self.logical_stream_index + 1 >=
                self.limits.max_logical_streams)
        {
            return error.OggLogicalStreamLimitExceeded;
        }
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
        try self.validateState();
        if (self.offset == self.encoded.len) {
            if (self.packet_continues) return error.TruncatedOggPacket;
            return null;
        }
        if (self.pages_read == self.limits.max_pages)
            return error.OggPageLimitExceeded;
        if (self.ended) {
            if (!self.allow_chaining)
                return error.OggDataAfterEndOfStream;
            if (self.logical_stream_index + 1 >=
                self.limits.max_logical_streams)
                return error.OggLogicalStreamLimitExceeded;
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
        self.pages_read += 1;
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

    fn validateState(self: *const PageIterator) !void {
        self.limits.validate() catch return error.InvalidOggReaderState;
        const encoded_bytes = std.math.cast(u64, self.encoded.len) orelse
            return error.InvalidOggReaderState;
        if (encoded_bytes > self.limits.max_stream_bytes)
            return error.OggStreamLimitExceeded;
        if (self.pages_read > self.limits.max_pages or
            self.logical_stream_index >= self.limits.max_logical_streams or
            self.offset > self.encoded.len or
            !oggReaderLifecycleValid(
                self.serial_number,
                self.expected_sequence,
                self.packet_continues,
                self.ended,
                self.allow_chaining,
                self.logical_stream_index,
            ))
        {
            return error.InvalidOggReaderState;
        }
    }
};

pub fn validateEncodedLimits(encoded: []const u8, limits: Limits) !void {
    try limits.validate();
    const encoded_bytes = std.math.cast(u64, encoded.len) orelse
        return error.OggStreamLimitExceeded;
    if (encoded_bytes > limits.max_stream_bytes)
        return error.OggStreamLimitExceeded;
}

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

    pub fn initWithLimits(
        encoded: []const u8,
        storage: []u8,
        limits: Limits,
    ) !PacketIterator {
        return .{
            .pages = try PageIterator.initWithLimits(encoded, limits),
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

    pub fn initChainedWithLimits(
        encoded: []const u8,
        storage: []u8,
        limits: Limits,
    ) !PacketIterator {
        return .{
            .pages = try PageIterator.initChainedWithLimits(encoded, limits),
            .storage = storage,
        };
    }

    pub fn next(self: *PacketIterator) !?Packet {
        var trial = self.*;
        const packet = try trial.nextInPlace();
        self.* = trial;
        return packet;
    }

    /// Stage a complete packet before advancing or changing bound storage.
    pub fn nextTransactional(
        self: *PacketIterator,
        scratch: []u8,
    ) !?Packet {
        try self.validateState();
        if (byteRangesOverlap(
            @intFromPtr(self.storage.ptr),
            self.storage.len,
            @intFromPtr(scratch.ptr),
            scratch.len,
        )) return error.OverlappingOggPacketStorage;

        const destination = self.storage;
        var trial = self.*;
        trial.storage = scratch;
        const staged = try trial.next() orelse {
            trial.storage = destination;
            self.* = trial;
            return null;
        };
        if (destination.len < staged.bytes.len)
            return error.OggPacketBufferTooSmall;
        @memcpy(destination[0..staged.bytes.len], staged.bytes);
        trial.storage = destination;
        self.* = trial;
        var packet = staged;
        packet.bytes = destination[0..staged.bytes.len];
        return packet;
    }

    pub fn valid(self: *const PacketIterator) bool {
        self.validateState() catch return false;
        return true;
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
        if (self.packet_index == self.pages.limits.max_packets and
            self.packet_index != std.math.maxInt(u64))
        {
            const page_exhausted = if (self.page) |page|
                self.segment_index == page.lacing_values.len
            else
                true;
            if (self.packet_bytes == 0 and
                self.pages.offset == self.pages.encoded.len and
                page_exhausted)
            {
                return null;
            }
            return error.OggPacketLimitExceeded;
        }
        while (true) {
            const page_exhausted = if (self.page) |page|
                self.segment_index == page.lacing_values.len
            else
                true;
            if (page_exhausted) {
                self.page = try self.pages.next() orelse {
                    if (self.packet_bytes != 0)
                        return error.TruncatedOggPacket;
                    return null;
                };
                self.segment_index = 0;
                self.body_offset = 0;
                if ((self.page orelse
                    return error.InvalidOggPacketReaderState).beginning)
                    self.logical_stream_packet_index = 0;
            }
            const page = self.page orelse
                return error.InvalidOggPacketReaderState;
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
                self.logical_stream_packet_index == std.math.maxInt(u64))
                return error.OggPacketCountOverflow;
            self.packet_index += 1;
            self.logical_stream_packet_index += 1;
            return packet;
        }
    }

    fn validateState(self: *const PacketIterator) !void {
        try self.pages.validateState();
        if (byteRangesOverlap(
            @intFromPtr(self.pages.encoded.ptr),
            self.pages.encoded.len,
            @intFromPtr(self.storage.ptr),
            self.storage.len,
        )) return error.OverlappingOggPacketStorage;
        if (self.packet_bytes > self.storage.len or
            self.packet_index > self.pages.limits.max_packets or
            self.logical_stream_packet_index > self.packet_index)
            return error.InvalidOggPacketReaderState;
        const page = self.page orelse {
            if (self.segment_index != 0 or self.body_offset != 0 or
                self.packet_bytes != 0)
                return error.InvalidOggPacketReaderState;
            return;
        };
        if (self.pages.pages_read == 0)
            return error.InvalidOggPacketReaderState;
        try self.validateRetainedPage(page);
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

    fn validateRetainedPage(self: *const PacketIterator, page: Page) !void {
        const start = std.math.cast(usize, page.byte_offset) orelse
            return error.InvalidOggPacketReaderState;
        const byte_length: usize = page.byte_length;
        if (byte_length < 27 or start > self.pages.encoded.len or
            byte_length > self.pages.encoded.len - start)
        {
            return error.InvalidOggPacketReaderState;
        }
        const end = start + byte_length;
        const complete = self.pages.encoded[start..end];
        const retained = try validateRetainedOggPage(
            page,
            complete,
            @intCast(start),
        );
        if (page.logical_stream_index != self.pages.logical_stream_index or
            self.pages.offset != end or
            self.pages.serial_number != retained.serial_number or
            self.pages.expected_sequence != retained.sequence_number +% 1 or
            self.pages.packet_continues != retained.packet_continues or
            self.pages.ended != retained.ended)
        {
            return error.InvalidOggPacketReaderState;
        }
    }
};

pub const RetainedOggPageState = struct {
    serial_number: u32,
    sequence_number: u32,
    packet_continues: bool,
    ended: bool,
};

pub fn validateRetainedOggPage(
    page: Page,
    complete: []const u8,
    byte_offset: u64,
) !RetainedOggPageState {
    if (complete.len < 27 or
        page.byte_offset != byte_offset or
        @as(usize, page.byte_length) != complete.len)
    {
        return error.InvalidOggPacketReaderState;
    }
    const header = complete[0..27];
    if (!std.mem.eql(u8, header[0..4], "OggS") or header[4] != 0 or
        header[5] & 0xf8 != 0)
    {
        return error.InvalidOggPacketReaderState;
    }
    const segment_count: usize = header[26];
    const header_bytes = 27 + segment_count;
    if (header_bytes > complete.len)
        return error.InvalidOggPacketReaderState;
    const lacing = complete[27..header_bytes];
    var body_bytes: usize = 0;
    for (lacing) |value| body_bytes += value;
    if (body_bytes != complete.len - header_bytes)
        return error.InvalidOggPacketReaderState;
    const body = complete[header_bytes..];
    if (!sameByteRange(page.lacing_values, lacing) or
        !sameByteRange(page.body, body) or
        pageChecksum(complete) !=
            std.mem.readInt(u32, header[22..26], .little))
    {
        return error.InvalidOggPacketReaderState;
    }

    const flags = header[5];
    const serial = std.mem.readInt(u32, header[14..18], .little);
    const sequence = std.mem.readInt(u32, header[18..22], .little);
    const continued = flags & 0x01 != 0;
    const beginning = flags & 0x02 != 0;
    const ended = flags & 0x04 != 0;
    const packet_continues = lacing.len != 0 and
        lacing[lacing.len - 1] == 255;
    if (page.continued != continued or page.beginning != beginning or
        page.end != ended or
        page.granule_position !=
            std.mem.readInt(u64, header[6..14], .little) or
        page.serial_number != serial or page.sequence_number != sequence)
    {
        return error.InvalidOggPacketReaderState;
    }
    return .{
        .serial_number = serial,
        .sequence_number = sequence,
        .packet_continues = packet_continues,
        .ended = ended,
    };
}

pub fn validateRetainedPageStorageRanges(
    page: Page,
    storage: []const u8,
) !void {
    if (storage.len < 27 or page.lacing_values.len > maximum_page_segments or
        @as(usize, page.byte_length) != storage.len)
    {
        return error.InvalidOggPacketReaderState;
    }
    const storage_start = @intFromPtr(storage.ptr);
    const lacing_start = std.math.add(
        usize,
        storage_start,
        27,
    ) catch return error.InvalidOggPacketReaderState;
    const body_start = std.math.add(
        usize,
        lacing_start,
        page.lacing_values.len,
    ) catch return error.InvalidOggPacketReaderState;
    const storage_end = std.math.add(
        usize,
        storage_start,
        storage.len,
    ) catch return error.InvalidOggPacketReaderState;
    const body_end = std.math.add(
        usize,
        body_start,
        page.body.len,
    ) catch return error.InvalidOggPacketReaderState;
    if (@intFromPtr(page.lacing_values.ptr) != lacing_start or
        @intFromPtr(page.body.ptr) != body_start or body_end != storage_end)
    {
        return error.InvalidOggPacketReaderState;
    }
}

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

pub const VorbisSeekIndexer = struct {
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
        const packet = last_audio_packet orelse
            return error.InvalidVorbisSeekContinuation;
        const decode = if (self.previous_pcm_end == null)
            self.first_audio_packet orelse
                return error.InvalidVorbisSeekContinuation
        else
            decode_packet orelse
                return error.InvalidVorbisSeekContinuation;
        const point = VorbisSeekPoint{
            .pcm_end = pcm_end,
            .decode = decode,
            .packet = packet,
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

pub fn vorbisPacketLocation(
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
    return requiredVorbisSeekPointsWithLimits(encoded, default_limits);
}

pub fn requiredVorbisSeekPointsWithLimits(
    encoded: []const u8,
    limits: Limits,
) !usize {
    var pages = try PageIterator.initChainedWithLimits(encoded, limits);
    var indexer = VorbisSeekIndexer{ .destination = null };
    while (try pages.next()) |page| try indexer.consume(page);
    return indexer.count;
}

pub fn buildVorbisSeekIndex(
    encoded: []const u8,
    destination: []VorbisSeekPoint,
) ![]const VorbisSeekPoint {
    return buildVorbisSeekIndexWithLimits(
        encoded,
        destination,
        default_limits,
    );
}

pub fn buildVorbisSeekIndexWithLimits(
    encoded: []const u8,
    destination: []VorbisSeekPoint,
    limits: Limits,
) ![]const VorbisSeekPoint {
    const required = try requiredVorbisSeekPointsWithLimits(encoded, limits);
    if (destination.len < required)
        return error.VorbisSeekIndexTooSmall;
    var pages = try PageIterator.initChainedWithLimits(encoded, limits);
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
            const previous_end = previous_pcm orelse
                return error.InvalidVorbisSeekIndex;
            if (stream < previous or
                (stream == previous and
                    previous_end > point.pcm_end))
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
    pages_read: u64 = 0,
    limits: Limits = default_limits,

    pub fn init(io: std.Io, file: std.Io.File) !FilePageReader {
        return initWithLimits(io, file, default_limits);
    }

    pub fn initWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FilePageReader {
        try limits.validate();
        const file_size = (try file.stat(io)).size;
        if (file_size > limits.max_stream_bytes)
            return error.OggStreamLimitExceeded;
        return .{
            .io = io,
            .file = file,
            .file_size = file_size,
            .limits = limits,
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

    pub fn initChainedWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FilePageReader {
        var reader = try initWithLimits(io, file, limits);
        reader.allow_chaining = true;
        return reader;
    }

    pub fn valid(self: *const FilePageReader) bool {
        self.validateState() catch return false;
        return true;
    }

    /// Returned page slices borrow storage until the next read.
    pub fn next(
        self: *FilePageReader,
        storage: []u8,
    ) !?Page {
        try self.validateState();
        if (self.offset == self.file_size) {
            if (self.packet_continues) return error.TruncatedOggPacket;
            return null;
        }
        if (self.pages_read == self.limits.max_pages)
            return error.OggPageLimitExceeded;
        if (self.ended and self.allow_chaining and
            self.logical_stream_index + 1 >=
                self.limits.max_logical_streams)
        {
            return error.OggLogicalStreamLimitExceeded;
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
            .pages_read = self.pages_read,
            .limits = self.limits,
        };
        var page = (try parser.next()) orelse
            return error.TruncatedOggPage;
        page.byte_offset = self.offset;
        self.serial_number = parser.serial_number;
        self.expected_sequence = parser.expected_sequence;
        self.packet_continues = parser.packet_continues;
        self.ended = parser.ended;
        self.logical_stream_index = parser.logical_stream_index;
        self.pages_read = parser.pages_read;
        self.offset += page_bytes;
        return page;
    }

    /// Stage one complete page so failures preserve state and destination.
    pub fn nextTransactional(
        self: *FilePageReader,
        storage: []u8,
        scratch: []u8,
    ) !?Page {
        try self.validateState();
        if (byteRangesOverlap(
            @intFromPtr(storage.ptr),
            storage.len,
            @intFromPtr(scratch.ptr),
            scratch.len,
        )) return error.OverlappingOggPageStorage;

        var trial = self.*;
        const staged = try trial.next(scratch) orelse {
            self.* = trial;
            return null;
        };
        const page_bytes: usize = staged.byte_length;
        if (storage.len < page_bytes)
            return error.OggPageBufferTooSmall;
        @memcpy(storage[0..page_bytes], scratch[0..page_bytes]);

        const header_bytes = 27 + @as(usize, storage[26]);
        var page = staged;
        page.lacing_values = storage[27..header_bytes];
        page.body = storage[header_bytes..page_bytes];
        self.* = trial;
        return page;
    }

    /// Advances past at most `maximum_skip_bytes` to a continuous valid page.
    pub fn resynchronize(
        self: *FilePageReader,
        storage: []u8,
        maximum_skip_bytes: u64,
    ) !u64 {
        try self.validateState();
        if (self.pages_read == self.limits.max_pages)
            return error.OggPageLimitExceeded;
        if (self.ended and self.allow_chaining and
            self.logical_stream_index + 1 >=
                self.limits.max_logical_streams)
        {
            return error.OggLogicalStreamLimitExceeded;
        }
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
                .pages_read = self.pages_read,
                .limits = self.limits,
            };
            _ = parser.next() catch continue;
            const skipped = candidate - self.offset;
            self.offset = candidate;
            return skipped;
        }
        return error.OggResynchronizationLimitReached;
    }

    fn validateState(self: *const FilePageReader) !void {
        self.limits.validate() catch
            return error.InvalidOggFileReaderState;
        if (self.file_size > self.limits.max_stream_bytes or
            self.pages_read > self.limits.max_pages or
            self.logical_stream_index >= self.limits.max_logical_streams or
            self.offset > self.file_size or
            !oggReaderLifecycleValid(
                self.serial_number,
                self.expected_sequence,
                self.packet_continues,
                self.ended,
                self.allow_chaining,
                self.logical_stream_index,
            ))
        {
            return error.InvalidOggFileReaderState;
        }
    }
};

pub fn oggReaderLifecycleValid(
    serial_number: ?u32,
    expected_sequence: ?u32,
    packet_continues: bool,
    ended: bool,
    allow_chaining: bool,
    logical_stream_index: u32,
) bool {
    if (serial_number == null) {
        return expected_sequence == null and
            !packet_continues and
            (if (ended)
                allow_chaining
            else
                logical_stream_index == 0);
    }
    return expected_sequence != null and
        !(ended and packet_continues) and
        (allow_chaining or logical_stream_index == 0);
}

pub fn requiredVorbisFileSeekPoints(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
) !usize {
    return requiredVorbisFileSeekPointsWithLimits(
        io,
        file,
        page_storage,
        default_limits,
    );
}

pub fn requiredVorbisFileSeekPointsWithLimits(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    limits: Limits,
) !usize {
    var pages = try FilePageReader.initChainedWithLimits(io, file, limits);
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
    return buildVorbisFileSeekIndexWithLimits(
        io,
        file,
        page_storage,
        destination,
        default_limits,
    );
}

pub fn buildVorbisFileSeekIndexWithLimits(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    destination: []VorbisSeekPoint,
    limits: Limits,
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
    const required = try requiredVorbisFileSeekPointsWithLimits(
        io,
        file,
        page_storage,
        limits,
    );
    if (destination.len < required)
        return error.VorbisSeekIndexTooSmall;
    var pages = try FilePageReader.initChainedWithLimits(io, file, limits);
    var indexer = VorbisSeekIndexer{ .destination = destination };
    while (try pages.next(page_storage)) |page| {
        try indexer.consume(page);
    }
    if (indexer.count != required)
        return error.VorbisSeekIndexChanged;
    return destination[0..required];
}

/// Stage the index so file changes cannot partially replace destination.
/// Page, destination, and index scratch storage must be pairwise disjoint.
pub fn buildVorbisFileSeekIndexTransactional(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    destination: []VorbisSeekPoint,
    index_scratch: []VorbisSeekPoint,
) ![]const VorbisSeekPoint {
    return buildVorbisFileSeekIndexTransactionalWithLimits(
        io,
        file,
        page_storage,
        destination,
        index_scratch,
        default_limits,
    );
}

pub fn buildVorbisFileSeekIndexTransactionalWithLimits(
    io: std.Io,
    file: std.Io.File,
    page_storage: []u8,
    destination: []VorbisSeekPoint,
    index_scratch: []VorbisSeekPoint,
    limits: Limits,
) ![]const VorbisSeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(VorbisSeekPoint),
    ) catch return error.VorbisSeekIndexSizeOverflow;
    const scratch_bytes = std.math.mul(
        usize,
        index_scratch.len,
        @sizeOf(VorbisSeekPoint),
    ) catch return error.VorbisSeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(page_storage.ptr),
        page_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(page_storage.ptr),
        page_storage.len,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(destination.ptr),
        destination_bytes,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    )) return error.OverlappingVorbisSeekStorage;

    const staged = try buildVorbisFileSeekIndexWithLimits(
        io,
        file,
        page_storage,
        index_scratch,
        limits,
    );
    if (destination.len < staged.len)
        return error.VorbisSeekIndexTooSmall;
    @memcpy(destination[0..staged.len], staged);
    return destination[0..staged.len];
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

    pub fn initWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FilePacketReader {
        return .{
            .pages = try FilePageReader.initWithLimits(io, file, limits),
        };
    }

    pub fn initChained(
        io: std.Io,
        file: std.Io.File,
    ) !FilePacketReader {
        return .{ .pages = try FilePageReader.initChained(io, file) };
    }

    pub fn initChainedWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FilePacketReader {
        return .{
            .pages = try FilePageReader.initChainedWithLimits(
                io,
                file,
                limits,
            ),
        };
    }

    /// Reposition to the preceding audio packet retained by a seek point.
    pub fn seek(
        self: *FilePacketReader,
        point: VorbisSeekPoint,
    ) !void {
        const location = point.decode;
        if (location.byte_offset > self.pages.file_size -| 27 or
            location.logical_stream_index >=
                self.pages.limits.max_logical_streams or
            location.logical_packet_index <
                location.completed_packets_before)
            return error.InvalidVorbisSeekPoint;
        if (location.completed_packets_before >=
            self.pages.limits.max_packets)
        {
            return error.OggPacketLimitExceeded;
        }
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
        self.pages.pages_read = 0;
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

    /// Preserve output on failure; scratch buffers retain reader bindings.
    pub fn nextTransactional(
        self: *FilePacketReader,
        destination: []u8,
        page_scratch: []u8,
        packet_scratch: []u8,
    ) !?Packet {
        try self.validateState(page_scratch, packet_scratch);
        if (byteRangesOverlap(
            @intFromPtr(destination.ptr),
            destination.len,
            @intFromPtr(page_scratch.ptr),
            page_scratch.len,
        ) or byteRangesOverlap(
            @intFromPtr(destination.ptr),
            destination.len,
            @intFromPtr(packet_scratch.ptr),
            packet_scratch.len,
        ) or byteRangesOverlap(
            @intFromPtr(page_scratch.ptr),
            page_scratch.len,
            @intFromPtr(packet_scratch.ptr),
            packet_scratch.len,
        )) return error.OverlappingOggPacketStorage;

        var trial = self.*;
        const staged = trial.next(
            page_scratch,
            packet_scratch,
        ) catch |err| {
            if (err == error.OggPacketBufferTooSmall)
                self.* = trial;
            return err;
        } orelse {
            self.* = trial;
            return null;
        };
        if (destination.len < staged.bytes.len)
            return error.OggPacketBufferTooSmall;
        @memcpy(destination[0..staged.bytes.len], staged.bytes);
        var packet = staged;
        packet.bytes = destination[0..staged.bytes.len];
        self.* = trial;
        return packet;
    }

    pub fn valid(
        self: *const FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) bool {
        self.validateState(
            page_storage,
            packet_storage,
        ) catch return false;
        return true;
    }

    fn nextInPlace(
        self: *FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) !?Packet {
        try self.validateState(page_storage, packet_storage);
        if (self.packet_index == self.pages.limits.max_packets and
            self.packet_index != std.math.maxInt(u64))
        {
            const page_exhausted = if (self.page) |page|
                self.segment_index == page.lacing_values.len
            else
                true;
            if (self.packet_bytes == 0 and
                self.pages.offset == self.pages.file_size and
                page_exhausted)
            {
                return null;
            }
            return error.OggPacketLimitExceeded;
        }
        if (self.packet_index != std.math.maxInt(u64) and
            self.packets_to_skip >=
                self.pages.limits.max_packets - self.packet_index)
        {
            return error.OggPacketLimitExceeded;
        }
        const checkpoint: ?FilePacketCheckpoint =
            if (self.packet_bytes == 0)
                self.packetCheckpoint()
            else
                null;
        if (self.page_storage_pointer) |pointer| {
            const packet_pointer = self.packet_storage_pointer orelse
                return error.InvalidOggFilePacketReaderState;
            if (pointer != page_storage.ptr or
                packet_pointer != packet_storage.ptr or
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
            const page_exhausted = if (self.page) |page|
                self.segment_index == page.lacing_values.len
            else
                true;
            if (page_exhausted) {
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
                const loaded_page = self.page orelse
                    return error.InvalidOggFilePacketReaderState;
                try validatePacketPageCursor(
                    loaded_page,
                    self.segment_index,
                    self.body_offset,
                );
                if (loaded_page.beginning and
                    !preserve_logical_index)
                    self.logical_stream_packet_index = 0;
            }
            const page = self.page orelse
                return error.InvalidOggFilePacketReaderState;
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
            if (self.packet_index == std.math.maxInt(u64) or
                self.logical_stream_packet_index == std.math.maxInt(u64))
                return error.OggPacketCountOverflow;
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
            const packet_pointer = self.packet_storage_pointer orelse
                return error.InvalidOggFilePacketReaderState;
            if (page_pointer != page_storage.ptr or
                packet_pointer != packet_storage.ptr or
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
        pages.pages_read -= 1;
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
        try self.validateStorageBinding(page_storage, packet_storage);
        self.pages.validateState() catch
            return error.InvalidOggFilePacketReaderState;
        if ((self.page_storage_pointer == null) !=
            (self.packet_storage_pointer == null) or
            self.packet_bytes > packet_storage.len or
            self.packet_index > self.pages.limits.max_packets or
            self.packets_to_skip >
                std.math.maxInt(u64) -
                    self.logical_stream_packet_index)
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
            page_storage.len < page.byte_length or
            self.pages.pages_read == 0)
            return error.InvalidOggFilePacketReaderState;
        if (self.page_storage_pointer == null)
            return error.InvalidOggFilePacketReaderState;
        const page_bytes: usize = page.byte_length;
        validateRetainedPageStorageRanges(
            page,
            page_storage[0..page_bytes],
        ) catch return error.InvalidOggFilePacketReaderState;
        const exhausted = self.segment_index == page.lacing_values.len;
        if (!exhausted) {
            _ = validateRetainedOggPage(
                page,
                page_storage[0..page_bytes],
                page.byte_offset,
            ) catch return error.InvalidOggFilePacketReaderState;
        }
        const expected_offset = std.math.add(
            u64,
            page.byte_offset,
            @as(u64, page.byte_length),
        ) catch return error.InvalidOggFilePacketReaderState;
        const packet_continues = !exhausted and
            page.lacing_values.len != 0 and
            page.lacing_values[page.lacing_values.len - 1] == 255;
        if (self.pages.offset < expected_offset or
            (!exhausted and self.pages.offset != expected_offset) or
            page.logical_stream_index != self.pages.logical_stream_index or
            self.pages.serial_number != page.serial_number or
            self.pages.expected_sequence != page.sequence_number +% 1 or
            (!exhausted and
                self.pages.packet_continues != packet_continues) or
            self.pages.ended != page.end)
        {
            return error.InvalidOggFilePacketReaderState;
        }
        try validatePacketPageCursor(
            page,
            self.segment_index,
            self.body_offset,
        );
    }

    fn validateStorageBinding(
        self: *const FilePacketReader,
        page_storage: []u8,
        packet_storage: []u8,
    ) !void {
        const page_pointer = self.page_storage_pointer orelse {
            if (self.packet_storage_pointer != null or
                self.page_storage_length != 0 or
                self.packet_storage_length != 0)
            {
                return error.InvalidOggFilePacketReaderState;
            }
            return;
        };
        const packet_pointer = self.packet_storage_pointer orelse
            return error.InvalidOggFilePacketReaderState;
        if (page_pointer != page_storage.ptr or
            packet_pointer != packet_storage.ptr or
            self.page_storage_length != page_storage.len or
            self.packet_storage_length != packet_storage.len)
        {
            return error.OggReaderStorageChanged;
        }
    }
};

pub const FilePacketCheckpoint = struct {
    pages: FilePageReader,
    reload_segment_index: usize = 0,
    reload_body_offset: usize = 0,
    preserve_logical_index_on_reload: bool = false,
    packet_index: u64,
    logical_stream_packet_index: u64,
    packets_to_skip: u16,
};

pub fn validatePacketPageCursor(
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

pub const PacketLayout = struct {
    segment_count: usize,
    page_count: usize,
    encoded_bytes: usize,
};

pub fn packetLayout(packet_bytes: usize) !PacketLayout {
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

pub fn committedPageStateValid(
    byte_count: u64,
    sequence_number: u32,
    began: bool,
    ended: bool,
) bool {
    if (ended and !began) return false;
    if (!began)
        return byte_count == 0 and sequence_number == 0;
    const minimum_page_bytes: u64 = 28;
    const maximum_bytes: u64 = maximum_page_bytes;
    if (byte_count < minimum_page_bytes) return false;
    const minimum_pages = (byte_count - 1) / maximum_bytes + 1;
    const maximum_pages = byte_count / minimum_page_bytes;
    const sequence_period = @as(u64, 1) << 32;
    var candidate: u64 = if (sequence_number == 0)
        sequence_period
    else
        sequence_number;
    if (candidate < minimum_pages) {
        const delta = minimum_pages - candidate;
        const periods = (delta - 1) / sequence_period + 1;
        candidate = std.math.add(
            u64,
            candidate,
            std.math.mul(u64, periods, sequence_period) catch return false,
        ) catch return false;
    }
    return candidate <= maximum_pages;
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

    pub fn valid(self: *const StreamWriter) bool {
        return self.byte_count <= self.destination.len and
            committedPageStateValid(
                self.byte_count,
                self.sequence_number,
                self.began,
                self.ended,
            );
    }

    pub fn appendPacket(
        self: *StreamWriter,
        packet: []const u8,
        granule_position: u64,
        beginning: bool,
        end: bool,
    ) !void {
        if (!self.valid()) return error.InvalidOggStreamWriterState;
        if (self.ended) return error.OggStreamAlreadyEnded;
        if (beginning != !self.began)
            return error.InvalidOggBeginningOfStream;
        if (packet.len != 0 and byteRangesOverlap(
            @intFromPtr(self.destination.ptr),
            self.destination.len,
            @intFromPtr(packet.ptr),
            packet.len,
        )) return error.OverlappingOggWriterStorage;
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
        if (!self.valid()) return &.{};
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
        try self.operations.sync(self.io, self.file);
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
        return committedPageStateValid(
            self.byte_count,
            self.sequence_number,
            self.began,
            self.ended,
        );
    }
};

fn sameByteRange(first: []const u8, second: []const u8) bool {
    return first.len == second.len and first.ptr == second.ptr;
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

fn pageChecksum(page: []const u8) u32 {
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
