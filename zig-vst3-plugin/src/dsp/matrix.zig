const std = @import("std");

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
        converged: bool,
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
                    .converged = transposed.converged,
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
                .converged = converged,
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
            return true;
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
        rank_tolerance: Sample,

        pub fn init(matrix: Source) !Self {
            if (!matrix.valid()) return error.InvalidMatrix;
            var result = Self{
                .factors = matrix.values,
                .tau = @splat(0.0),
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
            if (!std.math.isFinite(self.rank_tolerance) or
                self.rank_tolerance < 0.0)
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

        pub fn init(matrix: Square) !Self {
            if (!matrix.valid()) return error.InvalidMatrix;
            var result = Self{
                .factors = matrix.values,
                .permutation = undefined,
                .odd_swaps = false,
            };
            for (0..dimensions) |index|
                result.permutation[index] = index;

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
                    pivot_magnitude <= std.math.floatEps(Sample))
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
            var seen: [dimensions]bool = @splat(false);
            for (0..dimensions) |row| {
                const source = self.permutation[row];
                if (source >= dimensions or seen[source])
                    return false;
                seen[source] = true;
                for (0..dimensions) |column| {
                    if (!std.math.isFinite(
                        self.factors[row][column],
                    ))
                        return false;
                }
                if (@abs(self.factors[row][row]) <=
                    std.math.floatEps(Sample))
                    return false;
            }
            return true;
        }
    };
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

test "matrix transpose add and scale preserve fixed dimensions" {
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
    decomposition.permutation[1] = decomposition.permutation[0];
    try std.testing.expect(!decomposition.valid());
    try std.testing.expectError(
        error.InvalidMatrixDecomposition,
        decomposition.solve(.{ 1.0, 1.0 }),
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

    var overflow = try Tiny.identity().decomposeQr();
    overflow.factors[1][0] = std.math.floatMax(f64);
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
    const limited = try source.decomposeSvd(.{
        .maximum_sweeps = 1,
    });
    try std.testing.expect(!limited.converged);
    try std.testing.expectError(
        error.SvdDidNotConverge,
        limited.solveLeastSquares(.{ 1.0, 2.0, 3.0 }),
    );

    var corrupted = try source.decomposeSvd(.{});
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

    const zero = try Matrix(f32, 3, 2).zero().decomposeSvd(.{});
    try std.testing.expect(zero.converged);
    try std.testing.expectEqual(@as(usize, 0), zero.rank);
    try std.testing.expectEqualDeep(
        Matrix(f32, 2, 3).zero().values,
        (try zero.pseudoinverse()).values,
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
