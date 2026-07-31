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
pub fn DynamicMatrix(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("DynamicMatrix supports f32 and f64 elements");

    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        rows: usize,
        columns: usize,
        values: []Sample,

        pub fn init(
            allocator: std.mem.Allocator,
            rows: usize,
            columns: usize,
        ) !Self {
            const element_count = try checkedElementCount(rows, columns);
            const values = try allocator.alloc(Sample, element_count);
            @memset(values, 0.0);
            return .{
                .allocator = allocator,
                .rows = rows,
                .columns = columns,
                .values = values,
            };
        }

        pub fn fromSlice(
            allocator: std.mem.Allocator,
            rows: usize,
            columns: usize,
            source: []const Sample,
        ) !Self {
            const element_count = try checkedElementCount(rows, columns);
            if (source.len != element_count)
                return error.DynamicMatrixShapeMismatch;
            for (source) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }
            const result = try init(allocator, rows, columns);
            @memcpy(result.values, source);
            return result;
        }

        pub fn identity(
            allocator: std.mem.Allocator,
            dimensions: usize,
        ) !Self {
            var result = try init(allocator, dimensions, dimensions);
            for (0..dimensions) |index|
                result.values[index * dimensions + index] = 1.0;
            return result;
        }

        pub fn deinit(self: *Self) void {
            if (self.values.len != 0)
                self.allocator.free(self.values);
            self.rows = 0;
            self.columns = 0;
            self.values = &.{};
        }

        pub fn clone(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Self {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            return fromSlice(
                allocator,
                self.rows,
                self.columns,
                self.values,
            );
        }

        pub fn at(
            self: *const Self,
            row_index: usize,
            column: usize,
        ) !Sample {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (row_index >= self.rows or column >= self.columns)
                return error.DynamicMatrixIndexOutOfRange;
            return self.values[row_index * self.columns + column];
        }

        pub fn set(
            self: *Self,
            row_index: usize,
            column: usize,
            value: Sample,
        ) !void {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (row_index >= self.rows or column >= self.columns)
                return error.DynamicMatrixIndexOutOfRange;
            if (!std.math.isFinite(value))
                return error.MatrixNonFiniteValue;
            self.values[row_index * self.columns + column] = value;
        }

        pub fn row(
            self: *const Self,
            row_index: usize,
        ) ![]const Sample {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (row_index >= self.rows)
                return error.DynamicMatrixIndexOutOfRange;
            const start = row_index * self.columns;
            return self.values[start .. start + self.columns];
        }

        pub fn add(
            self: *const Self,
            other: *const Self,
            allocator: std.mem.Allocator,
        ) !Self {
            try validateSameShape(self, other);
            var result = try init(allocator, self.rows, self.columns);
            errdefer result.deinit();
            for (self.values, other.values, result.values) |
                first,
                second,
                *destination,
            | {
                const value = first + second;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                destination.* = value;
            }
            return result;
        }

        pub fn subtract(
            self: *const Self,
            other: *const Self,
            allocator: std.mem.Allocator,
        ) !Self {
            try validateSameShape(self, other);
            var result = try init(allocator, self.rows, self.columns);
            errdefer result.deinit();
            for (self.values, other.values, result.values) |
                first,
                second,
                *destination,
            | {
                const value = first - second;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                destination.* = value;
            }
            return result;
        }

        pub fn scaled(
            self: *const Self,
            factor: Sample,
            allocator: std.mem.Allocator,
        ) !Self {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (!std.math.isFinite(factor))
                return error.MatrixNonFiniteValue;
            var result = try init(allocator, self.rows, self.columns);
            errdefer result.deinit();
            for (self.values, result.values) |source, *destination| {
                const value = source * factor;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                destination.* = value;
            }
            return result;
        }

        pub fn transpose(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Self {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            var result = try init(allocator, self.columns, self.rows);
            for (0..self.rows) |row_index| {
                for (0..self.columns) |column_index| {
                    result.values[
                        column_index * self.rows + row_index
                    ] = self.values[
                        row_index * self.columns + column_index
                    ];
                }
            }
            return result;
        }

        pub fn multiply(
            self: *const Self,
            other: *const Self,
            allocator: std.mem.Allocator,
        ) !Self {
            if (!self.valid() or !other.valid())
                return error.InvalidDynamicMatrix;
            if (self.columns != other.rows)
                return error.DynamicMatrixShapeMismatch;
            var result = try init(allocator, self.rows, other.columns);
            errdefer result.deinit();
            for (0..self.rows) |row_index| {
                for (0..other.columns) |column_index| {
                    var value: Sample = 0.0;
                    for (0..self.columns) |inner| {
                        value +=
                            self.values[
                                row_index * self.columns + inner
                            ] *
                            other.values[
                                inner * other.columns + column_index
                            ];
                        if (!std.math.isFinite(value))
                            return error.MatrixNonFiniteValue;
                    }
                    result.values[
                        row_index * other.columns + column_index
                    ] = value;
                }
            }
            return result;
        }

        pub fn multiplyVectorInto(
            self: *const Self,
            vector: []const Sample,
            destination: []Sample,
            workspace: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (vector.len != self.columns or
                destination.len != self.rows or
                workspace.len != self.rows)
                return error.DynamicMatrixShapeMismatch;
            if (slicesOverlap(Sample, vector, workspace) or
                slicesOverlap(Sample, destination, workspace))
                return error.DynamicMatrixAliasedBuffers;
            for (vector) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }
            for (0..self.rows) |row_index| {
                var value: Sample = 0.0;
                for (0..self.columns) |column_index| {
                    value += self.values[
                        row_index * self.columns + column_index
                    ] * vector[column_index];
                    if (!std.math.isFinite(value))
                        return error.MatrixNonFiniteValue;
                }
                workspace[row_index] = value;
            }
            @memcpy(destination, workspace);
        }

        pub fn multiplyVector(
            self: *const Self,
            vector: []const Sample,
            allocator: std.mem.Allocator,
        ) ![]Sample {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (vector.len != self.columns)
                return error.DynamicMatrixShapeMismatch;
            const destination = try allocator.alloc(Sample, self.rows);
            errdefer allocator.free(destination);
            const workspace = try allocator.alloc(Sample, self.rows);
            defer allocator.free(workspace);
            try self.multiplyVectorInto(
                vector,
                destination,
                workspace,
            );
            return destination;
        }

        pub fn decomposeLu(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !DynamicLuDecomposition(Sample) {
            return DynamicLuDecomposition(Sample).init(
                allocator,
                self,
            );
        }

        pub fn decomposeQr(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !DynamicQrDecomposition(Sample) {
            return DynamicQrDecomposition(Sample).init(
                allocator,
                self,
            );
        }

        pub fn decomposeSvd(
            self: *const Self,
            allocator: std.mem.Allocator,
            options: DynamicSvdDecomposition(Sample).Options,
        ) !DynamicSvdDecomposition(Sample) {
            return DynamicSvdDecomposition(Sample).init(
                allocator,
                self,
                options,
            );
        }

        pub fn valid(self: *const Self) bool {
            const element_count =
                checkedElementCount(self.rows, self.columns) catch
                    return false;
            if (self.values.len != element_count) return false;
            for (self.values) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            return true;
        }

        fn validateSameShape(
            first: *const Self,
            second: *const Self,
        ) !void {
            if (!first.valid() or !second.valid())
                return error.InvalidDynamicMatrix;
            if (first.rows != second.rows or
                first.columns != second.columns)
            {
                return error.DynamicMatrixShapeMismatch;
            }
        }

        fn checkedElementCount(
            rows: usize,
            columns: usize,
        ) !usize {
            if (rows == 0 or columns == 0)
                return error.InvalidDynamicMatrixDimensions;
            return std.math.mul(
                usize,
                rows,
                columns,
            ) catch error.DynamicMatrixDimensionsOverflow;
        }
    };
}

/// Owns a reusable partial-pivot LU factorization of a dynamic square matrix.
pub fn DynamicLuDecomposition(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "DynamicLuDecomposition supports f32 and f64 elements",
        );

    return struct {
        const Self = @This();
        const Dynamic = DynamicMatrix(Sample);

        allocator: std.mem.Allocator,
        dimensions: usize,
        factors: []Sample,
        permutation: []usize,
        odd_swaps: bool,
        pivot_tolerance: Sample,

        pub fn init(
            allocator: std.mem.Allocator,
            matrix: *const Dynamic,
        ) !Self {
            if (!matrix.valid()) return error.InvalidDynamicMatrix;
            if (matrix.rows != matrix.columns)
                return error.DynamicMatrixNotSquare;

            const factors = try allocator.dupe(Sample, matrix.values);
            errdefer allocator.free(factors);
            const permutation = try allocator.alloc(
                usize,
                matrix.rows,
            );
            errdefer allocator.free(permutation);
            for (permutation, 0..) |*value, index| value.* = index;

            var matrix_scale: Sample = 0.0;
            for (matrix.values) |value|
                matrix_scale = @max(matrix_scale, @abs(value));
            if (matrix_scale == 0.0) return error.SingularMatrix;
            const pivot_tolerance =
                matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(matrix.rows));
            if (!std.math.isFinite(pivot_tolerance))
                return error.MatrixNonFiniteValue;

            var odd_swaps = false;
            for (0..matrix.rows) |pivot_column| {
                var pivot_row = pivot_column;
                var pivot_magnitude = @abs(
                    factors[
                        pivot_row * matrix.rows + pivot_column
                    ],
                );
                for (pivot_column + 1..matrix.rows) |candidate| {
                    const magnitude = @abs(
                        factors[
                            candidate * matrix.rows + pivot_column
                        ],
                    );
                    if (magnitude > pivot_magnitude) {
                        pivot_row = candidate;
                        pivot_magnitude = magnitude;
                    }
                }
                if (!std.math.isFinite(pivot_magnitude) or
                    pivot_magnitude <= pivot_tolerance)
                    return error.SingularMatrix;
                if (pivot_row != pivot_column) {
                    const first_start = pivot_row * matrix.rows;
                    const second_start = pivot_column * matrix.rows;
                    for (0..matrix.rows) |column| {
                        std.mem.swap(
                            Sample,
                            &factors[first_start + column],
                            &factors[second_start + column],
                        );
                    }
                    std.mem.swap(
                        usize,
                        &permutation[pivot_row],
                        &permutation[pivot_column],
                    );
                    odd_swaps = !odd_swaps;
                }

                const pivot =
                    factors[
                        pivot_column * matrix.rows + pivot_column
                    ];
                for (pivot_column + 1..matrix.rows) |row| {
                    const multiplier_index =
                        row * matrix.rows + pivot_column;
                    factors[multiplier_index] /= pivot;
                    if (!std.math.isFinite(
                        factors[multiplier_index],
                    ))
                        return error.MatrixNonFiniteValue;
                    const multiplier = factors[multiplier_index];
                    for (pivot_column + 1..matrix.rows) |column| {
                        const index = row * matrix.rows + column;
                        factors[index] -=
                            multiplier *
                            factors[
                                pivot_column * matrix.rows + column
                            ];
                        if (!std.math.isFinite(factors[index]))
                            return error.MatrixNonFiniteValue;
                    }
                }
            }

            const result = Self{
                .allocator = allocator,
                .dimensions = matrix.rows,
                .factors = factors,
                .permutation = permutation,
                .odd_swaps = odd_swaps,
                .pivot_tolerance = pivot_tolerance,
            };
            if (!result.valid())
                return error.InvalidDynamicLuDecomposition;
            return result;
        }

        pub fn deinit(self: *Self) void {
            if (self.factors.len != 0)
                self.allocator.free(self.factors);
            if (self.permutation.len != 0)
                self.allocator.free(self.permutation);
            self.dimensions = 0;
            self.factors = &.{};
            self.permutation = &.{};
            self.odd_swaps = false;
            self.pivot_tolerance = 0.0;
        }

        pub fn solveInto(
            self: *const Self,
            right_hand_side: []const Sample,
            destination: []Sample,
            workspace: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidDynamicLuDecomposition;
            if (right_hand_side.len != self.dimensions or
                destination.len != self.dimensions or
                workspace.len != self.dimensions)
                return error.DynamicMatrixShapeMismatch;
            if (slicesOverlap(
                Sample,
                right_hand_side,
                workspace,
            ) or
                slicesOverlap(Sample, destination, workspace))
                return error.DynamicMatrixAliasedBuffers;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }

            for (0..self.dimensions) |row| {
                var value =
                    right_hand_side[self.permutation[row]];
                for (0..row) |column| {
                    value -=
                        self.factors[
                            row * self.dimensions + column
                        ] * workspace[column];
                }
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                workspace[row] = value;
            }
            var row = self.dimensions;
            while (row != 0) {
                row -= 1;
                var value = workspace[row];
                for (row + 1..self.dimensions) |column| {
                    value -=
                        self.factors[
                            row * self.dimensions + column
                        ] * workspace[column];
                }
                value /=
                    self.factors[
                        row * self.dimensions + row
                    ];
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                workspace[row] = value;
            }
            @memcpy(destination, workspace);
        }

        pub fn solve(
            self: *const Self,
            allocator: std.mem.Allocator,
            right_hand_side: []const Sample,
        ) ![]Sample {
            if (!self.valid())
                return error.InvalidDynamicLuDecomposition;
            if (right_hand_side.len != self.dimensions)
                return error.DynamicMatrixShapeMismatch;
            const result = try allocator.alloc(
                Sample,
                self.dimensions,
            );
            errdefer allocator.free(result);
            const workspace = try allocator.alloc(
                Sample,
                self.dimensions,
            );
            defer allocator.free(workspace);
            try self.solveInto(
                right_hand_side,
                result,
                workspace,
            );
            return result;
        }

        pub fn solveMatrix(
            self: *const Self,
            allocator: std.mem.Allocator,
            right_hand_side: *const Dynamic,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicLuDecomposition;
            if (!right_hand_side.valid())
                return error.InvalidDynamicMatrix;
            if (right_hand_side.rows != self.dimensions)
                return error.DynamicMatrixShapeMismatch;

            var result = try Dynamic.init(
                allocator,
                self.dimensions,
                right_hand_side.columns,
            );
            errdefer result.deinit();
            const staged = try allocator.alloc(
                Sample,
                self.dimensions,
            );
            defer allocator.free(staged);
            const solution = try allocator.alloc(
                Sample,
                self.dimensions,
            );
            defer allocator.free(solution);
            for (0..right_hand_side.columns) |column| {
                for (0..self.dimensions) |row| {
                    staged[row] =
                        right_hand_side.values[
                            row * right_hand_side.columns + column
                        ];
                }
                try self.solveInto(staged, staged, solution);
                for (0..self.dimensions) |row| {
                    result.values[
                        row * right_hand_side.columns + column
                    ] = staged[row];
                }
            }
            return result;
        }

        pub fn determinant(self: *const Self) !Sample {
            if (!self.valid())
                return error.InvalidDynamicLuDecomposition;
            var result: Sample = if (self.odd_swaps) -1.0 else 1.0;
            for (0..self.dimensions) |index| {
                result *=
                    self.factors[index * self.dimensions + index];
                if (!std.math.isFinite(result))
                    return error.MatrixNonFiniteValue;
            }
            return result;
        }

        pub fn inverse(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicLuDecomposition;
            var identity = try Dynamic.identity(
                allocator,
                self.dimensions,
            );
            defer identity.deinit();
            return self.solveMatrix(allocator, &identity);
        }

        pub fn valid(self: *const Self) bool {
            if (self.dimensions == 0 or
                self.factors.len !=
                    checkedDynamicElementCount(
                        self.dimensions,
                        self.dimensions,
                    ) catch return false or
                        self.permutation.len != self.dimensions or
                        !std.math.isFinite(self.pivot_tolerance) or
                        self.pivot_tolerance < 0.0)
                return false;
            for (self.factors) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            for (0..self.dimensions) |row| {
                const source = self.permutation[row];
                if (source >= self.dimensions) return false;
                for (0..row) |previous| {
                    if (self.permutation[previous] == source)
                        return false;
                }
                if (@abs(
                    self.factors[
                        row * self.dimensions + row
                    ],
                ) <= self.pivot_tolerance)
                    return false;
            }
            return true;
        }
    };
}

/// Owns a reusable Householder QR factorization of a tall dynamic matrix.
pub fn DynamicQrDecomposition(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "DynamicQrDecomposition supports f32 and f64 elements",
        );

    return struct {
        const Self = @This();
        const Dynamic = DynamicMatrix(Sample);

        allocator: std.mem.Allocator,
        rows: usize,
        columns: usize,
        factors: []Sample,
        tau: []Sample,
        rank_tolerance: Sample,

        pub fn init(
            allocator: std.mem.Allocator,
            matrix: *const Dynamic,
        ) !Self {
            if (!matrix.valid()) return error.InvalidDynamicMatrix;
            if (matrix.rows < matrix.columns)
                return error.DynamicQrRequiresTallMatrix;

            const factors = try allocator.dupe(Sample, matrix.values);
            errdefer allocator.free(factors);
            const tau = try allocator.alloc(Sample, matrix.columns);
            errdefer allocator.free(tau);
            @memset(tau, 0.0);

            var matrix_scale: Sample = 0.0;
            for (matrix.values) |value|
                matrix_scale = @max(matrix_scale, @abs(value));
            const rank_tolerance =
                matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(matrix.rows));
            if (!std.math.isFinite(rank_tolerance))
                return error.MatrixNonFiniteValue;

            for (0..matrix.columns) |column| {
                var scale: Sample = 0.0;
                var sum: Sample = 1.0;
                for (column..matrix.rows) |row| {
                    const magnitude = @abs(
                        factors[row * matrix.columns + column],
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

                const diagonal_index =
                    column * matrix.columns + column;
                const first = factors[diagonal_index];
                const diagonal = if (first >= 0.0) -norm else norm;
                const leading = first - diagonal;
                if (!std.math.isFinite(leading) or leading == 0.0)
                    return error.RankDeficientMatrix;
                const reflector = (diagonal - first) / diagonal;
                if (!std.math.isFinite(reflector))
                    return error.MatrixNonFiniteValue;

                for (column + 1..matrix.rows) |row| {
                    const index = row * matrix.columns + column;
                    factors[index] /= leading;
                    if (!std.math.isFinite(factors[index]))
                        return error.MatrixNonFiniteValue;
                }
                for (column + 1..matrix.columns) |target| {
                    var projection =
                        factors[
                            column * matrix.columns + target
                        ];
                    for (column + 1..matrix.rows) |row| {
                        projection +=
                            factors[
                                row * matrix.columns + column
                            ] *
                            factors[
                                row * matrix.columns + target
                            ];
                    }
                    projection *= reflector;
                    factors[
                        column * matrix.columns + target
                    ] -= projection;
                    for (column + 1..matrix.rows) |row| {
                        factors[
                            row * matrix.columns + target
                        ] -=
                            factors[
                                row * matrix.columns + column
                            ] * projection;
                    }
                }
                factors[diagonal_index] = diagonal;
                tau[column] = reflector;
            }

            const result = Self{
                .allocator = allocator,
                .rows = matrix.rows,
                .columns = matrix.columns,
                .factors = factors,
                .tau = tau,
                .rank_tolerance = rank_tolerance,
            };
            if (!result.valid())
                return error.InvalidDynamicQrDecomposition;
            return result;
        }

        pub fn deinit(self: *Self) void {
            if (self.factors.len != 0)
                self.allocator.free(self.factors);
            if (self.tau.len != 0)
                self.allocator.free(self.tau);
            self.rows = 0;
            self.columns = 0;
            self.factors = &.{};
            self.tau = &.{};
            self.rank_tolerance = 0.0;
        }

        pub fn solveLeastSquaresInto(
            self: *const Self,
            right_hand_side: []const Sample,
            destination: []Sample,
            workspace: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidDynamicQrDecomposition;
            if (right_hand_side.len != self.rows or
                destination.len != self.columns or
                workspace.len != self.rows)
                return error.DynamicMatrixShapeMismatch;
            if (slicesOverlap(Sample, destination, workspace))
                return error.DynamicMatrixAliasedBuffers;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }
            if (slicesOverlap(
                Sample,
                right_hand_side,
                workspace,
            ))
                return error.DynamicMatrixAliasedBuffers;
            @memcpy(workspace, right_hand_side);
            try self.applyReflectors(workspace, false);

            var solution_row = self.columns;
            while (solution_row != 0) {
                solution_row -= 1;
                var value = workspace[solution_row];
                for (solution_row + 1..self.columns) |column| {
                    value -=
                        self.factors[
                            solution_row * self.columns + column
                        ] * workspace[column];
                }
                value /=
                    self.factors[
                        solution_row * self.columns + solution_row
                    ];
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                workspace[solution_row] = value;
            }
            @memcpy(destination, workspace[0..self.columns]);
        }

        pub fn solveLeastSquares(
            self: *const Self,
            allocator: std.mem.Allocator,
            right_hand_side: []const Sample,
        ) ![]Sample {
            if (!self.valid())
                return error.InvalidDynamicQrDecomposition;
            if (right_hand_side.len != self.rows)
                return error.DynamicMatrixShapeMismatch;
            const destination = try allocator.alloc(
                Sample,
                self.columns,
            );
            errdefer allocator.free(destination);
            const workspace = try allocator.alloc(Sample, self.rows);
            defer allocator.free(workspace);
            try self.solveLeastSquaresInto(
                right_hand_side,
                destination,
                workspace,
            );
            return destination;
        }

        pub fn upper(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicQrDecomposition;
            var result = try Dynamic.init(
                allocator,
                self.rows,
                self.columns,
            );
            errdefer result.deinit();
            for (0..self.columns) |row| {
                for (row..self.columns) |column| {
                    result.values[row * self.columns + column] =
                        self.factors[row * self.columns + column];
                }
            }
            return result;
        }

        pub fn orthogonal(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicQrDecomposition;
            var result = try Dynamic.identity(
                allocator,
                self.rows,
            );
            errdefer result.deinit();
            const workspace = try allocator.alloc(Sample, self.rows);
            defer allocator.free(workspace);
            for (0..self.rows) |column| {
                @memset(workspace, 0.0);
                workspace[column] = 1.0;
                try self.applyReflectors(workspace, true);
                for (0..self.rows) |row| {
                    result.values[row * self.rows + column] =
                        workspace[row];
                }
            }
            return result;
        }

        pub fn valid(self: *const Self) bool {
            if (self.rows == 0 or
                self.columns == 0 or
                self.rows < self.columns or
                self.factors.len !=
                    checkedDynamicElementCount(
                        self.rows,
                        self.columns,
                    ) catch return false or
                        self.tau.len != self.columns or
                        !std.math.isFinite(self.rank_tolerance) or
                        self.rank_tolerance < 0.0)
                return false;
            for (self.factors) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            for (0..self.columns) |column| {
                if (!std.math.isFinite(self.tau[column]) or
                    self.tau[column] <= 0.0 or
                    self.tau[column] > 2.0 or
                    @abs(
                        self.factors[
                            column * self.columns + column
                        ],
                    ) <= self.rank_tolerance)
                    return false;
            }
            return true;
        }

        fn applyReflectors(
            self: *const Self,
            values: []Sample,
            reverse: bool,
        ) !void {
            if (reverse) {
                var column = self.columns;
                while (column != 0) {
                    column -= 1;
                    try self.applyReflector(values, column);
                }
            } else {
                for (0..self.columns) |column|
                    try self.applyReflector(values, column);
            }
        }

        fn applyReflector(
            self: *const Self,
            values: []Sample,
            column: usize,
        ) !void {
            var projection = values[column];
            for (column + 1..self.rows) |row| {
                projection +=
                    self.factors[
                        row * self.columns + column
                    ] * values[row];
                if (!std.math.isFinite(projection))
                    return error.MatrixNonFiniteValue;
            }
            projection *= self.tau[column];
            if (!std.math.isFinite(projection))
                return error.MatrixNonFiniteValue;
            values[column] -= projection;
            if (!std.math.isFinite(values[column]))
                return error.MatrixNonFiniteValue;
            for (column + 1..self.rows) |row| {
                values[row] -=
                    self.factors[
                        row * self.columns + column
                    ] * projection;
                if (!std.math.isFinite(values[row]))
                    return error.MatrixNonFiniteValue;
            }
        }
    };
}

/// Owns a reusable compact one-sided Jacobi SVD of a dynamic matrix.
pub fn DynamicSvdDecomposition(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "DynamicSvdDecomposition supports f32 and f64 elements",
        );

    return struct {
        const Self = @This();
        const Dynamic = DynamicMatrix(Sample);

        pub const Options = struct {
            convergence_tolerance: Sample =
                if (Sample == f32) 1.0e-5 else 1.0e-12,
            relative_rank_tolerance: ?Sample = null,
            maximum_sweeps: usize = 64,
        };

        allocator: std.mem.Allocator,
        rows: usize,
        columns: usize,
        dimensions: usize,
        left: []Sample,
        singular_values: []Sample,
        right: []Sample,
        rank: usize,
        sweeps: usize,
        converged: bool,
        relative_rank_tolerance: Sample,

        pub fn init(
            allocator: std.mem.Allocator,
            matrix: *const Dynamic,
            options: Options,
        ) !Self {
            if (!matrix.valid()) return error.InvalidDynamicMatrix;
            const relative_rank_tolerance =
                options.relative_rank_tolerance orelse
                std.math.floatEps(Sample) *
                    @as(
                        Sample,
                        @floatFromInt(@max(
                            matrix.rows,
                            matrix.columns,
                        )),
                    );
            try validateOptions(options, relative_rank_tolerance);

            if (matrix.rows >= matrix.columns) {
                return initTall(
                    allocator,
                    matrix,
                    options,
                    relative_rank_tolerance,
                );
            }

            var transposed = try matrix.transpose(allocator);
            defer transposed.deinit();
            var tall = try initTall(
                allocator,
                &transposed,
                options,
                relative_rank_tolerance,
            );
            const result = Self{
                .allocator = allocator,
                .rows = matrix.rows,
                .columns = matrix.columns,
                .dimensions = matrix.rows,
                .left = tall.right,
                .singular_values = tall.singular_values,
                .right = tall.left,
                .rank = tall.rank,
                .sweeps = tall.sweeps,
                .converged = tall.converged,
                .relative_rank_tolerance = tall.relative_rank_tolerance,
            };
            tall.left = &.{};
            tall.singular_values = &.{};
            tall.right = &.{};
            tall.deinit();
            if (!result.valid())
                return error.InvalidDynamicSvdDecomposition;
            return result;
        }

        pub fn deinit(self: *Self) void {
            if (self.left.len != 0)
                self.allocator.free(self.left);
            if (self.singular_values.len != 0)
                self.allocator.free(self.singular_values);
            if (self.right.len != 0)
                self.allocator.free(self.right);
            self.rows = 0;
            self.columns = 0;
            self.dimensions = 0;
            self.left = &.{};
            self.singular_values = &.{};
            self.right = &.{};
            self.rank = 0;
            self.sweeps = 0;
            self.converged = false;
            self.relative_rank_tolerance = 0.0;
        }

        pub fn solveLeastSquaresInto(
            self: *const Self,
            right_hand_side: []const Sample,
            destination: []Sample,
            projection_workspace: []Sample,
            solution_workspace: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidDynamicSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            if (right_hand_side.len != self.rows or
                destination.len != self.columns or
                projection_workspace.len != self.dimensions or
                solution_workspace.len != self.columns)
                return error.DynamicMatrixShapeMismatch;
            if (slicesOverlap(
                Sample,
                destination,
                projection_workspace,
            ) or
                slicesOverlap(
                    Sample,
                    destination,
                    solution_workspace,
                ) or
                slicesOverlap(
                    Sample,
                    projection_workspace,
                    solution_workspace,
                ) or
                slicesOverlap(
                    Sample,
                    right_hand_side,
                    projection_workspace,
                ) or
                slicesOverlap(
                    Sample,
                    right_hand_side,
                    solution_workspace,
                ))
                return error.DynamicMatrixAliasedBuffers;
            for (right_hand_side) |value| {
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
            }
            @memset(projection_workspace, 0.0);
            for (0..self.rank) |column| {
                var projection: Sample = 0.0;
                for (0..self.rows) |row| {
                    projection +=
                        self.left[
                            row * self.dimensions + column
                        ] * right_hand_side[row];
                    if (!std.math.isFinite(projection))
                        return error.MatrixNonFiniteValue;
                }
                projection_workspace[column] =
                    projection / self.singular_values[column];
                if (!std.math.isFinite(
                    projection_workspace[column],
                ))
                    return error.MatrixNonFiniteValue;
            }
            @memset(solution_workspace, 0.0);
            for (0..self.columns) |row| {
                for (0..self.rank) |column| {
                    solution_workspace[row] +=
                        self.right[
                            row * self.dimensions + column
                        ] * projection_workspace[column];
                    if (!std.math.isFinite(
                        solution_workspace[row],
                    ))
                        return error.MatrixNonFiniteValue;
                }
            }
            @memcpy(destination, solution_workspace);
        }

        pub fn solveLeastSquares(
            self: *const Self,
            allocator: std.mem.Allocator,
            right_hand_side: []const Sample,
        ) ![]Sample {
            if (!self.valid())
                return error.InvalidDynamicSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            if (right_hand_side.len != self.rows)
                return error.DynamicMatrixShapeMismatch;
            const destination = try allocator.alloc(
                Sample,
                self.columns,
            );
            errdefer allocator.free(destination);
            const projection_workspace = try allocator.alloc(
                Sample,
                self.dimensions,
            );
            defer allocator.free(projection_workspace);
            const solution_workspace = try allocator.alloc(
                Sample,
                self.columns,
            );
            defer allocator.free(solution_workspace);
            try self.solveLeastSquaresInto(
                right_hand_side,
                destination,
                projection_workspace,
                solution_workspace,
            );
            return destination;
        }

        pub fn pseudoinverse(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            var result = try Dynamic.init(
                allocator,
                self.columns,
                self.rows,
            );
            errdefer result.deinit();
            for (0..self.columns) |row| {
                for (0..self.rows) |column| {
                    var value: Sample = 0.0;
                    for (0..self.rank) |inner| {
                        value +=
                            self.right[
                                row * self.dimensions + inner
                            ] *
                            self.left[
                                column * self.dimensions + inner
                            ] /
                            self.singular_values[inner];
                        if (!std.math.isFinite(value))
                            return error.MatrixNonFiniteValue;
                    }
                    result.values[row * self.rows + column] = value;
                }
            }
            return result;
        }

        pub fn reconstruct(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) !Dynamic {
            if (!self.valid())
                return error.InvalidDynamicSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            var result = try Dynamic.init(
                allocator,
                self.rows,
                self.columns,
            );
            errdefer result.deinit();
            for (0..self.rows) |row| {
                for (0..self.columns) |column| {
                    var value: Sample = 0.0;
                    for (0..self.dimensions) |inner| {
                        value +=
                            self.left[
                                row * self.dimensions + inner
                            ] *
                            self.singular_values[inner] *
                            self.right[
                                column * self.dimensions + inner
                            ];
                        if (!std.math.isFinite(value))
                            return error.MatrixNonFiniteValue;
                    }
                    result.values[
                        row * self.columns + column
                    ] = value;
                }
            }
            return result;
        }

        pub fn conditionNumber(self: *const Self) !Sample {
            if (!self.valid())
                return error.InvalidDynamicSvdDecomposition;
            if (!self.converged) return error.SvdDidNotConverge;
            if (self.rank < self.dimensions)
                return std.math.inf(Sample);
            const result =
                self.singular_values[0] /
                self.singular_values[self.dimensions - 1];
            if (!std.math.isFinite(result))
                return error.MatrixNonFiniteValue;
            return result;
        }

        pub fn valid(self: *const Self) bool {
            if (self.rows == 0 or
                self.columns == 0 or
                self.dimensions != @min(self.rows, self.columns) or
                self.left.len !=
                    checkedDynamicElementCount(
                        self.rows,
                        self.dimensions,
                    ) catch return false or
                        self.singular_values.len != self.dimensions or
                        self.right.len !=
                            checkedDynamicElementCount(
                                self.columns,
                                self.dimensions,
                            ) catch return false or
                                self.rank > self.dimensions or
                                !std.math.isFinite(
                                    self.relative_rank_tolerance,
                                ) or
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
            for (self.left) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            for (self.right) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            return true;
        }

        fn initTall(
            allocator: std.mem.Allocator,
            matrix: *const Dynamic,
            options: Options,
            relative_rank_tolerance: Sample,
        ) !Self {
            const working = try allocator.dupe(
                Sample,
                matrix.values,
            );
            errdefer allocator.free(working);
            var right_matrix = try Dynamic.identity(
                allocator,
                matrix.columns,
            );
            errdefer right_matrix.deinit();
            const singular_values = try allocator.alloc(
                Sample,
                matrix.columns,
            );
            errdefer allocator.free(singular_values);

            var sweeps: usize = 0;
            var converged = matrix.columns == 1;
            for (0..options.maximum_sweeps) |sweep| {
                var changed = false;
                for (0..matrix.columns) |first| {
                    for (first + 1..matrix.columns) |second| {
                        var scale: Sample = 0.0;
                        for (0..matrix.rows) |row| {
                            scale = @max(
                                scale,
                                @abs(
                                    working[
                                        row * matrix.columns + first
                                    ],
                                ),
                            );
                            scale = @max(
                                scale,
                                @abs(
                                    working[
                                        row * matrix.columns + second
                                    ],
                                ),
                            );
                        }
                        if (scale == 0.0) continue;

                        var first_norm: Sample = 0.0;
                        var second_norm: Sample = 0.0;
                        var cross: Sample = 0.0;
                        for (0..matrix.rows) |row| {
                            const first_value =
                                working[
                                    row * matrix.columns + first
                                ] / scale;
                            const second_value =
                                working[
                                    row * matrix.columns + second
                                ] / scale;
                            first_norm += first_value * first_value;
                            second_norm +=
                                second_value * second_value;
                            cross += first_value * second_value;
                        }
                        const threshold =
                            options.convergence_tolerance *
                            @sqrt(first_norm * second_norm) +
                            std.math.floatEps(Sample) *
                                @max(first_norm, second_norm) *
                                @as(
                                    Sample,
                                    @floatFromInt(matrix.rows),
                                );
                        if (@abs(cross) <= threshold) continue;

                        const offset =
                            (second_norm - first_norm) /
                            (2.0 * cross);
                        const tangent = if (offset >= 0.0)
                            1.0 /
                                (offset +
                                    @sqrt(
                                        1.0 + offset * offset,
                                    ))
                        else
                            -1.0 /
                                (-offset +
                                    @sqrt(
                                        1.0 + offset * offset,
                                    ));
                        const cosine =
                            1.0 / @sqrt(1.0 + tangent * tangent);
                        const sine = cosine * tangent;
                        if (!std.math.isFinite(cosine) or
                            !std.math.isFinite(sine))
                            return error.MatrixNonFiniteValue;

                        for (0..matrix.rows) |row| {
                            const first_index =
                                row * matrix.columns + first;
                            const second_index =
                                row * matrix.columns + second;
                            const first_value =
                                working[first_index];
                            const second_value =
                                working[second_index];
                            working[first_index] =
                                cosine * first_value -
                                sine * second_value;
                            working[second_index] =
                                sine * first_value +
                                cosine * second_value;
                            if (!std.math.isFinite(
                                working[first_index],
                            ) or
                                !std.math.isFinite(
                                    working[second_index],
                                ))
                                return error.MatrixNonFiniteValue;
                        }
                        for (0..matrix.columns) |row| {
                            const first_index =
                                row * matrix.columns + first;
                            const second_index =
                                row * matrix.columns + second;
                            const first_value =
                                right_matrix.values[first_index];
                            const second_value =
                                right_matrix.values[second_index];
                            right_matrix.values[first_index] =
                                cosine * first_value -
                                sine * second_value;
                            right_matrix.values[second_index] =
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

            for (0..matrix.columns) |column| {
                singular_values[column] = try dynamicColumnMagnitude(
                    Sample,
                    working,
                    matrix.rows,
                    matrix.columns,
                    column,
                );
                if (singular_values[column] == 0.0) continue;
                for (0..matrix.rows) |row| {
                    working[row * matrix.columns + column] /=
                        singular_values[column];
                }
            }
            sortDynamicSvd(
                Sample,
                singular_values,
                working,
                matrix.rows,
                right_matrix.values,
                matrix.columns,
            );

            const rank_threshold =
                singular_values[0] * relative_rank_tolerance;
            var rank: usize = 0;
            for (singular_values) |value| {
                if (value > rank_threshold) rank += 1;
            }
            const right = right_matrix.values;
            right_matrix.values = &.{};
            right_matrix.deinit();
            const result = Self{
                .allocator = allocator,
                .rows = matrix.rows,
                .columns = matrix.columns,
                .dimensions = matrix.columns,
                .left = working,
                .singular_values = singular_values,
                .right = right,
                .rank = rank,
                .sweeps = sweeps,
                .converged = converged,
                .relative_rank_tolerance = relative_rank_tolerance,
            };
            if (!result.valid())
                return error.InvalidDynamicSvdDecomposition;
            return result;
        }

        fn validateOptions(
            options: Options,
            relative_rank_tolerance: Sample,
        ) !void {
            if (!std.math.isFinite(
                options.convergence_tolerance,
            ) or
                options.convergence_tolerance <= 0.0 or
                options.convergence_tolerance >= 1.0)
                return error.InvalidSvdTolerance;
            if (!std.math.isFinite(relative_rank_tolerance) or
                relative_rank_tolerance < 0.0 or
                relative_rank_tolerance >= 1.0)
                return error.InvalidSvdRankTolerance;
            if (options.maximum_sweeps == 0)
                return error.InvalidSvdSweepLimit;
        }
    };
}

fn checkedDynamicElementCount(
    rows: usize,
    columns: usize,
) !usize {
    if (rows == 0 or columns == 0)
        return error.InvalidDynamicMatrixDimensions;
    return std.math.mul(
        usize,
        rows,
        columns,
    ) catch error.DynamicMatrixDimensionsOverflow;
}

fn slicesOverlap(
    comptime Element: type,
    first: []const Element,
    second: []const Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const first_end =
        first_start + first.len * @sizeOf(Element);
    const second_start = @intFromPtr(second.ptr);
    const second_end =
        second_start + second.len * @sizeOf(Element);
    return first_start < second_end and second_start < first_end;
}

fn dynamicColumnMagnitude(
    comptime Sample: type,
    values: []const Sample,
    rows: usize,
    columns: usize,
    column: usize,
) !Sample {
    var scale: Sample = 0.0;
    var sum: Sample = 1.0;
    for (0..rows) |row| {
        const magnitude = @abs(values[row * columns + column]);
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

fn sortDynamicSvd(
    comptime Sample: type,
    singular_values: []Sample,
    left: []Sample,
    left_rows: usize,
    right: []Sample,
    right_rows: usize,
) void {
    const dimensions = singular_values.len;
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
        for (0..left_rows) |row| {
            std.mem.swap(
                Sample,
                &left[row * dimensions + first],
                &left[row * dimensions + largest],
            );
        }
        for (0..right_rows) |row| {
            std.mem.swap(
                Sample,
                &right[row * dimensions + first],
                &right[row * dimensions + largest],
            );
        }
    }
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
    try std.testing.expectError(
        error.InvalidSvdTolerance,
        limited_source.decomposeSvd(
            std.testing.allocator,
            .{ .convergence_tolerance = 0.0 },
        ),
    );

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
    qr.factors[2] = std.math.floatMax(f64);
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

    var svd = try identity.decomposeSvd(
        std.testing.allocator,
        .{},
    );
    defer svd.deinit();
    svd.right[0] = std.math.floatMax(f64);
    var svd_destination = [_]f64{ 11.0, 12.0 };
    var projection_workspace: [2]f64 = undefined;
    var solution_workspace: [2]f64 = undefined;
    try std.testing.expectError(
        error.MatrixNonFiniteValue,
        svd.solveLeastSquaresInto(
            &.{ std.math.floatMax(f64), 1.0 },
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
