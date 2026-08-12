const std = @import("std");

const ztv_ok = 0;
const maximum_stream_bytes = 32 * 1024 * 1024;

const TremorInfo = extern struct {
    abi_version: u32,
    channel_count: u32,
    sample_rate: u32,
    open_error: i32,
    decode_error: i32,
    frame_count: u64,
};

extern fn ztv_probe(
    data: [*]const u8,
    size: usize,
    info: *TremorInfo,
) callconv(.c) c_int;

extern fn ztv_decode(
    data: [*]const u8,
    size: usize,
    output: [*]i16,
    output_values: usize,
    fail_after_frames: u64,
    info: *TremorInfo,
) callconv(.c) c_int;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 5) return error.InvalidArguments;
    const expected_rate = try std.fmt.parseInt(u32, args[2], 10);
    const expected_channels = try std.fmt.parseInt(u32, args[3], 10);
    if (expected_rate == 0 or expected_channels == 0)
        return error.InvalidArguments;
    const fail_after_frames = if (init.environ_map.get(
        "ZIG_VST3_TREMOR_FAIL_AFTER_FRAMES",
    )) |value|
        try std.fmt.parseInt(u64, value, 10)
    else
        std.math.maxInt(u64);
    const fail_link = if (init.environ_map.get(
        "ZIG_VST3_TREMOR_FAIL_LINK",
    )) |value|
        try std.fmt.parseInt(usize, value, 10)
    else
        std.math.maxInt(usize);

    var streams: std.ArrayList([]const u8) = .empty;
    var infos: std.ArrayList(TremorInfo) = .empty;
    var total_values: usize = 0;
    var total_frames: u64 = 0;
    for (args[4..]) |path| {
        const stream = try std.Io.Dir.cwd().readFileAlloc(
            init.io,
            path,
            allocator,
            .limited(maximum_stream_bytes),
        );
        var info: TremorInfo = undefined;
        if (ztv_probe(stream.ptr, stream.len, &info) != ztv_ok)
            return error.TremorProbeFailed;
        try validateInfo(info, expected_rate, expected_channels);
        const values = std.math.mul(
            usize,
            std.math.cast(usize, info.frame_count) orelse
                return error.TremorSizeOverflow,
            std.math.cast(usize, info.channel_count) orelse
                return error.TremorSizeOverflow,
        ) catch return error.TremorSizeOverflow;
        total_values = std.math.add(usize, total_values, values) catch
            return error.TremorSizeOverflow;
        total_frames = std.math.add(u64, total_frames, info.frame_count) catch
            return error.TremorSizeOverflow;
        try streams.append(allocator, stream);
        try infos.append(allocator, info);
    }

    const pcm = try allocator.alloc(i16, total_values);
    var value_offset: usize = 0;
    for (streams.items, infos.items, 0..) |stream, expected_info, link_index| {
        const values = std.math.mul(
            usize,
            @intCast(expected_info.frame_count),
            @intCast(expected_info.channel_count),
        ) catch return error.TremorSizeOverflow;
        var decoded_info: TremorInfo = undefined;
        if (ztv_decode(
            stream.ptr,
            stream.len,
            pcm[value_offset..].ptr,
            values,
            if (link_index == fail_link)
                fail_after_frames
            else
                std.math.maxInt(u64),
            &decoded_info,
        ) != ztv_ok)
            return error.TremorDecodeFailed;
        if (!std.meta.eql(expected_info, decoded_info))
            return error.TremorProbeChanged;
        value_offset += values;
    }
    const peak = try validatePcm(pcm);

    const encoded = try allocator.alloc(u8, pcm.len * @sizeOf(i16));
    for (pcm, 0..) |sample, index| {
        std.mem.writeInt(
            u16,
            encoded[index * @sizeOf(i16) ..][0..2],
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
        "Tremor decoded links={d} frames={d} values={d} peak={d}\n",
        .{ streams.items.len, total_frames, pcm.len, peak },
    );
}

fn validateInfo(info: TremorInfo, rate: u32, channels: u32) !void {
    if (info.abi_version != 1 or info.open_error != 0 or
        info.decode_error != 0 or info.frame_count == 0 or
        info.sample_rate != rate or info.channel_count != channels)
        return error.UnexpectedTremorFormat;
}

fn validatePcm(pcm: []const i16) !u16 {
    if (pcm.len == 0) return error.EmptyTremorPcm;
    var peak: u16 = 0;
    for (pcm) |sample| {
        const magnitude: u16 = if (sample == std.math.minInt(i16))
            32_768
        else
            @intCast(@abs(sample));
        peak = @max(peak, magnitude);
    }
    if (peak == 0) return error.SilentTremorPcm;
    return peak;
}

test "PCM validation accepts the complete signed 16-bit range" {
    try std.testing.expectError(error.EmptyTremorPcm, validatePcm(&.{}));
    try std.testing.expectError(
        error.SilentTremorPcm,
        validatePcm(&.{ 0, 0 }),
    );
    try std.testing.expectEqual(
        @as(u16, 32_768),
        try validatePcm(&.{ std.math.minInt(i16), std.math.maxInt(i16) }),
    );
}
