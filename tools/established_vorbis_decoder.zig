const std = @import("std");

const zsv_ok = 0;
const maximum_stream_bytes = 32 * 1024 * 1024;

const StbInfo = extern struct {
    abi_version: u32,
    channel_count: u32,
    sample_rate: u32,
    open_error: u32,
    decode_error: u32,
    frame_count: u64,
};

extern fn zsv_probe(
    data: [*]const u8,
    size: usize,
    info: *StbInfo,
) callconv(.c) c_int;

extern fn zsv_decode(
    data: [*]const u8,
    size: usize,
    output: [*]f32,
    output_values: usize,
    info: *StbInfo,
) callconv(.c) c_int;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 5) return error.InvalidArguments;
    const expected_rate = try std.fmt.parseInt(u32, args[2], 10);
    const expected_channels = try std.fmt.parseInt(u32, args[3], 10);
    if (expected_rate == 0 or expected_channels == 0)
        return error.InvalidArguments;

    var streams: std.ArrayList([]const u8) = .empty;
    var infos: std.ArrayList(StbInfo) = .empty;
    var total_values: usize = 0;
    var total_frames: u64 = 0;
    for (args[4..]) |path| {
        const stream = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            path,
            allocator,
            .limited(maximum_stream_bytes),
        );
        var info: StbInfo = undefined;
        if (zsv_probe(stream.ptr, stream.len, &info) != zsv_ok)
            return error.StbVorbisProbeFailed;
        try validateInfo(info, expected_rate, expected_channels);
        const values = std.math.mul(
            usize,
            std.math.cast(usize, info.frame_count) orelse
                return error.StbVorbisSizeOverflow,
            std.math.cast(usize, info.channel_count) orelse
                return error.StbVorbisSizeOverflow,
        ) catch return error.StbVorbisSizeOverflow;
        total_values = std.math.add(usize, total_values, values) catch
            return error.StbVorbisSizeOverflow;
        total_frames = std.math.add(u64, total_frames, info.frame_count) catch
            return error.StbVorbisSizeOverflow;
        try streams.append(allocator, stream);
        try infos.append(allocator, info);
    }

    const pcm = try allocator.alloc(f32, total_values);
    var value_offset: usize = 0;
    for (streams.items, infos.items) |stream, expected_info| {
        const values = std.math.mul(
            usize,
            @intCast(expected_info.frame_count),
            @intCast(expected_info.channel_count),
        ) catch return error.StbVorbisSizeOverflow;
        var decoded_info: StbInfo = undefined;
        if (zsv_decode(
            stream.ptr,
            stream.len,
            pcm[value_offset..].ptr,
            values,
            &decoded_info,
        ) != zsv_ok)
            return error.StbVorbisDecodeFailed;
        if (!std.meta.eql(expected_info, decoded_info))
            return error.StbVorbisProbeChanged;
        value_offset += values;
    }
    const peak = try validatePcm(pcm);

    const encoded = try allocator.alloc(u8, pcm.len * @sizeOf(f32));
    for (pcm, 0..) |sample, index| {
        std.mem.writeInt(
            u32,
            encoded[index * @sizeOf(f32) ..][0..4],
            @bitCast(sample),
            .little,
        );
    }
    var output = try std.Io.Dir.cwd().createFile(
        init.io,
        args[1],
        .{ .read = true },
    );
    defer output.close(init.io);
    try output.writePositionalAll(init.io, encoded, 0);
    try output.setLength(init.io, encoded.len);
    std.debug.print(
        "stb_vorbis decoded links={d} frames={d} values={d} peak={d:.9}\n",
        .{ streams.items.len, total_frames, pcm.len, peak },
    );
}

fn validateInfo(info: StbInfo, rate: u32, channels: u32) !void {
    if (info.abi_version != 1 or info.open_error != 0 or
        info.decode_error != 0 or info.frame_count == 0 or
        info.sample_rate != rate or info.channel_count != channels)
        return error.UnexpectedStbVorbisFormat;
}

fn validatePcm(pcm: []const f32) !f32 {
    if (pcm.len == 0) return error.EmptyStbVorbisPcm;
    var peak: f32 = 0;
    for (pcm) |sample| {
        if (!std.math.isFinite(sample)) return error.NonFiniteStbVorbisPcm;
        peak = @max(peak, @abs(sample));
    }
    if (peak == 0) return error.SilentStbVorbisPcm;
    return peak;
}

test "PCM validation rejects empty silent and non-finite output" {
    try std.testing.expectError(error.EmptyStbVorbisPcm, validatePcm(&.{}));
    try std.testing.expectError(
        error.SilentStbVorbisPcm,
        validatePcm(&.{ 0, -0.0 }),
    );
    try std.testing.expectError(
        error.NonFiniteStbVorbisPcm,
        validatePcm(&.{std.math.nan(f32)}),
    );
    try std.testing.expectEqual(@as(f32, 0.75), try validatePcm(&.{ -0.75, 0.5 }));
}
