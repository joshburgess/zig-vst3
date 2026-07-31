const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2 and args.len != 4 and args.len != 5)
        return error.InvalidArguments;
    const require_multiple_seek_points = args.len == 5;
    if (require_multiple_seek_points and
        !std.mem.eql(
            u8,
            args[4],
            "--require-tagged-multiple-seek-points",
        ))
    {
        return error.InvalidArguments;
    }

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    if (require_multiple_seek_points and
        (!std.mem.startsWith(u8, encoded, "ID3") or
            encoded.len < 4 or
            encoded[3] != 3 or
            encoded.len < 128 or
            !std.mem.eql(u8, encoded[encoded.len - 128 ..][0..3], "TAG")))
    {
        return error.MissingExpectedMp3Tags;
    }
    const summary = try plug.dsp.Mp3Stream.summarize(encoded);
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
