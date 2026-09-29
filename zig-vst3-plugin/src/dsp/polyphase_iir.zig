const std = @import("std");

pub const maximum_sections = 32;
const maximum_series_terms = 4096;
const series_tolerance = 1.0e-18;

const Complex = struct {
    real: f64,
    imaginary: f64,

    fn add(self: Complex, other: Complex) Complex {
        return .{
            .real = self.real + other.real,
            .imaginary = self.imaginary + other.imaginary,
        };
    }

    fn multiply(self: Complex, other: Complex) Complex {
        return .{
            .real = self.real * other.real -
                self.imaginary * other.imaginary,
            .imaginary = self.real * other.imaginary +
                self.imaginary * other.real,
        };
    }

    fn divide(self: Complex, other: Complex) Complex {
        const denominator =
            other.real * other.real +
            other.imaginary * other.imaginary;
        return .{
            .real = (self.real * other.real +
                self.imaginary * other.imaginary) / denominator,
            .imaginary = (self.imaginary * other.real -
                self.real * other.imaginary) / denominator,
        };
    }

    fn scale(self: Complex, amount: f64) Complex {
        return .{
            .real = self.real * amount,
            .imaginary = self.imaginary * amount,
        };
    }

    fn magnitude(self: Complex) f64 {
        return @sqrt(
            self.real * self.real +
                self.imaginary * self.imaginary,
        );
    }

    fn valid(self: Complex) bool {
        return std.math.isFinite(self.real) and
            std.math.isFinite(self.imaginary);
    }
};

pub fn Design(comptime Sample: type) type {
    requireSampleType(Sample);

    return struct {
        const Self = @This();

        alpha: [maximum_sections]Sample = @splat(0.0),
        section_count: usize = 0,
        order: usize = 0,
        normalized_transition_width: Sample = 0.0,
        stopband_attenuation_db: Sample = 0.0,

        pub fn directSectionCount(self: Self) usize {
            if (self.section_count > maximum_sections) return 0;
            return (self.section_count + 1) / 2;
        }

        pub fn delayedSectionCount(self: Self) usize {
            if (self.section_count > maximum_sections) return 0;
            return self.section_count / 2;
        }

        pub fn directAlpha(
            self: Self,
            section_index: usize,
        ) ?Sample {
            if (self.section_count > maximum_sections) return null;
            const index = std.math.mul(
                usize,
                section_index,
                2,
            ) catch return null;
            if (index >= self.section_count) return null;
            return self.alpha[index];
        }

        pub fn delayedAlpha(
            self: Self,
            section_index: usize,
        ) ?Sample {
            if (self.section_count > maximum_sections) return null;
            const doubled = std.math.mul(
                usize,
                section_index,
                2,
            ) catch return null;
            const index = std.math.add(usize, doubled, 1) catch return null;
            if (index >= self.section_count) return null;
            return self.alpha[index];
        }

        pub fn magnitude(
            self: Self,
            normalized_frequency: f64,
        ) !f64 {
            return self.responseMagnitude(
                normalized_frequency,
                false,
            );
        }

        pub fn highPassMagnitude(
            self: Self,
            normalized_frequency: f64,
        ) !f64 {
            return self.responseMagnitude(
                normalized_frequency,
                true,
            );
        }

        fn responseMagnitude(
            self: Self,
            normalized_frequency: f64,
            subtract_paths: bool,
        ) !f64 {
            if (!self.valid())
                return error.InvalidPolyphaseAllpassDesign;
            if (!std.math.isFinite(normalized_frequency) or
                normalized_frequency < 0.0 or
                normalized_frequency > 0.5)
                return error.InvalidNormalizedFrequency;

            const omega = std.math.tau * normalized_frequency;
            const delay = Complex{
                .real = @cos(omega),
                .imaginary = -@sin(omega),
            };
            const delay_squared = delay.multiply(delay);
            var direct = Complex{ .real = 1.0, .imaginary = 0.0 };
            var delayed = delay;
            for (self.alpha[0..self.section_count], 0..) |
                coefficient,
                index,
            | {
                const alpha: f64 = @floatCast(coefficient);
                const response = (Complex{
                    .real = alpha + delay_squared.real,
                    .imaginary = delay_squared.imaginary,
                }).divide(.{
                    .real = 1.0 + alpha * delay_squared.real,
                    .imaginary = alpha * delay_squared.imaginary,
                });
                if (!response.valid())
                    return error.InvalidPolyphaseAllpassResponse;
                if (index % 2 == 0)
                    direct = direct.multiply(response)
                else
                    delayed = delayed.multiply(response);
            }
            const combined_delayed =
                if (subtract_paths)
                    delayed.scale(-1.0)
                else
                    delayed;
            const result =
                direct.add(combined_delayed).scale(0.5);
            if (!result.valid())
                return error.InvalidPolyphaseAllpassResponse;
            return result.magnitude();
        }

        pub fn valid(self: Self) bool {
            if (self.section_count == 0 or
                self.section_count > maximum_sections or
                self.order != self.section_count * 2 + 1 or
                !validTransitionWidth(
                    @as(f64, @floatCast(
                        self.normalized_transition_width,
                    )),
                ) or
                !validStopbandAttenuation(
                    @as(f64, @floatCast(
                        self.stopband_attenuation_db,
                    )),
                ))
                return false;

            for (self.alpha, 0..) |coefficient, index| {
                if (!std.math.isFinite(coefficient)) return false;
                if (index < self.section_count) {
                    if (coefficient <= 0.0 or coefficient >= 1.0)
                        return false;
                } else if (coefficient != 0.0) {
                    return false;
                }
            }
            return true;
        }
    };
}

pub fn Designer(comptime Sample: type) type {
    requireSampleType(Sample);
    const Result = Design(Sample);

    return struct {
        pub fn halfBandLowPass(
            normalized_transition_width: Sample,
            stopband_attenuation_db: Sample,
        ) !Result {
            const transition: f64 =
                @floatCast(normalized_transition_width);
            const attenuation: f64 =
                @floatCast(stopband_attenuation_db);
            if (!validTransitionWidth(transition))
                return error.InvalidPolyphaseAllpassTransitionWidth;
            if (!validStopbandAttenuation(attenuation))
                return error.InvalidPolyphaseAllpassStopband;

            const transition_radians = std.math.tau * transition;
            const tangent =
                @tan((std.math.pi - transition_radians) * 0.25);
            const selectivity = tangent * tangent;
            const complementary =
                @sqrt(1.0 - selectivity * selectivity);
            const root_complementary = @sqrt(complementary);
            const seed =
                0.5 *
                (1.0 - root_complementary) /
                (1.0 + root_complementary);
            const nome = seed +
                2.0 * std.math.pow(f64, seed, 5.0) +
                15.0 * std.math.pow(f64, seed, 9.0) +
                150.0 * std.math.pow(f64, seed, 13.0);
            if (!std.math.isFinite(nome) or
                nome <= 0.0 or nome >= 1.0)
                return error.InvalidPolyphaseAllpassDesign;

            const stopband_gain =
                std.math.pow(f64, 10.0, attenuation / 20.0);
            const ripple_ratio =
                stopband_gain * stopband_gain /
                (1.0 - stopband_gain * stopband_gain);
            const raw_order = @ceil(
                @log(ripple_ratio * ripple_ratio / 16.0) /
                    @log(nome),
            );
            if (!std.math.isFinite(raw_order) or raw_order < 1.0)
                return error.InvalidPolyphaseAllpassDesign;
            if (raw_order >
                @as(
                    f64,
                    @floatFromInt(maximum_sections * 2 + 1),
                ))
                return error.PolyphaseAllpassCapacityExceeded;

            var order: usize = @intFromFloat(raw_order);
            if (order % 2 == 0) order += 1;
            order = @max(order, 3);
            const section_count = (order - 1) / 2;
            if (section_count > maximum_sections)
                return error.PolyphaseAllpassCapacityExceeded;

            var result = Result{
                .section_count = section_count,
                .order = order,
                .normalized_transition_width = normalized_transition_width,
                .stopband_attenuation_db = stopband_attenuation_db,
            };
            for (0..section_count) |zero_based_index| {
                const index = zero_based_index + 1;
                const ratio = try ellipticRatio(
                    nome,
                    index,
                    order,
                );
                const ratio_squared = ratio * ratio;
                const radicand =
                    (1.0 - ratio_squared * selectivity) *
                    (1.0 - ratio_squared / selectivity);
                if (!std.math.isFinite(radicand) or radicand <= 0.0)
                    return error.InvalidPolyphaseAllpassDesign;
                const pole_factor =
                    @sqrt(radicand) / (1.0 + ratio_squared);
                const coefficient =
                    (1.0 - pole_factor) / (1.0 + pole_factor);
                const stored: Sample = @floatCast(coefficient);
                if (!std.math.isFinite(stored) or
                    stored <= 0.0 or stored >= 1.0)
                    return error.InvalidPolyphaseAllpassDesign;
                result.alpha[zero_based_index] = stored;
            }
            if (!result.valid())
                return error.InvalidPolyphaseAllpassDesign;
            return result;
        }
    };
}

pub fn Split(comptime Sample: type) type {
    requireSampleType(Sample);
    return struct {
        low_pass: Sample,
        high_pass: Sample,
    };
}

pub fn HalfBandFilter(comptime Sample: type) type {
    requireSampleType(Sample);
    const FilterDesign = Design(Sample);

    return struct {
        const Self = @This();

        const Section = struct {
            alpha: Sample = 0.0,
            input_one: Sample = 0.0,
            input_two: Sample = 0.0,
            output_one: Sample = 0.0,
            output_two: Sample = 0.0,

            fn process(self: *Section, input: Sample) Sample {
                const output =
                    self.alpha * input +
                    self.input_two -
                    self.alpha * self.output_two;
                self.input_two = self.input_one;
                self.input_one = input;
                self.output_two = self.output_one;
                self.output_one = output;
                return output;
            }

            fn stateValid(self: Section) bool {
                return std.math.isFinite(self.alpha) and
                    std.math.isFinite(self.input_one) and
                    std.math.isFinite(self.input_two) and
                    std.math.isFinite(self.output_one) and
                    std.math.isFinite(self.output_two);
            }

            fn clearState(self: *Section) void {
                self.input_one = 0.0;
                self.input_two = 0.0;
                self.output_one = 0.0;
                self.output_two = 0.0;
            }
        };

        design: FilterDesign,
        sections: [maximum_sections]Section = @splat(.{}),
        delayed_input: Sample = 0.0,

        pub fn init(design: FilterDesign) !Self {
            if (!design.valid())
                return error.InvalidPolyphaseAllpassDesign;
            var result = Self{ .design = design };
            for (design.alpha[0..design.section_count], 0..) |
                coefficient,
                index,
            | {
                result.sections[index].alpha = coefficient;
            }
            return result;
        }

        pub fn configure(
            self: *Self,
            design: FilterDesign,
        ) !void {
            const replacement = try init(design);
            self.* = replacement;
        }

        pub fn reset(self: *Self) void {
            for (&self.sections) |*section| section.clearState();
            self.delayed_input = 0.0;
        }

        pub fn processSample(
            self: *Self,
            input: Sample,
        ) !Sample {
            return (try self.processSampleSplit(input)).low_pass;
        }

        pub fn processSampleSplit(
            self: *Self,
            input: Sample,
        ) !Split(Sample) {
            if (!std.math.isFinite(input))
                return error.NonFinitePolyphaseAllpassInput;
            if (!self.valid())
                return error.InvalidPolyphaseAllpassFilterState;

            return self.processSampleSplitValid(input);
        }

        fn processSampleSplitValid(
            self: *Self,
            input: Sample,
        ) !Split(Sample) {
            var direct = input;
            var delayed = self.delayed_input;
            self.delayed_input = input;
            for (self.sections[0..self.design.section_count], 0..) |
                *section,
                index,
            | {
                if (index % 2 == 0)
                    direct = section.process(direct)
                else
                    delayed = section.process(delayed);
            }
            const low_pass = (direct + delayed) * 0.5;
            const high_pass = (direct - delayed) * 0.5;
            if (!std.math.isFinite(low_pass) or
                !std.math.isFinite(high_pass))
            {
                self.reset();
                return error.NonFinitePolyphaseAllpassOutput;
            }
            return .{
                .low_pass = low_pass,
                .high_pass = high_pass,
            };
        }

        pub fn processBlock(
            self: *Self,
            samples: []Sample,
        ) !void {
            if (!self.valid())
                return error.InvalidPolyphaseAllpassFilterState;
            for (samples) |sample| {
                if (!std.math.isFinite(sample))
                    return error.NonFinitePolyphaseAllpassInput;
            }
            for (samples) |*sample| {
                sample.* =
                    (try self.processSampleSplitValid(
                        sample.*,
                    )).low_pass;
            }
        }

        pub fn valid(self: Self) bool {
            if (!self.design.valid() or
                !std.math.isFinite(self.delayed_input))
                return false;
            for (self.sections, 0..) |section, index| {
                if (!section.stateValid()) return false;
                if (index < self.design.section_count) {
                    if (section.alpha != self.design.alpha[index])
                        return false;
                } else if (section.alpha != 0.0) {
                    return false;
                }
            }
            return true;
        }
    };
}

fn ellipticRatio(
    nome: f64,
    index: usize,
    order: usize,
) !f64 {
    const angle =
        std.math.pi *
        @as(f64, @floatFromInt(index)) /
        @as(f64, @floatFromInt(order));

    var numerator: f64 = 0.0;
    var numerator_converged = false;
    for (0..maximum_series_terms) |term_index| {
        const exponent = term_index * (term_index + 1);
        const sign: f64 =
            if (term_index % 2 == 0) 1.0 else -1.0;
        const odd: f64 = @floatFromInt(term_index * 2 + 1);
        const term =
            sign *
            std.math.pow(
                f64,
                nome,
                @as(f64, @floatFromInt(exponent)),
            ) *
            @sin(odd * angle);
        numerator += term;
        if (term_index > 0 and @abs(term) <= series_tolerance) {
            numerator_converged = true;
            break;
        }
    }
    if (!numerator_converged)
        return error.PolyphaseAllpassSeriesDidNotConverge;
    numerator *=
        2.0 * std.math.pow(f64, nome, 0.25);

    var denominator_sum: f64 = 0.0;
    var denominator_converged = false;
    for (1..maximum_series_terms + 1) |term_index| {
        const sign: f64 =
            if (term_index % 2 == 0) 1.0 else -1.0;
        const term =
            sign *
            std.math.pow(
                f64,
                nome,
                @as(f64, @floatFromInt(term_index * term_index)),
            ) *
            @cos(
                @as(f64, @floatFromInt(term_index)) *
                    angle *
                    2.0,
            );
        denominator_sum += term;
        if (@abs(term) <= series_tolerance) {
            denominator_converged = true;
            break;
        }
    }
    if (!denominator_converged)
        return error.PolyphaseAllpassSeriesDidNotConverge;
    const denominator = 1.0 + 2.0 * denominator_sum;
    const result = numerator / denominator;
    if (!std.math.isFinite(result) or result <= 0.0)
        return error.InvalidPolyphaseAllpassDesign;
    return result;
}

fn validTransitionWidth(value: f64) bool {
    return std.math.isFinite(value) and
        value > 0.0 and value < 0.5;
}

fn validStopbandAttenuation(value: f64) bool {
    return std.math.isFinite(value) and
        value > -300.0 and value < -10.0;
}

fn requireSampleType(comptime Sample: type) void {
    if (Sample != f32 and Sample != f64)
        @compileError(
            "polyphase all-pass IIR filters support f32 and f64 samples",
        );
}

test "polyphase all-pass design meets half-band specifications" {
    const FilterDesigner = Designer(f64);
    inline for (.{
        .{ @as(f64, 0.1), @as(f64, -60.0) },
        .{ @as(f64, 0.05), @as(f64, -90.0) },
        .{ @as(f64, 0.025), @as(f64, -120.0) },
    }) |request| {
        const design =
            try FilterDesigner.halfBandLowPass(
                request[0],
                request[1],
            );
        try std.testing.expect(design.valid());
        const passband_edge = 0.25 - request[0] * 0.5;
        const stopband_edge = 0.25 + request[0] * 0.5;
        const maximum_stopband =
            std.math.pow(f64, 10.0, request[1] / 20.0);
        var minimum_passband: f64 = 1.0;
        var observed_stopband: f64 = 0.0;
        for (0..4097) |index| {
            const frequency =
                0.5 *
                @as(f64, @floatFromInt(index)) /
                4096.0;
            const magnitude = try design.magnitude(frequency);
            if (frequency <= passband_edge)
                minimum_passband = @min(
                    minimum_passband,
                    magnitude,
                );
            if (frequency >= stopband_edge)
                observed_stopband = @max(
                    observed_stopband,
                    magnitude,
                );
        }
        try std.testing.expect(
            minimum_passband >=
                @sqrt(1.0 - maximum_stopband * maximum_stopband) -
                    1.0e-12,
        );
        try std.testing.expect(
            observed_stopband <= maximum_stopband * 1.000_001,
        );
    }
}

test "polyphase all-pass response is power complementary" {
    const design =
        try Designer(f64).halfBandLowPass(0.04, -100.0);
    for (0..2049) |index| {
        const frequency =
            0.25 *
            @as(f64, @floatFromInt(index)) /
            2048.0;
        const low = try design.magnitude(frequency);
        const high = try design.highPassMagnitude(frequency);
        try std.testing.expectApproxEqAbs(
            @as(f64, 1.0),
            low * low + high * high,
            2.0e-12,
        );
    }
    try std.testing.expectApproxEqAbs(
        @as(f64, 1.0),
        try design.magnitude(0.0),
        1.0e-14,
    );
    try std.testing.expectApproxEqAbs(
        @as(f64, 0.0),
        try design.magnitude(0.5),
        1.0e-14,
    );
}

test "polyphase all-pass processor matches analytic impulse response" {
    const design =
        try Designer(f64).halfBandLowPass(0.08, -80.0);
    var filter = try HalfBandFilter(f64).init(design);
    var low_impulse: [8192]f64 = undefined;
    var high_impulse: [8192]f64 = undefined;
    for (0..low_impulse.len) |index| {
        const split =
            try filter.processSampleSplit(
                if (index == 0) 1.0 else 0.0,
            );
        low_impulse[index] = split.low_pass;
        high_impulse[index] = split.high_pass;
    }

    inline for (.{ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5 }) |
        frequency,
    | {
        var low_real: f64 = 0.0;
        var low_imaginary: f64 = 0.0;
        var high_real: f64 = 0.0;
        var high_imaginary: f64 = 0.0;
        for (
            low_impulse,
            high_impulse,
            0..,
        ) |low_sample, high_sample, index| {
            const phase =
                std.math.tau *
                frequency *
                @as(f64, @floatFromInt(index));
            low_real += low_sample * @cos(phase);
            low_imaginary -= low_sample * @sin(phase);
            high_real += high_sample * @cos(phase);
            high_imaginary -= high_sample * @sin(phase);
        }
        const measured_low =
            @sqrt(
                low_real * low_real +
                    low_imaginary * low_imaginary,
            );
        const measured_high =
            @sqrt(
                high_real * high_real +
                    high_imaginary * high_imaginary,
            );
        try std.testing.expectApproxEqAbs(
            try design.magnitude(frequency),
            measured_low,
            2.0e-10,
        );
        try std.testing.expectApproxEqAbs(
            try design.highPassMagnitude(frequency),
            measured_high,
            2.0e-10,
        );
    }
}

test "polyphase all-pass processing is partition independent" {
    const design =
        try Designer(f32).halfBandLowPass(0.075, -72.0);
    var input: [257]f32 = undefined;
    for (&input, 0..) |*sample, index| {
        sample.* =
            0.6 * @sin(
                std.math.tau *
                    0.037 *
                    @as(f32, @floatFromInt(index)),
            ) +
            0.25 * @cos(
                std.math.tau *
                    0.31 *
                    @as(f32, @floatFromInt(index)),
            );
    }

    var whole = try HalfBandFilter(f32).init(design);
    var whole_output = input;
    try whole.processBlock(&whole_output);

    var partitioned = try HalfBandFilter(f32).init(design);
    var partitioned_output = input;
    try partitioned.processBlock(partitioned_output[0..19]);
    try partitioned.processBlock(partitioned_output[19..113]);
    try partitioned.processBlock(partitioned_output[113..]);
    try std.testing.expectEqualSlices(
        f32,
        &whole_output,
        &partitioned_output,
    );
}

test "polyphase all-pass validation is transactional and hostile-safe" {
    const FilterDesigner = Designer(f64);
    try std.testing.expectError(
        error.InvalidPolyphaseAllpassTransitionWidth,
        FilterDesigner.halfBandLowPass(0.0, -80.0),
    );
    try std.testing.expectError(
        error.InvalidPolyphaseAllpassTransitionWidth,
        FilterDesigner.halfBandLowPass(0.5, -80.0),
    );
    try std.testing.expectError(
        error.InvalidPolyphaseAllpassStopband,
        FilterDesigner.halfBandLowPass(0.05, -10.0),
    );
    try std.testing.expectError(
        error.PolyphaseAllpassCapacityExceeded,
        FilterDesigner.halfBandLowPass(0.000_001, -299.0),
    );
    try std.testing.expectError(
        error.InvalidNormalizedFrequency,
        (try FilterDesigner.halfBandLowPass(
            0.05,
            -80.0,
        )).magnitude(0.500_01),
    );

    const original_design =
        try FilterDesigner.halfBandLowPass(0.08, -70.0);
    var filter = try HalfBandFilter(f64).init(original_design);
    var invalid_design = original_design;
    invalid_design.alpha[0] = 1.0;
    try std.testing.expectError(
        error.InvalidPolyphaseAllpassDesign,
        filter.configure(invalid_design),
    );
    try std.testing.expectEqualDeep(
        original_design,
        filter.design,
    );

    invalid_design = original_design;
    invalid_design.section_count = std.math.maxInt(usize);
    try std.testing.expect(!invalid_design.valid());
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_design.directSectionCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        invalid_design.delayedSectionCount(),
    );
    try std.testing.expect(invalid_design.directAlpha(0) == null);
    try std.testing.expect(invalid_design.delayedAlpha(0) == null);
    try std.testing.expect(original_design.directAlpha(
        std.math.maxInt(usize),
    ) == null);
    try std.testing.expect(original_design.delayedAlpha(
        std.math.maxInt(usize),
    ) == null);
    try std.testing.expectError(
        error.NonFinitePolyphaseAllpassInput,
        filter.processSample(std.math.nan(f64)),
    );

    filter.sections[0].output_one = std.math.inf(f64);
    try std.testing.expect(!filter.valid());
    try std.testing.expectError(
        error.InvalidPolyphaseAllpassFilterState,
        filter.processSample(0.0),
    );
}
