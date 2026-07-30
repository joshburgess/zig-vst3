const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.InvalidArguments;

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
        var pcm = plug.dsp.Mp3PcmFrame{
            .channel_count = 2,
            .sample_count = 1152,
        };
        for (0..1152) |sample_index| {
            const absolute =
                frame_index * 1152 + sample_index;
            const phase: f32 = @floatFromInt(absolute);
            pcm.channels[0][sample_index] =
                0.32 * @sin(phase * 0.071) +
                0.08 * @sin(phase * 0.313);
            pcm.channels[1][sample_index] =
                0.22 * @sin(phase * 0.071 + 0.4) +
                0.06 * @sin(phase * 0.257);
        }
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
        init.io,
        args[1],
        .{},
    );
    defer file.close(init.io);
    try file.writeStreamingAll(init.io, encoded[0..cursor]);
}
