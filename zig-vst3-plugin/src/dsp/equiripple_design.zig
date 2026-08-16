const std = @import("std");
const fir_design = @import("fir_design.zig");

pub const maximum_taps = 255;
pub const maximum_bands = 8;
pub const maximum_grid_density = 64;
const maximum_basis = maximum_taps / 2 + 1;
const maximum_extrema = maximum_basis + 1;
const maximum_grid_points =
    (maximum_taps + 1) * maximum_grid_density + 2 * maximum_bands;

pub const Band = fir_design.LeastSquaresBand;

pub const Symmetry = enum {
    even,
    odd,
};

const LinearPhaseType = enum {
    type_i,
    type_ii,
    type_iii,
    type_iv,

    fn forDesign(tap_count: usize, symmetry: Symmetry) LinearPhaseType {
        return switch (symmetry) {
            .even => if (tap_count % 2 == 1) .type_i else .type_ii,
            .odd => if (tap_count % 2 == 1) .type_iii else .type_iv,
        };
    }

    fn basisCount(self: LinearPhaseType, tap_count: usize) usize {
        return switch (self) {
            .type_i => tap_count / 2 + 1,
            .type_ii, .type_iii, .type_iv => tap_count / 2,
        };
    }

    fn forcesDcZero(self: LinearPhaseType) bool {
        return self == .type_iii or self == .type_iv;
    }

    fn forcesNyquistZero(self: LinearPhaseType) bool {
        return self == .type_ii or self == .type_iii;
    }
};

pub const Options = struct {
    grid_density: usize = 16,
    maximum_iterations: usize = 64,
    convergence_tolerance: f64 = 1.0e-7,

    pub fn validate(self: Options) !void {
        if (self.grid_density < 8 or
            self.grid_density > maximum_grid_density or
            self.maximum_iterations == 0 or
            self.maximum_iterations > 256 or
            !std.math.isFinite(self.convergence_tolerance) or
            self.convergence_tolerance <= 0.0 or
            self.convergence_tolerance > 0.01)
            return error.InvalidEquirippleOptions;
    }
};

pub const Report = struct {
    iterations: usize,
    weighted_ripple: f64,
    extremum_count: usize,
};

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("equiripple FIR design supports f32 and f64 coefficients");

    return struct {
        const Self = @This();

        pub fn design(
            output: []Sample,
            bands: []const Band,
            options: Options,
        ) !Report {
            return designWithSymmetry(output, bands, .even, options);
        }

        pub fn designWithSymmetry(
            output: []Sample,
            bands: []const Band,
            symmetry: Symmetry,
            options: Options,
        ) !Report {
            const linear_phase_type =
                LinearPhaseType.forDesign(output.len, symmetry);
            try validateRequest(
                output,
                bands,
                linear_phase_type,
                options,
            );

            const basis_count =
                linear_phase_type.basisCount(output.len);
            const extremum_count = basis_count + 1;
            var frequencies: [maximum_grid_points]f64 = undefined;
            var desired: [maximum_grid_points]f64 = undefined;
            var weights: [maximum_grid_points]f64 = undefined;
            var band_starts: [maximum_bands]usize = undefined;
            var band_ends: [maximum_bands]usize = undefined;
            const grid_count = buildGrid(
                bands,
                output.len,
                options.grid_density,
                linear_phase_type,
                &frequencies,
                &desired,
                &weights,
                &band_starts,
                &band_ends,
            );
            if (grid_count < extremum_count)
                return error.EquirippleGridTooSmall;

            var extrema: [maximum_extrema]usize = undefined;
            for (0..extremum_count) |index| {
                extrema[index] = @intFromFloat(@round(
                    @as(f64, @floatFromInt(index)) *
                        @as(f64, @floatFromInt(grid_count - 1)) /
                        @as(f64, @floatFromInt(extremum_count - 1)),
                ));
            }

            var basis_coefficients: [maximum_basis]f64 = undefined;
            var errors: [maximum_grid_points]f64 = undefined;
            var candidates: [maximum_grid_points]usize = undefined;
            var next_extrema: [maximum_extrema]usize = undefined;
            var ripple: f64 = 0.0;

            for (0..options.maximum_iterations) |iteration| {
                ripple = try solveExchange(
                    frequencies[0..grid_count],
                    desired[0..grid_count],
                    weights[0..grid_count],
                    extrema[0..extremum_count],
                    basis_coefficients[0..basis_count],
                    linear_phase_type,
                );
                evaluateErrors(
                    frequencies[0..grid_count],
                    desired[0..grid_count],
                    weights[0..grid_count],
                    basis_coefficients[0..basis_count],
                    linear_phase_type,
                    errors[0..grid_count],
                );
                const candidate_count = findAlternatingExtrema(
                    errors[0..grid_count],
                    band_starts[0..bands.len],
                    band_ends[0..bands.len],
                    &candidates,
                );
                if (candidate_count < extremum_count)
                    return error.EquirippleExchangeFailed;
                chooseExtrema(
                    errors[0..grid_count],
                    candidates[0..candidate_count],
                    next_extrema[0..extremum_count],
                );

                const stable = std.mem.eql(
                    usize,
                    extrema[0..extremum_count],
                    next_extrema[0..extremum_count],
                );
                const spread = extremalSpread(
                    errors[0..grid_count],
                    next_extrema[0..extremum_count],
                );
                if (stable or spread <= options.convergence_tolerance) {
                    if (!stable) {
                        @memcpy(
                            extrema[0..extremum_count],
                            next_extrema[0..extremum_count],
                        );
                        ripple = try solveExchange(
                            frequencies[0..grid_count],
                            desired[0..grid_count],
                            weights[0..grid_count],
                            extrema[0..extremum_count],
                            basis_coefficients[0..basis_count],
                            linear_phase_type,
                        );
                    }
                    try publish(
                        output,
                        basis_coefficients[0..basis_count],
                        linear_phase_type,
                    );
                    return .{
                        .iterations = iteration + 1,
                        .weighted_ripple = ripple,
                        .extremum_count = extremum_count,
                    };
                }
                @memcpy(
                    extrema[0..extremum_count],
                    next_extrema[0..extremum_count],
                );
            }
            return error.EquirippleDidNotConverge;
        }

        fn validateRequest(
            output: []const Sample,
            bands: []const Band,
            linear_phase_type: LinearPhaseType,
            options: Options,
        ) !void {
            try options.validate();
            if (output.len < 2 or output.len > maximum_taps)
                return error.InvalidEquirippleLength;
            if (bands.len == 0 or bands.len > maximum_bands)
                return error.InvalidEquirippleBands;
            for (bands, 0..) |band, index| {
                try band.validate();
                if (index > 0 and
                    band.lower_frequency <= bands[index - 1].upper_frequency)
                    return error.InvalidEquirippleBands;
                if ((linear_phase_type.forcesDcZero() and
                    band.lower_frequency == 0.0 and
                    band.lower_gain != 0.0) or
                    (linear_phase_type.forcesNyquistZero() and
                        band.upper_frequency == 0.5 and
                        band.upper_gain != 0.0))
                    return error.IncompatibleEquirippleEndpoint;
            }
        }

        fn publish(
            output: []Sample,
            basis_coefficients: []const f64,
            linear_phase_type: LinearPhaseType,
        ) !void {
            var replacement: [maximum_taps]Sample = undefined;
            const center = output.len / 2;
            switch (linear_phase_type) {
                .type_i => {
                    replacement[center] =
                        try checkedCoefficient(basis_coefficients[0]);
                    for (1..basis_coefficients.len) |index| {
                        const coefficient = try checkedCoefficient(
                            basis_coefficients[index] * 0.5,
                        );
                        replacement[center - index] = coefficient;
                        replacement[center + index] = coefficient;
                    }
                },
                .type_ii => {
                    for (basis_coefficients, 0..) |value, index| {
                        const coefficient =
                            try checkedCoefficient(value * 0.5);
                        replacement[center - 1 - index] = coefficient;
                        replacement[center + index] = coefficient;
                    }
                },
                .type_iii => {
                    replacement[center] = 0.0;
                    for (basis_coefficients, 0..) |value, index| {
                        const coefficient =
                            try checkedCoefficient(value * 0.5);
                        replacement[center - 1 - index] = coefficient;
                        replacement[center + 1 + index] = -coefficient;
                    }
                },
                .type_iv => {
                    for (basis_coefficients, 0..) |value, index| {
                        const coefficient =
                            try checkedCoefficient(value * 0.5);
                        replacement[center - 1 - index] = coefficient;
                        replacement[center + index] = -coefficient;
                    }
                },
            }
            @memcpy(output, replacement[0..output.len]);
        }

        fn checkedCoefficient(value: f64) !Sample {
            const coefficient: Sample = @floatCast(value);
            if (!std.math.isFinite(coefficient))
                return error.InvalidEquirippleSolution;
            return coefficient;
        }
    };
}

fn buildGrid(
    bands: []const Band,
    tap_count: usize,
    grid_density: usize,
    linear_phase_type: LinearPhaseType,
    frequencies: []f64,
    desired: []f64,
    weights: []f64,
    band_starts: []usize,
    band_ends: []usize,
) usize {
    var total_width: f64 = 0.0;
    for (bands) |band|
        total_width += band.upper_frequency - band.lower_frequency;
    const target_points = (tap_count + 1) * grid_density;
    var grid_count: usize = 0;
    for (bands, 0..) |band, band_index| {
        const proportional =
            @as(f64, @floatFromInt(target_points)) *
            (band.upper_frequency - band.lower_frequency) /
            total_width;
        const point_count = @max(
            @as(usize, 2),
            @as(usize, @intFromFloat(@round(proportional))),
        );
        const omit_lower =
            linear_phase_type.forcesDcZero() and
            band.lower_frequency == 0.0;
        const omit_upper =
            linear_phase_type.forcesNyquistZero() and
            band.upper_frequency == 0.5;
        const raw_point_count =
            point_count +
            @intFromBool(omit_lower) +
            @intFromBool(omit_upper);
        band_starts[band_index] = grid_count;
        for (0..raw_point_count) |point| {
            const unit = @as(f64, @floatFromInt(point)) /
                @as(f64, @floatFromInt(raw_point_count - 1));
            if ((omit_lower and point == 0) or
                (omit_upper and point + 1 == raw_point_count))
                continue;
            frequencies[grid_count] = band.lower_frequency +
                (band.upper_frequency - band.lower_frequency) * unit;
            desired[grid_count] = band.lower_gain +
                (band.upper_gain - band.lower_gain) * unit;
            weights[grid_count] = band.weight;
            grid_count += 1;
        }
        band_ends[band_index] = grid_count - 1;
    }
    return grid_count;
}

fn solveExchange(
    frequencies: []const f64,
    desired: []const f64,
    weights: []const f64,
    extrema: []const usize,
    coefficients: []f64,
    linear_phase_type: LinearPhaseType,
) !f64 {
    var augmented: [maximum_extrema][maximum_extrema + 1]f64 =
        undefined;
    const unknown_count = coefficients.len + 1;
    for (extrema, 0..) |grid_index, row| {
        for (0..coefficients.len) |column| {
            augmented[row][column] = basisValue(
                linear_phase_type,
                column,
                frequencies[grid_index],
            );
        }
        const sign: f64 = if (row % 2 == 0) 1.0 else -1.0;
        augmented[row][coefficients.len] =
            sign / weights[grid_index];
        augmented[row][unknown_count] = desired[grid_index];
    }

    for (0..unknown_count) |column| {
        var pivot_row = column;
        var pivot_magnitude = @abs(augmented[column][column]);
        for (column + 1..unknown_count) |candidate| {
            const candidate_magnitude =
                @abs(augmented[candidate][column]);
            if (candidate_magnitude > pivot_magnitude) {
                pivot_magnitude = candidate_magnitude;
                pivot_row = candidate;
            }
        }
        if (!std.math.isFinite(pivot_magnitude) or
            pivot_magnitude <= 1.0e-13)
            return error.SingularEquirippleExchange;
        if (pivot_row != column) {
            std.mem.swap(
                [maximum_extrema + 1]f64,
                &augmented[pivot_row],
                &augmented[column],
            );
        }
        const pivot = augmented[column][column];
        for (column + 1..unknown_count) |row| {
            const factor = augmented[row][column] / pivot;
            augmented[row][column] = 0.0;
            for (column + 1..unknown_count + 1) |remaining|
                augmented[row][remaining] -=
                    factor * augmented[column][remaining];
        }
    }

    var solution: [maximum_extrema]f64 = undefined;
    var row_index = unknown_count;
    while (row_index > 0) {
        row_index -= 1;
        var value = augmented[row_index][unknown_count];
        for (row_index + 1..unknown_count) |column|
            value -= augmented[row_index][column] * solution[column];
        const result = value / augmented[row_index][row_index];
        if (!std.math.isFinite(result))
            return error.InvalidEquirippleSolution;
        solution[row_index] = result;
    }
    @memcpy(coefficients, solution[0..coefficients.len]);
    return @abs(solution[coefficients.len]);
}

fn evaluateErrors(
    frequencies: []const f64,
    desired: []const f64,
    weights: []const f64,
    coefficients: []const f64,
    linear_phase_type: LinearPhaseType,
    errors: []f64,
) void {
    for (frequencies, 0..) |frequency, grid_index| {
        var response: f64 = 0.0;
        for (coefficients, 0..) |coefficient, basis_index| {
            response += coefficient * basisValue(
                linear_phase_type,
                basis_index,
                frequency,
            );
        }
        errors[grid_index] =
            (response - desired[grid_index]) * weights[grid_index];
    }
}

fn basisValue(
    linear_phase_type: LinearPhaseType,
    index: usize,
    frequency: f64,
) f64 {
    const basis_index: f64 = switch (linear_phase_type) {
        .type_i => @floatFromInt(index),
        .type_ii, .type_iv => @as(f64, @floatFromInt(index)) + 0.5,
        .type_iii => @as(f64, @floatFromInt(index)) + 1.0,
    };
    const angle = std.math.tau * frequency * basis_index;
    return switch (linear_phase_type) {
        .type_i, .type_ii => @cos(angle),
        .type_iii, .type_iv => @sin(angle),
    };
}

fn findAlternatingExtrema(
    errors: []const f64,
    band_starts: []const usize,
    band_ends: []const usize,
    candidates: []usize,
) usize {
    var raw: [maximum_grid_points]usize = undefined;
    var raw_count: usize = 0;
    for (band_starts, band_ends) |start, end| {
        raw[raw_count] = start;
        raw_count += 1;
        if (end > start + 1) {
            for (start + 1..end) |index| {
                const magnitude = @abs(errors[index]);
                if (magnitude >= @abs(errors[index - 1]) and
                    magnitude >= @abs(errors[index + 1]) and
                    (magnitude > @abs(errors[index - 1]) or
                        magnitude > @abs(errors[index + 1])))
                {
                    raw[raw_count] = index;
                    raw_count += 1;
                }
            }
        }
        if (end != start) {
            raw[raw_count] = end;
            raw_count += 1;
        }
    }

    var count: usize = 0;
    for (raw[0..raw_count]) |index| {
        if (count == 0) {
            candidates[count] = index;
            count += 1;
            continue;
        }
        const previous = candidates[count - 1];
        if (sameSign(errors[previous], errors[index])) {
            if (@abs(errors[index]) > @abs(errors[previous]))
                candidates[count - 1] = index;
        } else {
            candidates[count] = index;
            count += 1;
        }
    }
    return count;
}

fn sameSign(left: f64, right: f64) bool {
    return (left >= 0.0) == (right >= 0.0);
}

fn chooseExtrema(
    errors: []const f64,
    candidates: []const usize,
    output: []usize,
) void {
    var best_start: usize = 0;
    var best_minimum: f64 = -1.0;
    var best_sum: f64 = -1.0;
    for (0..candidates.len - output.len + 1) |start| {
        var minimum = std.math.inf(f64);
        var sum: f64 = 0.0;
        for (candidates[start..][0..output.len]) |index| {
            const magnitude = @abs(errors[index]);
            minimum = @min(minimum, magnitude);
            sum += magnitude;
        }
        if (minimum > best_minimum or
            (minimum == best_minimum and sum > best_sum))
        {
            best_start = start;
            best_minimum = minimum;
            best_sum = sum;
        }
    }
    @memcpy(output, candidates[best_start..][0..output.len]);
}

fn extremalSpread(errors: []const f64, extrema: []const usize) f64 {
    var minimum = std.math.inf(f64);
    var maximum: f64 = 0.0;
    for (extrema) |index| {
        const magnitude = @abs(errors[index]);
        minimum = @min(minimum, magnitude);
        maximum = @max(maximum, magnitude);
    }
    if (maximum <= 0.0 or !std.math.isFinite(maximum))
        return std.math.inf(f64);
    return (maximum - minimum) / maximum;
}

test "equiripple low-pass has alternating weighted ripple" {
    const Equiripple = Designer(f64);
    var coefficients: [31]f64 = undefined;
    const report = try Equiripple.design(
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
        .{ .grid_density = 32 },
    );
    try std.testing.expect(report.iterations <= 64);
    try std.testing.expectEqual(@as(usize, 17), report.extremum_count);
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            coefficients[coefficients.len - 1 - index],
            0.000_000_000_001,
        );
    }

    var maximum_pass_error: f64 = 0.0;
    var maximum_stop_error: f64 = 0.0;
    for (0..4_097) |point| {
        const unit = @as(f64, @floatFromInt(point)) / 4_096.0;
        maximum_pass_error = @max(
            maximum_pass_error,
            @abs(
                fir_design.Designer(f64).magnitude(
                    &coefficients,
                    0.18 * unit,
                ) - 1.0,
            ),
        );
        maximum_stop_error = @max(
            maximum_stop_error,
            fir_design.Designer(f64).magnitude(
                &coefficients,
                0.25 + 0.25 * unit,
            ),
        );
    }
    try std.testing.expect(maximum_pass_error < 0.02);
    try std.testing.expect(maximum_stop_error < 0.005);
    try std.testing.expectApproxEqRel(
        maximum_pass_error,
        maximum_stop_error * 4.0,
        0.03,
    );
}

test "equiripple designs high-pass and multiband responses" {
    const Equiripple = Designer(f32);
    var high_pass: [63]f32 = undefined;
    _ = try Equiripple.design(
        &high_pass,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.15,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 2.0,
            },
            .{
                .lower_frequency = 0.22,
                .upper_frequency = 0.5,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
        },
        .{},
    );
    try std.testing.expect(
        fir_design.Designer(f32).magnitude(&high_pass, 0.05) < 0.001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        fir_design.Designer(f32).magnitude(&high_pass, 0.35),
        0.001,
    );

    var multiband: [63]f32 = undefined;
    _ = try Equiripple.design(
        &multiband,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.08,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            .{
                .lower_frequency = 0.14,
                .upper_frequency = 0.22,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
            },
            .{
                .lower_frequency = 0.28,
                .upper_frequency = 0.5,
                .lower_gain = 0.5,
                .upper_gain = 0.5,
            },
        },
        .{},
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        fir_design.Designer(f32).magnitude(&multiband, 0.04),
        0.002,
    );
    try std.testing.expect(
        fir_design.Designer(f32).magnitude(&multiband, 0.18) < 0.002,
    );
    try std.testing.expectApproxEqAbs(
        @as(f32, 0.5),
        fir_design.Designer(f32).magnitude(&multiband, 0.4),
        0.002,
    );
}

test "type II equiripple supports even-length symmetric filters" {
    const Equiripple = Designer(f64);
    var coefficients: [32]f64 = undefined;
    const report = try Equiripple.design(
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
        .{ .grid_density = 32 },
    );
    try std.testing.expectEqual(@as(usize, 17), report.extremum_count);
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            coefficients[coefficients.len - 1 - index],
            1.0e-12,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        fir_design.Designer(f64).magnitude(&coefficients, 0.5),
        1.0e-12,
    );

    var maximum_pass_error: f64 = 0.0;
    var maximum_stop_error: f64 = 0.0;
    for (0..4_097) |point| {
        const unit = @as(f64, @floatFromInt(point)) / 4_096.0;
        maximum_pass_error = @max(
            maximum_pass_error,
            @abs(
                fir_design.Designer(f64).magnitude(
                    &coefficients,
                    0.18 * unit,
                ) - 1.0,
            ),
        );
        maximum_stop_error = @max(
            maximum_stop_error,
            fir_design.Designer(f64).magnitude(
                &coefficients,
                0.25 + 0.25 * unit,
            ),
        );
    }
    try std.testing.expect(maximum_pass_error < 0.025);
    try std.testing.expect(maximum_stop_error < 0.006_5);
}

test "type III equiripple supports odd-length antisymmetric filters" {
    const Equiripple = Designer(f64);
    var coefficients: [31]f64 = undefined;
    _ = try Equiripple.designWithSymmetry(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.05,
                .upper_frequency = 0.45,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
        },
        .odd,
        .{ .grid_density = 32 },
    );
    try std.testing.expectEqual(@as(f64, 0.0), coefficients[15]);
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            -coefficients[coefficients.len - 1 - index],
            1.0e-12,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        fir_design.Designer(f64).magnitude(&coefficients, 0.0),
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        fir_design.Designer(f64).magnitude(&coefficients, 0.5),
        1.0e-12,
    );
    var maximum_error: f64 = 0.0;
    for (0..4_097) |point| {
        const frequency =
            0.05 +
            0.4 * @as(f64, @floatFromInt(point)) / 4_096.0;
        maximum_error = @max(
            maximum_error,
            @abs(
                fir_design.Designer(f64).magnitude(
                    &coefficients,
                    frequency,
                ) - 1.0,
            ),
        );
    }
    try std.testing.expect(maximum_error < 0.004);
}

test "type IV equiripple supports even-length antisymmetric filters" {
    const Equiripple = Designer(f64);
    var coefficients: [32]f64 = undefined;
    _ = try Equiripple.designWithSymmetry(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.45,
                .lower_gain = 0.0,
                .upper_gain = 0.9,
            },
        },
        .odd,
        .{ .grid_density = 32 },
    );
    for (0..coefficients.len) |index| {
        try std.testing.expectApproxEqAbs(
            coefficients[index],
            -coefficients[coefficients.len - 1 - index],
            1.0e-12,
        );
    }
    var maximum_error: f64 = 0.0;
    for (1..4_097) |point| {
        const frequency =
            0.45 * @as(f64, @floatFromInt(point)) / 4_096.0;
        maximum_error = @max(
            maximum_error,
            @abs(
                fir_design.Designer(f64).magnitude(
                    &coefficients,
                    frequency,
                ) - 2.0 * frequency,
            ),
        );
    }
    try std.testing.expect(maximum_error < 0.001);
}

test "all equiripple symmetry responses match SciPy 1.17" {
    const Equiripple = Designer(f64);
    const low_pass_bands = [_]Band{
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
    };
    const low_pass_frequencies = [_]f64{
        0.0,  0.03, 0.06, 0.09, 0.12, 0.15, 0.18,
        0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
    };

    var type_i: [31]f64 = undefined;
    _ = try Equiripple.design(
        &type_i,
        &low_pass_bands,
        .{ .grid_density = 32 },
    );
    try expectReferenceResponse(
        &type_i,
        &low_pass_frequencies,
        &.{
            0.9821380833028893,
            1.0152589172105684,
            0.9915091182874333,
            1.0001706377619477,
            1.0067455265909893,
            0.990584958151264,
            0.9821380833028893,
            0.004465479174277505,
            0.002980469332620669,
            0.001582712146812538,
            0.004404251458374959,
            0.000307915622526509,
            0.004465479174277958,
        },
        2.0e-5,
    );

    var type_ii: [32]f64 = undefined;
    _ = try Equiripple.design(
        &type_ii,
        &low_pass_bands,
        .{ .grid_density = 32 },
    );
    try expectReferenceResponse(
        &type_ii,
        &low_pass_frequencies,
        &.{
            0.9854875031678232,
            1.0103443292538234,
            0.9983154497175524,
            0.99421031160212,
            1.0099899936332446,
            0.9894455092088377,
            0.9854875031678227,
            0.0036281242080441313,
            0.003335008051275881,
            0.0013043830498038356,
            0.0024078569819385113,
            0.0034145514921495807,
            1.1239198238196953e-17,
        },
        2.0e-5,
    );

    const odd_frequencies = [_]f64{
        0.05, 0.10, 0.15, 0.20, 0.25,
        0.30, 0.35, 0.40, 0.45,
    };
    var type_iii: [31]f64 = undefined;
    _ = try Equiripple.designWithSymmetry(
        &type_iii,
        &.{
            .{
                .lower_frequency = 0.05,
                .upper_frequency = 0.45,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
        },
        .odd,
        .{ .grid_density = 32 },
    );
    try expectReferenceResponse(
        &type_iii,
        &odd_frequencies,
        &.{
            0.9972935318681675,
            1.0027009149905233,
            1.0017936694351997,
            0.9990070020519176,
            0.9972935318681682,
            0.9990070020519143,
            1.0017936694352005,
            1.0027009149905255,
            0.9972935318681717,
        },
        2.0e-5,
    );

    var type_iv: [32]f64 = undefined;
    _ = try Equiripple.designWithSymmetry(
        &type_iv,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.45,
                .lower_gain = 0.0,
                .upper_gain = 0.45,
            },
        },
        .odd,
        .{ .grid_density = 32 },
    );
    try expectReferenceResponse(
        &type_iv,
        &.{ 0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45 },
        &.{
            6.653443800682529e-18,
            0.04999973944865046,
            0.10000311663241329,
            0.15000237408550945,
            0.19999496240605363,
            0.2499933722987233,
            0.30000316884907613,
            0.350011402805299,
            0.4000112444971465,
            0.44998520118556395,
        },
        2.0e-5,
    );
}

test "equiripple validation and convergence failure are transactional" {
    const Equiripple = Designer(f32);
    var coefficients: [15]f32 = @splat(2.0);
    const before = coefficients;
    try std.testing.expectError(
        error.InvalidEquirippleBands,
        Equiripple.design(
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
            .{},
        ),
    );
    try std.testing.expectEqual(before, coefficients);
    try std.testing.expectError(
        error.IncompatibleEquirippleEndpoint,
        Equiripple.designWithSymmetry(
            &coefficients,
            &.{
                .{
                    .lower_frequency = 0.0,
                    .upper_frequency = 0.4,
                    .lower_gain = 1.0,
                    .upper_gain = 1.0,
                },
            },
            .odd,
            .{},
        ),
    );
    try std.testing.expectEqual(before, coefficients);
    var even_coefficients: [16]f32 = @splat(3.0);
    const even_before = even_coefficients;
    try std.testing.expectError(
        error.IncompatibleEquirippleEndpoint,
        Equiripple.design(
            &even_coefficients,
            &.{
                .{
                    .lower_frequency = 0.1,
                    .upper_frequency = 0.5,
                    .lower_gain = 1.0,
                    .upper_gain = 1.0,
                },
            },
            .{},
        ),
    );
    try std.testing.expectEqual(even_before, even_coefficients);
    try std.testing.expectError(
        error.EquirippleDidNotConverge,
        Equiripple.design(
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
                },
            },
            .{
                .maximum_iterations = 1,
                .convergence_tolerance = 1.0e-12,
            },
        ),
    );
    try std.testing.expectEqual(before, coefficients);
}

test "equiripple remains finite at its maximum tap count" {
    const Equiripple = Designer(f32);
    var coefficients: [maximum_taps]f32 = undefined;
    const report = try Equiripple.design(
        &coefficients,
        &.{
            .{
                .lower_frequency = 0.0,
                .upper_frequency = 0.1,
                .lower_gain = 1.0,
                .upper_gain = 1.0,
            },
            .{
                .lower_frequency = 0.105,
                .upper_frequency = 0.5,
                .lower_gain = 0.0,
                .upper_gain = 0.0,
                .weight = 8.0,
            },
        },
        .{
            .grid_density = 8,
            .maximum_iterations = 128,
        },
    );
    try std.testing.expect(report.weighted_ripple < 0.1);
    for (coefficients) |coefficient|
        try std.testing.expect(std.math.isFinite(coefficient));
    try std.testing.expectApproxEqAbs(
        @as(f32, 1.0),
        fir_design.Designer(f32).magnitude(&coefficients, 0.05),
        0.08,
    );
    try std.testing.expect(
        fir_design.Designer(f32).magnitude(&coefficients, 0.3) <
            0.01,
    );
}

fn expectReferenceResponse(
    coefficients: []const f64,
    frequencies: []const f64,
    magnitudes: []const f64,
    tolerance: f64,
) !void {
    try std.testing.expectEqual(frequencies.len, magnitudes.len);
    for (frequencies, magnitudes) |frequency, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            fir_design.Designer(f64).magnitude(
                coefficients,
                frequency,
            ),
            tolerance,
        );
    }
}
