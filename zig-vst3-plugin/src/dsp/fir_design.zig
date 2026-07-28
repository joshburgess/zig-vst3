const std = @import("std");
const window = @import("window.zig");

pub const maximum_least_squares_taps = 255;

pub const LeastSquaresBand = struct {
    lower_frequency: f64,
    upper_frequency: f64,
    lower_gain: f64,
    upper_gain: f64,
    weight: f64 = 1.0,

    pub fn validate(self: LeastSquaresBand) !void {
        if (!std.math.isFinite(self.lower_frequency) or
            !std.math.isFinite(self.upper_frequency) or
            self.lower_frequency < 0.0 or
            self.upper_frequency > 0.5 or
            self.lower_frequency >= self.upper_frequency or
            !std.math.isFinite(self.lower_gain) or
            !std.math.isFinite(self.upper_gain) or
            !std.math.isFinite(self.weight) or
            self.weight <= 0.0)
            return error.InvalidLeastSquaresBand;
    }
};

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("FIR design supports f32 and f64 coefficients");

    return struct {
        pub fn lowPass(
            output: []Sample,
            cutoff: Sample,
            window_kind: window.Kind,
        ) !void {
            try validate(output, cutoff, null);
            designLowPass(output, cutoff, window_kind);
            try normalizeAt(output, 0.0);
        }

        pub fn highPass(
            output: []Sample,
            cutoff: Sample,
            window_kind: window.Kind,
        ) !void {
            try validate(output, cutoff, null);
            designLowPass(output, cutoff, window_kind);
            spectralInvert(output);
            try normalizeAt(output, 0.5);
        }

        pub fn bandPass(
            output: []Sample,
            lower_cutoff: Sample,
            upper_cutoff: Sample,
            window_kind: window.Kind,
        ) !void {
            try validate(output, lower_cutoff, upper_cutoff);
            designBandPass(output, lower_cutoff, upper_cutoff, window_kind);
            try normalizeAt(output, (lower_cutoff + upper_cutoff) * 0.5);
        }

        pub fn bandStop(
            output: []Sample,
            lower_cutoff: Sample,
            upper_cutoff: Sample,
            window_kind: window.Kind,
        ) !void {
            try validate(output, lower_cutoff, upper_cutoff);
            designBandPass(output, lower_cutoff, upper_cutoff, window_kind);
            spectralInvert(output);
            try normalizeAt(output, 0.0);
        }

        pub fn leastSquares(
            output: []Sample,
            bands: []const LeastSquaresBand,
            grid_density: usize,
        ) !void {
            if (output.len < 3 or
                output.len % 2 == 0 or
                output.len > maximum_least_squares_taps)
                return error.InvalidFirDesignLength;
            if (bands.len == 0 or grid_density < 4 or grid_density > 1_024)
                return error.InvalidLeastSquaresDesign;
            for (bands, 0..) |band, index| {
                try band.validate();
                if (index > 0 and
                    band.lower_frequency < bands[index - 1].upper_frequency)
                    return error.OverlappingLeastSquaresBands;
            }

            const basis_count = output.len / 2 + 1;
            var triangular: [maximum_least_squares_taps / 2 + 1][maximum_least_squares_taps / 2 + 1]f64 = undefined;
            var transformed_rhs: [maximum_least_squares_taps / 2 + 1]f64 =
                @splat(0.0);
            for (triangular[0..basis_count]) |*row|
                @memset(row[0..basis_count], 0.0);

            for (bands) |band| {
                const points = @max(grid_density * basis_count, 8);
                const scale = @sqrt(
                    band.weight *
                        (band.upper_frequency - band.lower_frequency),
                );
                for (0..points) |point| {
                    const unit =
                        (@as(f64, @floatFromInt(point)) + 0.5) /
                        @as(f64, @floatFromInt(points));
                    const frequency = band.lower_frequency +
                        (band.upper_frequency - band.lower_frequency) * unit;
                    const desired = band.lower_gain +
                        (band.upper_gain - band.lower_gain) * unit;
                    var row: [maximum_least_squares_taps / 2 + 1]f64 =
                        undefined;
                    row[0] = scale;
                    for (1..basis_count) |index| {
                        row[index] = scale * @cos(
                            std.math.tau *
                                frequency *
                                @as(f64, @floatFromInt(index)),
                        );
                    }
                    try updateQr(
                        triangular[0..basis_count],
                        transformed_rhs[0..basis_count],
                        row[0..basis_count],
                        scale * desired,
                    );
                }
            }

            try solveUpperTriangular(
                triangular[0..basis_count],
                transformed_rhs[0..basis_count],
            );
            var replacement: [maximum_least_squares_taps]Sample = undefined;
            const center = output.len / 2;
            replacement[center] =
                try checkedCoefficient(transformed_rhs[0]);
            for (1..basis_count) |index| {
                const coefficient = try checkedCoefficient(
                    transformed_rhs[index] * 0.5,
                );
                replacement[center - index] = coefficient;
                replacement[center + index] = coefficient;
            }
            @memcpy(output, replacement[0..output.len]);
        }

        pub fn magnitude(
            coefficients: []const Sample,
            frequency: Sample,
        ) Sample {
            if (coefficients.len == 0 or
                !std.math.isFinite(frequency) or
                frequency < 0.0 or
                frequency > 0.5)
                return 0.0;
            var real: Sample = 0.0;
            var imaginary: Sample = 0.0;
            for (coefficients, 0..) |coefficient_value, index| {
                if (!std.math.isFinite(coefficient_value)) return 0.0;
                const phase = -std.math.tau *
                    frequency *
                    @as(Sample, @floatFromInt(index));
                real += coefficient_value * @cos(phase);
                imaginary += coefficient_value * @sin(phase);
            }
            const result = @sqrt(real * real + imaginary * imaginary);
            return if (std.math.isFinite(result)) result else 0.0;
        }

        fn validate(
            output: []const Sample,
            lower_cutoff: Sample,
            upper_cutoff: ?Sample,
        ) !void {
            if (output.len < 3 or output.len % 2 == 0)
                return error.InvalidFirDesignLength;
            if (!validCutoff(lower_cutoff))
                return error.InvalidFirDesignCutoff;
            if (upper_cutoff) |upper| {
                if (!validCutoff(upper) or lower_cutoff >= upper)
                    return error.InvalidFirDesignCutoff;
            }
        }

        fn validCutoff(cutoff: Sample) bool {
            return std.math.isFinite(cutoff) and
                cutoff > 0.0 and
                cutoff < 0.5;
        }

        fn designLowPass(
            output: []Sample,
            cutoff: Sample,
            window_kind: window.Kind,
        ) void {
            const center = output.len / 2;
            for (output, 0..) |*coefficient_value, index| {
                const offset =
                    @as(Sample, @floatFromInt(index)) -
                    @as(Sample, @floatFromInt(center));
                coefficient_value.* =
                    2.0 * cutoff * sinc(2.0 * cutoff * offset) *
                    window.coefficient(
                        Sample,
                        output.len,
                        index,
                        window_kind,
                        false,
                    );
            }
        }

        fn designBandPass(
            output: []Sample,
            lower_cutoff: Sample,
            upper_cutoff: Sample,
            window_kind: window.Kind,
        ) void {
            const center = output.len / 2;
            for (output, 0..) |*coefficient_value, index| {
                const offset =
                    @as(Sample, @floatFromInt(index)) -
                    @as(Sample, @floatFromInt(center));
                const high =
                    2.0 * upper_cutoff *
                    sinc(2.0 * upper_cutoff * offset);
                const low =
                    2.0 * lower_cutoff *
                    sinc(2.0 * lower_cutoff * offset);
                coefficient_value.* =
                    (high - low) *
                    window.coefficient(
                        Sample,
                        output.len,
                        index,
                        window_kind,
                        false,
                    );
            }
        }

        fn spectralInvert(output: []Sample) void {
            for (output) |*coefficient_value|
                coefficient_value.* = -coefficient_value.*;
            output[output.len / 2] += 1.0;
        }

        fn normalizeAt(output: []Sample, frequency: Sample) !void {
            const gain = magnitude(output, frequency);
            if (!std.math.isFinite(gain) or gain <= 0.0)
                return error.InvalidFirDesignGain;
            const inverse_gain = 1.0 / gain;
            for (output) |*coefficient_value|
                coefficient_value.* *= inverse_gain;
        }

        fn sinc(value: Sample) Sample {
            if (@abs(value) < std.math.floatEps(Sample)) return 1.0;
            const angle = std.math.pi * value;
            return @sin(angle) / angle;
        }

        fn checkedCoefficient(value: f64) !Sample {
            const coefficient: Sample = @floatCast(value);
            if (!std.math.isFinite(coefficient))
                return error.InvalidLeastSquaresSolution;
            return coefficient;
        }

        fn updateQr(
            matrix: [][
                maximum_least_squares_taps / 2 + 1
            ]f64,
            transformed_rhs: []f64,
            row: []f64,
            right_hand_side: f64,
        ) !void {
            var residual = right_hand_side;
            for (0..row.len) |column| {
                const diagonal = matrix[column][column];
                const norm = std.math.hypot(diagonal, row[column]);
                if (!std.math.isFinite(norm))
                    return error.InvalidLeastSquaresSolution;
                if (norm <= std.math.floatEps(f64)) continue;
                const cosine = diagonal / norm;
                const sine = row[column] / norm;
                matrix[column][column] = norm;
                for (column + 1..row.len) |remaining| {
                    const upper = matrix[column][remaining];
                    const incoming = row[remaining];
                    matrix[column][remaining] =
                        cosine * upper + sine * incoming;
                    row[remaining] =
                        -sine * upper + cosine * incoming;
                    if (!std.math.isFinite(matrix[column][remaining]) or
                        !std.math.isFinite(row[remaining]))
                        return error.InvalidLeastSquaresSolution;
                }
                const existing_rhs = transformed_rhs[column];
                transformed_rhs[column] =
                    cosine * existing_rhs + sine * residual;
                residual =
                    -sine * existing_rhs + cosine * residual;
                if (!std.math.isFinite(transformed_rhs[column]) or
                    !std.math.isFinite(residual))
                    return error.InvalidLeastSquaresSolution;
            }
        }

        fn solveUpperTriangular(
            matrix: [][
                maximum_least_squares_taps / 2 + 1
            ]f64,
            rhs: []f64,
        ) !void {
            var row_index = rhs.len;
            while (row_index > 0) {
                row_index -= 1;
                var value = rhs[row_index];
                for (row_index + 1..rhs.len) |column|
                    value -= matrix[row_index][column] * rhs[column];
                const diagonal = matrix[row_index][row_index];
                if (!std.math.isFinite(diagonal) or diagonal <= 1.0e-12)
                    return error.SingularLeastSquaresDesign;
                const solution = value / diagonal;
                if (!std.math.isFinite(solution))
                    return error.InvalidLeastSquaresSolution;
                rhs[row_index] = solution;
            }
        }
    };
}

test "low-pass design is symmetric with unity DC gain" {
    const FirDesigner = Designer(f64);
    var coefficients: [31]f64 = undefined;
    try FirDesigner.lowPass(&coefficients, 0.125, .blackman);
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            coefficients[coefficients.len - 1 - index],
            0.000_000_000_001,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        FirDesigner.magnitude(&coefficients, 0.0),
        0.000_000_000_001,
    );
    try std.testing.expect(
        FirDesigner.magnitude(&coefficients, 0.4) < 0.001,
    );
}

test "high-pass and band designs normalize their pass bands" {
    const FirDesigner = Designer(f64);
    var high_pass: [63]f64 = undefined;
    try FirDesigner.highPass(&high_pass, 0.2, .blackman_harris);
    try std.testing.expect(FirDesigner.magnitude(&high_pass, 0.0) < 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        FirDesigner.magnitude(&high_pass, 0.5),
        0.000_000_001,
    );

    var band_pass: [63]f64 = undefined;
    try FirDesigner.bandPass(&band_pass, 0.1, 0.2, .blackman);
    try std.testing.expect(FirDesigner.magnitude(&band_pass, 0.0) < 0.001);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        FirDesigner.magnitude(&band_pass, 0.15),
        0.000_000_001,
    );

    var band_stop: [63]f64 = undefined;
    try FirDesigner.bandStop(&band_stop, 0.1, 0.2, .blackman);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        FirDesigner.magnitude(&band_stop, 0.0),
        0.000_000_001,
    );
    try std.testing.expect(FirDesigner.magnitude(&band_stop, 0.15) < 0.01);
}

test "invalid FIR designs leave output unchanged" {
    const FirDesigner = Designer(f32);
    var coefficients: [5]f32 = @splat(2.0);
    try std.testing.expectError(
        error.InvalidFirDesignCutoff,
        FirDesigner.lowPass(&coefficients, 0.5, .hann),
    );
    try std.testing.expectEqual(@as(f32, 2.0), coefficients[0]);
    try std.testing.expectError(
        error.InvalidFirDesignLength,
        FirDesigner.bandPass(coefficients[0..4], 0.1, 0.2, .hann),
    );
    try std.testing.expectEqual(@as(f32, 2.0), coefficients[0]);
}

test "least-squares FIR design fits weighted low-pass bands" {
    const FirDesigner = Designer(f64);
    var coefficients: [63]f64 = undefined;
    try FirDesigner.leastSquares(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.18,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            .{
                .lower_frequency = 0.25,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 4.0,
            },
        },
        16,
    );
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            coefficients[coefficients.len - 1 - index],
            0.000_000_000_001,
        );
    }
    for (0..65) |point| {
        const pass_frequency =
            0.18 * @as(f64, @floatFromInt(point)) / 64.0;
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            FirDesigner.magnitude(&coefficients, pass_frequency),
            0.01,
        );
        const stop_frequency =
            0.25 + 0.25 * @as(f64, @floatFromInt(point)) / 64.0;
        try std.testing.expect(
            FirDesigner.magnitude(&coefficients, stop_frequency) < 0.01,
        );
    }
}

test "least-squares FIR response matches SciPy 1.17" {
    const FirDesigner = Designer(f64);
    var coefficients: [63]f64 = undefined;
    try FirDesigner.leastSquares(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.18,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            .{
                .lower_frequency = 0.25,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 4.0,
            },
        },
        1_024,
    );
    const frequencies = [_]f64{
        0.0,  0.03, 0.06, 0.09, 0.12, 0.15, 0.18,
        0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
    };
    const magnitudes = [_]f64{
        1.0000612598004606,
        1.0000594673266443,
        1.0000547869455265,
        1.0000502016409398,
        1.000056518094891,
        1.0001262071636152,
        0.9990411276177775,
        0.000528992680320055,
        7.176258619254861e-05,
        3.304905901514796e-05,
        6.976599670155086e-06,
        2.989820695185463e-05,
        3.72892088620874e-05,
    };
    for (frequencies, magnitudes) |frequency, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            FirDesigner.magnitude(&coefficients, frequency),
            2.0e-9,
        );
    }
}

test "least-squares FIR validation is transactional" {
    const FirDesigner = Designer(f32);
    var coefficients: [7]f32 = @splat(2.0);
    try std.testing.expectError(
        error.OverlappingLeastSquaresBands,
        FirDesigner.leastSquares(
            &coefficients,
            &.{
                .{
                    .lower_frequency = 0.0,
                    .upper_frequency = 0.3,
                    .lower_gain = 1.0,
                    .upper_gain = 1.0,
                },
                .{
                    .lower_frequency = 0.2,
                    .upper_frequency = 0.5,
                    .lower_gain = 0.0,
                    .upper_gain = 0.0,
                },
            },
            8,
        ),
    );
    try std.testing.expectEqual([_]f32{2.0} ** 7, coefficients);
}

test "least-squares FIR remains finite at its maximum tap count" {
    const FirDesigner = Designer(f32);
    var coefficients: [maximum_least_squares_taps]f32 = undefined;
    try FirDesigner.leastSquares(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.1,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            .{
                .lower_frequency = 0.15,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 8.0,
            },
        },
        4,
    );
    for (coefficients) |coefficient|
        try std.testing.expect(std.math.isFinite(coefficient));
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        FirDesigner.magnitude(&coefficients, 0.05),
        0.002,
    );
    try std.testing.expect(
        FirDesigner.magnitude(&coefficients, 0.3) < 0.002,
    );
}
