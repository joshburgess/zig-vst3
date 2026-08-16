const std = @import("std");

pub fn Transform(comptime Sample: type, comptime size: usize) type {
    if (Sample != f32 and Sample != f64)
        @compileError("FFT supports f32 and f64 samples");
    if (size < 2 or !std.math.isPowerOfTwo(size))
        @compileError("FFT size must be a power of two of at least two");

    return struct {
        const Self = @This();

        pub const Value = struct {
            real: Sample = 0.0,
            imaginary: Sample = 0.0,

            pub fn valid(self: Value) bool {
                return std.math.isFinite(self.real) and
                    std.math.isFinite(self.imaginary);
            }

            pub fn magnitude(self: Value) Sample {
                if (!self.valid()) return 0.0;
                const scale = @max(@abs(self.real), @abs(self.imaginary));
                if (scale == 0.0) return 0.0;
                const real = self.real / scale;
                const imaginary = self.imaginary / scale;
                const result = scale * @sqrt(
                    real * real + imaginary * imaginary,
                );
                return if (std.math.isFinite(result)) result else 0.0;
            }

            pub fn multiplyAdd(
                target: *Value,
                left: Value,
                right: Value,
            ) void {
                target.real +=
                    left.real * right.real - left.imaginary * right.imaginary;
                target.imaginary +=
                    left.real * right.imaginary + left.imaginary * right.real;
            }
        };

        forward_twiddles: [size / 2]Value,
        inverse_twiddles: [size / 2]Value,

        pub fn init() Self {
            var self: Self = undefined;
            for (0..size / 2) |index| {
                const angle = std.math.tau *
                    @as(Sample, @floatFromInt(index)) /
                    @as(Sample, @floatFromInt(size));
                self.forward_twiddles[index] = .{
                    .real = @cos(angle),
                    .imaginary = -@sin(angle),
                };
                self.inverse_twiddles[index] = .{
                    .real = @cos(angle),
                    .imaginary = @sin(angle),
                };
            }
            return self;
        }

        pub fn forward(self: *const Self, values: *[size]Value) !void {
            try validate(values);
            self.transform(values, false);
        }

        pub fn inverse(self: *const Self, values: *[size]Value) !void {
            try validate(values);
            self.transform(values, true);
        }

        pub fn forwardReal(
            self: *const Self,
            input: *const [size]Sample,
            output: *[size]Value,
        ) !void {
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteFftInput;
            }
            for (input, output) |sample, *value| {
                value.* = .{ .real = sample };
            }
            self.transform(output, false);
        }

        pub fn inverseReal(
            self: *const Self,
            input: *const [size]Value,
            output: *[size]Sample,
        ) !void {
            try validate(input);
            var values = input.*;
            self.transform(&values, true);
            for (values, output) |value, *sample|
                sample.* = value.real;
        }

        pub fn forwardMagnitudes(
            self: *const Self,
            input: *const [size]Sample,
            output: *[size / 2 + 1]Sample,
        ) !void {
            for (input) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFiniteFftInput;
            }
            var values: [size]Value = undefined;
            for (input, &values) |sample, *value|
                value.* = .{ .real = sample };
            self.transform(&values, false);
            for (values[0 .. size / 2 + 1], output) |value, *magnitude|
                magnitude.* = value.magnitude();
        }

        fn validate(values: *const [size]Value) !void {
            for (values) |value| {
                if (!value.valid()) return error.NonFiniteFftInput;
            }
        }

        fn transform(
            self: *const Self,
            values: *[size]Value,
            inverse_transform: bool,
        ) void {
            var target: usize = 0;
            for (1..size) |index| {
                var bit = size >> 1;
                while (target & bit != 0) : (bit >>= 1) target &= ~bit;
                target |= bit;
                if (index < target)
                    std.mem.swap(Value, &values[index], &values[target]);
            }

            const twiddles = if (inverse_transform)
                &self.inverse_twiddles
            else
                &self.forward_twiddles;
            var length: usize = 2;
            while (length <= size) : (length *= 2) {
                const stride = size / length;
                var start: usize = 0;
                while (start < size) : (start += length) {
                    for (0..length / 2) |offset| {
                        const even = start + offset;
                        const odd = even + length / 2;
                        const twiddle = twiddles[offset * stride];
                        const odd_value = Value{
                            .real = values[odd].real * twiddle.real -
                                values[odd].imaginary * twiddle.imaginary,
                            .imaginary = values[odd].real * twiddle.imaginary +
                                values[odd].imaginary * twiddle.real,
                        };
                        values[odd] = .{
                            .real = values[even].real - odd_value.real,
                            .imaginary = values[even].imaginary - odd_value.imaginary,
                        };
                        values[even].real += odd_value.real;
                        values[even].imaginary += odd_value.imaginary;
                    }
                }
            }
            if (inverse_transform) {
                const scale =
                    1.0 / @as(Sample, @floatFromInt(size));
                for (values) |*value| {
                    value.real *= scale;
                    value.imaginary *= scale;
                }
            }
        }
    };
}

test "FFT impulse and cosine have deterministic bins" {
    const Fft = Transform(f64, 8);
    var fft = Fft.init();
    var impulse: [8]Fft.Value = @splat(.{});
    impulse[0].real = 1.0;
    try fft.forward(&impulse);
    for (impulse) |bin| {
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            bin.real,
            0.000_000_001,
        );
        try std.testing.expectApproxEqAbs(
            @as(f64, 0.0),
            bin.imaginary,
            0.000_000_001,
        );
    }

    var cosine: [8]f64 = undefined;
    for (&cosine, 0..) |*sample, index| {
        sample.* = @cos(
            std.math.tau * @as(f64, @floatFromInt(index)) / 8.0,
        );
    }
    var spectrum: [8]Fft.Value = undefined;
    try fft.forwardReal(&cosine, &spectrum);
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        spectrum[1].magnitude(),
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        spectrum[7].magnitude(),
        0.000_000_001,
    );
}

test "FFT inverse round trips complex values" {
    const Fft = Transform(f32, 16);
    var fft = Fft.init();
    var values: [16]Fft.Value = undefined;
    for (&values, 0..) |*value, index| {
        value.* = .{
            .real = @as(f32, @floatFromInt(index)) * 0.25 - 1.0,
            .imaginary = @as(f32, @floatFromInt(index % 3)) * 0.1,
        };
    }
    const original = values;
    try fft.forward(&values);
    try fft.inverse(&values);
    for (values, original) |actual, expected| {
        try std.testing.expectApproxEqAbs(
            expected.real,
            actual.real,
            0.000_01,
        );
        try std.testing.expectApproxEqAbs(
            expected.imaginary,
            actual.imaginary,
            0.000_01,
        );
    }
}

test "FFT real inverse and magnitude helpers are bounded" {
    const Fft = Transform(f64, 8);
    const fft = Fft.init();
    var input: [8]f64 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* = @cos(
            std.math.tau * @as(f64, @floatFromInt(index)) / 8.0,
        );
    }
    var spectrum: [8]Fft.Value = undefined;
    try fft.forwardReal(&input, &spectrum);
    var restored: [8]f64 = undefined;
    try fft.inverseReal(&spectrum, &restored);
    for (input, restored) |expected, actual| {
        try std.testing.expectApproxEqAbs(
            expected,
            actual,
            0.000_000_001,
        );
    }

    var magnitudes: [5]f64 = undefined;
    try fft.forwardMagnitudes(&input, &magnitudes);
    try std.testing.expectApproxEqAbs(
        @as(f64, 4.0),
        magnitudes[1],
        0.000_000_001,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        magnitudes[4],
        0.000_000_001,
    );
}

test "FFT rejects non-finite input before mutation" {
    const Fft = Transform(f32, 4);
    var fft = Fft.init();
    var values = [4]Fft.Value{
        .{ .real = 1.0 },
        .{ .real = 2.0 },
        .{ .real = std.math.nan(f32) },
        .{ .real = 4.0 },
    };
    try std.testing.expectError(
        error.NonFiniteFftInput,
        fft.forward(&values),
    );
    try std.testing.expectEqual(@as(f32, 1.0), values[0].real);
    try std.testing.expectEqual(@as(f32, 2.0), values[1].real);
    try std.testing.expect(std.math.isNan(values[2].real));
    try std.testing.expectEqual(@as(f32, 4.0), values[3].real);

    var real_input: [4]f32 = @splat(1.0);
    real_input[1] = std.math.nan(f32);
    var magnitudes: [3]f32 = @splat(7.0);
    try std.testing.expectError(
        error.NonFiniteFftInput,
        fft.forwardMagnitudes(&real_input, &magnitudes),
    );
    try std.testing.expectEqual(@as(f32, 7.0), magnitudes[0]);
}
