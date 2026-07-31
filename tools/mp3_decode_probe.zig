const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2 and args.len != 4)
        return error.InvalidArguments;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    const summary = try plug.dsp.Mp3Stream.summarize(encoded);
    if (args.len == 4) {
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

    const memory_evidence = try decodeMemory(encoded, summary);
    const file_evidence = try decodeFile(
        init.io,
        file,
        summary,
        &frame_storage,
    );
    if (!std.meta.eql(memory_evidence, file_evidence))
        return error.Mp3MemoryAndFilePcmDiffer;
}

const PcmEvidence = struct {
    frames: u64 = 0,
    audible_samples: u64 = 0,
    energy: f64 = 0.0,
    digest: u64 = 14_695_981_039_346_656_037,

    fn observe(
        self: *PcmEvidence,
        decoded: plug.dsp.Mp3TrimmedPcmFrame,
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
        try evidence.observe(decoded);
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
        try evidence.observe(decoded);
    }
    try evidence.validate(summary, decoder);
    return evidence;
}
