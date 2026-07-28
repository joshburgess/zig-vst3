const std = @import("std");
const biquad = @import("biquad.zig");
const butterworth = @import("butterworth_design.zig");
const special = @import("special_functions.zig");

pub const Config = struct {
    order: usize,
    sample_rate: f64,
    frequency_hz: f64,
    ripple_db: f64,
    attenuation_db: f64,
};

pub const Specification = butterworth.Specification;
const Kind = enum { low_pass, high_pass };

const Complex = struct {
    real: f64,
    imaginary: f64,

    fn scaled(self: Complex, scale: f64) Complex {
        return .{
            .real = self.real * scale,
            .imaginary = self.imaginary * scale,
        };
    }

    fn inverseScaled(self: Complex, scale: f64) Complex {
        const denominator =
            self.real * self.real + self.imaginary * self.imaginary;
        return .{
            .real = scale * self.real / denominator,
            .imaginary = -scale * self.imaginary / denominator,
        };
    }
};

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("elliptic design supports f32 and f64 samples");

    return struct {
        pub fn lowPass(config: Config) !butterworth.Cascade {
            return design(config, .low_pass);
        }

        pub fn highPass(config: Config) !butterworth.Cascade {
            return design(config, .high_pass);
        }

        pub fn lowPassForSpecification(
            specification: Specification,
        ) !butterworth.Cascade {
            return designSpecification(specification, .low_pass);
        }

        pub fn highPassForSpecification(
            specification: Specification,
        ) !butterworth.Cascade {
            return designSpecification(specification, .high_pass);
        }

        fn design(config: Config, kind: Kind) !butterworth.Cascade {
            try validate(config);
            const passband_error =
                std.math.pow(f64, 10.0, config.ripple_db / 10.0) - 1.0;
            const stopband_error =
                std.math.pow(f64, 10.0, config.attenuation_db / 10.0) -
                1.0;
            const first_parameter = passband_error / stopband_error;
            if (first_parameter <= 0.0 or first_parameter >= 1.0)
                return error.InvalidEllipticDesign;
            const parameter =
                try solveDegreeParameter(config.order, first_parameter);
            const quarter_period =
                (try special.ellipticIntegralK(@sqrt(parameter))).k;
            const first_integrals =
                try special.ellipticIntegralK(@sqrt(first_parameter));
            const inverse_sc = try inverseJacobiSc(
                1.0 / @sqrt(passband_error),
                1.0 - first_parameter,
            );
            const order: f64 = @floatFromInt(config.order);
            const v0 =
                quarter_period * inverse_sc / (order * first_integrals.k);
            const v = try special.jacobiElliptic(v0, 1.0 - parameter);
            const warped =
                @tan(std.math.pi * config.frequency_hz / config.sample_rate);

            var result = butterworth.Cascade{
                .section_count = (config.order + 1) / 2,
                .order = config.order,
            };
            const first_j: usize = 1 - config.order % 2;
            var section_index: usize = 0;
            var j = first_j;
            while (j < config.order) : (j += 2) {
                const argument =
                    @as(f64, @floatFromInt(j)) *
                    quarter_period /
                    order;
                const values =
                    try special.jacobiElliptic(argument, parameter);
                const denominator =
                    1.0 - (values.dn * v.sn) * (values.dn * v.sn);
                if (!std.math.isFinite(denominator) or
                    denominator <= std.math.floatEps(f64))
                    return error.InvalidEllipticDesign;
                const pole = Complex{
                    .real = -(values.cn *
                        values.dn *
                        v.sn *
                        v.cn) / denominator,
                    .imaginary = -(values.sn * v.dn) / denominator,
                };
                if (j == 0) {
                    result.sections[section_index] =
                        firstOrder(pole.real, warped, kind);
                } else {
                    const zero = Complex{
                        .real = 0.0,
                        .imaginary = 1.0 / (@sqrt(parameter) * values.sn),
                    };
                    result.sections[section_index] =
                        secondOrder(pole, zero, warped, kind);
                }
                section_index += 1;
            }

            const reference_hz = switch (kind) {
                .low_pass => 0.0,
                .high_pass => config.sample_rate * 0.5,
            };
            const current_gain =
                result.magnitude(config.sample_rate, reference_hz);
            const target_gain = if (config.order % 2 == 0)
                std.math.pow(f64, 10.0, -config.ripple_db / 20.0)
            else
                1.0;
            if (!std.math.isFinite(current_gain) or
                current_gain <= std.math.floatEps(f64))
                return error.InvalidEllipticDesign;
            const scale = target_gain / current_gain;
            result.sections[0].b0 *= scale;
            result.sections[0].b1 *= scale;
            result.sections[0].b2 *= scale;
            for (result.active()) |section| {
                if (!section.valid()) return error.InvalidEllipticDesign;
            }
            return result;
        }

        fn designSpecification(
            specification: Specification,
            kind: Kind,
        ) !butterworth.Cascade {
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
            const selectivity =
                try special.ellipticIntegralK(1.0 / transition_ratio);
            const ripple = try special.ellipticIntegralK(
                @sqrt(passband_error / stopband_error),
            );
            const order_float = @ceil(
                selectivity.k * ripple.complementary /
                    (selectivity.complementary * ripple.k),
            );
            if (!std.math.isFinite(order_float) or
                order_float < 1.0 or
                order_float >
                    @as(
                        f64,
                        @floatFromInt(butterworth.maximum_sections * 2),
                    ))
                return error.EllipticSpecificationExceedsMaximumOrder;
            return design(.{
                .order = @intFromFloat(order_float),
                .sample_rate = specification.sample_rate,
                .frequency_hz = specification.passband_hz,
                .ripple_db = specification.maximum_passband_loss_db,
                .attenuation_db = specification.minimum_stopband_attenuation_db,
            }, kind);
        }

        fn solveDegreeParameter(
            order: usize,
            first_parameter: f64,
        ) !f64 {
            const integrals =
                try special.ellipticIntegralK(@sqrt(first_parameter));
            const nome =
                @exp(-std.math.pi * integrals.complementary / integrals.k);
            const root_nome = std.math.pow(
                f64,
                nome,
                1.0 / @as(f64, @floatFromInt(order)),
            );
            var numerator: f64 = 0.0;
            for (0..8) |index| {
                numerator += std.math.pow(
                    f64,
                    root_nome,
                    @as(f64, @floatFromInt(index * (index + 1))),
                );
            }
            var denominator: f64 = 1.0;
            for (1..9) |index| {
                denominator += 2.0 * std.math.pow(
                    f64,
                    root_nome,
                    @as(f64, @floatFromInt(index * index)),
                );
            }
            const ratio = numerator / denominator;
            const result = 16.0 * root_nome * ratio * ratio * ratio * ratio;
            if (!std.math.isFinite(result) or result <= 0.0 or result >= 1.0)
                return error.InvalidEllipticDesign;
            return result;
        }

        fn inverseJacobiSc(value: f64, parameter: f64) !f64 {
            if (!std.math.isFinite(value) or value < 0.0 or
                !std.math.isFinite(parameter) or
                parameter < 0.0 or parameter >= 1.0)
                return error.InvalidEllipticDesign;
            if (value == 0.0) return 0.0;
            const quarter_period =
                (try special.ellipticIntegralK(@sqrt(parameter))).k;
            var lower: f64 = 0.0;
            var upper = quarter_period * (1.0 - 1.0e-8);
            const upper_values =
                try special.jacobiElliptic(upper, parameter);
            if (upper_values.cn <= 0.0 or
                upper_values.sn / upper_values.cn < value)
                return error.InvalidEllipticDesign;
            for (0..96) |_| {
                const middle = (lower + upper) * 0.5;
                const values =
                    try special.jacobiElliptic(middle, parameter);
                if (values.cn <= 0.0 or values.sn / values.cn >= value)
                    upper = middle
                else
                    lower = middle;
            }
            return (lower + upper) * 0.5;
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
                !std.math.isFinite(config.frequency_hz) or
                config.frequency_hz < 1.0 or
                config.frequency_hz >= config.sample_rate * 0.49 or
                !std.math.isFinite(config.ripple_db) or
                config.ripple_db < 0.01 or
                config.ripple_db > 12.0 or
                !std.math.isFinite(config.attenuation_db) or
                config.attenuation_db <= config.ripple_db or
                config.attenuation_db > 300.0)
                return error.InvalidEllipticDesign;
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
                specification.minimum_stopband_attenuation_db <=
                    specification.maximum_passband_loss_db or
                specification.minimum_stopband_attenuation_db > 300.0)
                return error.InvalidEllipticSpecification;
            const frequencies_valid = switch (kind) {
                .low_pass => specification.passband_hz <
                    specification.stopband_hz,
                .high_pass => specification.passband_hz >
                    specification.stopband_hz,
            };
            if (!frequencies_valid)
                return error.InvalidEllipticSpecification;
        }
    };
}

test "elliptic low-pass meets fixed-order passband contract" {
    const FilterDesign = Designer(f64);
    inline for (.{ 3, 4 }) |order| {
        const cascade = try FilterDesign.lowPass(.{
            .order = order,
            .sample_rate = 48_000.0,
            .frequency_hz = 2_000.0,
            .ripple_db = 1.0,
            .attenuation_db = 60.0,
        });
        const ripple_gain = std.math.pow(f64, 10.0, -1.0 / 20.0);
        try std.testing.expectApproxEqAbs(
            ripple_gain,
            cascade.magnitude(48_000.0, 2_000.0),
            0.000_001,
        );
        const reference = if (order % 2 == 0) ripple_gain else 1.0;
        try std.testing.expectApproxEqAbs(
            reference,
            cascade.magnitude(48_000.0, 0.0),
            0.000_001,
        );
    }
}

test "elliptic response matches SciPy 1.17" {
    const FilterDesign = Designer(f64);
    const low_pass = try FilterDesign.lowPass(.{
        .order = 6,
        .sample_rate = 8_000.0,
        .frequency_hz = 1_000.0,
        .ripple_db = 0.087,
        .attenuation_db = 90.0,
    });
    try expectReferenceResponse(
        low_pass,
        8_000.0,
        &.{ 0.0, 250.0, 500.0, 750.0, 1_000.0, 1_500.0, 2_000.0, 3_000.0, 4_000.0 },
        &.{ 0.9900337503672718, 0.9996527019462578, 0.9905867975893236, 0.9999118486015344, 0.9900337503672689, 0.013647998464433654, 0.00013456385550589142, 2.74991184116989e-05, 3.1622776601683816e-05 },
    );

    const high_pass = try FilterDesign.highPass(.{
        .order = 5,
        .sample_rate = 48_000.0,
        .frequency_hz = 6_000.0,
        .ripple_db = 1.0,
        .attenuation_db = 80.0,
    });
    try expectReferenceResponse(
        high_pass,
        48_000.0,
        &.{ 0.0, 1_000.0, 3_000.0, 6_000.0, 9_000.0, 12_000.0, 20_000.0, 24_000.0 },
        &.{ 0.0, 9.30681304936051e-05, 0.0012987543129830308, 0.891250938133746, 0.9988289567901183, 0.9117336511694251, 0.9682077238249296, 0.9999999999999996 },
    );
}

test "elliptic specifications meet low-pass and high-pass edges" {
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
    try expectSpecification(low, low_specification);
    try expectLowPassBands(low, low_specification);

    const high_specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 4_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 0.5,
        .minimum_stopband_attenuation_db = 50.0,
    };
    const high =
        try FilterDesign.highPassForSpecification(high_specification);
    try expectSpecification(high, high_specification);
    try expectHighPassBands(high, high_specification);
}

test "elliptic design rejects invalid and unbounded requests" {
    const FilterDesign = Designer(f64);
    try std.testing.expectError(
        error.InvalidEllipticDesign,
        FilterDesign.lowPass(.{
            .order = 4,
            .sample_rate = 48_000.0,
            .frequency_hz = 2_000.0,
            .ripple_db = 1.0,
            .attenuation_db = 0.5,
        }),
    );
    try std.testing.expectError(
        error.InvalidEllipticSpecification,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 2_000.0,
            .stopband_hz = 1_000.0,
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
            2.0e-6,
        );
    }
}

fn expectLowPassBands(
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
    for (0..257) |index| {
        const fraction = @as(f64, @floatFromInt(index)) / 256.0;
        const passband_hz = specification.passband_hz * fraction;
        const stopband_hz = specification.stopband_hz +
            (specification.sample_rate * 0.499 -
                specification.stopband_hz) *
                fraction;
        try std.testing.expect(
            cascade.magnitude(specification.sample_rate, passband_hz) +
                0.000_001 >=
                passband_floor,
        );
        try std.testing.expect(
            cascade.magnitude(specification.sample_rate, stopband_hz) <=
                stopband_ceiling + 0.000_001,
        );
    }
}

fn expectHighPassBands(
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
    for (0..257) |index| {
        const fraction = @as(f64, @floatFromInt(index)) / 256.0;
        const stopband_hz = specification.stopband_hz * fraction;
        const passband_hz = specification.passband_hz +
            (specification.sample_rate * 0.499 -
                specification.passband_hz) *
                fraction;
        try std.testing.expect(
            cascade.magnitude(specification.sample_rate, stopband_hz) <=
                stopband_ceiling + 0.000_001,
        );
        try std.testing.expect(
            cascade.magnitude(specification.sample_rate, passband_hz) +
                0.000_001 >=
                passband_floor,
        );
    }
}
