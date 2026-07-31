const plug = @import("zig-vst3-plugin");
const std = @import("std");

const maximum_peak_error = 0.05;
const maximum_normalized_rms_error = 0.02;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.InvalidArguments;

    const encoded = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[1],
        allocator,
        .limited(16 * 1024 * 1024),
    );
    const reference = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[2],
        allocator,
        .limited(64 * 1024 * 1024),
    );
    const expected_channels = try std.fmt.parseInt(u8, args[3], 10);
    if (expected_channels == 0) return error.InvalidArguments;

    const summary = try plug.dsp.Mp3Stream.summarize(encoded);
    if (summary.channels != expected_channels)
        return error.UnexpectedMp3ChannelCount;

    var stream = try plug.dsp.Mp3Stream.init(encoded);
    var decoder = try plug.dsp.Mp3StreamDecoder.init(summary);
    const sample_values = std.math.mul(
        u64,
        decoder.plan.audible_samples,
        expected_channels,
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    const expected_bytes = std.math.mul(
        u64,
        sample_values,
        @sizeOf(f32),
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    if (@as(u64, @intCast(reference.len)) != expected_bytes) {
        const reference_sample_values = reference.len / @sizeOf(f32);
        std.debug.print(
            "MP3 PCM reference sample-count mismatch project={d} reference={d}\n",
            .{ sample_values, reference_sample_values },
        );
        return error.Mp3PcmReferenceSampleCountMismatch;
    }

    var reference_offset: usize = 0;
    var compared_samples: u64 = 0;
    var reference_energy: f64 = 0.0;
    var error_energy: f64 = 0.0;
    var peak_error: f64 = 0.0;
    while (try stream.next()) |frame| {
        const decoded = try decoder.decode(frame);
        const start: usize = decoded.audible.start;
        const end = start + decoded.audible.length;
        for (start..end) |sample_index| {
            for (0..decoded.pcm.channel_count) |channel| {
                const project_sample = decoded.pcm.channels[channel][sample_index];
                if (reference_offset + @sizeOf(f32) > reference.len)
                    return error.Mp3PcmReferenceSampleCountMismatch;
                const reference_sample: f32 = @bitCast(std.mem.readInt(
                    u32,
                    reference[reference_offset..][0..4],
                    .little,
                ));
                reference_offset += @sizeOf(f32);
                if (!std.math.isFinite(project_sample) or
                    !std.math.isFinite(reference_sample))
                {
                    return error.NonFiniteMp3PcmReference;
                }
                const reference_value: f64 = reference_sample;
                const difference = @as(f64, @floatCast(project_sample)) -
                    reference_value;
                reference_energy += reference_value * reference_value;
                error_energy += difference * difference;
                peak_error = @max(peak_error, @abs(difference));
                compared_samples = std.math.add(
                    u64,
                    compared_samples,
                    1,
                ) catch return error.Mp3PcmReferenceSizeOverflow;
            }
        }
    }
    try decoder.finish();
    if (reference_offset != reference.len or compared_samples != sample_values)
        return error.Mp3PcmReferenceSampleCountMismatch;
    if (reference_energy <= 0.0)
        return error.SilentMp3PcmReference;

    const divisor: f64 = @floatFromInt(compared_samples);
    const reference_rms = @sqrt(reference_energy / divisor);
    const error_rms = @sqrt(error_energy / divisor);
    const normalized_rms_error = error_rms / reference_rms;
    std.debug.print(
        "MP3 PCM reference samples={d} peak_error={d:.9} rms_error={d:.9} normalized_rms_error={d:.9}\n",
        .{
            compared_samples,
            peak_error,
            error_rms,
            normalized_rms_error,
        },
    );
    if (peak_error > maximum_peak_error)
        return error.Mp3PcmReferencePeakErrorExceeded;
    if (normalized_rms_error > maximum_normalized_rms_error)
        return error.Mp3PcmReferenceRmsErrorExceeded;
}
