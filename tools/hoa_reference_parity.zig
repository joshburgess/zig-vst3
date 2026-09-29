const plugin = @import("zig-vst3-plugin");
const std = @import("std");

const ReferenceSpeaker = extern struct {
    azimuth_degrees: f64,
    elevation_degrees: f64,
    is_lfe: u8,
};

comptime {
    if (@sizeOf(ReferenceSpeaker) != 24 or
        @offsetOf(ReferenceSpeaker, "elevation_degrees") != 8 or
        @offsetOf(ReferenceSpeaker, "is_lfe") != 16)
    {
        @compileError("unexpected HOA reference speaker layout");
    }
}

extern fn hoa_reference_basis(
    normalization: u32,
    order: u32,
    degree: i32,
    azimuth_degrees: f64,
    elevation_degrees: f64,
    output: *f64,
) c_int;

extern fn hoa_reference_matrix(
    orders: [*]const u32,
    degrees: [*]const i32,
    input_count: usize,
    normalization: u32,
    speakers: [*]const ReferenceSpeaker,
    output_count: usize,
    max_re: u8,
    output: [*]f64,
    coefficient_count: usize,
) c_int;

const input_count = 16;
const output_count = 33;
const frame_count = 257;

pub fn main(init: std.process.Init) !void {
    try compareBasis();
    try compareMatrices();

    var stdout = std.Io.File.stdout().writer(init.io, &.{});
    try stdout.interface.print(
        "matched 336 HOA basis values, 12672 matrix coefficients, and 203544 rendered samples\n",
        .{},
    );
}

fn compareBasis() !void {
    var rejected: f64 = 123.25;
    if (hoa_reference_basis(
        0,
        4,
        0,
        0.0,
        0.0,
        &rejected,
    ) != 3 or rejected != 123.25) {
        return error.NonTransactionalHoaReferenceRejection;
    }
    const directions = [_][2]f64{
        .{ -180.0, -90.0 },
        .{ -137.0, -51.0 },
        .{ -31.0, -7.0 },
        .{ 0.0, 0.0 },
        .{ 47.0, 23.0 },
        .{ 119.0, 68.0 },
        .{ 180.0, 90.0 },
    };
    inline for (.{
        plugin.dsp.AdmXmlHoaNormalization.sn3d,
        plugin.dsp.AdmXmlHoaNormalization.n3d,
        plugin.dsp.AdmXmlHoaNormalization.fuma,
    }) |normalization| {
        for (directions) |direction| {
            for (0..4) |order_usize| {
                const order: u32 = @intCast(order_usize);
                const signed_order: i32 = @intCast(order);
                var degree = -signed_order;
                while (degree <= signed_order) : (degree += 1) {
                    var reference: f64 = 0.0;
                    if (hoa_reference_basis(
                        referenceNormalization(normalization),
                        order,
                        degree,
                        direction[0],
                        direction[1],
                        &reference,
                    ) != 0) return error.HoaBasisReferenceFailed;
                    const actual = try plugin.dsp.evaluateAdmHoaBasis(
                        normalization,
                        order,
                        degree,
                        direction[0],
                        direction[1],
                    );
                    try expectClose(actual, reference, 2.0e-12);
                }
            }
        }
    }
}

fn compareMatrices() !void {
    const document = try plugin.dsp.AdmXmlDocument.init(
        \\<audioFormatExtended>
        \\  <audioChannelFormat audioChannelFormatID="AC_00041001">
        \\    <audioBlockFormatHoa audioBlockFormatID="AB_00041001_00000001">
        \\      <order>0</order><degree>0</degree>
        \\      <normalization>SN3D</normalization>
        \\    </audioBlockFormatHoa>
        \\  </audioChannelFormat>
        \\</audioFormatExtended>
    );
    var iterator = document.blocks();
    const prototype = (try iterator.next()) orelse
        return error.MissingHoaPrototype;
    var blocks: [input_count]plugin.dsp.AdmXmlBlockFormat = undefined;
    var orders: [input_count]u32 = undefined;
    var degrees: [input_count]i32 = undefined;
    var component_index: usize = 0;
    for (0..4) |order| {
        const signed_order: i32 = @intCast(order);
        var degree = -signed_order;
        while (degree <= signed_order) : (degree += 1) {
            blocks[component_index] = prototype;
            blocks[component_index].hoa_order = @intCast(order);
            blocks[component_index].hoa_degree = degree;
            blocks[component_index].gain = if (component_index % 2 == 0)
                .{
                    .value = 0.5 +
                        @as(f64, @floatFromInt(component_index)) / 32.0,
                }
            else
                .{
                    .value = -6.0 +
                        @as(f64, @floatFromInt(component_index)) / 10.0,
                    .unit = .decibels,
                };
            orders[component_index] = @intCast(order);
            degrees[component_index] = degree;
            component_index += 1;
        }
    }

    var irregular_loudspeakers: [output_count]plugin.dsp.AdmHoaLoudspeaker = undefined;
    var irregular_reference_speakers: [output_count]ReferenceSpeaker = undefined;
    const golden_angle = 137.507_764_050_037_85;
    for (irregular_loudspeakers[0 .. output_count - 1], 0..) |*speaker, index| {
        const z = 1.0 -
            2.0 * (@as(f64, @floatFromInt(index)) + 0.5) /
                @as(f64, @floatFromInt(output_count - 1));
        const unwrapped = @as(f64, @floatFromInt(index)) * golden_angle;
        speaker.* = .{
            .azimuth_degrees = @mod(unwrapped + 180.0, 360.0) - 180.0,
            .elevation_degrees = std.math.asin(z) * 180.0 / std.math.pi,
        };
        irregular_reference_speakers[index] = .{
            .azimuth_degrees = speaker.azimuth_degrees,
            .elevation_degrees = speaker.elevation_degrees,
            .is_lfe = 0,
        };
    }
    irregular_loudspeakers[output_count - 1] = .{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
        .is_lfe = true,
    };
    irregular_reference_speakers[output_count - 1] = .{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
        .is_lfe = 1,
    };

    try compareMatrixOrdering(
        &blocks,
        &orders,
        &degrees,
        &irregular_loudspeakers,
        &irregular_reference_speakers,
    );

    const permutation = [_]usize{
        0, 5, 11, 2, 14, 7, 1, 9, 15, 4, 12, 6, 3, 13, 8, 10,
    };
    var permuted_blocks: [input_count]plugin.dsp.AdmXmlBlockFormat = undefined;
    var permuted_orders: [input_count]u32 = undefined;
    var permuted_degrees: [input_count]i32 = undefined;
    for (permutation, 0..) |source, destination| {
        permuted_blocks[destination] = blocks[source];
        permuted_orders[destination] = orders[source];
        permuted_degrees[destination] = degrees[source];
    }
    try compareMatrixOrdering(
        &permuted_blocks,
        &permuted_orders,
        &permuted_degrees,
        &irregular_loudspeakers,
        &irregular_reference_speakers,
    );

    const elevations = [_]f64{ -67.5, -22.5, 22.5, 67.5 };
    var regular_loudspeakers: [output_count]plugin.dsp.AdmHoaLoudspeaker = undefined;
    var regular_reference_speakers: [output_count]ReferenceSpeaker = undefined;
    for (regular_loudspeakers[0 .. output_count - 1], 0..) |*speaker, index| {
        const unwrapped = @as(f64, @floatFromInt(index % 8)) * 45.0;
        speaker.* = .{
            .azimuth_degrees = @mod(unwrapped + 180.0, 360.0) - 180.0,
            .elevation_degrees = elevations[index / 8],
        };
        regular_reference_speakers[index] = .{
            .azimuth_degrees = speaker.azimuth_degrees,
            .elevation_degrees = speaker.elevation_degrees,
            .is_lfe = 0,
        };
    }
    regular_loudspeakers[output_count - 1] = .{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
        .is_lfe = true,
    };
    regular_reference_speakers[output_count - 1] = .{
        .azimuth_degrees = 0.0,
        .elevation_degrees = 0.0,
        .is_lfe = 1,
    };
    try compareMatrixOrdering(
        &blocks,
        &orders,
        &degrees,
        &regular_loudspeakers,
        &regular_reference_speakers,
    );
    try compareMatrixOrdering(
        &permuted_blocks,
        &permuted_orders,
        &permuted_degrees,
        &regular_loudspeakers,
        &regular_reference_speakers,
    );
}

fn compareMatrixOrdering(
    blocks: *[input_count]plugin.dsp.AdmXmlBlockFormat,
    orders: *const [input_count]u32,
    degrees: *const [input_count]i32,
    loudspeakers: *const [output_count]plugin.dsp.AdmHoaLoudspeaker,
    reference_speakers: *const [output_count]ReferenceSpeaker,
) !void {
    for ([_]plugin.dsp.AdmXmlHoaNormalization{
        .sn3d,
        .n3d,
        .fuma,
    }) |normalization| {
        for (blocks) |*block| block.hoa_normalization = normalization;
        for ([_]plugin.dsp.AdmHoaOrderWeighting{
            .basic,
            .max_re,
        }) |weighting| {
            try compareMatrixCase(
                blocks,
                orders,
                degrees,
                normalization,
                loudspeakers,
                reference_speakers,
                weighting,
            );
        }
    }
}

fn compareMatrixCase(
    blocks: *const [input_count]plugin.dsp.AdmXmlBlockFormat,
    orders: *const [input_count]u32,
    degrees: *const [input_count]i32,
    normalization: plugin.dsp.AdmXmlHoaNormalization,
    loudspeakers: *const [output_count]plugin.dsp.AdmHoaLoudspeaker,
    reference_speakers: *const [output_count]ReferenceSpeaker,
    weighting: plugin.dsp.AdmHoaOrderWeighting,
) !void {
    var reference: [input_count * output_count]f64 = @splat(0.0);
    const sentinel: f64 = 123.25;
    @memset(&reference, sentinel);
    const short_status = hoa_reference_matrix(
        orders,
        degrees,
        input_count,
        referenceNormalization(normalization),
        reference_speakers,
        output_count,
        if (weighting == .max_re) 1 else 0,
        &reference,
        reference.len - 1,
    );
    if (short_status != 3 or !allEqual(&reference, sentinel))
        return error.NonTransactionalHoaReferenceRejection;

    const status = hoa_reference_matrix(
        orders,
        degrees,
        input_count,
        referenceNormalization(normalization),
        reference_speakers,
        output_count,
        if (weighting == .max_re) 1 else 0,
        &reference,
        reference.len,
    );
    if (status != 0) {
        std.debug.print("HOA matrix reference failed with status {d}\n", .{status});
        return error.HoaMatrixReferenceFailed;
    }

    const Matrix = plugin.dsp.AdmHoaLoudspeakerMatrix(
        f64,
        input_count,
        output_count,
    );
    const generated = try Matrix.init(
        blocks,
        loudspeakers,
        .{ .order_weighting = weighting },
    );
    for (try generated.coefficientSlice(), reference) |actual, expected| {
        try expectClose(actual, expected, 3.0e-10);
    }

    const decoder = try generated.decoder(blocks);
    var input_storage: [input_count][frame_count]f64 = undefined;
    var input_slices: [input_count][]const f64 = undefined;
    for (&input_storage, &input_slices, 0..) |*channel, *slice, input_index| {
        for (channel, 0..) |*sample, frame_index| {
            const phase =
                @as(f64, @floatFromInt((input_index + 1) * (frame_index + 3)));
            sample.* = 0.6 * @sin(phase * 0.013) +
                0.2 * @cos(phase * 0.037);
        }
        slice.* = channel;
    }
    var output_storage: [output_count][frame_count]f64 = undefined;
    var output_slices: [output_count][]f64 = undefined;
    for (&output_storage, &output_slices) |*channel, *slice|
        slice.* = channel;
    try decoder.process(&input_slices, &output_slices);

    for (output_storage, 0..) |channel, output_index| {
        for (channel, 0..) |actual, frame_index| {
            var expected: f64 = 0.0;
            for (input_storage, 0..) |input, input_index| {
                expected += input[frame_index] *
                    linearGain(blocks[input_index].gain) *
                    reference[output_index * input_count + input_index];
            }
            try expectClose(actual, expected, 4.0e-10);
        }
    }
}

fn linearGain(gain: plugin.dsp.AdmXmlGain) f64 {
    return switch (gain.unit) {
        .linear => gain.value,
        .decibels => std.math.pow(f64, 10.0, gain.value / 20.0),
    };
}

fn referenceNormalization(
    normalization: plugin.dsp.AdmXmlHoaNormalization,
) u32 {
    return switch (normalization) {
        .sn3d => 0,
        .n3d => 1,
        .fuma => 2,
    };
}

fn allEqual(values: []const f64, expected: f64) bool {
    for (values) |value| {
        if (value != expected) return false;
    }
    return true;
}

fn expectClose(actual: f64, expected: f64, tolerance: f64) !void {
    if (!std.math.isFinite(actual) or !std.math.isFinite(expected) or
        @abs(actual - expected) >
            tolerance * @max(@max(@abs(actual), @abs(expected)), 1.0))
    {
        return error.HoaReferenceMismatch;
    }
}
