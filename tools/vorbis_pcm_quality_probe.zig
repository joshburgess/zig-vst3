const plug = @import("zig-vst3-plugin");
const std = @import("std");

const CandidateEncoding = enum {
    f32le,
    s16le,
    s16le_clipped_reference,
    s16le_reference_s16le,

    fn parse(argument: []const u8) !CandidateEncoding {
        if (std.mem.eql(u8, argument, "--candidate-f32le"))
            return .f32le;
        if (std.mem.eql(u8, argument, "--candidate-s16le"))
            return .s16le;
        if (std.mem.eql(u8, argument, "--candidate-s16le-clipped-reference"))
            return .s16le_clipped_reference;
        if (std.mem.eql(u8, argument, "--candidate-s16le-reference-s16le"))
            return .s16le_reference_s16le;
        return error.InvalidArguments;
    }

    fn sampleSize(self: CandidateEncoding) usize {
        return switch (self) {
            .f32le => @sizeOf(f32),
            .s16le, .s16le_clipped_reference, .s16le_reference_s16le => @sizeOf(i16),
        };
    }

    fn referenceSampleSize(self: CandidateEncoding) usize {
        return switch (self) {
            .s16le_reference_s16le => @sizeOf(i16),
            else => @sizeOf(f32),
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 4) return error.InvalidArguments;

    const encoding = try CandidateEncoding.parse(args[1]);
    const candidate = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[2],
        allocator,
        .limited(64 * 1024 * 1024),
    );
    const reference = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        args[3],
        allocator,
        .limited(64 * 1024 * 1024),
    );
    const measurement = try measure(encoding, candidate, reference);
    std.debug.print(
        "Vorbis external PCM quality samples={d} peak_error={d:.9} rms_error={d:.9} normalized_rms_error={d:.9} optimal_candidate_gain={d:.9} gain_aligned_normalized_rms={d:.9} signal_to_noise_db={d:.9}\n",
        .{
            measurement.sample_count,
            measurement.peak_absolute_error,
            measurement.rms_error,
            measurement.normalized_rms_error,
            measurement.optimal_candidate_gain,
            measurement.gain_aligned_normalized_rms_error,
            measurement.signal_to_noise_db,
        },
    );
}

fn measure(
    encoding: CandidateEncoding,
    candidate: []const u8,
    reference: []const u8,
) !plug.dsp.VorbisPcmQualityMeasurement {
    const candidate_sample_size = encoding.sampleSize();
    const reference_sample_size = encoding.referenceSampleSize();
    if (candidate.len % candidate_sample_size != 0 or
        reference.len % reference_sample_size != 0)
    {
        return error.InvalidPcmByteCount;
    }
    const candidate_count = candidate.len / candidate_sample_size;
    const reference_count = reference.len / reference_sample_size;
    if (candidate_count == 0 or candidate_count != reference_count)
        return error.PcmSampleCountMismatch;

    var meter = plug.dsp.VorbisPcmQualityMeter{};
    for (0..reference_count) |index| {
        const reference_offset = index * reference_sample_size;
        const raw_reference_sample: f32 = switch (encoding) {
            .s16le_reference_s16le => @as(f32, @floatFromInt(@as(i16, @bitCast(
                std.mem.readInt(
                    u16,
                    reference[reference_offset..][0..2],
                    .little,
                ),
            )))) / 32_768.0,
            else => @bitCast(std.mem.readInt(
                u32,
                reference[reference_offset..][0..4],
                .little,
            )),
        };
        const reference_sample = switch (encoding) {
            .s16le_clipped_reference => std.math.clamp(
                raw_reference_sample,
                -1.0,
                @as(f32, 32_767.0 / 32_768.0),
            ),
            else => raw_reference_sample,
        };
        const candidate_offset = index * candidate_sample_size;
        const candidate_sample: f32 = switch (encoding) {
            .f32le => @bitCast(std.mem.readInt(
                u32,
                candidate[candidate_offset..][0..4],
                .little,
            )),
            .s16le, .s16le_clipped_reference, .s16le_reference_s16le => @as(f32, @floatFromInt(@as(i16, @bitCast(
                std.mem.readInt(
                    u16,
                    candidate[candidate_offset..][0..2],
                    .little,
                ),
            )))) / 32_768.0,
        };
        try meter.updateSample(
            f32,
            reference_sample,
            candidate_sample,
        );
    }
    return meter.measurement();
}

test "external PCM quality measures f32 and s16 candidates" {
    const reference_samples = [_]f32{ 0.25, -0.5, 0.75 };
    var reference: [reference_samples.len * @sizeOf(f32)]u8 = undefined;
    for (reference_samples, 0..) |sample, index| {
        std.mem.writeInt(
            u32,
            reference[index * @sizeOf(f32) ..][0..4],
            @bitCast(sample),
            .little,
        );
    }

    const exact = try measure(.f32le, &reference, &reference);
    try std.testing.expectEqual(@as(u64, 3), exact.sample_count);
    try std.testing.expectEqual(@as(f64, 0), exact.normalized_rms_error);

    const candidate_samples = [_]i16{ 8192, -16_384, 24_576 };
    var candidate: [candidate_samples.len * @sizeOf(i16)]u8 = undefined;
    for (candidate_samples, 0..) |sample, index| {
        std.mem.writeInt(
            u16,
            candidate[index * @sizeOf(i16) ..][0..2],
            @bitCast(sample),
            .little,
        );
    }
    const converted = try measure(.s16le, &candidate, &reference);
    try std.testing.expectEqual(@as(f64, 0), converted.normalized_rms_error);
    const integer_reference = try measure(
        .s16le_reference_s16le,
        &candidate,
        &candidate,
    );
    try std.testing.expectEqual(
        @as(f64, 0),
        integer_reference.normalized_rms_error,
    );

    const clipped_reference_samples = [_]f32{ -1.25, 1.25 };
    var clipped_reference: [clipped_reference_samples.len * @sizeOf(f32)]u8 = undefined;
    for (clipped_reference_samples, 0..) |sample, index| {
        std.mem.writeInt(
            u32,
            clipped_reference[index * @sizeOf(f32) ..][0..4],
            @bitCast(sample),
            .little,
        );
    }
    const clipped_candidate_samples = [_]i16{ -32_768, 32_767 };
    var clipped_candidate: [clipped_candidate_samples.len * @sizeOf(i16)]u8 = undefined;
    for (clipped_candidate_samples, 0..) |sample, index| {
        std.mem.writeInt(
            u16,
            clipped_candidate[index * @sizeOf(i16) ..][0..2],
            @bitCast(sample),
            .little,
        );
    }
    const clipped = try measure(
        .s16le_clipped_reference,
        &clipped_candidate,
        &clipped_reference,
    );
    try std.testing.expectEqual(@as(f64, 0), clipped.normalized_rms_error);
}

test "external PCM quality rejects malformed shapes and samples" {
    const reference_sample: f32 = 0.25;
    var reference: [@sizeOf(f32)]u8 = undefined;
    std.mem.writeInt(u32, &reference, @bitCast(reference_sample), .little);
    try std.testing.expectError(
        error.InvalidPcmByteCount,
        measure(.f32le, &.{ 0, 1, 2 }, &reference),
    );
    try std.testing.expectError(
        error.PcmSampleCountMismatch,
        measure(.s16le, &.{ 0, 0, 0, 0 }, &reference),
    );

    const non_finite: f32 = std.math.nan(f32);
    var non_finite_bytes: [@sizeOf(f32)]u8 = undefined;
    std.mem.writeInt(
        u32,
        &non_finite_bytes,
        @bitCast(non_finite),
        .little,
    );
    try std.testing.expectError(
        error.NonFiniteVorbisPcmQualitySample,
        measure(.f32le, &non_finite_bytes, &reference),
    );
}
