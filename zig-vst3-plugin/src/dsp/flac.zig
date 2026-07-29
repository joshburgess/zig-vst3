const std = @import("std");
const file_reader_io = @import("file_reader_io.zig");
const file_writer_io = @import("file_writer_io.zig");

pub const Encoding = enum(u8) {
    pcm_i8 = 8,
    pcm_i16 = 16,
    pcm_i24 = 24,
    pcm_i32 = 32,

    pub fn bits(self: Encoding) u6 {
        return @intCast(@intFromEnum(self));
    }

    pub fn bytes(self: Encoding) usize {
        return @intFromEnum(self) / 8;
    }
};

pub const Spec = struct {
    sample_rate: u32,
    channel_count: u8,
    encoding: Encoding,
    block_size: u16 = 4096,
};

pub const Info = struct {
    sample_rate: u32,
    channel_count: u8,
    encoding: Encoding,
    frame_count: u64,
    minimum_block_size: u16,
    maximum_block_size: u16,
};

pub const DecodeResult = struct {
    info: Info,
    frames_decoded: usize,
};

pub const FileWriter = struct {
    io: std.Io,
    file: std.Io.File,
    operations: file_writer_io.Operations = .{},
    spec: Spec,
    pending_samples: []i32,
    frame_storage: []u8,
    pending_frames: usize = 0,
    frames_written: u64 = 0,
    frame_number: u64 = 0,
    byte_count: u64 = streaminfo_bytes,
    minimum_frame_size: u32 = std.math.maxInt(u24),
    maximum_frame_size: u32 = 0,
    md5: std.crypto.hash.Md5 = .init(.{}),
    metadata_bytes: u32 = 0,
    has_metadata: bool = false,
    seek_table_payload_offset: u64 = 0,
    seek_interval: u32 = 0,
    seek_point_capacity: u32 = 0,
    seek_points_written: u32 = 0,
    failed: bool = false,
    finalizing: bool = false,
    finalized: bool = false,

    /// The file and both caller buffers must outlive the writer.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        pending_samples: []i32,
        frame_storage: []u8,
    ) !FileWriter {
        return initInternal(
            io,
            file,
            spec,
            pending_samples,
            frame_storage,
            null,
            .{},
            .{},
        );
    }

    /// Uses an injectable positional I/O backend for failure containment tests.
    pub fn initWithOperations(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        pending_samples: []i32,
        frame_storage: []u8,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        return initInternal(
            io,
            file,
            spec,
            pending_samples,
            frame_storage,
            null,
            .{},
            operations,
        );
    }

    /// Writes validated Vorbis comments before accepting PCM blocks.
    pub fn initWithComments(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        pending_samples: []i32,
        frame_storage: []u8,
        metadata_storage: []u8,
        comments: Comments,
    ) !FileWriter {
        return initInternal(
            io,
            file,
            spec,
            pending_samples,
            frame_storage,
            metadata_storage,
            .{ .comments = comments },
            .{},
        );
    }

    /// Reserves seek points as placeholders and fills them after frame commits.
    pub fn initWithMetadata(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        pending_samples: []i32,
        frame_storage: []u8,
        metadata_storage: []u8,
        metadata: FileWriterMetadata,
    ) !FileWriter {
        return initInternal(
            io,
            file,
            spec,
            pending_samples,
            frame_storage,
            metadata_storage,
            metadata,
            .{},
        );
    }

    fn initInternal(
        io: std.Io,
        file: std.Io.File,
        spec: Spec,
        pending_samples: []i32,
        frame_storage: []u8,
        metadata_storage: ?[]u8,
        metadata: FileWriterMetadata,
        operations: file_writer_io.Operations,
    ) !FileWriter {
        try validateSpec(spec);
        const pending_required = try requiredPendingSamples(spec);
        if (pending_samples.len < pending_required)
            return error.FlacPendingBufferTooSmall;
        const frame_required = try requiredFrameStorageBytes(spec);
        if (frame_storage.len < frame_required)
            return error.FlacFrameBufferTooSmall;
        if (byteSlicesOverlap(
            pending_samples[0..pending_required],
            frame_storage[0..frame_required],
        ))
            return error.OverlappingFlacBuffers;
        const required_metadata =
            try requiredFileWriterMetadataBytes(metadata);
        if (required_metadata != 0 and
            (metadata_storage == null or
                metadata_storage.?.len < required_metadata))
            return error.FlacMetadataBufferTooSmall;
        if (metadata.comments) |comments|
            try validateCommentStorageDisjoint(
                metadata_storage.?[0..required_metadata],
                comments,
            );
        var metadata_offset: usize = 0;
        if (metadata.comments) |value| {
            const storage = metadata_storage orelse
                return error.FlacMetadataBufferTooSmall;
            const required = try requiredCommentMetadataBytes(value);
            storage[metadata_offset] =
                if (metadata.seek_interval == null) 0x84 else 4;
            writeU24(
                storage[metadata_offset + 1 ..][0..3],
                @intCast(required - 4),
            );
            try writeCommentPayload(
                storage[metadata_offset + 4 ..][0 .. required - 4],
                value,
            );
            metadata_offset += required;
        }
        var seek_payload_offset: u64 = 0;
        if (metadata.seek_interval != null) {
            const storage = metadata_storage.?;
            const payload_bytes =
                @as(usize, metadata.seek_point_capacity) * 18;
            storage[metadata_offset] = 0x83;
            writeU24(
                storage[metadata_offset + 1 ..][0..3],
                @intCast(payload_bytes),
            );
            seek_payload_offset =
                streaminfo_bytes + metadata_offset + 4;
            for (0..metadata.seek_point_capacity) |index| {
                encodeSeekPoint(
                    storage[metadata_offset + 4 + index * 18 ..][0..18],
                    .{
                        .sample_number = std.math.maxInt(u64),
                        .byte_offset = 0,
                        .frame_samples = 0,
                    },
                );
            }
            metadata_offset += payload_bytes + 4;
        }
        const metadata_bytes: u32 = @intCast(metadata_offset);
        const initial_bytes = std.math.add(
            u64,
            streaminfo_bytes,
            metadata_bytes,
        ) catch return error.FlacSizeOverflow;
        var writer = FileWriter{
            .io = io,
            .file = file,
            .operations = operations,
            .spec = spec,
            .pending_samples = pending_samples[0..pending_required],
            .frame_storage = frame_storage[0..frame_required],
            .byte_count = initial_bytes,
            .metadata_bytes = metadata_bytes,
            .has_metadata = metadata_bytes != 0,
            .seek_table_payload_offset = seek_payload_offset,
            .seek_interval = metadata.seek_interval orelse 0,
            .seek_point_capacity = metadata.seek_point_capacity,
        };
        try operations.setLength(io, file, initial_bytes);
        try writer.writeCurrentStreaminfo(false);
        if (metadata_bytes != 0) {
            const storage = metadata_storage.?;
            try operations.writeAt(
                io,
                file,
                streaminfo_bytes,
                storage[0..metadata_bytes],
            );
        }
        return writer;
    }

    /// Buffers complete interleaved PCM frames and writes full FLAC blocks.
    pub fn append(self: *FileWriter, samples: []const i32) !void {
        if (!self.valid() or self.finalizing)
            return error.InvalidFlacFileWriterState;
        if (byteSlicesOverlap(samples, self.pending_samples) or
            byteSlicesOverlap(samples, self.frame_storage))
            return error.OverlappingFlacBuffers;
        if (samples.len % self.spec.channel_count != 0)
            return error.IncompleteSourceFrame;
        try validateSamples(samples, self.spec.encoding);
        const incoming_frames = samples.len / self.spec.channel_count;
        const current_frames = std.math.add(
            u64,
            self.frames_written,
            self.pending_frames,
        ) catch return error.FlacFrameCountOutOfRange;
        const next_frames = std.math.add(
            u64,
            current_frames,
            incoming_frames,
        ) catch return error.FlacFrameCountOutOfRange;
        if (next_frames > 0xfffffffff)
            return error.FlacFrameCountOutOfRange;
        const encoded_frames = std.math.divCeil(
            u64,
            next_frames,
            self.spec.block_size,
        ) catch return error.FlacFrameCountOutOfRange;
        if (encoded_frames > 0x80000000)
            return error.FlacFrameNumberOutOfRange;
        const buffered_frames = std.math.add(
            usize,
            self.pending_frames,
            incoming_frames,
        ) catch return error.FlacSizeOverflow;
        const flush_count = buffered_frames / self.spec.block_size;
        const maximum_append_bytes = std.math.mul(
            u64,
            flush_count,
            self.frame_storage.len,
        ) catch return error.FlacSizeOverflow;
        _ = std.math.add(
            u64,
            self.byte_count,
            maximum_append_bytes,
        ) catch return error.FlacSizeOverflow;
        if (self.seek_interval != 0) {
            const required_points = std.math.divCeil(
                u64,
                encoded_frames,
                self.seek_interval,
            ) catch return error.FlacSizeOverflow;
            if (required_points > self.seek_point_capacity)
                return error.FlacSeekTableCapacityExceeded;
        }

        var source_offset: usize = 0;
        while (source_offset < samples.len) {
            const available_frames =
                self.spec.block_size - self.pending_frames;
            const source_frames =
                (samples.len - source_offset) / self.spec.channel_count;
            const copied_frames = @min(available_frames, source_frames);
            const copied_samples =
                copied_frames * self.spec.channel_count;
            const pending_offset =
                self.pending_frames * self.spec.channel_count;
            @memcpy(
                self.pending_samples[pending_offset..][0..copied_samples],
                samples[source_offset..][0..copied_samples],
            );
            self.pending_frames += copied_frames;
            source_offset += copied_samples;
            if (self.pending_frames == self.spec.block_size)
                self.flushPending() catch |err| {
                    self.failed = true;
                    return err;
                };
        }
    }

    /// Writes a final partial block and patches STREAMINFO and its MD5 digest.
    pub fn finalize(self: *FileWriter) !void {
        if (self.finalized) return;
        if (!self.recoverable())
            return error.InvalidFlacFileWriterState;
        self.finalizing = true;
        try self.recover();
        try self.file.sync(self.io);
        self.finalized = true;
    }

    /// Truncates a failed write to its last committed frame and retries pending work.
    pub fn recover(self: *FileWriter) !void {
        if (!self.recoverable())
            return error.InvalidFlacFileWriterState;
        try file_writer_io.Checkpoint.exact(self.byte_count).restore(
            self.operations,
            self.io,
            self.file,
        );
        if (self.pending_frames != 0) {
            self.flushPending() catch |err| {
                self.failed = true;
                return err;
            };
        }
        if (self.finalizing) {
            self.writeCurrentStreaminfo(true) catch |err| {
                self.failed = true;
                return err;
            };
        }
        self.failed = false;
    }

    /// Reports whether the writer can accept more samples.
    pub fn valid(self: *const FileWriter) bool {
        return !self.failed and self.recoverable();
    }

    /// Reports whether retained state can be retried after an I/O failure.
    pub fn recoverable(self: *const FileWriter) bool {
        if (self.finalized) return false;
        if (self.spec.channel_count == 0 or
            self.pending_frames > self.spec.block_size)
            return false;
        if (self.failed and
            self.pending_frames != 0 and
            self.pending_frames != self.spec.block_size and
            !self.finalizing)
            return false;
        const required_pending = requiredPendingSamples(
            self.spec,
        ) catch return false;
        const required_frame = requiredFrameStorageBytes(
            self.spec,
        ) catch return false;
        const audio_offset = std.math.add(
            u64,
            streaminfo_bytes,
            self.metadata_bytes,
        ) catch return false;
        const seek_table_end = if (self.seek_interval == 0)
            0
        else blk: {
            const seek_payload_bytes = std.math.mul(
                u64,
                self.seek_point_capacity,
                18,
            ) catch return false;
            break :blk std.math.add(
                u64,
                self.seek_table_payload_offset,
                seek_payload_bytes,
            ) catch return false;
        };
        const expected_seek_points: u64 =
            if (self.seek_interval == 0 or self.frame_number == 0)
                0
            else
                std.math.divCeil(
                    u64,
                    self.frame_number,
                    self.seek_interval,
                ) catch return false;
        return self.pending_samples.len == required_pending and
            self.frame_storage.len == required_frame and
            self.frames_written <= 0xfffffffff and
            self.frame_number <= 0x80000000 and
            self.metadata_bytes <= std.math.maxInt(u24) + 4 and
            self.has_metadata == (self.metadata_bytes != 0) and
            @as(u64, self.seek_points_written) == expected_seek_points and
            self.seek_points_written <= self.seek_point_capacity and
            ((self.seek_interval == 0 and
                self.seek_point_capacity == 0 and
                self.seek_table_payload_offset == 0) or
                (self.seek_interval != 0 and
                    self.seek_point_capacity != 0 and
                    self.seek_table_payload_offset >= streaminfo_bytes and
                    seek_table_end <= audio_offset)) and
            self.byte_count >= audio_offset;
    }

    fn flushPending(self: *FileWriter) !void {
        if (self.pending_frames == 0) return;
        const sample_count =
            self.pending_frames * self.spec.channel_count;
        const encoded_end = try encodeVerbatimFrame(
            self.frame_storage,
            0,
            self.pending_samples[0..sample_count],
            0,
            self.pending_frames,
            self.frame_number,
            self.spec,
        );
        const next_frames = std.math.add(
            u64,
            self.frames_written,
            self.pending_frames,
        ) catch return error.FlacFrameCountOutOfRange;
        if (next_frames > 0xfffffffff)
            return error.FlacFrameCountOutOfRange;
        const next_frame_number = std.math.add(
            u64,
            self.frame_number,
            1,
        ) catch return error.FlacFrameNumberOutOfRange;
        if (next_frame_number > 0x80000000)
            return error.FlacFrameNumberOutOfRange;
        const next_byte_count = std.math.add(
            u64,
            self.byte_count,
            encoded_end,
        ) catch return error.FlacSizeOverflow;
        var seek_write_offset: u64 = 0;
        if (self.seek_interval != 0 and
            self.frame_number % self.seek_interval == 0)
        {
            if (self.seek_points_written >= self.seek_point_capacity)
                return error.FlacSeekTableCapacityExceeded;
            const point_offset = std.math.mul(
                u64,
                self.seek_points_written,
                18,
            ) catch return error.FlacSizeOverflow;
            seek_write_offset = std.math.add(
                u64,
                self.seek_table_payload_offset,
                point_offset,
            ) catch return error.FlacSizeOverflow;
            const seek_write_end = std.math.add(
                u64,
                seek_write_offset,
                18,
            ) catch return error.FlacSizeOverflow;
            const audio_offset = std.math.add(
                u64,
                streaminfo_bytes,
                self.metadata_bytes,
            ) catch return error.FlacSizeOverflow;
            if (seek_write_end > audio_offset)
                return error.InvalidFlacFileWriterState;
        }
        try self.operations.writeAt(
            self.io,
            self.file,
            self.byte_count,
            self.frame_storage[0..encoded_end],
        );
        if (self.seek_interval != 0 and
            self.frame_number % self.seek_interval == 0)
        {
            if (self.seek_points_written >= self.seek_point_capacity)
                return error.FlacSeekTableCapacityExceeded;
            var point: [18]u8 = undefined;
            encodeSeekPoint(
                &point,
                .{
                    .sample_number = self.frames_written,
                    .byte_offset = self.byte_count -
                        (streaminfo_bytes + self.metadata_bytes),
                    .frame_samples = @intCast(self.pending_frames),
                },
            );
            try self.operations.writeAt(
                self.io,
                self.file,
                seek_write_offset,
                &point,
            );
        }
        hashSamples(
            &self.md5,
            self.pending_samples[0..sample_count],
            self.spec.encoding,
        );
        self.frames_written = next_frames;
        self.frame_number = next_frame_number;
        if (self.seek_interval != 0 and
            (self.frame_number - 1) % self.seek_interval == 0)
            self.seek_points_written += 1;
        self.byte_count = next_byte_count;
        self.minimum_frame_size = @min(
            self.minimum_frame_size,
            @as(u32, @intCast(encoded_end)),
        );
        self.maximum_frame_size = @max(
            self.maximum_frame_size,
            @as(u32, @intCast(encoded_end)),
        );
        self.pending_frames = 0;
    }

    fn writeCurrentStreaminfo(
        self: *const FileWriter,
        complete: bool,
    ) !void {
        var header: [streaminfo_bytes]u8 = @splat(0);
        @memcpy(header[0..4], "fLaC");
        header[4] = if (self.has_metadata) 0 else 0x80;
        header[7] = 34;
        var digest: [16]u8 = @splat(0);
        if (complete) {
            var md5 = self.md5;
            md5.final(&digest);
        }
        writeStreaminfo(
            header[8..42],
            self.spec,
            if (complete) @intCast(self.frames_written) else 0,
            if (complete and self.frames_written != 0)
                self.minimum_frame_size
            else
                0,
            if (complete) self.maximum_frame_size else 0,
            digest,
        );
        try self.operations.writeAt(self.io, self.file, 0, &header);
    }
};

pub const Comment = struct {
    name: []const u8,
    value: []const u8,
};

pub const Comments = struct {
    vendor: []const u8 = "zig-vst3",
    fields: []const Comment = &.{},
};

pub const FileWriterMetadata = struct {
    comments: ?Comments = null,
    seek_interval: ?u32 = null,
    seek_point_capacity: u32 = 0,
};

pub const Metadata = struct {
    comments: ?Comments = null,
    encoded_frames_per_seek_point: ?u32 = null,
};

pub const CommentView = struct {
    name: []const u8,
    value: []const u8,
};

pub const SeekPoint = struct {
    sample_number: u64,
    byte_offset: u64,
    frame_samples: u16,

    pub fn placeholder(self: SeekPoint) bool {
        return self.sample_number == std.math.maxInt(u64);
    }
};

pub const SeekTableIterator = struct {
    payload: []const u8,
    offset: usize = 0,

    pub fn init(encoded: []const u8) !?SeekTableIterator {
        if (encoded.len < 4 or !std.mem.eql(u8, encoded[0..4], "fLaC"))
            return error.InvalidFlacSignature;
        var offset: usize = 4;
        var found = false;
        var payload: []const u8 = undefined;
        var first_block = true;
        while (true) {
            if (encoded.len - offset < 4) return error.TruncatedFlac;
            const header = encoded[offset];
            const block_type = header & 0x7f;
            const is_last = header & 0x80 != 0;
            const payload_size =
                (@as(usize, encoded[offset + 1]) << 16) |
                (@as(usize, encoded[offset + 2]) << 8) |
                encoded[offset + 3];
            if (first_block and (block_type != 0 or payload_size != 34))
                return error.InvalidFlacStreaminfo;
            if (!first_block and block_type == 0)
                return error.DuplicateFlacStreaminfo;
            first_block = false;
            offset += 4;
            if (payload_size > encoded.len - offset)
                return error.TruncatedFlac;
            if (block_type == 3) {
                if (found) return error.DuplicateFlacSeekTable;
                payload = encoded[offset..][0..payload_size];
                try validateSeekTablePayload(payload);
                found = true;
            }
            offset += payload_size;
            if (is_last) break;
        }
        return if (found) .{ .payload = payload } else null;
    }

    pub fn next(self: *SeekTableIterator) ?SeekPoint {
        if (self.offset > self.payload.len or
            self.payload.len - self.offset < 18)
            return null;
        const point = decodeSeekPoint(
            self.payload[self.offset..][0..18],
        );
        self.offset += 18;
        return point;
    }
};

pub const CommentIterator = struct {
    payload: []const u8,
    offset: usize,
    remaining: u32,
    vendor: []const u8,

    pub fn init(encoded: []const u8) !?CommentIterator {
        if (encoded.len < 4 or !std.mem.eql(u8, encoded[0..4], "fLaC"))
            return error.InvalidFlacSignature;
        var offset: usize = 4;
        var found = false;
        var first_block = true;
        var result: CommentIterator = undefined;
        while (true) {
            if (encoded.len - offset < 4) return error.TruncatedFlac;
            const header = encoded[offset];
            const block_type = header & 0x7f;
            const is_last = header & 0x80 != 0;
            const payload_size =
                (@as(usize, encoded[offset + 1]) << 16) |
                (@as(usize, encoded[offset + 2]) << 8) |
                encoded[offset + 3];
            if (first_block and (block_type != 0 or payload_size != 34))
                return error.InvalidFlacStreaminfo;
            if (!first_block and block_type == 0)
                return error.DuplicateFlacStreaminfo;
            first_block = false;
            offset += 4;
            if (payload_size > encoded.len - offset)
                return error.TruncatedFlac;
            if (block_type == 4) {
                if (found) return error.DuplicateFlacVorbisComments;
                result = try parseCommentPayload(
                    encoded[offset..][0..payload_size],
                );
                found = true;
            }
            offset += payload_size;
            if (is_last) break;
        }
        return if (found) result else null;
    }

    pub fn next(self: *CommentIterator) !?CommentView {
        if (self.offset > self.payload.len)
            return error.InvalidFlacVorbisComments;
        if (self.remaining == 0) {
            if (self.offset != self.payload.len)
                return error.InvalidFlacVorbisComments;
            return null;
        }
        if (self.payload.len - self.offset < 4)
            return error.InvalidFlacVorbisComments;
        const field_bytes = std.mem.readInt(
            u32,
            self.payload[self.offset..][0..4],
            .little,
        );
        self.offset += 4;
        if (field_bytes > self.payload.len - self.offset)
            return error.InvalidFlacVorbisComments;
        const field = self.payload[self.offset..][0..field_bytes];
        self.offset += field_bytes;
        self.remaining -= 1;
        if (!std.unicode.utf8ValidateSlice(field))
            return error.InvalidFlacVorbisCommentUtf8;
        const separator = std.mem.indexOfScalar(u8, field, '=') orelse
            return error.InvalidFlacVorbisCommentField;
        const name = field[0..separator];
        try validateCommentName(name);
        return .{
            .name = name,
            .value = field[separator + 1 ..],
        };
    }
};

const streaminfo_bytes = 42;

pub fn requiredBytes(spec: Spec, frame_count: usize) !usize {
    try validateSpec(spec);
    try validateFrameCount(frame_count, spec.block_size);
    const channels: usize = spec.channel_count;
    const sample_bytes = spec.encoding.bytes();
    var total: usize = streaminfo_bytes;
    var first_frame: usize = 0;
    var frame_number: u64 = 0;
    while (first_frame < frame_count) : (frame_number += 1) {
        const block_frames = @min(
            frame_count - first_frame,
            @as(usize, spec.block_size),
        );
        const header_bytes = 4 + codedNumberBytes(frame_number) + 2 + 1;
        const sample_count = std.math.mul(
            usize,
            block_frames,
            channels,
        ) catch return error.FlacSizeOverflow;
        const payload_bytes = std.math.mul(
            usize,
            sample_count,
            sample_bytes,
        ) catch return error.FlacSizeOverflow;
        const subframe_headers = channels;
        const frame_bytes = std.math.add(
            usize,
            header_bytes + subframe_headers + 2,
            payload_bytes,
        ) catch return error.FlacSizeOverflow;
        total = std.math.add(
            usize,
            total,
            frame_bytes,
        ) catch return error.FlacSizeOverflow;
        first_frame += block_frames;
    }
    return total;
}

pub fn requiredPendingSamples(spec: Spec) !usize {
    try validateSpec(spec);
    return std.math.mul(
        usize,
        spec.block_size,
        spec.channel_count,
    ) catch return error.FlacSizeOverflow;
}

pub fn requiredFrameStorageBytes(spec: Spec) !usize {
    try validateSpec(spec);
    const sample_count = try requiredPendingSamples(spec);
    const sample_bytes = std.math.mul(
        usize,
        sample_count,
        spec.encoding.bytes(),
    ) catch return error.FlacSizeOverflow;
    return std.math.add(
        usize,
        sample_bytes,
        4 + 6 + 2 + 1 + spec.channel_count + 2,
    ) catch return error.FlacSizeOverflow;
}

pub fn requiredCommentMetadataBytes(comments: Comments) !usize {
    const payload_bytes = try requiredCommentPayloadBytes(comments);
    return std.math.add(
        usize,
        payload_bytes,
        4,
    ) catch return error.FlacSizeOverflow;
}

pub fn requiredFileWriterMetadataBytes(
    metadata: FileWriterMetadata,
) !usize {
    var total: usize = 0;
    if (metadata.comments) |comments|
        total = try requiredCommentMetadataBytes(comments);
    if (metadata.seek_interval) |interval| {
        if (interval == 0 or metadata.seek_point_capacity == 0)
            return error.InvalidFlacSeekInterval;
        const payload_bytes = std.math.mul(
            usize,
            metadata.seek_point_capacity,
            18,
        ) catch return error.FlacSizeOverflow;
        if (payload_bytes > std.math.maxInt(u24))
            return error.FlacMetadataTooLarge;
        total = std.math.add(
            usize,
            total,
            payload_bytes + 4,
        ) catch return error.FlacSizeOverflow;
    } else if (metadata.seek_point_capacity != 0) {
        return error.InvalidFlacSeekInterval;
    }
    return total;
}

pub fn encodeInterleaved(
    destination: []u8,
    samples: []const i32,
    spec: Spec,
) ![]const u8 {
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.IncompleteSourceFrame;
    const frame_count = samples.len / spec.channel_count;
    try validateFrameCount(frame_count, spec.block_size);
    const required = try requiredBytes(spec, frame_count);
    if (destination.len < required) return error.FlacOutputTooSmall;
    try validateSamples(samples, spec.encoding);
    if (byteSlicesOverlap(destination[0..required], samples))
        return error.OverlappingFlacBuffers;

    @memcpy(destination[0..4], "fLaC");
    destination[4] = 0x80;
    destination[5] = 0;
    destination[6] = 0;
    destination[7] = 34;
    @memset(destination[8..streaminfo_bytes], 0);

    var md5 = std.crypto.hash.Md5.init(.{});
    hashSamples(&md5, samples, spec.encoding);

    var offset: usize = streaminfo_bytes;
    var first_frame: usize = 0;
    var frame_number: u64 = 0;
    var minimum_frame_size: u32 = std.math.maxInt(u24);
    var maximum_frame_size: u32 = 0;
    while (first_frame < frame_count) : (frame_number += 1) {
        const block_frames = @min(
            frame_count - first_frame,
            @as(usize, spec.block_size),
        );
        const next_frame = try encodeVerbatimFrame(
            destination,
            offset,
            samples,
            first_frame,
            block_frames,
            frame_number,
            spec,
        );
        const encoded_size = next_frame - offset;
        if (encoded_size > std.math.maxInt(u24))
            return error.FlacFrameTooLarge;
        minimum_frame_size = @min(minimum_frame_size, @as(u32, @intCast(encoded_size)));
        maximum_frame_size = @max(maximum_frame_size, @as(u32, @intCast(encoded_size)));
        offset = next_frame;
        first_frame += block_frames;
    }

    var digest: [16]u8 = undefined;
    md5.final(&digest);
    writeStreaminfo(
        destination[8..streaminfo_bytes],
        spec,
        frame_count,
        if (frame_count == 0) 0 else minimum_frame_size,
        maximum_frame_size,
        digest,
    );
    return destination[0..offset];
}

pub fn requiredBytesWithComments(
    spec: Spec,
    frame_count: usize,
    comments: Comments,
) !usize {
    const audio_bytes = try requiredBytes(spec, frame_count);
    const comment_payload = try requiredCommentPayloadBytes(comments);
    return std.math.add(
        usize,
        audio_bytes,
        comment_payload + 4,
    ) catch return error.FlacSizeOverflow;
}

pub fn encodeInterleavedWithComments(
    destination: []u8,
    samples: []const i32,
    spec: Spec,
    comments: Comments,
) ![]const u8 {
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.IncompleteSourceFrame;
    const frame_count = samples.len / spec.channel_count;
    const required = try requiredBytesWithComments(
        spec,
        frame_count,
        comments,
    );
    if (destination.len < required) return error.FlacOutputTooSmall;
    if (byteSlicesOverlap(destination[0..required], samples))
        return error.OverlappingFlacBuffers;
    try validateCommentStorageDisjoint(
        destination[0..required],
        comments,
    );
    const encoded = try encodeInterleaved(destination, samples, spec);
    const payload_bytes = try requiredCommentPayloadBytes(comments);
    const metadata_bytes = payload_bytes + 4;
    const final_bytes = encoded.len + metadata_bytes;
    std.mem.copyBackwards(
        u8,
        destination[streaminfo_bytes + metadata_bytes .. final_bytes],
        encoded[streaminfo_bytes..],
    );
    destination[4] = 0;
    destination[streaminfo_bytes] = 0x84;
    writeU24(
        destination[streaminfo_bytes + 1 ..][0..3],
        @intCast(payload_bytes),
    );
    try writeCommentPayload(
        destination[streaminfo_bytes + 4 ..][0..payload_bytes],
        comments,
    );
    return destination[0..final_bytes];
}

pub fn requiredBytesWithSeekTable(
    spec: Spec,
    frame_count: usize,
    encoded_frames_per_point: u32,
) !usize {
    if (encoded_frames_per_point == 0)
        return error.InvalidFlacSeekInterval;
    const audio_bytes = try requiredBytes(spec, frame_count);
    const encoded_frame_count =
        if (frame_count == 0)
            0
        else
            (frame_count - 1) / spec.block_size + 1;
    const point_count =
        if (encoded_frame_count == 0)
            0
        else
            (encoded_frame_count - 1) / encoded_frames_per_point + 1;
    const payload_bytes = std.math.mul(
        usize,
        point_count,
        18,
    ) catch return error.FlacSizeOverflow;
    if (payload_bytes > std.math.maxInt(u24))
        return error.FlacMetadataTooLarge;
    return std.math.add(
        usize,
        audio_bytes,
        payload_bytes + 4,
    ) catch return error.FlacSizeOverflow;
}

pub fn encodeInterleavedWithSeekTable(
    destination: []u8,
    samples: []const i32,
    spec: Spec,
    encoded_frames_per_point: u32,
) ![]const u8 {
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.IncompleteSourceFrame;
    const frame_count = samples.len / spec.channel_count;
    try validateFrameCount(frame_count, spec.block_size);
    const required = try requiredBytesWithSeekTable(
        spec,
        frame_count,
        encoded_frames_per_point,
    );
    if (destination.len < required) return error.FlacOutputTooSmall;
    try validateSamples(samples, spec.encoding);
    if (byteSlicesOverlap(destination[0..required], samples))
        return error.OverlappingFlacBuffers;

    const encoded_frame_count =
        if (frame_count == 0)
            0
        else
            (frame_count - 1) / spec.block_size + 1;
    const point_count =
        if (encoded_frame_count == 0)
            0
        else
            (encoded_frame_count - 1) / encoded_frames_per_point + 1;
    const seek_payload_bytes = std.math.mul(
        usize,
        point_count,
        18,
    ) catch return error.FlacSizeOverflow;
    const audio_offset = streaminfo_bytes + 4 + seek_payload_bytes;

    @memcpy(destination[0..4], "fLaC");
    destination[4] = 0;
    destination[5] = 0;
    destination[6] = 0;
    destination[7] = 34;
    @memset(destination[8..streaminfo_bytes], 0);
    destination[streaminfo_bytes] = 0x83;
    writeU24(
        destination[streaminfo_bytes + 1 ..][0..3],
        @intCast(seek_payload_bytes),
    );

    var md5 = std.crypto.hash.Md5.init(.{});
    hashSamples(&md5, samples, spec.encoding);
    var offset = audio_offset;
    var first_frame: usize = 0;
    var frame_number: u64 = 0;
    var seek_point_index: usize = 0;
    var minimum_frame_size: u32 = std.math.maxInt(u24);
    var maximum_frame_size: u32 = 0;
    while (first_frame < frame_count) : (frame_number += 1) {
        const block_frames = @min(
            frame_count - first_frame,
            @as(usize, spec.block_size),
        );
        if (frame_number % encoded_frames_per_point == 0) {
            const point_offset =
                streaminfo_bytes + 4 + seek_point_index * 18;
            encodeSeekPoint(
                destination[point_offset..][0..18],
                .{
                    .sample_number = first_frame,
                    .byte_offset = offset - audio_offset,
                    .frame_samples = @intCast(block_frames),
                },
            );
            seek_point_index += 1;
        }
        const next_frame = try encodeVerbatimFrame(
            destination,
            offset,
            samples,
            first_frame,
            block_frames,
            frame_number,
            spec,
        );
        const encoded_size = next_frame - offset;
        if (encoded_size > std.math.maxInt(u24))
            return error.FlacFrameTooLarge;
        minimum_frame_size = @min(
            minimum_frame_size,
            @as(u32, @intCast(encoded_size)),
        );
        maximum_frame_size = @max(
            maximum_frame_size,
            @as(u32, @intCast(encoded_size)),
        );
        offset = next_frame;
        first_frame += block_frames;
    }
    if (seek_point_index != point_count)
        return error.InvalidFlacSeekTable;

    var digest: [16]u8 = undefined;
    md5.final(&digest);
    writeStreaminfo(
        destination[8..streaminfo_bytes],
        spec,
        frame_count,
        if (frame_count == 0) 0 else minimum_frame_size,
        maximum_frame_size,
        digest,
    );
    return destination[0..offset];
}

pub fn requiredBytesWithMetadata(
    spec: Spec,
    frame_count: usize,
    metadata: Metadata,
) !usize {
    var total =
        if (metadata.encoded_frames_per_seek_point) |interval|
            try requiredBytesWithSeekTable(
                spec,
                frame_count,
                interval,
            )
        else
            try requiredBytes(spec, frame_count);
    if (metadata.comments) |comments| {
        const payload_bytes = try requiredCommentPayloadBytes(comments);
        total = std.math.add(
            usize,
            total,
            payload_bytes + 4,
        ) catch return error.FlacSizeOverflow;
    }
    return total;
}

pub fn encodeInterleavedWithMetadata(
    destination: []u8,
    samples: []const i32,
    spec: Spec,
    metadata: Metadata,
) ![]const u8 {
    try validateSpec(spec);
    if (samples.len % spec.channel_count != 0)
        return error.IncompleteSourceFrame;
    const frame_count = samples.len / spec.channel_count;
    const required = try requiredBytesWithMetadata(
        spec,
        frame_count,
        metadata,
    );
    if (destination.len < required) return error.FlacOutputTooSmall;
    if (byteSlicesOverlap(destination[0..required], samples))
        return error.OverlappingFlacBuffers;
    if (metadata.comments) |comments|
        try validateCommentStorageDisjoint(
            destination[0..required],
            comments,
        );
    if (metadata.encoded_frames_per_seek_point == null) {
        return if (metadata.comments) |comments|
            encodeInterleavedWithComments(
                destination,
                samples,
                spec,
                comments,
            )
        else
            encodeInterleaved(destination, samples, spec);
    }

    const interval = metadata.encoded_frames_per_seek_point.?;
    const with_seek_table = try encodeInterleavedWithSeekTable(
        destination,
        samples,
        spec,
        interval,
    );
    const comments = metadata.comments orelse
        return with_seek_table;
    const payload_bytes = try requiredCommentPayloadBytes(comments);
    const comment_metadata_bytes = payload_bytes + 4;
    const final_bytes = with_seek_table.len + comment_metadata_bytes;
    std.mem.copyBackwards(
        u8,
        destination[streaminfo_bytes + comment_metadata_bytes .. final_bytes],
        with_seek_table[streaminfo_bytes..],
    );
    destination[streaminfo_bytes] = 4;
    writeU24(
        destination[streaminfo_bytes + 1 ..][0..3],
        @intCast(payload_bytes),
    );
    try writeCommentPayload(
        destination[streaminfo_bytes + 4 ..][0..payload_bytes],
        comments,
    );
    return destination[0..final_bytes];
}

pub fn decodeInterleaved(
    encoded: []const u8,
    destination: []i32,
) !DecodeResult {
    return decodeInterleavedInternal(
        encoded,
        destination,
        &.{},
    );
}

/// Decodes every FLAC channel assignment with caller-owned side scratch.
pub fn decodeInterleavedWithWideScratch(
    encoded: []const u8,
    destination: []i32,
    wide_side_scratch: []i64,
) !DecodeResult {
    return decodeInterleavedInternal(
        encoded,
        destination,
        wide_side_scratch,
    );
}

fn decodeInterleavedInternal(
    encoded: []const u8,
    destination: []i32,
    wide_side_scratch: []i64,
) !DecodeResult {
    if (byteSlicesOverlap(encoded, destination) or
        byteSlicesOverlap(encoded, wide_side_scratch) or
        byteSlicesOverlap(destination, wide_side_scratch))
        return error.OverlappingFlacBuffers;
    var parser = try Parser.init(encoded);
    const channel_count: usize = parser.info.channel_count;
    const declared_frames = std.math.cast(
        usize,
        parser.info.frame_count,
    ) orelse return error.FlacSizeOverflow;
    const required_samples = std.math.mul(
        usize,
        declared_frames,
        channel_count,
    ) catch return error.FlacSizeOverflow;
    if (destination.len < required_samples)
        return error.FlacDestinationTooSmall;

    var frame_index: u64 = 0;
    var frames_decoded: usize = 0;
    while (parser.offset < encoded.len) : (frame_index += 1) {
        const decoded = try parser.decodeFrame(
            destination[frames_decoded * channel_count ..],
            frame_index,
            frames_decoded,
            wide_side_scratch,
        );
        frames_decoded = std.math.add(
            usize,
            frames_decoded,
            decoded,
        ) catch return error.FlacSizeOverflow;
        if (frames_decoded > parser.info.frame_count)
            return error.InvalidFlacFrameCount;
    }
    if (frames_decoded != parser.info.frame_count)
        return error.InvalidFlacFrameCount;

    var md5 = std.crypto.hash.Md5.init(.{});
    hashSamples(
        &md5,
        destination[0..required_samples],
        parser.info.encoding,
    );
    var digest: [16]u8 = undefined;
    md5.final(&digest);
    if (!allZero(&parser.md5) and !std.mem.eql(u8, &digest, &parser.md5))
        return error.FlacMd5Mismatch;
    return .{
        .info = parser.info,
        .frames_decoded = frames_decoded,
    };
}

/// Decodes a bounded frame range using the nearest preceding seek point.
pub fn decodeInterleavedRange(
    encoded: []const u8,
    first_frame: u64,
    destination: []i32,
    frame_scratch: []i32,
) !usize {
    return decodeInterleavedRangeInternal(
        encoded,
        first_frame,
        destination,
        frame_scratch,
        &.{},
    );
}

/// Decodes a range with separate decoded-frame and wide-side scratch.
pub fn decodeInterleavedRangeWithWideScratch(
    encoded: []const u8,
    first_frame: u64,
    destination: []i32,
    frame_scratch: []i32,
    wide_side_scratch: []i64,
) !usize {
    return decodeInterleavedRangeInternal(
        encoded,
        first_frame,
        destination,
        frame_scratch,
        wide_side_scratch,
    );
}

fn decodeInterleavedRangeInternal(
    encoded: []const u8,
    first_frame: u64,
    destination: []i32,
    frame_scratch: []i32,
    wide_side_scratch: []i64,
) !usize {
    if (byteSlicesOverlap(encoded, destination) or
        byteSlicesOverlap(encoded, frame_scratch) or
        byteSlicesOverlap(encoded, wide_side_scratch) or
        byteSlicesOverlap(destination, frame_scratch) or
        byteSlicesOverlap(destination, wide_side_scratch) or
        byteSlicesOverlap(frame_scratch, wide_side_scratch))
        return error.OverlappingFlacBuffers;
    var parser = try Parser.init(encoded);
    const channel_count: usize = parser.info.channel_count;
    if (destination.len % channel_count != 0)
        return error.IncompleteDestinationFrame;
    if (first_frame > parser.info.frame_count)
        return error.FrameIndexOutOfRange;
    const scratch_samples = std.math.mul(
        usize,
        parser.info.maximum_block_size,
        channel_count,
    ) catch return error.FlacSizeOverflow;
    if (frame_scratch.len < scratch_samples)
        return error.FlacFrameScratchTooSmall;

    var current_sample: u64 = 0;
    if (parser.seek_table_payload) |payload| {
        var offset: usize = 0;
        while (offset < payload.len) : (offset += 18) {
            const point = decodeSeekPoint(payload[offset..][0..18]);
            if (point.placeholder() or
                point.sample_number > first_frame)
                break;
            const byte_offset = std.math.cast(
                usize,
                point.byte_offset,
            ) orelse return error.InvalidFlacSeekTable;
            parser.offset = std.math.add(
                usize,
                parser.audio_offset,
                byte_offset,
            ) catch return error.InvalidFlacSeekTable;
            current_sample = point.sample_number;
        }
    }
    const fixed_block_size = parser.info.minimum_block_size ==
        parser.info.maximum_block_size;
    var frame_number: u64 =
        if (fixed_block_size)
            current_sample / parser.info.maximum_block_size
        else
            0;
    const requested_frames = destination.len / channel_count;
    var frames_produced: usize = 0;
    while (frames_produced < requested_frames and
        parser.offset < encoded.len)
    {
        const block_frames = try parser.decodeFrame(
            frame_scratch,
            frame_number,
            current_sample,
            wide_side_scratch,
        );
        const block_end = std.math.add(
            u64,
            current_sample,
            block_frames,
        ) catch return error.FlacSizeOverflow;
        const copy_start = @max(first_frame, current_sample);
        const requested_end = std.math.add(
            u64,
            first_frame,
            requested_frames,
        ) catch return error.FlacSizeOverflow;
        const copy_end = @min(block_end, requested_end);
        if (copy_start < copy_end) {
            const source_frame: usize =
                @intCast(copy_start - current_sample);
            const copied_frames: usize =
                @intCast(copy_end - copy_start);
            const copied_samples = copied_frames * channel_count;
            @memcpy(
                destination[frames_produced * channel_count ..][0..copied_samples],
                frame_scratch[source_frame * channel_count ..][0..copied_samples],
            );
            frames_produced += copied_frames;
        }
        current_sample = block_end;
        frame_number += 1;
    }
    return frames_produced;
}

/// Encodes completely before replacing the file contents.
pub fn writeInterleavedFile(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    samples: []const i32,
    spec: Spec,
) !usize {
    const encoded = try encodeInterleaved(
        encoded_storage,
        samples,
        spec,
    );
    try file.writePositionalAll(io, encoded, 0);
    try file.setLength(io, encoded.len);
    try file.sync(io);
    return encoded.len;
}

/// Encodes audio and comments before replacing the file contents.
pub fn writeInterleavedFileWithComments(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    samples: []const i32,
    spec: Spec,
    comments: Comments,
) !usize {
    const encoded = try encodeInterleavedWithComments(
        encoded_storage,
        samples,
        spec,
        comments,
    );
    try file.writePositionalAll(io, encoded, 0);
    try file.setLength(io, encoded.len);
    try file.sync(io);
    return encoded.len;
}

/// Encodes bounded audio and metadata before replacing the file contents.
pub fn writeInterleavedFileWithMetadata(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    samples: []const i32,
    spec: Spec,
    metadata: Metadata,
) !usize {
    const encoded = try encodeInterleavedWithMetadata(
        encoded_storage,
        samples,
        spec,
        metadata,
    );
    try file.writePositionalAll(io, encoded, 0);
    try file.setLength(io, encoded.len);
    try file.sync(io);
    return encoded.len;
}

/// Reads the complete bounded file into caller storage before decoding.
pub fn readInterleavedFile(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    destination: []i32,
) !DecodeResult {
    if (byteSlicesOverlap(encoded_storage, destination))
        return error.OverlappingFlacBuffers;
    const encoded = try file_reader_io.readBoundedFile(
        io,
        file,
        encoded_storage,
        error.FlacInputBufferTooSmall,
        error.TruncatedFlac,
    );
    return decodeInterleaved(
        encoded,
        destination,
    );
}

/// Reads the bounded file and decodes a frame range with caller scratch.
pub fn readInterleavedFileRange(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    first_frame: u64,
    destination: []i32,
    frame_scratch: []i32,
) !usize {
    if (byteSlicesOverlap(encoded_storage, destination) or
        byteSlicesOverlap(encoded_storage, frame_scratch) or
        byteSlicesOverlap(destination, frame_scratch))
        return error.OverlappingFlacBuffers;
    const encoded = try file_reader_io.readBoundedFile(
        io,
        file,
        encoded_storage,
        error.FlacInputBufferTooSmall,
        error.TruncatedFlac,
    );
    return decodeInterleavedRange(
        encoded,
        first_frame,
        destination,
        frame_scratch,
    );
}

/// Reads a bounded file range with wide side-channel support.
pub fn readInterleavedFileRangeWithWideScratch(
    io: std.Io,
    file: std.Io.File,
    encoded_storage: []u8,
    first_frame: u64,
    destination: []i32,
    frame_scratch: []i32,
    wide_side_scratch: []i64,
) !usize {
    if (byteSlicesOverlap(encoded_storage, destination) or
        byteSlicesOverlap(encoded_storage, frame_scratch) or
        byteSlicesOverlap(encoded_storage, wide_side_scratch) or
        byteSlicesOverlap(destination, frame_scratch) or
        byteSlicesOverlap(destination, wide_side_scratch) or
        byteSlicesOverlap(frame_scratch, wide_side_scratch))
        return error.OverlappingFlacBuffers;
    const encoded = try file_reader_io.readBoundedFile(
        io,
        file,
        encoded_storage,
        error.FlacInputBufferTooSmall,
        error.TruncatedFlac,
    );
    return decodeInterleavedRangeWithWideScratch(
        encoded,
        first_frame,
        destination,
        frame_scratch,
        wide_side_scratch,
    );
}

pub const FileReader = struct {
    io: std.Io,
    file: std.Io.File,
    info: Info,
    md5: [16]u8,
    minimum_frame_size: u32,
    maximum_frame_size: u32,
    audio_offset: u64,
    file_size: u64,
    comment_payload: []const u8,
    seek_table_payload: []const u8,

    pub fn requiredMetadataBytes(
        io: std.Io,
        file: std.Io.File,
    ) !usize {
        return requiredFileReaderMetadataBytes(io, file);
    }

    /// Retains Vorbis comments and seek points in caller storage.
    pub fn init(
        io: std.Io,
        file: std.Io.File,
        metadata_storage: []u8,
    ) !FileReader {
        const stat = try file.stat(io);
        if (stat.size < streaminfo_bytes) return error.TruncatedFlac;
        var signature: [4]u8 = undefined;
        try readFileExact(io, file, 0, &signature);
        if (!std.mem.eql(u8, &signature, "fLaC"))
            return error.InvalidFlacSignature;

        var offset: u64 = 4;
        var parsed_streaminfo: ?ParsedStreaminfo = null;
        var comments_found = false;
        var seek_found = false;
        var metadata_used: usize = 0;
        var comment_payload: []const u8 = &.{};
        var seek_payload: []const u8 = &.{};
        while (true) {
            var header: [4]u8 = undefined;
            try readFileExact(io, file, offset, &header);
            offset += 4;
            const is_last = header[0] & 0x80 != 0;
            const block_type = header[0] & 0x7f;
            if (block_type == 127) return error.ForbiddenFlacMetadata;
            const payload_size =
                (@as(usize, header[1]) << 16) |
                (@as(usize, header[2]) << 8) |
                header[3];
            const payload_end = std.math.add(
                u64,
                offset,
                payload_size,
            ) catch return error.FlacSizeOverflow;
            if (payload_end > stat.size) return error.TruncatedFlac;
            if (parsed_streaminfo == null) {
                if (block_type != 0 or payload_size != 34)
                    return error.InvalidFlacStreaminfo;
                var streaminfo: [34]u8 = undefined;
                try readFileExact(io, file, offset, &streaminfo);
                parsed_streaminfo = try parseStreaminfo(&streaminfo);
            } else if (block_type == 0) {
                return error.DuplicateFlacStreaminfo;
            } else if (block_type == 4) {
                if (comments_found)
                    return error.DuplicateFlacVorbisComments;
                if (payload_size > metadata_storage.len - metadata_used)
                    return error.FlacMetadataBufferTooSmall;
                const payload =
                    metadata_storage[metadata_used..][0..payload_size];
                try readFileExact(io, file, offset, payload);
                try validateCommentPayload(payload);
                comment_payload = payload;
                metadata_used += payload_size;
                comments_found = true;
            } else if (block_type == 3) {
                if (seek_found) return error.DuplicateFlacSeekTable;
                if (payload_size > metadata_storage.len - metadata_used)
                    return error.FlacMetadataBufferTooSmall;
                const payload =
                    metadata_storage[metadata_used..][0..payload_size];
                try readFileExact(io, file, offset, payload);
                try validateSeekTablePayload(payload);
                seek_payload = payload;
                metadata_used += payload_size;
                seek_found = true;
            }
            offset = payload_end;
            if (is_last) break;
        }
        const parsed = parsed_streaminfo orelse
            return error.MissingFlacStreaminfo;
        if (parsed.info.frame_count == 0 and offset < stat.size)
            return error.UnsupportedUnknownFlacFrameCount;
        try validateFileSeekTable(
            io,
            file,
            seek_payload,
            parsed.info,
            offset,
            stat.size,
        );
        return .{
            .io = io,
            .file = file,
            .info = parsed.info,
            .md5 = parsed.md5,
            .minimum_frame_size = parsed.minimum_frame_size,
            .maximum_frame_size = parsed.maximum_frame_size,
            .audio_offset = offset,
            .file_size = stat.size,
            .comment_payload = comment_payload,
            .seek_table_payload = seek_payload,
        };
    }

    pub fn commentIterator(
        self: *const FileReader,
    ) !?CommentIterator {
        try self.validateState();
        if (self.comment_payload.len == 0) return null;
        return try parseCommentPayload(self.comment_payload);
    }

    pub fn seekTableIterator(
        self: *const FileReader,
    ) ?SeekTableIterator {
        if (self.seek_table_payload.len == 0) return null;
        validateSeekTablePayload(self.seek_table_payload) catch return null;
        return .{ .payload = self.seek_table_payload };
    }

    pub fn decode(
        self: *const FileReader,
        destination: []i32,
        frame_storage: []u8,
        wide_side_scratch: []i64,
    ) !DecodeResult {
        try self.validateState();
        if (byteSlicesOverlap(destination, frame_storage) or
            byteSlicesOverlap(destination, wide_side_scratch) or
            byteSlicesOverlap(frame_storage, wide_side_scratch))
            return error.OverlappingFlacBuffers;
        const channels: usize = self.info.channel_count;
        const frames: usize = std.math.cast(
            usize,
            self.info.frame_count,
        ) orelse return error.FlacSizeOverflow;
        const required_samples = std.math.mul(
            usize,
            frames,
            channels,
        ) catch return error.FlacSizeOverflow;
        if (destination.len < required_samples)
            return error.FlacDestinationTooSmall;
        var file_offset = self.audio_offset;
        var decoded_frames: usize = 0;
        var frame_number: u64 = 0;
        var variable_blocking: ?bool = null;
        while (file_offset < self.file_size) : (frame_number += 1) {
            const decoded = try self.decodeFrameAt(
                &file_offset,
                destination[decoded_frames * channels ..],
                frame_storage,
                frame_number,
                decoded_frames,
                &variable_blocking,
                wide_side_scratch,
            );
            decoded_frames = std.math.add(
                usize,
                decoded_frames,
                decoded,
            ) catch return error.FlacSizeOverflow;
        }
        if (decoded_frames != frames) return error.InvalidFlacFrameCount;
        var md5 = std.crypto.hash.Md5.init(.{});
        hashSamples(
            &md5,
            destination[0 .. frames * channels],
            self.info.encoding,
        );
        var digest: [16]u8 = undefined;
        md5.final(&digest);
        if (!allZero(&self.md5) and !std.mem.eql(u8, &digest, &self.md5))
            return error.FlacMd5Mismatch;
        return .{ .info = self.info, .frames_decoded = decoded_frames };
    }

    pub fn decodeRange(
        self: *const FileReader,
        first_frame: u64,
        destination: []i32,
        frame_storage: []u8,
        decoded_frame_scratch: []i32,
        wide_side_scratch: []i64,
    ) !usize {
        try self.validateState();
        if (byteSlicesOverlap(destination, frame_storage) or
            byteSlicesOverlap(destination, decoded_frame_scratch) or
            byteSlicesOverlap(destination, wide_side_scratch) or
            byteSlicesOverlap(frame_storage, decoded_frame_scratch) or
            byteSlicesOverlap(frame_storage, wide_side_scratch) or
            byteSlicesOverlap(decoded_frame_scratch, wide_side_scratch))
            return error.OverlappingFlacBuffers;
        const channels: usize = self.info.channel_count;
        if (destination.len % channels != 0)
            return error.IncompleteDestinationFrame;
        if (first_frame > self.info.frame_count)
            return error.FrameIndexOutOfRange;
        const scratch_samples = std.math.mul(
            usize,
            self.info.maximum_block_size,
            channels,
        ) catch return error.FlacSizeOverflow;
        if (decoded_frame_scratch.len < scratch_samples)
            return error.FlacFrameScratchTooSmall;

        var file_offset = self.audio_offset;
        var current_sample: u64 = 0;
        for (0..self.seek_table_payload.len / 18) |index| {
            const point = decodeSeekPoint(
                self.seek_table_payload[index * 18 ..][0..18],
            );
            if (point.placeholder() or point.sample_number > first_frame)
                break;
            file_offset = std.math.add(
                u64,
                self.audio_offset,
                point.byte_offset,
            ) catch return error.InvalidFlacSeekTable;
            current_sample = point.sample_number;
        }
        const fixed_blocks =
            self.info.minimum_block_size == self.info.maximum_block_size;
        var frame_number = if (fixed_blocks)
            current_sample / self.info.maximum_block_size
        else
            0;
        const requested = destination.len / channels;
        var produced: usize = 0;
        var variable_blocking: ?bool = null;
        while (produced < requested and file_offset < self.file_size) {
            const block_frames = try self.decodeFrameAt(
                &file_offset,
                decoded_frame_scratch,
                frame_storage,
                frame_number,
                current_sample,
                &variable_blocking,
                wide_side_scratch,
            );
            const block_end = std.math.add(
                u64,
                current_sample,
                block_frames,
            ) catch return error.FlacSizeOverflow;
            const copy_start = @max(first_frame, current_sample);
            const requested_end = std.math.add(
                u64,
                first_frame,
                requested,
            ) catch return error.FlacSizeOverflow;
            const copy_end = @min(
                block_end,
                requested_end,
            );
            if (copy_start < copy_end) {
                const source_frame: usize =
                    @intCast(copy_start - current_sample);
                const copied_frames: usize =
                    @intCast(copy_end - copy_start);
                const copied_samples = copied_frames * channels;
                @memcpy(
                    destination[produced * channels ..][0..copied_samples],
                    decoded_frame_scratch[source_frame * channels ..][0..copied_samples],
                );
                produced += copied_frames;
            }
            current_sample = block_end;
            frame_number += 1;
        }
        return produced;
    }

    fn decodeFrameAt(
        self: *const FileReader,
        file_offset: *u64,
        destination: []i32,
        frame_storage: []u8,
        expected_frame_number: u64,
        expected_sample_number: u64,
        variable_blocking: *?bool,
        wide_side_scratch: []i64,
    ) !usize {
        const remaining = self.file_size - file_offset.*;
        const declared = if (self.maximum_frame_size == 0)
            frame_storage.len
        else
            self.maximum_frame_size;
        if (declared > frame_storage.len)
            return error.FlacFrameBufferTooSmall;
        const loaded: usize = @intCast(@min(remaining, declared));
        if (loaded == 0) return error.TruncatedFlac;
        try readFileExact(
            self.io,
            self.file,
            file_offset.*,
            frame_storage[0..loaded],
        );
        var parser = Parser{
            .encoded = frame_storage[0..loaded],
            .offset = 0,
            .info = self.info,
            .md5 = self.md5,
            .minimum_frame_size = self.minimum_frame_size,
            .maximum_frame_size = self.maximum_frame_size,
            .variable_blocking = variable_blocking.*,
            .audio_offset = 0,
            .seek_table_payload = null,
        };
        const frames = try parser.decodeFrame(
            destination,
            expected_frame_number,
            expected_sample_number,
            wide_side_scratch,
        );
        variable_blocking.* = parser.variable_blocking;
        file_offset.* = std.math.add(
            u64,
            file_offset.*,
            parser.offset,
        ) catch return error.FlacSizeOverflow;
        if (frames < self.info.minimum_block_size and
            file_offset.* != self.file_size)
            return error.InvalidFlacBlockSize;
        return frames;
    }

    fn validateState(self: *const FileReader) !void {
        const encoding = @intFromEnum(self.info.encoding);
        if (self.info.sample_rate == 0 or
            self.info.channel_count == 0 or
            self.info.channel_count > 8 or
            (encoding != 8 and
                encoding != 16 and
                encoding != 24 and
                encoding != 32) or
            self.info.minimum_block_size < 16 or
            self.info.maximum_block_size < self.info.minimum_block_size or
            (self.minimum_frame_size != 0 and
                self.maximum_frame_size != 0 and
                self.minimum_frame_size > self.maximum_frame_size) or
            self.audio_offset > self.file_size or
            (self.info.frame_count == 0 and
                self.audio_offset != self.file_size) or
            (self.info.frame_count != 0 and
                self.audio_offset == self.file_size))
            return error.InvalidFlacFileReaderState;

        if (self.comment_payload.len != 0)
            validateCommentPayload(self.comment_payload) catch
                return error.InvalidFlacFileReaderState;
        validateSeekTablePayload(self.seek_table_payload) catch
            return error.InvalidFlacFileReaderState;
        for (0..self.seek_table_payload.len / 18) |index| {
            const point = decodeSeekPoint(
                self.seek_table_payload[index * 18 ..][0..18],
            );
            if (point.placeholder()) continue;
            const point_end = std.math.add(
                u64,
                point.sample_number,
                point.frame_samples,
            ) catch return error.InvalidFlacFileReaderState;
            const target = std.math.add(
                u64,
                self.audio_offset,
                point.byte_offset,
            ) catch return error.InvalidFlacFileReaderState;
            if (point.sample_number >= self.info.frame_count or
                point.frame_samples > self.info.maximum_block_size or
                point_end > self.info.frame_count or
                target > self.file_size -| 2)
                return error.InvalidFlacFileReaderState;
        }
    }
};

pub fn requiredFileReaderMetadataBytes(
    io: std.Io,
    file: std.Io.File,
) !usize {
    const stat = try file.stat(io);
    if (stat.size < streaminfo_bytes) return error.TruncatedFlac;
    var signature: [4]u8 = undefined;
    try readFileExact(io, file, 0, &signature);
    if (!std.mem.eql(u8, &signature, "fLaC"))
        return error.InvalidFlacSignature;

    var offset: u64 = 4;
    var first_block = true;
    var comments_found = false;
    var seek_found = false;
    var required: usize = 0;
    while (true) {
        var header: [4]u8 = undefined;
        try readFileExact(io, file, offset, &header);
        offset += 4;
        const is_last = header[0] & 0x80 != 0;
        const block_type = header[0] & 0x7f;
        if (block_type == 127) return error.ForbiddenFlacMetadata;
        const payload_size =
            (@as(usize, header[1]) << 16) |
            (@as(usize, header[2]) << 8) |
            header[3];
        const payload_end = std.math.add(
            u64,
            offset,
            payload_size,
        ) catch return error.FlacSizeOverflow;
        if (payload_end > stat.size) return error.TruncatedFlac;

        if (first_block) {
            if (block_type != 0 or payload_size != 34)
                return error.InvalidFlacStreaminfo;
            first_block = false;
        } else if (block_type == 0) {
            return error.DuplicateFlacStreaminfo;
        } else if (block_type == 4) {
            if (comments_found)
                return error.DuplicateFlacVorbisComments;
            required = std.math.add(
                usize,
                required,
                payload_size,
            ) catch return error.FlacSizeOverflow;
            comments_found = true;
        } else if (block_type == 3) {
            if (seek_found) return error.DuplicateFlacSeekTable;
            required = std.math.add(
                usize,
                required,
                payload_size,
            ) catch return error.FlacSizeOverflow;
            seek_found = true;
        }
        offset = payload_end;
        if (is_last) break;
    }
    return required;
}

fn readFileExact(
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
        error.TruncatedFlac,
    );
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

fn validateFileSeekTable(
    io: std.Io,
    file: std.Io.File,
    payload: []const u8,
    info: Info,
    audio_offset: u64,
    file_size: u64,
) !void {
    for (0..payload.len / 18) |index| {
        const point = decodeSeekPoint(payload[index * 18 ..][0..18]);
        if (point.placeholder()) continue;
        if (point.sample_number >= info.frame_count or
            point.frame_samples > info.maximum_block_size)
            return error.InvalidFlacSeekTable;
        const point_end = std.math.add(
            u64,
            point.sample_number,
            point.frame_samples,
        ) catch return error.InvalidFlacSeekTable;
        const target = std.math.add(
            u64,
            audio_offset,
            point.byte_offset,
        ) catch return error.InvalidFlacSeekTable;
        if (point_end > info.frame_count or target > file_size -| 2)
            return error.InvalidFlacSeekTable;
        var sync: [2]u8 = undefined;
        try readFileExact(io, file, target, &sync);
        if (sync[0] != 0xff or (sync[1] != 0xf8 and sync[1] != 0xf9))
            return error.InvalidFlacSeekTable;
    }
}

const Parser = struct {
    encoded: []const u8,
    offset: usize,
    info: Info,
    md5: [16]u8,
    minimum_frame_size: u32,
    maximum_frame_size: u32,
    variable_blocking: ?bool = null,
    audio_offset: usize,
    seek_table_payload: ?[]const u8,

    fn init(encoded: []const u8) !Parser {
        if (encoded.len < streaminfo_bytes)
            return error.TruncatedFlac;
        if (!std.mem.eql(u8, encoded[0..4], "fLaC"))
            return error.InvalidFlacSignature;
        var offset: usize = 4;
        var streaminfo_found = false;
        var vorbis_comments_found = false;
        var seek_table_found = false;
        var seek_table_payload: ?[]const u8 = null;
        var info: Info = undefined;
        var md5: [16]u8 = undefined;
        var minimum_frame_size: u32 = 0;
        var maximum_frame_size: u32 = 0;
        while (true) {
            if (encoded.len - offset < 4) return error.TruncatedFlac;
            const header = encoded[offset];
            const is_last = header & 0x80 != 0;
            const block_type = header & 0x7f;
            if (block_type == 127) return error.ForbiddenFlacMetadata;
            const payload_size =
                (@as(usize, encoded[offset + 1]) << 16) |
                (@as(usize, encoded[offset + 2]) << 8) |
                encoded[offset + 3];
            offset += 4;
            if (payload_size > encoded.len - offset)
                return error.TruncatedFlac;
            if (!streaminfo_found) {
                if (block_type != 0 or payload_size != 34)
                    return error.InvalidFlacStreaminfo;
                const parsed = try parseStreaminfo(
                    encoded[offset..][0..34],
                );
                info = parsed.info;
                md5 = parsed.md5;
                minimum_frame_size = parsed.minimum_frame_size;
                maximum_frame_size = parsed.maximum_frame_size;
                streaminfo_found = true;
            } else if (block_type == 0) {
                return error.DuplicateFlacStreaminfo;
            } else if (block_type == 4) {
                if (vorbis_comments_found)
                    return error.DuplicateFlacVorbisComments;
                try validateCommentPayload(
                    encoded[offset..][0..payload_size],
                );
                vorbis_comments_found = true;
            } else if (block_type == 3) {
                if (seek_table_found)
                    return error.DuplicateFlacSeekTable;
                try validateSeekTablePayload(
                    encoded[offset..][0..payload_size],
                );
                seek_table_found = true;
                seek_table_payload =
                    encoded[offset..][0..payload_size];
            }
            offset += payload_size;
            if (is_last) break;
        }
        if (!streaminfo_found) return error.MissingFlacStreaminfo;
        if (seek_table_payload) |payload|
            try validateSeekTableAgainstStream(
                payload,
                info,
                encoded[offset..],
            );
        if (info.frame_count == 0 and offset < encoded.len)
            return error.UnsupportedUnknownFlacFrameCount;
        return .{
            .encoded = encoded,
            .offset = offset,
            .info = info,
            .md5 = md5,
            .minimum_frame_size = minimum_frame_size,
            .maximum_frame_size = maximum_frame_size,
            .audio_offset = offset,
            .seek_table_payload = seek_table_payload,
        };
    }

    fn decodeFrame(
        self: *Parser,
        destination: []i32,
        expected_frame_number: u64,
        expected_sample_number: u64,
        wide_side_scratch: []i64,
    ) !usize {
        const frame_start = self.offset;
        if (self.encoded.len - self.offset < 8)
            return error.TruncatedFlac;
        if (self.encoded[self.offset] != 0xff or
            (self.encoded[self.offset + 1] != 0xf8 and
                self.encoded[self.offset + 1] != 0xf9))
            return error.UnsupportedFlacBlockingStrategy;
        const variable_blocking = self.encoded[self.offset + 1] == 0xf9;
        if (self.variable_blocking) |previous| {
            if (previous != variable_blocking)
                return error.FlacBlockingStrategyChanged;
        } else {
            self.variable_blocking = variable_blocking;
        }
        self.offset += 2;
        const block_and_rate = self.encoded[self.offset];
        self.offset += 1;
        const block_code = block_and_rate >> 4;
        const rate_code = block_and_rate & 0x0f;
        const channels_and_depth = self.encoded[self.offset];
        self.offset += 1;
        if (channels_and_depth & 1 != 0)
            return error.InvalidFlacFrameHeader;
        const channel_code = channels_and_depth >> 4;
        const frame_channel_count: u8 = switch (channel_code) {
            0...7 => channel_code + 1,
            8...10 => 2,
            else => return error.UnsupportedFlacChannelAssignment,
        };
        if (frame_channel_count != self.info.channel_count)
            return error.FlacStreamPropertyChanged;
        const depth = try decodeDepth(
            (channels_and_depth >> 1) & 0x07,
            self.info.encoding,
        );
        if (depth != self.info.encoding)
            return error.FlacStreamPropertyChanged;

        const coded = try decodeCodedNumber(
            self.encoded,
            &self.offset,
        );
        const expected_number =
            if (variable_blocking)
                expected_sample_number
            else
                expected_frame_number;
        if (coded != expected_number)
            return error.InvalidFlacFrameNumber;
        const block_size = try decodeBlockSize(
            self.encoded,
            &self.offset,
            block_code,
        );
        const sample_rate = try decodeSampleRate(
            self.encoded,
            &self.offset,
            rate_code,
            self.info.sample_rate,
        );
        if (sample_rate != self.info.sample_rate)
            return error.FlacStreamPropertyChanged;
        if (block_size > self.info.maximum_block_size)
            return error.InvalidFlacBlockSize;
        if (self.offset >= self.encoded.len)
            return error.TruncatedFlac;
        const stored_header_crc = self.encoded[self.offset];
        if (crc8(self.encoded[frame_start..self.offset]) !=
            stored_header_crc)
            return error.FlacHeaderCrcMismatch;
        self.offset += 1;

        const required_samples = std.math.mul(
            usize,
            block_size,
            self.info.channel_count,
        ) catch return error.FlacSizeOverflow;
        if (destination.len < required_samples)
            return error.FlacDestinationTooSmall;
        var reader = BitReader{
            .bytes = self.encoded,
            .bit_position = self.offset * 8,
        };
        var used_wide_side = false;
        for (0..self.info.channel_count) |channel| {
            const subframe_bit_depth: u6 = switch (channel_code) {
                8 => if (channel == 1)
                    self.info.encoding.bits() + 1
                else
                    self.info.encoding.bits(),
                9 => if (channel == 0)
                    self.info.encoding.bits() + 1
                else
                    self.info.encoding.bits(),
                10 => if (channel == 1)
                    self.info.encoding.bits() + 1
                else
                    self.info.encoding.bits(),
                else => self.info.encoding.bits(),
            };
            if (subframe_bit_depth > 32) {
                if (wide_side_scratch.len < block_size)
                    return error.FlacWideSideScratchTooSmall;
                try decodeSubframe(
                    i64,
                    &reader,
                    wide_side_scratch[0..block_size],
                    block_size,
                    1,
                    0,
                    subframe_bit_depth,
                );
                used_wide_side = true;
            } else {
                try decodeSubframe(
                    i32,
                    &reader,
                    destination,
                    block_size,
                    self.info.channel_count,
                    channel,
                    subframe_bit_depth,
                );
            }
        }
        if (used_wide_side) {
            try restoreStereoChannelsWide(
                destination,
                wide_side_scratch[0..block_size],
                block_size,
                channel_code,
            );
        } else {
            try restoreStereoChannels(
                destination,
                block_size,
                channel_code,
            );
        }
        try reader.alignZero();
        self.offset = try reader.byteOffset();
        if (self.encoded.len - self.offset < 2)
            return error.TruncatedFlac;
        const stored_crc = std.mem.readInt(
            u16,
            self.encoded[self.offset..][0..2],
            .big,
        );
        if (crc16(self.encoded[frame_start..self.offset]) != stored_crc)
            return error.FlacFrameCrcMismatch;
        self.offset += 2;
        const frame_bytes = self.offset - frame_start;
        if ((self.minimum_frame_size != 0 and
            frame_bytes < self.minimum_frame_size) or
            (self.maximum_frame_size != 0 and
                frame_bytes > self.maximum_frame_size))
            return error.InvalidFlacFrameSize;
        if (block_size < self.info.minimum_block_size and
            self.offset != self.encoded.len)
            return error.InvalidFlacBlockSize;
        return block_size;
    }
};

fn requiredCommentPayloadBytes(comments: Comments) !usize {
    if (!std.unicode.utf8ValidateSlice(comments.vendor))
        return error.InvalidFlacVorbisCommentUtf8;
    if (comments.vendor.len > std.math.maxInt(u32) or
        comments.fields.len > std.math.maxInt(u32))
        return error.FlacMetadataTooLarge;
    var total = std.math.add(
        usize,
        8,
        comments.vendor.len,
    ) catch return error.FlacSizeOverflow;
    for (comments.fields) |field| {
        try validateCommentName(field.name);
        if (!std.unicode.utf8ValidateSlice(field.value))
            return error.InvalidFlacVorbisCommentUtf8;
        const name_bytes = std.math.add(
            usize,
            field.name.len,
            1,
        ) catch return error.FlacSizeOverflow;
        const field_bytes = std.math.add(
            usize,
            name_bytes,
            field.value.len,
        ) catch return error.FlacSizeOverflow;
        if (field_bytes > std.math.maxInt(u32))
            return error.FlacMetadataTooLarge;
        const stored_field_bytes = std.math.add(
            usize,
            field_bytes,
            4,
        ) catch return error.FlacSizeOverflow;
        total = std.math.add(
            usize,
            total,
            stored_field_bytes,
        ) catch return error.FlacSizeOverflow;
    }
    if (total > std.math.maxInt(u24))
        return error.FlacMetadataTooLarge;
    return total;
}

fn validateCommentStorageDisjoint(
    destination: []const u8,
    comments: Comments,
) !void {
    if (byteSlicesOverlap(destination, comments.vendor) or
        byteSlicesOverlap(destination, comments.fields))
        return error.OverlappingFlacBuffers;
    for (comments.fields) |field| {
        if (byteSlicesOverlap(destination, field.name) or
            byteSlicesOverlap(destination, field.value))
            return error.OverlappingFlacBuffers;
    }
}

fn writeCommentPayload(
    destination: []u8,
    comments: Comments,
) !void {
    const required = try requiredCommentPayloadBytes(comments);
    if (destination.len < required) return error.FlacOutputTooSmall;
    std.mem.writeInt(
        u32,
        destination[0..4],
        @intCast(comments.vendor.len),
        .little,
    );
    @memcpy(destination[4..][0..comments.vendor.len], comments.vendor);
    var offset = 4 + comments.vendor.len;
    std.mem.writeInt(
        u32,
        destination[offset..][0..4],
        @intCast(comments.fields.len),
        .little,
    );
    offset += 4;
    for (comments.fields) |field| {
        const field_bytes = field.name.len + 1 + field.value.len;
        std.mem.writeInt(
            u32,
            destination[offset..][0..4],
            @intCast(field_bytes),
            .little,
        );
        offset += 4;
        @memcpy(destination[offset..][0..field.name.len], field.name);
        offset += field.name.len;
        destination[offset] = '=';
        offset += 1;
        @memcpy(destination[offset..][0..field.value.len], field.value);
        offset += field.value.len;
    }
}

fn parseCommentPayload(payload: []const u8) !CommentIterator {
    if (payload.len < 8) return error.InvalidFlacVorbisComments;
    const vendor_bytes = std.mem.readInt(u32, payload[0..4], .little);
    if (vendor_bytes > payload.len - 8)
        return error.InvalidFlacVorbisComments;
    const vendor_end = 4 + @as(usize, vendor_bytes);
    const vendor = payload[4..vendor_end];
    if (!std.unicode.utf8ValidateSlice(vendor))
        return error.InvalidFlacVorbisCommentUtf8;
    const field_count = std.mem.readInt(
        u32,
        payload[vendor_end..][0..4],
        .little,
    );
    return .{
        .payload = payload,
        .offset = vendor_end + 4,
        .remaining = field_count,
        .vendor = vendor,
    };
}

fn validateCommentPayload(payload: []const u8) !void {
    var iterator = try parseCommentPayload(payload);
    while (try iterator.next()) |_| {}
}

fn validateCommentName(name: []const u8) !void {
    if (name.len == 0) return error.InvalidFlacVorbisCommentField;
    for (name) |byte| {
        if (byte < 0x20 or byte > 0x7e or byte == '=')
            return error.InvalidFlacVorbisCommentField;
    }
}

fn encodeSeekPoint(destination: *[18]u8, point: SeekPoint) void {
    std.mem.writeInt(
        u64,
        destination[0..8],
        point.sample_number,
        .big,
    );
    std.mem.writeInt(
        u64,
        destination[8..16],
        point.byte_offset,
        .big,
    );
    std.mem.writeInt(
        u16,
        destination[16..18],
        point.frame_samples,
        .big,
    );
}

fn decodeSeekPoint(source: *const [18]u8) SeekPoint {
    return .{
        .sample_number = std.mem.readInt(u64, source[0..8], .big),
        .byte_offset = std.mem.readInt(u64, source[8..16], .big),
        .frame_samples = std.mem.readInt(u16, source[16..18], .big),
    };
}

fn validateSeekTablePayload(payload: []const u8) !void {
    if (payload.len % 18 != 0)
        return error.InvalidFlacSeekTable;
    var offset: usize = 0;
    var previous_sample: ?u64 = null;
    var placeholders_started = false;
    while (offset < payload.len) : (offset += 18) {
        const point = decodeSeekPoint(payload[offset..][0..18]);
        if (point.placeholder()) {
            placeholders_started = true;
            continue;
        }
        if (placeholders_started)
            return error.InvalidFlacSeekTable;
        if (point.frame_samples == 0)
            return error.InvalidFlacSeekTable;
        if (previous_sample) |previous| {
            if (point.sample_number <= previous)
                return error.InvalidFlacSeekTable;
        }
        previous_sample = point.sample_number;
    }
}

fn validateSeekTableAgainstStream(
    payload: []const u8,
    info: Info,
    audio_frames: []const u8,
) !void {
    var offset: usize = 0;
    while (offset < payload.len) : (offset += 18) {
        const point = decodeSeekPoint(payload[offset..][0..18]);
        if (point.placeholder()) continue;
        if (point.sample_number >= info.frame_count or
            point.frame_samples > info.maximum_block_size)
            return error.InvalidFlacSeekTable;
        const point_end = std.math.add(
            u64,
            point.sample_number,
            point.frame_samples,
        ) catch return error.InvalidFlacSeekTable;
        if (point_end > info.frame_count or
            point.byte_offset > audio_frames.len -| 2)
            return error.InvalidFlacSeekTable;
        const byte_offset: usize = @intCast(point.byte_offset);
        if (audio_frames[byte_offset] != 0xff or
            (audio_frames[byte_offset + 1] != 0xf8 and
                audio_frames[byte_offset + 1] != 0xf9))
            return error.InvalidFlacSeekTable;
    }
}

const ParsedStreaminfo = struct {
    info: Info,
    md5: [16]u8,
    minimum_frame_size: u32,
    maximum_frame_size: u32,
};

fn parseStreaminfo(bytes: *const [34]u8) !ParsedStreaminfo {
    const minimum_block_size = std.mem.readInt(u16, bytes[0..2], .big);
    const maximum_block_size = std.mem.readInt(u16, bytes[2..4], .big);
    if (minimum_block_size < 16 or
        maximum_block_size < minimum_block_size)
        return error.InvalidFlacStreaminfo;
    const minimum_frame_size = readU24(bytes[4..7]);
    const maximum_frame_size = readU24(bytes[7..10]);
    if (minimum_frame_size != 0 and
        maximum_frame_size != 0 and
        minimum_frame_size > maximum_frame_size)
        return error.InvalidFlacStreaminfo;
    const stream_fields = std.mem.readInt(u64, bytes[10..18], .big);
    const sample_rate: u32 = @intCast((stream_fields >> 44) & 0xfffff);
    const channel_count: u8 = @intCast(((stream_fields >> 41) & 0x7) + 1);
    const bits_per_sample: u8 =
        @intCast(((stream_fields >> 36) & 0x1f) + 1);
    const encoding: Encoding = switch (bits_per_sample) {
        8 => .pcm_i8,
        16 => .pcm_i16,
        24 => .pcm_i24,
        32 => .pcm_i32,
        else => return error.UnsupportedFlacBitDepth,
    };
    if (sample_rate == 0) return error.UnsupportedNonAudioFlac;
    var md5: [16]u8 = undefined;
    @memcpy(&md5, bytes[18..34]);
    return .{
        .info = .{
            .sample_rate = sample_rate,
            .channel_count = channel_count,
            .encoding = encoding,
            .frame_count = stream_fields & 0xfffffffff,
            .minimum_block_size = minimum_block_size,
            .maximum_block_size = maximum_block_size,
        },
        .md5 = md5,
        .minimum_frame_size = minimum_frame_size,
        .maximum_frame_size = maximum_frame_size,
    };
}

fn encodeVerbatimFrame(
    destination: []u8,
    start: usize,
    samples: []const i32,
    first_frame: usize,
    block_frames: usize,
    frame_number: u64,
    spec: Spec,
) !usize {
    var offset = start;
    destination[offset] = 0xff;
    destination[offset + 1] = 0xf8;
    destination[offset + 2] = 0x70;
    destination[offset + 3] =
        ((spec.channel_count - 1) << 4) |
        (depthCode(spec.encoding) << 1);
    offset += 4;
    offset += try encodeCodedNumber(
        destination[offset..],
        frame_number,
    );
    if (block_frames == 0 or block_frames > std.math.maxInt(u16))
        return error.InvalidFlacBlockSize;
    std.mem.writeInt(
        u16,
        destination[offset..][0..2],
        @intCast(block_frames - 1),
        .big,
    );
    offset += 2;
    destination[offset] = crc8(destination[start..offset]);
    offset += 1;

    var writer = BitWriter{
        .bytes = destination,
        .bit_position = offset * 8,
    };
    for (0..spec.channel_count) |channel| {
        try encodeSubframe(
            &writer,
            samples,
            first_frame,
            block_frames,
            spec.channel_count,
            channel,
            spec.encoding.bits(),
        );
    }
    try writer.padZero();
    offset = try writer.byteOffset();
    const checksum = crc16(destination[start..offset]);
    std.mem.writeInt(
        u16,
        destination[offset..][0..2],
        checksum,
        .big,
    );
    return offset + 2;
}

const FixedPlan = struct {
    order: u3,
    rice_parameter: u4,
    bit_count: u64,
};

fn encodeSubframe(
    writer: *BitWriter,
    samples: []const i32,
    first_frame: usize,
    block_frames: usize,
    channel_count: usize,
    channel: usize,
    bit_depth: u6,
) !void {
    const first_sample = samples[first_frame * channel_count + channel];
    var constant = true;
    for (1..block_frames) |frame| {
        if (samples[(first_frame + frame) * channel_count + channel] !=
            first_sample)
        {
            constant = false;
            break;
        }
    }
    if (constant) {
        try writer.writeUnsigned(8, 0);
        try writer.writeSigned(bit_depth, first_sample);
        return;
    }

    const plan = chooseFixedPlan(
        samples,
        first_frame,
        block_frames,
        channel_count,
        channel,
        bit_depth,
    );
    const verbatim_bits =
        @as(u64, 8) + @as(u64, block_frames) * bit_depth;
    if (plan == null or plan.?.bit_count >= verbatim_bits) {
        try writer.writeUnsigned(8, 2);
        for (0..block_frames) |frame| {
            const sample_index =
                (first_frame + frame) * channel_count + channel;
            try writer.writeSigned(bit_depth, samples[sample_index]);
        }
        return;
    }

    const selected = plan.?;
    try writer.writeUnsigned(1, 0);
    try writer.writeUnsigned(6, 8 + @as(u64, selected.order));
    try writer.writeUnsigned(1, 0);
    for (0..selected.order) |frame| {
        const sample_index =
            (first_frame + frame) * channel_count + channel;
        try writer.writeSigned(bit_depth, samples[sample_index]);
    }
    try writer.writeUnsigned(2, 0);
    try writer.writeUnsigned(4, 0);
    try writer.writeUnsigned(4, selected.rice_parameter);
    for (selected.order..block_frames) |frame| {
        const residual = fixedResidual(
            samples,
            first_frame,
            channel_count,
            channel,
            frame,
            selected.order,
        );
        if (residual <= std.math.minInt(i32) or
            residual > std.math.maxInt(i32))
            return error.FlacResidualOutOfRange;
        const folded = foldResidual(residual);
        const quotient = folded >> selected.rice_parameter;
        try writer.writeZeroes(quotient);
        try writer.writeUnsigned(1, 1);
        if (selected.rice_parameter != 0) {
            const mask =
                (@as(u64, 1) << selected.rice_parameter) - 1;
            try writer.writeUnsigned(
                selected.rice_parameter,
                folded & mask,
            );
        }
    }
}

fn chooseFixedPlan(
    samples: []const i32,
    first_frame: usize,
    block_frames: usize,
    channel_count: usize,
    channel: usize,
    bit_depth: u6,
) ?FixedPlan {
    var best: ?FixedPlan = null;
    const maximum_order: u3 = @intCast(@min(block_frames - 1, 4));
    var order: u3 = 0;
    while (order <= maximum_order) : (order += 1) {
        var parameter: u4 = 0;
        while (parameter < 15) : (parameter += 1) {
            var bits =
                @as(u64, 8) +
                @as(u64, order) * bit_depth +
                10;
            var valid = true;
            for (order..block_frames) |frame| {
                const residual = fixedResidual(
                    samples,
                    first_frame,
                    channel_count,
                    channel,
                    frame,
                    order,
                );
                if (residual <= std.math.minInt(i32) or
                    residual > std.math.maxInt(i32))
                {
                    valid = false;
                    break;
                }
                const folded = foldResidual(residual);
                bits = std.math.add(
                    u64,
                    bits,
                    (folded >> parameter) + 1 + parameter,
                ) catch {
                    valid = false;
                    break;
                };
            }
            if (valid and (best == null or bits < best.?.bit_count)) {
                best = .{
                    .order = order,
                    .rice_parameter = parameter,
                    .bit_count = bits,
                };
            }
        }
    }
    return best;
}

fn fixedResidual(
    samples: []const i32,
    first_frame: usize,
    channel_count: usize,
    channel: usize,
    frame: usize,
    order: u3,
) i64 {
    const current = @as(i64, samples[
        (first_frame + frame) * channel_count + channel
    ]);
    return current - fixedPredictionFromSource(
        samples,
        first_frame,
        channel_count,
        channel,
        frame,
        order,
    );
}

fn fixedPredictionFromSource(
    samples: []const i32,
    first_frame: usize,
    channel_count: usize,
    channel: usize,
    frame: usize,
    order: u3,
) i64 {
    const a1 = if (order >= 1)
        @as(i64, samples[
            (first_frame + frame - 1) * channel_count + channel
        ])
    else
        0;
    const a2 = if (order >= 2)
        @as(i64, samples[
            (first_frame + frame - 2) * channel_count + channel
        ])
    else
        0;
    const a3 = if (order >= 3)
        @as(i64, samples[
            (first_frame + frame - 3) * channel_count + channel
        ])
    else
        0;
    const a4 = if (order >= 4)
        @as(i64, samples[
            (first_frame + frame - 4) * channel_count + channel
        ])
    else
        0;
    return switch (order) {
        0 => 0,
        1 => a1,
        2 => 2 * a1 - a2,
        3 => 3 * a1 - 3 * a2 + a3,
        4 => 4 * a1 - 6 * a2 + 4 * a3 - a4,
        else => unreachable,
    };
}

fn foldResidual(residual: i64) u64 {
    return if (residual >= 0)
        @intCast(residual * 2)
    else
        @intCast(-residual * 2 - 1);
}

fn decodeSubframe(
    comptime Sample: type,
    reader: *BitReader,
    destination: []Sample,
    block_size: usize,
    channel_count: usize,
    channel: usize,
    frame_bit_depth: u6,
) !void {
    if (try reader.readUnsigned(1) != 0)
        return error.InvalidFlacSubframe;
    const subframe_type: u6 = @intCast(try reader.readUnsigned(6));
    const wasted_flag = try reader.readUnsigned(1);
    var wasted_bits: u6 = 0;
    if (wasted_flag != 0) {
        const encoded_wasted = try reader.readUnary();
        if (encoded_wasted >= frame_bit_depth)
            return error.InvalidFlacWastedBits;
        wasted_bits = @intCast(encoded_wasted + 1);
    }
    const bit_depth = frame_bit_depth - wasted_bits;
    if (subframe_type == 0) {
        const sample = try readDecodedSample(Sample, reader, bit_depth);
        for (0..block_size) |frame|
            destination[frame * channel_count + channel] = sample;
    } else if (subframe_type == 1) {
        for (0..block_size) |frame|
            destination[frame * channel_count + channel] =
                try readDecodedSample(Sample, reader, bit_depth);
    } else if (subframe_type >= 8 and subframe_type <= 12) {
        const order: u6 = subframe_type - 8;
        if (order >= block_size) return error.InvalidFlacPredictorOrder;
        for (0..order) |frame|
            destination[frame * channel_count + channel] =
                try readDecodedSample(Sample, reader, bit_depth);
        try decodeResidual(
            Sample,
            reader,
            destination,
            block_size,
            channel_count,
            channel,
            order,
        );
        for (order..block_size) |frame| {
            const prediction = fixedPredictionFromDecoded(
                Sample,
                destination,
                channel_count,
                channel,
                frame,
                @intCast(order),
            );
            const reconstructed =
                @as(i128, destination[frame * channel_count + channel]) +
                prediction;
            if (reconstructed < std.math.minInt(Sample) or
                reconstructed > std.math.maxInt(Sample))
                return error.FlacSampleOverflow;
            destination[frame * channel_count + channel] =
                @intCast(reconstructed);
        }
    } else if (subframe_type >= 32) {
        const order: u6 = subframe_type - 31;
        if (order >= block_size) return error.InvalidFlacPredictorOrder;
        for (0..order) |frame|
            destination[frame * channel_count + channel] =
                try readDecodedSample(Sample, reader, bit_depth);
        const precision_code = try reader.readUnsigned(4);
        if (precision_code == 15)
            return error.InvalidFlacPredictorPrecision;
        const precision: u6 = @intCast(precision_code + 1);
        const shift = try reader.readSigned(5);
        if (shift < 0) return error.InvalidFlacPredictorShift;
        var coefficients: [32]i32 = undefined;
        for (0..order) |index|
            coefficients[index] = try reader.readSigned(precision);
        try decodeResidual(
            Sample,
            reader,
            destination,
            block_size,
            channel_count,
            channel,
            order,
        );
        for (order..block_size) |frame| {
            var prediction: i128 = 0;
            for (0..order) |coefficient| {
                prediction +=
                    @as(i128, coefficients[coefficient]) *
                    destination[
                        (frame - coefficient - 1) * channel_count + channel
                    ];
            }
            prediction >>= @intCast(shift);
            const reconstructed =
                @as(i128, destination[frame * channel_count + channel]) +
                prediction;
            if (reconstructed < std.math.minInt(Sample) or
                reconstructed > std.math.maxInt(Sample))
                return error.FlacSampleOverflow;
            destination[frame * channel_count + channel] =
                @intCast(reconstructed);
        }
    } else {
        return error.UnsupportedFlacSubframe;
    }
    if (wasted_bits != 0) {
        for (0..block_size) |frame| {
            const index = frame * channel_count + channel;
            const shifted =
                @as(i128, destination[index]) << wasted_bits;
            if (shifted < std.math.minInt(Sample) or
                shifted > std.math.maxInt(Sample))
                return error.FlacSampleOverflow;
            destination[index] = @intCast(shifted);
        }
    }
}

fn readDecodedSample(
    comptime Sample: type,
    reader: *BitReader,
    bit_depth: u6,
) !Sample {
    const value = try reader.readSignedWide(bit_depth);
    if (value < std.math.minInt(Sample) or
        value > std.math.maxInt(Sample))
        return error.FlacSampleOverflow;
    return @intCast(value);
}

fn restoreStereoChannels(
    samples: []i32,
    block_size: usize,
    channel_code: u8,
) !void {
    if (channel_code < 8) return;
    for (0..block_size) |frame| {
        const index = frame * 2;
        const first = @as(i64, samples[index]);
        const second = @as(i64, samples[index + 1]);
        const restored: struct { i64, i64 } = switch (channel_code) {
            8 => .{ first, first - second },
            9 => .{ first + second, second },
            10 => blk: {
                const expanded_mid =
                    (first << 1) | @as(i64, @intCast(second & 1));
                break :blk .{
                    (expanded_mid + second) >> 1,
                    (expanded_mid - second) >> 1,
                };
            },
            else => return error.UnsupportedFlacChannelAssignment,
        };
        const left = restored[0];
        const right = restored[1];
        if (left < std.math.minInt(i32) or
            left > std.math.maxInt(i32) or
            right < std.math.minInt(i32) or
            right > std.math.maxInt(i32))
            return error.FlacSampleOverflow;
        samples[index] = @intCast(left);
        samples[index + 1] = @intCast(right);
    }
}

fn restoreStereoChannelsWide(
    samples: []i32,
    side_samples: []const i64,
    block_size: usize,
    channel_code: u8,
) !void {
    if (channel_code < 8 or channel_code > 10)
        return error.UnsupportedFlacChannelAssignment;
    for (0..block_size) |frame| {
        const index = frame * 2;
        const side = side_samples[frame];
        const first = @as(i64, samples[index]);
        const second = @as(i64, samples[index + 1]);
        const restored: struct { i64, i64 } = switch (channel_code) {
            8 => .{ first, first - side },
            9 => .{ side + second, second },
            10 => blk: {
                const expanded_mid =
                    (first << 1) | @as(i64, @intCast(side & 1));
                break :blk .{
                    (expanded_mid + side) >> 1,
                    (expanded_mid - side) >> 1,
                };
            },
            else => unreachable,
        };
        if (restored[0] < std.math.minInt(i32) or
            restored[0] > std.math.maxInt(i32) or
            restored[1] < std.math.minInt(i32) or
            restored[1] > std.math.maxInt(i32))
            return error.FlacSampleOverflow;
        samples[index] = @intCast(restored[0]);
        samples[index + 1] = @intCast(restored[1]);
    }
}

fn decodeResidual(
    comptime Sample: type,
    reader: *BitReader,
    destination: []Sample,
    block_size: usize,
    channel_count: usize,
    channel: usize,
    predictor_order: u6,
) !void {
    const method = try reader.readUnsigned(2);
    const parameter_bits: u6 = switch (method) {
        0 => 4,
        1 => 5,
        else => return error.UnsupportedFlacResidualCoding,
    };
    const partition_order: u4 =
        @intCast(try reader.readUnsigned(4));
    const partition_count = @as(usize, 1) << partition_order;
    if (block_size % partition_count != 0)
        return error.InvalidFlacResidualPartition;
    const partition_size = block_size / partition_count;
    if (partition_size <= predictor_order)
        return error.InvalidFlacResidualPartition;

    var frame: usize = predictor_order;
    for (0..partition_count) |partition| {
        const samples_in_partition =
            partition_size -
            if (partition == 0) predictor_order else 0;
        const parameter = try reader.readUnsigned(parameter_bits);
        const escape = (@as(u64, 1) << parameter_bits) - 1;
        if (parameter == escape) {
            const raw_bits: u6 =
                @intCast(try reader.readUnsigned(5));
            for (0..samples_in_partition) |_| {
                destination[frame * channel_count + channel] =
                    if (raw_bits == 0)
                        0
                    else
                        try readDecodedSample(Sample, reader, raw_bits);
                frame += 1;
            }
        } else {
            const rice_parameter: u6 = @intCast(parameter);
            for (0..samples_in_partition) |_| {
                const quotient = try reader.readUnary();
                if (quotient >
                    (@as(u64, std.math.maxInt(u32)) >> rice_parameter))
                    return error.FlacResidualOverflow;
                const remainder = try reader.readUnsigned(rice_parameter);
                const folded = (quotient << rice_parameter) | remainder;
                const residual: i64 = if (folded & 1 == 0)
                    @intCast(folded >> 1)
                else
                    -@as(i64, @intCast((folded >> 1) + 1));
                if (residual <= std.math.minInt(i32) or
                    residual > std.math.maxInt(i32) or
                    residual < std.math.minInt(Sample) or
                    residual > std.math.maxInt(Sample))
                    return error.FlacResidualOverflow;
                destination[frame * channel_count + channel] =
                    @intCast(residual);
                frame += 1;
            }
        }
    }
    if (frame != block_size)
        return error.InvalidFlacResidualPartition;
}

fn fixedPredictionFromDecoded(
    comptime Sample: type,
    samples: []const Sample,
    channel_count: usize,
    channel: usize,
    frame: usize,
    order: u3,
) i128 {
    const a1 =
        if (order >= 1)
            @as(i128, samples[(frame - 1) * channel_count + channel])
        else
            0;
    const a2 =
        if (order >= 2)
            @as(i128, samples[(frame - 2) * channel_count + channel])
        else
            0;
    const a3 =
        if (order >= 3)
            @as(i128, samples[(frame - 3) * channel_count + channel])
        else
            0;
    const a4 =
        if (order >= 4)
            @as(i128, samples[(frame - 4) * channel_count + channel])
        else
            0;
    return switch (order) {
        0 => 0,
        1 => a1,
        2 => 2 * a1 - a2,
        3 => 3 * a1 - 3 * a2 + a3,
        4 => 4 * a1 - 6 * a2 + 4 * a3 - a4,
        else => unreachable,
    };
}

fn writeStreaminfo(
    destination: *[34]u8,
    spec: Spec,
    frame_count: usize,
    minimum_frame_size: u32,
    maximum_frame_size: u32,
    md5: [16]u8,
) void {
    std.mem.writeInt(u16, destination[0..2], spec.block_size, .big);
    std.mem.writeInt(u16, destination[2..4], spec.block_size, .big);
    writeU24(destination[4..7], minimum_frame_size);
    writeU24(destination[7..10], maximum_frame_size);
    const stream_fields =
        (@as(u64, spec.sample_rate) << 44) |
        (@as(u64, spec.channel_count - 1) << 41) |
        (@as(u64, spec.encoding.bits() - 1) << 36) |
        @as(u64, @intCast(frame_count));
    std.mem.writeInt(u64, destination[10..18], stream_fields, .big);
    @memcpy(destination[18..34], &md5);
}

fn validateSpec(spec: Spec) !void {
    if (spec.sample_rate == 0 or spec.sample_rate > 1_048_575)
        return error.InvalidFlacSampleRate;
    if (spec.channel_count == 0 or spec.channel_count > 8)
        return error.InvalidFlacChannelCount;
    if (spec.block_size < 16)
        return error.InvalidFlacBlockSize;
    const encoding = @intFromEnum(spec.encoding);
    if (encoding != 8 and
        encoding != 16 and
        encoding != 24 and
        encoding != 32)
        return error.UnsupportedFlacBitDepth;
}

fn validateFrameCount(frame_count: usize, block_size: u16) !void {
    if (frame_count > 0xfffffffff)
        return error.FlacFrameCountOutOfRange;
    const encoded_frames =
        if (frame_count == 0)
            0
        else
            (frame_count - 1) / block_size + 1;
    if (encoded_frames > 0x80000000)
        return error.FlacFrameNumberOutOfRange;
}

fn validateSamples(samples: []const i32, encoding: Encoding) !void {
    if (encoding == .pcm_i32) return;
    const bits = encoding.bits();
    const minimum = -(@as(i64, 1) << (bits - 1));
    const maximum = (@as(i64, 1) << (bits - 1)) - 1;
    for (samples) |sample| {
        if (sample < minimum or sample > maximum)
            return error.FlacSampleOutOfRange;
    }
}

fn hashSamples(
    md5: *std.crypto.hash.Md5,
    samples: []const i32,
    encoding: Encoding,
) void {
    var bytes: [4]u8 = undefined;
    const sample_bytes = encoding.bytes();
    for (samples) |sample| {
        std.mem.writeInt(i32, &bytes, sample, .little);
        md5.update(bytes[0..sample_bytes]);
    }
}

fn depthCode(encoding: Encoding) u8 {
    return switch (encoding) {
        .pcm_i8 => 1,
        .pcm_i16 => 4,
        .pcm_i24 => 6,
        .pcm_i32 => 7,
    };
}

fn decodeDepth(code: u8, fallback: Encoding) !Encoding {
    return switch (code) {
        0 => fallback,
        1 => .pcm_i8,
        4 => .pcm_i16,
        6 => .pcm_i24,
        7 => .pcm_i32,
        else => error.UnsupportedFlacBitDepth,
    };
}

fn decodeBlockSize(
    encoded: []const u8,
    offset: *usize,
    code: u8,
) !usize {
    return switch (code) {
        1 => 192,
        2...5 => @as(usize, 144) << @intCast(code),
        6 => blk: {
            if (offset.* >= encoded.len) return error.TruncatedFlac;
            const size = @as(usize, encoded[offset.*]) + 1;
            offset.* += 1;
            break :blk size;
        },
        7 => blk: {
            if (encoded.len - offset.* < 2) return error.TruncatedFlac;
            const size = @as(usize, std.mem.readInt(
                u16,
                encoded[offset.*..][0..2],
                .big,
            )) + 1;
            offset.* += 2;
            break :blk size;
        },
        8...15 => @as(usize, 1) << @intCast(code),
        else => error.InvalidFlacBlockSize,
    };
}

fn decodeSampleRate(
    encoded: []const u8,
    offset: *usize,
    code: u8,
    fallback: u32,
) !u32 {
    return switch (code) {
        0 => fallback,
        1 => 88_200,
        2 => 176_400,
        3 => 192_000,
        4 => 8_000,
        5 => 16_000,
        6 => 22_050,
        7 => 24_000,
        8 => 32_000,
        9 => 44_100,
        10 => 48_000,
        11 => 96_000,
        12 => blk: {
            if (offset.* >= encoded.len) return error.TruncatedFlac;
            const rate = @as(u32, encoded[offset.*]) * 1000;
            offset.* += 1;
            break :blk rate;
        },
        13, 14 => blk: {
            if (encoded.len - offset.* < 2) return error.TruncatedFlac;
            var rate: u32 = std.mem.readInt(
                u16,
                encoded[offset.*..][0..2],
                .big,
            );
            offset.* += 2;
            if (code == 14) rate *= 10;
            break :blk rate;
        },
        else => error.InvalidFlacSampleRate,
    };
}

fn codedNumberBytes(value: u64) usize {
    if (value <= 0x7f) return 1;
    if (value <= 0x7ff) return 2;
    if (value <= 0xffff) return 3;
    if (value <= 0x1fffff) return 4;
    if (value <= 0x3ffffff) return 5;
    return 6;
}

fn encodeCodedNumber(destination: []u8, value: u64) !usize {
    if (value > 0x7fffffff) return error.FlacFrameNumberOutOfRange;
    const count = codedNumberBytes(value);
    if (destination.len < count) return error.FlacOutputTooSmall;
    if (count == 1) {
        destination[0] = @intCast(value);
        return 1;
    }
    var remaining = value;
    var index = count;
    while (index > 1) {
        index -= 1;
        destination[index] = 0x80 | @as(u8, @intCast(remaining & 0x3f));
        remaining >>= 6;
    }
    const prefix: u8 = @as(u8, 0xff) << @intCast(8 - count);
    const payload_bits: u3 = @intCast(7 - count);
    const payload_mask: u8 =
        if (payload_bits == 0) 0 else (@as(u8, 1) << payload_bits) - 1;
    destination[0] =
        prefix | (@as(u8, @intCast(remaining)) & payload_mask);
    return count;
}

fn decodeCodedNumber(encoded: []const u8, offset: *usize) !u64 {
    if (offset.* >= encoded.len) return error.TruncatedFlac;
    const first = encoded[offset.*];
    offset.* += 1;
    if (first & 0x80 == 0) return first;
    var count: usize = 0;
    var mask: u8 = 0x80;
    while (first & mask != 0) : (mask >>= 1) count += 1;
    if (count < 2 or count > 6) return error.InvalidFlacCodedNumber;
    var value: u64 = first & (mask - 1);
    for (1..count) |_| {
        if (offset.* >= encoded.len) return error.TruncatedFlac;
        const continuation = encoded[offset.*];
        offset.* += 1;
        if (continuation & 0xc0 != 0x80)
            return error.InvalidFlacCodedNumber;
        value = (value << 6) | (continuation & 0x3f);
    }
    if (codedNumberBytes(value) != count)
        return error.NonCanonicalFlacCodedNumber;
    return value;
}

const BitWriter = struct {
    bytes: []u8,
    bit_position: usize,

    fn writeUnsigned(self: *BitWriter, bit_count: u6, value: u64) !void {
        if (bit_count == 0) return;
        if (bit_count < 64 and value >= (@as(u64, 1) << bit_count))
            return error.FlacBitValueOutOfRange;
        if (bit_count > self.bytes.len * 8 -| self.bit_position)
            return error.FlacOutputTooSmall;
        var remaining = bit_count;
        while (remaining > 0) {
            remaining -= 1;
            const byte_index = self.bit_position / 8;
            const bit_index: u3 = @intCast(7 - self.bit_position % 8);
            if (self.bit_position % 8 == 0) self.bytes[byte_index] = 0;
            const bit: u8 = @intCast((value >> remaining) & 1);
            self.bytes[byte_index] |= bit << bit_index;
            self.bit_position += 1;
        }
    }

    fn writeSigned(self: *BitWriter, bit_count: u6, value: i32) !void {
        const raw: u32 = @bitCast(value);
        const mask: u32 =
            if (bit_count == 32)
                std.math.maxInt(u32)
            else
                (@as(u32, 1) << @intCast(bit_count)) - 1;
        try self.writeUnsigned(bit_count, raw & mask);
    }

    fn writeZeroes(self: *BitWriter, bit_count: u64) !void {
        if (bit_count > self.bytes.len * 8 -| self.bit_position)
            return error.FlacOutputTooSmall;
        var remaining = bit_count;
        while (remaining != 0) {
            const chunk: u6 = @intCast(@min(remaining, 63));
            try self.writeUnsigned(chunk, 0);
            remaining -= chunk;
        }
    }

    fn padZero(self: *BitWriter) !void {
        const remainder = self.bit_position % 8;
        if (remainder != 0)
            try self.writeUnsigned(@intCast(8 - remainder), 0);
    }

    fn byteOffset(self: *const BitWriter) !usize {
        if (self.bit_position % 8 != 0)
            return error.UnalignedFlacBitstream;
        return self.bit_position / 8;
    }
};

const BitReader = struct {
    bytes: []const u8,
    bit_position: usize,

    fn readUnsigned(self: *BitReader, bit_count: u6) !u64 {
        if (bit_count > self.bytes.len * 8 -| self.bit_position)
            return error.TruncatedFlac;
        var value: u64 = 0;
        for (0..bit_count) |_| {
            const byte_index = self.bit_position / 8;
            const bit_index: u3 = @intCast(7 - self.bit_position % 8);
            value = (value << 1) |
                ((self.bytes[byte_index] >> bit_index) & 1);
            self.bit_position += 1;
        }
        return value;
    }

    fn readSigned(self: *BitReader, bit_count: u6) !i32 {
        const value = try self.readSignedWide(bit_count);
        if (value < std.math.minInt(i32) or
            value > std.math.maxInt(i32))
            return error.FlacSampleOverflow;
        return @intCast(value);
    }

    fn readSignedWide(self: *BitReader, bit_count: u6) !i64 {
        if (bit_count == 0) return error.InvalidFlacBitDepth;
        const raw = try self.readUnsigned(bit_count);
        if (bit_count == 64)
            return @bitCast(raw);
        const sign = @as(u64, 1) << (bit_count - 1);
        const extended = if (raw & sign == 0)
            raw
        else
            raw | (~@as(u64, 0) << bit_count);
        return @bitCast(extended);
    }

    fn readUnary(self: *BitReader) !u64 {
        var zero_count: u64 = 0;
        while (try self.readUnsigned(1) == 0) {
            if (zero_count == std.math.maxInt(u32))
                return error.FlacUnaryCodeTooLong;
            zero_count += 1;
        }
        return zero_count;
    }

    fn alignZero(self: *BitReader) !void {
        const remainder = self.bit_position % 8;
        if (remainder == 0) return;
        const padding = try self.readUnsigned(@intCast(8 - remainder));
        if (padding != 0) return error.InvalidFlacPadding;
    }

    fn byteOffset(self: *const BitReader) !usize {
        if (self.bit_position % 8 != 0)
            return error.UnalignedFlacBitstream;
        return self.bit_position / 8;
    }
};

fn writeU24(destination: *[3]u8, value: u32) void {
    destination[0] = @intCast((value >> 16) & 0xff);
    destination[1] = @intCast((value >> 8) & 0xff);
    destination[2] = @intCast(value & 0xff);
}

fn readU24(source: *const [3]u8) u32 {
    return (@as(u32, source[0]) << 16) |
        (@as(u32, source[1]) << 8) |
        source[2];
}

fn crc8(bytes: []const u8) u8 {
    var crc: u8 = 0;
    for (bytes) |byte| {
        crc ^= byte;
        for (0..8) |_| {
            crc = if (crc & 0x80 != 0)
                (crc << 1) ^ 0x07
            else
                crc << 1;
        }
    }
    return crc;
}

fn crc16(bytes: []const u8) u16 {
    var crc: u16 = 0;
    for (bytes) |byte| {
        crc ^= @as(u16, byte) << 8;
        for (0..8) |_| {
            crc = if (crc & 0x8000 != 0)
                (crc << 1) ^ 0x8005
            else
                crc << 1;
        }
    }
    return crc;
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}

test "verbatim FLAC round trips supported PCM widths and frame boundaries" {
    const source = [_]i32{
        -120, 110,  -90, 80,   -60, 50,  -30, 20,
        -10,  0,    10,  -20,  30,  -40, 60,  -70,
        90,   -100, 120, -110, 100, -80, 70,  -50,
        40,   -20,  10,  0,    -10, 20,  -30, 40,
        -50,  60,   -70, 80,
    };
    inline for ([_]Encoding{ .pcm_i8, .pcm_i16, .pcm_i24, .pcm_i32 }) |encoding| {
        const spec = Spec{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = encoding,
            .block_size = 16,
        };
        var encoded: [4096]u8 = undefined;
        const flac = try encodeInterleaved(&encoded, &source, spec);
        try std.testing.expectEqualStrings("fLaC", flac[0..4]);
        var decoded: [source.len]i32 = undefined;
        const result = try decodeInterleaved(flac, &decoded);
        try std.testing.expectEqual(source.len / 2, result.frames_decoded);
        try std.testing.expectEqualSlices(i32, &source, &decoded);
        try std.testing.expectEqual(encoding, result.info.encoding);
    }
}

test "FLAC codec rejects truncated and corrupt frames" {
    const source = [_]i32{0} ** 32;
    const spec = Spec{
        .sample_rate = 44_100,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [1024]u8 = undefined;
    const flac = try encodeInterleaved(&encoded, &source, spec);
    var decoded: [source.len]i32 = undefined;
    try std.testing.expectError(
        error.TruncatedFlac,
        decodeInterleaved(flac[0 .. flac.len - 1], &decoded),
    );
    encoded[flac.len - 3] ^= 1;
    try std.testing.expectError(
        error.FlacFrameCrcMismatch,
        decodeInterleaved(flac, &decoded),
    );
}

test "FLAC codec validates caller contracts" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i8,
        .block_size = 16,
    };
    var encoded: [128]u8 = undefined;
    try std.testing.expectError(
        error.IncompleteSourceFrame,
        encodeInterleaved(&encoded, &.{ 1, 2, 3 }, spec),
    );
    try std.testing.expectError(
        error.FlacSampleOutOfRange,
        encodeInterleaved(&encoded, &.{ 128, 0 }, spec),
    );
    var invalid_spec = spec;
    invalid_spec.channel_count = 0;
    try std.testing.expectError(
        error.InvalidFlacChannelCount,
        encodeInterleavedWithComments(
            &encoded,
            &.{},
            invalid_spec,
            .{},
        ),
    );
    try std.testing.expectError(
        error.InvalidFlacChannelCount,
        encodeInterleavedWithMetadata(
            &encoded,
            &.{},
            invalid_spec,
            .{},
        ),
    );

    var encoding_alias: [1024]u8 align(@alignOf(i32)) = @splat(0);
    const aliased_source = std.mem.bytesAsSlice(
        i32,
        encoding_alias[0 .. 32 * @sizeOf(i32)],
    );
    const encoding_alias_before = encoding_alias;
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        encodeInterleaved(
            &encoding_alias,
            aliased_source,
            spec,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &encoding_alias_before,
        &encoding_alias,
    );

    @memcpy(encoding_alias[0..6], "vendor");
    const comment_alias_before = encoding_alias;
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        encodeInterleavedWithMetadata(
            &encoding_alias,
            &([_]i32{0} ** 32),
            spec,
            .{
                .comments = .{
                    .vendor = encoding_alias[0..6],
                },
                .encoded_frames_per_seek_point = 1,
            },
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        &comment_alias_before,
        &encoding_alias,
    );

    const source = [_]i32{0} ** 32;
    var overlapping: [1024]u8 align(@alignOf(i32)) = undefined;
    const flac = try encodeInterleaved(&overlapping, &source, spec);
    const aliased_destination = std.mem.bytesAsSlice(
        i32,
        overlapping[0 .. source.len * @sizeOf(i32)],
    );
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        decodeInterleaved(flac, aliased_destination),
    );
    var frame_scratch: [32]i32 = undefined;
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        decodeInterleavedRange(
            flac,
            0,
            aliased_destination,
            &frame_scratch,
        ),
    );
}

test "FLAC fixed predictors and constant subframes reduce encoded size" {
    var ramp: [128]i32 = undefined;
    for (&ramp, 0..) |*sample, index| sample.* = @intCast(index * 7);
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 128,
    };
    var encoded: [1024]u8 = undefined;
    const compressed = try encodeInterleaved(&encoded, &ramp, spec);
    try std.testing.expect(compressed.len < streaminfo_bytes + ramp.len * 2);
    var decoded: [ramp.len]i32 = undefined;
    _ = try decodeInterleaved(compressed, &decoded);
    try std.testing.expectEqualSlices(i32, &ramp, &decoded);

    const silence = [_]i32{0} ** 128;
    const constant = try encodeInterleaved(&encoded, &silence, spec);
    try std.testing.expect(constant.len < compressed.len);
    _ = try decodeInterleaved(constant, &decoded);
    try std.testing.expectEqualSlices(i32, &silence, &decoded);
}

test "bounded file-backed FLAC round trip" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "round-trip.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    var source: [96]i32 = undefined;
    for (&source, 0..) |*sample, index| {
        const signed_index: i32 = @intCast(index);
        sample.* = if (index % 2 == 0)
            signed_index * 13
        else
            -signed_index * 9;
    }
    const spec = Spec{
        .sample_rate = 96_000,
        .channel_count = 2,
        .encoding = .pcm_i24,
        .block_size = 16,
    };
    var encoded: [4096]u8 = undefined;
    const byte_count = try writeInterleavedFileWithComments(
        std.testing.io,
        file,
        &encoded,
        &source,
        spec,
        .{ .fields = &.{
            .{ .name = "TITLE", .value = "File round trip" },
        } },
    );
    try std.testing.expectEqual(
        @as(u64, @intCast(byte_count)),
        try file.length(std.testing.io),
    );
    var file_storage: [4096]u8 = undefined;
    var decoded: [source.len]i32 = undefined;
    const result = try readInterleavedFile(
        std.testing.io,
        file,
        &file_storage,
        &decoded,
    );
    try std.testing.expectEqual(source.len / 2, result.frames_decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
    var comments =
        (try CommentIterator.init(file_storage[0..byte_count])).?;
    const title = (try comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", title.name);
    try std.testing.expectEqualStrings("File round trip", title.value);

    var range: [14]i32 = undefined;
    var scratch: [32]i32 = undefined;
    const range_frames = try readInterleavedFileRange(
        std.testing.io,
        file,
        &file_storage,
        5,
        &range,
        &scratch,
    );
    try std.testing.expectEqual(@as(usize, 7), range_frames);
    try std.testing.expectEqualSlices(
        i32,
        source[10..24],
        &range,
    );
}

test "incremental FLAC file writer round trips uneven appends" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "incremental.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 96_000,
        .channel_count = 2,
        .encoding = .pcm_i24,
        .block_size = 16,
    };
    var source: [74]i32 = undefined;
    for (&source, 0..) |*sample, index| {
        const value: i32 = @intCast(index * 101);
        sample.* = if (index % 3 == 0) -value else value;
    }
    var pending: [32]i32 = undefined;
    var frame_storage: [128]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
    );
    try writer.append(source[0..6]);
    try writer.append(source[6..40]);
    try writer.append(source[40..]);
    try std.testing.expectEqual(@as(u64, 32), writer.frames_written);
    try std.testing.expectEqual(@as(usize, 5), writer.pending_frames);
    try writer.finalize();
    try writer.finalize();
    try std.testing.expect(writer.finalized);
    try std.testing.expect(!writer.valid());
    try std.testing.expectEqual(@as(u64, 37), writer.frames_written);
    try std.testing.expectEqual(@as(usize, 0), writer.pending_frames);
    try std.testing.expectEqual(
        writer.byte_count,
        try file.length(std.testing.io),
    );
    try std.testing.expectError(
        error.InvalidFlacFileWriterState,
        writer.append(&.{ 1, 2 }),
    );

    var encoded: [4096]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    try std.testing.expectEqual(
        @as(usize, @intCast(writer.byte_count)),
        byte_count,
    );
    var decoded: [source.len]i32 = undefined;
    const result = try decodeInterleaved(
        encoded[0..byte_count],
        &decoded,
    );
    try std.testing.expectEqual(@as(usize, 37), result.frames_decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "incremental FLAC file writer validates before mutation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "transactional.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 44_100,
        .channel_count = 2,
        .encoding = .pcm_i8,
        .block_size = 16,
    };
    var pending: [32]i32 = undefined;
    var frame_storage: [96]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
    );
    var original_header: [streaminfo_bytes]u8 = undefined;
    _ = try file.readPositionalAll(
        std.testing.io,
        &original_header,
        0,
    );
    try std.testing.expectError(
        error.IncompleteSourceFrame,
        writer.append(&.{ 1, 2, 3 }),
    );
    try std.testing.expectError(
        error.FlacSampleOutOfRange,
        writer.append(&.{ 128, 0 }),
    );
    const aliased_source = writer.pending_samples[0..2];
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        writer.append(aliased_source),
    );
    try std.testing.expectEqual(@as(usize, 0), writer.pending_frames);
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);
    try std.testing.expectEqual(
        @as(u64, streaminfo_bytes),
        try file.length(std.testing.io),
    );
    var current_header: [streaminfo_bytes]u8 = undefined;
    _ = try file.readPositionalAll(
        std.testing.io,
        &current_header,
        0,
    );
    try std.testing.expectEqualSlices(
        u8,
        &original_header,
        &current_header,
    );

    var overflowing = writer;
    overflowing.byte_count = std.math.maxInt(u64);
    try std.testing.expectError(
        error.FlacSizeOverflow,
        overflowing.append(&([_]i32{0} ** 32)),
    );
    try std.testing.expectEqual(@as(usize, 0), overflowing.pending_frames);
    try std.testing.expectEqual(@as(u64, 0), overflowing.frames_written);
    try std.testing.expectEqual(
        @as(u64, streaminfo_bytes),
        try file.length(std.testing.io),
    );

    var overlapping_storage: [128]u8 align(@alignOf(i32)) = undefined;
    const overlapping_pending = std.mem.bytesAsSlice(
        i32,
        overlapping_storage[0..128],
    );
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        FileWriter.init(
            std.testing.io,
            file,
            spec,
            overlapping_pending,
            overlapping_storage[0..96],
        ),
    );
    @memcpy(overlapping_storage[0..6], "vendor");
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        FileWriter.initWithComments(
            std.testing.io,
            file,
            spec,
            &pending,
            &frame_storage,
            &overlapping_storage,
            .{ .vendor = overlapping_storage[0..6] },
        ),
    );
    try std.testing.expectEqual(
        @as(u64, streaminfo_bytes),
        try file.length(std.testing.io),
    );

    writer.has_metadata = true;
    try std.testing.expect(!writer.recoverable());
    writer.has_metadata = false;
    writer.pending_frames = 1;
    writer.failed = true;
    try std.testing.expect(!writer.recoverable());
    try std.testing.expectError(
        error.InvalidFlacFileWriterState,
        writer.recover(),
    );
}

const FileWriterFaults = struct {
    delegate: file_writer_io.Operations = .{},
    write_calls: usize = 0,
    set_length_calls: usize = 0,
    fail_write_call: ?usize = null,
    fail_set_length_call: ?usize = null,
    partial_write_bytes: usize = 0,

    fn operations(self: *@This()) file_writer_io.Operations {
        return .{
            .context = self,
            .vtable = &vtable,
        };
    }

    fn clear(self: *@This()) void {
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
            context orelse return error.MissingFlacFaultContext,
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
            return error.InjectedFlacWriteFailure;
        }
        try self.delegate.writeAt(io, file, offset, bytes);
        return bytes.len;
    }

    fn setLength(
        context: ?*anyopaque,
        io: std.Io,
        file: std.Io.File,
        length: u64,
    ) !void {
        const self: *@This() = @ptrCast(@alignCast(
            context orelse return error.MissingFlacFaultContext,
        ));
        self.set_length_calls += 1;
        if (self.fail_set_length_call == self.set_length_calls)
            return error.InjectedFlacTruncateFailure;
        try self.delegate.setLength(io, file, length);
    }

    const vtable = file_writer_io.Operations.VTable{
        .write_at = writeAt,
        .set_length = setLength,
    };
};

test "incremental FLAC file writer contains positional I/O failures" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "faults.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    const source = [_]i32{ 1, -2, 3, -4, 5, -6, 7, -8 } ** 3;
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var faults = FileWriterFaults{};
    var writer = try FileWriter.initWithOperations(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
        faults.operations(),
    );

    const initial_md5 = writer.md5;
    faults.fail_write_call = faults.write_calls + 1;
    faults.partial_write_bytes = 1;
    try std.testing.expectError(
        error.InjectedFlacWriteFailure,
        writer.append(source[0..16]),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    try std.testing.expectEqual(@as(usize, 16), writer.pending_frames);
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);
    try std.testing.expectEqual(streaminfo_bytes, writer.byte_count);
    try std.testing.expectEqualDeep(initial_md5, writer.md5);

    faults.fail_set_length_call = faults.set_length_calls + 1;
    try std.testing.expectError(
        error.InjectedFlacTruncateFailure,
        writer.recover(),
    );
    try std.testing.expectEqual(@as(usize, 16), writer.pending_frames);
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);

    faults.clear();
    try writer.recover();
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(usize, 0), writer.pending_frames);
    try std.testing.expectEqual(@as(u64, 16), writer.frames_written);

    try writer.append(source[16..]);
    faults.fail_write_call = faults.write_calls + 2;
    try std.testing.expectError(
        error.InjectedFlacWriteFailure,
        writer.finalize(),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    try std.testing.expectEqual(@as(u64, source.len), writer.frames_written);

    faults.clear();
    try writer.recover();
    try writer.finalize();
    var encoded: [256]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    var decoded: [source.len]i32 = undefined;
    _ = try decodeInterleaved(encoded[0..byte_count], &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "incremental FLAC recovery repairs a partial seek point" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek-fault.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    const source = [_]i32{ 1, -2, 3, -4, 5, -6, 7, -8 } ** 2;
    const metadata = FileWriterMetadata{
        .seek_interval = 1,
        .seek_point_capacity = 1,
    };
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var metadata_storage: [22]u8 = undefined;
    var faults = FileWriterFaults{};
    var writer = try FileWriter.initInternal(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
        &metadata_storage,
        metadata,
        faults.operations(),
    );
    const committed_bytes = writer.byte_count;

    faults.fail_write_call = faults.write_calls + 2;
    faults.partial_write_bytes = 3;
    try std.testing.expectError(
        error.InjectedFlacWriteFailure,
        writer.append(&source),
    );
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    try std.testing.expectEqual(@as(usize, 16), writer.pending_frames);
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);
    try std.testing.expectEqual(@as(u32, 0), writer.seek_points_written);
    try std.testing.expectEqual(committed_bytes, writer.byte_count);

    faults.clear();
    try writer.recover();
    try writer.finalize();
    try std.testing.expectEqual(@as(u64, source.len), writer.frames_written);
    try std.testing.expectEqual(@as(u32, 1), writer.seek_points_written);

    var encoded: [256]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    var points = (try SeekTableIterator.init(
        encoded[0..byte_count],
    )).?;
    const point = points.next().?;
    try std.testing.expectEqual(@as(u64, 0), point.sample_number);
    try std.testing.expectEqual(@as(u64, 0), point.byte_offset);
    try std.testing.expectEqual(@as(u16, 16), point.frame_samples);
    try std.testing.expect(points.next() == null);
    var decoded: [source.len]i32 = undefined;
    _ = try decodeInterleaved(encoded[0..byte_count], &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "incremental FLAC file writer recovers the last committed boundary" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "recover.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    const source = [_]i32{ 1, -2, 3, -4, 5, -6, 7, -8 } ** 5;
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
    );
    try writer.append(source[0..16]);
    try std.testing.expectEqual(@as(u64, 16), writer.frames_written);
    @memcpy(writer.pending_samples, source[16..32]);
    writer.pending_frames = 16;
    const committed_bytes = writer.byte_count;
    try file.writePositionalAll(
        std.testing.io,
        "uncommitted",
        committed_bytes,
    );
    writer.failed = true;
    try std.testing.expect(!writer.valid());
    try std.testing.expect(writer.recoverable());
    try writer.recover();
    try std.testing.expect(writer.valid());
    try std.testing.expectEqual(@as(u64, 32), writer.frames_written);
    try std.testing.expect(writer.byte_count > committed_bytes);
    try writer.append(source[32..]);
    try writer.finalize();

    var encoded: [512]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    var decoded: [source.len]i32 = undefined;
    _ = try decodeInterleaved(encoded[0..byte_count], &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "incremental FLAC file writer checks buffer sizes and empty files" {
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    try std.testing.expectEqual(
        @as(usize, 32),
        try requiredPendingSamples(spec),
    );
    try std.testing.expectEqual(
        @as(usize, 81),
        try requiredFrameStorageBytes(spec),
    );

    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "empty.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    var short_pending: [31]i32 = undefined;
    var pending: [32]i32 = undefined;
    var short_frame: [80]u8 = undefined;
    var frame_storage: [81]u8 = undefined;
    try std.testing.expectError(
        error.FlacPendingBufferTooSmall,
        FileWriter.init(
            std.testing.io,
            file,
            spec,
            &short_pending,
            &frame_storage,
        ),
    );
    try std.testing.expectError(
        error.FlacFrameBufferTooSmall,
        FileWriter.init(
            std.testing.io,
            file,
            spec,
            &pending,
            &short_frame,
        ),
    );
    var writer = try FileWriter.init(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
    );
    try writer.append(&.{});
    try writer.finalize();
    var encoded: [streaminfo_bytes]u8 = undefined;
    _ = try file.readPositionalAll(std.testing.io, &encoded, 0);
    var decoded: [0]i32 = .{};
    const result = try decodeInterleaved(&encoded, &decoded);
    try std.testing.expectEqual(@as(usize, 0), result.frames_decoded);
}

test "incremental FLAC file writer preserves Vorbis comments" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "comments.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    const comments = Comments{
        .vendor = "incremental test",
        .fields = &.{
            .{ .name = "TITLE", .value = "Chunked output" },
        },
    };
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var metadata_storage: [128]u8 = undefined;
    const metadata_bytes = try requiredCommentMetadataBytes(comments);
    try std.testing.expectError(
        error.FlacMetadataBufferTooSmall,
        FileWriter.initWithComments(
            std.testing.io,
            file,
            spec,
            &pending,
            &frame_storage,
            metadata_storage[0 .. metadata_bytes - 1],
            comments,
        ),
    );
    var writer = try FileWriter.initWithComments(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
        &metadata_storage,
        comments,
    );
    const source = [_]i32{ 11, -22, 33, -44, 55, -66, 77, -88 } ** 3;
    try writer.append(source[0..5]);
    try writer.append(source[5..]);
    try writer.finalize();

    var encoded: [512]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    var iterator =
        (try CommentIterator.init(encoded[0..byte_count])).?;
    try std.testing.expectEqualStrings(comments.vendor, iterator.vendor);
    const title = (try iterator.next()).?;
    try std.testing.expectEqualStrings("TITLE", title.name);
    try std.testing.expectEqualStrings("Chunked output", title.value);
    var decoded: [source.len]i32 = undefined;
    _ = try decodeInterleaved(encoded[0..byte_count], &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "incremental FLAC writer composes bounded seek metadata" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek-writer.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    const metadata = FileWriterMetadata{
        .comments = .{ .fields = &.{
            .{ .name = "TITLE", .value = "Incremental seek" },
        } },
        .seek_interval = 2,
        .seek_point_capacity = 6,
    };
    var pending: [32]i32 = undefined;
    var frame_storage: [96]u8 = undefined;
    var metadata_storage: [256]u8 = undefined;
    try std.testing.expect(
        try requiredFileWriterMetadataBytes(metadata) <=
            metadata_storage.len,
    );
    var writer = try FileWriter.initWithMetadata(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
        &metadata_storage,
        metadata,
    );
    var source: [200]i32 = undefined;
    for (&source, 0..) |*sample, index|
        sample.* = @as(i32, @intCast(index)) * 17 - 900;
    try writer.append(source[0..70]);
    try writer.append(source[70..]);
    try writer.finalize();
    try std.testing.expectEqual(@as(u32, 4), writer.seek_points_written);

    var retained_metadata: [256]u8 = undefined;
    const retained_metadata_bytes =
        (try requiredCommentMetadataBytes(metadata.comments.?) - 4) +
        @as(usize, metadata.seek_point_capacity) * 18;
    try std.testing.expectEqual(
        retained_metadata_bytes,
        try FileReader.requiredMetadataBytes(
            std.testing.io,
            file,
        ),
    );
    try std.testing.expectError(
        error.FlacMetadataBufferTooSmall,
        FileReader.init(
            std.testing.io,
            file,
            retained_metadata[0 .. retained_metadata_bytes - 1],
        ),
    );
    const reader = try FileReader.init(
        std.testing.io,
        file,
        retained_metadata[0..retained_metadata_bytes],
    );
    var comments = (try reader.commentIterator()).?;
    try std.testing.expectEqualStrings("zig-vst3", comments.vendor);
    const title = (try comments.next()).?;
    try std.testing.expectEqualStrings("TITLE", title.name);
    try std.testing.expectEqualStrings("Incremental seek", title.value);
    try std.testing.expect((try comments.next()) == null);

    var iterator = reader.seekTableIterator().?;
    const expected_samples = [_]u64{ 0, 32, 64, 96 };
    for (expected_samples) |expected|
        try std.testing.expectEqual(expected, iterator.next().?.sample_number);
    try std.testing.expect(iterator.next().?.placeholder());
    try std.testing.expect(iterator.next().?.placeholder());
    try std.testing.expect(iterator.next() == null);

    var encoded_frame: [128]u8 = undefined;
    var decoded_frame: [32]i32 = undefined;
    var range: [20]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 10),
        try reader.decodeRange(
            45,
            &range,
            &encoded_frame,
            &decoded_frame,
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(i32, source[90..110], &range);

    var encoded: [1024]u8 = undefined;
    const byte_count = try file.readPositionalAll(
        std.testing.io,
        encoded[0..@intCast(writer.byte_count)],
        0,
    );
    const comment_block_bytes =
        try requiredCommentMetadataBytes(metadata.comments.?);
    const seek_block_bytes =
        4 + @as(usize, metadata.seek_point_capacity) * 18;
    const metadata_end =
        streaminfo_bytes + comment_block_bytes + seek_block_bytes;
    try std.testing.expectEqual(
        @as(u8, 4),
        encoded[streaminfo_bytes] & 0x7f,
    );
    try std.testing.expectEqual(
        @as(u8, 3),
        encoded[streaminfo_bytes + comment_block_bytes] & 0x7f,
    );

    var reordered: [1024]u8 = undefined;
    @memcpy(
        reordered[0..streaminfo_bytes],
        encoded[0..streaminfo_bytes],
    );
    @memcpy(
        reordered[streaminfo_bytes..][0..seek_block_bytes],
        encoded[streaminfo_bytes + comment_block_bytes ..][0..seek_block_bytes],
    );
    reordered[streaminfo_bytes] &= 0x7f;
    @memcpy(
        reordered[streaminfo_bytes + seek_block_bytes ..][0..comment_block_bytes],
        encoded[streaminfo_bytes..][0..comment_block_bytes],
    );
    reordered[streaminfo_bytes + seek_block_bytes] |= 0x80;
    @memcpy(
        reordered[metadata_end..byte_count],
        encoded[metadata_end..byte_count],
    );
    try file.writePositionalAll(
        std.testing.io,
        reordered[0..byte_count],
        0,
    );
    try std.testing.expectEqual(
        retained_metadata_bytes,
        try requiredFileReaderMetadataBytes(
            std.testing.io,
            file,
        ),
    );

    var reordered_metadata: [256]u8 = undefined;
    const reordered_reader = try FileReader.init(
        std.testing.io,
        file,
        reordered_metadata[0..retained_metadata_bytes],
    );
    var reordered_comments =
        (try reordered_reader.commentIterator()).?;
    try std.testing.expectEqualStrings(
        "Incremental seek",
        (try reordered_comments.next()).?.value,
    );
    var reordered_seek = reordered_reader.seekTableIterator().?;
    try std.testing.expectEqual(
        @as(u64, 0),
        reordered_seek.next().?.sample_number,
    );

    var malformed = reordered;
    malformed[streaminfo_bytes] = 4;
    try file.writePositionalAll(
        std.testing.io,
        malformed[0..byte_count],
        0,
    );
    try std.testing.expectError(
        error.DuplicateFlacVorbisComments,
        FileReader.requiredMetadataBytes(
            std.testing.io,
            file,
        ),
    );

    malformed = reordered;
    malformed[streaminfo_bytes + 1] = 0xff;
    malformed[streaminfo_bytes + 2] = 0xff;
    malformed[streaminfo_bytes + 3] = 0xff;
    try file.writePositionalAll(
        std.testing.io,
        malformed[0..byte_count],
        0,
    );
    try std.testing.expectError(
        error.TruncatedFlac,
        requiredFileReaderMetadataBytes(
            std.testing.io,
            file,
        ),
    );
}

test "incremental FLAC seek capacity fails before mutation" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "seek-capacity.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var pending: [16]i32 = undefined;
    var frame_storage: [64]u8 = undefined;
    var metadata_storage: [22]u8 = undefined;
    var writer = try FileWriter.initWithMetadata(
        std.testing.io,
        file,
        spec,
        &pending,
        &frame_storage,
        &metadata_storage,
        .{ .seek_interval = 1, .seek_point_capacity = 1 },
    );
    const initial_bytes = writer.byte_count;
    try std.testing.expectError(
        error.FlacSeekTableCapacityExceeded,
        writer.append(&([_]i32{1} ** 32)),
    );
    try std.testing.expectEqual(@as(u64, 0), writer.frames_written);
    try std.testing.expectEqual(@as(usize, 0), writer.pending_frames);
    try std.testing.expectEqual(initial_bytes, writer.byte_count);
    try std.testing.expectEqual(
        initial_bytes,
        try file.length(std.testing.io),
    );
}

test "streaming FLAC file reader decodes without whole-file storage" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var file = try temporary.dir.createFile(
        std.testing.io,
        "streaming-reader.flac",
        .{ .read = true },
    );
    defer file.close(std.testing.io);

    var source: [200]i32 = undefined;
    for (&source, 0..) |*sample, index| {
        const value: i32 = @intCast(index * 37);
        sample.* = if (index % 2 == 0) value else -value;
    }
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i24,
        .block_size = 16,
    };
    var encoded: [4096]u8 = undefined;
    _ = try writeInterleavedFileWithMetadata(
        std.testing.io,
        file,
        &encoded,
        &source,
        spec,
        .{
            .comments = .{ .fields = &.{
                .{ .name = "TITLE", .value = "Streaming read" },
            } },
            .encoded_frames_per_seek_point = 2,
        },
    );
    var metadata_storage: [512]u8 = undefined;
    const reader = try FileReader.init(
        std.testing.io,
        file,
        &metadata_storage,
    );
    try std.testing.expectEqual(@as(u64, 100), reader.info.frame_count);
    try std.testing.expect(reader.seek_table_payload.len != 0);
    var short_frame_storage: [8]u8 = undefined;
    var decoded: [source.len]i32 = undefined;
    try std.testing.expectError(
        error.FlacFrameBufferTooSmall,
        reader.decode(
            &decoded,
            &short_frame_storage,
            &.{},
        ),
    );
    var frame_storage: [256]u8 = undefined;
    const result = try reader.decode(
        &decoded,
        &frame_storage,
        &.{},
    );
    try std.testing.expectEqual(@as(usize, 100), result.frames_decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);

    var range: [30]i32 = undefined;
    var decoded_frame_scratch: [32]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 15),
        try reader.decodeRange(
            35,
            &range,
            &frame_storage,
            &decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        source[70..100],
        &range,
    );

    var preserved = [_]i32{ 7, 8 };
    var invalid_channels = reader;
    invalid_channels.info.channel_count = 0;
    try std.testing.expectError(
        error.InvalidFlacFileReaderState,
        invalid_channels.decodeRange(
            0,
            &preserved,
            &frame_storage,
            &decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        &[_]i32{ 7, 8 },
        &preserved,
    );

    var invalid_extent = reader;
    invalid_extent.audio_offset = std.math.maxInt(u64);
    invalid_extent.file_size = std.math.maxInt(u64) - 1;
    try std.testing.expectError(
        error.InvalidFlacFileReaderState,
        invalid_extent.decodeRange(
            0,
            &preserved,
            &frame_storage,
            &decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expectEqualSlices(
        i32,
        &[_]i32{ 7, 8 },
        &preserved,
    );

    var invalid_seek = reader;
    invalid_seek.seek_table_payload = metadata_storage[0..1];
    try std.testing.expectError(
        error.InvalidFlacFileReaderState,
        invalid_seek.decodeRange(
            0,
            &preserved,
            &frame_storage,
            &decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expect(invalid_seek.seekTableIterator() == null);

    var aliased_storage: [256]u8 align(@alignOf(i32)) = undefined;
    const aliased_destination = std.mem.bytesAsSlice(
        i32,
        aliased_storage[0..40],
    );
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        reader.decodeRange(
            0,
            aliased_destination,
            aliased_storage[0..128],
            &decoded_frame_scratch,
            &.{},
        ),
    );
    try std.testing.expectError(
        error.OverlappingFlacBuffers,
        readInterleavedFile(
            std.testing.io,
            file,
            &aliased_storage,
            aliased_destination,
        ),
    );

    var hostile_seek_iterator = SeekTableIterator{
        .payload = metadata_storage[0..1],
        .offset = 2,
    };
    try std.testing.expect(hostile_seek_iterator.next() == null);
    hostile_seek_iterator.offset = 0;
    try std.testing.expect(hostile_seek_iterator.next() == null);

    var hostile_comment_iterator = CommentIterator{
        .payload = metadata_storage[0..1],
        .offset = 2,
        .remaining = 1,
        .vendor = &.{},
    };
    try std.testing.expectError(
        error.InvalidFlacVorbisComments,
        hostile_comment_iterator.next(),
    );
}

test "FLAC Vorbis comments preserve UTF-8 fields" {
    const comments = Comments{
        .vendor = "zig-vst3 tests",
        .fields = &.{
            .{ .name = "TITLE", .value = "Night Signal" },
            .{ .name = "ARTIST", .value = "Zoë" },
            .{ .name = "TRACKNUMBER", .value = "7" },
        },
    };
    const source = [_]i32{ 12, -12, 24, -24, 36, -36, 48, -48 } ** 4;
    const spec = Spec{
        .sample_rate = 44_100,
        .channel_count = 2,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [2048]u8 = undefined;
    const flac_bytes = try encodeInterleavedWithComments(
        &encoded,
        &source,
        spec,
        comments,
    );
    var iterator = (try CommentIterator.init(flac_bytes)).?;
    try std.testing.expectEqualStrings(comments.vendor, iterator.vendor);
    for (comments.fields) |expected| {
        const actual = (try iterator.next()).?;
        try std.testing.expectEqualStrings(expected.name, actual.name);
        try std.testing.expectEqualStrings(expected.value, actual.value);
    }
    try std.testing.expect((try iterator.next()) == null);

    var decoded: [source.len]i32 = undefined;
    const parsed = try Parser.init(flac_bytes);
    try std.testing.expectEqual(@as(u8, 0xff), flac_bytes[parsed.offset]);
    try std.testing.expectEqual(@as(u8, 0xf8), flac_bytes[parsed.offset + 1]);
    _ = try decodeInterleaved(flac_bytes, &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "FLAC Vorbis comments reject invalid names and UTF-8" {
    const spec = Spec{
        .sample_rate = 44_100,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [256]u8 = undefined;
    try std.testing.expectError(
        error.InvalidFlacVorbisCommentField,
        encodeInterleavedWithComments(
            &encoded,
            &([_]i32{0} ** 16),
            spec,
            .{ .fields = &.{
                .{ .name = "BAD=NAME", .value = "value" },
            } },
        ),
    );
    try std.testing.expectError(
        error.InvalidFlacVorbisCommentUtf8,
        encodeInterleavedWithComments(
            &encoded,
            &([_]i32{0} ** 16),
            spec,
            .{ .fields = &.{
                .{ .name = "TITLE", .value = "\xff" },
            } },
        ),
    );
}

test "FLAC decoder handles LPC and Rice2 escaped residuals" {
    var encoded: [128]u8 = undefined;
    var writer = BitWriter{
        .bytes = &encoded,
        .bit_position = 0,
    };
    try writer.writeUnsigned(1, 0);
    try writer.writeUnsigned(6, 32);
    try writer.writeUnsigned(1, 0);
    try writer.writeSigned(16, 10);
    try writer.writeUnsigned(4, 3);
    try writer.writeSigned(5, 0);
    try writer.writeSigned(4, 1);
    try writer.writeUnsigned(2, 1);
    try writer.writeUnsigned(4, 0);
    try writer.writeUnsigned(5, 31);
    try writer.writeUnsigned(5, 8);
    try writer.writeSigned(8, 1);
    try writer.writeSigned(8, 1);
    try writer.writeSigned(8, 1);

    var reader = BitReader{
        .bytes = &encoded,
        .bit_position = 0,
    };
    var decoded: [4]i32 = undefined;
    try decodeSubframe(i32, &reader, &decoded, 4, 1, 0, 16);
    try std.testing.expectEqualSlices(
        i32,
        &.{ 10, 11, 12, 13 },
        &decoded,
    );
}

test "FLAC decoder restores wasted bits and stereo assignments" {
    var encoded: [16]u8 = undefined;
    var writer = BitWriter{
        .bytes = &encoded,
        .bit_position = 0,
    };
    try writer.writeUnsigned(1, 0);
    try writer.writeUnsigned(6, 0);
    try writer.writeUnsigned(1, 1);
    try writer.writeUnsigned(2, 1);
    try writer.writeSigned(14, 3);
    var reader = BitReader{
        .bytes = &encoded,
        .bit_position = 0,
    };
    var constant: [3]i32 = undefined;
    try decodeSubframe(i32, &reader, &constant, 3, 1, 0, 16);
    try std.testing.expectEqualSlices(i32, &.{ 12, 12, 12 }, &constant);

    var left_side = [_]i32{ 10, 3, -5, -2 };
    try restoreStereoChannels(&left_side, 2, 8);
    try std.testing.expectEqualSlices(
        i32,
        &.{ 10, 7, -5, -3 },
        &left_side,
    );
    var mid_side = [_]i32{ 8, 5, -8, -5 };
    try restoreStereoChannels(&mid_side, 2, 10);
    try std.testing.expectEqualSlices(
        i32,
        &.{ 11, 6, -10, -5 },
        &mid_side,
    );
}

test "FLAC wide scratch decodes 33-bit side channels" {
    var expected: [32]i32 = undefined;
    for (0..16) |frame| {
        expected[frame * 2] = std.math.maxInt(i32);
        expected[frame * 2 + 1] = std.math.minInt(i32);
    }
    var encoded: [128]u8 = @splat(0);
    @memcpy(encoded[0..4], "fLaC");
    encoded[4] = 0x80;
    encoded[7] = 34;
    var md5 = std.crypto.hash.Md5.init(.{});
    hashSamples(&md5, &expected, .pcm_i32);
    var digest: [16]u8 = undefined;
    md5.final(&digest);
    writeStreaminfo(
        encoded[8..42],
        .{
            .sample_rate = 48_000,
            .channel_count = 2,
            .encoding = .pcm_i32,
            .block_size = 16,
        },
        16,
        21,
        21,
        digest,
    );
    const frame_start = 42;
    encoded[frame_start] = 0xff;
    encoded[frame_start + 1] = 0xf8;
    encoded[frame_start + 2] = 0x70;
    encoded[frame_start + 3] = 0xae;
    encoded[frame_start + 4] = 0;
    std.mem.writeInt(
        u16,
        encoded[frame_start + 5 ..][0..2],
        15,
        .big,
    );
    encoded[frame_start + 7] =
        crc8(encoded[frame_start .. frame_start + 7]);
    var writer = BitWriter{
        .bytes = &encoded,
        .bit_position = (frame_start + 8) * 8,
    };
    try writer.writeUnsigned(8, 0);
    try writer.writeSigned(32, -1);
    try writer.writeUnsigned(8, 0);
    try writer.writeUnsigned(33, 0xffffffff);
    try writer.padZero();
    const footer_offset = try writer.byteOffset();
    try std.testing.expectEqual(@as(usize, 61), footer_offset);
    std.mem.writeInt(
        u16,
        encoded[footer_offset..][0..2],
        crc16(encoded[frame_start..footer_offset]),
        .big,
    );

    var decoded: [expected.len]i32 = undefined;
    try std.testing.expectError(
        error.FlacWideSideScratchTooSmall,
        decodeInterleaved(encoded[0 .. footer_offset + 2], &decoded),
    );
    var wide_scratch: [16]i64 = undefined;
    _ = try decodeInterleavedWithWideScratch(
        encoded[0 .. footer_offset + 2],
        &decoded,
        &wide_scratch,
    );
    try std.testing.expectEqualSlices(i32, &expected, &decoded);

    var range: [8]i32 = undefined;
    var frame_scratch: [32]i32 = undefined;
    try std.testing.expectEqual(
        @as(usize, 4),
        try decodeInterleavedRangeWithWideScratch(
            encoded[0 .. footer_offset + 2],
            4,
            &range,
            &frame_scratch,
            &wide_scratch,
        ),
    );
    try std.testing.expectEqualSlices(i32, expected[8..16], &range);
}

test "FLAC coded numbers and checksum vectors are canonical" {
    const values = [_]u64{
        0,
        0x7f,
        0x80,
        0x7ff,
        0x800,
        0xffff,
        0x10000,
        0x1fffff,
        0x200000,
        0x3ffffff,
        0x4000000,
        0x7fffffff,
    };
    for (values) |value| {
        var encoded: [7]u8 = undefined;
        const byte_count = try encodeCodedNumber(&encoded, value);
        var offset: usize = 0;
        try std.testing.expectEqual(
            value,
            try decodeCodedNumber(encoded[0..byte_count], &offset),
        );
        try std.testing.expectEqual(byte_count, offset);
    }
    try std.testing.expectEqual(@as(u8, 0xf4), crc8("123456789"));
    try std.testing.expectEqual(@as(u16, 0xfee8), crc16("123456789"));
}

test "FLAC round trip crosses the multibyte frame-number boundary" {
    const frame_count = 16 * 130;
    const source = [_]i32{17} ** frame_count;
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [8192]u8 = undefined;
    const flac_bytes = try encodeInterleaved(
        &encoded,
        &source,
        spec,
    );
    var decoded: [frame_count]i32 = undefined;
    const result = try decodeInterleaved(flac_bytes, &decoded);
    try std.testing.expectEqual(frame_count, result.frames_decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "FLAC deterministic matrix covers channels blocks and PCM widths" {
    const frame_count = 257;
    var source: [frame_count * 8]i32 = undefined;
    var decoded: [source.len]i32 = undefined;
    var encoded: [source.len * 5 + 4096]u8 = undefined;
    inline for ([_]Encoding{
        .pcm_i8,
        .pcm_i16,
        .pcm_i24,
        .pcm_i32,
    }) |encoding| {
        const amplitude: i64 = switch (encoding) {
            .pcm_i8 => 100,
            .pcm_i16 => 20_000,
            .pcm_i24 => 2_000_000,
            .pcm_i32 => 1_000_000_000,
        };
        inline for ([_]u8{ 1, 2, 6, 8 }) |channel_count| {
            inline for ([_]u16{ 16, 31, 192 }) |block_size| {
                const channels: usize = channel_count;
                const sample_count = frame_count * channels;
                for (source[0..sample_count], 0..) |*sample, index| {
                    const pattern = @mod(
                        @as(i64, @intCast(index)) * 97 +
                            @as(i64, @intCast(index / channels)) * 31,
                        amplitude * 2 + 1,
                    );
                    sample.* = @intCast(pattern - amplitude);
                }
                const spec = Spec{
                    .sample_rate = 192_000,
                    .channel_count = channel_count,
                    .encoding = encoding,
                    .block_size = block_size,
                };
                const flac_bytes = try encodeInterleaved(
                    &encoded,
                    source[0..sample_count],
                    spec,
                );
                const result = try decodeInterleaved(
                    flac_bytes,
                    decoded[0..sample_count],
                );
                try std.testing.expectEqual(
                    frame_count,
                    result.frames_decoded,
                );
                try std.testing.expectEqualSlices(
                    i32,
                    source[0..sample_count],
                    decoded[0..sample_count],
                );
            }
        }
    }
}

test "FLAC decoder accepts canonical variable-block sample numbers" {
    const source = [_]i32{17} ** 32;
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [256]u8 = undefined;
    const fixed = try encodeInterleaved(&encoded, &source, spec);
    try std.testing.expectEqual(@as(usize, 68), fixed.len);
    for ([_]usize{ 42, 55 }, 0..) |start, index| {
        encoded[start + 1] = 0xf9;
        encoded[start + 4] = @intCast(index * 16);
        encoded[start + 7] = crc8(encoded[start .. start + 7]);
        std.mem.writeInt(
            u16,
            encoded[start + 11 ..][0..2],
            crc16(encoded[start .. start + 11]),
            .big,
        );
    }
    var decoded: [source.len]i32 = undefined;
    const result = try decodeInterleaved(fixed, &decoded);
    try std.testing.expectEqual(@as(usize, 32), result.frames_decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);
}

test "FLAC seek tables index bounded encoded frames" {
    var source: [200]i32 = undefined;
    for (&source, 0..) |*sample, index|
        sample.* = @as(i32, @intCast(index)) * 19 - 1_000;
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 2,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [4096]u8 = undefined;
    const flac_bytes = try encodeInterleavedWithMetadata(
        &encoded,
        &source,
        spec,
        .{
            .comments = .{ .fields = &.{
                .{ .name = "TITLE", .value = "Seekable" },
            } },
            .encoded_frames_per_seek_point = 2,
        },
    );
    var comments = (try CommentIterator.init(flac_bytes)).?;
    const title = (try comments.next()).?;
    try std.testing.expectEqualStrings("Seekable", title.value);
    var iterator = (try SeekTableIterator.init(flac_bytes)).?;
    const expected_samples = [_]u64{ 0, 32, 64, 96 };
    var previous_offset: ?u64 = null;
    for (expected_samples, 0..) |expected_sample, index| {
        const point = iterator.next().?;
        try std.testing.expectEqual(expected_sample, point.sample_number);
        if (previous_offset) |previous|
            try std.testing.expect(point.byte_offset > previous);
        previous_offset = point.byte_offset;
        try std.testing.expectEqual(
            @as(u16, if (index == 3) 4 else 16),
            point.frame_samples,
        );
    }
    try std.testing.expect(iterator.next() == null);
    var decoded: [source.len]i32 = undefined;
    _ = try decodeInterleaved(flac_bytes, &decoded);
    try std.testing.expectEqualSlices(i32, &source, &decoded);

    var range: [50]i32 = undefined;
    var scratch: [32]i32 = undefined;
    const range_frames = try decodeInterleavedRange(
        flac_bytes,
        35,
        &range,
        &scratch,
    );
    try std.testing.expectEqual(@as(usize, 25), range_frames);
    try std.testing.expectEqualSlices(
        i32,
        source[35 * 2 .. 60 * 2],
        &range,
    );
}

test "FLAC seek tables reject unsorted and duplicate points" {
    var payload: [36]u8 = undefined;
    encodeSeekPoint(
        payload[0..18],
        .{
            .sample_number = 32,
            .byte_offset = 100,
            .frame_samples = 16,
        },
    );
    encodeSeekPoint(
        payload[18..36],
        .{
            .sample_number = 16,
            .byte_offset = 50,
            .frame_samples = 16,
        },
    );
    try std.testing.expectError(
        error.InvalidFlacSeekTable,
        validateSeekTablePayload(&payload),
    );
}

test "FLAC decoder rejects unknown sample totals in bounded mode" {
    const source = [_]i32{0} ** 16;
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [256]u8 = undefined;
    const flac_bytes = try encodeInterleaved(&encoded, &source, spec);
    var stream_fields = std.mem.readInt(
        u64,
        encoded[18..26],
        .big,
    );
    stream_fields &= ~@as(u64, 0xfffffffff);
    std.mem.writeInt(u64, encoded[18..26], stream_fields, .big);
    var decoded: [source.len]i32 = undefined;
    try std.testing.expectError(
        error.UnsupportedUnknownFlacFrameCount,
        decodeInterleaved(flac_bytes, &decoded),
    );
}

test "FLAC decoder validates Vorbis payloads even when tags are ignored" {
    const source = [_]i32{0} ** 16;
    const spec = Spec{
        .sample_rate = 48_000,
        .channel_count = 1,
        .encoding = .pcm_i16,
        .block_size = 16,
    };
    var encoded: [512]u8 = undefined;
    const flac_bytes = try encodeInterleavedWithComments(
        &encoded,
        &source,
        spec,
        .{ .fields = &.{
            .{ .name = "TITLE", .value = "Valid" },
        } },
    );
    const payload_offset = streaminfo_bytes + 4;
    const vendor_bytes = std.mem.readInt(
        u32,
        flac_bytes[payload_offset..][0..4],
        .little,
    );
    const field_count_offset = payload_offset + 4 + vendor_bytes;
    std.mem.writeInt(
        u32,
        encoded[field_count_offset..][0..4],
        2,
        .little,
    );
    var decoded: [source.len]i32 = undefined;
    try std.testing.expectError(
        error.InvalidFlacVorbisComments,
        decodeInterleaved(flac_bytes, &decoded),
    );
}
