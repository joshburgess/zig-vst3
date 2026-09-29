const std = @import("std");
const dynamic = @import("matrix/dynamic.zig");

const slicesOverlap = dynamic.slicesOverlap;

pub fn Vector(
    comptime Sample: type,
    comptime dimensions: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Vector supports f32 and f64 elements");
    if (dimensions == 0)
        @compileError("Vector dimensions must be positive");

    return struct {
        const Self = @This();

        values: [dimensions]Sample,

        pub fn zero() Self {
            return .{ .values = @splat(0.0) };
        }

        pub fn init(values: [dimensions]Sample) !Self {
            const result = Self{ .values = values };
            if (!result.valid()) return error.VectorNonFiniteValue;
            return result;
        }

        pub fn add(self: Self, other: Self) !Self {
            var result = Self.zero();
            for (0..dimensions) |index| {
                const value = self.values[index] + other.values[index];
                if (!std.math.isFinite(value))
                    return error.VectorNonFiniteValue;
                result.values[index] = value;
            }
            return result;
        }

        pub fn subtract(self: Self, other: Self) !Self {
            var result = Self.zero();
            for (0..dimensions) |index| {
                const value = self.values[index] - other.values[index];
                if (!std.math.isFinite(value))
                    return error.VectorNonFiniteValue;
                result.values[index] = value;
            }
            return result;
        }

        pub fn scaled(self: Self, factor: Sample) !Self {
            if (!std.math.isFinite(factor))
                return error.VectorNonFiniteValue;
            var result = Self.zero();
            for (0..dimensions) |index| {
                const value = self.values[index] * factor;
                if (!std.math.isFinite(value))
                    return error.VectorNonFiniteValue;
                result.values[index] = value;
            }
            return result;
        }

        pub fn dot(self: Self, other: Self) !Sample {
            if (!self.valid() or !other.valid())
                return error.InvalidVector;
            var result: Sample = 0.0;
            for (0..dimensions) |index| {
                result += self.values[index] * other.values[index];
                if (!std.math.isFinite(result))
                    return error.VectorNonFiniteValue;
            }
            return result;
        }

        pub fn magnitude(self: Self) !Sample {
            if (!self.valid()) return error.InvalidVector;
            var scale: Sample = 0.0;
            var sum: Sample = 1.0;
            for (self.values) |value| {
                const magnitude_value = @abs(value);
                if (magnitude_value == 0.0) continue;
                if (scale < magnitude_value) {
                    const ratio = scale / magnitude_value;
                    sum = 1.0 + sum * ratio * ratio;
                    scale = magnitude_value;
                } else {
                    const ratio = magnitude_value / scale;
                    sum += ratio * ratio;
                }
            }
            if (scale == 0.0) return 0.0;
            const result = scale * @sqrt(sum);
            if (!std.math.isFinite(result))
                return error.VectorNonFiniteValue;
            return result;
        }

        pub fn normalized(self: Self) !Self {
            const length = try self.magnitude();
            if (length <= std.math.floatEps(Sample))
                return error.ZeroLengthVector;
            return self.scaled(1.0 / length);
        }

        pub fn valid(self: Self) bool {
            for (self.values) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            return true;
        }
    };
}

pub fn Matrix(
    comptime Sample: type,
    comptime rows: usize,
    comptime columns: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Matrix supports f32 and f64 elements");
    if (rows == 0 or columns == 0)
        @compileError("Matrix dimensions must be positive");

    return struct {
        const Self = @This();

        values: [rows][columns]Sample,

        pub fn zero() Self {
            return .{ .values = @splat(@splat(0.0)) };
        }

        pub fn init(values: [rows][columns]Sample) !Self {
            const result = Self{ .values = values };
            if (!result.valid()) return error.MatrixNonFiniteValue;
            return result;
        }

        pub fn identity() Self {
            if (rows != columns)
                @compileError("Matrix identity requires a square matrix");
            var result = Self.zero();
            for (0..rows) |index| result.values[index][index] = 1.0;
            return result;
        }

        pub fn add(self: Self, other: Self) !Self {
            var result = Self.zero();
            for (0..rows) |row| {
                for (0..columns) |column| {
                    const value = self.values[row][column] +
                        other.values[row][column];
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn subtract(self: Self, other: Self) !Self {
            var result = Self.zero();
            for (0..rows) |row| {
                for (0..columns) |column| {
                    const value = self.values[row][column] -
                        other.values[row][column];
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn scaled(self: Self, factor: Sample) !Self {
            if (!std.math.isFinite(factor)) return error.MatrixNonFiniteValue;
            var result = Self.zero();
            for (0..rows) |row| {
                for (0..columns) |column| {
                    const value = self.values[row][column] * factor;
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn transpose(self: Self) Matrix(Sample, columns, rows) {
            var result = Matrix(Sample, columns, rows).zero();
            for (0..rows) |row| {
                for (0..columns) |column|
                    result.values[column][row] = self.values[row][column];
            }
            return result;
        }

        pub fn multiply(
            self: Self,
            comptime result_columns: usize,
            other: Matrix(Sample, columns, result_columns),
        ) !Matrix(Sample, rows, result_columns) {
            var result = Matrix(Sample, rows, result_columns).zero();
            for (0..rows) |row| {
                for (0..result_columns) |column| {
                    var value: Sample = 0.0;
                    for (0..columns) |inner|
                        value += self.values[row][inner] *
                            other.values[inner][column];
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn multiplyVector(
            self: Self,
            vector: Vector(Sample, columns),
        ) !Vector(Sample, rows) {
            if (!self.valid() or !vector.valid())
                return error.InvalidMatrix;
            var result = Vector(Sample, rows).zero();
            for (0..rows) |row| {
                var value: Sample = 0.0;
                for (0..columns) |column| {
                    value += self.values[row][column] *
                        vector.values[column];
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                }
                result.values[row] = value;
            }
            return result;
        }

        pub fn decompose(self: Self) !LuDecomposition(Sample, rows) {
            if (rows != columns)
                @compileError(
                    "Matrix decomposition requires a square matrix",
                );
            return LuDecomposition(Sample, rows).init(self);
        }

        pub fn decomposeQr(
            self: Self,
        ) !QrDecomposition(Sample, rows, columns) {
            return QrDecomposition(Sample, rows, columns).init(self);
        }

        pub fn decomposeSvd(
            self: Self,
            options: SvdDecomposition(
                Sample,
                rows,
                columns,
            ).Options,
        ) !SvdDecomposition(Sample, rows, columns) {
            return SvdDecomposition(
                Sample,
                rows,
                columns,
            ).init(self, options);
        }

        pub fn solve(self: Self, right_hand_side: [rows]Sample) ![rows]Sample {
            if (rows != columns)
                @compileError("Matrix solve requires a square matrix");
            return (try self.decompose()).solve(right_hand_side);
        }

        pub fn valid(self: Self) bool {
            for (self.values) |row| {
                for (row) |value| {
                    if (!std.math.isFinite(value)) return false;
                }
            }
            return true;
        }
    };
}

/// Owns a finite row-major matrix whose dimensions are selected at runtime.
///
/// Construction and arithmetic allocate through the caller's allocator.
/// Realtime code should prepare these values before entering the audio thread.
/// Teardown is repeatable. Operations reject closed or malformed values.
pub const DynamicMatrix = dynamic.DynamicMatrix;
pub const DynamicLuDecomposition = dynamic.DynamicLuDecomposition;
pub const DynamicQrDecomposition = dynamic.DynamicQrDecomposition;
pub const DynamicSvdDecomposition = dynamic.DynamicSvdDecomposition;
pub fn SvdDecomposition(
    comptime Sample: type,
    comptime rows: usize,
    comptime columns: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("SvdDecomposition supports f32 and f64 elements");
    if (rows == 0 or columns == 0)
        @compileError("SvdDecomposition dimensions must be positive");

    return struct {
        const Self = @This();
        const Source = Matrix(Sample, rows, columns);
        const dimensions = @min(rows, columns);
        const TallRight = Matrix(Sample, columns, columns);
        pub const Options = struct {
            convergence_tolerance: Sample =
                if (Sample == f32) 1.0e-5 else 1.0e-12,
            relative_rank_tolerance: Sample =
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(@max(rows, columns))),
            maximum_sweeps: usize = 64,
        };

        left: [rows][dimensions]Sample,
        singular_values: [dimensions]Sample,
        right: [columns][dimensions]Sample,
        rank: usize,
        sweeps: usize,
        maximum_sweeps: usize,
        converged: bool,
        convergence_tolerance: Sample,
        relative_rank_tolerance: Sample,

        pub fn init(matrix: Source, options: Options) !Self {
            if (!matrix.valid()) return error.InvalidMatrix;
            if (!std.math.isFinite(options.convergence_tolerance) or
                options.convergence_tolerance <= 0.0 or
                options.convergence_tolerance >= 1.0)
                return error.InvalidSvdTolerance;
            if (!std.math.isFinite(
                options.relative_rank_tolerance,
            ) or
                options.relative_rank_tolerance < 0.0 or
                options.relative_rank_tolerance >= 1.0)
                return error.InvalidSvdRankTolerance;
            if (options.maximum_sweeps == 0)
                return error.InvalidSvdSweepLimit;

            if (comptime rows < columns) {
                const transposed = try SvdDecomposition(
                    Sample,
                    columns,
                    rows,
                ).init(matrix.transpose(), .{
                    .convergence_tolerance = options.convergence_tolerance,
                    .relative_rank_tolerance = options.relative_rank_tolerance,
                    .maximum_sweeps = options.maximum_sweeps,
                });
                const result = Self{
                    .left = transposed.right,
                    .singular_values = transposed.singular_values,
                    .right = transposed.left,
                    .rank = transposed.rank,
                    .sweeps = transposed.sweeps,
                    .maximum_sweeps = transposed.maximum_sweeps,
                    .converged = transposed.converged,
                    .convergence_tolerance = transposed.convergence_tolerance,
                    .relative_rank_tolerance = transposed.relative_rank_tolerance,
                };
                if (!result.valid())
                    return error.InvalidSvdDecomposition;
                return result;
            }

            var working = matrix.values;
            var right = TallRight.identity().values;
            var sweeps: usize = 0;
            var converged = dimensions == 1;
            for (0..options.maximum_sweeps) |sweep| {
                var changed = false;
                for (0..columns) |first| {
                    for (first + 1..columns) |second| {
                        var scale: Sample = 0.0;
                        for (0..rows) |row| {
                            scale = @max(
                                scale,
                                @abs(working[row][first]),
                            );
                            scale = @max(
                                scale,
                                @abs(working[row][second]),
                            );
                        }
                        if (scale == 0.0) continue;

                        var first_norm: Sample = 0.0;
                        var second_norm: Sample = 0.0;
                        var cross: Sample = 0.0;
                        for (0..rows) |row| {
                            const first_value =
                                working[row][first] / scale;
                            const second_value =
                                working[row][second] / scale;
                            first_norm += first_value * first_value;
                            second_norm += second_value * second_value;
                            cross += first_value * second_value;
                        }
                        const threshold =
                            options.convergence_tolerance *
                            @sqrt(first_norm * second_norm) +
                            std.math.floatEps(Sample) *
                                @max(first_norm, second_norm) *
                                @as(Sample, @floatFromInt(rows));
                        if (@abs(cross) <= threshold) continue;

                        const offset =
                            (second_norm - first_norm) /
                            (2.0 * cross);
                        const tangent = if (offset >= 0.0)
                            1.0 /
                                (offset + @sqrt(1.0 + offset * offset))
                        else
                            -1.0 /
                                (-offset + @sqrt(
                                    1.0 + offset * offset,
                                ));
                        const cosine =
                            1.0 / @sqrt(1.0 + tangent * tangent);
                        const sine = cosine * tangent;
                        if (!std.math.isFinite(cosine) or
                            !std.math.isFinite(sine))
                            return error.MatrixNonFiniteValue;

                        for (0..rows) |row| {
                            const first_value = working[row][first];
                            const second_value = working[row][second];
                            working[row][first] =
                                cosine * first_value -
                                sine * second_value;
                            working[row][second] =
                                sine * first_value +
                                cosine * second_value;
                            if (!std.math.isFinite(
                                working[row][first],
                            ) or
                                !std.math.isFinite(
                                    working[row][second],
                                ))
                                return error.MatrixNonFiniteValue;
                        }
                        for (0..columns) |row| {
                            const first_value = right[row][first];
                            const second_value = right[row][second];
                            right[row][first] =
                                cosine * first_value -
                                sine * second_value;
                            right[row][second] =
                                sine * first_value +
                                cosine * second_value;
                        }
                        changed = true;
                    }
                }
                sweeps = sweep + 1;
                if (!changed) {
                    converged = true;
                    break;
                }
            }

            var singular_values: [dimensions]Sample = undefined;
            var left: [rows][dimensions]Sample =
                @splat(@splat(0.0));
            for (0..dimensions) |column| {
                singular_values[column] =
                    try columnMagnitude(working, column);
                if (singular_values[column] == 0.0) continue;
                for (0..rows) |row| {
                    left[row][column] =
                        working[row][column] /
                        singular_values[column];
                }
            }
            sortDescending(&singular_values, &left, &right);

            const rank_threshold =
                singular_values[0] *
                options.relative_rank_tolerance;
            var rank: usize = 0;
            for (singular_values) |value| {
                if (value > rank_threshold) rank += 1;
            }
            const result = Self{
                .left = left,
                .singular_values = singular_values,
                .right = right,
                .rank = rank,
                .sweeps = sweeps,
                .maximum_sweeps = options.maximum_sweeps,
                .converged = converged,
                .convergence_tolerance = options.convergence_tolerance,
                .relative_rank_tolerance = options.relative_rank_tolerance,
            };
            if (!result.valid()) return error.InvalidSvdDecomposition;
            return result;
        }

        pub fn solveLeastSquares(
            self: Self,
            right_hand_side: [rows]Sample,
        ) ![columns]Sample {
            if (!self.valid()) return error.InvalidSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }

            var scaled_projection: [dimensions]Sample = @splat(0.0);
            for (0..self.rank) |column| {
                var projection: Sample = 0.0;
                for (0..rows) |row| {
                    projection +=
                        self.left[row][column] *
                        right_hand_side[row];
                    if (!std.math.isFinite(projection))
                        return error.MatrixNonFiniteValue;
                }
                scaled_projection[column] =
                    projection / self.singular_values[column];
                if (!std.math.isFinite(
                    scaled_projection[column],
                ))
                    return error.MatrixNonFiniteValue;
            }

            var result: [columns]Sample = @splat(0.0);
            for (0..columns) |row| {
                for (0..self.rank) |column| {
                    result[row] +=
                        self.right[row][column] *
                        scaled_projection[column];
                    if (!std.math.isFinite(result[row]))
                        return error.MatrixNonFiniteValue;
                }
            }
            return result;
        }

        pub fn pseudoinverse(
            self: Self,
        ) !Matrix(Sample, columns, rows) {
            if (!self.valid()) return error.InvalidSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            const Result = Matrix(Sample, columns, rows);
            var result = Result.zero();
            for (0..columns) |row| {
                for (0..rows) |column| {
                    var value: Sample = 0.0;
                    for (0..self.rank) |inner| {
                        value +=
                            self.right[row][inner] *
                            self.left[column][inner] /
                            self.singular_values[inner];
                        if (!std.math.isFinite(value))
                            return error.MatrixNonFiniteValue;
                    }
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn reconstruct(self: Self) !Source {
            if (!self.valid()) return error.InvalidSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            var result = Source.zero();
            for (0..rows) |row| {
                for (0..columns) |column| {
                    var value: Sample = 0.0;
                    for (0..dimensions) |inner| {
                        value +=
                            self.left[row][inner] *
                            self.singular_values[inner] *
                            self.right[column][inner];
                        if (!std.math.isFinite(value))
                            return error.MatrixNonFiniteValue;
                    }
                    result.values[row][column] = value;
                }
            }
            return result;
        }

        pub fn conditionNumber(self: Self) !Sample {
            if (!self.valid()) return error.InvalidSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            if (self.rank < dimensions) return std.math.inf(Sample);
            const result =
                self.singular_values[0] /
                self.singular_values[dimensions - 1];
            if (!std.math.isFinite(result))
                return error.MatrixNonFiniteValue;
            return result;
        }

        pub fn valid(self: Self) bool {
            if (self.rank > dimensions or
                self.maximum_sweeps == 0 or
                self.sweeps == 0 or
                self.sweeps > self.maximum_sweeps or
                (!self.converged and
                    self.sweeps != self.maximum_sweeps) or
                !std.math.isFinite(self.convergence_tolerance) or
                self.convergence_tolerance <= 0.0 or
                self.convergence_tolerance >= 1.0 or
                !std.math.isFinite(self.relative_rank_tolerance) or
                self.relative_rank_tolerance < 0.0 or
                self.relative_rank_tolerance >= 1.0)
                return false;
            var previous = std.math.inf(Sample);
            for (self.singular_values, 0..) |value, index| {
                if (!std.math.isFinite(value) or
                    value < 0.0 or value > previous)
                    return false;
                if ((index < self.rank) !=
                    (value >
                        self.singular_values[0] *
                            self.relative_rank_tolerance))
                    return false;
                previous = value;
            }
            for (self.left) |row| {
                for (row) |value| {
                    if (!std.math.isFinite(value)) return false;
                }
            }
            for (self.right) |row| {
                for (row) |value| {
                    if (!std.math.isFinite(value)) return false;
                }
            }
            const basis_tolerance = @min(
                @as(Sample, 0.01),
                std.math.floatEps(Sample) *
                    128.0 *
                    @as(
                        Sample,
                        @floatFromInt(@max(rows, columns)),
                    ),
            );
            for (0..dimensions) |column| {
                const left_magnitude = basisColumnMagnitude(
                    rows,
                    self.left,
                    column,
                ) catch return false;
                const right_magnitude = basisColumnMagnitude(
                    columns,
                    self.right,
                    column,
                ) catch return false;
                const singular = self.singular_values[column];
                const expected_left: Sample = if (rows < columns or singular != 0.0) 1.0 else 0.0;
                const expected_right: Sample = if (rows >= columns or singular != 0.0) 1.0 else 0.0;
                if (@abs(left_magnitude - expected_left) >
                    basis_tolerance or
                    @abs(right_magnitude - expected_right) >
                        basis_tolerance)
                    return false;
            }
            for (0..dimensions) |first| {
                for (first + 1..dimensions) |second| {
                    const left_active = rows < columns or
                        second < self.rank;
                    const right_active = rows >= columns or
                        second < self.rank;
                    if (left_active and
                        (rows < columns or self.converged))
                    {
                        const dot = basisColumnDot(
                            rows,
                            self.left,
                            first,
                            second,
                        ) catch return false;
                        const tolerance = basis_tolerance +
                            if (rows < columns)
                                basis_tolerance
                            else
                                self.convergence_tolerance;
                        if (@abs(dot) > tolerance) return false;
                    }
                    if (right_active and
                        (rows >= columns or self.converged))
                    {
                        const dot = basisColumnDot(
                            columns,
                            self.right,
                            first,
                            second,
                        ) catch return false;
                        const tolerance = basis_tolerance +
                            if (rows >= columns)
                                basis_tolerance
                            else
                                self.convergence_tolerance;
                        if (@abs(dot) > tolerance) return false;
                    }
                }
            }
            return true;
        }

        fn basisColumnDot(
            comptime basis_rows: usize,
            values: [basis_rows][dimensions]Sample,
            first: usize,
            second: usize,
        ) !Sample {
            var result: Sample = 0.0;
            for (0..basis_rows) |row| {
                result += values[row][first] * values[row][second];
                if (!std.math.isFinite(result))
                    return error.MatrixNonFiniteValue;
            }
            return result;
        }

        fn basisColumnMagnitude(
            comptime basis_rows: usize,
            values: [basis_rows][dimensions]Sample,
            column: usize,
        ) !Sample {
            var scale: Sample = 0.0;
            var sum: Sample = 1.0;
            for (0..basis_rows) |row| {
                const magnitude = @abs(values[row][column]);
                if (magnitude == 0.0) continue;
                if (scale < magnitude) {
                    const ratio = scale / magnitude;
                    sum = 1.0 + sum * ratio * ratio;
                    scale = magnitude;
                } else {
                    const ratio = magnitude / scale;
                    sum += ratio * ratio;
                }
            }
            if (scale == 0.0) return 0.0;
            const result = scale * @sqrt(sum);
            if (!std.math.isFinite(result))
                return error.MatrixNonFiniteValue;
            return result;
        }

        fn columnMagnitude(
            values: [rows][columns]Sample,
            column: usize,
        ) !Sample {
            var scale: Sample = 0.0;
            var sum: Sample = 1.0;
            for (0..rows) |row| {
                const magnitude = @abs(values[row][column]);
                if (magnitude == 0.0) continue;
                if (scale < magnitude) {
                    const ratio = scale / magnitude;
                    sum = 1.0 + sum * ratio * ratio;
                    scale = magnitude;
                } else {
                    const ratio = magnitude / scale;
                    sum += ratio * ratio;
                }
            }
            if (scale == 0.0) return 0.0;
            const result = scale * @sqrt(sum);
            if (!std.math.isFinite(result))
                return error.MatrixNonFiniteValue;
            return result;
        }

        fn sortDescending(
            singular_values: *[dimensions]Sample,
            left: *[rows][dimensions]Sample,
            right: *[columns][dimensions]Sample,
        ) void {
            for (0..dimensions) |first| {
                var largest = first;
                for (first + 1..dimensions) |candidate| {
                    if (singular_values[candidate] >
                        singular_values[largest])
                        largest = candidate;
                }
                if (largest == first) continue;
                std.mem.swap(
                    Sample,
                    &singular_values[first],
                    &singular_values[largest],
                );
                for (0..rows) |row| {
                    std.mem.swap(
                        Sample,
                        &left[row][first],
                        &left[row][largest],
                    );
                }
                for (0..columns) |row| {
                    std.mem.swap(
                        Sample,
                        &right[row][first],
                        &right[row][largest],
                    );
                }
            }
        }
    };
}

pub fn QrDecomposition(
    comptime Sample: type,
    comptime rows: usize,
    comptime columns: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("QrDecomposition supports f32 and f64 elements");
    if (rows == 0 or columns == 0 or rows < columns)
        @compileError(
            "QrDecomposition requires positive rows >= columns",
        );

    return struct {
        const Self = @This();
        const Source = Matrix(Sample, rows, columns);

        factors: [rows][columns]Sample,
        tau: [columns]Sample,
        matrix_scale: Sample,
        rank_tolerance: Sample,

        pub fn init(matrix: Source) !Self {
            if (!matrix.valid()) return error.InvalidMatrix;
            var result = Self{
                .factors = matrix.values,
                .tau = @splat(0.0),
                .matrix_scale = 0.0,
                .rank_tolerance = 0.0,
            };
            var matrix_scale: Sample = 0.0;
            for (matrix.values) |row| {
                for (row) |value|
                    matrix_scale = @max(matrix_scale, @abs(value));
            }
            const rank_tolerance = matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(rows));
            result.matrix_scale = matrix_scale;
            result.rank_tolerance = rank_tolerance;

            for (0..columns) |column| {
                var scale: Sample = 0.0;
                var sum: Sample = 1.0;
                for (column..rows) |row| {
                    const magnitude = @abs(
                        result.factors[row][column],
                    );
                    if (magnitude == 0.0) continue;
                    if (scale < magnitude) {
                        const ratio = scale / magnitude;
                        sum = 1.0 + sum * ratio * ratio;
                        scale = magnitude;
                    } else {
                        const ratio = magnitude / scale;
                        sum += ratio * ratio;
                    }
                }
                if (scale == 0.0) return error.RankDeficientMatrix;
                const norm = scale * @sqrt(sum);
                if (!std.math.isFinite(norm) or
                    norm <= rank_tolerance)
                    return error.RankDeficientMatrix;

                const first = result.factors[column][column];
                const diagonal = if (first >= 0.0) -norm else norm;
                const leading = first - diagonal;
                if (!std.math.isFinite(leading) or leading == 0.0)
                    return error.RankDeficientMatrix;
                const reflector = (diagonal - first) / diagonal;
                if (!std.math.isFinite(reflector))
                    return error.MatrixNonFiniteValue;

                for (column + 1..rows) |row| {
                    result.factors[row][column] /= leading;
                    if (!std.math.isFinite(
                        result.factors[row][column],
                    ))
                        return error.MatrixNonFiniteValue;
                }
                for (column + 1..columns) |target| {
                    var projection =
                        result.factors[column][target];
                    for (column + 1..rows) |row| {
                        projection +=
                            result.factors[row][column] *
                            result.factors[row][target];
                    }
                    projection *= reflector;
                    result.factors[column][target] -= projection;
                    for (column + 1..rows) |row| {
                        result.factors[row][target] -=
                            result.factors[row][column] * projection;
                    }
                }
                result.factors[column][column] = diagonal;
                result.tau[column] = reflector;
            }
            if (!result.valid())
                return error.MatrixNonFiniteValue;
            return result;
        }

        pub fn solveLeastSquares(
            self: Self,
            right_hand_side: [rows]Sample,
        ) ![columns]Sample {
            if (!self.valid()) return error.InvalidMatrixDecomposition;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }
            var transformed = right_hand_side;
            try self.applyReflectors(&transformed, false);

            var result: [columns]Sample = undefined;
            var row = columns;
            while (row != 0) {
                row -= 1;
                var value = transformed[row];
                for (row + 1..columns) |column|
                    value -= self.factors[row][column] * result[column];
                value /= self.factors[row][row];
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                result[row] = value;
            }
            return result;
        }

        pub fn upper(self: Self) !Source {
            if (!self.valid()) return error.InvalidMatrixDecomposition;
            var result = Source.zero();
            for (0..columns) |row| {
                for (row..columns) |column|
                    result.values[row][column] =
                        self.factors[row][column];
            }
            return result;
        }

        pub fn orthogonal(
            self: Self,
        ) !Matrix(Sample, rows, rows) {
            if (!self.valid()) return error.InvalidMatrixDecomposition;
            const Square = Matrix(Sample, rows, rows);
            var result = Square.zero();
            for (0..rows) |column| {
                var basis: [rows]Sample = @splat(0.0);
                basis[column] = 1.0;
                try self.applyReflectors(&basis, true);
                for (0..rows) |row|
                    result.values[row][column] = basis[row];
            }
            return result;
        }

        pub fn valid(self: Self) bool {
            if (!std.math.isFinite(self.matrix_scale) or
                self.matrix_scale <= 0.0 or
                !std.math.isFinite(self.rank_tolerance) or
                self.rank_tolerance < 0.0)
                return false;
            const expected_rank_tolerance =
                self.matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(rows));
            if (!std.math.isFinite(expected_rank_tolerance) or
                self.rank_tolerance != expected_rank_tolerance)
                return false;
            for (0..columns) |column| {
                if (!std.math.isFinite(self.tau[column]) or
                    self.tau[column] <= 0.0 or
                    self.tau[column] > 2.0 or
                    !std.math.isFinite(
                        self.factors[column][column],
                    ) or
                    @abs(self.factors[column][column]) <=
                        self.rank_tolerance)
                    return false;

                var reflector_scale: Sample = 1.0;
                var reflector_sum: Sample = 1.0;
                for (column + 1..rows) |row| {
                    const magnitude = @abs(
                        self.factors[row][column],
                    );
                    if (magnitude == 0.0) continue;
                    if (reflector_scale < magnitude) {
                        const ratio = reflector_scale / magnitude;
                        reflector_sum =
                            1.0 + reflector_sum * ratio * ratio;
                        reflector_scale = magnitude;
                    } else {
                        const ratio = magnitude / reflector_scale;
                        reflector_sum += ratio * ratio;
                    }
                    if (!std.math.isFinite(reflector_sum))
                        return false;
                }
                const inverse_scale = 1.0 / reflector_scale;
                const expected_tau =
                    2.0 * inverse_scale * inverse_scale /
                    reflector_sum;
                const reflector_length: Sample = @floatFromInt(
                    rows - column,
                );
                const tolerance =
                    std.math.floatEps(Sample) *
                    32.0 * reflector_length *
                    @max(@as(Sample, 1.0), expected_tau);
                if (!std.math.isFinite(expected_tau) or
                    expected_tau <= 0.0 or
                    !std.math.isFinite(tolerance) or
                    @abs(self.tau[column] - expected_tau) > tolerance)
                    return false;
            }
            for (self.factors) |row| {
                for (row) |value| {
                    if (!std.math.isFinite(value)) return false;
                }
            }
            return true;
        }

        fn applyReflectors(
            self: Self,
            values: *[rows]Sample,
            reverse: bool,
        ) !void {
            if (reverse) {
                var column = columns;
                while (column != 0) {
                    column -= 1;
                    try self.applyReflector(values, column);
                }
            } else {
                for (0..columns) |column|
                    try self.applyReflector(values, column);
            }
        }

        fn applyReflector(
            self: Self,
            values: *[rows]Sample,
            column: usize,
        ) !void {
            var projection = values[column];
            for (column + 1..rows) |row| {
                projection +=
                    self.factors[row][column] * values[row];
                if (!std.math.isFinite(projection))
                    return error.MatrixNonFiniteValue;
            }
            projection *= self.tau[column];
            if (!std.math.isFinite(projection))
                return error.MatrixNonFiniteValue;
            values[column] -= projection;
            if (!std.math.isFinite(values[column]))
                return error.MatrixNonFiniteValue;
            for (column + 1..rows) |row| {
                values[row] -=
                    self.factors[row][column] * projection;
                if (!std.math.isFinite(values[row]))
                    return error.MatrixNonFiniteValue;
            }
        }
    };
}

pub fn LuDecomposition(
    comptime Sample: type,
    comptime dimensions: usize,
) type {
    if (Sample != f32 and Sample != f64)
        @compileError("LuDecomposition supports f32 and f64 elements");
    if (dimensions == 0)
        @compileError("LuDecomposition dimensions must be positive");

    return struct {
        const Self = @This();
        const Square = Matrix(Sample, dimensions, dimensions);

        factors: [dimensions][dimensions]Sample,
        permutation: [dimensions]usize,
        odd_swaps: bool,
        matrix_scale: Sample,
        pivot_tolerance: Sample,

        pub fn init(matrix: Square) !Self {
            if (!matrix.valid()) return error.InvalidMatrix;
            var result = Self{
                .factors = matrix.values,
                .permutation = undefined,
                .odd_swaps = false,
                .matrix_scale = 0.0,
                .pivot_tolerance = 0.0,
            };
            for (0..dimensions) |index|
                result.permutation[index] = index;
            var matrix_scale: Sample = 0.0;
            for (matrix.values) |row| {
                for (row) |value|
                    matrix_scale = @max(matrix_scale, @abs(value));
            }
            if (matrix_scale == 0.0) return error.SingularMatrix;
            const pivot_tolerance =
                matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(dimensions));
            if (!std.math.isFinite(pivot_tolerance))
                return error.MatrixNonFiniteValue;
            result.matrix_scale = matrix_scale;
            result.pivot_tolerance = pivot_tolerance;

            for (0..dimensions) |pivot_column| {
                var pivot_row = pivot_column;
                var pivot_magnitude =
                    @abs(result.factors[pivot_row][pivot_column]);
                for (pivot_column + 1..dimensions) |candidate| {
                    const magnitude =
                        @abs(result.factors[candidate][pivot_column]);
                    if (magnitude > pivot_magnitude) {
                        pivot_row = candidate;
                        pivot_magnitude = magnitude;
                    }
                }
                if (!std.math.isFinite(pivot_magnitude) or
                    pivot_magnitude <= pivot_tolerance)
                    return error.SingularMatrix;
                if (pivot_row != pivot_column) {
                    std.mem.swap(
                        [dimensions]Sample,
                        &result.factors[pivot_row],
                        &result.factors[pivot_column],
                    );
                    std.mem.swap(
                        usize,
                        &result.permutation[pivot_row],
                        &result.permutation[pivot_column],
                    );
                    result.odd_swaps = !result.odd_swaps;
                }

                const pivot = result.factors[pivot_column][pivot_column];
                for (pivot_column + 1..dimensions) |row| {
                    result.factors[row][pivot_column] /= pivot;
                    if (!std.math.isFinite(
                        result.factors[row][pivot_column],
                    ))
                        return error.MatrixNonFiniteValue;
                    const multiplier =
                        result.factors[row][pivot_column];
                    for (pivot_column + 1..dimensions) |column| {
                        result.factors[row][column] -=
                            multiplier *
                            result.factors[pivot_column][column];
                        if (!std.math.isFinite(
                            result.factors[row][column],
                        ))
                            return error.MatrixNonFiniteValue;
                    }
                }
            }
            return result;
        }

        pub fn solve(
            self: Self,
            right_hand_side: [dimensions]Sample,
        ) ![dimensions]Sample {
            if (!self.valid()) return error.InvalidMatrixDecomposition;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }

            var result: [dimensions]Sample = undefined;
            for (0..dimensions) |row| {
                var value =
                    right_hand_side[self.permutation[row]];
                for (0..row) |column|
                    value -= self.factors[row][column] * result[column];
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                result[row] = value;
            }
            var row = dimensions;
            while (row != 0) {
                row -= 1;
                var value = result[row];
                for (row + 1..dimensions) |column|
                    value -= self.factors[row][column] * result[column];
                value /= self.factors[row][row];
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                result[row] = value;
            }
            return result;
        }

        pub fn solveVector(
            self: Self,
            right_hand_side: Vector(Sample, dimensions),
        ) !Vector(Sample, dimensions) {
            return Vector(Sample, dimensions).init(
                try self.solve(right_hand_side.values),
            );
        }

        pub fn solveMatrix(
            self: Self,
            comptime right_columns: usize,
            right_hand_side: Matrix(
                Sample,
                dimensions,
                right_columns,
            ),
        ) !Matrix(Sample, dimensions, right_columns) {
            if (!right_hand_side.valid())
                return error.InvalidMatrix;
            var result =
                Matrix(Sample, dimensions, right_columns).zero();
            for (0..right_columns) |column| {
                var right: [dimensions]Sample = undefined;
                for (0..dimensions) |row|
                    right[row] = right_hand_side.values[row][column];
                const solution = try self.solve(right);
                for (0..dimensions) |row|
                    result.values[row][column] = solution[row];
            }
            return result;
        }

        pub fn determinant(self: Self) !Sample {
            if (!self.valid()) return error.InvalidMatrixDecomposition;
            var result: Sample = if (self.odd_swaps) -1.0 else 1.0;
            for (0..dimensions) |index| {
                result *= self.factors[index][index];
                if (!std.math.isFinite(result))
                    return error.MatrixNonFiniteValue;
            }
            return result;
        }

        pub fn inverse(self: Self) !Square {
            return self.solveMatrix(
                dimensions,
                Square.identity(),
            );
        }

        pub fn valid(self: Self) bool {
            if (!std.math.isFinite(self.matrix_scale) or
                self.matrix_scale <= 0.0 or
                !std.math.isFinite(self.pivot_tolerance) or
                self.pivot_tolerance < 0.0)
                return false;
            const expected_pivot_tolerance =
                self.matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(dimensions));
            if (!std.math.isFinite(expected_pivot_tolerance) or
                self.pivot_tolerance != expected_pivot_tolerance)
                return false;
            var seen: [dimensions]bool = @splat(false);
            var permutation_odd = false;
            for (0..dimensions) |row| {
                const source = self.permutation[row];
                if (source >= dimensions or seen[source])
                    return false;
                seen[source] = true;
                for (0..row) |previous| {
                    if (self.permutation[previous] > source)
                        permutation_odd = !permutation_odd;
                }
                for (0..dimensions) |column| {
                    if (!std.math.isFinite(
                        self.factors[row][column],
                    ))
                        return false;
                }
                if (@abs(self.factors[row][row]) <=
                    self.pivot_tolerance)
                    return false;
            }
            if (self.odd_swaps != permutation_odd) return false;
            return true;
        }
    };
}

test "dynamic matrix public names remain exact aliases" {
    comptime {
        if (DynamicMatrix(f32) != dynamic.DynamicMatrix(f32) or
            DynamicLuDecomposition(f32) != dynamic.DynamicLuDecomposition(f32) or
            DynamicQrDecomposition(f32) != dynamic.DynamicQrDecomposition(f32) or
            DynamicSvdDecomposition(f32) != dynamic.DynamicSvdDecomposition(f32))
        {
            @compileError("dynamic matrix public alias identity changed");
        }
    }
}

test "vectors provide stable length and checked arithmetic" {
    const V = Vector(f64, 3);
    const first = try V.init(.{ 3.0e200, 4.0e200, 0.0 });
    try std.testing.expectApproxEqRel(
        @as(f64, 5.0e200),
        try first.magnitude(),
        0.000_000_000_001,
    );
    const unit = try (try V.init(.{ 3.0, 4.0, 0.0 })).normalized();
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try unit.magnitude(),
        0.000_000_000_001,
    );
    const sum = try unit.add(try V.init(.{ 0.4, -0.3, 1.0 }));
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.5),
        try sum.dot(try V.init(.{ 1.0, 1.0, 0.0 })),
        0.000_000_000_001,
    );
    try std.testing.expectError(
        error.ZeroLengthVector,
        V.zero().normalized(),
    );
}

test "matrix identity preserves rectangular multiplication" {
    const Left = Matrix(f64, 2, 3);
    const Right = Matrix(f64, 3, 3);
    const left = try Left.init(.{
        .{ 1.0, 2.0, 3.0 },
        .{ 4.0, 5.0, 6.0 },
    });
    const product = try left.multiply(3, Right.identity());
    try std.testing.expectEqualDeep(left.values, product.values);
}

test "matrix transpose arithmetic preserves fixed dimensions" {
    const M = Matrix(f32, 2, 2);
    const value = try M.init(.{
        .{ 1.0, 2.0 },
        .{ 3.0, 4.0 },
    });
    const sum = try value.add(value.transpose());
    const scaled = try sum.scaled(0.5);
    try std.testing.expectEqualDeep(
        [2][2]f32{
            .{ 1.0, 2.5 },
            .{ 2.5, 4.0 },
        },
        scaled.values,
    );
    try std.testing.expectEqualDeep(
        [2][2]f32{
            .{ 0.0, -1.0 },
            .{ 1.0, 0.0 },
        },
        (try value.subtract(value.transpose())).values,
    );
}

test "matrix operations reject non-finite values" {
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        Matrix(f32, 1, 1).init(.{.{std.math.nan(f32)}}),
    );
    const value = try Matrix(f32, 1, 1).init(.{.{1.0}});
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        value.scaled(std.math.inf(f32)),
    );
    const maximum = try Matrix(f32, 1, 1).init(
        .{.{std.math.floatMax(f32)}},
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        maximum.subtract(try Matrix(f32, 1, 1).init(
            .{.{-std.math.floatMax(f32)}},
        )),
    );
}

test "matrix solve uses partial pivoting" {
    const M = Matrix(f64, 3, 3);
    const coefficients = try M.init(.{
        .{ 0.0, 2.0, 1.0 },
        .{ 1.0, -2.0, -3.0 },
        .{ 3.0, -1.0, 2.0 },
    });
    const solution = try coefficients.solve(.{ 3.0, -4.0, 4.0 });
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solution[1],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solution[2],
        0.000_000_000_001,
    );
}

test "matrix solve rejects singular and non-finite systems" {
    const M = Matrix(f32, 2, 2);
    const singular = try M.init(.{
        .{ 1.0, 2.0 },
        .{ 2.0, 4.0 },
    });
    try std.testing.expectError(
        error.SingularMatrix,
        singular.solve(.{ 1.0, 2.0 }),
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        M.identity().solve(.{ std.math.nan(f32), 1.0 }),
    );
}

test "matrix vectors and reusable LU decomposition compose" {
    const M = Matrix(f64, 3, 3);
    const V = Vector(f64, 3);
    const coefficients = try M.init(.{
        .{ 0.0, 2.0, 1.0 },
        .{ 1.0, -2.0, -3.0 },
        .{ 3.0, -1.0, 2.0 },
    });
    const decomposition = try coefficients.decompose();
    const solution = try decomposition.solveVector(
        try V.init(.{ 3.0, -4.0, 4.0 }),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solution.values[0],
        0.000_000_000_001,
    );
    const reconstructed =
        try coefficients.multiplyVector(solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        reconstructed.values[1],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -17.0),
        try decomposition.determinant(),
        0.000_000_000_001,
    );

    const inverse = try decomposition.inverse();
    const identity = try coefficients.multiply(3, inverse);
    for (0..3) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                if (row == column) @as(f64, 1.0) else 0.0,
                identity.values[row][column],
                0.000_000_000_001,
            );
        }
    }

    const right = try Matrix(f64, 3, 2).init(.{
        .{ 3.0, 6.0 },
        .{ -4.0, -8.0 },
        .{ 4.0, 8.0 },
    });
    const multiple = try decomposition.solveMatrix(2, right);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        multiple.values[0][1],
        0.000_000_000_001,
    );
}

test "LU decomposition contains corrupted retained state" {
    const M = Matrix(f32, 2, 2);
    const coefficients = try M.init(.{
        .{ 2.0, 1.0 },
        .{ 1.0, 2.0 },
    });
    var decomposition = try coefficients.decompose();
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.determinant(),
    );
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(decomposition.valid());
    const retained_matrix_scale = decomposition.matrix_scale;
    decomposition.matrix_scale *= 2.0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.determinant(),
    );
    decomposition.matrix_scale = retained_matrix_scale;
    try std.testing.expect(decomposition.valid());
    const retained_pivot_tolerance = decomposition.pivot_tolerance;
    decomposition.pivot_tolerance *= 2.0;
    try std.testing.expect(!decomposition.valid());
    decomposition.pivot_tolerance = retained_pivot_tolerance;
    try std.testing.expect(decomposition.valid());
    decomposition.permutation[1] = decomposition.permutation[0];
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.solve(.{ 1.0, 1.0 }),
    );
}

test "LU decomposition scales its pivot threshold to tiny systems" {
    const M = Matrix(f64, 2, 2);
    const source = try M.init(.{
        .{ 1.0e-200, 0.0 },
        .{ 0.0, 2.0e-200 },
    });
    const decomposition = try source.decompose();
    const solution = try decomposition.solve(.{
        3.0e-200,
        -8.0e-200,
    });
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        solution[1],
        0.000_000_000_001,
    );
}

test "QR decomposition reconstructs rectangular matrices" {
    const M = Matrix(f64, 3, 2);
    const source = try M.init(.{
        .{ 1.0, 1.0 },
        .{ 1.0, 2.0 },
        .{ 1.0, 3.0 },
    });
    const decomposition = try source.decomposeQr();
    const orthogonal = try decomposition.orthogonal();
    const upper = try decomposition.upper();
    const reconstructed = try orthogonal.multiply(2, upper);
    for (0..3) |row| {
        for (0..2) |column| {
            try std.testing.expectApproxEqAbs(
                source.values[row][column],
                reconstructed.values[row][column],
                0.000_000_000_001,
            );
        }
    }
    const identity = try orthogonal.transpose().multiply(
        3,
        orthogonal,
    );
    for (0..3) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                if (row == column) @as(f64, 1.0) else 0.0,
                identity.values[row][column],
                0.000_000_000_001,
            );
        }
    }
}

test "QR decomposition solves least squares without normal equations" {
    const source = try Matrix(f64, 3, 2).init(.{
        .{ 1.0, 1.0 },
        .{ 1.0, 2.0 },
        .{ 1.0, 3.0 },
    });
    const solution =
        try (try source.decomposeQr()).solveLeastSquares(
            .{ 1.0, 2.0, 2.0 },
        );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0 / 3.0),
        solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        solution[1],
        0.000_000_000_001,
    );
}

test "QR decomposition rejects rank loss and corrupted state" {
    const M = Matrix(f32, 3, 2);
    try std.testing.expectError(
        error.RankDeficientMatrix,
        (try M.init(.{
            .{ 1.0, 2.0 },
            .{ 2.0, 4.0 },
            .{ 3.0, 6.0 },
        })).decomposeQr(),
    );
    var decomposition = try (try M.init(.{
        .{ 1.0, 0.0 },
        .{ 0.0, 1.0 },
        .{ 1.0, 1.0 },
    })).decomposeQr();
    const retained_tau = decomposition.tau[0];
    decomposition.tau[0] *= 0.5;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    decomposition.tau[0] = retained_tau;
    try std.testing.expect(decomposition.valid());
    const retained_matrix_scale = decomposition.matrix_scale;
    decomposition.matrix_scale *= 2.0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    decomposition.matrix_scale = retained_matrix_scale;
    try std.testing.expect(decomposition.valid());
    const retained_rank_tolerance = decomposition.rank_tolerance;
    decomposition.rank_tolerance *= 2.0;
    try std.testing.expect(!decomposition.valid());
    decomposition.rank_tolerance = retained_rank_tolerance;
    try std.testing.expect(decomposition.valid());
    decomposition.tau[0] = std.math.nan(f32);
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );

    const Tiny = Matrix(f64, 2, 2);
    const tiny = try (try Tiny.init(.{
        .{ 1.0e-200, 0.0 },
        .{ 0.0, 2.0e-200 },
    })).decomposeQr();
    const tiny_solution =
        try tiny.solveLeastSquares(.{ 1.0e-200, 4.0e-200 });
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        tiny_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        tiny_solution[1],
        0.000_000_000_001,
    );

    const overflow = try Tiny.identity().decomposeQr();
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        overflow.solveLeastSquares(.{
            std.math.floatMax(f64),
            std.math.floatMax(f64),
        }),
    );
}

test "SVD reconstructs rectangular matrices and pseudoinverts" {
    const M = Matrix(f64, 3, 2);
    const source = try M.init(.{
        .{ 3.0, 0.0 },
        .{ 0.0, 2.0 },
        .{ 0.0, 0.0 },
    });
    const decomposition = try source.decomposeSvd(.{});
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 2), decomposition.rank);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        decomposition.singular_values[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        decomposition.singular_values[1],
        0.000_000_000_001,
    );

    const pseudoinverse = try decomposition.pseudoinverse();
    const projected = try (try source.multiply(
        3,
        pseudoinverse,
    )).multiply(2, source);
    for (0..3) |row| {
        for (0..2) |column| {
            try std.testing.expectApproxEqAbs(
                source.values[row][column],
                projected.values[row][column],
                0.000_000_000_001,
            );
        }
    }
}

test "SVD solves rank-deficient systems with minimum norm" {
    const M = Matrix(f64, 3, 2);
    const source = try M.init(.{
        .{ 1.0, 2.0 },
        .{ 2.0, 4.0 },
        .{ 3.0, 6.0 },
    });
    const decomposition = try source.decomposeSvd(.{});
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 1), decomposition.rank);
    const solution =
        try decomposition.solveLeastSquares(.{ 1.0, 2.0, 3.0 });
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.2),
        solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.4),
        solution[1],
        0.000_000_000_001,
    );
    const reconstructed = try source.multiplyVector(
        try Vector(f64, 2).init(solution),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        reconstructed.values[2],
        0.000_000_000_001,
    );
}

test "SVD reports convergence and contains corrupted state" {
    const M = Matrix(f64, 3, 3);
    const source = try M.init(.{
        .{ 1.0, 2.0, 3.0 },
        .{ 4.0, 5.0, 6.0 },
        .{ 7.0, 8.0, 10.0 },
    });
    var limited = try source.decomposeSvd(.{
        .maximum_sweeps = 1,
    });
    try std.testing.expect(!limited.converged);
    try std.testing.expectError(
        error.SvdDidNotConverge,
        limited.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    const retained_limited_maximum_sweeps = limited.maximum_sweeps;
    limited.maximum_sweeps += 1;
    try std.testing.expect(!limited.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        limited.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    limited.maximum_sweeps = retained_limited_maximum_sweeps;
    try std.testing.expect(limited.valid());

    var corrupted = try source.decomposeSvd(.{});
    const retained_maximum_sweeps = corrupted.maximum_sweeps;
    corrupted.maximum_sweeps = 0;
    try std.testing.expect(!corrupted.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        corrupted.conditionNumber(),
    );
    corrupted.maximum_sweeps = retained_maximum_sweeps;
    try std.testing.expect(corrupted.valid());
    const retained_right_column = [_]f64{
        corrupted.right[0][0],
        corrupted.right[1][0],
        corrupted.right[2][0],
    };
    for (0..3) |row| corrupted.right[row][0] *= 0.5;
    try std.testing.expect(!corrupted.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        corrupted.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );
    for (0..3) |row|
        corrupted.right[row][0] = retained_right_column[row];
    try std.testing.expect(corrupted.valid());
    const retained_second_right_column = [_]f64{
        corrupted.right[0][1],
        corrupted.right[1][1],
        corrupted.right[2][1],
    };
    for (0..3) |row|
        corrupted.right[row][1] = corrupted.right[row][0];
    try std.testing.expect(!corrupted.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        corrupted.pseudoinverse(),
    );
    for (0..3) |row|
        corrupted.right[row][1] = retained_second_right_column[row];
    try std.testing.expect(corrupted.valid());
    corrupted.rank = 4;
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        corrupted.pseudoinverse(),
    );
    try std.testing.expectError(
        error.InvalidSvdTolerance,
        source.decomposeSvd(.{
            .convergence_tolerance = 0.0,
        }),
    );
}

test "SVD reconstructs dense matrices and reports conditioning" {
    const source = try Matrix(f64, 4, 3).init(.{
        .{ 1.0, -2.0, 0.5 },
        .{ 3.0, 4.0, -1.0 },
        .{ -2.0, 1.0, 5.0 },
        .{ 0.25, -0.75, 2.0 },
    });
    const decomposition = try source.decomposeSvd(.{});
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 3), decomposition.rank);
    const expected_singular_values =
        [_]f64{
            6.184337285920595,
            4.73430012269177,
            2.2837194841426935,
        };
    for (expected_singular_values, 0..) |expected, index| {
        try std.testing.expectApproxEqAbs(
            expected,
            decomposition.singular_values[index],
            0.000_000_000_01,
        );
    }
    const reconstructed = try decomposition.reconstruct();
    for (0..4) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                source.values[row][column],
                reconstructed.values[row][column],
                0.000_000_000_01,
            );
        }
    }
    const condition = try decomposition.conditionNumber();
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.708010913276501),
        condition,
        0.000_000_000_01,
    );

    const deficient = try (try Matrix(f64, 2, 2).init(.{
        .{ 1.0, 2.0 },
        .{ 2.0, 4.0 },
    })).decomposeSvd(.{});
    try std.testing.expectEqual(
        std.math.inf(f64),
        try deficient.conditionNumber(),
    );

    const source_f32 = try Matrix(f32, 3, 2).init(.{
        .{ 0.25, -1.0 },
        .{ 2.0, 0.5 },
        .{ -0.75, 3.0 },
    });
    const decomposition_f32 = try source_f32.decomposeSvd(.{});
    const reconstructed_f32 = try decomposition_f32.reconstruct();
    for (0..3) |row| {
        for (0..2) |column| {
            try std.testing.expectApproxEqAbs(
                source_f32.values[row][column],
                reconstructed_f32.values[row][column],
                0.000_1,
            );
        }
    }

    var zero = try Matrix(f32, 3, 2).zero().decomposeSvd(.{});
    try std.testing.expect(zero.converged);
    try std.testing.expectEqual(@as(usize, 0), zero.rank);
    try std.testing.expectEqualDeep(
        Matrix(f32, 2, 3).zero().values,
        (try zero.pseudoinverse()).values,
    );
    zero.left[0][0] = 0.5;
    try std.testing.expect(!zero.valid());
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        zero.reconstruct(),
    );
}

test "wide SVD reconstructs and solves underdetermined systems" {
    const source = try Matrix(f64, 2, 3).init(.{
        .{ 1.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
    });
    const decomposition = try source.decomposeSvd(.{});
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 2), decomposition.rank);
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 3.0)),
        decomposition.singular_values[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        decomposition.singular_values[1],
        0.000_000_000_001,
    );
    const reconstructed = try decomposition.reconstruct();
    for (0..2) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                source.values[row][column],
                reconstructed.values[row][column],
                0.000_000_000_001,
            );
        }
    }

    const solution =
        try decomposition.solveLeastSquares(.{ 1.0, 1.0 });
    for (
        [_]f64{ 1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0 },
        solution,
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
    const solved = try source.multiplyVector(
        try Vector(f64, 3).init(solution),
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solved.values[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        solved.values[1],
        0.000_000_000_001,
    );

    const pseudoinverse = try decomposition.pseudoinverse();
    const projected = try (try source.multiply(
        2,
        pseudoinverse,
    )).multiply(3, source);
    for (0..2) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                source.values[row][column],
                projected.values[row][column],
                0.000_000_000_001,
            );
        }
    }
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 3.0)),
        try decomposition.conditionNumber(),
        0.000_000_000_001,
    );
}

test "wide SVD handles rank loss and hostile state" {
    const limited_source = try Matrix(f64, 2, 3).init(.{
        .{ 1.0, 2.0, 3.0 },
        .{ 4.0, 5.0, 7.0 },
    });
    const limited = try limited_source.decomposeSvd(.{
        .maximum_sweeps = 1,
    });
    try std.testing.expect(!limited.converged);
    try std.testing.expectError(
        error.SvdDidNotConverge,
        limited.solveLeastSquares(.{ 1.0, 2.0 }),
    );

    const source = try Matrix(f64, 2, 3).init(.{
        .{ 1.0, 2.0, 3.0 },
        .{ 2.0, 4.0, 6.0 },
    });
    var decomposition = try source.decomposeSvd(.{});
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 1), decomposition.rank);
    const solution =
        try decomposition.solveLeastSquares(.{ 1.0, 2.0 });
    for (
        [_]f64{ 1.0 / 14.0, 1.0 / 7.0, 3.0 / 14.0 },
        solution,
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
    try std.testing.expectEqual(
        std.math.inf(f64),
        try decomposition.conditionNumber(),
    );

    decomposition.right[0][0] = std.math.nan(f64);
    try std.testing.expectError(
        error.InvalidSvdDecomposition,
        decomposition.reconstruct(),
    );

    const source_f32 = try Matrix(f32, 2, 4).init(.{
        .{ 0.25, -1.0, 2.0, 0.5 },
        .{ 1.5, 0.75, -0.5, 3.0 },
    });
    const decomposition_f32 = try source_f32.decomposeSvd(.{});
    const reconstructed_f32 = try decomposition_f32.reconstruct();
    for (0..2) |row| {
        for (0..4) |column| {
            try std.testing.expectApproxEqAbs(
                source_f32.values[row][column],
                reconstructed_f32.values[row][column],
                0.000_1,
            );
        }
    }

    const zero = try Matrix(f32, 2, 4).zero().decomposeSvd(.{});
    try std.testing.expect(zero.converged);
    try std.testing.expectEqual(@as(usize, 0), zero.rank);
    try std.testing.expectEqualDeep(
        Matrix(f32, 4, 2).zero().values,
        (try zero.pseudoinverse()).values,
    );
}

test "dynamic matrices own runtime-shaped arithmetic" {
    const D = DynamicMatrix(f64);
    var first = try D.fromSlice(
        std.testing.allocator,
        2,
        3,
        &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 },
    );
    defer first.deinit();
    var second = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 7.0, 8.0, 9.0, 10.0, 11.0, 12.0 },
    );
    defer second.deinit();
    var product = try first.multiply(&second, std.testing.allocator);
    defer product.deinit();
    try std.testing.expectEqualDeep(
        [_]f64{ 58.0, 64.0, 139.0, 154.0 },
        product.values[0..4].*,
    );

    var transposed = try first.transpose(std.testing.allocator);
    defer transposed.deinit();
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 4.0, 2.0, 5.0, 3.0, 6.0 },
        transposed.values[0..6].*,
    );
    var scaled = try first.scaled(-0.5, std.testing.allocator);
    defer scaled.deinit();
    try std.testing.expectEqual(
        @as(f64, -3.0),
        try scaled.at(1, 2),
    );
}

test "dynamic matrix caller-buffer arithmetic is transactional" {
    const D = DynamicMatrix(f64);
    var first = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 1.0, 2.0, 3.0, 4.0 },
    );
    defer first.deinit();
    var second = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 5.0, 6.0, 7.0, 8.0 },
    );
    defer second.deinit();
    var destination = try D.identity(std.testing.allocator, 2);
    defer destination.deinit();
    var workspace: [4]f64 = undefined;

    try first.addInto(&second, &destination, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ 6.0, 8.0, 10.0, 12.0 },
        destination.values[0..4].*,
    );
    try first.subtractInto(&second, &destination, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ -4.0, -4.0, -4.0, -4.0 },
        destination.values[0..4].*,
    );
    try first.scaledInto(-0.5, &destination, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ -0.5, -1.0, -1.5, -2.0 },
        destination.values[0..4].*,
    );
    try first.multiplyInto(&second, &destination, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ 19.0, 22.0, 43.0, 50.0 },
        destination.values[0..4].*,
    );
    try destination.transposeInto(&destination, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ 19.0, 43.0, 22.0, 50.0 },
        destination.values[0..4].*,
    );

    try first.addInto(&second, &first, &workspace);
    try std.testing.expectEqualDeep(
        [_]f64{ 6.0, 8.0, 10.0, 12.0 },
        first.values[0..4].*,
    );

    var rectangular = try D.fromSlice(
        std.testing.allocator,
        2,
        3,
        &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 },
    );
    defer rectangular.deinit();
    var transposed = try D.init(std.testing.allocator, 3, 2);
    defer transposed.deinit();
    var transpose_workspace: [6]f64 = undefined;
    try rectangular.transposeInto(
        &transposed,
        &transpose_workspace,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 1.0, 4.0, 2.0, 5.0, 3.0, 6.0 },
        transposed.values[0..6].*,
    );

    destination.values[0..4].* = .{ 7.0, 8.0, 9.0, 10.0 };
    try std.testing.expectError(
        error.DynamicMatrixShapeMismatch,
        rectangular.addInto(
            &rectangular,
            &destination,
            &transpose_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        destination.scaledInto(
            2.0,
            &destination,
            destination.values,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        first.scaledInto(
            2.0,
            &destination,
            first.values,
        ),
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        destination.scaledInto(
            std.math.inf(f64),
            &destination,
            &workspace,
        ),
    );
    first.values[0] = std.math.floatMax(f64);
    second.values[0] = std.math.floatMax(f64);
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        first.addInto(&second, &destination, &workspace),
    );
    second.values[0] = -std.math.floatMax(f64);
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        first.subtractInto(&second, &destination, &workspace),
    );
    second.values[0] = 2.0;
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        first.multiplyInto(&second, &destination, &workspace),
    );
    first.values[0] = 6.0;
    second.values[0] = 5.0;
    destination.values[0] = std.math.floatMax(f64);
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        destination.scaledInto(
            2.0,
            &destination,
            &workspace,
        ),
    );
    destination.values[0] = 7.0;
    try std.testing.expectEqualDeep(
        [_]f64{ 7.0, 8.0, 9.0, 10.0 },
        destination.values[0..4].*,
    );
}

test "dynamic matrix identity clone and checked mutation" {
    const D = DynamicMatrix(f32);
    var identity = try D.identity(std.testing.allocator, 3);
    defer identity.deinit();
    try identity.set(0, 2, 0.25);
    try std.testing.expectEqualDeep(
        [_]f32{ 1.0, 0.0, 0.25 },
        (try identity.row(0))[0..3].*,
    );
    var copy = try identity.clone(std.testing.allocator);
    defer copy.deinit();
    try std.testing.expectEqualDeep(identity.values, copy.values);
    try std.testing.expectError(
        error.DynamicMatrixIndexOutOfRange,
        identity.set(3, 0, 1.0),
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        identity.set(0, 0, std.math.nan(f32)),
    );
    try std.testing.expectEqual(@as(f32, 1.0), try identity.at(0, 0));
}

test "dynamic matrix vector multiplication is transactional" {
    const D = DynamicMatrix(f64);
    var matrix = try D.fromSlice(
        std.testing.allocator,
        2,
        3,
        &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 },
    );
    defer matrix.deinit();
    const allocated = try matrix.multiplyVector(
        &.{ 1.0, 0.0, -1.0 },
        std.testing.allocator,
    );
    defer std.testing.allocator.free(allocated);
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        allocated[0..2].*,
    );

    var in_place = [_]f64{ 1.0, 0.0, -1.0 };
    var workspace: [2]f64 = undefined;
    try matrix.multiplyVectorInto(
        &in_place,
        in_place[0..2],
        &workspace,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ -2.0, -2.0 },
        in_place[0..2].*,
    );

    var destination = [_]f64{ 7.0, 8.0 };
    try std.testing.expectError(
        error.DynamicMatrixShapeMismatch,
        matrix.multiplyVectorInto(
            &.{ 1.0, 2.0 },
            &destination,
            &workspace,
        ),
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        matrix.multiplyVectorInto(
            &.{ 1.0, std.math.nan(f64), 3.0 },
            &destination,
            &workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        matrix.multiplyVectorInto(
            &.{ 1.0, 2.0, 3.0 },
            &destination,
            &destination,
        ),
    );
    const retained_values = matrix.values[0..6].*;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        matrix.multiplyVectorInto(
            &.{ 1.0, 2.0, 3.0 },
            matrix.values[0..2],
            &workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        matrix.multiplyVectorInto(
            &.{ 1.0, 2.0, 3.0 },
            &destination,
            matrix.values[0..2],
        ),
    );
    try std.testing.expectEqualDeep(
        retained_values,
        matrix.values[0..6].*,
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 7.0, 8.0 },
        destination,
    );

    var failing_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 1 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        matrix.multiplyVector(
            &.{ 1.0, 2.0, 3.0 },
            failing_allocator.allocator(),
        ),
    );

    matrix.values[0] = std.math.floatMax(f64);
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        matrix.multiplyVectorInto(
            &.{ 2.0, 0.0, 0.0 },
            &destination,
            &workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 7.0, 8.0 },
        destination,
    );
}

test "dynamic matrices reject shapes overflow and hostile state" {
    const D = DynamicMatrix(f64);
    try std.testing.expectError(
        error.InvalidDynamicMatrixDimensions,
        D.init(std.testing.allocator, 0, 1),
    );
    try std.testing.expectError(
        error.DynamicMatrixDimensionsOverflow,
        D.init(std.testing.allocator, std.math.maxInt(usize), 2),
    );
    try std.testing.expectError(
        error.DynamicMatrixShapeMismatch,
        D.fromSlice(std.testing.allocator, 2, 2, &.{1.0}),
    );
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        D.fromSlice(
            std.testing.allocator,
            1,
            1,
            &.{std.math.inf(f64)},
        ),
    );

    var first = try D.init(std.testing.allocator, 2, 2);
    defer first.deinit();
    var second = try D.init(std.testing.allocator, 3, 1);
    defer second.deinit();
    try std.testing.expectError(
        error.DynamicMatrixShapeMismatch,
        first.add(&second, std.testing.allocator),
    );
    try std.testing.expectError(
        error.DynamicMatrixShapeMismatch,
        first.multiply(&second, std.testing.allocator),
    );
    first.values[0] = std.math.nan(f64);
    try std.testing.expect(!first.valid());
    try std.testing.expectError(
        error.InvalidDynamicMatrix,
        first.clone(std.testing.allocator),
    );

    var released = try D.init(std.testing.allocator, 1, 1);
    released.deinit();
    released.deinit();
    try std.testing.expect(!released.valid());
}

test "dynamic owners reject retained shape corruption after repeatable close" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 3.0, 1.0, 1.0, 2.0 },
    );
    defer source.deinit();
    var lu = try source.decomposeLu(std.testing.allocator);
    defer lu.deinit();
    var qr = try source.decomposeQr(std.testing.allocator);
    defer qr.deinit();
    var svd = try source.decomposeSvd(std.testing.allocator, .{});
    defer svd.deinit();

    source.rows = std.math.maxInt(usize);
    try std.testing.expect(!source.valid());
    try std.testing.expectError(
        error.InvalidDynamicMatrix,
        source.clone(std.testing.allocator),
    );
    source.rows = 2;

    lu.dimensions = std.math.maxInt(usize);
    try std.testing.expect(!lu.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        lu.determinant(),
    );
    lu.dimensions = 2;

    qr.rows = std.math.maxInt(usize);
    try std.testing.expect(!qr.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        qr.upper(std.testing.allocator),
    );
    qr.rows = 2;

    svd.rows = std.math.maxInt(usize);
    try std.testing.expect(!svd.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.conditionNumber(),
    );
    svd.rows = 2;

    source.deinit();
    source.deinit();
    try std.testing.expectError(
        error.InvalidDynamicMatrix,
        source.clone(std.testing.allocator),
    );
    lu.deinit();
    lu.deinit();
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        lu.determinant(),
    );
    qr.deinit();
    qr.deinit();
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        qr.upper(std.testing.allocator),
    );
    svd.deinit();
    svd.deinit();
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        svd.conditionNumber(),
    );
}

test "dynamic LU solves reusable vector and matrix systems" {
    const D = DynamicMatrix(f64);
    var coefficients = try D.fromSlice(
        std.testing.allocator,
        3,
        3,
        &.{
            0.0, 2.0,  1.0,
            1.0, -2.0, -3.0,
            3.0, -1.0, 2.0,
        },
    );
    defer coefficients.deinit();
    var decomposition = try coefficients.decomposeLu(
        std.testing.allocator,
    );
    defer decomposition.deinit();

    var solution: [3]f64 = undefined;
    var workspace: [3]f64 = undefined;
    try decomposition.solveInto(
        &.{ 3.0, -4.0, 4.0 },
        &solution,
        &workspace,
    );
    for (solution) |value| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            value,
            0.000_000_000_001,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, -17.0),
        try decomposition.determinant(),
        0.000_000_000_001,
    );

    var inverse = try decomposition.inverse(std.testing.allocator);
    defer inverse.deinit();
    var identity = try coefficients.multiply(
        &inverse,
        std.testing.allocator,
    );
    defer identity.deinit();
    for (0..3) |row| {
        for (0..3) |column| {
            try std.testing.expectApproxEqAbs(
                if (row == column) @as(f64, 1.0) else 0.0,
                identity.values[row * 3 + column],
                0.000_000_000_001,
            );
        }
    }

    var right = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 3.0, 6.0, -4.0, -8.0, 4.0, 8.0 },
    );
    defer right.deinit();
    var multiple = try decomposition.solveMatrix(
        std.testing.allocator,
        &right,
    );
    defer multiple.deinit();
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0),
        multiple.values[1],
        0.000_000_000_001,
    );
}

test "dynamic decompositions solve tiny systems" {
    const D = DynamicMatrix(f64);
    var square = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 1.0e-200, 0.0, 0.0, 2.0e-200 },
    );
    defer square.deinit();
    var lu = try square.decomposeLu(std.testing.allocator);
    defer lu.deinit();
    const lu_solution = try lu.solve(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200 },
    );
    defer std.testing.allocator.free(lu_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        lu_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        lu_solution[1],
        0.000_000_000_001,
    );

    var tall = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{
            1.0e-200, 0.0,
            0.0,      2.0e-200,
            1.0e-200, 2.0e-200,
        },
    );
    defer tall.deinit();
    var qr = try tall.decomposeQr(std.testing.allocator);
    defer qr.deinit();
    const qr_solution = try qr.solveLeastSquares(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200, -5.0e-200 },
    );
    defer std.testing.allocator.free(qr_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        qr_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        qr_solution[1],
        0.000_000_000_001,
    );

    var svd = try tall.decomposeSvd(std.testing.allocator, .{});
    defer svd.deinit();
    const svd_solution = try svd.solveLeastSquares(
        std.testing.allocator,
        &.{ 3.0e-200, -8.0e-200, -5.0e-200 },
    );
    defer std.testing.allocator.free(svd_solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        svd_solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -4.0),
        svd_solution[1],
        0.000_000_000_001,
    );
}

test "dynamic LU rejects singular shapes aliases and hostile state" {
    const D = DynamicMatrix(f32);
    var rectangular = try D.init(std.testing.allocator, 2, 3);
    defer rectangular.deinit();
    try std.testing.expectError(
        error.DynamicMatrixNotSquare,
        rectangular.decomposeLu(std.testing.allocator),
    );
    var singular = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 1.0, 2.0, 2.0, 4.0 },
    );
    defer singular.deinit();
    try std.testing.expectError(
        error.SingularMatrix,
        singular.decomposeLu(std.testing.allocator),
    );

    var source = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 2.0, 1.0, 1.0, 2.0 },
    );
    defer source.deinit();
    var decomposition = try source.decomposeLu(
        std.testing.allocator,
    );
    defer decomposition.deinit();
    var aliased = [_]f32{ 1.0, 2.0 };
    var destination: [2]f32 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        decomposition.solveInto(
            &aliased,
            &destination,
            &aliased,
        ),
    );
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        decomposition.determinant(),
    );
    decomposition.odd_swaps = !decomposition.odd_swaps;
    try std.testing.expect(decomposition.valid());
    const retained_matrix_scale = decomposition.matrix_scale;
    decomposition.matrix_scale *= 2.0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        decomposition.determinant(),
    );
    decomposition.matrix_scale = retained_matrix_scale;
    try std.testing.expect(decomposition.valid());
    const retained_pivot_tolerance = decomposition.pivot_tolerance;
    decomposition.pivot_tolerance *= 2.0;
    try std.testing.expect(!decomposition.valid());
    decomposition.pivot_tolerance = retained_pivot_tolerance;
    try std.testing.expect(decomposition.valid());
    decomposition.permutation[1] = decomposition.permutation[0];
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicLuDecomposition,
        decomposition.determinant(),
    );
}

test "dynamic QR reconstructs and solves tall least squares" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 1.0, 1.0, 1.0, 2.0, 1.0, 3.0 },
    );
    defer source.deinit();
    var decomposition = try source.decomposeQr(
        std.testing.allocator,
    );
    defer decomposition.deinit();

    var orthogonal = try decomposition.orthogonal(
        std.testing.allocator,
    );
    defer orthogonal.deinit();
    var upper = try decomposition.upper(std.testing.allocator);
    defer upper.deinit();
    var reconstructed = try orthogonal.multiply(
        &upper,
        std.testing.allocator,
    );
    defer reconstructed.deinit();
    for (source.values, reconstructed.values) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }

    const solution = try decomposition.solveLeastSquares(
        std.testing.allocator,
        &.{ 1.0, 2.0, 2.0 },
    );
    defer std.testing.allocator.free(solution);
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0 / 3.0),
        solution[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        solution[1],
        0.000_000_000_001,
    );
}

test "dynamic QR rejects wide rank deficient and corrupted inputs" {
    const D = DynamicMatrix(f32);
    var wide = try D.init(std.testing.allocator, 2, 3);
    defer wide.deinit();
    try std.testing.expectError(
        error.DynamicQrRequiresTallMatrix,
        wide.decomposeQr(std.testing.allocator),
    );
    var deficient = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 1.0, 2.0, 2.0, 4.0, 3.0, 6.0 },
    );
    defer deficient.deinit();
    try std.testing.expectError(
        error.RankDeficientMatrix,
        deficient.decomposeQr(std.testing.allocator),
    );

    var source = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 1.0, 0.0, 0.0, 1.0, 1.0, 1.0 },
    );
    defer source.deinit();
    var decomposition = try source.decomposeQr(
        std.testing.allocator,
    );
    defer decomposition.deinit();
    const retained_tau = decomposition.tau[0];
    decomposition.tau[0] *= 0.5;
    var finite_destination = [_]f32{ -17.0, 23.0 };
    var finite_workspace = [_]f32{ 31.0, -37.0, 41.0 };
    const expected_destination = finite_destination;
    const expected_workspace = finite_workspace;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        decomposition.solveLeastSquaresInto(
            &.{ 1.0, 2.0, 3.0 },
            &finite_destination,
            &finite_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        expected_destination,
        finite_destination,
    );
    try std.testing.expectEqualDeep(
        expected_workspace,
        finite_workspace,
    );
    decomposition.tau[0] = retained_tau;
    try std.testing.expect(decomposition.valid());
    const retained_matrix_scale = decomposition.matrix_scale;
    decomposition.matrix_scale *= 2.0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        decomposition.solveLeastSquaresInto(
            &.{ 1.0, 2.0, 3.0 },
            &finite_destination,
            &finite_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        expected_destination,
        finite_destination,
    );
    try std.testing.expectEqualDeep(
        expected_workspace,
        finite_workspace,
    );
    decomposition.matrix_scale = retained_matrix_scale;
    try std.testing.expect(decomposition.valid());
    const retained_rank_tolerance = decomposition.rank_tolerance;
    decomposition.rank_tolerance *= 2.0;
    try std.testing.expect(!decomposition.valid());
    decomposition.rank_tolerance = retained_rank_tolerance;
    try std.testing.expect(decomposition.valid());
    decomposition.tau[0] = std.math.nan(f32);
    var destination: [2]f32 = undefined;
    var workspace: [3]f32 = undefined;
    try std.testing.expectError(
        error.InvalidDynamicQrDecomposition,
        decomposition.solveLeastSquaresInto(
            &.{ 1.0, 2.0, 3.0 },
            &destination,
            &workspace,
        ),
    );
}

test "dynamic SVD reconstructs pseudoinverts and reports conditioning" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        4,
        3,
        &.{
            1.0,  -2.0,  0.5,
            3.0,  4.0,   -1.0,
            -2.0, 1.0,   5.0,
            0.25, -0.75, 2.0,
        },
    );
    defer source.deinit();
    var decomposition = try source.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer decomposition.deinit();
    try std.testing.expect(decomposition.converged);
    try std.testing.expectEqual(@as(usize, 3), decomposition.rank);
    for (
        [_]f64{
            6.184337285920595,
            4.73430012269177,
            2.2837194841426935,
        },
        decomposition.singular_values,
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_01,
        );
    }
    var reconstructed = try decomposition.reconstruct(
        std.testing.allocator,
    );
    defer reconstructed.deinit();
    for (source.values, reconstructed.values) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_01,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.708010913276501),
        try decomposition.conditionNumber(),
        0.000_000_000_01,
    );

    var pseudoinverse = try decomposition.pseudoinverse(
        std.testing.allocator,
    );
    defer pseudoinverse.deinit();
    var first_projection = try source.multiply(
        &pseudoinverse,
        std.testing.allocator,
    );
    defer first_projection.deinit();
    var projected = try first_projection.multiply(
        &source,
        std.testing.allocator,
    );
    defer projected.deinit();
    for (source.values, projected.values) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_01,
        );
    }
}

test "dynamic wide SVD returns minimum norm solutions" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        2,
        3,
        &.{ 1.0, 0.0, 1.0, 0.0, 1.0, 1.0 },
    );
    defer source.deinit();
    var decomposition = try source.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer decomposition.deinit();
    try std.testing.expect(decomposition.converged);
    const solution = try decomposition.solveLeastSquares(
        std.testing.allocator,
        &.{ 1.0, 1.0 },
    );
    defer std.testing.allocator.free(solution);
    for (
        [_]f64{ 1.0 / 3.0, 1.0 / 3.0, 2.0 / 3.0 },
        solution,
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }

    var reconstructed = try decomposition.reconstruct(
        std.testing.allocator,
    );
    defer reconstructed.deinit();
    for (source.values, reconstructed.values) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
}

test "dynamic SVD handles rank loss convergence and hostile state" {
    const D = DynamicMatrix(f32);
    var deficient = try D.fromSlice(
        std.testing.allocator,
        3,
        2,
        &.{ 1.0, 2.0, 2.0, 4.0, 3.0, 6.0 },
    );
    defer deficient.deinit();
    var decomposition = try deficient.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer decomposition.deinit();
    try std.testing.expectEqual(@as(usize, 1), decomposition.rank);
    try std.testing.expectEqual(
        std.math.inf(f32),
        try decomposition.conditionNumber(),
    );

    var limited_source = try D.fromSlice(
        std.testing.allocator,
        3,
        3,
        &.{
            1.0, 2.0, 3.0,
            4.0, 5.0, 6.0,
            7.0, 8.0, 10.0,
        },
    );
    defer limited_source.deinit();
    var limited = try limited_source.decomposeSvd(
        std.testing.allocator,
        .{ .maximum_sweeps = 1 },
    );
    defer limited.deinit();
    try std.testing.expect(!limited.converged);
    try std.testing.expectError(
        error.SvdDidNotConverge,
        limited.conditionNumber(),
    );
    const retained_limited_maximum_sweeps = limited.maximum_sweeps;
    limited.maximum_sweeps += 1;
    try std.testing.expect(!limited.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        limited.conditionNumber(),
    );
    limited.maximum_sweeps = retained_limited_maximum_sweeps;
    try std.testing.expect(limited.valid());
    try std.testing.expectError(
        error.InvalidSvdTolerance,
        limited_source.decomposeSvd(
            std.testing.allocator,
            .{ .convergence_tolerance = 0.0 },
        ),
    );

    const retained_maximum_sweeps = decomposition.maximum_sweeps;
    decomposition.maximum_sweeps = 0;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        decomposition.conditionNumber(),
    );
    decomposition.maximum_sweeps = retained_maximum_sweeps;
    try std.testing.expect(decomposition.valid());

    const retained_right_column = [_]f32{
        decomposition.right[0],
        decomposition.right[2],
    };
    decomposition.right[0] *= 0.5;
    decomposition.right[2] *= 0.5;
    var destination = [_]f32{ 43.0, -47.0 };
    var projection_workspace = [_]f32{ 53.0, -59.0 };
    var solution_workspace = [_]f32{ 61.0, -67.0 };
    const expected_destination = destination;
    const expected_projection = projection_workspace;
    const expected_solution = solution_workspace;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        decomposition.solveLeastSquaresInto(
            &.{ 1.0, 2.0, 3.0 },
            &destination,
            &projection_workspace,
            &solution_workspace,
        ),
    );
    try std.testing.expectEqualDeep(expected_destination, destination);
    try std.testing.expectEqualDeep(
        expected_projection,
        projection_workspace,
    );
    try std.testing.expectEqualDeep(expected_solution, solution_workspace);
    decomposition.right[0] = retained_right_column[0];
    decomposition.right[2] = retained_right_column[1];
    try std.testing.expect(decomposition.valid());

    const retained_second_right_column = [_]f32{
        decomposition.right[1],
        decomposition.right[3],
    };
    decomposition.right[1] = decomposition.right[0];
    decomposition.right[3] = decomposition.right[2];
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        decomposition.conditionNumber(),
    );
    decomposition.right[1] = retained_second_right_column[0];
    decomposition.right[3] = retained_second_right_column[1];
    try std.testing.expect(decomposition.valid());

    decomposition.rank = 3;
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidDynamicSvdDecomposition,
        decomposition.conditionNumber(),
    );
}

fn exerciseDynamicMatrixAllocations(
    allocator: std.mem.Allocator,
) !void {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        allocator,
        3,
        3,
        &.{
            4.0, 1.0, 0.0,
            1.0, 3.0, 1.0,
            0.0, 1.0, 2.0,
        },
    );
    defer source.deinit();
    var copy = try source.clone(allocator);
    defer copy.deinit();
    var identity = try D.identity(allocator, 3);
    defer identity.deinit();
    var sum = try source.add(&identity, allocator);
    defer sum.deinit();
    var difference = try source.subtract(&identity, allocator);
    defer difference.deinit();
    var scaled = try source.scaled(0.5, allocator);
    defer scaled.deinit();
    var transposed = try source.transpose(allocator);
    defer transposed.deinit();
    var product = try source.multiply(&identity, allocator);
    defer product.deinit();
    const vector_product = try source.multiplyVector(
        &.{ 1.0, 2.0, 3.0 },
        allocator,
    );
    defer allocator.free(vector_product);

    var lu = try source.decomposeLu(allocator);
    defer lu.deinit();
    const lu_solution = try lu.solve(
        allocator,
        &.{ 1.0, 2.0, 3.0 },
    );
    defer allocator.free(lu_solution);
    var right_hand_side = try D.fromSlice(
        allocator,
        3,
        2,
        &.{ 1.0, 2.0, 3.0, 4.0, 5.0, 6.0 },
    );
    defer right_hand_side.deinit();
    var matrix_solution = try lu.solveMatrix(
        allocator,
        &right_hand_side,
    );
    defer matrix_solution.deinit();
    var inverse = try lu.inverse(allocator);
    defer inverse.deinit();

    var qr = try source.decomposeQr(allocator);
    defer qr.deinit();
    const qr_solution = try qr.solveLeastSquares(
        allocator,
        &.{ 1.0, 2.0, 3.0 },
    );
    defer allocator.free(qr_solution);
    var upper = try qr.upper(allocator);
    defer upper.deinit();
    var orthogonal = try qr.orthogonal(allocator);
    defer orthogonal.deinit();

    var svd = try source.decomposeSvd(allocator, .{});
    defer svd.deinit();
    const svd_solution = try svd.solveLeastSquares(
        allocator,
        &.{ 1.0, 2.0, 3.0 },
    );
    defer allocator.free(svd_solution);
    var pseudoinverse = try svd.pseudoinverse(allocator);
    defer pseudoinverse.deinit();
    var reconstructed = try svd.reconstruct(allocator);
    defer reconstructed.deinit();

    var wide_source = try D.fromSlice(
        allocator,
        2,
        3,
        &.{ 1.0, 0.0, 1.0, 0.0, 1.0, 1.0 },
    );
    defer wide_source.deinit();
    var wide_svd = try wide_source.decomposeSvd(allocator, .{});
    defer wide_svd.deinit();
    var wide_reconstructed = try wide_svd.reconstruct(allocator);
    defer wide_reconstructed.deinit();
    var wide_pseudoinverse = try wide_svd.pseudoinverse(allocator);
    defer wide_pseudoinverse.deinit();
}

test "dynamic matrix allocation failures release every owner" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        exerciseDynamicMatrixAllocations,
        .{},
    );
}

test "dynamic matrix overlap checks contain hostile address spans" {
    const aligned_maximum = std.math.maxInt(usize) -
        (@alignOf(f64) - 1);
    const hostile_pointer: [*]const f64 =
        @ptrFromInt(aligned_maximum);
    const hostile = hostile_pointer[0..2];
    var ordinary = [_]f64{ 1.0, 2.0 };
    try std.testing.expect(slicesOverlap(
        f64,
        hostile,
        &ordinary,
    ));
}

test "dynamic decomposition allocation failures leave no ownership" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        3,
        3,
        &.{
            2.0, 1.0, 0.0,
            1.0, 3.0, 1.0,
            0.0, 1.0, 2.0,
        },
    );
    defer source.deinit();

    var lu_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 1 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        source.decomposeLu(lu_allocator.allocator()),
    );
    var qr_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 1 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        source.decomposeQr(qr_allocator.allocator()),
    );
    var svd_allocator = std.testing.FailingAllocator.init(
        std.testing.allocator,
        .{ .fail_index = 2 },
    );
    try std.testing.expectError(
        error.OutOfMemory,
        source.decomposeSvd(svd_allocator.allocator(), .{}),
    );
}

test "dynamic caller-buffer solve failures preserve destinations" {
    const D = DynamicMatrix(f64);
    var identity = try D.identity(std.testing.allocator, 2);
    defer identity.deinit();

    var lu = try identity.decomposeLu(std.testing.allocator);
    defer lu.deinit();
    lu.factors[2] = std.math.floatMax(f64);
    var lu_destination = [_]f64{ 7.0, 8.0 };
    var lu_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        lu.solveInto(
            &.{ std.math.floatMax(f64), std.math.floatMax(f64) },
            &lu_destination,
            &lu_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 7.0, 8.0 },
        lu_destination,
    );

    var qr = try identity.decomposeQr(std.testing.allocator);
    defer qr.deinit();
    var qr_destination = [_]f64{ 9.0, 10.0 };
    var qr_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        qr.solveLeastSquaresInto(
            &.{ std.math.floatMax(f64), std.math.floatMax(f64) },
            &qr_destination,
            &qr_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 9.0, 10.0 },
        qr_destination,
    );

    var svd_source = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 1.0, 1.0, 1.0, -1.0 },
    );
    defer svd_source.deinit();
    var svd = try svd_source.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer svd.deinit();
    var svd_destination = [_]f64{ 11.0, 12.0 };
    var projection_workspace: [2]f64 = undefined;
    var solution_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        svd.solveLeastSquaresInto(
            &.{ std.math.floatMax(f64), std.math.floatMax(f64) },
            &svd_destination,
            &projection_workspace,
            &solution_workspace,
        ),
    );
    try std.testing.expectEqualDeep(
        [_]f64{ 11.0, 12.0 },
        svd_destination,
    );
}

test "dynamic caller-buffer solves preserve decomposition ownership" {
    const D = DynamicMatrix(f64);
    var source = try D.fromSlice(
        std.testing.allocator,
        2,
        2,
        &.{ 3.0, 1.0, 1.0, 2.0 },
    );
    defer source.deinit();

    var lu = try source.decomposeLu(std.testing.allocator);
    defer lu.deinit();
    const lu_factors = lu.factors[0..4].*;
    var lu_destination: [2]f64 = undefined;
    var lu_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        lu.solveInto(
            &.{ 7.0, 5.0 },
            lu.factors[0..2],
            &lu_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        lu.solveInto(
            &.{ 7.0, 5.0 },
            &lu_destination,
            lu.factors[0..2],
        ),
    );
    try std.testing.expectEqualDeep(lu_factors, lu.factors[0..4].*);
    try std.testing.expect(lu.valid());

    var qr = try source.decomposeQr(std.testing.allocator);
    defer qr.deinit();
    const qr_factors = qr.factors[0..4].*;
    const qr_tau = qr.tau[0..2].*;
    var qr_destination: [2]f64 = undefined;
    var qr_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        qr.solveLeastSquaresInto(
            &.{ 7.0, 5.0 },
            qr.tau,
            &qr_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        qr.solveLeastSquaresInto(
            &.{ 7.0, 5.0 },
            &qr_destination,
            qr.factors[0..2],
        ),
    );
    try std.testing.expectEqualDeep(qr_factors, qr.factors[0..4].*);
    try std.testing.expectEqualDeep(qr_tau, qr.tau[0..2].*);
    try std.testing.expect(qr.valid());

    var svd = try source.decomposeSvd(std.testing.allocator, .{});
    defer svd.deinit();
    const svd_left = svd.left[0..4].*;
    const singular_values = svd.singular_values[0..2].*;
    const svd_right = svd.right[0..4].*;
    var svd_destination: [2]f64 = undefined;
    var projection_workspace: [2]f64 = undefined;
    var solution_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        svd.solveLeastSquaresInto(
            &.{ 7.0, 5.0 },
            svd.left[0..2],
            &projection_workspace,
            &solution_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        svd.solveLeastSquaresInto(
            &.{ 7.0, 5.0 },
            &svd_destination,
            svd.singular_values,
            &solution_workspace,
        ),
    );
    try std.testing.expectError(
        error.DynamicMatrixAliasedBuffers,
        svd.solveLeastSquaresInto(
            &.{ 7.0, 5.0 },
            &svd_destination,
            &projection_workspace,
            svd.right[0..2],
        ),
    );
    try std.testing.expectEqualDeep(svd_left, svd.left[0..4].*);
    try std.testing.expectEqualDeep(
        singular_values,
        svd.singular_values[0..2].*,
    );
    try std.testing.expectEqualDeep(svd_right, svd.right[0..4].*);
    try std.testing.expect(svd.valid());
}
