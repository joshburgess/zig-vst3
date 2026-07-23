const std = @import("std");

pub const Kind = enum {
    low_pass,
    high_pass,
    band_pass,
    notch,
    low_shelf,
    bell,
    high_shelf,
};

pub const Config = struct {
    kind: Kind,
    sample_rate: f64,
    frequency_hz: f64,
    gain_db: f64,
    q: f64,

    pub fn coefficients(self: Config) error{InvalidConfig}!Coefficients {
        if (!std.math.isFinite(self.sample_rate) or self.sample_rate < 1_000.0 or
            !std.math.isFinite(self.frequency_hz) or !std.math.isFinite(self.gain_db) or
            !std.math.isFinite(self.q)) return error.InvalidConfig;

        const frequency = std.math.clamp(self.frequency_hz, 10.0, self.sample_rate * 0.49);
        const q = std.math.clamp(self.q, 0.1, 18.0);
        const amplitude = std.math.pow(f64, 10.0, self.gain_db / 40.0);
        const omega = std.math.tau * frequency / self.sample_rate;
        const cosine = @cos(omega);
        const alpha = @sin(omega) / (2.0 * q);
        const root_amplitude = @sqrt(amplitude);

        const raw = switch (self.kind) {
            .low_pass => RawCoefficients{
                .b0 = (1.0 - cosine) * 0.5,
                .b1 = 1.0 - cosine,
                .b2 = (1.0 - cosine) * 0.5,
                .a0 = 1.0 + alpha,
                .a1 = -2.0 * cosine,
                .a2 = 1.0 - alpha,
            },
            .high_pass => RawCoefficients{
                .b0 = (1.0 + cosine) * 0.5,
                .b1 = -(1.0 + cosine),
                .b2 = (1.0 + cosine) * 0.5,
                .a0 = 1.0 + alpha,
                .a1 = -2.0 * cosine,
                .a2 = 1.0 - alpha,
            },
            .band_pass => RawCoefficients{
                .b0 = alpha,
                .b1 = 0.0,
                .b2 = -alpha,
                .a0 = 1.0 + alpha,
                .a1 = -2.0 * cosine,
                .a2 = 1.0 - alpha,
            },
            .notch => RawCoefficients{
                .b0 = 1.0,
                .b1 = -2.0 * cosine,
                .b2 = 1.0,
                .a0 = 1.0 + alpha,
                .a1 = -2.0 * cosine,
                .a2 = 1.0 - alpha,
            },
            .bell => RawCoefficients{
                .b0 = 1.0 + alpha * amplitude,
                .b1 = -2.0 * cosine,
                .b2 = 1.0 - alpha * amplitude,
                .a0 = 1.0 + alpha / amplitude,
                .a1 = -2.0 * cosine,
                .a2 = 1.0 - alpha / amplitude,
            },
            .low_shelf => RawCoefficients{
                .b0 = amplitude * ((amplitude + 1.0) - (amplitude - 1.0) * cosine + 2.0 * root_amplitude * alpha),
                .b1 = 2.0 * amplitude * ((amplitude - 1.0) - (amplitude + 1.0) * cosine),
                .b2 = amplitude * ((amplitude + 1.0) - (amplitude - 1.0) * cosine - 2.0 * root_amplitude * alpha),
                .a0 = (amplitude + 1.0) + (amplitude - 1.0) * cosine + 2.0 * root_amplitude * alpha,
                .a1 = -2.0 * ((amplitude - 1.0) + (amplitude + 1.0) * cosine),
                .a2 = (amplitude + 1.0) + (amplitude - 1.0) * cosine - 2.0 * root_amplitude * alpha,
            },
            .high_shelf => RawCoefficients{
                .b0 = amplitude * ((amplitude + 1.0) + (amplitude - 1.0) * cosine + 2.0 * root_amplitude * alpha),
                .b1 = -2.0 * amplitude * ((amplitude - 1.0) + (amplitude + 1.0) * cosine),
                .b2 = amplitude * ((amplitude + 1.0) + (amplitude - 1.0) * cosine - 2.0 * root_amplitude * alpha),
                .a0 = (amplitude + 1.0) - (amplitude - 1.0) * cosine + 2.0 * root_amplitude * alpha,
                .a1 = 2.0 * ((amplitude - 1.0) - (amplitude + 1.0) * cosine),
                .a2 = (amplitude + 1.0) - (amplitude - 1.0) * cosine - 2.0 * root_amplitude * alpha,
            },
        };
        return raw.normalized();
    }
};

const RawCoefficients = struct {
    b0: f64,
    b1: f64,
    b2: f64,
    a0: f64,
    a1: f64,
    a2: f64,

    fn normalized(self: RawCoefficients) error{InvalidConfig}!Coefficients {
        if (!std.math.isFinite(self.a0) or @abs(self.a0) <= std.math.floatEps(f64)) {
            return error.InvalidConfig;
        }
        const inverse = 1.0 / self.a0;
        const result = Coefficients{
            .b0 = self.b0 * inverse,
            .b1 = self.b1 * inverse,
            .b2 = self.b2 * inverse,
            .a1 = self.a1 * inverse,
            .a2 = self.a2 * inverse,
        };
        if (!result.valid()) return error.InvalidConfig;
        return result;
    }
};

pub const Coefficients = struct {
    b0: f64 = 1.0,
    b1: f64 = 0.0,
    b2: f64 = 0.0,
    a1: f64 = 0.0,
    a2: f64 = 0.0,

    pub fn identity() Coefficients {
        return .{};
    }

    pub fn response(self: Coefficients, sample_rate: f64, frequency_hz: f64) ComplexResponse {
        if (!self.valid() or !std.math.isFinite(sample_rate) or sample_rate <= 0.0 or
            !std.math.isFinite(frequency_hz)) return .{};
        const frequency = std.math.clamp(frequency_hz, 0.0, sample_rate * 0.5);
        const omega = std.math.tau * frequency / sample_rate;
        const cosine = @cos(omega);
        const sine = @sin(omega);
        const cosine2 = @cos(2.0 * omega);
        const sine2 = @sin(2.0 * omega);
        const numerator_real = self.b0 + self.b1 * cosine + self.b2 * cosine2;
        const numerator_imaginary = -self.b1 * sine - self.b2 * sine2;
        const denominator_real = 1.0 + self.a1 * cosine + self.a2 * cosine2;
        const denominator_imaginary = -self.a1 * sine - self.a2 * sine2;
        const numerator = numerator_real * numerator_real + numerator_imaginary * numerator_imaginary;
        const denominator = denominator_real * denominator_real + denominator_imaginary * denominator_imaginary;
        if (denominator <= std.math.floatEps(f64) or
            !std.math.isFinite(numerator) or !std.math.isFinite(denominator)) return .{};
        const result = ComplexResponse{
            .real = (numerator_real * denominator_real + numerator_imaginary * denominator_imaginary) / denominator,
            .imaginary = (numerator_imaginary * denominator_real - numerator_real * denominator_imaginary) / denominator,
        };
        return if (result.valid()) result else .{};
    }

    pub fn magnitude(self: Coefficients, sample_rate: f64, frequency_hz: f64) f64 {
        return self.response(sample_rate, frequency_hz).magnitude();
    }

    pub fn magnitudeDb(self: Coefficients, sample_rate: f64, frequency_hz: f64) f64 {
        const linear = self.magnitude(sample_rate, frequency_hz);
        if (linear <= std.math.floatEps(f64)) return -160.0;
        return 20.0 * std.math.log10(linear);
    }

    pub fn valid(self: Coefficients) bool {
        return std.math.isFinite(self.b0) and std.math.isFinite(self.b1) and
            std.math.isFinite(self.b2) and std.math.isFinite(self.a1) and
            std.math.isFinite(self.a2);
    }

    fn addScaled(self: *Coefficients, step: Coefficients) void {
        self.b0 += step.b0;
        self.b1 += step.b1;
        self.b2 += step.b2;
        self.a1 += step.a1;
        self.a2 += step.a2;
    }

    fn difference(target: Coefficients, current: Coefficients, divisor: f64) Coefficients {
        return .{
            .b0 = (target.b0 - current.b0) / divisor,
            .b1 = (target.b1 - current.b1) / divisor,
            .b2 = (target.b2 - current.b2) / divisor,
            .a1 = (target.a1 - current.a1) / divisor,
            .a2 = (target.a2 - current.a2) / divisor,
        };
    }
};

pub const ComplexResponse = struct {
    real: f64 = 0.0,
    imaginary: f64 = 0.0,

    pub fn magnitude(self: ComplexResponse) f64 {
        if (!self.valid()) return 0.0;
        const scale = @max(@abs(self.real), @abs(self.imaginary));
        if (scale == 0.0) return 0.0;
        const real = self.real / scale;
        const imaginary = self.imaginary / scale;
        const result = scale * @sqrt(real * real + imaginary * imaginary);
        return if (std.math.isFinite(result)) result else 0.0;
    }

    pub fn valid(self: ComplexResponse) bool {
        return std.math.isFinite(self.real) and std.math.isFinite(self.imaginary);
    }
};

pub fn SmoothedBiquad(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64) @compileError("SmoothedBiquad supports f32 and f64 samples");
    return struct {
        const Self = @This();

        current: Coefficients = .{},
        target: Coefficients = .{},
        step: Coefficients = .{ .b0 = 0.0 },
        remaining: usize = 0,
        z1: Sample = 0.0,
        z2: Sample = 0.0,

        pub fn reset(self: *Self) void {
            self.z1 = 0.0;
            self.z2 = 0.0;
        }

        pub fn setImmediate(self: *Self, coefficients: Coefficients) void {
            const accepted = if (coefficients.valid()) coefficients else Coefficients.identity();
            self.current = accepted;
            self.target = accepted;
            self.step = .{ .b0 = 0.0 };
            self.remaining = 0;
        }

        pub fn setTarget(self: *Self, coefficients: Coefficients, transition_samples: usize) void {
            if (!coefficients.valid()) {
                self.setImmediate(.{});
                self.reset();
                return;
            }
            if (!self.current.valid() or !self.target.valid() or !self.step.valid()) {
                self.setImmediate(.{});
                self.reset();
            }
            if (std.meta.eql(coefficients, self.target)) return;
            self.target = coefficients;
            if (transition_samples == 0) {
                self.setImmediate(coefficients);
                return;
            }
            self.step = Coefficients.difference(coefficients, self.current, @floatFromInt(transition_samples));
            self.remaining = transition_samples;
        }

        pub fn process(self: *Self, input: Sample) Sample {
            if (!std.math.isFinite(input)) {
                self.setImmediate(.{});
                self.reset();
                return 0.0;
            }
            if (self.remaining > 0) {
                self.current.addScaled(self.step);
                self.remaining -= 1;
                if (self.remaining == 0) self.current = self.target;
            }
            const b0: Sample = @floatCast(self.current.b0);
            const b1: Sample = @floatCast(self.current.b1);
            const b2: Sample = @floatCast(self.current.b2);
            const a1: Sample = @floatCast(self.current.a1);
            const a2: Sample = @floatCast(self.current.a2);
            const output = b0 * input + self.z1;
            self.z1 = b1 * input - a1 * output + self.z2;
            self.z2 = b2 * input - a2 * output;
            if (!std.math.isFinite(output) or !std.math.isFinite(self.z1) or !std.math.isFinite(self.z2)) {
                self.setImmediate(.{});
                self.reset();
                return 0.0;
            }
            return output;
        }
    };
}

test "bell response reaches its center gain" {
    const coefficients = try (Config{
        .kind = .bell,
        .sample_rate = 48_000.0,
        .frequency_hz = 1_000.0,
        .gain_db = 6.0,
        .q = 1.0,
    }).coefficients();
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), coefficients.magnitudeDb(48_000.0, 1_000.0), 0.0001);
}

test "shelves approach their requested gain" {
    const low = try (Config{ .kind = .low_shelf, .sample_rate = 48_000.0, .frequency_hz = 200.0, .gain_db = 9.0, .q = 0.707 }).coefficients();
    const high = try (Config{ .kind = .high_shelf, .sample_rate = 48_000.0, .frequency_hz = 6_000.0, .gain_db = -9.0, .q = 0.707 }).coefficients();
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), low.magnitudeDb(48_000.0, 10.0), 0.08);
    try std.testing.expectApproxEqAbs(@as(f64, -9.0), high.magnitudeDb(48_000.0, 23_000.0), 0.08);
}

test "configuration clamps finite frequency and q" {
    const clamped = try (Config{ .kind = .bell, .sample_rate = 48_000.0, .frequency_hz = 1.0e9, .gain_db = 3.0, .q = 0.001 }).coefficients();
    try std.testing.expect(std.math.isFinite(clamped.magnitudeDb(48_000.0, 23_000.0)));
    try std.testing.expectError(error.InvalidConfig, (Config{ .kind = .bell, .sample_rate = 0.0, .frequency_hz = 1_000.0, .gain_db = 0.0, .q = 1.0 }).coefficients());
    try std.testing.expectError(error.InvalidConfig, (Config{ .kind = .bell, .sample_rate = 48_000.0, .frequency_hz = std.math.nan(f64), .gain_db = 0.0, .q = 1.0 }).coefficients());
}

test "pass filters meet their cutoff response" {
    inline for (.{ Kind.low_pass, Kind.high_pass }) |kind| {
        const coefficients = try (Config{ .kind = kind, .sample_rate = 48_000.0, .frequency_hz = 1_000.0, .gain_db = 0.0, .q = 1.0 / @sqrt(2.0) }).coefficients();
        try std.testing.expectApproxEqAbs(@as(f64, -3.0103), coefficients.magnitudeDb(48_000.0, 1_000.0), 0.001);
    }

    const low = try (Config{ .kind = .low_pass, .sample_rate = 48_000.0, .frequency_hz = 1_000.0, .gain_db = 0.0, .q = 0.707 }).coefficients();
    const high = try (Config{ .kind = .high_pass, .sample_rate = 48_000.0, .frequency_hz = 1_000.0, .gain_db = 0.0, .q = 0.707 }).coefficients();
    try std.testing.expect(low.magnitudeDb(48_000.0, 100.0) > -0.01);
    try std.testing.expect(low.magnitudeDb(48_000.0, 10_000.0) < -35.0);
    try std.testing.expect(high.magnitudeDb(48_000.0, 100.0) < -35.0);
    try std.testing.expect(high.magnitudeDb(48_000.0, 10_000.0) > -0.01);
}

test "band pass peaks and notch rejects at center frequency" {
    const band = try (Config{ .kind = .band_pass, .sample_rate = 48_000.0, .frequency_hz = 2_000.0, .gain_db = 0.0, .q = 2.0 }).coefficients();
    const notch = try (Config{ .kind = .notch, .sample_rate = 48_000.0, .frequency_hz = 2_000.0, .gain_db = 0.0, .q = 2.0 }).coefficients();
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), band.magnitudeDb(48_000.0, 2_000.0), 0.0001);
    try std.testing.expect(notch.magnitudeDb(48_000.0, 2_000.0) < -120.0);
    try std.testing.expect(notch.magnitudeDb(48_000.0, 200.0) > -0.1);
}

test "complex response magnitude matches direct evaluation" {
    const coefficients = try (Config{ .kind = .notch, .sample_rate = 48_000.0, .frequency_hz = 2_000.0, .gain_db = 0.0, .q = 4.0 }).coefficients();
    inline for (.{ 100.0, 1_000.0, 2_000.0, 8_000.0 }) |frequency| {
        try std.testing.expectApproxEqAbs(coefficients.magnitude(48_000.0, frequency), coefficients.response(48_000.0, frequency).magnitude(), 0.0000001);
    }
}

test "biquad response contains extreme public values" {
    const extreme = Coefficients{
        .b0 = std.math.floatMax(f64),
        .b1 = std.math.floatMax(f64),
        .b2 = std.math.floatMax(f64),
        .a1 = std.math.floatMax(f64),
        .a2 = std.math.floatMax(f64),
    };
    const response = extreme.response(48_000.0, 1_000.0);
    try std.testing.expect(response.valid());
    try std.testing.expect(std.math.isFinite(response.magnitude()));
    try std.testing.expectEqual(@as(f64, 0.0), (ComplexResponse{
        .real = std.math.floatMax(f64),
        .imaginary = std.math.floatMax(f64),
    }).magnitude());
    try std.testing.expectEqual(@as(f64, 0.0), (ComplexResponse{
        .real = std.math.nan(f64),
        .imaginary = 1.0,
    }).magnitude());
}

test "unity filters preserve f32 and f64 samples" {
    inline for (.{ f32, f64 }) |Sample| {
        inline for (.{ Kind.low_shelf, Kind.bell, Kind.high_shelf }) |kind| {
            const coefficients = try (Config{ .kind = kind, .sample_rate = 48_000.0, .frequency_hz = 1_000.0, .gain_db = 0.0, .q = 1.0 }).coefficients();
            var filter = SmoothedBiquad(Sample){};
            filter.setImmediate(coefficients);
            const values = [_]Sample{ 0.25, -0.5, 0.75, -0.125 };
            for (values) |value| try std.testing.expectApproxEqAbs(value, filter.process(value), @as(Sample, 0.00001));
        }
    }
}

test "coefficient transition reaches its target in bounded samples" {
    const target = try (Config{ .kind = .bell, .sample_rate = 48_000.0, .frequency_hz = 2_000.0, .gain_db = 12.0, .q = 2.0 }).coefficients();
    var filter = SmoothedBiquad(f64){};
    filter.setTarget(target, 8);
    for (0..8) |_| _ = filter.process(0.0);
    try std.testing.expectEqual(@as(usize, 0), filter.remaining);
    try std.testing.expectApproxEqAbs(target.b0, filter.current.b0, 0.0000001);
    try std.testing.expectApproxEqAbs(target.a2, filter.current.a2, 0.0000001);
}

test "smoothed biquad contains malformed public state" {
    var filter = SmoothedBiquad(f64){};
    filter.setImmediate(.{ .b0 = std.math.nan(f64) });
    try std.testing.expectEqual(@as(f64, 0.25), filter.process(0.25));

    filter.current.a1 = std.math.inf(f64);
    filter.z1 = std.math.nan(f64);
    try std.testing.expectEqual(@as(f64, 0.0), filter.process(0.5));
    try std.testing.expect(filter.current.valid());
    try std.testing.expectEqual(@as(f64, 0.0), filter.z1);
    try std.testing.expectEqual(@as(f64, 0.0), filter.z2);

    filter.setTarget(.{ .a2 = std.math.nan(f64) }, 64);
    try std.testing.expectEqual(@as(usize, 0), filter.remaining);
    try std.testing.expectEqual(@as(f64, 0.0), filter.process(std.math.inf(f64)));
    try std.testing.expectEqual(@as(f64, 0.75), filter.process(0.75));
}
