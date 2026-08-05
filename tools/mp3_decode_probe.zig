const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2 and args.len != 4 and args.len != 5)
        return error.InvalidArguments;
    const requirement: Requirement = if (args.len != 5)
        .none
    else if (std.mem.eql(
        u8,
        args[4],
        "--require-tagged-multiple-seek-points",
    ))
        .tagged_multiple_seek_points
    else if (std.mem.eql(u8, args[4], "--require-id3v2.4"))
        .id3v2_4
    else if (std.mem.eql(u8, args[4], "--require-protected"))
        .protected
    else if (std.mem.eql(u8, args[4], "--require-free-format"))
        .free_format
    else if (std.mem.eql(u8, args[4], "--require-joint-stereo"))
        .joint_stereo
    else if (std.mem.eql(u8, args[4], "--require-vbri"))
        .vbri
    else if (std.mem.eql(u8, args[4], "--require-gapless"))
        .gapless
    else if (std.mem.eql(u8, args[4], "--require-junk-resync"))
        .junk_resync
    else if (std.mem.eql(
        u8,
        args[4],
        "--require-trailing-junk-rejection",
    ))
        .trailing_junk_rejection
    else
        return error.InvalidArguments;
    const require_multiple_seek_points =
        requirement == .tagged_multiple_seek_points;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    switch (requirement) {
        .none => {},
        .tagged_multiple_seek_points => {
            if (!hasId3v2Version(encoded, 3) or
                encoded.len < 128 or
                !std.mem.eql(u8, encoded[encoded.len - 128 ..][0..3], "TAG"))
            {
                return error.MissingExpectedMp3Tags;
            }
        },
        .id3v2_4 => {
            if (!hasId3v2Version(encoded, 4))
                return error.MissingExpectedMp3Tags;
        },
        .protected,
        .free_format,
        .joint_stereo,
        .vbri,
        .gapless,
        .junk_resync,
        .trailing_junk_rejection,
        => {},
    }
    if (requirement == .trailing_junk_rejection) {
        try verifyTrailingJunkRejection(init.io, args[1], encoded);
        return;
    }
    const summary = try plug.dsp.Mp3Stream.summarize(encoded);
    if (requirement == .junk_resync) {
        try verifyJunkResynchronization(encoded, summary, allocator);
        return;
    }
    if (requirement == .protected) {
        const first_frame = try plug.dsp.Mp3Frame.parse(
            encoded,
            summary.audio_offset,
        );
        if (!first_frame.header.crc_present or
            try first_frame.crcValid() != true)
        {
            return error.MissingExpectedMp3Protection;
        }
    }
    if (requirement == .free_format) {
        const first_frame = try plug.dsp.Mp3Frame.parse(
            encoded,
            summary.audio_offset,
        );
        if (!first_frame.header.free_format)
            return error.MissingExpectedMp3FreeFormat;
    }
    if (requirement == .joint_stereo) {
        const first_frame = try plug.dsp.Mp3Frame.parse(
            encoded,
            summary.audio_offset,
        );
        if (first_frame.header.channel_mode != .joint_stereo)
            return error.MissingExpectedMp3JointStereo;
    }
    if (requirement == .vbri) {
        const vbri = summary.first_vbri orelse
            return error.MissingExpectedMp3Vbri;
        if (vbri.stream_bytes != summary.audio_bytes or
            vbri.frame_count != summary.frame_count or
            vbri.toc_entries == 0)
        {
            return error.UnexpectedMp3VbriMetadata;
        }
    }
    if (requirement == .gapless) {
        const xing = summary.first_xing orelse
            return error.MissingExpectedMp3GaplessMetadata;
        const declared_frames = xing.frame_count orelse
            return error.MissingExpectedMp3GaplessMetadata;
        const declared_bytes = xing.stream_bytes orelse
            return error.MissingExpectedMp3GaplessMetadata;
        if (xing.encoder_delay == null or
            xing.encoder_padding == null or
            declared_frames != summary.frame_count or
            declared_bytes != summary.audio_bytes)
        {
            return error.UnexpectedMp3GaplessMetadata;
        }
        const plan = try plug.dsp.Mp3GaplessPlan.fromSummary(summary);
        if (plan.audible_samples == 0 or
            plan.audible_samples >= plan.encoded_samples)
        {
            return error.UnexpectedMp3GaplessRange;
        }
    }
    if (args.len >= 4) {
        const expected_sample_rate = try std.fmt.parseInt(
            u32,
            args[2],
            10,
        );
        const expected_channels = try std.fmt.parseInt(
            u8,
            args[3],
            10,
        );
        if (summary.sample_rate != expected_sample_rate or
            summary.channels != expected_channels)
        {
            return error.UnexpectedMp3Format;
        }
    }
    const file = try std.Io.Dir.cwd().openFile(
        init.io,
        args[1],
        .{},
    );
    defer file.close(init.io);
    var frame_storage: [plug.dsp.maximumMp3EncodedFrameBytes]u8 =
        undefined;
    const file_summary = try plug.dsp.Mp3FileReader.summarize(
        init.io,
        file,
        &frame_storage,
    );
    if (file_summary.audio_offset != summary.audio_offset or
        file_summary.audio_bytes != summary.audio_bytes or
        file_summary.frame_count != summary.frame_count or
        file_summary.sample_count != summary.sample_count or
        file_summary.sample_rate != summary.sample_rate or
        file_summary.channels != summary.channels or
        !std.meta.eql(file_summary.first_xing, summary.first_xing) or
        (file_summary.first_vbri == null) !=
            (summary.first_vbri == null))
    {
        return error.Mp3MemoryAndFileSummariesDiffer;
    }

    const seek_stride: u32 = @intCast(@max(
        @as(u64, 1),
        summary.frame_count / 8,
    ));
    const seek_point_count = try plug.dsp.requiredMp3SeekPoints(
        encoded,
        seek_stride,
    );
    const file_seek_point_count =
        try plug.dsp.requiredMp3FileSeekPoints(
            init.io,
            file,
            &frame_storage,
            seek_stride,
        );
    if (file_seek_point_count != seek_point_count)
        return error.Mp3MemoryAndFileSeekPointCountsDiffer;
    const seek_storage = try allocator.alloc(
        plug.dsp.Mp3SeekPoint,
        seek_point_count,
    );
    const file_seek_storage = try allocator.alloc(
        plug.dsp.Mp3SeekPoint,
        file_seek_point_count,
    );
    const seek_index = try plug.dsp.buildMp3SeekIndex(
        encoded,
        seek_stride,
        seek_storage,
    );
    const file_seek_index = try plug.dsp.buildMp3FileSeekIndex(
        init.io,
        file,
        &frame_storage,
        seek_stride,
        file_seek_storage,
    );
    if (require_multiple_seek_points and seek_index.len < 4)
        return error.InsufficientMp3SeekCoverage;
    if (seek_index.len != file_seek_index.len)
        return error.Mp3MemoryAndFileSeekIndexesDiffer;
    for (seek_index, file_seek_index) |memory_point, file_point| {
        if (!std.meta.eql(memory_point, file_point))
            return error.Mp3MemoryAndFileSeekIndexesDiffer;
    }
    const midpoint = try plug.dsp.findMp3SeekPoint(
        seek_index,
        summary.sample_count / 2,
    );
    var seek_reader = try plug.dsp.Mp3FileReader.init(init.io, file);
    try seek_reader.seek(midpoint);
    const seek_frame = try seek_reader.next(&frame_storage) orelse
        return error.Mp3SeekPointHasNoFrame;
    if (seek_frame.byte_offset != @as(u64, @intCast(midpoint.byte_offset)) or
        seek_reader.frame_index != midpoint.frame_index + 1 or
        seek_reader.sample_offset != midpoint.sample_offset +
            seek_frame.header.samplesPerFrame())
    {
        return error.Mp3SeekPositionMismatch;
    }

    const memory_evidence = try decodeMemory(encoded, summary);
    const file_evidence = try decodeFile(
        init.io,
        file,
        summary,
        &frame_storage,
    );
    if (!std.meta.eql(memory_evidence, file_evidence))
        return error.Mp3MemoryAndFilePcmDiffer;
    if (require_multiple_seek_points and
        (memory_evidence.padded_frames == 0 or
            memory_evidence.unpadded_frames == 0))
    {
        return error.InsufficientMp3PaddingCoverage;
    }
}

const Requirement = enum {
    none,
    tagged_multiple_seek_points,
    id3v2_4,
    protected,
    free_format,
    joint_stereo,
    vbri,
    gapless,
    junk_resync,
    trailing_junk_rejection,
};

fn hasId3v2Version(encoded: []const u8, version: u8) bool {
    return encoded.len >= 4 and
        std.mem.startsWith(u8, encoded, "ID3") and
        encoded[3] == version;
}

const PcmEvidence = struct {
    frames: u64 = 0,
    padded_frames: u64 = 0,
    unpadded_frames: u64 = 0,
    audible_samples: u64 = 0,
    energy: f64 = 0.0,
    digest: u64 = 14_695_981_039_346_656_037,

    fn observe(
        self: *PcmEvidence,
        decoded: plug.dsp.Mp3TrimmedPcmFrame,
        padded: bool,
    ) !void {
        const start: usize = decoded.audible.start;
        const end = start + decoded.audible.length;
        for (0..decoded.pcm.channel_count) |channel| {
            for (decoded.pcm.channels[channel][start..end]) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteMp3Pcm;
                self.energy += @as(f64, @floatCast(sample)) *
                    @as(f64, @floatCast(sample));
                if (!std.math.isFinite(self.energy))
                    return error.NonFiniteMp3PcmEnergy;
                self.digest ^= @as(u32, @bitCast(sample));
                self.digest *%= 1_099_511_628_211;
            }
        }
        self.frames = std.math.add(u64, self.frames, 1) catch
            return error.Mp3DecodedCountOverflow;
        const padding_count = if (padded)
            &self.padded_frames
        else
            &self.unpadded_frames;
        padding_count.* = std.math.add(
            u64,
            padding_count.*,
            1,
        ) catch return error.Mp3DecodedCountOverflow;
        self.audible_samples = std.math.add(
            u64,
            self.audible_samples,
            decoded.audible.length,
        ) catch return error.Mp3DecodedCountOverflow;
    }

    fn validate(
        self: PcmEvidence,
        summary: plug.dsp.Mp3Summary,
        decoder: plug.dsp.Mp3StreamDecoder,
    ) !void {
        try decoder.finish();
        if (self.frames != summary.frame_count or
            self.audible_samples != decoder.plan.audible_samples)
        {
            return error.Mp3DecodedCountsDiffer;
        }
        if (self.energy <= 0.0) return error.SilentMp3Pcm;
    }
};

fn decodeMemory(
    encoded: []const u8,
    summary: plug.dsp.Mp3Summary,
) !PcmEvidence {
    var stream = try plug.dsp.Mp3Stream.init(encoded);
    var decoder = try plug.dsp.Mp3StreamDecoder.init(summary);
    var evidence = PcmEvidence{};
    while (try stream.next()) |frame| {
        const decoded = try decoder.decode(frame);
        try evidence.observe(decoded, frame.header.padding);
    }
    try evidence.validate(summary, decoder);
    return evidence;
}

fn verifyJunkResynchronization(
    encoded: []const u8,
    summary: plug.dsp.Mp3Summary,
    allocator: std.mem.Allocator,
) !void {
    const junk = [_]u8{ 0x00, 0x49, 0x44, 0x33, 0x7f };
    var source = try plug.dsp.Mp3Stream.init(encoded);
    const first = try source.next() orelse
        return error.InsufficientMp3FramesForResynchronization;
    if ((try source.next()) == null)
        return error.InsufficientMp3FramesForResynchronization;
    const insertion = first.offset + first.bytes.len;
    const damaged = try allocator.alloc(u8, encoded.len + junk.len);
    @memcpy(damaged[0..insertion], encoded[0..insertion]);
    @memcpy(damaged[insertion..][0..junk.len], &junk);
    @memcpy(
        damaged[insertion + junk.len ..],
        encoded[insertion..],
    );

    const expected = try decodeMemory(encoded, summary);
    var stream = try plug.dsp.Mp3Stream.init(damaged);
    var decoder = try plug.dsp.Mp3StreamDecoder.init(summary);
    var evidence = PcmEvidence{};
    const recovered_first = try stream.next() orelse
        return error.InsufficientMp3FramesForResynchronization;
    try evidence.observe(
        try decoder.decode(recovered_first),
        recovered_first.header.padding,
    );
    if (stream.next()) |_| {
        return error.Mp3JunkWasNotRejected;
    } else |err| {
        if (err != error.InvalidMp3Sync) return err;
    }
    const retained = stream;
    if (stream.resynchronize(junk.len - 1)) |_| {
        return error.Mp3JunkExceededDeclaredBound;
    } else |err| {
        if (err != error.Mp3ResynchronizationLimitReached) return err;
    }
    if (!std.meta.eql(retained, stream))
        return error.Mp3FailedResynchronizationChangedState;
    if (try stream.resynchronize(junk.len) != junk.len)
        return error.UnexpectedMp3ResynchronizationDistance;
    while (try stream.next()) |frame| {
        try evidence.observe(
            try decoder.decode(frame),
            frame.header.padding,
        );
    }
    try evidence.validate(summary, decoder);
    if (!std.meta.eql(expected, evidence))
        return error.Mp3ResynchronizedPcmDiffered;
}

fn verifyTrailingJunkRejection(
    io: std.Io,
    path: []const u8,
    encoded: []const u8,
) !void {
    const junk = [_]u8{ 0x00, 0x49, 0x44, 0x33, 0x7f };
    if (!std.mem.endsWith(u8, encoded, &junk))
        return error.MissingExpectedMp3TrailingJunk;

    var stream = try plug.dsp.Mp3Stream.init(encoded);
    var memory_frames: u64 = 0;
    while (true) {
        const retained = stream;
        const frame = stream.next() catch |err| {
            if (err != error.InvalidMp3Sync) return err;
            if (!std.meta.eql(retained, stream))
                return error.Mp3TrailingJunkChangedMemoryState;
            break;
        };
        if (frame == null) return error.Mp3TrailingJunkWasAccepted;
        memory_frames = std.math.add(u64, memory_frames, 1) catch
            return error.Mp3DecodedCountOverflow;
    }
    if (memory_frames == 0) return error.Mp3StreamHasNoFrames;

    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);
    var reader = try plug.dsp.Mp3FileReader.init(io, file);
    var frame_storage: [plug.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    var file_frames: u64 = 0;
    while (true) {
        @memset(&frame_storage, 0xa5);
        const retained_offset = reader.offset;
        const retained_frame_index = reader.frame_index;
        const retained_sample_offset = reader.sample_offset;
        const frame = reader.next(&frame_storage) catch |err| {
            if (err != error.InvalidMp3Sync) return err;
            if (reader.offset != retained_offset or
                reader.frame_index != retained_frame_index or
                reader.sample_offset != retained_sample_offset)
            {
                return error.Mp3TrailingJunkChangedFileState;
            }
            for (frame_storage) |byte| {
                if (byte != 0xa5)
                    return error.Mp3TrailingJunkChangedFrameStorage;
            }
            break;
        };
        if (frame == null) return error.Mp3TrailingJunkWasAccepted;
        file_frames = std.math.add(u64, file_frames, 1) catch
            return error.Mp3DecodedCountOverflow;
    }
    if (file_frames != memory_frames)
        return error.Mp3MemoryAndFileFrameCountsDiffer;
}

fn decodeFile(
    io: std.Io,
    file: std.Io.File,
    summary: plug.dsp.Mp3Summary,
    frame_storage: []u8,
) !PcmEvidence {
    var reader = try plug.dsp.Mp3FileReader.init(io, file);
    var decoder = try plug.dsp.Mp3StreamDecoder.init(summary);
    var evidence = PcmEvidence{};
    while (try reader.next(frame_storage)) |frame| {
        const decoded = try decoder.decode(frame);
        try evidence.observe(decoded, frame.header.padding);
    }
    try evidence.validate(summary, decoder);
    return evidence;
}
