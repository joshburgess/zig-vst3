const plug = @import("zig-vst3-plugin");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 3) return error.InvalidArguments;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    try patchVbriMetadata(encoded, allocator);

    var output = try std.Io.Dir.cwd().createFile(init.io, args[2], .{});
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, encoded);
}

fn patchVbriMetadata(
    encoded: []u8,
    allocator: std.mem.Allocator,
) !void {
    const summary = try plug.dsp.Mp3Stream.summarize(encoded);
    const frame_count = std.math.cast(u32, summary.frame_count) orelse
        return error.Mp3FrameCountOverflow;
    const stream_bytes = std.math.cast(u32, summary.audio_bytes) orelse
        return error.Mp3ByteCountOverflow;
    if (frame_count == 0) return error.Mp3StreamHasNoFrames;

    const offsets = try allocator.alloc(u64, frame_count);
    defer allocator.free(offsets);
    var stream = try plug.dsp.Mp3Stream.init(encoded);
    var first_frame: ?plug.dsp.Mp3Frame = null;
    var index: usize = 0;
    while (try stream.next()) |frame| {
        if (index >= offsets.len) return error.UnexpectedMp3FrameCount;
        if (first_frame == null) first_frame = frame;
        offsets[index] = frame.offset - summary.audio_offset;
        index += 1;
    }
    if (index != offsets.len) return error.UnexpectedMp3FrameCount;

    const toc_bytes = try plug.dsp.requiredMp3VbriTocBytes(
        frame_count,
        1,
        4,
    );
    const toc_storage = try allocator.alloc(u8, toc_bytes);
    defer allocator.free(toc_storage);
    const toc = try plug.dsp.buildMp3VbriToc(
        offsets,
        frame_count,
        stream_bytes,
        1,
        1,
        4,
        toc_storage,
    );
    const metadata_frame = first_frame orelse
        return error.Mp3StreamHasNoFrames;
    if (metadata_frame.xing == null)
        return error.MissingReservedMp3MetadataFrame;
    const staged = try allocator.dupe(u8, encoded);
    defer allocator.free(staged);
    const patched = try plug.dsp.encodeMp3VbriFrame(
        metadata_frame.header,
        .{
            .quality = 80,
            .stream_bytes = stream_bytes,
            .frame_count = frame_count,
            .toc_scale = 1,
            .entry_bytes = 4,
            .frames_per_entry = 1,
            .toc = toc,
        },
        staged[metadata_frame.offset..],
    );
    if (patched.len != metadata_frame.bytes.len)
        return error.UnexpectedMp3VbriFrameSize;

    const verified = try plug.dsp.Mp3Stream.summarize(staged);
    const vbri = verified.first_vbri orelse
        return error.MissingMp3VbriMetadata;
    if (verified.audio_offset != summary.audio_offset or
        verified.audio_bytes != summary.audio_bytes or
        verified.frame_count != summary.frame_count or
        vbri.stream_bytes != stream_bytes or
        vbri.frame_count != frame_count)
    {
        return error.UnexpectedMp3VbriMetadata;
    }
    @memcpy(encoded, staged);
}

test "patch VBRI metadata into a complete encoded stream" {
    const config = plug.dsp.Mp3EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 192,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    };
    var encoder = try plug.dsp.Mp3PcmStreamEncoder.init(config);
    var encoded: [plug.dsp.maximumMp3EncodedFrameBytes * 5]u8 =
        undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(encoded[cursor..]);
    cursor += metadata.len;
    for (0..2) |_| {
        const frame = try encoder.append(.{
            .channel_count = 2,
            .sample_count = 1152,
        }, encoded[cursor..]);
        cursor += frame.len;
    }
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;

    try patchVbriMetadata(
        encoded[0..cursor],
        std.testing.allocator,
    );
    const summary = try plug.dsp.Mp3Stream.summarize(encoded[0..cursor]);
    const vbri = summary.first_vbri orelse
        return error.MissingMp3VbriMetadata;
    try std.testing.expectEqual(summary.audio_bytes, vbri.stream_bytes);
    try std.testing.expectEqual(summary.frame_count, vbri.frame_count);
    try std.testing.expectEqual(
        @as(u32, 0),
        try vbri.approximateByteOffsetForFrame(0),
    );
    try std.testing.expectEqual(
        @as(u32, @intCast(summary.audio_bytes)),
        try vbri.approximateByteOffsetForFrame(vbri.frame_count),
    );
}

test "preserve a stream without a reserved metadata frame" {
    const config = plug.dsp.Mp3EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 192,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    };
    var encoder = try plug.dsp.Mp3PcmStreamEncoder.init(config);
    var encoded: [plug.dsp.maximumMp3EncodedFrameBytes * 3]u8 =
        undefined;
    const frame = try encoder.append(.{
        .channel_count = 2,
        .sample_count = 1152,
    }, &encoded);
    var retained: [plug.dsp.maximumMp3EncodedFrameBytes]u8 = undefined;
    @memcpy(retained[0..frame.len], frame);

    try std.testing.expectError(
        error.MissingReservedMp3MetadataFrame,
        patchVbriMetadata(frame, std.testing.allocator),
    );
    try std.testing.expectEqualSlices(
        u8,
        retained[0..frame.len],
        frame,
    );
}

fn exercisePatchAllocations(allocator: std.mem.Allocator) !void {
    const config = plug.dsp.Mp3EncoderConfig{
        .version = .mpeg1,
        .bitrate_kbps = 192,
        .sample_rate = 44_100,
        .channel_mode = .joint_stereo,
        .mode_extension = 3,
    };
    var encoder = try plug.dsp.Mp3PcmStreamEncoder.init(config);
    var encoded: [plug.dsp.maximumMp3EncodedFrameBytes * 4]u8 =
        undefined;
    var cursor: usize = 0;
    const metadata = try encoder.startGaplessMetadata(encoded[cursor..]);
    cursor += metadata.len;
    const frame = try encoder.append(.{
        .channel_count = 2,
        .sample_count = 1152,
    }, encoded[cursor..]);
    cursor += frame.len;
    const finished = try encoder.finish(encoded[cursor..]);
    cursor += finished.frames.len;
    var retained: [plug.dsp.maximumMp3EncodedFrameBytes * 4]u8 =
        undefined;
    @memcpy(retained[0..cursor], encoded[0..cursor]);

    patchVbriMetadata(encoded[0..cursor], allocator) catch |err| {
        try std.testing.expectEqualSlices(
            u8,
            retained[0..cursor],
            encoded[0..cursor],
        );
        return err;
    };
    const summary = try plug.dsp.Mp3Stream.summarize(encoded[0..cursor]);
    try std.testing.expect(summary.first_vbri != null);
}

test "VBRI patch allocation failures preserve the input stream" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exercisePatchAllocations,
        .{},
    );
}
