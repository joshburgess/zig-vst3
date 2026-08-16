const std = @import("std");
const file_reader_io = @import("../file_reader_io.zig");
const syntax = @import("syntax.zig");
const decoder = @import("decoder.zig");
const metadata = @import("metadata.zig");

const Version = syntax.Version;
const maximum_free_format_frame_bytes =
    syntax.maximum_free_format_frame_bytes;
const Limits = syntax.Limits;
const default_limits = syntax.default_limits;
const decoder_delay_samples = syntax.decoder_delay_samples;
const Header = syntax.Header;
const headersCompatible = syntax.headersCompatible;
const readU32 = syntax.readU32;
const byteRangesOverlap = syntax.byteRangesOverlap;
const SideInformation = syntax.SideInformation;
const MainData = syntax.MainData;
const MainDataReservoir = syntax.MainDataReservoir;
const parseSideInformation = syntax.parseSideInformation;
const DecoderFormat = decoder.DecoderFormat;
const formatFromHeader = decoder.formatFromHeader;
const FrameDecoder = decoder.FrameDecoder;
const StreamDecoder = decoder.StreamDecoder;
const PcmFrame = decoder.PcmFrame;
const mp3SampleRateValid = decoder.mp3SampleRateValid;
const mp3SamplesPerFrameForRate =
    decoder.mp3SamplesPerFrameForRate;
const headerStateValid = decoder.headerStateValid;

pub const XingKind = metadata.XingKind;
pub const Xing = metadata.Xing;
pub const Vbri = metadata.Vbri;
pub const VbriSummary = metadata.VbriSummary;
pub const Summary = metadata.Summary;

pub const Frame = struct {
    offset: usize,
    bytes: []const u8,
    header: Header,
    xing: ?Xing,
    vbri: ?Vbri,

    pub fn parse(encoded: []const u8, offset: usize) !Frame {
        if (offset > encoded.len or encoded.len - offset < 4)
            return error.TruncatedMp3Header;
        const header = try Header.parse(encoded[offset..]);
        const free_base = if (header.free_format)
            try inferMemoryFreeFormatBase(
                encoded,
                offset,
                encoded.len,
                header,
            )
        else
            null;
        const frame_bytes = try resolvedFrameBytes(
            header,
            free_base,
        );
        if (frame_bytes < 4 or frame_bytes > encoded.len - offset)
            return error.TruncatedMp3Frame;
        return frameAtKnownLength(
            encoded,
            offset,
            header,
            frame_bytes,
        );
    }

    /// Return null when the frame does not carry a CRC.
    pub fn crcValid(self: Frame) !?bool {
        return frameCrcValid(self.bytes, self.header);
    }

    /// Parse the complete fixed side-information region.
    pub fn sideInformation(self: Frame) !SideInformation {
        return parseSideInformation(self.bytes, self.header);
    }
};

pub const SeekPoint = struct {
    frame_index: u64,
    sample_offset: u64,
    byte_offset: usize,
};

pub const FileFrame = struct {
    byte_offset: u64,
    bytes: []const u8,
    header: Header,
    xing: ?Xing,
    vbri: ?Vbri,

    /// Return null when the frame does not carry a CRC.
    pub fn crcValid(self: FileFrame) !?bool {
        return frameCrcValid(self.bytes, self.header);
    }

    /// Parse the complete fixed side-information region.
    pub fn sideInformation(self: FileFrame) !SideInformation {
        return parseSideInformation(self.bytes, self.header);
    }
};

pub const FileSummary = struct {
    audio_offset: u64,
    audio_bytes: u64,
    frame_count: u64,
    sample_count: u64,
    sample_rate: u32,
    channels: u8,
    first_xing: ?Xing,
    first_vbri: ?VbriSummary,

    pub fn durationSeconds(self: FileSummary) f64 {
        return @as(f64, @floatFromInt(self.sample_count)) /
            @as(f64, @floatFromInt(self.sample_rate));
    }
};

pub const Stream = struct {
    encoded: []const u8,
    audio_start: usize,
    audio_end: usize,
    cursor: usize,
    first_header: ?Header = null,
    frame_index: u64 = 0,
    sample_offset: u64 = 0,
    free_frame_base_bytes: ?usize = null,
    limits: Limits = default_limits,

    pub fn init(encoded: []const u8) !Stream {
        return initWithLimits(encoded, default_limits);
    }

    pub fn initWithLimits(encoded: []const u8, limits: Limits) !Stream {
        try limits.validate();
        const encoded_bytes = std.math.cast(u64, encoded.len) orelse
            return error.Mp3StreamLimitExceeded;
        if (encoded_bytes > limits.max_stream_bytes)
            return error.Mp3StreamLimitExceeded;
        const audio_start = try leadingTagBytes(encoded);
        const audio_end = trailingTagStart(encoded, audio_start);
        if (audio_end - audio_start < 4) return error.Mp3StreamHasNoFrames;
        return .{
            .encoded = encoded,
            .audio_start = audio_start,
            .audio_end = audio_end,
            .cursor = audio_start,
            .limits = limits,
        };
    }

    pub fn valid(self: *const Stream) bool {
        self.validateState() catch return false;
        return true;
    }

    pub fn next(self: *Stream) !?Frame {
        try self.validateState();
        if (self.cursor == self.audio_end) return null;
        if (self.frame_index == self.limits.max_frames)
            return error.Mp3FrameLimitExceeded;
        if (self.audio_end - self.cursor < 4)
            return error.TrailingMp3Data;
        const header = try Header.parse(self.encoded[self.cursor..]);
        const next_free_base = if (header.free_format)
            self.free_frame_base_bytes orelse
                try inferMemoryFreeFormatBase(
                    self.encoded,
                    self.cursor,
                    self.audio_end,
                    header,
                )
        else
            null;
        const frame_bytes = try resolvedFrameBytes(
            header,
            next_free_base,
        );
        if (frame_bytes > self.audio_end - self.cursor)
            return error.TruncatedMp3Frame;
        const frame = try frameAtKnownLength(
            self.encoded[0..self.audio_end],
            self.cursor,
            header,
            frame_bytes,
        );
        if (self.first_header) |first| {
            if (!headersCompatible(first, frame.header))
                return error.Mp3StreamFormatChanged;
        }
        const next_cursor = std.math.add(
            usize,
            self.cursor,
            frame.bytes.len,
        ) catch return error.Mp3ByteCountOverflow;
        const next_frame_index = std.math.add(
            u64,
            self.frame_index,
            1,
        ) catch return error.Mp3FrameCountOverflow;
        const next_sample_offset = std.math.add(
            u64,
            self.sample_offset,
            frame.header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        self.first_header = self.first_header orelse frame.header;
        self.free_frame_base_bytes = next_free_base;
        self.cursor = next_cursor;
        self.frame_index = next_frame_index;
        self.sample_offset = next_sample_offset;
        return frame;
    }

    /// Advances past at most `maximum_skip_bytes` to a compatible frame.
    pub fn resynchronize(
        self: *Stream,
        maximum_skip_bytes: usize,
    ) !usize {
        try self.validateState();
        if (maximum_skip_bytes == 0)
            return error.InvalidMp3ResynchronizationLimit;
        if (self.cursor >= self.audio_end -| 4)
            return error.Mp3ResynchronizationLimitReached;
        const first_candidate = std.math.add(
            usize,
            self.cursor,
            1,
        ) catch return error.Mp3ByteCountOverflow;
        const last_candidate = @min(
            self.audio_end - 4,
            std.math.add(
                usize,
                self.cursor,
                maximum_skip_bytes,
            ) catch self.audio_end - 4,
        );
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            const header = Header.parse(
                self.encoded[candidate..self.audio_end],
            ) catch continue;
            if (self.first_header) |first| {
                if (!headersCompatible(first, header)) continue;
            }
            const next_free_base = if (header.free_format)
                self.free_frame_base_bytes orelse
                    inferMemoryFreeFormatBase(
                        self.encoded,
                        candidate,
                        self.audio_end,
                        header,
                    ) catch continue
            else
                null;
            const frame_bytes = resolvedFrameBytes(
                header,
                next_free_base,
            ) catch continue;
            if (frame_bytes > self.audio_end - candidate)
                continue;
            const candidate_frame = frameAtKnownLength(
                self.encoded[0..self.audio_end],
                candidate,
                header,
                frame_bytes,
            ) catch continue;
            if (!frameRecoveryCandidateValid(candidate_frame)) continue;
            if (self.first_header == null) {
                const following = std.math.add(
                    usize,
                    candidate,
                    frame_bytes,
                ) catch continue;
                if (following != self.audio_end) {
                    if (following > self.audio_end -| 4)
                        continue;
                    const following_header = Header.parse(
                        self.encoded[following..self.audio_end],
                    ) catch continue;
                    if (!headersCompatible(header, following_header))
                        continue;
                }
            }
            const skipped = candidate - self.cursor;
            self.cursor = candidate;
            self.free_frame_base_bytes = next_free_base;
            return skipped;
        }
        return error.Mp3ResynchronizationLimitReached;
    }

    fn validateState(self: *const Stream) !void {
        self.limits.validate() catch return error.InvalidMp3StreamState;
        const encoded_bytes = std.math.cast(u64, self.encoded.len) orelse
            return error.InvalidMp3StreamState;
        if (self.audio_start > self.audio_end or
            self.audio_end > self.encoded.len or
            self.cursor < self.audio_start or
            self.cursor > self.audio_end or
            encoded_bytes > self.limits.max_stream_bytes or
            self.frame_index > self.limits.max_frames)
        {
            return error.InvalidMp3StreamState;
        }
        const first = self.first_header orelse {
            if (self.audio_end - self.audio_start < 4 or
                self.cursor > self.audio_end - 4 or
                self.frame_index != 0 or self.sample_offset != 0)
                return error.InvalidMp3StreamState;
            if (self.free_frame_base_bytes) |base| {
                if (base < 4 or base > maximum_free_format_frame_bytes)
                    return error.InvalidMp3StreamState;
            }
            return;
        };
        if (!headerStateValid(first))
            return error.InvalidMp3StreamState;
        if (self.frame_index == 0)
            return error.InvalidMp3StreamState;
        const expected_samples = std.math.mul(
            u64,
            self.frame_index,
            first.samplesPerFrame(),
        ) catch return error.InvalidMp3StreamState;
        if (self.sample_offset != expected_samples)
            return error.InvalidMp3StreamState;
        const consumed_bytes = std.math.cast(
            u64,
            self.cursor - self.audio_start,
        ) orelse return error.InvalidMp3StreamState;
        if (!mp3FrameProgressValid(
            self.frame_index,
            consumed_bytes,
            first,
        )) return error.InvalidMp3StreamState;
        if (first.free_format) {
            const base = self.free_frame_base_bytes orelse
                return error.InvalidMp3StreamState;
            if (base < minimumFrameBytes(first) or
                base > maximum_free_format_frame_bytes)
            {
                return error.InvalidMp3StreamState;
            }
            _ = resolvedFrameBytes(first, base) catch
                return error.InvalidMp3StreamState;
        } else if (self.free_frame_base_bytes != null) {
            return error.InvalidMp3StreamState;
        }
    }

    pub fn summarize(encoded: []const u8) !Summary {
        return summarizeWithLimits(encoded, default_limits);
    }

    pub fn summarizeWithLimits(encoded: []const u8, limits: Limits) !Summary {
        var stream = try Stream.initWithLimits(encoded, limits);
        var first_xing: ?Xing = null;
        var first_vbri: ?Vbri = null;
        while (try stream.next()) |frame| {
            if (stream.frame_index == 1) {
                first_xing = frame.xing;
                first_vbri = frame.vbri;
            }
        }
        const first = stream.first_header orelse
            return error.Mp3StreamHasNoFrames;
        return .{
            .audio_offset = stream.audio_start,
            .audio_bytes = stream.audio_end - stream.audio_start,
            .frame_count = stream.frame_index,
            .sample_count = stream.sample_offset,
            .sample_rate = first.sample_rate,
            .channels = first.channels(),
            .first_xing = first_xing,
            .first_vbri = first_vbri,
        };
    }
};

pub const FileReader = struct {
    io: std.Io,
    file: std.Io.File,
    audio_start: u64,
    audio_end: u64,
    offset: u64,
    first_header: Header,
    frame_index: u64 = 0,
    sample_offset: u64 = 0,
    free_frame_base_bytes: ?usize = null,
    limits: Limits = default_limits,

    /// The caller owns the file and frame storage for the reader lifetime.
    pub fn init(io: std.Io, file: std.Io.File) !FileReader {
        return initWithLimits(io, file, default_limits);
    }

    pub fn initWithLimits(
        io: std.Io,
        file: std.Io.File,
        limits: Limits,
    ) !FileReader {
        try limits.validate();
        const file_size = (try file.stat(io)).size;
        if (file_size > limits.max_stream_bytes)
            return error.Mp3StreamLimitExceeded;
        if (file_size < 3) return error.Mp3StreamHasNoFrames;

        var prefix: [10]u8 = undefined;
        const prefix_bytes: usize = @intCast(@min(file_size, prefix.len));
        try readExactAt(io, file, 0, prefix[0..prefix_bytes]);
        const audio_start = try leadingFileTagBytes(
            prefix[0..prefix_bytes],
            file_size,
        );

        var audio_end = file_size;
        if (audio_start <= file_size and
            file_size - audio_start >= 128)
        {
            var marker: [3]u8 = undefined;
            try readExactAt(io, file, file_size - 128, &marker);
            if (std.mem.eql(u8, &marker, "TAG"))
                audio_end -= 128;
        }
        if (audio_end < audio_start or audio_end - audio_start < 4)
            return error.Mp3StreamHasNoFrames;

        var header_bytes: [4]u8 = undefined;
        try readExactAt(io, file, audio_start, &header_bytes);
        const first_header = try Header.parse(&header_bytes);
        const free_frame_base_bytes = if (first_header.free_format)
            try inferFileFreeFormatBase(
                io,
                file,
                audio_start,
                audio_end,
                first_header,
            )
        else
            null;
        return .{
            .io = io,
            .file = file,
            .audio_start = audio_start,
            .audio_end = audio_end,
            .offset = audio_start,
            .first_header = first_header,
            .free_frame_base_bytes = free_frame_base_bytes,
            .limits = limits,
        };
    }

    pub fn valid(self: *const FileReader) bool {
        self.validateState() catch return false;
        return true;
    }

    /// Returned frame slices borrow storage until the caller reuses it.
    pub fn next(self: *FileReader, storage: []u8) !?FileFrame {
        try self.validateState();
        if (self.offset == self.audio_end) return null;
        if (self.frame_index == self.limits.max_frames)
            return error.Mp3FrameLimitExceeded;
        if (self.audio_end - self.offset < 4)
            return error.TrailingMp3Data;

        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, self.offset, &header_bytes);
        const header = try Header.parse(&header_bytes);
        if (!headersCompatible(self.first_header, header))
            return error.Mp3StreamFormatChanged;
        const frame_bytes = try resolvedFrameBytes(
            header,
            self.free_frame_base_bytes,
        );
        if (frame_bytes > self.audio_end - self.offset)
            return error.TruncatedMp3Frame;
        if (storage.len < frame_bytes)
            return error.Mp3FrameBufferTooSmall;
        const next_offset = std.math.add(
            u64,
            self.offset,
            frame_bytes,
        ) catch return error.Mp3ByteCountOverflow;
        const next_frame_index = std.math.add(
            u64,
            self.frame_index,
            1,
        ) catch return error.Mp3FrameCountOverflow;
        const next_sample_offset = std.math.add(
            u64,
            self.sample_offset,
            header.samplesPerFrame(),
        ) catch return error.Mp3SampleCountOverflow;
        try readExactAt(
            self.io,
            self.file,
            self.offset,
            storage[0..frame_bytes],
        );
        const parsed = try frameAtKnownLength(
            storage[0..frame_bytes],
            0,
            header,
            frame_bytes,
        );
        const byte_offset = self.offset;
        self.offset = next_offset;
        self.frame_index = next_frame_index;
        self.sample_offset = next_sample_offset;
        return .{
            .byte_offset = byte_offset,
            .bytes = parsed.bytes,
            .header = parsed.header,
            .xing = parsed.xing,
            .vbri = parsed.vbri,
        };
    }

    /// Stage a complete frame before advancing or changing destination.
    pub fn nextTransactional(
        self: *FileReader,
        storage: []u8,
        scratch: []u8,
    ) !?FileFrame {
        try self.validateState();
        if (byteRangesOverlap(
            @intFromPtr(storage.ptr),
            storage.len,
            @intFromPtr(scratch.ptr),
            scratch.len,
        )) return error.OverlappingMp3FileReaderBuffers;

        var staged_reader = self.*;
        const staged = try staged_reader.next(scratch) orelse return null;
        if (storage.len < staged.bytes.len)
            return error.Mp3FrameBufferTooSmall;
        var published_vbri = staged.vbri;
        if (published_vbri) |*vbri| {
            const frame_start = @intFromPtr(staged.bytes.ptr);
            const toc_start = @intFromPtr(vbri.toc.ptr);
            if (toc_start < frame_start)
                return error.InvalidVbriTocSize;
            const toc_offset = toc_start - frame_start;
            if (toc_offset > staged.bytes.len or
                vbri.toc.len > staged.bytes.len - toc_offset)
            {
                return error.InvalidVbriTocSize;
            }
            vbri.toc = storage[toc_offset..][0..vbri.toc.len];
        }
        @memcpy(storage[0..staged.bytes.len], staged.bytes);
        self.* = staged_reader;
        return .{
            .byte_offset = staged.byte_offset,
            .bytes = storage[0..staged.bytes.len],
            .header = staged.header,
            .xing = staged.xing,
            .vbri = published_vbri,
        };
    }

    /// Advances past at most `maximum_skip_bytes` to a compatible frame.
    pub fn resynchronize(
        self: *FileReader,
        maximum_skip_bytes: u64,
    ) !u64 {
        try self.validateState();
        if (maximum_skip_bytes == 0)
            return error.InvalidMp3ResynchronizationLimit;
        if (self.offset >= self.audio_end -| 4)
            return error.Mp3ResynchronizationLimitReached;
        const first_candidate = std.math.add(
            u64,
            self.offset,
            1,
        ) catch return error.Mp3ByteCountOverflow;
        const last_candidate = @min(
            self.audio_end - 4,
            std.math.add(
                u64,
                self.offset,
                maximum_skip_bytes,
            ) catch self.audio_end - 4,
        );
        var header_bytes: [4]u8 = undefined;
        var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
        var candidate = first_candidate;
        while (candidate <= last_candidate) : (candidate += 1) {
            readExactAt(
                self.io,
                self.file,
                candidate,
                &header_bytes,
            ) catch continue;
            const header = Header.parse(&header_bytes) catch continue;
            if (!headersCompatible(self.first_header, header)) continue;
            const frame_bytes = resolvedFrameBytes(
                header,
                self.free_frame_base_bytes,
            ) catch continue;
            if (frame_bytes > self.audio_end - candidate)
                continue;
            if (frame_bytes > frame_storage.len)
                continue;
            readExactAt(
                self.io,
                self.file,
                candidate,
                frame_storage[0..frame_bytes],
            ) catch continue;
            const candidate_frame = frameAtKnownLength(
                frame_storage[0..frame_bytes],
                0,
                header,
                frame_bytes,
            ) catch continue;
            if (!frameRecoveryCandidateValid(candidate_frame)) continue;
            const skipped = candidate - self.offset;
            self.offset = candidate;
            return skipped;
        }
        return error.Mp3ResynchronizationLimitReached;
    }

    pub fn seek(self: *FileReader, point: SeekPoint) !void {
        try self.validateState();
        const byte_offset: u64 = @intCast(point.byte_offset);
        if (byte_offset < self.audio_start or
            byte_offset > self.audio_end -| 4)
            return error.InvalidMp3SeekPoint;
        const expected_sample = std.math.mul(
            u64,
            point.frame_index,
            self.first_header.samplesPerFrame(),
        ) catch return error.InvalidMp3SeekPoint;
        if (point.sample_offset != expected_sample)
            return error.InvalidMp3SeekPoint;
        if (point.frame_index > self.limits.max_frames)
            return error.InvalidMp3SeekPoint;
        if (!mp3FrameProgressValid(
            point.frame_index,
            byte_offset - self.audio_start,
            self.first_header,
        )) return error.InvalidMp3SeekPoint;
        var header_bytes: [4]u8 = undefined;
        try readExactAt(self.io, self.file, byte_offset, &header_bytes);
        const header = Header.parse(&header_bytes) catch
            return error.InvalidMp3SeekPoint;
        if (!headersCompatible(self.first_header, header))
            return error.InvalidMp3SeekPoint;
        const frame_bytes = resolvedFrameBytes(
            header,
            self.free_frame_base_bytes,
        ) catch return error.InvalidMp3SeekPoint;
        if (frame_bytes > self.audio_end - byte_offset)
            return error.InvalidMp3SeekPoint;
        var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
        if (frame_bytes > frame_storage.len)
            return error.InvalidMp3SeekPoint;
        try readExactAt(
            self.io,
            self.file,
            byte_offset,
            frame_storage[0..frame_bytes],
        );
        const frame = frameAtKnownLength(
            frame_storage[0..frame_bytes],
            0,
            header,
            frame_bytes,
        ) catch return error.InvalidMp3SeekPoint;
        if (!frameRecoveryCandidateValid(frame))
            return error.InvalidMp3SeekPoint;
        self.offset = byte_offset;
        self.frame_index = point.frame_index;
        self.sample_offset = point.sample_offset;
    }

    fn validateState(self: *const FileReader) !void {
        self.limits.validate() catch
            return error.InvalidMp3FileReaderState;
        if (self.audio_start > self.audio_end or
            self.audio_end - self.audio_start < 4 or
            self.offset < self.audio_start or
            self.offset > self.audio_end or
            self.audio_end > self.limits.max_stream_bytes or
            self.frame_index > self.limits.max_frames)
        {
            return error.InvalidMp3FileReaderState;
        }
        if (!headerStateValid(self.first_header))
            return error.InvalidMp3FileReaderState;
        const expected_samples = std.math.mul(
            u64,
            self.frame_index,
            self.first_header.samplesPerFrame(),
        ) catch return error.InvalidMp3FileReaderState;
        if (self.sample_offset != expected_samples)
            return error.InvalidMp3FileReaderState;
        if (!mp3FrameProgressValid(
            self.frame_index,
            self.offset - self.audio_start,
            self.first_header,
        )) return error.InvalidMp3FileReaderState;
        if (self.first_header.free_format) {
            const base = self.free_frame_base_bytes orelse
                return error.InvalidMp3FileReaderState;
            if (base < minimumFrameBytes(self.first_header) or
                base > maximum_free_format_frame_bytes)
            {
                return error.InvalidMp3FileReaderState;
            }
            _ = resolvedFrameBytes(self.first_header, base) catch
                return error.InvalidMp3FileReaderState;
        } else if (self.free_frame_base_bytes != null) {
            return error.InvalidMp3FileReaderState;
        }
    }

    pub fn summarize(
        io: std.Io,
        file: std.Io.File,
        storage: []u8,
    ) !FileSummary {
        return summarizeWithLimits(
            io,
            file,
            storage,
            default_limits,
        );
    }

    pub fn summarizeWithLimits(
        io: std.Io,
        file: std.Io.File,
        storage: []u8,
        limits: Limits,
    ) !FileSummary {
        var reader = try FileReader.initWithLimits(io, file, limits);
        var first_xing: ?Xing = null;
        var first_vbri: ?VbriSummary = null;
        while (try reader.next(storage)) |frame| {
            if (reader.frame_index == 1) {
                first_xing = frame.xing;
                if (frame.vbri) |vbri|
                    first_vbri = VbriSummary.from(vbri);
            }
        }
        return .{
            .audio_offset = reader.audio_start,
            .audio_bytes = reader.audio_end - reader.audio_start,
            .frame_count = reader.frame_index,
            .sample_count = reader.sample_offset,
            .sample_rate = reader.first_header.sample_rate,
            .channels = reader.first_header.channels(),
            .first_xing = first_xing,
            .first_vbri = first_vbri,
        };
    }
};

pub fn requiredSeekPoints(encoded: []const u8, stride: u32) !usize {
    if (stride == 0) return error.InvalidMp3SeekStride;
    var stream = try Stream.init(encoded);
    var count: usize = 0;
    while (try stream.next()) |_| {
        const index = stream.frame_index - 1;
        if (index % stride == 0)
            count = std.math.add(
                usize,
                count,
                1,
            ) catch return error.Mp3SeekPointCountOverflow;
    }
    return count;
}

pub fn buildSeekIndex(
    encoded: []const u8,
    stride: u32,
    destination: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(encoded.ptr),
        encoded.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    )) return error.OverlappingMp3SeekStorage;
    const required = try requiredSeekPoints(encoded, stride);
    if (destination.len < required) return error.Mp3SeekIndexTooSmall;

    var stream = try Stream.init(encoded);
    var count: usize = 0;
    while (true) {
        const frame_index = stream.frame_index;
        const sample_offset = stream.sample_offset;
        const byte_offset = stream.cursor;
        const frame = try stream.next() orelse break;
        _ = frame;
        if (frame_index % stride != 0) continue;
        destination[count] = .{
            .frame_index = frame_index,
            .sample_offset = sample_offset,
            .byte_offset = byte_offset,
        };
        count += 1;
    }
    if (count != required) return error.Mp3SeekIndexChanged;
    return destination[0..count];
}

pub fn findSeekPoint(points: []const SeekPoint, target_sample: u64) !SeekPoint {
    if (points.len == 0) return error.EmptyMp3SeekIndex;
    var selected = points[0];
    if (selected.frame_index != 0 or selected.sample_offset != 0)
        return error.InvalidMp3SeekIndex;
    var previous = selected;
    for (points[1..]) |point| {
        if (point.frame_index <= previous.frame_index or
            point.sample_offset <= previous.sample_offset or
            point.byte_offset <= previous.byte_offset)
            return error.InvalidMp3SeekIndex;
        if (point.sample_offset <= target_sample) selected = point;
        previous = point;
    }
    return selected;
}

pub fn resolvedFrameBytes(
    header: Header,
    free_base_bytes: ?usize,
) !usize {
    if (!header.free_format) return header.frameBytes();
    const base = free_base_bytes orelse
        return error.CannotInferFreeFormatMp3FrameSize;
    return std.math.add(
        usize,
        base,
        @intFromBool(header.padding),
    ) catch return error.Mp3ByteCountOverflow;
}

pub fn minimumFrameBytes(header: Header) usize {
    return 4 + @as(usize, if (header.crc_present) 2 else 0) +
        header.sideInformationBytes();
}

fn mp3FrameProgressValid(
    frame_count: u64,
    consumed_bytes: u64,
    header: Header,
) bool {
    const minimum_compatible_bytes: u64 =
        4 + @as(u64, header.sideInformationBytes());
    const minimum_consumed = std.math.mul(
        u64,
        frame_count,
        minimum_compatible_bytes,
    ) catch return false;
    return consumed_bytes >= minimum_consumed;
}

fn inferMemoryFreeFormatBase(
    encoded: []const u8,
    offset: usize,
    audio_end: usize,
    header: Header,
) !usize {
    if (!header.free_format)
        return error.InvalidFreeFormatMp3Header;
    const first_candidate = std.math.add(
        usize,
        offset,
        minimumFrameBytes(header),
    ) catch return error.Mp3ByteCountOverflow;
    const maximum_candidate = @min(
        audio_end -| 4,
        std.math.add(
            usize,
            offset,
            maximum_free_format_frame_bytes,
        ) catch std.math.maxInt(usize),
    );
    var candidate = first_candidate;
    while (candidate <= maximum_candidate) : (candidate += 1) {
        const candidate_header =
            Header.parse(encoded[candidate..audio_end]) catch continue;
        if (!headersCompatible(header, candidate_header)) continue;
        const frame_bytes = candidate - offset;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
        if (!memoryFreeFormatFrameValid(
            encoded,
            offset,
            audio_end,
            header,
            frame_bytes,
        )) continue;
        if (try confirmsMemoryFreeFormat(
            encoded,
            candidate,
            audio_end,
            candidate_header,
            base,
        )) return base;
    }
    return error.CannotInferFreeFormatMp3FrameSize;
}

fn confirmsMemoryFreeFormat(
    encoded: []const u8,
    candidate: usize,
    audio_end: usize,
    header: Header,
    base: usize,
) !bool {
    const frame_bytes = try resolvedFrameBytes(header, base);
    if (!memoryFreeFormatFrameValid(
        encoded,
        candidate,
        audio_end,
        header,
        frame_bytes,
    )) return false;
    const next = std.math.add(
        usize,
        candidate,
        frame_bytes,
    ) catch return false;
    if (next == audio_end) return true;
    if (next > audio_end -| 4) return false;
    const next_header =
        Header.parse(encoded[next..audio_end]) catch return false;
    if (!headersCompatible(header, next_header)) return false;
    const next_frame_bytes = resolvedFrameBytes(
        next_header,
        base,
    ) catch return false;
    return memoryFreeFormatFrameValid(
        encoded,
        next,
        audio_end,
        next_header,
        next_frame_bytes,
    );
}

fn memoryFreeFormatFrameValid(
    encoded: []const u8,
    offset: usize,
    audio_end: usize,
    header: Header,
    frame_bytes: usize,
) bool {
    if (audio_end > encoded.len or
        offset > audio_end or
        frame_bytes > audio_end - offset)
        return false;
    const frame = frameAtKnownLength(
        encoded[0..audio_end],
        offset,
        header,
        frame_bytes,
    ) catch return false;
    return frameRecoveryCandidateValid(frame);
}

fn inferFileFreeFormatBase(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    audio_end: u64,
    header: Header,
) !usize {
    if (!header.free_format)
        return error.InvalidFreeFormatMp3Header;
    const first_candidate = std.math.add(
        u64,
        offset,
        minimumFrameBytes(header),
    ) catch return error.Mp3ByteCountOverflow;
    const maximum_candidate = @min(
        audio_end -| 4,
        std.math.add(
            u64,
            offset,
            maximum_free_format_frame_bytes,
        ) catch std.math.maxInt(u64),
    );
    var candidate = first_candidate;
    var header_bytes: [4]u8 = undefined;
    var frame_storage: [maximum_free_format_frame_bytes]u8 = undefined;
    while (candidate <= maximum_candidate) : (candidate += 1) {
        try readExactAt(io, file, candidate, &header_bytes);
        const candidate_header =
            Header.parse(&header_bytes) catch continue;
        if (!headersCompatible(header, candidate_header)) continue;
        const frame_bytes = std.math.cast(
            usize,
            candidate - offset,
        ) orelse return error.Mp3ByteCountOverflow;
        const padding: usize = @intFromBool(header.padding);
        if (frame_bytes <= padding) continue;
        const base = frame_bytes - padding;
        if (!try fileFreeFormatFrameValid(
            io,
            file,
            offset,
            audio_end,
            header,
            frame_bytes,
            &frame_storage,
        )) continue;
        if (try confirmsFileFreeFormat(
            io,
            file,
            candidate,
            audio_end,
            candidate_header,
            base,
            &frame_storage,
        )) return base;
    }
    return error.CannotInferFreeFormatMp3FrameSize;
}

fn confirmsFileFreeFormat(
    io: std.Io,
    file: std.Io.File,
    candidate: u64,
    audio_end: u64,
    header: Header,
    base: usize,
    frame_storage: []u8,
) !bool {
    const frame_bytes = try resolvedFrameBytes(header, base);
    if (!try fileFreeFormatFrameValid(
        io,
        file,
        candidate,
        audio_end,
        header,
        frame_bytes,
        frame_storage,
    )) return false;
    const next = std.math.add(
        u64,
        candidate,
        frame_bytes,
    ) catch return false;
    if (next == audio_end) return true;
    if (next > audio_end -| 4) return false;
    var next_bytes: [4]u8 = undefined;
    try readExactAt(io, file, next, &next_bytes);
    const next_header = Header.parse(&next_bytes) catch return false;
    if (!headersCompatible(header, next_header)) return false;
    const next_frame_bytes = resolvedFrameBytes(
        next_header,
        base,
    ) catch return false;
    return fileFreeFormatFrameValid(
        io,
        file,
        next,
        audio_end,
        next_header,
        next_frame_bytes,
        frame_storage,
    );
}

fn fileFreeFormatFrameValid(
    io: std.Io,
    file: std.Io.File,
    offset: u64,
    audio_end: u64,
    header: Header,
    frame_bytes: usize,
    storage: []u8,
) !bool {
    const frame_bytes_u64: u64 = @intCast(frame_bytes);
    if (offset > audio_end or
        frame_bytes_u64 > audio_end - offset or
        frame_bytes > storage.len)
        return false;
    try readExactAt(
        io,
        file,
        offset,
        storage[0..frame_bytes],
    );
    const frame = frameAtKnownLength(
        storage[0..frame_bytes],
        0,
        header,
        frame_bytes,
    ) catch return false;
    return frameRecoveryCandidateValid(frame);
}

pub fn frameAtKnownLength(
    encoded: []const u8,
    offset: usize,
    header: Header,
    frame_bytes: usize,
) !Frame {
    if (offset > encoded.len or
        frame_bytes < minimumFrameBytes(header) or
        frame_bytes > encoded.len - offset)
        return error.TruncatedMp3Frame;
    const bytes = encoded[offset .. offset + frame_bytes];
    return .{
        .offset = offset,
        .bytes = bytes,
        .header = header,
        .xing = try parseXing(bytes, header),
        .vbri = try parseVbri(bytes),
    };
}

fn frameCrcValid(bytes: []const u8, header: Header) !?bool {
    if (!header.crc_present) return null;
    const protected_end = std.math.add(
        usize,
        6,
        header.sideInformationBytes(),
    ) catch return error.TruncatedMp3Frame;
    if (bytes.len < protected_end)
        return error.TruncatedMp3Frame;
    const expected = readU16(bytes[4..6]);
    var crc = crc16(0xffff, bytes[2..4]);
    crc = crc16(crc, bytes[6..protected_end]);
    return crc == expected;
}

fn frameRecoveryCandidateValid(frame: Frame) bool {
    if (frameCrcValid(frame.bytes, frame.header) catch return false) |crc_valid| {
        if (!crc_valid) return false;
    }
    _ = parseSideInformation(frame.bytes, frame.header) catch return false;
    return true;
}

pub fn crc16(initial: u16, bytes: []const u8) u16 {
    var crc = initial;
    for (bytes) |byte| {
        var mask: u8 = 0x80;
        while (mask != 0) : (mask >>= 1) {
            const input_bit: u16 =
                if (byte & mask == 0) 0 else 1;
            const feedback = (crc >> 15) ^ input_bit;
            crc <<= 1;
            if (feedback != 0) crc ^= 0x8005;
        }
    }
    return crc;
}

pub fn requiredFileSeekPoints(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
) !usize {
    if (stride == 0) return error.InvalidMp3SeekStride;
    var reader = try FileReader.init(io, file);
    var count: usize = 0;
    while (try reader.next(frame_storage)) |_| {
        const index = reader.frame_index - 1;
        if (index % stride == 0)
            count = std.math.add(
                usize,
                count,
                1,
            ) catch return error.Mp3SeekPointCountOverflow;
    }
    return count;
}

pub fn buildFileSeekIndex(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
    destination: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    )) return error.OverlappingMp3SeekStorage;
    const required = try requiredFileSeekPoints(
        io,
        file,
        frame_storage,
        stride,
    );
    if (destination.len < required) return error.Mp3SeekIndexTooSmall;

    var reader = try FileReader.init(io, file);
    var count: usize = 0;
    while (true) {
        const frame_index = reader.frame_index;
        const sample_offset = reader.sample_offset;
        const byte_offset: usize = std.math.cast(
            usize,
            reader.offset,
        ) orelse return error.Mp3FileOffsetTooLarge;
        _ = try reader.next(frame_storage) orelse break;
        if (frame_index % stride != 0) continue;
        if (count >= destination.len)
            return error.Mp3SeekIndexChanged;
        destination[count] = .{
            .frame_index = frame_index,
            .sample_offset = sample_offset,
            .byte_offset = byte_offset,
        };
        count = std.math.add(
            usize,
            count,
            1,
        ) catch return error.Mp3SeekPointCountOverflow;
    }
    if (count != required) return error.Mp3SeekIndexChanged;
    return destination[0..count];
}

/// Stage the index so file changes cannot partially replace destination.
/// Frame, destination, and index scratch storage must be pairwise disjoint.
pub fn buildFileSeekIndexTransactional(
    io: std.Io,
    file: std.Io.File,
    frame_storage: []u8,
    stride: u32,
    destination: []SeekPoint,
    index_scratch: []SeekPoint,
) ![]const SeekPoint {
    const destination_bytes = std.math.mul(
        usize,
        destination.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    const scratch_bytes = std.math.mul(
        usize,
        index_scratch.len,
        @sizeOf(SeekPoint),
    ) catch return error.Mp3SeekIndexSizeOverflow;
    if (byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(destination.ptr),
        destination_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(frame_storage.ptr),
        frame_storage.len,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    ) or byteRangesOverlap(
        @intFromPtr(destination.ptr),
        destination_bytes,
        @intFromPtr(index_scratch.ptr),
        scratch_bytes,
    )) return error.OverlappingMp3SeekStorage;

    const staged = try buildFileSeekIndex(
        io,
        file,
        frame_storage,
        stride,
        index_scratch,
    );
    if (destination.len < staged.len)
        return error.Mp3SeekIndexTooSmall;
    @memcpy(destination[0..staged.len], staged);
    return destination[0..staged.len];
}

fn frameXingOffset(header: Header) usize {
    return 4 + header.sideInformationBytes();
}

fn isValidXingEncoderIdentifier(encoder: [9]u8) bool {
    var has_visible_byte = false;
    for (encoder) |byte| {
        if (byte < 0x20 or byte > 0x7e)
            return false;
        has_visible_byte = has_visible_byte or byte != ' ';
    }
    return has_visible_byte;
}

fn parseXing(frame: []const u8, header: Header) !?Xing {
    const offset = frameXingOffset(header);
    if (frame.len < offset + 4) return null;
    const marker = frame[offset .. offset + 4];
    const kind: XingKind = if (std.mem.eql(u8, marker, "Xing"))
        .variable
    else if (std.mem.eql(u8, marker, "Info"))
        .constant
    else
        return null;
    if (frame.len < offset + 8) return error.TruncatedXingHeader;
    const flags = readU32(frame[offset + 4 .. offset + 8]);
    if (flags & ~@as(u32, 0x7f) != 0 or
        (flags & 0x30 != 0 and flags & 0x40 == 0))
    {
        return error.InvalidXingFlags;
    }
    var cursor = offset + 8;
    var xing = Xing{
        .kind = kind,
        .frame_count = null,
        .stream_bytes = null,
        .toc = null,
        .quality = null,
        .encoder = null,
        .encoder_delay = null,
        .encoder_padding = null,
    };
    if (flags & 1 != 0) {
        xing.frame_count = try readOptionalU32(frame, &cursor);
    }
    if (flags & 2 != 0) {
        xing.stream_bytes = try readOptionalU32(frame, &cursor);
    }
    if (flags & 4 != 0) {
        if (frame.len -| cursor < 100) return error.TruncatedXingHeader;
        xing.toc = frame[cursor..][0..100].*;
        cursor += 100;
    }
    if (flags & 8 != 0) {
        xing.quality = try readOptionalU32(frame, &cursor);
    }
    if (flags & 0x10 != 0) {
        if (frame.len -| cursor < 20) return error.TruncatedXingHeader;
        cursor += 20;
    }
    if (flags & 0x20 != 0) {
        if (frame.len -| cursor < 20) return error.TruncatedXingHeader;
        cursor += 20;
    }

    if (frame.len -| cursor >= 24) {
        const encoder = frame[cursor..][0..9].*;
        xing.encoder = encoder;
        const delay_offset = cursor + 21;
        const delay_fields =
            readU24(frame[delay_offset .. delay_offset + 3]);
        if (delay_fields != 0 and
            isValidXingEncoderIdentifier(encoder))
        {
            xing.encoder_delay = @intCast(delay_fields >> 12);
            xing.encoder_padding = @intCast(delay_fields & 0xfff);
        }
    }
    return xing;
}

fn parseVbri(frame: []const u8) !?Vbri {
    const offset = 4 + 32;
    if (frame.len < offset + 4 or
        !std.mem.eql(u8, frame[offset .. offset + 4], "VBRI"))
        return null;
    if (frame.len < offset + 26) return error.TruncatedVbriHeader;
    const version = readU16(frame[offset + 4 .. offset + 6]);
    if (version != 1) return error.UnsupportedVbriVersion;
    const entry_count = readU16(frame[offset + 18 .. offset + 20]);
    const entry_bytes = readU16(frame[offset + 22 .. offset + 24]);
    if (entry_bytes < 1 or entry_bytes > 4)
        return error.InvalidVbriEntrySize;
    const toc_scale = readU16(frame[offset + 20 .. offset + 22]);
    if (toc_scale == 0)
        return error.InvalidVbriTocScale;
    const frames_per_entry =
        readU16(frame[offset + 24 .. offset + 26]);
    if (frames_per_entry == 0)
        return error.InvalidVbriFramesPerEntry;
    const toc_bytes = std.math.mul(
        usize,
        entry_count,
        entry_bytes,
    ) catch return error.VbriSizeOverflow;
    if (frame.len - (offset + 26) < toc_bytes)
        return error.TruncatedVbriToc;
    const result = Vbri{
        .version = version,
        .delay = readU16(frame[offset + 6 .. offset + 8]),
        .quality = readU16(frame[offset + 8 .. offset + 10]),
        .stream_bytes = readU32(frame[offset + 10 .. offset + 14]),
        .frame_count = readU32(frame[offset + 14 .. offset + 18]),
        .toc_entries = entry_count,
        .toc_scale = toc_scale,
        .entry_bytes = entry_bytes,
        .frames_per_entry = frames_per_entry,
        .toc = frame[offset + 26 ..][0..toc_bytes],
    };
    _ = try result.approximateByteOffsetForFrame(0);
    return result;
}

pub fn leadingTagBytes(encoded: []const u8) !usize {
    if (encoded.len < 3 or !std.mem.eql(u8, encoded[0..3], "ID3"))
        return 0;
    if (encoded.len < 10) return error.TruncatedLeadingId3Tag;
    const total = try leadingTagSize(encoded[0..10]);
    if (total > encoded.len) return error.TruncatedLeadingId3Tag;
    return total;
}

fn leadingTagSize(header: []const u8) !usize {
    const version = header[3];
    if (version < 2 or version > 4) return error.UnsupportedLeadingId3Tag;
    for (header[6..10]) |byte| {
        if (byte & 0x80 != 0) return error.InvalidLeadingId3Size;
    }
    const body_bytes =
        (@as(usize, header[6]) << 21) |
        (@as(usize, header[7]) << 14) |
        (@as(usize, header[8]) << 7) |
        header[9];
    const footer_bytes: usize =
        if (version == 4 and header[5] & 0x10 != 0) 10 else 0;
    return std.math.add(
        usize,
        10 + footer_bytes,
        body_bytes,
    ) catch return error.LeadingId3SizeOverflow;
}

fn leadingFileTagBytes(prefix: []const u8, file_size: u64) !u64 {
    if (prefix.len < 3 or !std.mem.eql(u8, prefix[0..3], "ID3"))
        return 0;
    if (prefix.len < 10) return error.TruncatedLeadingId3Tag;
    const total: u64 = try leadingTagSize(prefix[0..10]);
    if (total > file_size) return error.TruncatedLeadingId3Tag;
    return total;
}

pub fn trailingTagStart(encoded: []const u8, audio_start: usize) usize {
    if (audio_start <= encoded.len and
        encoded.len - audio_start >= 128 and
        std.mem.eql(u8, encoded[encoded.len - 128 ..][0..3], "TAG"))
        return encoded.len - 128;
    return encoded.len;
}

fn readOptionalU32(bytes: []const u8, cursor: *usize) !u32 {
    if (bytes.len -| cursor.* < 4) return error.TruncatedXingHeader;
    const value = readU32(bytes[cursor.*..][0..4]);
    cursor.* += 4;
    return value;
}

fn readU16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readU24(bytes: []const u8) u24 {
    return (@as(u24, bytes[0]) << 16) |
        (@as(u24, bytes[1]) << 8) |
        bytes[2];
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
        error.TruncatedMp3File,
    );
}
