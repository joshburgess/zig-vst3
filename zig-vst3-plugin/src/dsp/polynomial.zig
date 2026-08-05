const std = @import("std");
const matrix = @import("matrix.zig");

pub fn Polynomial(comptime Sample: type, comptime capacity: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Polynomial supports f32 and f64 coefficients");
    if (capacity == 0)
        @compileError("Polynomial capacity must be positive");

    return struct {
        const Self = @This();
        pub const Complex = std.math.Complex(Sample);
        pub const coefficient_capacity = capacity;
        pub const maximum_degree = capacity - 1;
        pub const default_root_tolerance: Sample =
            if (Sample == f32) 1.0e-5 else 1.0e-12;
        pub const default_root_maximum_iterations: usize = 256;
        pub const RootOptions = struct {
            tolerance: Sample = default_root_tolerance,
            maximum_iterations: usize =
                default_root_maximum_iterations,
        };
        pub const RootResult = struct {
            values: [capacity - 1]Complex =
                @splat(.{ .re = 0.0, .im = 0.0 }),
            count: usize = 0,
            iterations: usize = 0,
            converged: bool = true,

            pub fn slice(self: *const RootResult) []const Complex {
                if (!self.valid()) return &.{};
                return self.values[0..self.count];
            }

            pub fn valid(self: *const RootResult) bool {
                if (self.count > self.values.len) return false;
                for (self.values[0..self.count]) |value| {
                    if (!finiteComplex(value)) return false;
                }
                return true;
            }
        };
        pub const DivisionResult = struct {
            quotient: Self,
            remainder: Self,
        };

        coefficients: [capacity]Sample,
        count: usize,

        /// Coefficients are ordered from the constant term upward.
        pub fn init(source: []const Sample) !Self {
            if (source.len == 0) return error.PolynomialRequiresCoefficient;
            if (source.len > capacity) return error.PolynomialCapacityExceeded;
            var result = Self{
                .coefficients = @splat(0.0),
                .count = source.len,
            };
            for (source, 0..) |value, index| {
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index] = value;
            }
            return result;
        }

        pub fn evaluate(self: Self, x: Sample) Sample {
            if (!self.valid() or !std.math.isFinite(x)) return 0.0;
            var result = self.coefficients[self.count - 1];
            var index = self.count - 1;
            while (index > 0) {
                index -= 1;
                result = result * x + self.coefficients[index];
                if (!std.math.isFinite(result)) return 0.0;
            }
            return result;
        }

        pub fn derivative(self: Self) !Self {
            if (!self.valid() or self.count == 1)
                return .{
                    .coefficients = @splat(0.0),
                    .count = 1,
                };
            var result = Self{
                .coefficients = @splat(0.0),
                .count = self.count - 1,
            };
            for (1..self.count) |index| {
                const value =
                    self.coefficients[index] * @as(Sample, @floatFromInt(index));
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index - 1] = value;
            }
            return result;
        }

        pub fn integral(self: Self, constant: Sample) !Self {
            if (!self.valid()) return error.InvalidPolynomial;
            if (!std.math.isFinite(constant))
                return error.PolynomialNonFiniteValue;
            const source_count = self.effectiveCount();
            if (source_count == capacity)
                return error.PolynomialCapacityExceeded;
            var result = Self{
                .coefficients = @splat(0.0),
                .count = source_count + 1,
            };
            result.coefficients[0] = constant;
            for (0..source_count) |index| {
                const value = self.coefficients[index] /
                    @as(Sample, @floatFromInt(index + 1));
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index + 1] = value;
            }
            return result;
        }

        pub fn add(self: Self, other: Self) !Self {
            if (!self.valid() or !other.valid())
                return error.InvalidPolynomial;
            const result_count = @max(self.count, other.count);
            var result = Self{
                .coefficients = @splat(0.0),
                .count = result_count,
            };
            for (0..result_count) |index| {
                const left = if (index < self.count)
                    self.coefficients[index]
                else
                    0.0;
                const right = if (index < other.count)
                    other.coefficients[index]
                else
                    0.0;
                const value = left + right;
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index] = value;
            }
            return result;
        }

        pub fn subtract(self: Self, other: Self) !Self {
            if (!self.valid() or !other.valid())
                return error.InvalidPolynomial;
            const result_count = @max(self.count, other.count);
            var result = Self{
                .coefficients = @splat(0.0),
                .count = result_count,
            };
            for (0..result_count) |index| {
                const left = if (index < self.count)
                    self.coefficients[index]
                else
                    0.0;
                const right = if (index < other.count)
                    other.coefficients[index]
                else
                    0.0;
                const value = left - right;
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index] = value;
            }
            result.trim();
            return result;
        }

        pub fn multiply(self: Self, other: Self) !Self {
            if (!self.valid() or !other.valid())
                return error.InvalidPolynomial;
            const result_count = self.count + other.count - 1;
            if (result_count > capacity)
                return error.PolynomialCapacityExceeded;
            var result = Self{
                .coefficients = @splat(0.0),
                .count = result_count,
            };
            for (0..self.count) |left_index| {
                for (0..other.count) |right_index| {
                    const index = left_index + right_index;
                    const value = result.coefficients[index] +
                        self.coefficients[left_index] *
                            other.coefficients[right_index];
                    if (!std.math.isFinite(value))
                        return error.PolynomialNonFiniteValue;
                    result.coefficients[index] = value;
                }
            }
            return result;
        }

        pub fn compose(self: Self, inner: Self) !Self {
            if (!self.valid() or !inner.valid())
                return error.InvalidPolynomial;
            const source_count = self.effectiveCount();
            var result = try Self.init(
                &.{self.coefficients[source_count - 1]},
            );
            var index = source_count - 1;
            while (index != 0) {
                index -= 1;
                result = try result.multiply(inner);
                result.coefficients[0] += self.coefficients[index];
                if (!std.math.isFinite(result.coefficients[0]))
                    return error.PolynomialNonFiniteValue;
            }
            result.trim();
            return result;
        }

        pub fn divide(self: Self, divisor: Self) !DivisionResult {
            if (!self.valid() or !divisor.valid())
                return error.InvalidPolynomial;
            const dividend_count = self.effectiveCount();
            const divisor_count = divisor.effectiveCount();
            if (divisor_count == 1 and divisor.coefficients[0] == 0.0)
                return error.PolynomialDivisionByZero;

            var quotient = Self{
                .coefficients = @splat(0.0),
                .count = 1,
            };
            var remainder = self;
            remainder.count = dividend_count;
            if (dividend_count < divisor_count)
                return .{
                    .quotient = quotient,
                    .remainder = remainder,
                };

            quotient.count = dividend_count - divisor_count + 1;
            const divisor_leading =
                divisor.coefficients[divisor_count - 1];
            var remainder_count = dividend_count;
            while (remainder_count >= divisor_count) {
                const quotient_index =
                    remainder_count - divisor_count;
                const factor =
                    remainder.coefficients[remainder_count - 1] /
                    divisor_leading;
                if (!std.math.isFinite(factor))
                    return error.PolynomialNonFiniteValue;
                quotient.coefficients[quotient_index] = factor;
                for (0..divisor_count) |index| {
                    const destination = quotient_index + index;
                    const value =
                        remainder.coefficients[destination] -
                        factor * divisor.coefficients[index];
                    if (!std.math.isFinite(value))
                        return error.PolynomialNonFiniteValue;
                    remainder.coefficients[destination] = value;
                }
                remainder.coefficients[remainder_count - 1] = 0.0;
                remainder_count -= 1;
            }
            quotient.trim();
            remainder.trim();
            return .{
                .quotient = quotient,
                .remainder = remainder,
            };
        }

        pub fn interpolate(
            x_values: []const Sample,
            y_values: []const Sample,
        ) !Self {
            if (x_values.len == 0 or
                x_values.len != y_values.len)
                return error.InvalidPolynomialPoints;
            if (x_values.len > capacity)
                return error.PolynomialCapacityExceeded;

            var divided: [capacity]Sample = @splat(0.0);
            for (x_values, y_values, 0..) |x, y, index| {
                if (!std.math.isFinite(x) or
                    !std.math.isFinite(y))
                    return error.PolynomialNonFiniteValue;
                divided[index] = y;
            }
            for (1..x_values.len) |order| {
                var index = x_values.len;
                while (index > order) {
                    index -= 1;
                    const denominator =
                        x_values[index] - x_values[index - order];
                    if (!std.math.isFinite(denominator) or
                        denominator == 0.0)
                        return error.DuplicatePolynomialPoint;
                    divided[index] =
                        (divided[index] - divided[index - 1]) /
                        denominator;
                    if (!std.math.isFinite(divided[index]))
                        return error.PolynomialNonFiniteValue;
                }
            }

            var result = try Self.init(&.{
                divided[x_values.len - 1],
            });
            var index = x_values.len - 1;
            while (index != 0) {
                index -= 1;
                const factor = try Self.init(&.{
                    -x_values[index],
                    1.0,
                });
                result = try (try result.multiply(factor)).add(
                    try Self.init(&.{divided[index]}),
                );
            }
            result.trim();
            return result;
        }

        pub fn fitLeastSquares(
            comptime point_count: usize,
            comptime degree: usize,
            x_values: [point_count]Sample,
            y_values: [point_count]Sample,
        ) !Self {
            if (point_count == 0 or point_count < degree + 1)
                @compileError(
                    "polynomial fit requires at least degree + 1 points",
                );
            if (degree + 1 > capacity)
                @compileError(
                    "polynomial fit degree exceeds polynomial capacity",
                );

            const Design = matrix.Matrix(
                Sample,
                point_count,
                degree + 1,
            );
            var design = Design.zero();
            for (0..point_count) |row| {
                if (!std.math.isFinite(x_values[row]) or
                    !std.math.isFinite(y_values[row]))
                    return error.PolynomialNonFiniteValue;
                var power: Sample = 1.0;
                for (0..degree + 1) |column| {
                    design.values[row][column] = power;
                    power *= x_values[row];
                    if (!std.math.isFinite(power) and
                        column + 1 < degree + 1)
                        return error.PolynomialNonFiniteValue;
                }
            }
            const coefficients =
                try (try design.decomposeQr()).solveLeastSquares(
                    y_values,
                );
            return Self.init(&coefficients);
        }

        pub fn fitLeastSquaresMinimumNorm(
            comptime point_count: usize,
            comptime degree: usize,
            x_values: [point_count]Sample,
            y_values: [point_count]Sample,
        ) !Self {
            if (point_count == 0 or point_count < degree + 1)
                @compileError(
                    "polynomial fit requires at least degree + 1 points",
                );
            if (degree + 1 > capacity)
                @compileError(
                    "polynomial fit degree exceeds polynomial capacity",
                );

            const Design = matrix.Matrix(
                Sample,
                point_count,
                degree + 1,
            );
            var design = Design.zero();
            for (0..point_count) |row| {
                if (!std.math.isFinite(x_values[row]) or
                    !std.math.isFinite(y_values[row]))
                    return error.PolynomialNonFiniteValue;
                var power: Sample = 1.0;
                for (0..degree + 1) |column| {
                    design.values[row][column] = power;
                    power *= x_values[row];
                    if (!std.math.isFinite(power) and
                        column + 1 < degree + 1)
                        return error.PolynomialNonFiniteValue;
                }
            }
            const coefficients =
                try (try design.decomposeSvd(.{})).solveLeastSquares(
                    y_values,
                );
            return Self.init(&coefficients);
        }

        pub fn legendre(degree: usize) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{ 0.0, 1.0 });
            for (1..degree) |order| {
                const denominator: Sample =
                    @floatFromInt(order + 1);
                const next = try recurrenceStep(
                    previous,
                    current,
                    @as(Sample, @floatFromInt(2 * order + 1)) /
                        denominator,
                    @as(Sample, @floatFromInt(order)) /
                        denominator,
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn chebyshevFirstKind(degree: usize) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{ 0.0, 1.0 });
            for (1..degree) |_| {
                const next = try recurrenceStep(
                    previous,
                    current,
                    2.0,
                    1.0,
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn chebyshevSecondKind(degree: usize) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{ 0.0, 2.0 });
            for (1..degree) |_| {
                const next = try recurrenceStep(
                    previous,
                    current,
                    2.0,
                    1.0,
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn hermitePhysicists(degree: usize) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{ 0.0, 2.0 });
            for (1..degree) |order| {
                const next = try affineRecurrenceStep(
                    previous,
                    current,
                    0.0,
                    2.0,
                    @as(Sample, @floatFromInt(2 * order)),
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn hermiteProbabilists(degree: usize) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{ 0.0, 1.0 });
            for (1..degree) |order| {
                const next = try affineRecurrenceStep(
                    previous,
                    current,
                    0.0,
                    1.0,
                    @as(Sample, @floatFromInt(order)),
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn laguerre(degree: usize) !Self {
            return generalizedLaguerre(degree, 0.0);
        }

        pub fn generalizedLaguerre(
            degree: usize,
            alpha: Sample,
        ) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            if (!std.math.isFinite(alpha) or alpha <= -1.0)
                return error.InvalidPolynomialFamilyParameter;
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{
                1.0 + alpha,
                -1.0,
            });
            if (!current.valid())
                return error.PolynomialNonFiniteValue;
            for (1..degree) |order| {
                const n: Sample = @floatFromInt(order);
                const denominator = n + 1.0;
                const next = try affineRecurrenceStep(
                    previous,
                    current,
                    (2.0 * n + 1.0 + alpha) / denominator,
                    -1.0 / denominator,
                    (n + alpha) / denominator,
                );
                previous = current;
                current = next;
            }
            return current;
        }

        pub fn jacobi(
            degree: usize,
            alpha: Sample,
            beta: Sample,
        ) !Self {
            if (degree >= capacity)
                return error.PolynomialCapacityExceeded;
            if (!std.math.isFinite(alpha) or
                !std.math.isFinite(beta) or
                alpha <= -1.0 or beta <= -1.0)
            {
                return error.InvalidPolynomialFamilyParameter;
            }
            var previous = try Self.init(&.{1.0});
            if (degree == 0) return previous;
            var current = try Self.init(&.{
                (alpha - beta) / 2.0,
                (alpha + beta + 2.0) / 2.0,
            });
            if (!current.valid())
                return error.PolynomialNonFiniteValue;

            for (1..degree) |order| {
                const n: Sample = @floatFromInt(order);
                const sum = alpha + beta;
                const twice_n_sum = 2.0 * n + sum;
                const denominator =
                    2.0 *
                    (n + 1.0) *
                    (n + sum + 1.0) *
                    twice_n_sum;
                if (!std.math.isFinite(denominator) or
                    denominator == 0.0)
                {
                    return error.PolynomialNonFiniteValue;
                }
                const common = twice_n_sum + 1.0;
                const next = try affineRecurrenceStep(
                    previous,
                    current,
                    common *
                        (alpha * alpha - beta * beta) /
                        denominator,
                    common *
                        twice_n_sum *
                        (twice_n_sum + 2.0) /
                        denominator,
                    2.0 *
                        (n + alpha) *
                        (n + beta) *
                        (twice_n_sum + 2.0) /
                        denominator,
                );
                previous = current;
                current = next;
            }
            return current;
        }

        /// Finds every complex root without allocation.
        ///
        /// Trailing zero coefficients are ignored. The all-zero polynomial has
        /// no finite root set and is rejected.
        pub fn findRoots(
            self: Self,
            options: RootOptions,
        ) !RootResult {
            if (!self.valid()) return error.InvalidPolynomial;
            if (!std.math.isFinite(options.tolerance) or
                options.tolerance <= 0.0)
                return error.InvalidRootTolerance;
            if (options.maximum_iterations == 0)
                return error.InvalidRootIterationLimit;

            var coefficient_count = self.count;
            while (coefficient_count > 0 and
                self.coefficients[coefficient_count - 1] == 0.0)
            {
                coefficient_count -= 1;
            }
            if (coefficient_count == 0)
                return error.IndeterminatePolynomialRoots;

            const degree = coefficient_count - 1;
            var result = RootResult{};
            result.count = degree;
            if (degree == 0) return result;

            const leading = self.coefficients[degree];
            if (degree == 1) {
                result.values[0] = Complex.init(
                    -self.coefficients[0] / leading,
                    0.0,
                );
                return result;
            }

            var radius: Sample = 1.0;
            for (self.coefficients[0..degree]) |coefficient| {
                radius = @max(
                    radius,
                    1.0 + @abs(coefficient / leading),
                );
            }
            const degree_value: Sample = @floatFromInt(degree);
            for (0..degree) |index| {
                const phase = 2.0 * std.math.pi *
                    (@as(Sample, @floatFromInt(index)) + 0.5) /
                    degree_value;
                result.values[index] = Complex.init(
                    radius * @cos(phase),
                    radius * @sin(phase),
                );
            }

            var next: [capacity - 1]Complex = undefined;
            for (0..options.maximum_iterations) |iteration| {
                var all_converged = true;
                for (0..degree) |index| {
                    const root = result.values[index];
                    var denominator = Complex.init(1.0, 0.0);
                    for (0..degree) |other_index| {
                        if (other_index == index) continue;
                        denominator = denominator.mul(
                            root.sub(result.values[other_index]),
                        );
                    }
                    if (!finiteComplex(denominator) or
                        denominator.squaredMagnitude() == 0.0)
                        return error.PolynomialRootIterationStalled;

                    const correction = evaluateComplexMonic(
                        self,
                        coefficient_count,
                        root,
                    ).div(denominator);
                    if (!finiteComplex(correction))
                        return error.PolynomialRootIterationStalled;
                    next[index] = root.sub(correction);
                    if (!finiteComplex(next[index]))
                        return error.PolynomialRootIterationStalled;
                    if (correction.magnitude() >
                        options.tolerance *
                            (1.0 + next[index].magnitude()))
                    {
                        all_converged = false;
                    }
                }
                @memcpy(
                    result.values[0..degree],
                    next[0..degree],
                );
                result.iterations = iteration + 1;
                if (all_converged) {
                    result.converged = true;
                    sortRoots(result.values[0..degree]);
                    return result;
                }
            }
            result.converged = false;
            sortRoots(result.values[0..degree]);
            return result;
        }

        pub fn valid(self: Self) bool {
            if (self.count == 0 or self.count > capacity) return false;
            for (self.coefficients[0..self.count]) |value| {
                if (!std.math.isFinite(value)) return false;
            }
            for (self.coefficients[self.count..]) |value| {
                if (value != 0.0) return false;
            }
            return true;
        }

        fn effectiveCount(self: Self) usize {
            var result = self.count;
            while (result > 1 and
                self.coefficients[result - 1] == 0.0)
                result -= 1;
            return result;
        }

        fn trim(self: *Self) void {
            self.count = self.effectiveCount();
            @memset(self.coefficients[self.count..], 0.0);
        }

        fn recurrenceStep(
            previous: Self,
            current: Self,
            x_factor: Sample,
            previous_factor: Sample,
        ) !Self {
            if (!previous.valid() or !current.valid())
                return error.InvalidPolynomial;
            if (!std.math.isFinite(x_factor) or
                !std.math.isFinite(previous_factor))
                return error.PolynomialNonFiniteValue;
            if (current.count == capacity)
                return error.PolynomialCapacityExceeded;
            var result = Self{
                .coefficients = @splat(0.0),
                .count = current.count + 1,
            };
            for (0..current.count) |index| {
                const value = current.coefficients[index] * x_factor;
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index + 1] = value;
            }
            for (0..previous.count) |index| {
                const value = result.coefficients[index] -
                    previous.coefficients[index] * previous_factor;
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index] = value;
            }
            result.trim();
            return result;
        }

        fn affineRecurrenceStep(
            previous: Self,
            current: Self,
            constant_factor: Sample,
            x_factor: Sample,
            previous_factor: Sample,
        ) !Self {
            if (!previous.valid() or !current.valid())
                return error.InvalidPolynomial;
            if (!std.math.isFinite(constant_factor) or
                !std.math.isFinite(x_factor) or
                !std.math.isFinite(previous_factor))
            {
                return error.PolynomialNonFiniteValue;
            }
            if (current.count == capacity)
                return error.PolynomialCapacityExceeded;
            var result = Self{
                .coefficients = @splat(0.0),
                .count = current.count + 1,
            };
            for (0..current.count) |index| {
                const constant =
                    result.coefficients[index] +
                    current.coefficients[index] * constant_factor;
                const linear =
                    result.coefficients[index + 1] +
                    current.coefficients[index] * x_factor;
                if (!std.math.isFinite(constant) or
                    !std.math.isFinite(linear))
                {
                    return error.PolynomialNonFiniteValue;
                }
                result.coefficients[index] = constant;
                result.coefficients[index + 1] = linear;
            }
            for (0..previous.count) |index| {
                const value =
                    result.coefficients[index] -
                    previous.coefficients[index] * previous_factor;
                if (!std.math.isFinite(value))
                    return error.PolynomialNonFiniteValue;
                result.coefficients[index] = value;
            }
            result.trim();
            return result;
        }

        fn evaluateComplexMonic(
            self: Self,
            coefficient_count: usize,
            x: Complex,
        ) Complex {
            const degree = coefficient_count - 1;
            const leading = self.coefficients[degree];
            var result = Complex.init(1.0, 0.0);
            var index = degree;
            while (index > 0) {
                index -= 1;
                result = result.mul(x).add(Complex.init(
                    self.coefficients[index] / leading,
                    0.0,
                ));
            }
            return result;
        }

        fn finiteComplex(value: Complex) bool {
            return std.math.isFinite(value.re) and
                std.math.isFinite(value.im);
        }

        fn sortRoots(values: []Complex) void {
            for (1..values.len) |index| {
                const value = values[index];
                var destination = index;
                while (destination > 0 and
                    rootLess(value, values[destination - 1]))
                {
                    values[destination] = values[destination - 1];
                    destination -= 1;
                }
                values[destination] = value;
            }
        }

        fn rootLess(left: Complex, right: Complex) bool {
            if (left.re < right.re) return true;
            if (left.re > right.re) return false;
            return left.im < right.im;
        }
    };
}

test "polynomial evaluation and derivative use ascending coefficients" {
    const P = Polynomial(f64, 4);
    const value = try P.init(&.{ 1.0, 2.0, 3.0 });
    try std.testing.expectEqual(@as(f64, 17.0), value.evaluate(2.0));
    const derivative = try value.derivative();
    try std.testing.expectEqual(@as(f64, 14.0), derivative.evaluate(2.0));
}

test "polynomial addition and multiplication remain bounded" {
    const P = Polynomial(f32, 4);
    const left = try P.init(&.{ 1.0, 1.0 });
    const right = try P.init(&.{ 1.0, -1.0 });
    const sum = try left.add(right);
    try std.testing.expectEqual(@as(f32, 2.0), sum.evaluate(0.5));
    const product = try left.multiply(right);
    try std.testing.expectEqual(@as(f32, -3.0), product.evaluate(2.0));
}

test "polynomial algebra composes integrates and divides" {
    const P = Polynomial(f64, 8);
    const outer = try P.init(&.{ 1.0, 2.0, 3.0 });
    const inner = try P.init(&.{ -1.0, 1.0 });
    const composed = try outer.compose(inner);
    try std.testing.expectApproxEqAbs(
        outer.evaluate(inner.evaluate(2.5)),
        composed.evaluate(2.5),
        0.000_000_000_001,
    );

    const integrated = try outer.integral(7.0);
    const recovered = try integrated.derivative();
    for (0..outer.count) |index| {
        try std.testing.expectApproxEqAbs(
            outer.coefficients[index],
            recovered.coefficients[index],
            0.000_000_000_001,
        );
    }

    const dividend = try P.init(&.{ -6.0, 11.0, -6.0, 1.0 });
    const divisor = try P.init(&.{ -1.0, 1.0 });
    const division = try dividend.divide(divisor);
    try std.testing.expectEqual(@as(usize, 3), division.quotient.count);
    try std.testing.expectEqual(@as(usize, 1), division.remainder.count);
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        division.remainder.coefficients[0],
        0.000_000_000_001,
    );
    const reconstructed = try (try division.quotient.multiply(
        divisor,
    )).add(division.remainder);
    for (0..dividend.count) |index| {
        try std.testing.expectApproxEqAbs(
            dividend.coefficients[index],
            reconstructed.coefficients[index],
            0.000_000_000_001,
        );
    }
}

test "polynomial division and composition preserve failure contracts" {
    const P = Polynomial(f32, 3);
    const value = try P.init(&.{ 1.0, 2.0, 3.0 });
    const zero = try P.init(&.{0.0});
    try std.testing.expectError(
        error.PolynomialDivisionByZero,
        value.divide(zero),
    );
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        value.compose(try P.init(&.{ 0.0, 1.0, 1.0 })),
    );
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        value.integral(0.0),
    );
    try std.testing.expectError(
        error.PolynomialNonFiniteValue,
        value.integral(std.math.nan(f32)),
    );
}

test "polynomial interpolation reconstructs bounded point sets" {
    const P = Polynomial(f64, 5);
    const x_values = [_]f64{ -2.0, -0.5, 1.0, 3.0 };
    const y_values = [_]f64{ 9.0, 2.25, 0.0, 4.0 };
    const result = try P.interpolate(&x_values, &y_values);
    for (x_values, y_values) |x, expected| {
        try std.testing.expectApproxEqAbs(
            expected,
            result.evaluate(x),
            0.000_000_000_001,
        );
    }
    try std.testing.expectError(
        error.DuplicatePolynomialPoint,
        P.interpolate(&.{ 1.0, 1.0 }, &.{ 2.0, 3.0 }),
    );
    try std.testing.expectError(
        error.InvalidPolynomialPoints,
        P.interpolate(&.{1.0}, &.{ 2.0, 3.0 }),
    );
}

test "polynomial least squares uses rectangular QR fitting" {
    const P = Polynomial(f64, 4);
    const exact = try P.fitLeastSquares(
        5,
        2,
        .{ -2.0, -1.0, 0.0, 1.0, 2.0 },
        .{ 9.0, 4.0, 1.0, 0.0, 1.0 },
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        exact.coefficients[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -2.0),
        exact.coefficients[1],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        exact.coefficients[2],
        0.000_000_000_001,
    );

    const linear = try P.fitLeastSquares(
        3,
        1,
        .{ 1.0, 2.0, 3.0 },
        .{ 1.0, 2.0, 2.0 },
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 2.0 / 3.0),
        linear.coefficients[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.5),
        linear.coefficients[1],
        0.000_000_000_001,
    );
}

test "polynomial minimum-norm fitting accepts rank deficiency" {
    const P = Polynomial(f64, 4);
    const fitted = try P.fitLeastSquaresMinimumNorm(
        3,
        2,
        .{ 0.0, 0.0, 1.0 },
        .{ 1.0, 1.0, 3.0 },
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        fitted.coefficients[0],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        fitted.coefficients[1],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        fitted.coefficients[2],
        0.000_000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 3.0),
        fitted.evaluate(1.0),
        0.000_000_000_001,
    );
}

test "polynomial constructs Legendre families through bounded recurrence" {
    const P = Polynomial(f64, 8);
    const fourth = try P.legendre(4);
    try std.testing.expectEqual(@as(usize, 5), fourth.count);
    for (
        [_]f64{ 3.0 / 8.0, 0.0, -30.0 / 8.0, 0.0, 35.0 / 8.0 },
        fourth.coefficients[0..5],
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
    for (0..7) |degree| {
        const value = try P.legendre(degree);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            value.evaluate(1.0),
            0.000_000_000_001,
        );
        try std.testing.expectApproxEqAbs(
            if (degree % 2 == 0)
                @as(f64, 1.0)
            else
                @as(f64, -1.0),
            value.evaluate(-1.0),
            0.000_000_000_001,
        );
    }
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        P.legendre(std.math.maxInt(usize)),
    );
}

test "polynomial constructs both Chebyshev families" {
    const P = Polynomial(f64, 8);
    const first = try P.chebyshevFirstKind(5);
    const second = try P.chebyshevSecondKind(4);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 0.0, 5.0, 0.0, -20.0, 0.0, 16.0 },
        first.coefficients[0..6],
    );
    try std.testing.expectEqualSlices(
        f64,
        &.{ 1.0, 0.0, -12.0, 0.0, 16.0 },
        second.coefficients[0..5],
    );

    const angle: f64 = 0.37;
    const x = @cos(angle);
    for (0..7) |degree| {
        const first_value = try P.chebyshevFirstKind(degree);
        try std.testing.expectApproxEqAbs(
            @cos(@as(f64, @floatFromInt(degree)) * angle),
            first_value.evaluate(x),
            0.000_000_000_001,
        );
        const second_value = try P.chebyshevSecondKind(degree);
        try std.testing.expectApproxEqAbs(
            @sin(@as(f64, @floatFromInt(degree + 1)) * angle) /
                @sin(angle),
            second_value.evaluate(x),
            0.000_000_000_01,
        );
    }

    const P32 = Polynomial(f32, 5);
    try std.testing.expectApproxEqAbs(
        @as(f32, -1.0),
        (try P32.chebyshevFirstKind(3)).evaluate(-1.0),
        0.000_01,
    );
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        P32.chebyshevSecondKind(5),
    );
}

test "polynomial constructs both Hermite normalizations" {
    const P = Polynomial(f64, 8);
    const physicists = try P.hermitePhysicists(4);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 12.0, 0.0, -48.0, 0.0, 16.0 },
        physicists.coefficients[0..5],
    );
    const probabilists = try P.hermiteProbabilists(4);
    try std.testing.expectEqualSlices(
        f64,
        &.{ 3.0, 0.0, -6.0, 0.0, 1.0 },
        probabilists.coefficients[0..5],
    );
    for (0..7) |degree| {
        const physicists_value =
            try P.hermitePhysicists(degree);
        const probabilists_value =
            try P.hermiteProbabilists(degree);
        const x: f64 = 0.37;
        try std.testing.expectApproxEqAbs(
            physicists_value.evaluate(x),
            std.math.pow(
                f64,
                2.0,
                @as(f64, @floatFromInt(degree)) / 2.0,
            ) *
                probabilists_value.evaluate(x * @sqrt(2.0)),
            0.000_000_000_01,
        );
    }
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        P.hermitePhysicists(8),
    );
}

test "polynomial constructs ordinary and generalized Laguerre families" {
    const P = Polynomial(f64, 8);
    const ordinary = try P.laguerre(4);
    for (
        [_]f64{ 1.0, -4.0, 3.0, -2.0 / 3.0, 1.0 / 24.0 },
        ordinary.coefficients[0..5],
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
    const generalized = try P.generalizedLaguerre(3, 2.0);
    for (
        [_]f64{ 10.0, -10.0, 2.5, -1.0 / 6.0 },
        generalized.coefficients[0..4],
    ) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_000_001,
        );
    }
    try std.testing.expectError(
        error.InvalidPolynomialFamilyParameter,
        P.generalizedLaguerre(2, -1.0),
    );
}

test "polynomial constructs general Jacobi families" {
    const P = Polynomial(f64, 9);
    const selected = try P.jacobi(2, 1.0, 0.0);
    try std.testing.expectEqualSlices(
        f64,
        &.{ -0.5, 1.0, 2.5 },
        selected.coefficients[0..3],
    );
    for (0..8) |degree| {
        const jacobi_value = try P.jacobi(degree, 0.0, 0.0);
        const legendre_value = try P.legendre(degree);
        for (0..degree + 1) |index| {
            try std.testing.expectApproxEqAbs(
                legendre_value.coefficients[index],
                jacobi_value.coefficients[index],
                0.000_000_000_01,
            );
        }
    }
    try std.testing.expectError(
        error.InvalidPolynomialFamilyParameter,
        P.jacobi(2, std.math.nan(f64), 0.0),
    );
    try std.testing.expectError(
        error.InvalidPolynomialFamilyParameter,
        P.jacobi(2, 0.0, -1.0),
    );
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        P.jacobi(9, 0.0, 0.0),
    );
}

test "polynomial rejects capacity and finite-state violations" {
    const P = Polynomial(f32, 2);
    try std.testing.expectEqual(@as(usize, 2), P.coefficient_capacity);
    try std.testing.expectEqual(@as(usize, 1), P.maximum_degree);
    try std.testing.expectEqual(
        @as(f32, 1.0e-5),
        P.default_root_tolerance,
    );
    try std.testing.expectEqual(
        @as(usize, 256),
        P.default_root_maximum_iterations,
    );
    try std.testing.expectEqual(
        P.default_root_tolerance,
        (P.RootOptions{}).tolerance,
    );
    try std.testing.expectEqual(
        P.default_root_maximum_iterations,
        (P.RootOptions{}).maximum_iterations,
    );
    try std.testing.expectError(
        error.PolynomialCapacityExceeded,
        P.init(&.{ 1.0, 2.0, 3.0 }),
    );
    var value = try P.init(&.{1.0});
    value.coefficients[1] = 2.0;
    try std.testing.expect(!value.valid());
    try std.testing.expectEqual(@as(f32, 0.0), value.evaluate(1.0));
}

test "polynomial finds real and conjugate complex roots" {
    const P = Polynomial(f64, 5);
    const cubic = try P.init(&.{ -1.0, 0.0, 0.0, 1.0 });
    const roots = try cubic.findRoots(.{});
    try std.testing.expect(roots.converged);
    try std.testing.expectEqual(@as(usize, 3), roots.count);
    try std.testing.expectApproxEqAbs(
        @as(f64, -0.5),
        roots.values[0].re,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        -@sqrt(@as(f64, 0.75)),
        roots.values[0].im,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, -0.5),
        roots.values[1].re,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        @sqrt(@as(f64, 0.75)),
        roots.values[1].im,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        roots.values[2].re,
        1.0e-10,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        roots.values[2].im,
        1.0e-10,
    );
    try std.testing.expectEqual(@as(f64, 0.0), roots.values[3].re);
    try std.testing.expectEqual(@as(f64, 0.0), roots.values[3].im);

    var malformed = roots;
    malformed.count = std.math.maxInt(usize);
    try std.testing.expect(!malformed.valid());
    try std.testing.expectEqual(@as(usize, 0), malformed.slice().len);
}

test "polynomial roots handle constants linear terms and trailing zeros" {
    const P = Polynomial(f32, 4);
    const constant = try P.init(&.{2.0});
    const no_roots = try constant.findRoots(.{});
    try std.testing.expect(no_roots.converged);
    try std.testing.expectEqual(@as(usize, 0), no_roots.count);
    for (no_roots.values) |root| {
        try std.testing.expectEqual(@as(f32, 0.0), root.re);
        try std.testing.expectEqual(@as(f32, 0.0), root.im);
    }

    const linear = try P.init(&.{ 6.0, 3.0, 0.0 });
    const one_root = try linear.findRoots(.{});
    try std.testing.expectEqual(@as(usize, 1), one_root.count);
    try std.testing.expectEqual(@as(f32, -2.0), one_root.values[0].re);
    try std.testing.expectEqual(@as(f32, 0.0), one_root.values[0].im);
}

test "polynomial roots report repeated-root and iteration-limit outcomes" {
    const P = Polynomial(f64, 3);
    const repeated = try P.init(&.{ 1.0, -2.0, 1.0 });
    const solved = try repeated.findRoots(.{
        .tolerance = 1.0e-10,
    });
    try std.testing.expect(solved.converged);
    for (solved.slice()) |root| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            root.re,
            1.0e-6,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            root.im,
            1.0e-6,
        );
    }

    const limited = try repeated.findRoots(.{
        .tolerance = 1.0e-15,
        .maximum_iterations = 1,
    });
    try std.testing.expect(!limited.converged);
    try std.testing.expectEqual(@as(usize, 1), limited.iterations);
}

test "polynomial roots reject indeterminate and invalid solver inputs" {
    const P = Polynomial(f64, 3);
    const zero = try P.init(&.{ 0.0, 0.0 });
    try std.testing.expectError(
        error.IndeterminatePolynomialRoots,
        zero.findRoots(.{}),
    );
    const quadratic = try P.init(&.{ 1.0, 0.0, 1.0 });
    try std.testing.expectError(
        error.InvalidRootTolerance,
        quadratic.findRoots(.{ .tolerance = 0.0 }),
    );
    try std.testing.expectError(
        error.InvalidRootIterationLimit,
        quadratic.findRoots(.{ .maximum_iterations = 0 }),
    );
}
