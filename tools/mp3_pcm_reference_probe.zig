const plug = @import("zig-vst3-plugin");
const std = @import("std");

const maximum_peak_error = 0.05;
const maximum_normalized_rms_error = 0.02;

const ReferencePolicy = enum {
    audible_only,
    gapless_encoded_or_audible,
};

const ReferenceWindow = struct {
    start: usize,
    end: usize,
};

fn referenceWindow(
    plan: plug.dsp.Mp3GaplessPlan,
    channels: u8,
    reference_bytes: usize,
    policy: ReferencePolicy,
) !ReferenceWindow {
    if (!plan.valid() or channels == 0 or
        reference_bytes % @sizeOf(f32) != 0)
        return error.InvalidMp3PcmReference;
    const audible_values = std.math.mul(
        u64,
        plan.audible_samples,
        channels,
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    const audible_bytes = std.math.mul(
        u64,
        audible_values,
        @sizeOf(f32),
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    if (@as(u64, @intCast(reference_bytes)) == audible_bytes) {
        return .{ .start = 0, .end = reference_bytes };
    }
    if (policy != .gapless_encoded_or_audible)
        return error.Mp3PcmReferenceSampleCountMismatch;

    const encoded_values = std.math.mul(
        u64,
        plan.encoded_samples,
        channels,
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    const encoded_bytes = std.math.mul(
        u64,
        encoded_values,
        @sizeOf(f32),
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    if (@as(u64, @intCast(reference_bytes)) != encoded_bytes)
        return error.Mp3PcmReferenceSampleCountMismatch;
    const leading_values = std.math.mul(
        u64,
        plan.leading_samples,
        channels,
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    const leading_bytes = std.math.mul(
        u64,
        leading_values,
        @sizeOf(f32),
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    const end = std.math.add(
        u64,
        leading_bytes,
        audible_bytes,
    ) catch return error.Mp3PcmReferenceSizeOverflow;
    if (end > encoded_bytes)
        return error.InvalidMp3PcmReference;
    return .{
        .start = @intCast(leading_bytes),
        .end = @intCast(end),
    };
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4 and args.len != 5)
        return error.InvalidArguments;

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
    const reference_policy: ReferencePolicy = if (args.len == 4)
        .audible_only
    else if (std.mem.eql(
        u8,
        args[4],
        "--accept-full-gapless-reference",
    ))
        .gapless_encoded_or_audible
    else
        return error.InvalidArguments;

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
    const reference_window = referenceWindow(
        decoder.plan,
        expected_channels,
        reference.len,
        reference_policy,
    ) catch |window_error| {
        const reference_sample_values = reference.len / @sizeOf(f32);
        std.debug.print(
            "MP3 PCM reference sample-count mismatch project={d} reference={d}\n",
            .{ sample_values, reference_sample_values },
        );
        return window_error;
    };

    var reference_offset = reference_window.start;
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
    if (reference_offset != reference_window.end or
        compared_samples != sample_values)
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

test "reference window accepts complete gapless decoder PCM explicitly" {
    const plan = plug.dsp.Mp3GaplessPlan{
        .encoded_samples = 5_760,
        .leading_samples = 1_728,
        .trailing_samples = 576,
        .audible_samples = 3_456,
    };
    const audible_bytes = 3_456 * 2 * @sizeOf(f32);
    const encoded_bytes = 5_760 * 2 * @sizeOf(f32);

    try std.testing.expectEqual(
        ReferenceWindow{ .start = 0, .end = audible_bytes },
        try referenceWindow(plan, 2, audible_bytes, .audible_only),
    );
    try std.testing.expectError(
        error.Mp3PcmReferenceSampleCountMismatch,
        referenceWindow(plan, 2, encoded_bytes, .audible_only),
    );
    try std.testing.expectEqual(
        ReferenceWindow{
            .start = 1_728 * 2 * @sizeOf(f32),
            .end = (1_728 + 3_456) * 2 * @sizeOf(f32),
        },
        try referenceWindow(
            plan,
            2,
            encoded_bytes,
            .gapless_encoded_or_audible,
        ),
    );
    try std.testing.expectEqual(
        ReferenceWindow{ .start = 0, .end = audible_bytes },
        try referenceWindow(
            plan,
            2,
            audible_bytes,
            .gapless_encoded_or_audible,
        ),
    );
    try std.testing.expectError(
        error.Mp3PcmReferenceSampleCountMismatch,
        referenceWindow(
            plan,
            2,
            encoded_bytes - @sizeOf(f32),
            .gapless_encoded_or_audible,
        ),
    );
    try std.testing.expectError(
        error.InvalidMp3PcmReference,
        referenceWindow(
            plan,
            2,
            audible_bytes - 1,
            .gapless_encoded_or_audible,
        ),
    );
}
