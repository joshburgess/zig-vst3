const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 3) return error.InvalidArguments;
    try writeGaplessFixture(init.io, args[1]);
    try writeVbriFixture(init.io, args[2]);
}

fn writeGaplessFixture(io: std.Io, path: []const u8) !void {
    const config = plug.dsp.Mp3EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 192,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
        .crc_present = true,
    };
    var encoder = try plug.dsp.Mp3PcmStreamEncoder.init(config);
    var encoded: [plug.dsp.maximumMp3EncodedFrameBytes * 6]u8 =
        undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(
        encoded[cursor..],
    );
    cursor += metadata.len;

    for (0..3) |frame_index| {
        const pcm = pcmFrame(frame_index);
        const frame = try encoder.append(pcm, encoded[cursor..]);
        cursor += frame.len;
    }
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    var final_metadata: [plug.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    const patched = try encoder.gaplessMetadataFrame(
        &final_metadata,
    );
    @memcpy(encoded[0..patched.len], patched);

    var file = try std.Io.Dir.cwd().createFile(
        io,
        path,
        .{},
    );
    defer file.close(io);
    try file.writeStreamingAll(io, encoded[0..cursor]);
}

fn writeVbriFixture(io: std.Io, path: []const u8) !void {
    const config = plug.dsp.Mp3EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 320,
        .sample_rate = 44_100,
        .channel_mode = .stereo,
    };
    var encoder = try plug.dsp.Mp3PcmStreamEncoder.init(config);
    var encoded: [plug.dsp.maximumMp3EncodedFrameBytes * 6]u8 = undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(encoded[cursor..]);
    cursor += metadata.len;
    for (0..3) |frame_index| {
        const frame = try encoder.append(
            pcmFrame(frame_index),
            encoded[cursor..],
        );
        cursor += frame.len;
    }
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;

    var offsets: [6]u64 = undefined;
    var stream = try plug.dsp.Mp3Stream.init(encoded[0..cursor]);
    var frame_count: usize = 0;
    while (try stream.next()) |frame| {
        if (frame_count == offsets.len)
            return error.UnexpectedMp3VbriFrameCount;
        offsets[frame_count] = frame.offset;
        frame_count += 1;
    }
    const summary_frame_count = std.math.cast(
        u32,
        finished.summary.frame_count,
    ) orelse return error.Mp3FrameCountOverflow;
    if (frame_count != summary_frame_count)
        return error.UnexpectedMp3VbriFrameCount;
    const stream_bytes = std.math.cast(
        u32,
        finished.summary.byte_count,
    ) orelse return error.Mp3ByteCountOverflow;
    var toc_storage: [12]u8 = undefined;
    const toc = try plug.dsp.buildMp3VbriToc(
        offsets[0..frame_count],
        summary_frame_count,
        stream_bytes,
        1,
        1,
        2,
        &toc_storage,
    );
    const vbri = try plug.dsp.encodeMp3VbriFrame(
        try config.header(false),
        .{
            .delay = finished.summary.encoder_delay,
            .quality = 80,
            .stream_bytes = stream_bytes,
            .frame_count = summary_frame_count,
            .toc_scale = 1,
            .entry_bytes = 2,
            .frames_per_entry = 1,
            .toc = toc,
        },
        encoded[0..metadata.len],
    );
    if (vbri.len != metadata.len)
        return error.UnexpectedMp3VbriFrameSize;
    const parsed = try plug.dsp.Mp3Stream.summarize(encoded[0..cursor]);
    const parsed_vbri = parsed.first_vbri orelse
        return error.MissingMp3VbriMetadata;
    if (parsed_vbri.stream_bytes != stream_bytes or
        parsed_vbri.frame_count != summary_frame_count)
    {
        return error.UnexpectedMp3VbriMetadata;
    }

    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, encoded[0..cursor]);
}

fn pcmFrame(frame_index: usize) plug.dsp.Mp3PcmFrame {
    var pcm = plug.dsp.Mp3PcmFrame{
        .channel_count = 2,
        .sample_count = 1152,
    };
    for (0..1152) |sample_index| {
        const absolute = frame_index * 1152 + sample_index;
        const phase: f32 = @floatFromInt(absolute);
        pcm.channels[0][sample_index] =
            0.32 * @sin(phase * 0.071) +
            0.08 * @sin(phase * 0.313);
        pcm.channels[1][sample_index] =
            0.22 * @sin(phase * 0.071 + 0.4) +
            0.06 * @sin(phase * 0.257);
    }
    return pcm;
}
