const std = @import("std");
const biquad = @import("biquad.zig");

pub const maximum_sections = 8;
const DesignKind = enum { low_pass, high_pass };

pub const Specification = struct {
    sample_rate: f64,
    passband_hz: f64,
    stopband_hz: f64,
    maximum_passband_loss_db: f64 = 1.0,
    minimum_stopband_attenuation_db: f64 = 60.0,
};

pub const Cascade = struct {
    sections: [maximum_sections]biquad.Coefficients =
        [1]biquad.Coefficients{biquad.Coefficients.identity()} **
        maximum_sections,
    section_count: usize = 0,
    order: usize = 0,

    pub fn active(self: *const Cascade) []const biquad.Coefficients {
        if (!self.valid()) return &.{};
        return self.sections[0..self.section_count];
    }

    pub fn magnitude(
        self: *const Cascade,
        sample_rate: f64,
        frequency_hz: f64,
    ) f64 {
        if (!self.valid()) return 0.0;
        return cascadeMagnitude(self.active(), sample_rate, frequency_hz);
    }

    pub fn valid(self: *const Cascade) bool {
        if (self.order < 1 or
            self.order > maximum_sections * 2 or
            self.section_count != (self.order + 1) / 2)
        {
            return false;
        }
        for (self.sections[0..self.section_count]) |section| {
            if (!section.valid()) return false;
        }
        return true;
    }
};

pub const SpecificationDesign = struct {
    cascade: Cascade,
    cutoff_hz: f64,
};

pub fn Designer(comptime Sample: type) type {
    if (Sample != f32 and Sample != f64)
        @compileError("Butterworth design supports f32 and f64 samples");

    return struct {
        pub fn lowPass(
            output: []biquad.Coefficients,
            sample_rate: f64,
            frequency_hz: f64,
        ) !void {
            try design(output, sample_rate, frequency_hz, .low_pass);
        }

        pub fn highPass(
            output: []biquad.Coefficients,
            sample_rate: f64,
            frequency_hz: f64,
        ) !void {
            try design(output, sample_rate, frequency_hz, .high_pass);
        }

        pub fn lowPassOrder(
            order: usize,
            sample_rate: f64,
            frequency_hz: f64,
        ) !Cascade {
            return designOrder(order, sample_rate, frequency_hz, .low_pass);
        }

        pub fn highPassOrder(
            order: usize,
            sample_rate: f64,
            frequency_hz: f64,
        ) !Cascade {
            return designOrder(order, sample_rate, frequency_hz, .high_pass);
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

        pub fn magnitude(
            sections: []const biquad.Coefficients,
            sample_rate: f64,
            frequency_hz: f64,
        ) f64 {
            return cascadeMagnitude(sections, sample_rate, frequency_hz);
        }

        fn design(
            output: []biquad.Coefficients,
            sample_rate: f64,
            frequency_hz: f64,
            kind: DesignKind,
        ) !void {
            if (output.len == 0 or output.len > maximum_sections or
                !std.math.isFinite(sample_rate) or
                sample_rate < 1_000.0 or
                sample_rate > 768_000.0 or
                !std.math.isFinite(frequency_hz) or
                frequency_hz < 1.0 or
                frequency_hz >= sample_rate * 0.49)
                return error.InvalidButterworthDesign;

            var designed: [maximum_sections]biquad.Coefficients = undefined;
            const order = output.len * 2;
            for (output, 0..) |_, index| {
                const angle = std.math.pi *
                    @as(f64, @floatFromInt(2 * index + 1)) /
                    @as(f64, @floatFromInt(2 * order));
                const q = 1.0 / (2.0 * @cos(angle));
                designed[index] = (biquad.Config{
                    .kind = switch (kind) {
                        .low_pass => .low_pass,
                        .high_pass => .high_pass,
                    },
                    .sample_rate = sample_rate,
                    .frequency_hz = frequency_hz,
                    .gain_db = 0.0,
                    .q = q,
                }).coefficients() catch
                    return error.InvalidButterworthDesign;
            }
            @memcpy(output, designed[0..output.len]);
        }

        fn designOrder(
            order: usize,
            sample_rate: f64,
            frequency_hz: f64,
            kind: DesignKind,
        ) !Cascade {
            try validateRequest(order, sample_rate, frequency_hz);

            var result = Cascade{
                .section_count = (order + 1) / 2,
                .order = order,
            };
            var output_index: usize = 0;
            if (order % 2 == 1) {
                result.sections[0] = firstOrder(
                    sample_rate,
                    frequency_hz,
                    kind,
                );
                output_index = 1;
            }

            const pair_count = order / 2;
            for (0..pair_count) |pair_index| {
                const q = if (order % 2 == 0) blk: {
                    const angle = std.math.pi *
                        @as(f64, @floatFromInt(2 * pair_index + 1)) /
                        @as(f64, @floatFromInt(2 * order));
                    break :blk 1.0 / (2.0 * @cos(angle));
                } else blk: {
                    const angle = std.math.pi *
                        @as(f64, @floatFromInt(pair_index + 1)) /
                        @as(f64, @floatFromInt(order));
                    break :blk 1.0 / (2.0 * @cos(angle));
                };
                result.sections[output_index + pair_index] = (biquad.Config{
                    .kind = switch (kind) {
                        .low_pass => .low_pass,
                        .high_pass => .high_pass,
                    },
                    .sample_rate = sample_rate,
                    .frequency_hz = frequency_hz,
                    .gain_db = 0.0,
                    .q = q,
                }).coefficients() catch
                    return error.InvalidButterworthDesign;
            }
            return result;
        }

        fn designSpecification(
            specification: Specification,
            kind: DesignKind,
        ) !SpecificationDesign {
            try validateSpecification(specification, kind);

            const passband =
                @tan(std.math.pi *
                    specification.passband_hz /
                    specification.sample_rate);
            const stopband =
                @tan(std.math.pi *
                    specification.stopband_hz /
                    specification.sample_rate);
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
                @log(stopband_error / passband_error) /
                    (2.0 * @log(transition_ratio)),
            );
            if (!std.math.isFinite(order_float) or
                order_float < 1.0 or
                order_float >
                    @as(f64, @floatFromInt(maximum_sections * 2)))
                return error.ButterworthSpecificationExceedsMaximumOrder;
            const order: usize = @intFromFloat(order_float);

            const cutoff_scale = std.math.pow(
                f64,
                passband_error,
                1.0 / (2.0 * @as(f64, @floatFromInt(order))),
            );
            const cutoff_warped = switch (kind) {
                .low_pass => passband / cutoff_scale,
                .high_pass => passband * cutoff_scale,
            };
            const cutoff_hz =
                std.math.atan(cutoff_warped) *
                specification.sample_rate /
                std.math.pi;
            if (!std.math.isFinite(cutoff_hz))
                return error.InvalidButterworthSpecification;

            return .{
                .cascade = try designOrder(
                    order,
                    specification.sample_rate,
                    cutoff_hz,
                    kind,
                ),
                .cutoff_hz = cutoff_hz,
            };
        }

        fn firstOrder(
            sample_rate: f64,
            frequency_hz: f64,
            kind: DesignKind,
        ) biquad.Coefficients {
            const warped = @tan(std.math.pi * frequency_hz / sample_rate);
            const inverse = 1.0 / (1.0 + warped);
            const a1 = (warped - 1.0) * inverse;
            return switch (kind) {
                .low_pass => .{
                    .b0 = warped * inverse,
                    .b1 = warped * inverse,
                    .b2 = 0.0,
                    .a1 = a1,
                    .a2 = 0.0,
                },
                .high_pass => .{
                    .b0 = inverse,
                    .b1 = -inverse,
                    .b2 = 0.0,
                    .a1 = a1,
                    .a2 = 0.0,
                },
            };
        }

        fn validateRequest(
            order: usize,
            sample_rate: f64,
            frequency_hz: f64,
        ) !void {
            if (order == 0 or order > maximum_sections * 2 or
                !std.math.isFinite(sample_rate) or
                sample_rate < 1_000.0 or
                sample_rate > 768_000.0 or
                !std.math.isFinite(frequency_hz) or
                frequency_hz < 1.0 or
                frequency_hz >= sample_rate * 0.49)
                return error.InvalidButterworthDesign;
        }

        fn validateSpecification(
            specification: Specification,
            kind: DesignKind,
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
                specification.maximum_passband_loss_db <= 0.0 or
                specification.maximum_passband_loss_db > 24.0 or
                !std.math.isFinite(
                    specification.minimum_stopband_attenuation_db,
                ) or
                specification.minimum_stopband_attenuation_db <=
                    specification.maximum_passband_loss_db or
                specification.minimum_stopband_attenuation_db > 300.0)
                return error.InvalidButterworthSpecification;

            const frequencies_valid = switch (kind) {
                .low_pass => specification.passband_hz <
                    specification.stopband_hz,
                .high_pass => specification.passband_hz >
                    specification.stopband_hz,
            };
            if (!frequencies_valid)
                return error.InvalidButterworthSpecification;
        }
    };
}

fn cascadeMagnitude(
    sections: []const biquad.Coefficients,
    sample_rate: f64,
    frequency_hz: f64,
) f64 {
    if (sections.len == 0 or sections.len > maximum_sections)
        return 0.0;
    var result: f64 = 1.0;
    for (sections) |section| {
        result *= section.magnitude(sample_rate, frequency_hz);
        if (!std.math.isFinite(result)) return 0.0;
    }
    return result;
}

test "fourth-order Butterworth low-pass meets its cutoff response" {
    const FilterDesign = Designer(f64);
    var sections: [2]biquad.Coefficients = undefined;
    try FilterDesign.lowPass(&sections, 48_000.0, 1_000.0);
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0 / @sqrt(2.0)),
        FilterDesign.magnitude(&sections, 48_000.0, 1_000.0),
        0.000_001,
    );
    try std.testing.expect(
        FilterDesign.magnitude(&sections, 48_000.0, 100.0) >
            FilterDesign.magnitude(&sections, 48_000.0, 10_000.0) * 1_000.0,
    );
}

test "sixth-order Butterworth high-pass uses distinct section Q values" {
    const FilterDesign = Designer(f32);
    var sections: [3]biquad.Coefficients = undefined;
    try FilterDesign.highPass(&sections, 48_000.0, 2_000.0);
    try std.testing.expect(!std.meta.eql(sections[0], sections[1]));
    try std.testing.expect(!std.meta.eql(sections[1], sections[2]));
    try std.testing.expect(
        FilterDesign.magnitude(&sections, 48_000.0, 10_000.0) >
            FilterDesign.magnitude(&sections, 48_000.0, 100.0) * 1_000.0,
    );
}

test "Butterworth design rejects invalid requests transactionally" {
    const FilterDesign = Designer(f64);
    var sections = [2]biquad.Coefficients{
        biquad.Coefficients.identity(),
        biquad.Coefficients.identity(),
    };
    const before = sections;
    try std.testing.expectError(
        error.InvalidButterworthDesign,
        FilterDesign.lowPass(&sections, 48_000.0, 24_000.0),
    );
    try std.testing.expectEqualDeep(before, sections);
    try std.testing.expectError(
        error.InvalidButterworthDesign,
        FilterDesign.lowPass(sections[0..0], 48_000.0, 1_000.0),
    );
}

test "odd-order Butterworth cascades meet the cutoff response" {
    const FilterDesign = Designer(f64);
    inline for (.{ 1, 3, 5 }) |order| {
        const cascade = try FilterDesign.lowPassOrder(
            order,
            48_000.0,
            1_000.0,
        );
        try std.testing.expect(cascade.valid());
        try std.testing.expectEqual(order, cascade.order);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0 / @sqrt(2.0)),
            cascade.magnitude(48_000.0, 1_000.0),
            0.000_001,
        );
        try std.testing.expect(
            cascade.magnitude(48_000.0, 100.0) >
                cascade.magnitude(48_000.0, 10_000.0),
        );
    }
}

test "order-aware Butterworth design supports high-pass and rejects bounds" {
    const FilterDesign = Designer(f32);
    const cascade = try FilterDesign.highPassOrder(
        7,
        48_000.0,
        2_000.0,
    );
    try std.testing.expectEqual(@as(usize, 4), cascade.section_count);
    try std.testing.expect(
        cascade.magnitude(48_000.0, 10_000.0) >
            cascade.magnitude(48_000.0, 100.0) * 1_000.0,
    );
    try std.testing.expectError(
        error.InvalidButterworthDesign,
        FilterDesign.lowPassOrder(0, 48_000.0, 1_000.0),
    );
    try std.testing.expectError(
        error.InvalidButterworthDesign,
        FilterDesign.lowPassOrder(17, 48_000.0, 1_000.0),
    );
}

test "Butterworth cascade view rejects malformed retained state" {
    var cascade = try Designer(f64).lowPassOrder(
        3,
        48_000.0,
        1_000.0,
    );
    try std.testing.expectEqual(@as(usize, 2), cascade.active().len);

    cascade.section_count = std.math.maxInt(usize);
    try std.testing.expect(!cascade.valid());
    try std.testing.expectEqual(@as(usize, 0), cascade.active().len);

    cascade.section_count = 2;
    cascade.sections[0].b0 = std.math.nan(f64);
    try std.testing.expect(!cascade.valid());
    try std.testing.expectEqual(@as(usize, 0), cascade.active().len);
}

test "Butterworth specifications derive low-pass order and cutoff" {
    const FilterDesign = Designer(f64);
    const specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 1_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 40.0,
    };
    const design = try FilterDesign.lowPassForSpecification(specification);
    try std.testing.expect(design.cascade.valid());
    try std.testing.expect(design.cutoff_hz > specification.passband_hz);
    try std.testing.expect(
        design.cascade.magnitude(
            specification.sample_rate,
            specification.passband_hz,
        ) >= std.math.pow(
            f64,
            10.0,
            -specification.maximum_passband_loss_db / 20.0,
        ) - 0.000_001,
    );
    try std.testing.expect(
        design.cascade.magnitude(
            specification.sample_rate,
            specification.stopband_hz,
        ) <= std.math.pow(
            f64,
            10.0,
            -specification.minimum_stopband_attenuation_db / 20.0,
        ) + 0.000_001,
    );
}

test "Butterworth specifications derive high-pass order and reject limits" {
    const FilterDesign = Designer(f32);
    const specification = Specification{
        .sample_rate = 48_000.0,
        .passband_hz = 4_000.0,
        .stopband_hz = 2_000.0,
        .maximum_passband_loss_db = 1.0,
        .minimum_stopband_attenuation_db = 50.0,
    };
    const design = try FilterDesign.highPassForSpecification(specification);
    try std.testing.expect(design.cascade.valid());
    try std.testing.expect(design.cutoff_hz < specification.passband_hz);
    try std.testing.expect(
        design.cascade.magnitude(
            specification.sample_rate,
            specification.stopband_hz,
        ) <= std.math.pow(
            f64,
            10.0,
            -specification.minimum_stopband_attenuation_db / 20.0,
        ) + 0.000_001,
    );

    try std.testing.expectError(
        error.InvalidButterworthSpecification,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 2_000.0,
            .stopband_hz = 1_000.0,
        }),
    );
    try std.testing.expectError(
        error.ButterworthSpecificationExceedsMaximumOrder,
        FilterDesign.lowPassForSpecification(.{
            .sample_rate = 48_000.0,
            .passband_hz = 1_000.0,
            .stopband_hz = 1_050.0,
            .maximum_passband_loss_db = 0.1,
            .minimum_stopband_attenuation_db = 120.0,
        }),
    );
}
