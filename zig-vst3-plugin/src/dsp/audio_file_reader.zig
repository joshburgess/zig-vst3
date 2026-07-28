const std = @import("std");
const adm = @import("adm.zig");
const adm_xml = @import("adm_xml.zig");
const file_reader_io = @import("file_reader_io.zig");
const pcm_encode = @import("pcm_encode.zig");
const wave64_metadata = @import("wave64_metadata.zig");

pub const Container = enum {
    wav,
    rf64,
    bw64,
    wave64,
    aiff,
    aifc,
};

pub const Encoding = enum {
    pcm_i16,
    pcm_i24,
    pcm_i32,
    ieee_f32,
};

pub const MetadataKind = enum {
    broadcast,
    ixml,
    axml,
    channel_allocation,
    info,
};

pub const Info = struct {
    container: Container,
    encoding: Encoding,
    sample_rate: u32,
    channel_count: u16,
    frame_count: u64,
};

pub const AdmMetadata = struct {
    document: adm_xml.Document,
    channel_allocation: adm.View,
};

pub const AdmMetadataRequirements = struct {
    xml_bytes: usize,
    channel_allocation_bytes: usize,
};

pub const FileReader = struct {
    io: std.Io,
    file: std.Io.File,
    info: Info,
    data_offset: u64,
    data_bytes: u64,
    frame_bytes: u16,
    byte_order: std.builtin.Endian,

    /// The caller owns the file and must keep it open for the reader lifetime.
    pub fn init(io: std.Io, file: std.Io.File) !FileReader {
        const stat = try file.stat(io);
        if (stat.size < 12) return error.TruncatedAudioFile;
        var header: [12]u8 = undefined;
        try readExactAt(io, file, 0, &header);
        if (std.mem.eql(u8, header[0..4], "RIFF") and
            std.mem.eql(u8, header[8..12], "WAVE"))
        {
            return parseWav(io, file, stat.size, header);
        }
        if ((std.mem.eql(u8, header[0..4], "RF64") or
            std.mem.eql(u8, header[0..4], "BW64")) and
            std.mem.eql(u8, header[8..12], "WAVE"))
        {
            return parseLargeRiff(
                io,
                file,
                stat.size,
                if (std.mem.eql(u8, header[0..4], "BW64"))
                    .bw64
                else
                    .rf64,
            );
        }
        if (std.mem.eql(u8, header[0..4], "FORM") and
            (std.mem.eql(u8, header[8..12], "AIFF") or
                std.mem.eql(u8, header[8..12], "AIFC")))
        {
            return parseAiff(io, file, stat.size, header);
        }
        if (stat.size >= 40) {
            var wave64_header: [40]u8 = undefined;
            try readExactAt(io, file, 0, &wave64_header);
            if (std.mem.eql(u8, wave64_header[0..16], &wave64_riff_guid) and
                std.mem.eql(u8, wave64_header[24..40], &wave64_wave_guid))
            {
                return parseWave64(io, file, stat.size, wave64_header);
            }
        }
        return error.UnsupportedAudioContainer;
    }

    pub fn getInfo(self: *const FileReader) Info {
        return self.info;
    }

    /// Reports the exact storage needed by `readMetadataChunk`.
    pub fn requiredMetadataChunkBytes(
        self: *const FileReader,
        kind: MetadataKind,
    ) !?usize {
        if (self.info.container == .wave64)
            return scanWave64MetadataChunk(self, kind, null);
        if (self.info.container != .wav and
            self.info.container != .rf64 and
            self.info.container != .bw64)
        {
            return error.UnsupportedMetadataContainer;
        }
        return scanRiffMetadataChunk(self, kind, null);
    }

    /// Reads one complete metadata chunk into caller storage.
    pub fn readMetadataChunk(
        self: *const FileReader,
        kind: MetadataKind,
        destination: []u8,
    ) !?[]const u8 {
        const required = if (self.info.container == .wave64)
            try scanWave64MetadataChunk(self, kind, destination)
        else if (self.info.container == .wav or
            self.info.container == .rf64 or
            self.info.container == .bw64)
            try scanRiffMetadataChunk(self, kind, destination)
        else
            return error.UnsupportedMetadataContainer;
        if (required == null) return null;
        return destination[0..required.?];
    }

    /// Reports both buffers needed by `readAdmMetadata`.
    pub fn requiredAdmMetadataBytes(
        self: *const FileReader,
    ) !?AdmMetadataRequirements {
        const xml_bytes = try self.requiredMetadataChunkBytes(.axml);
        const channel_bytes =
            try self.requiredMetadataChunkBytes(.channel_allocation);
        if (xml_bytes == null and channel_bytes == null) return null;
        return .{
            .xml_bytes = xml_bytes orelse return error.MissingAdmXml,
            .channel_allocation_bytes = channel_bytes orelse
                return error.MissingAdmChannelAllocation,
        };
    }

    pub fn readAdmMetadata(
        self: *const FileReader,
        xml_storage: []u8,
        channel_storage: []u8,
    ) !?AdmMetadata {
        if (slicesOverlap(xml_storage, channel_storage))
            return error.AdmMetadataBuffersOverlap;
        const required =
            try self.requiredAdmMetadataBytes() orelse return null;
        if (xml_storage.len < required.xml_bytes or
            channel_storage.len < required.channel_allocation_bytes)
        {
            return error.MetadataBufferTooSmall;
        }
        const encoded_xml = (try self.readMetadataChunk(
            .axml,
            xml_storage[0..required.xml_bytes],
        )) orelse return error.MissingAdmXml;
        const encoded_channels = (try self.readMetadataChunk(
            .channel_allocation,
            channel_storage[0..required.channel_allocation_bytes],
        )) orelse return error.MissingAdmChannelAllocation;
        const xml_view =
            try @import("audio_metadata.zig").RiffXmlView.init(encoded_xml);
        const document = try adm_xml.Document.init(xml_view.document);
        const channel_allocation = try adm.View.init(encoded_channels);
        try document.validateChannelAllocationView(channel_allocation);
        return .{
            .document = document,
            .channel_allocation = channel_allocation,
        };
    }

    /// Reads complete interleaved frames and returns the number produced.
    pub fn readInterleaved(
        self: *const FileReader,
        comptime Sample: type,
        first_frame: u64,
        destination: []Sample,
    ) !usize {
        if (Sample != f32 and Sample != f64)
            @compileError("audio file reader output must be f32 or f64");
        try self.validateReadState();
        if (destination.len % self.info.channel_count != 0)
            return error.IncompleteDestinationFrame;
        if (first_frame > self.info.frame_count)
            return error.FrameIndexOutOfRange;

        const requested_frames: u64 =
            @intCast(destination.len / self.info.channel_count);
        const available_frames = self.info.frame_count - first_frame;
        const frame_count = @min(requested_frames, available_frames);
        const sample_count = std.math.mul(
            usize,
            @intCast(frame_count),
            self.info.channel_count,
        ) catch return error.AudioFileSizeOverflow;
        if (sample_count == 0) return 0;

        const first_byte = std.math.mul(
            u64,
            first_frame,
            self.frame_bytes,
        ) catch return error.AudioFileSizeOverflow;
        var file_offset = std.math.add(
            u64,
            self.data_offset,
            first_byte,
        ) catch return error.AudioFileSizeOverflow;
        const sample_bytes = bytesPerSample(self.info.encoding);
        var staging: [4096]u8 = undefined;
        var samples_done: usize = 0;
        while (samples_done < sample_count) {
            const remaining_samples = sample_count - samples_done;
            const chunk_samples = @min(
                remaining_samples,
                staging.len / sample_bytes,
            );
            const chunk_bytes = chunk_samples * sample_bytes;
            try readExactAt(
                self.io,
                self.file,
                file_offset,
                staging[0..chunk_bytes],
            );
            for (0..chunk_samples) |index| {
                const offset = index * sample_bytes;
                destination[samples_done + index] = @floatCast(decodeSample(
                    staging[offset..][0..sample_bytes],
                    self.info.encoding,
                    self.byte_order,
                ));
            }
            samples_done += chunk_samples;
            file_offset = std.math.add(
                u64,
                file_offset,
                chunk_bytes,
            ) catch return error.AudioFileSizeOverflow;
        }
        return @intCast(frame_count);
    }

    fn validateReadState(self: *const FileReader) !void {
        if (self.info.sample_rate == 0 or
            self.info.channel_count == 0 or
            self.frame_bytes == 0)
            return error.InvalidAudioFileReaderState;
        const expected_frame_bytes = std.math.mul(
            u16,
            self.info.channel_count,
            @intCast(bytesPerSample(self.info.encoding)),
        ) catch return error.InvalidAudioFileReaderState;
        if (self.frame_bytes != expected_frame_bytes or
            self.data_bytes % self.frame_bytes != 0 or
            self.info.frame_count !=
                self.data_bytes / self.frame_bytes)
            return error.InvalidAudioFileReaderState;
        _ = std.math.add(
            u64,
            self.data_offset,
            self.data_bytes,
        ) catch return error.InvalidAudioFileReaderState;
    }
};

fn scanRiffMetadataChunk(
    reader: *const FileReader,
    kind: MetadataKind,
    destination: ?[]u8,
) !?usize {
    const bounds = try riffBounds(reader);
    var offset: u64 = 12;
    while (offset < bounds.end) {
        if (bounds.end - offset < 8)
            return error.TruncatedAudioFile;
        var header: [8]u8 = undefined;
        try readExactAt(reader.io, reader.file, offset, &header);
        const size32 = std.mem.readInt(
            u32,
            header[4..8],
            .little,
        );
        const payload_bytes: u64 =
            if ((reader.info.container == .rf64 or
                reader.info.container == .bw64) and
            std.mem.eql(u8, header[0..4], "data") and
            size32 == std.math.maxInt(u32))
                bounds.rf64_data_bytes
            else
                size32;
        const payload_offset = offset + 8;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            payload_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > bounds.end)
            return error.TruncatedAudioFile;
        if (try chunkMatches(
            reader.io,
            reader.file,
            header[0..4],
            payload_offset,
            payload_bytes,
            kind,
        )) {
            const padded_payload = std.math.add(
                u64,
                payload_bytes,
                payload_bytes & 1,
            ) catch return error.AudioFileSizeOverflow;
            const total_bytes = std.math.add(
                u64,
                8,
                padded_payload,
            ) catch return error.AudioFileSizeOverflow;
            if (total_bytes > std.math.maxInt(usize))
                return error.MetadataSizeOverflow;
            const required: usize = @intCast(total_bytes);
            if (destination) |output| {
                if (output.len < required)
                    return error.MetadataBufferTooSmall;
                try readExactAt(
                    reader.io,
                    reader.file,
                    offset,
                    output[0..required],
                );
            }
            return required;
        }
        offset = std.math.add(
            u64,
            payload_end,
            payload_bytes & 1,
        ) catch return error.InvalidAudioFile;
        if (offset > bounds.end)
            return error.TruncatedAudioFile;
    }
    return null;
}

fn scanWave64MetadataChunk(
    reader: *const FileReader,
    kind: MetadataKind,
    destination: ?[]u8,
) !?usize {
    const desired_guid: [16]u8 = switch (kind) {
        .broadcast => wave64_metadata.broadcast_guid,
        .info => wave64_metadata.list_guid,
        .ixml, .axml, .channel_allocation => return error.UnsupportedWave64MetadataKind,
    };
    var container_header: [24]u8 = undefined;
    try readExactAt(reader.io, reader.file, 0, &container_header);
    const end = std.mem.readInt(
        u64,
        container_header[16..24],
        .little,
    );
    var offset: u64 = 40;
    while (offset < end) {
        if (end - offset < 24) return error.TruncatedAudioFile;
        var header: [24]u8 = undefined;
        try readExactAt(reader.io, reader.file, offset, &header);
        const chunk_bytes = std.mem.readInt(
            u64,
            header[16..24],
            .little,
        );
        if (chunk_bytes < 24) return error.InvalidAudioFile;
        const payload_bytes = chunk_bytes - 24;
        const payload_offset = offset + 24;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            payload_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > end) return error.TruncatedAudioFile;
        const aligned_end = try alignForward8(payload_end);
        if (aligned_end > end) return error.TruncatedAudioFile;

        var matches = std.mem.eql(
            u8,
            header[0..16],
            &desired_guid,
        );
        if (matches and kind == .info) {
            if (payload_bytes < 4) {
                matches = false;
            } else {
                var subtype: [4]u8 = undefined;
                try readExactAt(
                    reader.io,
                    reader.file,
                    payload_offset,
                    &subtype,
                );
                matches = std.mem.eql(u8, &subtype, "INFO");
            }
        }
        if (matches) {
            var padding: [7]u8 = undefined;
            const padding_bytes: usize = @intCast(
                aligned_end - payload_end,
            );
            if (padding_bytes != 0) {
                try readExactAt(
                    reader.io,
                    reader.file,
                    payload_end,
                    padding[0..padding_bytes],
                );
                for (padding[0..padding_bytes]) |byte| {
                    if (byte != 0)
                        return error.InvalidWave64MetadataPadding;
                }
            }
            if (payload_bytes > std.math.maxInt(u32))
                return error.MetadataSizeOverflow;
            const padded_payload = std.math.add(
                u64,
                payload_bytes,
                payload_bytes & 1,
            ) catch return error.MetadataSizeOverflow;
            const required = std.math.add(
                u64,
                8,
                padded_payload,
            ) catch return error.MetadataSizeOverflow;
            if (required > std.math.maxInt(usize))
                return error.MetadataSizeOverflow;
            const required_length: usize = @intCast(required);
            if (destination) |output| {
                if (output.len < required_length)
                    return error.MetadataBufferTooSmall;
                const payload_length: usize = @intCast(payload_bytes);
                try readExactAt(
                    reader.io,
                    reader.file,
                    payload_offset,
                    output[8..][0..payload_length],
                );
                @memcpy(
                    output[0..4],
                    if (kind == .broadcast) "bext" else "LIST",
                );
                std.mem.writeInt(
                    u32,
                    output[4..8],
                    @intCast(payload_bytes),
                    .little,
                );
                if (payload_bytes & 1 != 0)
                    output[8 + payload_length] = 0;
            }
            return required_length;
        }
        offset = aligned_end;
    }
    return null;
}

const ParsedFormat = struct {
    encoding: Encoding,
    sample_rate: u32,
    channel_count: u16,
    frame_bytes: u16,
};

const RiffBounds = struct {
    end: u64,
    rf64_data_bytes: u64 = 0,
};

fn riffBounds(reader: *const FileReader) !RiffBounds {
    var header: [12]u8 = undefined;
    try readExactAt(reader.io, reader.file, 0, &header);
    if (reader.info.container == .wav) {
        return .{
            .end = std.math.add(
                u64,
                std.mem.readInt(u32, header[4..8], .little),
                8,
            ) catch return error.InvalidAudioFile,
        };
    }
    var ds64: [24]u8 = undefined;
    try readExactAt(reader.io, reader.file, 20, &ds64);
    return .{
        .end = std.math.add(
            u64,
            std.mem.readInt(u64, ds64[0..8], .little),
            8,
        ) catch return error.InvalidAudioFile,
        .rf64_data_bytes = std.mem.readInt(u64, ds64[8..16], .little),
    };
}

fn chunkMatches(
    io: std.Io,
    file: std.Io.File,
    id: []const u8,
    payload_offset: u64,
    payload_bytes: u64,
    kind: MetadataKind,
) !bool {
    return switch (kind) {
        .broadcast => std.mem.eql(u8, id, "bext"),
        .ixml => std.mem.eql(u8, id, "iXML"),
        .axml => std.mem.eql(u8, id, "axml"),
        .channel_allocation => std.mem.eql(u8, id, "chna"),
        .info => blk: {
            if (!std.mem.eql(u8, id, "LIST") or payload_bytes < 4)
                break :blk false;
            var list_kind: [4]u8 = undefined;
            try readExactAt(io, file, payload_offset, &list_kind);
            break :blk std.mem.eql(u8, &list_kind, "INFO");
        },
    };
}

fn parseWav(
    io: std.Io,
    file: std.Io.File,
    file_size: u64,
    header: [12]u8,
) !FileReader {
    const riff_end = std.math.add(
        u64,
        std.mem.readInt(u32, header[4..8], .little),
        8,
    ) catch return error.InvalidAudioFile;
    if (riff_end > file_size) return error.TruncatedAudioFile;
    if (riff_end < 12) return error.InvalidAudioFile;

    var format: ?ParsedFormat = null;
    var data_offset: ?u64 = null;
    var data_bytes: u64 = 0;
    var offset: u64 = 12;
    while (offset < riff_end) {
        if (riff_end - offset < 8) return error.TruncatedAudioFile;
        var chunk_header: [8]u8 = undefined;
        try readExactAt(io, file, offset, &chunk_header);
        const chunk_bytes: u64 =
            std.mem.readInt(u32, chunk_header[4..8], .little);
        const payload_offset = offset + 8;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            chunk_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > riff_end) return error.TruncatedAudioFile;

        if (std.mem.eql(u8, chunk_header[0..4], "fmt ")) {
            if (format != null or chunk_bytes < 16)
                return error.InvalidAudioFile;
            var bytes: [16]u8 = undefined;
            try readExactAt(io, file, payload_offset, &bytes);
            format = try parseWavFormat(bytes);
        } else if (std.mem.eql(u8, chunk_header[0..4], "data")) {
            if (data_offset != null) return error.InvalidAudioFile;
            data_offset = payload_offset;
            data_bytes = chunk_bytes;
        }

        offset = std.math.add(
            u64,
            payload_end,
            chunk_bytes & 1,
        ) catch return error.InvalidAudioFile;
        if (offset > riff_end) return error.TruncatedAudioFile;
    }

    const parsed = format orelse return error.MissingAudioFormat;
    const payload = data_offset orelse return error.MissingAudioData;
    if (data_bytes % parsed.frame_bytes != 0)
        return error.IncompleteAudioFrame;
    return .{
        .io = io,
        .file = file,
        .info = .{
            .container = .wav,
            .encoding = parsed.encoding,
            .sample_rate = parsed.sample_rate,
            .channel_count = parsed.channel_count,
            .frame_count = data_bytes / parsed.frame_bytes,
        },
        .data_offset = payload,
        .data_bytes = data_bytes,
        .frame_bytes = parsed.frame_bytes,
        .byte_order = .little,
    };
}

fn parseWavFormat(bytes: [16]u8) !ParsedFormat {
    const format_tag = std.mem.readInt(u16, bytes[0..2], .little);
    const channel_count = std.mem.readInt(u16, bytes[2..4], .little);
    const sample_rate = std.mem.readInt(u32, bytes[4..8], .little);
    const byte_rate = std.mem.readInt(u32, bytes[8..12], .little);
    const frame_bytes = std.mem.readInt(u16, bytes[12..14], .little);
    const bit_count = std.mem.readInt(u16, bytes[14..16], .little);
    if (channel_count == 0 or sample_rate == 0)
        return error.InvalidAudioFormat;
    const encoding: Encoding = switch (format_tag) {
        1 => switch (bit_count) {
            16 => .pcm_i16,
            24 => .pcm_i24,
            32 => .pcm_i32,
            else => return error.UnsupportedAudioEncoding,
        },
        3 => if (bit_count == 32)
            .ieee_f32
        else
            return error.UnsupportedAudioEncoding,
        else => return error.UnsupportedAudioEncoding,
    };
    const expected_frame_bytes = std.math.mul(
        u16,
        channel_count,
        bytesPerSample(encoding),
    ) catch return error.InvalidAudioFormat;
    if (frame_bytes != expected_frame_bytes)
        return error.InvalidAudioFormat;
    const expected_byte_rate = std.math.mul(
        u32,
        sample_rate,
        frame_bytes,
    ) catch return error.InvalidAudioFormat;
    if (byte_rate != expected_byte_rate)
        return error.InvalidAudioFormat;
    return .{
        .encoding = encoding,
        .sample_rate = sample_rate,
        .channel_count = channel_count,
        .frame_bytes = frame_bytes,
    };
}

fn parseLargeRiff(
    io: std.Io,
    file: std.Io.File,
    file_size: u64,
    container: Container,
) !FileReader {
    if (file_size < 48) return error.TruncatedAudioFile;
    var ds64_header: [8]u8 = undefined;
    try readExactAt(io, file, 12, &ds64_header);
    if (!std.mem.eql(u8, ds64_header[0..4], "ds64"))
        return error.MissingRf64Sizes;
    const ds64_bytes: u64 =
        std.mem.readInt(u32, ds64_header[4..8], .little);
    if (ds64_bytes < 28) return error.InvalidRf64Sizes;
    var ds64: [28]u8 = undefined;
    try readExactAt(io, file, 20, &ds64);
    const riff_end = std.math.add(
        u64,
        std.mem.readInt(u64, ds64[0..8], .little),
        8,
    ) catch return error.InvalidRf64Sizes;
    const declared_data_bytes =
        std.mem.readInt(u64, ds64[8..16], .little);
    const declared_frames =
        std.mem.readInt(u64, ds64[16..24], .little);
    const table_entries: u64 =
        std.mem.readInt(u32, ds64[24..28], .little);
    const table_bytes = std.math.mul(
        u64,
        table_entries,
        12,
    ) catch return error.InvalidRf64Sizes;
    const minimum_ds64 = std.math.add(
        u64,
        28,
        table_bytes,
    ) catch return error.InvalidRf64Sizes;
    if (minimum_ds64 > ds64_bytes or riff_end > file_size or riff_end < 48)
        return error.InvalidRf64Sizes;

    var format: ?ParsedFormat = null;
    var data_offset: ?u64 = null;
    var data_bytes: u64 = 0;
    var offset: u64 = 12;
    while (offset < riff_end) {
        if (riff_end - offset < 8) return error.TruncatedAudioFile;
        var chunk_header: [8]u8 = undefined;
        try readExactAt(io, file, offset, &chunk_header);
        const size32 = std.mem.readInt(
            u32,
            chunk_header[4..8],
            .little,
        );
        const payload_offset = offset + 8;
        const chunk_bytes: u64 = if (std.mem.eql(
            u8,
            chunk_header[0..4],
            "data",
        ) and size32 == std.math.maxInt(u32))
            declared_data_bytes
        else
            size32;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            chunk_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > riff_end) return error.TruncatedAudioFile;

        if (std.mem.eql(u8, chunk_header[0..4], "fmt ")) {
            if (format != null or chunk_bytes < 16)
                return error.InvalidAudioFile;
            var bytes: [16]u8 = undefined;
            try readExactAt(io, file, payload_offset, &bytes);
            format = try parseWavFormat(bytes);
        } else if (std.mem.eql(u8, chunk_header[0..4], "data")) {
            if (data_offset != null or
                chunk_bytes != declared_data_bytes)
                return error.InvalidRf64Sizes;
            data_offset = payload_offset;
            data_bytes = chunk_bytes;
        }

        offset = std.math.add(
            u64,
            payload_end,
            chunk_bytes & 1,
        ) catch return error.InvalidAudioFile;
        if (offset > riff_end) return error.TruncatedAudioFile;
    }

    const parsed = format orelse return error.MissingAudioFormat;
    const payload = data_offset orelse return error.MissingAudioData;
    if (data_bytes % parsed.frame_bytes != 0)
        return error.IncompleteAudioFrame;
    const frame_count = data_bytes / parsed.frame_bytes;
    if (frame_count != declared_frames)
        return error.AudioFrameCountMismatch;
    return .{
        .io = io,
        .file = file,
        .info = .{
            .container = container,
            .encoding = parsed.encoding,
            .sample_rate = parsed.sample_rate,
            .channel_count = parsed.channel_count,
            .frame_count = frame_count,
        },
        .data_offset = payload,
        .data_bytes = data_bytes,
        .frame_bytes = parsed.frame_bytes,
        .byte_order = .little,
    };
}

const wave64_riff_guid = [_]u8{
    0x72, 0x69, 0x66, 0x66, 0x2e, 0x91, 0xcf, 0x11,
    0xa5, 0xd6, 0x28, 0xdb, 0x04, 0xc1, 0x00, 0x00,
};
const wave64_wave_guid = [_]u8{
    0x77, 0x61, 0x76, 0x65, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};
const wave64_format_guid = [_]u8{
    0x66, 0x6d, 0x74, 0x20, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};
const wave64_data_guid = [_]u8{
    0x64, 0x61, 0x74, 0x61, 0xf3, 0xac, 0xd3, 0x11,
    0x8c, 0xd1, 0x00, 0xc0, 0x4f, 0x8e, 0xdb, 0x8a,
};

fn parseWave64(
    io: std.Io,
    file: std.Io.File,
    file_size: u64,
    header: [40]u8,
) !FileReader {
    const riff_end = std.mem.readInt(u64, header[16..24], .little);
    if (riff_end > file_size) return error.TruncatedAudioFile;
    if (riff_end < 40) return error.InvalidAudioFile;

    var format: ?ParsedFormat = null;
    var data_offset: ?u64 = null;
    var data_bytes: u64 = 0;
    var offset: u64 = 40;
    while (offset < riff_end) {
        if (riff_end - offset < 24) return error.TruncatedAudioFile;
        var chunk_header: [24]u8 = undefined;
        try readExactAt(io, file, offset, &chunk_header);
        const chunk_bytes =
            std.mem.readInt(u64, chunk_header[16..24], .little);
        if (chunk_bytes < 24) return error.InvalidAudioFile;
        const payload_bytes = chunk_bytes - 24;
        const payload_offset = offset + 24;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            payload_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > riff_end) return error.TruncatedAudioFile;

        if (std.mem.eql(
            u8,
            chunk_header[0..16],
            &wave64_format_guid,
        )) {
            if (format != null or payload_bytes < 16)
                return error.InvalidAudioFile;
            var bytes: [16]u8 = undefined;
            try readExactAt(io, file, payload_offset, &bytes);
            format = try parseWavFormat(bytes);
        } else if (std.mem.eql(
            u8,
            chunk_header[0..16],
            &wave64_data_guid,
        )) {
            if (data_offset != null) return error.InvalidAudioFile;
            data_offset = payload_offset;
            data_bytes = payload_bytes;
        }

        offset = try alignForward8(payload_end);
        if (offset > riff_end) return error.TruncatedAudioFile;
    }

    const parsed = format orelse return error.MissingAudioFormat;
    const payload = data_offset orelse return error.MissingAudioData;
    if (data_bytes % parsed.frame_bytes != 0)
        return error.IncompleteAudioFrame;
    return .{
        .io = io,
        .file = file,
        .info = .{
            .container = .wave64,
            .encoding = parsed.encoding,
            .sample_rate = parsed.sample_rate,
            .channel_count = parsed.channel_count,
            .frame_count = data_bytes / parsed.frame_bytes,
        },
        .data_offset = payload,
        .data_bytes = data_bytes,
        .frame_bytes = parsed.frame_bytes,
        .byte_order = .little,
    };
}

fn parseAiff(
    io: std.Io,
    file: std.Io.File,
    file_size: u64,
    header: [12]u8,
) !FileReader {
    const is_aifc = std.mem.eql(u8, header[8..12], "AIFC");
    const form_end = std.math.add(
        u64,
        std.mem.readInt(u32, header[4..8], .big),
        8,
    ) catch return error.InvalidAudioFile;
    if (form_end > file_size) return error.TruncatedAudioFile;
    if (form_end < 12) return error.InvalidAudioFile;

    var format: ?ParsedFormat = null;
    var declared_frames: ?u32 = null;
    var data_offset: ?u64 = null;
    var data_bytes: u64 = 0;
    var offset: u64 = 12;
    while (offset < form_end) {
        if (form_end - offset < 8) return error.TruncatedAudioFile;
        var chunk_header: [8]u8 = undefined;
        try readExactAt(io, file, offset, &chunk_header);
        const chunk_bytes: u64 =
            std.mem.readInt(u32, chunk_header[4..8], .big);
        const payload_offset = offset + 8;
        const payload_end = std.math.add(
            u64,
            payload_offset,
            chunk_bytes,
        ) catch return error.InvalidAudioFile;
        if (payload_end > form_end) return error.TruncatedAudioFile;

        if (std.mem.eql(u8, chunk_header[0..4], "COMM")) {
            const required_bytes: usize = if (is_aifc) 23 else 18;
            if (format != null or
                (!is_aifc and chunk_bytes != required_bytes) or
                (is_aifc and chunk_bytes < required_bytes))
                return error.InvalidAudioFile;
            var bytes: [23]u8 = @splat(0);
            try readExactAt(
                io,
                file,
                payload_offset,
                bytes[0..required_bytes],
            );
            if (is_aifc) {
                if (!std.mem.eql(u8, bytes[18..22], "NONE"))
                    return error.UnsupportedAudioEncoding;
                const compression_name_bytes =
                    std.math.add(u64, bytes[22], 23) catch
                        return error.InvalidAudioFormat;
                if (compression_name_bytes > chunk_bytes)
                    return error.InvalidAudioFormat;
            }
            const channel_count = std.mem.readInt(
                u16,
                bytes[0..2],
                .big,
            );
            declared_frames = std.mem.readInt(u32, bytes[2..6], .big);
            const bit_count = std.mem.readInt(u16, bytes[6..8], .big);
            if (channel_count == 0) return error.InvalidAudioFormat;
            const encoding: Encoding = switch (bit_count) {
                16 => .pcm_i16,
                24 => .pcm_i24,
                32 => .pcm_i32,
                else => return error.UnsupportedAudioEncoding,
            };
            const frame_bytes = std.math.mul(
                u16,
                channel_count,
                bytesPerSample(encoding),
            ) catch return error.InvalidAudioFormat;
            format = .{
                .encoding = encoding,
                .sample_rate = try decodeExtendedRate(bytes[8..18]),
                .channel_count = channel_count,
                .frame_bytes = frame_bytes,
            };
        } else if (std.mem.eql(u8, chunk_header[0..4], "SSND")) {
            if (data_offset != null or chunk_bytes < 8)
                return error.InvalidAudioFile;
            var sound_header: [8]u8 = undefined;
            try readExactAt(io, file, payload_offset, &sound_header);
            const sound_offset: u64 =
                std.mem.readInt(u32, sound_header[0..4], .big);
            if (sound_offset > chunk_bytes - 8)
                return error.InvalidAudioFile;
            data_offset = payload_offset + 8 + sound_offset;
            data_bytes = chunk_bytes - 8 - sound_offset;
        }

        offset = std.math.add(
            u64,
            payload_end,
            chunk_bytes & 1,
        ) catch return error.InvalidAudioFile;
        if (offset > form_end) return error.TruncatedAudioFile;
    }

    const parsed = format orelse return error.MissingAudioFormat;
    const payload = data_offset orelse return error.MissingAudioData;
    if (data_bytes % parsed.frame_bytes != 0)
        return error.IncompleteAudioFrame;
    const frame_count = data_bytes / parsed.frame_bytes;
    if (frame_count != (declared_frames orelse return error.MissingAudioFormat))
        return error.AudioFrameCountMismatch;
    return .{
        .io = io,
        .file = file,
        .info = .{
            .container = if (is_aifc) .aifc else .aiff,
            .encoding = parsed.encoding,
            .sample_rate = parsed.sample_rate,
            .channel_count = parsed.channel_count,
            .frame_count = frame_count,
        },
        .data_offset = payload,
        .data_bytes = data_bytes,
        .frame_bytes = parsed.frame_bytes,
        .byte_order = .big,
    };
}

fn decodeExtendedRate(bytes: []const u8) !u32 {
    const sign_and_exponent = std.mem.readInt(u16, bytes[0..2], .big);
    if (sign_and_exponent & 0x8000 != 0)
        return error.InvalidSampleRate;
    const exponent = sign_and_exponent & 0x7fff;
    const mantissa = std.mem.readInt(u64, bytes[2..10], .big);
    if (exponent == 0 or exponent == 0x7fff or
        mantissa & (@as(u64, 1) << 63) == 0)
        return error.InvalidSampleRate;
    const shift: i32 = @as(i32, exponent) - 16383 - 63;
    const rate = std.math.ldexp(
        @as(f64, @floatFromInt(mantissa)),
        shift,
    );
    if (!std.math.isFinite(rate) or rate < 1 or
        rate > std.math.maxInt(u32))
        return error.InvalidSampleRate;
    const rounded = @round(rate);
    if (@abs(rate - rounded) > 0.001)
        return error.InvalidSampleRate;
    return @intFromFloat(rounded);
}

fn decodeSample(
    bytes: []const u8,
    encoding: Encoding,
    endian: std.builtin.Endian,
) f64 {
    return pcm_encode.decode(bytes, pcmEncoding(encoding), endian);
}

fn bytesPerSample(encoding: Encoding) u16 {
    return @intCast(pcm_encode.byteCount(pcmEncoding(encoding)));
}

fn pcmEncoding(encoding: Encoding) pcm_encode.Encoding {
    return switch (encoding) {
        .pcm_i16 => .pcm_i16,
        .pcm_i24 => .pcm_i24,
        .pcm_i32 => .pcm_i32,
        .ieee_f32 => .ieee_f32,
    };
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
        error.TruncatedAudioFile,
    );
}

fn alignForward8(value: u64) !u64 {
    const remainder = value & 7;
    if (remainder == 0) return value;
    return std.math.add(
        u64,
        value,
        8 - remainder,
    ) catch error.AudioFileSizeOverflow;
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

const wav_writer = @import("wav_writer.zig");
const aiff_writer = @import("aiff_writer.zig");
const rf64_writer = @import("rf64_writer.zig");
const wave64_writer = @import("wave64_writer.zig");

test "file reader decodes WAV metadata layout and random frame ranges" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.wav",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);

    const channel_entries = [_]@import("adm.zig").Entry{
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
    const metadata = @import("audio_metadata.zig").RiffMetadata{
        .broadcast = .{
            .description = "Reader",
            .version = .version_2,
        },
        .ixml = "<BWFXML/>",
        .channel_allocation = .{
            .num_tracks = 2,
            .entries = &channel_entries,
        },
        .info = &.{
            .{ .id = .{ 'I', 'N', 'A', 'M' }, .value = "Reader" },
        },
    };
    var writer = try wav_writer.FileWriter.initWithRiffMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = .pcm_i16,
        },
        metadata,
    );
    try writer.append(f32, &.{
        -1.0, -0.5,
        0.0,  0.5,
        1.0,  0.25,
    });
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.wav, reader.info.container);
    try std.testing.expectEqual(Encoding.pcm_i16, reader.info.encoding);
    try std.testing.expectEqual(@as(u64, 3), reader.info.frame_count);
    var output: [6]f64 = @splat(99);
    try std.testing.expectEqual(
        @as(usize, 2),
        try reader.readInterleaved(f64, 1, &output),
    );
    try std.testing.expectApproxEqAbs(0.0, output[0], 1.0 / 32768.0);
    try std.testing.expectApproxEqAbs(0.5, output[1], 1.0 / 32768.0);
    try std.testing.expectApproxEqAbs(
        32767.0 / 32768.0,
        output[2],
        1.0 / 32768.0,
    );
    try std.testing.expectApproxEqAbs(0.25, output[3], 1.0 / 32768.0);
    try std.testing.expectEqual(@as(f64, 99), output[4]);
    try std.testing.expectEqual(@as(f64, 99), output[5]);
    const required_broadcast =
        (try reader.requiredMetadataChunkBytes(.broadcast)).?;
    try std.testing.expect(required_broadcast > 8);
    var undersized_metadata: [8]u8 = @splat(0xa5);
    try std.testing.expectError(
        error.MetadataBufferTooSmall,
        reader.readMetadataChunk(.broadcast, &undersized_metadata),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** undersized_metadata.len),
        &undersized_metadata,
    );
    var metadata_storage: [1024]u8 = undefined;
    const broadcast = try reader.readMetadataChunk(
        .broadcast,
        &metadata_storage,
    );
    try std.testing.expectEqual(required_broadcast, broadcast.?.len);
    const broadcast_view =
        try @import("broadcast_metadata.zig").View.init(broadcast.?);
    try std.testing.expectEqualStrings(
        "Reader",
        broadcast_view.description,
    );
    const ixml = try reader.readMetadataChunk(
        .ixml,
        &metadata_storage,
    );
    const ixml_view =
        try @import("audio_metadata.zig").RiffXmlView.init(ixml.?);
    try std.testing.expectEqualStrings(
        "<BWFXML/>",
        ixml_view.document,
    );
    try std.testing.expect(
        try reader.requiredMetadataChunkBytes(.axml) == null,
    );
    try std.testing.expect(
        try reader.readMetadataChunk(.axml, &metadata_storage) == null,
    );
    const channel_allocation = try reader.readMetadataChunk(
        .channel_allocation,
        &metadata_storage,
    );
    const channel_view =
        try @import("adm.zig").View.init(channel_allocation.?);
    try std.testing.expectEqual(@as(u16, 2), channel_view.num_tracks);
    try std.testing.expectEqualStrings(
        "ATU_00000002",
        (try channel_view.entry(1)).uid,
    );
    const info_chunk = try reader.readMetadataChunk(
        .info,
        &metadata_storage,
    );
    _ = try @import("audio_metadata.zig").RiffInfoView.init(info_chunk.?);
    var incomplete: [1]f32 = undefined;
    try std.testing.expectError(
        error.IncompleteDestinationFrame,
        reader.readInterleaved(f32, 0, &incomplete),
    );
    var eof: [2]f32 = @splat(17);
    try std.testing.expectEqual(
        @as(usize, 0),
        try reader.readInterleaved(f32, 3, &eof),
    );
    try std.testing.expectEqualSlices(f32, &.{ 17, 17 }, &eof);
}

test "file reader decodes padded mono WAV PCM24" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "padded-24.wav",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const samples = [_]f32{ -1.0, 0.25, 1.0 };
    var writer = try wav_writer.FileWriter.init(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
    );
    try writer.append(f32, samples[0..1]);
    try writer.append(f32, samples[1..]);
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(
        Info{
            .container = .wav,
            .encoding = .pcm_i24,
            .sample_rate = 48_000,
            .channel_count = 1,
            .frame_count = 3,
        },
        reader.getInfo(),
    );
    var decoded: [3]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 3),
        try reader.readInterleaved(f32, 0, &decoded),
    );
    for (samples, decoded) |expected, actual|
        try std.testing.expectApproxEqAbs(expected, actual, 0.000_001);
}

test "file reader decodes padded AIFF PCM24" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.aiff",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);

    var writer = try aiff_writer.FileWriter.initWithMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 96_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        &.{.{ .id = .{ 'N', 'A', 'M', 'E' }, .value = "Odd" }},
    );
    try writer.append(f64, &.{ -1.0, 0.0, 0.75 });
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.aiff, reader.info.container);
    try std.testing.expectEqual(Encoding.pcm_i24, reader.info.encoding);
    try std.testing.expectEqual(@as(u32, 96_000), reader.info.sample_rate);
    var output: [3]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 3),
        try reader.readInterleaved(f32, 0, &output),
    );
    try std.testing.expectApproxEqAbs(-1.0, output[0], 1.0 / 8_388_608.0);
    try std.testing.expectApproxEqAbs(0.0, output[1], 1.0 / 8_388_608.0);
    try std.testing.expectApproxEqAbs(0.75, output[2], 1.0 / 8_388_608.0);
    var metadata_storage: [64]u8 = undefined;
    try std.testing.expectError(
        error.UnsupportedMetadataContainer,
        reader.readMetadataChunk(.broadcast, &metadata_storage),
    );
    try std.testing.expectError(
        error.UnsupportedMetadataContainer,
        reader.requiredMetadataChunkBytes(.broadcast),
    );
}

test "file reader decodes uncompressed AIFC" {
    const spec = aiff_writer.Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
    };
    var aiff: [58]u8 = undefined;
    _ = try aiff_writer.writeInterleaved(
        f32,
        &aiff,
        &.{ -0.5, 0.5 },
        spec,
    );
    var aifc: [64]u8 = @splat(0);
    @memcpy(aifc[0..38], aiff[0..38]);
    @memcpy(aifc[8..12], "AIFC");
    std.mem.writeInt(u32, aifc[4..8], 56, .big);
    std.mem.writeInt(u32, aifc[16..20], 23, .big);
    @memcpy(aifc[38..42], "NONE");
    aifc[42] = 0;
    @memcpy(aifc[44..64], aiff[38..58]);

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.aifc",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(std.testing.io, &aifc, 0);

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.aifc, reader.info.container);
    var output: [2]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try reader.readInterleaved(f32, 0, &output),
    );
    try std.testing.expectApproxEqAbs(-0.5, output[0], 1.0 / 32768.0);
    try std.testing.expectApproxEqAbs(0.5, output[1], 1.0 / 32768.0);

    try file.writePositionalAll(std.testing.io, "sowt", 38);
    try std.testing.expectError(
        error.UnsupportedAudioEncoding,
        FileReader.init(std.testing.io, file),
    );
    try file.writePositionalAll(std.testing.io, "NONE\x01", 38);
    try std.testing.expectError(
        error.InvalidAudioFormat,
        FileReader.init(std.testing.io, file),
    );
}

test "file reader decodes RF64 sizes metadata and IEEE samples" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.rf64.wav",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);

    var writer = try rf64_writer.FileWriter.initWithMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 44_100,
            .channel_count = 1,
            .encoding = .ieee_f32,
        },
        &.{.{ .id = .{ 'I', 'A', 'R', 'T' }, .value = "Reader" }},
    );
    try writer.append(f32, &.{ -0.75, 0.125, 1.0 });
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.rf64, reader.info.container);
    try std.testing.expectEqual(Encoding.ieee_f32, reader.info.encoding);
    try std.testing.expectEqual(@as(u64, 3), reader.info.frame_count);
    var output: [3]f64 = undefined;
    try std.testing.expectEqual(
        @as(usize, 3),
        try reader.readInterleaved(f64, 0, &output),
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ -0.75, 0.125, 1.0 },
        &output,
    );
}

test "file reader decodes BW64 ADM carriage and audio" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.bw64.wav",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);

    const channel_entries = [_]@import("adm.zig").Entry{.{
        .track_index = 1,
        .uid = "ATU_00000001",
        .track_ref = "AT_00010001_01",
        .pack_ref = "AP_00010001",
    }};
    var writer = try rf64_writer.FileWriter.initBw64WithRiffMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 48_000,
            .channel_count = 1,
            .encoding = .pcm_i24,
        },
        .{
            .axml = "<audioFormatExtended/>",
            .channel_allocation = .{
                .num_tracks = 1,
                .entries = &channel_entries,
                .entry_capacity = 2,
            },
        },
    );
    try writer.append(f32, &.{ -0.5, 0.5 });
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.bw64, reader.info.container);
    try std.testing.expectEqual(@as(u64, 2), reader.info.frame_count);
    var samples: [2]f32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 2),
        try reader.readInterleaved(f32, 0, &samples),
    );
    try std.testing.expectApproxEqAbs(@as(f32, -0.5), samples[0], 1.0e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), samples[1], 1.0e-6);

    const required_adm = (try reader.requiredAdmMetadataBytes()).?;
    try std.testing.expect(required_adm.xml_bytes <= 256);
    try std.testing.expect(required_adm.channel_allocation_bytes <= 256);
    var atomic_xml_storage: [256]u8 = @splat(0xa5);
    var atomic_channel_storage: [256]u8 = @splat(0x5a);
    try std.testing.expectError(
        error.MetadataBufferTooSmall,
        reader.readAdmMetadata(
            atomic_xml_storage[0..required_adm.xml_bytes],
            atomic_channel_storage[0 .. required_adm.channel_allocation_bytes - 1],
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** atomic_xml_storage.len),
        &atomic_xml_storage,
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0x5a} ** atomic_channel_storage.len),
        &atomic_channel_storage,
    );

    var metadata_storage: [256]u8 = undefined;
    const axml = try reader.readMetadataChunk(.axml, &metadata_storage);
    try std.testing.expectEqual(required_adm.xml_bytes, axml.?.len);
    const xml_view =
        try @import("audio_metadata.zig").RiffXmlView.init(axml.?);
    try std.testing.expectEqualStrings(
        "<audioFormatExtended/>",
        xml_view.document,
    );
    const channel_allocation = try reader.readMetadataChunk(
        .channel_allocation,
        &metadata_storage,
    );
    try std.testing.expectEqual(
        required_adm.channel_allocation_bytes,
        channel_allocation.?.len,
    );
    const channel_view =
        try @import("adm.zig").View.init(channel_allocation.?);
    try std.testing.expectEqual(@as(u16, 2), channel_view.entry_capacity);
    try std.testing.expectEqualStrings(
        "ATU_00000001",
        (try channel_view.entry(0)).uid,
    );
    var typed_xml_storage: [256]u8 = undefined;
    var typed_channel_storage: [256]u8 = undefined;
    const typed_adm = try reader.readAdmMetadata(
        &typed_xml_storage,
        &typed_channel_storage,
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        typed_adm.?.channel_allocation.num_tracks,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        typed_adm.?.document.declaration_count,
    );
    try std.testing.expectError(
        error.AdmMetadataBuffersOverlap,
        reader.readAdmMetadata(
            &typed_xml_storage,
            typed_xml_storage[64..],
        ),
    );
}

test "file reader decodes Wave64 PCM32 metadata and alignment padding" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "reader.w64",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);

    var writer = try wave64_writer.FileWriter.initWithMetadata(
        std.testing.io,
        file,
        .{
            .sample_rate = 192_000,
            .channel_count = 1,
            .encoding = .pcm_i32,
        },
        .{
            .broadcast = .{
                .description = "Wave64 reader",
                .coding_history = "A=PCM,F=192000,W=32,M=mono\r\n",
            },
            .info = &.{
                .{ .id = .{ 'I', 'N', 'A', 'M' }, .value = "Wave64" },
            },
        },
    );
    try writer.append(f64, &.{ -0.25, 0.5, 1.0 });
    try writer.finalize();

    const reader = try FileReader.init(std.testing.io, file);
    try std.testing.expectEqual(Container.wave64, reader.info.container);
    try std.testing.expectEqual(Encoding.pcm_i32, reader.info.encoding);
    try std.testing.expectEqual(@as(u64, 3), reader.info.frame_count);
    var output: [3]f64 = undefined;
    try std.testing.expectEqual(
        @as(usize, 3),
        try reader.readInterleaved(f64, 0, &output),
    );
    try std.testing.expectApproxEqAbs(-0.25, output[0], 1.0e-9);
    try std.testing.expectApproxEqAbs(0.5, output[1], 1.0e-9);
    try std.testing.expectApproxEqAbs(
        2_147_483_647.0 / 2_147_483_648.0,
        output[2],
        1.0e-9,
    );
    var undersized: [8]u8 = @splat(0xa5);
    const required_broadcast =
        (try reader.requiredMetadataChunkBytes(.broadcast)).?;
    try std.testing.expectError(
        error.MetadataBufferTooSmall,
        reader.readMetadataChunk(.broadcast, &undersized),
    );
    try std.testing.expectEqualSlices(
        u8,
        &([_]u8{0xa5} ** undersized.len),
        &undersized,
    );
    var metadata_storage: [1024]u8 = undefined;
    const broadcast = try reader.readMetadataChunk(
        .broadcast,
        &metadata_storage,
    );
    try std.testing.expectEqual(required_broadcast, broadcast.?.len);
    const broadcast_view =
        try @import("broadcast_metadata.zig").View.init(broadcast.?);
    try std.testing.expectEqualStrings(
        "Wave64 reader",
        broadcast_view.description,
    );
    const info = try reader.readMetadataChunk(.info, &metadata_storage);
    const info_view =
        try @import("audio_metadata.zig").RiffInfoView.init(info.?);
    var iterator = info_view.iterator();
    const title = (try iterator.next()).?;
    try std.testing.expectEqualStrings("Wave64", title.value);
    try std.testing.expect((try iterator.next()) == null);
    try std.testing.expectError(
        error.UnsupportedWave64MetadataKind,
        reader.readMetadataChunk(.ixml, &metadata_storage),
    );
    try std.testing.expectError(
        error.UnsupportedWave64MetadataKind,
        reader.requiredMetadataChunkBytes(.ixml),
    );
    var broadcast_header: [24]u8 = undefined;
    _ = try file.readPositionalAll(
        std.testing.io,
        &broadcast_header,
        40,
    );
    const broadcast_chunk_bytes = std.mem.readInt(
        u64,
        broadcast_header[16..24],
        .little,
    );
    try file.writePositionalAll(
        std.testing.io,
        &.{1},
        40 + broadcast_chunk_bytes,
    );
    try std.testing.expectError(
        error.InvalidWave64MetadataPadding,
        reader.readMetadataChunk(.broadcast, &metadata_storage),
    );
    try file.writePositionalAll(
        std.testing.io,
        &.{0},
        40 + broadcast_chunk_bytes,
    );
}

test "file reader rejects malformed structure and invalid requests" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const file = try temporary.dir.createFile(
        std.testing.io,
        "malformed.wav",
        .{ .read = true, .truncate = true },
    );
    defer file.close(std.testing.io);
    try file.writePositionalAll(
        std.testing.io,
        "RIFF\xff\xff\xff\xffWAVE",
        0,
    );
    try std.testing.expectError(
        error.TruncatedAudioFile,
        FileReader.init(std.testing.io, file),
    );

    try file.setLength(std.testing.io, 44);
    var header: [44]u8 = @splat(0);
    @memcpy(header[0..4], "RIFF");
    std.mem.writeInt(u32, header[4..8], 36, .little);
    @memcpy(header[8..12], "WAVE");
    @memcpy(header[12..16], "fmt ");
    std.mem.writeInt(u32, header[16..20], 16, .little);
    std.mem.writeInt(u16, header[20..22], 1, .little);
    std.mem.writeInt(u16, header[22..24], 1, .little);
    std.mem.writeInt(u32, header[24..28], 48_000, .little);
    std.mem.writeInt(u32, header[28..32], 96_000, .little);
    std.mem.writeInt(u16, header[32..34], 2, .little);
    std.mem.writeInt(u16, header[34..36], 16, .little);
    @memcpy(header[36..40], "data");
    try file.writePositionalAll(std.testing.io, &header, 0);
    const reader = try FileReader.init(std.testing.io, file);
    var incomplete: [1]f32 = undefined;
    try std.testing.expectError(
        error.FrameIndexOutOfRange,
        reader.readInterleaved(f32, 1, &incomplete),
    );
    var hostile = reader;
    var preserved = [_]f32{ 7, 8 };
    const original_preserved = preserved;
    hostile.info.channel_count = 0;
    try std.testing.expectError(
        error.InvalidAudioFileReaderState,
        hostile.readInterleaved(f32, 0, &preserved),
    );
    try std.testing.expectEqualSlices(
        f32,
        &original_preserved,
        &preserved,
    );
    hostile = reader;
    hostile.frame_bytes = 3;
    try std.testing.expectError(
        error.InvalidAudioFileReaderState,
        hostile.readInterleaved(f32, 0, &preserved),
    );
    try std.testing.expectEqualSlices(
        f32,
        &original_preserved,
        &preserved,
    );
    hostile = reader;
    hostile.info.frame_count = 1;
    hostile.data_offset = std.math.maxInt(u64);
    hostile.data_bytes = 2;
    try std.testing.expectError(
        error.InvalidAudioFileReaderState,
        hostile.readInterleaved(f32, 0, &preserved),
    );
    try std.testing.expectEqualSlices(
        f32,
        &original_preserved,
        &preserved,
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64) - 7,
        try alignForward8(std.math.maxInt(u64) - 7),
    );
    try std.testing.expectError(
        error.AudioFileSizeOverflow,
        alignForward8(std.math.maxInt(u64)),
    );

    try file.setLength(std.testing.io, 48);
    var invalid_rf64: [48]u8 = @splat(0);
    @memcpy(invalid_rf64[0..4], "RF64");
    @memset(invalid_rf64[4..8], 0xff);
    @memcpy(invalid_rf64[8..12], "WAVE");
    @memcpy(invalid_rf64[12..16], "ds64");
    std.mem.writeInt(u32, invalid_rf64[16..20], 28, .little);
    std.mem.writeInt(u64, invalid_rf64[20..28], 8, .little);
    try file.writePositionalAll(std.testing.io, &invalid_rf64, 0);
    try std.testing.expectError(
        error.InvalidRf64Sizes,
        FileReader.init(std.testing.io, file),
    );

    try file.setLength(std.testing.io, 40);
    var invalid_wave64: [40]u8 = @splat(0);
    @memcpy(invalid_wave64[0..16], &wave64_riff_guid);
    std.mem.writeInt(u64, invalid_wave64[16..24], 39, .little);
    @memcpy(invalid_wave64[24..40], &wave64_wave_guid);
    try file.writePositionalAll(std.testing.io, &invalid_wave64, 0);
    try std.testing.expectError(
        error.InvalidAudioFile,
        FileReader.init(std.testing.io, file),
    );
}
