const std = @import("std");
const special_functions = @import("special_functions.zig");

pub const Kind = enum {
    rectangular,
    triangular,
    hann,
    hamming,
    blackman,
    blackman_harris,
    flat_top,
};

pub const Normalization = enum {
    none,
    unit_sum,
    unit_peak,
};

pub fn fill(
    comptime Sample: type,
    output: []Sample,
    kind: Kind,
    periodic: bool,
    normalization: Normalization,
) !void {
    validateSampleType(Sample);
    if (output.len == 0) return error.EmptyWindow;
    const scale = try normalizationScale(Sample, output.len, kind, periodic, normalization);
    for (0..output.len) |index| {
        const value = coefficient(Sample, output.len, index, kind, periodic) * scale;
        if (!std.math.isFinite(value)) return error.NonFiniteWindowOutput;
    }
    for (output, 0..) |*sample, index| {
        sample.* = coefficient(Sample, output.len, index, kind, periodic) * scale;
    }
}

pub fn apply(
    comptime Sample: type,
    samples: []Sample,
    kind: Kind,
    periodic: bool,
    normalization: Normalization,
) !void {
    validateSampleType(Sample);
    if (samples.len == 0) return error.EmptyWindow;
    for (samples) |sample| {
        if (!std.math.isFinite(sample)) return error.NonFiniteWindowInput;
    }
    const scale = try normalizationScale(Sample, samples.len, kind, periodic, normalization);
    for (samples, 0..) |sample, index| {
        const window_value =
            coefficient(Sample, samples.len, index, kind, periodic) * scale;
        const value = sample * window_value;
        if (!std.math.isFinite(value)) return error.NonFiniteWindowOutput;
    }
    for (samples, 0..) |*sample, index| {
        sample.* *= coefficient(Sample, samples.len, index, kind, periodic) * scale;
    }
}

pub fn coefficient(
    comptime Sample: type,
    size: usize,
    index: usize,
    kind: Kind,
    periodic: bool,
) Sample {
    validateSampleType(Sample);
    if (size == 0 or index >= size) return 0.0;
    if (size == 1) return 1.0;
    const denominator = if (periodic)
        @as(Sample, @floatFromInt(size))
    else
        @as(Sample, @floatFromInt(size - 1));
    const phase = std.math.tau * @as(Sample, @floatFromInt(index)) / denominator;
    return switch (kind) {
        .rectangular => 1.0,
        .triangular => blk: {
            const position = @as(Sample, @floatFromInt(index));
            const center = denominator * 0.5;
            break :blk @max(0.0, 1.0 - @abs((position - center) / center));
        },
        .hann => 0.5 - 0.5 * @cos(phase),
        .hamming => 0.54 - 0.46 * @cos(phase),
        .blackman => 0.42 - 0.5 * @cos(phase) + 0.08 * @cos(2.0 * phase),
        .blackman_harris => 0.35875 -
            0.48829 * @cos(phase) +
            0.14128 * @cos(2.0 * phase) -
            0.01168 * @cos(3.0 * phase),
        .flat_top => 0.21557895 -
            0.41663158 * @cos(phase) +
            0.277263158 * @cos(2.0 * phase) -
            0.083578947 * @cos(3.0 * phase) +
            0.006947368 * @cos(4.0 * phase),
    };
}

pub fn fillKaiser(
    comptime Sample: type,
    output: []Sample,
    beta: Sample,
    periodic: bool,
    normalization: Normalization,
) !void {
    validateSampleType(Sample);
    try validateKaiser(output.len, beta);
    const scale = try kaiserNormalizationScale(
        Sample,
        output.len,
        beta,
        periodic,
        normalization,
    );
    for (0..output.len) |index| {
        const value = kaiserCoefficient(Sample, output.len, index, beta, periodic) * scale;
        if (!std.math.isFinite(value)) return error.NonFiniteWindowOutput;
    }
    for (output, 0..) |*sample, index| {
        sample.* =
            kaiserCoefficient(Sample, output.len, index, beta, periodic) *
            scale;
    }
}

pub fn applyKaiser(
    comptime Sample: type,
    samples: []Sample,
    beta: Sample,
    periodic: bool,
    normalization: Normalization,
) !void {
    validateSampleType(Sample);
    try validateKaiser(samples.len, beta);
    for (samples) |sample| {
        if (!std.math.isFinite(sample)) return error.NonFiniteWindowInput;
    }
    const scale = try kaiserNormalizationScale(
        Sample,
        samples.len,
        beta,
        periodic,
        normalization,
    );
    for (samples, 0..) |sample, index| {
        const window_value =
            kaiserCoefficient(Sample, samples.len, index, beta, periodic) *
            scale;
        const value = sample * window_value;
        if (!std.math.isFinite(value)) return error.NonFiniteWindowOutput;
    }
    for (samples, 0..) |*sample, index| {
        sample.* *=
            kaiserCoefficient(Sample, samples.len, index, beta, periodic) *
            scale;
    }
}

pub fn kaiserCoefficient(
    comptime Sample: type,
    size: usize,
    index: usize,
    beta: Sample,
    periodic: bool,
) Sample {
    validateSampleType(Sample);
    if (size == 0 or index >= size or
        !std.math.isFinite(beta) or beta < 0.0)
        return 0.0;
    if (size == 1) return 1.0;
    const denominator = if (periodic)
        @as(Sample, @floatFromInt(size))
    else
        @as(Sample, @floatFromInt(size - 1));
    const ratio =
        2.0 * @as(Sample, @floatFromInt(index)) / denominator - 1.0;
    const radial = @sqrt(@max(0.0, 1.0 - ratio * ratio));
    const result = special_functions.besselI0(beta * radial) /
        special_functions.besselI0(beta);
    return if (std.math.isFinite(result)) result else 0.0;
}

fn normalizationScale(
    comptime Sample: type,
    size: usize,
    kind: Kind,
    periodic: bool,
    normalization: Normalization,
) !Sample {
    if (normalization == .none) return 1.0;
    var aggregate: Sample = 0.0;
    for (0..size) |index| {
        const value = coefficient(Sample, size, index, kind, periodic);
        aggregate = if (normalization == .unit_sum)
            aggregate + value
        else
            @max(aggregate, value);
    }
    if (!std.math.isFinite(aggregate) or aggregate <= 0.0)
        return error.InvalidWindowNormalization;
    const scale = 1.0 / aggregate;
    if (!std.math.isFinite(scale))
        return error.InvalidWindowNormalization;
    return scale;
}

fn kaiserNormalizationScale(
    comptime Sample: type,
    size: usize,
    beta: Sample,
    periodic: bool,
    normalization: Normalization,
) !Sample {
    if (normalization == .none) return 1.0;
    var aggregate: Sample = 0.0;
    for (0..size) |index| {
        const value =
            kaiserCoefficient(Sample, size, index, beta, periodic);
        aggregate = if (normalization == .unit_sum)
            aggregate + value
        else
            @max(aggregate, value);
    }
    if (!std.math.isFinite(aggregate) or aggregate <= 0.0)
        return error.InvalidWindowNormalization;
    const scale = 1.0 / aggregate;
    if (!std.math.isFinite(scale))
        return error.InvalidWindowNormalization;
    return scale;
}

fn validateKaiser(size: usize, beta: anytype) !void {
    if (size == 0) return error.EmptyWindow;
    if (!std.math.isFinite(beta) or beta < 0.0)
        return error.InvalidKaiserBeta;
}

fn validateSampleType(comptime Sample: type) void {
    if (Sample != f32 and Sample != f64)
        @compileError("window functions support f32 and f64 samples");
}

test "symmetric windows have expected endpoints and symmetry" {
    inline for (.{ Kind.hann, Kind.hamming, Kind.blackman, Kind.blackman_harris, Kind.flat_top }) |kind| {
        var values: [9]f64 = undefined;
        try fill(f64, &values, kind, false, .none);
        for (0..values.len) |index| {
            try std.testing.expectApproxEqAbs(
                values[index],
                values[values.len - 1 - index],
                0.000_000_000_001,
            );
        }
    }

    var hann: [9]f64 = undefined;
    try fill(f64, &hann, .hann, false, .none);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), hann[0], 0.000_000_000_001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), hann[4], 0.000_000_000_001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), hann[8], 0.000_000_000_001);
}

test "periodic windows do not duplicate their first sample" {
    var values: [8]f32 = undefined;
    try fill(f32, &values, .hann, true, .none);
    try std.testing.expectEqual(@as(f32, 0.0), values[0]);
    try std.testing.expect(values[values.len - 1] > 0.0);
}

test "Kaiser windows are symmetric and beta checked" {
    var values: [9]f64 = undefined;
    try fillKaiser(f64, &values, 8.0, false, .unit_peak);
    for (0..values.len) |index| {
        try std.testing.expectApproxEqAbs(
            values[index],
            values[values.len - 1 - index],
            0.000_000_000_001,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        values[values.len / 2],
        0.000_000_000_001,
    );
    try std.testing.expect(values[0] < 0.01);

    const retained = values;
    try std.testing.expectError(
        error.InvalidKaiserBeta,
        applyKaiser(f64, &values, -1.0, false, .none),
    );
    try std.testing.expectEqualSlices(f64, &retained, &values);
}

test "normalization and application are checked" {
    var sum_window: [7]f64 = undefined;
    try fill(f64, &sum_window, .blackman, false, .unit_sum);
    var sum: f64 = 0.0;
    for (sum_window) |value| sum += value;
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), sum, 0.000_000_000_001);

    var peak_window: [8]f32 = undefined;
    try fill(f32, &peak_window, .hann, true, .unit_peak);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), peak_window[4], 0.000_001);

    var samples = [_]f32{ 1.0, std.math.nan(f32), 1.0 };
    try std.testing.expectError(
        error.NonFiniteWindowInput,
        apply(f32, &samples, .hann, false, .none),
    );
    try std.testing.expectEqual(@as(f32, 1.0), samples[0]);
    try std.testing.expect(std.math.isNan(samples[1]));
}

test "window application rejects non-finite output transactionally" {
    var samples: [5]f64 = @splat(std.math.floatMax(f64));
    const retained = samples;
    try std.testing.expectError(
        error.NonFiniteWindowOutput,
        apply(f64, &samples, .flat_top, false, .unit_sum),
    );
    try std.testing.expectEqualSlices(f64, &retained, &samples);
}
