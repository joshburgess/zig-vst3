const std = @import("std");
const biquad = @import("biquad.zig");
const butterworth = @import("butterworth_design.zig");

pub const Config = struct {
    order: usize,
    sample_rate: f64,
    frequency_hz: f64,
    ripple_db: f64,
};

pub const Specification = butterworth.Specification;

const Kind = enum { low_pass, high_pass };

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Chebyshev design supports f32 and f64 samples");

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
            const epsilon = @sqrt(
                std.math.pow(f64, 10.0, config.ripple_db / 10.0) - 1.0,
            );
            const order: f64 = @floatFromInt(config.order);
            const mu = std.math.asinh(1.0 / epsilon) / order;
            const warped = @tan(
                std.math.pi * config.frequency_hz / config.sample_rate,
            );

            var result = butterworth.Cascade{
                .section_count = (config.order + 1) / 2,
                .order = config.order,
            };
            var section_index: usize = 0;
            if (config.order % 2 == 1) {
                const pole = -std.math.sinh(mu);
                result.sections[0] = firstOrder(pole, warped, kind);
                section_index = 1;
            }

            for (0..config.order / 2) |pair_index| {
                const angle = std.math.pi *
                    @as(f64, @floatFromInt(2 * pair_index + 1)) /
                    (2.0 * order);
                const real = -std.math.sinh(mu) * @sin(angle);
                const imaginary = std.math.cosh(mu) * @cos(angle);
                result.sections[section_index + pair_index] = secondOrder(
                    real,
                    imaginary,
                    warped,
                    kind,
                );
            }

            if (config.order % 2 == 0) {
                const gain = std.math.pow(
                    f64,
                    10.0,
                    -config.ripple_db / 20.0,
                );
                result.sections[0].b0 *= gain;
                result.sections[0].b1 *= gain;
                result.sections[0].b2 *= gain;
            }
            for (result.active()) |section| {
                if (!section.valid()) return error.InvalidChebyshevDesign;
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
            const order_float = @ceil(
                std.math.acosh(@sqrt(stopband_error / passband_error)) /
                    std.math.acosh(transition_ratio),
            );
            if (!std.math.isFinite(order_float) or
                order_float < 1.0 or
                order_float >
                    @as(
                        f64,
                        @floatFromInt(butterworth.maximum_sections * 2),
                    ))
                return error.ChebyshevSpecificationExceedsMaximumOrder;

            return design(.{
                .order = @intFromFloat(order_float),
                .sample_rate = specification.sample_rate,
                .frequency_hz = specification.passband_hz,
                .ripple_db = specification.maximum_passband_loss_db,
            }, kind);
        }

        fn firstOrder(
            pole: f64,
            warped: f64,
            kind: Kind,
        ) biquad.Coefficients {
            return switch (kind) {
                .low_pass => blk: {
                    const a0 = 1.0 - warped * pole;
                    const numerator = -warped * pole / a0;
                    break :blk .{
                        .b0 = numerator,
                        .b1 = numerator,
                        .b2 = 0.0,
                        .a1 = (-1.0 - warped * pole) / a0,
                        .a2 = 0.0,
                    };
                },
                .high_pass => blk: {
                    const a0 = warped - pole;
                    break :blk .{
                        .b0 = -pole / a0,
                        .b1 = pole / a0,
                        .b2 = 0.0,
                        .a1 = (warped + pole) / a0,
                        .a2 = 0.0,
                    };
                },
            };
        }

        fn secondOrder(
            real: f64,
            imaginary: f64,
            warped: f64,
            kind: Kind,
        ) biquad.Coefficients {
            const magnitude_squared = real * real + imaginary * imaginary;
            return switch (kind) {
                .low_pass => blk: {
                    const scaled_magnitude =
                        warped * warped * magnitude_squared;
                    const a0 = 1.0 - 2.0 * warped * real +
                        scaled_magnitude;
                    const numerator = scaled_magnitude / a0;
                    break :blk .{
                        .b0 = numerator,
                        .b1 = 2.0 * numerator,
                        .b2 = numerator,
                        .a1 = 2.0 * (scaled_magnitude - 1.0) / a0,
                        .a2 = (1.0 + 2.0 * warped * real +
                            scaled_magnitude) / a0,
                    };
                },
                .high_pass => blk: {
                    const warped_squared = warped * warped;
                    const a0 = warped_squared - 2.0 * real * warped +
                        magnitude_squared;
                    const numerator = magnitude_squared / a0;
                    break :blk .{
                        .b0 = numerator,
                        .b1 = -2.0 * numerator,
                        .b2 = numerator,
                        .a1 = 2.0 *
                            (warped_squared - magnitude_squared) / a0,
                        .a2 = (warped_squared + 2.0 * real * warped +
                            magnitude_squared) / a0,
                    };
                },
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
                config.ripple_db > 12.0)
                return error.InvalidChebyshevDesign;
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
                return error.InvalidChebyshevSpecification;
            const frequencies_valid = switch (kind) {
                .low_pass => specification.passband_hz <
                    specification.stopband_hz,
                .high_pass => specification.passband_hz >
                    specification.stopband_hz,
            };
            if (!frequencies_valid)
                return error.InvalidChebyshevSpecification;
        }
    };
}

test "Chebyshev Type I low-pass meets odd and even ripple contracts" {
    const FilterDesign = Designer(f64);
    inline for (.{ 3, 4 }) |order| {
        const cascade = try FilterDesign.lowPass(.{
            .order = order,
            .sample_rate = 48_000.0,
            .frequency_hz = 2_000.0,
            .ripple_db = 1.0,
        });
        const cutoff_gain = std.math.pow(f64, 10.0, -1.0 / 20.0);
        try std.testing.expectApproxEqAbs(
            cutoff_gain,
            cascade.magnitude(48_000.0, 2_000.0),
            0.000_001,
        );
        const dc_expected = if (order % 2 == 0) cutoff_gain else 1.0;
        try std.testing.expectApproxEqAbs(
            dc_expected,
            cascade.magnitude(48_000.0, 0.0),
            0.000_001,
        );
        try std.testing.expect(
            cascade.magnitude(48_000.0, 500.0) >
                cascade.magnitude(48_000.0, 12_000.0) * 100.0,
        );
    }
}

test "Chebyshev Type I high-pass supports first and high orders" {
    const FilterDesign = Designer(f32);
    inline for (.{ 1, 7 }) |order| {
        const cascade = try FilterDesign.highPass(.{
            .order = order,
            .sample_rate = 48_000.0,
            .frequency_hz = 1_000.0,
            .ripple_db = 0.5,
        });
        try std.testing.expect(cascade.valid());
        const separation = if (order == 1) 2.0 else 1_000.0;
        try std.testing.expect(
            cascade.magnitude(48_000.0, 12_000.0) >
                cascade.magnitude(48_000.0, 100.0) * separation,
        );
        try std.testing.expectApproxEqAbs(
            std.math.pow(f64, 10.0, -0.5 / 20.0),
            cascade.magnitude(48_000.0, 1_000.0),
            0.000_001,
        );
    }
}

test "Chebyshev Type I rejects invalid configuration" {
    const FilterDesign = Designer(f64);
    try std.testing.expectError(
        error.InvalidChebyshevDesign,
        FilterDesign.lowPass(.{
            .order = 0,
            .sample_rate = 48_000.0,
            .frequency_hz = 1_000.0,
            .ripple_db = 1.0,
        }),
    );
    try std.testing.expectError(
        error.InvalidChebyshevDesign,
        FilterDesign.lowPass(.{
            .order = 4,
            .sample_rate = 48_000.0,
            .frequency_hz = 1_000.0,
            .ripple_db = 0.0,
        }),
    );
    const maximum_order = try FilterDesign.lowPass(.{
        .order = 16,
        .sample_rate = 192_000.0,
        .frequency_hz = 20_000.0,
        .ripple_db = 0.01,
    });
    try std.testing.expect(maximum_order.valid());
    try std.testing.expect(std.math.isFinite(
        maximum_order.magnitude(192_000.0, 20_000.0),
    ));
}

test "Chebyshev Type I specifications derive bounded low-pass order" {
    const FilterDesign = Designer(f64);
    const specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 60.0,
    };
    const cascade =
        try FilterDesign.lowPassForSpecification(specification);
    try std.testing.expect(cascade.valid());
    try std.testing.expect(
        cascade.magnitude(
            specification.sample_rate,
            specification.stopband_hz,
        ) <= std.math.pow(
            f64,
            10.0,
            -specification.minimum_stopband_attenuation_db / 20.0,
        ) + 0.000_001,
    );
}

test "Chebyshev Type I specifications support high-pass and reject limits" {
    const FilterDesign = Designer(f32);
    const specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 4_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 0.5,
        .minimum_stopband_attenuation_db = 50.0,
    };
    const cascade =
        try FilterDesign.highPassForSpecification(specification);
    try std.testing.expect(cascade.valid());
    try std.testing.expect(
        cascade.magnitude(
            specification.sample_rate,
            specification.stopband_hz,
        ) <= std.math.pow(
            f64,
            10.0,
            -specification.minimum_stopband_attenuation_db / 20.0,
        ) + 0.000_001,
    );
    try std.testing.expectError(
        error.InvalidChebyshevSpecification,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 2_000.0,
            .stopband_hz = 1_000.0,
        }),
    );
    try std.testing.expectError(
        error.ChebyshevSpecificationExceedsMaximumOrder,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 1_010.0,
            .maximum_passband_loss_db = 0.01,
            .minimum_stopband_attenuation_db = 200.0,
        }),
    );
}
