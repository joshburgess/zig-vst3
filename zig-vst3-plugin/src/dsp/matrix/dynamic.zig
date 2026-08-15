const std = @import("std");

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

        pub fn addInto(
            self: *const Self,
            other: *const Self,
            destination: *Self,
            workspace: []Sample,
        ) !void {
            try validateSameShape(self, other);
            try validateOutput(
                destination,
                workspace,
                self.rows,
                self.columns,
                &.{ self.values, other.values },
            );
            for (self.values, other.values, workspace) |
                first,
                second,
                *output,
            | {
                const value = first + second;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                output.* = value;
            }
            @memcpy(destination.values, workspace);
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

        pub fn subtractInto(
            self: *const Self,
            other: *const Self,
            destination: *Self,
            workspace: []Sample,
        ) !void {
            try validateSameShape(self, other);
            try validateOutput(
                destination,
                workspace,
                self.rows,
                self.columns,
                &.{ self.values, other.values },
            );
            for (self.values, other.values, workspace) |
                first,
                second,
                *output,
            | {
                const value = first - second;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                output.* = value;
            }
            @memcpy(destination.values, workspace);
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

        pub fn scaledInto(
            self: *const Self,
            factor: Sample,
            destination: *Self,
            workspace: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            if (!std.math.isFinite(factor))
                return error.MatrixNonFiniteValue;
            try validateOutput(
                destination,
                workspace,
                self.rows,
                self.columns,
                &.{self.values},
            );
            for (self.values, workspace) |source, *output| {
                const value = source * factor;
                if (!std.math.isFinite(value))
                    return error.MatrixNonFiniteValue;
                output.* = value;
            }
            @memcpy(destination.values, workspace);
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

        pub fn transposeInto(
            self: *const Self,
            destination: *Self,
            workspace: []Sample,
        ) !void {
            if (!self.valid()) return error.InvalidDynamicMatrix;
            try validateOutput(
                destination,
                workspace,
                self.columns,
                self.rows,
                &.{self.values},
            );
            for (0..self.rows) |row_index| {
                for (0..self.columns) |column_index| {
                    workspace[
                        column_index * self.rows + row_index
                    ] = self.values[
                        row_index * self.columns + column_index
                    ];
                }
            }
            @memcpy(destination.values, workspace);
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

        pub fn multiplyInto(
            self: *const Self,
            other: *const Self,
            destination: *Self,
            workspace: []Sample,
        ) !void {
            if (!self.valid() or !other.valid())
                return error.InvalidDynamicMatrix;
            if (self.columns != other.rows)
                return error.DynamicMatrixShapeMismatch;
            try validateOutput(
                destination,
                workspace,
                self.rows,
                other.columns,
                &.{ self.values, other.values },
            );
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
                    workspace[
                        row_index * other.columns + column_index
                    ] = value;
                }
            }
            @memcpy(destination.values, workspace);
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
                slicesOverlap(Sample, destination, workspace) or
                slicesOverlap(Sample, self.values, workspace) or
                slicesOverlap(Sample, self.values, destination))
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

        fn validateOutput(
            destination: *const Self,
            workspace: []Sample,
            rows: usize,
            columns: usize,
            sources: []const []const Sample,
        ) !void {
            if (!destination.valid())
                return error.InvalidDynamicMatrix;
            if (destination.rows != rows or
                destination.columns != columns or
                workspace.len != destination.values.len)
            {
                return error.DynamicMatrixShapeMismatch;
            }
            if (slicesOverlap(
                Sample,
                destination.values,
                workspace,
            )) return error.DynamicMatrixAliasedBuffers;
            for (sources) |source| {
                if (slicesOverlap(Sample, source, workspace))
                    return error.DynamicMatrixAliasedBuffers;
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
/// Teardown is repeatable. Operations reject closed or malformed values.
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
        matrix_scale: Sample,
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
                .matrix_scale = matrix_scale,
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
            self.matrix_scale = 0.0;
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
                slicesOverlap(Sample, destination, workspace) or
                anySlicesOverlap(
                    Sample,
                    &.{ destination, workspace },
                    &.{self.factors},
                ))
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
            if (self.dimensions == 0) return false;
            const factor_count = checkedDynamicElementCount(
                self.dimensions,
                self.dimensions,
            ) catch return false;
            if (self.factors.len != factor_count or
                self.permutation.len != self.dimensions or
                !std.math.isFinite(self.matrix_scale) or
                self.matrix_scale <= 0.0 or
                !std.math.isFinite(self.pivot_tolerance) or
                self.pivot_tolerance < 0.0)
                return false;
            const expected_pivot_tolerance =
                self.matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(self.dimensions));
            if (!std.math.isFinite(expected_pivot_tolerance) or
                self.pivot_tolerance != expected_pivot_tolerance)
                return false;
            for (self.factors) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            var permutation_odd = false;
            for (0..self.dimensions) |row| {
                const source = self.permutation[row];
                if (source >= self.dimensions) return false;
                for (0..row) |previous| {
                    if (self.permutation[previous] == source)
                        return false;
                    if (self.permutation[previous] > source)
                        permutation_odd = !permutation_odd;
                }
                if (@abs(
                    self.factors[
                        row * self.dimensions + row
                    ],
                ) <= self.pivot_tolerance)
                    return false;
            }
            if (self.odd_swaps != permutation_odd) return false;
            return true;
        }
    };
}

/// Owns a reusable Householder QR factorization of a tall dynamic matrix.
/// Teardown is repeatable. Operations reject closed or malformed values.
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
        matrix_scale: Sample,
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
                .matrix_scale = matrix_scale,
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
            self.matrix_scale = 0.0;
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
            if (slicesOverlap(Sample, destination, workspace) or
                anySlicesOverlap(
                    Sample,
                    &.{ destination, workspace },
                    &.{ self.factors, self.tau },
                ))
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
                self.rows < self.columns)
                return false;
            const factor_count = checkedDynamicElementCount(
                self.rows,
                self.columns,
            ) catch return false;
            if (self.factors.len != factor_count or
                self.tau.len != self.columns or
                !std.math.isFinite(self.matrix_scale) or
                self.matrix_scale <= 0.0 or
                !std.math.isFinite(self.rank_tolerance) or
                self.rank_tolerance < 0.0)
                return false;
            const expected_rank_tolerance =
                self.matrix_scale *
                std.math.floatEps(Sample) *
                @as(Sample, @floatFromInt(self.rows));
            if (!std.math.isFinite(expected_rank_tolerance) or
                self.rank_tolerance != expected_rank_tolerance)
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

                var reflector_scale: Sample = 1.0;
                var reflector_sum: Sample = 1.0;
                for (column + 1..self.rows) |row| {
                    const magnitude = @abs(
                        self.factors[
                            row * self.columns + column
                        ],
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
                    self.rows - column,
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
/// Teardown is repeatable. Operations reject closed or malformed values.
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
        maximum_sweeps: usize,
        converged: bool,
        convergence_tolerance: Sample,
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
            defer tall.deinit();
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
                .maximum_sweeps = tall.maximum_sweeps,
                .converged = tall.converged,
                .convergence_tolerance = tall.convergence_tolerance,
                .relative_rank_tolerance = tall.relative_rank_tolerance,
            };
            if (!result.valid())
                return error.InvalidDynamicSvdDecomposition;
            tall.left = &.{};
            tall.singular_values = &.{};
            tall.right = &.{};
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
            self.maximum_sweeps = 0;
            self.converged = false;
            self.convergence_tolerance = 0.0;
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
                ) or
                anySlicesOverlap(
                    Sample,
                    &.{
                        destination,
                        projection_workspace,
                        solution_workspace,
                    },
                    &.{
                        self.left,
                        self.singular_values,
                        self.right,
                    },
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
                self.dimensions != @min(self.rows, self.columns))
                return false;
            const left_count = checkedDynamicElementCount(
                self.rows,
                self.dimensions,
            ) catch return false;
            const right_count = checkedDynamicElementCount(
                self.columns,
                self.dimensions,
            ) catch return false;
            if (self.left.len != left_count or
                self.singular_values.len != self.dimensions or
                self.right.len != right_count or
                self.rank > self.dimensions or
                self.maximum_sweeps == 0 or
                self.sweeps == 0 or
                self.sweeps > self.maximum_sweeps or
                (!self.converged and
                    self.sweeps != self.maximum_sweeps) or
                !std.math.isFinite(self.convergence_tolerance) or
                self.convergence_tolerance <= 0.0 or
                self.convergence_tolerance >= 1.0 or
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
            const basis_tolerance = @min(
                @as(Sample, 0.01),
                std.math.floatEps(Sample) *
                    128.0 *
                    @as(
                        Sample,
                        @floatFromInt(@max(self.rows, self.columns)),
                    ),
            );
            for (0..self.dimensions) |column| {
                const left_magnitude = dynamicColumnMagnitude(
                    Sample,
                    self.left,
                    self.rows,
                    self.dimensions,
                    column,
                ) catch return false;
                const right_magnitude = dynamicColumnMagnitude(
                    Sample,
                    self.right,
                    self.columns,
                    self.dimensions,
                    column,
                ) catch return false;
                const singular = self.singular_values[column];
                const expected_left: Sample = if (self.rows < self.columns or singular != 0.0) 1.0 else 0.0;
                const expected_right: Sample = if (self.rows >= self.columns or singular != 0.0) 1.0 else 0.0;
                if (@abs(left_magnitude - expected_left) >
                    basis_tolerance or
                    @abs(right_magnitude - expected_right) >
                        basis_tolerance)
                    return false;
            }
            for (0..self.dimensions) |first| {
                for (first + 1..self.dimensions) |second| {
                    const left_active = self.rows < self.columns or
                        second < self.rank;
                    const right_active = self.rows >= self.columns or
                        second < self.rank;
                    if (left_active and
                        (self.rows < self.columns or self.converged))
                    {
                        const dot = dynamicColumnDot(
                            Sample,
                            self.left,
                            self.rows,
                            self.dimensions,
                            first,
                            second,
                        ) catch return false;
                        const tolerance = basis_tolerance +
                            if (self.rows < self.columns)
                                basis_tolerance
                            else
                                self.convergence_tolerance;
                        if (@abs(dot) > tolerance) return false;
                    }
                    if (right_active and
                        (self.rows >= self.columns or self.converged))
                    {
                        const dot = dynamicColumnDot(
                            Sample,
                            self.right,
                            self.columns,
                            self.dimensions,
                            first,
                            second,
                        ) catch return false;
                        const tolerance = basis_tolerance +
                            if (self.rows >= self.columns)
                                basis_tolerance
                            else
                                self.convergence_tolerance;
                        if (@abs(dot) > tolerance) return false;
                    }
                }
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
                .maximum_sweeps = options.maximum_sweeps,
                .converged = converged,
                .convergence_tolerance = options.convergence_tolerance,
                .relative_rank_tolerance = relative_rank_tolerance,
            };
            if (!result.valid())
                return error.InvalidDynamicSvdDecomposition;
            right_matrix.values = &.{};
            right_matrix.deinit();
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

fn dynamicColumnDot(
    comptime Sample: type,
    values: []const Sample,
    rows: usize,
    columns: usize,
    first: usize,
    second: usize,
) !Sample {
    var result: Sample = 0.0;
    for (0..rows) |row| {
        result += values[row * columns + first] *
            values[row * columns + second];
        if (!std.math.isFinite(result))
            return error.MatrixNonFiniteValue;
    }
    return result;
}

pub fn slicesOverlap(
    comptime Element: type,
    first: []const Element,
    second: []const Element,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const first_bytes = std.math.mul(
        usize,
        first.len,
        @sizeOf(Element),
    ) catch return true;
    const first_end = std.math.add(
        usize,
        first_start,
        first_bytes,
    ) catch return true;
    const second_start = @intFromPtr(second.ptr);
    const second_bytes = std.math.mul(
        usize,
        second.len,
        @sizeOf(Element),
    ) catch return true;
    const second_end = std.math.add(
        usize,
        second_start,
        second_bytes,
    ) catch return true;
    return first_start < second_end and second_start < first_end;
}

fn anySlicesOverlap(
    comptime Element: type,
    first: []const []const Element,
    second: []const []const Element,
) bool {
    for (first) |first_slice| {
        for (second) |second_slice| {
            if (slicesOverlap(Element, first_slice, second_slice))
                return true;
        }
    }
    return false;
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
