const std = @import("std");
const builtin = @import("builtin");

pub fn nativeLaneCount(comptime Sample: type) usize {
    if (Sample != f32 and Sample != f64)
        @compileError("native SIMD width supports f32 and f64 samples");
    const vector_bytes: usize = switch (builtin.cpu.arch) {
        .x86_64 => if (builtin.cpu.has(.x86, .avx2)) 32 else 16,
        .aarch64 => if (builtin.cpu.has(.aarch64, .neon)) 16 else @sizeOf(Sample),
        else => @sizeOf(Sample),
    };
    return @max(vector_bytes / @sizeOf(Sample), 1);
}

pub fn NativeRegister(comptime Sample: type) type {
    return Register(Sample, nativeLaneCount(Sample));
}

/// Provides fixed-lane vector arithmetic with checked slice boundaries.
pub fn Register(comptime Sample: type, comptime lane_count: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("SIMD registers support f32 and f64 samples");
    if (lane_count == 0 or lane_count > 64)
        @compileError("SIMD register lane count must be between 1 and 64");

    const Vector = @Vector(lane_count, Sample);

    return struct {
        const Self = @This();
        pub const Mask = @Vector(lane_count, bool);
        pub const alignment = @alignOf(Vector);
        pub const lanes = lane_count;

        values: Vector,

        pub fn splat(value: Sample) !Self {
            if (!std.math.isFinite(value))
                return error.InvalidSimdRegisterValue;
            return .{ .values = @splat(value) };
        }

        /// Reads exactly one register without requiring aligned storage.
        pub fn load(source: []const Sample) !Self {
            if (source.len < lane_count)
                return error.SimdRegisterSliceTooShort;

            var result: Vector = undefined;
            inline for (0..lane_count) |lane| {
                const value = source[lane];
                if (!std.math.isFinite(value))
                    return error.InvalidSimdRegisterValue;
                result[lane] = value;
            }
            return .{ .values = result };
        }

        pub fn loadAligned(source: []const Sample) !Self {
            if (source.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (@intFromPtr(source.ptr) % alignment != 0)
                return error.SimdRegisterMisaligned;
            return load(source);
        }

        /// Validates the destination size before replacing any sample.
        pub fn store(self: Self, destination: []Sample) !void {
            if (destination.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (!self.valid())
                return error.InvalidSimdRegisterValue;

            inline for (0..lane_count) |lane|
                destination[lane] = self.values[lane];
        }

        pub fn storeAligned(self: Self, destination: []Sample) !void {
            if (destination.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (@intFromPtr(destination.ptr) % alignment != 0)
                return error.SimdRegisterMisaligned;
            return self.store(destination);
        }

        pub fn add(self: Self, other: Self) !Self {
            return checked(self.values + other.values);
        }

        pub fn subtract(self: Self, other: Self) !Self {
            return checked(self.values - other.values);
        }

        pub fn multiply(self: Self, other: Self) !Self {
            return checked(self.values * other.values);
        }

        pub fn divide(self: Self, other: Self) !Self {
            if (!self.valid() or !other.valid())
                return error.InvalidSimdRegisterValue;
            inline for (0..lane_count) |lane|
                if (other.values[lane] == 0.0)
                    return error.SimdRegisterDivisionByZero;
            return checked(self.values / other.values);
        }

        pub fn multiplyAdd(
            self: Self,
            multiplier: Self,
            addend: Self,
        ) !Self {
            return checked(self.values * multiplier.values + addend.values);
        }

        pub fn minimum(self: Self, other: Self) !Self {
            return checked(@min(self.values, other.values));
        }

        pub fn maximum(self: Self, other: Self) !Self {
            return checked(@max(self.values, other.values));
        }

        pub fn absolute(self: Self) !Self {
            return checked(@abs(self.values));
        }

        pub fn squareRoot(self: Self) !Self {
            if (!self.valid())
                return error.InvalidSimdRegisterValue;
            inline for (0..lane_count) |lane|
                if (self.values[lane] < 0.0)
                    return error.InvalidSimdRegisterSquareRoot;
            return checked(@sqrt(self.values));
        }

        pub fn lessThan(self: Self, other: Self) Mask {
            return self.values < other.values;
        }

        pub fn greaterThan(self: Self, other: Self) Mask {
            return self.values > other.values;
        }

        pub fn select(
            mask: Mask,
            when_true: Self,
            when_false: Self,
        ) !Self {
            return checked(@select(
                Sample,
                mask,
                when_true.values,
                when_false.values,
            ));
        }

        pub fn getLane(self: Self, index: usize) !Sample {
            if (index >= lane_count)
                return error.SimdRegisterLaneOutOfRange;
            if (!self.valid())
                return error.InvalidSimdRegisterValue;
            const lane_values: [lane_count]Sample = @bitCast(self.values);
            return lane_values[index];
        }

        pub fn horizontalSum(self: Self) !Sample {
            if (!self.valid())
                return error.InvalidSimdRegisterValue;
            var result: Sample = 0.0;
            inline for (0..lane_count) |lane| {
                result += self.values[lane];
                if (!std.math.isFinite(result))
                    return error.InvalidSimdRegisterResult;
            }
            return result;
        }

        pub fn dot(self: Self, other: Self) !Sample {
            return (try self.multiply(other)).horizontalSum();
        }

        pub fn valid(self: Self) bool {
            inline for (0..lane_count) |lane|
                if (!std.math.isFinite(self.values[lane])) return false;
            return true;
        }

        fn checked(values: Vector) !Self {
            const result = Self{ .values = values };
            if (!result.valid())
                return error.InvalidSimdRegisterResult;
            return result;
        }
    };
}

pub fn ComplexRegister(
    comptime Sample: type,
    comptime lane_count: usize,
) type {
    const Real = Register(Sample, lane_count);
    const Complex = std.math.Complex(Sample);
    return struct {
        const Self = @This();
        pub const alignment = Real.alignment;
        pub const lanes = lane_count;

        real: Real,
        imaginary: Real,

        pub fn load(
            real: []const Sample,
            imaginary: []const Sample,
        ) !Self {
            return .{
                .real = try Real.load(real),
                .imaginary = try Real.load(imaginary),
            };
        }

        pub fn loadAligned(
            real: []const Sample,
            imaginary: []const Sample,
        ) !Self {
            return .{
                .real = try Real.loadAligned(real),
                .imaginary = try Real.loadAligned(imaginary),
            };
        }

        /// Reads interleaved complex values into split SIMD planes.
        pub fn loadInterleaved(source: []const Complex) !Self {
            if (source.len < lane_count)
                return error.SimdRegisterSliceTooShort;

            var real: [lane_count]Sample = undefined;
            var imaginary: [lane_count]Sample = undefined;
            inline for (0..lane_count) |lane| {
                real[lane] = source[lane].re;
                imaginary[lane] = source[lane].im;
            }
            return load(&real, &imaginary);
        }

        pub fn store(
            self: Self,
            real: []Sample,
            imaginary: []Sample,
        ) !void {
            if (real.len < lane_count or imaginary.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (simdSlicesOverlap(
                Sample,
                real[0..lane_count],
                imaginary[0..lane_count],
            ))
                return error.SimdComplexDestinationsOverlap;
            if (!self.valid()) return error.InvalidSimdRegisterValue;
            try self.real.store(real);
            try self.imaginary.store(imaginary);
        }

        pub fn storeAligned(
            self: Self,
            real: []Sample,
            imaginary: []Sample,
        ) !void {
            if (real.len < lane_count or imaginary.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (@intFromPtr(real.ptr) % alignment != 0 or
                @intFromPtr(imaginary.ptr) % alignment != 0)
                return error.SimdRegisterMisaligned;
            return self.store(real, imaginary);
        }

        /// Replaces exactly one register of interleaved complex values.
        pub fn storeInterleaved(
            self: Self,
            destination: []Complex,
        ) !void {
            if (destination.len < lane_count)
                return error.SimdRegisterSliceTooShort;
            if (!self.valid())
                return error.InvalidSimdRegisterValue;

            inline for (0..lane_count) |lane| {
                destination[lane] = Complex.init(
                    self.real.values[lane],
                    self.imaginary.values[lane],
                );
            }
        }

        pub fn add(self: Self, other: Self) !Self {
            return .{
                .real = try self.real.add(other.real),
                .imaginary = try self.imaginary.add(other.imaginary),
            };
        }

        pub fn subtract(self: Self, other: Self) !Self {
            return .{
                .real = try self.real.subtract(other.real),
                .imaginary = try self.imaginary.subtract(other.imaginary),
            };
        }

        pub fn multiply(self: Self, other: Self) !Self {
            const ac = try self.real.multiply(other.real);
            const bd = try self.imaginary.multiply(other.imaginary);
            const ad = try self.real.multiply(other.imaginary);
            const bc = try self.imaginary.multiply(other.real);
            return .{
                .real = try ac.subtract(bd),
                .imaginary = try ad.add(bc),
            };
        }

        pub fn conjugate(self: Self) !Self {
            return .{
                .real = self.real,
                .imaginary = try self.imaginary.multiply(
                    try Real.splat(-1.0),
                ),
            };
        }

        pub fn magnitudeSquared(self: Self) !Real {
            return (try self.real.multiply(self.real)).add(
                try self.imaginary.multiply(self.imaginary),
            );
        }

        pub fn valid(self: Self) bool {
            return self.real.valid() and self.imaginary.valid();
        }
    };
}

pub fn NativeComplexRegister(comptime Sample: type) type {
    return ComplexRegister(Sample, nativeLaneCount(Sample));
}

fn simdSlicesOverlap(
    comptime Sample: type,
    first: anytype,
    second: anytype,
) bool {
    if (first.len == 0 or second.len == 0) return false;
    const first_start = @intFromPtr(first.ptr);
    const second_start = @intFromPtr(second.ptr);
    const first_end = first_start + first.len * @sizeOf(Sample);
    const second_end = second_start + second.len * @sizeOf(Sample);
    return first_start < second_end and second_start < first_end;
}

test "SIMD register loads stores and combines unaligned slices" {
    const Simd = Register(f32, 4);
    const source = [_]f32{ 99.0, 1.0, 2.0, 3.0, 4.0 };
    const left = try Simd.load(source[1..]);
    const right = try Simd.splat(2.0);
    const offset = try Simd.splat(1.0);
    const result = try left.multiplyAdd(right, offset);

    var destination = [_]f32{ 0.0, 0.0, 0.0, 0.0, 99.0 };
    try result.store(&destination);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 3.0, 5.0, 7.0, 9.0, 99.0 },
        &destination,
    );
}

test "SIMD register reductions cover f64 lanes" {
    const Simd = Register(f64, 2);
    const left = try Simd.load(&.{ 1.5, -2.0 });
    const right = try Simd.load(&.{ 2.0, 4.0 });
    try std.testing.expectEqual(@as(f64, -5.0), try left.dot(right));
    try std.testing.expectEqual(
        @as(f64, -0.5),
        try left.horizontalSum(),
    );
}

test "SIMD register rejects bounds and non-finite results" {
    const Simd = Register(f32, 4);
    try std.testing.expectError(
        error.SimdRegisterSliceTooShort,
        Simd.load(&.{ 1.0, 2.0, 3.0 }),
    );
    try std.testing.expectError(
        error.InvalidSimdRegisterValue,
        Simd.load(&.{ 1.0, 2.0, std.math.nan(f32), 4.0 }),
    );
    const huge = try Simd.splat(std.math.floatMax(f32));
    try std.testing.expectError(
        error.InvalidSimdRegisterResult,
        huge.add(huge),
    );

    const valid = try Simd.splat(1.0);
    var destination = [_]f32{ 7.0, 7.0, 7.0 };
    const before = destination;
    try std.testing.expectError(
        error.SimdRegisterSliceTooShort,
        valid.store(&destination),
    );
    try std.testing.expectEqualSlices(f32, &before, &destination);
}

test "SIMD register supports division roots extrema and masks" {
    const Simd = Register(f32, 4);
    const left = try Simd.load(&.{ 1.0, 8.0, 9.0, 16.0 });
    const right = try Simd.load(&.{ 2.0, 4.0, 12.0, 8.0 });
    const divided = try left.divide(right);
    const rooted = try left.squareRoot();
    const selected = try Simd.select(
        left.lessThan(right),
        left,
        right,
    );
    var values: [4]f32 = undefined;
    try divided.store(&values);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 0.5, 2.0, 0.75, 2.0 },
        &values,
    );
    try std.testing.expectEqual(@as(f32, 3.0), try rooted.getLane(2));
    try selected.store(&values);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 4.0, 9.0, 8.0 },
        &values,
    );
    try (try left.minimum(right)).store(&values);
    try std.testing.expectEqualSlices(
        f32,
        &.{ 1.0, 4.0, 9.0, 8.0 },
        &values,
    );
}

test "SIMD register rejects invalid division roots and lanes" {
    const Simd = Register(f64, 2);
    const values = try Simd.load(&.{ 1.0, -1.0 });
    try std.testing.expectError(
        error.InvalidSimdRegisterSquareRoot,
        values.squareRoot(),
    );
    try std.testing.expectError(
        error.SimdRegisterDivisionByZero,
        values.divide(try Simd.load(&.{ 1.0, 0.0 })),
    );
    try std.testing.expectError(
        error.SimdRegisterLaneOutOfRange,
        values.getLane(2),
    );
}

test "native SIMD width follows the compiled target" {
    const lanes = nativeLaneCount(f32);
    try std.testing.expect(lanes >= 1);
    try std.testing.expectEqual(
        @as(usize, lanes),
        NativeRegister(f32).lanes,
    );
    if (builtin.cpu.arch == .aarch64 and
        builtin.cpu.has(.aarch64, .neon))
        try std.testing.expectEqual(@as(usize, 4), lanes);
}

test "SIMD register aligned APIs reject misaligned slices" {
    const Simd = Register(f32, 4);
    var aligned: [4]f32 align(Simd.alignment) = .{ 1.0, 2.0, 3.0, 4.0 };
    const value = try Simd.loadAligned(&aligned);
    try value.storeAligned(&aligned);

    const source: [5]f32 align(Simd.alignment) =
        .{ 0.0, 1.0, 2.0, 3.0, 4.0 };
    try std.testing.expectError(
        error.SimdRegisterMisaligned,
        Simd.loadAligned(source[1..]),
    );
}

test "complex SIMD lanes multiply conjugate and measure magnitude" {
    const Complex = ComplexRegister(f64, 2);
    const left = try Complex.load(&.{ 1.0, 2.0 }, &.{ 2.0, -1.0 });
    const right = try Complex.load(&.{ 3.0, -2.0 }, &.{ -1.0, 4.0 });
    const product = try left.multiply(right);
    var real: [2]f64 = undefined;
    var imaginary: [2]f64 = undefined;
    try product.store(&real, &imaginary);
    try std.testing.expectEqualSlices(f64, &.{ 5.0, 0.0 }, &real);
    try std.testing.expectEqualSlices(f64, &.{ 5.0, 10.0 }, &imaginary);

    const magnitude = try (try left.conjugate()).magnitudeSquared();
    try magnitude.store(&real);
    try std.testing.expectEqualSlices(f64, &.{ 5.0, 5.0 }, &real);
}

test "complex SIMD aligned storage validates both destinations" {
    const Complex = ComplexRegister(f32, 4);
    const source_real: [4]f32 align(Complex.alignment) =
        .{ 1.0, 2.0, 3.0, 4.0 };
    const source_imaginary: [4]f32 align(Complex.alignment) =
        .{ -1.0, -2.0, -3.0, -4.0 };
    const value = try Complex.loadAligned(
        &source_real,
        &source_imaginary,
    );
    var destination_real: [4]f32 align(Complex.alignment) = @splat(0.0);
    var destination_imaginary: [4]f32 align(Complex.alignment) = @splat(0.0);
    try value.storeAligned(
        &destination_real,
        &destination_imaginary,
    );
    try std.testing.expectEqualSlices(
        f32,
        &source_real,
        &destination_real,
    );
    try std.testing.expectEqualSlices(
        f32,
        &source_imaginary,
        &destination_imaginary,
    );

    var shared_storage: [8]f32 = @splat(0.0);
    try value.store(
        shared_storage[0..],
        shared_storage[4..],
    );
    try std.testing.expectEqualSlices(
        f32,
        &source_real,
        shared_storage[0..4],
    );
    try std.testing.expectEqualSlices(
        f32,
        &source_imaginary,
        shared_storage[4..8],
    );

    var misaligned_storage: [9]f32 align(Complex.alignment) = @splat(9.0);
    const before = misaligned_storage;
    try std.testing.expectError(
        error.SimdRegisterMisaligned,
        value.storeAligned(
            misaligned_storage[0..4],
            misaligned_storage[5..9],
        ),
    );
    try std.testing.expectEqualSlices(
        f32,
        &before,
        &misaligned_storage,
    );
    try std.testing.expectError(
        error.SimdComplexDestinationsOverlap,
        value.store(
            misaligned_storage[0..4],
            misaligned_storage[2..6],
        ),
    );
}

test "complex SIMD loads and stores interleaved values transactionally" {
    const Complex = ComplexRegister(f32, 4);
    const Value = std.math.Complex(f32);
    const source = [_]Value{
        Value.init(1.0, -1.0),
        Value.init(2.0, -2.0),
        Value.init(3.0, -3.0),
        Value.init(4.0, -4.0),
        Value.init(99.0, 99.0),
    };
    const value = try Complex.loadInterleaved(&source);
    var destination = [_]Value{
        Value.init(0.0, 0.0),
        Value.init(0.0, 0.0),
        Value.init(0.0, 0.0),
        Value.init(0.0, 0.0),
        Value.init(77.0, 77.0),
    };
    try value.storeInterleaved(&destination);
    try std.testing.expectEqualSlices(
        Value,
        source[0..4],
        destination[0..4],
    );
    try std.testing.expectEqual(Value.init(77.0, 77.0), destination[4]);

    var short = [_]Value{
        Value.init(8.0, 8.0),
        Value.init(8.0, 8.0),
        Value.init(8.0, 8.0),
    };
    const before = short;
    try std.testing.expectError(
        error.SimdRegisterSliceTooShort,
        value.storeInterleaved(&short),
    );
    try std.testing.expectEqualSlices(Value, &before, &short);
}

test "complex SIMD rejects invalid interleaved input" {
    const Complex = ComplexRegister(f64, 2);
    const Value = std.math.Complex(f64);
    try std.testing.expectError(
        error.SimdRegisterSliceTooShort,
        Complex.loadInterleaved(&.{Value.init(1.0, 2.0)}),
    );
    try std.testing.expectError(
        error.InvalidSimdRegisterValue,
        Complex.loadInterleaved(&.{
            Value.init(1.0, 2.0),
            Value.init(std.math.nan(f64), 3.0),
        }),
    );
}
