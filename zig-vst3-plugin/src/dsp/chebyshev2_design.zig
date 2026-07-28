const std = @import("std");
const biquad = @import("biquad.zig");
const butterworth = @import("butterworth_design.zig");

pub const Config = struct {
    order: usize,
    sample_rate: f64,
    stopband_hz: f64,
    attenuation_db: f64,
};

pub const Specification = butterworth.Specification;

pub const SpecificationDesign = struct {
    cascade: butterworth.Cascade,
    stopband_hz: f64,
};

const Kind = enum { low_pass, high_pass };

const Complex = struct {
    real: f64,
    imaginary: f64,

    fn inverseScaled(self: Complex, scale: f64) Complex {
        const denominator =
            self.real * self.real + self.imaginary * self.imaginary;
        return .{
            .real = scale * self.real / denominator,
            .imaginary = -scale * self.imaginary / denominator,
        };
    }

    fn scaled(self: Complex, scale: f64) Complex {
        return .{
            .real = self.real * scale,
            .imaginary = self.imaginary * scale,
        };
    }
};

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Chebyshev Type II design supports f32 and f64 samples");

    return struct {
        pub fn lowPass(config: Config) !butterworth.Cascade {
            return design(config, .low_pass);
        }

        pub fn highPass(config: Config) !butterworth.Cascade {
            return design(config, .high_pass);
        }

        pub fn lowPassForSpecification(
            specification: Specification,
        ) !SpecificationDesign {
            return designSpecification(specification, .low_pass);
        }

        pub fn highPassForSpecification(
            specification: Specification,
        ) !SpecificationDesign {
            return designSpecification(specification, .high_pass);
        }

        fn design(config: Config, kind: Kind) !butterworth.Cascade {
            try validate(config);

            const order: f64 = @floatFromInt(config.order);
            const stopband_error =
                std.math.pow(f64, 10.0, config.attenuation_db / 10.0) -
                1.0;
            const mu = std.math.asinh(@sqrt(stopband_error)) / order;
            const warped =
                @tan(std.math.pi * config.stopband_hz / config.sample_rate);

            var result = butterworth.Cascade{
                .section_count = (config.order + 1) / 2,
                .order = config.order,
            };
            var section_index: usize = 0;
            if (config.order % 2 == 1) {
                const prototype_pole = -1.0 / std.math.sinh(mu);
                result.sections[0] = firstOrder(
                    prototype_pole,
                    warped,
                    kind,
                );
                section_index = 1;
            }

            for (0..config.order / 2) |pair_index| {
                const angle = std.math.pi *
                    @as(f64, @floatFromInt(2 * pair_index + 1)) /
                    (2.0 * order);
                const prototype_base = Complex{
                    .real = -std.math.sinh(mu) * @sin(angle),
                    .imaginary = std.math.cosh(mu) * @cos(angle),
                };
                const prototype_pole =
                    prototype_base.inverseScaled(1.0);
                const prototype_zero = Complex{
                    .real = 0.0,
                    .imaginary = 1.0 / @cos(angle),
                };
                result.sections[section_index + pair_index] = secondOrder(
                    prototype_pole,
                    prototype_zero,
                    warped,
                    kind,
                );
            }

            const reference_hz = switch (kind) {
                .low_pass => 0.0,
                .high_pass => config.sample_rate * 0.5,
            };
            const reference_gain =
                result.magnitude(config.sample_rate, reference_hz);
            if (!std.math.isFinite(reference_gain) or
                reference_gain <= std.math.floatEps(f64))
                return error.InvalidChebyshevTypeIIDesign;
            const inverse_gain = 1.0 / reference_gain;
            result.sections[0].b0 *= inverse_gain;
            result.sections[0].b1 *= inverse_gain;
            result.sections[0].b2 *= inverse_gain;

            for (result.active()) |section| {
                if (!section.valid())
                    return error.InvalidChebyshevTypeIIDesign;
            }
            return result;
        }

        fn designSpecification(
            specification: Specification,
            kind: Kind,
        ) !SpecificationDesign {
            try validateSpecification(specification, kind);
            const passband = @tan(
                std.math.pi *
                    specification.passband_hz /
                    specification.sample_rate,
            );
            const stopband = @tan(
                std.math.pi *
                    specification.stopband_hz /
                    specification.sample_rate,
            );
            const transition_ratio = switch (kind) {
                .low_pass => stopband / passband,
                .high_pass => passband / stopband,
            };
            const passband_error =
                std.math.pow(
                    f64,
                    10.0,
                    specification.maximum_passband_loss_db / 10.0,
                ) - 1.0;
            const stopband_error =
                std.math.pow(
                    f64,
                    10.0,
                    specification.minimum_stopband_attenuation_db / 10.0,
                ) - 1.0;
            const selectivity = std.math.acosh(
                @sqrt(stopband_error / passband_error),
            );
            const order_float =
                @ceil(selectivity / std.math.acosh(transition_ratio));
            if (!std.math.isFinite(order_float) or
                order_float < 1.0 or
                order_float >
                    @as(
                        f64,
                        @floatFromInt(butterworth.maximum_sections * 2),
                    ))
                return error.ChebyshevTypeIISpecificationExceedsMaximumOrder;
            const order: usize = @intFromFloat(order_float);

            const passband_scale =
                1.0 / std.math.cosh(selectivity / order_float);
            const critical_warped = switch (kind) {
                .low_pass => passband / passband_scale,
                .high_pass => passband * passband_scale,
            };
            const critical_hz = std.math.atan(critical_warped) *
                specification.sample_rate /
                std.math.pi;
            if (!std.math.isFinite(critical_hz))
                return error.InvalidChebyshevTypeIISpecification;

            return .{
                .cascade = try design(.{
                    .order = order,
                    .sample_rate = specification.sample_rate,
                    .stopband_hz = critical_hz,
                    .attenuation_db = specification.minimum_stopband_attenuation_db,
                }, kind),
                .stopband_hz = critical_hz,
            };
        }

        fn firstOrder(
            prototype_pole: f64,
            warped: f64,
            kind: Kind,
        ) biquad.Coefficients {
            const analog_pole = switch (kind) {
                .low_pass => warped * prototype_pole,
                .high_pass => warped / prototype_pole,
            };
            const pole = (1.0 - analog_pole) / (1.0 + analog_pole);
            const zero: f64 = switch (kind) {
                .low_pass => -1.0,
                .high_pass => 1.0,
            };
            return .{
                .b0 = 1.0,
                .b1 = -zero,
                .b2 = 0.0,
                .a1 = -pole,
                .a2 = 0.0,
            };
        }

        fn secondOrder(
            prototype_pole: Complex,
            prototype_zero: Complex,
            warped: f64,
            kind: Kind,
        ) biquad.Coefficients {
            const analog_pole = switch (kind) {
                .low_pass => prototype_pole.scaled(warped),
                .high_pass => prototype_pole.inverseScaled(warped),
            };
            const analog_zero = switch (kind) {
                .low_pass => prototype_zero.scaled(warped),
                .high_pass => prototype_zero.inverseScaled(warped),
            };
            const pole = bilinearRoot(analog_pole);
            const zero = bilinearRoot(analog_zero);
            return .{
                .b0 = 1.0,
                .b1 = -2.0 * zero.real,
                .b2 = zero.real * zero.real +
                    zero.imaginary * zero.imaginary,
                .a1 = -2.0 * pole.real,
                .a2 = pole.real * pole.real +
                    pole.imaginary * pole.imaginary,
            };
        }

        fn bilinearRoot(root: Complex) Complex {
            const denominator =
                (1.0 + root.real) * (1.0 + root.real) +
                root.imaginary * root.imaginary;
            return .{
                .real = (1.0 -
                    root.real * root.real -
                    root.imaginary * root.imaginary) / denominator,
                .imaginary = -2.0 * root.imaginary / denominator,
            };
        }

        fn validate(config: Config) !void {
            if (config.order == 0 or
                config.order > butterworth.maximum_sections * 2 or
                !std.math.isFinite(config.sample_rate) or
                config.sample_rate < 1_000.0 or
                config.sample_rate > 768_000.0 or
                !std.math.isFinite(config.stopband_hz) or
                config.stopband_hz < 1.0 or
                config.stopband_hz >= config.sample_rate * 0.49 or
                !std.math.isFinite(config.attenuation_db) or
                config.attenuation_db < 3.0 or
                config.attenuation_db > 300.0)
                return error.InvalidChebyshevTypeIIDesign;
        }

        fn validateSpecification(
            specification: Specification,
            kind: Kind,
        ) !void {
            if (!std.math.isFinite(specification.sample_rate) or
                specification.sample_rate < 1_000.0 or
                specification.sample_rate > 768_000.0 or
                !std.math.isFinite(specification.passband_hz) or
                !std.math.isFinite(specification.stopband_hz) or
                specification.passband_hz < 1.0 or
                specification.stopband_hz < 1.0 or
                specification.passband_hz >=
                    specification.sample_rate * 0.49 or
                specification.stopband_hz >=
                    specification.sample_rate * 0.49 or
                !std.math.isFinite(
                    specification.maximum_passband_loss_db,
                ) or
                specification.maximum_passband_loss_db < 0.01 or
                specification.maximum_passband_loss_db > 12.0 or
                !std.math.isFinite(
                    specification.minimum_stopband_attenuation_db,
                ) or
                specification.minimum_stopband_attenuation_db < 3.0 or
                specification.minimum_stopband_attenuation_db <=
                    specification.maximum_passband_loss_db or
                specification.minimum_stopband_attenuation_db > 300.0)
                return error.InvalidChebyshevTypeIISpecification;
            const frequencies_valid = switch (kind) {
                .low_pass => specification.passband_hz <
                    specification.stopband_hz,
                .high_pass => specification.passband_hz >
                    specification.stopband_hz,
            };
            if (!frequencies_valid)
                return error.InvalidChebyshevTypeIISpecification;
        }
    };
}

test "Chebyshev Type II low-pass reaches its bounded stopband" {
    const FilterDesign = Designer(f64);
    inline for (.{ 3, 4 }) |order| {
        const cascade = try FilterDesign.lowPass(.{
            .order = order,
            .sample_rate = 48_000.0,
            .stopband_hz = 4_000.0,
            .attenuation_db = 60.0,
        });
        try std.testing.expect(cascade.valid());
        try std.testing.expectApproxEqAbs(
            1.0,
            cascade.magnitude(48_000.0, 0.0),
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            0.001,
            cascade.magnitude(48_000.0, 4_000.0),
            0.000_001,
        );
    }
}

test "Chebyshev Type II high-pass reaches its bounded stopband" {
    const FilterDesign = Designer(f32);
    inline for (.{ 1, 7 }) |order| {
        const cascade = try FilterDesign.highPass(.{
            .order = order,
            .sample_rate = 48_000.0,
            .stopband_hz = 2_000.0,
            .attenuation_db = 50.0,
        });
        try std.testing.expect(cascade.valid());
        try std.testing.expectApproxEqAbs(
            1.0,
            cascade.magnitude(48_000.0, 24_000.0),
            0.000_001,
        );
        try std.testing.expectApproxEqAbs(
            std.math.pow(f64, 10.0, -2.5),
            cascade.magnitude(48_000.0, 2_000.0),
            0.000_001,
        );
    }
}

test "Chebyshev Type II response matches SciPy 1.17" {
    const FilterDesign = Designer(f64);
    const low_pass = try FilterDesign.lowPass(.{
        .order = 5,
        .sample_rate = 48_000.0,
        .stopband_hz = 6_000.0,
        .attenuation_db = 60.0,
    });
    try expectReferenceResponse(
        low_pass,
        48_000.0,
        &.{ 0.0, 1_000.0, 3_000.0, 6_000.0, 9_000.0, 12_000.0, 20_000.0, 24_000.0 },
        &.{ 1.0, 0.999979525602483, 0.4151471794314627, 0.0010000000000000046, 0.0002002131907820497, 0.0008448046366081166, 0.0005278667140296997, 1.2681639173912003e-19 },
    );

    const high_pass = try FilterDesign.highPass(.{
        .order = 6,
        .sample_rate = 48_000.0,
        .stopband_hz = 3_000.0,
        .attenuation_db = 72.0,
    });
    try expectReferenceResponse(
        high_pass,
        48_000.0,
        &.{ 0.0, 500.0, 1_500.0, 3_000.0, 6_000.0, 12_000.0, 20_000.0, 24_000.0 },
        &.{ 0.000251188643150955, 0.00013740832021095839, 0.00025104728938029984, 0.0002511886431509587, 0.4088938879543825, 0.9999665094855582, 0.9999999999958988, 1.0 },
    );
}

test "Chebyshev Type II specification design meets both edges" {
    const FilterDesign = Designer(f64);
    const low_specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 60.0,
    };
    const low =
        try FilterDesign.lowPassForSpecification(low_specification);
    try expectSpecification(low.cascade, low_specification);
    try std.testing.expect(
        low.stopband_hz <= low_specification.stopband_hz,
    );

    const high_specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 4_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 0.5,
        .minimum_stopband_attenuation_db = 50.0,
    };
    const high =
        try FilterDesign.highPassForSpecification(high_specification);
    try expectSpecification(high.cascade, high_specification);
    try std.testing.expect(
        high.stopband_hz >= high_specification.stopband_hz,
    );
}

test "Chebyshev Type II rejects invalid and unbounded requests" {
    const FilterDesign = Designer(f64);
    try std.testing.expectError(
        error.InvalidChebyshevTypeIIDesign,
        FilterDesign.lowPass(.{
            .order = 0,
            .sample_rate = 48_000.0,
            .stopband_hz = 2_000.0,
            .attenuation_db = 60.0,
        }),
    );
    try std.testing.expectError(
        error.InvalidChebyshevTypeIISpecification,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 2_000.0,
            .stopband_hz = 1_000.0,
        }),
    );
    try std.testing.expectError(
        error.ChebyshevTypeIISpecificationExceedsMaximumOrder,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 1_010.0,
            .maximum_passband_loss_db = 0.01,
            .minimum_stopband_attenuation_db = 200.0,
        }),
    );
}

fn expectSpecification(
    cascade: butterworth.Cascade,
    specification: Specification,
) !void {
    const passband_floor = std.math.pow(
        f64,
        10.0,
        -specification.maximum_passband_loss_db / 20.0,
    );
    const stopband_ceiling = std.math.pow(
        f64,
        10.0,
        -specification.minimum_stopband_attenuation_db / 20.0,
    );
    try std.testing.expect(
        cascade.magnitude(
            specification.sample_rate,
            specification.passband_hz,
        ) + 0.000_001 >= passband_floor,
    );
    try std.testing.expect(
        cascade.magnitude(
            specification.sample_rate,
            specification.stopband_hz,
        ) <= stopband_ceiling + 0.000_001,
    );
}

fn expectReferenceResponse(
    cascade: butterworth.Cascade,
    sample_rate: f64,
    frequencies: []const f64,
    magnitudes: []const f64,
) !void {
    try std.testing.expectEqual(frequencies.len, magnitudes.len);
    for (frequencies, magnitudes) |frequency, expected| {
        try std.testing.expectApproxEqRel(
            expected,
            cascade.magnitude(sample_rate, frequency),
            1.0e-11,
        );
    }
}
